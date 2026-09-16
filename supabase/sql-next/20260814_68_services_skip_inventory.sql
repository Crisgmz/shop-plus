-- ============================================================================
-- Migración 68 — Los servicios NO mueven inventario
-- ============================================================================
-- Bug de fondo: un producto marcado como servicio (products.is_service = true)
-- igual descuenta stock al venderlo, porque los triggers de stock nunca miraron
-- ese flag. Resultado: "Mano de obra" termina con stock −47 y aparece en el
-- reporte de bajo stock.
--
-- Arreglo mínimo y seguro: los 4 triggers de stock quedan con el MISMO cuerpo,
-- solo que cada `update public.products` gana dos predicados:
--     and coalesce(p.is_service, false) = false
--     and coalesce(p.track_inventory, true) = true
-- Así un servicio simplemente no mueve stock en NINGUNA dirección (venta,
-- compra, devolución, ajuste). No se lanza error, no se bloquea nada: la fila
-- del producto no se toca.
--
-- Triggers corregidos (versiones de origen):
--   apply_sale_item_stock()          — supabase/sql/01_schema.sql:550-608
--   apply_purchase_item_stock()      — supabase/sql/01_schema.sql:505-547
--   apply_return_item_stock()        — sql-next/20260509_11_returns.sql:101-124
--   apply_inventory_movement_stock() — sql-next/20260509_09_reports_schema.sql:97-154
--
-- Vistas corregidas: un servicio nunca debe aparecer como "bajo stock".
--   public.inventory_low_stock_view    — supabase/sql/03_reports_views.sql:214
--   public.report_inventory_status_view— sql-next/20260509_13_reports_round2_views.sql:163
--
-- Las columnas products.is_service y products.track_inventory ya existen desde
-- 20260421_structural_backoffice_foundation.sql — aquí NO se crean.
--
-- Idempotente: solo `create or replace` + updates de saneo acotados.
-- ============================================================================

begin;

-- ============================================================================
-- 1) Triggers de stock
-- ============================================================================

create or replace function public.apply_purchase_item_stock()
returns trigger
language plpgsql
as $$
begin
  if tg_op = 'INSERT' then
    update public.products p
      set stock = p.stock + new.quantity
    where p.id = new.product_id
      and p.branch_id = new.branch_id
      and coalesce(p.is_service, false) = false
      and coalesce(p.track_inventory, true) = true;
    return new;
  end if;

  if tg_op = 'UPDATE' then
    if old.product_id = new.product_id and old.branch_id = new.branch_id then
      update public.products p
        set stock = p.stock + (new.quantity - old.quantity)
      where p.id = new.product_id
        and p.branch_id = new.branch_id
        and coalesce(p.is_service, false) = false
        and coalesce(p.track_inventory, true) = true;
    else
      update public.products p
        set stock = p.stock - old.quantity
      where p.id = old.product_id
        and p.branch_id = old.branch_id
        and coalesce(p.is_service, false) = false
        and coalesce(p.track_inventory, true) = true;

      update public.products p
        set stock = p.stock + new.quantity
      where p.id = new.product_id
        and p.branch_id = new.branch_id
        and coalesce(p.is_service, false) = false
        and coalesce(p.track_inventory, true) = true;
    end if;
    return new;
  end if;

  if tg_op = 'DELETE' then
    update public.products p
      set stock = p.stock - old.quantity
    where p.id = old.product_id
      and p.branch_id = old.branch_id
      and coalesce(p.is_service, false) = false
      and coalesce(p.track_inventory, true) = true;
    return old;
  end if;

  return null;
end;
$$;

create or replace function public.apply_sale_item_stock()
returns trigger
language plpgsql
as $$
begin
  if tg_op = 'INSERT' then
    update public.products p
      set stock = p.stock - new.quantity
    where p.id = new.product_id
      and p.branch_id = new.branch_id
      and coalesce(p.is_service, false) = false
      and coalesce(p.track_inventory, true) = true;
    return new;
  end if;

  if tg_op = 'UPDATE' then
    if old.product_id = new.product_id and old.branch_id = new.branch_id then
      update public.products p
        set stock = p.stock - (new.quantity - old.quantity)
      where p.id = new.product_id
        and p.branch_id = new.branch_id
        and coalesce(p.is_service, false) = false
        and coalesce(p.track_inventory, true) = true;
    else
      update public.products p
        set stock = p.stock + old.quantity
      where p.id = old.product_id
        and p.branch_id = old.branch_id
        and coalesce(p.is_service, false) = false
        and coalesce(p.track_inventory, true) = true;

      update public.products p
        set stock = p.stock - new.quantity
      where p.id = new.product_id
        and p.branch_id = new.branch_id
        and coalesce(p.is_service, false) = false
        and coalesce(p.track_inventory, true) = true;
    end if;
    return new;
  end if;

  if tg_op = 'DELETE' then
    update public.products p
      set stock = p.stock + old.quantity
    where p.id = old.product_id
      and p.branch_id = old.branch_id
      and coalesce(p.is_service, false) = false
      and coalesce(p.track_inventory, true) = true;
    return old;
  end if;

  return null;
end;
$$;

create or replace function public.apply_return_item_stock()
returns trigger
language plpgsql
as $$
begin
  if tg_op = 'INSERT' then
    update public.products p
      set stock = p.stock + new.quantity
    where p.id = new.product_id
      and p.branch_id = new.branch_id
      and coalesce(p.is_service, false) = false
      and coalesce(p.track_inventory, true) = true;
    return new;
  end if;

  if tg_op = 'DELETE' then
    update public.products p
      set stock = p.stock - old.quantity
    where p.id = old.product_id
      and p.branch_id = old.branch_id
      and coalesce(p.is_service, false) = false
      and coalesce(p.track_inventory, true) = true;
    return old;
  end if;

  return null;
end;
$$;

create or replace function public.apply_inventory_movement_stock()
returns trigger
language plpgsql
as $$
declare
  v_signed_qty numeric(14,3);
begin
  if tg_op = 'INSERT' then
    v_signed_qty := case new.movement_type
      when 'adjustment_in'  then  new.quantity
      when 'transfer_in'    then  new.quantity
      when 'opening'        then  new.quantity
      when 'recount'        then  new.quantity
      when 'waste'          then -new.quantity
      when 'breakage'       then -new.quantity
      when 'expired'        then -new.quantity
      when 'kitchen_return' then -new.quantity
      when 'adjustment_out' then -new.quantity
      when 'transfer_out'   then -new.quantity
    end;

    update public.products p
      set stock = p.stock + v_signed_qty
    where p.id = new.product_id
      and p.branch_id = new.branch_id
      and coalesce(p.is_service, false) = false
      and coalesce(p.track_inventory, true) = true;

    return new;
  end if;

  if tg_op = 'DELETE' then
    -- Revertir efecto al borrar
    v_signed_qty := case old.movement_type
      when 'adjustment_in'  then -old.quantity
      when 'transfer_in'    then -old.quantity
      when 'opening'        then -old.quantity
      when 'recount'        then -old.quantity
      when 'waste'          then  old.quantity
      when 'breakage'       then  old.quantity
      when 'expired'        then  old.quantity
      when 'kitchen_return' then  old.quantity
      when 'adjustment_out' then  old.quantity
      when 'transfer_out'   then  old.quantity
    end;

    update public.products p
      set stock = p.stock + v_signed_qty
    where p.id = old.product_id
      and p.branch_id = old.branch_id
      and coalesce(p.is_service, false) = false
      and coalesce(p.track_inventory, true) = true;

    return old;
  end if;

  return null;
end;
$$;

-- ============================================================================
-- 2) Backfill — sanear los servicios ya existentes
-- ============================================================================
-- Un servicio no lleva inventario: se le apaga track_inventory y se le limpia
-- el stock que los triggers viejos le dejaron (típicamente negativo).

update public.products
   set track_inventory = false
 where coalesce(is_service, false) = true
   and track_inventory is distinct from false;

update public.products
   set stock = 0,
       min_stock = 0
 where coalesce(is_service, false) = true
   and (stock <> 0 or min_stock <> 0);

-- ============================================================================
-- 3) Vistas de bajo stock — excluir servicios
-- ============================================================================

create or replace view public.inventory_low_stock_view
with (security_invoker = true)
as
select
  p.id,
  p.branch_id,
  b.code as branch_code,
  b.name as branch_name,
  p.sku,
  p.barcode,
  p.name,
  p.stock,
  p.min_stock,
  p.price,
  p.is_active,
  (p.stock <= p.min_stock) as is_low_stock
from public.products p
join public.branches b on b.id = p.branch_id
where public.has_branch_access(p.branch_id)
  and p.is_active
  and p.stock <= p.min_stock
  and coalesce(p.is_service, false) = false
  and coalesce(p.track_inventory, true) = true
order by p.stock asc, p.name asc;

create or replace view public.report_inventory_status_view
with (security_invoker = true)
as
select
  p.branch_id,
  p.id as product_id,
  p.name,
  p.sku,
  p.barcode,
  p.category_id,
  pc.name as category_name,
  p.stock,
  p.min_stock,
  p.cost,
  p.price,
  (p.stock * p.cost)::numeric(14,2) as inventory_value,
  case when p.stock <= p.min_stock and p.min_stock > 0 then true else false end
    as is_low_stock,
  case when p.stock <= 0 then true else false end as is_out_of_stock,
  p.is_active,
  p.updated_at
from public.products p
left join public.product_categories pc
  on pc.id = p.category_id and pc.branch_id = p.branch_id
where p.is_active = true
  and public.has_branch_access(p.branch_id)
  and coalesce(p.is_service, false) = false
  and coalesce(p.track_inventory, true) = true;

grant select on public.inventory_low_stock_view to authenticated;
grant select on public.report_inventory_status_view to authenticated;

commit;

notify pgrst, 'reload schema';
