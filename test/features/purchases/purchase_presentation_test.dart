import 'package:flutter_app/features/purchases/data/purchases_repository.dart';
import 'package:flutter_app/shared/packaging/product_packaging.dart';
import 'package:flutter_test/flutter_test.dart';

/// Compra por presentación: el proveedor factura 3 cajas a RD$ 1,234.56.
///
/// Los montos salen del costo por caja tal cual, para que la compra cuadre
/// con la factura del proveedor (y con el 606). El inventario recibe las
/// unidades base, y `products.cost` el costo por unidad.
void main() {
  final vasos = PurchaseProduct(
    id: 'p1',
    name: 'Vasos 12oz',
    cost: 100,
    price: 150,
    stock: 0,
    packaging: const ProductPackaging(unitsPerPack: 12, packLabel: 'Caja'),
  );

  group('línea de compra', () {
    test('3 cajas: montos exactos de la factura, 36 unidades al stock', () {
      final line = PurchaseLineInput(
        product: vasos,
        quantity: 3,
        unitCost: 1234.56,
        taxRate: 18,
        uom: PackagingUom.pack,
      );
      expect(line.lineSubtotal, 3703.68);
      expect(line.baseQuantity, 36);
      expect(line.unitCostPerBase, 102.88);
    });

    test('por unidad queda igual que antes', () {
      final line = PurchaseLineInput(
        product: vasos,
        quantity: 5,
        unitCost: 100,
        taxRate: 18,
      );
      expect(line.baseQuantity, 5);
      expect(line.unitCostPerBase, 100);
      expect(line.lineSubtotal, 500);
    });
  });

  group('detalle guardado', () {
    test('se muestra en cajas y con el costo exacto de la caja', () {
      final detail = PurchaseItemDetail(
        description: 'Vasos 12oz',
        quantity: 36,
        unitCost: 102.88,
        taxRate: 18,
        lineSubtotal: 3703.68,
        lineTax: 666.66,
        lineTotal: 4370.34,
        unitName: 'Caja',
        uom: PackagingUom.pack,
        uomFactor: 12,
      );
      expect(detail.presentationQuantity, 3);
      expect(detail.presentationUnitCost, closeTo(1234.56, 0.0001));
    });

    test('una línea por unidad no cambia', () {
      final detail = PurchaseItemDetail(
        description: 'Vasos 12oz',
        quantity: 5,
        unitCost: 100,
        taxRate: 18,
        lineSubtotal: 500,
        lineTax: 90,
        lineTotal: 590,
      );
      expect(detail.isPresentation, isFalse);
      expect(detail.presentationQuantity, 5);
      expect(detail.presentationUnitCost, 100);
    });
  });
}
