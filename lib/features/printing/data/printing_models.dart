enum PrintDocumentType {
  saleReceipt,
  fiscalInvoice,
  cashClose,
  quote,
  purchaseOrder,
  creditNote,
}

enum PrintPaperSize {
  thermal80mm,
  a4,
}

enum PrintTransportType {
  network,
  usb,
  system,
  pdf,
  agent,
}

enum PrintJobStatus {
  queued,
  processing,
  printed,
  failed,
  cancelled,
}

class PrinterProfile {
  const PrinterProfile({
    required this.id,
    required this.branchId,
    required this.code,
    required this.name,
    required this.paperSize,
    required this.transportType,
    this.driverType,
    this.endpoint,
    this.isDefault = false,
    this.isActive = true,
    this.capabilities = const <String, dynamic>{},
  });

  final String id;
  final String branchId;
  final String code;
  final String name;
  final PrintPaperSize paperSize;
  final PrintTransportType transportType;
  final String? driverType;
  final String? endpoint;
  final bool isDefault;
  final bool isActive;
  final Map<String, dynamic> capabilities;
}

class PrintTemplateProfile {
  const PrintTemplateProfile({
    required this.id,
    required this.code,
    required this.name,
    required this.documentType,
    required this.paperSize,
    required this.version,
    this.settings = const <String, dynamic>{},
    this.isDefault = false,
    this.isActive = true,
  });

  final String id;
  final String code;
  final String name;
  final PrintDocumentType documentType;
  final PrintPaperSize paperSize;
  final int version;
  final Map<String, dynamic> settings;
  final bool isDefault;
  final bool isActive;
}

class PrintRoute {
  const PrintRoute({
    required this.documentType,
    required this.paperSize,
    this.printerId,
    this.templateId,
    this.fallbackPrinterId,
    this.copies = 1,
    this.isActive = true,
  });

  final PrintDocumentType documentType;
  final PrintPaperSize paperSize;
  final String? printerId;
  final String? templateId;
  final String? fallbackPrinterId;
  final int copies;
  final bool isActive;
}

class PrintBranchIdentity {
  const PrintBranchIdentity({
    required this.name,
    this.address,
    this.phone,
    this.email,
    this.taxId,
    this.logoBytes,
    this.bankInfo,
    this.signatoryName,
    this.signatoryTitle,
  });

  final String name;
  final String? address;
  final String? phone;
  final String? email;
  final String? taxId;

  /// Bytes del logo (PNG/JPG). Si está presente se muestra centrado al tope
  /// del recibo. El caller es responsable de descargarlo de
  /// `app_settings.company_logo_url`.
  final List<int>? logoBytes;

  /// Datos bancarios para pago (texto multilínea). Solo factura/cotización A4.
  final String? bankInfo;

  /// Firmante impreso sobre la línea de firma (factura/cotización A4).
  final String? signatoryName;
  final String? signatoryTitle;
}

class PrintParty {
  const PrintParty({
    required this.name,
    this.document,
    this.address,
    this.phone,
    this.email,
  });

  final String name;
  final String? document;
  final String? address;
  final String? phone;
  final String? email;
}

class PrintDocumentItem {
  const PrintDocumentItem({
    required this.description,
    required this.quantity,
    required this.unitPrice,
    required this.lineSubtotal,
    required this.lineTax,
    required this.lineTotal,
    this.sku,
    this.unitLabel,
    this.notes,
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
}

class PrintPaymentLine {
  const PrintPaymentLine({required this.method, required this.amount, this.reference});

  final String method;
  final double amount;
  final String? reference;
}

class PrintTotals {
  const PrintTotals({
    required this.subtotal,
    required this.tax,
    required this.total,
    this.discount = 0,
    this.serviceCharge = 0,
    this.paid = 0,
    this.balance = 0,
  });

  final double subtotal;
  final double tax;
  final double total;
  final double discount;
  final double serviceCharge;
  final double paid;
  final double balance;
}

class PrintDocumentData {
  const PrintDocumentData({
    required this.documentType,
    required this.documentNumber,
    required this.issuedAt,
    required this.branch,
    required this.items,
    required this.totals,
    this.customer,
    this.cashierName,
    this.referenceNumber,
    this.receiptTypeLabel,
    this.ncf,
    this.notes,
    this.footerMessage,
    this.payments = const <PrintPaymentLine>[],
    this.extra = const <String, dynamic>{},
    this.priceTierLabel,
    this.cashRegisterName,
    this.changeAmount,
    this.showBarcode = true,
    this.paymentTermsLabel,
    this.observation,
    this.showTax = true,
    this.qrBytes,
  });

  final PrintDocumentType documentType;
  final String documentNumber;
  final DateTime issuedAt;
  final PrintBranchIdentity branch;
  final List<PrintDocumentItem> items;
  final PrintTotals totals;
  final PrintParty? customer;
  final String? cashierName;
  final String? referenceNumber;
  final String? receiptTypeLabel;
  final String? ncf;
  final String? notes;
  final String? footerMessage;
  final List<PrintPaymentLine> payments;
  final Map<String, dynamic> extra;

  /// Etiqueta del nivel de precio aplicado (ej. "mayorista", "minorista").
  final String? priceTierLabel;

  /// Nombre/código de la caja registradora.
  final String? cashRegisterName;

  /// Monto del cambio entregado al cliente (paid - total cuando paid > total).
  /// Si es null se omite la línea "Cambio".
  final double? changeAmount;

  /// Si false, no se imprime el código de barras al final del recibo.
  final bool showBarcode;

  /// Etiqueta de "Forma de pago" (ej. "CONTADO", "CRÉDITO"). Factura/cotización.
  final String? paymentTermsLabel;

  /// Observación opcional impresa al pie (factura/cotización A4).
  final String? observation;

  /// Si false, se oculta la columna ITBIS y el desglose de impuestos en el
  /// PDF A4 (ventas "sin comprobante", sin impuesto, o toggle apagado).
  final bool showTax;

  /// Bytes del código QR para el pie del A4 (descargado de `company_qr_url`).
  /// Si es null, el builder usa el asset `assets/QR.png` como fallback.
  final List<int>? qrBytes;
}

class ThermalTicketRow {
  const ThermalTicketRow({
    this.left,
    this.right,
    this.center,
    this.emphasized = false,
    this.isDivider = false,
  });

  final String? left;
  final String? right;
  final String? center;
  final bool emphasized;
  final bool isDivider;
}

class ThermalTicketTemplate {
  const ThermalTicketTemplate({
    required this.documentType,
    required this.title,
    required this.rows,
    this.copies = 1,
  });

  final PrintDocumentType documentType;
  final String title;
  final List<ThermalTicketRow> rows;
  final int copies;
}

class A4LineItemRow {
  const A4LineItemRow({
    required this.description,
    required this.quantityLabel,
    required this.unitPriceLabel,
    required this.totalLabel,
  });

  final String description;
  final String quantityLabel;
  final String unitPriceLabel;
  final String totalLabel;
}

class A4KeyValueRow {
  const A4KeyValueRow({required this.label, required this.value, this.emphasized = false});

  final String label;
  final String value;
  final bool emphasized;
}

class A4DocumentTemplate {
  const A4DocumentTemplate({
    required this.documentType,
    required this.title,
    required this.headerRows,
    required this.customerRows,
    required this.itemRows,
    required this.totalRows,
    this.notes,
    this.footer,
  });

  final PrintDocumentType documentType;
  final String title;
  final List<A4KeyValueRow> headerRows;
  final List<A4KeyValueRow> customerRows;
  final List<A4LineItemRow> itemRows;
  final List<A4KeyValueRow> totalRows;
  final String? notes;
  final String? footer;
}

class PrintJobDraft {
  const PrintJobDraft({
    required this.branchId,
    required this.documentType,
    required this.paperSize,
    required this.payload,
    this.printerId,
    this.templateId,
    this.sourceTable,
    this.sourceId,
    this.copies = 1,
    this.idempotencyKey,
  });

  final String branchId;
  final PrintDocumentType documentType;
  final PrintPaperSize paperSize;
  final String? printerId;
  final String? templateId;
  final String? sourceTable;
  final String? sourceId;
  final int copies;
  final String? idempotencyKey;
  final Map<String, dynamic> payload;
}

class PrintJobRecord {
  const PrintJobRecord({
    required this.id,
    required this.status,
    required this.documentType,
    required this.paperSize,
    required this.payload,
    required this.createdAt,
    this.printerId,
    this.templateId,
    this.printedAt,
    this.failureReason,
  });

  final String id;
  final PrintJobStatus status;
  final PrintDocumentType documentType;
  final PrintPaperSize paperSize;
  final Map<String, dynamic> payload;
  final DateTime createdAt;
  final String? printerId;
  final String? templateId;
  final DateTime? printedAt;
  final String? failureReason;
}
