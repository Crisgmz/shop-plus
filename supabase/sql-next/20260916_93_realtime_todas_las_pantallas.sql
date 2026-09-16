-- ============================================================================
-- 20260916_93_realtime_todas_las_pantallas.sql
--
-- Tiempo real en todas las pantallas operativas.
--
-- Las migraciones 24 y 41 publicaron 8 tablas (products, product_categories,
-- sales, payments, cash_sessions, cash_register_movements, clients, returns) y
-- la 46 les puso REPLICA IDENTITY FULL. Cotizaciones, compras, gastos,
-- suplidores, cuentas por pagar, caja chica, secuencias NCF y el catálogo de
-- cajas quedaron fuera: esas pantallas no se enteraban de ningún cambio.
--
-- Esta migración es la fuente ÚNICA del conjunto completo (20 tablas). Vuelve
-- a aplicar las 8 originales —publicación y REPLICA IDENTITY FULL— porque si
-- la 46 no llegó a correr en una base, sus DELETE nunca llegan al cliente. Es
-- idempotente: donde ya estaba, no cambia nada.
--
-- Agrega:
--   quotations, quotation_items         → Cotizaciones
--   purchases, purchase_items           → Compras, Cuentas por pagar, Impuestos
--   suppliers                           → Suplidores, Compras, Gastos
--   expenses                            → Gastos, Caja
--   supplier_payments                   → Cuentas por pagar, Caja (migración 60)
--   petty_cash_sessions,
--   petty_cash_movements,
--   petty_cash_categories               → Caja chica
--   ncf_sequences                       → banner de NCF, POS, Configuración
--   cash_registers                      → selector de cajas
--
-- Todas tienen branch_id y política de SELECT: el cliente filtra por sucursal
-- y Realtime solo entrega las filas que el usuario puede leer.
--
-- REPLICA IDENTITY FULL por lo mismo que la 46: sin ella un DELETE no trae
-- branch_id y el filtro por sucursal lo descarta.
--
-- BASE COMPARTIDA con flutter_shop+: agregar tablas a la publicación es
-- aditivo. La otra app no se suscribe a estas tablas, así que su
-- comportamiento no cambia; el único costo es algo más de WAL en los UPDATE y
-- DELETE de estas tablas.
--
-- Tolerante: si una tabla no existe (supplier_payments antes de la 60), la
-- salta en vez de abortar. Idempotente: se puede correr varias veces.
--
-- Mantener sincronizado con `_tableToProviders` en
-- lib/core/realtime/realtime_invalidator.dart — un test compara ambas listas.
-- ============================================================================

begin;

do $$
begin
  if not exists (select 1 from pg_publication where pubname = 'supabase_realtime') then
    create publication supabase_realtime;
  end if;
end $$;

do $$
declare
  v_tabla    text;
  v_agregada text[] := '{}';
  v_ya_habia text[] := '{}';
  v_no_existe text[] := '{}';
begin
  foreach v_tabla in array array[
    -- Originales (migraciones 24 y 41).
    'products', 'product_categories',
    'sales', 'payments', 'returns', 'clients',
    'cash_sessions', 'cash_register_movements',
    -- Nuevas.
    'cash_registers',
    'quotations', 'quotation_items',
    'purchases', 'purchase_items',
    'suppliers', 'expenses', 'supplier_payments',
    'petty_cash_sessions', 'petty_cash_movements', 'petty_cash_categories',
    'ncf_sequences'
  ] loop
    if to_regclass('public.' || v_tabla) is null then
      v_no_existe := v_no_existe || v_tabla;
      continue;
    end if;

    execute format('alter table public.%I replica identity full', v_tabla);

    begin
      execute format(
        'alter publication supabase_realtime add table public.%I', v_tabla
      );
      v_agregada := v_agregada || v_tabla;
    exception when duplicate_object then
      v_ya_habia := v_ya_habia || v_tabla;
    end;
  end loop;

  raise notice 'Realtime → agregadas: %  | ya estaban: %  | no existen (saltadas): %',
    v_agregada, v_ya_habia, v_no_existe;
end $$;

commit;
