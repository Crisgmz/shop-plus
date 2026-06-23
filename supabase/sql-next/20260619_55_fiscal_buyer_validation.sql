-- ============================================================================
-- Migración 55 — Validación de datos fiscales del comprador (NCF físico)
-- ============================================================================
-- Regla (decisión del dueño): un comprobante fiscal distinto de "Consumidor
-- Final" (Crédito Fiscal B01, Gubernamental B15, Régimen Especial B14,
-- Exportación B16) NO se puede emitir si el cliente no tiene RNC/cédula y
-- razón social/nombre. Se BLOQUEA la venta — ningún B01 sale inválido ante DGII.
--
-- Esta validación existía en el checkout original (20260410_pos_transactional_
-- core.sql, líneas 146-161) pero se perdió al reescribir checkout_sale_
-- transactional en las migraciones 52/53/54. Para que NO se vuelva a perder en
-- futuras reescrituras del checkout, se reimplementa como TRIGGER independiente
-- sobre public.sales — desacoplado de la función de checkout.
--
-- El trigger corre en las MISMAS condiciones que el de asignación de NCF
-- (trg_sales_assign_ncf): solo en ventas que se emiten de verdad
-- (status ∈ completed/credit) y solo para comprobantes ≠ consumer_final.
-- Las cuentas guardadas ('pending') y borradores no exigen datos fiscales.
--
-- Nombre 'assert' a propósito: ordena ANTES de 'assign' (los triggers BEFORE
-- corren en orden alfabético por nombre), así se valida antes de consumir un
-- número de la secuencia NCF. Aunque por la transacción un fallo posterior
-- revertiría el consumo, validar primero evita el gasto innecesario.
--
-- Ejecutar en el SQL Editor de Supabase, DESPUÉS de la migración 54.
-- Idempotente (CREATE OR REPLACE + DROP TRIGGER IF EXISTS).
-- ============================================================================

begin;

create or replace function public.tg_sales_assert_fiscal_client()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_doc  text;
  v_name text;
begin
  -- NO afectar ventas YA emitidas: si la venta ya tiene NCF es un comprobante
  -- existente y no debe re-validarse por cambios posteriores (anulación,
  -- reimpresión, edición, etc.). Las ventas NUEVAS aún no tienen NCF en este
  -- punto (este trigger 'assert' corre ANTES que el de asignación 'assign'),
  -- así que siguen validándose. Esto garantiza que la regla solo aplica de aquí
  -- en adelante y nunca rompe operaciones sobre el histórico.
  if new.ncf is not null and length(trim(new.ncf)) > 0 then
    return new;
  end if;

  -- Consumidor Final no requiere datos fiscales del comprador.
  if new.receipt_type = 'consumer_final'::public.receipt_type then
    return new;
  end if;

  -- Solo cuando la venta se emite de verdad. Las cuentas guardadas ('pending')
  -- y borradores ('draft') todavía pueden completar los datos del cliente.
  if new.status not in (
    'completed'::public.sale_status, 'credit'::public.sale_status
  ) then
    return new;
  end if;

  if new.client_id is null then
    raise exception
      'Debe seleccionar un cliente con RNC/cédula y razón social para emitir este comprobante (%).',
      new.receipt_type
      using errcode = '22023';
  end if;

  select nullif(trim(coalesce(c.document_number, '')), ''),
         nullif(trim(coalesce(c.legal_name, c.full_name, '')), '')
    into v_doc, v_name
    from public.clients c
   where c.id = new.client_id
     and c.branch_id = new.branch_id;

  if v_doc is null then
    raise exception
      'El cliente debe tener RNC/cédula registrado para emitir un comprobante fiscal (%).',
      new.receipt_type
      using errcode = '22023';
  end if;

  if v_name is null then
    raise exception
      'El cliente debe tener razón social o nombre registrado para emitir un comprobante fiscal (%).',
      new.receipt_type
      using errcode = '22023';
  end if;

  return new;
end;
$$;

comment on function public.tg_sales_assert_fiscal_client() is
  'Bloquea emitir comprobantes fiscales (≠ consumer_final) sin RNC/cédula y razón social del cliente.';

-- INSERT: venta nueva que entra directo como completed/credit (caso normal y
-- completar una cuenta guardada, que el checkout reinserta como completed).
drop trigger if exists trg_sales_assert_fiscal_client on public.sales;
create trigger trg_sales_assert_fiscal_client
  before insert on public.sales
  for each row
  execute function public.tg_sales_assert_fiscal_client();

-- UPDATE de estado: una venta draft/pending que pasa a completed/credit.
drop trigger if exists trg_sales_assert_fiscal_client_upd on public.sales;
create trigger trg_sales_assert_fiscal_client_upd
  before update of status on public.sales
  for each row
  when (old.status is distinct from new.status)
  execute function public.tg_sales_assert_fiscal_client();

commit;

notify pgrst, 'reload schema';
