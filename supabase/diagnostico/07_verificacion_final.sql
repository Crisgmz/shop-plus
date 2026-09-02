-- ============================================================================
-- VERIFICACIÓN FINAL — migraciones 80, 83, 84 y 85
--
-- Comprueba en la base los efectos concretos de cada una. Todo debe salir ✅.
-- SOLO LECTURA. Un solo resultado.
-- ============================================================================

with chequeos(orden, mig, que_verifica, ok) as (
  values
    -- ── 80: columnas que el app de flutter_shop+ ya pedía ──────────────────
    (1, '80', 'products.imei_on_purchase existe',
      exists (select 1 from information_schema.columns
               where table_schema='public' and table_name='products'
                 and column_name='imei_on_purchase')),
    (2, '80', 'purchase_items.imeis existe',
      exists (select 1 from information_schema.columns
               where table_schema='public' and table_name='purchase_items'
                 and column_name='imeis')),

    -- ── 83: una sola función de cobro, con todo ────────────────────────────
    (3, '83', 'quedó UNA sola sobrecarga de checkout_sale_transactional',
      (select count(*) = 1 from pg_proc p
         join pg_namespace n on n.oid=p.pronamespace
        where n.nspname='public' and p.proname='checkout_sale_transactional')),
    (4, '83', 'checkout lee discount_amount (no discount_pct)',
      exists (select 1 from pg_proc p join pg_namespace n on n.oid=p.pronamespace
               where n.nspname='public' and p.proname='checkout_sale_transactional'
                 and pg_get_functiondef(p.oid) like '%>>''discount_amount''%')),
    (5, '83', 'checkout respeta price_includes_tax',
      exists (select 1 from pg_proc p join pg_namespace n on n.oid=p.pronamespace
               where n.nspname='public' and p.proname='checkout_sale_transactional'
                 and pg_get_functiondef(p.oid) like '%price_includes_tax%')),
    (6, '83', 'checkout respeta track_inventory',
      exists (select 1 from pg_proc p join pg_namespace n on n.oid=p.pronamespace
               where n.nspname='public' and p.proname='checkout_sale_transactional'
                 and pg_get_functiondef(p.oid) like '%track_inventory%')),
    (7, '83', 'venta SIN COMPROBANTE no factura ITBIS (checkout)',
      exists (select 1 from pg_proc p join pg_namespace n on n.oid=p.pronamespace
               where n.nspname='public' and p.proname='checkout_sale_transactional'
                 and pg_get_functiondef(p.oid) like '%::text = ''none''%')),
    (8, '83', 'lo mismo al GUARDAR cuenta (hold)',
      exists (select 1 from pg_proc p join pg_namespace n on n.oid=p.pronamespace
               where n.nspname='public' and p.proname='hold_sale_transactional'
                 and pg_get_functiondef(p.oid) like '%price_includes_tax%'
                 and pg_get_functiondef(p.oid) like '%::text = ''none''%')),
    (9, '83', 'lo mismo al EDITAR una venta',
      exists (select 1 from pg_proc p join pg_namespace n on n.oid=p.pronamespace
               where n.nspname='public' and p.proname='edit_sale_transactional'
                 and pg_get_functiondef(p.oid) like '%::text = ''none''%')),

    -- ── 84: devoluciones ───────────────────────────────────────────────────
    (10, '84', 'process_return restaura los IMEIs al inventario',
      exists (select 1 from pg_proc p join pg_namespace n on n.oid=p.pronamespace
               where n.nspname='public' and p.proname='process_return'
                 and pg_get_functiondef(p.oid) like '%restore_product_imeis%')),
    (11, '84', 'se eliminó la llave foránea duplicada',
      not exists (select 1 from pg_constraint
                   where conname='returns_cash_session_branch_fk')),

    -- ── 85: admin acotado a su empresa ─────────────────────────────────────
    (12, '85', 'existe el helper can_access_branch',
      exists (select 1 from pg_proc p join pg_namespace n on n.oid=p.pronamespace
               where n.nspname='public' and p.proname='can_access_branch')),
    (13, '85', 'NINGUNA función conserva el atajo de admin entre empresas',
      not exists (select 1 from pg_proc p join pg_namespace n on n.oid=p.pronamespace
                   where n.nspname='public' and p.prosecdef
                     and pg_get_functiondef(p.oid) like
                         '%has_branch_access(v_branch_id) or public.is_admin()%')),
    (14, '85', 'las funciones de dashboard/reportes usan el helper nuevo',
      (select count(*) >= 5 from pg_proc p join pg_namespace n on n.oid=p.pronamespace
        where n.nspname='public'
          and pg_get_functiondef(p.oid) like '%can_access_branch(v_branch_id)%'))
)
select mig as migracion, que_verifica,
       case when ok then '✅' else '❌ REVISAR' end as estado
from chequeos order by orden;
