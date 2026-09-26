-- ============================================================================
-- 20260926_95_cotizacion_presentaciones.sql
--
-- Cotizar por CAJA o por PAQUETE, igual que el punto de venta.
--
-- El POS vende presentaciones desde la migración 86 y las cobra a su precio
-- desde la 92, pero las cotizaciones se quedaron en el modelo viejo: sus
-- líneas solo tienen precio unitario, así que una caja se cotizaba como "20"
-- paquetes y al convertirla la factura no decía "1 Caja".
--
-- Esta migración:
--   1. Agrega a `quotation_items` las mismas cuatro columnas que ya tienen
--      `sale_items` y `purchase_items`: `uom`, `uom_factor`, `uom_price` y
--      `unit_name`. Con `uom` nulo la línea se comporta como siempre.
--   2. `update_quotation_document` (copia FIEL de la 65) las guarda.
--   3. `convert_quotation_to_sale` (copia FIEL de la 94) las pasa a la venta,
--      para que la factura imprima "1 Caja" y cobre el precio exacto de la caja
--      con `uom_price`, como hace el checkout desde la 92.
--
-- `quotation_items.quantity` viaja en UNIDADES BASE, igual que `sale_items`:
-- así el trigger de stock descuenta bien al convertir, sin saber de empaques.
--
-- Los únicos cambios contra las versiones vivas van marcados
-- "CAMBIO (migración 95)". Ninguna firma cambia.
--
-- PRECONDICIONES: `update_quotation_document` debe ser la de la 65 (acepta
-- nombre de cliente a mano) y `convert_quotation_to_sale` la de la 94 (sin
-- ITBIS en las notas de venta). Si no, la migración aborta sin tocar nada.
--
-- Ejecutar en el SQL Editor de Supabase, DESPUÉS de la 94. Idempotente.
-- ============================================================================

begin;

-- ── 0) Precondiciones ──────────────────────────────────────────────────────
do $pre$
begin
  if not exists (
    select 1 from pg_proc p join pg_namespace n on n.oid = p.pronamespace
     where n.nspname = 'public' and p.proname = 'update_quotation_document'
       and pg_get_functiondef(p.oid) like '%requested_client_name%'
  ) then
    raise exception
      'La update_quotation_document viva no es la de la migración 65. '
      'Revisar con pg_get_functiondef antes de seguir.';
  end if;

  if not exists (
    select 1 from pg_proc p join pg_namespace n on n.oid = p.pronamespace
     where n.nspname = 'public' and p.proname = 'convert_quotation_to_sale'
       and pg_get_functiondef(p.oid) like '%v_no_tax%'
  ) then
    raise exception
      'La convert_quotation_to_sale viva no es la de la migración 94. '
      'Aplicar primero la 94.';
  end if;
end
$pre$;


-- ── 1) Columnas de presentación en las líneas de la cotización ─────────────
alter table public.quotation_items
  add column if not exists uom text,
  add column if not exists uom_factor numeric(14,3),
  add column if not exists uom_price numeric(14,2),
  add column if not exists unit_name text;

comment on column public.quotation_items.uom is
  'Presentación cotizada: unit | pack | box. `quantity` va en unidades base.';
comment on column public.quotation_items.uom_price is
  'Precio de UNA presentación (1 caja = 2,639.83). NULL = línea por unidad base.';

do $c$
begin
  if not exists (select 1 from pg_constraint
                  where conname = 'quotation_items_uom_valid') then
    alter table public.quotation_items
      add constraint quotation_items_uom_valid
      check (uom is null or uom in ('unit', 'pack', 'box')) not valid;
  end if;
end
$c$;


-- ── 2) Guardar la presentación al editar la cotización ─────────────────────
create or replace function public.update_quotation_document(
  target_quotation_id uuid,
  requested_client_id uuid,
  requested_status public.quote_status,
  requested_valid_until timestamptz,
  requested_notes text,
  requested_items jsonb,
  requested_client_name text default null
)
returns table (quotation_id uuid)
language plpgsql
security definer
set search_path = public
as $$
declare
  v_user_id uuid := auth.uid();
  v_quote public.quotations%rowtype;
  v_branch_id uuid;
  v_subtotal numeric(14,2) := 0;
  v_tax numeric(14,2) := 0;
  v_total numeric(14,2) := 0;
  v_item jsonb;
  v_client public.clients%rowtype;
begin
  if v_user_id is null then
    raise exception 'No hay sesión activa.';
  end if;

  if not public.can_operate_pos() then
    raise exception 'El usuario no tiene permisos para editar cotizaciones.';
  end if;

  if requested_status = 'converted' then
    raise exception 'No se puede forzar estado convertido desde edición manual.';
  end if;

  if requested_valid_until <= timezone('utc', now()) then
    raise exception 'La vigencia debe estar en el futuro.';
  end if;

  if requested_items is null or jsonb_typeof(requested_items) <> 'array' or jsonb_array_length(requested_items) = 0 then
    raise exception 'La cotización debe conservar al menos una línea.';
  end if;

  select *
    into v_quote
  from public.quotations q
  where q.id = target_quotation_id
  for update;

  if not found then
    raise exception 'La cotización no existe.';
  end if;

  if v_quote.status = 'converted' or v_quote.converted_sale_id is not null then
    raise exception 'La cotización convertida ya no se puede editar.';
  end if;

  if not public.has_branch_access(v_quote.branch_id) then
    raise exception 'No tienes acceso a la sucursal de esta cotización.';
  end if;

  v_branch_id := v_quote.branch_id;

  if requested_client_id is not null then
    select *
      into v_client
    from public.clients c
    where c.id = requested_client_id
      and c.branch_id = v_branch_id;

    if not found then
      raise exception 'El cliente seleccionado no existe en esta sucursal.';
    end if;
  end if;

  for v_item in select value from jsonb_array_elements(requested_items)
  loop
    v_subtotal := v_subtotal + coalesce((v_item->>'line_subtotal')::numeric, 0);
    v_tax := v_tax + coalesce((v_item->>'line_tax')::numeric, 0);
    v_total := v_total + coalesce((v_item->>'line_total')::numeric, 0);
  end loop;

  update public.quotations
     set client_id = requested_client_id,
         status = requested_status,
         valid_until = requested_valid_until,
         notes = nullif(btrim(requested_notes), ''),
         subtotal = round(v_subtotal, 2),
         tax_amount = round(v_tax, 2),
         total_amount = round(v_total, 2),
         -- Cliente del catálogo → su nombre. Si no hay, se respeta el nombre
         -- escrito a mano; y solo si tampoco hay, el placeholder.
         client_display_name = case
           when requested_client_id is not null then v_client.full_name
           else coalesce(nullif(btrim(requested_client_name), ''), 'Cliente general')
         end,
         client_legal_name = case when requested_client_id is null then null else nullif(v_client.legal_name, '') end,
         client_email = case when requested_client_id is null then null else nullif(v_client.email, '') end,
         client_phone = case when requested_client_id is null then null else nullif(v_client.phone, '') end,
         client_document_type = case when requested_client_id is null then null else nullif(v_client.document_type, '') end,
         client_document_number = case when requested_client_id is null then null else nullif(v_client.document_number, '') end,
         sent_at = case
           when requested_status = 'sent' and quotations.sent_at is null then timezone('utc', now())
           else quotations.sent_at
         end,
         approved_at = case
           when requested_status = 'approved' and quotations.approved_at is null then timezone('utc', now())
           when requested_status <> 'approved' then null
           else quotations.approved_at
         end,
         rejected_at = case
           when requested_status = 'rejected' and quotations.rejected_at is null then timezone('utc', now())
           when requested_status <> 'rejected' then null
           else quotations.rejected_at
         end,
         expired_at = case
           when requested_status = 'expired' then timezone('utc', now())
           else null
         end,
         updated_by = v_user_id
   where quotations.id = target_quotation_id;

  -- FIX ambigüedad: el RETURNS TABLE expone `quotation_id` como OUT column,
  -- así que aquí calificamos con el nombre de la tabla.
  delete from public.quotation_items qi
  where qi.quotation_id = target_quotation_id;

  insert into public.quotation_items (
    quotation_id,
    branch_id,
    product_id,
    product_name,
    product_sku,
    description,
    quantity,
    unit_price,
    discount_amount,
    tax_rate,
    line_subtotal,
    line_tax,
    line_total,
    -- CAMBIO (migración 95): presentación cotizada.
    uom,
    uom_factor,
    uom_price,
    unit_name,
    created_by,
    updated_by
  )
  select
    target_quotation_id,
    v_branch_id,
    (item->>'product_id')::uuid,
    coalesce(nullif(item->>'product_name', ''), item->>'description'),
    nullif(item->>'product_sku', ''),
    coalesce(nullif(item->>'description', ''), item->>'product_name'),
    coalesce((item->>'quantity')::numeric, 0),
    coalesce((item->>'unit_price')::numeric, 0),
    coalesce((item->>'discount_amount')::numeric, 0),
    coalesce((item->>'tax_rate')::numeric, 0),
    coalesce((item->>'line_subtotal')::numeric, 0),
    coalesce((item->>'line_tax')::numeric, 0),
    coalesce((item->>'line_total')::numeric, 0),
    -- CAMBIO (migración 95): la línea viaja con su presentación, igual que en
    -- el POS. `quantity` sigue en unidades base.
    lower(nullif(btrim(item->>'uom'), '')),
    nullif(item->>'uom_factor', '')::numeric,
    nullif(item->>'uom_price', '')::numeric,
    nullif(btrim(item->>'unit_name'), ''),
    v_user_id,
    v_user_id
  from jsonb_array_elements(requested_items) as item;

  insert into public.quotation_events (
    quotation_id,
    branch_id,
    event_type,
    payload,
    created_by
  )
  values (
    target_quotation_id,
    v_branch_id,
    'updated',
    jsonb_build_object(
      'status', requested_status,
      'valid_until', requested_valid_until,
      'items_count', jsonb_array_length(requested_items),
      'total_amount', round(v_total, 2)
    ),
    v_user_id
  );

  return query select target_quotation_id;
end;
$$;

grant execute on function public.update_quotation_document(
  uuid, uuid, public.quote_status, timestamptz, text, jsonb, text
) to authenticated;


-- ── 3) Pasarla a la venta al convertir ─────────────────────────────────────
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
    tax_rate, line_subtotal, line_tax, line_total,
    -- CAMBIO (migración 95): la presentación cotizada pasa a la factura.
    uom, uom_factor, uom_price, unit_name
  )
  select
    v_sale_id, qi.branch_id, qi.product_id, qi.description, qi.quantity, qi.unit_price, qi.discount_amount,
    -- CAMBIO (migración 94): sin comprobante, cada línea sin ITBIS.
    case when v_no_tax then 0 else qi.tax_rate end,
    qi.line_subtotal,
    case when v_no_tax then 0 else qi.line_tax end,
    case when v_no_tax then qi.line_total - qi.line_tax else qi.line_total end,
    -- CAMBIO (migración 95): `sale_items.uom` y `uom_factor` son NOT NULL con
    -- default, así que una cotización vieja (sin presentación) entra como
    -- 'unit' × 1, exactamente como antes.
    coalesce(qi.uom, 'unit'),
    coalesce(qi.uom_factor, 1),
    qi.uom_price,
    qi.unit_name
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
-- VERIFICACIÓN — una sola fila, con las cuatro columnas en true.
-- ============================================================================
select
  (select count(*) from information_schema.columns
    where table_schema = 'public' and table_name = 'quotation_items'
      and column_name in ('uom', 'uom_factor', 'uom_price', 'unit_name')) = 4
                                                        as columnas_listas,
  (select bool_or(pg_get_functiondef(p.oid) like '%uom_price%')
     from pg_proc p join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'public' and p.proname = 'update_quotation_document')
                                                        as guarda_presentacion,
  (select bool_or(pg_get_functiondef(p.oid) like '%qi.uom_price%')
     from pg_proc p join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'public' and p.proname = 'convert_quotation_to_sale')
                                                        as la_pasa_a_la_venta,
  (select bool_or(pg_get_functiondef(p.oid) like '%v_no_tax%')
     from pg_proc p join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'public' and p.proname = 'convert_quotation_to_sale')
                                                        as sigue_sin_itbis;
