import 'package:flutter_app/features/quotations/data/quotations_models.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('QuoteStatusX.fromDb', () {
    test('maps supported db values', () {
      expect(QuoteStatusX.fromDb('draft'), QuoteStatus.draft);
      expect(QuoteStatusX.fromDb('sent'), QuoteStatus.sent);
      expect(QuoteStatusX.fromDb('under_review'), QuoteStatus.underReview);
      expect(QuoteStatusX.fromDb('approved'), QuoteStatus.approved);
      expect(QuoteStatusX.fromDb('rejected'), QuoteStatus.rejected);
      expect(QuoteStatusX.fromDb('expired'), QuoteStatus.expired);
      expect(QuoteStatusX.fromDb('converted'), QuoteStatus.converted);
    });

    test('falls back to draft for unknown values', () {
      expect(QuoteStatusX.fromDb('weird'), QuoteStatus.draft);
      expect(QuoteStatusX.fromDb(null), QuoteStatus.draft);
    });
  });

  group('QuotationsMath', () {
    test('calculates subtotal tax and total from quote items', () {
      final items = [
        QuoteCreateItem(
          productId: 'p1',
          productName: 'Producto A',
          quantity: 2,
          unitPrice: 100,
          taxRate: 18,
        ),
        QuoteCreateItem(
          productId: 'p2',
          productName: 'Producto B',
          quantity: 1,
          unitPrice: 50,
          taxRate: 0,
        ),
      ];

      expect(QuotationsMath.subtotal(items), 250);
      expect(QuotationsMath.tax(items), 36);
      expect(QuotationsMath.total(items), 286);
    });
  });

  group('QuoteListItem state rules', () {
    test('marks non terminal past-due quotes as expired', () {
      final quote = QuoteListItem(
        id: 'q1',
        code: 'COT-1',
        clientName: 'Cliente',
        status: QuoteStatus.approved,
        createdAt: DateTime.now().subtract(const Duration(days: 2)),
        validUntil: DateTime.now().subtract(const Duration(days: 1)),
        total: 100,
        itemsCount: 1,
      );

      expect(quote.isExpired, true);
      expect(quote.effectiveStatus, QuoteStatus.expired);
      // Vencida SÍ se puede convertir: el vencimiento es informativo y la RPC
      // `convert_quotation_to_sale` acepta `approved` y `expired`.
      expect(quote.canConvert, true);
    });

    test('quote already stored as expired can still be converted', () {
      final quote = QuoteListItem(
        id: 'q3',
        code: 'COT-3',
        clientName: 'Cliente',
        status: QuoteStatus.expired,
        createdAt: DateTime.now().subtract(const Duration(days: 30)),
        validUntil: DateTime.now().subtract(const Duration(days: 15)),
        total: 100,
        itemsCount: 1,
      );

      expect(quote.canConvert, true);
    });

    test('lost and still-valid draft quotes cannot be converted', () {
      QuoteListItem build(QuoteStatus status) => QuoteListItem(
            id: 'q4',
            code: 'COT-4',
            clientName: 'Cliente',
            status: status,
            createdAt: DateTime.now(),
            validUntil: DateTime.now().add(const Duration(days: 5)),
            total: 100,
            itemsCount: 1,
          );

      expect(build(QuoteStatus.rejected).canConvert, false);
      expect(build(QuoteStatus.draft).canConvert, false);
      expect(build(QuoteStatus.sent).canConvert, false);
      expect(build(QuoteStatus.underReview).canConvert, false);
      expect(build(QuoteStatus.approved).canConvert, true);
    });

    test('converted quote cannot be edited or deleted', () {
      final quote = QuoteListItem(
        id: 'q2',
        code: 'COT-2',
        clientName: 'Cliente',
        status: QuoteStatus.converted,
        createdAt: DateTime.now(),
        validUntil: DateTime.now().add(const Duration(days: 10)),
        total: 100,
        itemsCount: 1,
        saleId: 'sale-1',
      );

      expect(quote.canEdit, false);
      expect(quote.canDelete, false);
      expect(quote.canConvert, false);
    });
  });

  group('QuoteCreateItem serialization', () {
    test('toRpcMap preserves line math fields', () {
      final item = QuoteCreateItem(
        productId: 'p1',
        productName: 'Producto A',
        productSku: 'SKU-1',
        productDescription: 'Detalle',
        quantity: 2,
        unitPrice: 100,
        taxRate: 18,
      );

      expect(item.toRpcMap(), {
        'product_id': 'p1',
        'product_name': 'Producto A',
        'product_sku': 'SKU-1',
        'description': 'Detalle',
        'quantity': 2.0,
        'unit_price': 100.0,
        'discount_amount': 0,
        'tax_rate': 18.0,
        'line_subtotal': 200.0,
        'line_tax': 36.0,
        'line_total': 236.0,
      });
    });
  });
}
