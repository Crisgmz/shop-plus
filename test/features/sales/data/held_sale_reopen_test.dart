import 'package:flutter_app/features/sales/data/sales_repository.dart';
import 'package:flutter_app/shared/packaging/product_packaging.dart';
import 'package:flutter_test/flutter_test.dart';

// Vasos: detalle a 508.47 la unidad, caja de 20 a 6,182.20 y, a Precio 2,
// 400.00 la unidad y 7,000.00 la caja.
SalesProduct _vasos({double unitsPerPack = 20}) => SalesProduct(
      id: 'vasos',
      name: 'VASOS PET 16 OZ',
      price: 508.47,
      cost: 200,
      taxRate: 18,
      stock: 580,
      isActive: true,
      priceTier1: 400,
      packaging: ProductPackaging(
        unitsPerPack: unitsPerPack,
        packLabel: 'Caja',
        packPrice: 6182.20,
        packTierPrices: const {'tier_1': 7000},
      ),
    );

Map<String, dynamic> _boxRow({
  double quantity = 80,
  double unitPrice = 508.47,
  double? uomPrice = 6182.20,
  double discountAmount = 0,
}) =>
    {
      'product_id': 'vasos',
      'quantity': quantity,
      'unit_price': unitPrice,
      'discount_amount': discountAmount,
      'uom': 'pack',
      'uom_factor': 20,
      'uom_price': uomPrice,
    };

void main() {
  test('una caja a su precio vuelve como caja y sin precio manual', () {
    final item = cartItemFromHeldSaleRow(_boxRow(), _vasos())!;

    expect(item.uom, PackagingUom.pack);
    expect(item.quantity, 4);
    expect(item.priceTier, 'retail');
    expect(item.presentationPriceOverride, isNull);
    expect(item.presentationPrice, 6182.20);
    expect(item.lineGross, 24728.80);
  });

  test('una caja a Precio 2 vuelve a Precio 2, no a Detalle', () {
    final item = cartItemFromHeldSaleRow(
      _boxRow(quantity: 40, unitPrice: 400, uomPrice: 7000),
      _vasos(),
    )!;

    expect(item.priceTier, 'tier_1');
    expect(item.presentationPriceOverride, isNull);
    expect(item.presentationPrice, 7000);
    expect(item.lineGross, 14000);
  });

  test('un precio de caja escrito a mano se conserva, con su descuento', () {
    final item = cartItemFromHeldSaleRow(
      _boxRow(uomPrice: 6000, discountAmount: 2400),
      _vasos(),
    )!;

    expect(item.presentationPriceOverride, 6000);
    expect(item.lineGross, 24000);
    expect(item.discountPct, closeTo(10, 1e-9));
    expect(item.lineDiscount, 2400);
  });

  test('si el empaque cambió, vuelve suelta con el unitario de la caja', () {
    final item = cartItemFromHeldSaleRow(
      _boxRow(),
      _vasos(unitsPerPack: 24),
    )!;

    expect(item.uom, PackagingUom.unit);
    expect(item.quantity, 80);
    expect(item.unitPrice, 309.11);
    expect(item.lineGross, 24728.80);
  });

  test('una línea suelta con IMEIs queda igual', () {
    final item = cartItemFromHeldSaleRow(
      {
        'product_id': 'vasos',
        'quantity': 2,
        'unit_price': 508.47,
        'discount_amount': 0,
        'uom': 'unit',
        'uom_factor': 1,
        'imeis': ['111', ' ', '222'],
      },
      _vasos(),
    )!;

    expect(item.uom, PackagingUom.unit);
    expect(item.quantity, 2);
    expect(item.unitPrice, 508.47);
    expect(item.imeis, ['111', '222']);
  });

  test('una fila sin cantidad se descarta', () {
    expect(cartItemFromHeldSaleRow(_boxRow(quantity: 0), _vasos()), isNull);
  });
}
