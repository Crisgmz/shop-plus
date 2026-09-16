import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_app/shared/widgets/ui_custom.dart';

const _columnas = [
  FlexTableColumn(label: 'Fecha', width: 96),
  FlexTableColumn(label: 'Cliente', flex: 3),
  FlexTableColumn(label: 'Estado', width: 100),
  FlexTableColumn(label: 'Total', numeric: true, width: 116),
];

List<List<Widget>> _filas() => [
      [
        const Text('16-09-2026'),
        const Text('Distribuidora del Cibao con un nombre larguísimo, S.R.L.'),
        const Text('Pagada'),
        const Text('RD\$ 6,200.00'),
      ],
    ];

Future<void> _pintar(
  WidgetTester tester, {
  required double ancho,
  required bool singleLine,
  double? minWidth,
}) async {
  tester.view.physicalSize = Size(ancho, 600);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: FlexTable(
          singleLine: singleLine,
          minWidth: minWidth,
          columns: _columnas,
          rows: _filas(),
        ),
      ),
    ),
  );
}

/// Alto del párrafo más alto de la tabla. Una línea de 13 px mide menos de
/// 26; si algo se partió en dos, lo supera.
double _parrafoMasAlto(WidgetTester tester) => tester
    .renderObjectList<RenderParagraph>(find.byType(RichText))
    .map((p) => p.size.height)
    .reduce((a, b) => a > b ? a : b);

void main() {
  group('FlexTable · una fila por registro', () {
    testWidgets('sin el modo una línea, el texto largo SÍ se parte',
        (tester) async {
      // Control: prueba que la medición detecta el problema de la captura.
      await _pintar(tester, ancho: 700, singleLine: false);
      expect(_parrafoMasAlto(tester), greaterThan(26));
    });

    testWidgets('en modo una línea, ninguna celda baja a otra línea',
        (tester) async {
      await _pintar(tester, ancho: 700, singleLine: true);
      expect(_parrafoMasAlto(tester), lessThan(26));
    });

    testWidgets('respeta los anchos fijos de cada columna', (tester) async {
      await _pintar(tester, ancho: 1000, singleLine: true);
      final tabla = tester.widget<Table>(find.byType(Table));
      expect(tabla.columnWidths![0], isA<FixedColumnWidth>());
      expect((tabla.columnWidths![0] as FixedColumnWidth).value, 96);
      expect(tabla.columnWidths![1], isA<FlexColumnWidth>());
    });
  });

  group('FlexTable · pantallas angostas', () {
    testWidgets('más angosta que el mínimo: se desplaza, no se aplasta',
        (tester) async {
      await _pintar(tester, ancho: 600, singleLine: true, minWidth: 900);
      expect(find.byType(SingleChildScrollView), findsOneWidget);
      expect(tester.getSize(find.byType(Table)).width, 900);
    });

    testWidgets('con espacio suficiente no aparece scroll', (tester) async {
      await _pintar(tester, ancho: 1200, singleLine: true, minWidth: 900);
      expect(find.byType(SingleChildScrollView), findsNothing);
    });

    testWidgets('sin mínimo se comporta como siempre (Cobros, Por pagar)',
        (tester) async {
      await _pintar(tester, ancho: 600, singleLine: false);
      expect(find.byType(SingleChildScrollView), findsNothing);
    });
  });
}
