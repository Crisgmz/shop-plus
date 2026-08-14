# DATABASE.md — Shop+

Referencia central de base de datos para `flutter_shop+`.

Úsalo como mapa rápido de:
- esquema actual en Supabase
- aislamiento por sucursal
- roles y permisos
- vistas/reportes existentes
- gaps actuales
- modelo objetivo para próximas fases

## 1) Fuente de verdad actual

Los scripts actuales están en `supabase/sql/` y se ejecutan en este orden:

1. `01_schema.sql`
2. `02_seed.sql`
3. `03_reports_views.sql`
4. `04_branch_context.sql`

Archivo auxiliar:
- `supabase/README.md`

## 2) Esquema actual implementado

### Tablas núcleo
- `profiles`
  - perfil del usuario autenticado
  - `role`: `admin | supervisor | cashier | accountant`
  - `is_active`
- `branches`
  - sucursales
  - `code`, `name`, `is_main`, `is_active`
- `users_branches`
  - asignación usuario ↔ sucursal
  - `role_override`
  - `is_default`
  - base del contexto multi-sucursal

### Catálogo
- `product_categories`
- `products`
  - `sku`, `barcode`, `cost`, `price`, `tax_rate`, `stock`, `min_stock`

### CRM / terceros
- `clients`
  - tipo de entidad, documento, balance, límite de crédito
- `suppliers`
  - RNC, contacto, datos de proveedor

### Compras
- `purchases`
- `purchase_items`

### Ventas / POS
- `sales`
- `sale_items`
- `payments`
- `cash_sessions`
- `expenses`

### Fiscal / comprobantes
- `ncf_sequences`
  - secuencias de comprobantes fiscales
- enums fiscales:
  - `receipt_type`
  - `dgii_status`

## 3) Enums actuales

- `app_role`
  - `admin`
  - `supervisor`
  - `cashier`
  - `accountant`

- `receipt_type`
  - `consumer_final`
  - `fiscal_credit`
  - `governmental`
  - `special`
  - `export`

- `dgii_status`
  - `pending`
  - `sent`
  - `approved`
  - `rejected`

- `sale_status`
  - `draft`
  - `completed`
  - `credit`
  - `pending`
  - `voided`

- `purchase_status`
  - `draft`
  - `posted`
  - `cancelled`

- `cash_session_status`
  - `open`
  - `closed`

- `payment_method`
  - `cash`
  - `card`
  - `transfer`
  - `mobile`
  - `mixed`
  - `credit`

- `entity_type`
  - `person`
  - `company`
  - `government`

## 4) Funciones / helpers actuales

### Auditoría
- `set_updated_at()`
- `set_audit_fields()`

### Sucursal actual
- `current_branch_id()`
- `set_current_branch(target_branch_id uuid)`

### Aislamiento por sucursal / RLS
El sistema está pensado para operar por sucursal usando:
- `users_branches`
- `current_branch_id()`
- helpers de acceso por sucursal (`has_branch_access()` en el esquema)
- políticas RLS por branch y rol

## 5) Comportamientos automáticos actuales

### Auditoría
Triggers rellenan:
- `created_by`
- `updated_by`
- `updated_at`

### Inventario
Triggers actuales soportan:
- compra suma stock
- venta descuenta stock

### Venta sin comprobante (nota de venta no fiscal)
`receipt_type = 'none'` — introducido por la migración 59 y completado por
`20260810_64_sale_without_ncf_complete.sql`.

- No consume NCF: `tg_sales_assign_ncf` y `tg_sales_assign_ncf_on_complete` lo
  saltean.
- No exige comprador identificado: `tg_sales_assert_fiscal_client` lo trata
  como `consumer_final`.
- **No factura ITBIS**: `checkout_sale_transactional`, `hold_sale_transactional`
  y `edit_sale_transactional` fuerzan la tasa de línea a 0 (`v_line_tax_rate` /
  `v_rate`), así `subtotal = total` y `paid_amount`, `balance_due` y las filas
  de `payments` cuadran. Por eso la regla vive en los RPC —donde se suman los
  totales— y no en un trigger.
- `normalize_receipt_type` acepta `'none'`, `'sin comprobante'` y `'ninguno'`.
- Queda fuera del 606/607: esos reportes filtran `ncf is not null`.
- El comprobante con el que arranca cada venta en el POS sale de
  `branch_fiscal_settings.default_receipt_type` (Ajustes → Fiscal). Si ese tipo
  necesita NCF y no hay secuencia disponible, el POS cae a `'none'`.

### Numeración de ventas
`trg_sales_short_number` (BEFORE INSERT en `sales`, migración
`20260810_63_short_sale_numbers.sql`) reemplaza el número autogenerado por los
RPC de checkout (`VTA-<timestamp>-<random>`) por un correlativo corto por
sucursal: `<app_settings.prefix_sale>-NNNNNN`, p. ej. `FA-000123`.

- Contador en `public.sale_number_counters` (una fila por sucursal), servido
  por `public.next_sale_number(branch_id)` — SECURITY DEFINER, con row lock
  para que dos cajas concurrentes no repitan número.
- Solo se reemplaza si `sale_number` es NULL o empieza con `VTA-`. Un número
  reusado (cuenta guardada que se reabre y se cobra) conserva el suyo.
- Las ventas anteriores a la migración conservan su número `VTA-…`.

## 6) Vistas actuales de reportes

Definidas en `03_reports_views.sql`:
- `dashboard_kpis_by_branch`
- `sales_monthly_summary`
- `sales_weekly_summary`
- `latest_sales_view`
- `accounts_receivable_summary`
- `inventory_low_stock_view`
- `ncf_usage_summary`

Estas vistas son la base del dashboard y reportes operativos.

## 7) Estado actual del sistema

### Ya resuelto
- multi-sucursal base
- autenticación + perfiles
- catálogo
- compras
- ventas
- cobros/pagos
- caja base por sesión (`cash_sessions`)
- gastos (`expenses`)
- secuencias NCF básicas
- reportes base

### Gaps explícitos ya conocidos
Según `CLAUDE.md` y el estado del proyecto:
- asignación automática de NCF en venta no está terminada
- generación fiscal certificada DGII no está lista
- offline mode no implementado
- multi-company no implementado

## 8) Próxima evolución requerida

Cristian quiere llevar el sistema hacia:
1. mejor UI/UX
2. impresión completa A4 y 80mm
3. caja chica
4. multiusuario fuerte con tipos de usuario/permisos
5. facturación con comprobantes legacy
6. dejar facturación electrónica lista para implementar

## 9) Modelo objetivo recomendado

### 9.1 Multiusuario / permisos
El esquema actual tiene roles globales simples. Para endurecerlo, la siguiente fase debería contemplar:

#### Mantener / ampliar
- `profiles`
- `users_branches`

#### Agregar recomendado
- `permissions`
  - catálogo de permisos (`sales.view`, `sales.create`, `inventory.edit`, etc.)
- `role_permissions`
  - permisos por rol
- opcional: `user_permissions`
  - overrides por usuario
- opcional: `branch_user_settings`
  - preferencias operativas por sucursal/usuario

#### Acciones que deberían poder restringirse
- ver
- crear
- editar
- eliminar/anular
- imprimir
- exportar
- aprobar/desaprobar
- cerrar caja
- administrar secuencias fiscales
- tocar configuración

### 9.2 Caja chica
`cash_sessions` y `expenses` no cubren completamente caja chica operativa.

Agregar recomendado:

- `petty_cash_sessions`
  - apertura/cierre de caja chica por sucursal y usuario
- `petty_cash_movements`
  - ingresos/egresos manuales
  - tipo: `income | expense | adjustment | replenishment`
- `petty_cash_categories`
  - transporte, papelería, limpieza, etc.
- opcional: `petty_cash_reconciliations`
  - arqueo / diferencia / observaciones

Campos clave:
- `branch_id`
- `opened_by`, `closed_by`
- `opening_amount`, `closing_amount_expected`, `closing_amount_real`
- `status`
- `notes`
- `reference_type`, `reference_id`

### 9.3 Comprobantes legacy (NCF tradicional)
Hoy existe la base en `ncf_sequences`, pero hace falta completarla de forma seria.

Agregar/reforzar recomendado:
- extender `ncf_sequences`
  - vigencia
  - prefijo/serie
  - rango inicial/final
  - siguiente número
  - estado
- `sales`
  - `receipt_type`
  - `ncf`
  - `legacy_ncf_sequence_id`
  - `fiscal_issued_at`
  - `void_reason`
- opcional: `fiscal_documents`
  - tabla consolidada de documentos fiscales emitidos

Casos mínimos a soportar:
- consumidor final
- crédito fiscal
- gubernamental
- régimen especial
- exportación
- anulación / nota de crédito futura si entra al roadmap

### 9.4 Facturación electrónica lista para implementar
No necesariamente implementarla ya, pero dejar lista la arquitectura.

Agregar recomendado:
- `electronic_documents`
  - vínculo a venta/documento fiscal
  - payload enviado
  - estado
  - track_id / response code
  - XML/JSON generado
  - timestamps de envío/respuesta
- `electronic_document_events`
  - historial de intentos/cambios de estado
- `taxpayer_profiles` o `company_fiscal_config`
  - datos fiscales del emisor
  - certificados/credenciales (si se manejan fuera del DB, guardar referencias)

Estados sugeridos:
- `draft`
- `queued`
- `generated`
- `sent`
- `accepted`
- `rejected`
- `cancelled`

La regla importante: **desacoplar** la venta del envío fiscal electrónico.
La venta no debe depender fuertemente del proveedor de e-factura.

### 9.5 Impresión A4 y 80mm
No todo es DB, pero sí conviene guardar metadata útil.

Agregar recomendado:
- `print_templates`
  - tipo de documento
  - formato (`a4`, `thermal_80mm`)
  - configuración visual/versionado
- opcional: `print_jobs`
  - historial de impresiones
  - reimpresiones
  - destino/dispositivo

Y en `sales` o documento fiscal:
- número legible
- cliente
- items
- subtotales
- impuestos
- forma de pago
- cajero
- sucursal
- NCF
- QR / hash futuro si aplica

## 10) Orden recomendado de migraciones futuras

### Fase 1 — endurecer seguridad y usuarios
1. permisos por rol
2. overrides por sucursal/usuario si hacen falta
3. políticas RLS alineadas a permisos

### Fase 2 — caja chica
4. tablas de caja chica
5. movimientos / arqueo / categorías
6. vistas/reportes de caja chica

### Fase 3 — fiscal legacy completo
7. reforzar secuencias NCF
8. asignación automática de NCF al facturar
9. validaciones y auditoría fiscal

### Fase 4 — facturación electrónica ready
10. tablas de documentos electrónicos
11. eventos / estados / payloads
12. capa desacoplada para integración futura

### Fase 5 — impresión / trazabilidad
13. templates de impresión
14. logs de impresión / reimpresión

## 11) Checklist mínimo antes de tocar DB

Antes de hacer cambios grandes, confirmar:
- qué roles exactos existirán
- si permisos serán por rol o por usuario también
- si caja chica es por sucursal, por caja física, o ambas
- qué tipos de comprobantes legacy van primero
- cómo se decide cuándo emitir legacy vs e-factura
- si una venta puede existir sin documento fiscal final
- qué impresiones son obligatorias en A4 y cuáles en 80mm

## 12) Referencias útiles del workspace

### Proyecto actual
- `CLAUDE.md`
- `supabase/README.md`
- `supabase/sql/01_schema.sql`
- `supabase/sql/03_reports_views.sql`
- `supabase/sql/04_branch_context.sql`

### Proyecto de referencia relacionado
- `/Users/cristiangomez/dev/mangospos`
- carpeta útil ahí: `backend data structure/`

Especialmente:
- `roles_permissions_schema.sql`
- `setup_roles_complete.sql`
- `mangopos_backend_reference.txt`
- `guia de base de datos.txt`
- `usuarios_gestion_spec.txt`

## 13) Regla práctica para futuros agentes

Si el trabajo toca DB, asumir esto:
- primero leer `CLAUDE.md`
- luego leer `DATABASE.md`
- después revisar SQL real en `supabase/sql/`
- si el cambio es de roles/caja/fiscal, revisar también la referencia de `mangospos`

Eso evita inventar estructura y mantiene coherencia con el roadmap real.
