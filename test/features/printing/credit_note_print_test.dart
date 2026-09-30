import 'package:flutter_app/features/printing/data/printing_models.dart';
import 'package:flutter_app/features/printing/data/sale_print_document_adapter.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('una devolución se imprime como NOTA DE CRÉDITO con su NCF B04', () {
    final document = const SalePrintDocumentAdapter().toDocumentData(
      SalePrintSource(
        saleId: 'r1',
        branchId: 'b1',
        saleNumber: 'NC-00001',
        status: 'completed',
        saleDate: DateTime(2026, 9, 30),
        receiptType: 'credit_note',
        branchName: 'Soplasora',
        ncf: 'B0400000001',
        notes: 'Modifica el NCF B0100000200 (venta FA-000008)',
        items: const [
          SalePrintItemSource(
            description: 'VASOS PET 16 OZ',
            quantity: 1,
            unitPrice: 6182.20,
            presentationLabel: 'Caja',
            lineSubtotal: 6182.20,
            lineTax: 1112.80,
            lineTotal: 7295.00,
          ),
        ],
        payments: const [
          SalePrintPaymentSource(method: 'transfer', amount: 7295.00),
        ],
        subtotal: 6182.20,
        taxAmount: 1112.80,
        totalAmount: 7295.00,
        paidAmount: 7295.00,
      ),
    );

    expect(document.documentType, PrintDocumentType.creditNote);
    expect(document.ncf, 'B0400000001');
    expect(document.receiptTypeLabel, 'Nota de crédito');
    expect(document.paymentTermsLabel, 'DEVOLUCIÓN');
    expect(document.notes, contains('B0100000200'));
    expect(document.totals.total, 7295.00);
  });

  test('la nota de crédito de una venta B02 no desglosa el ITBIS', () {
    final document = const SalePrintDocumentAdapter().toDocumentData(
      SalePrintSource(
        saleId: 'r2',
        branchId: 'b1',
        saleNumber: 'NC-00002',
        status: 'completed',
        saleDate: DateTime(2026, 9, 30),
        receiptType: 'credit_note',
        hideTaxBreakdown: true,
        branchName: 'Soplasora',
        ncf: 'B0400000002',
        items: const [
          SalePrintItemSource(
            description: 'Producto',
            quantity: 2,
            unitPrice: 100,
            lineSubtotal: 200,
            lineTax: 36,
            lineTotal: 236,
          ),
        ],
        subtotal: 200,
        taxAmount: 36,
        totalAmount: 236,
        paidAmount: 236,
      ),
    );

    expect(document.showTax, isFalse);
    expect(document.items.single.unitPrice, 118);
    expect(document.items.single.lineTax, 0);
    expect(document.totals.subtotal, 236);
    expect(document.totals.tax, 0);
    expect(document.totals.total, 236);
  });
}
