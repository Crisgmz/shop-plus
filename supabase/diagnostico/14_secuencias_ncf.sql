-- ============================================================================
-- El NCF sale por un número que no es el que configuraste
-- Negocio 3db1bc8d-011a-4b25-b132-eeb264e27777 (Soplasora). PASO 1: SOLO LECTURA.
--
-- `assign_next_ncf` (migración 56) usa, en este orden:
--     coalesce(next_number, greatest(sequence_start, current_number + 1))
--
-- La pantalla de Ajustes guardaba `current_number`, `sequence_start` y
-- `sequence_end`, pero NO `next_number`. Como el primer comprobante emitido
-- deja `next_number` poblado, a partir de ahí cambiar "Número actual" en la
-- app no movía nada: la secuencia seguía pegada en el número viejo.
--
-- El PASO 1 muestra cada secuencia y con qué número va a salir el próximo NCF.
-- El PASO 2 la realinea con lo que dice "Número actual" / el inicio del rango.
-- ============================================================================

-- ── PASO 1 — Qué hay hoy y qué NCF saldría ─────────────────────────────────
select s.id,
       s.receipt_type,
       s.prefix,
       s.sequence_start                                      as inicio_rango,
       s.sequence_end                                        as fin_rango,
       s.current_number                                      as numero_actual,
       s.next_number                                         as proximo_guardado,
       coalesce(
         s.next_number,
         greatest(coalesce(s.sequence_start, 1), coalesce(s.current_number, 0) + 1)
       )                                                     as proximo_efectivo,
       s.prefix || lpad(coalesce(
         s.next_number,
         greatest(coalesce(s.sequence_start, 1), coalesce(s.current_number, 0) + 1)
       )::text, 8, '0')                                      as proximo_ncf,
       s.is_active,
       s.status,
       s.expires_on,
       -- El último que realmente salió en una venta, para comparar.
       (select max(v.ncf)
          from public.sales v
         where v.branch_id = s.branch_id
           and v.receipt_type = s.receipt_type
           and v.ncf like s.prefix || '%')                    as ultimo_ncf_usado
  from public.ncf_sequences s
  join public.branches b on b.id = s.branch_id
 where b.company_id = '3db1bc8d-011a-4b25-b132-eeb264e27777'
 order by s.receipt_type, s.prefix;

-- Qué mirar:
--   · `proximo_ncf` es el que va a salir en la próxima factura.
--   · `ultimo_ncf_usado` es el último que realmente salió en una venta.
--   · OJO con `numero_actual`: cada emisión lo pisa con el número que usó. Si
--     la secuencia venía pegada, ese campo YA NO dice por dónde ibas de
--     verdad; el dato bueno es tu talonario / `ultimo_ncf_usado`.
--   · Si hay DOS secuencias activas del mismo tipo, se consume primero la del
--     número más bajo. Desactiva la que no uses antes de seguir.


-- ── PASO 2A — Ponerla donde va (lo normal) ─────────────────────────────────
-- Descomenta, pon el último NCF que emitiste DE VERDAD y el id del PASO 1.
-- Es lo mismo que hacer "Número actual = 45" en Ajustes → NCF con la versión
-- nueva de la app, que ya reescribe `next_number`.
--
-- update public.ncf_sequences
--    set current_number = 45,                  -- último NCF emitido de verdad
--        next_number    = 46,                  -- el que sigue
--        updated_at     = timezone('utc', now())
--  where id = '<id de la secuencia del PASO 1>';


-- ── PASO 2B — Realinear las que nunca se tocaron ───────────────────────────
-- Para secuencias cuyo `numero_actual` SÍ es confiable: deja el próximo en el
-- que sigue, sin bajar del inicio del rango. No toca las que ya están bien.
update public.ncf_sequences s
   set next_number = greatest(
         coalesce(s.sequence_start, 1),
         coalesce(s.current_number, 0) + 1
       ),
       updated_at = timezone('utc', now())
  from public.branches b
 where b.id = s.branch_id
   and b.company_id = '3db1bc8d-011a-4b25-b132-eeb264e27777'
   and s.next_number is distinct from greatest(
         coalesce(s.sequence_start, 1),
         coalesce(s.current_number, 0) + 1
       );

-- ── PASO 3 — Verificación (vuelve a correr el PASO 1) ──────────────────────
select s.receipt_type,
       s.prefix,
       s.current_number                                      as numero_actual,
       s.next_number                                         as proximo,
       s.prefix || lpad(s.next_number::text, 8, '0')         as proximo_ncf
  from public.ncf_sequences s
  join public.branches b on b.id = s.branch_id
 where b.company_id = '3db1bc8d-011a-4b25-b132-eeb264e27777'
 order by s.receipt_type, s.prefix;
