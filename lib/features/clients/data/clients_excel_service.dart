// Servicio de import/export Excel para clientes (F10).
//
// Modelado siguiendo el patrón de `inventory_excel_service.dart`:
//   - 1 hoja "Clientes" con headers fijos en la fila 1.
//   - 1 hoja "Instrucciones" para usuario final.
//   - Llave de upsert: `documento_numero` si está; si no, no se hace match
//     (siempre se crea fila nueva).
//
// La columna `nombre` es la única obligatoria. Todo lo demás tiene defaults.

import 'dart:typed_data';

import 'package:excel/excel.dart';

import 'clients_repository.dart';

const _clientsSheet = 'Clientes';
const _instructionsSheet = 'Instrucciones';

const List<String> _clientHeaders = [
  'nombre',
  'tipo_entidad',
  'nombre_legal',
  'email',
  'telefono',
  'telefono_alternativo',
  'direccion',
  'ciudad',
  'provincia',
  'pais',
  'documento_tipo',
  'documento_numero',
  'tier_precio',
  'limite_credito',
  'exento_itbis',
  'cobra_itbis',
  'comentarios',
  'activo',
];

const List<String> _instructions = [
  'Plantilla de Clientes — Shop+',
  '',
  '1. La hoja "Clientes" es la única que el sistema lee al importar.',
  '2. La columna "nombre" es obligatoria.',
  '3. Si "documento_numero" coincide con un cliente existente en tu sucursal, se ACTUALIZA. Si no, se crea uno nuevo.',
  '4. "tipo_entidad" acepta: persona, empresa, gobierno. Default: persona.',
  '5. "documento_tipo" acepta: cedula, rnc, passport (en minúsculas).',
  '6. "tier_precio" acepta: retail, tier_1, tier_2, tier_3. Default: retail.',
  '7. Los campos sí/no aceptan: si, sí, no, true, false, 1, 0.',
  '8. "limite_credito" en RD\$ (sólo el monto, sin símbolo).',
  '9. "pais" usa código ISO de 2 letras (DO, US, MX, …). Default: DO.',
  '10. No modifiques los nombres de columnas en la fila 1.',
];

class ClientImportRowError {
  ClientImportRowError({required this.rowNumber, required this.message});

  final int rowNumber;
  final String message;
}

class ClientImportParseResult {
  ClientImportParseResult({
    required this.inputs,
    required this.errors,
    required this.totalRows,
  });

  final List<ClientInput> inputs;
  final List<ClientImportRowError> errors;
  final int totalRows;
}

class ClientsExcelService {
  Uint8List buildTemplate() {
    final excel = Excel.createExcel();
    _writeHeaders(excel);
    _writeExampleRow(excel);
    _writeInstructionsSheet(excel);
    excel.delete('Sheet1');
    excel.setDefaultSheet(_instructionsSheet);
    final bytes = excel.save();
    if (bytes == null) {
      throw Exception('No se pudo generar la plantilla.');
    }
    return Uint8List.fromList(bytes);
  }

  Uint8List buildExport({required List<ClientEntity> clients}) {
    final excel = Excel.createExcel();
    _writeHeaders(excel);
    final sheet = excel[_clientsSheet];
    var row = 1;
    for (final c in clients) {
      _writeClientRow(sheet, row, c);
      row++;
    }
    _writeInstructionsSheet(excel);
    excel.delete('Sheet1');
    excel.setDefaultSheet(_clientsSheet);
    final bytes = excel.save();
    if (bytes == null) {
      throw Exception('No se pudo generar el archivo.');
    }
    return Uint8List.fromList(bytes);
  }

  /// Parsea el Excel a `ClientInput` con un `id` que viene del cliente
  /// existente en la sucursal (match por `documento_numero`). Si no hay
  /// match, queda con `id = null` → INSERT.
  ClientImportParseResult parseImport({
    required Uint8List bytes,
    required List<ClientEntity> existingClients,
  }) {
    final excel = Excel.decodeBytes(bytes);
    final sheet = excel.tables[_clientsSheet];
    if (sheet == null) {
      throw Exception(
        'El archivo no contiene la hoja "$_clientsSheet". '
        'Descarga la plantilla y vuelve a intentar.',
      );
    }

    final headerRow = sheet.rows.isNotEmpty ? sheet.rows.first : const [];
    final headerIndex = <String, int>{};
    for (var i = 0; i < headerRow.length; i++) {
      final value = _cellToString(headerRow[i])?.trim().toLowerCase();
      if (value != null && value.isNotEmpty) headerIndex[value] = i;
    }

    if (!headerIndex.containsKey('nombre')) {
      throw Exception(
        'Falta la columna obligatoria "nombre" en la hoja "$_clientsSheet".',
      );
    }

    final existingByDoc = <String, ClientEntity>{
      for (final c in existingClients)
        if ((c.documentNumber ?? '').isNotEmpty)
          (c.documentNumber!).trim().toLowerCase(): c,
    };

    final inputs = <ClientInput>[];
    final errors = <ClientImportRowError>[];
    var totalRows = 0;

    for (var i = 1; i < sheet.rows.length; i++) {
      final row = sheet.rows[i];
      if (_rowIsEmpty(row)) continue;
      totalRows++;
      final rowNumber = i + 1;

      try {
        final name = _readString(row, headerIndex, 'nombre');
        if (name == null || name.isEmpty) {
          throw Exception('"nombre" está vacío.');
        }

        final entityRaw =
            _readString(row, headerIndex, 'tipo_entidad')?.toLowerCase() ??
                'persona';
        final entityType = _mapEntityType(entityRaw);

        final docNumber = _readString(row, headerIndex, 'documento_numero');
        final docType = _readString(row, headerIndex, 'documento_tipo');

        final tierRaw = _readString(row, headerIndex, 'tier_precio')
                ?.toLowerCase() ??
            'retail';
        final tier = const {
          'retail',
          'tier_1',
          'tier_2',
          'tier_3',
        }.contains(tierRaw)
            ? tierRaw
            : 'retail';

        final creditLimit =
            _readDouble(row, headerIndex, 'limite_credito') ?? 0;
        if (creditLimit < 0) {
          throw Exception('"limite_credito" no puede ser negativo.');
        }

        // Match contra existentes por documento
        String? existingId;
        if (docNumber != null && docNumber.isNotEmpty) {
          existingId =
              existingByDoc[docNumber.trim().toLowerCase()]?.id;
        }

        inputs.add(
          ClientInput(
            id: existingId,
            fullName: name,
            entityType: entityType,
            firstName: _readString(row, headerIndex, 'nombre_legal') == null
                ? null
                : null, // No tenemos columna; se queda null.
            companyName:
                entityType == 'company' ? name : null,
            legalName: _readString(row, headerIndex, 'nombre_legal'),
            email: _readString(row, headerIndex, 'email'),
            phone: _readString(row, headerIndex, 'telefono'),
            secondaryPhone:
                _readString(row, headerIndex, 'telefono_alternativo'),
            address: _readString(row, headerIndex, 'direccion'),
            city: _readString(row, headerIndex, 'ciudad'),
            province: _readString(row, headerIndex, 'provincia'),
            countryCode:
                (_readString(row, headerIndex, 'pais') ?? 'DO').toUpperCase(),
            documentType: docType,
            documentNumber: docNumber,
            creditLimit: creditLimit,
            priceTier: tier,
            taxExempt: _readBool(row, headerIndex, 'exento_itbis') ?? false,
            chargeItbis: _readBool(row, headerIndex, 'cobra_itbis') ?? true,
            comments: _readString(row, headerIndex, 'comentarios'),
            isActive: _readBool(row, headerIndex, 'activo') ?? true,
          ),
        );
      } catch (error) {
        errors.add(
          ClientImportRowError(
            rowNumber: rowNumber,
            message: error is Exception
                ? error.toString().replaceFirst('Exception: ', '')
                : error.toString(),
          ),
        );
      }
    }

    return ClientImportParseResult(
      inputs: inputs,
      errors: errors,
      totalRows: totalRows,
    );
  }

  // ─── Internals ────────────────────────────────────────────────────────

  void _writeHeaders(Excel excel) {
    final sheet = excel[_clientsSheet];
    for (var i = 0; i < _clientHeaders.length; i++) {
      final cell = sheet.cell(
        CellIndex.indexByColumnRow(columnIndex: i, rowIndex: 0),
      );
      cell.value = TextCellValue(_clientHeaders[i]);
      cell.cellStyle = CellStyle(bold: true);
    }
  }

  void _writeExampleRow(Excel excel) {
    final sheet = excel[_clientsSheet];
    final example = <String, String>{
      'nombre': 'Cliente Ejemplo SRL',
      'tipo_entidad': 'empresa',
      'nombre_legal': 'Cliente Ejemplo Sociedad de Responsabilidad Limitada',
      'email': 'cliente@ejemplo.com',
      'telefono': '809-555-0100',
      'telefono_alternativo': '829-555-0101',
      'direccion': 'Av. Principal #123, Edif. Plaza, Piso 2',
      'ciudad': 'Santo Domingo',
      'provincia': 'Distrito Nacional',
      'pais': 'DO',
      'documento_tipo': 'rnc',
      'documento_numero': '130123456',
      'tier_precio': 'retail',
      'limite_credito': '50000',
      'exento_itbis': 'no',
      'cobra_itbis': 'si',
      'comentarios': 'Cliente recurrente',
      'activo': 'si',
    };
    for (var i = 0; i < _clientHeaders.length; i++) {
      final cell = sheet.cell(
        CellIndex.indexByColumnRow(columnIndex: i, rowIndex: 1),
      );
      cell.value = TextCellValue(example[_clientHeaders[i]] ?? '');
    }
  }

  void _writeClientRow(Sheet sheet, int row, ClientEntity c) {
    final values = <String, String>{
      'nombre': c.fullName,
      'tipo_entidad': _entityTypeToLabel(c.entityType),
      'nombre_legal': c.legalName ?? '',
      'email': c.email ?? '',
      'telefono': c.phone ?? '',
      'telefono_alternativo': c.secondaryPhone ?? '',
      'direccion': c.address ?? '',
      'ciudad': c.city ?? '',
      'provincia': c.province ?? '',
      'pais': c.countryCode,
      'documento_tipo': c.documentType ?? '',
      'documento_numero': c.documentNumber ?? '',
      'tier_precio': c.priceTier,
      'limite_credito': c.creditLimit.toStringAsFixed(2),
      'exento_itbis': c.taxExempt ? 'si' : 'no',
      'cobra_itbis': c.chargeItbis ? 'si' : 'no',
      'comentarios': c.comments ?? '',
      'activo': c.isActive ? 'si' : 'no',
    };
    for (var i = 0; i < _clientHeaders.length; i++) {
      final cell = sheet.cell(
        CellIndex.indexByColumnRow(columnIndex: i, rowIndex: row),
      );
      cell.value = TextCellValue(values[_clientHeaders[i]] ?? '');
    }
  }

  void _writeInstructionsSheet(Excel excel) {
    final sheet = excel[_instructionsSheet];
    for (var i = 0; i < _instructions.length; i++) {
      final cell = sheet.cell(
        CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: i),
      );
      cell.value = TextCellValue(_instructions[i]);
      if (i == 0) {
        cell.cellStyle = CellStyle(bold: true, fontSize: 14);
      }
    }
  }

  String _mapEntityType(String raw) {
    switch (raw) {
      case 'empresa':
      case 'company':
        return 'company';
      case 'gobierno':
      case 'government':
        return 'government';
      case 'persona':
      case 'person':
      default:
        return 'person';
    }
  }

  String _entityTypeToLabel(String t) {
    switch (t) {
      case 'company':
        return 'empresa';
      case 'government':
        return 'gobierno';
      default:
        return 'persona';
    }
  }

  String? _cellToString(Data? cell) {
    if (cell == null) return null;
    final value = cell.value;
    if (value == null) return null;
    if (value is TextCellValue) return value.value.text;
    if (value is IntCellValue) return value.value.toString();
    if (value is DoubleCellValue) return value.value.toString();
    if (value is BoolCellValue) return value.value.toString();
    if (value is DateCellValue) {
      return '${value.year.toString().padLeft(4, '0')}-'
          '${value.month.toString().padLeft(2, '0')}-'
          '${value.day.toString().padLeft(2, '0')}';
    }
    return value.toString();
  }

  bool _rowIsEmpty(List<Data?> row) {
    for (final cell in row) {
      final v = _cellToString(cell)?.trim();
      if (v != null && v.isNotEmpty) return false;
    }
    return true;
  }

  String? _readString(
    List<Data?> row,
    Map<String, int> idx,
    String key,
  ) {
    final col = idx[key];
    if (col == null || col >= row.length) return null;
    final raw = _cellToString(row[col])?.trim();
    if (raw == null || raw.isEmpty) return null;
    return raw;
  }

  double? _readDouble(
    List<Data?> row,
    Map<String, int> idx,
    String key,
  ) {
    final raw = _readString(row, idx, key);
    if (raw == null) return null;
    return double.tryParse(raw.replaceAll(',', '.'));
  }

  bool? _readBool(
    List<Data?> row,
    Map<String, int> idx,
    String key,
  ) {
    final raw = _readString(row, idx, key)?.toLowerCase();
    if (raw == null) return null;
    if (const {'si', 'sí', 'true', '1', 'y', 'yes'}.contains(raw)) return true;
    if (const {'no', 'false', '0', 'n'}.contains(raw)) return false;
    return null;
  }
}
