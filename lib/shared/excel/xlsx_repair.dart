/// Reparaciones de .xlsx antes de pasarlos al paquete `excel`.
library;

import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:xml/xml.dart';

/// Primer id libre para formatos de número propios según el estándar OOXML.
const int _firstCustomNumFmtId = 164;

const String _stylesPath = 'xl/styles.xml';

/// Renumera los formatos de número propios que usan un id reservado (< 164).
///
/// Numbers, Google Sheets y otros programas escriben, por ejemplo, el formato
/// "Contabilidad" como `<numFmt numFmtId="43" …/>`. El paquete `excel` 4.x
/// rechaza el archivo completo con "custom numFmtId starts at 164 but found a
/// value of 43", aunque las celdas estén bien.
///
/// Cada formato así pasa a un id libre desde 164, y los estilos de celda que lo
/// usaban (`cellXfs` y `cellStyleXfs`) apuntan al nuevo id. El texto del
/// formato no cambia, así que los números se leen igual. Si no hay nada que
/// reparar —o el archivo no es un .xlsx legible— devuelve los mismos bytes y
/// deja que `excel` informe su propio error.
Uint8List repairXlsxNumFormats(Uint8List bytes) {
  final Archive archive;
  try {
    archive = ZipDecoder().decodeBytes(bytes);
  } catch (_) {
    return bytes;
  }

  final styles = archive.findFile(_stylesPath);
  if (styles == null) return bytes;

  final XmlDocument document;
  try {
    document = XmlDocument.parse(
      utf8.decode(styles.content as List<int>, allowMalformed: true),
    );
  } catch (_) {
    return bytes;
  }

  final numFmts = document.findAllElements('numFmt').toList();
  final ids = numFmts
      .map((node) => int.tryParse(node.getAttribute('numFmtId') ?? ''))
      .whereType<int>()
      .toList();
  if (!ids.any((id) => id < _firstCustomNumFmtId)) return bytes;

  var nextId = ids.fold<int>(
    _firstCustomNumFmtId,
    (max, id) => id >= max ? id + 1 : max,
  );
  final renumbered = <int, int>{};
  for (final node in numFmts) {
    final id = int.tryParse(node.getAttribute('numFmtId') ?? '');
    if (id == null || id >= _firstCustomNumFmtId) continue;
    final newId = renumbered.putIfAbsent(id, () => nextId++);
    node.setAttribute('numFmtId', '$newId');
  }

  for (final group in ['cellXfs', 'cellStyleXfs']) {
    for (final parent in document.findAllElements(group)) {
      for (final xf in parent.findElements('xf')) {
        final id = int.tryParse(xf.getAttribute('numFmtId') ?? '');
        final newId = id == null ? null : renumbered[id];
        if (newId != null) xf.setAttribute('numFmtId', '$newId');
      }
    }
  }

  final patched = utf8.encode(document.toXmlString());
  final repaired = Archive();
  for (final file in archive.files) {
    if (file.name == _stylesPath) {
      repaired.addFile(ArchiveFile(_stylesPath, patched.length, patched));
    } else {
      repaired.addFile(file);
    }
  }

  final encoded = ZipEncoder().encode(repaired);
  return encoded == null ? bytes : Uint8List.fromList(encoded);
}
