-- ============================================================================
-- Migración 57 — Consulta RNC server-side (proxy DGII, anti-CORS)
-- ============================================================================
-- El POS consulta el padrón RNC de DGII vía rnc.megaplus.com.do. Esa API NO
-- envía cabeceras CORS, así que el GET directo desde el navegador (Flutter web)
-- queda BLOQUEADO por el navegador → "No se pudo conectar a DGII".
--
-- Solución (la opción "avanzada"): hacer la consulta DEL LADO DEL SERVIDOR con
-- la extensión `http` de Postgres, expuesta como RPC. La app llama el RPC por
-- la API de Supabase (que sí maneja CORS) y el servidor hace el llamado a DGII.
-- Funciona en web, móvil y escritorio por igual.
--
-- Requiere la extensión `http` (Supabase: Database › Extensions › http).
-- Statement timeout subido a 15s dentro de la función porque el rol
-- `authenticated` suele tener un límite menor (8s) y DGII puede tardar.
--
-- Si la extensión `http` no estuviera disponible en tu instancia, la
-- alternativa es una Edge Function que haga el mismo proxy; avísame y la armo.
--
-- Ejecutar en el SQL Editor de Supabase.
-- ============================================================================

create extension if not exists http with schema extensions;

-- ----------------------------------------------------------------------------
-- rnc_lookup: consulta un contribuyente por RNC/cédula. Devuelve el JSON de
-- DGII tal cual, o NULL si no está inscrito (HTTP 404).
-- ----------------------------------------------------------------------------
create or replace function public.rnc_lookup(p_rnc text)
returns jsonb
language plpgsql
security definer
set search_path = public, extensions
set statement_timeout to 15000
as $$
declare
  v_clean  text := regexp_replace(coalesce(p_rnc, ''), '[^0-9]', '', 'g');
  v_status int;
  v_body   text;
begin
  if length(v_clean) not in (9, 11) then
    raise exception 'El RNC debe tener 9 dígitos (empresa) o 11 (cédula).'
      using errcode = '22023';
  end if;

  select status, content
    into v_status, v_body
    from extensions.http_get(
      'https://rnc.megaplus.com.do/api/consulta?rnc=' || v_clean
    );

  if v_status = 404 then
    return null;
  end if;
  if v_status <> 200 then
    raise exception 'DGII devolvió un error (%).', v_status
      using errcode = 'P0001';
  end if;

  return v_body::jsonb;
end;
$$;

grant execute on function public.rnc_lookup(text) to authenticated;

-- ----------------------------------------------------------------------------
-- rnc_search: búsqueda parcial por nombre/razón social. Devuelve el JSON de
-- DGII (objeto con `resultados`). Devuelve lista vacía si la consulta es corta
-- o si el proxy responde con error.
-- ----------------------------------------------------------------------------
create or replace function public.rnc_search(p_query text)
returns jsonb
language plpgsql
security definer
set search_path = public, extensions
set statement_timeout to 15000
as $$
declare
  v_q      text := trim(coalesce(p_query, ''));
  v_status int;
  v_body   text;
begin
  if length(v_q) < 3 then
    return jsonb_build_object('resultados', '[]'::jsonb);
  end if;

  select status, content
    into v_status, v_body
    from extensions.http_get(
      'https://rnc.megaplus.com.do/api/consulta/nombres?buscar='
      || replace(v_q, ' ', '%20')
    );

  if v_status <> 200 then
    return jsonb_build_object('resultados', '[]'::jsonb);
  end if;

  return v_body::jsonb;
end;
$$;

grant execute on function public.rnc_search(text) to authenticated;

notify pgrst, 'reload schema';
