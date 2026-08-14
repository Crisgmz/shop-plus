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
      if (input.disallowNoStock && product.stock <= 0) {
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
              line.quantity > line.availableStock) {
            throw SaleCheckoutValidationException(
              'Stock insuficiente para ${line.description}. Disponible: ${line.availableStock.toStringAsFixed(line.availableStock % 1 == 0 ? 0 : 3)}.',
            );
          }

          final taxRate = chargesTax ? line.taxRate : 0.0;
          final lineSubtotal = round2(line.quantity * line.unitPrice);
          final lineTax = round2(lineSubtotal * (taxRate / 100));
          final lineTotal = round2(lineSubtotal + lineTax);

          return NormalizedSaleCheckoutItem(
            productId: line.productId,
            description: line.description,
            quantity: line.quantity,
            availableStock: line.availableStock,
            unitPrice: line.unitPrice,
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

    final subtotal = round2(
      lines.fold<double>(0, (sum, item) => sum + item.lineSubtotal),
    );
    final taxAmount = round2(
      lines.fold<double>(0, (sum, item) => sum + item.lineTax),
    );
    final total = round2(subtotal + taxAmount);
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
    this.imeis = const <String>[],
  });

  final SaleCheckoutSourceProduct product;
  final double quantity;
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
  });

  final String id;
  final String name;
  final double price;
  final double taxRate;
  final double stock;
  final bool isActive;
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
    this.imeis = const <String>[],
  });

  final String productId;
  final String description;
  final double quantity;
  final double availableStock;
  final double unitPrice;
  final double taxRate;
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
    List<String>? imeis,
  }) : imeis = [...?imeis];

  final String productId;
  final String description;
  double quantity;
  final double availableStock;
  final double unitPrice;
  final double taxRate;
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
