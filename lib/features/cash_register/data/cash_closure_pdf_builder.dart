import 'dart:typed_data';

import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../../../shared/formatters/formatters.dart';
import 'cash_register_repository.dart';

/// Genera el PDF del cierre de caja en formato térmico (rollo continuo).
/// Soporta dos anchos: 58mm y 80mm.
class CashClosurePdfBuilder {
  const CashClosurePdfBuilder();

  Future<Uint8List> build({
    required CashSessionEntity session,
    required CashSessionMetrics metrics,
    required List<CashMovementEntity> movements,
    required double widthMm,
    String? branchName,
    String? branchAddress,
    String? branchPhone,
    String? branchTaxId,
    String? cashierName,
  }) async {
    final doc = pw.Document(
      title: 'Cierre de caja ${session.id.substring(0, 8)}',
      author: branchName ?? 'Shop+',
    );

    final format = PdfPageFormat(
      widthMm * PdfPageFormat.mm,
      double.infinity,
      marginAll: 6 * PdfPageFormat.mm,
    );

    final isNarrow = widthMm <= 60;

    doc.addPage(
      pw.Page(
        pageFormat: format,
        build: (context) => _content(
          session: session,
          metrics: metrics,
          movements: movements,
          isNarrow: isNarrow,
          branchName: branchName,
          branchAddress: branchAddress,
          branchPhone: branchPhone,
          branchTaxId: branchTaxId,
          cashierName: cashierName,
        ),
      ),
    );

    return doc.save();
  }

  pw.Widget _content({
    required CashSessionEntity session,
    required CashSessionMetrics metrics,
    required List<CashMovementEntity> movements,
    required bool isNarrow,
    String? branchName,
    String? branchAddress,
    String? branchPhone,
    String? branchTaxId,
    String? cashierName,
  }) {
    final baseFont = isNarrow ? 8.0 : 9.0;
    final titleFont = isNarrow ? 10.0 : 12.0;
    final emphasizedFont = isNarrow ? 9.5 : 11.0;

    final expectedCash =
        metrics.expectedCashFromOpening(session.openingAmount);
    final diff = session.differenceAmount;

    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.stretch,
      children: [
        if (branchName != null && branchName.trim().isNotEmpty)
          pw.Center(
            child: pw.Text(
              branchName.trim(),
              style: pw.TextStyle(
                fontSize: titleFont,
                fontWeight: pw.FontWeight.bold,
              ),
            ),
          ),
        if (branchAddress != null && branchAddress.trim().isNotEmpty)
          pw.Center(
            child: pw.Text(
              branchAddress.trim(),
              style: pw.TextStyle(fontSize: baseFont),
              textAlign: pw.TextAlign.center,
            ),
          ),
        if (branchPhone != null && branchPhone.trim().isNotEmpty)
          pw.Center(
            child: pw.Text(
              'Tel: ${branchPhone.trim()}',
              style: pw.TextStyle(fontSize: baseFont),
            ),
          ),
        if (branchTaxId != null && branchTaxId.trim().isNotEmpty)
          pw.Center(
            child: pw.Text(
              'RNC: ${branchTaxId.trim()}',
              style: pw.TextStyle(fontSize: baseFont),
            ),
          ),
        pw.SizedBox(height: 4),
        _divider(),
        pw.Center(
          child: pw.Text(
            'CIERRE DE CAJA',
            style: pw.TextStyle(
              fontSize: titleFont,
              fontWeight: pw.FontWeight.bold,
            ),
          ),
        ),
        _divider(),
        _kv('Sesion:', session.id.substring(0, 8).toUpperCase(),
            baseFont: baseFont),
        _kv('Estado:', session.isOpen ? 'Abierta' : 'Cerrada',
            baseFont: baseFont),
        if (cashierName != null && cashierName.trim().isNotEmpty)
          _kv('Cajero:', cashierName.trim(), baseFont: baseFont),
        _kv('Apertura:', formatDateTime(session.openedAt), baseFont: baseFont),
        if (session.closedAt != null)
          _kv('Cierre:', formatDateTime(session.closedAt!),
              baseFont: baseFont),
        _divider(),
        _kv('Monto apertura', money(session.openingAmount),
            baseFont: baseFont),
        _kv('Total cobros', money(metrics.totalPayments), baseFont: baseFont),
        _kv('  En efectivo', money(metrics.cashPayments), baseFont: baseFont),
        _kv('Total gastos', money(metrics.totalExpenses), baseFont: baseFont),
        _kv('  En efectivo', money(metrics.cashExpenses), baseFont: baseFont),
        _divider(),
        _kv('Esperado en caja', money(expectedCash),
            baseFont: emphasizedFont, bold: true),
        if (session.closingAmount != null)
          _kv('Conteo cierre', money(session.closingAmount!),
              baseFont: emphasizedFont, bold: true),
        if (diff != null)
          _kv(
            'Diferencia',
            money(diff),
            baseFont: emphasizedFont,
            bold: true,
            rightColor: diff < 0 ? PdfColors.red700 : PdfColors.green700,
          ),
        if (movements.isNotEmpty) ...[
          pw.SizedBox(height: 4),
          _divider(),
          pw.Text(
            'MOVIMIENTOS',
            style: pw.TextStyle(
              fontSize: baseFont,
              fontWeight: pw.FontWeight.bold,
            ),
          ),
          pw.SizedBox(height: 2),
          for (final mv in movements)
            pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.stretch,
              children: [
                _kv(
                  mv.typeLabel,
                  money(mv.signedAmount),
                  baseFont: baseFont,
                  rightColor:
                      mv.signedAmount < 0 ? PdfColors.red700 : null,
                ),
                if (mv.reason != null && mv.reason!.trim().isNotEmpty)
                  pw.Text(
                    '  ${mv.reason!.trim()}',
                    style: pw.TextStyle(
                      fontSize: baseFont - 1,
                      color: PdfColors.grey700,
                    ),
                  ),
              ],
            ),
        ],
        if (session.notes != null && session.notes!.trim().isNotEmpty) ...[
          pw.SizedBox(height: 4),
          _divider(),
          pw.Text(
            'Notas',
            style: pw.TextStyle(
              fontSize: baseFont,
              fontWeight: pw.FontWeight.bold,
            ),
          ),
          pw.Text(
            session.notes!.trim(),
            style: pw.TextStyle(fontSize: baseFont),
          ),
        ],
        pw.SizedBox(height: 10),
        _divider(),
        pw.SizedBox(height: 16),
        pw.Center(
          child: pw.Text(
            '_____________________',
            style: pw.TextStyle(fontSize: baseFont),
          ),
        ),
        pw.Center(
          child: pw.Text(
            'Firma cajero',
            style: pw.TextStyle(fontSize: baseFont),
          ),
        ),
        pw.SizedBox(height: 6),
        pw.Center(
          child: pw.Text(
            'Generado: ${formatDateTime(DateTime.now())}',
            style: pw.TextStyle(
              fontSize: baseFont - 1,
              color: PdfColors.grey600,
            ),
          ),
        ),
      ],
    );
  }

  pw.Widget _kv(
    String left,
    String right, {
    required double baseFont,
    bool bold = false,
    PdfColor? rightColor,
  }) {
    return pw.Padding(
      padding: const pw.EdgeInsets.symmetric(vertical: 0.5),
      child: pw.Row(
        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Expanded(
            child: pw.Text(
              left,
              style: pw.TextStyle(
                fontSize: baseFont,
                fontWeight: bold ? pw.FontWeight.bold : pw.FontWeight.normal,
              ),
            ),
          ),
          pw.Text(
            right,
            style: pw.TextStyle(
              fontSize: baseFont,
              fontWeight: bold ? pw.FontWeight.bold : pw.FontWeight.normal,
              color: rightColor,
            ),
          ),
        ],
      ),
    );
  }

  pw.Widget _divider() {
    return pw.Padding(
      padding: const pw.EdgeInsets.symmetric(vertical: 2),
      child: pw.Container(
        height: 0.5,
        color: PdfColors.grey400,
      ),
    );
  }
}
