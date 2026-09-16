import 'dart:typed_data';

import 'package:excel/excel.dart';

import '../../../shared/formatters/formatters.dart';
import 'taxes_repository.dart';

/// Excel de los botones "Exportar 606 / 607" de /impuestos: las ventas y
/// compras del rango elegido, con los montos como números.
///
/// El 606/607 en formato DGII (columnas del TXT, por mes fiscal) sale de
/// /reportes → Fiscal DGII.
class TaxesExcelService {
  Uint8List build607(
    List<TaxSaleRecord> sales, {
    required String Function(String receiptType) receiptLabel,
  }) {
    return _build(
      sheetName: '607',
      headers: const [
        'Fecha',
        'Cliente',
        'Tipo comprobante',
        'NCF',
        'Total',
        'ITBIS',
        'Estado DGII',
      ],
      rows: [
        for (final s in sales)
          [
            TextCellValue(formatDate(s.saleDate)),
            TextCellValue(s.clientName),
            TextCellValue(receiptLabel(s.receiptType)),
            TextCellValue(s.ncf ?? ''),
            DoubleCellValue(s.totalAmount),
            DoubleCellValue(s.taxAmount),
            TextCellValue(s.dgiiStatus),
          ],
      ],
    );
  }

  Uint8List build606(List<TaxPurchaseRecord> purchases) {
    return _build(
      sheetName: '606',
      headers: const [
        'Fecha',
        'Suplidor',
        'Número factura',
        'Total',
        'ITBIS',
        'Estado',
      ],
      rows: [
        for (final p in purchases)
          [
            TextCellValue(formatDate(p.purchaseDate)),
            TextCellValue(p.supplierName),
            TextCellValue(p.invoiceNumber ?? ''),
            DoubleCellValue(p.totalAmount),
            DoubleCellValue(p.taxAmount),
            TextCellValue(p.status),
          ],
      ],
    );
  }

  Uint8List _build({
    required String sheetName,
    required List<String> headers,
    required List<List<CellValue>> rows,
  }) {
    final excel = Excel.createExcel();
    final sheet = excel[sheetName];
    for (var c = 0; c < headers.length; c++) {
      final cell = sheet.cell(
        CellIndex.indexByColumnRow(columnIndex: c, rowIndex: 0),
      );
      cell.value = TextCellValue(headers[c]);
      cell.cellStyle = CellStyle(bold: true);
    }
    for (var r = 0; r < rows.length; r++) {
      for (var c = 0; c < rows[r].length; c++) {
        sheet
            .cell(CellIndex.indexByColumnRow(columnIndex: c, rowIndex: r + 1))
            .value = rows[r][c];
      }
    }
    excel.delete('Sheet1');
    excel.setDefaultSheet(sheetName);
    final bytes = excel.save();
    if (bytes == null) {
      throw Exception('No se pudo generar el Excel $sheetName.');
    }
    return Uint8List.fromList(bytes);
  }
}
