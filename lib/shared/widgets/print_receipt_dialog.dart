import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:printing/printing.dart';

import '../../features/printing/data/printing.dart';
import 'app_snackbar.dart';

class PrintReceiptDialog extends StatefulWidget {
  const PrintReceiptDialog({
    super.key,
    required this.printData,
    this.enableDeliveryNote = false,
  });

  final PreparedPrintJobData printData;

  /// Si true, el diálogo muestra el toggle "Conduce (sin precios)" para
  /// reimprimir el mismo documento como nota de entrega. Lo activan las
  /// ventas cuando `app_enable_delivery_notes` está prendido.
  final bool enableDeliveryNote;

  static Future<void> show(
    BuildContext context,
    PreparedPrintJobData data, {
    bool enableDeliveryNote = false,
  }) {
    return showDialog(
      context: context,
      builder: (_) => PrintReceiptDialog(
        printData: data,
        enableDeliveryNote: enableDeliveryNote,
      ),
    );
  }

  @override
  State<PrintReceiptDialog> createState() => _PrintReceiptDialogState();
}

class _PrintReceiptDialogState extends State<PrintReceiptDialog> {
  late PrintPaperSize _selectedSize;

  /// Cuando está activo, el documento se imprime/previsualiza como CONDUCE
  /// (sin precios). Solo disponible si [PrintReceiptDialog.enableDeliveryNote].
  bool _asDeliveryNote = false;

  final _templateService = const PrintingTemplateService();

  @override
  void initState() {
    super.initState();
    _selectedSize = widget.printData.paperSize;
  }

  /// Documento efectivo a renderizar: el original, o su variante conduce
  /// (mismos datos, `hidePrices: true`) cuando el toggle está activo.
  PrintDocumentData get _effectiveDocument => _asDeliveryNote
      ? widget.printData.document.copyWith(hidePrices: true)
      : widget.printData.document;

  A4DocumentTemplate get _a4Template => _asDeliveryNote
      ? _templateService.buildA4Template(_effectiveDocument)
      : (widget.printData.a4Template ??
          _templateService.buildA4Template(widget.printData.document));

  String get _docTitle {
    if (_asDeliveryNote) return 'Conduce';
    return switch (widget.printData.document.documentType) {
      PrintDocumentType.quote => 'Cotización',
      PrintDocumentType.fiscalInvoice => 'Factura Fiscal',
      PrintDocumentType.purchaseOrder => 'Orden de compra',
      PrintDocumentType.paymentReceipt => 'Recibo de abono',
      PrintDocumentType.expenseVoucher => 'Comprobante de gasto',
      _ => 'Recibo de venta',
    };
  }

  /// Disparador del botón Imprimir.
  ///
  /// Importante para Flutter Web: NO hacemos Navigator.pop antes de llamar
  /// a `Printing.layoutPdf`. Antes lo hacíamos y en algunos navegadores
  /// (Chrome/Edge en Windows 10 con el bloqueador de pop-ups activo) el
  /// "user gesture" del click se consideraba consumido por el pop y la
  /// ventana de impresión nunca aparecía — sin error visible.
  ///
  /// Ahora:
  ///   1. Llamamos `layoutPdf` directamente en el callback del click.
  ///   2. Capturamos cualquier excepción y la mostramos con AppSnackBar
  ///      (antes una falla era completamente silenciosa).
  ///   3. Si retorna false (usuario canceló o el navegador bloqueó la
  ///      ventana), mostramos un hint sobre el bloqueador de pop-ups.
  ///   4. Solo cerramos el diálogo si la operación se completó OK.
  Future<void> _onPrintPressed(BuildContext context) async {
    final doc = _effectiveDocument;
    final name = doc.documentNumber;
    final useThermal = _selectedSize == PrintPaperSize.thermal80mm;
    final navigator = Navigator.of(context);
    final messengerContext = context;

    try {
      final ok = await Printing.layoutPdf(
        name: name,
        onLayout: (format) => useThermal
            ? const PdfReceiptBuilder().buildThermalBytes(doc)
            : const PdfReceiptBuilder().buildBytes(doc, pageFormat: format),
      );
      if (!ok) {
        if (messengerContext.mounted) {
          AppSnackBar.info(
            messengerContext,
            'No se abrió la ventana de impresión. Si tu navegador la bloqueó, '
            'permite las ventanas emergentes para este sitio.',
          );
        }
        return;
      }
      if (navigator.mounted) navigator.pop();
    } catch (error) {
      if (messengerContext.mounted) {
        AppSnackBar.error(messengerContext, 'No se pudo imprimir', error);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final isThermal = _selectedSize == PrintPaperSize.thermal80mm;

    return AlertDialog(
      titlePadding: const EdgeInsets.fromLTRB(20, 16, 12, 0),
      contentPadding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
      title: Row(
        children: [
          Expanded(
            child: Text(
              'Vista previa · $_docTitle',
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
            ),
          ),
          SegmentedButton<PrintPaperSize>(
            style: SegmentedButton.styleFrom(
              visualDensity: VisualDensity.compact,
              textStyle: const TextStyle(fontSize: 12),
            ),
            segments: const [
              ButtonSegment(
                value: PrintPaperSize.thermal80mm,
                label: Text('Ticket'),
                icon: Icon(Icons.receipt_outlined, size: 14),
              ),
              ButtonSegment(
                value: PrintPaperSize.a4,
                label: Text('A4'),
                icon: Icon(Icons.article_outlined, size: 14),
              ),
            ],
            selected: {_selectedSize},
            onSelectionChanged: (set) =>
                setState(() => _selectedSize = set.first),
          ),
        ],
      ),
      content: SizedBox(
        width: isThermal ? 340 : 560,
        height: 480,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (widget.enableDeliveryNote) _buildDeliveryToggle(),
            Expanded(
              child: ClipRect(
                child: isThermal
                    ? _ThermalPreview(document: _effectiveDocument)
                    : _A4Preview(
                        template: _a4Template,
                        document: _effectiveDocument,
                      ),
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cerrar'),
        ),
        FilledButton.icon(
          onPressed: () => _onPrintPressed(context),
          icon: const Icon(Icons.print_rounded, size: 18),
          label: Text(_asDeliveryNote ? 'Imprimir conduce' : 'Imprimir'),
        ),
      ],
    );
  }

  /// Toggle "Conduce (sin precios)". Al activarlo, la vista previa y la
  /// impresión pasan a la variante sin montos (misma venta, `hidePrices`).
  Widget _buildDeliveryToggle() {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      decoration: BoxDecoration(
        color: _asDeliveryNote ? const Color(0xFFEFF6FF) : const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: _asDeliveryNote
              ? const Color(0xFFBFDBFE)
              : const Color(0xFFE2E8F0),
        ),
      ),
      child: Row(
        children: [
          Icon(
            Icons.local_shipping_outlined,
            size: 18,
            color: _asDeliveryNote
                ? const Color(0xFF1D4ED8)
                : const Color(0xFF64748B),
          ),
          const SizedBox(width: 10),
          const Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Conduce (sin precios)',
                  style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700),
                ),
                Text(
                  'Nota de entrega: mismos productos y cantidades, sin montos.',
                  style: TextStyle(fontSize: 11, color: Color(0xFF64748B)),
                ),
              ],
            ),
          ),
          Switch(
            value: _asDeliveryNote,
            onChanged: (v) => setState(() => _asDeliveryNote = v),
          ),
        ],
      ),
    );
  }
}

// ── Thermal preview ─────────────────────────────────────────────────────────
//
// Refleja visualmente el PDF que produce `PdfReceiptBuilder.buildThermalBytes`:
// logo + empresa centrada → metadata derecha → "Factura a:" → tabla items →
// totales → código de barras. Lee directamente de `PrintDocumentData` para
// que el preview y el PDF se mantengan en sincronía.

class _ThermalPreview extends StatelessWidget {
  const _ThermalPreview({required this.document});

  final PrintDocumentData document;

  static const _mono = TextStyle(fontFamily: 'monospace', fontSize: 10.5);
  static const _monoBold = TextStyle(
    fontFamily: 'monospace',
    fontSize: 10.5,
    fontWeight: FontWeight.w800,
  );

  @override
  Widget build(BuildContext context) {
    final d = document;
    final customer = d.customer;
    return Container(
      color: const Color(0xFFF8FAFC),
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(8),
        child: Center(
          child: Container(
            width: 300,
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
            color: Colors.white,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Header centrado
                if (d.branch.logoBytes != null) ...[
                  Center(
                    child: Image.memory(
                      Uint8List.fromList(d.branch.logoBytes!),
                      width: 60,
                      height: 60,
                      fit: BoxFit.contain,
                    ),
                  ),
                  const SizedBox(height: 4),
                ],
                Text(
                  d.branch.name.toUpperCase(),
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontFamily: 'monospace',
                    fontSize: 13,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                if (_t(d.branch.address))
                  Text(
                    d.branch.address!,
                    textAlign: TextAlign.center,
                    style: _mono,
                  ),
                if (_t(d.branch.phone))
                  Text(
                    d.branch.phone!,
                    textAlign: TextAlign.center,
                    style: _mono,
                  ),
                if (_t(d.branch.taxId))
                  Text(
                    'RNC ${d.branch.taxId}',
                    textAlign: TextAlign.center,
                    style: _mono,
                  ),
                const SizedBox(height: 10),

                if (d.hidePrices) ...[
                  Center(
                    child: Text(
                      'CONDUCE',
                      style: _monoBold.copyWith(fontSize: 13),
                    ),
                  ),
                  const SizedBox(height: 8),
                ],

                // Fecha derecha
                Align(
                  alignment: Alignment.centerRight,
                  child: Text(_fmt(d.issuedAt), style: _mono),
                ),
                const SizedBox(height: 8),

                // Metadata derecha
                _metaRow('Serie y Número:', d.documentNumber),
                if (_t(d.cashRegisterName))
                  _metaRow('Caja registradora:', d.cashRegisterName!),
                if (_t(d.priceTierLabel))
                  _metaRow('Tipo de precio:', d.priceTierLabel!),
                if (_t(d.cashierName))
                  _metaRow('Empleado:', d.cashierName!),
                if (_t(d.ncf)) _metaRow('NCF:', d.ncf!),
                if (_t(d.receiptTypeLabel))
                  _metaRow('Tipo comprobante:', d.receiptTypeLabel!),
                const SizedBox(height: 10),

                // Cliente
                if (customer != null) ...[
                  const Align(
                    alignment: Alignment.centerLeft,
                    child: Text('Factura a:', style: _monoBold),
                  ),
                  const SizedBox(height: 2),
                  Text('Cliente: ${customer.name}', style: _mono),
                  if (_t(customer.address))
                    Text('Dirección : ${customer.address}', style: _mono),
                  if (_t(customer.document))
                    Text('Doc: ${customer.document}', style: _mono),
                  if (_t(customer.phone))
                    Text('Teléfono : ${customer.phone}', style: _mono),
                  const SizedBox(height: 10),
                ],

                // Tabla items
                _itemsTable(d),

                // Totales (no en conduce)
                if (!d.hidePrices) ...[
                  const SizedBox(height: 10),
                  _totals(d),
                ],

                if (_t(d.notes)) ...[
                  const SizedBox(height: 8),
                  Text(
                    'Notas: ${d.notes}',
                    style: TextStyle(
                      fontFamily: 'monospace',
                      fontSize: 9.5,
                      color: Colors.grey.shade700,
                    ),
                  ),
                ],
                if (_t(d.footerMessage)) ...[
                  const SizedBox(height: 12),
                  Text(
                    d.footerMessage!,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontFamily: 'monospace',
                      fontSize: 10,
                      fontStyle: FontStyle.italic,
                      color: Colors.grey.shade700,
                    ),
                  ),
                ],
                if (d.showBarcode) ...[
                  const SizedBox(height: 14),
                  Center(
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 8),
                      decoration: BoxDecoration(
                        border: Border.all(color: Colors.grey.shade300),
                      ),
                      child: Column(
                        children: [
                          // Representación visual sencilla del barcode
                          // (en el PDF real se usa Code128).
                          SizedBox(
                            width: 180,
                            height: 30,
                            child: Row(
                              children: [
                                for (var i = 0; i < d.documentNumber.length; i++)
                                  Expanded(
                                    child: Container(
                                      color: d.documentNumber.codeUnitAt(i)
                                                  .isOdd
                                          ? Colors.black
                                          : Colors.white,
                                    ),
                                  ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(d.documentNumber, style: _mono),
                        ],
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _metaRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 1),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          Text(label, style: _monoBold),
          const SizedBox(width: 6),
          Flexible(
            child: Text(
              value,
              textAlign: TextAlign.right,
              style: _mono,
            ),
          ),
        ],
      ),
    );
  }

  Widget _itemsTable(PrintDocumentData d) {
    // Conduce: solo Nombre + Cant., sin precio ni total.
    if (d.hidePrices) {
      return Table(
        columnWidths: const {
          0: FlexColumnWidth(5),
          1: FixedColumnWidth(44),
        },
        defaultVerticalAlignment: TableCellVerticalAlignment.top,
        children: [
          TableRow(
            decoration: BoxDecoration(
              border: Border(
                bottom: BorderSide(color: Colors.grey.shade400, width: 0.6),
              ),
            ),
            children: const [
              _Cell('Nombre', style: _monoBold),
              _Cell('Cant.', style: _monoBold, align: Alignment.center),
            ],
          ),
          for (final item in d.items)
            TableRow(
              children: [
                _Cell(item.description, style: _mono),
                _Cell(_qty(item.quantity),
                    style: _mono, align: Alignment.center),
              ],
            ),
        ],
      );
    }
    return Table(
      columnWidths: const {
        0: FlexColumnWidth(5),
        1: FixedColumnWidth(56),
        2: FixedColumnWidth(38),
        3: FixedColumnWidth(60),
      },
      defaultVerticalAlignment: TableCellVerticalAlignment.top,
      children: [
        TableRow(
          decoration: BoxDecoration(
            border: Border(
              bottom: BorderSide(color: Colors.grey.shade400, width: 0.6),
            ),
          ),
          children: const [
            _Cell('Nombre', style: _monoBold),
            _Cell('Precio', style: _monoBold, align: Alignment.centerRight),
            _Cell('Cant.', style: _monoBold, align: Alignment.center),
            _Cell('Total', style: _monoBold, align: Alignment.centerRight),
          ],
        ),
        for (final item in d.items)
          TableRow(
            children: [
              _Cell(item.description, style: _mono),
              _Cell(_money(item.unitPrice),
                  style: _mono, align: Alignment.centerRight),
              _Cell(_qty(item.quantity),
                  style: _mono, align: Alignment.center),
              _Cell(_money(item.lineTotal),
                  style: _mono, align: Alignment.centerRight),
            ],
          ),
      ],
    );
  }

  Widget _totals(PrintDocumentData d) {
    Widget line(String label, String value, {bool bold = false}) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 1),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            Text(label, style: bold ? _monoBold : _mono),
            const SizedBox(width: 12),
            SizedBox(
              width: 90,
              child: Text(
                value,
                textAlign: TextAlign.right,
                style: bold ? _monoBold : _mono,
              ),
            ),
          ],
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        line('Subtotal', _money(d.totals.subtotal)),
        if (d.totals.discount > 0)
          line('Descuento', '-${_money(d.totals.discount)}'),
        if (d.totals.serviceCharge > 0)
          line('Servicio', _money(d.totals.serviceCharge)),
        if (d.totals.tax > 0) line('ITBIS', _money(d.totals.tax)),
        line('Total', _money(d.totals.total), bold: true),
        if (d.changeAmount != null && d.changeAmount! >= 0)
          line('Cambio', _money(d.changeAmount!)),
        if (d.totals.balance > 0)
          line('Pendiente', _money(d.totals.balance), bold: true),
        for (final payment in d.payments)
          line(payment.method, _money(payment.amount)),
      ],
    );
  }

  static bool _t(String? v) => v != null && v.trim().isNotEmpty;

  static String _fmt(DateTime d) {
    final local = d.isUtc ? d.toLocal() : d;
    String two(int n) => n.toString().padLeft(2, '0');
    return '${two(local.day)}-${two(local.month)}-${local.year} '
        '${two(local.hour)}:${two(local.minute)}';
  }

  static String _money(double v) =>
      'RD\$${v.toStringAsFixed(2).replaceAllMapped(
            RegExp(r'(\d)(?=(\d{3})+(?!\d))'),
            (m) => '${m[1]},',
          )}';

  static String _qty(double v) {
    if (v == v.roundToDouble()) return v.toStringAsFixed(0);
    return v.toStringAsFixed(2);
  }
}

class _Cell extends StatelessWidget {
  const _Cell(this.text, {required this.style, this.align = Alignment.centerLeft});

  final String text;
  final TextStyle style;
  final Alignment align;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 4),
      child: Align(alignment: align, child: Text(text, style: style)),
    );
  }
}

// ── A4 preview ───────────────────────────────────────────────────────────────

class _A4Preview extends StatelessWidget {
  const _A4Preview({required this.template, required this.document});

  final A4DocumentTemplate template;
  final PrintDocumentData document;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header: issuer + doc meta
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      document.branch.name,
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w800,
                        color: Color(0xFF1E293B),
                      ),
                    ),
                    if (document.branch.address != null)
                      Text(
                        document.branch.address!,
                        style: const TextStyle(
                          fontSize: 12,
                          color: Color(0xFF64748B),
                        ),
                      ),
                    if (document.branch.phone != null)
                      Text(
                        'Tel: ${document.branch.phone}',
                        style: const TextStyle(
                          fontSize: 12,
                          color: Color(0xFF64748B),
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(width: 16),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    template.title.toUpperCase(),
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w900,
                      color: Color(0xFF2563EB),
                      letterSpacing: 0.5,
                    ),
                  ),
                  const SizedBox(height: 4),
                  for (final row in template.headerRows)
                    _KVLine(
                      label: row.label,
                      value: row.value,
                      emphasized: row.emphasized,
                    ),
                ],
              ),
            ],
          ),

          if (template.customerRows.isNotEmpty) ...[
            const SizedBox(height: 16),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: const Color(0xFFF1F5F9),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'DATOS DEL CLIENTE',
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w700,
                      color: Color(0xFF64748B),
                      letterSpacing: 0.8,
                    ),
                  ),
                  const SizedBox(height: 6),
                  for (final row in template.customerRows)
                    _KVLine(
                      label: row.label,
                      value: row.value,
                      emphasized: row.emphasized,
                    ),
                ],
              ),
            ),
          ],

          const SizedBox(height: 16),

          // Items table — en conduce se ocultan las columnas Precio y Total.
          Table(
            columnWidths: document.hidePrices
                ? const {0: FlexColumnWidth(5), 1: FlexColumnWidth(1)}
                : const {
                    0: FlexColumnWidth(4),
                    1: FlexColumnWidth(1),
                    2: FlexColumnWidth(2),
                    3: FlexColumnWidth(2),
                  },
            children: [
              TableRow(
                decoration: const BoxDecoration(
                  border: Border(
                    bottom: BorderSide(color: Color(0xFF334155), width: 1.5),
                  ),
                ),
                children: [
                  _tableHeader('Descripción'),
                  _tableHeader('Cant.', numeric: true),
                  if (!document.hidePrices) _tableHeader('Precio', numeric: true),
                  if (!document.hidePrices) _tableHeader('Total', numeric: true),
                ],
              ),
              for (int i = 0; i < template.itemRows.length; i++)
                TableRow(
                  decoration: BoxDecoration(
                    color: i.isOdd
                        ? const Color(0xFFF8FAFC)
                        : Colors.transparent,
                  ),
                  children: [
                    _tableCell(template.itemRows[i].description),
                    _tableCell(
                      template.itemRows[i].quantityLabel,
                      numeric: true,
                    ),
                    if (!document.hidePrices)
                      _tableCell(
                        template.itemRows[i].unitPriceLabel,
                        numeric: true,
                      ),
                    if (!document.hidePrices)
                      _tableCell(
                        template.itemRows[i].totalLabel,
                        numeric: true,
                        bold: true,
                      ),
                  ],
                ),
            ],
          ),

          // Totales (no en conduce).
          if (!document.hidePrices) ...[
            const SizedBox(height: 12),
            const Divider(height: 1, color: Color(0xFFE2E8F0)),
            const SizedBox(height: 8),
            Align(
              alignment: Alignment.centerRight,
              child: SizedBox(
                width: 220,
                child: Column(
                  children: [
                    for (final row in template.totalRows)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 2),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              row.label,
                              style: TextStyle(
                                fontSize: row.emphasized ? 14 : 12,
                                fontWeight: row.emphasized
                                    ? FontWeight.w800
                                    : FontWeight.w500,
                                color: const Color(0xFF475569),
                              ),
                            ),
                            Text(
                              row.value,
                              style: TextStyle(
                                fontSize: row.emphasized ? 15 : 12,
                                fontWeight: row.emphasized
                                    ? FontWeight.w900
                                    : FontWeight.w600,
                                color: row.emphasized
                                    ? const Color(0xFF2563EB)
                                    : const Color(0xFF1E293B),
                              ),
                            ),
                          ],
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ],

          if (template.notes != null) ...[
            const SizedBox(height: 16),
            const Text(
              'NOTAS',
              style: TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.w700,
                color: Color(0xFF64748B),
                letterSpacing: 0.8,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              template.notes!,
              style: const TextStyle(fontSize: 12, color: Color(0xFF475569)),
            ),
          ],

          if (template.footer != null) ...[
            const SizedBox(height: 20),
            Center(
              child: Text(
                template.footer!,
                style: const TextStyle(
                  fontSize: 12,
                  color: Color(0xFF94A3B8),
                  fontStyle: FontStyle.italic,
                ),
              ),
            ),
          ],

          const SizedBox(height: 8),
        ],
      ),
    );
  }

  Widget _tableHeader(String label, {bool numeric = false}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 4),
      child: Text(
        label,
        textAlign: numeric ? TextAlign.right : TextAlign.left,
        style: const TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w700,
          color: Color(0xFF334155),
          letterSpacing: 0.3,
        ),
      ),
    );
  }

  Widget _tableCell(
    String value, {
    bool numeric = false,
    bool bold = false,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5, horizontal: 4),
      child: Text(
        value,
        textAlign: numeric ? TextAlign.right : TextAlign.left,
        style: TextStyle(
          fontSize: 12,
          fontWeight: bold ? FontWeight.w700 : FontWeight.normal,
          color: const Color(0xFF1E293B),
        ),
      ),
    );
  }
}

class _KVLine extends StatelessWidget {
  const _KVLine({
    required this.label,
    required this.value,
    this.emphasized = false,
  });

  final String label;
  final String value;
  final bool emphasized;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 2),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            '$label: ',
            style: const TextStyle(fontSize: 12, color: Color(0xFF64748B)),
          ),
          Text(
            value,
            style: TextStyle(
              fontSize: 12,
              fontWeight:
                  emphasized ? FontWeight.w800 : FontWeight.w600,
              color: const Color(0xFF1E293B),
            ),
          ),
        ],
      ),
    );
  }
}

