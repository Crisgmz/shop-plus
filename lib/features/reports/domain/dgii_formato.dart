// Formatos de envío 606 (compras) y 607 (ventas) de la DGII.
//
// Norma General 07-2018 y 05-2019; columnas y códigos de las herramientas de
// envío oficiales (606 v2019.05, 607 v2023.1.1) y del instructivo del 607.
// Referencia completa en docs/DGII_606_607.md.
//
// Parte del JSON de `dgii_606_data` / `dgii_607_data` y produce las 23
// columnas de cada formato. Con esas filas se generan tanto el TXT que se sube
// a la Oficina Virtual como el Excel: así los dos nunca difieren.
//
// Reglas de la DGII que se aplican aquí:
//   607 · Tipo de Ingreso "01" (ingresos por operaciones, no financieros).
//       · Formas de venta (casillas 17-23): incluyen impuestos y suman el
//         total de la factura.
//       · Las facturas de consumo (B02 / E32) menores de RD$250,000 NO van una
//         por una: se reportan en el "Resumen General de Facturas de Consumo"
//         de la Oficina Virtual, que incluye TODAS las de consumo.
//   606 · Monto en servicios + monto en bienes = total facturado (sin ITBIS).
//       · ITBIS por adelantar = ITBIS facturado − ITBIS llevado al costo.
//       · Forma de pago: 01 efectivo, 02 cheque/transferencia/depósito,
//         03 tarjeta, 04 a crédito, 07 mixto.

import '../../../shared/formatters/formatters.dart';

/// Desde este monto una factura de consumo se reporta en el detalle del 607
/// (Norma General 10-18).
const dgiiTopeFacturaConsumo = 250000.0;

class DgiiColumna {
  const DgiiColumna(this.titulo, {this.monto = false});

  final String titulo;

  /// Casilla de monto: se escribe con dos decimales, o vacía si no aplica.
  final bool monto;
}

/// Casillas 17-23 del 607 / tipo de venta del resumen de consumo.
const dgiiFormasVenta = [
  'Efectivo',
  'Cheque/ Transferencia/ Depósito',
  'Tarjeta Débito/Crédito',
  'Venta a Crédito',
  'Bonos o Certificados de Regalo',
  'Permuta',
  'Otras Formas de Ventas',
];

const dgiiColumnas607 = [
  DgiiColumna('RNC/Cédula o Pasaporte'),
  DgiiColumna('Tipo Identificación'),
  DgiiColumna('Número Comprobante Fiscal'),
  DgiiColumna('Número Comprobante Fiscal Modificado'),
  DgiiColumna('Tipo de Ingreso'),
  DgiiColumna('Fecha Comprobante'),
  DgiiColumna('Fecha de Retención'),
  DgiiColumna('Monto Facturado', monto: true),
  DgiiColumna('ITBIS Facturado', monto: true),
  DgiiColumna('ITBIS Retenido por Terceros', monto: true),
  DgiiColumna('ITBIS Percibido', monto: true),
  DgiiColumna('Retención Renta por Terceros', monto: true),
  DgiiColumna('ISR Percibido', monto: true),
  DgiiColumna('Impuesto Selectivo al Consumo', monto: true),
  DgiiColumna('Otros Impuestos/Tasas', monto: true),
  DgiiColumna('Monto Propina Legal', monto: true),
  DgiiColumna('Efectivo', monto: true),
  DgiiColumna('Cheque/ Transferencia/ Depósito', monto: true),
  DgiiColumna('Tarjeta Débito/Crédito', monto: true),
  DgiiColumna('Venta a Crédito', monto: true),
  DgiiColumna('Bonos o Certificados de Regalo', monto: true),
  DgiiColumna('Permuta', monto: true),
  DgiiColumna('Otras Formas de Ventas', monto: true),
];

const dgiiColumnas606 = [
  DgiiColumna('RNC o Cédula'),
  DgiiColumna('Tipo Id'),
  DgiiColumna('Tipo Bienes y Servicios Comprados'),
  DgiiColumna('NCF'),
  DgiiColumna('NCF ó Documento Modificado'),
  DgiiColumna('Fecha Comprobante'),
  DgiiColumna('Fecha Pago'),
  DgiiColumna('Monto Facturado en Servicios', monto: true),
  DgiiColumna('Monto Facturado en Bienes', monto: true),
  DgiiColumna('Total Monto Facturado', monto: true),
  DgiiColumna('ITBIS Facturado', monto: true),
  DgiiColumna('ITBIS Retenido', monto: true),
  DgiiColumna('ITBIS sujeto a Proporcionalidad (Art. 349)', monto: true),
  DgiiColumna('ITBIS llevado al Costo', monto: true),
  DgiiColumna('ITBIS por Adelantar', monto: true),
  DgiiColumna('ITBIS percibido en compras', monto: true),
  DgiiColumna('Tipo de Retención en ISR'),
  DgiiColumna('Monto Retención Renta', monto: true),
  DgiiColumna('ISR Percibido en compras', monto: true),
  DgiiColumna('Impuesto Selectivo al Consumo', monto: true),
  DgiiColumna('Otros Impuesto/Tasas', monto: true),
  DgiiColumna('Monto Propina Legal', monto: true),
  DgiiColumna('Forma de Pago'),
];

/// "Resumen General de Facturas de Consumo (F.C.)" que se llena en la Oficina
/// Virtual al enviar el 607. Incluye todas las facturas de consumo del mes,
/// también las de RD$250,000 o más que van además en el detalle.
class DgiiResumenConsumo {
  const DgiiResumenConsumo({
    required this.cantidad,
    required this.montoFacturado,
    required this.itbis,
    required this.propina,
    required this.formasVenta,
  });

  final int cantidad;
  final double montoFacturado;
  final double itbis;
  final double propina;

  /// Un monto por cada entrada de [dgiiFormasVenta].
  final List<double> formasVenta;

  double get total => formasVenta.fold(0, (s, v) => s + v);
}

class DgiiFormato {
  const DgiiFormato({
    required this.tipo,
    required this.rnc,
    required this.periodo,
    required this.columnas,
    required this.filas,
    required this.desglosado,
    this.resumenConsumo,
  });

  /// '606' o '607'.
  final String tipo;
  final String rnc;

  /// AAAAMM.
  final String periodo;
  final List<DgiiColumna> columnas;

  /// Un registro por comprobante, una celda por columna: `String` en las de
  /// texto, `double?` en las de monto (null = casilla vacía).
  final List<List<Object?>> filas;

  /// false cuando el servidor aún no tiene la migración 93: la forma de pago
  /// (y en el 606 la fecha de pago y bienes/servicios) no se pudo desglosar.
  final bool desglosado;

  /// Solo en el 607.
  final DgiiResumenConsumo? resumenConsumo;

  /// Índices de las columnas que se muestran en la vista previa.
  ({int documento, int ncf, int fecha, int monto, int itbis}) get claves =>
      tipo == '606'
          ? (documento: 0, ncf: 3, fecha: 5, monto: 9, itbis: 10)
          : (documento: 0, ncf: 2, fecha: 5, monto: 7, itbis: 8);

  /// Archivo para la Oficina Virtual: cabecera `606|RNC|AAAAMM|cantidad` y un
  /// registro por línea con las 23 casillas separadas por `|`.
  String toTxt() {
    final lineas = [
      '$tipo|$rnc|$periodo|${filas.length}',
      for (final fila in filas)
        [
          for (final celda in fila)
            switch (celda) {
              null => '',
              double v => v.toStringAsFixed(2),
              _ => celda.toString().replaceAll(RegExp(r'[|\r\n]'), ' ').trim(),
            },
        ].join('|'),
    ];
    // CRLF: el pre-validador y la herramienta de la DGII son de Windows.
    return lineas.join('\r\n');
  }
}

DgiiFormato dgiiFormato607(Map<String, dynamic> data) {
  final desglosado = data['formato_version'] != null;
  final filas = <List<Object?>>[];

  var consumoCantidad = 0;
  var consumoMonto = 0;
  var consumoItbis = 0;
  var consumoPropina = 0;
  final consumoFormas = List.filled(dgiiFormasVenta.length, 0);

  for (final raw in (data['rows'] as List?) ?? const []) {
    if (raw is! Map) continue;
    final ncf = _texto(raw['ncf']);
    final total = _centavos(raw['monto_total']);
    final monto = _centavos(raw['monto_facturado']);
    final itbis = _centavos(raw['itbis_facturado']);
    final propina = _centavos(raw['propina_legal']);
    final formas = _formasVenta607(raw, total, desglosado: desglosado);

    final esConsumo = ncf.startsWith('B02') || ncf.startsWith('E32');
    if (esConsumo) {
      consumoCantidad++;
      consumoMonto += monto;
      consumoItbis += itbis;
      consumoPropina += propina;
      for (var i = 0; i < formas.length; i++) {
        consumoFormas[i] += formas[i];
      }
      if (total < dgiiTopeFacturaConsumo * 100) continue;
    }

    final documento = _documento(raw['rnc_cliente']);
    filas.add([
      documento,
      _tipoIdCliente(documento),
      ncf,
      _texto(raw['ncf_modificado']),
      '01',
      _texto(raw['fecha_comprobante']),
      '',
      monto / 100,
      itbis / 100,
      null, // ITBIS retenido por terceros
      null, // ITBIS percibido (deshabilitado por la DGII)
      null, // retención renta por terceros
      null, // ISR percibido (deshabilitado por la DGII)
      null, // impuesto selectivo al consumo
      null, // otros impuestos/tasas
      _montoOVacio(propina),
      for (final f in formas) _montoOVacio(f),
    ]);
  }

  return DgiiFormato(
    tipo: '607',
    rnc: _documento(data['rnc_negocio']),
    periodo: _texto(data['period']),
    columnas: dgiiColumnas607,
    filas: filas,
    desglosado: desglosado,
    resumenConsumo: DgiiResumenConsumo(
      cantidad: consumoCantidad,
      montoFacturado: consumoMonto / 100,
      itbis: consumoItbis / 100,
      propina: consumoPropina / 100,
      formasVenta: [for (final f in consumoFormas) f / 100],
    ),
  );
}

DgiiFormato dgiiFormato606(Map<String, dynamic> data) {
  final desglosado = data['formato_version'] != null;
  final filas = <List<Object?>>[];

  for (final raw in (data['rows'] as List?) ?? const []) {
    if (raw is! Map) continue;
    final monto = _centavos(raw['monto_facturado']);
    final itbis = _centavos(raw['itbis_facturado']);
    var servicios = desglosado ? _centavos(raw['monto_servicios']) : 0;
    if (servicios < 0) servicios = 0;
    if (servicios > monto) servicios = monto;
    final documento = _documento(raw['rnc_proveedor']);

    filas.add([
      documento,
      documento.length == 11 ? '2' : '1',
      _texto(raw['tipo_bien_servicio']).isEmpty
          ? '09'
          : _texto(raw['tipo_bien_servicio']),
      _texto(raw['ncf']),
      _texto(raw['ncf_modificado']),
      _texto(raw['fecha_comprobante']),
      desglosado ? _fechaPago606(raw) : _texto(raw['fecha_pago']),
      _montoOVacio(servicios),
      _montoOVacio(monto - servicios),
      monto / 100,
      itbis / 100,
      null, // ITBIS retenido
      null, // ITBIS sujeto a proporcionalidad
      null, // ITBIS llevado al costo
      itbis / 100, // ITBIS por adelantar = facturado − llevado al costo (0)
      null, // ITBIS percibido en compras
      '', // tipo de retención en ISR
      null, // monto retención renta
      null, // ISR percibido en compras
      null, // impuesto selectivo al consumo
      null, // otros impuestos/tasas
      null, // propina legal
      desglosado ? _formaPago606(raw) : '',
    ]);
  }

  return DgiiFormato(
    tipo: '606',
    rnc: _documento(data['rnc_negocio']),
    periodo: _texto(data['period']),
    columnas: dgiiColumnas606,
    filas: filas,
    desglosado: desglosado,
  );
}

/// Reparte el total de la venta entre las casillas 17-23, en centavos.
///
/// Los pagos del mismo día van a su casilla; si suman más que el total (hubo
/// devuelta) el exceso se descuenta primero del efectivo; lo que falte para
/// llegar al total es venta a crédito. Así la suma siempre es el total.
List<int> _formasVenta607(Map raw, int total, {required bool desglosado}) {
  final formas = List.filled(dgiiFormasVenta.length, 0);

  final Map pagos = desglosado
      ? (raw['pagos'] as Map?) ?? const {}
      // Sin la migración 93 solo se sabe cuánto se cobró, no cómo.
      : {'cash': raw['efectivo'], 'credit': raw['credito']};

  pagos.forEach((metodo, monto) {
    final i = switch (metodo) {
      'cash' => 0,
      'transfer' || 'check' || 'mobile' => 1,
      'card' => 2,
      'credit' => 3,
      _ => 6,
    };
    formas[i] += _centavos(monto);
  });

  var exceso = formas.fold<int>(0, (s, v) => s + v) - total;
  for (final i in const [0, 6, 1, 2, 3]) {
    if (exceso <= 0) break;
    final quitar = exceso < formas[i] ? exceso : formas[i];
    formas[i] -= quitar;
    exceso -= quitar;
  }
  final faltante = total - formas.fold<int>(0, (s, v) => s + v);
  if (faltante > 0) formas[3] += faltante;
  return formas;
}

/// Fecha del pago que saldó la compra. Vacía mientras quede saldo.
String _fechaPago606(Map raw) {
  if (_centavos(raw['saldo']) > 0) return '';
  final ultimo = _texto(raw['fecha_ultimo_pago']);
  return ultimo.isNotEmpty ? ultimo : _texto(raw['fecha_comprobante']);
}

String _formaPago606(Map raw) {
  final pagos = (raw['pagos'] as Map?) ?? const {};
  var efectivo = 0;
  var chequeTransferencia = 0;
  var tarjeta = 0;
  var abonos = 0;
  pagos.forEach((metodo, monto) {
    final c = _centavos(monto);
    abonos += c;
    switch (metodo) {
      case 'transfer' || 'check' || 'mobile':
        chequeTransferencia += c;
      case 'card':
        tarjeta += c;
      default:
        efectivo += c;
    }
  });
  // Lo pagado al registrar la compra no guarda método: se toma como efectivo.
  final sinMetodo = _centavos(raw['pagado']) - abonos;
  if (sinMetodo > 0) efectivo += sinMetodo;
  final credito = _centavos(raw['saldo']);

  final usadas = [
    if (efectivo > 0) '01',
    if (chequeTransferencia > 0) '02',
    if (tarjeta > 0) '03',
    if (credito > 0) '04',
  ];
  if (usadas.isEmpty) return '01';
  return usadas.length == 1 ? usadas.single : '07';
}

/// RNC / cédula sin guiones ni espacios: la DGII los pide solo con dígitos.
String _documento(Object? v) => _texto(v).replaceAll(RegExp(r'[\s-]'), '');

/// 1 = RNC (9 dígitos), 2 = cédula (11), 3 = pasaporte / ID tributaria.
/// Vacío cuando la venta no tiene cliente identificado.
String _tipoIdCliente(String documento) {
  if (documento.isEmpty) return '';
  if (RegExp(r'^\d{9}$').hasMatch(documento)) return '1';
  if (RegExp(r'^\d{11}$').hasMatch(documento)) return '2';
  return '3';
}

String _texto(Object? v) => v == null ? '' : v.toString().trim();

int _centavos(Object? v) => (toDouble(v) * 100).round();

double? _montoOVacio(int centavos) => centavos == 0 ? null : centavos / 100;
