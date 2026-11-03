import 'dart:typed_data';

import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

import '../../../shared/formatters/formatters.dart';
import 'ecf_onboarding_models.dart';

/// Representación impresa (RI) de un e-CF de las pruebas de simulación de la
/// DGII, con el orden y los datos que pide la DGII (Informe Técnico e-CF,
/// sección 18):
///   - encabezado derecho: tipo en palabras, e-NCF, vencimiento y, en notas,
///     e-NCF modificado y código de modificación en palabras;
///   - encabezado izquierdo: emisor (nombre comercial, razón social, RNC,
///     dirección, municipio, provincia, fecha de emisión) y, abajo, el cliente;
///   - detalle: cantidad, "E" en lo exento, descripción, unidad en palabras,
///     precio, ITBIS, descuento/recargo y valor;
///   - totales;
///   - abajo a la izquierda: QR (≥ 22 × 22 mm, a ≥ 2 cm del borde), código de
///     seguridad y fecha de firma digital.
/// Todo sale de [EcfPrintModel], que arma el servidor con lo mismo que firmó.
///
/// Portado del panel de MangoPOS (`lib/data/services/ecf_print_pdf.dart`).

/// Monto del XML con separador de miles. Los precios pueden traer hasta 4
/// decimales: si no son ceros, se deja el valor tal cual viene en el XML.
String _money(String? raw) {
  if (raw == null || raw.isEmpty) return '';
  final n = num.tryParse(raw);
  if (n == null) return raw;
  final decimals = raw.contains('.')
      ? raw.split('.').last.replaceFirst(RegExp(r'0+$'), '').length
      : 0;
  if (decimals > 2) return raw;
  return moneyPlain(n);
}

String _quantity(String? raw) {
  if (raw == null || raw.isEmpty) return '';
  final n = num.tryParse(raw);
  if (n == null) return raw;
  return n == n.roundToDouble()
      ? n.toInt().toString()
      : raw.replaceFirst(RegExp(r'0+$'), '');
}

/// PDF de la RI. Las fuentes se bajan de Google Fonts (como los demás PDF de
/// la app): con acentos y la Ñ. Las pruebas pasan las suyas.
Future<Uint8List> buildEcfPrintPdf(
  EcfPrintModel m, {
  pw.Font? font,
  pw.Font? boldFont,
}) async {
  final regular = font ?? await PdfGoogleFonts.robotoRegular();
  final bold = boldFont ?? await PdfGoogleFonts.robotoBold();
  final doc = pw.Document(
    title: '${m.typeName} ${m.encf}',
    author: m.issuer.legalName ?? m.issuer.rnc,
    creator: 'Busi Pos Web',
    theme: pw.ThemeData.withFont(base: regular, bold: bold),
  );

  final hasUnit = m.items.any((i) => i.unit != null);
  final hasDiscount = m.items.any((i) => i.discount != null);
  final hasSurcharge = m.items.any((i) => i.surcharge != null);
  final hasItbis = m.items.any((i) => i.itbis != null);

  doc.addPage(
    pw.MultiPage(
      pageFormat: PdfPageFormat.letter.copyWith(
        marginLeft: 2 * PdfPageFormat.cm,
        marginRight: 2 * PdfPageFormat.cm,
        marginTop: 1.8 * PdfPageFormat.cm,
        marginBottom: 2 * PdfPageFormat.cm,
      ),
      // Con paginación, el encabezado se repite en cada página.
      header: (ctx) => _header(m),
      footer: (ctx) => ctx.pagesCount > 1
          ? pw.Align(
              alignment: pw.Alignment.centerRight,
              child: pw.Text(
                'Página ${ctx.pageNumber} de ${ctx.pagesCount}',
                style: const pw.TextStyle(fontSize: 8),
              ),
            )
          : pw.SizedBox(),
      build: (ctx) => [
        pw.SizedBox(height: 10),
        _itemsTable(
          m,
          hasUnit: hasUnit,
          hasDiscount: hasDiscount,
          hasSurcharge: hasSurcharge,
          hasItbis: hasItbis,
        ),
        if (m.adjustments.isNotEmpty) ...[
          pw.SizedBox(height: 8),
          _adjustments(m),
        ],
        pw.SizedBox(height: 14),
        pw.Row(
          crossAxisAlignment: pw.CrossAxisAlignment.end,
          children: [_qr(m), pw.Spacer(), _totals(m)],
        ),
      ],
    ),
  );
  return doc.save();
}

pw.Widget _line(
  String label,
  String? value, {
  double size = 9,
  bool strong = false,
}) {
  if (value == null || value.isEmpty) return pw.SizedBox();
  return pw.Padding(
    padding: const pw.EdgeInsets.only(bottom: 1.5),
    child: pw.RichText(
      text: pw.TextSpan(
        style: pw.TextStyle(fontSize: size),
        children: [
          if (label.isNotEmpty)
            pw.TextSpan(
              text: '$label: ',
              style: pw.TextStyle(fontWeight: pw.FontWeight.bold),
            ),
          pw.TextSpan(
            text: value,
            style: strong ? pw.TextStyle(fontWeight: pw.FontWeight.bold) : null,
          ),
        ],
      ),
    ),
  );
}

pw.Widget _header(EcfPrintModel m) {
  final i = m.issuer;
  final b = m.buyer;
  return pw.Column(
    crossAxisAlignment: pw.CrossAxisAlignment.stretch,
    children: [
      pw.Row(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Expanded(
            flex: 6,
            child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                if (i.tradeName != null)
                  pw.Text(
                    i.tradeName!,
                    style: pw.TextStyle(
                      fontSize: 13,
                      fontWeight: pw.FontWeight.bold,
                    ),
                  ),
                if (i.legalName != null && i.legalName != i.tradeName)
                  pw.Text(
                    i.legalName!,
                    style: pw.TextStyle(
                      fontSize: 10,
                      fontWeight: pw.FontWeight.bold,
                    ),
                  ),
                pw.SizedBox(height: 4),
                _line('Sucursal', i.branch),
                _line('RNC', i.rnc),
                _line('Dirección', i.address),
                _line('Municipio', i.municipality),
                _line('Provincia', i.province),
                _line('Teléfono', i.phone),
                _line('Correo', i.email),
                _line('Fecha de emisión', i.issueDate),
              ],
            ),
          ),
          pw.SizedBox(width: 16),
          pw.Expanded(
            flex: 5,
            child: pw.Container(
              padding: const pw.EdgeInsets.all(8),
              decoration: pw.BoxDecoration(
                border: pw.Border.all(color: PdfColors.grey600, width: 0.8),
              ),
              child: pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  pw.Text(
                    m.typeName,
                    style: pw.TextStyle(
                      fontSize: 11,
                      fontWeight: pw.FontWeight.bold,
                    ),
                  ),
                  pw.SizedBox(height: 4),
                  _line('e-NCF', m.encf, size: 10, strong: true),
                  _line('Fecha de vencimiento', m.dueDate),
                  _line('e-NCF modificado', m.modifiedEncf),
                  _line('Fecha e-NCF modificado', m.modifiedDate),
                  _line('Código de modificación', m.modification),
                  _line('Razón de modificación', m.modificationReason),
                ],
              ),
            ),
          ),
        ],
      ),
      if (b != null) ...[
        pw.SizedBox(height: 8),
        pw.Container(
          padding: const pw.EdgeInsets.symmetric(vertical: 4),
          decoration: const pw.BoxDecoration(
            border: pw.Border(
              top: pw.BorderSide(color: PdfColors.grey400, width: 0.6),
            ),
          ),
          child: pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              _line('Razón social cliente', b.name),
              _line('RNC cliente', b.rnc),
              _line('Identificación extranjera', b.foreignId),
            ],
          ),
        ),
      ],
      pw.SizedBox(height: 4),
    ],
  );
}

pw.Widget _itemsTable(
  EcfPrintModel m, {
  required bool hasUnit,
  required bool hasDiscount,
  required bool hasSurcharge,
  required bool hasItbis,
}) {
  final headers = <String>[
    'Cantidad',
    'Descripción',
    if (hasUnit) 'Unidad',
    'Precio',
    if (hasItbis) 'ITBIS',
    if (hasDiscount) 'Descuento',
    if (hasSurcharge) 'Recargo',
    'Valor',
  ];
  final rows = m.items.map((it) {
    final description =
        '${it.exempt ? 'E  ' : ''}${it.description}'
        '${it.detail != null ? '\n${it.detail}' : ''}';
    return <String>[
      _quantity(it.quantity),
      description,
      if (hasUnit) it.unit ?? '',
      _money(it.price),
      if (hasItbis) _money(it.itbis),
      if (hasDiscount) _money(it.discount),
      if (hasSurcharge) _money(it.surcharge),
      _money(it.value),
    ];
  }).toList();
  final numeric = <int>{
    0,
    for (var c = 2; c < headers.length; c++)
      if (headers[c] != 'Unidad') c,
  };
  return pw.TableHelper.fromTextArray(
    headers: headers,
    data: rows,
    headerStyle: pw.TextStyle(fontSize: 8.5, fontWeight: pw.FontWeight.bold),
    cellStyle: const pw.TextStyle(fontSize: 8.5),
    headerDecoration: const pw.BoxDecoration(color: PdfColors.grey200),
    border: const pw.TableBorder(
      horizontalInside: pw.BorderSide(color: PdfColors.grey300, width: 0.5),
      bottom: pw.BorderSide(color: PdfColors.grey500, width: 0.6),
      top: pw.BorderSide(color: PdfColors.grey500, width: 0.6),
    ),
    cellPadding: const pw.EdgeInsets.symmetric(horizontal: 4, vertical: 3),
    // Ancho fijo para los números (que el encabezado no se parta) y el resto
    // para la descripción.
    columnWidths: {
      for (var c = 0; c < headers.length; c++)
        c: c == 1
            ? const pw.FlexColumnWidth()
            : pw.FixedColumnWidth(switch (headers[c]) {
                'Cantidad' => 46,
                'Unidad' => 58,
                'Valor' => 66,
                _ => 56,
              }),
    },
    cellAlignments: {
      for (var c = 0; c < headers.length; c++)
        c: numeric.contains(c)
            ? pw.Alignment.centerRight
            : pw.Alignment.centerLeft,
    },
  );
}

pw.Widget _adjustments(EcfPrintModel m) {
  return pw.Column(
    crossAxisAlignment: pw.CrossAxisAlignment.start,
    children: [
      for (final a in m.adjustments)
        _line(
          a.kind == 'R' ? 'Recargo' : 'Descuento',
          [
            a.description,
            if (a.percent != null) '${a.percent}%',
            if (a.amount != null) _money(a.amount),
          ].where((s) => s.isNotEmpty).join(' · '),
        ),
    ],
  );
}

pw.Widget _totals(EcfPrintModel m) {
  final t = m.totals;
  pw.TableRow row(String label, String? value, {bool strong = false}) {
    final style = pw.TextStyle(
      fontSize: strong ? 10.5 : 9,
      fontWeight: strong ? pw.FontWeight.bold : null,
    );
    return pw.TableRow(
      children: [
        pw.Padding(
          padding: const pw.EdgeInsets.symmetric(vertical: 1.5),
          child: pw.Text(label, style: style),
        ),
        pw.Padding(
          padding: const pw.EdgeInsets.only(left: 16, top: 1.5, bottom: 1.5),
          child: pw.Text(
            _money(value),
            style: style,
            textAlign: pw.TextAlign.right,
          ),
        ),
      ],
    );
  }

  final c = m.currency;
  return pw.Column(
    crossAxisAlignment: pw.CrossAxisAlignment.end,
    children: [
      pw.Table(
        defaultColumnWidth: const pw.IntrinsicColumnWidth(),
        children: [
          if (t.taxed != null) row('Subtotal gravado', t.taxed),
          if (t.exempt != null) row('Subtotal exento', t.exempt),
          if (t.additionalTaxes != null)
            row('Impuestos adicionales', t.additionalTaxes),
          if (t.itbis != null) row('Total ITBIS', t.itbis),
          if (t.itbisWithheld != null) row('ITBIS retenido', t.itbisWithheld),
          if (t.isrWithheld != null) row('ISR retenido', t.isrWithheld),
          row('Total', t.total, strong: true),
        ],
      ),
      if (c != null)
        pw.Padding(
          padding: const pw.EdgeInsets.only(top: 4),
          child: pw.Text(
            [
              'Moneda: ${c.code}',
              if (c.rate != null) 'Tasa: ${c.rate}',
              if (c.total != null) 'Total ${c.code}: ${_money(c.total)}',
            ].join(' · '),
            style: const pw.TextStyle(fontSize: 8.5),
          ),
        ),
    ],
  );
}

pw.Widget _qr(EcfPrintModel m) {
  return pw.Column(
    crossAxisAlignment: pw.CrossAxisAlignment.start,
    mainAxisSize: pw.MainAxisSize.min,
    children: [
      pw.Padding(
        // Margen de 3 mm alrededor del QR.
        padding: const pw.EdgeInsets.all(3 * PdfPageFormat.mm),
        child: pw.BarcodeWidget(
          barcode: pw.Barcode.qrCode(),
          data: m.qrUrl,
          drawText: false,
          width: 26 * PdfPageFormat.mm,
          height: 26 * PdfPageFormat.mm,
        ),
      ),
      _line('Código de seguridad', m.securityCode, size: 9, strong: true),
      _line('Fecha de firma digital', m.signedAt, size: 9),
    ],
  );
}
