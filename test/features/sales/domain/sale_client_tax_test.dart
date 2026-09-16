import 'package:flutter_app/features/sales/data/sales_repository.dart';
import 'package:flutter_app/features/sales/domain/sale_checkout_service.dart';
import 'package:flutter_test/flutter_test.dart';

/// "Cobrar ITBIS" y "Exento de impuestos" del cliente.
///
/// El POS espeja la regla que aplica `checkout_sale_transactional` cuando
/// shop-plus le pasa `p_honor_client_tax` (migración 91): si la pantalla y el
/// RPC calculan distinto, el cajero cobra un total y la venta queda con otro.
void main() {
  const service = SaleCheckoutService();

  NormalizedSaleCheckout checkout({
    required String receiptType,
    bool clientSkipsTax = false,
  }) =>
      service.normalize(
        SaleCheckoutServiceInput(
          items: const [
            SaleCheckoutSourceItem(
              product: SaleCheckoutSourceProduct(
                id: 'p1',
                name: 'Tapas planas',
                price: 1533.90,
                taxRate: 18,
                stock: 94,
                isActive: true,
              ),
              quantity: 2,
            ),
          ],
          receiptType: receiptType,
          asCredit: false,
          clientId: 'c1',
          clientSkipsTax: clientSkipsTax,
        ),
      );

  group('cliente sin ITBIS', () {
    test('consumidor final a un cliente que no cobra ITBIS: total = subtotal',
        () {
      final result =
          checkout(receiptType: 'consumer_final', clientSkipsTax: true);
      expect(result.subtotal, 3067.80);
      expect(result.taxAmount, 0);
      expect(result.total, 3067.80);
      expect(result.items.single.taxRate, 0);
    });

    test('un cliente normal sigue pagando ITBIS', () {
      final result = checkout(receiptType: 'consumer_final');
      expect(result.taxAmount, closeTo(552.20, 0.001));
      expect(result.total, closeTo(3620.00, 0.001));
    });
  });

  group('SalesClient.skipsTax', () {
    SalesClient client(Map<String, dynamic> extra) =>
        SalesClient.fromMap({'id': 'c1', 'full_name': 'CIBAO FROZEN', ...extra});

    test('"Cobrar ITBIS" apagado', () {
      expect(client({'charge_itbis': false}).skipsTax, isTrue);
    });

    test('exento de impuestos', () {
      expect(client({'tax_exempt': true, 'charge_itbis': true}).skipsTax,
          isTrue);
    });

    test('sin columnas (datos viejos) cobra, como el default de la base', () {
      expect(client(const {}).skipsTax, isFalse);
    });
  });
}
