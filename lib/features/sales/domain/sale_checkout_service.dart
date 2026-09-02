class SaleCheckoutService {
  const SaleCheckoutService();

  NormalizedSaleCheckout normalize(SaleCheckoutServiceInput input) {
    if (input.items.isEmpty) {
      throw const SaleCheckoutValidationException(
        'No hay productos en el carrito.',
      );
    }

    final receiptType = normalizeReceiptType(input.receiptType);
    // Una venta sin comprobante es una nota de venta no fiscal: no factura
    // ITBIS. Espeja `v_line_tax_rate` del RPC `checkout_sale_transactional`
    // (migración 64), que es quien fija los totales que se guardan.
    final chargesTax = receiptType != 'none';
    final normalizedItems = <String, _MutableSaleLine>{};

    for (final item in input.items) {
      final product = item.product;
      if (!product.isActive) {
        throw SaleCheckoutValidationException(
          'El producto ${product.name} no está activo.',
        );
      }
      if (item.quantity <= 0) {
        throw SaleCheckoutValidationException(
          'La cantidad de ${product.name} debe ser mayor que cero.',
        );
      }
      if (product.price < 0) {
        throw SaleCheckoutValidationException(
          'El precio de ${product.name} no es válido.',
        );
      }
      if (product.taxRate < 0 || product.taxRate > 100) {
        throw SaleCheckoutValidationException(
          'La tasa de impuesto de ${product.name} no es válida.',
        );
      }

      // Guarda app_settings.inv_disallow_no_stock — bloquea el carrito antes
      // de calcular líneas si el stock disponible <= 0 y el flag está activo.
      // Servicios y productos con stock negativo permitido NO se validan
      // contra el inventario: es la misma regla que aplica el RPC. Sin esto,
      // un servicio (stock 0 por naturaleza) no se podía vender.
      if (input.disallowNoStock &&
          product.tracksStock &&
          product.stock <= 0) {
        throw SaleCheckoutValidationException(
          'El producto ${product.name} no tiene stock disponible.',
        );
      }

      final existing = normalizedItems[product.id];
      if (existing == null) {
        normalizedItems[product.id] = _MutableSaleLine(
          productId: product.id,
          description: product.name,
          quantity: item.quantity,
          availableStock: product.stock,
          unitPrice: round2(product.price),
          taxRate: round2(product.taxRate),
          discountPct: item.discountPct,
          isTaxExempt: product.isTaxExempt,
          priceIncludesTax: product.priceIncludesTax,
          tracksStock: product.tracksStock,
          imeis: item.imeis,
        );
      } else {
        existing.quantity = round3(existing.quantity + item.quantity);
        existing.imeis.addAll(item.imeis);
      }
    }

    final lines = normalizedItems.values
        .map((line) {
          // Solo enforzamos la validación de "cantidad > stock" cuando el
          // setting global está prendido. Si el dueño permite venta sin
          // stock, dejamos pasar y que el RPC decida (con el flag por
          // producto si aplica).
          if (input.disallowNoStock &&
              line.tracksStock &&
              line.quantity > line.availableStock) {
            throw SaleCheckoutValidationException(
              'Stock insuficiente para ${line.description}. Disponible: ${line.availableStock.toStringAsFixed(line.availableStock % 1 == 0 ? 0 : 3)}.',
            );
          }

          // Espeja la tasa efectiva del RPC: sin comprobante o producto
          // exento ⇒ 0. Si el POS cobrara la tasa de un exento, el total en
          // pantalla no coincidiría con el que se registra.
          final taxRate = (chargesTax && !line.isTaxExempt) ? line.taxRate : 0.0;

          // Todo en CENTAVOS ENTEROS: Postgres calcula con `numeric` (decimal
          // exacto) y Dart con doubles. Un neto que caiga justo en medio
          // centavo redondeaba hacia el otro lado y dejaba la pantalla un
          // centavo por debajo del RPC — suficiente para que un pago dividido
          // rebote con "los pagos no cubren el total".
          final grossC = grossCents(line.quantity, line.unitPrice);
          final discountC = (grossC * (line.discountPct / 100))
              .roundToDouble()
              .clamp(0, grossC)
              .toDouble();
          final netC = grossC - discountC;
          // Precio con ITBIS incluido: el neto ES el total y el impuesto se
          // extrae. Si no, se agrega encima.
          final inclusive = line.priceIncludesTax && taxRate > 0;
          final taxC = taxCents(netC, taxRate, inclusive: inclusive);
          final subtotalC = inclusive ? netC - taxC : netC;
          final totalC = inclusive ? netC : netC + taxC;

          final lineDiscount = fromCents(discountC);
          final lineSubtotal = fromCents(subtotalC);
          final lineTax = fromCents(taxC);
          final lineTotal = fromCents(totalC);

          return NormalizedSaleCheckoutItem(
            productId: line.productId,
            description: line.description,
            quantity: line.quantity,
            availableStock: line.availableStock,
            unitPrice: line.unitPrice,
            discountPct: line.discountPct,
            discountAmount: lineDiscount,
            taxRate: taxRate,
            lineSubtotal: lineSubtotal,
            lineTax: lineTax,
            lineTotal: lineTotal,
            imeis: line.imeis,
          );
        })
        .toList(growable: false);

    if (input.asCredit && !input.creditAllowSales) {
      throw const SaleCheckoutValidationException(
        'Las ventas a crédito están deshabilitadas en la configuración.',
      );
    }

    if (input.asCredit && input.clientId == null) {
      throw const SaleCheckoutValidationException(
        'Para ventas a crédito debe seleccionar un cliente.',
      );
    }

    // Los comprobantes fiscales (B01/B14/B15/B16) exigen identificar al
    // comprador. Consumidor final (B02) y "sin comprobante" no.
    if (receiptType != 'consumer_final' &&
        receiptType != 'none' &&
        input.clientId == null) {
      throw const SaleCheckoutValidationException(
        'Debe seleccionar un cliente para este tipo de comprobante.',
      );
    }

    // Guarda app_settings.customer_required_for_sale — exige cliente para
    // cualquier venta cuando el flag está activo.
    if (input.customerRequiredForSale && input.clientId == null) {
      throw const SaleCheckoutValidationException(
        'La configuración requiere seleccionar un cliente para toda venta.',
      );
    }

    final subtotal = fromCents(
      lines.fold<double>(0, (sum, item) => sum + toCents(item.lineSubtotal)),
    );
    final taxAmount = fromCents(
      lines.fold<double>(0, (sum, item) => sum + toCents(item.lineTax)),
    );
    final total = fromCents(toCents(subtotal) + toCents(taxAmount));
    final saleStatus = input.asCredit ? 'credit' : 'completed';
    final paidAmount = input.asCredit ? 0.0 : total;
    final balanceDue = input.asCredit ? total : 0.0;

    return NormalizedSaleCheckout(
      receiptType: receiptType,
      asCredit: input.asCredit,
      paymentMethod: input.asCredit ? null : (input.paymentMethod ?? 'cash'),
      clientId: input.clientId,
      notes: nullIfBlank(input.notes),
      items: lines,
      subtotal: subtotal,
      taxAmount: taxAmount,
      total: total,
      saleStatus: saleStatus,
      paidAmount: paidAmount,
      balanceDue: balanceDue,
    );
  }
}

class SaleCheckoutServiceInput {
  const SaleCheckoutServiceInput({
    required this.items,
    required this.receiptType,
    required this.asCredit,
    this.paymentMethod,
    this.clientId,
    this.notes,
    this.disallowNoStock = false,
    this.customerRequiredForSale = false,
    this.creditAllowSales = true,
  });

  final List<SaleCheckoutSourceItem> items;
  final String receiptType;
  final bool asCredit;
  final String? paymentMethod;
  final String? clientId;
  final String? notes;

  /// app_settings.inv_disallow_no_stock
  final bool disallowNoStock;

  /// app_settings.customer_required_for_sale
  final bool customerRequiredForSale;

  /// app_settings.credit_allow_sales
  final bool creditAllowSales;
}

class SaleCheckoutSourceItem {
  const SaleCheckoutSourceItem({
    required this.product,
    required this.quantity,
    this.discountPct = 0,
    this.imeis = const <String>[],
  });

  final SaleCheckoutSourceProduct product;
  final double quantity;

  /// Descuento porcentual de la línea (0-100). Viaja al RPC como
  /// `discount_pct`; el servidor lo aplica sobre el bruto.
  final double discountPct;
  final List<String> imeis;
}

class SaleCheckoutSourceProduct {
  const SaleCheckoutSourceProduct({
    required this.id,
    required this.name,
    required this.price,
    required this.taxRate,
    required this.stock,
    required this.isActive,
    this.isService = false,
    this.isTaxExempt = false,
    this.allowNegativeStock = false,
    this.priceIncludesTax = false,
    this.trackInventory = true,
  });

  final String id;
  final String name;
  final double price;
  final double taxRate;
  final double stock;
  final bool isActive;

  /// Banderas que el RPC aplica y el POS tiene que espejar (ver
  /// `SalesProduct`): servicio y stock negativo permitido saltan la
  /// validación de inventario; exento fuerza tasa 0.
  final bool isService;
  final bool isTaxExempt;
  final bool allowNegativeStock;

  /// El precio ya trae el ITBIS adentro: el impuesto se EXTRAE en vez de
  /// agregarse encima. Lo aplica el RPC; si el POS no lo espejara, mostraría
  /// un total mayor al que se cobra.
  final bool priceIncludesTax;

  /// El producto lleva control de inventario. En `false` el RPC no valida
  /// stock ni lo descuenta.
  final bool trackInventory;

  /// Espeja la condición de stock del RPC: solo valida contra inventario si
  /// no es servicio, lleva control de inventario y no permite negativos.
  bool get tracksStock => !isService && trackInventory && !allowNegativeStock;
}

class NormalizedSaleCheckout {
  const NormalizedSaleCheckout({
    required this.receiptType,
    required this.asCredit,
    required this.paymentMethod,
    required this.clientId,
    required this.notes,
    required this.items,
    required this.subtotal,
    required this.taxAmount,
    required this.total,
    required this.saleStatus,
    required this.paidAmount,
    required this.balanceDue,
  });

  final String receiptType;
  final bool asCredit;
  final String? paymentMethod;
  final String? clientId;
  final String? notes;
  final List<NormalizedSaleCheckoutItem> items;
  final double subtotal;
  final double taxAmount;
  final double total;
  final String saleStatus;
  final double paidAmount;
  final double balanceDue;

  List<Map<String, dynamic>> toRpcItems() {
    return items
        .map(
          (item) => <String, dynamic>{
            'product_id': item.productId,
            'description': item.description,
            'quantity': item.quantity,
            'unit_price': item.unitPrice,
            // MONTO absoluto, no porcentaje. La función viva en la base es
            // `checkout_sale_transactional` de la migración 76 del árbol
            // flutter_shop+ (ambos proyectos comparten la misma base) y lee
            // `discount_amount`. Mandar el monto además evita que el
            // porcentaje redondee distinto en Dart y en Postgres y descuadre
            // el pago dividido por centavos.
            'discount_amount': item.discountAmount,
            'tax_rate': item.taxRate,
            if (item.imeis.isNotEmpty) 'imeis': item.imeis,
          },
        )
        .toList(growable: false);
  }
}

class NormalizedSaleCheckoutItem {
  const NormalizedSaleCheckoutItem({
    required this.productId,
    required this.description,
    required this.quantity,
    required this.availableStock,
    required this.unitPrice,
    required this.taxRate,
    required this.lineSubtotal,
    required this.lineTax,
    required this.lineTotal,
    this.discountPct = 0,
    this.discountAmount = 0,
    this.imeis = const <String>[],
  });

  final String productId;
  final String description;
  final double quantity;
  final double availableStock;
  final double unitPrice;
  final double taxRate;

  /// Descuento de la línea: porcentaje aplicado y su monto en pesos.
  final double discountPct;
  final double discountAmount;
  final double lineSubtotal;
  final double lineTax;
  final double lineTotal;
  final List<String> imeis;
}

class SaleCheckoutValidationException implements Exception {
  const SaleCheckoutValidationException(this.message);

  final String message;

  @override
  String toString() => message;
}

class _MutableSaleLine {
  _MutableSaleLine({
    required this.productId,
    required this.description,
    required this.quantity,
    required this.availableStock,
    required this.unitPrice,
    required this.taxRate,
    required this.discountPct,
    required this.isTaxExempt,
    required this.priceIncludesTax,
    required this.tracksStock,
    List<String>? imeis,
  }) : imeis = [...?imeis];

  final String productId;
  final String description;
  double quantity;
  final double availableStock;
  final double unitPrice;
  final double taxRate;
  final double discountPct;
  final bool isTaxExempt;
  final bool priceIncludesTax;
  final bool tracksStock;
  final List<String> imeis;
}

String normalizeReceiptType(String value) {
  final normalized = value
      .trim()
      .toLowerCase()
      .replaceAll('á', 'a')
      .replaceAll('é', 'e')
      .replaceAll('í', 'i')
      .replaceAll('ó', 'o')
      .replaceAll('ú', 'u')
      .replaceAll(RegExp(r'[^a-z0-9]+'), '_')
      .replaceAll(RegExp(r'_+'), '_')
      .replaceAll(RegExp(r'^_|_$'), '');

  switch (normalized) {
    // Sin comprobante: nota de venta no fiscal. No consume NCF, no exige
    // cliente y no factura ITBIS. Espeja `normalize_receipt_type` en SQL.
    case 'none':
    case 'sin_comprobante':
    case 'ninguno':
      return 'none';
    case '':
    case 'consumer_final':
    case 'consumidor_final':
      return 'consumer_final';
    case 'fiscal_credit':
    case 'credito_fiscal':
      return 'fiscal_credit';
    case 'governmental':
    case 'gubernamental':
      return 'governmental';
    case 'special':
    case 'regimen_especial':
      return 'special';
    case 'export':
    case 'exportacion':
      return 'export';
    default:
      throw SaleCheckoutValidationException(
        'Tipo de comprobante no soportado: $value.',
      );
  }
}

String? nullIfBlank(String? value) {
  if (value == null) return null;
  final trimmed = value.trim();
  return trimmed.isEmpty ? null : trimmed;
}

double round2(double value) => (value * 100).roundToDouble() / 100;
double round3(double value) => (value * 1000).roundToDouble() / 1000;

// ---------------------------------------------------------------------------
// Aritmética de dinero en CENTAVOS ENTEROS
// ---------------------------------------------------------------------------
// Postgres calcula con `numeric` (decimal exacto, media hacia arriba); Dart
// con doubles no: 18/100 vale 0.17999999999999999333. Trabajando en centavos
// enteros —y la cantidad en milésimas enteras— el producto es exacto y el
// medio centavo cae del mismo lado que en el SQL. Es lo que hace que el total
// en pantalla sea idéntico al que registra el RPC.

/// Monto en pesos → centavos enteros (equivale a `numeric(14,2)`).
double toCents(double amount) => (amount * 100).roundToDouble();

/// Centavos enteros → monto en pesos.
double fromCents(double cents) => cents / 100;

/// Bruto de la línea en centavos: `round(unit_price × quantity, 2)`.
double grossCents(double quantity, double unitPrice) {
  // La cantidad admite hasta 3 decimales; en milésimas enteras el producto
  // por los centavos del precio es exacto.
  final qtyMilli = (quantity * 1000).roundToDouble();
  return (toCents(unitPrice) * qtyMilli / 1000).roundToDouble();
}

/// ITBIS de la línea en centavos, con la fórmula del RPC.
/// [inclusive] = el precio ya trae el impuesto adentro y se EXTRAE
/// (`neto × t/(100+t)`); si no, se agrega encima (`neto × t/100`).
double taxCents(double netCents, double rate, {bool inclusive = false}) {
  if (rate <= 0 || netCents == 0) return 0;
  // La tasa es numeric(5,2): en centésimas enteras el cociente queda exacto.
  final rateCents = (rate * 100).roundToDouble();
  final denominator = inclusive ? 10000 + rateCents : 10000;
  return (netCents * rateCents / denominator).roundToDouble();
}
