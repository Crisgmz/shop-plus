import 'package:flutter_app/features/printing/data/printing_models.dart';
import 'package:flutter_app/features/sales/data/sales_repository.dart';
import 'package:flutter_app/features/sales/domain/sale_checkout_service.dart';
import 'package:flutter_app/shared/packaging/product_packaging.dart';
import 'package:flutter_test/flutter_test.dart';

/// Venta por presentación: una caja de 12 vasos a RD$ 100 el vaso.
///
/// El precio UNITARIO manda y viaja al checkout junto con la cantidad en
/// unidades base, así el RPC compartido (que no conoce empaques) calcula
/// exactamente lo mismo que la pantalla. Estos tests fijan ese contrato.
void main() {
  SalesProduct vasos({double stock = 500, double? minUnits}) => SalesProduct(
        id: 'p1',
        name: 'Vasos 12oz',
        price: 100,
        cost: 60,
        taxRate: 18,
        stock: stock,
        isActive: true,
        packaging: ProductPackaging(
          unitsPerPack: 12,
          packLabel: 'Caja',
          minUnitQty: minUnits,
        ),
      );

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
      );

  NormalizedSaleCheckout checkout(
    List<SaleCartItem> cart, {
    bool disallowNoStock = false,
  }) =>
      const SaleCheckoutService().normalize(
        SaleCheckoutServiceInput(
          items: [for (final it in cart) sourceOf(it)],
          receiptType: 'consumer_final',
          asCredit: false,
          disallowNoStock: disallowNoStock,
        ),
      );

  group('línea del carrito por presentación', () {
    test('2 cajas son 24 unidades y la caja vale unitario × 12', () {
      final line = SaleCartItem(
        product: vasos(),
        quantity: 2,
        uom: PackagingUom.pack,
      );
      expect(line.baseQuantity, 24);
      expect(line.presentationPrice, 1200);
      expect(line.presentationLabel, 'Caja');
      expect(line.lineGross, 2400);
      expect(line.lineTotal, 2832); // + 18% ITBIS
    });

    test('suelta funciona exactamente como antes', () {
      final line = SaleCartItem(product: vasos(), quantity: 5);
      expect(line.isPresentation, isFalse);
      expect(line.baseQuantity, 5);
      expect(line.presentationPrice, 100);
      expect(line.lineGross, 500);
    });

    test('copyWith conserva la presentación', () {
      final line = SaleCartItem(
        product: vasos(),
        quantity: 1,
        uom: PackagingUom.pack,
      );
      final changed = line.copyWith(discountPct: 10);
      expect(changed.uom, PackagingUom.pack);
      expect(changed.baseQuantity, 12);
    });

    test('la venta mínima bloquea suelto, nunca una caja completa', () {
      final product = vasos(minUnits: 6);
      expect(SaleCartItem(product: product, quantity: 5).respectsMinimum,
          isFalse);
      expect(SaleCartItem(product: product, quantity: 6).respectsMinimum,
          isTrue);
      expect(
        SaleCartItem(product: product, quantity: 1, uom: PackagingUom.pack)
            .respectsMinimum,
        isTrue,
      );
    });
  });

  group('checkout', () {
    test('una caja y unidades sueltas son dos líneas en unidades base', () {
      final result = checkout([
        SaleCartItem(product: vasos(), quantity: 1, uom: PackagingUom.pack),
        SaleCartItem(product: vasos(), quantity: 5),
      ]);

      expect(result.items, hasLength(2));
      expect(result.items[0].uom, 'pack');
      expect(result.items[0].quantity, 12);
      expect(result.items[1].uom, 'unit');
      expect(result.items[1].quantity, 5);
      expect(
        [for (final i in result.toRpcItems()) i['quantity']],
        [12, 5],
      );
    });

    test('la pantalla y el checkout calculan el mismo total', () {
      final cart = [
        SaleCartItem(
          product: vasos(),
          quantity: 3,
          uom: PackagingUom.pack,
          discountPct: 7,
        ),
        SaleCartItem(product: vasos(), quantity: 5),
      ];
      final screen = cart.fold<double>(0, (s, it) => s + it.lineTotal);
      expect(checkout(cart).total, closeTo(screen, 0.001));
    });

    test('solo las líneas por presentación se marcan después del cobro', () {
      final tags = checkout([
        SaleCartItem(product: vasos(), quantity: 2, uom: PackagingUom.pack),
        SaleCartItem(product: vasos(), quantity: 5),
      ]).toPresentationTags();

      expect(tags, hasLength(1));
      expect(tags.single, {
        'product_id': 'p1',
        'quantity': 24.0,
        'unit_price': 100.0,
        'uom': 'pack',
        'uom_factor': 12.0,
        'unit_name': 'Caja',
      });
    });

    test('el inventario se valida sumando todas las presentaciones', () {
      final cart = [
        SaleCartItem(
          product: vasos(stock: 16),
          quantity: 1,
          uom: PackagingUom.pack,
        ),
        SaleCartItem(product: vasos(stock: 16), quantity: 5),
      ];
      // 12 + 5 = 17 > 16, aunque cada línea por separado entre.
      expect(
        () => checkout(cart, disallowNoStock: true),
        throwsA(isA<SaleCheckoutValidationException>()),
      );
    });
  });

  group('precio escrito por presentación', () {
    test('se reparte exacto cuando da centavos enteros', () {
      expect(ProductPackaging.unitPriceFromPresentation(1200, 12), 100);
    });

    test('se ajusta al centavo por unidad cuando no', () {
      expect(ProductPackaging.unitPriceFromPresentation(100, 12), 8.33);
    });
  });

  group('impresión', () {
    PrintDocumentItem item({double quantity = 2, String? label}) =>
        PrintDocumentItem(
          description: 'Vasos 12oz',
          quantity: quantity,
          unitPrice: 1200,
          lineSubtotal: 2400,
          lineTax: 0,
          lineTotal: 2400,
          presentationLabel: label,
        );

    test('una presentación se imprime con su nombre', () {
      expect(item(label: 'Caja').quantityLabel, '2 Cajas');
      expect(item(quantity: 1, label: 'Caja').quantityLabel, '1 Caja');
      expect(item(label: 'Caja').descriptionWithPresentation,
          'Vasos 12oz (Caja)');
    });

    test('una línea por unidad no cambia', () {
      expect(item().quantityLabel, '2');
      expect(item().descriptionWithPresentation, 'Vasos 12oz');
    });
  });

  group('ejemplo del negocio · caja de 40 unidades', () {
    // 200 cajas de 40 = 8000 unidades en `products.stock`.
    SalesProduct caja40() => SalesProduct(
          id: 'p40',
          name: 'Vasos',
          price: 5,
          cost: 3,
          taxRate: 0,
          stock: 8000,
          isActive: true,
          packaging:
              const ProductPackaging(unitsPerPack: 40, packLabel: 'Caja'),
        );

    // Lo que descuenta el trigger de stock: la suma de `quantity` que viaja
    // al checkout, que siempre va en unidades base.
    double sold(List<SaleCartItem> cart) => checkout(cart)
        .toRpcItems()
        .fold<double>(0, (s, i) => s + (i['quantity'] as num).toDouble());

    test('vender 1 caja descuenta esa caja completa', () {
      final product = caja40();
      final left = product.stock -
          sold([
            SaleCartItem(product: product, quantity: 1, uom: PackagingUom.pack),
          ]);
      expect(left, 7960);
      expect(product.packaging.describeStock(left), '199 Cajas');
    });

    test('vender 10 unidades las descuenta de una caja', () {
      final product = caja40();
      final left = product.stock -
          sold([
            SaleCartItem(product: product, quantity: 1, uom: PackagingUom.pack),
            SaleCartItem(product: product, quantity: 10),
          ]);
      expect(left, 7950);
      expect(product.packaging.describeStock(left), '198 Cajas · 30 Unidades');
    });
  });

  group('precio propio de la presentación · caso CIBAO FROZEN', () {
    // Caja de 20 paquetes a RD$2,639.83. El paquete a 131.99: repartir la caja
    // al centavo por paquete daría 2,639.80 — tres centavos menos por caja.
    SalesProduct vasoPet() => SalesProduct(
          id: 'sp001',
          name: 'VASO PET 9 OZ',
          price: 131.99,
          cost: 80,
          taxRate: 18,
          stock: 1300,
          isActive: true,
          packaging: const ProductPackaging(
            unitsPerPack: 20,
            unitLabel: 'Paquete',
            packLabel: 'Caja',
            packPrice: 2639.83,
          ),
        );

    test('la caja se cobra a su precio, no unitario × 20', () {
      final line =
          SaleCartItem(product: vasoPet(), quantity: 1, uom: PackagingUom.pack);
      expect(line.presentationPrice, 2639.83);
      expect(line.lineGross, 2639.83);
      expect(line.baseQuantity, 20);
    });

    test('el precio escrito a mano manda sobre el configurado', () {
      final line = SaleCartItem(
        product: vasoPet(),
        quantity: 2,
        uom: PackagingUom.pack,
        presentationPriceOverride: 2500,
      );
      expect(line.lineGross, 5000);
    });

    test('suelto sigue cobrando el precio del paquete', () {
      final line = SaleCartItem(product: vasoPet(), quantity: 3);
      expect(line.presentationPrice, 131.99);
      expect(line.lineGross, closeTo(395.97, 0.001));
    });

    test('al checkout viaja el precio de la caja y la cantidad en paquetes',
        () {
      final item = checkout([
        SaleCartItem(product: vasoPet(), quantity: 1, uom: PackagingUom.pack),
      ]).toRpcItems().single;

      expect(item['quantity'], 20);        // unidades base → descuenta stock
      expect(item['uom_price'], 2639.83);  // precio con que se cobra
      expect(item['uom_factor'], 20);
      expect(item['unit_name'], 'Caja');
    });

    test('una línea suelta no manda campos de presentación', () {
      final item = checkout([SaleCartItem(product: vasoPet(), quantity: 3)])
          .toRpcItems()
          .single;
      expect(item.containsKey('uom_price'), isFalse);
      expect(item.containsKey('uom'), isFalse);
    });

    test('pantalla y checkout dan el mismo total', () {
      final cart = [
        SaleCartItem(product: vasoPet(), quantity: 2, uom: PackagingUom.pack),
        SaleCartItem(product: vasoPet(), quantity: 5),
      ];
      final pantalla = cart.fold<double>(0, (s, it) => s + it.lineTotal);
      expect(checkout(cart).total, closeTo(pantalla, 0.001));
    });
  });
}
