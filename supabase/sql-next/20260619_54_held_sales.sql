-- ============================================================================
-- Migración 54 — Ventas guardadas / cuentas abiertas (venta suspendida)
-- ============================================================================
-- Caso de uso: el cajero atiende a un cliente, llega otro, y deja la primera
-- cuenta GUARDADA y abierta. Pueden coexistir varias cuentas pendientes a la
-- vez (cada una su fila en el historial, en estado 'pending' / chip gris).
--
-- Modelo (decisión del dueño: el stock SE RESERVA al guardar):
--   - "Guardar"  → hold_sale_transactional: crea la venta en estado 'pending'
--     e inserta sus sale_items. El trigger trg_sale_items_stock descuenta el
--     stock (la reserva). NO se crea caja (cash_session_id = NULL), NO se
--     registran pagos y NO se asigna NCF (el trigger de NCF solo asigna en
--     'completed'/'credit'). Por eso NO entra al cierre de caja.
--   - "Descartar" → discard_held_sale: borra los sale_items (el trigger
--     DEVUELVE el stock) y borra la fila 'pending'. Solo opera sobre ventas en
--     estado 'pending' (nunca toca ventas reales).
--
-- Al COMPLETAR una cuenta reabierta, checkout_sale_transactional la ABSORBE
-- (nuevo parámetro p_hold_sale_id): reusa el MISMO número de la cuenta, libera
-- su stock reservado (borrando sus líneas → el trigger lo devuelve) y la
-- reemplaza por la venta real. Sigue siendo un INSERT, así que NCF y
-- fiscal_documents se generan por sus triggers normales. Todo en una sola
-- transacción (atómico): si el checkout falla, la cuenta guardada queda intacta.
--
-- Ejecutar en el SQL Editor de Supabase, DESPUÉS de la migración 53.
-- Idempotente (CREATE OR REPLACE). Esta migración REDEFINE
-- checkout_sale_transactional (copia fiel de la 53 + el parámetro p_hold_sale_id).
-- ============================================================================

begin;

-- ----------------------------------------------------------------------------
-- hold_sale_transactional: guarda el carrito como venta 'pending'.
-- ----------------------------------------------------------------------------
drop function if exists public.hold_sale_transactional(jsonb, text, uuid, text);

create or replace function public.hold_sale_transactional(
  p_items jsonb,
  p_receipt_type text default 'consumer_final',
  p_client_id uuid default null,
  p_notes text default null,
  p_replace_hold_sale_id uuid default null
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_user_id uuid := auth.uid();
  v_branch_id uuid := public.current_branch_id();
  v_receipt_type public.receipt_type;
  v_sale_id uuid;
  v_sale_number text;
  v_replace_sale_number text;
  v_subtotal numeric(14,2) := 0;
  v_tax_amount numeric(14,2) := 0;
  v_total_amount numeric(14,2) := 0;
  v_client record;
  v_item record;
  v_product record;
  v_item_count integer := 0;
  v_note text;
  v_now timestamptz := timezone('utc', now());
  v_enforce_stock boolean := true;
begin
  if v_user_id is null then
    raise exception 'Sesión inválida. Inicia sesión de nuevo.'
      using errcode = '28000';
  end if;

  if v_branch_id is null then
    raise exception 'No hay sucursal asignada para este usuario.'
      using errcode = '22023';
  end if;

  if not public.has_branch_access(v_branch_id) then
    raise exception 'No tienes acceso a la sucursal actual.'
      using errcode = '42501';
  end if;

  if not public.can_operate_pos() then
    raise exception 'Tu rol no puede operar el POS.'
      using errcode = '42501';
  end if;

  if p_items is null or jsonb_typeof(p_items) <> 'array'
     or jsonb_array_length(p_items) = 0 then
    raise exception 'No hay productos en el carrito.'
      using errcode = '22023';
  end if;

  v_receipt_type := public.normalize_receipt_type(p_receipt_type);
  v_note := nullif(trim(coalesce(p_notes, '')), '');

  if p_client_id is not null then
    select c.id, c.full_name, c.is_active
    into v_client
    from public.clients c
    where c.id = p_client_id and c.branch_id = v_branch_id;
    if not found then
      raise exception 'Cliente no encontrado en la sucursal actual.'
        using errcode = '23503';
    end if;
    if not v_client.is_active then
      raise exception 'Cliente "%": cuenta inactiva.', v_client.full_name
        using errcode = '22023';
    end if;
  end if;

  begin
    select coalesce(s.inv_disallow_no_stock, true)
      into v_enforce_stock
      from public.app_settings s
      join public.branches b on b.company_id = s.company_id
     where b.id = v_branch_id
     limit 1;
    if v_enforce_stock is null then
      v_enforce_stock := true;
    end if;
  exception
    when undefined_column or undefined_table or undefined_function then
      v_enforce_stock := true;
  end;

  -- Re-guardar una cuenta reabierta: reusar su número, liberar su stock
  -- reservado (borrando sus líneas → el trigger lo devuelve) y borrarla. Se
  -- hace ANTES de validar stock para que el inventario liberado esté
  -- disponible. La nueva cuenta guardada conserva el mismo número.
  if p_replace_hold_sale_id is not null then
    select sale_number into v_replace_sale_number
      from public.sales
     where id = p_replace_hold_sale_id
       and branch_id = v_branch_id
       and status = 'pending'::public.sale_status
     for update;
    if v_replace_sale_number is null then
      raise exception 'La cuenta guardada no existe o ya no está pendiente.'
        using errcode = '22023';
    end if;
    delete from public.sale_items where sale_id = p_replace_hold_sale_id;
    delete from public.sales where id = p_replace_hold_sale_id;
  end if;

  create temp table if not exists tmp_hold_items (
    product_id uuid,
    description text,
    quantity numeric(14,3),
    unit_price numeric(14,2),
    tax_rate numeric(5,2),
    line_subtotal numeric(14,2),
    line_tax numeric(14,2),
    line_total numeric(14,2),
    imeis text[]
  ) on commit drop;
  truncate tmp_hold_items;

  for v_item in
    select
      (item->>'product_id')::uuid as product_id,
      coalesce(nullif(trim(item->>'description'), ''), '')::text as description,
      coalesce((item->>'quantity')::numeric, 0)::numeric(14,3) as quantity,
      coalesce((item->>'unit_price')::numeric, 0)::numeric(14,2) as unit_price,
      coalesce(
        (select array_agg(x) from jsonb_array_elements_text(
           case when jsonb_typeof(item->'imeis') = 'array'
                then item->'imeis' else '[]'::jsonb end) as x),
        '{}'::text[]) as imeis
    from jsonb_array_elements(p_items) as item
  loop
    if v_item.product_id is null then
      raise exception 'Producto sin id en el carrito.' using errcode = '22023';
    end if;
    if v_item.quantity is null or v_item.quantity <= 0 then
      raise exception 'Cantidad inválida en producto %', v_item.product_id
        using errcode = '22023';
    end if;

    select p.id, p.name, p.price, p.tax_rate, p.stock, p.is_active,
           p.allow_negative_stock, p.is_service, p.is_tax_exempt
    into v_product
    from public.products p
    where p.id = v_item.product_id and p.branch_id = v_branch_id;

    if not found then
      raise exception 'Producto no encontrado: %', v_item.product_id
        using errcode = '23503';
    end if;
    if not v_product.is_active then
      raise exception 'Producto "%": inactivo.', v_product.name
        using errcode = '22023';
    end if;

    if v_enforce_stock
       and (not v_product.is_service)
       and (not coalesce(v_product.allow_negative_stock, false))
       and (v_product.stock is null or v_product.stock < v_item.quantity) then
      raise exception 'Stock insuficiente para "%": disponible % requerido %',
        v_product.name, coalesce(v_product.stock, 0), v_item.quantity
        using errcode = '22023';
    end if;

    insert into tmp_hold_items
    values (
      v_item.product_id,
      coalesce(nullif(v_item.description, ''), v_product.name),
      v_item.quantity,
      v_item.unit_price,
      case when v_product.is_tax_exempt then 0 else v_product.tax_rate end,
      round((v_item.unit_price * v_item.quantity)::numeric, 2),
      round((v_item.unit_price * v_item.quantity *
             case when v_product.is_tax_exempt then 0
                  else v_product.tax_rate end / 100)::numeric, 2),
      round((v_item.unit_price * v_item.quantity *
             (1 + case when v_product.is_tax_exempt then 0
                       else v_product.tax_rate end / 100))::numeric, 2),
      coalesce(v_item.imeis, '{}'::text[])
    );
    v_item_count := v_item_count + 1;
  end loop;

  if v_item_count = 0 then
    raise exception 'No hay productos válidos en el carrito.'
      using errcode = '22023';
  end if;

  select
    coalesce(sum(line_subtotal), 0),
    coalesce(sum(line_tax), 0),
    coalesce(sum(line_total), 0)
  into v_subtotal, v_tax_amount, v_total_amount
  from tmp_hold_items;

  -- Número: reusa el de la cuenta que se está reemplazando (re-guardado de una
  -- cuenta reabierta), o genera uno nuevo.
  v_sale_number := coalesce(
    v_replace_sale_number,
    'VTA-'
      || to_char(v_now at time zone 'UTC', 'YYYYMMDD-HH24MISSMS')
      || '-'
      || upper(substr(replace(gen_random_uuid()::text, '-', ''), 1, 4))
  );

  -- Venta GUARDADA: estado 'pending', sin caja, sin cobro. balance_due = 0 a
  -- propósito: una cuenta guardada NO es una deuda — no debe aparecer en Cobros
  -- ni en cuentas por cobrar (esas pantallas filtran balance_due > 0). El
  -- trigger de NCF NO asigna comprobante en 'pending'.
  insert into public.sales (
    branch_id, sale_number, client_id, cashier_id, receipt_type, status,
    sale_date, subtotal, discount_amount, tax_amount, total_amount,
    paid_amount, balance_due, change_amount, notes, due_date, cash_session_id
  ) values (
    v_branch_id, v_sale_number, p_client_id, v_user_id, v_receipt_type,
    'pending'::public.sale_status, v_now, v_subtotal, 0, v_tax_amount,
    v_total_amount, 0, 0, 0, v_note, null, null
  )
  returning id into v_sale_id;

  -- Inserta las líneas: el trigger trg_sale_items_stock RESERVA el stock.
  -- Nota: los IMEIs se guardan en la línea para poder reabrir la cuenta, pero
  -- NO se quitan de products.imeis todavía; eso ocurre al completar la venta
  -- real (checkout_sale_transactional), que es cuando el equipo sale de verdad.
  insert into public.sale_items (
    sale_id, branch_id, product_id, description, quantity, unit_price,
    discount_amount, tax_rate, line_subtotal, line_tax, line_total, imeis
  )
  select v_sale_id, v_branch_id, product_id, description, quantity,
         unit_price, 0, tax_rate, line_subtotal, line_tax, line_total,
         coalesce(imeis, '{}'::text[])
  from tmp_hold_items
  order by product_id;

  return jsonb_build_object(
    'sale_id', v_sale_id,
    'sale_number', v_sale_number,
    'branch_id', v_branch_id,
    'receipt_type', v_receipt_type,
    'status', 'pending',
    'subtotal', v_subtotal,
    'tax_amount', v_tax_amount,
    'total_amount', v_total_amount,
    'items_count', v_item_count
  );
end;
$$;

grant execute on function public.hold_sale_transactional(
  jsonb, text, uuid, text, uuid
) to authenticated;

-- ----------------------------------------------------------------------------
-- discard_held_sale: descarta una cuenta GUARDADA y devuelve el stock.
-- ----------------------------------------------------------------------------
-- Solo opera sobre ventas en estado 'pending' (cuentas guardadas). Borra los
-- sale_items (el trigger trg_sale_items_stock devuelve el stock reservado) y
-- borra la fila. No hay pagos ni NCF que revertir porque una cuenta guardada
-- nunca los tuvo.
create or replace function public.discard_held_sale(
  p_sale_id uuid
)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_branch_id uuid;
  v_status public.sale_status;
begin
  if p_sale_id is null then
    raise exception 'p_sale_id es requerido.'
      using errcode = '22023';
  end if;

  select branch_id, status into v_branch_id, v_status
  from public.sales
  where id = p_sale_id
  for update;

  if v_branch_id is null then
    raise exception 'Venta no encontrada.'
      using errcode = 'P0002';
  end if;

  if not public.has_branch_access(v_branch_id) then
    raise exception 'Sin acceso a esta venta.'
      using errcode = '42501';
  end if;

  if v_status <> 'pending'::public.sale_status then
    raise exception 'Solo se pueden descartar cuentas guardadas (pendientes).'
      using errcode = '22023';
  end if;

  -- 1) Borrar líneas → el trigger devuelve el stock reservado.
  delete from public.sale_items where sale_id = p_sale_id;

  -- 2) Borrar la cuenta guardada (no tiene pagos ni NCF).
  delete from public.sales where id = p_sale_id;
end;
$$;

grant execute on function public.discard_held_sale(uuid) to authenticated;

-- ----------------------------------------------------------------------------
-- checkout_sale_transactional: ahora puede ABSORBER una cuenta guardada.
-- ----------------------------------------------------------------------------
-- Copia FIEL de la migración 53 con un único agregado: el parámetro
-- p_hold_sale_id. Cuando se pasa, completar una cuenta reabierta:
--   1) toma el sale_number de esa cuenta 'pending',
--   2) borra sus líneas (el trigger DEVUELVE el stock reservado) y la fila,
--   3) la venta real reusa ESE número (no genera uno nuevo).
-- Se hace antes de validar stock para que el inventario liberado esté
-- disponible. Si p_hold_sale_id es null, se comporta igual que antes.
drop function if exists public.checkout_sale_transactional(
  jsonb, text, boolean, text, uuid, text, integer, uuid, jsonb
);

create or replace function public.checkout_sale_transactional(
  p_items jsonb,
  p_receipt_type text default 'consumer_final',
  p_as_credit boolean default false,
  p_payment_method text default null,
  p_client_id uuid default null,
  p_notes text default null,
  p_credit_due_days integer default null,
  p_cash_session_id uuid default null,
  p_payments jsonb default null,
  p_hold_sale_id uuid default null
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_user_id uuid := auth.uid();
  v_branch_id uuid := public.current_branch_id();
  v_receipt_type public.receipt_type;
  v_sale_status public.sale_status;
  v_payment_method public.payment_method;
  v_sale_id uuid;
  v_sale_number text;
  v_held_sale_number text;
  v_subtotal numeric(14,2) := 0;
  v_tax_amount numeric(14,2) := 0;
  v_total_amount numeric(14,2) := 0;
  v_paid_amount numeric(14,2) := 0;
  v_balance_due numeric(14,2) := 0;
  v_change numeric(14,2) := 0;
  v_open_cash_session_id uuid;
  v_client record;
  v_item record;
  v_product record;
  v_item_count integer := 0;
  v_note text;
  v_now timestamptz := timezone('utc', now());
  v_default_days integer;
  v_due_days integer;
  v_due_date date;
  v_enforce_stock boolean := true;
  v_pay record;
  v_pay_sum numeric(14,2) := 0;
  v_has_split boolean := false;
  v_sold record;
begin
  if v_user_id is null then
    raise exception 'Sesión inválida. Inicia sesión de nuevo.'
      using errcode = '28000';
  end if;

  if v_branch_id is null then
    raise exception 'No hay sucursal asignada para este usuario.'
      using errcode = '22023';
  end if;

  if not public.has_branch_access(v_branch_id) then
    raise exception 'No tienes acceso a la sucursal actual.'
      using errcode = '42501';
  end if;

  if not public.can_operate_pos() then
    raise exception 'Tu rol no puede operar el POS.'
      using errcode = '42501';
  end if;

  if p_items is null or jsonb_typeof(p_items) <> 'array'
     or jsonb_array_length(p_items) = 0 then
    raise exception 'No hay productos en el carrito.'
      using errcode = '22023';
  end if;

  v_receipt_type := public.normalize_receipt_type(p_receipt_type);
  v_sale_status := case when p_as_credit then 'credit'::public.sale_status
                        else 'completed'::public.sale_status end;
  v_note := nullif(trim(coalesce(p_notes, '')), '');

  if not p_as_credit then
    begin
      v_payment_method := coalesce(nullif(trim(p_payment_method), ''), 'cash')
        ::public.payment_method;
    exception
      when invalid_text_representation then
        raise exception 'Método de pago no soportado: %', p_payment_method
          using errcode = '22023';
    end;
  end if;

  if p_client_id is not null then
    select c.id, c.full_name, c.balance_due, c.credit_limit, c.is_active
    into v_client
    from public.clients c
    where c.id = p_client_id and c.branch_id = v_branch_id;
    if not found then
      raise exception 'Cliente no encontrado en la sucursal actual.'
        using errcode = '23503';
    end if;
    if not v_client.is_active then
      raise exception 'Cliente "%": cuenta inactiva.', v_client.full_name
        using errcode = '22023';
    end if;
  end if;

  if p_as_credit and p_client_id is null then
    raise exception 'Las ventas a crédito requieren un cliente.'
      using errcode = '22023';
  end if;

  if p_cash_session_id is not null then
    select cs.id into v_open_cash_session_id
      from public.cash_sessions cs
     where cs.id = p_cash_session_id
       and cs.branch_id = v_branch_id
       and cs.status = 'open'
       and (
         cs.opened_by = v_user_id
         or cs.cash_register_id is null
         or exists (
           select 1 from public.cash_register_users cru
           where cru.cash_register_id = cs.cash_register_id
             and cru.user_id = v_user_id
             and cru.is_active
         )
       );

    if v_open_cash_session_id is null then
      raise exception 'La caja seleccionada no está abierta o no tienes acceso a ella.'
        using errcode = '22023';
    end if;
  else
    select cs.id into v_open_cash_session_id
      from public.cash_sessions cs
     where cs.branch_id = v_branch_id
       and cs.status = 'open'
       and (
         cs.opened_by = v_user_id
         or exists (
           select 1 from public.cash_register_users cru
           where cru.cash_register_id = cs.cash_register_id
             and cru.user_id = v_user_id
             and cru.is_active
         )
       )
     order by cs.opened_at desc
     limit 1;
  end if;

  begin
    select coalesce(s.inv_disallow_no_stock, true)
      into v_enforce_stock
      from public.app_settings s
      join public.branches b on b.company_id = s.company_id
     where b.id = v_branch_id
     limit 1;
    if v_enforce_stock is null then
      v_enforce_stock := true;
    end if;
  exception
    when undefined_column or undefined_table or undefined_function then
      v_enforce_stock := true;
  end;

  -- Absorber una cuenta GUARDADA reabierta: reusar su número, liberar su stock
  -- reservado y borrarla. Se hace ANTES de validar stock para que el inventario
  -- devuelto esté disponible. Si el checkout falla luego, se revierte todo.
  if p_hold_sale_id is not null then
    select sale_number into v_held_sale_number
      from public.sales
     where id = p_hold_sale_id
       and branch_id = v_branch_id
       and status = 'pending'::public.sale_status
     for update;
    if v_held_sale_number is null then
      raise exception 'La cuenta guardada no existe o ya no está pendiente.'
        using errcode = '22023';
    end if;
    delete from public.sale_items where sale_id = p_hold_sale_id;
    delete from public.sales where id = p_hold_sale_id;
  end if;

  create temp table if not exists tmp_checkout_items (
    product_id uuid,
    description text,
    quantity numeric(14,3),
    unit_price numeric(14,2),
    tax_rate numeric(5,2),
    line_subtotal numeric(14,2),
    line_tax numeric(14,2),
    line_total numeric(14,2),
    imeis text[]
  ) on commit drop;
  truncate tmp_checkout_items;

  for v_item in
    select
      (item->>'product_id')::uuid as product_id,
      coalesce(nullif(trim(item->>'description'), ''), '')::text as description,
      coalesce((item->>'quantity')::numeric, 0)::numeric(14,3) as quantity,
      coalesce((item->>'unit_price')::numeric, 0)::numeric(14,2) as unit_price,
      coalesce(
        (select array_agg(x) from jsonb_array_elements_text(
           case when jsonb_typeof(item->'imeis') = 'array'
                then item->'imeis' else '[]'::jsonb end) as x),
        '{}'::text[]) as imeis
    from jsonb_array_elements(p_items) as item
  loop
    if v_item.product_id is null then
      raise exception 'Producto sin id en el carrito.' using errcode = '22023';
    end if;
    if v_item.quantity is null or v_item.quantity <= 0 then
      raise exception 'Cantidad inválida en producto %', v_item.product_id
        using errcode = '22023';
    end if;

    select p.id, p.name, p.price, p.tax_rate, p.stock, p.is_active,
           p.allow_negative_stock, p.is_service, p.is_tax_exempt
    into v_product
    from public.products p
    where p.id = v_item.product_id and p.branch_id = v_branch_id;

    if not found then
      raise exception 'Producto no encontrado: %', v_item.product_id
        using errcode = '23503';
    end if;
    if not v_product.is_active then
      raise exception 'Producto "%": inactivo.', v_product.name
        using errcode = '22023';
    end if;

    if v_enforce_stock
       and (not v_product.is_service)
       and (not coalesce(v_product.allow_negative_stock, false))
       and (v_product.stock is null or v_product.stock < v_item.quantity) then
      raise exception 'Stock insuficiente para "%": disponible % requerido %',
        v_product.name, coalesce(v_product.stock, 0), v_item.quantity
        using errcode = '22023';
    end if;

    insert into tmp_checkout_items
    values (
      v_item.product_id,
      coalesce(nullif(v_item.description, ''), v_product.name),
      v_item.quantity,
      v_item.unit_price,
      case when v_product.is_tax_exempt then 0 else v_product.tax_rate end,
      round((v_item.unit_price * v_item.quantity)::numeric, 2),
      round((v_item.unit_price * v_item.quantity *
             case when v_product.is_tax_exempt then 0
                  else v_product.tax_rate end / 100)::numeric, 2),
      round((v_item.unit_price * v_item.quantity *
             (1 + case when v_product.is_tax_exempt then 0
                       else v_product.tax_rate end / 100))::numeric, 2),
      coalesce(v_item.imeis, '{}'::text[])
    );
    v_item_count := v_item_count + 1;
  end loop;

  if v_item_count = 0 then
    raise exception 'No hay productos válidos en el carrito.'
      using errcode = '22023';
  end if;

  select
    coalesce(sum(line_subtotal), 0),
    coalesce(sum(line_tax), 0),
    coalesce(sum(line_total), 0)
  into v_subtotal, v_tax_amount, v_total_amount
  from tmp_checkout_items;

  v_paid_amount := case when p_as_credit then 0 else v_total_amount end;
  v_balance_due := case when p_as_credit then v_total_amount else 0 end;

  v_has_split := (not p_as_credit)
                 and p_payments is not null
                 and jsonb_typeof(p_payments) = 'array'
                 and jsonb_array_length(p_payments) > 0;
  if v_has_split then
    select coalesce(sum((e->>'amount')::numeric), 0)
      into v_pay_sum
      from jsonb_array_elements(p_payments) as e;

    if round(v_pay_sum, 2) < round(v_total_amount, 2) then
      raise exception 'Los pagos (%) no cubren el total (%).',
        round(v_pay_sum, 2), round(v_total_amount, 2)
        using errcode = '22023';
    end if;
    v_change := round(v_pay_sum - v_total_amount, 2);
  end if;

  if p_as_credit then
    select credit_default_days into v_default_days
    from public.app_settings where id = 1;
    v_default_days := coalesce(v_default_days, 30);
    v_due_days := coalesce(p_credit_due_days, v_default_days);
    if v_due_days <= 0 or v_due_days > 365 then
      v_due_days := v_default_days;
    end if;
    v_due_date := (v_now at time zone 'UTC')::date
                  + (v_due_days || ' days')::interval;
  end if;

  -- Número: reusa el de la cuenta guardada si se está absorbiendo una; si no,
  -- genera uno nuevo.
  v_sale_number := coalesce(
    v_held_sale_number,
    'VTA-'
      || to_char(v_now at time zone 'UTC', 'YYYYMMDD-HH24MISSMS')
      || '-'
      || upper(substr(replace(gen_random_uuid()::text, '-', ''), 1, 4))
  );

  insert into public.sales (
    branch_id, sale_number, client_id, cashier_id, receipt_type, status,
    sale_date, subtotal, discount_amount, tax_amount, total_amount,
    paid_amount, balance_due, change_amount, notes, due_date, cash_session_id
  ) values (
    v_branch_id, v_sale_number, p_client_id, v_user_id, v_receipt_type,
    v_sale_status, v_now, v_subtotal, 0, v_tax_amount, v_total_amount,
    v_paid_amount, v_balance_due, v_change, v_note, v_due_date,
    v_open_cash_session_id
  )
  returning id into v_sale_id;

  insert into public.sale_items (
    sale_id, branch_id, product_id, description, quantity, unit_price,
    discount_amount, tax_rate, line_subtotal, line_tax, line_total, imeis
  )
  select v_sale_id, v_branch_id, product_id, description, quantity,
         unit_price, 0, tax_rate, line_subtotal, line_tax, line_total,
         coalesce(imeis, '{}'::text[])
  from tmp_checkout_items
  order by product_id;

  -- Quitar del inventario los IMEIs vendidos (el equipo deja de existir).
  for v_sold in
    select product_id, imeis as sold
      from tmp_checkout_items
     where coalesce(array_length(imeis, 1), 0) > 0
  loop
    update public.products p
       set imeis = coalesce(
             (select array_agg(e order by e)
                from unnest(p.imeis) as e
               where not (e = any(v_sold.sold))),
             '{}'::text[])
     where p.id = v_sold.product_id and p.branch_id = v_branch_id;
  end loop;

  if not p_as_credit then
    if v_has_split then
      for v_pay in
        select
          coalesce(nullif(trim(e->>'method'), ''), 'cash') as method,
          coalesce((e->>'amount')::numeric, 0)::numeric(14,2) as amount
        from jsonb_array_elements(p_payments) as e
      loop
        if v_pay.amount <= 0 then
          continue;
        end if;
        begin
          insert into public.payments (
            branch_id, sale_id, client_id, cash_session_id, payment_method,
            amount, paid_at, reference, notes
          ) values (
            v_branch_id, v_sale_id, p_client_id, v_open_cash_session_id,
            v_pay.method::public.payment_method, v_pay.amount, v_now,
            v_sale_number, v_note
          );
        exception
          when invalid_text_representation then
            raise exception 'Método de pago no soportado: %', v_pay.method
              using errcode = '22023';
        end;
      end loop;
    else
      insert into public.payments (
        branch_id, sale_id, client_id, cash_session_id, payment_method,
        amount, paid_at, reference, notes
      ) values (
        v_branch_id, v_sale_id, p_client_id, v_open_cash_session_id,
        v_payment_method, v_total_amount, v_now, v_sale_number, v_note
      );
    end if;
  elsif p_client_id is not null then
    update public.clients
    set balance_due = round(
      (coalesce(balance_due, 0) + v_total_amount)::numeric, 2
    )
    where id = p_client_id and branch_id = v_branch_id;
  end if;

  return jsonb_build_object(
    'sale_id', v_sale_id,
    'sale_number', v_sale_number,
    'branch_id', v_branch_id,
    'cash_session_id', v_open_cash_session_id,
    'receipt_type', v_receipt_type,
    'status', v_sale_status,
    'subtotal', v_subtotal,
    'tax_amount', v_tax_amount,
    'total_amount', v_total_amount,
    'paid_amount', v_paid_amount,
    'balance_due', v_balance_due,
    'change_amount', v_change,
    'due_date', v_due_date,
    'items_count', (select count(*) from tmp_checkout_items)
  );
end;
$$;

grant execute on function public.checkout_sale_transactional(
  jsonb, text, boolean, text, uuid, text, integer, uuid, jsonb, uuid
) to authenticated;

-- ----------------------------------------------------------------------------
-- Consistencia de reportes con las cuentas guardadas.
-- ----------------------------------------------------------------------------
-- Las cuentas GUARDADAS quedan en estado 'pending' y NO son ventas reales
-- todavía (no cobradas, sin NCF, fuera del cierre de caja). Estos objetos
-- excluían solo 'voided'; ahora excluyen también 'pending' para que una cuenta
-- abierta no infle KPIs, totales por cliente ni el desglose fiscal. Son copias
-- FIELES de su definición actual: el ÚNICO cambio es el filtro de estado
-- (`<> 'voided'` → `not in ('voided','pending')`).

-- KPI "total de ventas" del dashboard (conteo).
create or replace function public.dashboard_v2_kpis(
  p_branch_id uuid default null
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_branch_id uuid;
  v_total_ventas bigint;
  v_total_inventario bigint;
  v_total_clientes bigint;
  v_total_kits bigint;
begin
  v_branch_id := coalesce(p_branch_id, public.current_branch_id());
  if v_branch_id is null then
    return jsonb_build_object(
      'partial', true,
      'total_ventas', 0,
      'total_inventario', 0,
      'total_clientes', 0,
      'total_kits', 0
    );
  end if;

  if not (public.has_branch_access(v_branch_id) or public.is_admin()) then
    raise exception 'Sin acceso a la sucursal indicada';
  end if;

  select count(*)
    into v_total_ventas
    from public.sales s
   where s.branch_id = v_branch_id
     and s.status not in (
       'voided'::public.sale_status, 'pending'::public.sale_status
     );

  select count(*)
    into v_total_inventario
    from public.products p
   where p.branch_id = v_branch_id
     and p.is_active = true
     and p.stock > 0;

  select count(*)
    into v_total_clientes
    from public.clients c
   where c.branch_id = v_branch_id
     and c.is_active = true
     and lower(coalesce(c.full_name, '')) <> 'consumidor final';

  -- Kits: TBD (PRD §12.1). No hay modelo de kits aún.
  v_total_kits := 0;

  return jsonb_build_object(
    'branch_id', v_branch_id,
    'total_ventas', coalesce(v_total_ventas, 0),
    'total_inventario', coalesce(v_total_inventario, 0),
    'total_clientes', coalesce(v_total_clientes, 0),
    'total_kits', v_total_kits,
    'partial', false
  );
end;
$$;

grant execute on function public.dashboard_v2_kpis(uuid) to authenticated;

-- Resumen por cliente: conteo y total vendido históricos.
create or replace view public.customer_balances_view
with (security_invoker = true)
as
select
  c.id,
  c.branch_id,
  c.full_name,
  c.company_name,
  c.phone,
  c.email,
  c.credit_limit,
  c.balance_due,
  c.price_tier,
  c.tax_exempt,
  c.charge_itbis,
  count(s.id) filter (
    where s.status not in (
      'voided'::public.sale_status, 'pending'::public.sale_status
    )
  )::bigint as sales_count,
  coalesce(sum(s.total_amount) filter (
    where s.status not in (
      'voided'::public.sale_status, 'pending'::public.sale_status
    )
  ), 0)::numeric(14,2) as total_sales_amount,
  max(s.sale_date) as last_sale_at
from public.clients c
left join public.sales s on s.client_id = c.id and s.branch_id = c.branch_id
where public.has_branch_access(c.branch_id)
group by c.id, c.branch_id, c.full_name, c.company_name, c.phone, c.email, c.credit_limit, c.balance_due, c.price_tier, c.tax_exempt, c.charge_itbis;

-- Desglose fiscal por venta (ITBIS / exento). Las pendientes no son fiscales.
create or replace view public.sales_tax_breakdown_view
with (security_invoker = true)
as
select
  s.id as sale_id,
  s.branch_id,
  s.sale_number,
  s.sale_date,
  s.receipt_type,
  s.status,
  s.taxable_amount,
  s.exempt_amount,
  s.tax_amount,
  s.service_charge_amount,
  s.total_amount,
  coalesce(s.client_name_snapshot, c.full_name, 'Cliente General') as client_name
from public.sales s
left join public.clients c on c.id = s.client_id and c.branch_id = s.branch_id
where public.has_branch_access(s.branch_id)
  and s.status not in (
    'voided'::public.sale_status, 'pending'::public.sale_status
  );

-- KPIs por sucursal (ventas de hoy/mes en monto y conteo).
create or replace view public.dashboard_kpis_by_branch
with (security_invoker = true)
as
with sales_scope as (
  select s.*
  from public.sales s
  where s.status not in (
    'voided'::public.sale_status, 'pending'::public.sale_status
  )
),
month_bounds as (
  select
    date_trunc('month', timezone('utc', now())) as month_start,
    date_trunc('month', timezone('utc', now())) + interval '1 month' as next_month_start
),
active_products as (
  select p.branch_id, count(*)::bigint as products_active
  from public.products p
  where p.is_active
  group by p.branch_id
),
active_clients as (
  select c.branch_id, count(*)::bigint as clients_active
  from public.clients c
  where c.is_active
  group by c.branch_id
),
ncf_usage as (
  select
    ns.branch_id,
    coalesce(sum(ns.current_number), 0)::bigint as ncf_consumed,
    coalesce(sum(greatest(coalesce(ns.max_number, ns.current_number), ns.current_number) - ns.current_number), 0)::bigint as ncf_available
  from public.ncf_sequences ns
  where ns.is_active
  group by ns.branch_id
)
select
  b.id as branch_id,
  b.code as branch_code,
  b.name as branch_name,
  coalesce(sum(case when s.sale_date::date = timezone('utc', now())::date then s.total_amount else 0 end), 0)::numeric(14,2) as sales_today_amount,
  coalesce(sum(case when s.sale_date::date = timezone('utc', now())::date then 1 else 0 end), 0)::bigint as sales_today_count,
  coalesce(sum(case when s.sale_date >= mb.month_start and s.sale_date < mb.next_month_start then s.total_amount else 0 end), 0)::numeric(14,2) as sales_month_amount,
  coalesce(sum(case when s.sale_date >= mb.month_start and s.sale_date < mb.next_month_start then 1 else 0 end), 0)::bigint as sales_month_count,
  coalesce(ap.products_active, 0)::bigint as products_active,
  coalesce(ac.clients_active, 0)::bigint as clients_active,
  coalesce(sum(case when s.ncf is not null and s.sale_date >= mb.month_start and s.sale_date < mb.next_month_start then 1 else 0 end), 0)::bigint as ecf_issued_month,
  coalesce(nu.ncf_consumed, 0)::bigint as ncf_consumed,
  coalesce(nu.ncf_available, 0)::bigint as ncf_available
from public.branches b
cross join month_bounds mb
left join sales_scope s on s.branch_id = b.id
left join active_products ap on ap.branch_id = b.id
left join active_clients ac on ac.branch_id = b.id
left join ncf_usage nu on nu.branch_id = b.id
where public.has_branch_access(b.id)
group by b.id, b.code, b.name, ap.products_active, ac.clients_active, nu.ncf_consumed, nu.ncf_available;

-- Ventas por mes (últimos 12 meses).
create or replace view public.sales_monthly_summary
with (security_invoker = true)
as
with months as (
  select generate_series(
    date_trunc('month', timezone('utc', now())) - interval '11 months',
    date_trunc('month', timezone('utc', now())),
    interval '1 month'
  ) as month_start
),
branches_scope as (
  select b.id, b.code, b.name
  from public.branches b
  where public.has_branch_access(b.id)
)
select
  bs.id as branch_id,
  bs.code as branch_code,
  bs.name as branch_name,
  m.month_start::date as period_start,
  to_char(m.month_start, 'YYYY-MM') as period_key,
  to_char(m.month_start, 'Mon YYYY') as period_label,
  coalesce(sum(s.total_amount), 0)::numeric(14,2) as total_amount,
  coalesce(count(s.id), 0)::bigint as transaction_count
from branches_scope bs
cross join months m
left join public.sales s
  on s.branch_id = bs.id
 and s.status not in (
   'voided'::public.sale_status, 'pending'::public.sale_status
 )
 and s.sale_date >= m.month_start
 and s.sale_date < m.month_start + interval '1 month'
group by bs.id, bs.code, bs.name, m.month_start
order by bs.name, m.month_start;

-- Ventas por semana (últimas 12 semanas).
create or replace view public.sales_weekly_summary
with (security_invoker = true)
as
with weeks as (
  select generate_series(
    date_trunc('week', timezone('utc', now())) - interval '11 weeks',
    date_trunc('week', timezone('utc', now())),
    interval '1 week'
  ) as week_start
),
branches_scope as (
  select b.id, b.code, b.name
  from public.branches b
  where public.has_branch_access(b.id)
)
select
  bs.id as branch_id,
  bs.code as branch_code,
  bs.name as branch_name,
  w.week_start::date as period_start,
  to_char(w.week_start, 'IYYY-"W"IW') as period_key,
  to_char(w.week_start, 'DD Mon') || ' - ' || to_char(w.week_start + interval '6 days', 'DD Mon') as period_label,
  coalesce(sum(s.total_amount), 0)::numeric(14,2) as total_amount,
  coalesce(count(s.id), 0)::bigint as transaction_count
from branches_scope bs
cross join weeks w
left join public.sales s
  on s.branch_id = bs.id
 and s.status not in (
   'voided'::public.sale_status, 'pending'::public.sale_status
 )
 and s.sale_date >= w.week_start
 and s.sale_date < w.week_start + interval '1 week'
group by bs.id, bs.code, bs.name, w.week_start
order by bs.name, w.week_start;

-- Cuentas por cobrar (resumen). 'pending' (cuenta guardada) NO es por cobrar.
create or replace view public.accounts_receivable_summary
with (security_invoker = true)
as
select
  s.branch_id,
  b.code as branch_code,
  b.name as branch_name,
  count(*) filter (where s.balance_due > 0)::bigint as invoices_open,
  coalesce(sum(s.balance_due) filter (where s.balance_due > 0), 0)::numeric(14,2) as total_balance_due,
  coalesce(sum(s.total_amount), 0)::numeric(14,2) as total_invoiced,
  coalesce(sum(p.amount), 0)::numeric(14,2) as total_collected
from public.sales s
join public.branches b on b.id = s.branch_id
left join public.payments p on p.sale_id = s.id and p.branch_id = s.branch_id
where public.has_branch_access(s.branch_id)
  and s.status in ('completed'::public.sale_status, 'credit'::public.sale_status)
group by s.branch_id, b.code, b.name;

commit;

notify pgrst, 'reload schema';
