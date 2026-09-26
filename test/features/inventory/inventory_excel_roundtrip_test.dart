import 'package:flutter_app/features/inventory/data/inventory_excel_service.dart';
import 'package:flutter_app/features/inventory/data/inventory_import_review.dart';
import 'package:flutter_app/features/inventory/data/inventory_repository.dart';
import 'package:flutter_app/shared/packaging/product_packaging.dart';
import 'package:flutter_test/flutter_test.dart';

InventoryProduct _producto({
  required String id,
  String? sku,
  String name = 'VASO PET 9 OZ',
  double price = 131.99,
  double? tier1,
  double? tier2,
  double? tier4,
  ProductPackaging packaging = ProductPackaging.none,
}) => InventoryProduct(
  id: id,
  name: name,
  sku: sku,
  barcode: null,
  categoryId: 'cat1',
  categoryName: 'Vasos',
  unit: 'paquete',
  cost: 92.39,
  price: price,
  taxRate: 18,
  stock: 1300,
  minStock: 0,
  isActive: true,
  packaging: packaging,
  priceTier1: tier1,
  priceTier2: tier2,
  priceTier4: tier4,
);

void main() {
  final service = InventoryExcelService();
  final categorias = [InventoryCategory(id: 'cat1', name: 'Vasos')];
  // Cuatro tipos de precio configurados en Ajustes.
  const tipos = ['Mayorista', 'Distribuidor', 'Especial', 'Zona franca'];

  const caja = ProductPackaging(
    unitsPerPack: 20,
    unitLabel: 'Paquete',
    packLabel: 'Caja',
    packPrice: 2639.83,
    packTierPrices: {'tier_2': 2400},
  );

  InventoryImportParseResult ida(List<InventoryProduct> productos) =>
      service.parseImport(
        bytes: service.buildExport(
          products: productos,
          categories: categorias,
          priceTypes: tipos,
        ),
        categories: categorias,
        priceTypes: tipos,
      );

  test('descargar y volver a subir actualiza: cada fila trae su id', () {
    final vaso = _producto(id: 'aaaaaaaa-0000-4000-8000-000000000001', sku: 'SP-001');
    final parsed = ida([vaso]);

    expect(parsed.inputs.single.id, vaso.id);
    expect(parsed.inputs.single.sku, 'SP-001');
    expect(countNewProducts(inputs: parsed.inputs, catalog: [vaso]), 0);
  });

  test('un producto sin SKU también se actualiza, por su id', () {
    final envase = _producto(
      id: 'aaaaaaaa-0000-4000-8000-000000000002',
      sku: null,
      name: 'ENVASE PARA HELADO 6 OZ',
    );
    final parsed = ida([envase]);

    expect(parsed.inputs.single.id, envase.id);
    expect(countNewProducts(inputs: parsed.inputs, catalog: [envase]), 0);
    expect(
      reviewImportAgainstCatalog(inputs: parsed.inputs, catalog: [envase]),
      isEmpty,
    );
  });

  test('los cuatro tipos de precio van y vuelven completos', () {
    final vaso = _producto(
      id: 'aaaaaaaa-0000-4000-8000-000000000001',
      sku: 'SP-001',
      tier1: 131.99,
      tier2: 120,
      tier4: 110,
    );
    final input = ida([vaso]).inputs.single;

    expect(input.priceTier1, 131.99);
    expect(input.priceTier2, 120);
    expect(input.priceTier4, 110, reason: 'antes se perdía y se borraba');
    expect(input.priceTiersPresent, {1, 2, 3, 4});
  });

  test('un tipo de precio que el archivo no trae no se toca', () {
    // Plantilla vieja: solo precio_2 y precio_3.
    final bytes = service.buildExport(
      products: [
        _producto(id: 'aaaaaaaa-0000-4000-8000-000000000001', sku: 'SP-001'),
      ],
      categories: categorias,
      priceTypes: const ['Mayorista', 'Distribuidor'],
    );
    final input = service
        .parseImport(bytes: bytes, categories: categorias, priceTypes: tipos)
        .inputs
        .single;

    expect(input.priceTiersPresent, {1, 2});
  });

  test('la presentación y los precios de caja no viajan en la plantilla', () {
    // Se conservan porque el repositorio los quita del payload al importar.
    final input = ida([
      _producto(
        id: 'aaaaaaaa-0000-4000-8000-000000000001',
        sku: 'SP-001',
        packaging: caja,
      ),
    ]).inputs.single;

    expect(input.packaging.hasPacks, isFalse);
    expect(
      ProductPackaging.none.toMap().keys,
      contains(ProductPackaging.packTierPricesKey),
    );
  });

  test('una fila sin id ni SKU de un producto que ya existe avisa', () {
    final vaso = _producto(
      id: 'aaaaaaaa-0000-4000-8000-000000000001',
      sku: 'SP-001',
    );
    final aMano = InventoryProductInput(
      name: 'vaso pet 9 oz',
      price: 131.99,
      cost: 0,
      stock: 0,
      minStock: 0,
      taxRate: 18,
      unit: 'unidad',
      isActive: true,
    );

    final warnings = reviewImportAgainstCatalog(
      inputs: [aMano],
      catalog: [vaso],
    );
    expect(warnings.single.messages.single, contains('creará un producto aparte'));
    expect(countNewProducts(inputs: [aMano], catalog: [vaso]), 1);
  });
}
