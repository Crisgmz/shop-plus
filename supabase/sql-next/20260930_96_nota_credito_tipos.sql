-- ============================================================================
-- 20260930_96_nota_credito_tipos.sql
--
-- Tipos que necesita la migración 97 (notas de crédito B04 y anulaciones):
--
--   receipt_type  + 'credit_note'  → secuencias NCF de Nota de Crédito (B04,
--                                    E34 en e-CF) y el tipo de las devoluciones
--                                    de ventas con comprobante fiscal.
--   dgii_status   + 'voided'       → el comprobante de una venta anulada. Sin
--                                    este valor, "Anular comprobante" en
--                                    Comprobantes fallaba siempre.
--
-- VA SOLA y SIN `begin/commit`: Postgres no deja usar un valor nuevo de un
-- enum en la misma transacción que lo crea ("unsafe use of new value"). Correr
-- ANTES de la 97. Idempotente (`if not exists`).
--
-- Base compartida con flutter_shop+: agregar valores a un enum no rompe nada
-- del otro app (ninguno enumera todos los valores).
-- ============================================================================

alter type public.receipt_type add value if not exists 'credit_note';
alter type public.dgii_status add value if not exists 'voided';
