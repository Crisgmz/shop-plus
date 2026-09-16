import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:excel/excel.dart';
import 'package:flutter_app/shared/excel/xlsx_repair.dart';
import 'package:flutter_test/flutter_test.dart';

/// Un .xlsx con la hoja "Productos" y un precio con formato Contabilidad
/// guardado como `numFmtId="43"`, tal como lo escriben Numbers o Google Sheets.
Uint8List _xlsxConContabilidad43() {
  final excel = Excel.createExcel();
  final sheet = excel['Productos'];
  sheet.appendRow([TextCellValue('nombre'), TextCellValue('precio')]);
  sheet.appendRow([TextCellValue('VASO PET 9 OZ'), DoubleCellValue(2639.83)]);
  excel.delete('Sheet1');
  final archive = ZipDecoder().decodeBytes(excel.save()!);

  final out = Archive();
  for (final file in archive.files) {
    if (file.name == 'xl/styles.xml') {
      var xml = utf8.decode(file.content as List<int>);
      const fmt = '<numFmts count="1"><numFmt numFmtId="43" '
          'formatCode="_(* #,##0.00_);_(* \\(#,##0.00\\);_(* &quot;-&quot;??_);_(@_)"/>'
          '</numFmts>';
      xml = xml.replaceFirst(RegExp(r'<numFmts[^>]*/>|<numFmts[\s\S]*?</numFmts>'), '');
      xml = xml.replaceFirstMapped(
          RegExp(r'(<styleSheet[^>]*>)'), (m) => '${m[1]}$fmt');
      // El estilo de la celda del precio (s="2", numFmtId="2") pasa a usar
      // el formato 43, así la lectura recorre el formato reparado.
      const precioXf = 'fontId="1" numFmtId="2"';
      expect(xml, contains(precioXf), reason: 'cambió la salida de excel');
      xml = xml.replaceFirst(precioXf, 'fontId="1" numFmtId="43"');
      final bytes = utf8.encode(xml);
      out.addFile(ArchiveFile(file.name, bytes.length, bytes));
    } else {
      out.addFile(file);
    }
  }
  return Uint8List.fromList(ZipEncoder().encode(out)!);
}

String _styles(Uint8List bytes) => utf8.decode(
      ZipDecoder().decodeBytes(bytes).findFile('xl/styles.xml')!.content
          as List<int>,
    );

void main() {
  test('sin reparar, excel rechaza el archivo como en la captura', () {
    final bytes = _xlsxConContabilidad43();
    expect(
      () => Excel.decodeBytes(bytes),
      throwsA(predicate((e) => e.toString().contains(
          'custom numFmtId starts at 164 but found a value of 43'))),
    );
  });

  test('reparado se lee completo y el precio sigue siendo el número', () {
    final repaired = repairXlsxNumFormats(_xlsxConContabilidad43());
    final sheet = Excel.decodeBytes(repaired).tables['Productos']!;

    expect(sheet.rows[1][0]!.value.toString(), 'VASO PET 9 OZ');
    final precio = sheet.rows[1][1]!.value;
    final numero = switch (precio) {
      DoubleCellValue(:final value) => value,
      IntCellValue(:final value) => value.toDouble(),
      _ => double.tryParse(precio.toString()),
    };
    expect(numero, 2639.83);
  });

  test('el formato pasa a 164 y el estilo que lo usaba lo sigue', () {
    final styles = _styles(repairXlsxNumFormats(_xlsxConContabilidad43()));
    expect(styles, contains('numFmtId="164"'));
    expect(styles, isNot(contains('numFmtId="43"')));
    expect(styles, contains('formatCode="_(* #,##0.00_)'));
  });

  test('un archivo sano vuelve tal cual', () {
    final excel = Excel.createExcel();
    excel['Productos'].appendRow([TextCellValue('nombre')]);
    final bytes = Uint8List.fromList(excel.save()!);
    expect(identical(repairXlsxNumFormats(bytes), bytes), isTrue);
  });

  test('lo que no es .xlsx vuelve tal cual para que excel dé su error', () {
    final bytes = Uint8List.fromList(utf8.encode('nombre,precio\nvaso,1'));
    expect(identical(repairXlsxNumFormats(bytes), bytes), isTrue);
  });
}
