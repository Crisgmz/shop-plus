import 'print_dispatch_payload_builder.dart';
import 'printing_models.dart';
import 'printing_template_service.dart';
import 'sale_print_document_adapter.dart';

class PreparedPrintJobData {
  const PreparedPrintJobData({
    required this.document,
    required this.paperSize,
    required this.job,
    required this.dispatchPayload,
    this.thermalTemplate,
    this.a4Template,
  });

  final PrintDocumentData document;
  final PrintPaperSize paperSize;
  final PrintJobDraft job;
  final Map<String, dynamic> dispatchPayload;
  final ThermalTicketTemplate? thermalTemplate;
  final A4DocumentTemplate? a4Template;
}

class SalePrintJobPreparationService {
  const SalePrintJobPreparationService({
    this.documentAdapter = const SalePrintDocumentAdapter(),
    this.templateService = const PrintingTemplateService(),
    this.payloadBuilder = const PrintDispatchPayloadBuilder(),
  });

  final SalePrintDocumentAdapter documentAdapter;
  final PrintingTemplateService templateService;
  final PrintDispatchPayloadBuilder payloadBuilder;

  PreparedPrintJobData prepareCompletedSaleReceipt({
    required SalePrintSource sale,
    PrintPaperSize paperSize = PrintPaperSize.thermal80mm,
    String? printerId,
    String? templateId,
    int copies = 1,
  }) {
    final normalizedStatus = sale.status.trim().toLowerCase();
    // Las ventas a crédito también generan recibo (el cliente necesita el
    // comprobante del saldo aunque no haya pagado). Solo se bloquean estados
    // sin recibo válido (p. ej. anuladas).
    if (normalizedStatus != 'completed' && normalizedStatus != 'credit') {
      throw StateError(
        'Solo se puede preparar impresión para ventas pagadas o a crédito.',
      );
    }

    final document = documentAdapter.toDocumentData(sale);

    switch (paperSize) {
      case PrintPaperSize.thermal80mm:
        final template = templateService.buildThermal80Template(
          document,
          copies: copies,
        );
        final dispatchPayload = <String, dynamic>{
          'document_type': _documentTypeValue(document.documentType),
          'paper_size': _paperSizeValue(PrintPaperSize.thermal80mm),
          'printer_id': printerId,
          'template_id': templateId,
          'content_type': 'thermal_template',
          'content': <String, dynamic>{
            'title': template.title,
            'copies': template.copies,
            'issued_at': document.issuedAt.toIso8601String(),
            'document_number': document.documentNumber,
            'rows': template.rows
                .map(
                  (row) => <String, dynamic>{
                    'left': row.left,
                    'right': row.right,
                    'center': row.center,
                    'emphasized': row.emphasized,
                    'is_divider': row.isDivider,
                  },
                )
                .toList(growable: false),
          },
        };

        return PreparedPrintJobData(
          document: document,
          paperSize: paperSize,
          thermalTemplate: template,
          dispatchPayload: dispatchPayload,
          job: PrintJobDraft(
            branchId: sale.branchId,
            documentType: document.documentType,
            paperSize: paperSize,
            printerId: printerId,
            templateId: templateId,
            sourceTable: 'sales',
            sourceId: sale.saleId,
            copies: copies,
            idempotencyKey: _salePrintJobKey(
              saleId: sale.saleId,
              paperSize: paperSize,
            ),
            payload: payloadBuilder.buildPrintJobPayload(
              document: document,
              paperSize: paperSize,
              printerId: printerId,
              templateId: templateId,
              sourceTable: 'sales',
              sourceId: sale.saleId,
              copies: copies,
              idempotencyKey: _salePrintJobKey(
                saleId: sale.saleId,
                paperSize: paperSize,
              ),
            ),
          ),
        );
      case PrintPaperSize.a4:
        final template = templateService.buildA4Template(document);
        final dispatchPayload = payloadBuilder.buildA4Payload(
          document: document,
          template: template,
          printerId: printerId,
          templateId: templateId,
        );

        return PreparedPrintJobData(
          document: document,
          paperSize: paperSize,
          a4Template: template,
          dispatchPayload: dispatchPayload,
          job: PrintJobDraft(
            branchId: sale.branchId,
            documentType: document.documentType,
            paperSize: paperSize,
            printerId: printerId,
            templateId: templateId,
            sourceTable: 'sales',
            sourceId: sale.saleId,
            copies: copies,
            idempotencyKey: _salePrintJobKey(
              saleId: sale.saleId,
              paperSize: paperSize,
            ),
            payload: payloadBuilder.buildPrintJobPayload(
              document: document,
              paperSize: paperSize,
              printerId: printerId,
              templateId: templateId,
              sourceTable: 'sales',
              sourceId: sale.saleId,
              copies: copies,
              idempotencyKey: _salePrintJobKey(
                saleId: sale.saleId,
                paperSize: paperSize,
              ),
            ),
          ),
        );
    }
  }
}

String _salePrintJobKey({
  required String saleId,
  required PrintPaperSize paperSize,
}) {
  return 'sale:$saleId:${_paperSizeValue(paperSize)}:v1';
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
