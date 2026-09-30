import 'package:flutter/material.dart';
import 'package:flutter_app/features/sales/data/sales_history_repository.dart';
import 'package:flutter_app/features/sales/data/sales_repository.dart';
import 'package:flutter_app/features/sales/presentation/sales_edit_page.dart';
import 'package:flutter_app/features/sales/presentation/sales_history_providers.dart';
import 'package:flutter_app/features/sales/presentation/sales_providers.dart';
import 'package:flutter_app/features/settings/data/app_settings.dart';
import 'package:flutter_app/features/settings/presentation/app_settings_providers.dart';
import 'package:flutter_app/shared/packaging/product_packaging.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

// FA-000008: 4 Cajas de 20 VASOS PET 16 OZ a RD$ 6,182.20 la caja, crédito
// fiscal. `sale_items` la guarda en unidades base (80) con el unitario de
// Detalle (508.47) y el precio de la caja en `uom_price`.
SalesProduct _vasosCon({double stock = 580}) => SalesProduct(
  id: 'vasos',
  name: 'VASOS PET 16 OZ',
  price: 508.47,
  cost: 200,
  taxRate: 18,
  stock: stock,
  isActive: true,
  priceTier1: 300,
  packaging: const ProductPackaging(
    unitsPerPack: 20,
    packLabel: 'Caja',
    packPrice: 6182.20,
    packTierPrices: {'tier_1': 5800},
  ),
);

SalesHistoryDetail _detailFor(String receiptType) => SalesHistoryDetail(
  sale: SalesHistoryRow.fromMap({
    'id': 'venta',
    'sale_number': 'FA-000008',
    'sale_date': '2026-09-30T13:29:00Z',
    'status': 'completed',
    'receipt_type': receiptType,
    'ncf': 'B0100000200',
    'total_amount': 29179.98,
    'paid_amount': 29179.98,
    'client_id': 'sober',
  }),
  items: [
    SalesHistoryItem.fromMap({
      'id': 'linea',
      'product_id': 'vasos',
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
    }),
  ],
  subtotal: 24728.80,
  taxAmount: 4451.18,
  paymentMethod: 'transfer',
  paymentMethods: const ['transfer'],
  paymentCount: 1,
);

/// Devuelve FA-000008 y guarda lo que la pantalla manda al RPC.
class _FakeHistoryRepo implements SalesHistoryRepository {
  _FakeHistoryRepo(this.receiptType);

  final String receiptType;
  List<Map<String, dynamic>>? saved;

  @override
  Future<SalesHistoryDetail?> fetchDetail(String saleId) async =>
      _detailFor(receiptType);

  @override
  Future<SalesEditResult> editSale({
    required String saleId,
    required List<Map<String, dynamic>> items,
    String? clientId,
    bool clearClient = false,
    String? notes,
    bool clearNotes = false,
    bool clientSkipsTax = false,
  }) async {
    saved = items;
    return SalesEditResult(
      saleId: saleId,
      subtotal: 0,
      taxAmount: 0,
      totalAmount: 0,
      paidAmount: 0,
      balanceDue: 0,
      itemsCount: items.length,
    );
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// Ajustes con un segundo tipo de precio: así aparece el selector.
class _FakeSettings extends AppSettingsController {
  @override
  Future<AppSettings> build() async => const AppSettings({
    'sale_price_types': ['Por Mayor'],
  });
}

Future<_FakeHistoryRepo> _openEdit(
  WidgetTester tester, {
  double stock = 580,
  String? clientRnc = '133334781',
  String receiptType = 'fiscal_credit',
}) async {
  tester.view.physicalSize = const Size(1400, 1000);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);

  final repo = _FakeHistoryRepo(receiptType);
  final router = GoRouter(
    initialLocation: '/editar',
    routes: [
      GoRoute(
        path: '/editar',
        // En la app la envuelve el Scaffold del AppShell.
        builder: (_, _) => const Scaffold(body: SalesEditPage(saleId: 'venta')),
      ),
      GoRoute(
        path: '/ventas/historial',
        builder: (_, _) => const Text('historial'),
      ),
    ],
  );
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        salesHistoryRepositoryProvider.overrideWithValue(repo),
        salesProductsProvider.overrideWith(
          (ref) async => [_vasosCon(stock: stock)],
        ),
        saleLineProductsProvider.overrideWith(
          (ref, saleId) async => [_vasosCon(stock: stock)],
        ),
        salesClientsProvider.overrideWith(
          (ref) async => [
            SalesClient(
              id: 'sober',
              fullName: 'SOBER LOUNGE SRL',
              documentNumber: clientRnc,
            ),
          ],
        ),
        appSettingsProvider.overrideWith(_FakeSettings.new),
      ],
      child: MaterialApp.router(routerConfig: router),
    ),
  );
  await tester.pumpAndSettle();
  return repo;
}

Future<void> _save(WidgetTester tester) async {
  await tester.tap(find.text('Guardar cambios'));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('abre la venta en cajas, al precio de la caja', (tester) async {
    final repo = await _openEdit(tester);

    expect(find.text('Cajas'), findsOneWidget);
    expect(find.widgetWithText(TextField, '4'), findsOneWidget);
    expect(find.widgetWithText(TextField, '6182.20'), findsOneWidget);
    expect(find.text('Caja · 20 u'), findsOneWidget);
    expect(find.text('Detalle'), findsOneWidget);
    // Total de la factura, no 80 × 508.47.
    expect(find.text('RD\$ 29,179.98'), findsWidgets);
    expect(find.text('RD\$ 47,999.57'), findsNothing);

    await _save(tester);
    final item = repo.saved!.single;
    expect(item['quantity'], 80);
    expect(item['uom'], 'pack');
    expect(item['uom_factor'], 20);
    expect(item['uom_price'], 6182.20);
    expect(item['unit_name'], 'Caja');
    expect(item['discount_amount'], 0);
  });

  testWidgets('el tipo de precio cambia el precio de la caja', (tester) async {
    final repo = await _openEdit(tester);

    await tester.tap(find.text('Detalle'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Por Mayor').last);
    await tester.pumpAndSettle();

    expect(find.widgetWithText(TextField, '5800'), findsOneWidget);
    // 4 × 5,800 = 23,200 + 18% = 27,376.
    expect(find.text('RD\$ 27,376.00'), findsWidgets);

    await _save(tester);
    final item = repo.saved!.single;
    expect(item['quantity'], 80);
    expect(item['unit_price'], 300);
    expect(item['uom_price'], 5800);
  });

  testWidgets('se puede pasar de caja a suelto', (tester) async {
    final repo = await _openEdit(tester);

    await tester.tap(find.text('Caja · 20 u'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Unidad').last);
    await tester.pumpAndSettle();

    expect(find.text('Cantidad'), findsOneWidget);
    expect(find.widgetWithText(TextField, '508.47'), findsOneWidget);

    await _save(tester);
    final item = repo.saved!.single;
    expect(item['quantity'], 1);
    expect(item['unit_price'], 508.47);
    expect(item.containsKey('uom'), isFalse);
    expect(item.containsKey('uom_price'), isFalse);
  });

  testWidgets('lo que la venta ya tenía cuenta como disponible', (
    tester,
  ) async {
    // Quedan 20 vasos (1 caja) + las 4 cajas de la venta = 5 cajas.
    final repo = await _openEdit(tester, stock: 20);
    final qty = find.widgetWithText(TextField, '4');

    await tester.enterText(qty, '6');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();
    expect(find.text('Sin stock suficiente'), findsOneWidget);

    await tester.enterText(find.widgetWithText(TextField, '6'), '5');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();

    await _save(tester);
    expect(repo.saved!.single['quantity'], 100);
  });

  testWidgets('una factura B01 no se guarda con un cliente sin RNC', (
    tester,
  ) async {
    final repo = await _openEdit(tester, clientRnc: null);

    expect(find.textContaining('no tiene RNC o cédula'), findsOneWidget);
    await _save(tester);
    expect(repo.saved, isNull);
  });

  testWidgets('avisa que la factura tiene NCF', (tester) async {
    await _openEdit(tester);
    expect(find.textContaining('Factura con NCF B0100000200'), findsOneWidget);
  });

  testWidgets('B02: el precio va con el ITBIS adentro y no se desglosa', (
    tester,
  ) async {
    final repo = await _openEdit(tester, receiptType: 'consumer_final');

    // 6,182.20 + 18% = 7,294.996 → 7,295.00 por caja.
    expect(find.widgetWithText(TextField, '7295'), findsOneWidget);
    expect(find.text('ITBIS'), findsNothing);
    expect(find.text('Subtotal'), findsNothing);
    expect(find.text('RD\$ 29,179.98'), findsWidgets);

    // Lo que se guarda sigue siendo el precio base de la caja.
    await _save(tester);
    expect(repo.saved!.single['uom_price'], 6182.20);
  });
}
