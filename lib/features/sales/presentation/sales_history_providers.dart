import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../auth/presentation/auth_providers.dart';
import '../data/sales_history_repository.dart';
import '../data/sales_repository.dart';
import 'sales_providers.dart';

final salesHistoryRepositoryProvider =
    Provider<SalesHistoryRepository>((ref) {
  final client = ref.watch(supabaseClientProvider);
  return SalesHistoryRepository(client);
});

/// Filtros activos en el historial (fecha + búsqueda + status).
final salesHistoryFilterProvider =
    StateProvider<SalesHistoryFilter>((ref) {
  return const SalesHistoryFilter();
});

/// Página actual (0-indexada). Cambia con los botones de paginación.
final salesHistoryPageIndexProvider = StateProvider<int>((ref) => 0);

/// Datos de la página actual (re-fetch cuando cambian filtros o índice).
final salesHistoryPageProvider =
    FutureProvider.autoDispose<SalesHistoryPage>((ref) async {
  final repo = ref.watch(salesHistoryRepositoryProvider);
  final filter = ref.watch(salesHistoryFilterProvider);
  final index = ref.watch(salesHistoryPageIndexProvider);
  return repo.fetchPage(pageIndex: index, filter: filter);
});

/// Detalle bajo demanda. Family por saleId.
final salesHistoryDetailProvider =
    FutureProvider.autoDispose.family<SalesHistoryDetail?, String>(
  (ref, saleId) async {
    final repo = ref.watch(salesHistoryRepositoryProvider);
    return repo.fetchDetail(saleId);
  },
);

/// Productos de las líneas de una venta, ACTIVOS O NO. La edición los usa para
/// no perder (ni borrar al guardar) la línea de un producto que se desactivó
/// después de venderlo.
final saleLineProductsProvider =
    FutureProvider.autoDispose.family<List<SalesProduct>, String>(
  (ref, saleId) async {
    final detail = await ref.watch(salesHistoryDetailProvider(saleId).future);
    if (detail == null) return const [];
    final ids = [
      for (final item in detail.items)
        if (item.productId != null) item.productId!,
    ];
    return ref.watch(salesRepositoryProvider).fetchProductsByIds(ids);
  },
);
