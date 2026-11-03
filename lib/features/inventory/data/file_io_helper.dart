import 'dart:io' show File, Platform;
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../../../shared/io/web_download_stub.dart'
    if (dart.library.html) '../../../shared/io/web_download_html.dart';

class FileIoHelper {
  /// Guarda bytes con un diálogo nativo de "Guardar como" (desktop/web) o
  /// dispara compartir (mobile).
  ///
  /// `extension` sin el punto (ej: 'xlsx', 'pdf', 'csv', 'txt'). Si el
  /// usuario no agrega la extensión en el diálogo, la añadimos.
  static Future<bool> saveBytes({
    required Uint8List bytes,
    required String fileName,
    String dialogTitle = 'Guardar archivo',
    String extension = 'xlsx',
  }) async {
    final allowed = <String>[extension];

    if (kIsWeb) {
      // `FilePicker.platform.saveFile` no está implementado en web — usamos
      // un anchor invisible con Object URL para forzar la descarga.
      final dotExt = '.$extension';
      final finalName = fileName.toLowerCase().endsWith(dotExt)
          ? fileName
          : '$fileName$dotExt';
      return downloadBytesInBrowser(
        bytes: bytes,
        fileName: finalName,
        mimeType: _mimeFor(extension),
      );
    }

    if (Platform.isAndroid || Platform.isIOS) {
      final tempDir = await getTemporaryDirectory();
      final tempFile = File('${tempDir.path}/$fileName');
      await tempFile.writeAsBytes(bytes, flush: true);
      final result = await Share.shareXFiles(
        [XFile(tempFile.path, name: fileName)],
        subject: fileName,
      );
      return result.status == ShareResultStatus.success ||
          result.status == ShareResultStatus.unavailable;
    }

    final path = await FilePicker.platform.saveFile(
      dialogTitle: dialogTitle,
      fileName: fileName,
      type: FileType.custom,
      allowedExtensions: allowed,
    );
    if (path == null) return false;
    final dotExt = '.$extension';
    final fixed = path.toLowerCase().endsWith(dotExt) ? path : '$path$dotExt';
    await File(fixed).writeAsBytes(bytes, flush: true);
    return true;
  }

  static Future<Uint8List?> pickXlsxBytes() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: const ['xlsx'],
      withData: true,
    );
    if (result == null || result.files.isEmpty) return null;
    final file = result.files.first;
    if (file.bytes != null) return file.bytes;
    final path = file.path;
    if (path == null) return null;
    return File(path).readAsBytes();
  }

  /// Igual que [pickXlsxBytes] pero devuelve también el nombre del archivo,
  /// para mostrarlo en la UI ("La ruta del archivo").
  static Future<({Uint8List bytes, String name})?> pickXlsxFile() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: const ['xlsx'],
      withData: true,
    );
    if (result == null || result.files.isEmpty) return null;
    final file = result.files.first;
    var bytes = file.bytes;
    if (bytes == null && file.path != null) {
      bytes = await File(file.path!).readAsBytes();
    }
    if (bytes == null) return null;
    return (bytes: bytes, name: file.name);
  }

  /// Picker para importar inventario: acepta .xlsx y .csv. El CSV sirve de
  /// respaldo cuando un .xlsx falla al leerse por sus formatos internos.
  static Future<({Uint8List bytes, String name})?> pickImportFile() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: const ['xlsx', 'csv'],
      withData: true,
    );
    if (result == null || result.files.isEmpty) return null;
    final file = result.files.first;
    var bytes = file.bytes;
    if (bytes == null && file.path != null) {
      bytes = await File(file.path!).readAsBytes();
    }
    if (bytes == null) return null;
    return (bytes: bytes, name: file.name);
  }

  /// Abre el picker filtrado al certificado de firma digital de la DGII.
  /// Se usa al solicitar la facturación electrónica: el archivo viaja al
  /// proveedor y no se guarda en ningún lado.
  static Future<({Uint8List bytes, String name})?> pickCertificateFile() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: const ['p12', 'pfx'],
      withData: true,
    );
    if (result == null || result.files.isEmpty) return null;
    final file = result.files.first;
    var bytes = file.bytes;
    if (bytes == null && file.path != null) {
      bytes = await File(file.path!).readAsBytes();
    }
    if (bytes == null) return null;
    return (bytes: bytes, name: file.name);
  }

  /// Picker de un XML de la DGII (postulación, declaración jurada, roles) para
  /// que el proveedor de facturación electrónica lo firme.
  static Future<({Uint8List bytes, String name})?> pickXmlFile() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: const ['xml'],
      withData: true,
    );
    if (result == null || result.files.isEmpty) return null;
    final file = result.files.first;
    var bytes = file.bytes;
    if (bytes == null && file.path != null) {
      bytes = await File(file.path!).readAsBytes();
    }
    if (bytes == null) return null;
    return (bytes: bytes, name: file.name);
  }

  /// MIME type aproximado a partir de la extensión sin punto. Usado por la
  /// descarga web; el resto de plataformas no lo necesitan.
  static String _mimeFor(String extension) {
    switch (extension.toLowerCase()) {
      case 'pdf':
        return 'application/pdf';
      case 'xlsx':
        return 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet';
      case 'csv':
        return 'text/csv';
      case 'txt':
        return 'text/plain';
      case 'json':
        return 'application/json';
      case 'xml':
        return 'application/xml';
      case 'png':
        return 'image/png';
      case 'jpg':
      case 'jpeg':
        return 'image/jpeg';
      default:
        return 'application/octet-stream';
    }
  }

  /// Abre el picker filtrado a imágenes y devuelve {bytes, extension}.
  /// `extension` siempre en minúsculas sin punto (jpg, png, webp...).
  static Future<({Uint8List bytes, String extension})?> pickImage() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: const ['jpg', 'jpeg', 'png', 'webp', 'gif'],
      withData: true,
    );
    if (result == null || result.files.isEmpty) return null;
    final file = result.files.first;

    Uint8List? bytes = file.bytes;
    if (bytes == null) {
      final path = file.path;
      if (path == null) return null;
      bytes = await File(path).readAsBytes();
    }

    final rawExt = (file.extension ?? '').toLowerCase();
    final ext = rawExt.isEmpty ? 'jpg' : rawExt;
    return (bytes: bytes, extension: ext);
  }
}
