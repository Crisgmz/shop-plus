// Excel del 606 / 607 en el formato de la DGII.
//
// Las filas salen de `dgii_formato.dart`, las mismas del TXT: 23 columnas en
// el orden de la herramienta de envío, montos como números y RNC / NCF /
// fechas AAAAMMDD como texto (no pierden ceros a la izquierda). Se puede pegar
// el bloque de datos directo en la herramienta de la DGII.
//
// Hojas:
//   - "606" / "607": encabezado (RNC, período, cantidad) + detalle.
//   - "Resumen consumo" (solo 607): lo que se llena en la Oficina Virtual.
//   - "Inconsistencias": lo que quedó fuera del archivo y por qué. Solo si hay.

import 'dart:typed_data';

import 'package:excel/excel.dart';

import '../../../shared/formatters/formatters.dart';
import '../domain/dgii_formato.dart';

/// Fila de la hoja principal donde van los títulos de las 23 columnas; el
/// detalle empieza en la siguiente.
const dgiiXlsxFilaTitulos = 5;

/// Columna del Excel: encabezado + clave en el JSON del RPC.
class _Col {
  const _Col(this.header, this.key, {this.date = false});

  final String header;
  final String key;

  /// Fecha ISO / timestamptz → formato de fecha configurado.
  final bool date;
}

const _inconsistencias606 = [
  _Col('Fecha', 'purchase_date', date: true),
  _Col('Proveedor', 'supplier_name'),
  _Col('Factura / NCF', 'invoice_number'),
  _Col('Motivo', 'reason'),
];

const _inconsistencias607 = [
  _Col('Fecha', 'sale_date', date: true),
  _Col('Venta', 'sale_number'),
  _Col('Cliente', 'client_name'),
  _Col('NCF', 'ncf'),
  _Col('Motivo', 'reason'),
];

Uint8List buildDgii606Xlsx(Map<String, dynamic> data) =>
    _build(dgiiFormato606(data), data, _inconsistencias606);

Uint8List buildDgii607Xlsx(Map<String, dynamic> data) =>
    _build(dgiiFormato607(data), data, _inconsistencias607);

Uint8List _build(
  DgiiFormato formato,
  Map<String, dynamic> data,
  List<_Col> inconsistencyCols,
) {
  final excel = Excel.createExcel();

  _writeDetalle(excel[formato.tipo], formato);

  final resumen = formato.resumenConsumo;
  if (resumen != null) {
    _writeResumenConsumo(excel['Resumen consumo'], formato.periodo, resumen);
  }

  final inconsistencies = (data['inconsistencies'] as List?) ?? const [];
  if (inconsistencies.isNotEmpty) {
    _writeInconsistencias(
      excel['Inconsistencias'],
      inconsistencyCols,
      inconsistencies,
    );
  }

  excel.delete('Sheet1');
  excel.setDefaultSheet(formato.tipo);
  final bytes = excel.save();
  if (bytes == null) {
    throw Exception('No se pudo generar el Excel ${formato.tipo}.');
  }
  return Uint8List.fromList(bytes);
}

void _writeDetalle(Sheet sheet, DgiiFormato formato) {
  _text(sheet, 0, 0, 'RNC o Cédula', bold: true);
  _text(sheet, 0, 1, formato.rnc);
  _text(sheet, 1, 0, 'Periodo', bold: true);
  _text(sheet, 1, 1, formato.periodo);
  _text(sheet, 2, 0, 'Cantidad Registros', bold: true);
  _cell(sheet, 2, 1).value = IntCellValue(formato.filas.length);
  if (!formato.desglosado) {
    _text(
      sheet,
      3,
      0,
      'Forma de pago sin desglosar: falta ejecutar la migración 93 en la base '
      'de datos.',
      italic: true,
    );
  }

  for (var c = 0; c < formato.columnas.length; c++) {
    _cell(sheet, dgiiXlsxFilaTitulos - 1, c).value = IntCellValue(c + 1);
    _text(sheet, dgiiXlsxFilaTitulos, c, formato.columnas[c].titulo,
        bold: true);
  }

  for (var r = 0; r < formato.filas.length; r++) {
    final fila = formato.filas[r];
    for (var c = 0; c < fila.length; c++) {
      final valor = fila[c];
      final row = dgiiXlsxFilaTitulos + 1 + r;
      // Las casillas que no aplican quedan vacías, igual que en el TXT.
      if (valor is double) {
        _cell(sheet, row, c).value = DoubleCellValue(valor);
      } else if (valor is String && valor.isNotEmpty) {
        _text(sheet, row, c, valor);
      }
    }
  }
}

void _writeResumenConsumo(
  Sheet sheet,
  String periodo,
  DgiiResumenConsumo resumen,
) {
  _text(sheet, 0, 0, 'Resumen General de Facturas de Consumo (F.C.)',
      bold: true);
  _text(sheet, 1, 0, 'Periodo');
  _text(sheet, 1, 1, periodo);

  var row = 3;
  void monto(String label, double valor, {bool bold = false}) {
    _text(sheet, row, 0, label, bold: bold);
    _cell(sheet, row, 1).value = DoubleCellValue(valor);
    row++;
  }

  _text(sheet, row, 0, 'Cantidad NCFs Emitidos de F.C.');
  _cell(sheet, row, 1).value = IntCellValue(resumen.cantidad);
  row++;
  monto('Total Monto Facturado', resumen.montoFacturado);
  monto('Total ITBIS Facturado', resumen.itbis);
  monto('Impuesto Selectivo al Consumo', 0);
  monto('Total Otros Impuestos/Tasas', 0);
  monto('Total Monto Propina Legal', resumen.propina);

  row++;
  _text(sheet, row, 0, 'Tipo de venta', bold: true);
  _text(sheet, row, 1, 'Monto', bold: true);
  row++;
  for (var i = 0; i < dgiiFormasVenta.length; i++) {
    monto(dgiiFormasVenta[i], resumen.formasVenta[i]);
  }
  monto('Total', resumen.total, bold: true);

  row++;
  _text(
    sheet,
    row,
    0,
    'Se llena en la Oficina Virtual al enviar el 607. Incluye todas las '
    'facturas de consumo del mes; las de RD\$250,000 o más van además en el '
    'detalle.',
    italic: true,
  );
}

void _writeInconsistencias(Sheet sheet, List<_Col> cols, List rows) {
  for (var c = 0; c < cols.length; c++) {
    _text(sheet, 0, c, cols[c].header, bold: true);
  }

  var r = 1;
  for (final raw in rows) {
    if (raw is! Map) continue;
    for (var c = 0; c < cols.length; c++) {
      final col = cols[c];
      final value = raw[col.key];
      _text(
        sheet,
        r,
        c,
        value == null
            ? ''
            : col.date
                ? formatDate(value)
                : value.toString(),
      );
    }
    r++;
  }
}

Data _cell(Sheet sheet, int row, int col) =>
    sheet.cell(CellIndex.indexByColumnRow(columnIndex: col, rowIndex: row));

void _text(
  Sheet sheet,
  int row,
  int col,
  String value, {
  bool bold = false,
  bool italic = false,
}) {
  final cell = _cell(sheet, row, col);
  cell.value = TextCellValue(value);
  if (bold || italic) {
    cell.cellStyle = CellStyle(bold: bold, italic: italic);
  }
}
