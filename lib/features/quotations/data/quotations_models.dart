import '../../../shared/packaging/product_packaging.dart';

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
    this.clientId,
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

  /// Cliente del catálogo. `null` con nombre escrito a mano: esa cotización
  /// no puede convertirse a crédito, porque la deuda necesita una cuenta.
  final String? clientId;

  bool get isExpired =>
      !status.isTerminal && validUntil.isBefore(DateTime.now());
  bool get canEdit => status != QuoteStatus.converted;

  /// El vencimiento NO bloquea la conversión: es informativo. Una cotización
  /// vencida se sigue pudiendo cobrar sin tener que revalidarla primero
  /// (la RPC `convert_quotation_to_sale` acepta `approved` y `expired`).
  bool get canConvert =>
      saleId == null &&
      (status == QuoteStatus.approved ||
          effectiveStatus == QuoteStatus.expired);
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

/// Opciones del desplegable "Estado" de la cotización.
///
/// "Convertida" no se elige a mano, pero una cotización YA convertida la tiene
/// como estado actual, y `DropdownButtonFormField` exige que su valor esté
/// entre los items: sin esto, abrir o convertir una cotización reventaba con
/// "There should be exactly one item with [DropdownButton]'s value".
List<QuoteStatus> quoteStatusOptions(QuoteStatus current) => [
  ...QuoteStatus.values.where((status) => status.canBeSelectedOnForm),
  if (!current.canBeSelectedOnForm) current,
];

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
    this.packaging = ProductPackaging.none,
    this.isTaxExempt = false,
    this.priceIncludesTax = false,
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

  /// Exento: no lleva ITBIS aunque tenga tasa (como en el POS).
  final bool isTaxExempt;

  /// El precio ya trae el ITBIS: se EXTRAE en vez de sumarse encima. Antes la
  /// cotización lo sumaba y un producto de 118 salía en 139.24.
  final bool priceIncludesTax;

  double get effectiveTaxRate => isTaxExempt ? 0 : taxRate;

  /// Caja / paquete y sus precios, igual que en el POS. Sin empaque, la
  /// línea se cotiza por unidad como siempre.
  final ProductPackaging packaging;

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
      packaging: ProductPackaging.fromMap(map),
      isTaxExempt: map['is_tax_exempt'] == true,
      priceIncludesTax: map['price_includes_tax'] == true,
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
    this.uom = PackagingUom.unit,
    this.presentationPriceOverride,
  }) : unitPrice = unitPrice ?? product.price;

  final QuoteCatalogProduct product;

  /// Cantidad EN LA PRESENTACIÓN de la línea: 2 cajas son `quantity` 2.
  final double quantity;

  /// Precio de la unidad base (arranca en `product.price`).
  final double unitPrice;

  /// Descuento en porcentaje (0..100) aplicado al precio de la presentación.
  final double discountPct;

  /// Presentación cotizada: caja, paquete o suelto.
  final PackagingUom uom;

  /// Precio escrito a mano para la presentación. Manda sobre el configurado.
  final double? presentationPriceOverride;

  bool get isPresentation => uom != PackagingUom.unit;

  /// Unidades base que representa UNA presentación (1 caja = 20 paquetes).
  double get uomFactor => product.packaging.factorFor(uom);

  /// Nombre de la presentación para la factura ("Caja").
  String get unitName => product.packaging.labelFor(uom);

  /// Precio de UNA presentación: el propio de la caja si está configurado.
  double get presentationPrice =>
      presentationPriceOverride ??
      product.packaging.priceFor(uom, unitPrice);

  /// Cantidad en unidades base: es la que viaja a la base y la que descuenta
  /// inventario al convertir la cotización en venta.
  double get baseQuantity => product.packaging.toBaseUnits(quantity, uom);

  double get netUnitPrice =>
      QuotationsMath.round2(presentationPrice * (1 - discountPct / 100));

  /// Bruto menos descuento: con precio ITBIS-incluido ya es el total.
  double get lineNet => QuotationsMath.round2(quantity * netUnitPrice);

  bool get _taxIncluded =>
      product.priceIncludesTax && product.effectiveTaxRate > 0;

  double get lineTax => QuotationsMath.lineTax(
        lineNet,
        product.effectiveTaxRate,
        inclusive: _taxIncluded,
      );
  double get lineSubtotal =>
      _taxIncluded ? QuotationsMath.round2(lineNet - lineTax) : lineNet;
  double get lineTotal =>
      _taxIncluded ? lineNet : QuotationsMath.round2(lineNet + lineTax);

  /// Monto absoluto del descuento (para persistir en `discount_amount`).
  double get discountAmount =>
      QuotationsMath.round2(quantity * presentationPrice - lineNet);

  QuoteDraftLine copyWith({
    QuoteCatalogProduct? product,
    double? quantity,
    double? unitPrice,
    double? discountPct,
    PackagingUom? uom,
    double? presentationPriceOverride,
    bool clearPresentationPrice = false,
  }) {
    return QuoteDraftLine(
      product: product ?? this.product,
      quantity: quantity ?? this.quantity,
      unitPrice: unitPrice ?? this.unitPrice,
      discountPct: discountPct ?? this.discountPct,
      uom: uom ?? this.uom,
      presentationPriceOverride: clearPresentationPrice
          ? null
          : (presentationPriceOverride ?? this.presentationPriceOverride),
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
    this.clientName,
  });

  final String? clientId;
  final List<QuoteCreateItem> items;
  final DateTime validUntil;
  final QuoteStatus status;
  final String? notes;

  /// Nombre escrito a mano cuando la cotización no apunta a un cliente del
  /// catálogo ([clientId] null). Se guarda en `quotations.client_display_name`
  /// y es lo que se ve en el listado y en el PDF. Si viene vacío, la
  /// cotización queda como "Cliente general".
  final String? clientName;
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
    this.uom = 'unit',
    this.uomFactor = 1,
    this.uomPrice,
    this.unitName,
    this.priceIncludesTax = false,
  });

  final String productId;
  final String productName;
  final String? productSku;
  final String? productDescription;
  final double quantity;
  final double unitPrice;
  final double taxRate;
  final double discountAmount;

  /// Presentación cotizada: 'unit' | 'pack' | 'box'. `quantity` va SIEMPRE en
  /// unidades base, igual que en las ventas, para que al convertir la
  /// cotización el inventario descuente bien.
  final String uom;

  /// Unidades base que representa UNA presentación (1 caja = 20 paquetes).
  final double uomFactor;

  /// Precio de UNA presentación. NULL = la línea va por unidad base.
  final double? uomPrice;

  /// Cómo se llama la presentación en el documento ("Caja").
  final String? unitName;

  /// El precio ya trae el ITBIS: se extrae (ver [QuoteCatalogProduct]).
  final bool priceIncludesTax;

  bool get isPresentation => uom != 'unit' && uomPrice != null && uomFactor > 0;

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
      uom: (map['uom']?.toString().trim().isNotEmpty ?? false)
          ? map['uom'].toString().trim().toLowerCase()
          : 'unit',
      uomFactor: map['uom_factor'] == null ? 1 : _toDouble(map['uom_factor']),
      uomPrice: map['uom_price'] == null ? null : _toDouble(map['uom_price']),
      unitName: map['unit_name']?.toString(),
      // No hay columna: se deduce de lo guardado. Con precio ITBIS-incluido
      // el total de la línea es el neto (bruto − descuento).
      priceIncludesTax: _looksTaxIncluded(map),
    );
  }

  /// Cantidad en la presentación: 40 paquetes en cajas de 20 son 2 cajas.
  double get presentationQuantity =>
      isPresentation ? quantity / uomFactor : quantity;

  /// El bruto sale del precio de la presentación cuando la línea la trae, como
  /// hace el checkout desde la migración 92: una caja a 2,639.83 no es
  /// 131.99 × 20 (= 2,639.80).
  /// Bruto menos descuento. El bruto sale del precio de la presentación
  /// cuando la línea la trae, como hace el checkout desde la migración 92.
  double get lineNet => isPresentation
      ? QuotationsMath.round2(
          uomPrice! * presentationQuantity - discountAmount,
        )
      : QuotationsMath.round2(quantity * unitPrice - discountAmount);

  bool get _taxIncluded => priceIncludesTax && taxRate > 0;

  double get lineTax =>
      QuotationsMath.lineTax(lineNet, taxRate, inclusive: _taxIncluded);
  double get lineSubtotal =>
      _taxIncluded ? QuotationsMath.round2(lineNet - lineTax) : lineNet;
  double get lineTotal =>
      _taxIncluded ? lineNet : QuotationsMath.round2(lineNet + lineTax);

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
      // Solo cuando hay presentación: una línea suelta viaja como siempre y la
      // función la guarda con `uom` nulo.
      if (isPresentation) ...{
        'uom': uom,
        'uom_factor': uomFactor,
        'uom_price': uomPrice,
        'unit_name': unitName ?? '',
      },
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

  /// Igual que en [QuoteListItem]: vencida también se convierte.
  bool get canConvert =>
      saleId == null &&
      (status == QuoteStatus.approved ||
          effectiveStatus == QuoteStatus.expired);
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
    bool asCredit = false,
    int? creditDueDays,
    String receiptType = 'consumer_final',
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

  /// ITBIS de una línea, con la fórmula del checkout: encima del neto, o
  /// extraído de él si el precio ya lo incluye.
  static double lineTax(double net, double rate, {bool inclusive = false}) {
    if (rate <= 0) return 0;
    return round2(inclusive ? net * rate / (100 + rate) : net * rate / 100);
  }
}

/// Una línea guardada con precio ITBIS-incluido tiene total = neto.
bool _looksTaxIncluded(Map<String, dynamic> map) {
  final tax = _toDouble(map['line_tax']);
  if (tax <= 0) return false;
  final total = _toDouble(map['line_total']);
  final subtotal = _toDouble(map['line_subtotal']);
  final discount = _toDouble(map['discount_amount']);
  final factor = _toDouble(map['uom_factor']);
  final uomPrice = map['uom_price'] == null ? null : _toDouble(map['uom_price']);
  final quantity = _toDouble(map['quantity']);
  final gross = uomPrice != null && factor > 0
      ? uomPrice * quantity / factor
      : quantity * _toDouble(map['unit_price']);
  final net = gross - discount;
  return (net - total).abs() < (net - subtotal).abs();
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
