-- ============================================================================
-- Migración 58 — Campos de empresa para factura/cotización (formato A4)
-- ============================================================================
-- El PDF de página completa (factura y cotización) debe mostrar el bloque del
-- emisor (dirección, teléfono, email), los datos bancarios para pago, el
-- firmante (nombre + cargo) y una observación, todo tomado de configuración.
--
-- Estos datos viven en app_settings (fila singleton por empresa, RLS por
-- tenant). Hoy solo existían company_name / company_legal_name / company_tax_id
-- / company_logo_url. Agregamos el resto como columnas text opcionales.
--
-- Idempotente (ADD COLUMN IF NOT EXISTS). Ejecutar en el SQL Editor de Supabase.
-- ============================================================================

begin;

alter table public.app_settings
  add column if not exists company_address          text,
  add column if not exists company_phone            text,
  add column if not exists company_email            text,
  add column if not exists company_bank_info        text,
  add column if not exists company_signatory_name   text,
  add column if not exists company_signatory_title  text,
  add column if not exists invoice_observation       text,
  add column if not exists invoice_show_itbis        boolean not null default true,
  add column if not exists company_qr_url            text;

comment on column public.app_settings.company_address is
  'Dirección del emisor mostrada en el encabezado de factura/cotización.';
comment on column public.app_settings.company_phone is
  'Teléfono(s) del emisor. Texto libre (admite varios separados por " / ").';
comment on column public.app_settings.company_email is
  'Correo del emisor mostrado en el encabezado.';
comment on column public.app_settings.company_bank_info is
  'Datos bancarios para pago (banco, cuenta, titular). Texto multilínea.';
comment on column public.app_settings.company_signatory_name is
  'Nombre del firmante que aparece sobre la línea de firma (ej. gerente).';
comment on column public.app_settings.company_signatory_title is
  'Cargo del firmante (ej. "Gerente de Finanzas").';
comment on column public.app_settings.invoice_observation is
  'Texto de observación opcional impreso en el pie de factura/cotización.';

commit;

notify pgrst, 'reload schema';
