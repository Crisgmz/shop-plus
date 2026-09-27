import 'package:flutter_app/features/quotations/data/quotations_models.dart';
import 'package:flutter_app/shared/packaging/product_packaging.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  // VASO PET 9 OZ: caja de 20 paquetes a RD$2,639.83; paquete suelto 175.
  QuoteCatalogProduct vaso() => QuoteCatalogProduct(
    id: 'sp001',
    name: 'VASO PET 9 OZ',
    price: 175,
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

  /// Lo que la pantalla manda a guardar desde una línea.
  QuoteCreateItem aGuardar(QuoteDraftLine line) => QuoteCreateItem(
    productId: line.product.id,
    productName: line.product.name,
    quantity: line.baseQuantity,
    unitPrice: line.unitPrice,
    taxRate: line.product.taxRate,
    discountAmount: line.discountAmount,
    uom: line.uom.dbValue,
    uomFactor: line.uomFactor,
    uomPrice: line.isPresentation ? line.presentationPrice : null,
    unitName: line.isPresentation ? line.unitName : null,
  );

  group('la línea de cotización cotiza por caja', () {
    test('2 cajas se cotizan a su precio, no al paquete × 20', () {
      final line = QuoteDraftLine(
        product: vaso(),
        quantity: 2,
        uom: PackagingUom.pack,
      );

      expect(line.presentationPrice, 2639.83);
      expect(line.lineSubtotal, 5279.66);
      expect(line.lineTax, closeTo(950.34, 0.001));
      expect(line.lineTotal, closeTo(6230.00, 0.001));
      // A la base va en unidades base: 2 cajas = 40 paquetes.
      expect(line.baseQuantity, 40);
      expect(line.unitName, 'Caja');
    });

    test('suelto cotiza el paquete', () {
      final line = QuoteDraftLine(product: vaso(), quantity: 3);
      expect(line.presentationPrice, 175);
      expect(line.lineSubtotal, 525);
      expect(line.baseQuantity, 3);
      expect(line.isPresentation, isFalse);
    });

    test('el precio escrito a mano manda sobre el de la caja', () {
      final line = QuoteDraftLine(
        product: vaso(),
        quantity: 1,
        uom: PackagingUom.pack,
        presentationPriceOverride: 2500,
      );
      expect(line.lineSubtotal, 2500);
    });

    test('el descuento se aplica sobre el precio de la caja', () {
      final line = QuoteDraftLine(
        product: vaso(),
        quantity: 1,
        uom: PackagingUom.pack,
        discountPct: 10,
      );
      expect(line.netUnitPrice, closeTo(2375.85, 0.001));
      expect(line.discountAmount, closeTo(263.98, 0.001));
    });

    test('cambiar de presentación retoma el precio configurado', () {
      final caja = QuoteDraftLine(
        product: vaso(),
        quantity: 2,
        uom: PackagingUom.pack,
        presentationPriceOverride: 2500,
      );
      final suelto = caja.copyWith(
        uom: PackagingUom.unit,
        quantity: 1,
        clearPresentationPrice: true,
      );
      expect(suelto.presentationPrice, 175);
    });
  });

  group('lo que se guarda y se vuelve a leer', () {
    test('la línea guardada conserva la caja y su precio', () {
      final item = aGuardar(
        QuoteDraftLine(product: vaso(), quantity: 2, uom: PackagingUom.pack),
      );

      expect(item.quantity, 40);
      expect(item.uom, 'pack');
      expect(item.uomFactor, 20);
      expect(item.uomPrice, 2639.83);
      expect(item.lineSubtotal, 5279.66);
      expect(item.lineTotal, closeTo(6230.00, 0.001));

      final rpc = item.toRpcMap();
      expect(rpc['quantity'], 40);
      expect(rpc['uom'], 'pack');
      expect(rpc['uom_price'], 2639.83);
      expect(rpc['unit_name'], 'Caja');
    });

    test('una línea suelta no manda campos de presentación', () {
      final rpc = aGuardar(
        QuoteDraftLine(product: vaso(), quantity: 3),
      ).toRpcMap();

      expect(rpc.containsKey('uom'), isFalse);
      expect(rpc['quantity'], 3);
    });

    test('al reabrirla vuelve como 2 cajas', () {
      final leida = QuoteCreateItem.fromMap({
        'product_id': 'sp001',
        'product_name': 'VASO PET 9 OZ',
        'quantity': 40,
        'unit_price': 175,
        'tax_rate': 18,
        'discount_amount': 0,
        'uom': 'pack',
        'uom_factor': 20,
        'uom_price': 2639.83,
        'unit_name': 'Caja',
      });

      expect(leida.presentationQuantity, 2);
      expect(leida.lineSubtotal, 5279.66);
      expect(leida.isPresentation, isTrue);
    });

    test('una cotización vieja, sin presentación, se lee igual que antes', () {
      final leida = QuoteCreateItem.fromMap({
        'product_id': 'sp001',
        'product_name': 'VASO PET 9 OZ',
        'quantity': 2,
        'unit_price': 175,
        'tax_rate': 18,
        'discount_amount': 0,
      });

      expect(leida.uom, 'unit');
      expect(leida.isPresentation, isFalse);
      expect(leida.presentationQuantity, 2);
      expect(leida.lineSubtotal, 350);
    });
  });

  group('estado de la cotización en el desplegable', () {
    test('las que se eligen a mano no incluyen "Convertida"', () {
      final opciones = quoteStatusOptions(QuoteStatus.draft);
      expect(opciones, isNot(contains(QuoteStatus.converted)));
      expect(opciones, contains(QuoteStatus.draft));
    });

    test('una cotización ya convertida trae su propio estado', () {
      // Sin esto el desplegable revienta: su valor no estaba entre los items.
      final opciones = quoteStatusOptions(QuoteStatus.converted);
      expect(opciones.where((s) => s == QuoteStatus.converted), hasLength(1));
    });
  });
}
