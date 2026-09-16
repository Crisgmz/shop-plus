import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_app/features/sales/data/sales_repository.dart';

SalesProduct _p({
  bool isService = false,
  bool trackInventory = true,
  bool allowNegativeStock = false,
  double stock = 0,
}) =>
    SalesProduct(
      id: 'p1',
      name: 'X',
      price: 100,
      cost: 50,
      taxRate: 18,
      stock: stock,
      isActive: true,
      isService: isService,
      trackInventory: trackInventory,
      allowNegativeStock: allowNegativeStock,
    );

void main() {
  group('un servicio no tiene existencia', () {
    test('un servicio nunca tiene inventario', () {
      expect(_p(isService: true).hasInventory, isFalse);
    });

    test('un producto sin control de inventario tampoco', () {
      expect(_p(trackInventory: false).hasInventory, isFalse);
    });

    test('un producto normal sí', () {
      expect(_p(stock: 3).hasInventory, isTrue);
    });

    test('admitir stock negativo NO le quita la existencia', () {
      // Esta es la diferencia con tracksStock, que sí lo excluye porque
      // decide si se bloquea la venta, no si hay existencia que mostrar.
      final p = _p(allowNegativeStock: true, stock: 3);
      expect(p.hasInventory, isTrue);
      expect(p.tracksStock, isFalse);
    });

    test('un servicio con stock 0 no debe contar como bajo stock', () {
      // Era el bug: el POS marcaba "Bajo stock" con `stock <= 5` a secas, y
      // todo servicio tiene stock 0.
      final servicio = _p(isService: true);
      expect(servicio.stock <= 5, isTrue, reason: 'el umbral viejo lo marcaba');
      expect(servicio.hasInventory && servicio.stock <= 5, isFalse);
    });
  });
}
