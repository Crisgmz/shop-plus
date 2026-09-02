-- ============================================================================
-- DIAGNÓSTICO — ¿qué versión de cada objeto quedó viva en la base?
--
-- UNA SOLA CONSULTA a propósito: el SQL Editor de Supabase solo muestra el
-- resultado de la ÚLTIMA sentencia, así que todo va unido en un solo resultado.
--
-- 100% SOLO LECTURA. Copiar completo, ejecutar, y pasar la tabla resultante.
-- ============================================================================

with defs as (
  select
    p.proname                                 as fn,
    pg_get_function_identity_arguments(p.oid) as args,
    pg_get_functiondef(p.oid)                 as src
  from pg_proc p
  join pg_namespace n on n.oid = p.pronamespace
  where n.nspname = 'public'
    and p.proname in (
      'checkout_sale_transactional', 'hold_sale_transactional',
      'edit_sale_transactional', 'process_return',
      'convert_quotation_to_sale', 'update_quotation_document'
    )
),

-- 1) ¿Qué linaje quedó vivo en cada función compartida?
funciones as (
  select
    '1_FUNCION' as seccion,
    fn || '(' || left(args, 40) || ')' as item,
    concat_ws(' · ',
      case
        when src like '%discount_amount%' and src like '%discount_pct%' then 'desc:AMBOS'
        when src like '%discount_amount%' then 'desc:MONTO(flutter_shop+)'
        when src like '%discount_pct%'    then 'desc:PCT(shop-plus)'
        else 'desc:NINGUNO(se pierde)'
      end,
      case when src like '%price_includes_tax%' then 'itbis_incluido:SI' else 'itbis_incluido:NO' end,
      case when src like '%receipt_type::text = ''none''%'
             or src like '%v_receipt_type::text = ''none''%' then 'sin_comprobante:SI'
           else 'sin_comprobante:NO' end,
      case when src like '%track_inventory%' then 'track_inv:SI' else 'track_inv:NO' end,
      case when src like '%restore_product_imeis%' then 'restaura_imeis:SI' else '' end,
      case when src like '%client_name_snapshot%' then 'nombre_manual:SI' else '' end,
      case when src like '%vencida y no puede convertirse%' then 'BLOQUEA_VENCIDA' else '' end
    ) as resultado
  from defs
),

-- 2) Columnas en disputa
columnas as (
  select
    '2_COLUMNA' as seccion,
    c.table_name || '.' || c.column_name as item,
    c.udt_name ||
      case
        when c.table_name = 'returns' and c.column_name = 'refund_method'
          then case when c.udt_name = 'text'
                 then '  → OK (flutter_shop+, acepta credit_note)'
                 else '  → ENUM (shop-plus, RECHAZA credit_note)' end
        else ''
      end as resultado
  from information_schema.columns c
  where c.table_schema = 'public'
    and (
      (c.table_name = 'returns'        and c.column_name in ('refund_method','cash_session_id'))
      or (c.table_name = 'return_items' and c.column_name = 'imeis')
      or (c.table_name = 'products'     and c.column_name in ('price_includes_tax','is_service','track_inventory'))
      or (c.table_name = 'quotations'   and c.column_name = 'receipt_type')
      or (c.table_name = 'sales'        and c.column_name = 'client_name_snapshot')
    )
),

-- 3) Objetos que solo existen en un árbol (muestra también los que FALTAN)
esperados(tipo, nombre, viene_de) as (
  values
    ('tabla','sale_number_counters','shop-plus: números cortos de venta'),
    ('tabla','company_ecf_settings','flutter_shop+: facturación electrónica'),
    ('funcion','restore_product_imeis','flutter_shop+: mig 69'),
    ('funcion','register_sale_payment','shop-plus: abonos atómicos (mig 82)'),
    ('funcion','register_supplier_payment','shop-plus: abonos atómicos (mig 82)'),
    ('trigger','trg_sales_short_number','shop-plus: números cortos'),
    ('constraint','returns_cash_session_fk','flutter_shop+: mig 69'),
    ('constraint','returns_cash_session_branch_fk','shop-plus: mi mig 68 (DUPLICADA)')
),
objetos as (
  select
    '3_OBJETO' as seccion,
    e.tipo || ': ' || e.nombre as item,
    case when exists (
      select 1 from pg_tables t
       where t.schemaname = 'public' and t.tablename = e.nombre and e.tipo = 'tabla'
      union all
      select 1 from pg_proc p join pg_namespace n on n.oid = p.pronamespace
       where n.nspname = 'public' and p.proname = e.nombre and e.tipo = 'funcion'
      union all
      select 1 from pg_trigger g
       where not g.tgisinternal and g.tgname = e.nombre and e.tipo = 'trigger'
      union all
      select 1 from pg_constraint c
       where c.conname = e.nombre and e.tipo = 'constraint'
    ) then 'EXISTE' else 'no existe' end || '  (' || e.viene_de || ')' as resultado
  from esperados e
),

-- 4) Evidencia: ¿hay descuentos registrados alguna vez?
datos as (
  select '4_DATOS' as seccion,
         'ventas con descuento (histórico completo)' as item,
         count(*) filter (where d.total > 0)::text || ' de ' || count(*)::text ||
         ' ventas · último descuento: ' ||
         coalesce(max(s.sale_date) filter (where d.total > 0)::date::text, 'NUNCA') as resultado
  from public.sales s
  join lateral (
    select coalesce(sum(i.discount_amount), 0) as total
      from public.sale_items i where i.sale_id = s.id
  ) d on true
  where s.status <> 'voided'
)

select seccion, item, resultado from funciones
union all select seccion, item, resultado from columnas
union all select seccion, item, resultado from objetos
union all select seccion, item, resultado from datos
order by seccion, item;
