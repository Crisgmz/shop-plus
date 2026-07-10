import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../shared/extensions/iterable_extensions.dart';
import '../../auth/presentation/auth_providers.dart';
import '../../branches/presentation/branches_providers.dart';
import '../../cash_register/presentation/cash_register_providers.dart';
import '../../clients/presentation/clients_providers.dart';
import '../../cobros/presentation/cobros_providers.dart';
import '../../dashboard/presentation/dashboard_providers.dart';
import '../../expenses/presentation/expenses_providers.dart';
import '../../inventory/presentation/inventory_providers.dart';
import '../../payables/presentation/payables_providers.dart';
import '../../purchases/presentation/purchases_providers.dart';
import '../../reports/presentation/reports_providers.dart';
import '../../sales/presentation/sales_providers.dart';
import '../../settings/presentation/settings_providers.dart';
import '../../suppliers/presentation/suppliers_providers.dart';
import '../../taxes/presentation/taxes_providers.dart';
import '../../users/presentation/users_providers.dart';
import 'shell_nav_items.dart';

class ShellBranchOption {
  const ShellBranchOption({
    required this.branchId,
    required this.code,
    required this.name,
    required this.isDefault,
  });

  final String branchId;
  final String code;
  final String name;
  final bool isDefault;
}

class ShellUserInfo {
  const ShellUserInfo({
    required this.displayName,
    required this.roleCode,
    required this.roleLabel,
    required this.email,
  });

  final String displayName;
  final String roleCode;
  final String roleLabel;
  final String email;
}

class ShellAccessProfile {
  const ShellAccessProfile({
    required this.roleCode,
    required this.roleLabel,
    required this.source,
  });

  final String roleCode;
  final String roleLabel;
  final String source;

  bool canAccess(String role) => roleCode == role;
  bool get isAdmin => roleCode == 'admin';
  bool get isSupervisor => roleCode == 'supervisor';
  bool get isCashier => roleCode == 'cashier';
  bool get isAccountant => roleCode == 'accountant';
}

final shellBranchOptionsProvider = FutureProvider<List<ShellBranchOption>>((
  ref,
) async {
  ref.watch(authStateChangesProvider);
  final client = ref.watch(supabaseClientProvider);
  final user = client.auth.currentUser;
  if (user == null) return const [];

  final rows = await client
      .from('users_branches')
      .select('branch_id, is_default, branches(code, name)')
      .eq('user_id', user.id)
      .eq('is_active', true)
      .order('is_default', ascending: false);

  return rows
      .map((row) {
        final item = Map<String, dynamic>.from(row as Map);
        final branch = Map<String, dynamic>.from(
          (item['branches'] as Map?) ?? const <String, dynamic>{},
        );
        return ShellBranchOption(
          branchId: (item['branch_id'] ?? '').toString(),
          code: (branch['code'] ?? '').toString(),
          name: (branch['name'] ?? '').toString(),
          isDefault: item['is_default'] == true,
        );
      })
      .where((item) => item.branchId.isNotEmpty)
      .toList(growable: false);
});

final shellCurrentBranchNameProvider = FutureProvider<String>((ref) async {
  final options = await ref.watch(shellBranchOptionsProvider.future);
  if (options.isEmpty) return 'Sin sucursal';
  final selected =
      options.where((item) => item.isDefault).firstOrNull ?? options.first;
  return selected.name.trim().isEmpty
      ? 'Sucursal principal'
      : selected.name.trim();
});

final shellUserInfoProvider = FutureProvider<ShellUserInfo>((ref) async {
  ref.watch(authStateChangesProvider);
  final client = ref.watch(supabaseClientProvider);
  final user = client.auth.currentUser;
  if (user == null) {
    return const ShellUserInfo(
      displayName: 'Usuario',
      roleCode: 'cashier',
      roleLabel: 'Sin sesión',
      email: '',
    );
  }

  final rows = await client
      .from('profiles')
      .select('full_name, role, email')
      .eq('id', user.id)
      .limit(1);

  if (rows.isEmpty) {
    return ShellUserInfo(
      displayName: user.email?.split('@').first ?? 'Usuario',
      roleCode: 'cashier',
      roleLabel: 'Usuario',
      email: user.email ?? '',
    );
  }

  final row = Map<String, dynamic>.from(rows.first as Map);
  final fullName = (row['full_name'] ?? '').toString().trim();
  final role = (row['role'] ?? '').toString().trim();
  final email = (row['email'] ?? user.email ?? '').toString();

  return ShellUserInfo(
    displayName: fullName.isEmpty
        ? (user.email?.split('@').first ?? 'Usuario')
        : fullName,
    roleCode: role.isEmpty ? 'cashier' : role,
    roleLabel: _roleLabel(role),
    email: email,
  );
});

final shellAccessProfileProvider = FutureProvider<ShellAccessProfile>((
  ref,
) async {
  ref.watch(authStateChangesProvider);
  final client = ref.watch(supabaseClientProvider);
  final user = client.auth.currentUser;
  final userInfo = await ref.watch(shellUserInfoProvider.future);

  if (user == null) {
    return const ShellAccessProfile(
      roleCode: 'cashier',
      roleLabel: 'Sin sesión',
      source: 'fallback',
    );
  }

  final branchIdResult = await client.rpc('current_branch_id');
  final branchId = branchIdResult?.toString();

  if (branchId == null || branchId.isEmpty) {
    return ShellAccessProfile(
      roleCode: userInfo.roleCode,
      roleLabel: userInfo.roleLabel,
      source: 'profile',
    );
  }

  final overrides = await client
      .from('users_branches')
      .select('role_override')
      .eq('user_id', user.id)
      .eq('branch_id', branchId)
      .eq('is_active', true)
      .limit(1);

  if (overrides.isEmpty) {
    return ShellAccessProfile(
      roleCode: userInfo.roleCode,
      roleLabel: userInfo.roleLabel,
      source: 'profile',
    );
  }

  final row = Map<String, dynamic>.from(overrides.first as Map);
  final roleOverride = (row['role_override'] ?? '').toString().trim();
  if (roleOverride.isEmpty) {
    return ShellAccessProfile(
      roleCode: userInfo.roleCode,
      roleLabel: userInfo.roleLabel,
      source: 'profile',
    );
  }

  return ShellAccessProfile(
    roleCode: roleOverride,
    roleLabel: _roleLabel(roleOverride),
    source: 'branch_override',
  );
});

final shellVisibleNavItemsProvider = FutureProvider<List<NavItem>>((
  ref,
) async {
  final access = await ref.watch(shellAccessProfileProvider.future);
  return navItems
      .where((item) => item.allowedRoles.contains(access.roleCode))
      .toList(growable: false);
});

final shellVisibleNavSectionsProvider = FutureProvider<List<NavSection>>((
  ref,
) async {
  final access = await ref.watch(shellAccessProfileProvider.future);
  return visibleNavSectionsForRole(access.roleCode);
});

String _roleLabel(String role) {
  return switch (role) {
    'admin' => 'Administrador',
    'supervisor' => 'Supervisor',
    'cashier' => 'Cajero',
    'accountant' => 'Contador',
    _ => role.isEmpty ? 'Usuario' : role,
  };
}

void invalidateBranchScopedData(dynamic ref) {
  void invalidate(ProviderOrFamily provider) {
    if (ref is Ref) {
      ref.invalidate(provider);
    } else {
      (ref as dynamic).invalidate(provider);
    }
  }

  invalidate(shellBranchOptionsProvider);
  invalidate(shellCurrentBranchNameProvider);
  invalidate(shellUserInfoProvider);
  invalidate(shellAccessProfileProvider);
  invalidate(shellVisibleNavItemsProvider);
  invalidate(shellVisibleNavSectionsProvider);
  invalidate(dashboardKpisProvider);
  invalidate(dashboardChartProvider);
  invalidate(dashboardCloseoutProvider);
  invalidate(inventoryCategoriesProvider);
  invalidate(inventoryProductsProvider);
  invalidate(salesProductsProvider);
  invalidate(salesClientsProvider);
  invalidate(cobrosReceivablesProvider);
  invalidate(cobrosPaymentsProvider);
  invalidate(payablesListProvider);
  invalidate(supplierPaymentsProvider);
  invalidate(clientsListProvider);
  invalidate(suppliersListProvider);
  invalidate(purchasesListProvider);
  invalidate(purchaseSuppliersProvider);
  invalidate(purchaseProductsProvider);
  invalidate(cashRegisterDataProvider);
  invalidate(expensesListProvider);
  invalidate(expenseSuppliersProvider);
  invalidate(reportsDataProvider);
  invalidate(settingsDataProvider);
  invalidate(branchesListProvider);
  invalidate(branchMembersProvider);
  invalidate(branchUsersProvider);
  invalidate(usersListProvider);
  invalidate(usersBranchOptionsProvider);
  invalidate(taxesDataProvider);
}
