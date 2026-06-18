// PDF renderer para reportes (PRD 07 sub-fase 7.D).
//
// Diseño:
//   - Tamaño Letter (8.5 × 11) con MultiPage para paginación automática.
//   - Header en cada página: logo (si existe en app_settings), nombre de
//     compañía, RNC, sucursal, título del reporte, rango de fechas.
//   - Footer en cada página: timestamp de generación + "Página N de M".
//   - Una sola fuente embebida (Roboto vía PdfGoogleFonts) — no dependemos
//     de fuentes del sistema.
//
// El renderer es PURO: recibe `ReportExportData` y devuelve `Uint8List`.
// No toca filesystem ni share — eso vive en `report_export_controller.dart`.

import 'dart:typed_data';

import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

import 'report_export_models.dart';

class ReportPdfRenderer {
  Future<Uint8List> render(ReportExportData data) async {
    final pdf = pw.Document(
      title: data.title,
      author: data.companyName ?? 'Shop+',
      subject: data.subtitle ?? data.title,
    );

    final theme = pw.ThemeData.withFont(
      base: await PdfGoogleFonts.robotoRegular(),
      bold: await PdfGoogleFonts.robotoBold(),
      italic: await PdfGoogleFonts.robotoItalic(),
    );

    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.letter,
        theme: theme,
        margin: const pw.EdgeInsets.symmetric(
          horizontal: 36,
          vertical: 28,
        ),
        header: (ctx) => _buildHeader(ctx, data),
        footer: (ctx) => _buildFooter(ctx),
        build: (ctx) => _buildBody(data),
      ),
    );

    return pdf.save();
  }

  pw.Widget _buildHeader(pw.Context ctx, ReportExportData data) {
    final accent = PdfColor.fromInt(0xFF0D6EFD); // AppTokens.primary
    final muted = PdfColor.fromInt(0xFF66798E);  // AppTokens.mutedForeground

    return pw.Container(
      margin: const pw.EdgeInsets.only(bottom: 12),
      padding: const pw.EdgeInsets.only(bottom: 8),
      decoration: pw.BoxDecoration(
        border: pw.Border(
          bottom: pw.BorderSide(color: accent, width: 1.5),
        ),
      ),
      child: pw.Row(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Expanded(
            child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                if ((data.companyName ?? '').isNotEmpty)
                  pw.Text(
                    data.companyName!,
                    style: pw.TextStyle(
                      fontSize: 14,
                      fontWeight: pw.FontWeight.bold,
                    ),
                  ),
                if ((data.companyTaxId ?? '').isNotEmpty)
                  pw.Text(
                    'RNC ${data.companyTaxId}',
                    style: pw.TextStyle(fontSize: 9, color: muted),
                  ),
                if ((data.branchName ?? '').isNotEmpty)
                  pw.Text(
                    data.branchName!,
                    style: pw.TextStyle(fontSize: 9, color: muted),
                  ),
              ],
            ),
          ),
          pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.end,
            children: [
              pw.Text(
                data.title,
                style: pw.TextStyle(
                  fontSize: 16,
                  fontWeight: pw.FontWeight.bold,
                  color: accent,
                ),
              ),
              if ((data.subtitle ?? '').isNotEmpty)
                pw.Text(
                  data.subtitle!,
                  style: pw.TextStyle(fontSize: 9, color: muted),
                ),
              if (data.dateFrom != null && data.dateTo != null)
                pw.Text(
                  '${_fmtDate(data.dateFrom!)} → ${_fmtDate(data.dateTo!)}',
                  style: pw.TextStyle(fontSize: 9, color: muted),
                ),
            ],
          ),
        ],
      ),
    );
  }

  pw.Widget _buildFooter(pw.Context ctx) {
    final muted = PdfColor.fromInt(0xFF66798E);
    final now = DateTime.now();
    return pw.Container(
      margin: const pw.EdgeInsets.only(top: 12),
      padding: const pw.EdgeInsets.only(top: 6),
      decoration: pw.BoxDecoration(
        border: pw.Border(
          top: pw.BorderSide(color: muted, width: 0.5),
        ),
      ),
      child: pw.Row(
        children: [
          pw.Text(
            'Generado ${_fmtDateTime(now)} · Shop+',
            style: pw.TextStyle(fontSize: 8, color: muted),
          ),
          pw.Spacer(),
          pw.Text(
            'Página ${ctx.pageNumber} de ${ctx.pagesCount}',
            style: pw.TextStyle(fontSize: 8, color: muted),
          ),
        ],
      ),
    );
  }

  List<pw.Widget> _buildBody(ReportExportData data) {
    final widgets = <pw.Widget>[];
    for (var i = 0; i < data.sections.length; i++) {
      final section = data.sections[i];
      // Aplanamos cada sección al nivel del MultiPage. Si envolviéramos
      // todos los hijos en un Column, pdf no podría partir una tabla larga
      // entre páginas y lanzaría `TooManyPagesException`.
      widgets.addAll(_buildSectionWidgets(section));
      if (i < data.sections.length - 1) {
        widgets.add(pw.SizedBox(height: 12));
      }
    }
    if (widgets.isEmpty) {
      widgets.add(
        pw.Padding(
          padding: const pw.EdgeInsets.symmetric(vertical: 24),
          child: pw.Center(
            child: pw.Text(
              'Sin datos para el rango seleccionado.',
              style: pw.TextStyle(
                fontSize: 11,
                color: PdfColor.fromInt(0xFF66798E),
              ),
            ),
          ),
        ),
      );
    }
    return widgets;
  }

  /// Devuelve los hijos de una sección como widgets independientes (no
  /// envueltos en un Column) para que `pw.MultiPage` pueda paginar la tabla
  /// si excede una página.
  List<pw.Widget> _buildSectionWidgets(ReportSection section) {
    final children = <pw.Widget>[];
    if ((section.title ?? '').isNotEmpty) {
      children.add(
        pw.Container(
          width: double.infinity,
          padding: const pw.EdgeInsets.symmetric(
              horizontal: 8, vertical: 4),
          decoration: pw.BoxDecoration(
            color: PdfColor.fromInt(0xFFF1F3F5),
            borderRadius: pw.BorderRadius.circular(3),
          ),
          margin: const pw.EdgeInsets.only(bottom: 6),
          child: pw.Text(
            section.title!,
            style: pw.TextStyle(
              fontSize: 11,
              fontWeight: pw.FontWeight.bold,
            ),
          ),
        ),
      );
    }

    if (section.table != null) {
      children.add(_buildTable(section.table!));
    }
    if (section.kv != null && section.kv!.isNotEmpty) {
      children.add(_buildKv(section.kv!));
    }
    if (section.totals != null && section.totals!.isNotEmpty) {
      children.add(pw.SizedBox(height: 4));
      children.add(_buildTotals(section.totals!));
    }
    if ((section.note ?? '').isNotEmpty) {
      children.add(pw.SizedBox(height: 4));
      children.add(
        pw.Text(
          section.note!,
          style: pw.TextStyle(
            fontSize: 8,
            fontStyle: pw.FontStyle.italic,
            color: PdfColor.fromInt(0xFF66798E),
          ),
        ),
      );
    }
    return children;
  }

  pw.Widget _buildTable(ReportTable table) {
    if (table.rows.isEmpty) {
      return pw.Padding(
        padding: const pw.EdgeInsets.symmetric(vertical: 8),
        child: pw.Text(
          'Sin datos.',
          style: pw.TextStyle(
            fontSize: 9,
            color: PdfColor.fromInt(0xFF66798E),
          ),
        ),
      );
    }

    final headerStyle = pw.TextStyle(
      fontSize: 9,
      fontWeight: pw.FontWeight.bold,
      color: PdfColors.white,
    );
    final cellStyle = pw.TextStyle(fontSize: 9);
    final accent = PdfColor.fromInt(0xFF0D6EFD);

    return pw.Table(
      border: pw.TableBorder.all(
        color: PdfColor.fromInt(0xFFE9ECEF),
        width: 0.5,
      ),
      children: [
        pw.TableRow(
          decoration: pw.BoxDecoration(color: accent),
          children: [
            for (var i = 0; i < table.columns.length; i++)
              pw.Padding(
                padding: const pw.EdgeInsets.symmetric(
                  horizontal: 4,
                  vertical: 5,
                ),
                child: pw.Text(
                  table.columns[i],
                  style: headerStyle,
                  textAlign: table.numericColumns.contains(i)
                      ? pw.TextAlign.right
                      : pw.TextAlign.left,
                ),
              ),
          ],
        ),
        for (var ri = 0; ri < table.rows.length; ri++)
          pw.TableRow(
            decoration: ri.isEven
                ? const pw.BoxDecoration(color: PdfColors.white)
                : pw.BoxDecoration(color: PdfColor.fromInt(0xFFF8F9FA)),
            children: [
              for (var ci = 0; ci < table.rows[ri].length; ci++)
                pw.Padding(
                  padding: const pw.EdgeInsets.symmetric(
                    horizontal: 4,
                    vertical: 4,
                  ),
                  child: pw.Text(
                    table.rows[ri][ci],
                    style: cellStyle,
                    textAlign: table.numericColumns.contains(ci)
                        ? pw.TextAlign.right
                        : pw.TextAlign.left,
                  ),
                ),
            ],
          ),
      ],
    );
  }

  pw.Widget _buildKv(List<ReportKv> kv) {
    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        for (final entry in kv)
          pw.Padding(
            padding: const pw.EdgeInsets.symmetric(vertical: 2),
            child: pw.Row(
              children: [
                pw.Expanded(
                  child: pw.Text(
                    entry.label,
                    style: pw.TextStyle(
                      fontSize: 10,
                      color: PdfColor.fromInt(0xFF66798E),
                    ),
                  ),
                ),
                pw.Text(
                  entry.value,
                  style: pw.TextStyle(
                    fontSize: 10,
                    fontWeight: entry.highlight
                        ? pw.FontWeight.bold
                        : pw.FontWeight.normal,
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }

  pw.Widget _buildTotals(List<ReportKv> totals) {
    return pw.Container(
      padding: const pw.EdgeInsets.symmetric(
        horizontal: 6,
        vertical: 4,
      ),
      decoration: pw.BoxDecoration(
        color: PdfColor.fromInt(0xFFE9ECEF),
        borderRadius: pw.BorderRadius.circular(3),
      ),
      child: pw.Wrap(
        spacing: 16,
        runSpacing: 4,
        children: [
          for (final entry in totals)
            pw.Row(
              mainAxisSize: pw.MainAxisSize.min,
              children: [
                pw.Text(
                  '${entry.label}: ',
                  style: pw.TextStyle(
                    fontSize: 9,
                    color: PdfColor.fromInt(0xFF66798E),
                  ),
                ),
                pw.Text(
                  entry.value,
                  style: pw.TextStyle(
                    fontSize: 9,
                    fontWeight: pw.FontWeight.bold,
                  ),
                ),
              ],
            ),
        ],
      ),
    );
  }

  String _fmtDate(DateTime d) {
    return '${d.day.toString().padLeft(2, '0')}/'
        '${d.month.toString().padLeft(2, '0')}/'
        '${d.year}';
  }

  String _fmtDateTime(DateTime d) {
    final local = d.isUtc ? d.toLocal() : d;
    return '${_fmtDate(local)} '
        '${local.hour.toString().padLeft(2, '0')}:'
        '${local.minute.toString().padLeft(2, '0')}';
  }
}
