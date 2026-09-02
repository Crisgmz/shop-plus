-- ============================================================================
-- IMPACTO POR DÍA — ¿cuándo se empezó a cobrar de más, de verdad?
--
-- Corrige el sesgo de `03_impacto_cobro_de_mas.sql`: aquella cruzaba el flag
-- ACTUAL del producto contra ventas históricas, así que marcaba ventas hechas
-- ANTES de que el producto se marcara como precio-con-ITBIS-incluido (o antes
-- de que existiera la columna, 17 jul 2026). Esas se cobraron bien.
--
-- Esta consulta separa, día por día, las líneas cobradas BIEN (el total es
-- igual al neto, o sea el ITBIS se extrajo) de las cobradas MAL (se agregó
-- encima). Un día con líneas correctas prueba que la función buena estaba
-- viva; un día con solo líneas malas es daño real.
--
-- SOLO LECTURA. Un solo resultado.
-- ============================================================================

with lineas as (
  select
    s.sale_date::date as dia,
    round((si.quantity * si.unit_price
           - coalesce(si.discount_amount, 0))::numeric, 2) as neto,
    si.line_total
  from public.sale_items si
  join public.sales    s on s.id = si.sale_id
  join public.products p on p.id = si.product_id
  where coalesce(p.price_includes_tax, false)
    and coalesce(si.tax_rate, 0) > 0
    and s.status <> 'voided'
),
por_dia as (
  select
    dia,
    count(*) filter (where line_total <= neto + 0.01) as bien,
    count(*) filter (where line_total >  neto + 0.01) as mal,
    round(coalesce(sum(line_total - neto)
      filter (where line_total > neto + 0.01), 0), 2)  as cobrado_de_mas
  from lineas
  group by dia
)
select
  dia,
  bien   as lineas_correctas,
  mal    as lineas_cobradas_de_mas,
  cobrado_de_mas,
  case
    when bien > 0 and mal = 0 then 'OK — la función buena estaba viva'
    when bien > 0 and mal > 0 then 'MIXTO — revisar (¿flag puesto ese día?)'
    when bien = 0 and mal > 0 then 'DAÑO — la función rota estaba viva'
  end as veredicto
from por_dia
order by dia desc;
