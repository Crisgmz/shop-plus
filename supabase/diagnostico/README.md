# Diagnóstico de la base compartida

`shop-plus` y `flutter_shop+` son dos bifurcaciones del mismo repositorio
(ancestro común `42d74d6`, 17 jun 2026) que **comparten una sola base**
(`https://supabase.busiposweb.com`). Sus números de migración chocan, así que
lo que está vivo en la base es lo que corrió de último, no lo que dice el árbol.

Todas las consultas son **solo lectura** y devuelven **un solo resultado**
(el SQL Editor de Supabase solo muestra el de la última sentencia).

| Archivo | Para qué |
|---|---|
| `01_estado_real_bd.sql` | Qué linaje quedó vivo en cada función, tipos de columnas en disputa, objetos que solo existen en un árbol |
| `02_sobrecargas.sql` | Firmas completas de las funciones duplicadas y qué sabe hacer cada una |
| `03_impacto_cobro_de_mas.sql` | Ventas a las que se les cobró ITBIS encima de un precio que ya lo incluía |

## Hallazgos (31 ago 2026)

1. **Tres `checkout_sale_transactional`** (6, 7 y 10 parámetros). Los dos apps
   resuelven a la de 10 porque es la única con `p_cash_session_id`.
2. La de 10 es la **migración 67 descartada**: lee `discount_pct` y no conoce
   `price_includes_tax` ni `track_inventory`. Por eso:
   - los descuentos de flutter_shop+ (que manda `discount_amount`) se pierden;
   - los productos con precio-ITBIS-incluido se cobran de más.
3. **`process_return` perdió la restauración de IMEIs** (migración 68 descartada).
4. FK duplicada en `returns.cash_session_id`.

Reparaciones: migraciones `83` (checkout y hold) y `84` (devoluciones e IMEIs).
