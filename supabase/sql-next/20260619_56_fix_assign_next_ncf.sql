-- ============================================================================
-- Migración 56 — Fix: assign_next_ncf resuelve next_number correctamente
-- ============================================================================
-- Bug: al crear una secuencia NCF desde la UI (Configuración › Mi cuenta/NCF),
-- el guardado NO inicializa `next_number` (queda NULL). El RPC assign_next_ncf
-- (migración 18) lo usaba crudo:
--
--     and (sequence_end is null or next_number <= sequence_end)
--
-- Con next_number NULL y un FIN de rango definido (lo normal según DGII),
-- `NULL <= fin` es NULL → la fila se EXCLUÍA → no se hallaba secuencia → la
-- venta se completaba SIN NCF en silencio (el trigger no bloquea). Y si el fin
-- quedaba vacío, `next_number := 1` arrancaba en 1 ignorando el inicio de rango.
--
-- Fix: derivar el "siguiente número efectivo" cuando next_number es NULL, igual
-- que ya lo hace la vista vw_ncf_stock:
--
--     coalesce(next_number, greatest(inicio_rango, current_number + 1))
--
-- Una vez asignado el primer NCF, next_number queda poblado y se usa tal cual.
-- Solo se reemplaza la función assign_next_ncf (idempotente); no toca triggers
-- ni el checkout. Beneficia también a bulk_assign_missing_ncfs y al trigger
-- trg_sales_assign_ncf, que la invocan.
--
-- Ejecutar en el SQL Editor de Supabase, DESPUÉS de la migración 18 (y 55).
-- ============================================================================

begin;

create or replace function public.assign_next_ncf(
  p_branch_id    uuid,
  p_receipt_type public.receipt_type
)
returns text
language plpgsql
security definer
set search_path = public
as $$
declare
  v_seq_id    uuid;
  v_prefix    text;
  v_next_num  bigint;
  v_seq_end   bigint;
  v_ncf       text;
begin
  if p_branch_id is null then
    raise exception 'branch_id requerido' using errcode = '22023';
  end if;

  if not public.has_branch_access(p_branch_id) and not public.is_admin() then
    raise exception 'Sin acceso a la sucursal indicada' using errcode = '42501';
  end if;

  -- Buscar la secuencia activa con capacidad. El "siguiente número efectivo" se
  -- deriva de next_number, o si está sin inicializar (NULL en secuencias recién
  -- creadas) de greatest(inicio_rango, current_number + 1). Así una secuencia
  -- nueva con fin de rango ya no queda excluida, y se respeta el inicio de rango.
  -- Si hay varias, se consume primero la de menor número.
  select id, prefix,
         coalesce(
           next_number,
           greatest(coalesce(sequence_start, 1), coalesce(current_number, 0) + 1)
         ),
         sequence_end
    into v_seq_id, v_prefix, v_next_num, v_seq_end
    from public.ncf_sequences
   where branch_id = p_branch_id
     and receipt_type = p_receipt_type
     and is_active = true
     and coalesce(status, 'active') = 'active'
     and (expires_on is null or expires_on >= current_date)
     and (
       sequence_end is null
       or coalesce(
            next_number,
            greatest(coalesce(sequence_start, 1), coalesce(current_number, 0) + 1)
          ) <= sequence_end
     )
   order by coalesce(
              next_number,
              greatest(coalesce(sequence_start, 1), coalesce(current_number, 0) + 1)
            ) asc
   limit 1
   for update;

  if v_seq_id is null then
    raise exception 'No hay secuencia NCF disponible para % en esta sucursal. Configúrala en Configuración › Mi cuenta/NCF.', p_receipt_type
      using errcode = 'P0001';
  end if;

  if v_seq_end is not null and v_next_num > v_seq_end then
    raise exception 'Secuencia NCF agotada para % (último: %). Crea una nueva o extiéndela.', p_receipt_type, v_seq_end
      using errcode = 'P0001';
  end if;

  -- Avanzar la secuencia: el número usado queda en current_number y el próximo
  -- en next_number (ya poblado, para no volver a derivarlo).
  update public.ncf_sequences
     set current_number = v_next_num,
         next_number    = v_next_num + 1,
         updated_at     = timezone('utc', now())
   where id = v_seq_id;

  v_ncf := v_prefix || lpad(v_next_num::text, 8, '0');
  return v_ncf;
end;
$$;

grant execute on function public.assign_next_ncf(uuid, public.receipt_type) to authenticated;

comment on function public.assign_next_ncf(uuid, public.receipt_type) is
  'Lockea y avanza la secuencia NCF activa para (branch, tipo). Devuelve el NCF formateado. Resuelve next_number desde inicio_rango/current_number si está sin inicializar.';

commit;

notify pgrst, 'reload schema';
