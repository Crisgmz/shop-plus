import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../shared/errors/friendly_error.dart';

class ClientEntity {
  ClientEntity({
    required this.id,
    required this.fullName,
    required this.entityType,
    required this.legalName,
    required this.email,
    required this.phone,
    required this.address,
    required this.documentType,
    required this.documentNumber,
    required this.creditLimit,
    required this.balanceDue,
    required this.isActive,
    // ── fields from 20260421 migration ──────────────────────────────────
    this.firstName,
    this.lastName,
    this.companyName,
    this.secondaryPhone,
    this.addressLine1,
    this.addressLine2,
    this.city,
    this.province,
    this.countryCode = 'DO',
    this.postalCode,
    this.googleMapsUrl,
    this.avatarUrl,
    this.birthday,
    this.comments,
    this.defaultReceiptType,
    this.priceTier = 'retail',
    this.taxExempt = false,
    this.chargeItbis = true,
    this.creditInvoiceLimit = 0,
  });

  final String id;
  final String fullName;
  final String entityType;
  final String? legalName;
  final String? email;
  final String? phone;
  final String? address;
  final String? documentType;
  final String? documentNumber;
  final double creditLimit;
  final double balanceDue;
  final bool isActive;

  final String? firstName;
  final String? lastName;
  final String? companyName;
  final String? secondaryPhone;
  final String? addressLine1;
  final String? addressLine2;
  final String? city;
  final String? province;
  final String countryCode;
  final String? postalCode;
  final String? googleMapsUrl;
  final String? avatarUrl;
  final DateTime? birthday;
  final String? comments;
  final String? defaultReceiptType;
  final String priceTier;
  final bool taxExempt;
  final bool chargeItbis;
  final int creditInvoiceLimit;

  factory ClientEntity.fromMap(Map<String, dynamic> map) {
    return ClientEntity(
      id: (map['id'] ?? '').toString(),
      fullName: (map['full_name'] ?? '').toString(),
      entityType: (map['entity_type'] ?? 'person').toString(),
      legalName: map['legal_name']?.toString(),
      email: map['email']?.toString(),
      phone: map['phone']?.toString(),
      address: map['address']?.toString(),
      documentType: map['document_type']?.toString(),
      documentNumber: map['document_number']?.toString(),
      creditLimit: _toDouble(map['credit_limit']),
      balanceDue: _toDouble(map['balance_due']),
      isActive: map['is_active'] == true,
      firstName: map['first_name']?.toString(),
      lastName: map['last_name']?.toString(),
      companyName: map['company_name']?.toString(),
      secondaryPhone: map['secondary_phone']?.toString(),
      addressLine1: map['address_line_1']?.toString(),
      addressLine2: map['address_line_2']?.toString(),
      city: map['city']?.toString(),
      province: map['province']?.toString(),
      countryCode: (map['country_code'] ?? 'DO').toString(),
      postalCode: map['postal_code']?.toString(),
      googleMapsUrl: map['google_maps_url']?.toString(),
      avatarUrl: map['avatar_url']?.toString(),
      birthday: map['birthday'] == null
          ? null
          : DateTime.tryParse(map['birthday'].toString()),
      comments: map['comments']?.toString(),
      defaultReceiptType: map['default_receipt_type']?.toString(),
      priceTier: (map['price_tier'] ?? 'retail').toString(),
      taxExempt: map['tax_exempt'] == true,
      chargeItbis: map['charge_itbis'] != false,
      creditInvoiceLimit: _toInt(map['credit_invoice_limit']),
    );
  }
}

class ClientInput {
  ClientInput({
    required this.fullName,
    required this.entityType,
    required this.creditLimit,
    required this.isActive,
    this.id,
    this.firstName,
    this.lastName,
    this.companyName,
    this.legalName,
    this.email,
    this.phone,
    this.secondaryPhone,
    this.address,
    this.addressLine1,
    this.addressLine2,
    this.city,
    this.province,
    this.countryCode = 'DO',
    this.postalCode,
    this.googleMapsUrl,
    this.documentType,
    this.documentNumber,
    this.birthday,
    this.comments,
    this.defaultReceiptType,
    this.priceTier = 'retail',
    this.taxExempt = false,
    this.chargeItbis = true,
    this.creditInvoiceLimit = 0,
  });

  final String? id;
  final String fullName;
  final String entityType;
  final String? firstName;
  final String? lastName;
  final String? companyName;
  final String? legalName;
  final String? email;
  final String? phone;
  final String? secondaryPhone;
  final String? address;
  final String? addressLine1;
  final String? addressLine2;
  final String? city;
  final String? province;
  final String countryCode;
  final String? postalCode;
  final String? googleMapsUrl;
  final String? documentType;
  final String? documentNumber;
  final double creditLimit;
  final bool isActive;
  final DateTime? birthday;
  final String? comments;
  final String? defaultReceiptType;
  final String priceTier;
  final bool taxExempt;
  final bool chargeItbis;
  final int creditInvoiceLimit;
}

class CustomerBalanceItem {
  CustomerBalanceItem({
    required this.id,
    required this.fullName,
    required this.balanceDue,
    required this.creditLimit,
    required this.salesCount,
    required this.totalSalesAmount,
    this.companyName,
    this.phone,
    this.email,
    this.lastSaleAt,
    this.priceTier = 'retail',
  });

  final String id;
  final String fullName;
  final String? companyName;
  final String? phone;
  final String? email;
  final double balanceDue;
  final double creditLimit;
  final int salesCount;
  final double totalSalesAmount;
  final DateTime? lastSaleAt;
  final String priceTier;

  String get displayName => companyName?.isNotEmpty == true ? companyName! : fullName;
  bool get overLimit => creditLimit > 0 && balanceDue > creditLimit;

  factory CustomerBalanceItem.fromMap(Map<String, dynamic> map) {
    return CustomerBalanceItem(
      id: (map['id'] ?? '').toString(),
      fullName: (map['full_name'] ?? '').toString(),
      companyName: map['company_name']?.toString(),
      phone: map['phone']?.toString(),
      email: map['email']?.toString(),
      balanceDue: _toDouble(map['balance_due']),
      creditLimit: _toDouble(map['credit_limit']),
      salesCount: _toInt(map['sales_count']),
      totalSalesAmount: _toDouble(map['total_sales_amount']),
      lastSaleAt: map['last_sale_at'] == null
          ? null
          : DateTime.tryParse(map['last_sale_at'].toString()),
      priceTier: (map['price_tier'] ?? 'retail').toString(),
    );
  }
}

class ClientsBulkUpsertResult {
  ClientsBulkUpsertResult({
    required this.created,
    required this.updated,
    required this.errors,
  });

  final int created;
  final int updated;
  final List<String> errors;

  int get total => created + updated;
}

class ClientsRepository {
  ClientsRepository(this._client);

  final SupabaseClient _client;

  Future<List<ClientEntity>> fetchClients() async {
    final branchId = await _currentBranchId();
    if (branchId == null) return const [];

    // Paginado: Supabase corta cada consulta en su tope (por defecto 1000
    // filas). Con muchos clientes una sola consulta dejaría fuera el resto.
    // Pedimos en lotes avanzando por la cantidad devuelta hasta vaciar.
    const pageSize = 1000;
    final rows = <Map<String, dynamic>>[];
    var from = 0;
    while (true) {
      final page = await _client
          .from('clients')
          .select(
            'id, full_name, entity_type, legal_name, email, phone, address, '
            'document_type, document_number, credit_limit, balance_due, is_active, '
            'first_name, last_name, company_name, secondary_phone, '
            'address_line_1, address_line_2, city, province, country_code, '
            'postal_code, google_maps_url, avatar_url, birthday, comments, '
            'default_receipt_type, price_tier, tax_exempt, charge_itbis, '
            'credit_invoice_limit',
          )
          .eq('branch_id', branchId)
          .order('full_name')
          .range(from, from + pageSize - 1);
      if (page.isEmpty) break;
      rows.addAll(page.map((e) => Map<String, dynamic>.from(e as Map)));
      from += page.length;
      if (page.length < pageSize) break;
    }

    return rows
        .map(ClientEntity.fromMap)
        .toList(growable: false);
  }

  Future<void> saveClient(ClientInput input) async {
    final branchId = await _currentBranchId();
    if (branchId == null) {
      throw Exception('No hay sucursal asignada para este usuario.');
    }

    final payload = <String, dynamic>{
      'full_name': input.fullName.trim(),
      'entity_type': input.entityType,
      'first_name': _nullIfEmpty(input.firstName),
      'last_name': _nullIfEmpty(input.lastName),
      'company_name': _nullIfEmpty(input.companyName),
      'legal_name': _nullIfEmpty(input.legalName),
      'email': _nullIfEmpty(input.email),
      'phone': _nullIfEmpty(input.phone),
      'secondary_phone': _nullIfEmpty(input.secondaryPhone),
      'address': _nullIfEmpty(input.address),
      'address_line_1': _nullIfEmpty(input.addressLine1),
      'address_line_2': _nullIfEmpty(input.addressLine2),
      'city': _nullIfEmpty(input.city),
      'province': _nullIfEmpty(input.province),
      'country_code':
          input.countryCode.isNotEmpty ? input.countryCode : 'DO',
      'postal_code': _nullIfEmpty(input.postalCode),
      'google_maps_url': _nullIfEmpty(input.googleMapsUrl),
      'document_type': _nullIfEmpty(input.documentType),
      'document_number': _nullIfEmpty(input.documentNumber),
      'credit_limit': input.creditLimit,
      'is_active': input.isActive,
      'birthday': input.birthday?.toIso8601String().split('T').first,
      'comments': _nullIfEmpty(input.comments),
      'default_receipt_type': input.defaultReceiptType,
      'price_tier': input.priceTier,
      'tax_exempt': input.taxExempt,
      'charge_itbis': input.chargeItbis,
      'credit_invoice_limit': input.creditInvoiceLimit,
    };

    if (input.id == null) {
      payload['branch_id'] = branchId;
      await _client.from('clients').insert(payload);
      return;
    }

    await _client
        .from('clients')
        .update(payload)
        .eq('id', input.id!)
        .eq('branch_id', branchId);
  }

  /// Crea un cliente rápido (desde la pantalla de Ventas) con lo mínimo y
  /// devuelve su id para seleccionarlo de inmediato en la venta.
  Future<String> createQuickClient({
    required String fullName,
    String? phone,
    String? documentNumber,
  }) async {
    final branchId = await _currentBranchId();
    if (branchId == null) {
      throw Exception('No hay sucursal asignada para este usuario.');
    }
    if (fullName.trim().isEmpty) {
      throw Exception('El nombre del cliente es requerido.');
    }
    final row = await _client
        .from('clients')
        .insert({
          'branch_id': branchId,
          'full_name': fullName.trim(),
          'entity_type': 'person',
          'phone': _nullIfEmpty(phone),
          'document_number': _nullIfEmpty(documentNumber),
          'is_active': true,
          'price_tier': 'retail',
          'charge_itbis': true,
        })
        .select('id')
        .single();
    return (row['id'] ?? '').toString();
  }

  /// Crea o actualiza múltiples clientes en bloque. Devuelve los conteos.
  Future<ClientsBulkUpsertResult> bulkUpsertClients(
    List<ClientInput> inputs,
  ) async {
    var created = 0;
    var updated = 0;
    final errors = <String>[];

    for (final input in inputs) {
      try {
        final wasNew = input.id == null;
        await saveClient(input);
        if (wasNew) {
          created += 1;
        } else {
          updated += 1;
        }
      } catch (e) {
        errors.add('${input.fullName}: ${friendlyErrorMessage(e)}');
      }
    }

    return ClientsBulkUpsertResult(
      created: created,
      updated: updated,
      errors: errors,
    );
  }

  Future<List<CustomerBalanceItem>> fetchCustomerBalances({
    bool withBalanceOnly = true,
  }) async {
    final branchId = await _currentBranchId();
    if (branchId == null) return const [];

    var query = _client
        .from('customer_balances_view')
        .select(
          'id, full_name, company_name, phone, email, '
          'credit_limit, balance_due, price_tier, '
          'sales_count, total_sales_amount, last_sale_at',
        )
        .eq('branch_id', branchId);

    if (withBalanceOnly) {
      query = query.gt('balance_due', 0);
    }

    final rows = await query
        .order('balance_due', ascending: false)
        .limit(100);

    return rows
        .map(
          (item) => CustomerBalanceItem.fromMap(
            Map<String, dynamic>.from(item as Map),
          ),
        )
        .toList(growable: false);
  }

  Future<void> setClientActive({
    required String clientId,
    required bool isActive,
  }) async {
    final branchId = await _currentBranchId();
    if (branchId == null) {
      throw Exception('No hay sucursal asignada para este usuario.');
    }

    await _client
        .from('clients')
        .update({'is_active': isActive})
        .eq('id', clientId)
        .eq('branch_id', branchId);
  }

  /// Borra el cliente físicamente. Si tiene ventas/pagos vinculados la DB
  /// lo bloquea con FK violation (código 23503). El caller decide si hacer
  /// fallback a soft-delete (desactivar).
  Future<void> deleteClient(String clientId) async {
    final branchId = await _currentBranchId();
    if (branchId == null) {
      throw Exception('No hay sucursal asignada para este usuario.');
    }

    await _client
        .from('clients')
        .delete()
        .eq('id', clientId)
        .eq('branch_id', branchId);
  }

  /// Historial de pagos hechos por un cliente.
  Future<List<ClientPaymentRow>> fetchPaymentsForClient(
    String clientId, {
    int limit = 200,
  }) async {
    final branchId = await _currentBranchId();
    if (branchId == null) return const [];

    final rows = await _client
        .from('payments')
        .select(
          'id, sale_id, payment_method, amount, paid_at, reference, notes, '
          'sales(sale_number, total_amount, status, receipt_type)',
        )
        .eq('branch_id', branchId)
        .eq('client_id', clientId)
        .order('paid_at', ascending: false)
        .limit(limit);

    return rows
        .map((item) => ClientPaymentRow.fromMap(
              Map<String, dynamic>.from(item as Map),
            ))
        .toList(growable: false);
  }

  /// Edita un pago existente. Solo `amount`, `payment_method`, `reference`
  /// y `notes` son editables.
  Future<void> updatePayment({
    required String paymentId,
    required double amount,
    required String paymentMethod,
    String? reference,
    String? notes,
  }) async {
    final branchId = await _currentBranchId();
    if (branchId == null) {
      throw Exception('No hay sucursal asignada para este usuario.');
    }
    if (amount <= 0) {
      throw Exception('El monto debe ser mayor que cero.');
    }
    await _client
        .from('payments')
        .update({
          'amount': amount,
          'payment_method': paymentMethod,
          'reference': _nullIfEmpty(reference),
          'notes': _nullIfEmpty(notes),
        })
        .eq('id', paymentId)
        .eq('branch_id', branchId);
  }

  Future<void> deletePayment(String paymentId) async {
    final branchId = await _currentBranchId();
    if (branchId == null) {
      throw Exception('No hay sucursal asignada para este usuario.');
    }
    await _client
        .from('payments')
        .delete()
        .eq('id', paymentId)
        .eq('branch_id', branchId);
  }

  Future<String?> _currentBranchId() async {
    final result = await _client.rpc('current_branch_id');
    if (result == null) return null;
    final value = result.toString();
    return value.isEmpty ? null : value;
  }
}

/// Fila del historial de pagos de un cliente.
class ClientPaymentRow {
  ClientPaymentRow({
    required this.id,
    required this.amount,
    required this.paymentMethod,
    required this.paidAt,
    this.saleId,
    this.saleNumber,
    this.saleStatus,
    this.saleTotal,
    this.reference,
    this.notes,
  });

  factory ClientPaymentRow.fromMap(Map<String, dynamic> map) {
    final sale = map['sales'];
    return ClientPaymentRow(
      id: (map['id'] ?? '').toString(),
      amount: _toDouble(map['amount']),
      paymentMethod: (map['payment_method'] ?? '').toString(),
      paidAt: DateTime.tryParse(map['paid_at']?.toString() ?? '') ??
          DateTime.now(),
      saleId: map['sale_id']?.toString(),
      saleNumber: sale is Map ? sale['sale_number']?.toString() : null,
      saleStatus: sale is Map ? sale['status']?.toString() : null,
      saleTotal: sale is Map ? _toDouble(sale['total_amount']) : null,
      reference: map['reference']?.toString(),
      notes: map['notes']?.toString(),
    );
  }

  final String id;
  final double amount;
  final String paymentMethod;
  final DateTime paidAt;
  final String? saleId;
  final String? saleNumber;
  final String? saleStatus;
  final double? saleTotal;
  final String? reference;
  final String? notes;
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

int _toInt(dynamic value) {
  if (value == null) return 0;
  if (value is int) return value;
  if (value is double) return value.toInt();
  return int.tryParse(value.toString()) ?? 0;
}
