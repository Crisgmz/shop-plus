import 'package:flutter_app/features/quotations/data/quotations_models.dart';
import 'package:flutter_test/flutter_test.dart';

QuoteCatalogProduct producto({
  double price = 118,
  bool incluido = false,
  bool exento = false,
}) =>
    QuoteCatalogProduct(
      id: 'p1',
      name: 'Producto',
      price: price,
      taxRate: 18,
      stock: 10,
      isActive: true,
      priceIncludesTax: incluido,
      isTaxExempt: exento,
    );

void main() {
  test('precio con ITBIS incluido: se extrae, no se suma', () {
    final line = QuoteDraftLine(product: producto(incluido: true), quantity: 1);
    expect(line.lineTotal, 118);
    expect(line.lineTax, 18);
    expect(line.lineSubtotal, 100);
  });

  test('producto exento: sin ITBIS', () {
    final line = QuoteDraftLine(product: producto(exento: true), quantity: 2);
    expect(line.lineTax, 0);
    expect(line.lineTotal, 236);
  });

  test('precio normal: ITBIS encima, como antes', () {
    final line = QuoteDraftLine(product: producto(price: 100), quantity: 1);
    expect(line.lineSubtotal, 100);
    expect(line.lineTax, 18);
    expect(line.lineTotal, 118);
  });

  test('lo que se guarda y lo que se recarga dan lo mismo', () {
    final line = QuoteDraftLine(product: producto(incluido: true), quantity: 3);
    final item = QuoteCreateItem(
      productId: 'p1',
      productName: 'Producto',
      quantity: line.baseQuantity,
      unitPrice: line.unitPrice,
      taxRate: line.product.effectiveTaxRate,
      priceIncludesTax: line.product.priceIncludesTax,
      discountAmount: line.discountAmount,
    );
    expect(item.lineTotal, 354);
    // Recargada desde la base (sin la bandera): se deduce de los montos.
    final reloaded = QuoteCreateItem.fromMap(item.toRpcMap());
    expect(reloaded.priceIncludesTax, isTrue);
    expect(reloaded.lineTotal, 354);
    expect(reloaded.lineTax, item.lineTax);
  });
}
