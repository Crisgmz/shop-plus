-- ============================================================================
-- ⚠ REEMPLAZADO POR 11_formato_caja_paquete.sql — NO CORRER ESTE.
--   Correrlo dos veces vuelve a dividir el precio entre los paquetes, y en el
--   editor de Supabase su verificación no se ve. El 11 hace lo mismo, se puede
--   repetir sin daño y no toca lo que ya está convertido.
-- ============================================================================
-- Unificar los pares duplicados y dejar el catálogo en CAJA → PAQUETE
-- Negocio 3db1bc8d-011a-4b25-b132-eeb264e27777 (hoja de inventario semanal).
--
-- Decisiones ya tomadas con el dueño:
--   · Se vende por CAJA y por PAQUETE. Nunca por unidad suelta.
--     => la unidad base del sistema pasa a ser el PAQUETE.
--   · Se queda el producto de caja (SP-001…SP-021); el gemelo se desactiva.
--   · El stock se cuenta como "cajas × paquetes".
--   · El precio de la caja es el que se cobra tal cual (`pack_price`), no el
--     paquete × cuántos trae. Eso lo respeta la migración 92.
--
-- Paquetes por caja, según la hoja:
--   Vasos    : 20 paquetes por caja  (50 vasos cada paquete)
--   Tapas    : 10 paquetes por caja  (100 tapas cada paquete)
--   Sorbetes : 20 paquetes por caja  (100 sorbetes cada paquete)
--
-- Requiere la migración 86 (columnas de empaque) y la 92 (precio por
-- presentación) ya aplicadas.
--
-- PASO A es SOLO LECTURA. PASO B va dentro de una transacción que TERMINA EN
-- `rollback;`: se corre, se lee la verificación del final y recién entonces se
-- cambia esa última línea por `commit;`.
-- ============================================================================


-- ── La hoja, una sola vez ───────────────────────────────────────────────────
-- (Se repite en cada paso porque el editor de Supabase corre sentencias
--  sueltas; un CTE no sobrevive de un bloque al otro.)


-- ── PASO A — Plan par por par (SOLO LECTURA, no cambia nada) ────────────────
with alcance as (
  select b.id from public.branches b
   where b.id = '3db1bc8d-011a-4b25-b132-eeb264e27777'
      or b.company_id = '3db1bc8d-011a-4b25-b132-eeb264e27777'
),
hoja(modelo, paq_por_caja, und_por_paq, cajas_hoja) as (values
  ('VASO PET 9 OZ',               20,  50, 65),
  ('VASO PET 12 OZ',              20,  50, 59),
  ('VASO PET 12 OZ TIPO U',       20,  50, 50),
  ('VASO PET 16 OZ',              20,  50, 37),
  ('VASO PET 16 OZ ALTO',         20,  50, 51),
  ('VASO PET 16 OZ TIPO U',       20,  50, 23),
  ('VASO CAFÉ 8 OZ BLANCO',       20,  50,  4),
  ('TAPAS PLANAS 9 OZ S/H',       10, 100, 15),
  ('TAPAS DOMO 9 OZ S/H',         10, 100, 15),
  ('TAPAS PLANAS 12 OZ C/H',      10, 100, 75),
  ('TAPAS DOMO 12 OZ C/H',        10, 100, 45),
  ('TAPAS SIPPER 12 OZ',          10, 100, 39),
  ('TAPAS PLANAS 16 OZ C/H',      10, 100, 45),
  ('TAPAS DOMO 16 OZ S/H',        10, 100, 14),
  ('TAPAS DOMO 16 OZ C/H',        10, 100, 36),
  ('TAPAS SIPPER 16 OZ',          10, 100, 48),
  ('TAPAS VASO CAFÉ 8 OZ NEGRA',  10, 100,  4),
  ('SORBETE 12/190MM',            20, 100, 20),
  ('SORBETE 12/230MM',            20, 100, 18)
),
pares as (
  -- El de precio más alto de cada par es el de CAJA; el otro, el de unidad.
  select h.*, p.id, p.sku, p.name, p.price, p.cost, p.stock, p.units_per_pack,
         row_number() over (partition by h.modelo order by p.price desc) as rn
    from hoja h
    join public.products p
      on p.branch_id in (select id from alcance)
     and upper(btrim(p.name)) = upper(btrim(h.modelo))
     and p.is_active
)
select
  modelo,
  paq_por_caja                                          as paquetes_x_caja,
  max(case when rn = 1 then sku end)                    as sku_se_queda,
  max(case when rn = 1 then price end)                  as precio_caja_hoy,
  -- Lo que quedará configurado:
  max(case when rn = 1 then price end)                  as nuevo_pack_price,
  round(max(case when rn = 1 then price end)
        / paq_por_caja, 2)                              as nuevo_precio_paquete,
  max(case when rn = 2 then price end)                  as precio_del_gemelo,
  max(case when rn = 2 then sku end)                    as sku_se_desactiva,
  max(case when rn = 1 then stock end)                  as stock_hoy_caja,
  max(case when rn = 2 then stock end)                  as stock_hoy_gemelo,
  cajas_hoja                                            as cajas_en_la_hoja,
  cajas_hoja * paq_por_caja                             as nuevo_stock_paquetes,
  count(*)                                              as productos_encontrados
from pares
group by modelo, paq_por_caja, cajas_hoja
order by modelo;
-- Qué mirar antes de seguir:
--   · `productos_encontrados` = 2 en todos. Si alguno da 1, ese modelo no tiene
--     gemelo y el PASO B igual lo configura (solo que no desactiva nada).
--   · `sku_se_queda` debe ser el SP-0xx que el dueño quiere conservar.
--   · `nuevo_precio_paquete` vs `precio_del_gemelo`: si difieren mucho, el
--     gemelo no se vendía por paquete sino por unidad suelta. Decidir cuál
--     manda ANTES de hacer commit.


-- ── PASO B — Unificar (transacción que termina en ROLLBACK) ─────────────────
begin;

create temporary table _plan on commit drop as
with alcance as (
  select b.id from public.branches b
   where b.id = '3db1bc8d-011a-4b25-b132-eeb264e27777'
      or b.company_id = '3db1bc8d-011a-4b25-b132-eeb264e27777'
),
hoja(modelo, paq_por_caja, und_por_paq, cajas_hoja) as (values
  ('VASO PET 9 OZ',               20,  50, 65),
  ('VASO PET 12 OZ',              20,  50, 59),
  ('VASO PET 12 OZ TIPO U',       20,  50, 50),
  ('VASO PET 16 OZ',              20,  50, 37),
  ('VASO PET 16 OZ ALTO',         20,  50, 51),
  ('VASO PET 16 OZ TIPO U',       20,  50, 23),
  ('VASO CAFÉ 8 OZ BLANCO',       20,  50,  4),
  ('TAPAS PLANAS 9 OZ S/H',       10, 100, 15),
  ('TAPAS DOMO 9 OZ S/H',         10, 100, 15),
  ('TAPAS PLANAS 12 OZ C/H',      10, 100, 75),
  ('TAPAS DOMO 12 OZ C/H',        10, 100, 45),
  ('TAPAS SIPPER 12 OZ',          10, 100, 39),
  ('TAPAS PLANAS 16 OZ C/H',      10, 100, 45),
  ('TAPAS DOMO 16 OZ S/H',        10, 100, 14),
  ('TAPAS DOMO 16 OZ C/H',        10, 100, 36),
  ('TAPAS SIPPER 16 OZ',          10, 100, 48),
  ('TAPAS VASO CAFÉ 8 OZ NEGRA',  10, 100,  4),
  ('SORBETE 12/190MM',            20, 100, 20),
  ('SORBETE 12/230MM',            20, 100, 18)
),
pares as (
  select h.modelo, h.paq_por_caja, h.und_por_paq, h.cajas_hoja,
         p.id, p.branch_id, p.sku, p.price, p.stock,
         row_number() over (partition by h.modelo order by p.price desc) as rn
    from hoja h
    join public.products p
      on p.branch_id in (select id from alcance)
     and upper(btrim(p.name)) = upper(btrim(h.modelo))
     and p.is_active
)
select
  c.modelo,
  c.paq_por_caja,
  c.und_por_paq,
  c.id                              as producto_id,
  c.branch_id,
  c.sku,
  c.stock                           as stock_actual,
  (c.cajas_hoja * c.paq_por_caja)::numeric(14,3) as stock_objetivo,
  g.id                              as gemelo_id,
  g.sku                             as gemelo_sku,
  g.stock                           as gemelo_stock
from      (select * from pares where rn = 1) c
left join (select * from pares where rn = 2) g using (modelo);

-- B.1 — Empaque y precios del producto que se queda.
--   `price`      pasa a ser el precio del PAQUETE (la nueva unidad base)
--   `pack_price` guarda el precio de la CAJA tal como se cobra hoy
--   `cost`       se reparte igual, si estaba cargado
update public.products p
   set units_per_pack = pl.paq_por_caja,
       packs_per_box  = null,
       unit_label     = 'Paquete',
       pack_label     = 'Caja',
       box_label      = null,
       min_unit_qty   = null,
       pack_price     = p.price,
       price          = round(p.price / pl.paq_por_caja, 2),
       cost           = round(p.cost  / pl.paq_por_caja, 2)
  from _plan pl
 where p.id = pl.producto_id;

-- B.2 — Los niveles de precio también estaban por caja: se rebajan al paquete.
--   Dinámico porque price_tier_4..10 solo existen si corrió la migración 32.
do $$
declare
  v_col text;
  v_n   int;
begin
  for v_n in 1..10 loop
    v_col := 'price_tier_' || v_n;
    if exists (
      select 1 from information_schema.columns
       where table_schema = 'public' and table_name = 'products'
         and column_name = v_col
    ) then
      execute format(
        'update public.products p
            set %I = round(p.%I / pl.paq_por_caja, 2)
           from _plan pl
          where p.id = pl.producto_id and p.%I is not null',
        v_col, v_col, v_col);
    end if;
  end loop;
end $$;

-- B.3 — Stock del producto que se queda: llevarlo a "cajas de la hoja ×
--   paquetes por caja". Se hace con un movimiento firmado, no con un update
--   directo, para que quede en el kardex quién lo movió y por qué.
insert into public.inventory_movements
  (branch_id, product_id, movement_type, quantity, reason, reference_type)
select pl.branch_id,
       pl.producto_id,
       case when pl.stock_objetivo > pl.stock_actual
            then 'adjustment_in'::public.inventory_movement_type
            else 'adjustment_out'::public.inventory_movement_type end,
       abs(pl.stock_objetivo - pl.stock_actual),
       'Recuento semanal: se reexpresa el inventario en paquetes (caja × paquetes)',
       'unificacion_empaque'
  from _plan pl
 where pl.stock_objetivo <> pl.stock_actual;

-- B.4 — El gemelo: bajar su stock a cero (si no, el inventario queda contado
--   dos veces) y desactivarlo. No se borra: tiene historial de ventas.
insert into public.inventory_movements
  (branch_id, product_id, movement_type, quantity, reason, reference_type)
select pl.branch_id,
       pl.gemelo_id,
       'adjustment_out'::public.inventory_movement_type,
       pl.gemelo_stock,
       'Producto unificado con ' || pl.sku || ': su existencia pasa a ese código',
       'unificacion_empaque'
  from _plan pl
 where pl.gemelo_id is not null
   and pl.gemelo_stock > 0;

update public.products p
   set is_active = false
  from _plan pl
 where p.id = pl.gemelo_id;

-- ── Verificación: esto es lo que hay que leer antes de decidir ──────────────
select
  pl.modelo,
  p.sku,
  p.price                                   as precio_paquete,
  p.pack_price                              as precio_caja,
  p.units_per_pack                          as paquetes_x_caja,
  p.unit_label, p.pack_label,
  p.stock                                   as stock_en_paquetes,
  floor(p.stock / p.units_per_pack)         as equivale_a_cajas,
  (p.stock % p.units_per_pack)              as y_paquetes_sueltos,
  pl.gemelo_sku,
  (select is_active from public.products g where g.id = pl.gemelo_id)
                                            as gemelo_sigue_activo,
  (select stock     from public.products g where g.id = pl.gemelo_id)
                                            as gemelo_stock_final
from _plan pl
join public.products p on p.id = pl.producto_id
order by pl.modelo;

-- Y el total del inventario a precio de venta, para comparar con lo de antes:
select round(sum(p.stock * p.price), 2) as inventario_a_precio_venta,
       round(sum(p.stock * p.cost), 2)  as inventario_a_costo
  from _plan pl join public.products p on p.id = pl.producto_id;

rollback;  -- ← cambiar por `commit;` cuando la verificación se vea bien


-- ── PASO C — Después del commit, en la app ─────────────────────────────────
--   1. Inventario → cada producto debe mostrar Presentación "Caja",
--      "Paquetes por caja" y "Precio de la caja".
--   2. POS → al agregar uno, entra como "1 Caja" al precio de caja; el chip
--      de presentación permite bajarlo a "Paquete".
--   3. Vender 1 caja descuenta `paquetes_x_caja` del stock; vender 3 paquetes
--      descuenta 3.
