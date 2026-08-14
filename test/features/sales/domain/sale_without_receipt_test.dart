import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_app/features/sales/domain/sale_checkout_service.dart';

/// Venta SIN comprobante (`receipt_type = 'none'`): nota de venta no fiscal.
/// No consume NCF, no exige cliente y no factura ITBIS.
///
/// Estas reglas espejan `normalize_receipt_type` y `v_line_tax_rate` del RPC
/// `checkout_sale_transactional` (migración 64). Si el POS y el RPC calculan
/// distinto, el cajero cobra un total que no coincide con el registrado.
void main() {
  const service = SaleCheckoutService();

  SaleCheckoutSourceProduct product({double price = 100, double taxRate = 18}) {
    return SaleCheckoutSourceProduct(
      id: 'p1',
      name: 'Producto',
      price: price,
      taxRate: taxRate,
      stock: 10,
      isActive: true,
    );
  }

  SaleCheckoutServiceInput input({
    required String receiptType,
    String? clientId,
    double quantity = 1,
  }) {
    return SaleCheckoutServiceInput(
      items: [SaleCheckoutSourceItem(product: product(), quantity: quantity)],
      receiptType: receiptType,
      asCredit: false,
      clientId: clientId,
    );
  }

  group('normalizeReceiptType · sin comprobante', () {
    test('acepta "none" y sus alias en español', () {
      expect(normalizeReceiptType('none'), 'none');
      expect(normalizeReceiptType('Sin comprobante'), 'none');
      expect(normalizeReceiptType('ninguno'), 'none');
    });

    test('vacío sigue cayendo en consumidor final', () {
      expect(normalizeReceiptType(''), 'consumer_final');
    });
  });

  group('Venta sin comprobante', () {
    test('no factura ITBIS: total = subtotal', () {
      final result = service.normalize(input(receiptType: 'none', quantity: 2));

      expect(result.receiptType, 'none');
      expect(result.subtotal, 200);
      expect(result.taxAmount, 0);
      expect(result.total, 200);
      expect(result.items.single.lineTax, 0);
      expect(result.items.single.lineTotal, 200);
      // La tasa que viaja al RPC también va en 0.
      expect(result.items.single.taxRate, 0);
    });

    test('no exige cliente', () {
      expect(
        () => service.normalize(input(receiptType: 'none')),
        returnsNormally,
      );
    });

    test('paid_amount de contado cuadra con el total sin ITBIS', () {
      final result = service.normalize(input(receiptType: 'none', quantity: 2));
      expect(result.paidAmount, 200);
      expect(result.balanceDue, 0);
    });
  });

  group('Comprobantes fiscales (no cambian)', () {
    test('consumidor final sigue facturando ITBIS', () {
      final result = service.normalize(
        input(receiptType: 'consumer_final', quantity: 2),
      );

      expect(result.subtotal, 200);
      expect(result.taxAmount, 36);
      expect(result.total, 236);
    });

    test('crédito fiscal sigue exigiendo cliente', () {
      expect(
        () => service.normalize(input(receiptType: 'fiscal_credit')),
        throwsA(isA<SaleCheckoutValidationException>()),
      );
    });
  });
}
