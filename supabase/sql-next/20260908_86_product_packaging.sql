-- ============================================================================
-- 20260908_86_product_packaging.sql
--
-- EMPAQUES — vender el mismo producto por caja, por paquete o por unidad.
--
-- Caso real: una caja de vasos trae 40 paquetes y cada paquete trae N vasos.
-- Se vende la caja completa, el paquete suelto o el vaso. Al vender 10
-- paquetes de un stock de 200 cajas, deben quedar 199 cajas + 30 paquetes.
--
-- DECISIÓN CENTRAL: `products.stock` guarda SIEMPRE la unidad más pequeña.
-- Cajas y paquetes son una VISTA derivada, no columnas aparte:
--
--     unidades_por_caja = units_per_pack × packs_per_box
--     cajas    = floor(stock / unidades_por_caja)
--     resto    = stock % unidades_por_caja
--     paquetes = floor(resto / units_per_pack)
--     unidades = resto % units_per_pack
--
-- Así es imposible que las tres cifras se desincronicen, y el trigger de stock
-- sigue restando `quantity` plano sin enterarse: la línea de venta viaja con
-- la cantidad YA convertida a unidades base (1 caja = 1000 vasos).
--
-- POR QUÉ ESTA MIGRACIÓN NO TOCA NINGUNA FUNCIÓN:
-- Esta base la comparten dos árboles del mismo repo (shop-plus y
-- flutter_shop+) y 30 empresas. Reemplazar `checkout_sale_transactional` o el
-- trigger de stock fue exactamente lo que rompió cosas a fin de agosto. Aquí
-- solo se AGREGAN columnas con default nulo:
--
--   · `units_per_pack IS NULL`  ⇒  el producto se comporta EXACTAMENTE como
--     hoy. Los 30 negocios y el otro app no notan ningún cambio.
--   · La conversión y el redondeo de centavos los resuelve la app usando el
--     descuento por línea que ya existe (migración 83).
--
-- Ejecutar en el SQL Editor de Supabase. Idempotente.
-- ============================================================================

begin;

-- ── 1) Configuración de empaque, por producto ──────────────────────────────
alter table public.products
  -- Cuántas unidades base trae un paquete. NULL = producto sin empaque.
  add column if not exists units_per_pack numeric(14,3),
  -- Cuántos paquetes trae una caja. NULL = solo dos niveles (paquete/unidad).
  add column if not exists packs_per_box  numeric(14,3),
  -- Nombres que ve el cajero. Se guardan aparte de `sale_unit` para que el
  -- otro app no los pise al guardar un producto.
  add column if not exists unit_label text,
  add column if not exists pack_label text,
  add column if not exists box_label  text,
  -- Precios de venta por presentación. NULL = no se vende así.
  add column if not exists pack_price numeric(14,2),
  add column if not exists box_price  numeric(14,2),
  -- Mínimo al vender SUELTO (en unidades base). El POS lo bloquea; vender una
  -- caja o un paquete completo nunca se bloquea por esto.
  add column if not exists min_unit_qty numeric(14,3);

comment on column public.products.units_per_pack is
  'Unidades base por paquete. NULL = producto sin empaque (comportamiento histórico).';
comment on column public.products.packs_per_box is
  'Paquetes por caja. NULL = solo dos niveles.';
comment on column public.products.min_unit_qty is
  'Mínimo de unidades base al vender suelto. No aplica a paquete o caja completos.';

-- Cantidades de empaque siempre positivas si están definidas.
do $c$
begin
  if not exists (select 1 from pg_constraint
                  where conname = 'products_units_per_pack_positive') then
    alter table public.products
      add constraint products_units_per_pack_positive
      check (units_per_pack is null or units_per_pack > 0) not valid;
  end if;
  if not exists (select 1 from pg_constraint
                  where conname = 'products_packs_per_box_positive') then
    alter table public.products
      add constraint products_packs_per_box_positive
      check (packs_per_box is null or packs_per_box > 0) not valid;
  end if;
end
$c$;


-- ── 2) Cómo se vendió / se compró cada línea ───────────────────────────────
-- `quantity` sigue siendo la cantidad en UNIDADES BASE (por eso el trigger de
-- stock no cambia). Estas dos columnas solo describen la presentación, para
-- que la factura diga "1 Caja" y no "1000".
alter table public.sale_items
  add column if not exists uom text not null default 'unit',
  add column if not exists uom_factor numeric(14,3) not null default 1;

alter table public.purchase_items
  add column if not exists uom text not null default 'unit',
  add column if not exists uom_factor numeric(14,3) not null default 1;

comment on column public.sale_items.uom is
  'Presentación vendida: unit | pack | box. `quantity` va siempre en unidades base.';
comment on column public.sale_items.uom_factor is
  'Unidades base que representa una de esas presentaciones (1 caja = 1000).';

do $c$
begin
  if not exists (select 1 from pg_constraint where conname = 'sale_items_uom_valid') then
    alter table public.sale_items
      add constraint sale_items_uom_valid
      check (uom in ('unit', 'pack', 'box')) not valid;
  end if;
  if not exists (select 1 from pg_constraint where conname = 'purchase_items_uom_valid') then
    alter table public.purchase_items
      add constraint purchase_items_uom_valid
      check (uom in ('unit', 'pack', 'box')) not valid;
  end if;
end
$c$;

commit;

notify pgrst, 'reload schema';


-- ============================================================================
-- VERIFICACIÓN — debe devolver 11 filas.
-- ============================================================================
select table_name, column_name, data_type
from information_schema.columns
where table_schema = 'public'
  and (
    (table_name = 'products' and column_name in
      ('units_per_pack','packs_per_box','unit_label','pack_label','box_label',
       'pack_price','box_price','min_unit_qty'))
    or (table_name in ('sale_items','purchase_items') and column_name = 'uom')
  )
order by table_name, column_name;
