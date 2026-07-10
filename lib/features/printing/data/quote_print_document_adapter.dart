import 'printing_models.dart';

class QuotePrintSource {
  const QuotePrintSource({
    required this.quoteId,
    required this.branchId,
    required this.quoteCode,
    required this.clientName,
    required this.issuedAt,
    required this.validUntil,
    required this.branchName,
    required this.items,
    required this.subtotal,
    required this.taxAmount,
    required this.totalAmount,
    this.branchAddress,
    this.branchPhone,
    this.branchEmail,
    this.branchTaxId,
    this.branchLogoBytes,
    this.bankInfo,
    this.signatoryName,
    this.signatoryTitle,
    this.observation,
    this.clientLegalName,
    this.clientDocument,
    this.clientAddress,
    this.clientPhone,
    this.clientEmail,
    this.notes,
    this.showItbis = true,
    this.qrBytes,
  });

  final String quoteId;
  final String branchId;
  final String quoteCode;
  final String clientName;
  final DateTime issuedAt;
  final DateTime validUntil;
  final String branchName;
  final String? branchAddress;
  final String? branchPhone;
  final String? branchEmail;
  final String? branchTaxId;
  final List<int>? branchLogoBytes;
  final String? bankInfo;
  final String? signatoryName;
  final String? signatoryTitle;
  final String? observation;
  final String? clientLegalName;
  final String? clientDocument;
  final String? clientAddress;
  final String? clientPhone;
  final String? clientEmail;
  final String? notes;
  final bool showItbis;
  final List<int>? qrBytes;
  final List<QuotePrintItemSource> items;
  final double subtotal;
  final double taxAmount;
  final double totalAmount;
}

class QuotePrintItemSource {
  const QuotePrintItemSource({
    required this.description,
    required this.quantity,
    required this.unitPrice,
    required this.lineSubtotal,
    required this.lineTax,
    required this.lineTotal,
    this.sku,
  });

  final String description;
  final double quantity;
  final double unitPrice;
  final double lineSubtotal;
  final double lineTax;
  final double lineTotal;
  final String? sku;
}

class QuotePrintDocumentAdapter {
  const QuotePrintDocumentAdapter();

  PrintDocumentData toDocumentData(QuotePrintSource source) {
    return PrintDocumentData(
      documentType: PrintDocumentType.quote,
      documentNumber: source.quoteCode,
      issuedAt: source.issuedAt,
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
      customer: PrintParty(
        name: _nullIfBlank(source.clientLegalName) ?? source.clientName,
        document: _nullIfBlank(source.clientDocument),
        address: _nullIfBlank(source.clientAddress),
        phone: _nullIfBlank(source.clientPhone),
        email: _nullIfBlank(source.clientEmail),
      ),
      receiptTypeLabel: 'Cotización',
      paymentTermsLabel: 'CONTADO',
      showTax: source.showItbis &&
          source.items.any((i) => i.lineTax > 0.0049),
      qrBytes: source.qrBytes,
      observation: _nullIfBlank(source.observation),
      referenceNumber: 'Vigencia: ${_dateLabel(source.validUntil)}',
      notes: _nullIfBlank(source.notes),
      footerMessage: 'Gracias por su preferencia',
      items: source.items
          .map(
            (item) => PrintDocumentItem(
              description: item.description,
              quantity: item.quantity,
              unitPrice: item.unitPrice,
              lineSubtotal: item.lineSubtotal,
              lineTax: item.lineTax,
              lineTotal: item.lineTotal,
              sku: _nullIfBlank(item.sku),
            ),
          )
          .toList(growable: false),
      payments: const [],
      totals: PrintTotals(
        subtotal: source.subtotal,
        tax: source.taxAmount,
        total: source.totalAmount,
      ),
      extra: <String, dynamic>{
        'source_table': 'quotations',
        'source_id': source.quoteId,
        'branch_id': source.branchId,
      },
    );
  }
}

String _dateLabel(DateTime date) {
  final d = date.toLocal();
  return '${d.day.toString().padLeft(2, '0')}/'
      '${d.month.toString().padLeft(2, '0')}/'
      '${d.year}';
}

String? _nullIfBlank(String? value) {
  if (value == null) return null;
  final trimmed = value.trim();
  return trimmed.isEmpty ? null : trimmed;
}
