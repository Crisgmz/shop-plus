# Shop+

Flutter POS (Point of Sale) management system with Supabase backend. Designed for multi-branch retail operations in the Dominican Republic.

## Tech Stack

- **Flutter** (Dart SDK ≥ 3.11.0) — multi-platform (iOS, Android, macOS, Linux, Web)
- **Supabase** — auth, database (PostgREST), realtime
- **Riverpod** — state management (providers + repository pattern)
- **GoRouter** — declarative routing with auth-aware redirects + ShellRoute
- **shared_preferences** — local storage

## Architecture

Clean Architecture with feature-first organization:

```
lib/
├── app/              # App root, GoRouter config, refresh stream
├── core/
│   ├── config/       # Environment variables (Supabase URL/key)
│   ├── supabase/     # Bootstrap initialization
│   └── theme/
│       ├── app_theme.dart   # Material 3 ThemeData
│       └── tokens.dart      # Design tokens (colors, spacing, radii, breakpoints)
├── features/         # Feature modules (auth, sales, inventory, etc.)
│   └── <feature>/
│       ├── data/            # Repository + models
│       └── presentation/    # Riverpod providers + Pages + widgets
├── shared/
│   ├── formatters/   # Money, date, number formatters
│   ├── responsive/   # Breakpoints, ResponsiveBuilder
│   └── widgets/      # Reusable widgets (ModulePage scaffold)
└── main.dart         # Entry point
```

## Common Commands

```bash
# Run (dev, with Supabase env vars)
flutter run --dart-define=SUPABASE_URL=<url> --dart-define=SUPABASE_ANON_KEY=<key>

# Run tests
flutter test

# Analyze code
flutter analyze

# Build
flutter build apk        # Android
flutter build ios         # iOS
flutter build web         # Web
```

## Key Conventions

- Feature modules follow: `data/` (repos + models), `presentation/` (providers + pages)
- Pages: `ConsumerStatefulWidget` for interactive, `ConsumerWidget` for read-only
- State: `FutureProvider` for data, `StateProvider` for UI state
- Repositories inject `SupabaseClient` via `supabaseClientProvider`
- All queries filter by branch via `_currentBranchId()` RPC
- Routes use Spanish paths (`/ventas`, `/cobros`, `/caja`, `/inventario`, etc.)
- All module routes wrapped by `ShellRoute` → `AppShell`
- Multi-branch support via `current_branch_id()` RPC and row-level security
- Material 3 theming with brand color `#0B5ED7`
- Linting via `flutter_lints` (see `analysis_options.yaml`)

## Database (Supabase)

Schema scripts in `supabase/sql/` — run in order 01-04:
1. `01_schema.sql` — 15 tables, enums, RLS policies, stock triggers, audit triggers
2. `02_seed.sql` — demo data (branch, products, clients, suppliers, sales, expenses)
3. `03_reports_views.sql` — 7 views (dashboard KPIs, sales summaries, receivables, low stock, NCF usage)
4. `04_branch_context.sql` — `set_current_branch()` RPC

**Canonical DB reference:** read `DATABASE.md` before doing any substantial backend/data/modeling work. It documents the current schema, branch isolation model, reporting views, and the planned next-phase additions (multi-user hardening, caja chica, legacy comprobantes, and e-facturación-ready architecture).

Tables: profiles, branches, users_branches, product_categories, products, clients, suppliers, purchases, purchase_items, ncf_sequences, sales, sale_items, cash_sessions, payments, expenses.

Key DB patterns:
- All tables use `branch_id` isolation + RLS via `has_branch_access()`
- Audit fields (`created_by`, `updated_by`, `updated_at`) auto-set via triggers
- Stock triggers: `purchase_items` INSERT adds stock, `sale_items` INSERT deducts stock
- Roles: `admin`, `supervisor`, `cashier`, `accountant` — enforced by RLS helper functions
- NCF sequences for Dominican fiscal compliance (receipt types)
- Unique partial indexes for SKU, barcode, RNC, document_number (per branch)

### Known Limits (Post-MVP)
- NCF auto-assignment on sale creation not yet implemented
- DGII certified fiscal generation pending
- Offline mode not implemented
- Multi-company support not implemented

## Do NOT

- Hardcode colors — use `AppTokens` or `Theme.of(context)`
- Duplicate formatter logic — use `shared/formatters/`
- Wrap individual routes in `AppShell` — the `ShellRoute` handles it
- Use `Navigator.push` — use `context.go()` / `context.push()` via GoRouter
- Add packages without discussing first
