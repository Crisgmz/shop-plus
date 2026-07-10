import 'package:supabase_flutter/supabase_flutter.dart';

/// Compra con saldo pendiente de pago a un proveedor (cuenta por pagar).
/// Espejo de `ReceivableSale` del módulo de Cuentas por Cobrar.
class PayablePurchase {
  PayablePurchase({
    required this.id,
    required this.purchaseNumber,
    required this.invoiceNumber,
    required this.purchaseDate,
    required this.supplierId,
    required this.supplierName,
    required this.totalAmount,
    required this.paidAmount,
    required this.balanceDue,
    required this.status,
    required this.dueDate,
  });

  final String id;
  final String purchaseNumber;
  final String? invoiceNumber;
  final DateTime purchaseDate;
  final String? supplierId;
  final String supplierName;
  final double totalAmount;
  final double paidAmount;
  final double balanceDue;
  final String status;

  /// Fecha de vencimiento del crédito con el proveedor (null si es de contado
  /// o una compra vieja sin migrar).
  final DateTime? dueDate;

  int? get daysUntilDue {
    if (dueDate == null) return null;
    final today = DateTime.now();
    final t = DateTime(today.year, today.month, today.day);
    final d = DateTime(dueDate!.year, dueDate!.month, dueDate!.day);
    return d.difference(t).inDays;
  }

  bool get isOverdue {
    final d = daysUntilDue;
    return d != null && d < 0;
  }

  bool isNearDue(int warnDays) {
    final d = daysUntilDue;
    return d != null && d >= 0 && d <= warnDays;
  }

  factory PayablePurchase.fromMap(
    Map<String, dynamic> map,
    Map<String, String> suppliersById,
  ) {
    final supplierId = map['supplier_id']?.toString();
    final rawDue = map['due_date']?.toString();

    return PayablePurchase(
      id: (map['id'] ?? '').toString(),
      purchaseNumber: (map['purchase_number'] ?? '-').toString(),
      invoiceNumber: map['invoice_number']?.toString(),
      purchaseDate:
          DateTime.tryParse((map['purchase_date'] ?? '').toString()) ??
          DateTime.fromMillisecondsSinceEpoch(0),
      supplierId: supplierId,
      supplierName: supplierId == null
          ? 'Proveedor general'
          : (suppliersById[supplierId] ?? 'Proveedor general'),
      totalAmount: _toDouble(map['total_amount']),
      paidAmount: _toDouble(map['paid_amount']),
      balanceDue: _toDouble(map['balance_due']),
      status: (map['status'] ?? '').toString(),
      dueDate: rawDue == null || rawDue.isEmpty
          ? null
          : DateTime.tryParse(rawDue),
    );
  }
}

/// Abono registrado a un proveedor. Espejo de `ReceivedPayment`.
class SupplierPaymentRow {
  SupplierPaymentRow({
    required this.id,
    required this.purchaseId,
    required this.purchaseNumber,
    required this.supplierName,
    required this.amount,
    required this.paymentMethod,
    required this.paidAt,
    required this.reference,
  });

  final String id;
  final String? purchaseId;
  final String purchaseNumber;
  final String supplierName;
  final double amount;
  final String paymentMethod;
  final DateTime paidAt;
  final String? reference;

  factory SupplierPaymentRow.fromMap(
    Map<String, dynamic> map,
    Map<String, String> suppliersById,
    Map<String, String> purchasesById,
  ) {
    final supplierId = map['supplier_id']?.toString();
    final purchaseId = map['purchase_id']?.toString();

    return SupplierPaymentRow(
      id: (map['id'] ?? '').toString(),
      purchaseId: purchaseId,
      purchaseNumber: purchaseId == null ? '-' : (purchasesById[purchaseId] ?? '-'),
      supplierName: supplierId == null
          ? 'Proveedor general'
          : (suppliersById[supplierId] ?? 'Proveedor general'),
      amount: _toDouble(map['amount']),
      paymentMethod: (map['payment_method'] ?? '').toString(),
      paidAt:
          DateTime.tryParse((map['paid_at'] ?? '').toString()) ??
          DateTime.fromMillisecondsSinceEpoch(0),
      reference: map['reference']?.toString(),
    );
  }
}

class PayablePaymentInput {
  PayablePaymentInput({
    required this.purchaseId,
    required this.amount,
    required this.paymentMethod,
    this.reference,
    this.notes,
  });

  final String purchaseId;
  final double amount;
  final String paymentMethod;
  final String? reference;
  final String? notes;
}

class PayablesRepository {
  PayablesRepository(this._client);

  final SupabaseClient _client;

  Future<List<PayablePurchase>> fetchPayables() async {
    final branchId = await _currentBranchId();
    if (branchId == null) return const [];

    final suppliersById = await _loadSuppliersById(branchId);

    final rows = await _client
        .from('purchases')
        .select(
          'id, purchase_number, invoice_number, purchase_date, supplier_id, '
          'total_amount, paid_amount, balance_due, status, due_date',
        )
        .eq('branch_id', branchId)
        .gt('balance_due', 0)
        .neq('status', 'cancelled')
        .order('due_date', ascending: true, nullsFirst: false)
        .order('purchase_date', ascending: false);

    return rows
        .map(
          (item) => PayablePurchase.fromMap(
            Map<String, dynamic>.from(item as Map),
            suppliersById,
          ),
        )
        .toList(growable: false);
  }

  Future<List<SupplierPaymentRow>> fetchSupplierPayments() async {
    final branchId = await _currentBranchId();
    if (branchId == null) return const [];

    final suppliersById = await _loadSuppliersById(branchId);
    final purchasesById = await _loadPurchasesById(branchId);

    final rows = await _client
        .from('supplier_payments')
        .select(
          'id, purchase_id, supplier_id, amount, payment_method, paid_at, reference',
        )
        .eq('branch_id', branchId)
        .order('paid_at', ascending: false)
        .limit(30);

    return rows
        .map(
          (item) => SupplierPaymentRow.fromMap(
            Map<String, dynamic>.from(item as Map),
            suppliersById,
            purchasesById,
          ),
        )
        .toList(growable: false);
  }

  Future<void> registerPayment(PayablePaymentInput input) async {
    final branchId = await _currentBranchId();
    if (branchId == null) {
      throw Exception('No hay sucursal asignada para este usuario.');
    }

    final purchase = await _client
        .from('purchases')
        .select('id, supplier_id, paid_amount, balance_due, total_amount')
        .eq('id', input.purchaseId)
        .eq('branch_id', branchId)
        .single();

    final currentBalance = _toDouble(purchase['balance_due']);
    if (currentBalance <= 0) {
      throw Exception('La compra no tiene saldo pendiente.');
    }
    if (input.amount <= 0) {
      throw Exception('El monto debe ser mayor que 0.');
    }
    if (input.amount > currentBalance) {
      throw Exception('El abono no puede exceder el saldo pendiente.');
    }

    final supplierId = purchase['supplier_id']?.toString();
    final openCashSessionId = await _currentOpenCashSessionId(branchId);

    await _client.from('supplier_payments').insert({
      'branch_id': branchId,
      'purchase_id': input.purchaseId,
      'supplier_id': supplierId,
      'cash_session_id': openCashSessionId,
      'payment_method': input.paymentMethod,
      'amount': input.amount,
      'paid_at': DateTime.now().toUtc().toIso8601String(),
      'reference': _nullIfEmpty(input.reference),
      'notes': _nullIfEmpty(input.notes),
    });

    final nextPaid = _round2(_toDouble(purchase['paid_amount']) + input.amount);
    final nextBalance = _round2(currentBalance - input.amount);

    await _client
        .from('purchases')
        .update({
          'paid_amount': nextPaid,
          'balance_due': nextBalance,
        })
        .eq('id', input.purchaseId)
        .eq('branch_id', branchId);

    // Rollup del saldo total adeudado al proveedor (como clients.balance_due).
    if (supplierId != null) {
      final supplierPurchases = await _client
          .from('purchases')
          .select('balance_due')
          .eq('branch_id', branchId)
          .eq('supplier_id', supplierId)
          .gt('balance_due', 0)
          .neq('status', 'cancelled');

      final supplierBalance = _round2(
        supplierPurchases.fold<double>(
          0,
          (sum, row) => sum + _toDouble((row as Map)['balance_due']),
        ),
      );

      await _client
          .from('suppliers')
          .update({'balance_due': supplierBalance})
          .eq('id', supplierId)
          .eq('branch_id', branchId);
    }
  }

  Future<Map<String, String>> _loadSuppliersById(String branchId) async {
    final rows = await _client
        .from('suppliers')
        .select('id, legal_name, trade_name')
        .eq('branch_id', branchId)
        .order('legal_name');

    return {
      for (final row in rows)
        (row['id'] ?? '').toString(): _supplierName(row as Map),
    };
  }

  Future<Map<String, String>> _loadPurchasesById(String branchId) async {
    final rows = await _client
        .from('purchases')
        .select('id, purchase_number')
        .eq('branch_id', branchId)
        .order('purchase_date', ascending: false)
        .limit(200);

    return {
      for (final row in rows)
        (row['id'] ?? '').toString():
            (row['purchase_number'] ?? '-').toString(),
    };
  }

  Future<String?> _currentBranchId() async {
    final result = await _client.rpc('current_branch_id');
    if (result == null) return null;
    final value = result.toString();
    return value.isEmpty ? null : value;
  }

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
}

String _supplierName(Map row) {
  final trade = (row['trade_name'] ?? '').toString().trim();
  final legal = (row['legal_name'] ?? '').toString().trim();
  if (trade.isNotEmpty) return trade;
  if (legal.isNotEmpty) return legal;
  return 'Proveedor';
}

String? _nullIfEmpty(String? value) {
  if (value == null) return null;
  final trimmed = value.trim();
  return trimmed.isEmpty ? null : trimmed;
}

double _toDouble(dynamic value) {
  if (value == null) return 0;
  if (value is double) return value;
  if (value is int) return value.toDouble();
  return double.tryParse(value.toString()) ?? 0;
}

double _round2(double value) => (value * 100).roundToDouble() / 100;
