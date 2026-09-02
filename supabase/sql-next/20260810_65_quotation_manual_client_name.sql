-- ============================================================================
-- 20260810_65_quotation_manual_client_name.sql
--
-- Permitir escribir el cliente A MANO en una cotización.
--
-- Hasta ahora el campo "Cliente" del detalle comercial solo dejaba elegir una
-- ficha del catálogo (o "Cliente general"). Para cotizar a alguien que todavía
-- no es cliente había que crearle la ficha primero.
--
-- La columna `quotations.client_display_name` ya existía y es la que se
-- muestra en el listado y en el PDF, pero `update_quotation_document` la
-- pisaba en cada guardado:
--
--     client_display_name = case when requested_client_id is null
--                                then 'Cliente general' else v_client.full_name end
--
-- ...así que cualquier nombre manual se perdía al guardar.
--
-- Esta migración agrega el parámetro `requested_client_name` (al final, con
-- DEFAULT, para no romper llamadas existentes) y hace que el nombre manual se
-- respete cuando no hay cliente del catálogo.
--
-- Los demás campos de snapshot (client_legal_name, email, teléfono, documento)
-- siguen quedando NULL sin ficha: un nombre suelto no tiene esos datos.
--
-- Copia FIEL de la función de la migración 17; los ÚNICOS cambios son el
-- parámetro nuevo y esa expresión.
--
-- Ejecutar en el SQL Editor de Supabase.
-- Idempotente (DROP IF EXISTS de la firma vieja + CREATE OR REPLACE).
-- ============================================================================

-- La firma vieja (6 argumentos) se elimina: si quedaran ambas, una llamada con
-- 6 parámetros sería ambigua y PostgREST devolvería "function is not unique".
drop function if exists public.update_quotation_document(
  uuid, uuid, public.quote_status, timestamptz, text, jsonb
);

create or replace function public.update_quotation_document(
  target_quotation_id uuid,
  requested_client_id uuid,
  requested_status public.quote_status,
  requested_valid_until timestamptz,
  requested_notes text,
  requested_items jsonb,
  requested_client_name text default null
)
returns table (quotation_id uuid)
language plpgsql
security definer
set search_path = public
as $$
declare
  v_user_id uuid := auth.uid();
  v_quote public.quotations%rowtype;
  v_branch_id uuid;
  v_subtotal numeric(14,2) := 0;
  v_tax numeric(14,2) := 0;
  v_total numeric(14,2) := 0;
  v_item jsonb;
  v_client public.clients%rowtype;
begin
  if v_user_id is null then
    raise exception 'No hay sesión activa.';
  end if;

  if not public.can_operate_pos() then
    raise exception 'El usuario no tiene permisos para editar cotizaciones.';
  end if;

  if requested_status = 'converted' then
    raise exception 'No se puede forzar estado convertido desde edición manual.';
  end if;

  if requested_valid_until <= timezone('utc', now()) then
    raise exception 'La vigencia debe estar en el futuro.';
  end if;

  if requested_items is null or jsonb_typeof(requested_items) <> 'array' or jsonb_array_length(requested_items) = 0 then
    raise exception 'La cotización debe conservar al menos una línea.';
  end if;

  select *
    into v_quote
  from public.quotations q
  where q.id = target_quotation_id
  for update;

  if not found then
    raise exception 'La cotización no existe.';
  end if;

  if v_quote.status = 'converted' or v_quote.converted_sale_id is not null then
    raise exception 'La cotización convertida ya no se puede editar.';
  end if;

  if not public.has_branch_access(v_quote.branch_id) then
    raise exception 'No tienes acceso a la sucursal de esta cotización.';
  end if;

  v_branch_id := v_quote.branch_id;

  if requested_client_id is not null then
    select *
      into v_client
    from public.clients c
    where c.id = requested_client_id
      and c.branch_id = v_branch_id;

    if not found then
      raise exception 'El cliente seleccionado no existe en esta sucursal.';
    end if;
  end if;

  for v_item in select value from jsonb_array_elements(requested_items)
  loop
    v_subtotal := v_subtotal + coalesce((v_item->>'line_subtotal')::numeric, 0);
    v_tax := v_tax + coalesce((v_item->>'line_tax')::numeric, 0);
    v_total := v_total + coalesce((v_item->>'line_total')::numeric, 0);
  end loop;

  update public.quotations
     set client_id = requested_client_id,
         status = requested_status,
         valid_until = requested_valid_until,
         notes = nullif(btrim(requested_notes), ''),
         subtotal = round(v_subtotal, 2),
         tax_amount = round(v_tax, 2),
         total_amount = round(v_total, 2),
         -- Cliente del catálogo → su nombre. Si no hay, se respeta el nombre
         -- escrito a mano; y solo si tampoco hay, el placeholder.
         client_display_name = case
           when requested_client_id is not null then v_client.full_name
           else coalesce(nullif(btrim(requested_client_name), ''), 'Cliente general')
         end,
         client_legal_name = case when requested_client_id is null then null else nullif(v_client.legal_name, '') end,
         client_email = case when requested_client_id is null then null else nullif(v_client.email, '') end,
         client_phone = case when requested_client_id is null then null else nullif(v_client.phone, '') end,
         client_document_type = case when requested_client_id is null then null else nullif(v_client.document_type, '') end,
         client_document_number = case when requested_client_id is null then null else nullif(v_client.document_number, '') end,
         sent_at = case
           when requested_status = 'sent' and quotations.sent_at is null then timezone('utc', now())
           else quotations.sent_at
         end,
         approved_at = case
           when requested_status = 'approved' and quotations.approved_at is null then timezone('utc', now())
           when requested_status <> 'approved' then null
           else quotations.approved_at
         end,
         rejected_at = case
           when requested_status = 'rejected' and quotations.rejected_at is null then timezone('utc', now())
           when requested_status <> 'rejected' then null
           else quotations.rejected_at
         end,
         expired_at = case
           when requested_status = 'expired' then timezone('utc', now())
           else null
         end,
         updated_by = v_user_id
   where quotations.id = target_quotation_id;

  -- FIX ambigüedad: el RETURNS TABLE expone `quotation_id` como OUT column,
  -- así que aquí calificamos con el nombre de la tabla.
  delete from public.quotation_items qi
  where qi.quotation_id = target_quotation_id;

  insert into public.quotation_items (
    quotation_id,
    branch_id,
    product_id,
    product_name,
    product_sku,
    description,
    quantity,
    unit_price,
    discount_amount,
    tax_rate,
    line_subtotal,
    line_tax,
    line_total,
    created_by,
    updated_by
  )
  select
    target_quotation_id,
    v_branch_id,
    (item->>'product_id')::uuid,
    coalesce(nullif(item->>'product_name', ''), item->>'description'),
    nullif(item->>'product_sku', ''),
    coalesce(nullif(item->>'description', ''), item->>'product_name'),
    coalesce((item->>'quantity')::numeric, 0),
    coalesce((item->>'unit_price')::numeric, 0),
    coalesce((item->>'discount_amount')::numeric, 0),
    coalesce((item->>'tax_rate')::numeric, 0),
    coalesce((item->>'line_subtotal')::numeric, 0),
    coalesce((item->>'line_tax')::numeric, 0),
    coalesce((item->>'line_total')::numeric, 0),
    v_user_id,
    v_user_id
  from jsonb_array_elements(requested_items) as item;

  insert into public.quotation_events (
    quotation_id,
    branch_id,
    event_type,
    payload,
    created_by
  )
  values (
    target_quotation_id,
    v_branch_id,
    'updated',
    jsonb_build_object(
      'status', requested_status,
      'valid_until', requested_valid_until,
      'items_count', jsonb_array_length(requested_items),
      'total_amount', round(v_total, 2)
    ),
    v_user_id
  );

  return query select target_quotation_id;
end;
$$;

grant execute on function public.update_quotation_document(
  uuid, uuid, public.quote_status, timestamptz, text, jsonb, text
) to authenticated;

notify pgrst, 'reload schema';
