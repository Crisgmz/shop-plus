import 'dart:typed_data';

import 'raw_tcp_printer_stub.dart'
    if (dart.library.io) 'raw_tcp_printer_io.dart';

/// Resultado de un intento de impresión por TCP.
class TcpPrintResult {
  const TcpPrintResult.success() : ok = true, error = null;
  const TcpPrintResult.failure(this.error) : ok = false;

  final bool ok;
  final String? error;
}

/// Transporte que envía bytes ESC/POS crudos a una impresora térmica por
/// socket TCP (puerto crudo, típicamente 9100 / JetDirect / RAW).
///
/// La implementación real usa `dart:io` (escritorio/móvil). En Web la
/// implementación stub lanza [UnsupportedError] porque los sockets crudos no
/// están disponibles en el navegador.
abstract class RawTcpPrinter {
  /// Crea la implementación adecuada según la plataforma.
  factory RawTcpPrinter() = RawTcpPrinterImpl;

  /// Envía [bytes] a `host:port`. Lanza/retorna error si la conexión o el
  /// envío fallan dentro de [timeout].
  Future<TcpPrintResult> send({
    required String host,
    required int port,
    required Uint8List bytes,
    Duration timeout = const Duration(seconds: 6),
  });

  /// True en plataformas con sockets crudos (todo excepto Web).
  bool get isSupported;
}
