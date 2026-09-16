-- ============================================================================
-- Dejar TODOS los productos de la hoja en formato CAJA → PAQUETE
-- Negocio 3db1bc8d-011a-4b25-b132-eeb264e27777 (hoja de inventario semanal).
--
-- Reemplaza al 10. Aquel tenía dos problemas:
--   · Su verificación iba antes del `rollback;`, y el editor de Supabase solo
--     muestra la ÚLTIMA sentencia: no se veía nada y no se aplicaba nada.
--   · Correrlo dos veces volvía a dividir el precio entre los paquetes.
--
-- Este lee cómo está HOY cada producto y decide solo:
--   · ya está en caja/paquete        → no se toca (ni precio ni stock)
--   · solo unidades, o empaque viejo → se convierte
--   · algo que no cuadra             → NO se toca y se dice por qué
-- Se puede correr las veces que haga falta.
--
-- Decisiones del dueño (sesión del 16/09/2026):
--   · Se vende por CAJA y por PAQUETE, nunca por unidad suelta
--     ⇒ la unidad base del sistema es el PAQUETE.
--   · Se queda el producto de caja; el gemelo por unidad se desactiva.
--   · Stock = cajas de la hoja × paquetes por caja.
--   · La caja se cobra a su precio (`pack_price`); el paquete suelto va a
--     precio de mayoreo = caja ÷ paquetes (confirmado tras ver la vista previa).
--   · VASO CAFÉ 12 OZ BLANCO y TAPAS VASO CAFÉ 12 OZ NEGRA, que no están en la
--     hoja, van con el empaque de sus pares de 8 oz y stock 0.
--
-- Requiere las migraciones 86 (columnas de empaque) y 92 (precio por
-- presentación).
--
-- ── CÓMO SE USA ─────────────────────────────────────────────────────────────
--   1. Pegue TODO el archivo en el SQL Editor y dele Run tal como está.
--      `aplicar` viene en `false`: no cambia nada, y la tabla que sale muestra
--      producto por producto qué hay hoy y cómo va a quedar.
--   2. Si se ve bien, cambie `false` por `true` en la línea marcada con ◀◀◀
--      y dele Run otra vez. La tabla ahora muestra cómo QUEDÓ.
--   Si el editor avisa de una "operación destructiva", es por el
--   `drop table if exists pg_temp._plan`: una tabla temporal de este mismo
--   script. Se puede continuar.
-- ============================================================================

begin;

drop table if exists pg_temp._plan;

create temporary table _plan as
with
config(aplicar) as (values
  (false)   -- ◀◀◀  false = solo mirar  ·  true = APLICAR
),

-- La hoja: paquetes por caja, unidades por paquete (informativo) y cajas
-- contadas el 11/9/26.
hoja(orden, modelo, paq_por_caja, und_por_paq, cajas_hoja) as (values
  ( 1, 'VASO PET 9 OZ',              20,  50, 65),
  ( 2, 'VASO PET 12 OZ',             20,  50, 59),
  ( 3, 'VASO PET 12 OZ TIPO U',      20,  50, 50),
  ( 4, 'VASO PET 16 OZ',             20,  50, 37),
  ( 5, 'VASO PET 16 OZ ALTO',        20,  50, 51),
  ( 6, 'VASO PET 16 OZ TIPO U',      20,  50, 23),
  ( 7, 'VASO CAFÉ 8 OZ BLANCO',      20,  50,  4),
  ( 8, 'TAPAS PLANAS 9 OZ S/H',      10, 100, 15),
  ( 9, 'TAPAS DOMO 9 OZ S/H',        10, 100, 15),
  (10, 'TAPAS PLANAS 12 OZ C/H',     10, 100, 75),
  (11, 'TAPAS DOMO 12 OZ C/H',       10, 100, 45),
  (12, 'TAPAS SIPPER 12 OZ',         10, 100, 39),
  (13, 'TAPAS PLANAS 16 OZ C/H',     10, 100, 45),
  (14, 'TAPAS DOMO 16 OZ S/H',       10, 100, 14),
  (15, 'TAPAS DOMO 16 OZ C/H',       10, 100, 36),
  (16, 'TAPAS SIPPER 16 OZ',         10, 100, 48),
  (17, 'TAPAS VASO CAFÉ 8 OZ NEGRA', 10, 100,  4),
  (18, 'SORBETE 12/190MM',           20, 100, 20),
  (19, 'SORBETE 12/230MM',           20, 100, 18),
  -- No están en la hoja. El dueño decidió: mismo empaque que los de 8 oz y
  -- 0 cajas (el producto de caja ya tenía 0; los 5,000 del gemelo no eran un
  -- conteo real).
  (20, 'VASO CAFÉ 12 OZ BLANCO',      20,  50,  0),
  (21, 'TAPAS VASO CAFÉ 12 OZ NEGRA', 10, 100,  0)
),

alcance as (
  select b.id from public.branches b
   where b.id = '3db1bc8d-011a-4b25-b132-eeb264e27777'
      or b.company_id = '3db1bc8d-011a-4b25-b132-eeb264e27777'
),

-- El nombre se compara sin tildes, espacios ni signos: "Vaso Cafe 8oz blanco"
-- y "VASO CAFÉ 8 OZ BLANCO" son el mismo modelo.
hoja_c as (
  select h.*,
         upper(regexp_replace(
           translate(h.modelo, 'áéíóúüñÁÉÍÓÚÜÑ', 'aeiouunAEIOUUN'),
           '[^A-Za-z0-9]+', '', 'g')) as clave
    from hoja h
),
prod as (
  select p.*,
         upper(regexp_replace(
           translate(coalesce(p.name, ''), 'áéíóúüñÁÉÍÓÚÜÑ', 'aeiouunAEIOUUN'),
           '[^A-Za-z0-9]+', '', 'g')) as clave
    from public.products p
   where p.branch_id in (select id from alcance)
),

cand0 as (
  select h.orden, h.modelo, h.paq_por_caja, h.und_por_paq, h.cajas_hoja,
         p.id, p.branch_id, p.sku, p.name, p.is_active, p.price, p.cost,
         p.pack_price, p.units_per_pack, p.packs_per_box, p.unit_label,
         p.pack_label, p.stock, p.min_stock,
         coalesce(p.units_per_pack = h.paq_por_caja
                  and p.packs_per_box is null
                  and lower(btrim(p.unit_label)) = 'paquete'
                  and lower(btrim(p.pack_label)) = 'caja'
                  and p.pack_price > 0, false) as listo
    from hoja_c h
    join prod p on p.clave = h.clave
),
-- El que se queda: primero el activo, luego el que ya está en formato, luego
-- el de precio más alto (el de caja). Los demás son gemelos.
cand as (
  select c.*,
         row_number() over (
           partition by c.branch_id, c.orden
           order by c.is_active desc, c.listo desc, c.price desc, c.sku
         ) as rn
    from cand0 c
),
-- Precio por unidad del gemelo: sirve para detectar precios que no son de caja.
gem as (
  select branch_id, orden,
         max(price) filter (where units_per_pack is null) as precio_unidad_gemelo
    from cand
   where rn > 1
   group by branch_id, orden
),
princ as (
  select c.*, g.precio_unidad_gemelo,
         case
           when not c.is_active then
             'todos los productos de este modelo están inactivos'
           -- Precio de caja por debajo de 1/10 de lo que valen sus unidades al
           -- precio del gemelo: ese número es de paquete, no de caja.
           when c.listo and g.precio_unidad_gemelo > 0
                and c.pack_price * 10
                    < g.precio_unidad_gemelo * c.und_por_paq * c.paq_por_caja then
             'ya está en caja/paquete, pero el precio de caja parece de paquete (¿se convirtió dos veces?)'
           when c.listo then null
           when coalesce(c.pack_price, 0) > 0 then
             'tiene un precio de presentación propio con otro empaque'
           when coalesce(c.price, 0) <= 0 then
             'no tiene precio'
           when g.precio_unidad_gemelo > 0
                and c.price * 10
                    < g.precio_unidad_gemelo * c.und_por_paq * c.paq_por_caja then
             'su precio no parece de caja (es muy bajo al lado del de unidad)'
           when g.precio_unidad_gemelo is null
                and c.units_per_pack = c.paq_por_caja then
             'ya dice ' || c.paq_por_caja || ' paquetes por caja pero sin precio de caja: no se sabe si el precio es de caja o de paquete'
         end as motivo
    from cand c
    left join gem g using (branch_id, orden)
   where c.rn = 1
)

-- 1) El producto que se queda
select (select aplicar from config) as aplicar,
       pr.orden, 1 as sub, pr.modelo, pr.paq_por_caja, pr.und_por_paq,
       pr.cajas_hoja, pr.id, pr.branch_id, pr.sku, pr.name as nombre,
       'se queda'::text as papel,
       case when pr.motivo is not null then 'revisar'
            when pr.listo then 'listo'
            else 'convertir' end as accion,
       pr.motivo,
       pr.precio_unidad_gemelo,
       pr.is_active as activo_hoy, pr.price as precio_hoy,
       pr.pack_price as precio_caja_hoy, pr.units_per_pack as empaque_hoy,
       pr.unit_label as unidad_hoy, pr.stock as stock_hoy,
       -- Cómo queda. Lo que no se convierte conserva sus valores.
       case when pr.motivo is null and not pr.listo
            then pr.price else pr.pack_price end                 as precio_caja,
       case when pr.motivo is null and not pr.listo
            then round(pr.price / pr.paq_por_caja, 2)
            else pr.price end                                    as precio_paquete,
       case when pr.motivo is null and not pr.listo
            then round(pr.cost / pr.paq_por_caja, 2)
            else pr.cost end                                     as costo,
       case when pr.motivo is null and not pr.listo
            then (pr.cajas_hoja * pr.paq_por_caja)::numeric(14,3)
            else pr.stock end                                    as stock_nuevo,
       case when pr.motivo is null and not pr.listo
            then pr.min_stock * pr.paq_por_caja
            else pr.min_stock end                                as min_stock_nuevo,
       case when pr.motivo is null and not pr.listo
            then pr.paq_por_caja
            else pr.units_per_pack end                           as empaque_nuevo,
       pr.is_active                                              as activo_nuevo
  from princ pr

union all

-- 2) Los gemelos: se deciden junto con su producto principal.
select (select aplicar from config),
       g.orden, 2, g.modelo, g.paq_por_caja, g.und_por_paq, g.cajas_hoja,
       g.id, g.branch_id, g.sku, g.name,
       'gemelo',
       case when pr.motivo is not null then 'revisar'
            when g.is_active or g.stock <> 0 then 'desactivar'
            else 'ya desactivado' end,
       case when pr.motivo is not null
            then 'se decide junto con ' || coalesce(pr.sku, pr.name) end,
       null,
       g.is_active, g.price, g.pack_price, g.units_per_pack, g.unit_label, g.stock,
       g.pack_price, g.price, g.cost,
       case when pr.motivo is null then 0::numeric(14,3) else g.stock end,
       g.min_stock, g.units_per_pack,
       case when pr.motivo is null then false else g.is_active end
  from cand g
  join princ pr using (branch_id, orden)
 where g.rn > 1

union all

-- 3) Modelos de la hoja sin ningún producto.
select (select aplicar from config),
       h.orden, 1, h.modelo, h.paq_por_caja, h.und_por_paq, h.cajas_hoja,
       null, null, null, null,
       '—', 'no existe', null, null,
       null, null, null, null, null, null,
       null, null, null, null, null, null, null
  from hoja_c h
 where not exists (select 1 from cand c where c.orden = h.orden)

union all

-- 4) Productos activos del negocio que no están en la hoja: no se tocan, pero
--    se listan para ver si alguno es un modelo de la hoja con otro nombre.
select (select aplicar from config),
       null, 3, null, null, null, null,
       p.id, p.branch_id, p.sku, p.name,
       '—', 'fuera de la hoja', null, null,
       p.is_active, p.price, p.pack_price, p.units_per_pack, p.unit_label, p.stock,
       p.pack_price, p.price, p.cost, p.stock, p.min_stock, p.units_per_pack,
       p.is_active
  from prod p
 where p.is_active
   and not coalesce(p.is_service, false)
   and p.clave not in (select clave from hoja_c);


-- ── A) Stock: movimiento firmado por la diferencia ─────────────────────────
-- No es un `update` directo: el trigger de `inventory_movements` suma el delta
-- y queda en el kardex quién lo movió y por qué.
insert into public.inventory_movements
  (branch_id, product_id, movement_type, quantity, reason, reference_type)
select pl.branch_id,
       pl.id,
       (case when pl.stock_nuevo > pl.stock_hoy
             then 'adjustment_in' else 'adjustment_out' end
       )::public.inventory_movement_type,
       abs(pl.stock_nuevo - pl.stock_hoy),
       case pl.accion
         when 'convertir' then
           'Formato caja/paquete: recuento de la hoja, '
           || pl.cajas_hoja || ' cajas × ' || pl.paq_por_caja || ' paquetes'
         else
           'Gemelo por unidad desactivado: su existencia se cuenta en el producto de caja'
       end,
       'formato_caja_paquete'
  from _plan pl
 where pl.aplicar
   and pl.accion in ('convertir', 'desactivar')
   and pl.stock_nuevo <> pl.stock_hoy;

-- ── B) Empaque y precios del producto que se queda ─────────────────────────
update public.products p
   set units_per_pack = pl.paq_por_caja,
       packs_per_box  = null,
       unit_label     = 'Paquete',
       pack_label     = 'Caja',
       box_label      = null,
       pack_price     = pl.precio_caja,
       box_price      = null,
       min_unit_qty   = null,
       price          = pl.precio_paquete,
       cost           = pl.costo,
       min_stock      = pl.min_stock_nuevo,
       sale_unit      = 'paquete',
       purchase_unit  = 'paquete'
  from _plan pl
 where pl.aplicar
   and pl.accion = 'convertir'
   and p.id = pl.id;

-- ── C) Niveles de precio: estaban por caja, pasan a paquete ────────────────
-- Dinámico porque price_tier_4..10 solo existen si corrió la migración 32.
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
          where pl.aplicar and pl.accion = ''convertir''
            and p.id = pl.id and p.%I is not null',
        v_col, v_col, v_col);
    end if;
  end loop;
end $$;

-- ── D) Gemelos: fuera del catálogo (no se borran: tienen ventas) ───────────
update public.products p
   set is_active = false
  from _plan pl
 where pl.aplicar
   and pl.accion = 'desactivar'
   and p.id = pl.id;

commit;


-- ── Resultado: lo único que muestra el editor ──────────────────────────────
-- En vista previa muestra cómo VA a quedar; aplicado, lee la tabla real.
select
  case when pl.aplicar then 'APLICADO'
       else 'VISTA PREVIA: no se cambió nada' end            as modo,
  coalesce(pl.modelo, '— no está en la hoja —')             as modelo,
  pl.sku,
  pl.nombre                                                 as producto,
  case pl.accion
    when 'listo'            then '✔ ya estaba en caja/paquete: no se toca'
    when 'convertir'        then case when pl.aplicar then '✔ convertido'
                                      else '→ pasa a caja de ' || pl.paq_por_caja || ' paquetes' end
    when 'desactivar'       then case when pl.aplicar then '✔ gemelo desactivado'
                                      else '→ gemelo: stock a 0 y se desactiva' end
    when 'ya desactivado'   then '· gemelo ya desactivado'
    when 'revisar'          then '⚠ NO SE TOCA: ' || pl.motivo
    when 'no existe'        then '✘ no hay ningún producto con este nombre'
    when 'fuera de la hoja' then '· no está en la hoja: no se toca'
  end                                                       as que_pasa,
  -- Precios solo del que se queda: los del gemelo y los de fuera de la hoja
  -- están en `como_estaba`.
  case when pl.papel <> 'se queda' then null
       when pl.aplicar then p.pack_price else pl.precio_caja end      as precio_caja,
  case when pl.papel <> 'se queda' then null
       when pl.aplicar then p.price      else pl.precio_paquete end   as precio_paquete,
  round(pl.precio_unidad_gemelo * pl.und_por_paq, 2)        as paquete_al_precio_del_gemelo,
  case when pl.aplicar then p.stock      else pl.stock_nuevo end      as stock,
  -- Lo que muestra la app: "64 Cajas · 12 Paquetes".
  (select case
            when not e.act then 'no aparece (desactivado)'
            when e.emp > 0 then
              floor(e.stk / e.emp)::bigint || ' cajas'
              || case when mod(e.stk, e.emp) <> 0
                      then ' · ' || (mod(e.stk, e.emp))::float8 || ' paquetes'
                      else '' end
            else e.stk::float8 || ' (solo unidades, sin opción de caja)'
          end
     from (select case when pl.aplicar then p.stock else pl.stock_nuevo end as stk,
                  case when pl.aplicar then p.units_per_pack else pl.empaque_nuevo end as emp,
                  case when pl.aplicar then p.is_active else pl.activo_nuevo end as act) e
  )                                                         as se_ve_en_la_app,
  case when pl.aplicar then p.is_active  else pl.activo_nuevo end     as activo,
  'precio ' || pl.precio_hoy
    || coalesce(' · caja ' || pl.precio_caja_hoy, '')
    || ' · stock ' || pl.stock_hoy::float8
    || coalesce(' · empaque ' || pl.empaque_hoy::float8 || ' '
                || coalesce(pl.unidad_hoy, 'unid.'), ' · sin empaque')
    || case when pl.activo_hoy then '' else ' · inactivo' end as como_estaba
from _plan pl
left join public.products p on p.id = pl.id
order by pl.orden nulls last, pl.sub, pl.sku;
