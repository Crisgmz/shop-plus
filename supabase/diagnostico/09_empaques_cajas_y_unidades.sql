-- ============================================================================
-- Configurar CAJA → PAQUETE → UNIDAD para el negocio
-- 3db1bc8d-011a-4b25-b132-eeb264e27777, según su hoja de inventario semanal.
--
--   Vasos    : 20 paq × 50 und  = 1,000 unidades por caja
--   Tapas    : 10 paq × 100 und = 1,000 unidades por caja
--   Sorbetes : 20 paq × 100 und = 2,000 unidades por caja
--
-- Requiere la migración 86 (columnas de empaque en `products`).
--
-- PASO 0 y PASO 1 son SOLO LECTURA: dicen qué hay antes de tocar nada.
-- El PASO 2 va dentro de una transacción que TERMINA EN ROLLBACK: se corre, se
-- mira el resultado y recién ahí se cambia la última línea a `commit;`.
--
-- Regla de seguridad del PASO 2: solo configura los modelos que coinciden con
-- UN SOLO producto. Si un modelo tiene dos (el clásico "uno por caja" y "uno
-- por unidad"), lo deja intacto: fusionarlos es una decisión de datos, no algo
-- que deba hacer un script a ciegas.
--
-- NO toca stock ni precios. Ver PASO 3 al final.
-- ============================================================================

-- ── PASO 0 — ¿ese id es la empresa o una sucursal? ──────────────────────────
select 'es una empresa'             as que, count(*) as filas
  from public.companies where id = '3db1bc8d-011a-4b25-b132-eeb264e27777'
union all
select 'es una sucursal',            count(*)
  from public.branches  where id = '3db1bc8d-011a-4b25-b132-eeb264e27777'
union all
select 'sucursales de esa empresa',  count(*)
  from public.branches  where company_id = '3db1bc8d-011a-4b25-b132-eeb264e27777';


-- ── PASO 1 — Qué producto existe para cada modelo de la hoja ────────────────
with alcance as (
  select b.id, b.name as sucursal
    from public.branches b
   where b.id = '3db1bc8d-011a-4b25-b132-eeb264e27777'
      or b.company_id = '3db1bc8d-011a-4b25-b132-eeb264e27777'
),
hoja(modelo, und_por_paq, paq_por_caja, und_por_caja, cajas_hoja) as (values
  ('VASO PET 9 OZ',                50, 20, 1000, 65),
  ('VASO PET 12 OZ',               50, 20, 1000, 59),
  ('VASO PET 12 OZ TIPO U',        50, 20, 1000, 50),
  ('VASO PET 16 OZ',               50, 20, 1000, 37),
  ('VASO PET 16 OZ ALTO',          50, 20, 1000, 51),
  ('VASO PET 16 OZ TIPO U',        50, 20, 1000, 23),
  ('VASO CAFÉ 8 OZ BLANCO',        50, 20, 1000,  4),
  ('TAPAS PLANAS 9 OZ S/H',       100, 10, 1000, 15),
  ('TAPAS DOMO 9 OZ S/H',         100, 10, 1000, 15),
  ('TAPAS PLANAS 12 OZ C/H',      100, 10, 1000, 75),
  ('TAPAS DOMO 12 OZ C/H',        100, 10, 1000, 45),
  ('TAPAS SIPPER 12 OZ',          100, 10, 1000, 39),
  ('TAPAS PLANAS 16 OZ C/H',      100, 10, 1000, 45),
  ('TAPAS DOMO 16 OZ S/H',        100, 10, 1000, 14),
  ('TAPAS DOMO 16 OZ C/H',        100, 10, 1000, 36),
  ('TAPAS SIPPER 16 OZ',          100, 10, 1000, 48),
  ('TAPAS VASO CAFÉ 8 OZ NEGRA',  100, 10, 1000,  4),
  ('SORBETE 12/190MM',            100, 20, 2000, 20),
  ('SORBETE 12/230MM',            100, 20, 2000, 18)
)
select
  h.modelo,
  h.und_por_caja                          as und_por_caja,
  h.cajas_hoja                            as cajas_en_la_hoja,
  count(p.id)                             as productos_con_ese_nombre,
  coalesce(
    string_agg(
      coalesce(p.sku, 'sin SKU')
        || ' · precio ' || to_char(p.price, 'FM999G999D00')
        || ' · stock '  || to_char(p.stock, 'FM999G999D999')
        || case when p.units_per_pack is null then '' else ' · YA configurado' end
        || case when p.is_active then '' else ' · INACTIVO' end,
      E'\n' order by p.price desc),
    '— NO EXISTE ESE PRODUCTO —')         as encontrados
from hoja h
left join public.products p
       on p.branch_id in (select id from alcance)
      and upper(btrim(p.name)) = upper(btrim(h.modelo))
group by h.modelo, h.und_por_caja, h.cajas_hoja
order by h.modelo;


-- ── PASO 1b — Plan de unificación, par por par (SOLO LECTURA) ───────────────
-- Cada modelo tiene hoy DOS productos: uno que se vende por caja (precio alto,
-- stock en cajas) y otro por unidad (precio bajo, stock en unidades). Esta
-- consulta los pone lado a lado con lo que quedaría al unificarlos.
with alcance as (
  select b.id from public.branches b
   where b.id = '3db1bc8d-011a-4b25-b132-eeb264e27777'
      or b.company_id = '3db1bc8d-011a-4b25-b132-eeb264e27777'
),
hoja(modelo, und_por_paq, paq_por_caja, und_por_caja, cajas_hoja) as (values
  ('VASO PET 9 OZ',                50, 20, 1000, 65),
  ('VASO PET 12 OZ',               50, 20, 1000, 59),
  ('VASO PET 12 OZ TIPO U',        50, 20, 1000, 50),
  ('VASO PET 16 OZ',               50, 20, 1000, 37),
  ('VASO PET 16 OZ ALTO',          50, 20, 1000, 51),
  ('VASO PET 16 OZ TIPO U',        50, 20, 1000, 23),
  ('VASO CAFÉ 8 OZ BLANCO',        50, 20, 1000,  4),
  ('TAPAS PLANAS 9 OZ S/H',       100, 10, 1000, 15),
  ('TAPAS DOMO 9 OZ S/H',         100, 10, 1000, 15),
  ('TAPAS PLANAS 12 OZ C/H',      100, 10, 1000, 75),
  ('TAPAS DOMO 12 OZ C/H',        100, 10, 1000, 45),
  ('TAPAS SIPPER 12 OZ',          100, 10, 1000, 39),
  ('TAPAS PLANAS 16 OZ C/H',      100, 10, 1000, 45),
  ('TAPAS DOMO 16 OZ S/H',        100, 10, 1000, 14),
  ('TAPAS DOMO 16 OZ C/H',        100, 10, 1000, 36),
  ('TAPAS SIPPER 16 OZ',          100, 10, 1000, 48),
  ('TAPAS VASO CAFÉ 8 OZ NEGRA',  100, 10, 1000,  4),
  ('SORBETE 12/190MM',            100, 20, 2000, 20),
  ('SORBETE 12/230MM',            100, 20, 2000, 18)
),
pares as (
  -- El de precio más alto es el de CAJA; el otro, el de UNIDAD.
  select h.modelo, h.und_por_caja, h.cajas_hoja, h.und_por_paq, h.paq_por_caja,
         p.id, p.sku, p.price, p.stock, p.units_per_pack,
         row_number() over (partition by h.modelo order by p.price desc) as rn
    from hoja h
    join public.products p
      on p.branch_id in (select id from alcance)
     and upper(btrim(p.name)) = upper(btrim(h.modelo))
)
select
  modelo,
  und_por_caja,
  max(case when rn = 1 then sku end)                      as sku_caja,
  max(case when rn = 1 then price end)                    as precio_caja,
  round(max(case when rn = 1 then price end)
        / und_por_caja, 4)                                as precio_x_unidad_en_caja,
  max(case when rn = 1 then stock end)                    as stock_producto_caja,
  max(case when rn = 2 then sku end)                      as sku_unidad,
  max(case when rn = 2 then price end)                    as precio_unidad,
  max(case when rn = 2 then stock end)                    as stock_producto_unidad,
  cajas_hoja                                              as cajas_en_la_hoja,
  cajas_hoja * und_por_caja                               as unidades_segun_la_hoja,
  case when bool_or(rn = 1 and units_per_pack is not null)
       then '⚠ el producto CAJA ya tiene empaque configurado' else '' end as revisar
from pares
group by modelo, und_por_caja, cajas_hoja, und_por_paq, paq_por_caja
order by modelo;


-- ── PASO 2 — Configurar el empaque (transacción con ROLLBACK) ───────────────
begin;

with alcance as (
  select b.id from public.branches b
   where b.id = '3db1bc8d-011a-4b25-b132-eeb264e27777'
      or b.company_id = '3db1bc8d-011a-4b25-b132-eeb264e27777'
),
hoja(modelo, und_por_paq, paq_por_caja) as (values
  ('VASO PET 9 OZ',                50, 20),
  ('VASO PET 12 OZ',               50, 20),
  ('VASO PET 12 OZ TIPO U',        50, 20),
  ('VASO PET 16 OZ',               50, 20),
  ('VASO PET 16 OZ ALTO',          50, 20),
  ('VASO PET 16 OZ TIPO U',        50, 20),
  ('VASO CAFÉ 8 OZ BLANCO',        50, 20),
  ('TAPAS PLANAS 9 OZ S/H',       100, 10),
  ('TAPAS DOMO 9 OZ S/H',         100, 10),
  ('TAPAS PLANAS 12 OZ C/H',      100, 10),
  ('TAPAS DOMO 12 OZ C/H',        100, 10),
  ('TAPAS SIPPER 12 OZ',          100, 10),
  ('TAPAS PLANAS 16 OZ C/H',      100, 10),
  ('TAPAS DOMO 16 OZ S/H',        100, 10),
  ('TAPAS DOMO 16 OZ C/H',        100, 10),
  ('TAPAS SIPPER 16 OZ',          100, 10),
  ('TAPAS VASO CAFÉ 8 OZ NEGRA',  100, 10),
  ('SORBETE 12/190MM',            100, 20),
  ('SORBETE 12/230MM',            100, 20)
),
unicos as (
  -- Solo los modelos con UN producto: si hay dos, se deja para decidir a mano.
  -- `array_agg(...)[1]` y no `min()`: Postgres no tiene min() para uuid.
  select h.und_por_paq, h.paq_por_caja, (array_agg(p.id))[1] as product_id
    from hoja h
    join public.products p
      on p.branch_id in (select id from alcance)
     and upper(btrim(p.name)) = upper(btrim(h.modelo))
   group by h.modelo, h.und_por_paq, h.paq_por_caja
  having count(*) = 1
)
update public.products p
   set units_per_pack = u.und_por_paq,
       packs_per_box  = u.paq_por_caja,
       unit_label     = 'Unidad',
       pack_label     = 'Paquete',
       box_label      = 'Caja'
  from unicos u
 where p.id = u.product_id;

-- Verificación: así queda cada producto configurado.
select
  p.name,
  p.units_per_pack                        as und_por_paquete,
  p.packs_per_box                         as paq_por_caja,
  -- `packs_per_box` nulo = dos niveles (caja → unidad base), no tres.
  p.units_per_pack * coalesce(p.packs_per_box, 1) as und_por_caja,
  p.stock                                        as stock_en_unidades,
  floor(p.stock / (p.units_per_pack * coalesce(p.packs_per_box, 1)))
                                                 as cajas_que_mostrara
from public.products p
where p.branch_id in (
        select b.id from public.branches b
         where b.id = '3db1bc8d-011a-4b25-b132-eeb264e27777'
            or b.company_id = '3db1bc8d-011a-4b25-b132-eeb264e27777')
  and p.units_per_pack is not null
order by p.name;

rollback;  -- ← cambiar a `commit;` cuando la verificación se vea bien


-- ── PASO 3 — Stock (NO se corre automático) ─────────────────────────────────
-- El stock de la hoja está en CAJAS y la base lo guarda en UNIDADES. Antes de
-- convertir hay que saber, producto por producto, en qué unidad está hoy: en
-- las capturas hay productos con stock 96 (parecen cajas) junto a otros con
-- 5,000 (parecen unidades). Convertir a ciegas destruiría el inventario.
--
-- Una vez confirmado, por producto:
--
--   update public.products
--      set stock = 75 * 1000        -- cajas de la hoja × unidades por caja
--    where id = '<id del producto>';
