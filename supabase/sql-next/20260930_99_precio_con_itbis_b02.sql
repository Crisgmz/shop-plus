-- ============================================================================
-- 20260930_99_precio_con_itbis_b02.sql
--
-- Ventas B02 (Consumidor Final) cobran EXACTAMENTE el precio que se muestra.
--
-- En B02 el POS muestra y deja escribir los precios con el ITBIS adentro.
-- Antes ese precio se convertía a base redondeada al centavo (600 → 508.47) y
-- al sumarle el ITBIS a la línea salía otro total: 3 × 600 = 1,799.98 y
-- 2 × 320 = 640.01. Ningún precio base de 2 decimales lo evita.
--
-- Ahora cada línea puede traer `inclusive_price`: el precio CON ITBIS de UNA
-- presentación (la unidad, o la caja si la línea va por caja). Con él, el
-- bruto = precio × cantidad y el ITBIS se EXTRAE, igual que un producto con
-- "precio incluye ITBIS": 3 × 600 = 1,800.00 (ITBIS 274.58). Se guarda en
-- `sale_items.inclusive_price` para reimprimir, editar y reabrir igual.
--
-- `unit_price` / `uom_price` siguen viajando como base. Una línea sin
-- `inclusive_price` (el otro app, ventas viejas, B01) se calcula como antes.
--
-- Reemplaza checkout_sale_transactional y hold_sale_transactional (de la 92)
-- y edit_sale_transactional (de la 97) con las MISMAS firmas; el único cambio
-- es `inclusive_price`. Correr DESPUÉS de la 97. Idempotente.
-- ============================================================================

begin;

alter table public.sale_items
  add column if not exists inclusive_price numeric(14,2);

comment on column public.sale_items.inclusive_price is
  'Precio CON ITBIS de una presentación con que se cobró la línea (venta B02, migración 99). La línea se calcula desde él y el ITBIS se extrae. NULL = precio base de siempre.';

-- ── hold_sale_transactional ────────────────────────────────────────────────

create or replace function public.hold_sale_transactional(
  p_items jsonb,
  p_receipt_type text default 'consumer_final',
  p_client_id uuid default null,
  p_notes text default null,
  p_replace_hold_sale_id uuid default null,
  p_honor_client_tax boolean default false
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
  v_discount_total numeric(14,2) := 0;
  v_client record;
  v_client_no_tax boolean := false;
  v_item record;
  v_product record;
  v_item_count integer := 0;
  v_note text;
  v_now timestamptz := timezone('utc', now());
  v_enforce_stock boolean := true;
  v_rate numeric(5,2);
  v_gross numeric(14,2);
  v_discount numeric(14,2);
  v_net numeric(14,2);
  v_line_subtotal numeric(14,2);
  v_line_tax numeric(14,2);
  v_line_total numeric(14,2);
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
    select c.id, c.full_name, c.is_active, c.tax_exempt, c.charge_itbis
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
    -- CAMBIO (migración 91): si el app lo pide (`p_honor_client_tax`), un
    -- cliente con "Cobrar ITBIS" apagado o marcado exento no factura ITBIS.
    v_client_no_tax := coalesce(p_honor_client_tax, false)
      and (coalesce(v_client.tax_exempt, false)
           or not coalesce(v_client.charge_itbis, true));
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
    imeis text[],
    -- Presentación vendida (migración 92): "1 Caja" en vez de "20 paquetes".
    uom text,
    uom_factor numeric(14,3),
    uom_price numeric(14,2),
    unit_name text,
    inclusive_price numeric(14,2)
  ) on commit drop;
  truncate tmp_hold_items;

  for v_item in
    select
      (item->>'product_id')::uuid as product_id,
      coalesce(nullif(trim(item->>'description'), ''), '')::text as description,
      coalesce((item->>'quantity')::numeric, 0)::numeric(14,3) as quantity,
      coalesce((item->>'unit_price')::numeric, 0)::numeric(14,2) as unit_price,
      -- Descuento de la línea en MONTO absoluto (no porcentaje).
      coalesce((item->>'discount_amount')::numeric, 0)::numeric(14,2)
        as discount_amount,
      -- Presentación (migración 92). Si no vienen, la línea es por unidad
      -- base y todo se calcula como antes: el otro app no las manda.
      lower(nullif(btrim(item->>'uom'), ''))          as uom,
      nullif(item->>'uom_factor', '')::numeric(14,3)  as uom_factor,
      nullif(item->>'uom_price', '')::numeric(14,2)   as uom_price,
      -- Migración 99: precio CON ITBIS de la presentación (venta B02).
      nullif(item->>'inclusive_price', '')::numeric(14,2) as inclusive_price,
      nullif(btrim(item->>'unit_name'), '')           as unit_name,
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
           p.allow_negative_stock, p.is_service, p.is_tax_exempt,
           p.price_includes_tax, p.track_inventory
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

    -- Un producto sin control de inventario (track_inventory = false) nunca
    -- bloquea la venta: tras la migración 68 su stock ya no se mueve en ninguna
    -- dirección, así que exigirle existencias lo dejaría infacturable.
    if v_enforce_stock
       and (not v_product.is_service)
       and coalesce(v_product.track_inventory, true)
       and (not coalesce(v_product.allow_negative_stock, false))
       and (v_product.stock is null or v_product.stock < v_item.quantity) then
      raise exception 'Stock insuficiente para "%": disponible % requerido %',
        v_product.name, coalesce(v_product.stock, 0), v_item.quantity
        using errcode = '22023';
    end if;

    -- CAMBIO (migración 83): una venta SIN COMPROBANTE es una nota de venta
    -- no fiscal y NO factura ITBIS. Esta regla existía en el árbol de
    -- shop-plus (migración 64) y nunca llegó a esta función, así que el POS
    -- de esa tienda mostraba ITBIS 0 en pantalla y el servidor lo cobraba
    -- completo: el cliente pagaba un monto y la venta quedaba con otro.
    v_rate := case
      when v_receipt_type::text = 'none' then 0
      when v_client_no_tax               then 0
      when v_product.is_tax_exempt       then 0
      else coalesce(v_product.tax_rate, 0)
    end;
    -- CAMBIO (migración 92): si la línea trae el precio de la PRESENTACIÓN
    -- (1 caja a 2,639.83), el bruto sale de ahí. Derivarlo del precio por
    -- unidad base obliga a redondear al centavo por unidad y la caja nunca
    -- daría su precio exacto. Sin esos campos, se calcula igual que siempre.
    -- CAMBIO (migración 99): venta B02 con precio CON ITBIS. El bruto sale
    -- del precio que vio y escribió el cajero (por unidad o por caja) y el
    -- impuesto se extrae más abajo: 3 × 600.00 = 1,800.00 exactos. Antes ese
    -- precio se volvía base redondeada (508.47) y al sumarle el ITBIS daba
    -- 1,799.98. Sin `inclusive_price` (otro app, o tasa 0) todo es como antes.
    if v_item.inclusive_price is not null and v_rate > 0 then
      v_gross := round(
        (v_item.inclusive_price * (case
           when v_item.uom_price is not null and coalesce(v_item.uom_factor, 0) > 0
             then v_item.quantity / v_item.uom_factor
           else v_item.quantity
         end))::numeric, 2
      );
    elsif v_item.uom_price is not null and coalesce(v_item.uom_factor, 0) > 0 then
      v_gross := round(
        (v_item.uom_price * (v_item.quantity / v_item.uom_factor))::numeric, 2
      );
    else
      v_gross := round((v_item.unit_price * v_item.quantity)::numeric, 2);
    end if;
    -- El descuento nunca puede dejar la línea en negativo ni sumar al total.
    v_discount := least(
      greatest(coalesce(v_item.discount_amount, 0), 0::numeric),
      v_gross
    );
    v_net := round((v_gross - v_discount)::numeric, 2);
    if (coalesce(v_product.price_includes_tax, false)
        or v_item.inclusive_price is not null) and v_rate > 0 then
      -- Precio con ITBIS incluido: el neto es el total exacto y el impuesto se
      -- extrae.
      v_line_total := v_net;
      v_line_tax := round((v_net * v_rate / (100 + v_rate))::numeric, 2);
      v_line_subtotal := v_line_total - v_line_tax;
    else
      -- Exclusivo: el ITBIS se agrega encima del neto.
      v_line_subtotal := v_net;
      v_line_tax := round((v_net * v_rate / 100)::numeric, 2);
      v_line_total := round((v_line_subtotal + v_line_tax)::numeric, 2);
    end if;

    insert into tmp_hold_items (
      product_id, description, quantity, unit_price, discount_amount,
      tax_rate, line_subtotal, line_tax, line_total, imeis,
      uom, uom_factor, uom_price, unit_name, inclusive_price
    ) values (
      v_item.product_id,
      coalesce(nullif(v_item.description, ''), v_product.name),
      v_item.quantity,
      v_item.unit_price,
      v_discount,
      v_rate,
      v_line_subtotal,
      v_line_tax,
      v_line_total,
      coalesce(v_item.imeis, '{}'::text[]),
      coalesce(v_item.uom, 'unit'),
      coalesce(v_item.uom_factor, 1),
      v_item.uom_price,
      v_item.unit_name,
      case when v_rate > 0 then v_item.inclusive_price end
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
    coalesce(sum(line_total), 0),
    coalesce(sum(discount_amount), 0)
  into v_subtotal, v_tax_amount, v_total_amount, v_discount_total
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
  -- sales.discount_amount = suma de los descuentos de línea. Es informativo:
  -- el subtotal ya viene neto, así que NO se vuelve a restar del total.
  insert into public.sales (
    branch_id, sale_number, client_id, cashier_id, receipt_type, status,
    sale_date, subtotal, discount_amount, tax_amount, total_amount,
    paid_amount, balance_due, change_amount, notes, due_date, cash_session_id
  ) values (
    v_branch_id, v_sale_number, p_client_id, v_user_id, v_receipt_type,
    'pending'::public.sale_status, v_now, v_subtotal, v_discount_total,
    v_tax_amount, v_total_amount, 0, 0, 0, v_note, null, null
  )
  -- CAMBIO (migración 83): `sale_number` vuelve en el RETURNING. Si el
  -- trigger `trg_sales_short_number` (árbol shop-plus) está instalado,
  -- reemplaza el número provisional por el correlativo corto; leyendo la
  -- variable local el app mostraba e imprimía un número que no era el
  -- guardado. Sin ese trigger el valor vuelve igual, así que es inocuo.
  returning id, sale_number into v_sale_id, v_sale_number;

  -- Inserta las líneas: el trigger trg_sale_items_stock RESERVA el stock.
  -- Nota: los IMEIs se guardan en la línea para poder reabrir la cuenta, pero
  -- NO se quitan de products.imeis todavía; eso ocurre al completar la venta
  -- real (checkout_sale_transactional), que es cuando el equipo sale de verdad.
  insert into public.sale_items (
    sale_id, branch_id, product_id, description, quantity, unit_price,
    discount_amount, tax_rate, line_subtotal, line_tax, line_total, imeis,
    uom, uom_factor, uom_price, unit_name, inclusive_price
  )
  select v_sale_id, v_branch_id, product_id, description, quantity,
         unit_price, discount_amount, tax_rate, line_subtotal, line_tax,
         line_total, coalesce(imeis, '{}'::text[]),
         coalesce(uom, 'unit'), coalesce(uom_factor, 1), uom_price, unit_name,
         inclusive_price
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
  jsonb, text, uuid, text, uuid, boolean
) to authenticated;

-- ── checkout_sale_transactional ────────────────────────────────────────────

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
  p_hold_sale_id uuid default null,
  p_honor_client_tax boolean default false
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
  v_discount_total numeric(14,2) := 0;
  v_paid_amount numeric(14,2) := 0;
  v_balance_due numeric(14,2) := 0;
  v_change numeric(14,2) := 0;
  v_open_cash_session_id uuid;
  v_client record;
  v_client_no_tax boolean := false;
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
  v_rate numeric(5,2);
  v_gross numeric(14,2);
  v_discount numeric(14,2);
  v_net numeric(14,2);
  v_line_subtotal numeric(14,2);
  v_line_tax numeric(14,2);
  v_line_total numeric(14,2);
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
    select c.id, c.full_name, c.balance_due, c.credit_limit, c.is_active,
           c.tax_exempt, c.charge_itbis
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
    -- CAMBIO (migración 91): si el app lo pide (`p_honor_client_tax`), un
    -- cliente con "Cobrar ITBIS" apagado o marcado exento no factura ITBIS.
    v_client_no_tax := coalesce(p_honor_client_tax, false)
      and (coalesce(v_client.tax_exempt, false)
           or not coalesce(v_client.charge_itbis, true));
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
    imeis text[],
    -- Presentación vendida (migración 92): "1 Caja" en vez de "20 paquetes".
    uom text,
    uom_factor numeric(14,3),
    uom_price numeric(14,2),
    unit_name text,
    inclusive_price numeric(14,2)
  ) on commit drop;
  truncate tmp_checkout_items;

  for v_item in
    select
      (item->>'product_id')::uuid as product_id,
      coalesce(nullif(trim(item->>'description'), ''), '')::text as description,
      coalesce((item->>'quantity')::numeric, 0)::numeric(14,3) as quantity,
      coalesce((item->>'unit_price')::numeric, 0)::numeric(14,2) as unit_price,
      -- Descuento de la línea en MONTO absoluto (no porcentaje).
      coalesce((item->>'discount_amount')::numeric, 0)::numeric(14,2)
        as discount_amount,
      -- Presentación (migración 92). Si no vienen, la línea es por unidad
      -- base y todo se calcula como antes: el otro app no las manda.
      lower(nullif(btrim(item->>'uom'), ''))          as uom,
      nullif(item->>'uom_factor', '')::numeric(14,3)  as uom_factor,
      nullif(item->>'uom_price', '')::numeric(14,2)   as uom_price,
      -- Migración 99: precio CON ITBIS de la presentación (venta B02).
      nullif(item->>'inclusive_price', '')::numeric(14,2) as inclusive_price,
      nullif(btrim(item->>'unit_name'), '')           as unit_name,
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
           p.allow_negative_stock, p.is_service, p.is_tax_exempt,
           p.price_includes_tax, p.track_inventory
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

    -- Un producto sin control de inventario (track_inventory = false) nunca
    -- bloquea la venta: tras la migración 68 su stock ya no se mueve en ninguna
    -- dirección, así que exigirle existencias lo dejaría infacturable.
    if v_enforce_stock
       and (not v_product.is_service)
       and coalesce(v_product.track_inventory, true)
       and (not coalesce(v_product.allow_negative_stock, false))
       and (v_product.stock is null or v_product.stock < v_item.quantity) then
      raise exception 'Stock insuficiente para "%": disponible % requerido %',
        v_product.name, coalesce(v_product.stock, 0), v_item.quantity
        using errcode = '22023';
    end if;

    -- CAMBIO (migración 83): una venta SIN COMPROBANTE es una nota de venta
    -- no fiscal y NO factura ITBIS. Esta regla existía en el árbol de
    -- shop-plus (migración 64) y nunca llegó a esta función, así que el POS
    -- de esa tienda mostraba ITBIS 0 en pantalla y el servidor lo cobraba
    -- completo: el cliente pagaba un monto y la venta quedaba con otro.
    v_rate := case
      when v_receipt_type::text = 'none' then 0
      when v_client_no_tax               then 0
      when v_product.is_tax_exempt       then 0
      else coalesce(v_product.tax_rate, 0)
    end;
    -- CAMBIO (migración 92): si la línea trae el precio de la PRESENTACIÓN
    -- (1 caja a 2,639.83), el bruto sale de ahí. Derivarlo del precio por
    -- unidad base obliga a redondear al centavo por unidad y la caja nunca
    -- daría su precio exacto. Sin esos campos, se calcula igual que siempre.
    -- CAMBIO (migración 99): venta B02 con precio CON ITBIS. El bruto sale
    -- del precio que vio y escribió el cajero (por unidad o por caja) y el
    -- impuesto se extrae más abajo: 3 × 600.00 = 1,800.00 exactos. Antes ese
    -- precio se volvía base redondeada (508.47) y al sumarle el ITBIS daba
    -- 1,799.98. Sin `inclusive_price` (otro app, o tasa 0) todo es como antes.
    if v_item.inclusive_price is not null and v_rate > 0 then
      v_gross := round(
        (v_item.inclusive_price * (case
           when v_item.uom_price is not null and coalesce(v_item.uom_factor, 0) > 0
             then v_item.quantity / v_item.uom_factor
           else v_item.quantity
         end))::numeric, 2
      );
    elsif v_item.uom_price is not null and coalesce(v_item.uom_factor, 0) > 0 then
      v_gross := round(
        (v_item.uom_price * (v_item.quantity / v_item.uom_factor))::numeric, 2
      );
    else
      v_gross := round((v_item.unit_price * v_item.quantity)::numeric, 2);
    end if;
    -- El descuento nunca puede dejar la línea en negativo ni sumar al total.
    v_discount := least(
      greatest(coalesce(v_item.discount_amount, 0), 0::numeric),
      v_gross
    );
    v_net := round((v_gross - v_discount)::numeric, 2);
    if (coalesce(v_product.price_includes_tax, false)
        or v_item.inclusive_price is not null) and v_rate > 0 then
      -- Precio con ITBIS incluido: el neto es el total exacto y el impuesto se
      -- extrae.
      v_line_total := v_net;
      v_line_tax := round((v_net * v_rate / (100 + v_rate))::numeric, 2);
      v_line_subtotal := v_line_total - v_line_tax;
    else
      -- Exclusivo: el ITBIS se agrega encima del neto.
      v_line_subtotal := v_net;
      v_line_tax := round((v_net * v_rate / 100)::numeric, 2);
      v_line_total := round((v_line_subtotal + v_line_tax)::numeric, 2);
    end if;

    insert into tmp_checkout_items (
      product_id, description, quantity, unit_price, discount_amount,
      tax_rate, line_subtotal, line_tax, line_total, imeis,
      uom, uom_factor, uom_price, unit_name, inclusive_price
    ) values (
      v_item.product_id,
      coalesce(nullif(v_item.description, ''), v_product.name),
      v_item.quantity,
      v_item.unit_price,
      v_discount,
      v_rate,
      v_line_subtotal,
      v_line_tax,
      v_line_total,
      coalesce(v_item.imeis, '{}'::text[]),
      coalesce(v_item.uom, 'unit'),
      coalesce(v_item.uom_factor, 1),
      v_item.uom_price,
      v_item.unit_name,
      case when v_rate > 0 then v_item.inclusive_price end
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
    coalesce(sum(line_total), 0),
    coalesce(sum(discount_amount), 0)
  into v_subtotal, v_tax_amount, v_total_amount, v_discount_total
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

  -- sales.discount_amount = suma de los descuentos de línea (informativo, para
  -- recibo y reportes). El subtotal ya viene neto, así que subtotal +
  -- tax_amount = total_amount y la cabecera NO se vuelve a restar.
  insert into public.sales (
    branch_id, sale_number, client_id, cashier_id, receipt_type, status,
    sale_date, subtotal, discount_amount, tax_amount, total_amount,
    paid_amount, balance_due, change_amount, notes, due_date, cash_session_id
  ) values (
    v_branch_id, v_sale_number, p_client_id, v_user_id, v_receipt_type,
    v_sale_status, v_now, v_subtotal, v_discount_total, v_tax_amount,
    v_total_amount, v_paid_amount, v_balance_due, v_change, v_note, v_due_date,
    v_open_cash_session_id
  )
  -- CAMBIO (migración 83): `sale_number` vuelve en el RETURNING. Si el
  -- trigger `trg_sales_short_number` (árbol shop-plus) está instalado,
  -- reemplaza el número provisional por el correlativo corto; leyendo la
  -- variable local el app mostraba e imprimía un número que no era el
  -- guardado. Sin ese trigger el valor vuelve igual, así que es inocuo.
  returning id, sale_number into v_sale_id, v_sale_number;

  insert into public.sale_items (
    sale_id, branch_id, product_id, description, quantity, unit_price,
    discount_amount, tax_rate, line_subtotal, line_tax, line_total, imeis,
    uom, uom_factor, uom_price, unit_name, inclusive_price
  )
  select v_sale_id, v_branch_id, product_id, description, quantity,
         unit_price, discount_amount, tax_rate, line_subtotal, line_tax,
         line_total, coalesce(imeis, '{}'::text[]),
         coalesce(uom, 'unit'), coalesce(uom_factor, 1), uom_price, unit_name,
         inclusive_price
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
  jsonb, text, boolean, text, uuid, text, integer, uuid, jsonb, uuid, boolean
) to authenticated;

-- ── edit_sale_transactional ────────────────────────────────────────────────

create or replace function public.edit_sale_transactional(
  p_sale_id uuid,
  p_items jsonb,
  p_client_id uuid default null,
  p_clear_client boolean default false,
  p_notes text default null,
  p_clear_notes boolean default false,
  p_honor_client_tax boolean default false
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_user_id uuid := auth.uid();
  v_branch_id uuid;
  v_sale record;
  v_old_total numeric(14,2);
  v_old_client_id uuid;
  v_item record;
  v_product record;
  v_line record;
  v_subtotal numeric(14,2) := 0;
  v_tax_amount numeric(14,2) := 0;
  v_total_amount numeric(14,2) := 0;
  v_discount_total numeric(14,2) := 0;
  v_paid_amount numeric(14,2);
  v_balance_due numeric(14,2);
  v_change numeric(14,2);
  v_tendered numeric(14,2);
  v_status public.sale_status;
  v_note text;
  v_target_client uuid;
  v_client_no_tax boolean := false;
  v_item_count integer := 0;
  v_old_imei_count integer := 0;
  v_new_imei_count integer := 0;
  v_enforce_stock boolean := true;
  v_prev_qty numeric(14,3);
  v_last_payment uuid;
  v_doc text;
  v_returns text;
begin
  if v_user_id is null then
    raise exception 'Sesión inválida.' using errcode = '28000';
  end if;

  if not public.is_admin()
     and public.current_user_role() <> 'supervisor'::public.app_role then
    raise exception 'Solo admin o supervisor pueden editar ventas.'
      using errcode = '42501';
  end if;

  if p_items is null or jsonb_typeof(p_items) <> 'array'
     or jsonb_array_length(p_items) = 0 then
    raise exception 'La venta no puede quedar sin items.'
      using errcode = '22023';
  end if;

  select id, branch_id, status, total_amount, paid_amount, change_amount,
         client_id, notes, receipt_type, due_date, ncf
  into v_sale
  from public.sales
  where id = p_sale_id
  for update;

  if not found then
    raise exception 'Venta no encontrada.' using errcode = '23503';
  end if;

  if v_sale.status = 'voided'::public.sale_status then
    raise exception 'No se puede editar una venta anulada.'
      using errcode = '22023';
  end if;

  -- CAMBIO 97: una cuenta guardada (pending) se edita reabriéndola en el POS.
  -- Editarla aquí le ponía saldo y la hacía aparecer en Cuentas por cobrar.
  if v_sale.status not in (
    'completed'::public.sale_status, 'credit'::public.sale_status
  ) then
    raise exception 'Solo se pueden editar ventas cobradas o a crédito.'
      using errcode = '22023';
  end if;

  v_branch_id := v_sale.branch_id;
  v_old_total := coalesce(v_sale.total_amount, 0);
  v_old_client_id := v_sale.client_id;

  if not public.has_branch_access(v_branch_id) then
    raise exception 'No tienes acceso a la sucursal de esta venta.'
      using errcode = '42501';
  end if;

  -- CAMBIO 97: con devoluciones no se edita. El editor no sabe de lo devuelto:
  -- volvía a cobrar y a sacar del inventario (IMEIs incluidos) lo que ya
  -- había regresado.
  select string_agg(coalesce(r.return_number, 'sin número'), ', ')
    into v_returns
    from public.returns r
   where r.original_sale_id = p_sale_id;
  if v_returns is not null then
    raise exception 'Esta venta tiene devoluciones (%): no se puede editar. Para corregirla, registra otra devolución.', v_returns
      using errcode = '22023';
  end if;

  if p_clear_client then
    v_target_client := null;
  elsif p_client_id is not null then
    v_target_client := p_client_id;
  else
    v_target_client := v_old_client_id;
  end if;

  if v_target_client is not null
     and v_target_client is distinct from v_old_client_id then
    if not exists (
      select 1 from public.clients
      where id = v_target_client and branch_id = v_branch_id and is_active
    ) then
      raise exception 'Cliente nuevo no válido para esta sucursal.'
        using errcode = '23503';
    end if;
  end if;

  -- CAMBIO 97: un comprobante fiscal (todo menos Consumidor Final y sin
  -- comprobante) debe quedar con un cliente con RNC/cédula. El trigger
  -- tg_sales_assert_fiscal_client solo corre al crear la venta.
  if v_sale.receipt_type::text not in ('consumer_final', 'none') then
    if v_target_client is null then
      raise exception 'Esta factura tiene comprobante fiscal: debe quedar con un cliente con RNC o cédula.'
        using errcode = '22023';
    end if;
    select nullif(trim(coalesce(c.document_number, '')), '')
      into v_doc
      from public.clients c
     where c.id = v_target_client
       and c.branch_id = v_branch_id;
    if v_doc is null then
      raise exception 'El cliente debe tener RNC o cédula registrado: la factura tiene comprobante fiscal.'
        using errcode = '22023';
    end if;
  end if;

  -- El cliente con que QUEDA la venta decide el ITBIS (migración 91).
  if coalesce(p_honor_client_tax, false) and v_target_client is not null then
    select coalesce(c.tax_exempt, false) or not coalesce(c.charge_itbis, true)
      into v_client_no_tax
      from public.clients c
     where c.id = v_target_client;
    v_client_no_tax := coalesce(v_client_no_tax, false);
  end if;

  if p_clear_notes then
    v_note := null;
  elsif p_notes is not null then
    v_note := nullif(trim(p_notes), '');
  else
    v_note := v_sale.notes;
  end if;

  -- "No permitir venta sin stock" (migración 87 de flutter_shop+). Si el
  -- negocio permite vender sin stock, editar tampoco lo exige.
  begin
    select coalesce(s.inv_disallow_no_stock, true)
      into v_enforce_stock
      from public.app_settings s
      join public.branches b on b.company_id = s.company_id
     where b.id = v_branch_id
     limit 1;
    v_enforce_stock := coalesce(v_enforce_stock, true);
  exception
    when undefined_column or undefined_table or undefined_function then
      v_enforce_stock := true;
  end;

  -- Lo que la venta YA tenía de cada producto: distingue "corregir la venta"
  -- de "vender más" al validar stock y al aceptar productos desactivados.
  create temp table if not exists tmp_edit_prev_qty (
    product_id uuid primary key,
    quantity numeric(14,3)
  ) on commit drop;
  truncate tmp_edit_prev_qty;
  insert into tmp_edit_prev_qty (product_id, quantity)
  select si.product_id, sum(si.quantity)
    from public.sale_items si
   where si.sale_id = p_sale_id
     and si.product_id is not null
   group by si.product_id;

  -- 0) Devolver al producto los IMEIs de las líneas viejas (antes del delete:
  --    la línea es la única copia).
  for v_line in
    select si.product_id, si.branch_id, si.imeis
      from public.sale_items si
     where si.sale_id = p_sale_id
       and coalesce(array_length(si.imeis, 1), 0) > 0
  loop
    v_old_imei_count := v_old_imei_count + coalesce(array_length(v_line.imeis, 1), 0);
    perform public.restore_product_imeis(
      v_line.product_id, v_line.branch_id, v_line.imeis
    );
  end loop;

  -- 1) Borrar las líneas viejas. El trigger trg_sale_items_stock devuelve su
  --    stock, UNA vez, fila por fila.
  --    CAMBIO 97: antes, además, se devolvía a mano (doble).
  delete from public.sale_items where sale_id = p_sale_id;

  -- 2) Líneas nuevas normalizadas.
  create temp table if not exists tmp_edit_items_imeis (
    product_id uuid,
    description text,
    quantity numeric(14,3),
    unit_price numeric(14,2),
    discount_amount numeric(14,2),
    tax_rate numeric(5,2),
    line_subtotal numeric(14,2),
    line_tax numeric(14,2),
    line_total numeric(14,2),
    imeis text[],
    uom text,
    uom_factor numeric(14,3),
    uom_price numeric(14,2),
    unit_name text,
    inclusive_price numeric(14,2)
  ) on commit drop;
  truncate tmp_edit_items_imeis;

  for v_item in
    select
      (item->>'product_id')::uuid as product_id,
      coalesce(nullif(trim(item->>'description'), ''), '')::text as description,
      coalesce((item->>'quantity')::numeric, 0)::numeric(14,3) as quantity,
      coalesce((item->>'unit_price')::numeric, 0)::numeric(14,2) as unit_price,
      nullif(item->>'discount_amount', '')::numeric as discount_amount_in,
      nullif(item->>'discount_pct', '')::numeric as discount_pct_in,
      lower(nullif(btrim(item->>'uom'), ''))          as uom,
      nullif(item->>'uom_factor', '')::numeric(14,3)  as uom_factor,
      nullif(item->>'uom_price', '')::numeric(14,2)   as uom_price,
      -- Migración 99: precio CON ITBIS de la presentación (venta B02).
      nullif(item->>'inclusive_price', '')::numeric(14,2) as inclusive_price,
      nullif(btrim(item->>'unit_name'), '')           as unit_name,
      coalesce(
        (select array_agg(x) from jsonb_array_elements_text(
           case when jsonb_typeof(item->'imeis') = 'array'
                then item->'imeis' else '[]'::jsonb end) as x),
        '{}'::text[]) as imeis
    from jsonb_array_elements(p_items) as item
  loop
    if v_item.product_id is null then
      raise exception 'Producto sin id en la edición.' using errcode = '22023';
    end if;
    if v_item.quantity is null or v_item.quantity <= 0 then
      raise exception 'Cantidad inválida en un producto de la venta.'
        using errcode = '22023';
    end if;
    if v_item.discount_amount_in is null
       and v_item.discount_pct_in is not null
       and (v_item.discount_pct_in < 0 or v_item.discount_pct_in > 100) then
      raise exception 'Descuento fuera de rango (0-100).' using errcode = '22023';
    end if;

    select p.id, p.name, p.tax_rate, p.is_active, p.is_tax_exempt,
           p.price_includes_tax
    into v_product
    from public.products p
    where p.id = v_item.product_id and p.branch_id = v_branch_id;

    if not found then
      raise exception 'Uno de los productos ya no existe en esta sucursal.'
        using errcode = '23503';
    end if;

    -- CAMBIO 97: un producto desactivado DESPUÉS de venderlo se puede mantener
    -- en la venta; lo que no se puede es agregarlo.
    v_prev_qty := coalesce(
      (select q.quantity from tmp_edit_prev_qty q
        where q.product_id = v_item.product_id), 0);
    if not v_product.is_active and v_prev_qty = 0 then
      raise exception 'Producto "%": inactivo.', v_product.name
        using errcode = '22023';
    end if;

    v_new_imei_count := v_new_imei_count + coalesce(array_length(v_item.imeis, 1), 0);

    declare
      v_rate numeric(5,2) := case
        when v_sale.receipt_type::text = 'none' then 0
        when v_client_no_tax                    then 0
        when v_product.is_tax_exempt            then 0
        else coalesce(v_product.tax_rate, 0)
      end;
      -- Migración 99: con precio CON ITBIS (venta B02) el bruto sale de él
      -- y el impuesto se extrae (ver checkout).
      v_gross numeric(14,2) := case
        when v_item.inclusive_price is not null and v_rate > 0
          then round(
            (v_item.inclusive_price * (case
               when v_item.uom_price is not null
                    and coalesce(v_item.uom_factor, 0) > 0
                 then v_item.quantity / v_item.uom_factor
               else v_item.quantity
             end))::numeric, 2)
        when v_item.uom_price is not null
             and coalesce(v_item.uom_factor, 0) > 0
          then round(
            (v_item.uom_price * (v_item.quantity / v_item.uom_factor))::numeric,
            2)
        else round((v_item.unit_price * v_item.quantity)::numeric, 2)
      end;
      v_disc numeric(14,2);
      v_net numeric(14,2);
      v_sub numeric(14,2);
      v_tax numeric(14,2);
      v_line_total numeric(14,2);
    begin
      v_disc := coalesce(
        v_item.discount_amount_in,
        round((v_gross * coalesce(v_item.discount_pct_in, 0) / 100)::numeric, 2)
      );
      v_disc := least(greatest(v_disc, 0::numeric), v_gross);
      v_net := round((v_gross - v_disc)::numeric, 2);

      if (coalesce(v_product.price_includes_tax, false)
          or v_item.inclusive_price is not null) and v_rate > 0 then
        v_line_total := v_net;
        v_tax := round((v_net * v_rate / (100 + v_rate))::numeric, 2);
        v_sub := v_line_total - v_tax;
      else
        v_sub := v_net;
        v_tax := round((v_net * v_rate / 100)::numeric, 2);
        v_line_total := round((v_sub + v_tax)::numeric, 2);
      end if;

      insert into tmp_edit_items_imeis (
        product_id, description, quantity, unit_price, discount_amount,
        tax_rate, line_subtotal, line_tax, line_total, imeis,
        uom, uom_factor, uom_price, unit_name, inclusive_price
      ) values (
        v_item.product_id,
        coalesce(nullif(v_item.description, ''), v_product.name),
        v_item.quantity, v_item.unit_price, v_disc, v_rate, v_sub, v_tax,
        v_line_total, coalesce(v_item.imeis, '{}'::text[]),
        coalesce(v_item.uom, 'unit'), coalesce(v_item.uom_factor, 1),
        v_item.uom_price, v_item.unit_name,
        case when v_rate > 0 then v_item.inclusive_price end
      );
    end;

    v_item_count := v_item_count + 1;
  end loop;

  if v_item_count = 0 then
    raise exception 'No se procesó ningún item válido.' using errcode = '22023';
  end if;

  -- 3) CAMBIO 97: stock por PRODUCTO (caja + sueltas suman) y solo cuando la
  --    edición pide más de lo que la venta ya tenía. El stock ya incluye lo
  --    que devolvió el delete del paso 1.
  for v_line in
    select t.product_id, sum(t.quantity) as qty
      from tmp_edit_items_imeis t
     group by t.product_id
  loop
    select p.name, p.stock, p.is_service, p.allow_negative_stock,
           p.track_inventory
      into v_product
      from public.products p
     where p.id = v_line.product_id and p.branch_id = v_branch_id;

    v_prev_qty := coalesce(
      (select q.quantity from tmp_edit_prev_qty q
        where q.product_id = v_line.product_id), 0);

    if v_enforce_stock
       and not coalesce(v_product.is_service, false)
       and not coalesce(v_product.allow_negative_stock, false)
       and coalesce(v_product.track_inventory, true)
       and v_line.qty > v_prev_qty
       and (v_product.stock is null or v_product.stock < v_line.qty) then
      raise exception 'Stock insuficiente para "%": disponible % requerido %',
        v_product.name, coalesce(v_product.stock, 0), v_line.qty
        using errcode = '22023';
    end if;
  end loop;

  -- 4) Insertar las líneas nuevas. El trigger descuenta su stock, UNA vez.
  --    CAMBIO 97: antes, además, se descontaba a mano (doble).
  insert into public.sale_items (
    sale_id, branch_id, product_id, description, quantity, unit_price,
    discount_amount, tax_rate, line_subtotal, line_tax, line_total, imeis,
    uom, uom_factor, uom_price, unit_name, inclusive_price
  )
  select
    p_sale_id, v_branch_id, product_id, description, quantity, unit_price,
    discount_amount, tax_rate, line_subtotal, line_tax, line_total,
    coalesce(imeis, '{}'::text[]),
    coalesce(uom, 'unit'), coalesce(uom_factor, 1), uom_price, unit_name,
    inclusive_price
  from tmp_edit_items_imeis
  order by product_id;

  -- 5) Los IMEIs que quedaron en la venta salen otra vez del inventario.
  for v_line in
    select product_id, imeis as sold
      from tmp_edit_items_imeis
     where coalesce(array_length(imeis, 1), 0) > 0
  loop
    update public.products p
       set imeis = coalesce(
             (select array_agg(e order by e)
                from unnest(p.imeis) as e
               where not (e = any(v_line.sold))),
             '{}'::text[])
     where p.id = v_line.product_id and p.branch_id = v_branch_id;
  end loop;

  -- 6) Totales.
  select
    coalesce(sum(line_subtotal), 0),
    coalesce(sum(line_tax), 0),
    coalesce(sum(line_total), 0),
    coalesce(sum(discount_amount), 0)
  into v_subtotal, v_tax_amount, v_total_amount, v_discount_total
  from tmp_edit_items_imeis;

  -- 7) CAMBIO 97: pagos y saldo.
  select coalesce(sum(p.amount), 0)
    into v_tendered
    from public.payments p
   where p.sale_id = p_sale_id;

  if v_sale.status = 'credit'::public.sale_status
     or v_sale.due_date is not null then
    -- Cuenta por cobrar (a crédito, aunque ya esté saldada con abonos): lo
    -- abonado se respeta y el saldo sigue al total nuevo. Antes una venta a
    -- crédito ya pagada se marcaba pagada otra vez al subirle el total, y
    -- una que quedaba cubierta seguía "a crédito" para siempre.
    v_paid_amount := greatest(coalesce(v_sale.paid_amount, 0), 0);
    v_balance_due := round((v_total_amount - v_paid_amount)::numeric, 2);
    if v_balance_due > 0 then
      v_status := 'credit'::public.sale_status;
      v_change := coalesce(v_sale.change_amount, 0);
    else
      -- Lo abonado cubre el total nuevo: queda pagada y lo pagado de más se
      -- devuelve (cambio).
      v_change := round(
        (coalesce(v_sale.change_amount, 0) + (v_paid_amount - v_total_amount))::numeric,
        2);
      v_paid_amount := v_total_amount;
      v_balance_due := 0;
      v_status := 'completed'::public.sale_status;
    end if;
  else
    -- Venta cobrada: queda saldada. Lo entregado (pagos) no se toca y la
    -- diferencia va al cambio, así pagos − cambio = total y la caja espera lo
    -- correcto. Antes el único pago se reescribía al total sin tocar el
    -- cambio, y un pago dividido quedaba con el monto viejo.
    v_status := 'completed'::public.sale_status;
    v_paid_amount := v_total_amount;
    v_balance_due := 0;
    if v_tendered >= v_total_amount then
      v_change := round((v_tendered - v_total_amount)::numeric, 2);
    else
      -- El total nuevo supera lo entregado: el cliente paga la diferencia con
      -- el último método que usó.
      select p.id into v_last_payment
        from public.payments p
       where p.sale_id = p_sale_id
       order by p.paid_at desc nulls last, p.created_at desc
       limit 1;
      if v_last_payment is not null then
        update public.payments
           set amount = round((amount + (v_total_amount - v_tendered))::numeric, 2)
         where id = v_last_payment;
      end if;
      v_change := 0;
    end if;
  end if;

  -- 8) La venta.
  update public.sales
  set
    subtotal = v_subtotal,
    discount_amount = v_discount_total,
    tax_amount = v_tax_amount,
    total_amount = v_total_amount,
    paid_amount = v_paid_amount,
    balance_due = v_balance_due,
    change_amount = v_change,
    status = v_status,
    client_id = v_target_client,
    notes = v_note,
    updated_at = timezone('utc', now())
  where id = p_sale_id;

  -- 9) CAMBIO 97: saldo de los clientes afectados, desde sus ventas. Antes se
  --    movía el TOTAL (no el saldo) al cambiar de cliente una venta abonada.
  perform public.recompute_client_balance(v_old_client_id, v_branch_id);
  if v_target_client is distinct from v_old_client_id then
    perform public.recompute_client_balance(v_target_client, v_branch_id);
  end if;

  -- 10) CAMBIO 97: el documento fiscal refleja montos y cliente nuevos.
  if v_sale.ncf is not null then
    update public.fiscal_documents fd
       set client_id = v_target_client,
           customer_name = c.customer_name,
           customer_document_type = c.customer_document_type,
           customer_document_number = c.customer_document_number,
           customer_address = c.customer_address,
           subtotal = v_subtotal,
           discount_amount = v_discount_total,
           tax_amount = v_tax_amount,
           total_amount = v_total_amount,
           updated_at = timezone('utc', now())
      from (
        select
          coalesce(nullif(cl.legal_name, ''), cl.full_name) as customer_name,
          cl.document_type::text as customer_document_type,
          cl.document_number as customer_document_number,
          cl.address as customer_address
        from (select 1) one
        left join public.clients cl
          on cl.id = v_target_client and cl.branch_id = v_branch_id
      ) c
     where fd.sale_id = p_sale_id
       and fd.branch_id = v_branch_id
       and fd.ncf = v_sale.ncf;
  end if;

  return jsonb_build_object(
    'sale_id', p_sale_id,
    'subtotal', v_subtotal,
    'discount_amount', v_discount_total,
    'tax_amount', v_tax_amount,
    'total_amount', v_total_amount,
    'paid_amount', v_paid_amount,
    'balance_due', v_balance_due,
    'change_amount', v_change,
    'status', v_status,
    'items_count', v_item_count,
    'client_id', v_target_client,
    'old_total', v_old_total,
    'imeis_restored', v_old_imei_count,
    'imeis_kept', v_new_imei_count
  );
end;
$$;

grant execute on function public.edit_sale_transactional(
  uuid, jsonb, uuid, boolean, text, boolean, boolean
) to authenticated;

commit;

notify pgrst, 'reload schema';
