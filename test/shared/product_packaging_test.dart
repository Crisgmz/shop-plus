import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_app/shared/packaging/product_packaging.dart';

void main() {
  group('el ejemplo del negocio · caja de 40 paquetes', () {
    // "Cada caja trae 40 paquetes de vasos". El paquete es la unidad más
    // pequeña que se vende, así que una unidad base = un paquete.
    const vasos = ProductPackaging(
      unitsPerPack: 1,
      packsPerBox: 40,
      unitLabel: 'Paquete',
      packLabel: 'Paquete',
      boxLabel: 'Caja',
    );

    test('200 cajas son 8000 paquetes', () {
      expect(vasos.unitsPerBox, 40);
      expect(vasos.toBaseUnits(200, PackagingUom.box), 8000);
    });

    test('vender 10 paquetes deja 199 cajas y 30 paquetes', () {
      const stockInicial = 8000.0; // 200 cajas
      final restante = stockInicial - vasos.toBaseUnits(10, PackagingUom.unit);

      final b = vasos.breakdown(restante);
      expect(b.boxes, 199);
      expect(b.packs, 30);
      expect(b.units, 0);
      expect(vasos.describeStock(restante), '199 Cajas · 30 Paquetes');
    });

    test('vender una caja completa deja 199 cajas justas', () {
      final restante = 8000.0 - vasos.toBaseUnits(1, PackagingUom.box);
      expect(vasos.describeStock(restante), '199 Cajas');
    });
  });

  group('tres niveles · caja → paquete → vaso', () {
    const vasos = ProductPackaging(
      unitsPerPack: 25, // 25 vasos por paquete
      packsPerBox: 40, // 40 paquetes por caja
      unitLabel: 'Vaso',
      packLabel: 'Paquete',
      boxLabel: 'Caja',
    );

    test('una caja son 1000 vasos', () {
      expect(vasos.unitsPerBox, 1000);
    });

    test('vender 10 vasos de 200 cajas baja hasta el último nivel', () {
      const stockInicial = 200000.0; // 200 cajas
      final restante = stockInicial - 10;

      final b = vasos.breakdown(restante);
      expect(b.boxes, 199);
      expect(b.packs, 39);
      expect(b.units, 15);
      expect(vasos.describeStock(restante), '199 Cajas · 39 Paquetes · 15 Vasos');
    });

    test('vender un paquete descuenta 25 vasos', () {
      expect(vasos.toBaseUnits(1, PackagingUom.pack), 25);
      expect(vasos.toBaseUnits(3, PackagingUom.box), 3000);
    });

    test('las tres presentaciones quedan disponibles', () {
      expect(vasos.sellableUoms,
          [PackagingUom.box, PackagingUom.pack, PackagingUom.unit]);
    });
  });

  group('mínimo de venta configurable', () {
    const conMinimo = ProductPackaging(
      unitsPerPack: 1,
      packsPerBox: 40,
      minUnitQty: 8,
      unitLabel: 'Paquete',
    );

    test('bloquea vender suelto por debajo del mínimo', () {
      expect(conMinimo.respectsMinimum(7, PackagingUom.unit), false);
      expect(conMinimo.respectsMinimum(8, PackagingUom.unit), true);
      expect(conMinimo.respectsMinimum(20, PackagingUom.unit), true);
    });

    test('el mínimo NO aplica a paquete ni caja completos', () {
      expect(conMinimo.respectsMinimum(1, PackagingUom.pack), true);
      expect(conMinimo.respectsMinimum(40, PackagingUom.box), true);
    });

    test('sin mínimo configurado no se bloquea nada', () {
      const sinMinimo = ProductPackaging(unitsPerPack: 1, packsPerBox: 40);
      expect(sinMinimo.respectsMinimum(1, PackagingUom.unit), true);
    });

    test('el mensaje nombra la unidad del producto', () {
      expect(conMinimo.minimumMessage(), contains('8 Paquetes'));
    });
  });

  group('precios por presentación', () {
    test('usa el precio propio de la caja si está configurado', () {
      const p = ProductPackaging(
        unitsPerPack: 1,
        packsPerBox: 40,
        boxPrice: 950,
        packPrice: 25,
      );
      expect(p.priceFor(PackagingUom.box, 26), 950);
      expect(p.priceFor(PackagingUom.pack, 26), 25);
      expect(p.priceFor(PackagingUom.unit, 26), 26);
    });

    test('sin precio propio lo deriva del unitario', () {
      const p = ProductPackaging(unitsPerPack: 1, packsPerBox: 40);
      expect(p.priceFor(PackagingUom.box, 26), 1040);
    });
  });

  group('producto SIN empaque', () {
    test('se comporta exactamente como antes', () {
      const simple = ProductPackaging.none;
      expect(simple.isConfigured, false);
      expect(simple.sellableUoms, [PackagingUom.unit]);
      expect(simple.toBaseUnits(7, PackagingUom.unit), 7);
      expect(simple.breakdown(7).units, 7);
      expect(simple.describeStock(7), '7 Unidad');
    });

    test('un mapa sin columnas de empaque no rompe', () {
      final p = ProductPackaging.fromMap({'name': 'algo'});
      expect(p.isConfigured, false);
    });

    test('valores cero o negativos se ignoran', () {
      final p = ProductPackaging.fromMap(
        {'units_per_pack': 0, 'packs_per_box': -5},
      );
      expect(p.isConfigured, false);
    });
  });

  group('bordes', () {
    const p = ProductPackaging(
      unitsPerPack: 25,
      packsPerBox: 40,
      unitLabel: 'Vaso',
      packLabel: 'Paquete',
      boxLabel: 'Caja',
    );

    test('stock cero', () {
      expect(p.breakdown(0).isEmpty, true);
      expect(p.describeStock(0), '0 Vasos');
    });

    test('stock negativo no inventa cajas', () {
      expect(p.breakdown(-50).isEmpty, true);
    });

    test('menos de un paquete son solo unidades', () {
      expect(p.describeStock(7), '7 Vasos');
    });

    test('el singular no se pluraliza', () {
      expect(p.describeStock(1), '1 Vaso');
      expect(p.describeStock(1000), '1 Caja');
    });

    test('stock con decimales no se va por un centavo de unidad', () {
      // 2000.999 vasos = 2 cajas, 0 paquetes, 0.999 vasos.
      final b = p.breakdown(2000.999);
      expect(b.boxes, 2);
      expect(b.packs, 0);
      expect(b.units, closeTo(0.999, 0.0001));
    });
  });
}
