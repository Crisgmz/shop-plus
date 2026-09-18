-- ============================================================================
-- 20260918_94_quotation_none_without_itbis.sql
--
-- Convertir una cotización en venta "Sin comprobante" cobraba ITBIS.
--
-- Se encontró investigando FA-000002 (Soplasora, 15/09/2026), una NOTA DE
-- VENTA que salió con ITBIS: 7,615.00 + 1,370.70 = 8,985.70. Esa venta NO vino
-- de una cotización: se hizo en el POS sin ITBIS y se editó horas después con
-- una `edit_sale_transactional` que no conocía 'none' (la 87 de flutter_shop+),
-- ya reemplazada por la 92. El diagnóstico está en
-- `supabase/diagnostico/13_itbis_en_notas_de_venta.sql`. La conversión de
-- cotizaciones tenía el mismo defecto y es lo que corrige esta migración.
--
-- `convert_quotation_to_sale` copia tal cual `tax_amount`, `total_amount` y
-- las líneas (`line_tax`, `line_total`) de la cotización, sin mirar el
-- comprobante elegido. El checkout, en cambio, pone la tasa en 0 para 'none'
-- desde la migración 64. Esta migración hace lo mismo al convertir:
--
--   · 'none'  → cada línea con tasa 0, `line_tax` 0 y `line_total` sin ITBIS;
--               la venta con `tax_amount` 0 y total = total − ITBIS; el pago
--               (contado) o la deuda del cliente (crédito) por ese monto.
--   · cualquier otro comprobante → exactamente lo de la 88.
--
-- Copia FIEL de la función de la migración 88. Los únicos cambios van marcados
-- "CAMBIO (migración 94)". Misma firma: no se borra ni se crea sobrecarga.
--
-- PRECONDICIÓN: la versión viva debe ser la de la 88 (acepta crédito). La
-- función la comparten los dos árboles del repo y todas las empresas; si la
-- viva es otra, la migración aborta sin cambiar nada.
--
-- Las ventas que YA salieron así no se tocan aquí: se corrigen desde la app
-- (Historial → Editar venta → Guardar): `edit_sale_transactional` (92)
-- recalcula con tasa 0 para 'none' y ajusta el pago único al nuevo total.
-- Consulta para encontrarlas al final del archivo.
--
-- Ejecutar en el SQL Editor de Supabase, DESPUÉS de la 88. Idempotente.
-- ============================================================================

begin;

-- ── 0) Precondición: la versión viva debe ser la de la 88 (o esta misma) ───
do $pre$
begin
  if not exists (
    select 1
      from pg_proc p
      join pg_namespace n on n.oid = p.pronamespace
     where n.nspname = 'public'
       and p.proname = 'convert_quotation_to_sale'
       and pg_get_functiondef(p.oid) like '%requested_as_credit%'
  ) then
    raise exception
      'La convert_quotation_to_sale viva no es la de la migración 88 (no acepta crédito). '
      'No se aplica para no pisar otra versión: pasar pg_get_functiondef antes de seguir.';
  end if;
end
$pre$;


-- ── 1) La función: copia fiel de la 88 + ITBIS 0 para 'none' ───────────────
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
  -- CAMBIO (migración 94): "Sin comprobante" es nota de venta no fiscal.
  v_no_tax boolean := requested_receipt_type::text = 'none';
  v_tax_amount numeric(14,2);
  v_total_amount numeric(14,2);
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

  -- ── CAMBIO (migración 94): sin comprobante no lleva ITBIS ───────────────
  -- La cotización calculó el ITBIS de cada línea. Si la venta sale "Sin
  -- comprobante", se quita igual que en `checkout_sale_transactional`
  -- (tasa 0 para 'none'): el total queda en subtotal y el pago o la deuda
  -- se registran por ese monto. Cualquier otro comprobante, idéntico a la 88.
  v_tax_amount := case when v_no_tax then 0 else v_quote.tax_amount end;
  v_total_amount := case
    when v_no_tax
      then round((v_quote.total_amount - v_quote.tax_amount)::numeric, 2)
    else v_quote.total_amount
  end;

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
    timezone('utc', now()), v_note_suffix, v_quote.subtotal, v_quote.discount_amount, v_tax_amount, v_total_amount,
    case when v_as_credit then 0 else v_total_amount end,
    case when v_as_credit then v_total_amount else 0 end,
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
    -- CAMBIO (migración 94): sin comprobante, cada línea sin ITBIS.
    case when v_no_tax then 0 else qi.tax_rate end,
    qi.line_subtotal,
    case when v_no_tax then 0 else qi.line_tax end,
    case when v_no_tax then qi.line_total - qi.line_tax else qi.line_total end
  from public.quotation_items qi
  where qi.quotation_id = v_quote.id;

  if v_as_credit then
    -- CAMBIO (migración 88): a crédito no entra dinero; sube la deuda del
    -- cliente, igual que en el checkout.
    update public.clients
       set balance_due = round((coalesce(balance_due, 0) + v_total_amount)::numeric, 2)
     where id = v_quote.client_id
       and branch_id = v_quote.branch_id;
  elsif v_total_amount > 0 then
    -- Pago por el total (la tabla payments exige amount > 0).
    insert into public.payments (
      branch_id, sale_id, client_id, cash_session_id, payment_method, amount, paid_at
    )
    values (
      v_quote.branch_id, v_sale_id, v_quote.client_id, v_session_id, requested_payment_method,
      v_total_amount, timezone('utc', now())
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
      -- CAMBIO (migración 94)
      'sin_itbis', v_no_tax,
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
-- VERIFICACIÓN — una sola fila, con las tres columnas en true.
-- ============================================================================
select
  p.oid::regprocedure::text                                   as firma,
  (pg_get_functiondef(p.oid) like '%requested_as_credit%')    as acepta_credito,
  (pg_get_functiondef(p.oid) like '%converted_expired%')      as permite_vencidas,
  (pg_get_functiondef(p.oid) like '%v_no_tax%')               as sin_comprobante_sin_itbis
from pg_proc p
join pg_namespace n on n.oid = p.pronamespace
where n.nspname = 'public'
  and p.proname = 'convert_quotation_to_sale';


-- ============================================================================
-- VENTAS YA AFECTADAS (solo lectura): notas de venta que quedaron con ITBIS,
-- por cualquiera de los dos caminos. Corregir cada una desde la app. La 13 da
-- además el origen de cada una.
-- ============================================================================
-- select s.sale_number, s.source_quotation_code, s.sale_date::date as fecha,
--        s.status, s.subtotal, s.tax_amount, s.total_amount, s.paid_amount
--   from public.sales s
--  where s.receipt_type::text = 'none'
--    and s.tax_amount > 0
--  order by s.sale_date;
