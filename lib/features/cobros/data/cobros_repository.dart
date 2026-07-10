import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../shared/io/storage_image_loader.dart';
import '../../printing/data/printing.dart';

class ReceivableSale {
  ReceivableSale({
    required this.id,
    required this.saleNumber,
    required this.saleDate,
    required this.clientId,
    required this.clientName,
    required this.receiptType,
    required this.ncf,
    required this.totalAmount,
    required this.paidAmount,
    required this.balanceDue,
    required this.status,
    required this.dueDate,
  });

  final String id;
  final String saleNumber;
  final DateTime saleDate;
  final String? clientId;
  final String clientName;
  final String receiptType;
  final String? ncf;
  final double totalAmount;
  final double paidAmount;
  final double balanceDue;
  final String status;

  /// Fecha de vencimiento del crédito (null si la venta no es a crédito o
  /// si es una venta antigua sin migrar).
  final DateTime? dueDate;

  /// Días hasta el vencimiento desde "hoy". Negativo si ya venció.
  /// `null` si no tiene `dueDate`.
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

  factory ReceivableSale.fromMap(
    Map<String, dynamic> map,
    Map<String, String> clientsById,
  ) {
    final clientId = map['client_id']?.toString();
    final rawDue = map['due_date']?.toString();

    return ReceivableSale(
      id: (map['id'] ?? '').toString(),
      saleNumber: (map['sale_number'] ?? '-').toString(),
      saleDate:
          DateTime.tryParse((map['sale_date'] ?? '').toString()) ??
          DateTime.fromMillisecondsSinceEpoch(0),
      clientId: clientId,
      clientName: clientId == null
          ? 'Cliente General'
          : (clientsById[clientId] ?? 'Cliente General'),
      receiptType: (map['receipt_type'] ?? '').toString(),
      ncf: map['ncf']?.toString(),
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

class ReceivedPayment {
  ReceivedPayment({
    required this.id,
    required this.saleId,
    required this.saleNumber,
    required this.clientName,
    required this.amount,
    required this.paymentMethod,
    required this.paidAt,
    required this.reference,
  });

  final String id;
  final String? saleId;
  final String saleNumber;
  final String clientName;
  final double amount;
  final String paymentMethod;
  final DateTime paidAt;
  final String? reference;

  factory ReceivedPayment.fromMap(
    Map<String, dynamic> map,
    Map<String, String> clientsById,
    Map<String, String> salesById,
  ) {
    final clientId = map['client_id']?.toString();
    final saleId = map['sale_id']?.toString();

    return ReceivedPayment(
      id: (map['id'] ?? '').toString(),
      saleId: saleId,
      saleNumber: saleId == null ? '-' : (salesById[saleId] ?? '-'),
      clientName: clientId == null
          ? 'Cliente General'
          : (clientsById[clientId] ?? 'Cliente General'),
      amount: _toDouble(map['amount']),
      paymentMethod: (map['payment_method'] ?? '').toString(),
      paidAt:
          DateTime.tryParse((map['paid_at'] ?? '').toString()) ??
          DateTime.fromMillisecondsSinceEpoch(0),
      reference: map['reference']?.toString(),
    );
  }
}

class CobrosPaymentInput {
  CobrosPaymentInput({
    required this.saleId,
    required this.amount,
    required this.paymentMethod,
    this.reference,
    this.notes,
  });

  final String saleId;
  final double amount;
  final String paymentMethod;
  final String? reference;
  final String? notes;
}

class CobrosRepository {
  CobrosRepository(this._client);

  final SupabaseClient _client;

  Future<List<ReceivableSale>> fetchReceivables() async {
    final branchId = await _currentBranchId();
    if (branchId == null) return const [];

    final clientsById = await _loadClientsById(branchId);

    final rows = await _client
        .from('sales')
        .select(
          'id, sale_number, sale_date, client_id, receipt_type, ncf, total_amount, paid_amount, balance_due, status, due_date',
        )
        .eq('branch_id', branchId)
        .gt('balance_due', 0)
        .inFilter('status', ['credit', 'pending', 'completed'])
        .order('due_date', ascending: true, nullsFirst: false)
        .order('sale_date', ascending: false);

    return rows
        .map(
          (item) => ReceivableSale.fromMap(
            Map<String, dynamic>.from(item as Map),
            clientsById,
          ),
        )
        .toList(growable: false);
  }

  Future<List<ReceivedPayment>> fetchReceivedPayments() async {
    final branchId = await _currentBranchId();
    if (branchId == null) return const [];

    final clientsById = await _loadClientsById(branchId);
    final salesById = await _loadSalesById(branchId);

    final rows = await _client
        .from('payments')
        .select(
          'id, sale_id, client_id, amount, payment_method, paid_at, reference',
        )
        .eq('branch_id', branchId)
        .order('paid_at', ascending: false)
        .limit(30);

    return rows
        .map(
          (item) => ReceivedPayment.fromMap(
            Map<String, dynamic>.from(item as Map),
            clientsById,
            salesById,
          ),
        )
        .toList(growable: false);
  }

  Future<void> registerPayment(CobrosPaymentInput input) async {
    final branchId = await _currentBranchId();
    if (branchId == null) {
      throw Exception('No hay sucursal asignada para este usuario.');
    }

    final sale = await _client
        .from('sales')
        .select('id, client_id, paid_amount, balance_due, status')
        .eq('id', input.saleId)
        .eq('branch_id', branchId)
        .single();

    final currentBalance = _toDouble(sale['balance_due']);
    if (currentBalance <= 0) {
      throw Exception('La venta no tiene balance pendiente.');
    }

    if (input.amount <= 0) {
      throw Exception('El monto debe ser mayor que 0.');
    }

    if (input.amount > currentBalance) {
      throw Exception('El abono no puede exceder el balance pendiente.');
    }

    final clientId = sale['client_id']?.toString();
    final openCashSessionId = await _currentOpenCashSessionId(branchId);

    await _client.from('payments').insert({
      'branch_id': branchId,
      'sale_id': input.saleId,
      'client_id': clientId,
      'cash_session_id': openCashSessionId,
      'payment_method': input.paymentMethod,
      'amount': input.amount,
      'paid_at': DateTime.now().toUtc().toIso8601String(),
      'reference': _nullIfEmpty(input.reference),
      'notes': _nullIfEmpty(input.notes),
    });

    final nextPaid = _round2(_toDouble(sale['paid_amount']) + input.amount);
    final nextBalance = _round2(currentBalance - input.amount);
    final nextStatus = nextBalance <= 0 ? 'completed' : 'credit';

    await _client
        .from('sales')
        .update({
          'paid_amount': nextPaid,
          'balance_due': nextBalance,
          'status': nextStatus,
        })
        .eq('id', input.saleId)
        .eq('branch_id', branchId);

    if (clientId != null) {
      await _recomputeClientBalance(branchId, clientId);
    }
  }

  /// Anula (revierte) un abono: borra el registro de pago y devuelve el monto
  /// al balance de la venta. Recalcula el estado de la venta y el saldo del
  /// cliente. Es la operación inversa de [registerPayment].
  Future<void> voidPayment(String paymentId) async {
    final branchId = await _currentBranchId();
    if (branchId == null) {
      throw Exception('No hay sucursal asignada para este usuario.');
    }

    final payment = await _client
        .from('payments')
        .select('id, sale_id, client_id, amount')
        .eq('id', paymentId)
        .eq('branch_id', branchId)
        .single();

    final amount = _toDouble(payment['amount']);
    final saleId = payment['sale_id']?.toString();
    final clientId = payment['client_id']?.toString();

    // 1) Borrar el pago. Verificamos que realmente se borró: bajo RLS, si el
    // usuario no tiene permiso (payments_delete exige rol supervisor/admin), el
    // DELETE afecta 0 filas SIN lanzar error. Si no revisamos, devolveríamos el
    // balance a la venta dejando el pago intacto (inconsistencia).
    final deleted = await _client
        .from('payments')
        .delete()
        .eq('id', paymentId)
        .eq('branch_id', branchId)
        .select('id');
    if ((deleted as List).isEmpty) {
      throw Exception(
        'No se pudo anular el pago. Es posible que no tengas permiso '
        '(anular requiere rol de supervisor o administrador).',
      );
    }

    // 2) Devolver el balance a la venta (si el pago estaba asociado a una).
    if (saleId != null) {
      final sale = await _client
          .from('sales')
          .select('paid_amount, balance_due, total_amount')
          .eq('id', saleId)
          .eq('branch_id', branchId)
          .single();

      final total = _toDouble(sale['total_amount']);
      var nextPaid = _round2(_toDouble(sale['paid_amount']) - amount);
      if (nextPaid < 0) nextPaid = 0;
      var nextBalance = _round2(_toDouble(sale['balance_due']) + amount);
      if (total > 0 && nextBalance > total) nextBalance = total;
      final nextStatus = nextBalance > 0 ? 'credit' : 'completed';

      await _client
          .from('sales')
          .update({
            'paid_amount': nextPaid,
            'balance_due': nextBalance,
            'status': nextStatus,
          })
          .eq('id', saleId)
          .eq('branch_id', branchId);
    }

    // 3) Recalcular el saldo del cliente.
    if (clientId != null) {
      await _recomputeClientBalance(branchId, clientId);
    }
  }

  /// Edita un abono ya registrado. Permite cambiar monto, método y referencia.
  /// Si el monto cambia, recalcula el balance/estado de la venta y el saldo del
  /// cliente aplicando la diferencia (nuevo - anterior).
  Future<void> updatePayment({
    required String paymentId,
    required double newAmount,
    required String paymentMethod,
    String? reference,
  }) async {
    final branchId = await _currentBranchId();
    if (branchId == null) {
      throw Exception('No hay sucursal asignada para este usuario.');
    }
    if (newAmount <= 0) {
      throw Exception('El monto debe ser mayor que 0.');
    }

    final payment = await _client
        .from('payments')
        .select('id, sale_id, client_id, amount')
        .eq('id', paymentId)
        .eq('branch_id', branchId)
        .single();

    final oldAmount = _toDouble(payment['amount']);
    final saleId = payment['sale_id']?.toString();
    final clientId = payment['client_id']?.toString();

    final paymentUpdate = <String, dynamic>{
      'amount': newAmount,
      'payment_method': paymentMethod,
      'reference': _nullIfEmpty(reference),
    };

    if (saleId != null) {
      final sale = await _client
          .from('sales')
          .select('paid_amount, balance_due')
          .eq('id', saleId)
          .eq('branch_id', branchId)
          .single();

      final currentBalance = _toDouble(sale['balance_due']);
      // El tope para este pago = balance actual + lo que este mismo pago ya
      // aportaba (porque lo estamos reemplazando).
      final maxAllowed = _round2(currentBalance + oldAmount);
      if (newAmount > maxAllowed) {
        throw Exception(
          'El monto no puede exceder el balance de la venta (${maxAllowed.toStringAsFixed(2)}).',
        );
      }

      final delta = _round2(newAmount - oldAmount);
      final nextPaid = _round2(_toDouble(sale['paid_amount']) + delta);
      final nextBalance = _round2(currentBalance - delta);
      final nextStatus = nextBalance > 0 ? 'credit' : 'completed';

      // Actualizamos el pago primero y verificamos que afectó una fila: si RLS
      // lo bloqueara, evitamos tocar el balance de la venta con datos viejos.
      final updated = await _client
          .from('payments')
          .update(paymentUpdate)
          .eq('id', paymentId)
          .eq('branch_id', branchId)
          .select('id');
      if ((updated as List).isEmpty) {
        throw Exception('No se pudo actualizar el pago (permiso denegado).');
      }

      await _client
          .from('sales')
          .update({
            'paid_amount': nextPaid,
            'balance_due': nextBalance,
            'status': nextStatus,
          })
          .eq('id', saleId)
          .eq('branch_id', branchId);
    } else {
      await _client
          .from('payments')
          .update(paymentUpdate)
          .eq('id', paymentId)
          .eq('branch_id', branchId);
    }

    if (clientId != null) {
      await _recomputeClientBalance(branchId, clientId);
    }
  }

  /// Prepara el recibo de abono (comprobante del pago) listo para imprimir.
  /// Reutiliza el diálogo/builder de impresión existentes vía
  /// [PreparedPrintJobData].
  Future<PreparedPrintJobData> prepareAbonoReceipt(String paymentId) async {
    final branchId = await _currentBranchId();
    if (branchId == null) {
      throw Exception('No hay sucursal asignada para este usuario.');
    }

    final payment = await _client
        .from('payments')
        .select(
          'id, sale_id, client_id, amount, payment_method, paid_at, reference, notes, created_by',
        )
        .eq('id', paymentId)
        .eq('branch_id', branchId)
        .single();

    final saleId = payment['sale_id']?.toString();
    final clientId = payment['client_id']?.toString();
    final amount = _toDouble(payment['amount']);
    final method = (payment['payment_method'] ?? '').toString();
    final reference = payment['reference']?.toString();
    final paidAt =
        DateTime.tryParse((payment['paid_at'] ?? '').toString()) ??
        DateTime.now();

    // Venta asociada: número + saldo actual (para mostrar "Pendiente").
    var saleNumber = '-';
    var saleBalance = 0.0;
    if (saleId != null) {
      final rows = await _client
          .from('sales')
          .select('sale_number, balance_due')
          .eq('id', saleId)
          .eq('branch_id', branchId)
          .limit(1);
      if (rows.isNotEmpty) {
        final sale = Map<String, dynamic>.from(rows.first as Map);
        saleNumber = (sale['sale_number'] ?? '-').toString();
        saleBalance = _toDouble(sale['balance_due']);
      }
    }

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

    // Cliente.
    Map<String, dynamic> client = const <String, dynamic>{};
    if (clientId != null) {
      final rows = await _client
          .from('clients')
          .select('full_name, document_type, document_number, address, phone')
          .eq('id', clientId)
          .eq('branch_id', branchId)
          .limit(1);
      if (rows.isNotEmpty) {
        client = Map<String, dynamic>.from(rows.first as Map);
      }
    }

    // Cajero que registró el abono.
    String? cashierName;
    final createdBy = payment['created_by']?.toString();
    if (createdBy != null && createdBy.isNotEmpty) {
      final rows = await _client
          .from('profiles')
          .select('full_name')
          .eq('id', createdBy)
          .limit(1);
      if (rows.isNotEmpty) {
        cashierName = (rows.first as Map)['full_name']?.toString();
      }
    }

    final clientName = (client['full_name'] ??
            (clientId == null ? 'Cliente General' : ''))
        .toString();

    final document = PrintDocumentData(
      documentType: PrintDocumentType.paymentReceipt,
      documentNumber: saleNumber,
      issuedAt: paidAt,
      branch: PrintBranchIdentity(
        name: (branch['name'] ?? 'Sucursal').toString(),
        address: _firstNonEmpty([
          settings['company_address'],
          branch['address'],
        ]),
        phone: _firstNonEmpty([settings['company_phone'], branch['phone']]),
        taxId: _firstNonEmpty([settings['company_tax_id']]),
        logoBytes: logoBytes,
      ),
      customer: clientName.trim().isEmpty
          ? null
          : PrintParty(
              name: clientName,
              document: _clientDocumentLabel(client),
              address: _firstNonEmpty([client['address']]),
              phone: _firstNonEmpty([client['phone']]),
            ),
      cashierName: _firstNonEmpty([cashierName]),
      receiptTypeLabel: 'RECIBO DE ABONO',
      showTax: false,
      showBarcode: settings['receipt_hide_barcode'] != true,
      footerMessage: 'Comprobante de abono · Gracias por su pago',
      notes: _firstNonEmpty([payment['notes']]),
      items: [
        PrintDocumentItem(
          description: 'Abono a factura $saleNumber',
          quantity: 1,
          unitPrice: amount,
          lineSubtotal: amount,
          lineTax: 0,
          lineTotal: amount,
        ),
      ],
      payments: [
        PrintPaymentLine(
          method: _paymentMethodLabel(method),
          amount: amount,
          reference: _nullIfEmpty(reference),
        ),
      ],
      totals: PrintTotals(
        subtotal: amount,
        tax: 0,
        total: amount,
        paid: amount,
        balance: saleBalance,
      ),
      extra: <String, dynamic>{
        'source_table': 'payments',
        'source_id': paymentId,
        'branch_id': branchId,
      },
    );

    return PreparedPrintJobData(
      document: document,
      paperSize: PrintPaperSize.thermal80mm,
      job: PrintJobDraft(
        branchId: branchId,
        documentType: PrintDocumentType.paymentReceipt,
        paperSize: PrintPaperSize.thermal80mm,
        sourceTable: 'payments',
        sourceId: paymentId,
        payload: document.extra,
      ),
      dispatchPayload: const <String, dynamic>{},
    );
  }

  /// Recalcula `clients.balance_due` sumando el balance pendiente de todas las
  /// ventas no anuladas del cliente. Compartido por registrar/anular/editar
  /// abonos para mantener el saldo del cliente consistente.
  Future<void> _recomputeClientBalance(
    String branchId,
    String clientId,
  ) async {
    final clientSales = await _client
        .from('sales')
        .select('balance_due')
        .eq('branch_id', branchId)
        .eq('client_id', clientId)
        .gt('balance_due', 0)
        .neq('status', 'voided');

    final clientBalance = _round2(
      clientSales.fold<double>(
        0,
        (sum, row) => sum + _toDouble((row as Map)['balance_due']),
      ),
    );

    await _client
        .from('clients')
        .update({'balance_due': clientBalance})
        .eq('id', clientId)
        .eq('branch_id', branchId);
  }

  /// Extiende (o redefine) la fecha de vencimiento de una venta a crédito.
  /// Si `additionalDays` se pasa, se suma a la `due_date` actual; si se pasa
  /// `newDueDate`, se reemplaza directamente.
  Future<void> extendCreditDueDate({
    required String saleId,
    int? additionalDays,
    DateTime? newDueDate,
  }) async {
    if (additionalDays == null && newDueDate == null) {
      throw ArgumentError(
        'Debes pasar `additionalDays` o `newDueDate`.',
      );
    }

    final branchId = await _currentBranchId();
    if (branchId == null) {
      throw Exception('No hay sucursal asignada para este usuario.');
    }

    DateTime resolvedDue;
    if (newDueDate != null) {
      resolvedDue = newDueDate;
    } else {
      final row = await _client
          .from('sales')
          .select('due_date, sale_date')
          .eq('id', saleId)
          .eq('branch_id', branchId)
          .single();
      final base = DateTime.tryParse(
            (row['due_date'] ?? row['sale_date'] ?? '').toString(),
          ) ??
          DateTime.now();
      resolvedDue = base.add(Duration(days: additionalDays!));
    }

    final iso = '${resolvedDue.year.toString().padLeft(4, '0')}-'
        '${resolvedDue.month.toString().padLeft(2, '0')}-'
        '${resolvedDue.day.toString().padLeft(2, '0')}';

    await _client
        .from('sales')
        .update({'due_date': iso})
        .eq('id', saleId)
        .eq('branch_id', branchId);
  }

  /// Cuenta cuántos créditos pendientes vencen dentro de `warnDays` días
  /// (próximos a vencer pero aún no vencidos). Usado por el banner de login.
  Future<int> countCreditsNearDue({required int warnDays}) async {
    final branchId = await _currentBranchId();
    if (branchId == null) return 0;

    final today = DateTime.now();
    final limit = today.add(Duration(days: warnDays));
    String iso(DateTime d) =>
        '${d.year.toString().padLeft(4, '0')}-'
        '${d.month.toString().padLeft(2, '0')}-'
        '${d.day.toString().padLeft(2, '0')}';

    final rows = await _client
        .from('sales')
        .select('id')
        .eq('branch_id', branchId)
        .eq('status', 'credit')
        .gt('balance_due', 0)
        .gte('due_date', iso(today))
        .lte('due_date', iso(limit));

    return rows.length;
  }

  Future<Map<String, String>> _loadClientsById(String branchId) async {
    final rows = await _client
        .from('clients')
        .select('id, full_name')
        .eq('branch_id', branchId)
        .order('full_name');

    return {
      for (final row in rows)
        (row['id'] ?? '').toString(): (row['full_name'] ?? '').toString(),
    };
  }

  Future<Map<String, String>> _loadSalesById(String branchId) async {
    final rows = await _client
        .from('sales')
        .select('id, sale_number')
        .eq('branch_id', branchId)
        .order('sale_date', ascending: false)
        .limit(200);

    return {
      for (final row in rows)
        (row['id'] ?? '').toString(): (row['sale_number'] ?? '-').toString(),
    };
  }

  Future<String?> _currentBranchId() async {
    final result = await _client.rpc('current_branch_id');
    if (result == null) return null;
    final value = result.toString();
    return value.isEmpty ? null : value;
  }

  /// Sesión de caja abierta DEL USUARIO ACTUAL. Con multi-caja cada cajero
  /// tiene su propia sesión; los abonos van a la sesión del que los registra.
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

String? _nullIfEmpty(String? value) {
  if (value == null) return null;
  final trimmed = value.trim();
  return trimmed.isEmpty ? null : trimmed;
}

/// Primer valor no vacío de la lista, ya "trimmeado". `null` si todos vacíos.
String? _firstNonEmpty(List<dynamic> values) {
  for (final v in values) {
    final s = v?.toString().trim();
    if (s != null && s.isNotEmpty) return s;
  }
  return null;
}

/// Etiqueta del documento del cliente para el recibo (ej. "RNC: 130..." o
/// "Cédula: 001..."). `null` si el cliente no tiene número de documento.
String? _clientDocumentLabel(Map<String, dynamic> client) {
  final number = (client['document_number'] ?? '').toString().trim();
  if (number.isEmpty) return null;
  final type = (client['document_type'] ?? '').toString().trim().toLowerCase();
  final prefix = switch (type) {
    'rnc' => 'RNC',
    'cedula' || 'cédula' => 'Cédula',
    'passport' || 'pasaporte' => 'Pasaporte',
    '' => 'Doc',
    _ => type.toUpperCase(),
  };
  return '$prefix: $number';
}

/// Método de pago en español para el recibo de abono.
String _paymentMethodLabel(String value) {
  switch (value) {
    case 'cash':
      return 'Efectivo';
    case 'card':
      return 'Tarjeta';
    case 'transfer':
      return 'Transferencia';
    case 'mobile':
      return 'Pago móvil';
    case 'mixed':
      return 'Mixto';
    case 'credit':
      return 'Crédito';
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
