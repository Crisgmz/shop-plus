import 'package:flutter/material.dart';

import '../../core/theme/tokens.dart';

/// Explicit content-width modes for back-office screens.
///
/// - [standard]: centered pages with a restrained reading width.
/// - [wide]: management surfaces that need more horizontal room for tables,
///   split panes, KPI grids, and denser operational layouts.
enum AppPageLayoutMode { standard, wide }

const _wideModulePaths = <String>{
  '/panel',
  '/ventas',
  '/cuentas-por-cobrar',
  '/cuentas-por-pagar',
  '/inventario',
  '/compras',
  '/reportes',
  '/usuarios',
  '/sucursales',
  '/clientes',
  '/proveedores',
  '/gastos',
  '/caja',
};

AppPageLayoutMode appPageLayoutModeForPath(String path) {
  return _wideModulePaths.contains(path)
      ? AppPageLayoutMode.wide
      : AppPageLayoutMode.standard;
}

class AppPageLayout extends StatelessWidget {
  const AppPageLayout({super.key, required this.mode, required this.child});

  final AppPageLayoutMode mode;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final maxWidth = switch (mode) {
      AppPageLayoutMode.standard => AppTokens.contentMaxWidth,
      AppPageLayoutMode.wide => AppTokens.contentWideMaxWidth,
    };

    return Align(
      alignment: Alignment.topCenter,
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: maxWidth),
        child: SizedBox(width: double.infinity, child: child),
      ),
    );
  }
}
