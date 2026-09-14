-- ============================================================================
-- 20260914_89_tag_sale_item_presentations.sql
--
-- PRESENTACIONES EN LA FACTURA — "1 Caja" en vez de "12 unidades".
--
-- La migración 86 agregó `sale_items.uom` / `uom_factor` pero, a propósito, no
-- tocó `checkout_sale_transactional`: esa función la comparten dos apps y 30
-- empresas, y reemplazarla fue lo que rompió cosas a fin de agosto. Así que el
-- checkout inserta cada línea con `uom = 'unit'` y `quantity` en unidades base,
-- que es lo correcto para la plata y el inventario.
--
-- Esta migración agrega UNA función nueva — no reemplaza ninguna — que el app
-- llama justo después del cobro para marcar qué líneas se vendieron como
-- presentación. Solo cambia `uom`, `uom_factor` y `unit_name`:
--
--   · `quantity`, `unit_price` y los totales no se tocan → el trigger de stock
--     recibe un UPDATE con delta 0 y los montos quedan intactos.
--   · Si la llamada falla, la venta ya es correcta; la factura solo saldría en
--     unidades.
--   · El otro app nunca la llama y no nota nada.
--
-- Cómo encuentra la fila: el checkout no devuelve ids de línea, así que busca
-- por (venta, producto, cantidad, precio) entre las que siguen en 'unit'. Si
-- dos filas coinciden en TODO eso, son idénticas en plata, y marcar una u otra
-- produce la misma factura.
--
-- Ejecutar en el SQL Editor de Supabase, DESPUÉS de la migración 86.
-- Idempotente (CREATE OR REPLACE).
-- ============================================================================

begin;

create or replace function public.tag_sale_item_presentations(
  p_sale_id uuid,
  p_lines jsonb
)
returns integer
language plpgsql
security definer
set search_path = public
as $$
declare
  v_branch_id uuid;
  v_line record;
  v_row_id uuid;
  v_tagged integer := 0;
begin
  if auth.uid() is null then
    raise exception 'Sesión inválida. Inicia sesión de nuevo.'
      using errcode = '28000';
  end if;

  if p_lines is null or jsonb_typeof(p_lines) <> 'array' then
    return 0;
  end if;

  select s.branch_id into v_branch_id
    from public.sales s
   where s.id = p_sale_id;

  if v_branch_id is null then
    raise exception 'La venta no existe.' using errcode = '23503';
  end if;

  if not public.has_branch_access(v_branch_id) then
    raise exception 'No tienes acceso a la sucursal de esta venta.'
      using errcode = '42501';
  end if;

  for v_line in
    select
      (e->>'product_id')::uuid                          as product_id,
      (e->>'quantity')::numeric(14,3)                   as quantity,
      (e->>'unit_price')::numeric(14,2)                 as unit_price,
      lower(btrim(coalesce(e->>'uom', '')))             as uom,
      (e->>'uom_factor')::numeric(14,3)                 as uom_factor,
      nullif(btrim(coalesce(e->>'unit_name', '')), '')  as unit_name
    from jsonb_array_elements(p_lines) as e
  loop
    -- Solo presentaciones reales, con un factor que reparta exacto la cantidad
    -- (24 unidades con factor 12 = 2 cajas; 25 no es un número de cajas).
    continue when v_line.uom not in ('pack', 'box')
               or v_line.product_id is null
               or v_line.quantity is null
               or v_line.uom_factor is null
               or v_line.uom_factor <= 0
               or mod(v_line.quantity, v_line.uom_factor) <> 0;

    select si.id into v_row_id
      from public.sale_items si
     where si.sale_id    = p_sale_id
       and si.product_id = v_line.product_id
       and si.quantity   = v_line.quantity
       and si.unit_price = v_line.unit_price
       and si.uom        = 'unit'
     order by si.created_at, si.id
     limit 1;

    continue when v_row_id is null;

    update public.sale_items
       set uom        = v_line.uom,
           uom_factor = v_line.uom_factor,
           unit_name  = coalesce(v_line.unit_name, unit_name)
     where id = v_row_id;

    v_tagged := v_tagged + 1;
  end loop;

  return v_tagged;
end;
$$;

grant execute on function public.tag_sale_item_presentations(uuid, jsonb)
  to authenticated;

commit;

notify pgrst, 'reload schema';
