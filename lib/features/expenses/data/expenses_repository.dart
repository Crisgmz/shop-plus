import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../shared/io/storage_image_loader.dart';
import '../../printing/data/printing.dart';

class ExpenseSupplier {
  ExpenseSupplier({required this.id, required this.name});

  final String id;
  final String name;

  factory ExpenseSupplier.fromMap(Map<String, dynamic> map) {
    return ExpenseSupplier(
      id: (map['id'] ?? '').toString(),
      name: (map['legal_name'] ?? '').toString(),
    );
  }
}

class ExpenseEntity {
  ExpenseEntity({
    required this.id,
    required this.category,
    required this.description,
    required this.paymentMethod,
    required this.amount,
    required this.expenseDate,
    required this.supplierName,
    this.supplierId,
  });

  final String id;
  final String category;
  final String? description;
  final String paymentMethod;
  final double amount;
  final DateTime expenseDate;
  final String? supplierName;
  final String? supplierId;

  factory ExpenseEntity.fromMap(
    Map<String, dynamic> map,
    Map<String, String> suppliersById,
  ) {
    final supplierId = map['supplier_id']?.toString();

    return ExpenseEntity(
      id: (map['id'] ?? '').toString(),
      category: (map['category'] ?? '').toString(),
      description: map['description']?.toString(),
      paymentMethod: (map['payment_method'] ?? '').toString(),
      amount: _toDouble(map['amount']),
      expenseDate:
          DateTime.tryParse((map['expense_date'] ?? '').toString()) ??
          DateTime.fromMillisecondsSinceEpoch(0),
      supplierName: supplierId == null ? null : suppliersById[supplierId],
      supplierId: supplierId,
    );
  }
}

class ExpenseInput {
  ExpenseInput({
    required this.category,
    required this.paymentMethod,
    required this.amount,
    required this.expenseDate,
    this.description,
    this.supplierId,
  });

  final String category;
  final String paymentMethod;
  final double amount;
  final DateTime expenseDate;
  final String? description;
  final String? supplierId;
}

class ExpensesRepository {
  ExpensesRepository(this._client);

  final SupabaseClient _client;

  Future<List<ExpenseSupplier>> fetchSuppliers() async {
    final branchId = await _currentBranchId();
    if (branchId == null) return const [];

    final rows = await _client
        .from('suppliers')
        .select('id, legal_name')
        .eq('branch_id', branchId)
        .eq('is_active', true)
        .order('legal_name');

    return rows
        .map(
          (item) =>
              ExpenseSupplier.fromMap(Map<String, dynamic>.from(item as Map)),
        )
        .toList(growable: false);
  }

  Future<List<ExpenseEntity>> fetchExpenses() async {
    final branchId = await _currentBranchId();
    if (branchId == null) return const [];

    final suppliers = await fetchSuppliers();
    final suppliersById = {
      for (final supplier in suppliers) supplier.id: supplier.name,
    };

    final rows = await _client
        .from('expenses')
        .select(
          'id, supplier_id, category, description, payment_method, amount, expense_date',
        )
        .eq('branch_id', branchId)
        .order('expense_date', ascending: false)
        .limit(100);

    return rows
        .map(
          (item) => ExpenseEntity.fromMap(
            Map<String, dynamic>.from(item as Map),
            suppliersById,
          ),
        )
        .toList(growable: false);
  }

  /// [cashSessionId]: la caja ACTIVA del POS (activeCashSessionIdProvider).
  /// Si se pasa, el gasto se imputa a esa caja para que aparezca en su cuadre.
  /// Si es null, cae a la última caja abierta del usuario (compatibilidad).
  Future<void> createExpense(
    ExpenseInput input, {
    String? cashSessionId,
  }) async {
    final branchId = await _currentBranchId();
    if (branchId == null) {
      throw Exception('No hay sucursal asignada para este usuario.');
    }

    if (input.amount <= 0) {
      throw Exception('El monto debe ser mayor que 0.');
    }

    final resolvedSessionId = (cashSessionId != null && cashSessionId.isNotEmpty)
        ? cashSessionId
        : await _currentOpenCashSessionId(branchId);

    await _client.from('expenses').insert({
      'branch_id': branchId,
      'cash_session_id': resolvedSessionId,
      'supplier_id': _nullIfEmpty(input.supplierId),
      'category': input.category.trim(),
      'description': _nullIfEmpty(input.description),
      'payment_method': input.paymentMethod,
      'amount': _round2(input.amount),
      'expense_date': input.expenseDate.toIso8601String().split('T').first,
    });
  }

  /// Edita un gasto existente. Verifica que la fila se actualizó (bajo RLS
  /// `expenses_update` exige poder operar el POS).
  Future<void> updateExpense(String id, ExpenseInput input) async {
    final branchId = await _currentBranchId();
    if (branchId == null) {
      throw Exception('No hay sucursal asignada para este usuario.');
    }
    if (input.amount <= 0) {
      throw Exception('El monto debe ser mayor que 0.');
    }

    final updated = await _client
        .from('expenses')
        .update({
          'supplier_id': _nullIfEmpty(input.supplierId),
          'category': input.category.trim(),
          'description': _nullIfEmpty(input.description),
          'payment_method': input.paymentMethod,
          'amount': _round2(input.amount),
          'expense_date': input.expenseDate.toIso8601String().split('T').first,
        })
        .eq('id', id)
        .eq('branch_id', branchId)
        .select('id');

    if ((updated as List).isEmpty) {
      throw Exception('No se pudo editar el gasto (permiso denegado).');
    }
  }

  /// Elimina un gasto. Verifica el borrado: bajo RLS `expenses_delete` exige rol
  /// que pueda administrar datos de sucursal (supervisor/admin). Si no, el
  /// DELETE afecta 0 filas sin lanzar error.
  Future<void> deleteExpense(String id) async {
    final branchId = await _currentBranchId();
    if (branchId == null) {
      throw Exception('No hay sucursal asignada para este usuario.');
    }

    final deleted = await _client
        .from('expenses')
        .delete()
        .eq('id', id)
        .eq('branch_id', branchId)
        .select('id');

    if ((deleted as List).isEmpty) {
      throw Exception(
        'No se pudo eliminar el gasto. Es posible que no tengas permiso '
        '(eliminar requiere rol de supervisor o administrador).',
      );
    }
  }

  /// Prepara el comprobante de gasto (egreso) listo para imprimir, reutilizando
  /// el diálogo/builder de impresión existentes.
  Future<PreparedPrintJobData> prepareExpenseReceipt(String expenseId) async {
    final branchId = await _currentBranchId();
    if (branchId == null) {
      throw Exception('No hay sucursal asignada para este usuario.');
    }

    final expense = await _client
        .from('expenses')
        .select(
          'id, supplier_id, category, description, payment_method, amount, expense_date',
        )
        .eq('id', expenseId)
        .eq('branch_id', branchId)
        .single();

    final amount = _toDouble(expense['amount']);
    final category = (expense['category'] ?? '').toString();
    final description = expense['description']?.toString();
    final method = (expense['payment_method'] ?? '').toString();
    final expenseDate =
        DateTime.tryParse((expense['expense_date'] ?? '').toString()) ??
        DateTime.now();
    final supplierId = expense['supplier_id']?.toString();

    // Emisor: sucursal + app_settings + logo.
    final branchRows = await _client
        .from('branches')
        .select('name, address, phone')
        .eq('id', branchId)
        .limit(1);
    final branch = branchRows.isEmpty
        ? const <String, dynamic>{}
        : Map<String, dynamic>.from(branchRows.first as Map);

    final settingsRows = await _client.from('app_settings').select().limit(1);
    final settings = settingsRows.isEmpty
        ? const <String, dynamic>{}
        : Map<String, dynamic>.from(settingsRows.first as Map);
    final logoBytes = await downloadStorageImageBytes(
      _client,
      settings['company_logo_url']?.toString(),
    );

    // Proveedor / beneficiario (si aplica).
    String? supplierName;
    if (supplierId != null && supplierId.isNotEmpty) {
      final rows = await _client
          .from('suppliers')
          .select('legal_name')
          .eq('id', supplierId)
          .eq('branch_id', branchId)
          .limit(1);
      if (rows.isNotEmpty) {
        supplierName = (rows.first as Map)['legal_name']?.toString();
      }
    }

    final noteParts = <String>[
      if (supplierName != null && supplierName.trim().isNotEmpty)
        'Proveedor: $supplierName',
      if (description != null && description.trim().isNotEmpty) description,
    ];

    final document = PrintDocumentData(
      documentType: PrintDocumentType.expenseVoucher,
      documentNumber:
          'GASTO-${expenseId.replaceAll('-', '').substring(0, 8).toUpperCase()}',
      issuedAt: expenseDate,
      branch: PrintBranchIdentity(
        name: (branch['name'] ?? 'Sucursal').toString(),
        address: _expenseFirstNonEmpty([
          settings['company_address'],
          branch['address'],
        ]),
        phone: _expenseFirstNonEmpty([
          settings['company_phone'],
          branch['phone'],
        ]),
        taxId: _expenseFirstNonEmpty([settings['company_tax_id']]),
        logoBytes: logoBytes,
      ),
      receiptTypeLabel: 'COMPROBANTE DE GASTO',
      showTax: false,
      showBarcode: settings['receipt_hide_barcode'] != true,
      footerMessage: 'Comprobante de egreso',
      notes: noteParts.isEmpty ? null : noteParts.join(' · '),
      items: [
        PrintDocumentItem(
          description: category.isEmpty ? 'Gasto operativo' : category,
          quantity: 1,
          unitPrice: amount,
          lineSubtotal: amount,
          lineTax: 0,
          lineTotal: amount,
        ),
      ],
      payments: [
        PrintPaymentLine(
          method: _expenseMethodLabel(method),
          amount: amount,
        ),
      ],
      totals: PrintTotals(
        subtotal: amount,
        tax: 0,
        total: amount,
        paid: amount,
      ),
      extra: <String, dynamic>{
        'source_table': 'expenses',
        'source_id': expenseId,
        'branch_id': branchId,
      },
    );

    return PreparedPrintJobData(
      document: document,
      paperSize: PrintPaperSize.thermal80mm,
      job: PrintJobDraft(
        branchId: branchId,
        documentType: PrintDocumentType.expenseVoucher,
        paperSize: PrintPaperSize.thermal80mm,
        sourceTable: 'expenses',
        sourceId: expenseId,
        payload: document.extra,
      ),
      dispatchPayload: const <String, dynamic>{},
    );
  }

  /// Sesión de caja abierta DEL USUARIO ACTUAL (multi-caja).
  Future<String?> _currentOpenCashSessionId(String branchId) async {
    final userId = _client.auth.currentUser?.id;
    if (userId == null) return null;
    final rows = await _client
        .from('cash_sessions')
        .select('id')
        .eq('branch_id', branchId)
        .eq('status', 'open')
        .eq('opened_by', userId)
        .order('opened_at', ascending: false)
        .limit(1);

    if (rows.isEmpty) return null;
    return (rows.first as Map)['id']?.toString();
  }

  Future<String?> _currentBranchId() async {
    final result = await _client.rpc('current_branch_id');
    if (result == null) return null;
    final value = result.toString();
    return value.isEmpty ? null : value;
  }
}

String? _nullIfEmpty(String? value) {
  if (value == null) return null;
  final trimmed = value.trim();
  return trimmed.isEmpty ? null : trimmed;
}

/// Primer valor no vacío de la lista (para el comprobante de gasto).
String? _expenseFirstNonEmpty(List<dynamic> values) {
  for (final v in values) {
    final s = v?.toString().trim();
    if (s != null && s.isNotEmpty) return s;
  }
  return null;
}

/// Método de pago en español para el comprobante de gasto.
String _expenseMethodLabel(String value) {
  switch (value) {
    case 'cash':
      return 'Efectivo';
    case 'card':
      return 'Tarjeta';
    case 'transfer':
      return 'Transferencia';
    case 'mobile':
      return 'Pago móvil';
    default:
      return value.trim().isEmpty ? 'Pago' : value;
  }
}

double _toDouble(dynamic value) {
  if (value == null) return 0;
  if (value is double) return value;
  if (value is int) return value.toDouble();
  return double.tryParse(value.toString()) ?? 0;
}

double _round2(double value) => (value * 100).roundToDouble() / 100;
