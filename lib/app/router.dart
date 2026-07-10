import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../core/config/env.dart';
import '../features/auth/presentation/auth_providers.dart';
import '../features/auth/presentation/login_page.dart';
import '../features/auth/presentation/signup_page.dart';
import '../features/auth/presentation/signup_success_page.dart';
import '../features/branches/presentation/branches_page.dart';
import '../features/cash_register/presentation/cash_register_page.dart';
import '../features/clients/presentation/clients_page.dart';
import '../features/cobros/presentation/cobros_page.dart';
import '../features/dashboard/presentation/closeout_page.dart';
import '../features/expenses/presentation/expenses_page.dart';
import '../features/dashboard/presentation/dashboard_page.dart';
import '../features/petty_cash/presentation/petty_cash_page.dart';
import '../features/fiscal_documents/presentation/fiscal_documents_page.dart';
import '../features/inventory/presentation/inventory_page.dart';
import '../features/payables/presentation/payables_page.dart';
import '../features/purchases/presentation/purchases_page.dart';
import '../features/quotations/presentation/quotation_create_page.dart';
import '../features/quotations/presentation/quotations_page.dart';
import '../features/reports/presentation/reports_page.dart';
import '../features/returns/presentation/returns_page.dart';
import '../features/sales/presentation/sales_edit_page.dart';
import '../features/sales/presentation/sales_entry_page.dart';
import '../features/sales/presentation/sales_history_page.dart';
import '../features/settings/presentation/app_settings_page.dart';
import '../features/settings/presentation/settings_page.dart';
import '../features/setup/presentation/setup_page.dart';
import '../features/shell/presentation/app_shell.dart';
import '../features/suppliers/presentation/suppliers_page.dart';
import '../features/taxes/presentation/taxes_page.dart';
import '../features/users/presentation/users_page.dart';
import 'router_refresh_stream.dart';

final appRouterProvider = Provider<GoRouter>((ref) {
  // ── Supabase not configured → show setup wizard ───────────────────────────
  if (!Env.isSupabaseConfigured) {
    return GoRouter(
      initialLocation: '/setup',
      routes: [GoRoute(path: '/setup', builder: (_, _) => const SetupPage())],
    );
  }

  // ── Normal app flow ───────────────────────────────────────────────────────
  final authRepo = ref.watch(authRepositoryProvider);
  final refreshStream = GoRouterRefreshStream(authRepo.authStateChanges);
  ref.onDispose(refreshStream.dispose);

  return GoRouter(
    initialLocation: '/panel',
    refreshListenable: refreshStream,
    redirect: (_, state) {
      final loggedIn = authRepo.currentSession != null;
      final loc = state.matchedLocation;
      final isPublic = loc == '/login' ||
          loc == '/registro' ||
          loc == '/registro/exito';

      // No autenticado y la ruta no es pública → forzar login.
      if (!loggedIn && !isPublic) return '/login';
      // Autenticado entrando a login/registro → ir al panel.
      if (loggedIn && isPublic) return '/panel';
      return null;
    },
    routes: [
      GoRoute(path: '/login', builder: (_, _) => const LoginPage()),
      GoRoute(path: '/registro', builder: (_, _) => const SignupPage()),
      GoRoute(
        path: '/registro/exito',
        builder: (_, state) => SignupSuccessPage(
          companyName: state.uri.queryParameters['empresa'],
        ),
      ),

      // Todas las rutas autenticadas comparten el AppShell vía
      // StatefulShellRoute.indexedStack: cada sección es una "branch" que se
      // mantiene VIVA en un IndexedStack una vez visitada. Así, volver a entrar
      // a una sección es instantáneo (no se reconstruye el árbol ni se pierde
      // el scroll), que es justo lo que causaba el lag al navegar.
      StatefulShellRoute.indexedStack(
        builder: (_, _, navigationShell) => AppShell(child: navigationShell),
        branches: [
          // Panel + cierre
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/panel',
                pageBuilder: (_, _) =>
                    const NoTransitionPage(child: DashboardPage()),
                routes: [
                  GoRoute(
                    path: 'cierre',
                    pageBuilder: (_, _) =>
                        const NoTransitionPage(child: CloseoutPage()),
                  ),
                ],
              ),
            ],
          ),
          // Ventas + historial + edición
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/ventas',
                pageBuilder: (_, _) =>
                    const NoTransitionPage(child: SalesEntryPage()),
                routes: [
                  GoRoute(
                    path: 'historial',
                    pageBuilder: (_, _) =>
                        const NoTransitionPage(child: SalesHistoryPage()),
                    routes: [
                      GoRoute(
                        path: ':saleId/editar',
                        pageBuilder: (_, state) => NoTransitionPage(
                          child: SalesEditPage(
                            saleId: state.pathParameters['saleId'] ?? '',
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ],
          ),
          _simpleBranch('/devoluciones', const ReturnsPage()),
          // Cotizaciones + nueva + edición
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/cotizaciones',
                pageBuilder: (_, _) =>
                    const NoTransitionPage(child: QuotationsPage()),
                routes: [
                  GoRoute(
                    path: 'nueva',
                    pageBuilder: (_, _) =>
                        const NoTransitionPage(child: QuotationCreatePage()),
                  ),
                  GoRoute(
                    path: ':quoteId',
                    pageBuilder: (_, state) => NoTransitionPage(
                      child: QuotationCreatePage(
                        quoteId: state.pathParameters['quoteId'],
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
          // Cuentas por cobrar (+ redirect de la ruta vieja /cobros)
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/cuentas-por-cobrar',
                pageBuilder: (_, _) =>
                    const NoTransitionPage(child: CobrosPage()),
              ),
              GoRoute(
                path: '/cobros',
                redirect: (_, _) => '/cuentas-por-cobrar',
              ),
            ],
          ),
          _simpleBranch('/cuentas-por-pagar', const PayablesPage()),
          _simpleBranch('/gastos', const ExpensesPage()),
          _simpleBranch('/inventario', const InventoryPage()),
          _simpleBranch('/compras', const PurchasesPage()),
          _simpleBranch('/clientes', const ClientsPage()),
          _simpleBranch('/proveedores', const SuppliersPage()),
          _simpleBranch('/caja', const CashRegisterPage()),
          _simpleBranch('/caja-chica', const PettyCashPage()),
          _simpleBranch('/reportes', const ReportsPage()),
          _simpleBranch('/comprobantes', const FiscalDocumentsPage()),
          _simpleBranch('/impuestos', const TaxesPage()),
          _simpleBranch('/sucursales', const BranchesPage()),
          _simpleBranch('/usuarios', const UsersPage()),
          // Configuración + cuenta
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/configuracion',
                pageBuilder: (_, _) =>
                    const NoTransitionPage(child: AppSettingsPage()),
                routes: [
                  GoRoute(
                    path: 'cuenta',
                    pageBuilder: (_, _) =>
                        const NoTransitionPage(child: SettingsPage()),
                  ),
                ],
              ),
            ],
          ),
        ],
      ),
    ],
  );
});

/// Branch de una sección simple (una sola ruta) con [NoTransitionPage].
StatefulShellBranch _simpleBranch(String path, Widget child) {
  return StatefulShellBranch(
    routes: [
      GoRoute(
        path: path,
        pageBuilder: (_, _) => NoTransitionPage(child: child),
      ),
    ],
  );
}
