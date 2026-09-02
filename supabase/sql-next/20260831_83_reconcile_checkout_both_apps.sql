-- ============================================================================
-- 20260831_83_reconcile_checkout_both_apps.sql
--
-- RECONCILIACIÓN — una sola función de cobro que sirve a los DOS proyectos.
--
-- Contexto: `shop-plus` y `flutter_shop+` son dos bifurcaciones del mismo
-- repositorio (ancestro común 42d74d6, 17 jun 2026) y apuntan a la MISMA base
-- (https://supabase.busiposweb.com). Como solo puede existir una
-- `checkout_sale_transactional`, la que corrió de último dejó al otro app
-- desalineado. Ninguna de las dos versiones servía a ambos:
--
--   capacidad                         shop-plus(64)   flutter_shop+(76)
--   receipt_type 'none' → ITBIS 0          SÍ                NO
--   price_includes_tax                     NO                SÍ
--   descuento por línea                    NO                SÍ (monto)
--   track_inventory                        NO                SÍ
--
-- Esta migración parte de la 76 de flutter_shop+ (la más avanzada) y le suma
-- lo único que le faltaba del otro árbol. DOS cambios, nada más:
--
--   1) `receipt_type = 'none'` fuerza tasa 0. Sin esto, el POS de shop-plus
--      mostraba ITBIS 0 en una "venta sin comprobante" y el servidor cobraba
--      el ITBIS completo — la venta quedaba registrada por más de lo que el
--      cliente pagó. (La feature quedó a medias en este linaje: la migración
--      59 agregó 'none' al enum y al trigger de NCF, pero nunca al cálculo.)
--
--   2) `returning id, sale_number` en vez de `returning id`. Si el trigger
--      `trg_sales_short_number` está instalado, el app tiene que recibir el
--      correlativo corto que dejó el trigger, no el provisional. Si no está
--      instalado, el valor vuelve idéntico: inocuo.
--
-- Todo lo demás es COPIA FIEL de la 76: descuento por monto absoluto acotado
-- a [0, bruto], price_includes_tax, track_inventory, is_service,
-- allow_negative_stock, pagos divididos, IMEIs.
--
-- ⚠️ Es la función de cobro de DOS negocios en producción. Probar una venta
--    de cada tipo (normal, sin comprobante, con descuento, pago dividido)
--    antes de dejarla operando.
--
-- ── ESTADO REAL CONFIRMADO POR EL DIAGNÓSTICO (31 ago 2026) ────────────────
-- En la base conviven TRES `checkout_sale_transactional`, porque
-- `create or replace` solo reemplaza cuando la firma coincide exacto:
--
--   (jsonb,text,boolean,text,uuid,text)                       6 par. — sin descuento
--   (jsonb,text,boolean,text,uuid,text,integer)               7 par. — sin descuento
--   (jsonb,text,boolean,text,uuid,text,integer,uuid,jsonb,uuid) 10 par. ← la viva
--
-- Los DOS apps mandan `p_cash_session_id` y `p_hold_sale_id`, que solo existen
-- en la de 10 parámetros, así que ambos resuelven a ESA. Las de 6 y 7 son
-- restos inalcanzables — pero peligrosos: si mañana un app deja de mandar uno
-- de esos parámetros, PostgREST resolvería a código de hace meses sin avisar.
-- Por eso se eliminan.
--
-- La de 10 parámetros hoy es la migración 67 (descartada) del árbol shop-plus:
-- lee `discount_pct` y NO tiene `price_includes_tax` ni `track_inventory`.
-- Consecuencia en producción, desde que se aplicó:
--   · flutter_shop+ manda `discount_amount` → sus descuentos se PIERDEN.
--   · un producto con `price_includes_tax` recibe el ITBIS ENCIMA de un precio
--     que ya lo incluía → se está COBRANDO DE MÁS.
-- Esta migración cierra las dos cosas.
--
-- Ejecutar en el SQL Editor de Supabase, DESPUÉS de:
--   flutter_shop+/supabase/sql-next/20260814_76_checkout_line_discount.sql
-- Idempotente (CREATE OR REPLACE sobre las mismas firmas).
-- ============================================================================

begin;

-- ── 0) Eliminar las sobrecargas muertas ─────────────────────────────────────
-- Ningún app las alcanza (les falta p_cash_session_id). Se van para que quede
-- UNA sola función de cobro y PostgREST no tenga nada que elegir.
drop function if exists public.checkout_sale_transactional(
  jsonb, text, boolean, text, uuid, text
);
drop function if exists public.checkout_sale_transactional(
  jsonb, text, boolean, text, uuid, text, integer
);

-- ----------------------------------------------------------------------------
-- 1) hold_sale_transactional — guardar la cuenta.
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
  v_sale_id uuid;
  v_sale_number text;
  v_replace_sale_number text;
  v_subtotal numeric(14,2) := 0;
  v_tax_amount numeric(14,2) := 0;
  v_total_amount numeric(14,2) := 0;
  v_discount_total numeric(14,2) := 0;
  v_client record;
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
      -- Descuento de la línea en MONTO absoluto (no porcentaje).
      coalesce((item->>'discount_amount')::numeric, 0)::numeric(14,2)
        as discount_amount,
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
      when v_product.is_tax_exempt       then 0
      else coalesce(v_product.tax_rate, 0)
    end;
    v_gross := round((v_item.unit_price * v_item.quantity)::numeric, 2);
    -- El descuento nunca puede dejar la línea en negativo ni sumar al total.
    v_discount := least(
      greatest(coalesce(v_item.discount_amount, 0), 0::numeric),
      v_gross
    );
    v_net := round((v_gross - v_discount)::numeric, 2);
    if coalesce(v_product.price_includes_tax, false) and v_rate > 0 then
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
      tax_rate, line_subtotal, line_tax, line_total, imeis
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
-- 2) checkout_sale_transactional — cobrar.
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
      -- Descuento de la línea en MONTO absoluto (no porcentaje).
      coalesce((item->>'discount_amount')::numeric, 0)::numeric(14,2)
        as discount_amount,
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
      when v_product.is_tax_exempt       then 0
      else coalesce(v_product.tax_rate, 0)
    end;
    v_gross := round((v_item.unit_price * v_item.quantity)::numeric, 2);
    -- El descuento nunca puede dejar la línea en negativo ni sumar al total.
    v_discount := least(
      greatest(coalesce(v_item.discount_amount, 0), 0::numeric),
      v_gross
    );
    v_net := round((v_gross - v_discount)::numeric, 2);
    if coalesce(v_product.price_includes_tax, false) and v_rate > 0 then
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
      tax_rate, line_subtotal, line_tax, line_total, imeis
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
-- 3) edit_sale_transactional — editar una venta ya registrada.
-- ----------------------------------------------------------------------------
-- La versión viva (migración 77 de flutter_shop+) ya trae descuento, ITBIS
-- incluido, track_inventory y restauración de IMEIs. Lo ÚNICO que le falta es
-- la regla de venta sin comprobante: abrir y guardar una nota de venta no
-- fiscal le agregaba ITBIS. Copia fiel de la 77 + esa regla.
create or replace function public.edit_sale_transactional(
  p_sale_id uuid,
  p_items jsonb,
  p_client_id uuid default null,
  p_clear_client boolean default false,
  p_notes text default null,
  p_clear_notes boolean default false
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
  v_subtotal numeric(14,2) := 0;
  v_tax_amount numeric(14,2) := 0;
  v_total_amount numeric(14,2) := 0;
  v_discount_total numeric(14,2) := 0;
  v_paid_amount numeric(14,2);
  v_balance_due numeric(14,2);
  v_payment_count integer;
  v_note text;
  v_target_client uuid;
  v_item_count integer := 0;
  v_line record;
  v_old_imei_count integer := 0;
  v_new_imei_count integer := 0;
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

  -- CAMBIO (migración 83): se agrega `receipt_type` para poder aplicar la
  -- regla de venta sin comprobante al recalcular las líneas.
  select id, branch_id, status, total_amount, paid_amount, client_id, notes,
         receipt_type
  into v_sale
  from public.sales
  where id = p_sale_id
  for update;

  if not found then
    raise exception 'Venta % no encontrada.', p_sale_id
      using errcode = '23503';
  end if;

  if v_sale.status = 'voided'::public.sale_status then
    raise exception 'No se puede editar una venta anulada.'
      using errcode = '22023';
  end if;

  v_branch_id := v_sale.branch_id;
  v_old_total := coalesce(v_sale.total_amount, 0);
  v_old_client_id := v_sale.client_id;

  if not public.has_branch_access(v_branch_id) then
    raise exception 'No tienes acceso a la sucursal de esta venta.'
      using errcode = '42501';
  end if;

  if p_clear_client then
    v_target_client := null;
  elsif p_client_id is not null then
    v_target_client := p_client_id;
  else
    v_target_client := v_old_client_id;
  end if;

  if v_target_client is not null and v_target_client is distinct from v_old_client_id then
    if not exists (
      select 1 from public.clients
      where id = v_target_client and branch_id = v_branch_id and is_active
    ) then
      raise exception 'Cliente nuevo no válido para esta sucursal.'
        using errcode = '23503';
    end if;
  end if;

  if p_clear_notes then
    v_note := null;
  elsif p_notes is not null then
    v_note := nullif(trim(p_notes), '');
  else
    v_note := v_sale.notes;
  end if;

  -- 0) Devolver al producto los IMEIs de las líneas VIEJAS. Va antes del
  --    delete del paso 2: la línea es la única copia que queda del IMEI.
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

  -- 1) Restaurar stock de los items viejos.
  update public.products p
  set stock = round(
    (coalesce(p.stock, 0) + si.quantity)::numeric(14, 3),
    3
  )
  from public.sale_items si
  where si.sale_id = p_sale_id
    and p.id = si.product_id
    and p.branch_id = v_branch_id
    and coalesce(p.is_service, false) = false
    and coalesce(p.track_inventory, true) = true;

  -- 2) Borrar los items viejos.
  delete from public.sale_items where sale_id = p_sale_id;

  -- 3) Tabla temporal con items normalizados.
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
    imeis text[]
  ) on commit drop;
  truncate tmp_edit_items_imeis;

  for v_item in
    select
      (item->>'product_id')::uuid as product_id,
      coalesce(nullif(trim(item->>'description'), ''), '')::text as description,
      coalesce((item->>'quantity')::numeric, 0)::numeric(14,3) as quantity,
      coalesce((item->>'unit_price')::numeric, 0)::numeric(14,2) as unit_price,
      -- Descuento de la línea en MONTO absoluto (criterio unificado con
      -- checkout/hold). `discount_pct` queda solo como fallback para clientes
      -- viejos: se usa únicamente si no vino el monto.
      nullif(item->>'discount_amount', '')::numeric as discount_amount_in,
      nullif(item->>'discount_pct', '')::numeric as discount_pct_in,
      coalesce(
        (select array_agg(x) from jsonb_array_elements_text(
           case when jsonb_typeof(item->'imeis') = 'array'
                then item->'imeis' else '[]'::jsonb end) as x),
        '{}'::text[]) as imeis
    from jsonb_array_elements(p_items) as item
  loop
    if v_item.product_id is null then
      raise exception 'Producto sin id en la edición.'
        using errcode = '22023';
    end if;
    if v_item.quantity is null or v_item.quantity <= 0 then
      raise exception 'Cantidad inválida en producto %', v_item.product_id
        using errcode = '22023';
    end if;
    if v_item.discount_amount_in is null
       and v_item.discount_pct_in is not null
       and (v_item.discount_pct_in < 0 or v_item.discount_pct_in > 100) then
      raise exception 'Descuento fuera de rango (0-100).'
        using errcode = '22023';
    end if;

    select p.id, p.name, p.price, p.tax_rate, p.stock,
           p.is_active, p.allow_negative_stock, p.is_service,
           p.is_tax_exempt, p.track_inventory, p.price_includes_tax
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

    if (not v_product.is_service)
       and (not coalesce(v_product.allow_negative_stock, false))
       and coalesce(v_product.track_inventory, true)
       and (v_product.stock is null or v_product.stock < v_item.quantity) then
      raise exception 'Stock insuficiente para "%": disponible % requerido %',
        v_product.name, coalesce(v_product.stock, 0), v_item.quantity
        using errcode = '22023';
    end if;

    v_new_imei_count := v_new_imei_count + coalesce(array_length(v_item.imeis, 1), 0);

    declare
      -- CAMBIO (migración 83): editar una venta SIN COMPROBANTE no puede
      -- agregarle ITBIS. Sin esta regla, abrir y guardar una nota de venta no
      -- fiscal le sumaba el impuesto y el total dejaba de coincidir con lo
      -- que el cliente pagó.
      v_rate numeric(5,2) := case
        when v_sale.receipt_type::text = 'none' then 0
        when v_product.is_tax_exempt            then 0
        else coalesce(v_product.tax_rate, 0)
      end;
      v_gross numeric(14,2) := round(
        (v_item.unit_price * v_item.quantity)::numeric, 2
      );
      v_disc numeric(14,2);
      v_net numeric(14,2);
      v_sub numeric(14,2);
      v_tax numeric(14,2);
      v_line_total numeric(14,2);
    begin
      -- Monto si vino; si no, el porcentaje del fallback sobre el bruto.
      v_disc := coalesce(
        v_item.discount_amount_in,
        round((v_gross * coalesce(v_item.discount_pct_in, 0) / 100)::numeric, 2)
      );
      -- El descuento nunca puede dejar la línea en negativo ni sumar al total.
      v_disc := least(greatest(v_disc, 0::numeric), v_gross);
      v_net := round((v_gross - v_disc)::numeric, 2);

      if coalesce(v_product.price_includes_tax, false) and v_rate > 0 then
        -- Precio con ITBIS incluido: el neto es el total exacto y el impuesto
        -- se extrae.
        v_line_total := v_net;
        v_tax := round((v_net * v_rate / (100 + v_rate))::numeric, 2);
        v_sub := v_line_total - v_tax;
      else
        -- Exclusivo: el ITBIS se agrega encima del neto.
        v_sub := v_net;
        v_tax := round((v_net * v_rate / 100)::numeric, 2);
        v_line_total := round((v_sub + v_tax)::numeric, 2);
      end if;

      insert into tmp_edit_items_imeis (
        product_id, description, quantity, unit_price, discount_amount,
        tax_rate, line_subtotal, line_tax, line_total, imeis
      ) values (
        v_item.product_id,
        coalesce(nullif(v_item.description, ''), v_product.name),
        v_item.quantity, v_item.unit_price, v_disc, v_rate, v_sub, v_tax,
        v_line_total, coalesce(v_item.imeis, '{}'::text[])
      );
    end;

    v_item_count := v_item_count + 1;
  end loop;

  if v_item_count = 0 then
    raise exception 'No se procesó ningún item válido.'
      using errcode = '22023';
  end if;

  if v_old_imei_count > 0 and v_new_imei_count = 0 then
    raise notice
      'edit_sale_transactional(%): % IMEI(s) devueltos al inventario porque la edición no envió imeis. La venta editada queda sin IMEIs.',
      p_sale_id, v_old_imei_count;
  end if;

  -- 4) Aplicar el nuevo stock (deducir cantidad nueva).
  update public.products p
  set stock = round(
    (coalesce(p.stock, 0) - tei.quantity)::numeric(14, 3),
    3
  )
  from tmp_edit_items_imeis tei
  where p.id = tei.product_id
    and p.branch_id = v_branch_id
    and coalesce(p.is_service, false) = false
    and coalesce(p.track_inventory, true) = true;

  -- 5) Insertar los nuevos items.
  insert into public.sale_items (
    sale_id, branch_id, product_id, description, quantity, unit_price,
    discount_amount, tax_rate, line_subtotal, line_tax, line_total, imeis
  )
  select
    p_sale_id, v_branch_id, product_id, description, quantity, unit_price,
    discount_amount, tax_rate, line_subtotal, line_tax, line_total,
    coalesce(imeis, '{}'::text[])
  from tmp_edit_items_imeis
  order by product_id;

  -- 5b) Los IMEIs que quedaron en la venta salen otra vez del inventario.
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

  -- 6) Recalcular totales desde tmp_edit_items_imeis.
  select
    coalesce(sum(line_subtotal), 0),
    coalesce(sum(line_tax), 0),
    coalesce(sum(line_total), 0),
    coalesce(sum(discount_amount), 0)
  into v_subtotal, v_tax_amount, v_total_amount, v_discount_total
  from tmp_edit_items_imeis;

  -- 7) Pago y saldo según el estado de la venta.
  if v_sale.status = 'completed'::public.sale_status then
    -- Venta pagada: el pago sigue al total (queda saldada).
    v_paid_amount := v_total_amount;
    v_balance_due := 0;

    -- Si hay UN solo pago (caso normal del POS), ajustar su monto para que el
    -- cuadre de caja y los reportes reflejen el total corregido. Si hay varios
    -- (pago dividido), no tocamos los pagos: solo ajustamos el encabezado.
    select count(*) into v_payment_count
      from public.payments where sale_id = p_sale_id;
    if v_payment_count = 1 then
      update public.payments
         set amount = v_total_amount
       where sale_id = p_sale_id;
    end if;
  else
    -- Crédito (u otros): se preserva lo pagado; el saldo se recalcula.
    v_paid_amount := coalesce(v_sale.paid_amount, 0);
    v_balance_due := greatest(
      round((v_total_amount - v_paid_amount)::numeric, 2),
      0
    );
  end if;

  -- 8) Actualizar la fila sales. discount_amount = suma de los descuentos de
  --    línea: informativo para recibo y reportes, NO se resta del total (el
  --    subtotal ya viene neto).
  update public.sales
  set
    subtotal = v_subtotal,
    discount_amount = v_discount_total,
    tax_amount = v_tax_amount,
    total_amount = v_total_amount,
    paid_amount = v_paid_amount,
    balance_due = v_balance_due,
    client_id = v_target_client,
    notes = v_note,
    updated_at = timezone('utc', now())
  where id = p_sale_id;

  -- 9) Ajustar clients.balance_due por la diferencia (solo crédito / saldo).
  if v_sale.status = 'credit'::public.sale_status
     or v_balance_due > 0 then
    if v_old_client_id is distinct from v_target_client then
      if v_old_client_id is not null then
        update public.clients
        set balance_due = greatest(
          round((coalesce(balance_due, 0) - v_old_total)::numeric, 2),
          0
        )
        where id = v_old_client_id and branch_id = v_branch_id;
      end if;
      if v_target_client is not null then
        update public.clients
        set balance_due = round(
          (coalesce(balance_due, 0) + v_total_amount)::numeric, 2
        )
        where id = v_target_client and branch_id = v_branch_id;
      end if;
    elsif v_target_client is not null then
      update public.clients
      set balance_due = greatest(
        round(
          (coalesce(balance_due, 0) + (v_total_amount - v_old_total))::numeric,
          2
        ),
        0
      )
      where id = v_target_client and branch_id = v_branch_id;
    end if;
  end if;

  return jsonb_build_object(
    'sale_id', p_sale_id,
    'subtotal', v_subtotal,
    'discount_amount', v_discount_total,
    'tax_amount', v_tax_amount,
    'total_amount', v_total_amount,
    'paid_amount', v_paid_amount,
    'balance_due', v_balance_due,
    'items_count', v_item_count,
    'client_id', v_target_client,
    'old_total', v_old_total,
    'imeis_restored', v_old_imei_count,
    'imeis_kept', v_new_imei_count
  );
end;
$$;

grant execute on function public.edit_sale_transactional(
  uuid, jsonb, uuid, boolean, text, boolean
) to authenticated;

commit;

notify pgrst, 'reload schema';


-- ============================================================================
-- VERIFICACIÓN — correr después. Debe devolver UNA sola fila por función,
-- con descuento=discount_amount, itbis_incluido=true y track_inventory=true.
-- ============================================================================
select
  p.oid::regprocedure::text as firma,
  case when pg_get_functiondef(p.oid) like '%>>''discount_amount''%'
       then 'discount_amount OK' else 'REVISAR' end as descuento,
  (pg_get_functiondef(p.oid) like '%price_includes_tax%') as itbis_incluido,
  (pg_get_functiondef(p.oid) like '%track_inventory%')    as track_inventory,
  (pg_get_functiondef(p.oid) like '%::text = ''none''%')  as sin_comprobante
from pg_proc p
join pg_namespace n on n.oid = p.pronamespace
where n.nspname = 'public'
  and p.proname in ('checkout_sale_transactional','hold_sale_transactional',
                    'edit_sale_transactional')
order by 1;
