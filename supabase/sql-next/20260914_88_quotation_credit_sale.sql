-- ============================================================================
-- 20260914_88_quotation_credit_sale.sql
--
-- Convertir una cotización en venta A CRÉDITO, no solo pagada al contado.
--
-- Hasta ahora `convert_quotation_to_sale` siempre creaba una venta pagada:
-- status 'completed', paid = total, balance = 0 y una fila en `payments`.
-- Esta migración agrega la opción de dejarla como cuenta por cobrar, con las
-- MISMAS reglas que ya aplica el POS en `checkout_sale_transactional`:
--
--   · exige un cliente del catálogo — un nombre escrito a mano no tiene
--     cuenta donde cargar la deuda;
--   · el cliente debe existir en la sucursal y estar activo;
--   · respeta `app_settings.credit_allow_sales`;
--   · plazo = días pedidos, o `credit_default_days` de la empresa, o 30;
--     fuera de 1..365 cae al default;
--   · status 'credit', paid = 0, balance = total, `due_date` calculada;
--   · NO se inserta pago, y el saldo del cliente sube por el total.
--
-- Una diferencia a propósito con el checkout: el default de días y
-- `credit_allow_sales` se leen de la EMPRESA de la sucursal. El checkout aún
-- lee `app_settings where id = 1`, que en esta base es un registro residual
-- ("Mi Negocio") — el mismo defecto que la migración 87 corrigió en los
-- reportes fiscales.
--
-- FIRMA: se agregan dos parámetros al final, con default. Por eso primero se
-- BORRA la firma de 4 parámetros: `create or replace` con otra firma no
-- reemplaza, crea una segunda sobrecarga — que es exactamente lo que dejó tres
-- `checkout_sale_transactional` conviviendo en agosto. El app de flutter_shop+
-- llama con 4 parámetros nombrados y resuelve a esta versión sin cambios.
--
-- PRECONDICIÓN: esta función se comparte entre los dos árboles del repo y las
-- 31 empresas. Antes de tocarla se verifica que la versión viva sea la de la
-- migración 81; si no lo es, la migración aborta sin cambiar nada.
--
-- Ejecutar en el SQL Editor de Supabase. Idempotente.
-- ============================================================================

begin;

-- ── 0) Precondición: la versión viva debe ser la de la migración 81 ────────
do $pre$
begin
  if not exists (
    select 1
      from pg_proc p
      join pg_namespace n on n.oid = p.pronamespace
     where n.nspname = 'public'
       and p.proname = 'convert_quotation_to_sale'
  ) then
    raise exception 'No existe convert_quotation_to_sale en la base. Revisar antes de continuar.';
  end if;

  if not exists (
    select 1
      from pg_proc p
      join pg_namespace n on n.oid = p.pronamespace
     where n.nspname = 'public'
       and p.proname = 'convert_quotation_to_sale'
       and pg_get_functiondef(p.oid) like '%converted_expired%'
  ) then
    raise exception
      'La convert_quotation_to_sale viva no es la de la migración 81 (no permite cotizaciones vencidas). '
      'No se aplica para no pisar otra versión: pasar pg_get_functiondef antes de seguir.';
  end if;
end
$pre$;


-- ── 1) Quitar la firma anterior (si no, queda una segunda sobrecarga) ───────
drop function if exists public.convert_quotation_to_sale(
  uuid, public.receipt_type, public.payment_method, uuid
);


-- ── 2) La función: copia fiel de la 81 + rama de crédito ───────────────────
create or replace function public.convert_quotation_to_sale(
  target_quotation_id uuid,
  requested_receipt_type public.receipt_type default 'consumer_final',
  requested_payment_method public.payment_method default 'cash',
  requested_cash_session_id uuid default null,
  -- CAMBIO (migración 88): venta a crédito.
  requested_as_credit boolean default false,
  requested_credit_due_days integer default null
)
returns table (sale_id uuid, sale_number text)
language plpgsql
security definer
set search_path = public
as $$
declare
  v_user_id uuid := auth.uid();
  v_quote public.quotations%rowtype;
  v_sale_id uuid;
  v_sale_number text;
  v_note_suffix text;
  v_session_id uuid;
  -- CAMBIO (migración 88)
  v_as_credit boolean := coalesce(requested_as_credit, false);
  v_client record;
  v_credit_allowed boolean;
  v_default_days integer;
  v_due_days integer;
  v_due_date date;
begin
  if v_user_id is null then
    raise exception 'No hay sesión activa.';
  end if;

  if not public.can_operate_pos() then
    raise exception 'El usuario no tiene permisos para convertir cotizaciones en ventas.';
  end if;

  select *
    into v_quote
  from public.quotations q
  where q.id = target_quotation_id
  for update;

  if not found then
    raise exception 'La cotización no existe.';
  end if;

  if not public.has_branch_access(v_quote.branch_id) then
    raise exception 'No tienes acceso a la sucursal de esta cotización.';
  end if;

  if v_quote.converted_sale_id is not null or v_quote.status = 'converted' then
    raise exception 'La cotización ya fue convertida previamente.';
  end if;

  -- (migración 66/81) El vencimiento no bloquea la conversión: `expired` es
  -- convertible. Sigue bloqueado lo vigente sin aprobar y lo perdido.
  if v_quote.status not in ('approved'::public.quote_status,
                            'expired'::public.quote_status) then
    raise exception 'Solo las cotizaciones aprobadas o vencidas pueden convertirse en venta.';
  end if;

  if not exists (
    select 1 from public.quotation_items qi where qi.quotation_id = v_quote.id
  ) then
    raise exception 'La cotización no tiene líneas para convertir.';
  end if;

  -- ── CAMBIO (migración 88): validaciones de la venta a crédito ────────────
  -- Mismas reglas que `checkout_sale_transactional`.
  if v_as_credit then
    if v_quote.client_id is null then
      raise exception
        'Para vender a crédito la cotización debe tener un cliente registrado. '
        'Un nombre escrito a mano no tiene cuenta donde cargar la deuda.';
    end if;

    select c.id, c.full_name, c.is_active
      into v_client
      from public.clients c
     where c.id = v_quote.client_id
       and c.branch_id = v_quote.branch_id;

    if not found then
      raise exception 'El cliente de la cotización ya no existe en esta sucursal.';
    end if;
    if not v_client.is_active then
      raise exception 'Cliente "%": cuenta inactiva.', v_client.full_name;
    end if;

    -- Configuración de la EMPRESA de la sucursal (no `where id = 1`).
    begin
      select s.credit_allow_sales, s.credit_default_days
        into v_credit_allowed, v_default_days
        from public.app_settings s
        join public.branches b on b.company_id = s.company_id
       where b.id = v_quote.branch_id
       limit 1;
    exception
      when undefined_column or undefined_table then
        v_credit_allowed := true;
        v_default_days := null;
    end;

    if not coalesce(v_credit_allowed, true) then
      raise exception 'Las ventas a crédito están deshabilitadas en la configuración.';
    end if;

    v_default_days := coalesce(v_default_days, 30);
    v_due_days := coalesce(requested_credit_due_days, v_default_days);
    if v_due_days <= 0 or v_due_days > 365 then
      v_due_days := v_default_days;
    end if;
    v_due_date := (timezone('utc', now()))::date + v_due_days;
  end if;

  -- NOTA: se OMITE a propósito la validación de stock. Convertir una cotización
  -- a venta puede dejar el inventario en 0 o negativo (decisión del negocio).

  -- Sesión de caja: la enviada por el cliente, o la abierta del usuario, o null.
  v_session_id := requested_cash_session_id;
  if v_session_id is null then
    select cs.id
      into v_session_id
    from public.cash_sessions cs
    where cs.branch_id = v_quote.branch_id
      and cs.status = 'open'
      and cs.opened_by = v_user_id
    order by cs.opened_at desc
    limit 1;
  end if;

  v_sale_number := format('VTA-Q-%s', to_char(clock_timestamp(), 'YYYYMMDD-HH24MISSMS'));
  v_note_suffix := coalesce(v_quote.notes || E'\n\n', '') ||
    format('Origen: cotización %s', v_quote.code);

  -- Contado: 'completed', paid = total, balance = 0.
  -- Crédito (migración 88): 'credit', paid = 0, balance = total, con vencimiento.
  insert into public.sales (
    branch_id, sale_number, client_id, client_name_snapshot, cashier_id, cash_session_id,
    receipt_type, status,
    sale_date, notes, subtotal, discount_amount, tax_amount, total_amount, paid_amount, balance_due,
    due_date, source_quotation_id, source_quotation_code
  )
  values (
    v_quote.branch_id, v_sale_number, v_quote.client_id,
    -- Nombre escrito a mano en la cotización (ver migración 65).
    case
      when v_quote.client_id is not null then null
      when btrim(coalesce(v_quote.client_display_name, '')) in ('', 'Cliente general') then null
      else btrim(v_quote.client_display_name)
    end,
    v_user_id, v_session_id, requested_receipt_type,
    case when v_as_credit then 'credit'::public.sale_status
         else 'completed'::public.sale_status end,
    timezone('utc', now()), v_note_suffix, v_quote.subtotal, v_quote.discount_amount, v_quote.tax_amount, v_quote.total_amount,
    case when v_as_credit then 0 else v_quote.total_amount end,
    case when v_as_credit then v_quote.total_amount else 0 end,
    v_due_date, v_quote.id, v_quote.code
  )
  -- Calificado con la tabla: el RETURNS TABLE expone `sale_number` como OUT.
  returning sales.id, sales.sale_number into v_sale_id, v_sale_number;

  -- Líneas (el trigger de stock descuenta inventario; puede quedar negativo).
  insert into public.sale_items (
    sale_id, branch_id, product_id, description, quantity, unit_price, discount_amount,
    tax_rate, line_subtotal, line_tax, line_total
  )
  select
    v_sale_id, qi.branch_id, qi.product_id, qi.description, qi.quantity, qi.unit_price, qi.discount_amount,
    qi.tax_rate, qi.line_subtotal, qi.line_tax, qi.line_total
  from public.quotation_items qi
  where qi.quotation_id = v_quote.id;

  if v_as_credit then
    -- CAMBIO (migración 88): a crédito no entra dinero; sube la deuda del
    -- cliente, igual que en el checkout.
    update public.clients
       set balance_due = round((coalesce(balance_due, 0) + v_quote.total_amount)::numeric, 2)
     where id = v_quote.client_id
       and branch_id = v_quote.branch_id;
  elsif v_quote.total_amount > 0 then
    -- Pago por el total (la tabla payments exige amount > 0).
    insert into public.payments (
      branch_id, sale_id, client_id, cash_session_id, payment_method, amount, paid_at
    )
    values (
      v_quote.branch_id, v_sale_id, v_quote.client_id, v_session_id, requested_payment_method,
      v_quote.total_amount, timezone('utc', now())
    );
  end if;

  update public.quotations
     set status = 'converted',
         converted_sale_id = v_sale_id,
         converted_at = timezone('utc', now()),
         converted_by = v_user_id
   where id = v_quote.id;

  insert into public.quotation_events (
    quotation_id, branch_id, event_type, payload, created_by
  )
  values (
    v_quote.id, v_quote.branch_id, 'converted_to_sale',
    jsonb_build_object(
      'sale_id', v_sale_id,
      'sale_number', v_sale_number,
      'requested_receipt_type', requested_receipt_type,
      'payment_method', case when v_as_credit then null else requested_payment_method end,
      'status', case when v_as_credit then 'credit' else 'completed' end,
      'converted_expired', (v_quote.valid_until < timezone('utc', now())),
      -- CAMBIO (migración 88)
      'as_credit', v_as_credit,
      'credit_due_days', v_due_days,
      'due_date', v_due_date
    ),
    v_user_id
  );

  return query select v_sale_id, v_sale_number;
end;
$$;

grant execute on function public.convert_quotation_to_sale(
  uuid, public.receipt_type, public.payment_method, uuid, boolean, integer
) to authenticated;

commit;

notify pgrst, 'reload schema';


-- ============================================================================
-- VERIFICACIÓN — una sola fila, con las dos columnas en true.
-- ============================================================================
select
  p.oid::regprocedure::text                                   as firma,
  (pg_get_functiondef(p.oid) like '%requested_as_credit%')    as acepta_credito,
  (pg_get_functiondef(p.oid) like '%converted_expired%')      as permite_vencidas
from pg_proc p
join pg_namespace n on n.oid = p.pronamespace
where n.nspname = 'public'
  and p.proname = 'convert_quotation_to_sale';
