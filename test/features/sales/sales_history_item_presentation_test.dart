import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_app/features/sales/data/sales_history_repository.dart';
import 'package:flutter_app/features/sales/domain/sale_checkout_service.dart';
import 'package:flutter_app/shared/packaging/product_packaging.dart';

void main() {
  // FA-000008: 4 Cajas de 20 a RD$ 6,182.20. `sale_items` la guarda en
  // unidades base (80) con el unitario de detalle (508.47) y el precio de la
  // caja en `uom_price`.
  final boxLine = SalesHistoryItem.fromMap({
    'id': 'a',
    'product_id': 'p',
    'description': 'VASOS PET 16 OZ',
    'quantity': 80,
    'unit_price': 508.47,
    'discount_amount': 0,
    'tax_rate': 18,
    'line_subtotal': 24728.80,
    'line_tax': 4451.18,
    'line_total': 29179.98,
    'uom': 'pack',
    'uom_factor': 20,
    'uom_price': 6182.20,
    'unit_name': 'Caja',
  });

  test('una línea por caja se lee en cajas y al precio de la caja', () {
    expect(boxLine.isPresentation, isTrue);
    expect(boxLine.presentationQuantity, 4);
    expect(boxLine.presentationPrice, 6182.20);
    expect(boxLine.presentationLabel, 'Caja');
    // El bruto que recalcula la edición es el mismo que cobró el RPC.
    expect(
      fromCents(grossCents(
        boxLine.presentationQuantity,
        boxLine.presentationPrice,
      )),
      24728.80,
    );
  });

  test('sin uom_price (antes de la migración 92) deriva de unitario', () {
    final legacy = SalesHistoryItem.fromMap({
      'quantity': 24,
      'unit_price': 10.5,
      'uom': 'box',
      'uom_factor': 12,
    });
    expect(legacy.presentationQuantity, 2);
    expect(legacy.presentationPrice, 126);
    expect(legacy.presentationLabel, 'Caja');
  });

  test('los IMEIs de la línea se leen para poder reenviarlos al editar', () {
    final phones = SalesHistoryItem.fromMap({
      'quantity': 2,
      'unit_price': 15000,
      'imeis': ['356938035643809', '', '356938035643817'],
    });
    expect(phones.imeis, ['356938035643809', '356938035643817']);
    expect(boxLine.imeis, isEmpty);
  });

  test('una línea suelta queda igual que antes', () {
    final unit = SalesHistoryItem.fromMap({
      'quantity': 3,
      'unit_price': 99.99,
    });
    expect(unit.uom, PackagingUom.unit);
    expect(unit.isPresentation, isFalse);
    expect(unit.presentationQuantity, 3);
    expect(unit.presentationPrice, 99.99);
  });
}
