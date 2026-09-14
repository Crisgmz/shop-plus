import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_app/features/quotations/data/quotations_models.dart';
import 'package:flutter_app/features/quotations/data/quotations_repository.dart'
    show buildConvertQuotationParams;
import 'package:flutter_app/features/quotations/presentation/convert_payment_dialog.dart';
import 'package:flutter_app/shared/formatters/formatters.dart';

void main() {
  group('parámetros de la conversión', () {
    test('al contado NO manda las claves de crédito', () {
      // Así sigue funcionando contra la firma anterior si el app se despliega
      // antes de la migración 88.
      final params = buildConvertQuotationParams(
        quoteId: 'q1',
        paymentMethod: 'card',
        cashSessionId: 'caja-1',
      );

      expect(params, {
        'target_quotation_id': 'q1',
        'requested_payment_method': 'card',
        'requested_cash_session_id': 'caja-1',
      });
      expect(params.containsKey('requested_as_credit'), false);
      expect(params.containsKey('requested_credit_due_days'), false);
    });

    test('a crédito manda la bandera y los días', () {
      final params = buildConvertQuotationParams(
        quoteId: 'q1',
        paymentMethod: 'cash',
        asCredit: true,
        creditDueDays: 45,
      );

      expect(params['requested_as_credit'], true);
      expect(params['requested_credit_due_days'], 45);
    });

    test('a crédito sin días deja que el servidor use el default', () {
      final params = buildConvertQuotationParams(
        quoteId: 'q1',
        paymentMethod: 'cash',
        asCredit: true,
      );

      expect(params['requested_as_credit'], true);
      expect(params.containsKey('requested_credit_due_days'), false);
    });

    test('una caja vacía no se manda', () {
      final params = buildConvertQuotationParams(
        quoteId: 'q1',
        paymentMethod: 'cash',
        cashSessionId: '',
      );
      expect(params.containsKey('requested_cash_session_id'), false);
    });
  });

  group('días de plazo', () {
    test('respeta lo escrito dentro del rango', () {
      expect(clampCreditDays('45', 30), 45);
    });

    test('vacío o inválido usa el default de la empresa', () {
      expect(clampCreditDays('', 30), 30);
      expect(clampCreditDays('abc', 15), 15);
    });

    test('se acota a 1..365 igual que el servidor', () {
      expect(clampCreditDays('0', 30), 1);
      expect(clampCreditDays('999', 30), 365);
    });
  });

  group('vencimiento', () {
    test('cruza de mes', () {
      expect(creditDueDate(DateTime.utc(2026, 1, 25), 10), DateTime(2026, 2, 4));
    });

    test('respeta años bisiestos', () {
      expect(creditDueDate(DateTime.utc(2028, 2, 25), 5), DateTime(2028, 3, 1));
    });
  });

  group('mensaje de confirmación', () {
    test('al contado', () {
      expect(
        quoteConversionMessage('FA-000120', const QuoteConversionChoice.cash('cash')),
        'Cotización convertida a venta FA-000120.',
      );
    });

    test('a crédito indica la fecha de vencimiento', () {
      final now = DateTime.utc(2026, 9, 14);
      final msg = quoteConversionMessage(
        'FA-000121',
        const QuoteConversionChoice.credit(30),
        nowUtc: now,
      );

      expect(msg, contains('a crédito FA-000121'));
      expect(msg, contains(formatDate(DateTime(2026, 10, 14))));
    });
  });

  group('elección de cobro', () {
    test('a crédito no lleva método de pago real', () {
      const choice = QuoteConversionChoice.credit(20);
      expect(choice.asCredit, true);
      expect(choice.creditDueDays, 20);
    });

    test('la cotización sin cliente del catálogo lo expone', () {
      final quote = QuoteListItem(
        id: 'q1',
        code: 'COT-1',
        clientName: 'Juan escrito a mano',
        status: QuoteStatus.approved,
        createdAt: DateTime(2026, 9, 1),
        validUntil: DateTime(2026, 9, 30),
        total: 1000,
        itemsCount: 1,
      );
      expect(quote.clientId, isNull);
    });
  });
}
