-- ============================================================================
-- 20260831_84_restore_process_return_imeis.sql
--
-- REPARACIÓN — deshacer el daño de la migración descartada 68.
--
-- Qué pasó: la 68 (escrita contra el árbol de shop-plus) definió
-- `process_return` con la MISMA firma de 7 parámetros que la versión buena de
-- flutter_shop+ (migración 69). `create or replace` la reemplazó SIN ERROR y
-- se perdieron:
--
--   · la restauración de IMEIs al inventario al devolver un equipo;
--   · la validación que impide que una devolución parcial mal armada
--     reinyecte equipos que siguen vendidos;
--   · el soporte de `refund_method = 'credit_note'` (la 68 lo declaraba como
--     enum public.payment_method, que no tiene ese valor).
--
-- El diagnóstico lo confirmó: la `process_return` viva NO menciona
-- `restore_product_imeis`.
--
-- Esta migración restaura la versión de flutter_shop+ TAL CUAL (copia literal
-- de su migración 69) y limpia la llave foránea duplicada que dejó la 68.
--
-- ⚠️ Efecto sobre datos ya grabados: las devoluciones de equipos con IMEI
--    procesadas mientras estuvo viva la 68 NO devolvieron el IMEI al
--    inventario. Hay que revisarlas a mano; la consulta del final las lista.
--
-- Ejecutar en el SQL Editor de Supabase. Idempotente.
-- ============================================================================

begin;

-- ── 1) Llave foránea duplicada ──────────────────────────────────────────────
-- `returns_cash_session_fk` (flutter_shop+) y `returns_cash_session_branch_fk`
-- (la 68) validan exactamente lo mismo sobre las mismas columnas. Se deja la
-- original y se elimina la que sobra.
alter table public.returns
  drop constraint if exists returns_cash_session_branch_fk;


-- ── 2) process_return: versión de flutter_shop+ (migración 69), literal ─────
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
  v_gross numeric(14,2);
  v_line_subtotal numeric(14,2);
  v_line_tax numeric(14,2);
  v_line_total numeric(14,2);
  v_product_id uuid;
  v_product_name text;
  v_price_includes_tax boolean;
  v_line_imeis text[];
  v_bad_imeis text[];
  v_was_credit_sale boolean := false;
  v_prefix text;
  v_seq bigint;
  v_cash_session_id uuid;
  v_refund_method text;
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

  v_refund_method := coalesce(nullif(trim(coalesce(p_refund_method, '')), ''), 'cash');

  -- Resolver la sesión de caja (mismo bloque que checkout_sale_transactional).
  -- A diferencia del checkout, aquí NO se exige caja abierta: una devolución
  -- puede registrarse fuera de caja y queda con cash_session_id null.
  if p_cash_session_id is not null then
    select cs.id into v_cash_session_id
      from public.cash_sessions cs
     where cs.id = p_cash_session_id
       and cs.branch_id = v_branch_id
       and cs.status = 'open'
       and (
         cs.opened_by = v_user
         or cs.cash_register_id is null
         or exists (
           select 1 from public.cash_register_users cru
           where cru.cash_register_id = cs.cash_register_id
             and cru.user_id = v_user
             and cru.is_active
         )
       );

    if v_cash_session_id is null then
      raise exception 'La caja seleccionada no está abierta o no tienes acceso a ella.'
        using errcode = '22023';
    end if;
  else
    select cs.id into v_cash_session_id
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
  -- El prefijo se resuelve por COMPAÑÍA de la sucursal: `where id = 1` tomaba
  -- la fila de otra empresa en instalaciones multi-empresa.
  select coalesce(s.prefix_credit_note, 'NC') into v_prefix
    from public.app_settings s
    join public.branches b on b.company_id = s.company_id
   where b.id = v_branch_id
   limit 1;
  v_prefix := coalesce(v_prefix, 'NC');

  select coalesce(count(*), 0) + 1 into v_seq
    from public.returns
   where branch_id = v_branch_id
     and id <> v_return_id;

  v_return_number := v_prefix || '-' || lpad(v_seq::text, 5, '0');
  update public.returns set return_number = v_return_number where id = v_return_id;

  -- Insertar líneas
  for v_item in select * from jsonb_array_elements(p_items)
  loop
    v_product_id := (v_item->>'product_id')::uuid;
    v_qty := (v_item->>'quantity')::numeric(14,3);
    v_price := (v_item->>'unit_price')::numeric(14,2);
    v_tax_rate := coalesce((v_item->>'tax_rate')::numeric(5,2), 18.00);

    if v_qty is null or v_qty <= 0 then
      raise exception 'La cantidad de cada línea debe ser mayor que cero';
    end if;
    if v_price is null or v_price < 0 then
      raise exception 'El precio unitario es inválido';
    end if;

    -- IMEIs devueltos en esta línea (opcional). Se normalizan aquí mismo:
    -- trim, se descartan vacíos y se deduplican, para que el conteo con el
    -- que se valida abajo sea el mismo que se guarda y se restaura.
    select coalesce(array_agg(distinct t.v order by t.v), '{}'::text[])
      into v_line_imeis
      from jsonb_array_elements_text(
             case when jsonb_typeof(v_item->'imeis') = 'array'
                  then v_item->'imeis' else '[]'::jsonb end) as u(raw)
      cross join lateral (select nullif(trim(u.raw), '') as v) t
     where t.v is not null;

    select name, coalesce(price_includes_tax, false)
      into v_product_name, v_price_includes_tax
      from public.products
     where id = v_product_id
       and branch_id = v_branch_id;
    if not found then
      raise exception 'Producto no encontrado en la sucursal';
    end if;

    -- Defensa contra devoluciones PARCIALES mal armadas: si la línea trae más
    -- IMEIs que unidades devueltas, restaurarlos todos dejaría equipos vendidos
    -- otra vez disponibles en el inventario. El RPC no confía en el cliente.
    if coalesce(array_length(v_line_imeis, 1), 0) > v_qty then
      raise exception
        'La línea de "%" trae % IMEI(s) para una cantidad devuelta de %. No se pueden devolver más equipos que unidades.',
        v_product_name, coalesce(array_length(v_line_imeis, 1), 0), v_qty
        using errcode = '22023';
    end if;

    -- Si la devolución está ligada a una venta, cada IMEI tiene que haber
    -- salido de ESA venta. Así no se cuela al inventario un equipo de otra
    -- factura (o inventado) por la vía de la devolución.
    if p_original_sale_id is not null
       and coalesce(array_length(v_line_imeis, 1), 0) > 0 then
      select array_agg(u.imei order by u.imei)
        into v_bad_imeis
        from unnest(v_line_imeis) as u(imei)
       where not exists (
         select 1
           from public.sale_items si
          where si.sale_id = p_original_sale_id
            and si.branch_id = v_branch_id
            and si.imeis @> array[u.imei]
       );

      if coalesce(array_length(v_bad_imeis, 1), 0) > 0 then
        raise exception
          'Los IMEI % no pertenecen a la venta original.',
          array_to_string(v_bad_imeis, ', ')
          using errcode = '22023';
      end if;
    end if;

    v_gross := round(v_qty * v_price, 2);
    if v_price_includes_tax and v_tax_rate > 0 then
      -- Precio con ITBIS incluido: se reembolsa el total exacto y el
      -- impuesto se extrae.
      v_line_total := v_gross;
      v_line_tax := round((v_gross * v_tax_rate / (100 + v_tax_rate))::numeric, 2);
      v_line_subtotal := v_line_total - v_line_tax;
    else
      -- Exclusivo (comportamiento histórico, mismos redondeos).
      v_line_subtotal := v_gross;
      v_line_tax := round(v_line_subtotal * v_tax_rate / 100.0, 2);
      v_line_total := v_line_subtotal + v_line_tax;
    end if;

    insert into public.return_items (
      return_id, branch_id, product_id, description, quantity,
      unit_price, tax_rate, line_subtotal, line_tax, line_total, imeis
    ) values (
      v_return_id, v_branch_id, v_product_id, v_product_name, v_qty,
      v_price, v_tax_rate, v_line_subtotal, v_line_tax, v_line_total,
      v_line_imeis
    );

    -- El equipo vuelve a estar disponible en el inventario.
    if coalesce(array_length(v_line_imeis, 1), 0) > 0 then
      perform public.restore_product_imeis(v_product_id, v_branch_id, v_line_imeis);
    end if;

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

  -- Recordatorio: NO se inserta en public.cash_register_movements. El cierre
  -- de caja resta los reembolsos leyendo `returns` directamente; un movimiento
  -- aquí haría que se descuenten dos veces.

  return jsonb_build_object(
    'return_id', v_return_id,
    'return_number', v_return_number,
    'total_amount', v_total,
    'items_count', v_items_count,
    'cash_session_id', v_cash_session_id,
    'refund_method', v_refund_method,
    'credit_balance_adjusted', v_was_credit_sale and p_client_id is not null
  );
end;
$$;

grant execute on function public.process_return(
  uuid, uuid, uuid, text, jsonb, uuid, text
) to authenticated;

commit;

notify pgrst, 'reload schema';


-- ============================================================================
-- REVISIÓN MANUAL — devoluciones que pudieron perder el IMEI
-- ============================================================================
-- Correr aparte. Lista las devoluciones con IMEIs en sus líneas cuyos equipos
-- NO están de vuelta en el inventario del producto: son las que procesó la
-- versión rota y hay que reingresar a mano.
--
--   select r.return_number, r.return_date, ri.product_id, p.name, ri.imeis
--     from public.return_items ri
--     join public.returns r  on r.id = ri.return_id
--     join public.products p on p.id = ri.product_id
--    where coalesce(array_length(ri.imeis, 1), 0) > 0
--      and not (ri.imeis <@ coalesce(p.imeis, '{}'::text[]))
--    order by r.return_date desc;
-- ============================================================================
