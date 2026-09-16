-- ============================================================================
-- 20260916_93_dgii_606_607_formato_completo.sql
--
-- Los datos que faltaban para llenar las 23 columnas del 606 y del 607
-- (Norma General 07-2018, herramientas de envío DGII). Ver docs/DGII_606_607.md.
--
-- Hasta ahora el app solo podía emitir 9 columnas del 606 y 10 del 607, y con
-- tres valores mal: todo el cobro caía en "Efectivo" (aunque fuera tarjeta o
-- transferencia), el 606 no sabía la forma de pago y la fecha de pago era la
-- de la compra. El app arma ahora las 23 columnas; esta migración le da los
-- datos crudos.
--
-- Cada fila de `rows` GANA estas claves (las que ya existían no cambian, así
-- el otro app — flutter_shop+ — sigue funcionando igual):
--
--   607 (ventas)
--     receipt_type      tipo de comprobante (para separar facturas de consumo)
--     propina_legal     sales.service_charge_amount (casilla 16)
--     pagos             {"cash": 100.00, "card": 18.00, ...} cobrado EL MISMO
--                       DÍA de la venta. Lo cobrado después (cobros de una venta
--                       a crédito) no cambia el tipo de venta: sigue a crédito.
--                       Si suma más que el total, la diferencia es la devuelta.
--
--   606 (compras)
--     monto_servicios   subtotal de las líneas cuyo producto es servicio
--     pagos             {"cash": ..., "transfer": ..., "check": ...} de
--                       supplier_payments (abonos registrados)
--     pagado            purchases.paid_amount (incluye lo pagado al registrar
--                       la compra, que no tiene método)
--     saldo             purchases.balance_due (lo que queda a crédito)
--     fecha_ultimo_pago AAAAMMDD del último abono, o null
--
-- Y el JSON gana `formato_version: 2`, con el que el app sabe que ya puede
-- desglosar. Sin esta migración el app sigue generando el archivo, pero avisa
-- que la forma de pago no está desglosada.
--
-- Además el mes y la fecha del comprobante del 607 se calculan en la hora de
-- la sucursal (branches.timezone_name, por defecto America/Santo_Domingo), no
-- en UTC. Antes una venta de las 9:00 p.m. del 31 caía en el mes siguiente y
-- con fecha del día 1.
--
-- Lo demás no cambia: las ventas sin comprobante siguen saliendo como
-- inconsistencia "NCF faltante" (decisión documentada en DATABASE.md).
--
-- Se reemplazan las funciones completas. La definición viva es la de la
-- migración 23 + el parche de la 87 (RNC por empresa y validación de
-- sucursal); ambas cosas se conservan tal cual. El bloque inicial aborta si la
-- 87 no está aplicada, para no pisar una definición distinta a la esperada.
--
-- Ejecutar en el SQL Editor de Supabase, DESPUÉS de la 87.
-- Idempotente (CREATE OR REPLACE).
-- ============================================================================

begin;

do $guard$
declare
  v_fn text;
begin
  foreach v_fn in array array['dgii_606_data', 'dgii_607_data'] loop
    if not exists (
      select 1
        from pg_proc p
        join pg_namespace n on n.oid = p.pronamespace
       where n.nspname = 'public'
         and p.proname = v_fn
         and (pg_get_functiondef(p.oid) like '%can_access_branch%'
              or pg_get_functiondef(p.oid) like '%formato_version%')
    ) then
      raise exception
        'public.% no tiene el parche de la migración 87. Ejecuta la 87 antes que esta.',
        v_fn;
    end if;
  end loop;
end
$guard$;

-- =====================================================
-- dgii_606_data — Compras del mes con NCF
-- =====================================================

create or replace function public.dgii_606_data(
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
          'rnc_proveedor', supplier_rnc,
          'tipo_id', case when length(coalesce(supplier_rnc, '')) >= 11 then '2' else '1' end,
          'tipo_bien_servicio', '09',
          'ncf', invoice_number,
          'ncf_modificado', null,
          'fecha_comprobante', to_char(purchase_date, 'YYYYMMDD'),
          'fecha_pago', to_char(purchase_date, 'YYYYMMDD'),
          'monto_facturado', subtotal,
          'itbis_facturado', tax_amount,
          'monto_total', total_amount,
          'supplier_name', supplier_name,
          -- Migración 93: datos para las 23 columnas.
          'monto_servicios', monto_servicios,
          'pagos', pagos,
          'pagado', paid_amount,
          'saldo', balance_due,
          'fecha_ultimo_pago', fecha_ultimo_pago
        ) order by purchase_date
      ) filter (where is_valid),
      '[]'::jsonb
    ),
    coalesce(
      jsonb_agg(
        jsonb_build_object(
          'purchase_id', id,
          'purchase_date', purchase_date,
          'supplier_name', supplier_name,
          'invoice_number', invoice_number,
          'reason', reason
        )
      ) filter (where not is_valid),
      '[]'::jsonb
    ),
    count(*) filter (where is_valid)
  into v_rows, v_inconsistencies, v_total_count
  from (
    select
      p.id,
      p.branch_id,
      p.purchase_date,
      p.invoice_number,
      p.subtotal,
      p.tax_amount,
      p.total_amount,
      p.receipt_type,
      coalesce(p.paid_amount, 0) as paid_amount,
      coalesce(p.balance_due, 0) as balance_due,
      s.rnc as supplier_rnc,
      s.legal_name as supplier_name,
      coalesce((
        select sum(pi.line_subtotal)
          from public.purchase_items pi
          join public.products pr
            on pr.id = pi.product_id and pr.branch_id = pi.branch_id
         where pi.purchase_id = p.id
           and pi.branch_id = p.branch_id
           and coalesce(pr.is_service, false)
      ), 0) as monto_servicios,
      coalesce((
        select jsonb_object_agg(m.metodo, m.monto)
          from (
            select sp.payment_method as metodo, sum(sp.amount) as monto
              from public.supplier_payments sp
             where sp.purchase_id = p.id
               and sp.branch_id = p.branch_id
             group by sp.payment_method
          ) m
      ), '{}'::jsonb) as pagos,
      (
        select to_char(max(sp.paid_at at time zone v_tz), 'YYYYMMDD')
          from public.supplier_payments sp
         where sp.purchase_id = p.id
           and sp.branch_id = p.branch_id
      ) as fecha_ultimo_pago,
      (p.invoice_number is not null
       and public.is_valid_ncf(p.invoice_number)
       and s.rnc is not null
       and s.rnc <> '') as is_valid,
      case
        when p.invoice_number is null then 'NCF faltante'
        when not public.is_valid_ncf(p.invoice_number) then 'NCF inválido'
        when s.rnc is null or s.rnc = '' then 'RNC de proveedor faltante'
        else 'Otra inconsistencia'
      end as reason
    from public.purchases p
    join public.suppliers s
      on s.id = p.supplier_id and s.branch_id = p.branch_id
    where p.branch_id = v_branch_id
      and p.status in ('posted'::public.purchase_status,
                       'received'::public.purchase_status)
      and extract(year from p.purchase_date) = p_year
      and extract(month from p.purchase_date) = p_month
  ) classified;

  return jsonb_build_object(
    'report_type', '606',
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

grant execute on function public.dgii_606_data(integer, integer, uuid) to authenticated;

-- =====================================================
-- dgii_607_data — Ventas del mes con NCF
-- =====================================================

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
          'ncf_modificado', null,
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
      s.receipt_type::text as receipt_type,
      s.client_id,
      s.subtotal,
      s.tax_amount,
      s.total_amount,
      s.paid_amount,
      s.balance_due,
      s.status,
      coalesce(s.service_charge_amount, 0) as service_charge_amount,
      c.document_number as client_doc,
      c.document_type as client_doc_type,
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

commit;

notify pgrst, 'reload schema';


-- ============================================================================
-- VERIFICACIÓN — las dos deben salir en true.
-- ============================================================================
select
  p.proname                                                    as funcion,
  (pg_get_functiondef(p.oid) like '%formato_version%')          as formato_completo,
  (pg_get_functiondef(p.oid) like '%b.company_id = s.company_id%') as rnc_por_empresa,
  (pg_get_functiondef(p.oid) like '%can_access_branch%')          as valida_sucursal
from pg_proc p
join pg_namespace n on n.oid = p.pronamespace
where n.nspname = 'public'
  and p.proname in ('dgii_606_data', 'dgii_607_data')
order by 1;
