-- ============================================================================
-- 20260830_66_convert_expired_quotation.sql
--
-- Convertir a venta una cotización VENCIDA.
--
-- Hasta ahora `convert_quotation_to_sale` rechazaba dos veces una cotización
-- fuera de vigencia:
--
--   1) `status <> 'approved'` → una cotización aprobada que se vencía pasaba a
--      `expired` (por el job `expire_overdue_quotations`) y dejaba de calificar.
--   2) `valid_until < now()` → además marcaba la cotización como vencida y
--      abortaba con "no puede convertirse sin revalidación".
--
-- Resultado: el cliente volvía con la cotización pasada de fecha y había que
-- editarla, empujar la vigencia y guardar antes de poder cobrarla. Esta
-- migración elimina ese paso: `expired` pasa a ser un estado convertible y la
-- fecha de vigencia queda como dato informativo.
--
-- Sigue bloqueado (sin cambios):
--   · convertir dos veces la misma cotización,
--   · convertir una perdida (`rejected`) o una vigente sin aprobar
--     (`draft` / `sent` / `under_review`),
--   · convertir una cotización sin líneas.
--
-- Copia FIEL de la función de la migración 63; los ÚNICOS cambios son el
-- bloque de validación de estado/vigencia y una clave extra en el evento.
--
-- Ejecutar en el SQL Editor de Supabase, DESPUÉS de:
--   supabase/sql-next/20260810_63_short_sale_numbers.sql
-- Idempotente (CREATE OR REPLACE sobre la misma firma).
-- ============================================================================

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

  -- CAMBIO (migración 66): el vencimiento ya NO bloquea la conversión.
  --
  -- Antes esto eran dos validaciones: status = 'approved' y valid_until en el
  -- futuro. En la práctica el cliente vuelve días después con la cotización en
  -- la mano y había que revalidarla (mover la fecha, guardar, recién ahí
  -- cobrar). Ahora `expired` es un estado convertible más.
  --
  -- Nota: el job `expire_overdue_quotations()` pisa el estado anterior al
  -- vencer (draft/sent/under_review/approved → expired), así que una vez
  -- vencida no queda rastro de si llegó a aprobarse; por eso `expired` se
  -- acepta sin más. Lo que sigue bloqueado es convertir algo que nunca se
  -- aprobó y todavía está vigente (borrador, enviada, en revisión) y lo
  -- explícitamente perdido (`rejected`).
  if v_quote.status not in ('approved'::public.quote_status,
                            'expired'::public.quote_status) then
    raise exception 'Solo las cotizaciones aprobadas o vencidas pueden convertirse en venta.';
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
      'status', 'completed',
      -- Queda registrado si se cobró vencida, para auditoría comercial.
      'converted_expired', (v_quote.valid_until < timezone('utc', now()))
    ),
    v_user_id
  );

  return query select v_sale_id, v_sale_number;
end;
$$;

grant execute on function public.convert_quotation_to_sale(uuid, public.receipt_type, public.payment_method, uuid) to authenticated;

notify pgrst, 'reload schema';
