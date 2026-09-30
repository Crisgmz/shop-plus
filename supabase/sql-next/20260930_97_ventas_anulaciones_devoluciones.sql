-- ============================================================================
-- 20260930_97_ventas_anulaciones_devoluciones.sql
--
-- Correcciones de la auditoría del 30 sep 2026 sobre editar, anular y devolver
-- ventas, más las notas de crédito fiscales (B04). Correr DESPUÉS de la 96.
--
-- BASE COMPARTIDA con flutter_shop+: las tres funciones que se reemplazan
-- conservan su firma y todo lo que el otro app manda sigue funcionando. Lo
-- nuevo (motivo de anulación, NCF de nota de crédito) son parámetros o
-- columnas adicionales que el otro app simplemente no usa.
--
-- 1) edit_sale_transactional
--    · INVENTARIO DOBLE. Desde la migración 25 la función devolvía el stock a
--      mano y además borraba las líneas, y el trigger trg_sale_items_stock lo
--      devolvía otra vez; igual al descontar. Editar una línea de 5 a 3 subía
--      el stock 4 en vez de 2. Ahora lo hace solo el trigger.
--    · El `UPDATE products … FROM sale_items` con dos líneas del mismo
--      producto (caja + sueltas) aplicaba UNA sola al azar. Desaparece con lo
--      anterior.
--    · Stock: se valida por PRODUCTO (todas sus líneas) y solo cuando la
--      edición pide más de lo que la venta ya tenía, respetando "No permitir
--      venta sin stock" — la regla de la migración 87 de flutter_shop+, que la
--      91/92 de este árbol pisaron sin querer.
--    · Solo ventas cobradas o a crédito; nunca una con devoluciones (el
--      editor ignoraba lo devuelto y volvía a sacar del inventario los IMEIs
--      que ya habían regresado).
--    · Un producto desactivado se puede mantener si ya estaba en la venta.
--    · Comprobante fiscal (B01, B14, B15…): el cliente con que queda debe
--      tener RNC/cédula. El trigger que lo exige solo corre al crear la venta.
--    · Pagos: sum(pagos) − cambio = total, siempre. Antes el único pago se
--      reescribía al total sin tocar el cambio (la caja esperaba de menos), y
--      un pago dividido quedaba con el monto viejo.
--    · Cuentas por cobrar: lo abonado se respeta; si el nuevo total queda
--      cubierto, la venta pasa a pagada. El saldo del cliente se recalcula
--      desde sus ventas (antes se movía el TOTAL, no el saldo).
--    · El documento fiscal queda con los montos y el cliente nuevos.
--
-- 2) void_sale_with_stock_return
--    · Stock sumado por producto (mismo problema del UPDATE … FROM).
--    · Bloquea la fila (dos anulaciones a la vez devolvían el stock dos veces).
--    · Solo cobradas o a crédito; nunca una venta con devoluciones.
--    · Pagos de un turno YA CERRADO se conservan (ese turno sí recibió el
--      dinero) y el efectivo que se devuelve hoy sale como movimiento de la
--      caja abierta de quien anula. Antes se borraban: la caja de hoy daba
--      corta y el cierre de ayer cambiaba.
--    · Recalcula el saldo del cliente y marca el comprobante como anulado.
--    · Nueva sobrecarga con motivo (tipo de anulación DGII, para el 608).
--
-- 3) process_return
--    · Con venta original: montos e ITBIS salen de las LÍNEAS DE LA VENTA,
--      prorrateados por la cantidad devuelta. Antes se confiaba en el precio y
--      la tasa que mandaba el app: con precio ITBIS-incluido se reembolsaba
--      solo la base (118 → 100) y en ventas sin comprobante se inventaba ITBIS.
--    · No se puede devolver más de lo vendido menos lo ya devuelto, ni un
--      producto que no está en la venta, ni una cuenta guardada.
--    · Venta a crédito: la devolución baja primero el saldo de ESA venta; solo
--      lo que exceda se reembolsa. El cliente es el de la venta.
--    · Venta con NCF: toma un NCF de Nota de Crédito (B04) que referencia el
--      original y registra el documento fiscal. Sin secuencia B04, la
--      devolución se hace igual y la respuesta lo avisa.
--    · Permiso de POS, acceso por empresa (can_access_branch, migración 85,
--      que la 88 de flutter_shop+ deshizo) y numeración sin choques.
--
-- 4) cash_session_summary_view multiplicaba ventas × pagos de la sesión.
-- 5) FKs compuestas con ON DELETE SET NULL que ponían en null branch_id.
--
-- Idempotente (create or replace, add column if not exists).
-- ============================================================================

begin;

-- ── 0) Esquema ──────────────────────────────────────────────────────────────

-- Anulación: cuándo, quién y el tipo DGII (01..10) para el formato 608.
alter table public.sales
  add column if not exists voided_at timestamptz,
  add column if not exists voided_by uuid references auth.users(id),
  add column if not exists void_reason_code text;

comment on column public.sales.void_reason_code is
  'Tipo de anulación DGII (608): 01 deterioro, 02 errores de impresión, 03 impresión defectuosa, 04 corrección de la información, 05 cambio de productos, 06 devolución de productos, 07 omisión de productos, 08 errores en secuencia NCF, 09 cese de operaciones, 10 pérdida o hurto de talonarios.';

-- Nota de crédito fiscal y reparto crédito / efectivo de la devolución.
alter table public.returns
  add column if not exists receipt_type public.receipt_type,
  add column if not exists ncf text,
  add column if not exists ncf_modificado text,
  add column if not exists fiscal_document_id uuid,
  add column if not exists credit_applied numeric(14,2) not null default 0,
  add column if not exists cash_refund_amount numeric(14,2);

comment on column public.returns.ncf is
  'NCF de Nota de Crédito (B04/E34) de la devolución de una venta con comprobante fiscal.';
comment on column public.returns.ncf_modificado is
  'NCF de la venta original que la nota de crédito modifica.';
comment on column public.returns.credit_applied is
  'Parte de la devolución que bajó el saldo pendiente de la venta a crédito.';
comment on column public.returns.cash_refund_amount is
  'Dinero realmente devuelto (total − credit_applied). NULL en devoluciones anteriores a la migración 97: se asume el total.';

create unique index if not exists returns_branch_ncf_key
  on public.returns (branch_id, ncf) where ncf is not null;

-- Presentación de la línea devuelta ("1 Caja"), para la nota de crédito.
alter table public.return_items
  add column if not exists uom text,
  add column if not exists uom_factor numeric(14,3),
  add column if not exists unit_name text;

-- FKs compuestas (x_id, branch_id) con ON DELETE SET NULL: al borrar la venta
-- (completar o descartar una cuenta guardada) intentaban poner branch_id en
-- null, que es NOT NULL, y el borrado fallaba. PG15: SET NULL (columna).
alter table public.returns drop constraint if exists returns_sale_branch_fk;
alter table public.returns
  add constraint returns_sale_branch_fk
  foreign key (original_sale_id, branch_id)
  references public.sales (id, branch_id)
  on delete set null (original_sale_id);

alter table public.fiscal_documents drop constraint if exists fiscal_documents_sale_fk;
alter table public.fiscal_documents
  add constraint fiscal_documents_sale_fk
  foreign key (sale_id, branch_id)
  references public.sales (id, branch_id)
  on delete set null (sale_id);

alter table public.fiscal_documents drop constraint if exists fiscal_documents_client_fk;
alter table public.fiscal_documents
  add constraint fiscal_documents_client_fk
  foreign key (client_id, branch_id)
  references public.clients (id, branch_id)
  on delete set null (client_id);

-- ── Helper: saldo del cliente = lo pendiente en sus ventas vivas ────────────
-- Misma regla que register_sale_payment (migración 82). Un solo lugar para
-- que editar, anular y devolver dejen el saldo igual que un abono.
create or replace function public.recompute_client_balance(
  p_client_id uuid,
  p_branch_id uuid
)
returns numeric
language plpgsql
security definer
set search_path = public
as $$
declare
  v_balance numeric(14,2);
begin
  if p_client_id is null then
    return 0;
  end if;
  select coalesce(round(sum(s.balance_due)::numeric, 2), 0)
    into v_balance
    from public.sales s
   where s.branch_id = p_branch_id
     and s.client_id = p_client_id
     and s.balance_due > 0
     and s.status <> 'voided'::public.sale_status;

  update public.clients
     set balance_due = coalesce(v_balance, 0)
   where id = p_client_id
     and branch_id = p_branch_id;
  return coalesce(v_balance, 0);
end;
$$;

-- Solo lo usan las funciones de este archivo (SECURITY DEFINER): el app no
-- lo llama directo.
revoke all on function public.recompute_client_balance(uuid, uuid)
  from public, anon, authenticated;

-- ── 1) edit_sale_transactional ──────────────────────────────────────────────

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
    unit_name text
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
      v_gross numeric(14,2) := case
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

      if coalesce(v_product.price_includes_tax, false) and v_rate > 0 then
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
        uom, uom_factor, uom_price, unit_name
      ) values (
        v_item.product_id,
        coalesce(nullif(v_item.description, ''), v_product.name),
        v_item.quantity, v_item.unit_price, v_disc, v_rate, v_sub, v_tax,
        v_line_total, coalesce(v_item.imeis, '{}'::text[]),
        coalesce(v_item.uom, 'unit'), coalesce(v_item.uom_factor, 1),
        v_item.uom_price, v_item.unit_name
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
    uom, uom_factor, uom_price, unit_name
  )
  select
    p_sale_id, v_branch_id, product_id, description, quantity, unit_price,
    discount_amount, tax_rate, line_subtotal, line_tax, line_total,
    coalesce(imeis, '{}'::text[]),
    coalesce(uom, 'unit'), coalesce(uom_factor, 1), uom_price, unit_name
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

-- ── 2) Anular venta ─────────────────────────────────────────────────────────

create or replace function public.void_sale_with_stock_return(
  p_sale_id uuid,
  p_reason_code text
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_user uuid := auth.uid();
  v_sale record;
  v_line record;
  v_override boolean;
  v_can_void boolean;
  v_returns text;
  v_reason text := nullif(btrim(coalesce(p_reason_code, '')), '');
  v_closed_cash numeric(14,2) := 0;
  v_session_id uuid;
begin
  if p_sale_id is null then
    raise exception 'Falta la venta a anular.' using errcode = '22023';
  end if;

  if v_reason is not null and v_reason !~ '^(0[1-9]|10)$' then
    raise exception 'Motivo de anulación inválido.' using errcode = '22023';
  end if;

  -- CAMBIO 97: FOR UPDATE. Dos anulaciones a la vez (dos equipos, o reabrir
  -- el menú mientras corría la primera) devolvían el stock dos veces.
  select id, branch_id, status, client_id, ncf, sale_number,
         cash_session_id, change_amount
    into v_sale
    from public.sales
   where id = p_sale_id
   for update;

  if not found then
    raise exception 'Venta no encontrada.' using errcode = 'P0002';
  end if;

  if not public.has_branch_access(v_sale.branch_id) then
    raise exception 'Sin acceso a esta venta.' using errcode = '42501';
  end if;

  -- Permiso: override del usuario sobre `sales.void`, o el rol (migración 88).
  select up.granted
    into v_override
    from public.user_permissions up
    join public.permissions p on p.id = up.permission_id
   where up.user_id = v_user
     and up.is_active
     and p.code = 'sales.void'
     and (up.branch_id is null or up.branch_id = v_sale.branch_id)
   order by case when up.branch_id = v_sale.branch_id then 0 else 1 end,
            up.created_at desc
   limit 1;

  v_can_void := public.is_admin() or coalesce(
    v_override,
    public.current_user_role() = 'supervisor'::public.app_role
  );
  if not v_can_void then
    raise exception 'No tienes permiso para anular ventas.' using errcode = '42501';
  end if;

  if v_sale.status = 'voided'::public.sale_status then
    raise exception 'La venta ya está anulada.' using errcode = '23505';
  end if;

  -- CAMBIO 97: una cuenta guardada se descarta, no se anula (anularla
  -- devolvía IMEIs que guardar nunca sacó).
  if v_sale.status not in (
    'completed'::public.sale_status, 'credit'::public.sale_status
  ) then
    raise exception 'Solo se anulan ventas cobradas o a crédito. Una cuenta guardada se descarta desde el historial.'
      using errcode = '22023';
  end if;

  -- CAMBIO 97: con devoluciones no se anula: devolvería otra vez el stock y
  -- el dinero de lo que ya regresó.
  select string_agg(coalesce(r.return_number, 'sin número'), ', ')
    into v_returns
    from public.returns r
   where r.original_sale_id = p_sale_id;
  if v_returns is not null then
    raise exception 'Esta venta tiene devoluciones (%): no se puede anular. Devuelve el resto de la mercancía con otra devolución.', v_returns
      using errcode = '22023';
  end if;

  -- 0) IMEIs de vuelta al inventario.
  for v_line in
    select si.product_id, si.branch_id, si.imeis
      from public.sale_items si
     where si.sale_id = p_sale_id
       and coalesce(array_length(si.imeis, 1), 0) > 0
  loop
    perform public.restore_product_imeis(
      v_line.product_id, v_line.branch_id, v_line.imeis
    );
  end loop;

  -- 1) Stock de vuelta SIN borrar las líneas (la factura anulada conserva su
  --    detalle, migración 88). CAMBIO 97: sumado por producto; con caja +
  --    sueltas del mismo producto el UPDATE … FROM aplicaba una sola línea.
  update public.products p
     set stock = round((coalesce(p.stock, 0) + agg.qty)::numeric(14, 3), 3)
    from (
      select si.product_id, sum(si.quantity) as qty
        from public.sale_items si
       where si.sale_id = p_sale_id
         and si.product_id is not null
       group by si.product_id
    ) agg
   where p.id = agg.product_id
     and p.branch_id = v_sale.branch_id
     and coalesce(p.is_service, false) = false
     and coalesce(p.track_inventory, true) = true;

  -- 2) Pagos.
  --    CAMBIO 97: los de un turno YA CERRADO se conservan — ese turno sí
  --    recibió el dinero y su cierre no debe cambiar — y el efectivo que se
  --    devuelve hoy sale como movimiento de la caja abierta de quien anula.
  --    Los de una caja abierta (o sin caja) se borran, como antes: el dinero
  --    sale de esa misma caja.
  select coalesce(sum(p.amount), 0)
    into v_closed_cash
    from public.payments p
    join public.cash_sessions cs on cs.id = p.cash_session_id
   where p.sale_id = p_sale_id
     and cs.status <> 'open'
     and p.payment_method::text = 'cash';

  -- El cambio que se entregó en ese turno no se devuelve.
  if v_closed_cash > 0 and exists (
    select 1 from public.cash_sessions cs
     where cs.id = v_sale.cash_session_id and cs.status <> 'open'
  ) then
    v_closed_cash := greatest(v_closed_cash - coalesce(v_sale.change_amount, 0), 0);
  end if;

  if v_closed_cash > 0 then
    select cs.id into v_session_id
      from public.cash_sessions cs
     where cs.branch_id = v_sale.branch_id
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

    if v_session_id is null then
      raise exception 'Esta venta se cobró en un turno ya cerrado: abre una caja para anularla, el efectivo que devuelves sale de ella.'
        using errcode = '22023';
    end if;

    insert into public.cash_register_movements (
      branch_id, cash_session_id, movement_type, amount, reason,
      reference_type, reference_id, performed_by
    ) values (
      v_sale.branch_id, v_session_id, 'withdrawal', v_closed_cash,
      'Anulación de la venta ' || coalesce(v_sale.sale_number, ''),
      'sale_void', p_sale_id, v_user
    );
  end if;

  delete from public.payments p
   where p.sale_id = p_sale_id
     and (
       p.cash_session_id is null
       or exists (
         select 1 from public.cash_sessions cs
          where cs.id = p.cash_session_id and cs.status = 'open'
       )
     );

  -- 3) La venta.
  update public.sales
     set status = 'voided'::public.sale_status,
         voided_at = timezone('utc', now()),
         voided_by = v_user,
         void_reason_code = v_reason,
         updated_at = timezone('utc', now())
   where id = p_sale_id;

  -- 4) CAMBIO 97: saldo del cliente (una venta a crédito anulada seguía
  --    sumando a su deuda hasta el próximo abono).
  perform public.recompute_client_balance(v_sale.client_id, v_sale.branch_id);

  -- 5) CAMBIO 97: el comprobante queda anulado (para el 608).
  if v_sale.ncf is not null then
    update public.fiscal_documents
       set fiscal_status = 'voided'::public.dgii_status,
           voided_at = timezone('utc', now()),
           void_reason = coalesce(v_reason, void_reason),
           updated_at = timezone('utc', now())
     where sale_id = p_sale_id
       and branch_id = v_sale.branch_id
       and ncf = v_sale.ncf;
  end if;

  return jsonb_build_object(
    'sale_id', p_sale_id,
    'status', 'voided',
    'cash_refunded_from_open_session', v_closed_cash,
    'cash_session_id', v_session_id
  );
end;
$$;

grant execute on function public.void_sale_with_stock_return(uuid, text)
  to authenticated;

-- La firma de siempre (la usa flutter_shop+): misma lógica, sin motivo.
create or replace function public.void_sale_with_stock_return(
  p_sale_id uuid
)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  perform public.void_sale_with_stock_return(p_sale_id, null::text);
end;
$$;

grant execute on function public.void_sale_with_stock_return(uuid)
  to authenticated;

-- ── 3) Devoluciones y notas de crédito ──────────────────────────────────────

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
  v_user uuid := auth.uid();
  v_sale record;
  v_client_id uuid;
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
  v_sold record;
  v_prev record;
  v_remaining numeric(14,3);
  v_prefix text;
  v_seq bigint;
  v_cash_session_id uuid;
  v_refund_method text;
  v_credit_applied numeric(14,2) := 0;
  v_cash_refund numeric(14,2) := 0;
  v_nc_ncf text;
  v_ncf_error text;
  v_fiscal_doc_id uuid;
  v_issuer record;
  v_customer record;
  -- Datos de la venta original en variables simples: leer un campo de un
  -- record sin asignar (devolución sin venta) falla aunque el `and` corte.
  v_orig_ncf text;
  v_orig_receipt text;
  v_orig_balance numeric(14,2) := 0;
  v_orig_client uuid;
  v_orig_number text;
begin
  v_branch_id := coalesce(p_branch_id, public.current_branch_id());

  if v_user is null then
    raise exception 'Sesión inválida.' using errcode = '28000';
  end if;
  if v_branch_id is null then
    raise exception 'No hay sucursal asignada al usuario.' using errcode = '22023';
  end if;

  -- CAMBIO 97: acceso por empresa (migración 85; la 88 de flutter_shop+ lo
  -- había vuelto a `is_admin()` a secas, que abría otras empresas).
  if not public.can_access_branch(v_branch_id) then
    raise exception 'Sin acceso a la sucursal indicada.' using errcode = '42501';
  end if;

  -- CAMBIO 97: solo quien opera el POS. SECURITY DEFINER se saltaba la RLS
  -- de `returns`, así que cualquier rol (contador incluido) podía devolver.
  if not public.can_operate_pos() then
    raise exception 'No tienes permiso para registrar devoluciones.'
      using errcode = '42501';
  end if;

  if jsonb_array_length(coalesce(p_items, '[]'::jsonb)) = 0 then
    raise exception 'Una devolución requiere al menos un artículo.'
      using errcode = '22023';
  end if;

  v_refund_method := lower(coalesce(nullif(trim(coalesce(p_refund_method, '')), ''), 'cash'));

  -- Sesión de caja (igual que antes): la indicada si está abierta y es del
  -- usuario, o la última abierta del usuario. Puede quedar sin caja.
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

  v_client_id := p_client_id;

  if p_original_sale_id is not null then
    -- CAMBIO 97: bloqueo de la venta; dos devoluciones a la vez podían pasar
    -- las dos el tope de lo vendido.
    select id, status, client_id, ncf, receipt_type, balance_due, sale_number
      into v_sale
      from public.sales
     where id = p_original_sale_id
       and branch_id = v_branch_id
     for update;
    if not found then
      raise exception 'La venta original no existe en esta sucursal.'
        using errcode = '23503';
    end if;
    if v_sale.status = 'voided'::public.sale_status then
      raise exception 'La venta % está anulada: su stock y su dinero ya se devolvieron al anularla.', v_sale.sale_number
        using errcode = '22023';
    end if;
    -- CAMBIO 97: una cuenta guardada no se cobró: no hay nada que devolver.
    if v_sale.status not in (
      'completed'::public.sale_status, 'credit'::public.sale_status
    ) then
      raise exception 'La venta % no está cobrada: una cuenta guardada se descarta, no se devuelve.', v_sale.sale_number
        using errcode = '22023';
    end if;
    -- CAMBIO 97: el cliente es el de la venta. Con otro, la devolución bajaba
    -- la deuda de un cliente que no la tenía.
    v_client_id := v_sale.client_id;
    v_orig_ncf := v_sale.ncf;
    v_orig_receipt := v_sale.receipt_type::text;
    v_orig_balance := coalesce(v_sale.balance_due, 0);
    v_orig_client := v_sale.client_id;
    v_orig_number := v_sale.sale_number;
  end if;

  insert into public.returns (
    branch_id, client_id, original_sale_id, cashier_id, notes,
    subtotal, tax_amount, total_amount, cash_session_id, refund_method
  ) values (
    v_branch_id, v_client_id, p_original_sale_id, v_user, p_notes,
    0, 0, 0, v_cash_session_id, v_refund_method
  ) returning id into v_return_id;

  -- Número de devolución: prefijo de la empresa + correlativo por sucursal.
  -- CAMBIO 97: bajo un lock por sucursal y desde el MAYOR número usado; con
  -- count(*)+1 dos devoluciones a la vez chocaban, y tras borrar una todas
  -- las siguientes fallaban por número repetido.
  perform pg_advisory_xact_lock(hashtextextended('returns:' || v_branch_id::text, 0));
  select coalesce(s.prefix_credit_note, 'NC') into v_prefix
    from public.app_settings s
    join public.branches b on b.company_id = s.company_id
   where b.id = v_branch_id
   limit 1;
  v_prefix := coalesce(v_prefix, 'NC');
  select coalesce(max((regexp_match(r.return_number, '(\d+)$'))[1]::bigint), 0) + 1
    into v_seq
    from public.returns r
   where r.branch_id = v_branch_id
     and r.id <> v_return_id;
  v_return_number := v_prefix || '-' || lpad(v_seq::text, 5, '0');
  update public.returns set return_number = v_return_number where id = v_return_id;

  for v_item in select * from jsonb_array_elements(p_items)
  loop
    v_product_id := (v_item->>'product_id')::uuid;
    v_qty := (v_item->>'quantity')::numeric(14,3);

    if v_product_id is null then
      raise exception 'Falta el producto en una línea de la devolución.'
        using errcode = '22023';
    end if;
    if v_qty is null or v_qty <= 0 then
      raise exception 'La cantidad de cada línea debe ser mayor que cero.'
        using errcode = '22023';
    end if;

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
      raise exception 'Producto no encontrado en la sucursal.' using errcode = '23503';
    end if;

    if coalesce(array_length(v_line_imeis, 1), 0) > v_qty then
      raise exception
        'La línea de "%" trae % IMEI(s) para una cantidad devuelta de %. No se pueden devolver más equipos que unidades.',
        v_product_name, coalesce(array_length(v_line_imeis, 1), 0), v_qty
        using errcode = '22023';
    end if;

    if p_original_sale_id is not null then
      -- IMEIs: cada uno debe haber salido de ESA venta.
      if coalesce(array_length(v_line_imeis, 1), 0) > 0 then
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
          raise exception 'Los IMEI % no pertenecen a la venta original.',
            array_to_string(v_bad_imeis, ', ')
            using errcode = '22023';
        end if;
      end if;

      -- CAMBIO 97: lo vendido de este producto en la venta...
      select coalesce(sum(si.quantity), 0) as qty,
             coalesce(sum(si.line_subtotal), 0) as sub,
             coalesce(sum(si.line_tax), 0) as tax,
             coalesce(sum(si.line_total), 0) as total,
             coalesce(max(si.tax_rate), 0) as rate
        into v_sold
        from public.sale_items si
       where si.sale_id = p_original_sale_id
         and si.product_id = v_product_id;
      if v_sold.qty <= 0 then
        raise exception 'El producto "%" no está en la venta original.', v_product_name
          using errcode = '22023';
      end if;

      -- ... menos lo ya devuelto (incluye las líneas de ESTA devolución).
      select coalesce(sum(ri.quantity), 0) as qty,
             coalesce(sum(ri.line_tax), 0) as tax,
             coalesce(sum(ri.line_total), 0) as total
        into v_prev
        from public.return_items ri
        join public.returns r on r.id = ri.return_id
       where r.original_sale_id = p_original_sale_id
         and ri.product_id = v_product_id;

      v_remaining := v_sold.qty - v_prev.qty;
      if v_qty > v_remaining + 0.0005 then
        raise exception 'No se puede devolver más de lo vendido de "%": vendido %, ya devuelto %, se piden %.',
          v_product_name, v_sold.qty, v_prev.qty, v_qty
          using errcode = '22023';
      end if;

      -- CAMBIO 97: montos de la venta, prorrateados. Al devolver todo lo que
      -- queda se usa el resto exacto, para que la suma de devoluciones dé al
      -- centavo el total de la venta.
      if v_qty >= v_remaining - 0.0005 then
        v_line_total := round((v_sold.total - v_prev.total)::numeric, 2);
        v_line_tax := round((v_sold.tax - v_prev.tax)::numeric, 2);
      else
        v_line_total := round((v_sold.total * v_qty / v_sold.qty)::numeric, 2);
        v_line_tax := round((v_sold.tax * v_qty / v_sold.qty)::numeric, 2);
      end if;
      v_line_subtotal := v_line_total - v_line_tax;
      v_tax_rate := v_sold.rate;
      v_price := round((v_line_subtotal / v_qty)::numeric, 2);
    else
      -- Devolución sin venta: como antes, con el precio y la tasa del app.
      v_price := (v_item->>'unit_price')::numeric(14,2);
      v_tax_rate := coalesce((v_item->>'tax_rate')::numeric(5,2), 18.00);
      if v_price is null or v_price < 0 then
        raise exception 'El precio unitario es inválido.' using errcode = '22023';
      end if;
      v_gross := round(v_qty * v_price, 2);
      if v_price_includes_tax and v_tax_rate > 0 then
        v_line_total := v_gross;
        v_line_tax := round((v_gross * v_tax_rate / (100 + v_tax_rate))::numeric, 2);
        v_line_subtotal := v_line_total - v_line_tax;
      else
        v_line_subtotal := v_gross;
        v_line_tax := round(v_line_subtotal * v_tax_rate / 100.0, 2);
        v_line_total := v_line_subtotal + v_line_tax;
      end if;
    end if;

    insert into public.return_items (
      return_id, branch_id, product_id, description, quantity,
      unit_price, tax_rate, line_subtotal, line_tax, line_total, imeis,
      uom, uom_factor, unit_name
    ) values (
      v_return_id, v_branch_id, v_product_id, v_product_name, v_qty,
      v_price, v_tax_rate, v_line_subtotal, v_line_tax, v_line_total,
      v_line_imeis,
      nullif(lower(btrim(coalesce(v_item->>'uom', ''))), ''),
      nullif(v_item->>'uom_factor', '')::numeric(14,3),
      nullif(btrim(coalesce(v_item->>'unit_name', '')), '')
    );

    if coalesce(array_length(v_line_imeis, 1), 0) > 0 then
      perform public.restore_product_imeis(v_product_id, v_branch_id, v_line_imeis);
    end if;

    v_subtotal := v_subtotal + v_line_subtotal;
    v_tax := v_tax + v_line_tax;
    v_total := v_total + v_line_total;
    v_items_count := v_items_count + 1;
  end loop;

  -- CAMBIO 97: venta con saldo pendiente → la devolución baja primero ESE
  -- saldo; solo lo que exceda se reembolsa. Antes se restaba el total a la
  -- deuda del cliente (sin tocar la venta, así que el próximo abono la
  -- revivía) y además contaba como efectivo que salió de la caja.
  v_cash_refund := v_total;
  if p_original_sale_id is not null and v_orig_balance > 0 then
    v_credit_applied := least(v_total, v_orig_balance);
    v_cash_refund := v_total - v_credit_applied;
    update public.sales
       set balance_due = round((balance_due - v_credit_applied)::numeric, 2),
           status = case
             when round((balance_due - v_credit_applied)::numeric, 2) <= 0
               then 'completed'::public.sale_status
             else status
           end,
           updated_at = timezone('utc', now())
     where id = p_original_sale_id;
    perform public.recompute_client_balance(v_orig_client, v_branch_id);
    -- Todo fue a la deuda: no sale dinero de la caja. `credit_balance` hace
    -- que el cuadre de los dos apps no lo reste como efectivo.
    if v_cash_refund <= 0 then
      v_refund_method := 'credit_balance';
    end if;
  end if;

  update public.returns
     set subtotal = v_subtotal,
         tax_amount = v_tax,
         total_amount = v_total,
         credit_applied = v_credit_applied,
         cash_refund_amount = v_cash_refund,
         refund_method = v_refund_method
   where id = v_return_id;

  -- CAMBIO 97: Nota de Crédito fiscal. Si la venta llevó NCF, la devolución
  -- toma el siguiente de la secuencia de Notas de Crédito (B04) y guarda el
  -- NCF que modifica. Sin secuencia, la devolución sigue (no se bloquea la
  -- operación) y la respuesta lo avisa para configurarla.
  if p_original_sale_id is not null
     and v_orig_ncf is not null
     and v_orig_receipt <> 'none' then
    begin
      v_nc_ncf := public.assign_next_ncf(v_branch_id, 'credit_note'::public.receipt_type);
    exception when others then
      v_nc_ncf := null;
      v_ncf_error := 'No hay secuencia de Notas de Crédito (B04) disponible: la devolución se registró sin NCF.';
    end;

    update public.returns
       set receipt_type = 'credit_note'::public.receipt_type,
           ncf = v_nc_ncf,
           ncf_modificado = v_orig_ncf
     where id = v_return_id;

    -- Documento fiscal de la nota de crédito (serie física). Una E34 no se
    -- registra aquí: el emisor electrónico todavía no la sabe enviar y la
    -- dejaría atascada en la cola.
    if v_nc_ncf is not null and v_nc_ncf not like 'E%' then
      select coalesce(nullif(s.company_legal_name, ''), s.company_name) as name,
             s.company_tax_id as tax_id
        into v_issuer
        from public.app_settings s
        join public.branches b on b.company_id = s.company_id
       where b.id = v_branch_id
       limit 1;

      select coalesce(nullif(c.legal_name, ''), c.full_name) as name,
             c.document_type::text as doc_type,
             c.document_number as doc_number,
             c.address as address
        into v_customer
        from public.clients c
       where c.id = v_client_id and c.branch_id = v_branch_id;

      insert into public.fiscal_documents (
        branch_id, sale_id, client_id, ncf_sequence_id, receipt_type,
        ncf, fiscal_status, issued_at,
        customer_name, customer_document_type, customer_document_number,
        customer_address, issuer_name, issuer_tax_id,
        subtotal, discount_amount, tax_amount, total_amount, payload
      ) values (
        v_branch_id, p_original_sale_id, v_client_id,
        (select q.id from public.ncf_sequences q
          where q.branch_id = v_branch_id
            and q.receipt_type = 'credit_note'::public.receipt_type
            and v_nc_ncf like q.prefix || '%'
          order by q.updated_at desc limit 1),
        'credit_note'::public.receipt_type,
        v_nc_ncf, 'pending'::public.dgii_status, timezone('utc', now()),
        v_customer.name, v_customer.doc_type, v_customer.doc_number,
        v_customer.address, v_issuer.name, v_issuer.tax_id,
        v_subtotal, 0, v_tax, v_total,
        jsonb_build_object(
          'return_id', v_return_id,
          'return_number', v_return_number,
          'ncf_modificado', v_orig_ncf,
          'original_sale_number', v_orig_number
        )
      )
      on conflict (branch_id, ncf) do nothing
      returning id into v_fiscal_doc_id;

      update public.returns set fiscal_document_id = v_fiscal_doc_id
       where id = v_return_id;
    end if;
  end if;

  return jsonb_build_object(
    'return_id', v_return_id,
    'return_number', v_return_number,
    'subtotal', v_subtotal,
    'tax_amount', v_tax,
    'total_amount', v_total,
    'items_count', v_items_count,
    'cash_session_id', v_cash_session_id,
    'refund_method', v_refund_method,
    'credit_applied', v_credit_applied,
    'cash_refund_amount', v_cash_refund,
    'credit_balance_adjusted', v_credit_applied > 0,
    'ncf', v_nc_ncf,
    'ncf_modificado', case when v_nc_ncf is not null or v_ncf_error is not null
                           then v_orig_ncf end,
    'ncf_error', v_ncf_error
  );
end;
$$;

grant execute on function public.process_return(
  uuid, uuid, uuid, text, jsonb, uuid, text
) to authenticated;

-- ── 4) Resumen de caja: sin producto cartesiano ─────────────────────────────
-- Antes: `left join sales … left join payments …` por sesión multiplicaba
-- cada venta por cada pago (3 ventas de 100 con su pago → 900).
create or replace view public.cash_session_summary_view
with (security_invoker = true)
as
select
  cs.id as cash_session_id,
  cs.branch_id,
  cs.opened_by,
  cs.closed_by,
  cs.status,
  cs.opened_at,
  cs.closed_at,
  cs.opening_amount,
  cs.expected_amount,
  cs.closing_amount,
  cs.difference_amount,
  coalesce(sv.sales_completed, 0)::bigint as sales_completed,
  coalesce(sv.sales_voided, 0)::bigint as sales_voided,
  coalesce(sv.sales_total, 0)::numeric(14,2) as sales_total,
  coalesce(pv.cash_collected, 0)::numeric(14,2) as cash_collected,
  coalesce(pv.card_collected, 0)::numeric(14,2) as card_collected,
  coalesce(pv.transfer_collected, 0)::numeric(14,2) as transfer_collected,
  coalesce(pv.mobile_collected, 0)::numeric(14,2) as mobile_collected,
  coalesce(pv.credit_collected, 0)::numeric(14,2) as credit_collected
from public.cash_sessions cs
left join lateral (
  select
    count(*) filter (where s.status = 'completed'::public.sale_status) as sales_completed,
    count(*) filter (where s.status = 'voided'::public.sale_status) as sales_voided,
    sum(s.total_amount) filter (where s.status = 'completed'::public.sale_status) as sales_total
  from public.sales s
  where s.cash_session_id = cs.id and s.branch_id = cs.branch_id
) sv on true
left join lateral (
  select
    sum(pay.amount) filter (where pay.payment_method = 'cash'::public.payment_method) as cash_collected,
    sum(pay.amount) filter (where pay.payment_method = 'card'::public.payment_method) as card_collected,
    sum(pay.amount) filter (where pay.payment_method = 'transfer'::public.payment_method) as transfer_collected,
    sum(pay.amount) filter (where pay.payment_method = 'mobile'::public.payment_method) as mobile_collected,
    sum(pay.amount) filter (where pay.payment_method = 'credit'::public.payment_method) as credit_collected
  from public.payments pay
  where pay.cash_session_id = cs.id and pay.branch_id = cs.branch_id
) pv on true
where public.has_branch_access(cs.branch_id);

grant select on public.cash_session_summary_view to authenticated;

commit;
