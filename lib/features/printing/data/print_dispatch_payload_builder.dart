import '../../../shared/formatters/formatters.dart';
import 'printing_models.dart';

class PrintDispatchPayloadBuilder {
  const PrintDispatchPayloadBuilder();

  Map<String, dynamic> buildThermalAgentPayload({
    required PrinterProfile printer,
    required PrintDocumentData document,
    required ThermalTicketTemplate template,
    String? templateId,
  }) {
    return <String, dynamic>{
      'document_type': _documentTypeValue(document.documentType),
      'paper_size': _paperSizeValue(PrintPaperSize.thermal80mm),
      'printer': <String, dynamic>{
        'id': printer.id,
        'code': printer.code,
        'name': printer.name,
        'transport_type': _transportTypeValue(printer.transportType),
        'driver_type': printer.driverType,
        'endpoint': printer.endpoint,
        'capabilities': printer.capabilities,
      },
      'template_id': templateId,
      'content_type': 'json_instruction',
      'content': <String, dynamic>{
        'title': template.title,
        'copies': template.copies,
        'issued_at': document.issuedAt.toIso8601String(),
        'document_number': document.documentNumber,
        'lines': template.rows.map(_thermalRowToInstruction).toList(growable: false),
      },
    };
  }

  Map<String, dynamic> buildA4Payload({
    required PrintDocumentData document,
    required A4DocumentTemplate template,
    String? printerId,
    String? templateId,
  }) {
    return <String, dynamic>{
      'document_type': _documentTypeValue(document.documentType),
      'paper_size': _paperSizeValue(PrintPaperSize.a4),
      'printer_id': printerId,
      'template_id': templateId,
      'content_type': 'document_model',
      'content': <String, dynamic>{
        'title': template.title,
        'issuer': <String, dynamic>{
          'name': document.branch.name,
          'address': document.branch.address,
          'phone': document.branch.phone,
          'email': document.branch.email,
          'tax_id': document.branch.taxId,
        },
        'header_rows': template.headerRows.map(_keyValueRowToMap).toList(growable: false),
        'customer_rows': template.customerRows.map(_keyValueRowToMap).toList(growable: false),
        'item_rows': template.itemRows
            .map(
              (row) => <String, dynamic>{
                'description': row.description,
                'quantity': row.quantityLabel,
                'unit_price': row.unitPriceLabel,
                'total': row.totalLabel,
              },
            )
            .toList(growable: false),
        'total_rows': template.totalRows.map(_keyValueRowToMap).toList(growable: false),
        'notes': template.notes,
        'footer': template.footer,
        'summary': <String, dynamic>{
          'subtotal': money(document.totals.subtotal),
          'tax': money(document.totals.tax),
          'discount': money(document.totals.discount),
          'total': money(document.totals.total),
          'paid': money(document.totals.paid),
          'balance': money(document.totals.balance),
        },
      },
    };
  }

  Map<String, dynamic> buildPrintJobPayload({
    required PrintDocumentData document,
    required PrintPaperSize paperSize,
    String? printerId,
    String? templateId,
    String? sourceTable,
    String? sourceId,
    int copies = 1,
    String? idempotencyKey,
  }) {
    return <String, dynamic>{
      'source_table': sourceTable,
      'source_id': sourceId,
      'document_type': _documentTypeValue(document.documentType),
      'paper_size': _paperSizeValue(paperSize),
      'printer_id': printerId,
      'template_id': templateId,
      'copies': copies,
      'idempotency_key': idempotencyKey,
      'payload': <String, dynamic>{
        'document_number': document.documentNumber,
        'issued_at': document.issuedAt.toIso8601String(),
        'receipt_type_label': document.receiptTypeLabel,
        'ncf': document.ncf,
        'cashier_name': document.cashierName,
        'reference_number': document.referenceNumber,
        'notes': document.notes,
        'footer_message': document.footerMessage,
        'branch': <String, dynamic>{
          'name': document.branch.name,
          'address': document.branch.address,
          'phone': document.branch.phone,
          'email': document.branch.email,
          'tax_id': document.branch.taxId,
        },
        'customer': document.customer == null
            ? null
            : <String, dynamic>{
                'name': document.customer!.name,
                'document': document.customer!.document,
                'address': document.customer!.address,
                'phone': document.customer!.phone,
                'email': document.customer!.email,
              },
        'items': document.items
            .map(
              (item) => <String, dynamic>{
                'description': item.description,
                'quantity': item.quantity,
                'unit_price': item.unitPrice,
                'line_subtotal': item.lineSubtotal,
                'line_tax': item.lineTax,
                'line_total': item.lineTotal,
                'sku': item.sku,
                'unit_label': item.unitLabel,
                'notes': item.notes,
              },
            )
            .toList(growable: false),
        'payments': document.payments
            .map(
              (payment) => <String, dynamic>{
                'method': payment.method,
                'amount': payment.amount,
                'reference': payment.reference,
              },
            )
            .toList(growable: false),
        'totals': <String, dynamic>{
          'subtotal': document.totals.subtotal,
          'discount': document.totals.discount,
          'tax': document.totals.tax,
          'total': document.totals.total,
          'paid': document.totals.paid,
          'balance': document.totals.balance,
        },
        'extra': document.extra,
      },
    };
  }
}

Map<String, dynamic> _thermalRowToInstruction(ThermalTicketRow row) {
  if (row.isDivider) {
    return const <String, dynamic>{'type': 'divider'};
  }

  if (row.center != null) {
    return <String, dynamic>{
      'type': 'text',
      'align': 'center',
      'value': row.center,
      'emphasized': row.emphasized,
    };
  }

  return <String, dynamic>{
    'type': 'row',
    'left': row.left,
    'right': row.right,
    'emphasized': row.emphasized,
  };
}

Map<String, dynamic> _keyValueRowToMap(A4KeyValueRow row) {
  return <String, dynamic>{
    'label': row.label,
    'value': row.value,
    'emphasized': row.emphasized,
  };
}

String _documentTypeValue(PrintDocumentType value) {
  switch (value) {
    case PrintDocumentType.saleReceipt:
      return 'sale_receipt';
    case PrintDocumentType.fiscalInvoice:
      return 'fiscal_invoice';
    case PrintDocumentType.cashClose:
      return 'cash_close';
    case PrintDocumentType.quote:
      return 'quote';
    case PrintDocumentType.purchaseOrder:
      return 'purchase_order';
    case PrintDocumentType.creditNote:
      return 'credit_note';
    case PrintDocumentType.paymentReceipt:
      return 'payment_receipt';
    case PrintDocumentType.expenseVoucher:
      return 'expense_voucher';
  }
}

String _paperSizeValue(PrintPaperSize value) {
  switch (value) {
    case PrintPaperSize.thermal80mm:
      return 'thermal_80mm';
    case PrintPaperSize.a4:
      return 'a4';
  }
}

String _transportTypeValue(PrintTransportType value) {
  switch (value) {
    case PrintTransportType.network:
      return 'network';
    case PrintTransportType.usb:
      return 'usb';
    case PrintTransportType.system:
      return 'system';
    case PrintTransportType.pdf:
      return 'pdf';
    case PrintTransportType.agent:
      return 'agent';
  }
}
