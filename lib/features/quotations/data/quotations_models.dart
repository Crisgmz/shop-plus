class QuoteListItem {
  QuoteListItem({
    required this.id,
    required this.code,
    required this.clientName,
    required this.status,
    required this.createdAt,
    required this.validUntil,
    required this.total,
    required this.itemsCount,
    this.summary = '',
    this.saleId,
  });

  final String id;
  final String code;
  final String clientName;
  final QuoteStatus status;
  final DateTime createdAt;
  final DateTime validUntil;
  final double total;
  final int itemsCount;
  final String summary;
  final String? saleId;

  bool get isExpired =>
      !status.isTerminal && validUntil.isBefore(DateTime.now());
  bool get canEdit => status != QuoteStatus.converted;
  bool get canConvert => status == QuoteStatus.approved && !isExpired;
  bool get canDelete =>
      status == QuoteStatus.draft ||
      status == QuoteStatus.rejected ||
      status == QuoteStatus.expired;

  int get daysRemaining => validUntil.difference(DateTime.now()).inDays;

  QuoteStatus get effectiveStatus => isExpired ? QuoteStatus.expired : status;
}

enum QuoteStatus {
  draft,
  sent,
  underReview,
  approved,
  rejected,
  expired,
  converted,
}

extension QuoteStatusX on QuoteStatus {
  String get label {
    switch (this) {
      case QuoteStatus.draft:
        return 'Borrador';
      case QuoteStatus.sent:
        return 'Enviada';
      case QuoteStatus.underReview:
        return 'En revisión';
      case QuoteStatus.approved:
        return 'Aprobada';
      case QuoteStatus.rejected:
        return 'Perdida';
      case QuoteStatus.expired:
        return 'Expirada';
      case QuoteStatus.converted:
        return 'Convertida';
    }
  }

  bool get isTerminal {
    switch (this) {
      case QuoteStatus.rejected:
      case QuoteStatus.expired:
      case QuoteStatus.converted:
        return true;
      case QuoteStatus.draft:
      case QuoteStatus.sent:
      case QuoteStatus.underReview:
      case QuoteStatus.approved:
        return false;
    }
  }

  String get dbValue {
    switch (this) {
      case QuoteStatus.draft:
        return 'draft';
      case QuoteStatus.sent:
        return 'sent';
      case QuoteStatus.underReview:
        return 'under_review';
      case QuoteStatus.approved:
        return 'approved';
      case QuoteStatus.rejected:
        return 'rejected';
      case QuoteStatus.expired:
        return 'expired';
      case QuoteStatus.converted:
        return 'converted';
    }
  }

  bool get canBeSelectedOnForm => this != QuoteStatus.converted;

  static QuoteStatus fromDb(String? status) {
    switch ((status ?? '').trim().toLowerCase()) {
      case 'draft':
        return QuoteStatus.draft;
      case 'sent':
        return QuoteStatus.sent;
      case 'under_review':
        return QuoteStatus.underReview;
      case 'approved':
        return QuoteStatus.approved;
      case 'rejected':
        return QuoteStatus.rejected;
      case 'expired':
        return QuoteStatus.expired;
      case 'converted':
        return QuoteStatus.converted;
      default:
        return QuoteStatus.draft;
    }
  }
}

class QuoteCatalogProduct {
  QuoteCatalogProduct({
    required this.id,
    required this.name,
    required this.price,
    required this.taxRate,
    required this.stock,
    required this.isActive,
    this.sku,
    this.barcode,
    this.description,
  });

  final String id;
  final String name;
  final String? sku;
  final String? barcode;
  final String? description;
  final double price;
  final double taxRate;
  final double stock;
  final bool isActive;

  factory QuoteCatalogProduct.fromMap(Map<String, dynamic> map) {
    return QuoteCatalogProduct(
      id: (map['id'] ?? '').toString(),
      name: (map['name'] ?? '').toString(),
      sku: map['sku']?.toString(),
      barcode: map['barcode']?.toString(),
      description: map['description']?.toString(),
      price: _toDouble(map['price']),
      taxRate: _toDouble(map['tax_rate']),
      stock: _toDouble(map['stock']),
      isActive: map['is_active'] == true,
    );
  }
}

class QuoteClientOption {
  QuoteClientOption({
    required this.id,
    required this.fullName,
    this.legalName,
    this.email,
    this.phone,
    this.documentType,
    this.documentNumber,
  });

  final String id;
  final String fullName;
  final String? legalName;
  final String? email;
  final String? phone;
  final String? documentType;
  final String? documentNumber;

  factory QuoteClientOption.fromMap(Map<String, dynamic> map) {
    return QuoteClientOption(
      id: (map['id'] ?? '').toString(),
      fullName: (map['full_name'] ?? '').toString(),
      legalName: map['legal_name']?.toString(),
      email: map['email']?.toString(),
      phone: map['phone']?.toString(),
      documentType: map['document_type']?.toString(),
      documentNumber: map['document_number']?.toString(),
    );
  }
}

class QuoteDraftLine {
  QuoteDraftLine({
    required this.product,
    required this.quantity,
    double? unitPrice,
    this.discountPct = 0,
  }) : unitPrice = unitPrice ?? product.price;

  final QuoteCatalogProduct product;
  final double quantity;

  /// Precio unitario editable por línea (arranca en `product.price`).
  final double unitPrice;

  /// Descuento en porcentaje (0..100) aplicado al precio unitario.
  final double discountPct;

  double get netUnitPrice =>
      QuotationsMath.round2(unitPrice * (1 - discountPct / 100));
  double get lineSubtotal => QuotationsMath.round2(quantity * netUnitPrice);
  double get lineTax =>
      QuotationsMath.round2(lineSubtotal * (product.taxRate / 100));
  double get lineTotal => QuotationsMath.round2(lineSubtotal + lineTax);

  /// Monto absoluto del descuento (para persistir en `discount_amount`).
  double get discountAmount =>
      QuotationsMath.round2(quantity * unitPrice - lineSubtotal);

  QuoteDraftLine copyWith({
    QuoteCatalogProduct? product,
    double? quantity,
    double? unitPrice,
    double? discountPct,
  }) {
    return QuoteDraftLine(
      product: product ?? this.product,
      quantity: quantity ?? this.quantity,
      unitPrice: unitPrice ?? this.unitPrice,
      discountPct: discountPct ?? this.discountPct,
    );
  }
}

class QuoteCreateInput {
  QuoteCreateInput({
    required this.clientId,
    required this.items,
    required this.validUntil,
    required this.status,
    this.notes,
  });

  final String? clientId;
  final List<QuoteCreateItem> items;
  final DateTime validUntil;
  final QuoteStatus status;
  final String? notes;
}

class QuoteCreateItem {
  QuoteCreateItem({
    required this.productId,
    required this.productName,
    required this.quantity,
    required this.unitPrice,
    required this.taxRate,
    this.discountAmount = 0,
    this.productSku,
    this.productDescription,
  });

  final String productId;
  final String productName;
  final String? productSku;
  final String? productDescription;
  final double quantity;
  final double unitPrice;
  final double taxRate;
  final double discountAmount;

  factory QuoteCreateItem.fromMap(Map<String, dynamic> map) {
    return QuoteCreateItem(
      productId: (map['product_id'] ?? '').toString(),
      productName: (map['product_name'] ?? map['description'] ?? '').toString(),
      productSku: map['product_sku']?.toString(),
      productDescription: map['description']?.toString(),
      quantity: _toDouble(map['quantity']),
      unitPrice: _toDouble(map['unit_price']),
      taxRate: _toDouble(map['tax_rate']),
      discountAmount: _toDouble(map['discount_amount']),
    );
  }

  double get lineSubtotal =>
      QuotationsMath.round2(quantity * unitPrice - discountAmount);
  double get lineTax => QuotationsMath.round2(lineSubtotal * (taxRate / 100));
  double get lineTotal => QuotationsMath.round2(lineSubtotal + lineTax);

  Map<String, dynamic> toRpcMap() {
    return {
      'product_id': productId,
      'product_name': productName,
      'product_sku': productSku,
      'description': productDescription ?? productName,
      'quantity': quantity,
      'unit_price': unitPrice,
      'discount_amount': discountAmount,
      'tax_rate': taxRate,
      'line_subtotal': lineSubtotal,
      'line_tax': lineTax,
      'line_total': lineTotal,
    };
  }
}

class QuoteDetail {
  QuoteDetail({
    required this.id,
    required this.code,
    required this.clientId,
    required this.clientName,
    required this.status,
    required this.createdAt,
    required this.validUntil,
    required this.notes,
    required this.items,
    required this.subtotal,
    required this.taxAmount,
    required this.totalAmount,
    this.saleId,
  });

  final String id;
  final String code;
  final String? clientId;
  final String clientName;
  final QuoteStatus status;
  final DateTime createdAt;
  final DateTime validUntil;
  final String notes;
  final List<QuoteCreateItem> items;
  final double subtotal;
  final double taxAmount;
  final double totalAmount;
  final String? saleId;

  bool get isExpired =>
      !status.isTerminal && validUntil.isBefore(DateTime.now());
  bool get canEdit => status != QuoteStatus.converted;
  bool get canConvert => status == QuoteStatus.approved && !isExpired;
  bool get canDelete =>
      status == QuoteStatus.draft ||
      status == QuoteStatus.rejected ||
      status == QuoteStatus.expired;

  QuoteStatus get effectiveStatus => isExpired ? QuoteStatus.expired : status;

  factory QuoteDetail.fromMaps({
    required Map<String, dynamic> quote,
    required List<Map<String, dynamic>> items,
  }) {
    final createdAt =
        DateTime.tryParse(quote['created_at']?.toString() ?? '') ??
        DateTime.now();
    final validUntil =
        DateTime.tryParse(quote['valid_until']?.toString() ?? '') ??
        DateTime.now();

    return QuoteDetail(
      id: (quote['id'] ?? '').toString(),
      code: (quote['code'] ?? '').toString(),
      clientId: _nullIfEmpty(quote['client_id']?.toString()),
      clientName:
          _nullIfEmpty(quote['client_display_name']?.toString()) ??
          _nullIfEmpty(
            (quote['clients'] as Map?)?['full_name']?.toString(),
          ) ??
          'Cliente general',
      status: QuoteStatusX.fromDb(quote['status']?.toString()),
      createdAt: createdAt,
      validUntil: validUntil,
      notes: quote['notes']?.toString() ?? '',
      items: items.map(QuoteCreateItem.fromMap).toList(growable: false),
      subtotal: _toDouble(quote['subtotal']),
      taxAmount: _toDouble(quote['tax_amount']),
      totalAmount: _toDouble(quote['total_amount']),
      saleId: _nullIfEmpty(quote['converted_sale_id']?.toString()),
    );
  }
}

class QuoteConversionResult {
  QuoteConversionResult({required this.saleId, required this.saleNumber});

  final String saleId;
  final String saleNumber;
}

class QuoteMetric {
  QuoteMetric({
    required this.label,
    required this.value,
    required this.helpText,
    this.highlight = false,
  });

  final String label;
  final String value;
  final String helpText;
  final bool highlight;
}

class QuotePipelineStage {
  QuotePipelineStage({
    required this.label,
    required this.count,
    required this.amount,
    required this.note,
  });

  final String label;
  final int count;
  final double amount;
  final String note;
}

class QuoteFoundationBundle {
  QuoteFoundationBundle({
    required this.metrics,
    required this.pipeline,
    required this.recentQuotes,
  });

  final List<QuoteMetric> metrics;
  final List<QuotePipelineStage> pipeline;
  final List<QuoteListItem> recentQuotes;
}

abstract class QuotationsRepositoryContract {
  Future<QuoteFoundationBundle> loadFoundation();
  Future<List<QuoteListItem>> fetchQuotes();
  Future<QuoteDetail> fetchQuoteDetail(String quoteId);
  Future<List<QuoteCatalogProduct>> fetchProducts();
  Future<List<QuoteClientOption>> fetchClients();
  Future<String> createQuote(QuoteCreateInput input);
  Future<void> updateQuote(String quoteId, QuoteCreateInput input);
  Future<QuoteConversionResult> convertToSale(
    String quoteId, {
    required String paymentMethod,
    String? cashSessionId,
  });
  Future<void> deleteQuote(String quoteId);
}

class QuotationsMath {
  static double subtotal(List<QuoteCreateItem> items) =>
      round2(items.fold<double>(0, (sum, item) => sum + item.lineSubtotal));

  static double tax(List<QuoteCreateItem> items) =>
      round2(items.fold<double>(0, (sum, item) => sum + item.lineTax));

  static double total(List<QuoteCreateItem> items) =>
      round2(subtotal(items) + tax(items));

  static double round2(double value) => (value * 100).roundToDouble() / 100;
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
