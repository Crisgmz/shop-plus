import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../auth/presentation/auth_providers.dart';
import '../data/inventory_repository.dart';

final inventorySearchProvider = StateProvider<String>((ref) => '');
final inventoryLowStockOnlyProvider = StateProvider<bool>((ref) => false);

/// Ver los productos archivados (desactivados). Apagado: no aparecen en la
/// lista, igual que ya no aparecen en el punto de venta. Es lo que queda de
/// "eliminar" un producto con ventas: la factura vieja lo necesita, así que
/// no se borra, se esconde.
final inventoryShowArchivedProvider = StateProvider<bool>((ref) => false);
final inventorySelectedCategoryProvider = StateProvider<String?>((ref) => null);

/// IDs de productos marcados para borrado masivo. Vive en un provider (no en
/// el estado local de la página) para que la selección no se pierda al
/// navegar a otra sección y volver.
final inventorySelectionProvider =
    StateProvider<Set<String>>((ref) => <String>{});

final inventoryRepositoryProvider = Provider<InventoryRepository>((ref) {
  final client = ref.watch(supabaseClientProvider);
  return InventoryRepository(client);
});

final inventoryCategoriesProvider = FutureProvider<List<InventoryCategory>>((
  ref,
) async {
  final repository = ref.watch(inventoryRepositoryProvider);
  return repository.fetchCategories();
});

/// Lista completa de productos. Antes era un StreamProvider que recibía
/// la lista entera cada vez que cambiaba 1 producto; ahora es Future +
/// el RealtimeInvalidator lo invalida cuando hay cambios en `products`,
/// disparando un refetch limpio.
final inventoryProductsProvider =
    FutureProvider<List<InventoryProduct>>((ref) async {
  final repository = ref.watch(inventoryRepositoryProvider);
  return repository.fetchProducts();
});

/// Productos filtrados por búsqueda + categoría + low-stock. Memoizado
/// — antes el filter + fold corrían en cada `build()`.
final inventoryFilteredProductsProvider =
    Provider<List<InventoryProduct>>((ref) {
  final productsAsync = ref.watch(inventoryProductsProvider);
  final products = productsAsync.valueOrNull;
  if (products == null) return const <InventoryProduct>[];

  final query = ref.watch(inventorySearchProvider).trim().toLowerCase();
  final categoryId = ref.watch(inventorySelectedCategoryProvider);
  final lowStockOnly = ref.watch(inventoryLowStockOnlyProvider);
  final showArchived = ref.watch(inventoryShowArchivedProvider);

  return products.where((p) {
    if (!showArchived && !p.isActive) return false;
    if (lowStockOnly && !p.isLowStock) return false;
    if (categoryId != null && p.categoryId != categoryId) return false;
    if (query.isEmpty) return true;
    final name = p.name.toLowerCase();
    if (name.contains(query)) return true;
    final sku = p.sku?.toLowerCase();
    if (sku != null && sku.contains(query)) return true;
    final barcode = p.barcode?.toLowerCase();
    if (barcode != null && barcode.contains(query)) return true;
    final cat = p.categoryName?.toLowerCase();
    if (cat != null && cat.contains(query)) return true;
    return false;
  }).toList(growable: false);
});

/// Cuántos productos archivados hay, para el chip del filtro.
final inventoryArchivedCountProvider = Provider<int>((ref) {
  final products = ref.watch(inventoryProductsProvider).valueOrNull;
  if (products == null) return 0;
  return products.where((p) => !p.isActive).length;
});

/// KPIs del listado filtrado (costo total, precio total, stock total).
/// Memoizado para no recorrer la lista 3 veces en cada rebuild.
class InventoryKpis {
  const InventoryKpis({
    required this.totalCost,
    required this.totalPrice,
    required this.totalStock,
  });

  final double totalCost;
  final double totalPrice;
  final double totalStock;
}

final inventoryFilteredKpisProvider = Provider<InventoryKpis>((ref) {
  final filtered = ref.watch(inventoryFilteredProductsProvider);
  var cost = 0.0;
  var price = 0.0;
  var stock = 0.0;
  for (final p in filtered) {
    cost += p.cost * p.stock;
    price += p.price * p.stock;
    stock += p.stock;
  }
  return InventoryKpis(
    totalCost: cost,
    totalPrice: price,
    totalStock: stock,
  );
});
