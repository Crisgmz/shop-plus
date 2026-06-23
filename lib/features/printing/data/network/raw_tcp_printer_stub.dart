import 'dart:typed_data';

import 'raw_tcp_printer.dart';

/// Implementación stub para Web: los sockets TCP crudos no están disponibles
/// en el navegador, por lo que la impresión por TCP queda deshabilitada.
class RawTcpPrinterImpl implements RawTcpPrinter {
  RawTcpPrinterImpl();

  @override
  bool get isSupported => false;

  @override
  Future<TcpPrintResult> send({
    required String host,
    required int port,
    required Uint8List bytes,
    Duration timeout = const Duration(seconds: 6),
  }) async {
    return const TcpPrintResult.failure(
      'La impresión por TCP no está disponible en la versión web. '
      'Usa la aplicación de escritorio para Windows.',
    );
  }
}
