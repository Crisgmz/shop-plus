import 'dart:convert';
import 'dart:typed_data';

import 'package:excel/excel.dart';

import 'inventory_repository.dart';

const _productSheet = 'Productos';
const _categorySheet = 'Categorias';
const _instructionsSheet = 'Instrucciones';

const List<String> _productHeaders = [
  'sku',
  'nombre',
  'codigo_barras',
  'codigo_interno',
  'categoria',
  'marca',
  'modelo',
  'unidad',
  'costo',
  'precio',
  'precio_2',
  'precio_3',
  'precio_4',
  'itbis_porcentaje',
  'exento_itbis',
  'stock',
  'stock_minimo',
  'nivel_reorden',
  'stock_maximo',
  'rastrear_inventario',
  'permite_negativo',
  'es_servicio',
  'activo',
  'talla',
  'variante',
  'imagen_url',
  'notas',
];

const List<String> _instructions = [
  'Plantilla de inventario — Shop+',
  '',
  '1. La hoja "Productos" es la única que el sistema lee al importar.',
  '2. La columna "nombre", "precio" y "costo" son obligatorias.',
  '3. La columna "sku" se usa como llave: si ya existe en tu sucursal, el producto se actualiza; si no existe (o está vacío), se crea uno nuevo.',
  '4. La columna "categoria" debe coincidir (sin distinguir mayúsculas) con un nombre de la hoja "Categorias". Si la categoría no existe, la fila se rechaza.',
  '5. Los campos sí/no aceptan: si, sí, no, true, false, 1, 0.',
  '6. Los números pueden usar punto o coma como separador decimal.',
  '7. Si dejas vacíos los valores numéricos: costo=0, precio=obligatorio, itbis=18, stock=0, stock_minimo=0, nivel_reorden=0, stock_maximo=0.',
  '8. Si "exento_itbis" es sí, la columna "itbis_porcentaje" se ignora pero igual conviene dejarla en 0.',
  '9. No modifiques los nombres de columnas en la fila 1 — el sistema los usa para identificar cada campo.',
  '10. La hoja "Categorias" es solo informativa; los cambios en ella no se aplican.',
];

class InventoryImportRowError {
  InventoryImportRowError({required this.rowNumber, required this.message});

  final int rowNumber;
  final String message;
}

class InventoryImportParseResult {
  InventoryImportParseResult({
    required this.inputs,
    required this.errors,
    required this.totalRows,
  });

  final List<InventoryProductInput> inputs;
  final List<InventoryImportRowError> errors;
  final int totalRows;
}

class InventoryExcelService {
  Uint8List buildTemplate({
    required List<InventoryCategory> categories,
  }) {
    final excel = Excel.createExcel();
    _writeProductHeaders(excel);
    _writeExampleRow(excel);
    _writeCategorySheet(excel, categories);
    _writeInstructionsSheet(excel);
    excel.delete('Sheet1');
    excel.setDefaultSheet(_instructionsSheet);
    final bytes = excel.save();
    if (bytes == null) {
      throw Exception('No se pudo generar la plantilla.');
    }
    return Uint8List.fromList(bytes);
  }

  Uint8List buildExport({
    required List<InventoryProduct> products,
    required List<InventoryCategory> categories,
  }) {
    final excel = Excel.createExcel();
    _writeProductHeaders(excel);
    final sheet = excel[_productSheet];
    var row = 1;
    for (final product in products) {
      _writeProductRow(sheet, row, product);
      row++;
    }
    _writeCategorySheet(excel, categories);
    _writeInstructionsSheet(excel);
    excel.delete('Sheet1');
    excel.setDefaultSheet(_productSheet);
    final bytes = excel.save();
    if (bytes == null) {
      throw Exception('No se pudo generar el archivo de exportación.');
    }
    return Uint8List.fromList(bytes);
  }

  InventoryImportParseResult parseImport({
    required Uint8List bytes,
    required List<InventoryCategory> categories,
  }) {
    final excel = Excel.decodeBytes(bytes);
    final sheet = excel.tables[_productSheet];
    if (sheet == null) {
      throw Exception(
        'El archivo no contiene la hoja "$_productSheet". '
        'Descarga la plantilla y vuelve a intentar.',
      );
    }

    final headerRow = sheet.rows.isNotEmpty ? sheet.rows.first : const [];
    final headerIndex = <String, int>{};
    for (var i = 0; i < headerRow.length; i++) {
      final value = _cellToString(headerRow[i])?.trim().toLowerCase();
      if (value != null && value.isNotEmpty) headerIndex[value] = i;
    }

    for (final required in const ['nombre', 'precio', 'costo']) {
      if (!headerIndex.containsKey(required)) {
        throw Exception(
          'Falta la columna obligatoria "$required" en la hoja "$_productSheet".',
        );
      }
    }

    final categoryByName = <String, InventoryCategory>{
      for (final c in categories) c.name.trim().toLowerCase(): c,
    };

    final inputs = <InventoryProductInput>[];
    final errors = <InventoryImportRowError>[];
    var totalRows = 0;

    for (var i = 1; i < sheet.rows.length; i++) {
      final row = sheet.rows[i];
      if (_rowIsEmpty(row)) continue;
      totalRows++;
      final rowNumber = i + 1;

      try {
        String? cell(String key) {
          final idx = headerIndex[key];
          if (idx == null || idx >= row.length) return null;
          return _cellToString(row[idx]);
        }

        inputs.add(_rowToInput(cell, categoryByName));
      } catch (error) {
        errors.add(_rowError(rowNumber, error));
      }
    }

    return InventoryImportParseResult(
      inputs: inputs,
      errors: errors,
      totalRows: totalRows,
    );
  }

  /// Importa desde CSV (separado por coma, punto y coma o tab). El CSV nunca
  /// falla por formatos de número como el .xlsx, así que sirve de respaldo
  /// cuando un archivo de Excel da error al leerse.
  InventoryImportParseResult parseImportCsv({
    required Uint8List bytes,
    required List<InventoryCategory> categories,
  }) {
    final rows = _parseCsv(_decodeText(bytes));
    if (rows.isEmpty) {
      throw Exception('El archivo CSV está vacío.');
    }

    final headerRow = rows.first;
    final headerIndex = <String, int>{};
    for (var i = 0; i < headerRow.length; i++) {
      final value = headerRow[i].trim().toLowerCase();
      if (value.isNotEmpty) headerIndex[value] = i;
    }

    for (final required in const ['nombre', 'precio', 'costo']) {
      if (!headerIndex.containsKey(required)) {
        throw Exception(
          'Falta la columna obligatoria "$required". La primera fila del CSV '
          'debe tener los mismos encabezados que la plantilla.',
        );
      }
    }

    final categoryByName = <String, InventoryCategory>{
      for (final c in categories) c.name.trim().toLowerCase(): c,
    };

    final inputs = <InventoryProductInput>[];
    final errors = <InventoryImportRowError>[];
    var totalRows = 0;

    for (var i = 1; i < rows.length; i++) {
      final row = rows[i];
      if (row.every((c) => c.trim().isEmpty)) continue;
      totalRows++;
      final rowNumber = i + 1;

      try {
        String? cell(String key) {
          final idx = headerIndex[key];
          if (idx == null || idx >= row.length) return null;
          return row[idx];
        }

        inputs.add(_rowToInput(cell, categoryByName));
      } catch (error) {
        errors.add(_rowError(rowNumber, error));
      }
    }

    return InventoryImportParseResult(
      inputs: inputs,
      errors: errors,
      totalRows: totalRows,
    );
  }

  InventoryImportRowError _rowError(int rowNumber, Object error) {
    return InventoryImportRowError(
      rowNumber: rowNumber,
      message: error is Exception
          ? error.toString().replaceFirst('Exception: ', '')
          : error.toString(),
    );
  }

  /// Construye un [InventoryProductInput] a partir de un accesor de celdas por
  /// nombre de columna. Compartido por el lector de xlsx y el de CSV.
  InventoryProductInput _rowToInput(
    String? Function(String key) raw,
    Map<String, InventoryCategory> categoryByName,
  ) {
    String? str(String key) {
      final value = raw(key)?.trim();
      return (value == null || value.isEmpty) ? null : value;
    }

    double? dbl(String key) {
      final value = str(key);
      if (value == null) return null;
      return double.tryParse(value.replaceAll(',', '.'));
    }

    final name = str('nombre');
    if (name == null) throw Exception('"nombre" está vacío.');

    final price = dbl('precio');
    if (price == null) {
      throw Exception('"precio" está vacío o no es un número válido.');
    }
    if (price < 0) throw Exception('"precio" no puede ser negativo.');

    final cost = dbl('costo') ?? 0;
    if (cost < 0) throw Exception('"costo" no puede ser negativo.');

    final taxRate = dbl('itbis_porcentaje') ?? 18;
    if (taxRate < 0 || taxRate > 100) {
      throw Exception('"itbis_porcentaje" debe estar entre 0 y 100.');
    }

    final stock = dbl('stock') ?? 0;
    final minStock = dbl('stock_minimo') ?? 0;
    if (minStock < 0) {
      throw Exception('"stock_minimo" no puede ser negativo.');
    }
    final reorderLevel = dbl('nivel_reorden') ?? 0;
    final maxStock = dbl('stock_maximo') ?? 0;

    final categoryRaw = str('categoria');
    String? categoryId;
    if (categoryRaw != null) {
      final found = categoryByName[categoryRaw.toLowerCase()];
      if (found == null) {
        throw Exception(
          'La categoría "$categoryRaw" no existe. Crea la categoría en el sistema o corrige el nombre.',
        );
      }
      categoryId = found.id;
    }

    return InventoryProductInput(
      name: name,
      sku: str('sku'),
      barcode: str('codigo_barras'),
      internalCode: str('codigo_interno'),
      categoryId: categoryId,
      brand: str('marca'),
      model: str('modelo'),
      unit: str('unidad') ?? 'unidad',
      cost: cost,
      price: price,
      taxRate: taxRate,
      stock: stock,
      minStock: minStock,
      reorderLevel: reorderLevel,
      maxStock: maxStock,
      isActive: _parseBool(str('activo')) ?? true,
      isService: _parseBool(str('es_servicio')) ?? false,
      isTaxExempt: _parseBool(str('exento_itbis')) ?? false,
      trackInventory: _parseBool(str('rastrear_inventario')) ?? true,
      allowNegativeStock: _parseBool(str('permite_negativo')) ?? false,
      sizeLabel: str('talla'),
      variantName: str('variante'),
      imageUrl: str('imagen_url'),
      notes: str('notas'),
      priceTier1: dbl('precio_2'),
      priceTier2: dbl('precio_3'),
      priceTier3: dbl('precio_4'),
    );
  }

  /// Decodifica los bytes como UTF-8; si el archivo viene en Latin-1
  /// (Windows / Excel en algunas configuraciones), cae a esa codificación.
  String _decodeText(Uint8List bytes) {
    try {
      var text = utf8.decode(bytes);
      // Quitar BOM UTF-8 si aparece como U+FEFF.
      if (text.isNotEmpty && text.codeUnitAt(0) == 0xFEFF) {
        text = text.substring(1);
      }
      return text;
    } on FormatException {
      return latin1.decode(bytes);
    }
  }

  /// Parser CSV tolerante: detecta el separador, respeta comillas dobles con
  /// delimitadores y saltos de línea embebidos, y comillas escapadas ("").
  List<List<String>> _parseCsv(String text) {
    final delimiter = _detectDelimiter(text);
    final rows = <List<String>>[];
    var field = StringBuffer();
    var row = <String>[];
    var inQuotes = false;
    var sawAny = false;

    void endField() {
      row.add(field.toString());
      field = StringBuffer();
    }

    void endRow() {
      endField();
      rows.add(row);
      row = <String>[];
    }

    for (var i = 0; i < text.length; i++) {
      final ch = text[i];
      sawAny = true;
      if (inQuotes) {
        if (ch == '"') {
          if (i + 1 < text.length && text[i + 1] == '"') {
            field.write('"');
            i++;
          } else {
            inQuotes = false;
          }
        } else {
          field.write(ch);
        }
      } else if (ch == '"') {
        inQuotes = true;
      } else if (ch == delimiter) {
        endField();
      } else if (ch == '\n') {
        endRow();
      } else if (ch == '\r') {
        if (i + 1 >= text.length || text[i + 1] != '\n') endRow();
      } else {
        field.write(ch);
      }
    }
    if (sawAny && (field.isNotEmpty || row.isNotEmpty)) {
      endRow();
    }
    return rows;
  }

  String _detectDelimiter(String text) {
    final firstLine = const LineSplitter()
        .convert(text)
        .firstWhere((l) => l.trim().isNotEmpty, orElse: () => '');
    final candidates = {
      ',': ','.allMatches(firstLine).length,
      ';': ';'.allMatches(firstLine).length,
      '\t': '\t'.allMatches(firstLine).length,
    };
    var best = ',';
    var bestCount = -1;
    candidates.forEach((delimiter, count) {
      if (count > bestCount) {
        best = delimiter;
        bestCount = count;
      }
    });
    return best;
  }

  void _writeProductHeaders(Excel excel) {
    final sheet = excel[_productSheet];
    final headerStyle = CellStyle(
      bold: true,
      backgroundColorHex: ExcelColor.fromHexString('#0B5ED7'),
      fontColorHex: ExcelColor.fromHexString('#FFFFFF'),
      horizontalAlign: HorizontalAlign.Center,
    );
    for (var i = 0; i < _productHeaders.length; i++) {
      final cell = sheet.cell(
        CellIndex.indexByColumnRow(columnIndex: i, rowIndex: 0),
      );
      cell.value = TextCellValue(_productHeaders[i]);
      cell.cellStyle = headerStyle;
      sheet.setColumnWidth(i, _columnWidth(_productHeaders[i]));
    }
  }

  void _writeExampleRow(Excel excel) {
    final sheet = excel[_productSheet];
    final values = <dynamic>[
      'SKU-001',
      'Coca Cola 600ml',
      '7501055330034',
      '',
      '',
      'Coca Cola',
      '600ml',
      'unidad',
      45.0,
      75.0,
      72.0,
      70.0,
      68.0,
      18.0,
      'no',
      100.0,
      10.0,
      20.0,
      0.0,
      'si',
      'no',
      'no',
      'si',
      '',
      '',
      '',
      'Producto de ejemplo — bórralo antes de importar',
    ];
    for (var i = 0; i < values.length; i++) {
      sheet
              .cell(CellIndex.indexByColumnRow(columnIndex: i, rowIndex: 1))
              .value =
          _toCellValue(values[i]);
    }
  }

  void _writeProductRow(Sheet sheet, int rowIndex, InventoryProduct product) {
    final values = <dynamic>[
      product.sku ?? '',
      product.name,
      product.barcode ?? '',
      product.internalCode ?? '',
      product.categoryName ?? '',
      product.brand ?? '',
      product.model ?? '',
      product.unit,
      product.cost,
      product.price,
      product.priceTier1 ?? '',
      product.priceTier2 ?? '',
      product.priceTier3 ?? '',
      product.taxRate,
      product.isTaxExempt ? 'si' : 'no',
      product.stock,
      product.minStock,
      product.reorderLevel,
      product.maxStock,
      product.trackInventory ? 'si' : 'no',
      product.allowNegativeStock ? 'si' : 'no',
      product.isService ? 'si' : 'no',
      product.isActive ? 'si' : 'no',
      product.sizeLabel ?? '',
      product.variantName ?? '',
      product.imageUrl ?? '',
      product.notes ?? '',
    ];
    for (var i = 0; i < values.length; i++) {
      sheet
              .cell(
                CellIndex.indexByColumnRow(columnIndex: i, rowIndex: rowIndex),
              )
              .value =
          _toCellValue(values[i]);
    }
  }

  void _writeCategorySheet(Excel excel, List<InventoryCategory> categories) {
    final sheet = excel[_categorySheet];
    final headerStyle = CellStyle(
      bold: true,
      backgroundColorHex: ExcelColor.fromHexString('#0B5ED7'),
      fontColorHex: ExcelColor.fromHexString('#FFFFFF'),
    );
    final headers = ['nombre', 'id'];
    for (var i = 0; i < headers.length; i++) {
      final cell = sheet.cell(
        CellIndex.indexByColumnRow(columnIndex: i, rowIndex: 0),
      );
      cell.value = TextCellValue(headers[i]);
      cell.cellStyle = headerStyle;
    }
    sheet.setColumnWidth(0, 32);
    sheet.setColumnWidth(1, 38);

    for (var i = 0; i < categories.length; i++) {
      sheet
              .cell(
                CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: i + 1),
              )
              .value =
          TextCellValue(categories[i].name);
      sheet
              .cell(
                CellIndex.indexByColumnRow(columnIndex: 1, rowIndex: i + 1),
              )
              .value =
          TextCellValue(categories[i].id);
    }
  }

  void _writeInstructionsSheet(Excel excel) {
    final sheet = excel[_instructionsSheet];
    sheet.setColumnWidth(0, 110);
    final titleStyle = CellStyle(bold: true, fontSize: 14);
    for (var i = 0; i < _instructions.length; i++) {
      final cell = sheet.cell(
        CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: i),
      );
      cell.value = TextCellValue(_instructions[i]);
      if (i == 0) cell.cellStyle = titleStyle;
    }
  }

  CellValue? _toCellValue(dynamic value) {
    if (value == null || (value is String && value.isEmpty)) {
      return TextCellValue('');
    }
    if (value is bool) return BoolCellValue(value);
    if (value is int) return IntCellValue(value);
    if (value is double) return DoubleCellValue(value);
    return TextCellValue(value.toString());
  }

  double _columnWidth(String header) {
    switch (header) {
      case 'sku':
      case 'codigo_barras':
      case 'codigo_interno':
        return 18;
      case 'nombre':
      case 'notas':
      case 'imagen_url':
        return 32;
      case 'categoria':
      case 'marca':
      case 'modelo':
        return 18;
      default:
        return 14;
    }
  }

  bool _rowIsEmpty(List<Data?> row) {
    for (final cell in row) {
      final text = _cellToString(cell)?.trim();
      if (text != null && text.isNotEmpty) return false;
    }
    return true;
  }

  String? _cellToString(Data? cell) {
    final value = cell?.value;
    if (value == null) return null;
    if (value is TextCellValue) return value.value.text;
    if (value is IntCellValue) return value.value.toString();
    if (value is DoubleCellValue) return value.value.toString();
    if (value is BoolCellValue) return value.value ? 'true' : 'false';
    if (value is FormulaCellValue) return value.formula;
    return value.toString();
  }

  bool? _parseBool(String? value) {
    final raw = value?.trim().toLowerCase();
    if (raw == null || raw.isEmpty) return null;
    if (const ['si', 'sí', 'yes', 'y', 'true', '1', 'verdadero', 'verdad']
        .contains(raw)) {
      return true;
    }
    if (const ['no', 'n', 'false', '0', 'falso'].contains(raw)) {
      return false;
    }
    return null;
  }
}
