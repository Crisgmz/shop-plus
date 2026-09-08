-- ============================================================================
-- 20260908_87_dgii_rnc_por_empresa.sql
--
-- Los reportes 606 / 607 / IT-1 usaban el RNC de otra empresa — y en la
-- práctica, de NINGUNA.
--
-- Las tres funciones fiscales resolvían el RNC del contribuyente así:
--
--     select coalesce(company_tax_id, '') into v_rnc
--       from public.app_settings where id = 1;
--
-- Pero `app_settings` tiene UNA FILA POR EMPRESA (la migración 27 le puso
-- `company_id UNIQUE`). Hoy hay 31 filas, y la número 1 es un registro
-- residual llamado "Mi Negocio" SIN RNC.
--
-- Consecuencia: las 31 empresas reciben RNC vacío en la cabecera del TXT, y
-- como la pantalla deshabilita el botón de exportar cuando el RNC está vacío,
-- NINGUNA puede generar su 606 ni su 607. Ni siquiera las 9 que sí tienen su
-- RNC bien configurado.
--
-- Se corrigen dos cosas de una vez:
--
--   1) El RNC se resuelve por la EMPRESA de la sucursal del reporte — mismo
--      patrón que ya usa la migración 84 para el prefijo de notas de crédito.
--
--   2) Se agrega la validación de sucursal que faltaba. Estas tres funciones
--      reciben `p_branch_id` por parámetro y solo comprobaban el ROL: un
--      admin o contable de una empresa podía pedir el 606 de otra pasando su
--      UUID. Se usa `can_access_branch()` (migración 85), que exige
--      pertenencia o rol admin DENTRO de la misma empresa.
--
-- Además el JSON devuelve `rnc_missing`, para que la pantalla pueda decir
-- "configura el RNC de tu empresa" en vez de dejar un botón muerto sin
-- explicación.
--
-- CÓMO: se parchea la definición VIVA, no se reescriben las funciones desde
-- los archivos del repo — que fue justo lo que rompió cosas en agosto. El
-- bloque lee `pg_get_functiondef`, sustituye solo lo necesario y vuelve a
-- crear. Lo que no coincida se reporta y no se toca.
--
-- Ejecutar en el SQL Editor de Supabase, DESPUÉS de la 85 (usa su helper).
-- Idempotente: al segundo pase no encuentra nada que cambiar.
-- ============================================================================

begin;

do $patch$
declare
  r record;
  v_src text;
  v_out text;

  -- 1) RNC por empresa de la sucursal, no por `id = 1`.
  c_rnc_viejo constant text :=
    E'  select coalesce(company_tax_id, \'\')::text into v_rnc\n'
    '    from public.app_settings where id = 1;';
  c_rnc_nuevo constant text :=
    E'  -- CAMBIO (migración 87): el RNC sale de la empresa DUEÑA de esta\n'
    '  -- sucursal. Antes se leía siempre `app_settings where id = 1`, que en\n'
    '  -- esta base es un registro residual sin RNC: las 31 empresas recibían\n'
    '  -- cabecera vacía y no podían exportar.\n'
    '  select coalesce(s.company_tax_id, \'\')::text into v_rnc\n'
    '    from public.app_settings s\n'
    '    join public.branches b on b.company_id = s.company_id\n'
    '   where b.id = v_branch_id\n'
    '   limit 1;';

  -- 2) Validación de sucursal que faltaba.
  c_rol_viejo constant text :=
    E'    raise exception \'Solo admin o accountant pueden generar reportes fiscales\';\n'
    '  end if;';
  c_rol_nuevo constant text :=
    E'    raise exception \'Solo admin o accountant pueden generar reportes fiscales\';\n'
    '  end if;\n'
    '\n'
    '  -- CAMBIO (migración 87): faltaba comprobar la SUCURSAL. `p_branch_id`\n'
    '  -- llega por parámetro, así que sin esto un contable podía pedir el\n'
    '  -- reporte fiscal de otra empresa pasando su UUID.\n'
    '  if not public.can_access_branch(v_branch_id) then\n'
    '    raise exception \'Sin acceso a la sucursal indicada\';\n'
    '  end if;';

  -- 3) Avisar a la pantalla si la empresa no tiene RNC configurado.
  c_ret_viejo constant text := E'    \'rnc_negocio\', v_rnc,';
  c_ret_nuevo constant text :=
    E'    \'rnc_negocio\', v_rnc,\n'
    '    \'rnc_missing\', (coalesce(v_rnc, \'\') = \'\'),';

  v_n int := 0;
begin
  for r in
    select p.oid, p.oid::regprocedure::text as firma
      from pg_proc p
      join pg_namespace n on n.oid = p.pronamespace
     where n.nspname = 'public'
       and p.proname in ('dgii_606_data', 'dgii_607_data', 'dgii_it1_summary')
     order by 1
  loop
    v_src := pg_get_functiondef(r.oid);
    v_out := v_src;

    if position(c_rnc_viejo in v_out) > 0 then
      v_out := replace(v_out, c_rnc_viejo, c_rnc_nuevo);
    else
      raise notice 'OJO — % ya no resuelve el RNC como se esperaba; revisar a mano', r.firma;
    end if;

    if position(c_rol_viejo in v_out) > 0
       and position('can_access_branch' in v_out) = 0 then
      v_out := replace(v_out, c_rol_viejo, c_rol_nuevo);
    end if;

    if position(c_ret_viejo in v_out) > 0
       and position('rnc_missing' in v_out) = 0 then
      v_out := replace(v_out, c_ret_viejo, c_ret_nuevo);
    end if;

    if v_out = v_src then
      raise notice 'sin cambios: %', r.firma;
      continue;
    end if;

    execute v_out;
    v_n := v_n + 1;
    raise notice 'parcheada: %', r.firma;
  end loop;

  raise notice '--- % funciones fiscales parcheadas ---', v_n;
end
$patch$;

commit;

notify pgrst, 'reload schema';


-- ============================================================================
-- VERIFICACIÓN — las tres deben salir en true.
-- ============================================================================
select
  p.proname                                                    as funcion,
  (pg_get_functiondef(p.oid) like '%b.company_id = s.company_id%') as rnc_por_empresa,
  (pg_get_functiondef(p.oid) like '%can_access_branch%')          as valida_sucursal,
  (pg_get_functiondef(p.oid) like '%rnc_missing%')                as avisa_rnc_faltante
from pg_proc p
join pg_namespace n on n.oid = p.pronamespace
where n.nspname = 'public'
  and p.proname in ('dgii_606_data','dgii_607_data','dgii_it1_summary')
order by 1;
