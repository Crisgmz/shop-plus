-- ============================================================================
-- Migración 59 — Vender SIN comprobante (nota de venta no fiscal)
-- ============================================================================
-- Decisión del dueño: el POS debe permitir vender sin comprobante fiscal — una
-- nota de venta simple, sin NCF, sin exigir cliente con RNC y sin ITBIS. El
-- comprobante fiscal (B02 consumidor final, B01 crédito fiscal, etc.) pasa a ser
-- OPCIONAL: el cajero lo elige solo cuando el cliente lo pide.
--
-- Se modela con un nuevo valor del enum receipt_type: 'none'.
--   - El trigger de asignación de NCF NO le asigna número.
--   - El trigger de validación fiscal (migración 55) NO le exige RNC/razón social
--     (igual que 'consumer_final').
--
-- Nota técnica: las funciones comparan con new.receipt_type::text = 'none' (no
-- 'none'::receipt_type) para no "usar" el valor de enum recién agregado en la
-- misma transacción (Postgres lo prohíbe). Así el script corre de una sola vez.
--
-- Ejecutar en el SQL Editor de Supabase, DESPUÉS de la migración 55/56.
-- Idempotente (ADD VALUE IF NOT EXISTS + CREATE OR REPLACE).
-- ============================================================================

-- 1) Nuevo valor del enum (sin transacción explícita: ADD VALUE no debe usarse
--    dentro de la misma tx donde se referencia como literal; aquí no se hace).
alter type public.receipt_type add value if not exists 'none';

-- 2) Asignación de NCF (INSERT): saltar 'none' antes de intentar secuencia.
create or replace function public.tg_sales_assign_ncf()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if new.receipt_type::text = 'none' then
    return new;  -- nota de venta no fiscal: nunca consume NCF
  end if;

  if new.ncf is not null and length(trim(new.ncf)) > 0 then
    return new;  -- ya tiene NCF explícito
  end if;

  if new.status in ('completed'::public.sale_status, 'credit'::public.sale_status) then
    begin
      new.ncf := public.assign_next_ncf(new.branch_id, new.receipt_type);
    exception when others then
      raise notice 'No se pudo asignar NCF para venta % (tipo %): %',
        new.id, new.receipt_type, SQLERRM;
    end;
  end if;

  return new;
end;
$$;

-- 3) Asignación de NCF (UPDATE de status): mismo skip para 'none'.
create or replace function public.tg_sales_assign_ncf_on_complete()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if new.receipt_type::text = 'none' then
    return new;
  end if;

  if new.status not in ('completed'::public.sale_status, 'credit'::public.sale_status) then
    return new;
  end if;

  if new.ncf is not null and length(trim(new.ncf)) > 0 then
    return new;
  end if;

  if old.status not in ('draft'::public.sale_status, 'pending'::public.sale_status) then
    return new;
  end if;

  begin
    new.ncf := public.assign_next_ncf(new.branch_id, new.receipt_type);
  exception when others then
    raise notice 'No se pudo asignar NCF al completar venta % (tipo %): %',
      new.id, new.receipt_type, SQLERRM;
  end;

  return new;
end;
$$;

-- 4) Validación fiscal del comprador (migración 55): 'none' tampoco exige datos
--    fiscales (igual que 'consumer_final').
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
  -- Consumidor Final y "sin comprobante" no requieren datos fiscales.
  if new.receipt_type::text in ('consumer_final', 'none') then
    return new;
  end if;

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

notify pgrst, 'reload schema';
