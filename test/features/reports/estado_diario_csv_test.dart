import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_app/features/reports/data/reports_repository.dart'
    show SaleDetailRow;
import 'package:flutter_app/features/reports/export/estado_diario_csv.dart';

void main() {
  SaleDetailRow venta({
    required String numero,
    required DateTime fecha,
    String? ncf,
    String? cliente,
    double subtotal = 100,
    double itbis = 18,
    double total = 118,
    String estado = 'completed',
    String tipo = 'consumer_final',
  }) {
    return SaleDetailRow(
      saleId: numero,
      saleNumber: numero,
      saleDate: fecha,
      receiptType: tipo,
      status: estado,
      subtotal: subtotal,
      taxAmount: itbis,
      totalAmount: total,
      discountAmount: 0,
      paidAmount: total,
      balanceDue: 0,
      profit: 0,
      ncf: ncf,
      clientName: cliente,
    );
  }

  Map<DateTime, List<SaleDetailRow>> agrupar(List<SaleDetailRow> ventas) {
    final m = <DateTime, List<SaleDetailRow>>{};
    for (final v in ventas) {
      final d = DateTime(v.saleDate.year, v.saleDate.month, v.saleDate.day);
      m.putIfAbsent(d, () => []).add(v);
    }
    return m;
  }

  group('estado de diario · CSV', () {
    final d1 = DateTime(2026, 9, 1, 10);
    final d2 = DateTime(2026, 9, 2, 15);

    test('lleva encabezado y una fila por venta', () {
      final ventas = [
        venta(numero: 'FA-001', fecha: d1, ncf: 'B0200000001'),
        venta(numero: 'FA-002', fecha: d1, ncf: 'B0200000002'),
      ];
      final csv = buildEstadoDiarioCsv([DateTime(2026, 9, 1)], agrupar(ventas));
      final lineas = csv.trim().split('\n');

      expect(lineas.first, startsWith('Fecha,Venta,NCF,Cliente'));
      expect(lineas.any((l) => l.contains('FA-001')), true);
      expect(lineas.any((l) => l.contains('B0200000002')), true);
    });

    test('cierra cada día con su corte', () {
      final ventas = [
        venta(numero: 'FA-001', fecha: d1, subtotal: 100, itbis: 18, total: 118),
        venta(numero: 'FA-002', fecha: d1, subtotal: 200, itbis: 36, total: 236),
      ];
      final csv = buildEstadoDiarioCsv([DateTime(2026, 9, 1)], agrupar(ventas));
      final corte = csv.split('\n').firstWhere((l) => l.startsWith('TOTAL 0'),
          orElse: () => csv.split('\n').firstWhere((l) => l.contains('TOTAL ')));

      expect(corte, contains('2 venta(s)'));
      expect(corte, contains('300.00')); // subtotal del día
      expect(corte, contains('54.00')); // ITBIS del día
      expect(corte, contains('354.00')); // total del día
    });

    test('el total general suma todos los días', () {
      final ventas = [
        venta(numero: 'FA-001', fecha: d1, subtotal: 100, itbis: 18, total: 118),
        venta(numero: 'FA-002', fecha: d2, subtotal: 50, itbis: 9, total: 59),
      ];
      final csv = buildEstadoDiarioCsv(
        [DateTime(2026, 9, 1), DateTime(2026, 9, 2)],
        agrupar(ventas),
      );
      final general =
          csv.split('\n').firstWhere((l) => l.startsWith('TOTAL GENERAL'));

      expect(general, contains('2 venta(s)'));
      expect(general, contains('150.00'));
      expect(general, contains('27.00'));
      expect(general, contains('177.00'));
    });

    test('sin cliente escribe Consumidor Final', () {
      final csv = buildEstadoDiarioCsv(
        [DateTime(2026, 9, 1)],
        agrupar([venta(numero: 'FA-001', fecha: d1)]),
      );
      expect(csv, contains('Consumidor Final'));
    });

    test('una venta a crédito se marca como tal', () {
      final csv = buildEstadoDiarioCsv(
        [DateTime(2026, 9, 1)],
        agrupar([venta(numero: 'FA-001', fecha: d1, estado: 'credit')]),
      );
      expect(csv, contains('A credito'));
    });

    test('un cliente con coma no rompe las columnas', () {
      final csv = buildEstadoDiarioCsv(
        [DateTime(2026, 9, 1)],
        agrupar([
          venta(numero: 'FA-001', fecha: d1, cliente: 'Pérez, Juan S.R.L.'),
        ]),
      );
      expect(csv, contains('"Pérez, Juan S.R.L."'));
    });

    test('sin ventas devuelve solo encabezado y total en cero', () {
      final csv = buildEstadoDiarioCsv([], {});
      final lineas = csv.trim().split('\n');
      expect(lineas.length, 2);
      expect(lineas.last, contains('TOTAL GENERAL'));
      expect(lineas.last, contains('0 venta(s)'));
    });
  });
}
