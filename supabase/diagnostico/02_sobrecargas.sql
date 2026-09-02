-- ============================================================================
-- DIAGNÓSTICO 2 — Las SOBRECARGAS de checkout_sale_transactional
--
-- El diagnóstico 1 reveló TRES funciones con ese nombre. `create or replace`
-- solo reemplaza cuando la firma coincide EXACTO; si una migración cambió la
-- lista de parámetros, dejó la vieja viva al lado. Con varias sobrecargas,
-- PostgREST elige según los nombres de parámetro que manda el app — o falla
-- con "Could not choose the best candidate function".
--
-- Esta consulta muestra la firma COMPLETA de cada una y qué sabe hacer.
-- SOLO LECTURA. Devuelve un solo resultado.
-- ============================================================================

select
  p.proname                                          as funcion,
  p.oid::regprocedure::text                          as firma_completa,
  pg_get_function_identity_arguments(p.oid)          as parametros,
  array_length(p.proargnames, 1)                     as n_parametros,
  -- Qué lee del JSON de items
  case
    when pg_get_functiondef(p.oid) like '%>>''discount_amount''%' then 'lee discount_amount'
    when pg_get_functiondef(p.oid) like '%>>''discount_pct''%'    then 'lee discount_pct'
    else 'NO lee descuento'
  end                                                as descuento,
  (pg_get_functiondef(p.oid) like '%price_includes_tax%')  as itbis_incluido,
  (pg_get_functiondef(p.oid) like '%track_inventory%')     as track_inventory,
  (pg_get_functiondef(p.oid) like '%::text = ''none''%')   as sin_comprobante,
  (pg_get_functiondef(p.oid) like '%restore_product_imeis%') as restaura_imeis,
  (pg_get_functiondef(p.oid) like '%returning id, sale_number%') as devuelve_num_corto,
  length(pg_get_functiondef(p.oid))                  as tam_codigo
from pg_proc p
join pg_namespace n on n.oid = p.pronamespace
where n.nspname = 'public'
  and p.proname in ('checkout_sale_transactional','hold_sale_transactional','process_return')
order by p.proname, array_length(p.proargnames, 1);
