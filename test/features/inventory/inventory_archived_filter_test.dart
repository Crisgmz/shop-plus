import 'package:flutter_app/features/inventory/data/inventory_repository.dart';
import 'package:flutter_app/features/inventory/presentation/inventory_providers.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

InventoryProduct _producto(String name, {required bool isActive}) =>
    InventoryProduct(
      id: 'id-$name',
      name: name,
      sku: null,
      barcode: null,
      categoryId: null,
      categoryName: null,
      unit: 'unidad',
      cost: 0,
      price: 10,
      taxRate: 18,
      stock: 5,
      minStock: 0,
      isActive: isActive,
    );

void main() {
  final catalogo = [
    _producto('VASO PET 9 OZ', isActive: true),
    _producto('VASO PET 9 OZ (gemelo)', isActive: false),
  ];

  ProviderContainer contenedor() {
    final c = ProviderContainer(
      overrides: [
        inventoryProductsProvider.overrideWith((ref) async => catalogo),
      ],
    );
    addTearDown(c.dispose);
    return c;
  }

  test('un producto archivado no sale en la lista', () async {
    final c = contenedor();
    await c.read(inventoryProductsProvider.future);

    expect(
      c.read(inventoryFilteredProductsProvider).map((p) => p.name),
      ['VASO PET 9 OZ'],
    );
    expect(c.read(inventoryArchivedCountProvider), 1);
  });

  test('el chip "Archivados" los vuelve a mostrar', () async {
    final c = contenedor();
    await c.read(inventoryProductsProvider.future);
    c.read(inventoryShowArchivedProvider.notifier).state = true;

    expect(c.read(inventoryFilteredProductsProvider), hasLength(2));
  });

  test('la búsqueda tampoco encuentra un archivado', () async {
    final c = contenedor();
    await c.read(inventoryProductsProvider.future);
    c.read(inventorySearchProvider.notifier).state = 'gemelo';

    expect(c.read(inventoryFilteredProductsProvider), isEmpty);
  });
}
