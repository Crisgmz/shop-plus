import 'printing_models.dart';

class SalePrintSource {
  const SalePrintSource({
    required this.saleId,
    required this.branchId,
    required this.saleNumber,
    required this.status,
    required this.saleDate,
    required this.receiptType,
    required this.branchName,
    required this.items,
    required this.subtotal,
    required this.taxAmount,
    required this.totalAmount,
    this.discountAmount = 0,
    this.serviceChargeAmount = 0,
    this.paidAmount = 0,
    this.balanceDue = 0,
    this.branchAddress,
    this.branchPhone,
    this.branchTaxId,
    this.branchLogoBytes,
    this.branchEmail,
    this.bankInfo,
    this.signatoryName,
    this.signatoryTitle,
    this.observation,
    this.clientName,
    this.clientDocument,
    this.clientAddress,
    this.clientPhone,
    this.clientEmail,
    this.cashierName,
    this.ncf,
    this.notes,
    this.payments = const <SalePrintPaymentSource>[],
    this.cashRegisterName,
    this.priceTierLabel,
    this.changeAmount,
    this.showBarcode = true,
    this.showItbis = true,
    this.qrBytes,
    this.hideTaxBreakdown,
  });

  final String saleId;
  final String branchId;
  final String saleNumber;
  final String status;
  final DateTime saleDate;
  final String receiptType;
  final String branchName;
  final String? branchAddress;
  final String? branchPhone;
  final String? branchTaxId;
  final List<int>? branchLogoBytes;
  final String? branchEmail;
  final String? bankInfo;
  final String? signatoryName;
  final String? signatoryTitle;
  final String? observation;
  final String? clientName;
  final String? clientDocument;
  final String? clientAddress;
  final String? clientPhone;
  final String? clientEmail;
  final String? cashierName;
  final String? ncf;
  final String? notes;
  final List<SalePrintItemSource> items;
  final List<SalePrintPaymentSource> payments;
  final double subtotal;
  final double discountAmount;
  final double serviceChargeAmount;
  final double taxAmount;
  final double totalAmount;
  final double paidAmount;
  final double balanceDue;

  /// Nombre/código de la caja registradora abierta en el momento de la venta.
  final String? cashRegisterName;

  /// Etiqueta del nivel de precio aplicado (ej. "Mayorista", "Minorista").
  final String? priceTierLabel;

  /// Cambio entregado al cliente (paid - total). Si null se omite.
  final double? changeAmount;

  /// Si false oculta el barcode del recibo (alineado con
  /// `app_settings.receipt_hide_barcode`).
  final bool showBarcode;

  /// Si false, nunca se muestra el ITBIS en el documento A4 (toggle de config).
  final bool showItbis;

  /// Bytes del QR (descargado de company_qr_url). Null → fallback al asset.
  final List<int>? qrBytes;

  /// ITBIS cobrado pero sin desglose: precios y total con el impuesto
  /// adentro. Null = la regla de siempre (solo Consumidor Final, B02). La nota
  /// de crédito de una venta B02 lo pasa en true: se muestra igual que la
  /// factura que modifica.
  final bool? hideTaxBreakdown;
}

class SalePrintItemSource {
  const SalePrintItemSource({
    required this.description,
    required this.quantity,
    required this.unitPrice,
    required this.lineSubtotal,
    required this.lineTax,
    required this.lineTotal,
    this.sku,
    this.unitLabel,
    this.notes,
    this.presentationLabel,
    this.lineDiscount = 0,
    this.baseUnitLabel,
  });

  final String description;
  final double quantity;
  final double unitPrice;
  final double lineSubtotal;
  final double lineTax;
  final double lineTotal;
  final String? sku;
  final String? unitLabel;
  final String? notes;

  /// Ver [PrintDocumentItem.presentationLabel].
  final String? presentationLabel;

  /// Monto de descuento de la línea (`sale_items.discount_amount`). Sirve para
  /// saber si [unitPrice] ya traía el ITBIS adentro.
  final double lineDiscount;

  /// Unidad base del producto (`products.unit_label`). Ver
  /// [PrintDocumentItem.baseUnitLabel].
  final String? baseUnitLabel;
}

class SalePrintPaymentSource {
  const SalePrintPaymentSource({
    required this.method,
    required this.amount,
    this.reference,
  });

  final String method;
  final double amount;
  final String? reference;
}

class SalePrintDocumentAdapter {
  const SalePrintDocumentAdapter();

  PrintDocumentData toDocumentData(SalePrintSource source) {
    // Si alguna línea va por presentación ("1 Caja"), las sueltas dicen en qué
    // unidad van ("6 Paquetes"); si ninguna, siguen saliendo "6" como siempre.
    final mixesPresentations = source.items.any(
      (i) => (i.presentationLabel ?? '').trim().isNotEmpty,
    );
    // Consumidor Final: el ITBIS se cobra y queda registrado en la venta (607,
    // reportes), pero el documento no lo desglosa — precios, subtotal y total
    // salen con el impuesto adentro, igual que en la caja.
    final taxIncluded =
        source.hideTaxBreakdown ?? source.receiptType == 'consumer_final';
    return PrintDocumentData(
      documentType: _documentTypeForSale(source),
      documentNumber: source.saleNumber,
      issuedAt: source.saleDate,
      branch: PrintBranchIdentity(
        name: source.branchName,
        address: _nullIfBlank(source.branchAddress),
        phone: _nullIfBlank(source.branchPhone),
        email: _nullIfBlank(source.branchEmail),
        taxId: _nullIfBlank(source.branchTaxId),
        logoBytes: source.branchLogoBytes,
        bankInfo: _nullIfBlank(source.bankInfo),
        signatoryName: _nullIfBlank(source.signatoryName),
        signatoryTitle: _nullIfBlank(source.signatoryTitle),
      ),
      customer: _customerForSale(source),
      cashierName: _nullIfBlank(source.cashierName),
      cashRegisterName: _nullIfBlank(source.cashRegisterName),
      priceTierLabel: _nullIfBlank(source.priceTierLabel),
      changeAmount: source.changeAmount,
      showBarcode: source.showBarcode,
      receiptTypeLabel: _receiptTypeLabel(source.receiptType),
      paymentTermsLabel: source.receiptType == 'credit_note'
          ? 'DEVOLUCIÓN'
          : source.balanceDue > 0.0049
              ? 'CRÉDITO'
              : 'CONTADO',
      // ITBIS solo si: el toggle de config está activo, NO es venta sin
      // comprobante, y al menos un ítem realmente lleva impuesto.
      showTax:
          source.showItbis &&
          source.receiptType != 'none' &&
          !taxIncluded &&
          source.items.any((i) => i.lineTax > 0.0049),
      qrBytes: source.qrBytes,
      observation: _nullIfBlank(source.observation),
      ncf: _nullIfBlank(source.ncf),
      notes: _nullIfBlank(source.notes),
      footerMessage: source.receiptType == 'credit_note'
          ? 'Documento de devolución'
          : 'Gracias por su compra',
      items: source.items
          .map(
            (item) => PrintDocumentItem(
              description: item.description,
              quantity: item.quantity,
              unitPrice: taxIncluded ? _unitPriceWithTax(item) : item.unitPrice,
              lineSubtotal: taxIncluded ? item.lineTotal : item.lineSubtotal,
              lineTax: taxIncluded ? 0 : item.lineTax,
              lineTotal: item.lineTotal,
              sku: _nullIfBlank(item.sku),
              unitLabel: _nullIfBlank(item.unitLabel),
              notes: _nullIfBlank(item.notes),
              presentationLabel: _nullIfBlank(item.presentationLabel),
              baseUnitLabel: mixesPresentations
                  ? _nullIfBlank(item.baseUnitLabel) ?? 'Unidad'
                  : null,
            ),
          )
          .toList(growable: false),
      payments: source.payments
          .map(
            (payment) => PrintPaymentLine(
              method: _paymentMethodLabel(payment.method),
              amount: payment.amount,
              reference: _nullIfBlank(payment.reference),
            ),
          )
          .toList(growable: false),
      totals: PrintTotals(
        subtotal: taxIncluded
            ? _round2(source.subtotal + source.taxAmount)
            : source.subtotal,
        discount: source.discountAmount,
        serviceCharge: source.serviceChargeAmount,
        tax: taxIncluded ? 0 : source.taxAmount,
        total: source.totalAmount,
        paid: source.paidAmount,
        balance: source.balanceDue,
      ),
      extra: <String, dynamic>{
        'source_table': 'sales',
        'source_id': source.saleId,
        'branch_id': source.branchId,
        'sale_status': source.status,
        'receipt_type': source.receiptType,
      },
    );
  }
}

/// Precio unitario con el ITBIS adentro. Si el producto ya tenía el precio
/// ITBIS-incluido, el neto (bruto − descuento) coincide con el total de la
/// línea y el precio se deja tal cual; si no, coincide con el subtotal y se le
/// suma la misma proporción de impuesto que lleva la línea.
double _unitPriceWithTax(SalePrintItemSource item) {
  if (item.lineTax <= 0.0049 || item.lineSubtotal <= 0) return item.unitPrice;
  final net = item.unitPrice * item.quantity - item.lineDiscount;
  final alreadyIncluded =
      (net - item.lineTotal).abs() < (net - item.lineSubtotal).abs();
  if (alreadyIncluded) return item.unitPrice;
  return _round2(item.unitPrice * item.lineTotal / item.lineSubtotal);
}

double _round2(double value) => (value * 100).roundToDouble() / 100;

PrintDocumentType _documentTypeForSale(SalePrintSource source) {
  // Devolución (migración 97): NOTA DE CRÉDITO, lleve o no NCF B04.
  if (source.receiptType == 'credit_note') return PrintDocumentType.creditNote;
  if (_hasText(source.ncf)) {
    return PrintDocumentType.fiscalInvoice;
  }

  return PrintDocumentType.saleReceipt;
}

PrintParty? _customerForSale(SalePrintSource source) {
  final name = _nullIfBlank(source.clientName);
  if (name == null) return null;

  return PrintParty(
    name: name,
    document: _nullIfBlank(source.clientDocument),
    address: _nullIfBlank(source.clientAddress),
    phone: _nullIfBlank(source.clientPhone),
    email: _nullIfBlank(source.clientEmail),
  );
}

String _receiptTypeLabel(String value) {
  switch (value) {
    case 'none':
      return 'Sin comprobante';
    case 'consumer_final':
      return 'Consumidor final';
    case 'fiscal_credit':
      return 'Crédito fiscal';
    case 'governmental':
      return 'Gubernamental';
    case 'special':
      return 'Régimen especial';
    case 'export':
      return 'Exportación';
    case 'credit_note':
      return 'Nota de crédito';
    default:
      return value.trim().isEmpty ? 'Venta' : value;
  }
}

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

String? _nullIfBlank(String? value) {
  if (!_hasText(value)) return null;
  return value!.trim();
}

bool _hasText(String? value) => value != null && value.trim().isNotEmpty;
