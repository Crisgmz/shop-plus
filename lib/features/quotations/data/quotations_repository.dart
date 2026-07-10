import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../shared/formatters/formatters.dart' as fmt;
import '../../../shared/io/storage_image_loader.dart';
import '../../printing/data/printing.dart';
import 'quotations_models.dart';

class QuotationsRepository implements QuotationsRepositoryContract {
  QuotationsRepository(this._client);

  final SupabaseClient _client;
  static const QuotePrintJobPreparationService _quotePrintService =
      QuotePrintJobPreparationService();

  @override
  Future<List<QuoteListItem>> fetchQuotes() async {
    final branchId = await _currentBranchId();
    if (branchId == null) return const [];

    final rows = await _client
        .from('quotations')
        .select(
          'id, code, status, created_at, valid_until, total_amount, notes, converted_sale_id, client_display_name, clients(full_name)',
        )
        .eq('branch_id', branchId)
        .order('created_at', ascending: false);

    final quoteIds = rows
        .map((row) => (row as Map)['id']?.toString())
        .whereType<String>()
        .where((id) => id.isNotEmpty)
        .toList(growable: false);

    final itemCounts = await _loadItemCounts(quoteIds);

    return rows.map(_mapListItem(itemCounts)).toList(growable: false);
  }

  @override
  Future<QuoteDetail> fetchQuoteDetail(String quoteId) async {
    final row = await _client
        .from('quotations')
        .select(
          'id, code, client_id, status, created_at, valid_until, notes, subtotal, tax_amount, total_amount, converted_sale_id, client_display_name, clients(full_name)',
        )
        .eq('id', quoteId)
        .single();

    final itemRows = await _client
        .from('quotation_items')
        .select(
          'product_id, product_name, product_sku, description, quantity, unit_price, tax_rate',
        )
        .eq('quotation_id', quoteId)
        .order('created_at');

    return QuoteDetail.fromMaps(
      quote: _normalizeMap(row),
      items: itemRows.map(_normalizeMap).toList(growable: false),
    );
  }

  @override
  Future<List<QuoteCatalogProduct>> fetchProducts() async {
    final branchId = await _currentBranchId();
    if (branchId == null) return const [];

    final rows = await _client
        .from('products')
        .select(
          'id, name, sku, barcode, description, price, tax_rate, stock, is_active',
        )
        .eq('branch_id', branchId)
        .eq('is_active', true)
        .order('name');

    return rows
        .map(
          (item) => QuoteCatalogProduct.fromMap(
            Map<String, dynamic>.from(item as Map),
          ),
        )
        .toList(growable: false);
  }

  @override
  Future<List<QuoteClientOption>> fetchClients() async {
    final branchId = await _currentBranchId();
    if (branchId == null) return const [];

    final rows = await _client
        .from('clients')
        .select(
          'id, full_name, legal_name, email, phone, document_type, document_number',
        )
        .eq('branch_id', branchId)
        .eq('is_active', true)
        .order('full_name');

    return rows
        .map(
          (item) =>
              QuoteClientOption.fromMap(Map<String, dynamic>.from(item as Map)),
        )
        .toList(growable: false);
  }

  /// Marca como `expired` las cotizaciones cuyo `valid_until` ya pasó. Es
  /// idempotente — invocar antes de listar para que la UI nunca muestre
  /// cotizaciones activas que ya vencieron.
  Future<int> expireOverdue() async {
    try {
      final result = await _client.rpc('expire_overdue_quotations');
      if (result is int) return result;
      return int.tryParse(result?.toString() ?? '0') ?? 0;
    } catch (_) {
      // El RPC puede no existir (proyectos viejos); fallar suavemente.
      return 0;
    }
  }

  @override
  Future<QuoteFoundationBundle> loadFoundation() async {
    // Auto-expirar antes de listar para que el dashboard refleje el estado real.
    await expireOverdue();
    final quotes = await fetchQuotes();
    final openQuotes = quotes
        .where(
          (q) =>
              q.effectiveStatus != QuoteStatus.converted &&
              q.effectiveStatus != QuoteStatus.rejected &&
              q.effectiveStatus != QuoteStatus.expired,
        )
        .toList(growable: false);
    final approvedQuotes = quotes
        .where((q) => q.effectiveStatus == QuoteStatus.approved)
        .toList(growable: false);
    final expiringSoon = openQuotes
        .where((q) => q.daysRemaining >= 0 && q.daysRemaining <= 3)
        .length;
    final totalPipeline = openQuotes.fold<double>(0, (sum, q) => sum + q.total);
    final totalApproved = approvedQuotes.fold<double>(
      0,
      (sum, q) => sum + q.total,
    );

    final metrics = [
      QuoteMetric(
        label: 'Cotizaciones activas',
        value: fmt.qty(openQuotes.length),
        helpText: 'Borradores, enviadas, en revisión y aprobadas vigentes.',
        highlight: true,
      ),
      QuoteMetric(
        label: 'Monto en pipeline',
        value: fmt.money(totalPipeline),
        helpText: 'Oportunidades vigentes todavía no cerradas.',
      ),
      QuoteMetric(
        label: 'Listas para venta',
        value: fmt.money(totalApproved),
        helpText: 'Cotizaciones aprobadas listas para convertir.',
      ),
      QuoteMetric(
        label: 'Vencen pronto',
        value: fmt.qty(expiringSoon),
        helpText: 'Requieren seguimiento comercial inmediato.',
      ),
    ];

    final pipeline = [
      _buildStage('Borrador', QuoteStatus.draft, quotes, 'Preparación interna'),
      _buildStage('Enviadas', QuoteStatus.sent, quotes, 'Seguimiento abierto'),
      _buildStage(
        'En revisión',
        QuoteStatus.underReview,
        quotes,
        'Negociación activa',
      ),
      _buildStage(
        'Aprobadas',
        QuoteStatus.approved,
        quotes,
        'Listas para cerrar',
      ),
    ];

    return QuoteFoundationBundle(
      metrics: metrics,
      pipeline: pipeline,
      recentQuotes: quotes,
    );
  }

  @override
  Future<String> createQuote(QuoteCreateInput input) async {
    final branchId = await _currentBranchId();
    final userId = _client.auth.currentUser?.id;
    _validateInput(input, branchId: branchId, userId: userId);

    final quotePayload = await _buildQuotePayload(
      input,
      branchId: branchId!,
      userId: userId!,
    );

    final createdQuote = await _client
        .from('quotations')
        .insert(quotePayload)
        .select('id')
        .single();
    final quoteId = (createdQuote['id'] ?? '').toString();
    if (quoteId.isEmpty) {
      throw Exception('No se pudo crear la cotización.');
    }

    await _client.from('quotation_items').insert(
      _itemsPayload(input.items, quoteId: quoteId, branchId: branchId),
    );

    await _appendEvent(
      quotationId: quoteId,
      branchId: branchId,
      eventType: 'created',
      payload: {
        'items_count': input.items.length,
        'total_amount': QuotationsMath.total(input.items),
        'status': input.status.dbValue,
      },
    );

    return quoteId;
  }

  @override
  Future<void> updateQuote(String quoteId, QuoteCreateInput input) async {
    final quote = await fetchQuoteDetail(quoteId);
    if (!quote.canEdit || quote.saleId != null) {
      throw Exception('La cotización convertida ya no se puede editar.');
    }

    final rpcResult = await _client.rpc(
      'update_quotation_document',
      params: {
        'target_quotation_id': quoteId,
        'requested_client_id': _nullIfEmpty(input.clientId),
        'requested_status': input.status.dbValue,
        'requested_valid_until': input.validUntil.toUtc().toIso8601String(),
        'requested_notes': _nullIfEmpty(input.notes),
        'requested_items': input.items.map((item) => item.toRpcMap()).toList(),
      },
    );

    final normalized = _parseMaybeMap(rpcResult);
    if (normalized == null || normalized['quotation_id']?.toString() != quoteId) {
      throw Exception('No se pudo actualizar la cotización.');
    }
  }

  @override
  Future<QuoteConversionResult> convertToSale(
    String quoteId, {
    required String paymentMethod,
    String? cashSessionId,
  }) async {
    final result = await _client.rpc(
      'convert_quotation_to_sale',
      params: {
        'target_quotation_id': quoteId,
        'requested_payment_method': paymentMethod,
        if (cashSessionId != null && cashSessionId.isNotEmpty)
          'requested_cash_session_id': cashSessionId,
      },
    );

    final map = _parseMaybeMap(result);
    if (map != null) {
      return QuoteConversionResult(
        saleId: (map['sale_id'] ?? '').toString(),
        saleNumber: (map['sale_number'] ?? '').toString(),
      );
    }

    throw Exception(
      'La base de datos no devolvió un resultado válido al convertir la cotización.',
    );
  }

  @override
  Future<void> deleteQuote(String quoteId) async {
    final quoteRow = await _client
        .from('quotations')
        .select('id, branch_id, status, valid_until, converted_sale_id')
        .eq('id', quoteId)
        .single();
    final quote = Map<String, dynamic>.from(quoteRow as Map);
    final quoteItem = QuoteListItem(
      id: quoteId,
      code: '',
      clientName: '',
      status: QuoteStatusX.fromDb(quote['status']?.toString()),
      createdAt: DateTime.now(),
      validUntil:
          DateTime.tryParse(quote['valid_until']?.toString() ?? '') ??
          DateTime.now(),
      total: 0,
      itemsCount: 0,
      saleId: _nullIfEmpty(quote['converted_sale_id']?.toString()),
    );

    if (!quoteItem.canDelete || quoteItem.saleId != null) {
      throw Exception(
        'Solo se pueden eliminar cotizaciones borrador, perdidas o expiradas no convertidas.',
      );
    }

    await _client.from('quotations').delete().eq('id', quoteId);
  }

  QuotePipelineStage _buildStage(
    String label,
    QuoteStatus status,
    List<QuoteListItem> quotes,
    String note,
  ) {
    final filtered = quotes
        .where((q) => q.effectiveStatus == status)
        .toList(growable: false);
    final amount = filtered.fold<double>(0, (sum, q) => sum + q.total);
    return QuotePipelineStage(
      label: label,
      count: filtered.length,
      amount: amount,
      note: note,
    );
  }

  Future<Map<String, int>> _loadItemCounts(List<String> quoteIds) async {
    if (quoteIds.isEmpty) return const {};

    final rows = await _client
        .from('quotation_items')
        .select('quotation_id')
        .inFilter('quotation_id', quoteIds);

    final counts = <String, int>{};
    for (final row in rows) {
      final quotationId = (row as Map)['quotation_id']?.toString();
      if (quotationId == null || quotationId.isEmpty) continue;
      counts.update(quotationId, (value) => value + 1, ifAbsent: () => 1);
    }
    return counts;
  }

  Future<Map<String, dynamic>> _buildQuotePayload(
    QuoteCreateInput input, {
    required String branchId,
    required String userId,
  }) async {
    Map<String, dynamic>? clientSnapshot;
    if (_nullIfEmpty(input.clientId) != null) {
      final clientRow = await _client
          .from('clients')
          .select(
            'id, full_name, legal_name, email, phone, document_type, document_number',
          )
          .eq('id', input.clientId!)
          .eq('branch_id', branchId)
          .single();
      clientSnapshot = Map<String, dynamic>.from(clientRow as Map);
    }

    final subtotal = QuotationsMath.subtotal(input.items);
    final taxAmount = QuotationsMath.tax(input.items);
    final total = QuotationsMath.total(input.items);

    return <String, dynamic>{
      'branch_id': branchId,
      'client_id': _nullIfEmpty(input.clientId),
      'code': _buildQuoteCode(),
      'status': input.status.dbValue,
      'version_no': 1,
      'owner_user_id': userId,
      'client_display_name':
          _nullIfEmpty(clientSnapshot?['full_name']?.toString()) ??
          'Cliente general',
      'client_legal_name': _nullIfEmpty(
        clientSnapshot?['legal_name']?.toString(),
      ),
      'client_email': _nullIfEmpty(clientSnapshot?['email']?.toString()),
      'client_phone': _nullIfEmpty(clientSnapshot?['phone']?.toString()),
      'client_document_type': _nullIfEmpty(
        clientSnapshot?['document_type']?.toString(),
      ),
      'client_document_number': _nullIfEmpty(
        clientSnapshot?['document_number']?.toString(),
      ),
      'sent_at': input.status == QuoteStatus.sent ? DateTime.now().toUtc().toIso8601String() : null,
      'approved_at': input.status == QuoteStatus.approved ? DateTime.now().toUtc().toIso8601String() : null,
      'rejected_at': input.status == QuoteStatus.rejected ? DateTime.now().toUtc().toIso8601String() : null,
      'expired_at': input.status == QuoteStatus.expired ? DateTime.now().toUtc().toIso8601String() : null,
      'subtotal': subtotal,
      'tax_amount': taxAmount,
      'total_amount': total,
      'valid_until': input.validUntil.toUtc().toIso8601String(),
      'notes': _nullIfEmpty(input.notes),
    };
  }

  List<Map<String, dynamic>> _itemsPayload(
    List<QuoteCreateItem> items, {
    required String quoteId,
    required String branchId,
  }) {
    return items
        .map(
          (item) => <String, dynamic>{
            'quotation_id': quoteId,
            'branch_id': branchId,
            'product_id': item.productId,
            'product_name': item.productName,
            'product_sku': _nullIfEmpty(item.productSku),
            'description':
                _nullIfEmpty(item.productDescription) ?? item.productName,
            'quantity': item.quantity,
            'unit_price': item.unitPrice,
            'discount_amount': 0,
            'tax_rate': item.taxRate,
            'line_subtotal': item.lineSubtotal,
            'line_tax': item.lineTax,
            'line_total': item.lineTotal,
          },
        )
        .toList(growable: false);
  }

  void _validateInput(
    QuoteCreateInput input, {
    required String? branchId,
    required String? userId,
  }) {
    if (input.items.isEmpty) {
      throw Exception('La cotización debe tener al menos una línea.');
    }
    if (branchId == null) {
      throw Exception('No hay sucursal activa para trabajar con cotizaciones.');
    }
    if (userId == null) {
      throw Exception('La sesión no es válida. Inicia sesión de nuevo.');
    }
    if (!input.validUntil.toUtc().isAfter(DateTime.now().toUtc())) {
      throw Exception('La vigencia debe estar en el futuro.');
    }
    if (input.status == QuoteStatus.converted) {
      throw Exception('No puedes guardar una cotización ya convertida desde el formulario.');
    }
  }

  QuoteListItem Function(dynamic row) _mapListItem(Map<String, int> itemCounts) {
    return (row) {
      final map = _normalizeMap(row);
      final clientRaw = map['clients'];
      final clientMap = clientRaw is Map ? _normalizeMap(clientRaw) : null;

      final createdAt = DateTime.tryParse(map['created_at']?.toString() ?? '');
      final validUntil = DateTime.tryParse(map['valid_until']?.toString() ?? '');

      return QuoteListItem(
        id: map['id'].toString(),
        code: (map['code'] ?? '').toString(),
        clientName:
            _nullIfEmpty(map['client_display_name']?.toString()) ??
            _nullIfEmpty(clientMap?['full_name']?.toString()) ??
            'Cliente general',
        status: QuoteStatusX.fromDb(map['status']?.toString()),
        createdAt: createdAt ?? DateTime.now(),
        validUntil: validUntil ?? DateTime.now(),
        total: _toDouble(map['total_amount']),
        itemsCount: itemCounts[map['id'].toString()] ?? 0,
        summary: map['notes']?.toString() ?? '',
        saleId: _nullIfEmpty(map['converted_sale_id']?.toString()),
      );
    };
  }

  Future<void> _appendEvent({
    required String quotationId,
    required String branchId,
    required String eventType,
    Map<String, dynamic>? payload,
  }) async {
    try {
      await _client.from('quotation_events').insert({
        'quotation_id': quotationId,
        'branch_id': branchId,
        'event_type': eventType,
        'payload': payload ?? <String, dynamic>{},
      });
    } catch (_) {
      // Keep the main flow resilient while migration adoption is in progress.
    }
  }

  Future<PreparedPrintJobData?> prepareQuotePrintJob({
    required String quoteId,
    PrintPaperSize paperSize = PrintPaperSize.a4,
  }) async {
    final quoteRow = await _client
        .from('quotations')
        .select(
          'id, branch_id, code, status, created_at, valid_until, notes, '
          'subtotal, tax_amount, total_amount, client_display_name, client_id',
        )
        .eq('id', quoteId)
        .single();

    final quote = Map<String, dynamic>.from(quoteRow as Map);
    final branchId = (quote['branch_id'] ?? '').toString();
    if (branchId.isEmpty) return null;

    // Datos completos del cliente (para el A4): dirección, teléfono, email, RNC.
    final clientId = quote['client_id']?.toString();
    Map<String, dynamic> client = const <String, dynamic>{};
    if (clientId != null && clientId.isNotEmpty) {
      final clientRows = await _client
          .from('clients')
          .select(
            'full_name, legal_name, address, phone, email, '
            'document_type, document_number',
          )
          .eq('id', clientId)
          .eq('branch_id', branchId)
          .limit(1);
      if (clientRows.isNotEmpty) {
        client = Map<String, dynamic>.from(clientRows.first as Map);
      }
    }

    final branchRows = await _client
        .from('branches')
        .select('name, address, phone')
        .eq('id', branchId)
        .limit(1);
    final branch = branchRows.isEmpty
        ? const <String, dynamic>{}
        : Map<String, dynamic>.from(branchRows.first as Map);

    // app_settings (emisor + banco + firmante + observación). RLS por tenant.
    // Se piden todas las columnas para no romper la cotización si la migración
    // de campos del emisor todavía no se aplicó (columnas ausentes → nulas).
    final settingsRows = await _client.from('app_settings').select().limit(1);
    final settings = settingsRows.isEmpty
        ? const <String, dynamic>{}
        : Map<String, dynamic>.from(settingsRows.first as Map);
    final logoBytes = await downloadStorageImageBytes(
      _client,
      settings['company_logo_url']?.toString(),
    );
    final qrBytes = await downloadStorageImageBytes(
      _client,
      settings['company_qr_url']?.toString(),
    );

    final itemRows = await _client
        .from('quotation_items')
        .select(
          'product_name, product_sku, quantity, unit_price, '
          'line_subtotal, line_tax, line_total',
        )
        .eq('quotation_id', quoteId)
        .order('created_at');

    final quoteSource = QuotePrintSource(
      quoteId: quoteId,
      branchId: branchId,
      quoteCode: (quote['code'] ?? '').toString(),
      clientName:
          (quote['client_display_name'] ?? 'Cliente general').toString(),
      issuedAt:
          DateTime.tryParse(quote['created_at']?.toString() ?? '') ??
          DateTime.now(),
      validUntil:
          DateTime.tryParse(quote['valid_until']?.toString() ?? '') ??
          DateTime.now(),
      branchName: (branch['name'] ?? 'Sucursal').toString(),
      branchAddress: _firstNonEmpty([
        settings['company_address'],
        branch['address'],
      ]),
      branchPhone: _firstNonEmpty([
        settings['company_phone'],
        branch['phone'],
      ]),
      branchEmail: _firstNonEmpty([settings['company_email']]),
      branchTaxId: _firstNonEmpty([settings['company_tax_id']]),
      branchLogoBytes: logoBytes,
      qrBytes: qrBytes,
      bankInfo: _firstNonEmpty([settings['company_bank_info']]),
      signatoryName: _firstNonEmpty([settings['company_signatory_name']]),
      signatoryTitle: _firstNonEmpty([settings['company_signatory_title']]),
      observation: _firstNonEmpty([settings['invoice_observation']]),
      showItbis: settings['invoice_show_itbis'] != false,
      clientLegalName: _firstNonEmpty([client['legal_name']]),
      clientDocument: _clientDocLabel(
        client['document_type']?.toString(),
        client['document_number']?.toString(),
      ),
      clientAddress: _firstNonEmpty([client['address']]),
      clientPhone: _firstNonEmpty([client['phone']]),
      clientEmail: _firstNonEmpty([client['email']]),
      notes: _nullIfEmpty(quote['notes']?.toString()),
      subtotal: _toDouble(quote['subtotal']),
      taxAmount: _toDouble(quote['tax_amount']),
      totalAmount: _toDouble(quote['total_amount']),
      items: itemRows
          .map((row) => Map<String, dynamic>.from(row as Map))
          .map(
            (item) => QuotePrintItemSource(
              description: (item['product_name'] ?? '').toString(),
              quantity: _toDouble(item['quantity']),
              unitPrice: _toDouble(item['unit_price']),
              lineSubtotal: _toDouble(item['line_subtotal']),
              lineTax: _toDouble(item['line_tax']),
              lineTotal: _toDouble(item['line_total']),
              sku: item['product_sku']?.toString(),
            ),
          )
          .toList(growable: false),
    );

    return _quotePrintService.prepareQuotePreview(
      quote: quoteSource,
      paperSize: paperSize,
    );
  }

  Future<String?> _currentBranchId() async {
    final result = await _client.rpc('current_branch_id');
    if (result == null) return null;
    final value = result.toString().trim();
    return value.isEmpty ? null : value;
  }

  String _buildQuoteCode() {
    final now = DateTime.now();
    final y = now.year.toString();
    final m = now.month.toString().padLeft(2, '0');
    final d = now.day.toString().padLeft(2, '0');
    final hh = now.hour.toString().padLeft(2, '0');
    final mm = now.minute.toString().padLeft(2, '0');
    final ss = now.second.toString().padLeft(2, '0');
    return 'COT-$y$m$d-$hh$mm$ss';
  }
}

Map<String, dynamic> _normalizeMap(dynamic value) {
  return Map<String, dynamic>.from(value as Map);
}

Map<String, dynamic>? _parseMaybeMap(dynamic result) {
  if (result is Map<String, dynamic>) {
    return result;
  }
  if (result is Map) {
    return Map<String, dynamic>.from(result);
  }
  if (result is List && result.isNotEmpty && result.first is Map) {
    return Map<String, dynamic>.from(result.first as Map);
  }
  return null;
}

String? _nullIfEmpty(String? value) {
  if (value == null) return null;
  final trimmed = value.trim();
  return trimmed.isEmpty ? null : trimmed;
}

/// Primer valor no vacío de la lista (tras trim), o null. Para preferir un
/// campo de configuración sobre el de la sucursal.
String? _firstNonEmpty(List<dynamic> values) {
  for (final v in values) {
    final s = v?.toString().trim();
    if (s != null && s.isNotEmpty) return s;
  }
  return null;
}

/// Etiqueta del documento del cliente para el A4 (ej. "RNC: 130..." o
/// "Cédula: 001..."). `null` si no hay número.
String? _clientDocLabel(String? type, String? number) {
  final n = (number ?? '').trim();
  if (n.isEmpty) return null;
  final t = (type ?? '').trim().toLowerCase();
  final prefix = t == 'rnc'
      ? 'RNC'
      : (t.contains('céd') || t.contains('ced'))
          ? 'Cédula'
          : (t.contains('pas'))
              ? 'Pasaporte'
              : (t.isEmpty ? 'Doc' : type!.toUpperCase());
  return '$prefix: $n';
}

double _toDouble(dynamic value) {
  if (value == null) return 0;
  if (value is num) return value.toDouble();
  return double.tryParse(value.toString()) ?? 0;
}
