-- ============================================================================
-- 20260831_85_scope_admin_to_company.sql
--
-- Acotar el atajo de administrador a SU PROPIA empresa.
--
-- Esta base es un SaaS multi-inquilino: 30 empresas, 30 sucursales, 69
-- usuarios. El aislamiento normal es sólido — las políticas RLS usan
-- `has_branch_access(branch_id)`, que exige pertenencia real en
-- `users_branches`, y ningún usuario está asignado a dos empresas.
--
-- El hueco está en las funciones `SECURITY DEFINER` que reciben la sucursal
-- por PARÁMETRO y la validan así:
--
--     if not (public.has_branch_access(v_branch_id) or public.is_admin()) then
--
-- `is_admin()` es un rol GLOBAL (`profiles.role = 'admin'`), no está acotado a
-- ninguna empresa. Y una función SECURITY DEFINER salta RLS por diseño. Así
-- que un administrador de la empresa A podía pasar el `branch_id` de la
-- empresa B y leer sus KPIs, su estado de resultados o sus comisiones.
--
-- Explotarlo exige conocer el UUID ajeno, que no se expone (la tabla
-- `branches` también está bajo RLS), así que es un riesgo de insider — pero
-- con 30 clientes en la misma base hay que cerrarlo.
--
-- ARREGLO: el atajo se mantiene (un admin sigue viendo cualquier sucursal),
-- pero solo dentro de SU empresa.
--
-- CÓMO: en vez de reescribir cada función a mano —que fue justo lo que salió
-- mal con las migraciones 67 y 68— se parchea la definición VIVA. El bloque
-- lee `pg_get_functiondef`, sustituye únicamente ese predicado y la vuelve a
-- crear. Lo que no coincida exactamente no se toca y se reporta.
--
-- Ejecutar en el SQL Editor de Supabase, DESPUÉS de la 84 (así también se
-- parchea `process_return`). Idempotente: al segundo pase ya no encuentra
-- nada que cambiar.
-- ============================================================================

begin;

-- ── 1) Helper: pertenencia a la sucursal, o admin de la MISMA empresa ───────
-- Sin dependencias de otras migraciones: la comprobación de empresa va
-- escrita aquí, no delega en `has_company_access`.
create or replace function public.can_access_branch(p_branch_id uuid)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select
    public.has_branch_access(p_branch_id)
    or (
      public.is_admin()
      and exists (
        select 1
          from public.users_branches ub
          join public.branches propia on propia.id = ub.branch_id
          join public.branches objetivo on objetivo.id = p_branch_id
          join public.profiles pr on pr.id = ub.user_id
         where ub.user_id = auth.uid()
           and ub.is_active
           and pr.is_active
           and propia.company_id = objetivo.company_id
      )
    );
$$;

comment on function public.can_access_branch(uuid) is
  'Pertenencia a la sucursal, o rol admin dentro de la MISMA empresa. '
  'Reemplaza el patrón `has_branch_access(x) or is_admin()`, que permitía a '
  'un admin alcanzar sucursales de otras empresas.';

grant execute on function public.can_access_branch(uuid) to authenticated;


-- ── 2) Parchear en sitio las funciones afectadas ───────────────────────────
do $patch$
declare
  r record;
  v_src text;
  v_nuevo text;
  v_patrón constant text :=
    'public.has_branch_access(v_branch_id) or public.is_admin()';
  v_parcheadas int := 0;
  v_omitidas int := 0;
begin
  for r in
    select p.oid, p.oid::regprocedure::text as firma
      from pg_proc p
      join pg_namespace n on n.oid = p.pronamespace
     where n.nspname = 'public'
       and p.prosecdef
       and pg_get_functiondef(p.oid) like '%public.is_admin()%'
       and pg_get_functiondef(p.oid) like '%has_branch_access%'
     order by 1
  loop
    v_src := pg_get_functiondef(r.oid);

    if position(v_patrón in v_src) = 0 then
      -- Usa is_admin() para otra cosa (p. ej. "solo admin o supervisor
      -- editan ventas"), que es un chequeo de ROL, no de sucursal. No se toca.
      v_omitidas := v_omitidas + 1;
      raise notice 'omitida (no es atajo de sucursal): %', r.firma;
      continue;
    end if;

    v_nuevo := replace(v_src, v_patrón, 'public.can_access_branch(v_branch_id)');
    execute v_nuevo;
    v_parcheadas := v_parcheadas + 1;
    raise notice 'parcheada: %', r.firma;
  end loop;

  raise notice '--- % parcheadas, % omitidas ---', v_parcheadas, v_omitidas;
end
$patch$;

commit;

notify pgrst, 'reload schema';


-- ============================================================================
-- VERIFICACIÓN — correr después. No debe devolver ninguna fila.
-- ============================================================================
select p.oid::regprocedure::text as sigue_con_el_atajo
from pg_proc p
join pg_namespace n on n.oid = p.pronamespace
where n.nspname = 'public'
  and p.prosecdef
  and pg_get_functiondef(p.oid) like
      '%public.has_branch_access(v_branch_id) or public.is_admin()%';
