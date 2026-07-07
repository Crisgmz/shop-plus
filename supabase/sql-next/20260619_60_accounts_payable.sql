-- ============================================================================
-- Migración 60 — Cuentas por Pagar (payables)
-- ============================================================================
-- Espejo del modelo de Cuentas por Cobrar (ventas a crédito + tabla payments),
-- pero para compras a crédito y pagos a proveedores.
--
--   - purchases gana paid_amount / balance_due / due_date (como sales).
--     Al crear una compra, la app captura cuánto se pagó ahora; el resto queda
--     como saldo (balance_due > 0 = cuenta por pagar).
--   - suppliers gana balance_due (total adeudado, rollup como clients).
--   - Nueva tabla supplier_payments (espejo de payments) para los abonos.
--
-- Las compras EXISTENTES se dan por pagadas (balance_due = 0) para no volverlas
-- payables retroactivamente. La actualización de saldos al abonar se hace en la
-- app (Dart), igual que Cobros — no hay trigger.
--
-- Ejecutar en el SQL Editor de Supabase. Idempotente.
-- ============================================================================

begin;

-- ── 1) Columnas de pago en purchases ───────────────────────────────────────
alter table public.purchases
  add column if not exists paid_amount numeric(14,2) not null default 0
    check (paid_amount >= 0),
  add column if not exists balance_due numeric(14,2) not null default 0
    check (balance_due >= 0),
  add column if not exists due_date date;

-- Backfill: compras previas se consideran pagadas (contado) para que no
-- aparezcan como cuentas por pagar. Solo las nuevas (con captura de pago)
-- tendrán balance_due > 0.
update public.purchases
   set paid_amount = total_amount, balance_due = 0
 where paid_amount = 0 and balance_due = 0 and status <> 'cancelled';

-- ── 2) Saldo adeudado por proveedor (rollup, como clients.balance_due) ──────
alter table public.suppliers
  add column if not exists balance_due numeric(14,2) not null default 0;

-- ── 3) Tabla de pagos a proveedores (espejo de payments) ────────────────────
create table if not exists public.supplier_payments (
  id uuid primary key default gen_random_uuid(),
  branch_id uuid not null references public.branches(id) on delete cascade,
  purchase_id uuid,
  supplier_id uuid,
  cash_session_id uuid,
  payment_method text not null default 'cash',
  amount numeric(14,2) not null check (amount > 0),
  paid_at timestamptz not null default timezone('utc', now()),
  reference text,
  notes text,
  created_at timestamptz not null default timezone('utc', now()),
  created_by uuid references auth.users(id),
  constraint supplier_payments_purchase_fk
    foreign key (purchase_id, branch_id)
    references public.purchases(id, branch_id)
    on delete cascade,
  constraint supplier_payments_supplier_fk
    foreign key (supplier_id, branch_id)
    references public.suppliers(id, branch_id)
    on delete restrict,
  constraint supplier_payments_cash_session_fk
    foreign key (cash_session_id, branch_id)
    references public.cash_sessions(id, branch_id)
    on delete restrict,
  constraint supplier_payments_requires_target
    check (purchase_id is not null or supplier_id is not null)
);

create index if not exists idx_supplier_payments_branch
  on public.supplier_payments(branch_id);
create index if not exists idx_supplier_payments_purchase
  on public.supplier_payments(purchase_id);
create index if not exists idx_supplier_payments_supplier
  on public.supplier_payments(supplier_id);

-- ── 4) RLS (mismo patrón que payments) ──────────────────────────────────────
alter table public.supplier_payments enable row level security;

drop policy if exists supplier_payments_select on public.supplier_payments;
create policy supplier_payments_select
  on public.supplier_payments for select to authenticated
  using (public.has_branch_access(branch_id));

drop policy if exists supplier_payments_insert on public.supplier_payments;
create policy supplier_payments_insert
  on public.supplier_payments for insert to authenticated
  with check (public.has_branch_access(branch_id) and public.can_operate_pos());

drop policy if exists supplier_payments_update on public.supplier_payments;
create policy supplier_payments_update
  on public.supplier_payments for update to authenticated
  using (public.has_branch_access(branch_id) and public.can_operate_pos())
  with check (public.has_branch_access(branch_id) and public.can_operate_pos());

drop policy if exists supplier_payments_delete on public.supplier_payments;
create policy supplier_payments_delete
  on public.supplier_payments for delete to authenticated
  using (public.has_branch_access(branch_id) and public.can_manage_branch_data());

commit;

notify pgrst, 'reload schema';
