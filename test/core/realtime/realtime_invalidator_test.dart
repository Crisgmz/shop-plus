import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_app/core/realtime/realtime_invalidator.dart';

const _migration =
    'supabase/sql-next/20260916_93_realtime_todas_las_pantallas.sql';

/// Tablas que la migración 93 publica, leídas del propio archivo SQL.
Set<String> _tablesInMigration() {
  final sql = File(_migration).readAsStringSync();
  final array = RegExp(
    r'foreach v_tabla in array array\[(.*?)\]',
    dotAll: true,
  ).firstMatch(sql);
  expect(array, isNotNull, reason: 'no encontré la lista de tablas en la 93');
  return RegExp(r"'([a-z_]+)'")
      .allMatches(array!.group(1)!)
      .map((m) => m.group(1)!)
      .toSet();
}

void main() {
  group('lo que escucha la app coincide con lo que publica la base', () {
    test('mismas tablas en el invalidador y en la migración 93', () {
      // Si difieren: una tabla publicada que nadie escucha no actualiza
      // ninguna pantalla, y una escuchada que no está publicada nunca emite.
      expect(RealtimeInvalidator.subscribedTables, _tablesInMigration());
    });

    test('cubre las pantallas que antes no se enteraban de nada', () {
      expect(
        RealtimeInvalidator.subscribedTables,
        containsAll(<String>[
          'quotations', 'purchases', 'suppliers', 'expenses',
          'supplier_payments', 'petty_cash_movements', 'ncf_sequences',
        ]),
      );
    });
  });

  group('solo se invalidan providers de datos', () {
    test('ningún provider de estado (reiniciaría los filtros del usuario)', () {
      // Invalidar p. ej. el rango de fechas de un reporte se lo reiniciaría
      // al usuario cada vez que alguien vende.
      final noDeDatos = RealtimeInvalidator.allProviders
          .map((p) => p.runtimeType.toString())
          .where((t) =>
              !t.contains('FutureProvider') && !t.contains('StreamProvider'))
          .toSet();
      expect(noDeDatos, isEmpty);
    });
  });

  group('agrupar eventos de una ráfaga', () {
    final a = Provider((ref) => 1);
    final b = Provider((ref) => 2);
    final c = Provider((ref) => 3);

    test('muchos eventos seguidos → una sola recarga con todo junto', () async {
      final flushes = <Set<ProviderOrFamily>>[];
      final batcher = InvalidationBatcher(
        window: const Duration(milliseconds: 40),
        onFlush: flushes.add,
      );

      // Una venta: la venta, el pago y varios UPDATE de stock.
      batcher.add([a, b]);
      batcher.add([b, c]);
      batcher.add([a]);
      expect(flushes, isEmpty, reason: 'todavía dentro de la ventana');

      await Future<void>.delayed(const Duration(milliseconds: 80));
      expect(flushes, hasLength(1));
      expect(flushes.single, {a, b, c});
      expect(batcher.hasPending, isFalse);
    });

    test('una ráfaga continua no posterga la recarga indefinidamente', () async {
      final flushes = <Set<ProviderOrFamily>>[];
      final batcher = InvalidationBatcher(
        window: const Duration(milliseconds: 60),
        onFlush: flushes.add,
      );

      // Eventos cada 20 ms durante 150 ms: si la ventana se alargara con cada
      // uno, nunca se aplicaría nada mientras dure la ráfaga.
      for (var i = 0; i < 8; i++) {
        batcher.add([a]);
        await Future<void>.delayed(const Duration(milliseconds: 20));
      }
      expect(flushes, isNotEmpty);
      batcher.cancel();
    });

    test('cancelar descarta lo pendiente (cambio de sucursal, logout)', () async {
      final flushes = <Set<ProviderOrFamily>>[];
      final batcher = InvalidationBatcher(
        window: const Duration(milliseconds: 30),
        onFlush: flushes.add,
      );

      batcher.add([a, b]);
      batcher.cancel();
      await Future<void>.delayed(const Duration(milliseconds: 60));
      expect(flushes, isEmpty);
      expect(batcher.hasPending, isFalse);
    });

    test('flush aplica ya, sin esperar la ventana', () {
      final flushes = <Set<ProviderOrFamily>>[];
      final batcher = InvalidationBatcher(
        window: const Duration(seconds: 10),
        onFlush: flushes.add,
      );

      batcher.add([c]);
      batcher.flush();
      expect(flushes.single, {c});
    });

    test('sin providers no agenda nada', () async {
      final flushes = <Set<ProviderOrFamily>>[];
      final batcher = InvalidationBatcher(
        window: const Duration(milliseconds: 20),
        onFlush: flushes.add,
      );

      batcher.add(const []);
      await Future<void>.delayed(const Duration(milliseconds: 40));
      expect(flushes, isEmpty);
    });
  });
}
