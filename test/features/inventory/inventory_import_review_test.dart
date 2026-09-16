import 'package:flutter_app/features/inventory/data/inventory_import_review.dart';
import 'package:flutter_app/features/inventory/data/inventory_repository.dart';
import 'package:flutter_app/shared/packaging/product_packaging.dart';
import 'package:flutter_test/flutter_test.dart';

InventoryProduct _product({
  required String sku,
  required String name,
  required double price,
  required double stock,
  bool isActive = true,
  ProductPackaging packaging = ProductPackaging.none,
}) =>
    InventoryProduct(
      id: sku,
      name: name,
      sku: sku,
      barcode: null,
      categoryId: null,
      categoryName: null,
      unit: 'paquete',
      cost: 0,
      price: price,
      taxRate: 18,
      stock: stock,
      minStock: 0,
      isActive: isActive,
      packaging: packaging,
    );

InventoryProductInput _row({
  required String sku,
  required double price,
  required double stock,
  bool isActive = true,
}) =>
    InventoryProductInput(
      name: sku,
      sku: sku,
      price: price,
      cost: 0,
      stock: stock,
      minStock: 0,
      taxRate: 18,
      unit: 'unidad',
      isActive: isActive,
    );

void main() {
  // Como quedó VASO PET 16 OZ ALTO tras el script 12.
  final vasoAlto = _product(
    sku: 'SP-005',
    name: 'VASO PET 16 OZ ALTO',
    price: 168.64,
    stock: 1020,
    packaging: const ProductPackaging(
      unitsPerPack: 20,
      unitLabel: 'Paquete',
      packLabel: 'Caja',
      packPrice: 3372.88,
    ),
  );
  // Su gemelo por unidad, desactivado.
  final gemelo = _product(
    sku: 'SP-026',
    name: 'VASO PET 16 OZ ALTO',
    price: 10.17,
    stock: 0,
    isActive: false,
  );

  test('un archivo viejo con precio y stock de caja se marca', () {
    final warnings = reviewImportAgainstCatalog(
      inputs: [_row(sku: 'SP-005', price: 3372.88, stock: 53)],
      catalog: [vasoAlto, gemelo],
    );

    expect(warnings, hasLength(1));
    expect(warnings.single.sku, 'SP-005');
    expect(warnings.single.messages, hasLength(2));
    expect(warnings.single.messages[0], contains('parece de caja'));
    expect(
      warnings.single.messages[1],
      contains('51 Cajas → 2 Cajas · 13 Paquetes'),
    );
  });

  test('reactivar un gemelo desactivado se marca', () {
    final warnings = reviewImportAgainstCatalog(
      inputs: [_row(sku: 'SP-026', price: 10.17, stock: 0)],
      catalog: [vasoAlto, gemelo],
    );
    expect(warnings.single.messages.single, contains('vuelve a activar'));
  });

  test('el mismo producto sin cambios no avisa', () {
    final warnings = reviewImportAgainstCatalog(
      inputs: [
        _row(sku: 'SP-005', price: 168.64, stock: 1020),
        _row(sku: 'SP-026', price: 10.17, stock: 0, isActive: false),
      ],
      catalog: [vasoAlto, gemelo],
    );
    expect(warnings, isEmpty);
  });

  test('un precio de paquete razonable no se marca como de caja', () {
    final warnings = reviewImportAgainstCatalog(
      inputs: [_row(sku: 'SP-005', price: 175, stock: 1020)],
      catalog: [vasoAlto],
    );
    expect(warnings, isEmpty);
  });

  test('productos sin empaque y SKU nuevos no avisan', () {
    final envase = _product(sku: 'ENV-1', name: 'ENVASE', price: 7.2, stock: 0);
    final warnings = reviewImportAgainstCatalog(
      inputs: [
        _row(sku: 'ENV-1', price: 9, stock: 300),
        _row(sku: 'NUEVO-1', price: 50, stock: 10),
      ],
      catalog: [envase],
    );
    expect(warnings, isEmpty);
  });
}
