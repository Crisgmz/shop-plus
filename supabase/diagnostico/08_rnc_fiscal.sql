-- ============================================================================
-- ¿Por qué el 606/607 no se puede descargar?
--
-- Las tres funciones fiscales resuelven el RNC del negocio con
-- `from public.app_settings where id = 1`. Pero la migración 27 declara
-- `app_settings.company_id UNIQUE` — o sea, UNA FILA POR EMPRESA.
--
-- Si no existe la fila con id = 1, el RNC llega vacío, y la interfaz
-- deshabilita el botón de exportar cuando el RNC está vacío.
--
-- SOLO LECTURA. Copiar y ejecutar completo.
-- ============================================================================

select
  s.id                                        as id_fila,
  coalesce(c.name, '(sin empresa)')           as empresa,
  coalesce(nullif(s.company_tax_id, ''), '(SIN RNC)') as rnc,
  case
    when s.id = 1 then '← la única que ven hoy TODAS las empresas'
    else 'su 606/607 sale con el RNC de la fila id=1'
  end                                         as situacion
from public.app_settings s
left join public.companies c on c.id = s.company_id
order by s.id;
