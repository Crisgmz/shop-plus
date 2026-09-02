-- ============================================================================
-- 20260830_69_atomic_payment_rpcs.sql
--
-- Registrar un abono dejó de hacerse en tres viajes desde el app.
--
-- Cobros y Cuentas por pagar hacían read-modify-write desde el cliente:
--
--   1) leer el saldo de la venta/compra,
--   2) insertar el pago,
--   3) escribir paid_amount/balance_due calculados con el valor LEÍDO,
--   4) recalcular el saldo del cliente/proveedor.
--
-- Dos problemas reales:
--   · Dos cajeros abonando a la misma venta a la vez → el segundo pisa al
--     primero con un saldo calculado sobre una lectura vieja (lost update):
--     el dinero entra dos veces pero la deuda solo baja una.
--   · Si se corta la conexión entre (2) y (3), queda el pago insertado y la
--     venta con el saldo intacto.
--
-- Estas dos funciones hacen todo en UNA transacción con `for update` sobre la
-- fila, que es como ya trabajan checkout, edición y devoluciones.
--
-- La app las llama con fallback: si la migración todavía no se ejecutó,
-- sigue por el camino viejo (mismo patrón que `p_payments` en la 50/52).
--
-- Ejecutar en el SQL Editor de Supabase. Idempotente.
-- ============================================================================


-- ----------------------------------------------------------------------------
-- 1) register_sale_payment — abono a una venta a crédito (Cobros).
-- ----------------------------------------------------------------------------
create or replace function public.register_sale_payment(
  p_sale_id uuid,
  p_amount numeric,
  p_payment_method text default 'cash',
  p_reference text default null,
  p_notes text default null,
  p_cash_session_id uuid default null
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_user_id uuid := auth.uid();
  v_branch_id uuid := public.current_branch_id();
  v_sale public.sales%rowtype;
  v_amount numeric(14,2);
  v_method public.payment_method;
  v_session_id uuid;
  v_next_paid numeric(14,2);
  v_next_balance numeric(14,2);
  v_next_status public.sale_status;
  v_client_balance numeric(14,2);
begin
  if v_user_id is null then
    raise exception 'No hay sesión activa.' using errcode = '28000';
  end if;
  if v_branch_id is null then
    raise exception 'No hay sucursal asignada para este usuario.'
      using errcode = '22023';
  end if;

  begin
    v_method := coalesce(nullif(btrim(p_payment_method), ''), 'cash')
      ::public.payment_method;
  exception
    when invalid_text_representation then
      raise exception 'Método de pago no soportado: %', p_payment_method
        using errcode = '22023';
  end;

  v_amount := round(coalesce(p_amount, 0)::numeric, 2);
  if v_amount <= 0 then
    raise exception 'El monto debe ser mayor que 0.' using errcode = '22023';
  end if;

  -- `for update`: bloquea la venta mientras se registra el abono. Es lo que
  -- impide que dos cajeros calculen el saldo sobre la misma lectura.
  select * into v_sale
    from public.sales
   where id = p_sale_id and branch_id = v_branch_id
   for update;

  if not found then
    raise exception 'La venta no existe en esta sucursal.' using errcode = '23503';
  end if;
  if not public.has_branch_access(v_sale.branch_id) then
    raise exception 'No tienes acceso a la sucursal de esta venta.'
      using errcode = '42501';
  end if;
  if v_sale.status = 'voided'::public.sale_status then
    raise exception 'La venta está anulada.' using errcode = '22023';
  end if;
  if coalesce(v_sale.balance_due, 0) <= 0 then
    raise exception 'La venta no tiene balance pendiente.' using errcode = '22023';
  end if;
  if v_amount > round(v_sale.balance_due::numeric, 2) then
    raise exception 'El abono (%) no puede exceder el balance pendiente (%).',
      v_amount, round(v_sale.balance_due::numeric, 2) using errcode = '22023';
  end if;

  v_session_id := p_cash_session_id;
  if v_session_id is null then
    select cs.id into v_session_id
      from public.cash_sessions cs
     where cs.branch_id = v_branch_id
       and cs.status = 'open'
       and (
         cs.opened_by = v_user_id
         or exists (
           select 1 from public.cash_register_users cru
           where cru.cash_register_id = cs.cash_register_id
             and cru.user_id = v_user_id
             and cru.is_active
         )
       )
     order by cs.opened_at desc
     limit 1;
  end if;

  insert into public.payments (
    branch_id, sale_id, client_id, cash_session_id, payment_method,
    amount, paid_at, reference, notes
  ) values (
    v_branch_id, v_sale.id, v_sale.client_id, v_session_id, v_method,
    v_amount, timezone('utc', now()),
    nullif(btrim(coalesce(p_reference, '')), ''),
    nullif(btrim(coalesce(p_notes, '')), '')
  );

  v_next_paid := round((coalesce(v_sale.paid_amount, 0) + v_amount)::numeric, 2);
  v_next_balance := round((v_sale.balance_due - v_amount)::numeric, 2);
  v_next_status := case
    when v_next_balance <= 0 then 'completed'::public.sale_status
    else 'credit'::public.sale_status
  end;

  update public.sales
     set paid_amount = v_next_paid,
         balance_due = v_next_balance,
         status = v_next_status
   where id = v_sale.id;

  -- Rollup del saldo del cliente: suma de lo pendiente en sus ventas vivas.
  if v_sale.client_id is not null then
    select coalesce(round(sum(s.balance_due)::numeric, 2), 0)
      into v_client_balance
      from public.sales s
     where s.branch_id = v_branch_id
       and s.client_id = v_sale.client_id
       and s.balance_due > 0
       and s.status <> 'voided'::public.sale_status;

    update public.clients
       set balance_due = coalesce(v_client_balance, 0)
     where id = v_sale.client_id and branch_id = v_branch_id;
  end if;

  return jsonb_build_object(
    'sale_id', v_sale.id,
    'paid_amount', v_next_paid,
    'balance_due', v_next_balance,
    'status', v_next_status,
    'client_balance_due', coalesce(v_client_balance, 0),
    'cash_session_id', v_session_id
  );
end;
$$;

grant execute on function public.register_sale_payment(
  uuid, numeric, text, text, text, uuid
) to authenticated;


-- ----------------------------------------------------------------------------
-- 2) register_supplier_payment — abono a una compra (Cuentas por pagar).
-- ----------------------------------------------------------------------------
create or replace function public.register_supplier_payment(
  p_purchase_id uuid,
  p_amount numeric,
  p_payment_method text default 'cash',
  p_reference text default null,
  p_notes text default null,
  p_cash_session_id uuid default null
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_user_id uuid := auth.uid();
  v_branch_id uuid := public.current_branch_id();
  v_purchase public.purchases%rowtype;
  v_amount numeric(14,2);
  v_method public.payment_method;
  v_session_id uuid;
  v_next_paid numeric(14,2);
  v_next_balance numeric(14,2);
  v_supplier_balance numeric(14,2);
begin
  if v_user_id is null then
    raise exception 'No hay sesión activa.' using errcode = '28000';
  end if;
  if v_branch_id is null then
    raise exception 'No hay sucursal asignada para este usuario.'
      using errcode = '22023';
  end if;

  begin
    v_method := coalesce(nullif(btrim(p_payment_method), ''), 'cash')
      ::public.payment_method;
  exception
    when invalid_text_representation then
      raise exception 'Método de pago no soportado: %', p_payment_method
        using errcode = '22023';
  end;

  v_amount := round(coalesce(p_amount, 0)::numeric, 2);
  if v_amount <= 0 then
    raise exception 'El monto debe ser mayor que 0.' using errcode = '22023';
  end if;

  select * into v_purchase
    from public.purchases
   where id = p_purchase_id and branch_id = v_branch_id
   for update;

  if not found then
    raise exception 'La compra no existe en esta sucursal.' using errcode = '23503';
  end if;
  if not public.has_branch_access(v_purchase.branch_id) then
    raise exception 'No tienes acceso a la sucursal de esta compra.'
      using errcode = '42501';
  end if;
  if coalesce(v_purchase.balance_due, 0) <= 0 then
    raise exception 'La compra no tiene saldo pendiente.' using errcode = '22023';
  end if;
  if v_amount > round(v_purchase.balance_due::numeric, 2) then
    raise exception 'El abono (%) no puede exceder el saldo pendiente (%).',
      v_amount, round(v_purchase.balance_due::numeric, 2) using errcode = '22023';
  end if;

  v_session_id := p_cash_session_id;
  if v_session_id is null then
    select cs.id into v_session_id
      from public.cash_sessions cs
     where cs.branch_id = v_branch_id
       and cs.status = 'open'
       and (
         cs.opened_by = v_user_id
         or exists (
           select 1 from public.cash_register_users cru
           where cru.cash_register_id = cs.cash_register_id
             and cru.user_id = v_user_id
             and cru.is_active
         )
       )
     order by cs.opened_at desc
     limit 1;
  end if;

  insert into public.supplier_payments (
    branch_id, purchase_id, supplier_id, cash_session_id, payment_method,
    amount, paid_at, reference, notes
  ) values (
    -- `supplier_payments.payment_method` es TEXT (no el enum), por eso el
    -- cast explícito: valida el método contra el enum y guarda su texto.
    v_branch_id, v_purchase.id, v_purchase.supplier_id, v_session_id,
    v_method::text,
    v_amount, timezone('utc', now()),
    nullif(btrim(coalesce(p_reference, '')), ''),
    nullif(btrim(coalesce(p_notes, '')), '')
  );

  v_next_paid := round(
    (coalesce(v_purchase.paid_amount, 0) + v_amount)::numeric, 2
  );
  v_next_balance := round((v_purchase.balance_due - v_amount)::numeric, 2);

  update public.purchases
     set paid_amount = v_next_paid,
         balance_due = v_next_balance
   where id = v_purchase.id;

  if v_purchase.supplier_id is not null then
    select coalesce(round(sum(p.balance_due)::numeric, 2), 0)
      into v_supplier_balance
      from public.purchases p
     where p.branch_id = v_branch_id
       and p.supplier_id = v_purchase.supplier_id
       and p.balance_due > 0
       and p.status <> 'cancelled';

    update public.suppliers
       set balance_due = coalesce(v_supplier_balance, 0)
     where id = v_purchase.supplier_id and branch_id = v_branch_id;
  end if;

  return jsonb_build_object(
    'purchase_id', v_purchase.id,
    'paid_amount', v_next_paid,
    'balance_due', v_next_balance,
    'supplier_balance_due', coalesce(v_supplier_balance, 0),
    'cash_session_id', v_session_id
  );
end;
$$;

grant execute on function public.register_supplier_payment(
  uuid, numeric, text, text, text, uuid
) to authenticated;

notify pgrst, 'reload schema';
