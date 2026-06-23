import '../printing_models.dart';
import 'esc_pos_encoder.dart';
import 'network_printer_config.dart';
import 'raw_tcp_printer.dart';
import 'thermal_escpos_renderer.dart';

/// Orquesta el render ESC/POS y el envío por TCP a la impresora térmica de red.
class NetworkPrintService {
  NetworkPrintService({RawTcpPrinter? transport})
      : _transport = transport ?? RawTcpPrinter();

  final RawTcpPrinter _transport;

  bool get isSupported => _transport.isSupported;

  /// Imprime un recibo de venta/cotización/etc. por TCP.
  Future<TcpPrintResult> printDocument(
    PrintDocumentData document,
    NetworkPrinterConfig config, {
    bool openDrawer = false,
  }) async {
    if (!config.isConfigured) {
      return const TcpPrintResult.failure(
        'No hay impresora de red configurada (falta la dirección IP).',
      );
    }
    final renderer = ThermalEscPosRenderer(columns: config.paperColumns);
    final bytes = renderer.render(
      document,
      copies: config.copies,
      openDrawer: openDrawer && config.openDrawerOnCashSale,
    );
    return _transport.send(
      host: config.host.trim(),
      port: config.port,
      bytes: bytes,
    );
  }

  /// Imprime un ticket de prueba para validar la conexión y el papel.
  Future<TcpPrintResult> printTestTicket(NetworkPrinterConfig config) async {
    if (!config.isConfigured) {
      return const TcpPrintResult.failure(
        'Ingresa la dirección IP de la impresora antes de probar.',
      );
    }
    final e = EscPosEncoder(columns: config.paperColumns)..reset();
    e.align(PosAlign.center).bold(true).size(doubleHeight: true);
    e.text('SHOP+');
    e.size().bold(false);
    e.text('Prueba de impresion TCP');
    e.feed();
    e.align(PosAlign.left);
    e.twoColumns('Impresora:', '${config.host}:${config.port}');
    e.twoColumns('Ancho:', '${config.paperColumns} cols');
    e.divider();
    e.text('Si lees este ticket, la conexion');
    e.text('por TCP funciona correctamente.');
    e.divider();
    e.align(PosAlign.center).text('ABCDEFG abcdefg 0123456789');
    e.text('Acentos: aeiou ñ ¿? ¡! RD\$');
    e.cut();

    return _transport.send(
      host: config.host.trim(),
      port: config.port,
      bytes: e.bytes(),
    );
  }
}
