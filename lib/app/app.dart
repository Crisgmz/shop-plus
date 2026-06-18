import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/realtime/realtime_invalidator.dart';
import '../core/theme/app_theme.dart';
import '../features/settings/presentation/app_settings_providers.dart';
import '../features/shell/presentation/shell_providers.dart';
import '../shared/formatters/live_settings.dart';
import 'router.dart';

class ShopPlusApp extends ConsumerWidget {
  const ShopPlusApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final router = ref.watch(appRouterProvider);

    // Sincronizar LiveSettings (cache que usan los formatters puros)
    // cada vez que cambia la configuración global. Esto hace que money(),
    // formatDate() y formatMoney() reaccionen automáticamente.
    final currentSettings = ref.watch(appSettingsProvider).valueOrNull;
    if (currentSettings != null) {
      LiveSettings.update(
        currencySymbol: currentSettings.currencySymbol,
        currencyDecimals: currentSettings.currencyDecimals,
        thousandsSep: currentSettings.currencyThousandsSep,
        decimalPoint: currentSettings.currencyDecimalPoint,
        dateFormat: currentSettings.appDateFormat,
        timeFormat: currentSettings.appTimeFormat,
      );
    }

    // Realtime: cuando la sucursal default cambia (al loguearse, al hacer
    // switch en el header), re-suscribir los canales Postgres Changes con
    // filtro por branch_id. Los providers tocados en _tableToProviders se
    // invalidan solos al recibir INSERT/UPDATE/DELETE.
    String? resolveBranchId(List<ShellBranchOption>? branches) {
      if (branches == null || branches.isEmpty) return null;
      return branches
              .where((b) => b.isDefault)
              .map((b) => b.branchId)
              .firstOrNull ??
          branches.first.branchId;
    }

    // Attach inicial con el valor actual (si ya está hidratado).
    final initialBranches =
        ref.read(shellBranchOptionsProvider).valueOrNull;
    final initialBranchId = resolveBranchId(initialBranches);
    if (initialBranchId != null) {
      ref.read(realtimeInvalidatorProvider).attach(initialBranchId);
    }

    // Re-attach en cada cambio posterior.
    ref.listen<AsyncValue<List<ShellBranchOption>>>(
      shellBranchOptionsProvider,
      (previous, next) {
        final branchId = resolveBranchId(next.valueOrNull);
        if (branchId == null) return;
        ref.read(realtimeInvalidatorProvider).attach(branchId);
      },
    );

    return MaterialApp.router(
      title: 'Shop+',
      theme: AppTheme.light,
      debugShowCheckedModeBanner: false,
      routerConfig: router,
    );
  }
}
