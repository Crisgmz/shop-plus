-- ============================================================================
-- ¿QUÉ MIGRACIÓN FALTA EJECUTAR?
--
-- Comprueba en la base los efectos concretos de cada migración pendiente.
-- SOLO LECTURA. Un solo resultado.
-- ============================================================================

with chequeos(orden, migracion, que_verifica, aplicada) as (
  values
    -- 65: update_quotation_document acepta el nombre de cliente escrito a mano.
    -- ⚠️ CRÍTICO antes de desplegar shop-plus: el app manda
    -- `requested_client_name`; si la función no lo tiene, PostgREST no la
    -- encuentra y GUARDAR UNA COTIZACIÓN FALLA.
    (1, '65_quotation_manual_client_name',
     'update_quotation_document acepta requested_client_name',
     exists (
       select 1 from pg_proc p
       join pg_namespace n on n.oid = p.pronamespace
       where n.nspname = 'public'
         and p.proname = 'update_quotation_document'
         and 'requested_client_name' = any(p.proargnames)
     )),

    -- 83: una sola función de cobro, con todo.
    (2, '83_reconcile_checkout_both_apps',
     'checkout lee discount_amount y conoce price_includes_tax',
     exists (
       select 1 from pg_proc p
       join pg_namespace n on n.oid = p.pronamespace
       where n.nspname = 'public'
         and p.proname = 'checkout_sale_transactional'
         and pg_get_functiondef(p.oid) like '%>>''discount_amount''%'
         and pg_get_functiondef(p.oid) like '%price_includes_tax%'
     )),

    (3, '83_reconcile_checkout_both_apps',
     'quedó UNA sola sobrecarga de checkout_sale_transactional',
     (select count(*) = 1 from pg_proc p
        join pg_namespace n on n.oid = p.pronamespace
       where n.nspname = 'public'
         and p.proname = 'checkout_sale_transactional')),

    (4, '83_reconcile_checkout_both_apps',
     'editar una venta sin comprobante no le agrega ITBIS',
     exists (
       select 1 from pg_proc p
       join pg_namespace n on n.oid = p.pronamespace
       where n.nspname = 'public'
         and p.proname = 'edit_sale_transactional'
         and pg_get_functiondef(p.oid) like '%::text = ''none''%'
     )),

    -- 84: devoluciones.
    (5, '84_restore_process_return_imeis',
     'process_return restaura los IMEIs al inventario',
     exists (
       select 1 from pg_proc p
       join pg_namespace n on n.oid = p.pronamespace
       where n.nspname = 'public'
         and p.proname = 'process_return'
         and pg_get_functiondef(p.oid) like '%restore_product_imeis%'
     )),

    (6, '84_restore_process_return_imeis',
     'se eliminó la llave foránea duplicada de returns',
     not exists (
       select 1 from pg_constraint
       where conname = 'returns_cash_session_branch_fk'
     ))
)
select
  migracion,
  que_verifica,
  case when aplicada then '✅ ya aplicada' else '❌ FALTA EJECUTAR' end as estado
from chequeos
order by orden;
