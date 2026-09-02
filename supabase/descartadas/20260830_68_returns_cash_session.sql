-- ############################################################################
-- ⛔ NO EJECUTAR — MIGRACIÓN DESCARTADA
--
-- Esta migración se escribió contra el árbol de shop-plus, que está ~2 semanas
-- atrás del de flutter_shop+. AMBOS apuntan a la MISMA base
-- (https://supabase.busiposweb.com), así que correrla PISARÍA funciones más
-- nuevas y mejores, sin dar ningún error visible.
--
-- Lo que arregla ya está resuelto —mejor— en flutter_shop+:
--   · 20260814_76_checkout_line_discount.sql  (descuento por MONTO absoluto,
--     matemática en centavos, soporta price_includes_tax)
--   · 20260814_69_returns_cash_and_imeis.sql  (caja + método de reembolso en
--     TEXT y restauración de IMEIs con validación)
--   · 20260814_68_services_skip_inventory.sql (servicios no mueven stock, a
--     nivel de trigger)
--   · 20260814_75_checkout_respects_track_inventory.sql
--
-- Se conserva solo como referencia de la investigación. Si algún día hace
-- falta algo de aquí, hay que REESCRIBIRLO sobre el linaje de flutter_shop+.
--
-- El guard de abajo hace que falle de inmediato si alguien la pega por error.
-- ############################################################################

do $guard$
begin
  raise exception
    'MIGRACIÓN DESCARTADA: pisaría funciones más nuevas de flutter_shop+. Ver el encabezado del archivo.';
end
$guard$;

-- ============================================================================
-- 20260830_68_returns_cash_session.sql
--
-- Las DEVOLUCIONES no descontaban del arqueo de caja.
--
-- Al devolverle dinero al cliente sale efectivo del cajón, pero `returns` no
-- guardaba ninguna referencia a la sesión de caja y `process_return` ni tocaba
-- el tema. El efectivo esperado del cierre solo restaba `expenses`, así que la
-- caja aparecía CORTA por el monto de las devoluciones del día.
--
-- Esta migración:
--   1) Agrega `returns.cash_session_id` y `returns.refund_method`.
--   2) Reescribe `process_return` para resolver la sesión abierta (mismo
--      criterio que el checkout) y guardar ambos datos.
--   3) De paso corrige el correlativo de la nota de crédito: se calculaba con
--      count(*) + 1, así que borrar una devolución hacía que la siguiente
--      repitiera número.
--
-- Los dos parámetros nuevos van al final y con DEFAULT, así que una app vieja
-- sigue funcionando: sin ellos la devolución se carga a la caja abierta del
-- usuario y se asume reembolso en efectivo.
--
-- Ejecutar en el SQL Editor de Supabase. Idempotente.
-- ============================================================================

alter table public.returns
  add column if not exists cash_session_id uuid,
  add column if not exists refund_method public.payment_method not null
    default 'cash';

-- FK compuesta: la sesión tiene que ser de la MISMA sucursal que la
-- devolución (cash_sessions declara unique (id, branch_id)).
do $fk$
begin
  if not exists (
    select 1 from pg_constraint where conname = 'returns_cash_session_branch_fk'
  ) then
    alter table public.returns
      add constraint returns_cash_session_branch_fk
      foreign key (cash_session_id, branch_id)
      references public.cash_sessions(id, branch_id)
      on delete set null;
  end if;
end
$fk$;

create index if not exists returns_cash_session_idx
  on public.returns (cash_session_id)
  where cash_session_id is not null;


-- ----------------------------------------------------------------------------
-- process_return — copia fiel de la migración 11 + caja, método y correlativo.
-- ----------------------------------------------------------------------------
-- La firma vieja (5 argumentos) se elimina: con las dos conviviendo, una
-- llamada de 5 parámetros sería ambigua para PostgREST.
drop function if exists public.process_return(uuid, uuid, uuid, text, jsonb);

create or replace function public.process_return(
  p_branch_id uuid default null,
  p_client_id uuid default null,
  p_original_sale_id uuid default null,
  p_notes text default null,
  p_items jsonb default '[]'::jsonb,
  p_cash_session_id uuid default null,
  p_refund_method text default 'cash'
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_branch_id uuid;
  v_user uuid;
  v_return_id uuid;
  v_return_number text;
  v_subtotal numeric(14,2) := 0;
  v_tax numeric(14,2) := 0;
  v_total numeric(14,2) := 0;
  v_items_count integer := 0;
  v_item jsonb;
  v_qty numeric(14,3);
  v_price numeric(14,2);
  v_tax_rate numeric(5,2);
  v_line_subtotal numeric(14,2);
  v_line_tax numeric(14,2);
  v_line_total numeric(14,2);
  v_product_name text;
  v_was_credit_sale boolean := false;
  v_prefix text;
  v_seq bigint;
  v_cash_session_id uuid;
  v_refund_method public.payment_method;
begin
  v_branch_id := coalesce(p_branch_id, public.current_branch_id());
  v_user := auth.uid();

  if v_branch_id is null then
    raise exception 'No hay sucursal asignada al usuario';
  end if;

  if not (public.has_branch_access(v_branch_id) or public.is_admin()) then
    raise exception 'Sin acceso a la sucursal indicada';
  end if;

  if jsonb_array_length(coalesce(p_items, '[]'::jsonb)) = 0 then
    raise exception 'Una devolución requiere al menos un artículo';
  end if;

  -- Método del reembolso. Por defecto efectivo: es lo que sale del cajón.
  begin
    v_refund_method := coalesce(nullif(btrim(p_refund_method), ''), 'cash')
      ::public.payment_method;
  exception
    when invalid_text_representation then
      raise exception 'Método de reembolso no soportado: %', p_refund_method
        using errcode = '22023';
  end;

  -- Sesión de caja a la que se carga el reembolso: la enviada por la app o la
  -- abierta del usuario. Sin esto el arqueo no descontaba el efectivo que sale
  -- del cajón al devolverle al cliente y la caja aparecía corta.
  v_cash_session_id := p_cash_session_id;
  if v_cash_session_id is null then
    select cs.id
      into v_cash_session_id
      from public.cash_sessions cs
     where cs.branch_id = v_branch_id
       and cs.status = 'open'
       and (
         cs.opened_by = v_user
         or exists (
           select 1 from public.cash_register_users cru
           where cru.cash_register_id = cs.cash_register_id
             and cru.user_id = v_user
             and cru.is_active
         )
       )
     order by cs.opened_at desc
     limit 1;
  end if;

  -- Si hay venta original: validar que pertenece a la sucursal y guardar
  -- si fue a crédito (para ajustar balance_due).
  if p_original_sale_id is not null then
    select status = 'credit'::public.sale_status
      into v_was_credit_sale
      from public.sales
     where id = p_original_sale_id
       and branch_id = v_branch_id;
    if not found then
      raise exception 'La venta original no existe en esta sucursal';
    end if;
  end if;

  -- Insertar la cabecera con totales en 0; los recalculamos al final.
  insert into public.returns (
    branch_id, client_id, original_sale_id, cashier_id, notes,
    subtotal, tax_amount, total_amount, cash_session_id, refund_method
  ) values (
    v_branch_id, p_client_id, p_original_sale_id, v_user, p_notes,
    0, 0, 0, v_cash_session_id, v_refund_method
  ) returning id into v_return_id;

  -- Asignar return_number con prefijo de app_settings + correlativo por sucursal.
  select coalesce(prefix_credit_note, 'NC') into v_prefix
    from public.app_settings where id = 1;
  v_prefix := coalesce(v_prefix, 'NC');

  -- Correlativo por el MAYOR emitido, no por count(*): con count, borrar una
  -- devolución hacía que la siguiente repitiera un número de nota de crédito.
  select coalesce(
           max(
             nullif(regexp_replace(r.return_number, '^.*-', ''), '')::bigint
           ),
           0
         ) + 1
    into v_seq
    from public.returns r
   where r.branch_id = v_branch_id
     and r.id <> v_return_id
     and r.return_number ~ '-[0-9]+$';

  v_return_number := v_prefix || '-' || lpad(v_seq::text, 5, '0');
  update public.returns set return_number = v_return_number where id = v_return_id;

  -- Insertar líneas
  for v_item in select * from jsonb_array_elements(p_items)
  loop
    v_qty := (v_item->>'quantity')::numeric(14,3);
    v_price := (v_item->>'unit_price')::numeric(14,2);
    v_tax_rate := coalesce((v_item->>'tax_rate')::numeric(5,2), 18.00);

    if v_qty is null or v_qty <= 0 then
      raise exception 'La cantidad de cada línea debe ser mayor que cero';
    end if;
    if v_price is null or v_price < 0 then
      raise exception 'El precio unitario es inválido';
    end if;

    select name into v_product_name
      from public.products
     where id = (v_item->>'product_id')::uuid
       and branch_id = v_branch_id;
    if not found then
      raise exception 'Producto no encontrado en la sucursal';
    end if;

    v_line_subtotal := round(v_qty * v_price, 2);
    v_line_tax := round(v_line_subtotal * v_tax_rate / 100.0, 2);
    v_line_total := v_line_subtotal + v_line_tax;

    insert into public.return_items (
      return_id, branch_id, product_id, description, quantity,
      unit_price, tax_rate, line_subtotal, line_tax, line_total
    ) values (
      v_return_id, v_branch_id, (v_item->>'product_id')::uuid, v_product_name, v_qty,
      v_price, v_tax_rate, v_line_subtotal, v_line_tax, v_line_total
    );

    v_subtotal := v_subtotal + v_line_subtotal;
    v_tax := v_tax + v_line_tax;
    v_total := v_total + v_line_total;
    v_items_count := v_items_count + 1;
  end loop;

  update public.returns
     set subtotal = v_subtotal,
         tax_amount = v_tax,
         total_amount = v_total
   where id = v_return_id;

  -- Si la venta original fue a crédito y hay cliente, ajustar saldo.
  if v_was_credit_sale and p_client_id is not null then
    update public.clients
       set balance_due = greatest(0, balance_due - v_total)
     where id = p_client_id
       and branch_id = v_branch_id;
  end if;

  return jsonb_build_object(
    'return_id', v_return_id,
    'return_number', v_return_number,
    'total_amount', v_total,
    'items_count', v_items_count,
    'credit_balance_adjusted', v_was_credit_sale and p_client_id is not null,
    'cash_session_id', v_cash_session_id,
    'refund_method', v_refund_method
  );
end;
$$;

grant execute on function public.process_return(
  uuid, uuid, uuid, text, jsonb, uuid, text
) to authenticated;

notify pgrst, 'reload schema';
