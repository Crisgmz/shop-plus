import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

import '../../../core/theme/tokens.dart';
import '../../../shared/formatters/formatters.dart';
import '../../../shared/responsive/responsive_layout.dart';
import '../../../shared/widgets/empty_state.dart';
import '../../../shared/widgets/module_page.dart';
import '../../../shared/widgets/print_receipt_dialog.dart';
import '../../cash_register/presentation/cash_register_providers.dart';
import '../../inventory/data/file_io_helper.dart';
import '../data/quotations_excel_service.dart';
import '../data/quotations_models.dart';
import 'convert_payment_dialog.dart';
import 'quotations_providers.dart';

class QuotationsPage extends ConsumerStatefulWidget {
  const QuotationsPage({super.key});

  @override
  ConsumerState<QuotationsPage> createState() => _QuotationsPageState();
}

class _QuotationsPageState extends ConsumerState<QuotationsPage> {
  @override
  Widget build(BuildContext context) {
    final foundationAsync = ref.watch(quotationsFoundationProvider);

    return foundationAsync.when(
      data: (foundation) => ModulePage(
        title: 'Cotizaciones',
        description: 'Gestión comercial de propuestas y cierre de ventas.',
        actions: [
          OutlinedButton.icon(
            onPressed: () => ref.invalidate(quotationsFoundationProvider),
            icon: const Icon(Icons.refresh_rounded, size: 18),
            label: const Text('Actualizar'),
          ),
          const SizedBox(width: AppTokens.s8),
          _buildExportMenu(foundation.recentQuotes),
          const SizedBox(width: AppTokens.s8),
          FilledButton.icon(
            onPressed: () => context.push('/cotizaciones/nueva'),
            icon: const Icon(Icons.note_add_outlined, size: 18),
            label: const Text('Nueva cotización'),
          ),
        ],
        child: Column(
          children: [
            _MetricsGrid(metrics: foundation.metrics),
            const SizedBox(height: AppTokens.s24),
            ResponsiveLayout(
              mobile: _PipelineCard(pipeline: foundation.pipeline),
              desktop: _PipelineCard(pipeline: foundation.pipeline),
            ),
            const SizedBox(height: AppTokens.s24),
            _RecentQuotesCard(quotes: foundation.recentQuotes),
          ],
        ),
      ),
      loading: () => const ModulePage(
        title: 'Cotizaciones',
        child: Center(child: CircularProgressIndicator()),
      ),
      error: (error, _) => ModulePage(
        title: 'Cotizaciones',
        child: ErrorCard(
          message: 'No se pudo cargar la base de cotizaciones: $error',
          onRetry: () => ref.invalidate(quotationsFoundationProvider),
        ),
      ),
    );
  }

  Widget _buildExportMenu(List<QuoteListItem> quotes) {
    return PopupMenuButton<String>(
      tooltip: 'Exportar reporte',
      position: PopupMenuPosition.under,
      onSelected: (value) {
        if (value == 'export_excel') {
          _onExportQuotesExcel(quotes);
        } else if (value == 'export_pdf') {
          _onExportQuotesPdf(quotes);
        }
      },
      itemBuilder: (_) => const [
        PopupMenuItem(
          value: 'export_excel',
          child: ListTile(
            dense: true,
            contentPadding: EdgeInsets.zero,
            leading: Icon(Icons.table_chart_outlined, size: 18),
            title: Text('Exportar a Excel'),
          ),
        ),
        PopupMenuItem(
          value: 'export_pdf',
          child: ListTile(
            dense: true,
            contentPadding: EdgeInsets.zero,
            leading: Icon(Icons.picture_as_pdf_outlined, size: 18),
            title: Text('Exportar a PDF'),
          ),
        ),
      ],
      child: OutlinedButton.icon(
        onPressed: null,
        icon: const Icon(Icons.ios_share_rounded, size: 18),
        label: const Text('Exportar'),
        style: OutlinedButton.styleFrom(
          foregroundColor: AppTokens.foreground,
          disabledForegroundColor: AppTokens.foreground,
        ),
      ),
    );
  }

  Future<void> _onExportQuotesExcel(List<QuoteListItem> quotes) async {
    if (quotes.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No hay cotizaciones para exportar.')),
      );
      return;
    }

    try {
      final bytes = QuotationsExcelService().buildExport(quotes: quotes);
      final saved = await FileIoHelper.saveBytes(
        bytes: bytes,
        fileName: 'cotizaciones_${_timestamp()}.xlsx',
        dialogTitle: 'Guardar Cotizaciones Excel',
        extension: 'xlsx',
      );
      if (!mounted) return;
      if (saved) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Cotizaciones exportadas a Excel (${quotes.length} cotizaciones)'),
          ),
        );
      }
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('No se pudo exportar a Excel: $error')),
      );
    }
  }

  Future<void> _onExportQuotesPdf(List<QuoteListItem> quotes) async {
    if (quotes.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No hay cotizaciones para exportar.')),
      );
      return;
    }

    try {
      final bytes = await _buildQuotesPdf(quotes);
      final saved = await FileIoHelper.saveBytes(
        bytes: bytes,
        fileName: 'cotizaciones_${_timestamp()}.pdf',
        dialogTitle: 'Guardar Reporte de Cotizaciones',
        extension: 'pdf',
      );
      if (!mounted) return;
      if (saved) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Reporte PDF exportado (${quotes.length} cotizaciones)'),
          ),
        );
      }
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('No se pudo exportar a PDF: $error')),
      );
    }
  }

  String _timestamp() {
    final now = DateTime.now();
    String two(int n) => n.toString().padLeft(2, '0');
    return '${now.year}${two(now.month)}${two(now.day)}_${two(now.hour)}${two(now.minute)}';
  }

  Future<Uint8List> _buildQuotesPdf(List<QuoteListItem> quotes) async {
    final pdf = pw.Document(
      theme: pw.ThemeData.withFont(
        base: await PdfGoogleFonts.robotoRegular(),
        bold: await PdfGoogleFonts.robotoBold(),
        italic: await PdfGoogleFonts.robotoItalic(),
      ),
    );

    final accent = PdfColor.fromInt(0xFF0D6EFD); // AppTokens.primary
    final muted = PdfColor.fromInt(0xFF66798E);  // AppTokens.mutedForeground
    final borderCol = PdfColor.fromInt(0xFFE9ECEF);

    final totalAmount = quotes.fold<double>(0, (sum, q) => sum + q.total);

    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.letter,
        margin: const pw.EdgeInsets.all(32),
        header: (context) => pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.stretch,
          children: [
            pw.Row(
              mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
              children: [
                pw.Text(
                  'REPORTE DE COTIZACIONES',
                  style: pw.TextStyle(
                    fontSize: 16,
                    fontWeight: pw.FontWeight.bold,
                    color: accent,
                  ),
                ),
                pw.Text(
                  _fmtDateTime(DateTime.now()),
                  style: pw.TextStyle(fontSize: 10, color: muted),
                ),
              ],
            ),
            pw.SizedBox(height: 4),
            pw.Text(
              'Busi Pos Web — Sistema de Gestión Comercial',
              style: pw.TextStyle(fontSize: 9, color: muted),
            ),
            pw.SizedBox(height: 12),
            pw.Divider(height: 1, color: borderCol),
            pw.SizedBox(height: 16),
          ],
        ),
        footer: (context) => pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.stretch,
          children: [
            pw.Divider(height: 1, color: borderCol),
            pw.SizedBox(height: 8),
            pw.Row(
              mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
              children: [
                pw.Text(
                  'Busi Pos Web — Reporte generado automáticamente',
                  style: pw.TextStyle(fontSize: 8, color: muted),
                ),
                pw.Text(
                  'Pág. ${context.pageNumber} de ${context.pagesCount}',
                  style: pw.TextStyle(fontSize: 8, color: muted),
                ),
              ],
            ),
          ],
        ),
        build: (context) => [
          // KPI summary
          pw.Container(
            padding: const pw.EdgeInsets.all(12),
            margin: const pw.EdgeInsets.only(bottom: 20),
            decoration: pw.BoxDecoration(
              color: PdfColor.fromInt(0xFFF8F9FA),
              borderRadius: const pw.BorderRadius.all(pw.Radius.circular(6)),
            ),
            child: pw.Row(
              mainAxisAlignment: pw.MainAxisAlignment.spaceAround,
              children: [
                _buildPdfKpi('Total Cotizaciones', quotes.length.toString(), accent),
                _buildPdfKpi('Monto Acumulado', money(totalAmount), accent),
              ],
            ),
          ),

          // Table
          pw.Table(
            border: pw.TableBorder(
              bottom: pw.BorderSide(color: borderCol, width: 0.5),
              horizontalInside: pw.BorderSide(color: borderCol, width: 0.5),
            ),
            columnWidths: const {
              0: pw.FlexColumnWidth(1.2), // Código
              1: pw.FlexColumnWidth(2.5), // Cliente
              2: pw.FlexColumnWidth(1.5), // Estado
              3: pw.FlexColumnWidth(1.5), // Emisión
              4: pw.FlexColumnWidth(1.5), // Vence
              5: pw.FlexColumnWidth(1.5), // Total
            },
            children: [
              // Header
              pw.TableRow(
                decoration: pw.BoxDecoration(
                  color: PdfColor.fromInt(0xFFF8F9FA),
                ),
                children: [
                  _pdfHeaderCell('Código'),
                  _pdfHeaderCell('Cliente'),
                  _pdfHeaderCell('Estado'),
                  _pdfHeaderCell('Emisión'),
                  _pdfHeaderCell('Vence'),
                  _pdfHeaderCell('Total', alignRight: true),
                ],
              ),
              // Rows
              ...quotes.map(
                (q) => pw.TableRow(
                  children: [
                    _pdfCell(q.code),
                    _pdfCell(q.clientName, bold: true),
                    _pdfCell(q.effectiveStatus.label),
                    _pdfCell(q.createdAt.toIso8601String().split('T').first),
                    _pdfCell(q.validUntil.toIso8601String().split('T').first),
                    _pdfCell(money(q.total), alignRight: true),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );

    return pdf.save();
  }

  pw.Widget _buildPdfKpi(String label, String value, PdfColor color) {
    return pw.Column(
      mainAxisSize: pw.MainAxisSize.min,
      children: [
        pw.Text(
          label.toUpperCase(),
          style: pw.TextStyle(
            fontSize: 8,
            fontWeight: pw.FontWeight.bold,
            color: PdfColor.fromInt(0xFF66798E),
          ),
        ),
        pw.SizedBox(height: 4),
        pw.Text(
          value,
          style: pw.TextStyle(
            fontSize: 14,
            fontWeight: pw.FontWeight.bold,
            color: color,
          ),
        ),
      ],
    );
  }

  pw.Widget _pdfHeaderCell(String text, {bool alignRight = false}) {
    return pw.Padding(
      padding: const pw.EdgeInsets.symmetric(horizontal: 6, vertical: 8),
      child: pw.Text(
        text,
        style: pw.TextStyle(fontSize: 8, fontWeight: pw.FontWeight.bold),
        textAlign: alignRight ? pw.TextAlign.right : pw.TextAlign.left,
      ),
    );
  }

  pw.Widget _pdfCell(String text, {bool bold = false, bool alignRight = false}) {
    return pw.Padding(
      padding: const pw.EdgeInsets.symmetric(horizontal: 6, vertical: 6),
      child: pw.Text(
        text,
        style: pw.TextStyle(fontSize: 8, fontWeight: bold ? pw.FontWeight.bold : pw.FontWeight.normal),
        textAlign: alignRight ? pw.TextAlign.right : pw.TextAlign.left,
      ),
    );
  }

  String _fmtDateTime(DateTime dt) {
    String two(int n) => n.toString().padLeft(2, '0');
    return '${dt.year}-${two(dt.month)}-${two(dt.day)} ${two(dt.hour)}:${two(dt.minute)}';
  }
}

class _RecentQuotesCard extends ConsumerWidget {
  const _RecentQuotesCard({required this.quotes});

  final List<QuoteListItem> quotes;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isMobile = ResponsiveLayout.isMobile(context);

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(AppTokens.s16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Cotizaciones recientes',
                  style: Theme.of(
                    context,
                  ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800),
                ),
                Text(
                  '${quotes.length} registradas',
                  style: const TextStyle(
                    color: AppTokens.textSecondary,
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
            const SizedBox(height: AppTokens.s14),
            if (quotes.isEmpty)
              const EmptyStateCard(
                icon: Icons.request_quote_outlined,
                message: 'Aún no hay cotizaciones preparadas.',
              )
            else if (isMobile)
              Column(
                children: [
                  for (final quote in quotes) ...[
                    _QuoteMobileCard(quote: quote),
                    if (quote != quotes.last)
                      const SizedBox(height: AppTokens.s10),
                  ],
                ],
              )
            else
              _QuotesDataTable(quotes: quotes),
          ],
        ),
      ),
    );
  }
}

/// Header de la tabla virtualizada de cotizaciones (fijo arriba del
/// ListView.builder, no se duplica por fila).
class _QuoteRowHeader extends StatelessWidget {
  const _QuoteRowHeader();

  @override
  Widget build(BuildContext context) {
    return Container(
      color: AppTokens.background,
      padding: const EdgeInsets.symmetric(
          horizontal: AppTokens.s16, vertical: AppTokens.s10),
      child: const Row(
        children: [
          Expanded(flex: 2, child: _QuoteColumnLabel('Código')),
          Expanded(flex: 3, child: _QuoteColumnLabel('Cliente')),
          Expanded(flex: 2, child: _QuoteColumnLabel('Estado')),
          Expanded(flex: 2, child: _QuoteColumnLabel('Vigencia')),
          Expanded(
              flex: 2,
              child: _QuoteColumnLabel('Monto', align: TextAlign.right)),
          SizedBox(width: 180, child: _QuoteColumnLabel('Acciones')),
        ],
      ),
    );
  }
}

class _QuoteColumnLabel extends StatelessWidget {
  const _QuoteColumnLabel(this.text, {this.align = TextAlign.left});

  final String text;
  final TextAlign align;

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      textAlign: align,
      style: const TextStyle(
        fontSize: 12,
        fontWeight: FontWeight.w700,
        color: AppTokens.mutedForeground,
        letterSpacing: 0.3,
      ),
    );
  }
}

/// Fila virtualizada de la tabla de cotizaciones. Con
/// `ListView.builder(itemExtent: 56)`.
class _QuoteRow extends StatelessWidget {
  const _QuoteRow({
    super.key,
    required this.quote,
    required this.onOpen,
    required this.onPrint,
    required this.onConvert,
    required this.onDelete,
  });

  final QuoteListItem quote;
  final VoidCallback onOpen;
  final VoidCallback onPrint;
  final VoidCallback onConvert;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onOpen,
      child: Container(
        decoration: const BoxDecoration(
          border: Border(top: BorderSide(color: AppTokens.border)),
        ),
        padding: const EdgeInsets.symmetric(horizontal: AppTokens.s16),
        child: Row(
          children: [
            Expanded(
              flex: 2,
              child: Text(
                quote.code,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
            Expanded(
              flex: 3,
              child: Text(
                quote.clientName,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 13),
              ),
            ),
            Expanded(
              flex: 2,
              child: _StatusChip(status: quote.effectiveStatus),
            ),
            Expanded(
              flex: 2,
              child: Text(
                formatDate(quote.validUntil),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 13),
              ),
            ),
            Expanded(
              flex: 2,
              child: Text(
                money(quote.total),
                textAlign: TextAlign.right,
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: AppTokens.brandBlueDark,
                ),
              ),
            ),
            SizedBox(
              width: 180,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  IconButton(
                    onPressed: onOpen,
                    icon: const Icon(Icons.visibility_outlined, size: 20),
                    tooltip: 'Ver / editar',
                    visualDensity: VisualDensity.compact,
                  ),
                  IconButton(
                    onPressed: onPrint,
                    icon: const Icon(Icons.print_outlined, size: 20),
                    tooltip: 'Imprimir cotización',
                    visualDensity: VisualDensity.compact,
                  ),
                  if (quote.canConvert)
                    IconButton(
                      onPressed: onConvert,
                      icon: const Icon(
                        Icons.shopping_cart_checkout_rounded,
                        color: AppTokens.success,
                        size: 20,
                      ),
                      tooltip: 'Convertir a venta',
                      visualDensity: VisualDensity.compact,
                    ),
                  if (quote.canDelete)
                    IconButton(
                      onPressed: onDelete,
                      icon: const Icon(
                        Icons.delete_outline_rounded,
                        color: AppTokens.error,
                        size: 20,
                      ),
                      tooltip: 'Eliminar',
                      visualDensity: VisualDensity.compact,
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _QuotesDataTable extends ConsumerWidget {
  const _QuotesDataTable({required this.quotes});
  final List<QuoteListItem> quotes;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Tabla virtualizada: solo renderiza las filas visibles, evita el
    // costo de materializar 500+ DataRow.
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        const _QuoteRowHeader(),
        SizedBox(
          height: (MediaQuery.of(context).size.height * 0.55)
              .clamp(360.0, double.infinity),
          child: ListView.builder(
            itemCount: quotes.length,
            itemExtent: 56,
            itemBuilder: (context, index) {
              final quote = quotes[index];
              return _QuoteRow(
                key: ValueKey(quote.id),
                quote: quote,
                onOpen: () => context.push('/cotizaciones/${quote.id}'),
                onPrint: () => _printQuote(context, ref, quote),
                onConvert: () => _convertToSale(context, ref, quote),
                onDelete: () => _deleteQuote(context, ref, quote),
              );
            },
          ),
        ),
      ],
    );
  }

  Future<void> _convertToSale(
    BuildContext context,
    WidgetRef ref,
    QuoteListItem quote,
  ) async {
    final method = await showConvertPaymentDialog(
      context,
      quoteCode: quote.code,
    );

    if (method == null) return;

    {
      try {
        final result = await ref
            .read(quotationsRepositoryProvider)
            .convertToSale(
              quote.id,
              paymentMethod: method,
              cashSessionId: ref.read(activeCashSessionIdProvider),
            );
        ref.invalidate(quotationsFoundationProvider);
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                'Cotización convertida a venta ${result.saleNumber}.',
              ),
            ),
          );
        }
      } catch (e) {
        if (context.mounted) {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(SnackBar(content: Text('Error: $e')));
        }
      }
    }
  }

  Future<void> _printQuote(
    BuildContext context,
    WidgetRef ref,
    QuoteListItem quote,
  ) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      final printJob = await ref
          .read(quotationsRepositoryProvider)
          .prepareQuotePrintJob(quoteId: quote.id);
      if (printJob == null) {
        messenger.showSnackBar(
          const SnackBar(content: Text('No se pudo preparar la impresión.')),
        );
        return;
      }
      if (context.mounted) {
        await PrintReceiptDialog.show(context, printJob);
      }
    } catch (e) {
      if (context.mounted) {
        messenger.showSnackBar(SnackBar(content: Text('Error: $e')));
      }
    }
  }

  Future<void> _deleteQuote(
    BuildContext context,
    WidgetRef ref,
    QuoteListItem quote,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Eliminar cotización'),
        content: Text(
          '¿Estás seguro de que deseas eliminar la cotización ${quote.code}?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(backgroundColor: AppTokens.error),
            child: const Text('Eliminar'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      try {
        await ref.read(quotationsRepositoryProvider).deleteQuote(quote.id);
        ref.invalidate(quotationsFoundationProvider);
      } catch (e) {
        if (context.mounted) {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(SnackBar(content: Text('Error: $e')));
        }
      }
    }
  }
}

class _QuoteMobileCard extends ConsumerWidget {
  const _QuoteMobileCard({required this.quote});

  final QuoteListItem quote;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return InkWell(
      onTap: () => context.push('/cotizaciones/${quote.id}'),
      borderRadius: BorderRadius.circular(AppTokens.radiusL),
      child: Container(
        padding: const EdgeInsets.all(AppTokens.s14),
        decoration: BoxDecoration(
          color: const Color(0xFFF9FBFF),
          borderRadius: BorderRadius.circular(AppTokens.radiusL),
          border: Border.all(color: AppTokens.cardBorder),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    quote.code,
                    style: Theme.of(context)
                        .textTheme
                        .titleSmall
                        ?.copyWith(fontWeight: FontWeight.w800),
                  ),
                ),
                _StatusChip(status: quote.effectiveStatus),
              ],
            ),
            const SizedBox(height: AppTokens.s6),
            Text(
              quote.clientName,
              style: Theme.of(context)
                  .textTheme
                  .bodyLarge
                  ?.copyWith(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: AppTokens.s10),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Vence ${formatDate(quote.validUntil)}',
                  style: const TextStyle(
                    fontSize: 12,
                    color: AppTokens.textSecondary,
                  ),
                ),
                Text(
                  money(quote.total),
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w800,
                        color: AppTokens.brandBlueDark,
                      ),
                ),
              ],
            ),
            const SizedBox(height: AppTokens.s8),
            Row(
              children: [
                OutlinedButton.icon(
                  onPressed: () => _printQuote(context, ref),
                  icon: const Icon(Icons.print_outlined, size: 16),
                  label: const Text('Imprimir'),
                  style: OutlinedButton.styleFrom(
                    minimumSize: const Size(0, 32),
                    padding: const EdgeInsets.symmetric(horizontal: 10),
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    textStyle: const TextStyle(fontSize: 12),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _printQuote(BuildContext context, WidgetRef ref) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      final printJob = await ref
          .read(quotationsRepositoryProvider)
          .prepareQuotePrintJob(quoteId: quote.id);
      if (printJob == null) {
        messenger.showSnackBar(
          const SnackBar(content: Text('No se pudo preparar la impresión.')),
        );
        return;
      }
      if (context.mounted) {
        await PrintReceiptDialog.show(context, printJob);
      }
    } catch (e) {
      if (context.mounted) {
        messenger.showSnackBar(SnackBar(content: Text('Error: $e')));
      }
    }
  }
}

class _StatusChip extends StatelessWidget {
  const _StatusChip({required this.status});

  final QuoteStatus status;

  @override
  Widget build(BuildContext context) {
    final palette = switch (status) {
      QuoteStatus.draft => (const Color(0xFFEAF2FF), AppTokens.brandBlueDark),
      QuoteStatus.sent => (const Color(0xFFEAF8FF), AppTokens.info),
      QuoteStatus.underReview => (const Color(0xFFFFF6E5), AppTokens.warning),
      QuoteStatus.approved => (const Color(0xFFE8F8EE), AppTokens.success),
      QuoteStatus.rejected => (const Color(0xFFFDEBED), AppTokens.error),
      QuoteStatus.expired => (const Color(0xFFF1F3F7), AppTokens.textMuted),
      QuoteStatus.converted => (const Color(0xFFE8F8EE), AppTokens.success),
    };

    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppTokens.s10,
        vertical: AppTokens.s6,
      ),
      decoration: BoxDecoration(
        color: palette.$1,
        borderRadius: BorderRadius.circular(AppTokens.radiusRound),
      ),
      child: Text(
        status.label,
        style: TextStyle(
          color: palette.$2,
          fontWeight: FontWeight.w700,
          fontSize: 12,
        ),
      ),
    );
  }
}

class _MetricsGrid extends StatelessWidget {
  const _MetricsGrid({required this.metrics});

  final List<QuoteMetric> metrics;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final columns = kpiCrossAxisCount(constraints.maxWidth);
        return GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: metrics.length,
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: columns,
            mainAxisSpacing: AppTokens.s12,
            crossAxisSpacing: AppTokens.s12,
            childAspectRatio:
                constraints.maxWidth >= AppTokens.breakpointExpanded
                ? 1.9
                : 2.1,
          ),
          itemBuilder: (_, index) => _MetricCard(metric: metrics[index]),
        );
      },
    );
  }
}

class _MetricCard extends StatelessWidget {
  const _MetricCard({required this.metric});

  final QuoteMetric metric;

  @override
  Widget build(BuildContext context) {
    final background = metric.highlight
        ? const Color(0xFFEAF2FF)
        : Colors.white;

    return Card(
      color: background,
      child: Padding(
        padding: const EdgeInsets.all(AppTokens.s16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              metric.label,
              style: Theme.of(context).textTheme.labelLarge?.copyWith(
                color: AppTokens.textSecondary,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: AppTokens.s8),
            Text(
              metric.value,
              style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                fontWeight: FontWeight.w800,
                color: metric.highlight
                    ? AppTokens.brandBlueDark
                    : AppTokens.textPrimary,
              ),
            ),
            const SizedBox(height: AppTokens.s6),
            Text(
              metric.helpText,
              style: Theme.of(
                context,
              ).textTheme.bodySmall?.copyWith(color: AppTokens.textSecondary),
            ),
          ],
        ),
      ),
    );
  }
}

class _PipelineCard extends StatelessWidget {
  const _PipelineCard({required this.pipeline});

  final List<QuotePipelineStage> pipeline;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(AppTokens.s16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Pipeline comercial',
              style: Theme.of(
                context,
              ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: AppTokens.s14),
            Row(
              children: [
                for (final stage in pipeline) ...[
                  Expanded(child: _PipelineStageWidget(stage: stage)),
                  if (stage != pipeline.last)
                    const Icon(
                      Icons.chevron_right,
                      color: AppTokens.cardBorder,
                    ),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _PipelineStageWidget extends StatelessWidget {
  const _PipelineStageWidget({required this.stage});
  final QuotePipelineStage stage;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Text(
          stage.count.toString(),
          style: const TextStyle(
            fontWeight: FontWeight.w900,
            fontSize: 20,
            color: AppTokens.brandBlue,
          ),
        ),
        Text(
          stage.label,
          style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13),
        ),
        Text(
          money(stage.amount),
          style: const TextStyle(color: AppTokens.textSecondary, fontSize: 11),
        ),
      ],
    );
  }
}
