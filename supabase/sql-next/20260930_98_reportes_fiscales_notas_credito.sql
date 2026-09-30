-- ============================================================================
-- 20260930_98_reportes_fiscales_notas_credito.sql
--
-- Reportes después de la auditoría del 30 sep 2026. Correr DESPUÉS de la 97.
--
-- 1) dgii_607_data: incluye las Notas de Crédito fiscales (B04) de las
--    devoluciones, con el NCF que modifican. Antes el 607 no tenía ninguna
--    y no cuadraba con el IT-1.
-- 2) dgii_608_data (NUEVO): comprobantes anulados del mes, con el tipo de
--    anulación DGII que se elige al anular (migración 97).
-- 3) dgii_it1_summary:
--    · meses en la zona horaria de la sucursal (como el 607); en UTC las
--      ventas de 8 a 12 de la noche del último día caían en el mes siguiente;
--    · bases gravada y exenta desde las líneas (las columnas de la venta
--      nunca se llenaban: salían en 0);
--    · ventas sin comprobante fuera del ITBIS (se informan aparte);
--    · ITBIS pagado solo de compras válidas para el 606 (NCF y RNC);
--    · devoluciones: solo las notas de crédito fiscales.
-- 4) Ventas a crédito en los reportes de ventas (por día, artículo,
--    categoría e impuestos) desde el día en que se venden. Antes no salían
--    hasta cobrarse y entonces aparecían con la fecha vieja.
-- 5) report_pl: ingresos sin ITBIS, ventas a crédito incluidas, y el costo
--    de lo devuelto vuelve al inventario (una venta devuelta completa daba
--    pérdida por su costo).
-- 6) El documento fiscal de cada venta toma el emisor (nombre y RNC) de la
--    empresa de la sucursal, no de la fila residual `app_settings id = 1`
--    que lo dejaba en blanco; y se completa en los que ya estaban vacíos.
-- 7) KPIs del dashboard (hoy / mes) en hora dominicana, no UTC.
--
-- Idempotente (create or replace). Base compartida con flutter_shop+: las
-- firmas no cambian y las columnas de las vistas son las mismas.
-- ============================================================================

begin;

-- ── 1) 607 ──────────────────────────────────────────────────────────────────

create or replace function public.dgii_607_data(
  p_year integer,
  p_month integer,
  p_branch_id uuid default null
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_branch_id uuid;
  v_period text;
  v_rnc text;
  v_tz text;
  v_rows jsonb;
  v_inconsistencies jsonb;
  v_total_count integer;
begin
  v_branch_id := coalesce(p_branch_id, public.current_branch_id());

  if v_branch_id is null then
    raise exception 'No hay sucursal asignada';
  end if;

  if not (public.is_admin()
          or public.current_user_role() = 'accountant'::public.app_role) then
    raise exception 'Solo admin o accountant pueden generar reportes fiscales';
  end if;

  -- Migración 87: faltaba comprobar la SUCURSAL.
  if not public.can_access_branch(v_branch_id) then
    raise exception 'Sin acceso a la sucursal indicada';
  end if;

  if p_month < 1 or p_month > 12 then
    raise exception 'Mes inválido (1-12)';
  end if;

  v_period := lpad(p_year::text, 4, '0') || lpad(p_month::text, 2, '0');

  -- Migración 87: el RNC sale de la empresa DUEÑA de esta sucursal.
  select coalesce(s.company_tax_id, '')::text into v_rnc
    from public.app_settings s
    join public.branches b on b.company_id = s.company_id
   where b.id = v_branch_id
   limit 1;

  select coalesce(nullif(b.timezone_name, ''), 'America/Santo_Domingo')
    into v_tz
    from public.branches b
   where b.id = v_branch_id;
  v_tz := coalesce(v_tz, 'America/Santo_Domingo');

  select
    coalesce(
      jsonb_agg(
        jsonb_build_object(
          'rnc_cliente', client_doc,
          'tipo_id', case
                       when length(coalesce(client_doc, '')) >= 11 then '2'
                       when length(coalesce(client_doc, '')) >= 9 then '1'
                       else '3'
                     end,
          'ncf', ncf,
          -- CAMBIO 98: las notas de crédito (B04) llevan el NCF que modifican.
          'ncf_modificado', ncf_modificado,
          'tipo_ingreso', tipo_ingreso,
          'fecha_comprobante', to_char(sale_local, 'YYYYMMDD'),
          'monto_facturado', subtotal,
          'itbis_facturado', tax_amount,
          'monto_total', total_amount,
          'efectivo', case when status = 'completed' then paid_amount else 0 end,
          'credito', case when status = 'credit' then total_amount else balance_due end,
          'client_name', client_name,
          -- Migración 93: datos para las 23 columnas.
          'receipt_type', receipt_type,
          'propina_legal', service_charge_amount,
          'pagos', pagos
        ) order by sale_date
      ) filter (where is_valid),
      '[]'::jsonb
    ),
    coalesce(
      jsonb_agg(
        jsonb_build_object(
          'sale_id', id,
          'sale_date', sale_date,
          'sale_number', sale_number,
          'client_name', client_name,
          'ncf', ncf,
          'reason', reason
        )
      ) filter (where not is_valid),
      '[]'::jsonb
    ),
    count(*) filter (where is_valid)
  into v_rows, v_inconsistencies, v_total_count
  from (
    select
      s.id,
      s.branch_id,
      s.sale_date,
      (s.sale_date at time zone v_tz) as sale_local,
      s.sale_number,
      s.ncf,
      null::text as ncf_modificado,
      s.receipt_type::text as receipt_type,
      s.client_id,
      s.subtotal,
      s.tax_amount,
      s.total_amount,
      s.paid_amount,
      s.balance_due,
      s.status::text as status,
      coalesce(s.service_charge_amount, 0) as service_charge_amount,
      c.document_number as client_doc,
      c.document_type::text as client_doc_type,
      c.full_name as client_name,
      case s.receipt_type
        when 'consumer_final' then '02'
        when 'fiscal_credit'  then '01'
        when 'governmental'   then '06'
        when 'special'        then '03'
        when 'export'         then '04'
        else '02'
      end as tipo_ingreso,
      -- Cobrado el mismo día de la venta (hora de la sucursal). Los cobros
      -- posteriores de una venta a crédito no la vuelven de contado.
      coalesce((
        select jsonb_object_agg(m.metodo, m.monto)
          from (
            select py.payment_method::text as metodo, sum(py.amount) as monto
              from public.payments py
             where py.sale_id = s.id
               and py.branch_id = s.branch_id
               and (py.paid_at at time zone v_tz)::date
                   <= (s.sale_date at time zone v_tz)::date
             group by py.payment_method
          ) m
      ), '{}'::jsonb) as pagos,
      (s.ncf is not null
       and public.is_valid_ncf(s.ncf)
       and (s.receipt_type <> 'fiscal_credit'::public.receipt_type
            or (c.document_number is not null
                and c.document_number <> ''))) as is_valid,
      case
        when s.ncf is null then 'NCF faltante'
        when not public.is_valid_ncf(coalesce(s.ncf, '')) then 'NCF inválido'
        when s.receipt_type = 'fiscal_credit'::public.receipt_type
             and (c.document_number is null or c.document_number = '')
          then 'Crédito fiscal sin documento de cliente'
        else 'Otra inconsistencia'
      end as reason
    from public.sales s
    left join public.clients c
      on c.id = s.client_id and c.branch_id = s.branch_id
    where s.branch_id = v_branch_id
      and s.status in ('completed'::public.sale_status,
                       'credit'::public.sale_status)
      and extract(year from (s.sale_date at time zone v_tz)) = p_year
      and extract(month from (s.sale_date at time zone v_tz)) = p_month

    -- CAMBIO 98: notas de crédito fiscales (devoluciones de ventas con NCF,
    -- migración 97). Van con su NCF B04, el NCF que modifican y la fecha de
    -- la devolución; la forma de pago es cómo se reembolsó (lo aplicado al
    -- saldo de una venta a crédito va como crédito).
    union all
    select
      r.id,
      r.branch_id,
      r.return_date as sale_date,
      (r.return_date at time zone v_tz) as sale_local,
      r.return_number as sale_number,
      r.ncf,
      r.ncf_modificado,
      'credit_note'::text as receipt_type,
      r.client_id,
      r.subtotal,
      r.tax_amount,
      r.total_amount,
      r.total_amount as paid_amount,
      0::numeric as balance_due,
      'completed'::text as status,
      0::numeric as service_charge_amount,
      c.document_number as client_doc,
      c.document_type::text as client_doc_type,
      c.full_name as client_name,
      '01'::text as tipo_ingreso,
      (
        select coalesce(jsonb_object_agg(k, v) filter (where v > 0), '{}'::jsonb)
          from (values
            (case when r.refund_method in ('cash', 'card', 'transfer', 'mobile', 'check')
                  then r.refund_method else 'cash' end,
             coalesce(r.cash_refund_amount, r.total_amount - r.credit_applied)),
            ('credit', r.credit_applied)
          ) as pv(k, v)
      ) as pagos,
      (r.ncf is not null and public.is_valid_ncf(r.ncf)) as is_valid,
      case
        when r.ncf is null
          then 'Nota de crédito sin NCF (falta secuencia B04)'
        else 'NCF de nota de crédito inválido'
      end as reason
    from public.returns r
    left join public.clients c
      on c.id = r.client_id and c.branch_id = r.branch_id
    where r.branch_id = v_branch_id
      and r.receipt_type = 'credit_note'::public.receipt_type
      and extract(year from (r.return_date at time zone v_tz)) = p_year
      and extract(month from (r.return_date at time zone v_tz)) = p_month
  ) classified;

  return jsonb_build_object(
    'report_type', '607',
    'formato_version', 2,
    'period', v_period,
    'rnc_negocio', v_rnc,
    'rnc_missing', (coalesce(v_rnc, '') = ''),
    'records_count', v_total_count,
    'rows', v_rows,
    'inconsistencies', v_inconsistencies,
    'inconsistencies_count', jsonb_array_length(v_inconsistencies)
  );
end;
$$;


grant execute on function public.dgii_607_data(integer, integer, uuid) to authenticated;

-- ── 2) 608: comprobantes anulados ───────────────────────────────────────────

create or replace function public.dgii_608_data(
  p_year integer,
  p_month integer,
  p_branch_id uuid default null
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_branch_id uuid;
  v_period text;
  v_rnc text;
  v_tz text;
  v_rows jsonb;
  v_count integer;
begin
  v_branch_id := coalesce(p_branch_id, public.current_branch_id());
  if v_branch_id is null then
    raise exception 'No hay sucursal asignada';
  end if;
  if not (public.is_admin()
          or public.current_user_role() = 'accountant'::public.app_role) then
    raise exception 'Solo admin o accountant pueden generar reportes fiscales';
  end if;
  if not public.can_access_branch(v_branch_id) then
    raise exception 'Sin acceso a la sucursal indicada';
  end if;
  if p_month < 1 or p_month > 12 then
    raise exception 'Mes inválido (1-12)';
  end if;

  v_period := lpad(p_year::text, 4, '0') || lpad(p_month::text, 2, '0');

  select coalesce(s.company_tax_id, '')::text into v_rnc
    from public.app_settings s
    join public.branches b on b.company_id = s.company_id
   where b.id = v_branch_id
   limit 1;

  select coalesce(nullif(b.timezone_name, ''), 'America/Santo_Domingo')
    into v_tz
    from public.branches b
   where b.id = v_branch_id;
  v_tz := coalesce(v_tz, 'America/Santo_Domingo');

  -- Anuladas EN el mes (por fecha de anulación; las anuladas antes de la
  -- migración 97 no la tienen y se toma la última actualización). La fecha
  -- que se reporta es la del comprobante. Sin motivo guardado (anuladas
  -- desde el otro app), 04 — corrección de la información.
  select
    coalesce(jsonb_agg(
      jsonb_build_object(
        'ncf', v.ncf,
        'fecha_comprobante', to_char(v.sale_date at time zone v_tz, 'YYYYMMDD'),
        'tipo_anulacion', coalesce(v.void_reason_code, '04'),
        'sale_number', v.sale_number,
        'total_amount', v.total_amount,
        'voided_at', v.voided_on
      ) order by v.ncf
    ), '[]'::jsonb),
    count(*)
  into v_rows, v_count
  from (
    select s.ncf, s.sale_date, s.void_reason_code, s.sale_number,
           s.total_amount, coalesce(s.voided_at, s.updated_at) as voided_on
      from public.sales s
     where s.branch_id = v_branch_id
       and s.status = 'voided'::public.sale_status
       and s.ncf is not null
       and public.is_valid_ncf(s.ncf)
       and extract(year from (coalesce(s.voided_at, s.updated_at) at time zone v_tz)) = p_year
       and extract(month from (coalesce(s.voided_at, s.updated_at) at time zone v_tz)) = p_month
  ) v;

  return jsonb_build_object(
    'report_type', '608',
    'period', v_period,
    'rnc_negocio', v_rnc,
    'rnc_missing', (coalesce(v_rnc, '') = ''),
    'records_count', v_count,
    'rows', v_rows
  );
end;
$$;

grant execute on function public.dgii_608_data(integer, integer, uuid) to authenticated;

-- ── 3) IT-1 ─────────────────────────────────────────────────────────────────

create or replace function public.dgii_it1_summary(
  p_year integer,
  p_month integer,
  p_branch_id uuid default null
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_branch_id uuid;
  v_period text;
  v_rnc text;
  v_tz text;
  v_start timestamptz;
  v_end timestamptz;
  v_sales_total numeric(14,2) := 0;
  v_sales_taxable numeric(14,2) := 0;
  v_sales_exempt numeric(14,2) := 0;
  v_itbis_received numeric(14,2) := 0;
  v_sales_no_receipt numeric(14,2) := 0;
  v_purchases_total numeric(14,2) := 0;
  v_itbis_paid numeric(14,2) := 0;
  v_returns_total numeric(14,2) := 0;
  v_returns_itbis numeric(14,2) := 0;
begin
  v_branch_id := coalesce(p_branch_id, public.current_branch_id());
  if v_branch_id is null then
    raise exception 'No hay sucursal asignada';
  end if;
  if not (public.is_admin()
          or public.current_user_role() = 'accountant'::public.app_role) then
    raise exception 'Solo admin o accountant pueden generar reportes fiscales';
  end if;
  if not public.can_access_branch(v_branch_id) then
    raise exception 'Sin acceso a la sucursal indicada';
  end if;
  if p_month < 1 or p_month > 12 then
    raise exception 'Mes inválido (1-12)';
  end if;

  v_period := lpad(p_year::text, 4, '0') || lpad(p_month::text, 2, '0');

  select coalesce(s.company_tax_id, '')::text into v_rnc
    from public.app_settings s
    join public.branches b on b.company_id = s.company_id
   where b.id = v_branch_id
   limit 1;

  -- CAMBIO 98: el mes en la hora de la sucursal, como el 607.
  select coalesce(nullif(b.timezone_name, ''), 'America/Santo_Domingo')
    into v_tz
    from public.branches b
   where b.id = v_branch_id;
  v_tz := coalesce(v_tz, 'America/Santo_Domingo');
  v_start := make_timestamp(p_year, p_month, 1, 0, 0, 0) at time zone v_tz;
  v_end := (make_timestamp(p_year, p_month, 1, 0, 0, 0) + interval '1 month')
           at time zone v_tz;

  -- CAMBIO 98: ventas con comprobante. Base gravada / exenta desde las
  -- líneas: las columnas taxable_amount / exempt_amount de la venta nunca se
  -- llenaron.
  select
    coalesce(sum(si.line_subtotal), 0),
    coalesce(sum(si.line_subtotal) filter (where si.tax_rate > 0), 0),
    coalesce(sum(si.line_subtotal) filter (where coalesce(si.tax_rate, 0) = 0), 0),
    coalesce(sum(si.line_tax), 0)
  into v_sales_total, v_sales_taxable, v_sales_exempt, v_itbis_received
  from public.sale_items si
  join public.sales s on s.id = si.sale_id and s.branch_id = si.branch_id
  where s.branch_id = v_branch_id
    and s.status in ('completed'::public.sale_status, 'credit'::public.sale_status)
    and s.receipt_type::text <> 'none'
    and s.sale_date >= v_start
    and s.sale_date < v_end;

  -- Sin comprobante: no facturan ITBIS; se informan aparte.
  select coalesce(sum(s.total_amount), 0)
    into v_sales_no_receipt
    from public.sales s
   where s.branch_id = v_branch_id
     and s.status in ('completed'::public.sale_status, 'credit'::public.sale_status)
     and s.receipt_type::text = 'none'
     and s.sale_date >= v_start
     and s.sale_date < v_end;

  -- CAMBIO 98: ITBIS pagado solo de compras que el 606 acepta (NCF válido y
  -- RNC del proveedor).
  select
    coalesce(sum(p.total_amount), 0),
    coalesce(sum(p.tax_amount), 0)
  into v_purchases_total, v_itbis_paid
  from public.purchases p
  join public.suppliers sp on sp.id = p.supplier_id and sp.branch_id = p.branch_id
  where p.branch_id = v_branch_id
    and p.status in ('posted'::public.purchase_status, 'received'::public.purchase_status)
    and p.invoice_number is not null
    and public.is_valid_ncf(p.invoice_number)
    and coalesce(sp.rnc, '') <> ''
    and extract(year from p.purchase_date) = p_year
    and extract(month from p.purchase_date) = p_month;

  -- CAMBIO 98: solo notas de crédito fiscales. Una devolución de una venta
  -- sin comprobante no rebaja ITBIS (nunca se cobró).
  select
    coalesce(sum(r.subtotal), 0),
    coalesce(sum(r.tax_amount), 0)
  into v_returns_total, v_returns_itbis
  from public.returns r
  where r.branch_id = v_branch_id
    and r.receipt_type = 'credit_note'::public.receipt_type
    and r.ncf is not null
    and r.return_date >= v_start
    and r.return_date < v_end;

  return jsonb_build_object(
    'report_type', 'IT1',
    'period', v_period,
    'rnc_negocio', v_rnc,
    'rnc_missing', (coalesce(v_rnc, '') = ''),
    'sales_total', v_sales_total,
    'sales_taxable', v_sales_taxable,
    'sales_exempt', v_sales_exempt,
    'itbis_received', v_itbis_received,
    'sales_without_receipt', v_sales_no_receipt,
    'purchases_total', v_purchases_total,
    'itbis_paid', v_itbis_paid,
    'returns_total', v_returns_total,
    'returns_itbis', v_returns_itbis,
    'itbis_balance', v_itbis_received - v_itbis_paid - v_returns_itbis,
    'balance_direction',
      case
        when (v_itbis_received - v_itbis_paid - v_returns_itbis) > 0 then 'pagar'
        when (v_itbis_received - v_itbis_paid - v_returns_itbis) < 0 then 'favor'
        else 'cero' end
  );
end;
$$;

grant execute on function public.dgii_it1_summary(integer, integer, uuid) to authenticated;

-- ── 4) Ventas a crédito en los reportes de ventas ──────────────────────────
-- Mismas columnas que la migración 15 / 14; solo cambia el filtro de estado.

create or replace view public.sales_daily_view
with (security_invoker = true)
as
select
  s.branch_id,
  date(s.sale_date at time zone 'America/Santo_Domingo') as sale_day,
  coalesce(s.seller_id, s.cashier_id) as seller_user_id,
  s.receipt_type,
  count(*)::bigint as sales_count,
  coalesce(sum(s.subtotal), 0)::numeric(14,2) as gross_total,
  coalesce(sum(s.tax_amount), 0)::numeric(14,2) as itbis_total,
  coalesce(sum(s.service_charge_amount), 0)::numeric(14,2) as service_charge_total,
  coalesce(sum(s.discount_amount), 0)::numeric(14,2) as discount_total,
  coalesce(sum(s.total_amount), 0)::numeric(14,2) as net_total
from public.sales s
where s.status in ('completed'::public.sale_status, 'credit'::public.sale_status)
  and public.has_branch_access(s.branch_id)
group by 1, 2, 3, 4;

create or replace view public.sales_by_item_view
with (security_invoker = true)
as
select
  si.branch_id,
  date(s.sale_date at time zone 'America/Santo_Domingo') as sale_day,
  si.product_id,
  coalesce(p.name, si.description) as product_name,
  coalesce(sum(si.quantity), 0)::numeric(14,3) as units_sold,
  coalesce(sum(si.line_subtotal), 0)::numeric(14,2) as gross_total,
  coalesce(sum(si.line_tax), 0)::numeric(14,2) as itbis_total,
  coalesce(sum(si.line_total), 0)::numeric(14,2) as net_total,
  count(distinct si.sale_id)::bigint as sales_count
from public.sale_items si
join public.sales s on s.id = si.sale_id and s.branch_id = si.branch_id
left join public.products p
  on p.id = si.product_id and p.branch_id = si.branch_id
where s.status in ('completed'::public.sale_status, 'credit'::public.sale_status)
  and public.has_branch_access(si.branch_id)
group by 1, 2, 3, 4;

create or replace view public.sales_by_category_view
with (security_invoker = true)
as
select
  si.branch_id,
  date(s.sale_date at time zone 'America/Santo_Domingo') as sale_day,
  coalesce(si.category_id, p.category_id) as category_id,
  coalesce(si.category_name_snapshot, pc.name, 'Sin categoría') as category_name,
  coalesce(sum(si.quantity), 0)::numeric(14,3) as units_sold,
  coalesce(sum(si.line_subtotal), 0)::numeric(14,2) as gross_total,
  coalesce(sum(si.line_tax), 0)::numeric(14,2) as itbis_total,
  coalesce(sum(si.line_total), 0)::numeric(14,2) as net_total
from public.sale_items si
join public.sales s on s.id = si.sale_id and s.branch_id = si.branch_id
left join public.products p on p.id = si.product_id and p.branch_id = si.branch_id
left join public.product_categories pc
  on pc.id = coalesce(si.category_id, p.category_id)
  and pc.branch_id = si.branch_id
where s.status in ('completed'::public.sale_status, 'credit'::public.sale_status)
  and public.has_branch_access(si.branch_id)
group by 1, 2, 3, 4;

create or replace view public.report_tax_breakdown_view
with (security_invoker = true)
as
select
  si.branch_id,
  date(s.sale_date at time zone 'America/Santo_Domingo') as sale_day,
  si.tax_rate,
  count(distinct si.sale_id) as sales_count,
  sum(si.quantity)::numeric(14,3) as items_count,
  sum(si.line_subtotal)::numeric(14,2) as taxable_base,
  sum(si.line_tax)::numeric(14,2) as tax_amount,
  sum(si.line_total)::numeric(14,2) as total_with_tax
from public.sale_items si
join public.sales s on s.id = si.sale_id and s.branch_id = si.branch_id
where s.status in ('completed'::public.sale_status, 'credit'::public.sale_status)
  and public.has_branch_access(si.branch_id)
group by si.branch_id, date(s.sale_date at time zone 'America/Santo_Domingo'), si.tax_rate;

-- ── 5) Pérdidas y ganancias ─────────────────────────────────────────────────

create or replace function public.report_pl(
  p_from date default null,
  p_to date default null,
  p_branch_id uuid default null
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_branch_id uuid;
  v_from date;
  v_to date;
  v_start timestamptz;
  v_end timestamptz;
  v_revenue numeric(14,2);
  v_cogs numeric(14,2);
  v_returns numeric(14,2);
  v_returns_cost numeric(14,2);
  v_expenses numeric(14,2);
  v_tax_received numeric(14,2);
  v_tax_paid numeric(14,2);
  v_purchases numeric(14,2);
begin
  v_branch_id := coalesce(p_branch_id, public.current_branch_id());
  v_from := coalesce(p_from, date_trunc('month', current_date)::date);
  v_to := coalesce(p_to, current_date);

  if v_branch_id is null then
    return jsonb_build_object('partial', true);
  end if;

  if not (public.can_access_branch(v_branch_id)) then
    raise exception 'Sin acceso a la sucursal indicada';
  end if;

  v_start := (v_from::timestamp at time zone 'America/Santo_Domingo');
  v_end := ((v_to + 1)::timestamp at time zone 'America/Santo_Domingo');

  -- CAMBIO 98: ingresos SIN ITBIS (el ITBIS no es ganancia: es del fisco) y
  -- con las ventas a crédito, que también son ventas.
  select coalesce(sum(subtotal), 0),
         coalesce(sum(tax_amount), 0)
    into v_revenue, v_tax_received
    from public.sales
   where branch_id = v_branch_id
     and status in ('completed'::public.sale_status, 'credit'::public.sale_status)
     and sale_date >= v_start
     and sale_date <  v_end;

  select coalesce(sum(si.quantity * coalesce(p.cost, 0)), 0)
    into v_cogs
    from public.sale_items si
    join public.sales s on s.id = si.sale_id and s.branch_id = si.branch_id
    left join public.products p
      on p.id = si.product_id and p.branch_id = si.branch_id
   where s.branch_id = v_branch_id
     and s.status in ('completed'::public.sale_status, 'credit'::public.sale_status)
     and s.sale_date >= v_start
     and s.sale_date <  v_end;

  -- CAMBIO 98: devoluciones sin ITBIS, y su costo vuelve (la mercancía
  -- regresó al inventario). Antes una venta devuelta completa daba pérdida.
  select coalesce(sum(subtotal), 0)
    into v_returns
    from public.returns
   where branch_id = v_branch_id
     and return_date >= v_start
     and return_date <  v_end;

  select coalesce(sum(ri.quantity * coalesce(p.cost, 0)), 0)
    into v_returns_cost
    from public.return_items ri
    join public.returns r on r.id = ri.return_id and r.branch_id = ri.branch_id
    left join public.products p
      on p.id = ri.product_id and p.branch_id = ri.branch_id
   where r.branch_id = v_branch_id
     and r.return_date >= v_start
     and r.return_date <  v_end;

  select coalesce(sum(amount), 0)
    into v_expenses
    from public.expenses
   where branch_id = v_branch_id
     and expense_date >= v_from
     and expense_date <= v_to;

  select coalesce(sum(total_amount), 0),
         coalesce(sum(tax_amount), 0)
    into v_purchases, v_tax_paid
    from public.purchases
   where branch_id = v_branch_id
     and status in ('posted'::public.purchase_status, 'received'::public.purchase_status)
     and purchase_date >= v_from
     and purchase_date <= v_to;

  return jsonb_build_object(
    'from', v_from,
    'to', v_to,
    'revenue', v_revenue,
    'cogs', v_cogs - v_returns_cost,
    'returns', v_returns,
    'gross_profit', v_revenue - v_returns - (v_cogs - v_returns_cost),
    'expenses', v_expenses,
    'net_profit', (v_revenue - v_returns - (v_cogs - v_returns_cost)) - v_expenses,
    'tax_received', v_tax_received,
    'tax_paid', v_tax_paid,
    'tax_balance', v_tax_received - v_tax_paid,
    'purchases_total', v_purchases
  );
end;
$$;

grant execute on function public.report_pl(date, date, uuid) to authenticated;

-- ── 6) Emisor del documento fiscal ──────────────────────────────────────────
-- Copia fiel de la migración 21 salvo el snapshot del emisor.

create or replace function public.tg_sales_register_fiscal_document()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $$
declare
  v_seq_id              uuid;
  v_seq_number          bigint;
  v_customer_name       text;
  v_customer_legal_name text;
  v_customer_doc_type   text;
  v_customer_doc_number text;
  v_customer_address    text;
  v_issuer_name         text;
  v_issuer_legal_name   text;
  v_issuer_tax_id       text;
begin
  if new.ncf is null or length(trim(new.ncf)) = 0 then
    return new;
  end if;

  -- Localizar la secuencia que produjo este NCF (por prefijo + tipo)
  select id
    into v_seq_id
    from public.ncf_sequences
   where branch_id = new.branch_id
     and receipt_type = new.receipt_type
     and new.ncf like prefix || '%'
   order by current_number desc
   limit 1;

  -- Extraer la parte numérica del NCF
  begin
    v_seq_number := (regexp_replace(new.ncf, '\D', '', 'g'))::bigint;
  exception when others then
    v_seq_number := null;
  end;

  -- Snapshot del cliente (solo si hay client_id). Las variables escalares
  -- quedan en NULL si no hay match.
  if new.client_id is not null then
    select c.full_name,
           c.legal_name,
           c.document_type::text,
           c.document_number,
           c.address
      into v_customer_name,
           v_customer_legal_name,
           v_customer_doc_type,
           v_customer_doc_number,
           v_customer_address
      from public.clients c
     where c.id = new.client_id
       and c.branch_id = new.branch_id;
  end if;

  -- Snapshot del emisor. CAMBIO 98: de la empresa DUEÑA de la sucursal.
  -- `app_settings where id = 1` es una fila residual sin datos: todos los
  -- comprobantes quedaban con el emisor (nombre y RNC) en blanco.
  select s.company_name, s.company_legal_name, s.company_tax_id
    into v_issuer_name, v_issuer_legal_name, v_issuer_tax_id
    from public.app_settings s
    join public.branches b on b.company_id = s.company_id
   where b.id = new.branch_id
   limit 1;

  insert into public.fiscal_documents (
    branch_id, sale_id, client_id, ncf_sequence_id, receipt_type,
    ncf, sequence_number, fiscal_status, issued_at,
    customer_name, customer_document_type, customer_document_number, customer_address,
    issuer_name, issuer_tax_id,
    subtotal, discount_amount, tax_amount, total_amount,
    payload
  ) values (
    new.branch_id, new.id, new.client_id, v_seq_id, new.receipt_type,
    new.ncf, v_seq_number, 'pending'::public.dgii_status, new.sale_date,
    coalesce(nullif(v_customer_legal_name, ''), v_customer_name),
    v_customer_doc_type,
    v_customer_doc_number,
    v_customer_address,
    coalesce(nullif(v_issuer_legal_name, ''), v_issuer_name),
    v_issuer_tax_id,
    new.subtotal, new.discount_amount, new.tax_amount, new.total_amount,
    jsonb_build_object('sale_number', new.sale_number)
  )
  on conflict (branch_id, ncf) do nothing;

  return new;
end;
$$;

-- Los comprobantes que ya quedaron sin emisor lo toman de su empresa. Solo
-- se completan campos vacíos.
update public.fiscal_documents fd
   set issuer_name = coalesce(nullif(fd.issuer_name, ''),
                              nullif(s.company_legal_name, ''), s.company_name),
       issuer_tax_id = coalesce(nullif(fd.issuer_tax_id, ''), s.company_tax_id)
  from public.branches b
  join public.app_settings s on s.company_id = b.company_id
 where b.id = fd.branch_id
   and (coalesce(fd.issuer_name, '') = '' or coalesce(fd.issuer_tax_id, '') = '');

-- ── 7) KPIs del dashboard en hora dominicana ────────────────────────────────
-- "Ventas de hoy" y "del mes" se calculaban con el día y el mes UTC: a las
-- 8 de la noche "hoy" volvía a cero y el último día del mes las ventas de la
-- noche caían en el mes siguiente. Mismas columnas que la versión anterior.

create or replace view public.dashboard_kpis_by_branch as
with bounds as (
  select
    (date_trunc('month', now() at time zone 'America/Santo_Domingo')
       at time zone 'America/Santo_Domingo') as month_start,
    ((date_trunc('month', now() at time zone 'America/Santo_Domingo')
       + interval '1 month') at time zone 'America/Santo_Domingo') as next_month_start,
    (now() at time zone 'America/Santo_Domingo')::date as today_local
), sales_scope as (
  select s_1.id, s_1.branch_id, s_1.sale_date, s_1.total_amount, s_1.ncf
    from public.sales s_1
    cross join bounds mb
   where s_1.sale_date >= mb.month_start
     and s_1.sale_date < mb.next_month_start
     and s_1.status <> all (array['voided'::public.sale_status, 'pending'::public.sale_status])
), active_products as (
  select p.branch_id, count(*) as products_active
    from public.products p
   where p.is_active
   group by p.branch_id
), active_clients as (
  select c.branch_id, count(*) as clients_active
    from public.clients c
   where c.is_active
   group by c.branch_id
), ncf_usage as (
  select ns.branch_id,
         coalesce(sum(ns.current_number), 0::numeric)::bigint as ncf_consumed,
         coalesce(sum(greatest(coalesce(ns.max_number, ns.current_number), ns.current_number)
                      - ns.current_number), 0::numeric)::bigint as ncf_available
    from public.ncf_sequences ns
   where ns.is_active
   group by ns.branch_id
)
select
  b.id as branch_id,
  b.code as branch_code,
  b.name as branch_name,
  coalesce(sum(case when (s.sale_date at time zone 'America/Santo_Domingo')::date
                         = (select today_local from bounds)
                    then s.total_amount else 0::numeric end), 0::numeric)::numeric(14,2)
    as sales_today_amount,
  coalesce(sum(case when (s.sale_date at time zone 'America/Santo_Domingo')::date
                         = (select today_local from bounds)
                    then 1 else 0 end), 0::bigint) as sales_today_count,
  coalesce(sum(s.total_amount), 0::numeric)::numeric(14,2) as sales_month_amount,
  coalesce(count(s.id), 0::bigint) as sales_month_count,
  coalesce(ap.products_active, 0::bigint) as products_active,
  coalesce(ac.clients_active, 0::bigint) as clients_active,
  coalesce(sum(case when s.ncf is not null then 1 else 0 end), 0::bigint) as ecf_issued_month,
  coalesce(nu.ncf_consumed, 0::bigint) as ncf_consumed,
  coalesce(nu.ncf_available, 0::bigint) as ncf_available
from public.branches b
left join sales_scope s on s.branch_id = b.id
left join active_products ap on ap.branch_id = b.id
left join active_clients ac on ac.branch_id = b.id
left join ncf_usage nu on nu.branch_id = b.id
where public.has_branch_access(b.id)
group by b.id, b.code, b.name, ap.products_active, ac.clients_active,
         nu.ncf_consumed, nu.ncf_available;

commit;

notify pgrst, 'reload schema';
