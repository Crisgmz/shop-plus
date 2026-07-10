import '../../../shared/formatters/formatters.dart';
import 'printing_models.dart';

class PrintingTemplateService {
  const PrintingTemplateService();

  ThermalTicketTemplate buildThermal80Template(
    PrintDocumentData document, {
    int copies = 1,
  }) {
    final hidePrices = document.hidePrices;
    final title = hidePrices ? 'CONDUCE' : _thermalTitle(document.documentType);
    final rows = <ThermalTicketRow>[
      ThermalTicketRow(center: document.branch.name, emphasized: true),
      if (_notEmpty(document.branch.address))
        ThermalTicketRow(center: document.branch.address),
      if (_notEmpty(document.branch.phone))
        ThermalTicketRow(center: 'Tel: ${document.branch.phone}'),
      if (_notEmpty(document.branch.taxId))
        ThermalTicketRow(center: 'RNC: ${document.branch.taxId}'),
      const ThermalTicketRow(isDivider: true),
      ThermalTicketRow(center: title, emphasized: true),
      ThermalTicketRow(left: 'Doc:', right: document.documentNumber),
      ThermalTicketRow(left: 'Fecha:', right: formatDateTime(document.issuedAt)),
      if (_notEmpty(document.receiptTypeLabel))
        ThermalTicketRow(left: 'Tipo:', right: document.receiptTypeLabel),
      if (_notEmpty(document.ncf)) ThermalTicketRow(left: 'NCF:', right: document.ncf),
      if (_notEmpty(document.cashierName))
        ThermalTicketRow(left: 'Cajero:', right: document.cashierName),
      if (_notEmpty(document.referenceNumber))
        ThermalTicketRow(left: 'Ref:', right: document.referenceNumber),
      if (document.customer != null) ...[
        const ThermalTicketRow(isDivider: true),
        ThermalTicketRow(left: 'Cliente:', right: document.customer!.name),
        if (_notEmpty(document.customer!.document))
          ThermalTicketRow(left: 'Doc:', right: document.customer!.document),
      ],
      const ThermalTicketRow(isDivider: true),
    ];

    for (final item in document.items) {
      rows.add(
        ThermalTicketRow(
          left: '${_qty(item.quantity)} x ${item.description}',
          // Conduce: sin monto por línea.
          right: hidePrices ? null : money(item.lineTotal),
        ),
      );
      if (_notEmpty(item.notes)) {
        rows.add(ThermalTicketRow(left: '  ${item.notes}'));
      }
    }

    // El conduce omite totales y pagos por completo.
    if (!hidePrices) {
      rows.addAll([
        const ThermalTicketRow(isDivider: true),
        ThermalTicketRow(left: 'SUBTOTAL', right: money(document.totals.subtotal)),
        if (document.totals.discount > 0)
          ThermalTicketRow(left: 'DESCUENTO', right: money(-document.totals.discount)),
        if (document.totals.serviceCharge > 0)
          ThermalTicketRow(left: 'LEY/SERVICIO', right: money(document.totals.serviceCharge)),
        ThermalTicketRow(left: 'ITBIS', right: money(document.totals.tax)),
        ThermalTicketRow(
          left: 'TOTAL',
          right: money(document.totals.total),
          emphasized: true,
        ),
        if (document.totals.paid > 0)
          ThermalTicketRow(left: 'PAGADO', right: money(document.totals.paid)),
        if (document.totals.balance > 0)
          ThermalTicketRow(left: 'BALANCE', right: money(document.totals.balance)),
      ]);

      if (document.payments.isNotEmpty) {
        rows.add(const ThermalTicketRow(isDivider: true));
        for (final payment in document.payments) {
          rows.add(
            ThermalTicketRow(left: payment.method, right: money(payment.amount)),
          );
        }
      }
    }

    if (_notEmpty(document.notes)) {
      rows.addAll([
        const ThermalTicketRow(isDivider: true),
        ThermalTicketRow(left: 'Notas:'),
        ThermalTicketRow(left: document.notes),
      ]);
    }

    rows.addAll([
      const ThermalTicketRow(isDivider: true),
      ThermalTicketRow(center: document.footerMessage ?? 'Gracias por su compra'),
    ]);

    return ThermalTicketTemplate(
      documentType: document.documentType,
      title: title,
      rows: rows,
      copies: copies,
    );
  }

  A4DocumentTemplate buildA4Template(PrintDocumentData document) {
    final hidePrices = document.hidePrices;
    return A4DocumentTemplate(
      documentType: document.documentType,
      title: hidePrices ? 'Conduce' : _a4Title(document.documentType),
      headerRows: [
        A4KeyValueRow(label: 'Documento', value: document.documentNumber),
        A4KeyValueRow(label: 'Fecha', value: formatDateTime(document.issuedAt)),
        if (_notEmpty(document.receiptTypeLabel))
          A4KeyValueRow(label: 'Tipo', value: document.receiptTypeLabel!),
        if (_notEmpty(document.ncf)) A4KeyValueRow(label: 'NCF', value: document.ncf!),
        A4KeyValueRow(label: 'Sucursal', value: document.branch.name),
        if (_notEmpty(document.branch.taxId))
          A4KeyValueRow(label: 'RNC', value: document.branch.taxId!),
        if (_notEmpty(document.cashierName))
          A4KeyValueRow(label: 'Cajero', value: document.cashierName!),
      ],
      customerRows: document.customer == null
          ? const <A4KeyValueRow>[]
          : [
              A4KeyValueRow(label: 'Cliente', value: document.customer!.name),
              if (_notEmpty(document.customer!.document))
                A4KeyValueRow(label: 'Documento', value: document.customer!.document!),
              if (_notEmpty(document.customer!.address))
                A4KeyValueRow(label: 'Direccion', value: document.customer!.address!),
              if (_notEmpty(document.customer!.phone))
                A4KeyValueRow(label: 'Telefono', value: document.customer!.phone!),
            ],
      itemRows: document.items
          .map(
            (item) => A4LineItemRow(
              description: item.description,
              quantityLabel: _qty(item.quantity),
              unitPriceLabel: hidePrices ? '' : money(item.unitPrice),
              totalLabel: hidePrices ? '' : money(item.lineTotal),
            ),
          )
          .toList(growable: false),
      // En un conduce no se listan totales.
      totalRows: hidePrices
          ? const <A4KeyValueRow>[]
          : [
        A4KeyValueRow(label: 'Subtotal', value: money(document.totals.subtotal)),
        if (document.totals.discount > 0)
          A4KeyValueRow(label: 'Descuento', value: money(-document.totals.discount)),
        if (document.totals.serviceCharge > 0)
          A4KeyValueRow(label: 'Ley/servicio', value: money(document.totals.serviceCharge)),
        A4KeyValueRow(label: 'ITBIS', value: money(document.totals.tax)),
        A4KeyValueRow(
          label: 'Total',
          value: money(document.totals.total),
          emphasized: true,
        ),
        if (document.totals.paid > 0)
          A4KeyValueRow(label: 'Pagado', value: money(document.totals.paid)),
        if (document.totals.balance > 0)
          A4KeyValueRow(label: 'Balance pendiente', value: money(document.totals.balance)),
      ],
      notes: document.notes,
      footer: document.footerMessage,
    );
  }
}

String _thermalTitle(PrintDocumentType type) {
  switch (type) {
    case PrintDocumentType.saleReceipt:
      return 'RECIBO DE VENTA';
    case PrintDocumentType.fiscalInvoice:
      return 'FACTURA FISCAL';
    case PrintDocumentType.cashClose:
      return 'CIERRE DE CAJA';
    case PrintDocumentType.quote:
      return 'COTIZACION';
    case PrintDocumentType.purchaseOrder:
      return 'ORDEN DE COMPRA';
    case PrintDocumentType.creditNote:
      return 'NOTA DE CREDITO';
    case PrintDocumentType.paymentReceipt:
      return 'RECIBO DE ABONO';
    case PrintDocumentType.expenseVoucher:
      return 'COMPROBANTE DE GASTO';
  }
}

String _a4Title(PrintDocumentType type) {
  switch (type) {
    case PrintDocumentType.saleReceipt:
      return 'Recibo de venta';
    case PrintDocumentType.fiscalInvoice:
      return 'Factura fiscal';
    case PrintDocumentType.cashClose:
      return 'Cierre de caja';
    case PrintDocumentType.quote:
      return 'Cotizacion';
    case PrintDocumentType.purchaseOrder:
      return 'Orden de compra';
    case PrintDocumentType.creditNote:
      return 'Nota de credito';
    case PrintDocumentType.paymentReceipt:
      return 'Recibo de abono';
    case PrintDocumentType.expenseVoucher:
      return 'Comprobante de gasto';
  }
}

bool _notEmpty(String? value) => value != null && value.trim().isNotEmpty;

String _qty(double value) {
  if (value == value.roundToDouble()) {
    return value.toStringAsFixed(0);
  }
  return value.toStringAsFixed(2);
}
