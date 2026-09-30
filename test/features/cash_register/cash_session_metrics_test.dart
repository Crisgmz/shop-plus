import 'package:flutter_app/features/cash_register/data/cash_register_repository.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('las sangrías y los depósitos mueven el efectivo esperado', () {
    // Apertura 1,000 + ventas en efectivo 5,000; se sacan 3,000 a la caja
    // fuerte y se meten 500 de cambio.
    final metrics = CashSessionMetrics(
      totalPayments: 5000,
      cashPayments: 5000,
      totalExpenses: 0,
      cashExpenses: 0,
      cashWithdrawals: 3000,
      cashDeposits: 500,
    );
    expect(metrics.expectedCashFromOpening(1000), 3500);
  });

  test('todas las salidas y entradas del cajón', () {
    final metrics = CashSessionMetrics(
      totalPayments: 6000,
      cashPayments: 5000,
      totalExpenses: 300,
      cashExpenses: 200,
      changeGiven: 150,
      supplierCashPayments: 400,
      cashRefunds: 118,
      cashDeposits: 1000,
      cashAdjustments: 5,
      cashWithdrawals: 2000,
    );
    // 1000 + 5000 + 1000 + 5 − 200 − 150 − 400 − 118 − 2000
    expect(metrics.expectedCashFromOpening(1000), 4137);
  });
}
