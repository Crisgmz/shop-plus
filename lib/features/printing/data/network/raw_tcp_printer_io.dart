import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'raw_tcp_printer.dart';

/// Implementación de [RawTcpPrinter] basada en `dart:io` (escritorio/móvil).
class RawTcpPrinterImpl implements RawTcpPrinter {
  RawTcpPrinterImpl();

  @override
  bool get isSupported => true;

  @override
  Future<TcpPrintResult> send({
    required String host,
    required int port,
    required Uint8List bytes,
    Duration timeout = const Duration(seconds: 6),
  }) async {
    Socket? socket;
    try {
      socket = await Socket.connect(host, port, timeout: timeout);
      socket.add(bytes);
      await socket.flush().timeout(timeout);
      // Pequeña espera para que la impresora drene el búfer antes de cerrar.
      await socket.close().timeout(timeout);
      return const TcpPrintResult.success();
    } on SocketException catch (e) {
      _destroy(socket);
      return TcpPrintResult.failure(_socketMessage(host, port, e));
    } on TimeoutException {
      _destroy(socket);
      return TcpPrintResult.failure(
        'Tiempo de espera agotado conectando a $host:$port. '
        'Verifica que la impresora esté encendida y en la misma red.',
      );
    } catch (e) {
      _destroy(socket);
      return TcpPrintResult.failure('Error de impresión: $e');
    }
  }

  void _destroy(Socket? socket) {
    try {
      socket?.destroy();
    } catch (_) {
      // best-effort
    }
  }

  String _socketMessage(String host, int port, SocketException e) {
    final reason = e.osError?.message ?? e.message;
    return 'No se pudo conectar a la impresora en $host:$port ($reason).';
  }
}
