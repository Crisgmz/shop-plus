import '../../../shared/formatters/formatters.dart';
import '../data/reports_repository.dart' show SaleDetailRow;

/// CSV del estado de diario: una fila por venta, un corte por día y el total
/// general al final. Con BOM lo abre Excel sin romper los acentos.
String buildEstadoDiarioCsv(
  List<DateTime> dias,
  Map<DateTime, List<SaleDetailRow>> porDia,
) {
  String esc(String v) =>
      v.contains(RegExp(r'[",;\n]')) ? '"${v.replaceAll('"', '""')}"' : v;
  String num2(double v) => v.toStringAsFixed(2);

  final buf = StringBuffer()
    ..writeln('Fecha,Venta,NCF,Cliente,Tipo comprobante,Subtotal,ITBIS,'
        'Total,Estado');

  var gSub = 0.0, gTax = 0.0, gTot = 0.0, gCount = 0;

  for (final dia in dias) {
    final ventas = porDia[dia]!;
    var sub = 0.0, tax = 0.0, tot = 0.0;
    for (final r in ventas) {
      sub += r.subtotal;
      tax += r.taxAmount;
      tot += r.totalAmount;
      buf.writeln([
        esc(formatDate(r.saleDate)),
        esc(r.saleNumber),
        esc((r.ncf ?? '').trim()),
        esc(r.clientName ?? 'Consumidor Final'),
        esc(r.receiptType),
        num2(r.subtotal),
        num2(r.taxAmount),
        num2(r.totalAmount),
        esc(r.status == 'credit' ? 'A credito' : 'Pagada'),
      ].join(','));
    }
    // Corte del día.
    buf.writeln([
      esc('TOTAL ${formatDate(dia)}'),
      '',
      '',
      '',
      '${ventas.length} venta(s)',
      num2(sub),
      num2(tax),
      num2(tot),
      '',
    ].join(','));

    gSub += sub;
    gTax += tax;
    gTot += tot;
    gCount += ventas.length;
  }

  buf.writeln([
    'TOTAL GENERAL',
    '',
    '',
    '',
    '$gCount venta(s)',
    num2(gSub),
    num2(gTax),
    num2(gTot),
    '',
  ].join(','));

  return buf.toString();
}
