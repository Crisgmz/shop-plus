import 'package:flutter/material.dart';
import 'package:flutter_app/features/sales/data/sales_repository.dart';
import 'package:flutter_app/features/sales/presentation/cart_line_tile.dart';
import 'package:flutter_app/features/settings/data/app_settings.dart';
import 'package:flutter_app/features/settings/presentation/app_settings_providers.dart';
import 'package:flutter_app/shared/packaging/product_packaging.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

class _FakeSettings extends AppSettingsController {
  @override
  Future<AppSettings> build() async => const AppSettings({
    'sale_price_types': ['Por Mayor'],
  });
}

final _item = SaleCartItem(
  product: SalesProduct(
    id: 'vasos',
    name: 'VASOS PET 16 OZ',
    price: 508.47,
    cost: 200,
    taxRate: 18,
    stock: 580,
    isActive: true,
    priceTier1: 300,
    packaging: const ProductPackaging(
      unitsPerPack: 20,
      packLabel: 'Caja',
      packPrice: 6182.20,
    ),
  ),
  quantity: 1,
  uom: PackagingUom.pack,
);

Future<void> _pumpTile(
  WidgetTester tester,
  double width, {
  bool shaded = false,
}) async {
  tester.view.physicalSize = const Size(1400, 600);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [appSettingsProvider.overrideWith(_FakeSettings.new)],
      child: MaterialApp(
        home: Scaffold(
          body: Align(
            alignment: Alignment.topLeft,
            child: SizedBox(
              width: width,
              child: CartLineTile(
                item: _item,
                shaded: shaded,
                chargesTax: true,
                onRemove: () {},
                onPriceChanged: (_) {},
                onQuantityChanged: (_) {},
                onDiscountChanged: (_) {},
                onPriceTierChanged: (_) {},
                onUomChanged: (_) {},
              ),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('con espacio, tipo de precio y presentación van junto al '
      'nombre', (tester) async {
    await _pumpTile(tester, 1000);

    final name = tester.getRect(find.text('VASOS PET 16 OZ'));
    final tier = tester.getRect(find.text('Detalle'));
    final uom = tester.getRect(find.text('Caja · 20 u'));
    final priceLabel = tester.getRect(find.text('Precio caja'));

    // Al lado del nombre (no en el borde derecho), en su misma línea y por
    // encima de los campos.
    expect(tier.bottom, lessThan(priceLabel.top));
    expect(tier.left, greaterThan(name.right));
    // El chip (su ícono) empieza a pocos píxeles del nombre.
    final tierIcon = tester.getRect(find.byIcon(Icons.sell_outlined));
    expect(tierIcon.left - name.right, lessThan(30));
    expect((tier.center.dy - uom.center.dy).abs(), lessThan(1));
    expect((tier.center.dy - name.center.dy).abs(), lessThan(1));
  });

  testWidgets('en el carrito angosto del POS van debajo del nombre', (
    tester,
  ) async {
    await _pumpTile(tester, 420);

    final inventory = tester.getRect(find.textContaining('Inventario:'));
    final tier = tester.getRect(find.text('Detalle'));
    expect(tier.top, greaterThan(inventory.bottom));
  });

  group('sombreado por producto', () {
    test('cambia cada vez que cambia el producto', () {
      expect(shadesByProduct(['vasos', 'tapas', 'platos']), [
        false,
        true,
        false,
      ]);
    });

    test('las líneas seguidas del mismo producto comparten tono', () {
      // Vasos por caja y sueltos, luego tapas, luego vasos otra vez.
      expect(shadesByProduct(['vasos', 'vasos', 'tapas', 'vasos']), [
        false,
        false,
        true,
        false,
      ]);
    });

    test('sin líneas no hay tonos', () {
      expect(shadesByProduct(const []), isEmpty);
    });

    testWidgets('la línea sombreada tiene otro fondo', (tester) async {
      Color background() {
        final box = tester.widget<Container>(
          find
              .ancestor(
                of: find.byType(LayoutBuilder),
                matching: find.byType(Container),
              )
              .first,
        );
        return (box.decoration! as BoxDecoration).color!;
      }

      await _pumpTile(tester, 1000);
      final plain = background();
      await _pumpTile(tester, 1000, shaded: true);
      expect(background(), isNot(plain));
    });
  });
}
