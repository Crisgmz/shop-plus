import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_app/features/printing/data/pdf_receipt_builder.dart';
import 'package:flutter_app/features/printing/data/printing_models.dart';
import 'package:flutter_app/features/printing/data/printing_template_service.dart';

PrintDocumentData _sampleSale({bool hidePrices = false}) {
  return PrintDocumentData(
    documentType: PrintDocumentType.saleReceipt,
    documentNumber: 'FA-00123',
    issuedAt: DateTime(2026, 7, 10, 14, 30),
    branch: const PrintBranchIdentity(name: 'Shop+ Demo', taxId: '131000000'),
    customer: const PrintParty(name: 'MangoPOS S.R.L', document: '131999999'),
    items: const [
      PrintDocumentItem(
        description: 'Producto A',
        quantity: 2,
        unitPrice: 100,
        lineSubtotal: 200,
        lineTax: 36,
        lineTotal: 236,
      ),
      PrintDocumentItem(
        description: 'Producto B',
        quantity: 1,
        unitPrice: 50,
        lineSubtotal: 50,
        lineTax: 9,
        lineTotal: 59,
      ),
    ],
    totals: const PrintTotals(subtotal: 250, tax: 45, total: 295),
    payments: const [PrintPaymentLine(method: 'Efectivo', amount: 295)],
    receiptTypeLabel: 'Consumidor final',
    hidePrices: hidePrices,
  );
}

void main() {
  const builder = PdfReceiptBuilder();
  const templates = PrintingTemplateService();

  group('Conduce (hidePrices) PDF generation', () {
    test('A4 y térmico generan bytes tanto con precios como sin ellos',
        () async {
      for (final hide in [false, true]) {
        final doc = _sampleSale(hidePrices: hide);
        final a4 = await builder.buildBytes(doc);
        final thermal = await builder.buildThermalBytes(doc);
        expect(a4, isNotEmpty, reason: 'A4 hidePrices=$hide');
        expect(thermal, isNotEmpty, reason: 'thermal hidePrices=$hide');
      }
    });

    test('El template del conduce titula CONDUCE y no lista totales', () {
      final doc = _sampleSale(hidePrices: true);
      final a4 = templates.buildA4Template(doc);
      final thermal = templates.buildThermal80Template(doc);

      expect(a4.title, 'Conduce');
      expect(a4.totalRows, isEmpty);
      // Los ítems no muestran monto (labels vacíos) pero sí cantidad.
      expect(a4.itemRows.first.unitPriceLabel, '');
      expect(a4.itemRows.first.totalLabel, '');
      expect(a4.itemRows.first.quantityLabel, '2');

      expect(thermal.title, 'CONDUCE');
      // Ninguna fila del ticket debe contener montos en RD$.
      final hasMoney = thermal.rows.any(
        (r) => (r.right ?? '').contains(r'RD$') ||
            (r.left ?? '').contains(r'RD$'),
      );
      expect(hasMoney, isFalse);
    });

    test('El template normal sí titula e incluye totales', () {
      final doc = _sampleSale(hidePrices: false);
      final a4 = templates.buildA4Template(doc);
      expect(a4.title, isNot('Conduce'));
      expect(a4.totalRows, isNotEmpty);
      expect(a4.itemRows.first.totalLabel, isNotEmpty);
    });

    test('factura + conduce se combinan en un solo PDF (A4 y térmico)',
        () async {
      final factura = _sampleSale();
      final conduce = factura.copyWith(hidePrices: true);
      final a4 = await builder.buildDocumentsBytes([factura, conduce]);
      final thermal =
          await builder.buildThermalDocumentsBytes([factura, conduce]);
      expect(a4, isNotEmpty);
      expect(thermal, isNotEmpty);
    });
  });
}
