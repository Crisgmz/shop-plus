-- ============================================================================
-- ¿Por qué una NOTA DE VENTA ("Sin comprobante") salió con ITBIS?
-- Negocio 3db1bc8d-011a-4b25-b132-eeb264e27777 (Soplasora). SOLO LECTURA.
--
-- Una venta 'none' nunca debe llevar ITBIS. Hay dos caminos que lo agregaban:
--   · convertir una cotización: copiaba el ITBIS de la cotización tal cual
--     (lo corrige la migración 94);
--   · editar la venta con una versión de `edit_sale_transactional` que no
--     conoce 'none' (la 87 de flutter_shop+ la recalcula al 18%).
--
-- Pegue todo y Run. La tabla dice, primero, si cada función viva respeta
-- "Sin comprobante"; después, cada nota de venta con ITBIS y de dónde vino.
-- ============================================================================
select 1 as orden,
       p.oid::regprocedure::text                                     as que,
       case when pg_get_functiondef(p.oid) like '%''none''%'
            then 'OK: sin comprobante = sin ITBIS'
            else 'MAL: cobra ITBIS aunque sea sin comprobante' end   as resultado
  from pg_proc p
  join pg_namespace n on n.oid = p.pronamespace
 where n.nspname = 'public'
   and p.proname in ('checkout_sale_transactional', 'hold_sale_transactional',
                     'edit_sale_transactional', 'convert_quotation_to_sale')
union all
select 2,
       'venta ' || s.sale_number,
       'ITBIS ' || s.tax_amount || ' · total ' || s.total_amount
       || ' · ' || to_char(s.created_at at time zone 'America/Santo_Domingo', 'DD/MM/YYYY HH24:MI')
       || coalesce(' · vino de la cotización ' || s.source_quotation_code,
                   ' · hecha en el punto de venta')
       || case when s.updated_at > s.created_at + interval '2 minutes'
               then ' · modificada después, el '
                    || to_char(s.updated_at at time zone 'America/Santo_Domingo', 'DD/MM HH24:MI')
               else '' end
  from public.sales s
  join public.branches b on b.id = s.branch_id
 where b.company_id = '3db1bc8d-011a-4b25-b132-eeb264e27777'
   and s.receipt_type::text = 'none'
   and s.tax_amount > 0
order by orden, que;
