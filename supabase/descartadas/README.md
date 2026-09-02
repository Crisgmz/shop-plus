# Migraciones descartadas

Escritas contra el árbol de **shop-plus**, que está atrasado respecto de
**flutter_shop+**. Los dos proyectos son bifurcaciones del mismo repositorio
(ancestro común `42d74d6`, 17 jun 2026) y **comparten la misma base de datos**
(`https://supabase.busiposweb.com`).

Correrlas reemplazaría funciones más nuevas **sin error visible**, porque usan
`create or replace` con la misma firma.

| Archivo | Por qué se descartó | Qué lo reemplaza |
|---|---|---|
| `20260830_67_checkout_line_discount.sql` | Usa `discount_pct`; el app de flutter_shop+ manda `discount_amount`. Además pisaría precios con ITBIS incluido y `track_inventory`. | `20260814_76_checkout_line_discount.sql` |
| `20260830_68_returns_cash_session.sql` | Misma firma de 7 parámetros que la versión buena: la reemplazaría en silencio y se perdería la restauración de IMEIs. Además declara `refund_method` como enum, que rechaza `'credit_note'`. | `20260814_69_returns_cash_and_imeis.sql` |

Cada archivo lleva un `raise exception` al inicio para que falle de inmediato
si alguien lo pega en el SQL Editor por error.
