-- =====================================================================
-- 20260810_63_short_sale_numbers.sql
--
-- Números de venta cortos y correlativos por sucursal.
--
-- Problema: los RPC de checkout generan el número con timestamp + sufijo
-- aleatorio, p. ej. `VTA-20260810-173521603-99DB` (27 caracteres). En la
-- factura impresa es ilegible y el cliente no puede dictarlo por teléfono.
--
-- Solución: un contador por sucursal y un trigger BEFORE INSERT en
-- `public.sales` que reemplaza ese número autogenerado por
-- `<prefix_sale>-NNNNNN` (6 dígitos), p. ej. `FA-000123`. El prefijo sale de
-- `app_settings.prefix_sale` (por defecto 'FA') de la empresa dueña de la
-- sucursal, igual que `return_number` usa `prefix_credit_note`.
--
-- Se hace con trigger — y no editando cada RPC — porque hoy hay varias
-- funciones que insertan en `sales` (checkout, cuentas guardadas, conversión
-- de cotización, ventas a crédito). El trigger las cubre a todas y sobrevive
-- a futuras versiones de esos RPC.
--
-- Compatibilidad:
--   · Las ventas YA existentes conservan su número `VTA-…` — no se tocan.
--   · Solo se reemplaza el número si viene NULL o empieza con 'VTA-' (la
--     marca de "autogenerado por un RPC"). Un número reusado — la cuenta
--     guardada que se reabre y se cobra conserva el suyo — ya viene en el
--     formato corto y se respeta tal cual.
-- =====================================================================

-- ── 1) Contador por sucursal ─────────────────────────────────────────

create table if not exists public.sale_number_counters (
  branch_id   uuid primary key references public.branches(id) on delete cascade,
  last_number bigint not null default 0,
  updated_at  timestamptz not null default now()
);

-- Nadie toca esta tabla directamente desde el cliente: se manipula solo
-- dentro de `next_sale_number` (SECURITY DEFINER). RLS activo y sin políticas
-- = acceso denegado por PostgREST.
alter table public.sale_number_counters enable row level security;

comment on table public.sale_number_counters is
  'Correlativo de sale_number por sucursal. Solo lo escribe next_sale_number().';

-- ── 2) Siguiente número ──────────────────────────────────────────────

create or replace function public.next_sale_number(p_branch_id uuid)
returns text
language plpgsql
security definer
set search_path = public
as $$
declare
  v_next   bigint;
  v_prefix text;
begin
  -- Semilla del contador: el mayor correlativo ya emitido con este formato.
  -- Solo aplica la primera vez (o si se borró la fila): evita repetir números
  -- si la migración se corre de nuevo sobre una base que ya emitió facturas
  -- cortas. Los números legacy `VTA-…` no matchean y quedan fuera.
  insert into public.sale_number_counters (branch_id, last_number)
  values (
    p_branch_id,
    coalesce(
      (
        select max(substring(s.sale_number from '(\d{1,9})$')::bigint)
          from public.sales s
         where s.branch_id = p_branch_id
           and s.sale_number ~ '^[A-Z0-9]{1,10}-\d{1,9}$'
      ),
      0
    )
  )
  on conflict (branch_id) do nothing;

  -- El UPDATE toma un row lock: dos cajas vendiendo a la vez se serializan
  -- aquí y ninguna repite número.
  update public.sale_number_counters
     set last_number = last_number + 1,
         updated_at  = now()
   where branch_id = p_branch_id
  returning last_number into v_next;

  select coalesce(nullif(btrim(s.prefix_sale), ''), 'FA')
    into v_prefix
    from public.app_settings s
    join public.branches b on b.company_id = s.company_id
   where b.id = p_branch_id;

  return coalesce(v_prefix, 'FA') || '-' || lpad(v_next::text, 6, '0');
end;
$$;

comment on function public.next_sale_number(uuid) is
  'Correlativo de factura de 6 dígitos con el prefijo de app_settings.prefix_sale.';

-- Solo el trigger la usa: llamarla suelta desde el cliente quemaría números.
revoke all on function public.next_sale_number(uuid) from public;

-- ── 3) Trigger: reemplazar el número autogenerado ────────────────────

create or replace function public.tg_sales_short_number()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  -- 'VTA-…' es la firma de los números que arman los RPC de checkout. Un
  -- número reusado o cargado a mano no la tiene y se deja intacto.
  if new.sale_number is null or new.sale_number like 'VTA-%' then
    new.sale_number := public.next_sale_number(new.branch_id);
  end if;
  return new;
end;
$$;

drop trigger if exists trg_sales_short_number on public.sales;
create trigger trg_sales_short_number
  before insert on public.sales
  for each row
  execute function public.tg_sales_short_number();

-- El trigger corre DESPUÉS de trg_sales_assign_ncf y trg_sales_audit_fields
-- (orden alfabético entre BEFORE INSERT), y antes de cualquier AFTER INSERT
-- — así `trg_sales_register_fiscal_document` guarda ya el número corto en el
-- payload del comprobante fiscal.


-- ----------------------------------------------------------------------------
-- 4) convert_quotation_to_sale — copia de la 62 + dos cambios.
-- ----------------------------------------------------------------------------
-- Es el tercer RPC que inserta en `sales`. Los otros dos (checkout y hold) se
-- corrigen en la migración 64, que ya los reescribe. Copia FIEL de la 62 con
-- dos únicos cambios:
--
--   1) Leer `sale_number` de vuelta en el RETURNING, para devolver el
--      correlativo corto que asignó el trigger y no el provisional.
--   2) Copiar a `sales.client_name_snapshot` el nombre escrito a mano en la
--      cotización (ver migración 65), para que la factura de una venta
--      convertida diga a quién se le vendió y no "Consumidor Final".
create or replace function public.convert_quotation_to_sale(
  target_quotation_id uuid,
  requested_receipt_type public.receipt_type default 'consumer_final',
  requested_payment_method public.payment_method default 'cash',
  requested_cash_session_id uuid default null
)
returns table (sale_id uuid, sale_number text)
language plpgsql
security definer
set search_path = public
as $$
declare
  v_user_id uuid := auth.uid();
  v_quote public.quotations%rowtype;
  v_sale_id uuid;
  v_sale_number text;
  v_note_suffix text;
  v_session_id uuid;
begin
  if v_user_id is null then
    raise exception 'No hay sesión activa.';
  end if;

  if not public.can_operate_pos() then
    raise exception 'El usuario no tiene permisos para convertir cotizaciones en ventas.';
  end if;

  select *
    into v_quote
  from public.quotations q
  where q.id = target_quotation_id
  for update;

  if not found then
    raise exception 'La cotización no existe.';
  end if;

  if not public.has_branch_access(v_quote.branch_id) then
    raise exception 'No tienes acceso a la sucursal de esta cotización.';
  end if;

  if v_quote.converted_sale_id is not null or v_quote.status = 'converted' then
    raise exception 'La cotización ya fue convertida previamente.';
  end if;

  if v_quote.status <> 'approved' then
    raise exception 'Solo las cotizaciones aprobadas pueden convertirse en venta.';
  end if;

  if v_quote.valid_until < timezone('utc', now()) then
    update public.quotations
      set status = 'expired',
          expired_at = timezone('utc', now())
    where id = v_quote.id;
    raise exception 'La cotización está vencida y no puede convertirse sin revalidación.';
  end if;

  if not exists (
    select 1 from public.quotation_items qi where qi.quotation_id = v_quote.id
  ) then
    raise exception 'La cotización no tiene líneas para convertir.';
  end if;

  -- NOTA: se OMITE a propósito la validación de stock. Convertir una cotización
  -- a venta puede dejar el inventario en 0 o negativo (decisión del negocio).
  -- Las ventas normales del POS siguen validando stock; esto solo aplica aquí.

  -- Sesión de caja: la enviada por el cliente, o la abierta del usuario, o null.
  v_session_id := requested_cash_session_id;
  if v_session_id is null then
    select cs.id
      into v_session_id
    from public.cash_sessions cs
    where cs.branch_id = v_quote.branch_id
      and cs.status = 'open'
      and cs.opened_by = v_user_id
    order by cs.opened_at desc
    limit 1;
  end if;

  v_sale_number := format('VTA-Q-%s', to_char(clock_timestamp(), 'YYYYMMDD-HH24MISSMS'));
  v_note_suffix := coalesce(v_quote.notes || E'\n\n', '') ||
    format('Origen: cotización %s', v_quote.code);

  -- Venta PAGADA (completed): paid = total, balance = 0.
  insert into public.sales (
    branch_id, sale_number, client_id, client_name_snapshot, cashier_id, cash_session_id,
    receipt_type, status,
    sale_date, notes, subtotal, discount_amount, tax_amount, total_amount, paid_amount, balance_due,
    source_quotation_id, source_quotation_code
  )
  values (
    v_quote.branch_id, v_sale_number, v_quote.client_id,
    -- Nombre escrito a mano en la cotización: sin ficha de cliente es el único
    -- rastro de a quién se le vendió, así que viaja a la venta para que la
    -- factura no diga "Consumidor Final". Con ficha no hace falta (el nombre
    -- sale de clients) y el placeholder no se copia.
    case
      when v_quote.client_id is not null then null
      when btrim(coalesce(v_quote.client_display_name, '')) in ('', 'Cliente general') then null
      else btrim(v_quote.client_display_name)
    end,
    v_user_id, v_session_id, requested_receipt_type, 'completed',
    timezone('utc', now()), v_note_suffix, v_quote.subtotal, v_quote.discount_amount, v_quote.tax_amount, v_quote.total_amount,
    v_quote.total_amount, 0, v_quote.id, v_quote.code
  )
  -- `sale_number` vuelve en el RETURNING: el trigger trg_sales_short_number
  -- reemplaza el número autogenerado por el correlativo corto, y quien
  -- convierte la cotización tiene que ver ESE número, no el provisional.
  -- Calificado con el nombre de la tabla A PROPÓSITO: el RETURNS TABLE de esta
  -- función expone `sale_number` como columna OUT, así que sin calificar
  -- Postgres falla con "column reference sale_number is ambiguous".
  returning sales.id, sales.sale_number into v_sale_id, v_sale_number;

  -- Líneas (el trigger de stock descuenta inventario; puede quedar negativo).
  insert into public.sale_items (
    sale_id, branch_id, product_id, description, quantity, unit_price, discount_amount,
    tax_rate, line_subtotal, line_tax, line_total
  )
  select
    v_sale_id, qi.branch_id, qi.product_id, qi.description, qi.quantity, qi.unit_price, qi.discount_amount,
    qi.tax_rate, qi.line_subtotal, qi.line_tax, qi.line_total
  from public.quotation_items qi
  where qi.quotation_id = v_quote.id;

  -- Pago por el total (la tabla payments exige amount > 0). Si el total es 0
  -- (cotización sin monto) no se inserta pago, pero la venta igual queda pagada.
  if v_quote.total_amount > 0 then
    insert into public.payments (
      branch_id, sale_id, client_id, cash_session_id, payment_method, amount, paid_at
    )
    values (
      v_quote.branch_id, v_sale_id, v_quote.client_id, v_session_id, requested_payment_method,
      v_quote.total_amount, timezone('utc', now())
    );
  end if;

  update public.quotations
     set status = 'converted',
         converted_sale_id = v_sale_id,
         converted_at = timezone('utc', now()),
         converted_by = v_user_id
   where id = v_quote.id;

  insert into public.quotation_events (
    quotation_id, branch_id, event_type, payload, created_by
  )
  values (
    v_quote.id, v_quote.branch_id, 'converted_to_sale',
    jsonb_build_object(
      'sale_id', v_sale_id,
      'sale_number', v_sale_number,
      'requested_receipt_type', requested_receipt_type,
      'payment_method', requested_payment_method,
      'status', 'completed'
    ),
    v_user_id
  );

  return query select v_sale_id, v_sale_number;
end;
$$;

grant execute on function public.convert_quotation_to_sale(uuid, public.receipt_type, public.payment_method, uuid) to authenticated;
