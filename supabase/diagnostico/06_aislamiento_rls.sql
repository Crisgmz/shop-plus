-- ============================================================================
-- AISLAMIENTO — ¿cada negocio ve solo sus datos?
--
-- Con dos negocios en una sola base, esto es lo que hay que verificar.
-- El modelo es: cada fila lleva `branch_id` y las políticas RLS usan
-- `has_branch_access(branch_id)`, que comprueba pertenencia REAL en
-- `users_branches`. No hay atajo por rol dentro de las políticas.
--
-- SOLO LECTURA. Un solo resultado.
-- ============================================================================

with
-- 1) Tablas con datos de negocio SIN RLS activo = puerta abierta.
sin_rls as (
  select
    '1_RLS' as bloque,
    'tabla SIN RLS: ' || c.relname as detalle,
    'RIESGO — cualquier autenticado la lee entera' as estado
  from pg_class c
  join pg_namespace n on n.oid = c.relnamespace
  where n.nspname = 'public'
    and c.relkind = 'r'
    and not c.relrowsecurity
    and exists (
      select 1 from information_schema.columns col
      where col.table_schema = 'public'
        and col.table_name = c.relname
        and col.column_name = 'branch_id'
    )
),

-- 2) RLS activo pero sin políticas: la tabla queda inaccesible.
sin_politicas as (
  select
    '1_RLS',
    'RLS activo SIN políticas: ' || c.relname,
    'REVISAR — tabla inaccesible'
  from pg_class c
  join pg_namespace n on n.oid = c.relnamespace
  where n.nspname = 'public'
    and c.relkind = 'r'
    and c.relrowsecurity
    and not exists (select 1 from pg_policy pol where pol.polrelid = c.oid)
),

-- 3) Resumen de inquilinos.
inquilinos as (
  select '2_INQUILINOS', 'empresas registradas',
         (select count(*)::text from public.companies)
  union all
  select '2_INQUILINOS', 'sucursales',
         (select count(*)::text from public.branches)
  union all
  select '2_INQUILINOS', 'usuarios activos con sucursal',
         (select count(distinct user_id)::text
            from public.users_branches where is_active)
),

-- 4) LO IMPORTANTE: ¿algún usuario pertenece a sucursales de MÁS DE UNA
--    empresa? Sería el único capaz de ver los dos negocios.
cruzados as (
  select
    '3_CRUCE' as bloque,
    'usuario en varias empresas: '
      || coalesce(p.full_name, u.user_id::text) as detalle,
    count(distinct b.company_id)::text || ' empresas — REVISAR' as estado
  from public.users_branches u
  join public.branches b on b.id = u.branch_id
  left join public.profiles p on p.id = u.user_id
  where u.is_active
  group by u.user_id, p.full_name
  having count(distinct b.company_id) > 1
),

-- 5) Funciones SECURITY DEFINER que reciben la sucursal por PARÁMETRO y
--    aceptan `or is_admin()` como atajo. Saltan RLS por diseño, así que un
--    admin podría pasar el branch_id de la otra empresa.
bypass as (
  select
    '4_BYPASS' as bloque,
    p.proname || '()' as detalle,
    'recibe branch por parámetro y admite atajo por rol admin' as estado
  from pg_proc p
  join pg_namespace n on n.oid = p.pronamespace
  where n.nspname = 'public'
    and p.prosecdef
    and pg_get_functiondef(p.oid) like '%or public.is_admin()%'
    and pg_get_functiondef(p.oid) like '%has_branch_access%'
)

select * from sin_rls
union all select * from sin_politicas
union all select * from inquilinos
union all select * from cruzados
union all select * from bypass
order by 1, 2;
