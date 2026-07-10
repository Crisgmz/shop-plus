import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../auth/presentation/auth_providers.dart';
import '../data/permissions_repository.dart';

final permissionsRepositoryProvider = Provider<PermissionsRepository>((ref) {
  final client = ref.watch(supabaseClientProvider);
  return PermissionsRepository(client);
});

final allPermissionsProvider =
    FutureProvider<List<PermissionDefinition>>((ref) async {
  final repo = ref.watch(permissionsRepositoryProvider);
  return repo.fetchAllPermissions();
});

// autoDispose: al recorrer usuarios en el admin de permisos, sin esto se
// acumulaba una lista cacheada por cada combinación usuario/sucursal.
final effectivePermissionsProvider = FutureProvider.autoDispose.family<
    List<EffectivePermission>,
    ({String userId, String branchId})>((ref, args) async {
  final repo = ref.watch(permissionsRepositoryProvider);
  return repo.fetchEffectivePermissions(
    userId: args.userId,
    branchId: args.branchId,
  );
});
