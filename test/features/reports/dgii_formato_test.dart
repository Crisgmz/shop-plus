import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_app/features/reports/domain/dgii_formato.dart';

// Filas con la forma que devuelven `dgii_607_data` / `dgii_606_data` tras la
// migración 93 (salida real de la función sobre datos de prueba).

Map<String, dynamic> venta({
  required String ncf,
  String? rncCliente,
  double montoFacturado = 100,
  double itbis = 18,
  double? total,
  double propina = 0,
  Map<String, dynamic> pagos = const {},
  String fecha = '20260810',
}) =>
    {
      'ncf': ncf,
      'rnc_cliente': rncCliente,
      'tipo_id': '2',
      'tipo_ingreso': '02',
      'ncf_modificado': null,
      'fecha_comprobante': fecha,
      'monto_facturado': montoFacturado,
      'itbis_facturado': itbis,
      'monto_total': total ?? montoFacturado + itbis + propina,
      'efectivo': total ?? montoFacturado + itbis + propina,
      'credito': 0,
      'client_name': null,
      'receipt_type': ncf.startsWith('B02') ? 'consumer_final' : 'fiscal_credit',
      'propina_legal': propina,
      'pagos': pagos,
    };

Map<String, dynamic> compra({
  required String ncf,
  String rnc = '131999999',
  double montoFacturado = 1000,
  double itbis = 180,
  double servicios = 0,
  Map<String, dynamic> pagos = const {},
  double pagado = 0,
  double saldo = 0,
  String? fechaUltimoPago,
}) =>
    {
      'rnc_proveedor': rnc,
      'tipo_id': '1',
      'tipo_bien_servicio': '09',
      'ncf': ncf,
      'ncf_modificado': null,
      'fecha_comprobante': '20260805',
      'fecha_pago': '20260805',
      'monto_facturado': montoFacturado,
      'itbis_facturado': itbis,
      'monto_total': montoFacturado + itbis,
      'supplier_name': 'Proveedor SRL',
      'monto_servicios': servicios,
      'pagos': pagos,
      'pagado': pagado,
      'saldo': saldo,
      'fecha_ultimo_pago': fechaUltimoPago,
    };

Map<String, dynamic> reporte(String tipo, List<Map<String, dynamic>> rows,
        {bool conMigracion = true}) =>
    {
      'report_type': tipo,
      if (conMigracion) 'formato_version': 2,
      'period': '202608',
      'rnc_negocio': '1-31-00000-1',
      'records_count': rows.length,
      'rows': rows,
      'inconsistencies': const [],
      'inconsistencies_count': 0,
    };

void main() {
  group('607', () {
    test('23 columnas en el orden de la DGII y TXT con cabecera', () {
      final f = dgiiFormato607(reporte('607', [
        venta(
          ncf: 'B0100000001',
          rncCliente: '1-31-12345-6',
          montoFacturado: 900,
          itbis: 148,
          propina: 50,
          // 1,100 cobrados sobre 1,098: RD$2 de devuelta.
          pagos: {'cash': 100.0, 'card': 1000.0},
        ),
      ]));

      expect(f.columnas, hasLength(23));
      expect(f.filas.single, hasLength(23));
      expect(f.rnc, '131000001');

      final lineas = f.toTxt().split('\r\n');
      expect(lineas.first, '607|131000001|202608|1');
      expect(
        lineas[1],
        '131123456|1|B0100000001||01|20260810||900.00|148.00|||||||50.00|'
        '98.00||1000.00||||',
      );
      expect(lineas, hasLength(2));
    });

    test('las formas de venta siempre suman el total de la factura', () {
      final f = dgiiFormato607(reporte('607', [
        // Nada cobrado el día de la venta → todo a crédito.
        venta(ncf: 'B0100000002', rncCliente: '131123456', total: 1180,
            montoFacturado: 1000, itbis: 180),
        // Pago parcial por transferencia, el resto queda a crédito.
        venta(ncf: 'B0100000003', rncCliente: '131123456', total: 1180,
            montoFacturado: 1000, itbis: 180, pagos: {'transfer': 500.0}),
        // Pago móvil y "otro".
        venta(ncf: 'B0100000004', rncCliente: '131123456', total: 118,
            pagos: {'mobile': 18.0, 'other': 100.0}),
      ]));

      List<double?> formas(int i) => f.filas[i].sublist(16).cast<double?>();
      expect(formas(0), [null, null, null, 1180.0, null, null, null]);
      expect(formas(1), [null, 500.0, null, 680.0, null, null, null]);
      expect(formas(2), [null, 18.0, null, null, null, null, 100.0]);
    });

    test('consumo menor de 250,000 va al resumen, no al detalle', () {
      final f = dgiiFormato607(reporte('607', [
        venta(ncf: 'B0200000001', pagos: {'transfer': 118.0}),
        venta(ncf: 'E320000000001', pagos: {'cash': 118.0}),
        venta(
          ncf: 'B0200000002',
          rncCliente: '00112345678',
          montoFacturado: 250000,
          itbis: 45000,
          pagos: {'card': 295000.0},
        ),
      ]));

      // Solo la de RD$295,000 va en el detalle.
      expect(f.filas, hasLength(1));
      expect(f.filas.single[2], 'B0200000002');
      expect(f.filas.single[1], '2');

      final r = f.resumenConsumo!;
      expect(r.cantidad, 3);
      expect(r.montoFacturado, 250200);
      expect(r.itbis, 45036);
      expect(r.formasVenta, [118, 118, 295000, 0, 0, 0, 0]);
      expect(r.total, 295236);
    });

    test('consumo sin cliente: RNC y tipo de identificación vacíos', () {
      final f = dgiiFormato607(reporte('607', [
        venta(ncf: 'B0200000003', montoFacturado: 300000, itbis: 0),
      ]));
      expect(f.filas.single.sublist(0, 2), ['', '']);
    });

    test('sin la migración 93 marca el formato como no desglosado', () {
      final f = dgiiFormato607(reporte(
        '607',
        [venta(ncf: 'B0100000001', rncCliente: '131123456')],
        conMigracion: false,
      ));
      expect(f.desglosado, isFalse);
      // Lo cobrado cae en efectivo, como antes.
      expect(f.filas.single[16], 118.0);
    });
  });

  group('606', () {
    test('23 columnas, forma de pago y fecha del último pago', () {
      final f = dgiiFormato606(reporte('606', [
        // 500 pagados al registrar (sin método) + transferencia + cheque.
        compra(
          ncf: 'B0100000500',
          servicios: 200,
          pagos: {'transfer': 400.0, 'check': 280.0},
          pagado: 1180,
          fechaUltimoPago: '20260825',
        ),
        // A crédito, sin pagos.
        compra(ncf: 'B0100000501', montoFacturado: 500, itbis: 90, saldo: 590),
      ]));

      expect(f.columnas, hasLength(23));
      final pagada = f.filas[0];
      expect(pagada, hasLength(23));
      expect(pagada[6], '20260825'); // fecha pago
      expect(pagada[7], 200.0); // servicios
      expect(pagada[8], 800.0); // bienes
      expect(pagada[9], 1000.0); // total monto facturado
      expect(pagada[14], 180.0); // ITBIS por adelantar
      expect(pagada[22], '07'); // efectivo + cheque/transferencia = mixto

      final lineas = f.toTxt().split('\r\n');
      expect(lineas.first, '606|131000001|202608|2');
      expect(
        lineas[2],
        '131999999|1|09|B0100000501||20260805|||500.00|500.00|90.00||||90.00'
        '||||||||04',
      );
    });

    test('forma de pago según cómo se pagó', () {
      String forma(Map<String, dynamic> c) =>
          dgiiFormato606(reporte('606', [c])).filas.single[22] as String;

      expect(forma(compra(ncf: 'B0100000001', pagado: 1180)), '01');
      expect(
        forma(compra(
            ncf: 'B0100000002', pagos: {'transfer': 1180.0}, pagado: 1180)),
        '02',
      );
      expect(
        forma(compra(ncf: 'B0100000003', pagos: {'card': 1180.0}, pagado: 1180)),
        '03',
      );
      expect(forma(compra(ncf: 'B0100000004', saldo: 1180)), '04');
      expect(
        forma(compra(ncf: 'B0100000005', pagado: 500, saldo: 680)),
        '07',
      );
    });

    test('proveedor con cédula: Tipo Id 2; con saldo no hay fecha de pago', () {
      final fila = dgiiFormato606(reporte('606', [
        compra(ncf: 'B1100000001', rnc: '001-1234567-8', saldo: 1180),
      ])).filas.single;
      expect(fila.sublist(0, 2), ['00112345678', '2']);
      expect(fila[6], '');
    });
  });
}
