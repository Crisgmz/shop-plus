-- ============================================================================
-- 20260915_90_missing_ncf_skips_receiptless_sales.sql
--
-- "Asignar faltantes" ya no intenta ponerle NCF a una venta SIN comprobante.
--
-- `bulk_assign_missing_ncfs` (migración 18) recorre las ventas completadas o a
-- crédito con `ncf` vacío y les asigna el siguiente de su secuencia. Nunca se
-- enteró de `receipt_type = 'none'` (migraciones 59/64): una nota de venta no
-- fiscal no lleva NCF POR DISEÑO, pero la función la tomaba como faltante,
-- intentaba `assign_next_ncf(..., 'none')`, fallaba, y el usuario veía
-- "NCF asignados: 0. Sin asignar: 1" con las secuencias en regla.
--
-- No hubo daño en datos: la asignación falla dentro de un bloque con manejo de
-- errores y la venta no se modifica.
--
-- Copia FIEL de la versión de la migración 18; el ÚNICO cambio es el filtro
-- `receipt_type <> 'none'`. No toca el checkout.
--
-- Ejecutar en el SQL Editor de Supabase. Idempotente (CREATE OR REPLACE).
-- ============================================================================

create or replace function public.bulk_assign_missing_ncfs(p_branch_id uuid)
returns table(sale_id uuid, sale_number text, ncf text, error text)
language plpgsql
security definer
set search_path = public
as $$
declare
  v_sale record;
  v_ncf  text;
begin
  if not public.has_branch_access(p_branch_id) and not public.is_admin() then
    raise exception 'Sin acceso a la sucursal indicada' using errcode = '42501';
  end if;

  for v_sale in
    select s.id, s.sale_number, s.receipt_type
      from public.sales s
     where s.branch_id = p_branch_id
       and s.status in ('completed'::public.sale_status, 'credit'::public.sale_status)
       and (s.ncf is null or length(trim(s.ncf)) = 0)
       -- Venta sin comprobante: no lleva NCF, no es un faltante.
       and s.receipt_type::text <> 'none'
     order by s.sale_date asc
  loop
    begin
      v_ncf := public.assign_next_ncf(p_branch_id, v_sale.receipt_type);
      update public.sales
         set ncf = v_ncf
       where id = v_sale.id;
      return query select v_sale.id, v_sale.sale_number, v_ncf, null::text;
    exception when others then
      return query select v_sale.id, v_sale.sale_number, null::text, SQLERRM;
    end;
  end loop;
end;
$$;

grant execute on function public.bulk_assign_missing_ncfs(uuid) to authenticated;

notify pgrst, 'reload schema';
