import 'package:excel/excel.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_app/features/reports/export/dgii_xlsx.dart';

void main() {
  Map<String, dynamic> compra(int i) => {
        'rnc_proveedor': '131999999',
        'tipo_id': '1',
        'tipo_bien_servicio': '09',
        'ncf': 'B01${i.toString().padLeft(8, '0')}',
        'ncf_modificado': null,
        'fecha_comprobante': '20260805',
        'fecha_pago': '20260805',
        'monto_facturado': 1000 + i,
        'itbis_facturado': 180.5,
        'monto_total': 1180.5 + i,
        'supplier_name': 'Proveedor $i',
        'monto_servicios': 0,
        'pagos': const {},
        'pagado': 1180.5 + i,
        'saldo': 0,
        'fecha_ultimo_pago': null,
      };

  List<List<Data?>> filas(Excel excel, String hoja) => excel.tables[hoja]!.rows;

  // Al releer, el paquete devuelve 1000.0 como IntCellValue: lo que importa
  // es que la celda sea numérica y no texto como "RD\$ 1,000.00".
  num? numero(Data? celda) => switch (celda?.value) {
        IntCellValue(:final value) => value,
        DoubleCellValue(:final value) => value,
        _ => null,
      };

  String? texto(Data? celda) => switch (celda?.value) {
        TextCellValue(:final value) => value.text,
        _ => null,
      };

  test('606: encabezado DGII, 23 columnas y todas las filas', () {
    final data = {
      'formato_version': 2,
      'rnc_negocio': '131000001',
      'period': '202608',
      'records_count': 250,
      'rows': [for (var i = 0; i < 250; i++) compra(i)],
      'inconsistencies': const [],
      'inconsistencies_count': 0,
    };

    final excel = Excel.decodeBytes(buildDgii606Xlsx(data));

    expect(excel.tables.keys, ['606']);
    final rows = filas(excel, '606');
    expect(texto(rows[0][0]), 'RNC o Cédula');
    expect(texto(rows[0][1]), '131000001');
    expect(texto(rows[1][1]), '202608');
    expect(numero(rows[2][1]), 250);

    final titulos = rows[dgiiXlsxFilaTitulos];
    expect(titulos.where((c) => c?.value != null), hasLength(23));
    expect(texto(titulos[3]), 'NCF');
    expect(texto(titulos[22]), 'Forma de Pago');

    // Sin el tope de 200 de la vista previa.
    expect(rows.length - dgiiXlsxFilaTitulos - 1, 250);
    final primera = rows[dgiiXlsxFilaTitulos + 1];
    expect(texto(primera[3]), 'B0100000000');
    expect(primera[4]?.value, isNull); // NCF modificado vacío
    expect(numero(primera[9]), 1000);
    expect(numero(primera[10]), 180.5);
    expect(texto(primera[22]), '01');
  });

  test('607: hoja de resumen de consumo e inconsistencias', () {
    final data = {
      'formato_version': 2,
      'rnc_negocio': '131000001',
      'period': '202608',
      'records_count': 2,
      'rows': [
        {
          'rnc_cliente': '131000000',
          'ncf': 'B0100000010',
          'fecha_comprobante': '20260810',
          'monto_facturado': 500,
          'itbis_facturado': 90,
          'monto_total': 590,
          'propina_legal': 0,
          'pagos': {'cash': 590},
        },
        {
          'rnc_cliente': null,
          'ncf': 'B0200000001',
          'fecha_comprobante': '20260831',
          'monto_facturado': 100,
          'itbis_facturado': 18,
          'monto_total': 118,
          'propina_legal': 0,
          'pagos': {'transfer': 118},
        },
      ],
      'inconsistencies': [
        {
          'sale_id': 'x',
          'sale_date': '2026-08-11',
          'sale_number': 'V-0042',
          'client_name': null,
          'ncf': null,
          'reason': 'NCF faltante',
        },
      ],
      'inconsistencies_count': 1,
    };

    final excel = Excel.decodeBytes(buildDgii607Xlsx(data));

    expect(
      excel.tables.keys,
      containsAll(['607', 'Resumen consumo', 'Inconsistencias']),
    );

    final ventas = filas(excel, '607');
    // La factura de consumo de RD$118 no va en el detalle.
    expect(ventas.length - dgiiXlsxFilaTitulos - 1, 1);
    final venta = ventas[dgiiXlsxFilaTitulos + 1];
    expect(texto(venta[4]), '01');
    expect(numero(venta[16]), 590);

    final resumen = filas(excel, 'Resumen consumo');
    expect(numero(resumen[3][1]), 1); // cantidad NCFs de consumo
    expect(numero(resumen[4][1]), 100); // monto facturado

    final inc = filas(excel, 'Inconsistencias');
    expect(inc, hasLength(2));
    expect(texto(inc[1][1]), 'V-0042');
    expect(texto(inc[1][4]), 'NCF faltante');
  });
}
