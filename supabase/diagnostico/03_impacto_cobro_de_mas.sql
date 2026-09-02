-- ============================================================================
-- IMPACTO — ¿a cuántas ventas se les cobró ITBIS de más?
--
-- Un producto con `price_includes_tax = true` trae el ITBIS DENTRO del precio:
-- la función correcta lo EXTRAE. La versión que quedó viva (migración 67,
-- descartada) no conoce esa bandera y se lo AGREGA ENCIMA. Resultado: el
-- cliente pagó el impuesto dos veces.
--
-- Cómo se detecta: en una línea con precio-con-ITBIS-incluido bien calculada,
-- `line_total` es igual al neto (cantidad × precio − descuento). Si el total
-- quedó POR ENCIMA del neto, se le agregó el impuesto encima.
--
-- SOLO LECTURA. Devuelve un solo resultado.
-- ============================================================================

with lineas as (
  select
    s.id                                    as sale_id,
    s.sale_number,
    s.sale_date,
    s.branch_id,
    p.name                                  as producto,
    si.quantity, si.unit_price, si.discount_amount,
    si.line_total,
    round((si.quantity * si.unit_price - coalesce(si.discount_amount, 0))::numeric, 2) as neto,
    si.tax_rate
  from public.sale_items si
  join public.sales    s on s.id = si.sale_id
  join public.products p on p.id = si.product_id
  where coalesce(p.price_includes_tax, false)
    and coalesce(si.tax_rate, 0) > 0
    and s.status <> 'voided'
),
afectadas as (
  select *, round((line_total - neto)::numeric, 2) as cobrado_de_mas
  from lineas
  where line_total > neto + 0.01
)

-- Resumen primero, detalle después (todo en un solo resultado)
select
  '1_RESUMEN' as bloque,
  'productos con precio-ITBIS-incluido' as detalle,
  (select count(*)::text from public.products where coalesce(price_includes_tax, false)) as valor
union all
select '1_RESUMEN', 'líneas afectadas',
       (select count(*)::text from afectadas)
union all
select '1_RESUMEN', 'ventas afectadas',
       (select count(distinct sale_id)::text from afectadas)
union all
select '1_RESUMEN', 'TOTAL cobrado de más (RD$)',
       (select coalesce(sum(cobrado_de_mas), 0)::text from afectadas)
union all
select '1_RESUMEN', 'rango de fechas',
       (select coalesce(min(sale_date)::date::text || ' → ' || max(sale_date)::date::text, 'ninguna')
          from afectadas)
union all
select '2_DETALLE',
       sale_number || ' · ' || sale_date::date::text || ' · ' || producto,
       'neto ' || neto::text || ' → cobrado ' || line_total::text ||
       '  (de más: ' || cobrado_de_mas::text || ')'
from afectadas
order by bloque, detalle;
