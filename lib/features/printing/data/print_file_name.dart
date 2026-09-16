import 'printing_models.dart';

/// Caracteres que Windows y macOS rechazan dentro de un nombre de archivo.
final _ilegales = RegExp(r'[\\/:*?"<>|\x00-\x1F]');
final _espaciosSeguidos = RegExp(r'\s+');
final _puntoFinal = RegExp(r'[.\s]+$');
final _digito = RegExp(r'\d');

/// Hasta dónde se deja crecer el nombre del cliente. El comprobante va aparte,
/// así un cliente con razón social larguísima no se come el número.
const _largoCliente = 50;

/// Cuántos dígitos del NCF son el secuencial ("el terminal"): B01 + 8.
const _largoTerminal = 8;

/// Nombre con el que se guarda el PDF: `Juan Pérez - 00000123`.
///
/// Es lo que el navegador y el diálogo de impresión del sistema proponen al
/// guardar. Antes era el número interno de la venta, que no distingue nada
/// cuando hay doscientas facturas en la carpeta de Descargas.
///
/// Reglas:
///   · [ncf] manda cuando existe: de `B0100000123` se queda con `00000123`,
///     el secuencial, que es como el negocio identifica la factura.
///   · Sin comprobante (venta 'none') cae al número de venta.
///   · Sin contraparte se queda solo con el comprobante. Quién es la
///     contraparte cuando falta lo decide [printDocumentFileName], que sí sabe
///     qué clase de documento es.
String buildPrintFileName({
  required String documentNumber,
  String? clientName,
  String? ncf,
  bool withConduce = false,
}) {
  var cliente = _limpiar(clientName ?? '');
  if (cliente.length > _largoCliente) {
    cliente = _limpiar(cliente.substring(0, _largoCliente));
  }

  final comprobante = _terminal(ncf) ?? _limpiar(documentNumber);

  var nombre = [
    if (cliente.isNotEmpty) cliente,
    if (comprobante.isNotEmpty) comprobante,
  ].join(' - ');
  if (nombre.isEmpty) nombre = 'Documento';

  return withConduce ? '$nombre-con-conduce' : nombre;
}

/// Misma regla, aplicada al documento que se está por imprimir.
///
/// El diálogo de impresión lo comparten ventas, cotizaciones, compras, gastos
/// y cobros, así que aquí se decide qué poner cuando no hay contraparte.
String printDocumentFileName(
  PrintDocumentData doc, {
  bool withConduce = false,
}) {
  final contraparte = _limpiar(doc.customer?.name ?? '');
  return buildPrintFileName(
    documentNumber: doc.documentNumber,
    clientName:
        contraparte.isNotEmpty ? contraparte : _sinContraparte(doc.documentType),
    ncf: doc.ncf,
    withConduce: withConduce,
  );
}

/// Una venta sin cliente ES a consumidor final, y así lo dice la factura
/// impresa. Una compra o un gasto sin proveedor es un dato que falta, no un
/// consumidor final: esos se quedan solo con su número.
String? _sinContraparte(PrintDocumentType tipo) => switch (tipo) {
      PrintDocumentType.saleReceipt ||
      PrintDocumentType.fiscalInvoice ||
      PrintDocumentType.creditNote =>
        'Consumidor Final',
      _ => null,
    };

/// Los últimos 8 dígitos del NCF. Se toman los dígitos sueltos y no un
/// `substring` a ciegas para que dé igual si viene como `B0100000123`,
/// `B01-00000123` o con espacios de más.
String? _terminal(String? ncf) {
  final limpio = _limpiar(ncf ?? '');
  if (limpio.isEmpty) return null;

  final digitos = _digito.allMatches(limpio).map((m) => m[0]!).join();
  if (digitos.isEmpty) return limpio; // comprobante raro: se usa tal cual
  if (digitos.length <= _largoTerminal) return digitos;
  return digitos.substring(digitos.length - _largoTerminal);
}

String _limpiar(String valor) => valor
    .replaceAll(_ilegales, ' ')
    .replaceAll(_espaciosSeguidos, ' ')
    .trim()
    // Windows tampoco admite un nombre que termine en punto.
    .replaceAll(_puntoFinal, '');
