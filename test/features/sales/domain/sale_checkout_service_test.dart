import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_app/features/sales/domain/sale_checkout_service.dart';

void main() {
  const service = SaleCheckoutService();

  SaleCheckoutSourceProduct buildProduct({
    String id = 'p1',
    String name = 'Producto',
    double price = 100,
    double taxRate = 18,
    double stock = 10,
    bool isActive = true,
    bool isService = false,
    bool isTaxExempt = false,
    bool allowNegativeStock = false,
    bool priceIncludesTax = false,
    bool trackInventory = true,
  }) {
    return SaleCheckoutSourceProduct(
      id: id,
      name: name,
      price: price,
      taxRate: taxRate,
      stock: stock,
      isActive: isActive,
      isService: isService,
      isTaxExempt: isTaxExempt,
      allowNegativeStock: allowNegativeStock,
      priceIncludesTax: priceIncludesTax,
      trackInventory: trackInventory,
    );
  }

  group('normalizeReceiptType', () {
    test('normaliza aliases en español al enum canónico', () {
      expect(normalizeReceiptType('consumidor_final'), 'consumer_final');
      expect(normalizeReceiptType('Crédito Fiscal'), 'fiscal_credit');
      expect(normalizeReceiptType('gubernamental'), 'governmental');
      expect(normalizeReceiptType('régimen especial'), 'special');
      expect(normalizeReceiptType('exportación'), 'export');
    });

    test('rechaza tipos no soportados', () {
      expect(
        () => normalizeReceiptType('otro'),
        throwsA(isA<SaleCheckoutValidationException>()),
      );
    });
  });

  group('SaleCheckoutService', () {
    test('consolida líneas repetidas y calcula totales', () {
      final result = service.normalize(
        SaleCheckoutServiceInput(
          items: [
            SaleCheckoutSourceItem(
              product: buildProduct(id: 'a', name: 'A'),
              quantity: 1,
            ),
            SaleCheckoutSourceItem(
              product: buildProduct(id: 'a', name: 'A'),
              quantity: 2,
            ),
          ],
          receiptType: 'consumer_final',
          asCredit: false,
          paymentMethod: 'cash',
        ),
      );

      expect(result.items, hasLength(1));
      expect(result.items.first.quantity, 3);
      expect(result.subtotal, 300);
      expect(result.taxAmount, 54);
      expect(result.total, 354);
      expect(result.saleStatus, 'completed');
      expect(result.paidAmount, 354);
      expect(result.balanceDue, 0);
    });

    test('exige cliente para crédito y para comprobantes fiscales', () {
      expect(
        () => service.normalize(
          SaleCheckoutServiceInput(
            items: [
              SaleCheckoutSourceItem(product: buildProduct(), quantity: 1),
            ],
            receiptType: 'consumer_final',
            asCredit: true,
          ),
        ),
        throwsA(isA<SaleCheckoutValidationException>()),
      );

      expect(
        () => service.normalize(
          SaleCheckoutServiceInput(
            items: [
              SaleCheckoutSourceItem(product: buildProduct(), quantity: 1),
            ],
            receiptType: 'fiscal_credit',
            asCredit: false,
          ),
        ),
        throwsA(isA<SaleCheckoutValidationException>()),
      );
    });

    // El stock solo se valida en el cliente cuando `inv_disallow_no_stock`
    // está prendido (commit e34adf7, "ventas sin stock"): si el dueño permite
    // vender en negativo, el POS deja pasar y decide el RPC.
    test('rechaza productos sin stock cuando disallowNoStock está activo', () {
      expect(
        () => service.normalize(
          SaleCheckoutServiceInput(
            items: [
              SaleCheckoutSourceItem(
                product: buildProduct(stock: 1),
                quantity: 2,
              ),
            ],
            receiptType: 'consumer_final',
            asCredit: false,
            disallowNoStock: true,
          ),
        ),
        throwsA(isA<SaleCheckoutValidationException>()),
      );
    });

    test('permite vender sin stock cuando disallowNoStock está apagado', () {
      final result = service.normalize(
        SaleCheckoutServiceInput(
          items: [
            SaleCheckoutSourceItem(
              product: buildProduct(stock: 1),
              quantity: 2,
            ),
          ],
          receiptType: 'consumer_final',
          asCredit: false,
        ),
      );
      expect(result.items.single.quantity, 2);
    });
  });

  group('descuento por línea', () {
    test('descuenta del bruto y calcula el ITBIS sobre la base descontada', () {
      final result = service.normalize(
        SaleCheckoutServiceInput(
          items: [
            SaleCheckoutSourceItem(
              product: buildProduct(price: 100, taxRate: 18),
              quantity: 2,
              discountPct: 10,
            ),
          ],
          receiptType: 'consumer_final',
          asCredit: false,
        ),
      );

      final line = result.items.single;
      // bruto 200 − 10% = 180 de base; ITBIS 18% sobre 180 = 32.40.
      expect(line.discountAmount, 20);
      expect(line.lineSubtotal, 180);
      expect(line.lineTax, 32.40);
      expect(line.lineTotal, 212.40);
      expect(result.total, 212.40);
    });

    test('el descuento viaja al RPC como discount_amount (monto absoluto)', () {
      final result = service.normalize(
        SaleCheckoutServiceInput(
          items: [
            SaleCheckoutSourceItem(
              product: buildProduct(price: 50),
              quantity: 1,
              discountPct: 25,
            ),
          ],
          receiptType: 'consumer_final',
          asCredit: false,
        ),
      );

      // 25% sobre 50 = 12.50. Se manda el MONTO, que es lo que lee la
      // función viva en la base (migración 76 del árbol flutter_shop+).
      expect(result.toRpcItems().single['discount_amount'], 12.50);
      expect(result.toRpcItems().single['unit_price'], 50);
      expect(result.toRpcItems().single.containsKey('discount_pct'), false);
    });

    test('sin descuento el total no cambia', () {
      final result = service.normalize(
        SaleCheckoutServiceInput(
          items: [
            SaleCheckoutSourceItem(
              product: buildProduct(price: 100, taxRate: 18),
              quantity: 1,
            ),
          ],
          receiptType: 'consumer_final',
          asCredit: false,
        ),
      );

      expect(result.items.single.discountAmount, 0);
      expect(result.total, 118);
    });
  });

  group('banderas del producto que el RPC aplica', () {
    test('un producto exento no factura ITBIS aunque tenga tasa', () {
      final result = service.normalize(
        SaleCheckoutServiceInput(
          items: [
            SaleCheckoutSourceItem(
              product: buildProduct(price: 100, taxRate: 18, isTaxExempt: true),
              quantity: 1,
            ),
          ],
          receiptType: 'consumer_final',
          asCredit: false,
        ),
      );

      expect(result.items.single.taxRate, 0);
      expect(result.taxAmount, 0);
      expect(result.total, 100);
    });

    test('un servicio se vende aunque el stock sea 0 y se exija stock', () {
      final result = service.normalize(
        SaleCheckoutServiceInput(
          items: [
            SaleCheckoutSourceItem(
              product: buildProduct(stock: 0, isService: true),
              quantity: 3,
            ),
          ],
          receiptType: 'consumer_final',
          asCredit: false,
          disallowNoStock: true,
        ),
      );

      expect(result.items.single.quantity, 3);
    });

    test('un producto con stock negativo permitido tampoco se bloquea', () {
      final result = service.normalize(
        SaleCheckoutServiceInput(
          items: [
            SaleCheckoutSourceItem(
              product: buildProduct(stock: 1, allowNegativeStock: true),
              quantity: 5,
            ),
          ],
          receiptType: 'consumer_final',
          asCredit: false,
          disallowNoStock: true,
        ),
      );

      expect(result.items.single.quantity, 5);
    });

    test('un producto normal sin stock sigue bloqueado', () {
      expect(
        () => service.normalize(
          SaleCheckoutServiceInput(
            items: [
              SaleCheckoutSourceItem(
                product: buildProduct(stock: 0),
                quantity: 1,
              ),
            ],
            receiptType: 'consumer_final',
            asCredit: false,
            disallowNoStock: true,
          ),
        ),
        throwsA(isA<SaleCheckoutValidationException>()),
      );
    });
  });

  group('precio con ITBIS incluido', () {
    test('extrae el impuesto en vez de agregarlo: 100.00 sigue siendo 100.00', () {
      final result = service.normalize(
        SaleCheckoutServiceInput(
          items: [
            SaleCheckoutSourceItem(
              product: buildProduct(
                price: 100,
                taxRate: 18,
                priceIncludesTax: true,
              ),
              quantity: 1,
            ),
          ],
          receiptType: 'consumer_final',
          asCredit: false,
        ),
      );

      final line = result.items.single;
      // 100 × 18/118 = 15.2542… → 15.25 (misma fórmula que el RPC).
      expect(line.lineTax, 15.25);
      expect(line.lineSubtotal, 84.75);
      expect(line.lineTotal, 100.00);
      expect(result.total, 100.00);
    });

    test('sin comprobante no se extrae nada: el neto es el total', () {
      final result = service.normalize(
        SaleCheckoutServiceInput(
          items: [
            SaleCheckoutSourceItem(
              product: buildProduct(
                price: 100,
                taxRate: 18,
                priceIncludesTax: true,
              ),
              quantity: 1,
            ),
          ],
          receiptType: 'none',
          asCredit: false,
        ),
      );

      expect(result.taxAmount, 0);
      expect(result.total, 100.00);
    });

    test('con descuento, el total incluido es el neto exacto', () {
      final result = service.normalize(
        SaleCheckoutServiceInput(
          items: [
            SaleCheckoutSourceItem(
              product: buildProduct(
                price: 100,
                taxRate: 18,
                priceIncludesTax: true,
              ),
              quantity: 2,
              discountPct: 10,
            ),
          ],
          receiptType: 'consumer_final',
          asCredit: false,
        ),
      );

      // bruto 200 − 10% = 180 de total; ITBIS extraído 180×18/118 = 27.46.
      expect(result.items.single.discountAmount, 20);
      expect(result.items.single.lineTax, 27.46);
      expect(result.total, 180.00);
    });
  });

  group('aritmética en centavos', () {
    test('el medio centavo redondea como Postgres, no como un double', () {
      final result = service.normalize(
        SaleCheckoutServiceInput(
          items: [
            SaleCheckoutSourceItem(
              product: buildProduct(price: 2208.99, taxRate: 0),
              quantity: 0.5,
            ),
          ],
          receiptType: 'consumer_final',
          asCredit: false,
        ),
      );

      // 2208.99 × 0.5 = 1104.495. Postgres `round(…, 2)` da 1104.50.
      // Con doubles, (1104.495 * 100) vale 110449.49999999999 y redondeaba a
      // 1104.49 — un centavo por debajo del RPC, suficiente para que un pago
      // dividido rebotara con "los pagos no cubren el total".
      expect(result.items.single.lineSubtotal, 1104.50);
      expect(result.total, 1104.50);
    });
  });

  group('control de inventario', () {
    test('un producto sin track_inventory no se valida contra stock', () {
      final result = service.normalize(
        SaleCheckoutServiceInput(
          items: [
            SaleCheckoutSourceItem(
              product: buildProduct(stock: 0, trackInventory: false),
              quantity: 4,
            ),
          ],
          receiptType: 'consumer_final',
          asCredit: false,
          disallowNoStock: true,
        ),
      );

      expect(result.items.single.quantity, 4);
    });
  });
}
