# Runbook — reconciliación de la base compartida

**Fecha:** 31 ago 2026 · **Estado:** migraciones 83 y 84 pendientes de ejecutar.

## El problema

`shop-plus` y `flutter_shop+` son **dos bifurcaciones del mismo repositorio**
(ancestro común `42d74d6`, 17 jun 2026; nunca se fusionaron, 74 de 147 archivos
`.dart` difieren) y **comparten una sola base**: `https://supabase.busiposweb.com`.

Sus números de migración chocan: `63`–`69` significan cosas distintas en cada
árbol. Lo que está vivo en la base es lo que corrió de último, no lo que dice
el árbol que uno tenga abierto.

Las migraciones 66–69 de shop-plus se aplicaron sobre ese estado y pisaron
funciones más nuevas del otro árbol, porque `create or replace` con la misma
firma reemplaza sin dar ningún error.

## Daño confirmado (diagnóstico del 31 ago)

| Qué | Efecto |
|---|---|
| `checkout_sale_transactional` quedó en la versión de la mig. 67 | Lee `discount_pct`, pero los dos apps mandan `discount_amount` → **descuentos perdidos**. No conoce `price_includes_tax` → **ITBIS cobrado encima de un precio que ya lo incluía**. No conoce `track_inventory` |
| `hold_sale_transactional` idem | Lo mismo en cuentas guardadas |
| `process_return` quedó en la versión de la mig. 68 | **Perdió la restauración de IMEIs** y su validación; `refund_method` como enum rechaza `credit_note` |
| Tres sobrecargas de `checkout_sale_transactional` (6, 7 y 10 parámetros) | Los apps resuelven a la de 10; las otras dos son restos inalcanzables pero peligrosos |
| FK duplicada en `returns.cash_session_id` | `returns_cash_session_fk` + `returns_cash_session_branch_fk` |

## Orden de ejecución

### 1. Medir el impacto (solo lectura)
```
supabase/diagnostico/03_impacto_cobro_de_mas.sql
```
Dice cuántas ventas, cuánto dinero y desde qué fecha se cobró ITBIS de más.
Correr **antes** de arreglar, para no mezclar la evidencia con ventas nuevas.

### 2. Migración 84 — devoluciones e IMEIs
```
supabase/sql-next/20260831_84_restore_process_return_imeis.sql
```
Independiente y segura. Restaura `process_return` de flutter_shop+ literal y
borra la FK duplicada. Al final trae la consulta de los IMEIs que quedaron sin
reingresar mientras estuvo rota: **hay que devolverlos al inventario a mano**.

### 3. Migración 83 — las tres funciones de venta
```
supabase/sql-next/20260831_83_reconcile_checkout_both_apps.sql
```
- Elimina las dos sobrecargas muertas de `checkout_sale_transactional`.
- Deja **una sola** versión de `checkout`, `hold` y `edit` que sirve a los dos
  apps: `discount_amount` + `price_includes_tax` + `track_inventory` +
  `is_service` + `is_tax_exempt` + `receipt_type = 'none'` + números cortos.
- Trae consulta de verificación al final: debe devolver una fila por función,
  con `descuento = discount_amount OK` y el resto en `true`.

### 4. Desplegar shop-plus
**En este orden.** El app ahora manda `discount_amount` y calcula con precio
ITBIS-incluido; si se despliega antes de la 83, los descuentos se siguen
perdiendo.

### 5. Probar
Venta normal · sin comprobante · con descuento · con pago dividido ·
devolución de un equipo con IMEI · editar una venta existente.

## Cambios en el app de shop-plus (ya hechos)

| Archivo | Cambio |
|---|---|
| `sale_checkout_service.dart` | Aritmética en **centavos enteros** (igual que el `numeric` de Postgres), precio con ITBIS incluido, `track_inventory`, manda `discount_amount` |
| `sales_repository.dart` | `SalesProduct` lee `price_includes_tax`, `track_inventory`, `is_service`, `is_tax_exempt`, `allow_negative_stock`; `SaleCartItem` calcula en centavos con ITBIS incluido |
| `sales_page.dart` | Totales usan el neto cuando la venta no factura ITBIS; guardas de stock respetan servicios y `track_inventory` |
| `sales_edit_page.dart` | Misma matemática que el RPC; el descuento se reconstruye del **monto** guardado, no del subtotal |
| `sales_history_repository.dart` | `SalesHistoryItem` expone `discountAmount` |

Cobertura: 44 tests, incluidos los de ITBIS incluido, descuento sobre base
descontada, y el caso del medio centavo (`2208.99 × 0.5`) que antes daba un
centavo por debajo del RPC y hacía rebotar los pagos divididos.

## Deuda pendiente

shop-plus está **18 migraciones atrás** de flutter_shop+: no tiene facturación
electrónica, IMEIs en compras, ni varios arreglos de reportes. Dos apps
divergentes sobre una base es insostenible: hay que **fusionar los árboles o
separar las bases**. Mientras tanto, cualquier migración nueva debe numerarse
desde la **85** y verificarse contra el estado real con
`supabase/diagnostico/01_estado_real_bd.sql` antes de escribirla.
