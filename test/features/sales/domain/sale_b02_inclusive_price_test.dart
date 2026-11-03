import 'package:flutter_app/features/sales/data/sales_repository.dart';
import 'package:flutter_app/features/sales/domain/sale_checkout_service.dart';
import 'package:flutter_app/shared/packaging/product_packaging.dart';
import 'package:flutter_test/flutter_test.dart';

/// B02: se cobra exactamente el precio CON ITBIS que se ve y se escribe, y el
/// impuesto se saca de adentro (migración 99). Antes se guardaba la base
/// (600 / 1.18 = 508.47) y se le volvía a sumar el ITBIS: 3 × 600 daba
/// 1,799.98 y 2 × 320 daba 640.01.
void main() {
  SalesProduct product({
    String id = 'p1',
    double price = 508.47,
    ProductPackaging packaging = const ProductPackaging(),
  }) =>
      SalesProduct(
        id: id,
        name: 'Producto $id',
        price: price,
        cost: 100,
        taxRate: 18,
        stock: 500,
        isActive: true,
        packaging: packaging,
      );

  /// Lo que hace el POS al escribir [typed] en una línea B02.
  SaleCartItem typedB02(
    SalesProduct p,
    double typed, {
    double quantity = 1,
    PackagingUom uom = PackagingUom.unit,
  }) {
    final item = SaleCartItem(
      product: p,
      quantity: quantity,
      uom: uom,
      taxInclusive: true,
    );
    final base = (typed / 1.18 * 100).roundToDouble() / 100;
    return item.isPresentation
        ? item.copyWith(
            presentationPriceOverride: base,
            inclusivePriceOverride: typed,
          )
        : item.copyWith(unitPrice: base, inclusivePriceOverride: typed);
  }

  // Igual que `SalesRepository.checkoutSale` arma cada ítem.
  SaleCheckoutSourceItem sourceOf(SaleCartItem item) => SaleCheckoutSourceItem(
        product: SaleCheckoutSourceProduct(
          id: item.product.id,
          name: item.product.name,
          price: item.unitPrice,
          taxRate: item.product.taxRate,
          stock: item.product.stock,
          isActive: item.product.isActive,
        ),
        quantity: item.baseQuantity,
        discountPct: item.discountPct,
        uom: item.uom.dbValue,
        uomFactor: item.uomFactor,
        uomPrice: item.isPresentation ? item.presentationPrice : null,
        unitName: item.isPresentation ? item.presentationLabel : null,
        inclusivePrice: item.inclusiveMode ? item.inclusivePrice : null,
      );

  NormalizedSaleCheckout checkout(
    List<SaleCartItem> cart, {
    String receiptType = 'consumer_final',
  }) =>
      const SaleCheckoutService().normalize(
        SaleCheckoutServiceInput(
          items: [for (final it in cart) sourceOf(it)],
          receiptType: receiptType,
          asCredit: false,
          disallowNoStock: false,
        ),
      );

  group('línea del carrito', () {
    test('3 × 600.00 escrito son 1,800.00 exactos', () {
      final line = typedB02(product(), 600, quantity: 3);
      expect(line.inclusiveMode, isTrue);
      expect(line.isCustomPrice, isTrue);
      expect(line.lineTotal, 1800);
      expect(line.lineTax, 274.58);
      expect(line.lineSubtotal, 1525.42);
    });

    test('2 × 320.00 escrito son 640.00, no 640.01', () {
      final line = typedB02(product(price: 271.19), 320, quantity: 2);
      expect(line.lineTotal, 640);
      expect(line.lineTax, 97.63);
    });

    test('4 cajas a 7,295.00 son 29,180.00', () {
      final line = typedB02(
        product(
          packaging: const ProductPackaging(
            unitsPerPack: 12,
            packLabel: 'Caja',
          ),
        ),
        7295,
        quantity: 4,
        uom: PackagingUom.pack,
      );
      expect(line.baseQuantity, 48);
      expect(line.lineTotal, 29180);
    });

    test('sin precio escrito cobra el del catálogo con ITBIS que se ve', () {
      final line = SaleCartItem(
        product: product(),
        quantity: 3,
        taxInclusive: true,
      );
      // 508.47 × 1.18 = 599.99: lo que muestra la línea.
      expect(line.inclusivePrice, 599.99);
      expect(line.lineTotal, 1799.97);
      expect(line.isCustomPrice, isFalse);
    });

    test('fuera de B02 sigue cobrando la base más el ITBIS', () {
      final line = typedB02(product(), 600, quantity: 3)
          .copyWith(taxInclusive: false);
      expect(line.inclusiveMode, isFalse);
      expect(line.lineTotal, 1799.98);
      // Al volver a B02 se recupera el precio escrito.
      expect(line.copyWith(taxInclusive: true).lineTotal, 1800);
    });

    test('cambiar el tipo de precio descarta el precio escrito', () {
      final line = typedB02(product(), 600, quantity: 3).copyWith(
        unitPrice: 508.47,
        clearPresentationPrice: true,
      );
      expect(line.inclusivePriceOverride, isNull);
      expect(line.inclusivePrice, 599.99);
    });
  });

  group('checkout', () {
    test('la pantalla y el RPC dan el mismo total al centavo', () {
      final cart = [
        typedB02(product(), 600, quantity: 3),
        typedB02(product(id: 'p2', price: 271.19), 320, quantity: 2),
      ];
      final result = checkout(cart);
      expect(result.total, 2440);
      expect(
        result.total,
        cart.fold<double>(0, (s, it) => s + it.lineTotal),
      );
      expect(result.taxAmount, 372.21);
      expect(result.subtotal, 2067.79);
    });

    test('el precio con ITBIS viaja al RPC como inclusive_price', () {
      final rpc = checkout([typedB02(product(), 600, quantity: 3)])
          .toRpcItems()
          .single;
      expect(rpc['inclusive_price'], 600);
      expect(rpc['unit_price'], 508.47);
    });

    test('sin comprobante no se manda: no hay ITBIS que sacar', () {
      final result = checkout(
        [typedB02(product(), 600, quantity: 3)],
        receiptType: 'none',
      );
      expect(result.toRpcItems().single.containsKey('inclusive_price'), isFalse);
      expect(result.taxAmount, 0);
    });

    test('con descuento, el ITBIS sale del neto descontado', () {
      final line =
          typedB02(product(), 600, quantity: 2).copyWith(discountPct: 10);
      final result = checkout([line]);
      expect(result.total, 1080);
      expect(line.lineTotal, 1080);
    });
  });
}
