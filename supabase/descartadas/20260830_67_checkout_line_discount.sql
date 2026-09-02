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
-- 20260830_67_checkout_line_discount.sql
--
-- El DESCUENTO POR LÍNEA del POS no llegaba al servidor.
--
-- El carrito resta el descuento y muestra el total ya rebajado, pero el
-- checkout mandaba el precio unitario BRUTO y estas funciones guardaban
-- `discount_amount = 0` fijo. Resultado, según cómo cobrara el cajero:
--
--   · Pago simple exacto → la venta quedaba registrada al precio COMPLETO, en
--     silencio: el cliente pagaba menos de lo que decía la venta y la caja
--     terminaba descuadrada.
--   · Pago mixto o con vuelto → el cobro FALLABA con "Los pagos (X) no cubren
--     el total (Y)", porque el servidor calculaba un total mayor que la suma
--     de los pagos enviados.
--
-- Lo delator: `edit_sale_transactional` (migración 47) SÍ acepta `discount_pct`
-- por línea. La misma venta valía distinto según si se creaba o se editaba.
--
-- Se corrigen las DOS funciones que insertan líneas desde el carrito:
--   1) checkout_sale_transactional — cobrar.
--   2) hold_sale_transactional     — guardar la cuenta (si no, el descuento
--      se perdía al guardar y reabrir).
--
-- Ambas son copia FIEL de la migración 64 + el descuento, con la MISMA
-- fórmula de la de edición:
--
--     bruto = precio × cantidad
--     desc  = bruto × discount_pct / 100
--     base  = bruto − desc
--     itbis = base × tasa / 100        (sobre la base YA descontada)
--
-- `discount_pct` es opcional y por defecto 0: una app vieja que no lo mande
-- sigue comportándose exactamente igual que antes.
--
-- Ejecutar en el SQL Editor de Supabase, DESPUÉS de:
--   supabase/sql-next/20260810_64_sale_without_ncf_complete.sql
-- Idempotente (CREATE OR REPLACE sobre las mismas firmas).
-- ============================================================================


-- ----------------------------------------------------------------------------
-- 1) checkout_sale_transactional — cobrar la venta.
-- ----------------------------------------------------------------------------
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
  v_line_tax_rate numeric(5,2);
  v_sale_status public.sale_status;
  v_payment_method public.payment_method;
  v_sale_id uuid;
  v_sale_number text;
  v_held_sale_number text;
  v_subtotal numeric(14,2) := 0;
  v_discount_amount numeric(14,2) := 0;
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
    discount_amount numeric(14,2),
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
      coalesce((item->>'discount_pct')::numeric, 0)::numeric(5,2) as discount_pct,
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
    if v_item.discount_pct < 0 or v_item.discount_pct > 100 then
      raise exception 'Descuento inválido en producto %: %',
        v_item.product_id, v_item.discount_pct
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

    -- Tasa efectiva de la línea. Una venta SIN comprobante es una nota de
    -- venta no fiscal: no factura ITBIS, así que la tasa va en 0 aunque el
    -- producto tenga la suya. Igual que un producto exento.
    v_line_tax_rate := case
      when v_receipt_type::text = 'none' then 0
      when v_product.is_tax_exempt        then 0
      else coalesce(v_product.tax_rate, 0)
    end;

    -- CAMBIO (migración 67): descuento por línea. MISMA fórmula que
    -- `edit_sale_transactional` (migración 47), para que una venta valga lo
    -- mismo se cree, se guarde o se edite: el descuento se aplica sobre el
    -- bruto y el ITBIS se calcula sobre la base YA descontada.
    declare
      v_gross numeric(14,2) := round(
        (v_item.unit_price * v_item.quantity)::numeric, 2
      );
      v_disc numeric(14,2) := round(
        (v_item.unit_price * v_item.quantity
         * v_item.discount_pct / 100)::numeric, 2
      );
      v_sub numeric(14,2);
      v_tax numeric(14,2);
    begin
      v_sub := round((v_gross - v_disc)::numeric, 2);
      v_tax := round((v_sub * v_line_tax_rate / 100)::numeric, 2);

      insert into tmp_checkout_items (
        product_id, description, quantity, unit_price, discount_amount,
        tax_rate, line_subtotal, line_tax, line_total, imeis
      ) values (
        v_item.product_id,
        coalesce(nullif(v_item.description, ''), v_product.name),
        v_item.quantity,
        v_item.unit_price,
        v_disc,
        v_line_tax_rate,
        v_sub,
        v_tax,
        round((v_sub + v_tax)::numeric, 2),
        coalesce(v_item.imeis, '{}'::text[])
      );
    end;
    v_item_count := v_item_count + 1;
  end loop;

  if v_item_count = 0 then
    raise exception 'No hay productos válidos en el carrito.'
      using errcode = '22023';
  end if;

  select
    coalesce(sum(line_subtotal), 0),
    coalesce(sum(line_tax), 0),
    coalesce(sum(line_total), 0),
    coalesce(sum(discount_amount), 0)
  into v_subtotal, v_tax_amount, v_total_amount, v_discount_amount
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
    v_sale_status, v_now, v_subtotal, v_discount_amount, v_tax_amount,
    v_total_amount,
    v_paid_amount, v_balance_due, v_change, v_note, v_due_date,
    v_open_cash_session_id
  )
  -- `sale_number` vuelve en el RETURNING, no de la variable local: el
  -- trigger trg_sales_short_number (migración 63) reemplaza el número
  -- autogenerado por el correlativo corto, y la app tiene que recibir ESE.
  returning id, sale_number into v_sale_id, v_sale_number;

  insert into public.sale_items (
    sale_id, branch_id, product_id, description, quantity, unit_price,
    discount_amount, tax_rate, line_subtotal, line_tax, line_total, imeis
  )
  select v_sale_id, v_branch_id, product_id, description, quantity,
         unit_price, discount_amount, tax_rate, line_subtotal, line_tax,
         line_total, coalesce(imeis, '{}'::text[])
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
    'discount_amount', v_discount_amount,
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
-- 2) hold_sale_transactional — guardar la cuenta para cobrarla después.
-- ----------------------------------------------------------------------------
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
  v_line_tax_rate numeric(5,2);
  v_sale_id uuid;
  v_sale_number text;
  v_replace_sale_number text;
  v_subtotal numeric(14,2) := 0;
  v_discount_amount numeric(14,2) := 0;
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
    discount_amount numeric(14,2),
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
      coalesce((item->>'discount_pct')::numeric, 0)::numeric(5,2) as discount_pct,
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
    if v_item.discount_pct < 0 or v_item.discount_pct > 100 then
      raise exception 'Descuento inválido en producto %: %',
        v_item.product_id, v_item.discount_pct
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

    -- Tasa efectiva de la línea. Una venta SIN comprobante es una nota de
    -- venta no fiscal: no factura ITBIS, así que la tasa va en 0 aunque el
    -- producto tenga la suya. Igual que un producto exento.
    v_line_tax_rate := case
      when v_receipt_type::text = 'none' then 0
      when v_product.is_tax_exempt        then 0
      else coalesce(v_product.tax_rate, 0)
    end;

    -- CAMBIO (migración 67): descuento por línea. MISMA fórmula que
    -- `edit_sale_transactional` (migración 47), para que una venta valga lo
    -- mismo se cree, se guarde o se edite: el descuento se aplica sobre el
    -- bruto y el ITBIS se calcula sobre la base YA descontada.
    declare
      v_gross numeric(14,2) := round(
        (v_item.unit_price * v_item.quantity)::numeric, 2
      );
      v_disc numeric(14,2) := round(
        (v_item.unit_price * v_item.quantity
         * v_item.discount_pct / 100)::numeric, 2
      );
      v_sub numeric(14,2);
      v_tax numeric(14,2);
    begin
      v_sub := round((v_gross - v_disc)::numeric, 2);
      v_tax := round((v_sub * v_line_tax_rate / 100)::numeric, 2);

      insert into tmp_hold_items (
        product_id, description, quantity, unit_price, discount_amount,
        tax_rate, line_subtotal, line_tax, line_total, imeis
      ) values (
        v_item.product_id,
        coalesce(nullif(v_item.description, ''), v_product.name),
        v_item.quantity,
        v_item.unit_price,
        v_disc,
        v_line_tax_rate,
        v_sub,
        v_tax,
        round((v_sub + v_tax)::numeric, 2),
        coalesce(v_item.imeis, '{}'::text[])
      );
    end;
    v_item_count := v_item_count + 1;
  end loop;

  if v_item_count = 0 then
    raise exception 'No hay productos válidos en el carrito.'
      using errcode = '22023';
  end if;

  select
    coalesce(sum(line_subtotal), 0),
    coalesce(sum(line_tax), 0),
    coalesce(sum(line_total), 0),
    coalesce(sum(discount_amount), 0)
  into v_subtotal, v_tax_amount, v_total_amount, v_discount_amount
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
    'pending'::public.sale_status, v_now, v_subtotal, v_discount_amount,
    v_tax_amount,
    v_total_amount, 0, 0, 0, v_note, null, null
  )
  -- `sale_number` vuelve en el RETURNING, no de la variable local: el
  -- trigger trg_sales_short_number (migración 63) reemplaza el número
  -- autogenerado por el correlativo corto, y la app tiene que recibir ESE.
  returning id, sale_number into v_sale_id, v_sale_number;

  -- Inserta las líneas: el trigger trg_sale_items_stock RESERVA el stock.
  -- Nota: los IMEIs se guardan en la línea para poder reabrir la cuenta, pero
  -- NO se quitan de products.imeis todavía; eso ocurre al completar la venta
  -- real (checkout_sale_transactional), que es cuando el equipo sale de verdad.
  insert into public.sale_items (
    sale_id, branch_id, product_id, description, quantity, unit_price,
    discount_amount, tax_rate, line_subtotal, line_tax, line_total, imeis
  )
  select v_sale_id, v_branch_id, product_id, description, quantity,
         unit_price, discount_amount, tax_rate, line_subtotal, line_tax,
         line_total, coalesce(imeis, '{}'::text[])
  from tmp_hold_items
  order by product_id;

  return jsonb_build_object(
    'sale_id', v_sale_id,
    'sale_number', v_sale_number,
    'branch_id', v_branch_id,
    'receipt_type', v_receipt_type,
    'status', 'pending',
    'subtotal', v_subtotal,
    'discount_amount', v_discount_amount,
    'tax_amount', v_tax_amount,
    'total_amount', v_total_amount,
    'items_count', v_item_count
  );
end;
$$;

grant execute on function public.hold_sale_transactional(
  jsonb, text, uuid, text, uuid
) to authenticated;

notify pgrst, 'reload schema';
