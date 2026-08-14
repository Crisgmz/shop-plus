import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../../../shared/formatters/formatters.dart';
import 'printing_models.dart';

/// Reduce una imagen a `maxDim` px en su lado mayor ANTES de embeberla en el
/// PDF. Embeber un logo/QR de ~2000px hace que el `pdf` decodifique millones de
/// píxeles de forma SÍNCRONA al generar — en web eso congela la UI varios
/// segundos. Con ~400px el costo baja ~25x. Si la imagen ya es chica o el
/// decode falla, devuelve los bytes originales.
Future<Uint8List?> _shrinkImageForPdf(List<int>? bytes, {int maxDim = 420}) async {
  if (bytes == null) return null;
  final input = Uint8List.fromList(bytes);
  try {
    final probe = await ui.instantiateImageCodec(input);
    final probeFrame = await probe.getNextFrame();
    final w = probeFrame.image.width;
    final h = probeFrame.image.height;
    probeFrame.image.dispose();

    final longest = w > h ? w : h;
    if (longest <= maxDim) return input; // ya es chica

    final scale = maxDim / longest;
    final codec = await ui.instantiateImageCodec(
      input,
      targetWidth: (w * scale).round(),
      targetHeight: (h * scale).round(),
    );
    final frame = await codec.getNextFrame();
    final data = await frame.image.toByteData(format: ui.ImageByteFormat.png);
    frame.image.dispose();
    return data?.buffer.asUint8List() ?? input;
  } catch (_) {
    return input;
  }
}

/// Azul corporativo del encabezado (logo / título / número de documento).
const PdfColor _kNavy = PdfColor.fromInt(0xFF1B3A6B);

/// Rojo del "TOTAL A PAGAR".
const PdfColor _kRed = PdfColor.fromInt(0xFFC0202A);

class PdfReceiptBuilder {
  const PdfReceiptBuilder();

  Future<Uint8List> buildBytes(
    PrintDocumentData data, {
    PdfPageFormat pageFormat = PdfPageFormat.a4,
  }) =>
      buildDocumentsBytes([data], pageFormat: pageFormat);

  /// Igual que [buildBytes] pero concatena varios documentos como páginas de un
  /// mismo PDF (ej. factura + conduce), para imprimirlos en una sola ventana de
  /// impresión — en Flutter Web abrir dos ventanas seguidas suele bloquearse.
  Future<Uint8List> buildDocumentsBytes(
    List<PrintDocumentData> docs, {
    PdfPageFormat pageFormat = PdfPageFormat.a4,
  }) async {
    final pdf = pw.Document(
      title: docs.first.documentNumber,
      author: docs.first.branch.name,
    );

    for (final data in docs) {
      // QR: SOLO si el negocio configuró `company_qr_url` (data.qrBytes).
      // Reducir imágenes antes de embeberlas evita el freeze de la UI.
      final qrBytes = await _shrinkImageForPdf(data.qrBytes, maxDim: 420);
      final logoBytes =
          await _shrinkImageForPdf(data.branch.logoBytes, maxDim: 320);

      pdf.addPage(
        pw.Page(
          pageFormat: pageFormat,
          // Margen superior más holgado que el resto: el logo va pegado al
          // tope y con 36pt quedaba dentro del área no imprimible de varias
          // impresoras (salía cortado por arriba).
          margin: const pw.EdgeInsets.fromLTRB(36, 48, 36, 36),
          build: (context) =>
              _buildContent(data, qrBytes: qrBytes, logoBytes: logoBytes),
        ),
      );
    }

    return pdf.save();
  }

  /// Construye el PDF en formato ticket térmico ~80mm de ancho.
  /// Layout vertical: logo → empresa centrada → bloque metadata derecha →
  /// "Factura a:" → cliente → items → totales → barcode.
  Future<Uint8List> buildThermalBytes(PrintDocumentData data) =>
      buildThermalDocumentsBytes([data]);

  /// Varios documentos térmicos concatenados en un solo PDF (factura + conduce).
  Future<Uint8List> buildThermalDocumentsBytes(
    List<PrintDocumentData> docs,
  ) async {
    final pdf = pw.Document(
      title: docs.first.documentNumber,
      author: docs.first.branch.name,
    );

    // 80mm = 226.77pt; usamos altura infinita (roll continuo).
    final format = PdfPageFormat(
      80 * PdfPageFormat.mm,
      double.infinity,
      marginAll: 8 * PdfPageFormat.mm,
    );

    for (final data in docs) {
      final logoBytes =
          await _shrinkImageForPdf(data.branch.logoBytes, maxDim: 320);
      pdf.addPage(
        pw.Page(
          pageFormat: format,
          build: (context) => _buildThermalContent(data, logoBytes),
        ),
      );
    }

    return pdf.save();
  }

  pw.Widget _buildContent(
    PrintDocumentData data, {
    Uint8List? qrBytes,
    Uint8List? logoBytes,
  }) {
    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.stretch,
      children: [
        _header(data, logoBytes),
        pw.SizedBox(height: 14),
        _titleBand(data),
        pw.SizedBox(height: 12),
        _clientBlock(data),
        pw.SizedBox(height: 12),
        _itemsTable(data),
        pw.SizedBox(height: 14),
        // En un conduce no se imprimen totales ni "TOTAL A PAGAR".
        if (!data.hidePrices) _bankAndTotal(data),
        if (_hasText(data.notes)) ...[
          pw.SizedBox(height: 10),
          pw.Text(
            'Notas: ${data.notes}',
            style: const pw.TextStyle(fontSize: 9.5, color: PdfColors.grey700),
          ),
        ],
        pw.Spacer(),
        _signatureAndObservation(data, qrBytes),
        if (_hasText(data.footerMessage)) ...[
          pw.SizedBox(height: 8),
          pw.Center(
            child: pw.Text(
              data.footerMessage!,
              style: pw.TextStyle(
                fontSize: 9.5,
                color: PdfColors.grey600,
                fontStyle: pw.FontStyle.italic,
              ),
            ),
          ),
        ],
      ],
    );
  }

  // ────────────────────────────────────────────────────────────────────────
  // Thermal (80mm) layout — sigue el formato del ticket de la foto.
  // ────────────────────────────────────────────────────────────────────────

  pw.Widget _buildThermalContent(PrintDocumentData data, Uint8List? logoBytes) {
    final mutedColor = PdfColors.grey700;
    final base = const pw.TextStyle(fontSize: 8.5);
    final muted = pw.TextStyle(fontSize: 8.5, color: mutedColor);
    final bold = pw.TextStyle(
      fontSize: 8.5,
      fontWeight: pw.FontWeight.bold,
    );
    final big = pw.TextStyle(
      fontSize: 11,
      fontWeight: pw.FontWeight.bold,
    );

    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.stretch,
      children: [
        // ── 1) Encabezado centrado: logo + empresa + dirección + teléfono ──
        if (logoBytes != null)
          pw.Center(
            child: pw.SizedBox(
              width: 60,
              height: 60,
              child: pw.Image(pw.MemoryImage(logoBytes)),
            ),
          ),
        if (logoBytes != null) pw.SizedBox(height: 4),
        pw.Center(
          child: pw.Text(
            data.branch.name.toUpperCase(),
            textAlign: pw.TextAlign.center,
            style: big,
          ),
        ),
        if (_hasText(data.branch.address))
          pw.Center(
            child: pw.Text(
              data.branch.address!,
              textAlign: pw.TextAlign.center,
              style: base,
            ),
          ),
        if (_hasText(data.branch.phone))
          pw.Center(
            child: pw.Text(
              data.branch.phone!,
              textAlign: pw.TextAlign.center,
              style: base,
            ),
          ),
        if (_hasText(data.branch.taxId))
          pw.Center(
            child: pw.Text(
              'RNC ${data.branch.taxId}',
              textAlign: pw.TextAlign.center,
              style: base,
            ),
          ),
        _thermalDashedDivider(),

        // Título CONDUCE (nota de entrega) — solo cuando se ocultan precios.
        if (data.hidePrices) ...[
          pw.Center(child: pw.Text('CONDUCE', style: big)),
          _thermalDashedDivider(),
        ],

        // ── 2) Fecha centrada ─────────────────────────────────────────────
        pw.Center(
          child: pw.Text(
            formatDateTime(data.issuedAt),
            style: base,
          ),
        ),
        _thermalDashedDivider(),

        // ── 3) Metadata centrada: serie, caja, tipo precio, empleado, NCF ─
        _thermalMetaRow('Serie y Número:', data.documentNumber, bold: bold, base: base),
        if (_hasText(data.cashRegisterName))
          _thermalMetaRow('Caja registradora:', data.cashRegisterName!, bold: bold, base: base),
        if (_hasText(data.priceTierLabel))
          _thermalMetaRow('Tipo de precio:', data.priceTierLabel!, bold: bold, base: base),
        if (_hasText(data.cashierName))
          _thermalMetaRow('Empleado:', data.cashierName!, bold: bold, base: base),
        if (_hasText(data.ncf))
          _thermalMetaRow('NCF:', data.ncf!, bold: bold, base: base),
        if (_hasText(data.receiptTypeLabel))
          _thermalMetaRow('Tipo comprobante:', data.receiptTypeLabel!, bold: bold, base: base),

        // ── 4) Bloque cliente "Factura a:" ────────────────────────────────
        if (data.customer != null) ...[
          _thermalDashedDivider(),
          pw.Text('Factura a:', style: bold),
          pw.SizedBox(height: 2),
          pw.Text('Cliente: ${data.customer!.name}', style: base),
          if (_hasText(data.customer!.address))
            pw.Text('Dirección : ${data.customer!.address}', style: base),
          if (_hasText(data.customer!.document))
            pw.Text('Doc: ${data.customer!.document}', style: base),
          if (_hasText(data.customer!.phone))
            pw.Text('Teléfono : ${data.customer!.phone}', style: base),
        ],

        // ── 5) Tabla de items ─────────────────────────────────────────────
        _thermalDashedDivider(),
        _thermalItemsTable(data, base: base, bold: bold, muted: muted),

        // ── 6) Totales alineados a la derecha (no en conduce) ─────────────
        if (!data.hidePrices) ...[
          _thermalDashedDivider(),
          _thermalTotals(data, base: base, bold: bold),
        ],

        // ── 7) Notas / acuse de entrega / footer / barcode ────────────────
        if (_hasText(data.notes)) ...[
          _thermalDashedDivider(),
          pw.Text('Notas: ${data.notes}', style: muted),
        ],
        // Conduce: acuse de recibo, igual que en el A4 — quien recibe la
        // mercancía firma aquí.
        if (data.hidePrices) ...[
          _thermalDashedDivider(),
          pw.Text('RECIBIDO POR:', style: bold),
          _thermalFormLine('Nombre', style: base),
          _thermalFormLine('Cédula o ID', style: base),
          _thermalFormLine('Firma', style: base),
          _thermalFormLine('Fecha', style: base),
        ],
        if (_hasText(data.footerMessage)) ...[
          pw.SizedBox(height: 6),
          pw.Center(
            child: pw.Text(
              data.footerMessage!,
              textAlign: pw.TextAlign.center,
              style: pw.TextStyle(
                fontSize: 8.5,
                fontStyle: pw.FontStyle.italic,
                color: mutedColor,
              ),
            ),
          ),
        ],
        if (data.showBarcode) ...[
          _thermalDashedDivider(),
          pw.Center(
            child: pw.BarcodeWidget(
              barcode: pw.Barcode.code128(),
              data: data.documentNumber,
              width: 180,
              height: 40,
              drawText: true,
              textStyle: const pw.TextStyle(fontSize: 8),
            ),
          ),
        ],
      ],
    );
  }

  /// Separador discontinuo estilo ticket térmico clásico (- - - - -).
  /// Se renderiza como texto plano para no depender de `BorderStyle.dashed`
  /// (que no existe en `pdf ^3.12`).
  pw.Widget _thermalDashedDivider() {
    return pw.Padding(
      padding: const pw.EdgeInsets.symmetric(vertical: 4),
      child: pw.Text(
        '- ' * 32,
        textAlign: pw.TextAlign.center,
        overflow: pw.TextOverflow.clip,
        style: pw.TextStyle(
          fontSize: 7,
          color: PdfColors.grey600,
        ),
      ),
    );
  }

  /// Línea de formulario del ticket (`Firma _________`) para el acuse de
  /// entrega del conduce.
  pw.Widget _thermalFormLine(String label, {required pw.TextStyle style}) {
    return pw.Padding(
      padding: const pw.EdgeInsets.only(top: 8),
      child: pw.Text('$label: ______________________', style: style),
    );
  }

  pw.Widget _thermalMetaRow(
    String label,
    String value, {
    required pw.TextStyle bold,
    required pw.TextStyle base,
  }) {
    return pw.Padding(
      padding: const pw.EdgeInsets.symmetric(vertical: 1),
      child: pw.Center(
        child: pw.RichText(
          textAlign: pw.TextAlign.center,
          text: pw.TextSpan(
            children: [
              pw.TextSpan(text: '$label  ', style: bold),
              pw.TextSpan(text: value, style: base),
            ],
          ),
        ),
      ),
    );
  }

  pw.Widget _thermalItemsTable(
    PrintDocumentData data, {
    required pw.TextStyle base,
    required pw.TextStyle bold,
    required pw.TextStyle muted,
  }) {
    // Conduce: solo Nombre + Cant., sin precio ni total.
    if (data.hidePrices) {
      return pw.Table(
        columnWidths: const {
          0: pw.FlexColumnWidth(1),
          1: pw.FixedColumnWidth(40),
        },
        children: [
          pw.TableRow(
            decoration: const pw.BoxDecoration(
              border: pw.Border(
                bottom: pw.BorderSide(color: PdfColors.grey700, width: 0.5),
              ),
            ),
            children: [
              _thermalCell('Nombre', style: bold),
              _thermalCell('Cant.', style: bold, align: pw.Alignment.center),
            ],
          ),
          for (final item in data.items)
            pw.TableRow(
              children: [
                _thermalCell(item.description, style: base),
                _thermalCell(
                  _qty(item.quantity),
                  style: base,
                  align: pw.Alignment.center,
                ),
              ],
            ),
        ],
      );
    }
    // El ancho útil del ticket son ~181pt (80mm − 8mm de margen a cada lado).
    // Con "RD$" en cada línea los importes no entraban y saltaban de línea,
    // así que las columnas van sin símbolo (`moneyPlain`) y este aparece una
    // sola vez, en los totales.
    final amountStyle = pw.TextStyle(fontSize: base.fontSize! - 0.5);
    return pw.Table(
      columnWidths: const {
        0: pw.FlexColumnWidth(1),   // Nombre (toma el espacio restante)
        1: pw.FixedColumnWidth(45), // Precio — "999,999.99" sin símbolo
        2: pw.FixedColumnWidth(26), // Cant
        3: pw.FixedColumnWidth(49), // Total
      },
      children: [
        // Header
        pw.TableRow(
          decoration: const pw.BoxDecoration(
            border: pw.Border(
              bottom: pw.BorderSide(color: PdfColors.grey700, width: 0.5),
            ),
          ),
          children: [
            _thermalCell('Nombre', style: bold),
            _thermalCell('Precio', style: bold, align: pw.Alignment.centerRight),
            _thermalCell('Cant', style: bold, align: pw.Alignment.center),
            _thermalCell('Total', style: bold, align: pw.Alignment.centerRight),
          ],
        ),
        for (final item in data.items)
          pw.TableRow(
            children: [
              _thermalCell(item.description, style: base),
              _thermalCell(
                moneyPlain(item.unitPrice),
                style: amountStyle,
                align: pw.Alignment.centerRight,
                noWrap: true,
              ),
              _thermalCell(
                _qty(item.quantity),
                style: base,
                align: pw.Alignment.center,
              ),
              _thermalCell(
                moneyPlain(item.lineTotal),
                style: amountStyle,
                align: pw.Alignment.centerRight,
                noWrap: true,
              ),
            ],
          ),
      ],
    );
  }

  pw.Widget _thermalCell(
    String text, {
    required pw.TextStyle style,
    pw.Alignment align = pw.Alignment.centerLeft,
    bool noWrap = false,
  }) {
    return pw.Padding(
      // Padding interno mayor: separa visualmente columnas (antes 1pt
      // hacía que "2" tocara "1,100.00").
      padding: const pw.EdgeInsets.symmetric(vertical: 4, horizontal: 2),
      child: pw.Align(
        alignment: align,
        child: pw.Text(
          text,
          style: style,
          softWrap: noWrap ? false : null,
          maxLines: noWrap ? 1 : null,
          textAlign: noWrap ? pw.TextAlign.right : null,
        ),
      ),
    );
  }

  pw.Widget _thermalTotals(
    PrintDocumentData data, {
    required pw.TextStyle base,
    required pw.TextStyle bold,
  }) {
    pw.Widget line(String label, String value, {bool emphasized = false}) {
      return pw.Padding(
        padding: const pw.EdgeInsets.symmetric(vertical: 1),
        child: pw.Row(
          mainAxisAlignment: pw.MainAxisAlignment.end,
          children: [
            pw.Text(label, style: emphasized ? bold : base),
            pw.SizedBox(width: 12),
            pw.SizedBox(
              width: 84,
              child: pw.Text(
                value,
                softWrap: false,
                maxLines: 1,
                textAlign: pw.TextAlign.right,
                style: emphasized ? bold : base,
              ),
            ),
          ],
        ),
      );
    }

    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.stretch,
      children: [
        line('Subtotal', money(data.totals.subtotal)),
        if (data.totals.discount > 0)
          line('Descuento', '-${money(data.totals.discount)}'),
        if (data.totals.serviceCharge > 0)
          line('Servicio', money(data.totals.serviceCharge)),
        if (data.totals.tax > 0) line('ITBIS', money(data.totals.tax)),
        line('Total', money(data.totals.total), emphasized: true),
        if (data.changeAmount != null && data.changeAmount! >= 0)
          line('Cambio', money(data.changeAmount!)),
        if (data.totals.balance > 0)
          line('Pendiente', money(data.totals.balance), emphasized: true),
        for (final payment in data.payments)
          line(payment.method, money(payment.amount)),
      ],
    );
  }

  pw.Widget _header(PrintDocumentData data, Uint8List? logoBytes) {
    return pw.Row(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        // Emisor (izquierda): RNC, dirección, teléfono(s), email.
        pw.Expanded(
          child: pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              if (_hasText(data.branch.taxId))
                pw.Text(
                  'RNC: ${data.branch.taxId}',
                  style: pw.TextStyle(
                    fontSize: 10,
                    fontWeight: pw.FontWeight.bold,
                  ),
                ),
              for (final line in _lines(data.branch.address))
                pw.Text(
                  line,
                  style: const pw.TextStyle(
                    fontSize: 9.5,
                    color: PdfColors.grey700,
                  ),
                ),
              if (_hasText(data.branch.phone))
                pw.Text(
                  data.branch.phone!,
                  style: const pw.TextStyle(
                    fontSize: 9.5,
                    color: PdfColors.grey700,
                  ),
                ),
              if (_hasText(data.branch.email))
                pw.Text(
                  data.branch.email!,
                  style: const pw.TextStyle(
                    fontSize: 9.5,
                    color: PdfColors.grey700,
                  ),
                ),
            ],
          ),
        ),
        pw.SizedBox(width: 16),
        // Logo + nombre comercial + número de documento (derecha).
        pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.end,
          children: [
            // Caja fija + BoxFit.contain: el logo entra completo sea cual sea
            // su relación de aspecto. Sin el ancho acotado, un logo apaisado
            // se comía el ancho de la fila y aplastaba los datos del emisor.
            if (logoBytes != null)
              pw.SizedBox(
                width: 130,
                height: 50,
                child: pw.Image(
                  pw.MemoryImage(logoBytes),
                  fit: pw.BoxFit.contain,
                  alignment: pw.Alignment.centerRight,
                ),
              ),
            pw.SizedBox(height: 3),
            pw.Text(
              data.branch.name,
              style: pw.TextStyle(
                fontSize: 13,
                fontWeight: pw.FontWeight.bold,
                color: _kNavy,
                letterSpacing: 1,
              ),
            ),
            pw.SizedBox(height: 16),
            pw.Text(
              data.documentNumber,
              style: pw.TextStyle(
                fontSize: 12,
                fontWeight: pw.FontWeight.bold,
                color: _kNavy,
              ),
            ),
          ],
        ),
      ],
    );
  }

  /// Banda central con líneas punteadas y el título según el comprobante.
  pw.Widget _titleBand(PrintDocumentData data) {
    return pw.Column(
      children: [
        _dottedLine(),
        pw.SizedBox(height: 7),
        pw.Center(
          child: pw.Text(
            _invoiceTitle(data),
            style: pw.TextStyle(
              fontSize: 13,
              fontWeight: pw.FontWeight.bold,
              color: _kNavy,
              letterSpacing: 0.5,
            ),
          ),
        ),
        pw.SizedBox(height: 7),
        _dottedLine(),
      ],
    );
  }

  pw.Widget _dottedLine() {
    return pw.Container(
      decoration: const pw.BoxDecoration(
        border: pw.Border(
          bottom: pw.BorderSide(
            color: PdfColors.grey500,
            width: 0.8,
            style: pw.BorderStyle.dotted,
          ),
        ),
      ),
      child: pw.SizedBox(width: double.infinity, height: 0),
    );
  }

  pw.Widget _clientBlock(PrintDocumentData data) {
    final c = data.customer;
    pw.Widget row(String label, String value) {
      return pw.Padding(
        padding: const pw.EdgeInsets.symmetric(vertical: 1.5),
        child: pw.Row(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.SizedBox(
              width: 96,
              child: pw.Text(
                label,
                style: pw.TextStyle(
                  fontSize: 10,
                  fontWeight: pw.FontWeight.bold,
                ),
              ),
            ),
            pw.Expanded(
              child: pw.Text(value, style: const pw.TextStyle(fontSize: 10)),
            ),
          ],
        ),
      );
    }

    // Etiqueta del documento según su prefijo (RNC / Cédula / etc.).
    final docRaw = (c?.document ?? '').toLowerCase();
    final docLabel = docRaw.contains('céd') || docRaw.contains('ced')
        ? 'Cédula:'
        : docRaw.contains('pasa')
            ? 'Pasaporte:'
            : 'RNC:';

    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        row('Cliente:', c?.name ?? 'Consumidor Final'),
        row(docLabel, _docNumberOnly(c?.document) ?? 'N/A'),
        if (_hasText(c?.address)) row('Dirección:', c!.address!),
        if (_hasText(c?.phone)) row('Teléfono:', c!.phone!),
        if (_hasText(c?.email)) row('Email:', c!.email!),
        row('Fecha:', _dateLabel(data.issuedAt)),
        if (_hasText(data.paymentTermsLabel))
          row('Forma de pago:', data.paymentTermsLabel!),
        if (_hasText(data.ncf)) row('NCF:', data.ncf!),
        if (_hasText(data.referenceNumber)) row('', data.referenceNumber!),
      ],
    );
  }

  pw.Widget _itemsTable(PrintDocumentData data) {
    pw.Widget hCell(String text, {pw.Alignment align = pw.Alignment.centerLeft}) {
      return pw.Padding(
        padding: const pw.EdgeInsets.symmetric(vertical: 6, horizontal: 3),
        child: pw.Align(
          alignment: align,
          child: pw.Text(
            text,
            style: pw.TextStyle(
              fontSize: 8.5,
              fontWeight: pw.FontWeight.bold,
              color: PdfColors.grey800,
            ),
          ),
        ),
      );
    }

    pw.Widget cell(
      String text, {
      pw.Alignment align = pw.Alignment.centerLeft,
      bool bold = false,
    }) {
      return pw.Padding(
        padding: const pw.EdgeInsets.symmetric(vertical: 5, horizontal: 3),
        child: pw.Align(
          alignment: align,
          child: pw.Text(
            text,
            style: pw.TextStyle(
              fontSize: 9.5,
              fontWeight: bold ? pw.FontWeight.bold : null,
            ),
          ),
        ),
      );
    }

    // Celda de monto: una sola línea, siempre. Sin `softWrap: false` el
    // espacio de "RD$ 76.27" era un punto de corte válido y el importe salía
    // partido — "RD$" arriba y el número abajo.
    pw.Widget moneyCell(String text, {bool bold = false}) {
      return pw.Padding(
        padding: const pw.EdgeInsets.symmetric(vertical: 5, horizontal: 3),
        child: pw.Align(
          alignment: pw.Alignment.centerRight,
          child: pw.Text(
            text,
            softWrap: false,
            maxLines: 1,
            textAlign: pw.TextAlign.right,
            style: pw.TextStyle(
              fontSize: 9,
              fontWeight: bold ? pw.FontWeight.bold : null,
            ),
          ),
        ),
      );
    }

    const right = pw.Alignment.centerRight;

    // Conduce (nota de entrega): solo Cantidad + Descripción, sin montos.
    if (data.hidePrices) {
      return pw.Table(
        columnWidths: const <int, pw.TableColumnWidth>{
          0: pw.FixedColumnWidth(70),
          1: pw.FlexColumnWidth(1),
        },
        children: [
          pw.TableRow(
            decoration: const pw.BoxDecoration(
              border: pw.Border(
                top: pw.BorderSide(color: PdfColors.grey700, width: 0.8),
                bottom: pw.BorderSide(color: PdfColors.grey700, width: 0.8),
              ),
            ),
            children: [
              hCell('CANTIDAD', align: pw.Alignment.center),
              hCell('DESCRIPCION'),
            ],
          ),
          for (final it in data.items)
            pw.TableRow(
              decoration: const pw.BoxDecoration(
                border: pw.Border(
                  bottom: pw.BorderSide(color: PdfColors.grey200, width: 0.5),
                ),
              ),
              children: [
                cell(_qty(it.quantity), align: pw.Alignment.center),
                cell(it.description),
              ],
            ),
        ],
      );
    }

    final showTax = data.showTax;
    // Anchos dimensionados para que "RD$ 999,999.99" entre completo en una
    // línea a 9pt (≈72pt de texto + 6pt de padding). La columna ITBIS tenía
    // 36pt — de ahí que el importe se partiera en dos líneas.
    // Sin ITBIS se reparte su ancho entre las demás columnas numéricas.
    final columnWidths = showTax
        ? const <int, pw.TableColumnWidth>{
            0: pw.FixedColumnWidth(56), // "CANTIDAD" en una línea
            1: pw.FlexColumnWidth(3),
            2: pw.FixedColumnWidth(74),
            3: pw.FixedColumnWidth(74),
            4: pw.FixedColumnWidth(68),
            5: pw.FixedColumnWidth(80),
          }
        : const <int, pw.TableColumnWidth>{
            0: pw.FixedColumnWidth(56), // "CANTIDAD" en una línea
            1: pw.FlexColumnWidth(3),
            2: pw.FixedColumnWidth(80),
            3: pw.FixedColumnWidth(80),
            4: pw.FixedColumnWidth(86),
          };
    return pw.Table(
      columnWidths: columnWidths,
      children: [
        pw.TableRow(
          decoration: const pw.BoxDecoration(
            border: pw.Border(
              top: pw.BorderSide(color: PdfColors.grey700, width: 0.8),
              bottom: pw.BorderSide(color: PdfColors.grey700, width: 0.8),
            ),
          ),
          children: [
            hCell('CANTIDAD', align: pw.Alignment.center),
            hCell('DESCRIPCION'),
            hCell('MONTO', align: right),
            hCell('SUB TOTAL', align: right),
            if (showTax) hCell('ITBIS', align: right),
            hCell('VALOR TOTAL', align: right),
          ],
        ),
        for (final it in data.items)
          pw.TableRow(
            decoration: const pw.BoxDecoration(
              border: pw.Border(
                bottom: pw.BorderSide(color: PdfColors.grey200, width: 0.5),
              ),
            ),
            children: [
              cell(_qty(it.quantity), align: pw.Alignment.center),
              cell(it.description),
              moneyCell(money(it.unitPrice)),
              moneyCell(money(it.lineSubtotal)),
              if (showTax)
                moneyCell(it.lineTax > 0.0049 ? money(it.lineTax) : '-'),
              moneyCell(money(it.lineTotal), bold: true),
            ],
          ),
      ],
    );
  }

  /// Datos bancarios (izquierda) + "TOTAL A PAGAR" en rojo (derecha).
  pw.Widget _bankAndTotal(PrintDocumentData data) {
    final bankLines = _lines(data.branch.bankInfo);
    // El ITBIS solo se desglosa si el documento lleva impuesto (data.showTax).
    final showBreakdown = (data.showTax && data.totals.tax > 0.0049) ||
        data.totals.discount > 0.0049 ||
        data.totals.serviceCharge > 0.0049;
    return pw.Row(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Expanded(
          child: pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              for (final line in bankLines)
                pw.Text(
                  line,
                  style: pw.TextStyle(
                    fontSize: 9.5,
                    fontWeight: pw.FontWeight.bold,
                    color: PdfColors.grey800,
                  ),
                ),
            ],
          ),
        ),
        pw.SizedBox(width: 16),
        pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.end,
          children: [
            if (showBreakdown) ...[
              _miniTotal('Subtotal', money(data.totals.subtotal)),
              if (data.totals.discount > 0.0049)
                _miniTotal('Descuento', '-${money(data.totals.discount)}'),
              if (data.totals.serviceCharge > 0.0049)
                _miniTotal('Ley / Servicio', money(data.totals.serviceCharge)),
              if (data.showTax && data.totals.tax > 0.0049)
                _miniTotal('ITBIS', money(data.totals.tax)),
              pw.SizedBox(height: 3),
            ],
            pw.Row(
              mainAxisSize: pw.MainAxisSize.min,
              crossAxisAlignment: pw.CrossAxisAlignment.center,
              children: [
                pw.Text(
                  'TOTAL A\nPAGAR',
                  textAlign: pw.TextAlign.right,
                  style: pw.TextStyle(
                    fontSize: 10,
                    fontWeight: pw.FontWeight.bold,
                    color: PdfColors.grey600,
                  ),
                ),
                pw.SizedBox(width: 12),
                pw.Text(
                  money(data.totals.total),
                  softWrap: false,
                  maxLines: 1,
                  style: pw.TextStyle(
                    fontSize: 17,
                    fontWeight: pw.FontWeight.bold,
                    color: _kRed,
                  ),
                ),
              ],
            ),
            if (data.totals.balance > 0.0049)
              pw.Padding(
                padding: const pw.EdgeInsets.only(top: 2),
                child: _miniTotal(
                  'Balance pendiente',
                  money(data.totals.balance),
                ),
              ),
          ],
        ),
      ],
    );
  }

  pw.Widget _miniTotal(String label, String value) {
    return pw.Padding(
      padding: const pw.EdgeInsets.symmetric(vertical: 1),
      child: pw.Row(
        mainAxisSize: pw.MainAxisSize.min,
        children: [
          pw.Text(
            '$label:',
            style: const pw.TextStyle(fontSize: 9.5, color: PdfColors.grey600),
          ),
          pw.SizedBox(width: 8),
          pw.Text(
            value,
            softWrap: false,
            maxLines: 1,
            style: const pw.TextStyle(fontSize: 9.5),
          ),
        ],
      ),
    );
  }

  /// Firma del emisor + bloque del receptor (OBSERVACION en factura,
  /// RECIBIDO POR en conduce) + QR.
  pw.Widget _signatureAndObservation(
    PrintDocumentData data,
    Uint8List? qrBytes,
  ) {
    // En un conduce el bloque del receptor es el acuse de entrega: quien
    // recibe la mercancía firma ahí. En una factura es la observación.
    final isConduce = data.hidePrices;

    pw.Widget formLine(String label) {
      return pw.Padding(
        padding: const pw.EdgeInsets.only(top: 6),
        child: pw.Text(
          '$label _______________________',
          style: const pw.TextStyle(fontSize: 9.5),
        ),
      );
    }

    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        if (_hasText(data.branch.signatoryName)) ...[
          pw.SizedBox(height: 4),
          pw.Center(
            child: pw.Column(
              children: [
                pw.Container(
                  width: 220,
                  decoration: const pw.BoxDecoration(
                    border: pw.Border(
                      top: pw.BorderSide(color: PdfColors.grey500, width: 0.8),
                    ),
                  ),
                  padding: const pw.EdgeInsets.only(top: 3),
                  child: pw.Text(
                    data.branch.signatoryName!,
                    textAlign: pw.TextAlign.center,
                    style: pw.TextStyle(
                      fontSize: 10,
                      fontStyle: pw.FontStyle.italic,
                    ),
                  ),
                ),
                if (_hasText(data.branch.signatoryTitle))
                  pw.Text(
                    data.branch.signatoryTitle!,
                    style: const pw.TextStyle(
                      fontSize: 9,
                      color: PdfColors.grey600,
                    ),
                  ),
              ],
            ),
          ),
          pw.SizedBox(height: 14),
        ],
        pw.Row(
          crossAxisAlignment: pw.CrossAxisAlignment.end,
          children: [
            pw.Expanded(
              child: pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  pw.Text(
                    isConduce ? 'RECIBIDO POR:' : 'OBSERVACION:',
                    style: pw.TextStyle(
                      fontSize: 9,
                      fontWeight: pw.FontWeight.bold,
                    ),
                  ),
                  if (!isConduce && _hasText(data.observation))
                    pw.Padding(
                      padding: const pw.EdgeInsets.only(top: 2),
                      child: pw.Text(
                        data.observation!,
                        style: const pw.TextStyle(
                          fontSize: 9,
                          color: PdfColors.grey700,
                        ),
                      ),
                    ),
                  formLine(
                    isConduce
                        ? 'Nombre de quien recibe:'
                        : 'Nombre del representante:',
                  ),
                  formLine('Cédula o ID:'),
                  formLine('Firma:'),
                  formLine('Fecha:'),
                ],
              ),
            ),
            if (qrBytes != null) ...[
              pw.SizedBox(width: 16),
              pw.Image(pw.MemoryImage(qrBytes), width: 92, height: 92),
            ],
          ],
        ),
      ],
    );
  }
}

/// Título del documento según el comprobante seleccionado. Para venta usa el
/// `receiptTypeLabel`; para cotización siempre "COTIZACIÓN".
String _invoiceTitle(PrintDocumentData data) {
  if (data.hidePrices) return 'CONDUCE';
  if (data.documentType == PrintDocumentType.quote) return 'COTIZACIÓN';
  if (data.documentType == PrintDocumentType.paymentReceipt) {
    return 'RECIBO DE ABONO';
  }
  if (data.documentType == PrintDocumentType.expenseVoucher) {
    return 'COMPROBANTE DE GASTO';
  }
  final label = (data.receiptTypeLabel ?? '').toLowerCase();
  if (label.contains('sin comprobante')) return 'NOTA DE VENTA';
  if (label.contains('consumidor')) return 'FACTURA PARA CONSUMIDOR FINAL';
  if (label.contains('crédito') ||
      label.contains('credito') ||
      label.contains('fiscal')) {
    return 'FACTURA CON CRÉDITO FISCAL';
  }
  if (label.contains('gubernamental')) return 'FACTURA GUBERNAMENTAL';
  if (label.contains('especial')) return 'FACTURA RÉGIMEN ESPECIAL';
  if (label.contains('exporta')) return 'FACTURA DE EXPORTACIÓN';
  return 'FACTURA';
}

/// Divide un texto multilínea en líneas no vacías (para dirección / banco).
List<String> _lines(String? text) {
  if (text == null) return const [];
  return text
      .split('\n')
      .map((l) => l.trim())
      .where((l) => l.isNotEmpty)
      .toList(growable: false);
}

/// Quita el prefijo "RNC:"/"CÉDULA:" del documento del cliente y deja el número.
String? _docNumberOnly(String? doc) {
  if (!_hasText(doc)) return null;
  final idx = doc!.indexOf(':');
  return idx >= 0 ? doc.substring(idx + 1).trim() : doc.trim();
}

/// Fecha corta dd/MM/yyyy (formato de la factura).
String _dateLabel(DateTime dt) {
  final l = dt.isUtc ? dt.toLocal() : dt;
  final dd = l.day.toString().padLeft(2, '0');
  final mm = l.month.toString().padLeft(2, '0');
  return '$dd/$mm/${l.year}';
}

bool _hasText(String? value) => value != null && value.trim().isNotEmpty;

String _qty(double value) {
  if (value == value.roundToDouble()) return value.toStringAsFixed(0);
  return value.toStringAsFixed(2);
}
