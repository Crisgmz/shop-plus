import 'dart:convert';
import 'dart:typed_data';

import 'package:excel/excel.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_app/features/inventory/data/inventory_excel_service.dart';

const _priceTypes = ['Mayorista', 'Distribuidor', 'VIP'];

Uint8List _bytes(String csv) => Uint8List.fromList(utf8.encode(csv));

List<String> _headersOf(List<int> bytes) {
  final sheet = Excel.decodeBytes(bytes).tables['Productos']!;
  return sheet.rows.first
      .map((c) => (c?.value as TextCellValue?)?.value.text ?? '')
      .toList();
}

/// CSV con encabezados arbitrarios y una fila de producto con los 3 niveles.
String _csv(List<String> tierHeaders) {
  return 'nombre,costo,precio,${tierHeaders.join(',')}\n'
      'Producto A,50,100,90,85,80\n';
}

void main() {
  final service = InventoryExcelService();

  group('Plantilla de inventario · niveles de precio', () {
    test('los encabezados usan los tipos de precio configurados', () {
      final headers = _headersOf(
        service.buildTemplate(categories: const [], priceTypes: _priceTypes),
      );

      expect(headers, containsAll(_priceTypes));
      expect(headers, isNot(contains('precio_2')));
      // El precio base sigue llamándose "precio".
      expect(headers, contains('precio'));
    });

    test('sin tipos configurados conserva los encabezados legados', () {
      final headers = _headersOf(service.buildTemplate(categories: const []));
      expect(headers, containsAll(['precio_2', 'precio_3', 'precio_4']));
    });

    test('un nombre que choca con otra columna cae al encabezado legado', () {
      final headers = _headersOf(
        service.buildTemplate(
          categories: const [],
          priceTypes: const ['costo', 'Distribuidor', ''],
        ),
      );

      // 'costo' ya es una columna de la plantilla → ese slot queda legado.
      expect(headers, contains('precio_2'));
      expect(headers, contains('Distribuidor'));
      // Slot vacío → legado.
      expect(headers, contains('precio_4'));
    });

    test('al importar se aceptan los nombres configurados', () {
      final result = service.parseImportCsv(
        bytes: _bytes(_csv(_priceTypes)),
        categories: const [],
        priceTypes: _priceTypes,
      );

      expect(result.errors, isEmpty);
      final product = result.inputs.single;
      expect(product.priceTier1, 90);
      expect(product.priceTier2, 85);
      expect(product.priceTier3, 80);
    });

    test('al importar se siguen aceptando los encabezados legados', () {
      final result = service.parseImportCsv(
        bytes: _bytes(_csv(const ['precio_2', 'precio_3', 'precio_4'])),
        categories: const [],
        priceTypes: _priceTypes,
      );

      expect(result.errors, isEmpty);
      final product = result.inputs.single;
      expect(product.priceTier1, 90);
      expect(product.priceTier2, 85);
      expect(product.priceTier3, 80);
    });

    test('sin columnas de nivel los tiers quedan nulos', () {
      final result = service.parseImportCsv(
        bytes: _bytes('nombre,costo,precio\nProducto A,50,100\n'),
        categories: const [],
        priceTypes: _priceTypes,
      );

      expect(result.errors, isEmpty);
      final product = result.inputs.single;
      expect(product.priceTier1, isNull);
      expect(product.priceTier2, isNull);
      expect(product.priceTier3, isNull);
    });
  });
}
