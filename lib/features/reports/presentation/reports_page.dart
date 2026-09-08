// PRD 07 — Módulo de Reportes Unificado (round 1).
//
// Layout:
//   - Sidebar de 24 categorías agrupadas (PRD §4) — desktop 280px,
//     drawer/dropdown en mobile.
//   - Panel derecho: filter bar sticky + breadcrumb + contenido.
//   - Sin categoría seleccionada → tarjeta de bienvenida con highlights.
//   - Categoría seleccionada sin modo → dual cards (Gráfico / Resumen).
//   - Categoría + modo → contenido del reporte.
//
// Round 1 implementa 6 reportes operativos:
//   Ventas, Caja, Liquidación, Cobros, Pagos, Ventas suspendidas.
// El resto son placeholders "Próximamente".

import 'dart:math' as math;

import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/tokens.dart';
import '../../../shared/formatters/formatters.dart';
import '../../../shared/widgets/empty_state.dart';
import '../../../shared/widgets/module_page.dart';
import '../../inventory/data/file_io_helper.dart';
import '../../settings/presentation/app_settings_providers.dart';
import '../../shell/presentation/shell_providers.dart';
import '../data/reports_repository.dart'
    show FiscalZClosureRow, SaleDetailRow;
import '../export/estado_diario_csv.dart';
import '../domain/report_category.dart';
import '../export/report_export_models.dart';
import '../export/report_export_service.dart';
import 'reports_providers.dart';

class ReportsPage extends ConsumerWidget {
  const ReportsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final selected = ref.watch(reportCategoryProvider);
    final mode = ref.watch(reportModeProvider);
    final ventasSub = ref.watch(ventasSubReportProvider);

    final atLeaf = mode != null || ventasSub != null;
    final atHub = !atLeaf && selected != null;
    final canGoBack = selected != null;

    // Si el usuario clickeó "PDF" o "Excel" en una tarjeta Gráfico/Resumen,
    // se setea `pendingExportFormatProvider` antes de navegar. Cuando el
    // Nivel 2 publica su snapshot, este listener dispara la descarga
    // automáticamente y limpia el estado pendiente.
    ref.listen<ReportExportSnapshot?>(
      currentReportExportProvider,
      (previous, next) {
        if (next == null) return;
        final pending = ref.read(pendingExportFormatProvider);
        if (pending == null) return;
        // Limpiamos primero para evitar disparar dos veces si el snapshot
        // se republica.
        ref.read(pendingExportFormatProvider.notifier).state = null;
        final format = pending == 'pdf'
            ? ReportExportFormat.pdf
            : ReportExportFormat.xlsx;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!context.mounted) return;
          _exportCurrentSnapshot(context, ref, format);
        });
      },
    );

    final (title, description) = _resolveHeader(selected, mode, ventasSub);

    return ModulePage(
      title: title,
      description: description,
      actions: [
        if (canGoBack)
          OutlinedButton.icon(
            onPressed: () => _goBack(ref, mode, ventasSub),
            icon: const Icon(Icons.arrow_back, size: 18),
            label: const Text('Atrás'),
          ),
        if (atLeaf) const _ExportMenuButton(),
        OutlinedButton.icon(
          onPressed: () => _invalidateAll(ref),
          icon: const Icon(Icons.refresh, size: 18),
          label: const Text('Actualizar'),
        ),
      ],
      child: _resolveBody(
        selected: selected,
        mode: mode,
        ventasSub: ventasSub,
        atHub: atHub,
        atLeaf: atLeaf,
      ),
    );
  }

  Widget _resolveBody({
    required ReportCategory? selected,
    required ReportMode? mode,
    required VentasSubReport? ventasSub,
    required bool atHub,
    required bool atLeaf,
  }) {
    if (selected == null) {
      // Nivel 0: lista completa de las 24 categorías.
      return const _AllCategoriesList();
    }
    if (!selected.isImplemented) {
      return _ComingSoon(category: selected);
    }
    final isVentas = selected == ReportCategory.ventas;
    if (atHub) {
      // Nivel 1: hub de la categoría. Para Ventas, sub-menú; para los demás,
      // las dual cards Gráfico/Resumen.
      if (isVentas) {
        return const _VentasSubReportMenu();
      }
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const _FilterBar(),
          const SizedBox(height: AppTokens.s16),
          _DualCards(category: selected),
        ],
      );
    }
    // Nivel 2: contenido del reporte.
    final content = ventasSub != null
        ? _VentasSubReportContent(sub: ventasSub)
        : _CategoryContent(category: selected, mode: mode!);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const _FilterBar(),
        const SizedBox(height: AppTokens.s16),
        content,
      ],
    );
  }

  (String, String) _resolveHeader(
    ReportCategory? selected,
    ReportMode? mode,
    VentasSubReport? ventasSub,
  ) {
    if (selected == null) {
      return (
        'Reportes',
        'Inteligencia operativa, financiera y fiscal del negocio.'
      );
    }
    if (ventasSub != null) {
      return (ventasSub.title, 'Ventas › ${ventasSub.title}');
    }
    if (mode != null) {
      final modeLabel = mode == ReportMode.graphic
          ? 'Reporte gráfico'
          : 'Reporte de resumen';
      return ('${selected.title} — $modeLabel', selected.description);
    }
    if (selected == ReportCategory.ventas) {
      return (selected.title, 'Elige el sub-reporte que necesitas.');
    }
    return (selected.title, selected.description);
  }

  void _goBack(
    WidgetRef ref,
    ReportMode? mode,
    VentasSubReport? ventasSub,
  ) {
    // Limpiar snapshot exportable al cambiar de leaf
    ref.read(currentReportExportProvider.notifier).state = null;
    // Nivel 2 → Nivel 1 (limpiar leaf, mantener categoría)
    if (mode != null || ventasSub != null) {
      ref.read(reportModeProvider.notifier).state = null;
      ref.read(ventasSubReportProvider.notifier).state = null;
      return;
    }
    // Nivel 1 → Nivel 0 (limpiar categoría)
    ref.read(reportCategoryProvider.notifier).state = null;
  }

  void _invalidateAll(WidgetRef ref) {
    ref.invalidate(salesDailyReportProvider);
    ref.invalidate(cashSessionsReportProvider);
    ref.invalidate(paymentsReportProvider);
    ref.invalidate(outgoingPaymentsReportProvider);
    ref.invalidate(suspendedSalesReportProvider);
    ref.invalidate(operationalCloseoutReportProvider);
    ref.invalidate(detailedSalesReportProvider);
    ref.invalidate(voidedSalesReportProvider);
    ref.invalidate(hourlySalesReportProvider);
  }
}

/// Nivel 0 — lista completa de las 24 categorías a pantalla completa,
/// agrupadas por encabezado. Es esencialmente el sidebar pero como contenido
/// principal.
class _AllCategoriesList extends ConsumerWidget {
  const _AllCategoriesList();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final groups = <ReportCategoryGroup, List<ReportCategory>>{};
    for (final cat in ReportCategory.values) {
      groups.putIfAbsent(cat.group, () => []).add(cat);
    }

    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: AppTokens.s12,
          vertical: AppTokens.s12,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final group in ReportCategoryGroup.values) ...[
              Padding(
                padding: const EdgeInsets.fromLTRB(
                    AppTokens.s12, AppTokens.s16, AppTokens.s12, AppTokens.s6),
                child: Text(
                  group.label.toUpperCase(),
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                        color: AppTokens.mutedForeground,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 1.2,
                      ),
                ),
              ),
              for (final cat in groups[group] ?? const <ReportCategory>[])
                _CategoryListTile(category: cat),
            ],
          ],
        ),
      ),
    );
  }
}

class _CategoryListTile extends ConsumerWidget {
  const _CategoryListTile({required this.category});

  final ReportCategory category;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final accent = category.group.accent;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () {
          ref.read(reportCategoryProvider.notifier).state = category;
          ref.read(reportModeProvider.notifier).state = null;
          ref.read(ventasSubReportProvider.notifier).state = null;
        },
        borderRadius: BorderRadius.circular(6),
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: AppTokens.s16,
            vertical: AppTokens.s14,
          ),
          child: Row(
            children: [
              Icon(category.icon, color: accent, size: 20),
              const SizedBox(width: AppTokens.s16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      category.title,
                      style: TextStyle(
                        color: category.isImplemented
                            ? AppTokens.foreground
                            : AppTokens.mutedForeground,
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      category.description,
                      style: const TextStyle(
                        color: AppTokens.mutedForeground,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: AppTokens.s12),
              if (!category.isImplemented)
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(
                    color: AppTokens.muted,
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    'Próx.',
                    style: TextStyle(
                      color: AppTokens.mutedForeground,
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                )
              else
                Icon(Icons.chevron_right,
                    size: 18, color: AppTokens.mutedForeground),
            ],
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────
// Filter bar
// ─────────────────────────────────────────────────────────────────────────

class _FilterBar extends ConsumerWidget {
  const _FilterBar();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final range = ref.watch(reportDateRangeProvider);
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(AppTokens.s12),
        child: Wrap(
          crossAxisAlignment: WrapCrossAlignment.center,
          spacing: AppTokens.s8,
          runSpacing: AppTokens.s8,
          children: [
            for (final preset in ReportDateRangePreset.values)
              if (preset != ReportDateRangePreset.customRange)
                ChoiceChip(
                  label: Text(preset.label),
                  selected: range.preset == preset,
                  onSelected: (_) {
                    ref.read(reportDateRangeProvider.notifier).state =
                        ReportDateRange.fromPreset(preset);
                  },
                ),
            OutlinedButton.icon(
              onPressed: () => _pickCustomRange(context, ref, range),
              icon: const Icon(Icons.calendar_today_outlined, size: 16),
              label: Text(
                range.preset == ReportDateRangePreset.customRange
                    ? '${formatDate(range.from)} → ${formatDate(range.to)}'
                    : 'Personalizado',
                style: const TextStyle(fontSize: 12),
              ),
            ),
            const SizedBox(width: AppTokens.s8),
            Text(
              'Rango actual: ${formatDate(range.from)} → ${formatDate(range.to)}',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: AppTokens.mutedForeground,
                  ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _pickCustomRange(
    BuildContext context,
    WidgetRef ref,
    ReportDateRange current,
  ) async {
    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2020),
      lastDate: DateTime.now().add(const Duration(days: 1)),
      initialDateRange: DateTimeRange(start: current.from, end: current.to),
    );
    if (picked == null) return;
    ref.read(reportDateRangeProvider.notifier).state =
        ReportDateRange.fromPreset(
      ReportDateRangePreset.customRange,
      customFrom: picked.start,
      customTo: picked.end,
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────
// Dual cards (cuando la categoría no tiene modo seleccionado)
// ─────────────────────────────────────────────────────────────────────────

class _DualCards extends ConsumerWidget {
  const _DualCards({required this.category});

  final ReportCategory category;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final supportsGraphic = category.supportsGraphicMode;
    return LayoutBuilder(builder: (context, constraints) {
      final isWide = constraints.maxWidth >= 720;
      final cardWidth = isWide
          ? (constraints.maxWidth - AppTokens.s16) / 2
          : constraints.maxWidth;

      void openMode(ReportMode mode, {String? autoExport}) {
        // Si se pidió auto-exportar, guardamos el formato pendiente ANTES de
        // cambiar el modo. El listener montado en ReportsPage detectará el
        // próximo snapshot y disparará la descarga.
        if (autoExport != null) {
          ref.read(pendingExportFormatProvider.notifier).state = autoExport;
        }
        ref.read(reportModeProvider.notifier).state = mode;
      }

      return Wrap(
        spacing: AppTokens.s16,
        runSpacing: AppTokens.s16,
        children: [
          if (supportsGraphic)
            SizedBox(
              width: cardWidth,
              child: _ModeCard(
                title: 'Reporte gráfico',
                description:
                    'Visualización temporal: tendencias y comparativas.',
                icon: Icons.bar_chart_rounded,
                accent: category.group.accent,
                onTap: () => openMode(ReportMode.graphic),
                onExportPdf: () =>
                    openMode(ReportMode.graphic, autoExport: 'pdf'),
                onExportXlsx: () =>
                    openMode(ReportMode.graphic, autoExport: 'xlsx'),
              ),
            ),
          SizedBox(
            width: cardWidth,
            child: _ModeCard(
              title: 'Reporte de resumen',
              description:
                  'Tabla densa con totales, subtotales y desglose.',
              icon: Icons.table_chart_outlined,
              accent: category.group.accent,
              onTap: () => openMode(ReportMode.summary),
              onExportPdf: () =>
                  openMode(ReportMode.summary, autoExport: 'pdf'),
              onExportXlsx: () =>
                  openMode(ReportMode.summary, autoExport: 'xlsx'),
            ),
          ),
        ],
      );
    });
  }
}

class _ModeCard extends StatelessWidget {
  const _ModeCard({
    required this.title,
    required this.description,
    required this.icon,
    required this.accent,
    required this.onTap,
    required this.onExportPdf,
    required this.onExportXlsx,
  });

  final String title;
  final String description;
  final IconData icon;
  final Color accent;
  final VoidCallback onTap;
  final VoidCallback onExportPdf;
  final VoidCallback onExportXlsx;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: EdgeInsets.zero,
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(AppTokens.s24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                padding: const EdgeInsets.all(AppTokens.s10),
                decoration: BoxDecoration(
                  color: accent.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(icon, color: accent, size: 24),
              ),
              const SizedBox(height: AppTokens.s16),
              Text(
                title,
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
              ),
              const SizedBox(height: AppTokens.s4),
              Text(
                description,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: AppTokens.mutedForeground,
                    ),
              ),
              const SizedBox(height: AppTokens.s12),
              Row(
                children: [
                  Text(
                    'Abrir',
                    style: TextStyle(
                      color: accent,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(width: 4),
                  Icon(Icons.arrow_forward, size: 16, color: accent),
                ],
              ),
              const SizedBox(height: AppTokens.s12),
              Wrap(
                spacing: AppTokens.s8,
                children: [
                  OutlinedButton.icon(
                    onPressed: onExportPdf,
                    icon: const Icon(
                      Icons.picture_as_pdf_outlined,
                      size: 16,
                    ),
                    label: const Text('PDF'),
                    style: OutlinedButton.styleFrom(
                      minimumSize: const Size(0, 34),
                      padding:
                          const EdgeInsets.symmetric(horizontal: 12),
                    ),
                  ),
                  OutlinedButton.icon(
                    onPressed: onExportXlsx,
                    icon: const Icon(
                      Icons.table_chart_outlined,
                      size: 16,
                    ),
                    label: const Text('Excel'),
                    style: OutlinedButton.styleFrom(
                      minimumSize: const Size(0, 34),
                      padding:
                          const EdgeInsets.symmetric(horizontal: 12),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────
// Coming soon (categorías no implementadas)
// ─────────────────────────────────────────────────────────────────────────

class _ComingSoon extends StatelessWidget {
  const _ComingSoon({required this.category});

  final ReportCategory category;

  @override
  Widget build(BuildContext context) {
    return EmptyStateCard(
      icon: category.icon,
      message:
          '"${category.title}" está mapeado pero llega en próximos rounds del '
          'PRD 07. El backend ya soporta esta categoría — sólo falta cablear '
          'la UI.',
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────
// Despachador por categoría (sólo las 6 implementadas)
// ─────────────────────────────────────────────────────────────────────────

class _CategoryContent extends StatelessWidget {
  const _CategoryContent({required this.category, required this.mode});

  final ReportCategory category;
  final ReportMode mode;

  @override
  Widget build(BuildContext context) {
    switch (category) {
      case ReportCategory.ventas:
        return _VentasReport(mode: mode);
      case ReportCategory.caja:
        return _CajaReport(mode: mode);
      case ReportCategory.liquidacion:
        return const _LiquidacionReport();
      case ReportCategory.cobros:
        return _CobrosReport(mode: mode);
      case ReportCategory.pagos:
        return _PagosReport(mode: mode);
      case ReportCategory.ventasSuspendidas:
        return _SuspendedReport(mode: mode);
      // ── Round 2 ────────────────────────────────────────────────────
      case ReportCategory.empleados:
        return _EmpleadosReport(mode: mode);
      case ReportCategory.comision:
        return const _ComisionReport();
      case ReportCategory.inventario:
        return _InventarioReport(mode: mode);
      case ReportCategory.articulos:
        return _ArticulosReport(mode: mode);
      case ReportCategory.categorias:
        return _CategoriasReport(mode: mode);
      case ReportCategory.precios:
        return const _PreciosReport();
      case ReportCategory.mermas:
        return _MermasReport(mode: mode);
      case ReportCategory.perdidasGanancias:
        return const _PlReport();
      case ReportCategory.credito:
        return const _CreditoReport();
      case ReportCategory.gastos:
        return _GastosReport(mode: mode);
      case ReportCategory.compras:
        return _ComprasReport(mode: mode);
      case ReportCategory.proveedores:
        return const _ProveedoresReport();
      case ReportCategory.clientes:
        return const _ClientesReport();
      case ReportCategory.descuentos:
        return const _DescuentosReport();
      // ── Round 3 (DGII) ─────────────────────────────────────────────
      case ReportCategory.estadoDiario:
        return const _EstadoDiarioReport();
      case ReportCategory.reporte606:
        return const _Dgii606Report();
      case ReportCategory.reporte607:
        return const _Dgii607Report();
      case ReportCategory.reporteIt1:
        return const _DgiiIt1Report();
      case ReportCategory.cierreZFiscal:
        return const _CierreZReport();
      case ReportCategory.impuestos:
        return _ImpuestosReport(mode: mode);
      default:
        return _ComingSoon(category: category);
    }
  }
}

// ─────────────────────────────────────────────────────────────────────────
// Helpers de tabla / chart compartidos
// ─────────────────────────────────────────────────────────────────────────

class _ReportCard extends StatelessWidget {
  const _ReportCard({required this.title, required this.child});
  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(AppTokens.s16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
            ),
            const SizedBox(height: AppTokens.s12),
            child,
          ],
        ),
      ),
    );
  }
}

/// Tabla simple usada por casi todos los reportes (26 usos).
///
/// Virtualizada: si hay muchas filas (> [maxVisibleRows]) usa
/// `ListView.builder + itemExtent` para que el render sea O(filas
/// visibles) en vez de O(filas totales). Si la tabla es chica
/// muestra todo sin altura fija para que se adapte al contenido.
class _SimpleTable extends StatelessWidget {
  const _SimpleTable({required this.columns, required this.rows});
  final List<String> columns;
  final List<List<String>> rows;

  static const _rowHeight = 44.0;
  static const _maxVisibleRows = 12;

  @override
  Widget build(BuildContext context) {
    if (rows.isEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: AppTokens.s24),
        child: Center(
          child: Text(
            'Sin datos para el rango seleccionado.',
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: AppTokens.mutedForeground,
                ),
          ),
        ),
      );
    }

    final flexes = _flexesFor(columns);
    final header = _ReportTableHeader(labels: columns, flexes: flexes);

    if (rows.length <= _maxVisibleRows) {
      // Tabla corta: render directo, altura natural.
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          header,
          for (int i = 0; i < rows.length; i++)
            SizedBox(
              height: _rowHeight,
              child: _ReportTableRow(
                cells: rows[i],
                flexes: flexes,
              ),
            ),
        ],
      );
    }

    // Tabla larga: viewport fijo + ListView.builder virtualizado.
    final viewportHeight = _maxVisibleRows * _rowHeight;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        header,
        SizedBox(
          height: viewportHeight,
          child: ListView.builder(
            itemCount: rows.length,
            itemExtent: _rowHeight,
            itemBuilder: (context, index) => _ReportTableRow(
              cells: rows[index],
              flexes: flexes,
            ),
          ),
        ),
      ],
    );
  }

  static List<int> _flexesFor(List<String> columns) {
    // Por default flex 1 en todas; las que parecen numéricas (con $, %,
    // o solo dígitos en el header) reciben flex 1 también — el layout se
    // adapta al ancho del padre.
    return List<int>.filled(columns.length, 1);
  }
}

class _ReportTableHeader extends StatelessWidget {
  const _ReportTableHeader({required this.labels, required this.flexes});

  final List<String> labels;
  final List<int> flexes;

  @override
  Widget build(BuildContext context) {
    return Container(
      color: const Color(0xFFF8FAFC),
      padding: const EdgeInsets.symmetric(
          horizontal: AppTokens.s16, vertical: AppTokens.s10),
      child: Row(
        children: [
          for (int i = 0; i < labels.length; i++)
            Expanded(
              flex: flexes[i],
              child: Text(
                labels[i],
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: Color(0xFF475569),
                  letterSpacing: 0.3,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _ReportTableRow extends StatelessWidget {
  const _ReportTableRow({required this.cells, required this.flexes});

  final List<String> cells;
  final List<int> flexes;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        border: Border(
          top: BorderSide(color: Color(0xFFE2E8F0)),
        ),
      ),
      padding: const EdgeInsets.symmetric(horizontal: AppTokens.s16),
      child: Row(
        children: [
          for (int i = 0; i < cells.length; i++)
            Expanded(
              flex: i < flexes.length ? flexes[i] : 1,
              child: Text(
                cells[i],
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 13),
              ),
            ),
        ],
      ),
    );
  }
}

class _SimpleBarChart extends StatelessWidget {
  const _SimpleBarChart({
    required this.points,
    required this.color,
  });

  final List<({String label, double value})> points;
  final Color color;
  static const double height = 220;

  @override
  Widget build(BuildContext context) {
    if (points.isEmpty) {
      return SizedBox(
        height: height,
        child: Center(
          child: Text(
            'Sin datos para graficar.',
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: AppTokens.mutedForeground,
                ),
          ),
        ),
      );
    }
    final maxValue = points.fold<double>(
      0,
      (prev, p) => math.max(prev, p.value),
    );
    final scale = maxValue == 0 ? 1.0 : maxValue;

    return SizedBox(
      height: height + 28,
      child: Column(
        children: [
          Expanded(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                for (final p in points)
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 3),
                      child: Tooltip(
                        message: '${p.label}\n${money(p.value)}',
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.end,
                          children: [
                            Container(
                              height:
                                  math.max(4, (p.value / scale) * height),
                              decoration: BoxDecoration(
                                color: color,
                                borderRadius: const BorderRadius.vertical(
                                  top: Radius.circular(6),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: AppTokens.s4),
          Row(
            children: [
              for (final p in points)
                Expanded(
                  child: Center(
                    child: Text(
                      p.label,
                      style: Theme.of(context).textTheme.labelSmall?.copyWith(
                            color: AppTokens.mutedForeground,
                          ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────
// 1) Ventas
// ─────────────────────────────────────────────────────────────────────────

class _VentasReport extends ConsumerWidget {
  const _VentasReport({required this.mode});

  final ReportMode mode;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final dataAsync = ref.watch(salesDailyReportProvider);

    return dataAsync.when(
      loading: () =>
          const Padding(padding: EdgeInsets.all(AppTokens.s32), child:
              Center(child: CircularProgressIndicator())),
      error: (error, _) => ErrorCard(
        message: 'No se pudieron cargar las ventas: $error',
        onRetry: () => ref.invalidate(salesDailyReportProvider),
      ),
      data: (rows) {
        if (rows.isEmpty) {
          return const _ReportCard(
            title: 'Ventas',
            child: _SimpleTable(columns: [], rows: []),
          );
        }

        // Agrupar por día para gráfico/tabla.
        final byDay = <DateTime, _SalesDayBucket>{};
        for (final r in rows) {
          final day = DateTime(
              r.saleDay.year, r.saleDay.month, r.saleDay.day);
          byDay.update(
            day,
            (b) {
              b.salesCount += r.salesCount;
              b.netTotal += r.netTotal;
              b.taxTotal += r.itbisTotal;
              return b;
            },
            ifAbsent: () => _SalesDayBucket()
              ..salesCount = r.salesCount
              ..netTotal = r.netTotal
              ..taxTotal = r.itbisTotal,
          );
        }
        final days = byDay.keys.toList()..sort();

        if (mode == ReportMode.graphic) {
          final points = [
            for (final d in days)
              (label: '${d.day}/${d.month}', value: byDay[d]!.netTotal),
          ];
          return _ReportCard(
            title: 'Ventas — Reporte gráfico',
            child: _SimpleBarChart(
              points: points,
              color: ReportCategory.ventas.group.accent,
            ),
          );
        }

        final tableRows = days
            .map((d) => [
                  formatDate(d),
                  byDay[d]!.salesCount.toString(),
                  money(byDay[d]!.netTotal),
                  money(byDay[d]!.taxTotal),
                ])
            .toList(growable: false);
        // Totales
        final totalCount =
            byDay.values.fold<int>(0, (s, b) => s + b.salesCount);
        final totalNet =
            byDay.values.fold<double>(0, (s, b) => s + b.netTotal);
        final totalTax =
            byDay.values.fold<double>(0, (s, b) => s + b.taxTotal);

        final range = ref.read(reportDateRangeProvider);
        _publishExport(
          ref,
          fileBaseName: 'ventas_resumen',
          build: () => ReportExportData(
            title: 'Reporte de Ventas',
            subtitle: 'Resumen por día',
            dateFrom: range.from,
            dateTo: range.to,
            sections: [
              ReportSection(
                table: ReportTable(
                  columns: const ['Fecha', 'Ventas', 'Neto', 'ITBIS'],
                  rows: tableRows,
                  numericColumns: const {1, 2, 3},
                ),
                totals: [
                  ReportKv('Transacciones', '$totalCount'),
                  ReportKv('ITBIS', money(totalTax)),
                  ReportKv('Neto', money(totalNet), highlight: true),
                ],
              ),
            ],
          ),
        );

        return _ReportCard(
          title: 'Ventas — Reporte de resumen',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _SimpleTable(
                columns: const ['Fecha', 'Ventas', 'Neto', 'ITBIS'],
                rows: tableRows,
              ),
              const Divider(),
              _TotalsRow(items: {
                'Transacciones': '$totalCount',
                'ITBIS': money(totalTax),
                'Neto': money(totalNet),
              }),
            ],
          ),
        );
      },
    );
  }
}

class _SalesDayBucket {
  int salesCount = 0;
  double netTotal = 0;
  double taxTotal = 0;
}

// ─────────────────────────────────────────────────────────────────────────
// 2) Caja
// ─────────────────────────────────────────────────────────────────────────

class _CajaReport extends ConsumerWidget {
  const _CajaReport({required this.mode});

  final ReportMode mode;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(cashSessionsReportProvider);

    return async.when(
      loading: () =>
          const Padding(padding: EdgeInsets.all(AppTokens.s32), child:
              Center(child: CircularProgressIndicator())),
      error: (error, _) => ErrorCard(
        message: 'No se pudieron cargar las sesiones de caja: $error',
        onRetry: () => ref.invalidate(cashSessionsReportProvider),
      ),
      data: (rows) {
        if (mode == ReportMode.graphic) {
          // Totales por método agregados de todas las sesiones.
          final totalCash =
              rows.fold<double>(0, (s, r) => s + r.cashCollected);
          final totalCard =
              rows.fold<double>(0, (s, r) => s + r.cardCollected);
          final totalTransfer =
              rows.fold<double>(0, (s, r) => s + r.transferCollected);
          final totalCredit =
              rows.fold<double>(0, (s, r) => s + r.creditCollected);
          return _ReportCard(
            title: 'Caja — Cobros por método (gráfico)',
            child: _SimpleBarChart(
              points: [
                (label: 'Efectivo', value: totalCash),
                (label: 'Tarjeta', value: totalCard),
                (label: 'Transf.', value: totalTransfer),
                (label: 'Crédito', value: totalCredit),
              ],
              color: ReportCategory.caja.group.accent,
            ),
          );
        }

        final tableRows = rows
            .map((r) => [
                  formatDate(r.openedAt),
                  r.status == 'open' ? 'Abierta' : 'Cerrada',
                  money(r.openingAmount),
                  money(r.salesTotal),
                  '${r.salesCompleted}',
                  '${r.salesVoided}',
                  r.closingAmount == null
                      ? '—'
                      : money(r.closingAmount),
                  r.differenceAmount == null
                      ? '—'
                      : money(r.differenceAmount),
                ])
            .toList(growable: false);

        const cajaColumns = [
          'Apertura',
          'Estado',
          'Inicial',
          'Ventas',
          'Compl.',
          'Anul.',
          'Cierre',
          'Diferencia',
        ];

        final range = ref.read(reportDateRangeProvider);
        _publishExport(
          ref,
          fileBaseName: 'caja_sesiones',
          build: () => ReportExportData(
            title: 'Reporte de Caja',
            subtitle: 'Sesiones del período',
            dateFrom: range.from,
            dateTo: range.to,
            sections: [
              ReportSection(
                table: ReportTable(
                  columns: cajaColumns,
                  rows: tableRows,
                  numericColumns: const {2, 3, 4, 5, 6, 7},
                ),
              ),
            ],
          ),
        );

        return _ReportCard(
          title: 'Caja — Sesiones del período',
          child: _SimpleTable(
            columns: cajaColumns,
            rows: tableRows,
          ),
        );
      },
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────
// 3) Liquidación (solo summary, reusa closeout del dashboard)
// ─────────────────────────────────────────────────────────────────────────

class _LiquidacionReport extends ConsumerWidget {
  const _LiquidacionReport();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(operationalCloseoutReportProvider);

    return async.when(
      loading: () =>
          const Padding(padding: EdgeInsets.all(AppTokens.s32), child:
              Center(child: CircularProgressIndicator())),
      error: (error, _) => ErrorCard(
        message: 'No se pudo cargar la liquidación: $error',
        onRetry: () => ref.invalidate(operationalCloseoutReportProvider),
      ),
      data: (data) {
        final sales = (data['sales'] as Map?) ?? const {};
        final cash = (data['cash_monitoring'] as Map?) ?? const {};
        final salesTotal = (sales['sales_total_with_tax'] as num?)?.toDouble() ?? 0;
        final txCount = (sales['transactions_count'] as num?)?.toInt() ?? 0;
        final avgTicket = (sales['avg_ticket'] as num?)?.toDouble() ?? 0;
        final cashAmount =
            (sales['cash_amount'] as num?)?.toDouble() ?? 0;
        final cashEnabled = cash['enabled'] == true;

        final range = ref.read(reportDateRangeProvider);
        _publishExport(
          ref,
          fileBaseName: 'liquidacion',
          build: () => ReportExportData(
            title: 'Liquidación operativa',
            subtitle: 'Cierre del día ${formatDate(range.to)}',
            dateFrom: range.from,
            dateTo: range.to,
            sections: [
              ReportSection(
                kv: [
                  ReportKv('Total ventas del día', money(salesTotal)),
                  ReportKv('Transacciones', '$txCount'),
                  ReportKv('Ticket promedio', money(avgTicket)),
                  ReportKv('Efectivo cobrado', money(cashAmount)),
                  if (cashEnabled) ...[
                    ReportKv(
                      'Efectivo inicial',
                      money((cash['opening_amount'] as num?)?.toDouble() ?? 0),
                    ),
                    ReportKv(
                      'Efectivo esperado',
                      money((cash['expected_amount'] as num?)?.toDouble() ?? 0),
                    ),
                    if (cash['closing_amount'] != null)
                      ReportKv(
                        'Cierre declarado',
                        money((cash['closing_amount'] as num).toDouble()),
                      ),
                    if (cash['difference_amount'] != null)
                      ReportKv(
                        'Diferencia',
                        money((cash['difference_amount'] as num).toDouble()),
                        highlight: true,
                      ),
                  ],
                ],
                note: cashEnabled
                    ? null
                    : 'No hay sesión de caja registrada para este día.',
              ),
            ],
          ),
        );

        return _ReportCard(
          title: 'Liquidación operativa — ${formatDate(range.to)}',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _KVRow('Total ventas del día', money(salesTotal)),
              _KVRow('Transacciones', '$txCount'),
              _KVRow('Ticket promedio', money(avgTicket)),
              _KVRow('Efectivo cobrado', money(cashAmount)),
              const Divider(),
              if (cashEnabled) ...[
                _KVRow('Efectivo inicial',
                    money((cash['opening_amount'] as num?)?.toDouble() ?? 0)),
                _KVRow('Efectivo esperado',
                    money((cash['expected_amount'] as num?)?.toDouble() ?? 0)),
                if (cash['closing_amount'] != null)
                  _KVRow('Cierre declarado',
                      money((cash['closing_amount'] as num).toDouble())),
                if (cash['difference_amount'] != null)
                  _KVRow('Diferencia',
                      money((cash['difference_amount'] as num).toDouble())),
              ] else
                Text(
                  'No hay sesión de caja registrada para este día.',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: AppTokens.mutedForeground,
                      ),
                ),
            ],
          ),
        );
      },
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────
// 4) Cobros
// ─────────────────────────────────────────────────────────────────────────

class _CobrosReport extends ConsumerWidget {
  const _CobrosReport({required this.mode});

  final ReportMode mode;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(paymentsReportProvider);

    return async.when(
      loading: () =>
          const Padding(padding: EdgeInsets.all(AppTokens.s32), child:
              Center(child: CircularProgressIndicator())),
      error: (error, _) => ErrorCard(
        message: 'No se pudieron cargar los cobros: $error',
        onRetry: () => ref.invalidate(paymentsReportProvider),
      ),
      data: (rows) {
        if (mode == ReportMode.graphic) {
          return _ReportCard(
            title: 'Cobros — Total por método',
            child: _SimpleBarChart(
              points: [
                for (final r in rows)
                  (label: r.methodLabel, value: r.total),
              ],
              color: ReportCategory.cobros.group.accent,
            ),
          );
        }

        final tableRows = rows
            .map((r) => [r.methodLabel, '${r.count}', money(r.total)])
            .toList(growable: false);
        final totalAmount =
            rows.fold<double>(0, (s, r) => s + r.total);
        final totalCount = rows.fold<int>(0, (s, r) => s + r.count);

        final range = ref.read(reportDateRangeProvider);
        _publishExport(
          ref,
          fileBaseName: 'cobros_resumen',
          build: () => ReportExportData(
            title: 'Reporte de Cobros',
            subtitle: 'Por método de pago',
            dateFrom: range.from,
            dateTo: range.to,
            sections: [
              ReportSection(
                table: ReportTable(
                  columns: const ['Método', 'Pagos', 'Total'],
                  rows: tableRows,
                  numericColumns: const {1, 2},
                ),
                totals: [
                  ReportKv('Pagos', '$totalCount'),
                  ReportKv('Total cobrado', money(totalAmount), highlight: true),
                ],
              ),
            ],
          ),
        );

        return _ReportCard(
          title: 'Cobros — Reporte de resumen',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _SimpleTable(
                columns: const ['Método', 'Pagos', 'Total'],
                rows: tableRows,
              ),
              const Divider(),
              _TotalsRow(items: {
                'Pagos': '$totalCount',
                'Total cobrado': money(totalAmount),
              }),
            ],
          ),
        );
      },
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────
// 5) Pagos (gastos + compras)
// ─────────────────────────────────────────────────────────────────────────

class _PagosReport extends ConsumerWidget {
  const _PagosReport({required this.mode});

  final ReportMode mode;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(outgoingPaymentsReportProvider);

    return async.when(
      loading: () =>
          const Padding(padding: EdgeInsets.all(AppTokens.s32), child:
              Center(child: CircularProgressIndicator())),
      error: (error, _) => ErrorCard(
        message: 'No se pudieron cargar los pagos: $error',
        onRetry: () => ref.invalidate(outgoingPaymentsReportProvider),
      ),
      data: (rows) {
        if (mode == ReportMode.graphic) {
          // Sumar por día.
          final byDay = <String, double>{};
          for (final r in rows) {
            final key = formatDate(r.date);
            byDay.update(key, (v) => v + r.amount, ifAbsent: () => r.amount);
          }
          final points = byDay.entries
              .map((e) => (label: e.key, value: e.value))
              .toList();
          return _ReportCard(
            title: 'Pagos — Total por día',
            child: _SimpleBarChart(
              points: points,
              color: ReportCategory.pagos.group.accent,
            ),
          );
        }

        final tableRows = rows
            .map((r) => [
                  formatDate(r.date),
                  r.kind,
                  r.description,
                  money(r.amount),
                ])
            .toList(growable: false);
        final total = rows.fold<double>(0, (s, r) => s + r.amount);

        final range = ref.read(reportDateRangeProvider);
        _publishExport(
          ref,
          fileBaseName: 'pagos_resumen',
          build: () => ReportExportData(
            title: 'Reporte de Pagos',
            subtitle: 'Egresos del período (compras y gastos)',
            dateFrom: range.from,
            dateTo: range.to,
            sections: [
              ReportSection(
                table: ReportTable(
                  columns: const ['Fecha', 'Tipo', 'Descripción', 'Monto'],
                  rows: tableRows,
                  numericColumns: const {3},
                ),
                totals: [
                  ReportKv('Pagos', '${rows.length}'),
                  ReportKv('Total', money(total), highlight: true),
                ],
              ),
            ],
          ),
        );

        return _ReportCard(
          title: 'Pagos — Reporte de resumen',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _SimpleTable(
                columns: const ['Fecha', 'Tipo', 'Descripción', 'Monto'],
                rows: tableRows,
              ),
              const Divider(),
              _TotalsRow(
                  items: {'Pagos': '${rows.length}', 'Total': money(total)}),
            ],
          ),
        );
      },
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────
// 6) Ventas suspendidas
// ─────────────────────────────────────────────────────────────────────────

class _SuspendedReport extends ConsumerWidget {
  const _SuspendedReport({required this.mode});

  final ReportMode mode;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(suspendedSalesReportProvider);

    return async.when(
      loading: () =>
          const Padding(padding: EdgeInsets.all(AppTokens.s32), child:
              Center(child: CircularProgressIndicator())),
      error: (error, _) => ErrorCard(
        message: 'No se pudieron cargar las ventas suspendidas: $error',
        onRetry: () => ref.invalidate(suspendedSalesReportProvider),
      ),
      data: (rows) {
        if (mode == ReportMode.graphic) {
          // Cuenta por día.
          final byDay = <String, double>{};
          for (final r in rows) {
            final key = formatDate(r.saleDate);
            byDay.update(key, (v) => v + r.totalAmount,
                ifAbsent: () => r.totalAmount);
          }
          final points = byDay.entries
              .map((e) => (label: e.key, value: e.value))
              .toList();
          return _ReportCard(
            title: 'Ventas suspendidas — Monto pendiente por día',
            child: _SimpleBarChart(
              points: points,
              color: ReportCategory.ventasSuspendidas.group.accent,
            ),
          );
        }
        final tableRows = rows
            .map((r) => [
                  formatDateTime(r.saleDate),
                  r.saleNumber,
                  r.clientName ?? '—',
                  r.status,
                  money(r.totalAmount),
                ])
            .toList(growable: false);
        final total = rows.fold<double>(0, (s, r) => s + r.totalAmount);

        final range = ref.read(reportDateRangeProvider);
        _publishExport(
          ref,
          fileBaseName: 'ventas_suspendidas',
          build: () => ReportExportData(
            title: 'Ventas suspendidas',
            subtitle: 'Cuentas abiertas / pendientes',
            dateFrom: range.from,
            dateTo: range.to,
            sections: [
              ReportSection(
                table: ReportTable(
                  columns: const [
                    'Fecha',
                    '#',
                    'Cliente',
                    'Estado',
                    'Total',
                  ],
                  rows: tableRows,
                  numericColumns: const {4},
                ),
                totals: [
                  ReportKv('Cuentas abiertas', '${rows.length}'),
                  ReportKv('Monto pendiente', money(total), highlight: true),
                ],
              ),
            ],
          ),
        );

        return _ReportCard(
          title: 'Ventas suspendidas — Reporte de resumen',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _SimpleTable(
                columns: const ['Fecha', '#', 'Cliente', 'Estado', 'Total'],
                rows: tableRows,
              ),
              const Divider(),
              _TotalsRow(items: {
                'Cuentas abiertas': '${rows.length}',
                'Monto pendiente': money(total),
              }),
            ],
          ),
        );
      },
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────
// Helpers UI compartidos
// ─────────────────────────────────────────────────────────────────────────

class _KVRow extends StatelessWidget {
  const _KVRow(this.label, this.value);
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppTokens.s4),
      child: Row(
        children: [
          Expanded(
              child: Text(label,
                  style: Theme.of(context).textTheme.bodyMedium)),
          Text(value,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                  )),
        ],
      ),
    );
  }
}

class _TotalsRow extends StatelessWidget {
  const _TotalsRow({required this.items});
  final Map<String, String> items;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: AppTokens.s8),
      child: Wrap(
        spacing: AppTokens.s24,
        runSpacing: AppTokens.s8,
        children: [
          for (final entry in items.entries)
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  '${entry.key}: ',
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: AppTokens.mutedForeground,
                      ),
                ),
                Text(
                  entry.value,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                ),
              ],
            ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────
// Ventas: sub-menú de sub-reportes (PRD §F-Ventas)
// ─────────────────────────────────────────────────────────────────────────

class _VentasSubReportMenu extends ConsumerWidget {
  const _VentasSubReportMenu();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: AppTokens.s12,
          vertical: AppTokens.s8,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(
                  AppTokens.s12, AppTokens.s12, AppTokens.s12, AppTokens.s6),
              child: Row(
                children: [
                  Icon(ReportCategory.ventas.icon,
                      color: ReportCategory.ventas.group.accent),
                  const SizedBox(width: AppTokens.s10),
                  Text(
                    'Ventas',
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(
                          color: ReportCategory.ventas.group.accent,
                          fontWeight: FontWeight.w800,
                        ),
                  ),
                ],
              ),
            ),
            const Divider(height: 1, color: AppTokens.border),
            for (var i = 0; i < VentasSubReport.values.length; i++) ...[
              _VentasSubReportTile(sub: VentasSubReport.values[i]),
              if (i != VentasSubReport.values.length - 1)
                const Divider(height: 1, color: AppTokens.border),
            ],
          ],
        ),
      ),
    );
  }
}

class _VentasSubReportTile extends ConsumerWidget {
  const _VentasSubReportTile({required this.sub});

  final VentasSubReport sub;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final accent = ReportCategory.ventas.group.accent;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () {
          if (!sub.isImplemented) return;
          if (sub == VentasSubReport.detallado607) {
            // Cambiar de categoría → llevar al usuario al reporte 607.
            ref.read(reportCategoryProvider.notifier).state =
                ReportCategory.reporte607;
            ref.read(ventasSubReportProvider.notifier).state = null;
            return;
          }
          if (sub == VentasSubReport.graficos) {
            ref.read(reportModeProvider.notifier).state = ReportMode.graphic;
            ref.read(ventasSubReportProvider.notifier).state = null;
            return;
          }
          if (sub == VentasSubReport.resumen) {
            ref.read(reportModeProvider.notifier).state = ReportMode.summary;
            ref.read(ventasSubReportProvider.notifier).state = null;
            return;
          }
          ref.read(ventasSubReportProvider.notifier).state = sub;
        },
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: AppTokens.s16,
            vertical: AppTokens.s14,
          ),
          child: Row(
            children: [
              Icon(sub.icon, color: accent, size: 20),
              const SizedBox(width: AppTokens.s16),
              Expanded(
                child: Text(
                  sub.title,
                  style: TextStyle(
                    color: sub.isImplemented
                        ? AppTokens.foreground
                        : AppTokens.mutedForeground,
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
              if (!sub.isImplemented)
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(
                    color: AppTokens.muted,
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    'Próx.',
                    style: TextStyle(
                      color: AppTokens.mutedForeground,
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                )
              else
                Icon(Icons.chevron_right,
                    size: 18, color: AppTokens.mutedForeground),
            ],
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────
// Ventas: contenido del sub-reporte seleccionado
// ─────────────────────────────────────────────────────────────────────────

class _VentasSubReportContent extends ConsumerWidget {
  const _VentasSubReportContent({required this.sub});

  final VentasSubReport sub;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    switch (sub) {
      case VentasSubReport.detallados:
        return const _DetailedSalesReport(voidedOnly: false);
      case VentasSubReport.eliminadas:
        return const _DetailedSalesReport(voidedOnly: true);
      case VentasSubReport.resumenTime:
        return const _TimeReport(graphic: false);
      case VentasSubReport.graficoTime:
        return const _TimeReport(graphic: true);
      case VentasSubReport.beneficioEntregas:
      case VentasSubReport.conduce:
      case VentasSubReport.delivery:
        return _ComingSoonSub(sub: sub);
      // Estos deberían haberse interceptado en el menú; fallback defensivo.
      case VentasSubReport.graficos:
      case VentasSubReport.resumen:
      case VentasSubReport.detallado607:
        return const _DetailedSalesReport(voidedOnly: false);
    }
  }
}

class _ComingSoonSub extends StatelessWidget {
  const _ComingSoonSub({required this.sub});

  final VentasSubReport sub;

  @override
  Widget build(BuildContext context) {
    return EmptyStateCard(
      icon: sub.icon,
      message: '"${sub.title}" llega cuando el sistema soporte entregas/conduces/'
          'delivery. La estructura ya está prevista en el PRD pero falta '
          'el modelo de datos correspondiente.',
    );
  }
}

class _DetailedSalesReport extends ConsumerWidget {
  const _DetailedSalesReport({required this.voidedOnly});

  final bool voidedOnly;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(voidedOnly
        ? voidedSalesReportProvider
        : detailedSalesReportProvider);

    return async.when(
      loading: () => const Padding(
        padding: EdgeInsets.all(AppTokens.s32),
        child: Center(child: CircularProgressIndicator()),
      ),
      error: (error, _) => ErrorCard(
        message: 'No se pudieron cargar las ventas: $error',
        onRetry: () => ref.invalidate(voidedOnly
            ? voidedSalesReportProvider
            : detailedSalesReportProvider),
      ),
      data: (rows) {
        final tableRows = rows
            .map((r) => [
                  formatDateTime(r.saleDate),
                  r.saleNumber,
                  r.ncf ?? '—',
                  r.clientName ?? 'Consumidor Final',
                  r.cashierName ?? '—',
                  r.cashRegisterName ?? '—',
                  _statusLabel(r.status),
                  money(r.subtotal),
                  money(r.taxAmount),
                  money(r.totalAmount),
                  money(r.profit),
                ])
            .toList(growable: false);
        final totalAmount =
            rows.fold<double>(0, (s, r) => s + r.totalAmount);
        final totalTax =
            rows.fold<double>(0, (s, r) => s + r.taxAmount);
        final totalProfit =
            rows.fold<double>(0, (s, r) => s + r.profit);

        const columns = [
          'Fecha',
          '#',
          'NCF',
          'Cliente',
          'Cajero',
          'Caja',
          'Estado',
          'Subtotal',
          'ITBIS',
          'Total',
          'Ganancia',
        ];
        final range = ref.read(reportDateRangeProvider);
        _publishExport(
          ref,
          fileBaseName: voidedOnly ? 'ventas_eliminadas' : 'ventas_detalladas',
          build: () => ReportExportData(
            title: voidedOnly
                ? 'Ventas eliminadas / anuladas'
                : 'Ventas detalladas',
            dateFrom: range.from,
            dateTo: range.to,
            sections: [
              ReportSection(
                table: ReportTable(
                  columns: columns,
                  rows: tableRows,
                  numericColumns: const {7, 8, 9, 10},
                ),
                totals: rows.isEmpty
                    ? null
                    : [
                        ReportKv('Ventas', '${rows.length}'),
                        ReportKv('ITBIS', money(totalTax)),
                        ReportKv('Total', money(totalAmount), highlight: true),
                        ReportKv('Ganancia', money(totalProfit)),
                      ],
              ),
            ],
          ),
        );

        return _ReportCard(
          title: voidedOnly
              ? 'Ventas eliminadas / anuladas'
              : 'Ventas detalladas',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _SimpleTable(
                columns: const [
                  'Fecha',
                  '#',
                  'NCF',
                  'Cliente',
                  'Cajero',
                  'Caja',
                  'Estado',
                  'Subtotal',
                  'ITBIS',
                  'Total',
                  'Ganancia',
                ],
                rows: tableRows,
              ),
              if (rows.isNotEmpty) ...[
                const Divider(),
                _TotalsRow(items: {
                  'Ventas': '${rows.length}',
                  'ITBIS': money(totalTax),
                  'Total': money(totalAmount),
                  'Ganancia': money(totalProfit),
                }),
              ],
            ],
          ),
        );
      },
    );
  }

  String _statusLabel(String status) {
    switch (status) {
      case 'completed':
        return 'Completada';
      case 'credit':
        return 'A crédito';
      case 'voided':
        return 'Anulada';
      case 'pending':
        return 'Pendiente';
      case 'draft':
        return 'Borrador';
      default:
        return status;
    }
  }
}

class _TimeReport extends ConsumerWidget {
  const _TimeReport({required this.graphic});

  final bool graphic;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(hourlySalesReportProvider);

    return async.when(
      loading: () => const Padding(
        padding: EdgeInsets.all(AppTokens.s32),
        child: Center(child: CircularProgressIndicator()),
      ),
      error: (error, _) => ErrorCard(
        message: 'No se pudieron cargar las ventas por hora: $error',
        onRetry: () => ref.invalidate(hourlySalesReportProvider),
      ),
      data: (rows) {
        if (graphic) {
          return _ReportCard(
            title: 'Ventas por hora del día (gráfico)',
            child: _SimpleBarChart(
              points: [
                for (final r in rows)
                  (label: r.hourLabel, value: r.total),
              ],
              color: ReportCategory.ventas.group.accent,
            ),
          );
        }
        final tableRows = rows
            .where((r) => r.salesCount > 0)
            .map((r) => [
                  r.hourLabel,
                  r.salesCount.toString(),
                  money(r.tax),
                  money(r.total),
                ])
            .toList(growable: false);
        final totalCount =
            rows.fold<int>(0, (s, r) => s + r.salesCount);
        final totalAmount =
            rows.fold<double>(0, (s, r) => s + r.total);

        final range = ref.read(reportDateRangeProvider);
        _publishExport(
          ref,
          fileBaseName: 'ventas_por_hora',
          build: () => ReportExportData(
            title: 'Ventas por hora del día',
            dateFrom: range.from,
            dateTo: range.to,
            sections: [
              ReportSection(
                table: ReportTable(
                  columns: const ['Hora', 'Ventas', 'ITBIS', 'Total'],
                  rows: tableRows,
                  numericColumns: const {1, 2, 3},
                ),
                totals: totalCount == 0
                    ? null
                    : [
                        ReportKv('Transacciones', '$totalCount'),
                        ReportKv('Total', money(totalAmount), highlight: true),
                      ],
              ),
            ],
          ),
        );

        return _ReportCard(
          title: 'Ventas por hora del día',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _SimpleTable(
                columns: const ['Hora', 'Ventas', 'ITBIS', 'Total'],
                rows: tableRows,
              ),
              if (totalCount > 0) ...[
                const Divider(),
                _TotalsRow(items: {
                  'Transacciones': '$totalCount',
                  'Total': money(totalAmount),
                }),
              ],
            ],
          ),
        );
      },
    );
  }
}

// ═════════════════════════════════════════════════════════════════════════
// ROUND 2 — 12 reportes adicionales
// ═════════════════════════════════════════════════════════════════════════

class _EmpleadosReport extends ConsumerWidget {
  const _EmpleadosReport({required this.mode});
  final ReportMode mode;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(employeeProductivityProvider);
    return async.when(
      loading: () => const _LoadingBox(),
      error: (e, _) => ErrorCard(
        message: 'No se pudo cargar: $e',
        onRetry: () => ref.invalidate(employeeProductivityProvider),
      ),
      data: (rows) {
        // Agrupar por empleado (la vista trae filas por día).
        final byEmployee = <String, _EmpAgg>{};
        for (final r in rows) {
          final key = r.employeeId ?? 'sin-asignar';
          byEmployee.update(
            key,
            (a) {
              a.sales += r.salesCount;
              a.total += r.salesTotal;
              a.items += r.itemsSold;
              if (a.last == null || (r.lastSaleAt != null && r.lastSaleAt!.isAfter(a.last!))) {
                a.last = r.lastSaleAt;
              }
              return a;
            },
            ifAbsent: () => _EmpAgg(name: r.employeeName)
              ..sales = r.salesCount
              ..total = r.salesTotal
              ..items = r.itemsSold
              ..last = r.lastSaleAt,
          );
        }
        final entries = byEmployee.values.toList()
          ..sort((a, b) => b.total.compareTo(a.total));

        if (mode == ReportMode.graphic) {
          return _ReportCard(
            title: 'Empleados — Ventas por persona',
            child: _SimpleBarChart(
              points: [
                for (final e in entries)
                  (label: e.name.split(' ').first, value: e.total),
              ],
              color: ReportCategory.empleados.group.accent,
            ),
          );
        }

        const empColumns = ['Empleado', 'Ventas', 'Total', 'Items', 'Última'];
        final tableRows = [
          for (final e in entries)
            [
              e.name,
              '${e.sales}',
              money(e.total),
              qty(e.items.toInt()),
              e.last == null ? '—' : formatDate(e.last!),
            ],
        ];

        final range = ref.read(reportDateRangeProvider);
        _publishExport(
          ref,
          fileBaseName: 'empleados_productividad',
          build: () => ReportExportData(
            title: 'Empleados — Productividad',
            dateFrom: range.from,
            dateTo: range.to,
            sections: [
              ReportSection(
                table: ReportTable(
                  columns: empColumns,
                  rows: tableRows,
                  numericColumns: const {1, 2, 3},
                ),
              ),
            ],
          ),
        );

        return _ReportCard(
          title: 'Empleados — Productividad',
          child: _SimpleTable(
            columns: empColumns,
            rows: tableRows,
          ),
        );
      },
    );
  }
}

class _EmpAgg {
  _EmpAgg({required this.name});
  final String name;
  int sales = 0;
  double total = 0;
  double items = 0;
  DateTime? last;
}

class _ComisionReport extends ConsumerWidget {
  const _ComisionReport();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(commissionReportProvider);
    return async.when(
      loading: () => const _LoadingBox(),
      error: (e, _) => ErrorCard(
        message: 'No se pudo cargar la comisión: $e',
        onRetry: () => ref.invalidate(commissionReportProvider),
      ),
      data: (data) {
        final rate = (data['rate'] as num?)?.toDouble() ?? 0;
        final method = (data['method'] ?? 'sale_price').toString();
        final rows = (data['rows'] as List?) ?? const [];

        final methodLabel = switch (method) {
          'profit_margin' => 'Margen de ganancia',
          'total_sales' => 'Total de ventas',
          _ => 'Precio de venta',
        };

        const colsComision = [
          'Empleado',
          'Ventas',
          'Total',
          'Base',
          'Comisión',
        ];
        final commissionRows = [
          for (final r in rows.cast<Map>())
            [
              (r['employee_name'] ?? '—').toString(),
              '${r['sales_count'] ?? 0}',
              money((r['sales_total'] as num?)?.toDouble() ?? 0),
              money((r['base_amount'] as num?)?.toDouble() ?? 0),
              money((r['commission_amount'] as num?)?.toDouble() ?? 0),
            ],
        ];
        final totalCommission = rows.cast<Map>().fold<double>(
              0,
              (s, r) =>
                  s + ((r['commission_amount'] as num?)?.toDouble() ?? 0),
            );

        final range = ref.read(reportDateRangeProvider);
        _publishExport(
          ref,
          fileBaseName: 'comision',
          build: () => ReportExportData(
            title: 'Comisión',
            subtitle: '$rate% sobre $methodLabel',
            dateFrom: range.from,
            dateTo: range.to,
            sections: [
              ReportSection(
                table: ReportTable(
                  columns: colsComision,
                  rows: commissionRows,
                  numericColumns: const {1, 2, 3, 4},
                ),
                totals: [
                  ReportKv(
                    'Comisión total',
                    money(totalCommission),
                    highlight: true,
                  ),
                ],
                note: rate == 0
                    ? 'La tasa de comisión está en 0%. Cámbiala en Configuración › Empleado.'
                    : null,
              ),
            ],
          ),
        );

        return _ReportCard(
          title: 'Comisión — $rate% sobre $methodLabel',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _SimpleTable(
                columns: const [
                  'Empleado',
                  'Ventas',
                  'Total',
                  'Base',
                  'Comisión',
                ],
                rows: [
                  for (final r in rows.cast<Map>())
                    [
                      (r['employee_name'] ?? '—').toString(),
                      '${r['sales_count'] ?? 0}',
                      money((r['sales_total'] as num?)?.toDouble() ?? 0),
                      money((r['base_amount'] as num?)?.toDouble() ?? 0),
                      money((r['commission_amount'] as num?)?.toDouble() ?? 0),
                    ],
                ],
              ),
              if (rate == 0)
                Padding(
                  padding: const EdgeInsets.only(top: AppTokens.s12),
                  child: Text(
                    'La tasa de comisión está en 0%. Cámbiala en '
                    'Configuración › Empleado.',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: AppTokens.warning,
                        ),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }
}

class _InventarioReport extends ConsumerWidget {
  const _InventarioReport({required this.mode});
  final ReportMode mode;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(inventoryStatusReportProvider);
    return async.when(
      loading: () => const _LoadingBox(),
      error: (e, _) => ErrorCard(
        message: 'No se pudo cargar el inventario: $e',
        onRetry: () => ref.invalidate(inventoryStatusReportProvider),
      ),
      data: (rows) {
        final total = rows.fold<double>(0, (s, r) => s + r.inventoryValue);
        final lowStock = rows.where((r) => r.isLowStock).length;

        if (mode == ReportMode.graphic) {
          // Top 10 productos por valor.
          final top = rows.take(10).toList();
          return _ReportCard(
            title: 'Inventario — Top 10 por valor',
            child: _SimpleBarChart(
              points: [
                for (final r in top)
                  (
                    label: r.name.length > 12
                        ? '${r.name.substring(0, 12)}…'
                        : r.name,
                    value: r.inventoryValue,
                  ),
              ],
              color: ReportCategory.inventario.group.accent,
            ),
          );
        }

        const invColumns = [
          'Producto',
          'Categoría',
          'Stock',
          'Mín.',
          'Costo',
          'Valor',
          'Estado',
        ];
        final invRows = [
          for (final r in rows)
            [
              r.name,
              r.categoryName ?? '—',
              qty(r.stock.toInt()),
              qty(r.minStock.toInt()),
              money(r.cost),
              money(r.inventoryValue),
              r.isOutOfStock
                  ? 'Sin stock'
                  : r.isLowStock
                      ? 'Bajo'
                      : 'OK',
            ],
        ];

        _publishExport(
          ref,
          fileBaseName: 'inventario_estado',
          build: () => ReportExportData(
            title: 'Inventario — Estado actual',
            sections: [
              ReportSection(
                table: ReportTable(
                  columns: invColumns,
                  rows: invRows,
                  numericColumns: const {2, 3, 4, 5},
                ),
                totals: [
                  ReportKv('Productos', '${rows.length}'),
                  ReportKv('En stock bajo', '$lowStock'),
                  ReportKv('Valor total', money(total), highlight: true),
                ],
              ),
            ],
          ),
        );

        return _ReportCard(
          title: 'Inventario — Estado actual',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _SimpleTable(columns: invColumns, rows: invRows),
              const Divider(),
              _TotalsRow(items: {
                'Productos': '${rows.length}',
                'En stock bajo': '$lowStock',
                'Valor total': money(total),
              }),
            ],
          ),
        );
      },
    );
  }
}

class _ArticulosReport extends ConsumerWidget {
  const _ArticulosReport({required this.mode});
  final ReportMode mode;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(salesByItemReportProvider);
    return async.when(
      loading: () => const _LoadingBox(),
      error: (e, _) => ErrorCard(
        message: 'No se pudieron cargar los artículos: $e',
        onRetry: () => ref.invalidate(salesByItemReportProvider),
      ),
      data: (rows) {
        final byProduct = <String, _ItemAgg>{};
        for (final r in rows) {
          byProduct.update(
            r.productId,
            (a) {
              a.units += r.unitsSold;
              a.gross += r.grossTotal;
              a.net += r.netTotal;
              a.sales += r.salesCount;
              return a;
            },
            ifAbsent: () => _ItemAgg(name: r.productName)
              ..units = r.unitsSold
              ..gross = r.grossTotal
              ..net = r.netTotal
              ..sales = r.salesCount,
          );
        }
        final ordered = byProduct.values.toList()
          ..sort((a, b) => b.net.compareTo(a.net));

        if (mode == ReportMode.graphic) {
          final top = ordered.take(10).toList();
          return _ReportCard(
            title: 'Artículos — Top 10 vendidos',
            child: _SimpleBarChart(
              points: [
                for (final p in top)
                  (
                    label: p.name.length > 12
                        ? '${p.name.substring(0, 12)}…'
                        : p.name,
                    value: p.net,
                  ),
              ],
              color: ReportCategory.articulos.group.accent,
            ),
          );
        }
        const articulosCols = ['Producto', 'Unidades', 'Ventas', 'Neto'];
        final articulosRows = [
          for (final p in ordered)
            [
              p.name,
              qty(p.units.toInt()),
              '${p.sales}',
              money(p.net),
            ],
        ];

        final range = ref.read(reportDateRangeProvider);
        _publishExport(
          ref,
          fileBaseName: 'articulos_resumen',
          build: () => ReportExportData(
            title: 'Artículos — Resumen del período',
            dateFrom: range.from,
            dateTo: range.to,
            sections: [
              ReportSection(
                table: ReportTable(
                  columns: articulosCols,
                  rows: articulosRows,
                  numericColumns: const {1, 2, 3},
                ),
              ),
            ],
          ),
        );

        return _ReportCard(
          title: 'Artículos — Resumen del período',
          child: _SimpleTable(
            columns: articulosCols,
            rows: articulosRows,
          ),
        );
      },
    );
  }
}

class _ItemAgg {
  _ItemAgg({required this.name});
  final String name;
  double units = 0;
  double gross = 0;
  double net = 0;
  int sales = 0;
}

class _CategoriasReport extends ConsumerWidget {
  const _CategoriasReport({required this.mode});
  final ReportMode mode;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(salesByCategoryReportProvider);
    return async.when(
      loading: () => const _LoadingBox(),
      error: (e, _) => ErrorCard(
        message: 'No se pudieron cargar las categorías: $e',
        onRetry: () => ref.invalidate(salesByCategoryReportProvider),
      ),
      data: (rows) {
        final byCat = <String, _CatAgg>{};
        for (final r in rows) {
          byCat.update(
            r.categoryName,
            (a) {
              a.units += r.unitsSold;
              a.net += r.netTotal;
              return a;
            },
            ifAbsent: () => _CatAgg()
              ..units = r.unitsSold
              ..net = r.netTotal,
          );
        }
        final entries = byCat.entries.toList()
          ..sort((a, b) => b.value.net.compareTo(a.value.net));

        if (mode == ReportMode.graphic) {
          return _ReportCard(
            title: 'Categorías — Ventas por categoría',
            child: _SimpleBarChart(
              points: [
                for (final e in entries)
                  (label: e.key, value: e.value.net),
              ],
              color: ReportCategory.categorias.group.accent,
            ),
          );
        }
        const catColumns = ['Categoría', 'Unidades', 'Neto'];
        final catRows = [
          for (final e in entries)
            [e.key, qty(e.value.units.toInt()), money(e.value.net)],
        ];

        final range = ref.read(reportDateRangeProvider);
        _publishExport(
          ref,
          fileBaseName: 'categorias_resumen',
          build: () => ReportExportData(
            title: 'Categorías — Resumen',
            dateFrom: range.from,
            dateTo: range.to,
            sections: [
              ReportSection(
                table: ReportTable(
                  columns: catColumns,
                  rows: catRows,
                  numericColumns: const {1, 2},
                ),
              ),
            ],
          ),
        );

        return _ReportCard(
          title: 'Categorías — Resumen',
          child: _SimpleTable(
            columns: catColumns,
            rows: catRows,
          ),
        );
      },
    );
  }
}

class _CatAgg {
  double units = 0;
  double net = 0;
}

/// Sub-modo del reporte de Precios: lista vigente o historial de cambios.
final preciosViewProvider = StateProvider<_PreciosView>(
  (ref) => _PreciosView.actual,
);

enum _PreciosView { actual, historial }

class _PreciosReport extends ConsumerWidget {
  const _PreciosReport();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final view = ref.watch(preciosViewProvider);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _PreciosViewToggle(value: view),
        const SizedBox(height: AppTokens.s12),
        if (view == _PreciosView.actual)
          const _PreciosActualSection()
        else
          const _PreciosHistorialSection(),
      ],
    );
  }
}

class _PreciosViewToggle extends ConsumerWidget {
  const _PreciosViewToggle({required this.value});
  final _PreciosView value;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return SegmentedButton<_PreciosView>(
      segments: const [
        ButtonSegment(
          value: _PreciosView.actual,
          icon: Icon(Icons.price_check_outlined, size: 16),
          label: Text('Lista actual'),
        ),
        ButtonSegment(
          value: _PreciosView.historial,
          icon: Icon(Icons.history, size: 16),
          label: Text('Historial de cambios'),
        ),
      ],
      selected: {value},
      onSelectionChanged: (s) =>
          ref.read(preciosViewProvider.notifier).state = s.first,
      showSelectedIcon: false,
    );
  }
}

class _PreciosActualSection extends ConsumerWidget {
  const _PreciosActualSection();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(currentPricesReportProvider);
    return async.when(
      loading: () => const _LoadingBox(),
      error: (e, _) => ErrorCard(
        message: 'No se pudieron cargar los precios: $e',
        onRetry: () => ref.invalidate(currentPricesReportProvider),
      ),
      data: (rows) {
        const preciosCols = ['Producto', 'SKU', 'Costo', 'Precio', 'Margen'];
        final preciosRows = [
          for (final r in rows)
            [
              r.name,
              r.sku ?? '—',
              money(r.cost),
              money(r.price),
              r.marginPct == null ? '—' : '${r.marginPct!.toStringAsFixed(1)}%',
            ],
        ];

        _publishExport(
          ref,
          fileBaseName: 'precios_actuales',
          build: () => ReportExportData(
            title: 'Precios — Lista actual',
            sections: [
              ReportSection(
                table: ReportTable(
                  columns: preciosCols,
                  rows: preciosRows,
                  numericColumns: const {2, 3, 4},
                ),
              ),
            ],
          ),
        );

        return _ReportCard(
          title: 'Precios — Lista actual',
          child: _SimpleTable(columns: preciosCols, rows: preciosRows),
        );
      },
    );
  }
}

class _PreciosHistorialSection extends ConsumerWidget {
  const _PreciosHistorialSection();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(priceHistoryReportProvider);
    return async.when(
      loading: () => const _LoadingBox(),
      error: (e, _) => ErrorCard(
        message: 'No se pudo cargar el historial: $e',
        onRetry: () => ref.invalidate(priceHistoryReportProvider),
      ),
      data: (rows) {
        const histCols = [
          'Fecha',
          'Producto',
          'Costo ant.',
          'Costo nuevo',
          'Δ Costo',
          'Precio ant.',
          'Precio nuevo',
          'Δ Precio',
          'Por',
        ];
        final histRows = [
          for (final r in rows)
            [
              formatDateTime(r.changedAt),
              r.productName,
              r.oldCost == null ? '—' : money(r.oldCost!),
              r.newCost == null ? '—' : money(r.newCost!),
              r.costPctChange == null
                  ? '—'
                  : '${r.costPctChange! >= 0 ? '+' : ''}${r.costPctChange!.toStringAsFixed(1)}%',
              r.oldPrice == null ? '—' : money(r.oldPrice!),
              r.newPrice == null ? '—' : money(r.newPrice!),
              r.pricePctChange == null
                  ? '—'
                  : '${r.pricePctChange! >= 0 ? '+' : ''}${r.pricePctChange!.toStringAsFixed(1)}%',
              r.changedByName ?? '—',
            ],
        ];

        final range = ref.read(reportDateRangeProvider);
        _publishExport(
          ref,
          fileBaseName: 'precios_historial',
          build: () => ReportExportData(
            title: 'Precios — Historial de cambios',
            subtitle: 'Cambios registrados en el período',
            dateFrom: range.from,
            dateTo: range.to,
            sections: [
              ReportSection(
                table: ReportTable(
                  columns: histCols,
                  rows: histRows,
                  numericColumns: const {2, 3, 4, 5, 6, 7},
                ),
                note: rows.isEmpty
                    ? 'No se registraron cambios de precio/costo en el período seleccionado.'
                    : null,
              ),
            ],
          ),
        );

        return _ReportCard(
          title: 'Precios — Historial de cambios',
          child: rows.isEmpty
              ? const EmptyStateCard(
                  icon: Icons.history,
                  message:
                      'No se registraron cambios de precio/costo en el período seleccionado.',
                )
              : _SimpleTable(columns: histCols, rows: histRows),
        );
      },
    );
  }
}

class _MermasReport extends ConsumerWidget {
  const _MermasReport({required this.mode});
  final ReportMode mode;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(inventoryMovementsReportProvider);
    return async.when(
      loading: () => const _LoadingBox(),
      error: (e, _) => ErrorCard(
        message: 'No se pudieron cargar las mermas: $e',
        onRetry: () => ref.invalidate(inventoryMovementsReportProvider),
      ),
      data: (rows) {
        final byType = <String, double>{};
        for (final r in rows) {
          byType.update(r.movementType, (v) => v + r.totalCost,
              ifAbsent: () => r.totalCost);
        }
        if (mode == ReportMode.graphic) {
          return _ReportCard(
            title: 'Mermas — Costo por tipo',
            child: _SimpleBarChart(
              points: [
                for (final e in byType.entries)
                  (label: _movementLabel(e.key), value: e.value),
              ],
              color: ReportCategory.mermas.group.accent,
            ),
          );
        }
        final total = rows.fold<double>(0, (s, r) => s + r.totalCost);

        const mermasCols = ['Fecha', 'Tipo', 'Cantidad', 'Costo'];
        final mermasRows = [
          for (final r in rows)
            [
              formatDate(r.movementDay),
              _movementLabel(r.movementType),
              qty(r.totalQuantity.toInt()),
              money(r.totalCost),
            ],
        ];

        final range = ref.read(reportDateRangeProvider);
        _publishExport(
          ref,
          fileBaseName: 'mermas',
          build: () => ReportExportData(
            title: 'Mermas — Resumen',
            dateFrom: range.from,
            dateTo: range.to,
            sections: [
              ReportSection(
                table: ReportTable(
                  columns: mermasCols,
                  rows: mermasRows,
                  numericColumns: const {2, 3},
                ),
                totals: [
                  ReportKv('Movimientos', '${rows.length}'),
                  ReportKv('Costo perdido', money(total), highlight: true),
                ],
              ),
            ],
          ),
        );

        return _ReportCard(
          title: 'Mermas — Resumen',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _SimpleTable(columns: mermasCols, rows: mermasRows),
              const Divider(),
              _TotalsRow(items: {
                'Movimientos': '${rows.length}',
                'Costo perdido': money(total),
              }),
            ],
          ),
        );
      },
    );
  }

  static String _movementLabel(String type) {
    switch (type) {
      case 'waste':
        return 'Desperdicio';
      case 'breakage':
        return 'Quiebre';
      case 'expired':
        return 'Vencido';
      case 'kitchen_return':
        return 'Devolución cocina';
      default:
        return type;
    }
  }
}

class _PlReport extends ConsumerWidget {
  const _PlReport();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(plReportProvider);
    return async.when(
      loading: () => const _LoadingBox(),
      error: (e, _) => ErrorCard(
        message: 'No se pudo calcular P&L: $e',
        onRetry: () => ref.invalidate(plReportProvider),
      ),
      data: (data) {
        double d(String k) => (data[k] as num?)?.toDouble() ?? 0;

        final range = ref.read(reportDateRangeProvider);
        _publishExport(
          ref,
          fileBaseName: 'pyg',
          build: () => ReportExportData(
            title: 'Pérdidas y Ganancias',
            dateFrom: range.from,
            dateTo: range.to,
            sections: [
              ReportSection(
                title: 'Resultado operativo',
                kv: [
                  ReportKv('Ingresos (ventas)', money(d('revenue'))),
                  ReportKv('— COGS (costo de venta)', money(d('cogs'))),
                  ReportKv('— Devoluciones', money(d('returns'))),
                  ReportKv('Utilidad bruta', money(d('gross_profit'))),
                  ReportKv('— Gastos', money(d('expenses'))),
                  ReportKv(
                    'UTILIDAD NETA',
                    money(d('net_profit')),
                    highlight: true,
                  ),
                ],
              ),
              ReportSection(
                title: 'Impuestos',
                kv: [
                  ReportKv('ITBIS recibido', money(d('tax_received'))),
                  ReportKv('ITBIS pagado', money(d('tax_paid'))),
                  ReportKv(
                    'Balance ITBIS',
                    money(d('tax_balance')),
                    highlight: true,
                  ),
                ],
              ),
            ],
          ),
        );

        return _ReportCard(
          title: 'Pérdidas y Ganancias',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _KVRow('Ingresos (ventas)', money(d('revenue'))),
              _KVRow('— COGS (costo de venta)', money(d('cogs'))),
              _KVRow('— Devoluciones', money(d('returns'))),
              const Divider(),
              _KVRow('Utilidad bruta', money(d('gross_profit'))),
              _KVRow('— Gastos', money(d('expenses'))),
              const Divider(),
              _KVRow('UTILIDAD NETA', money(d('net_profit'))),
              const SizedBox(height: AppTokens.s12),
              Text(
                'Impuestos',
                style: Theme.of(context).textTheme.labelMedium?.copyWith(
                      color: AppTokens.mutedForeground,
                    ),
              ),
              _KVRow('ITBIS recibido', money(d('tax_received'))),
              _KVRow('ITBIS pagado', money(d('tax_paid'))),
              _KVRow('Balance ITBIS', money(d('tax_balance'))),
            ],
          ),
        );
      },
    );
  }
}

class _CreditoReport extends ConsumerWidget {
  const _CreditoReport();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(creditAgingReportProvider);
    return async.when(
      loading: () => const _LoadingBox(),
      error: (e, _) => ErrorCard(
        message: 'No se pudo cargar crédito: $e',
        onRetry: () => ref.invalidate(creditAgingReportProvider),
      ),
      data: (rows) {
        final buckets = <String, double>{'0-30': 0, '31-60': 0, '61-90': 0, '+90': 0};
        for (final r in rows) {
          if (buckets.containsKey(r.agingBucket)) {
            buckets[r.agingBucket] = buckets[r.agingBucket]! + r.balanceDue;
          }
        }
        final total = rows.fold<double>(0, (s, r) => s + r.balanceDue);

        const creditoCols = [
          'Cliente',
          'Saldo',
          'Límite',
          'Días',
          'Bucket',
        ];
        final creditoRows = [
          for (final r in rows)
            [
              r.clientName,
              money(r.balanceDue),
              money(r.creditLimit),
              r.daysOverdue?.toString() ?? '—',
              r.agingBucket,
            ],
        ];

        _publishExport(
          ref,
          fileBaseName: 'credito_antiguedad',
          build: () => ReportExportData(
            title: 'Crédito — Antigüedad de saldos',
            sections: [
              ReportSection(
                title: 'Buckets',
                kv: [
                  for (final e in buckets.entries) ReportKv(e.key, money(e.value)),
                ],
              ),
              ReportSection(
                table: ReportTable(
                  columns: creditoCols,
                  rows: creditoRows,
                  numericColumns: const {1, 2, 3},
                ),
                totals: [
                  ReportKv('Cuentas con saldo', '${rows.length}'),
                  ReportKv('Total por cobrar', money(total), highlight: true),
                ],
              ),
            ],
          ),
        );

        return _ReportCard(
          title: 'Crédito — Antigüedad de saldos',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _SimpleBarChart(
                points: [
                  for (final e in buckets.entries)
                    (label: e.key, value: e.value),
                ],
                color: ReportCategory.credito.group.accent,
              ),
              const SizedBox(height: AppTokens.s12),
              _SimpleTable(
                columns: const [
                  'Cliente',
                  'Saldo',
                  'Límite',
                  'Días',
                  'Bucket',
                ],
                rows: [
                  for (final r in rows)
                    [
                      r.clientName,
                      money(r.balanceDue),
                      money(r.creditLimit),
                      r.daysOverdue?.toString() ?? '—',
                      r.agingBucket,
                    ],
                ],
              ),
              const Divider(),
              _TotalsRow(items: {
                'Cuentas con saldo': '${rows.length}',
                'Total por cobrar': money(total),
              }),
            ],
          ),
        );
      },
    );
  }
}

class _GastosReport extends ConsumerWidget {
  const _GastosReport({required this.mode});
  final ReportMode mode;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(expensesReportProvider);
    return async.when(
      loading: () => const _LoadingBox(),
      error: (e, _) => ErrorCard(
        message: 'No se pudieron cargar los gastos: $e',
        onRetry: () => ref.invalidate(expensesReportProvider),
      ),
      data: (rows) {
        final byCat = <String, double>{};
        for (final r in rows) {
          byCat.update(r.category, (v) => v + r.total,
              ifAbsent: () => r.total);
        }
        if (mode == ReportMode.graphic) {
          return _ReportCard(
            title: 'Gastos — Total por categoría',
            child: _SimpleBarChart(
              points: [
                for (final e in byCat.entries)
                  (label: e.key, value: e.value),
              ],
              color: ReportCategory.gastos.group.accent,
            ),
          );
        }
        final total = rows.fold<double>(0, (s, r) => s + r.total);

        const gastosCols = ['Fecha', 'Categoría', 'Transacciones', 'Total'];
        final gastosRows = [
          for (final r in rows)
            [
              formatDate(r.expenseDate),
              r.category,
              '${r.count}',
              money(r.total),
            ],
        ];

        final range = ref.read(reportDateRangeProvider);
        _publishExport(
          ref,
          fileBaseName: 'gastos',
          build: () => ReportExportData(
            title: 'Gastos — Resumen',
            dateFrom: range.from,
            dateTo: range.to,
            sections: [
              ReportSection(
                table: ReportTable(
                  columns: gastosCols,
                  rows: gastosRows,
                  numericColumns: const {2, 3},
                ),
                totals: [
                  ReportKv('Total gastado', money(total), highlight: true),
                ],
              ),
            ],
          ),
        );

        return _ReportCard(
          title: 'Gastos — Resumen',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _SimpleTable(columns: gastosCols, rows: gastosRows),
              const Divider(),
              _TotalsRow(items: {'Total gastado': money(total)}),
            ],
          ),
        );
      },
    );
  }
}

class _ComprasReport extends ConsumerWidget {
  const _ComprasReport({required this.mode});
  final ReportMode mode;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(purchasesReportV2Provider);
    return async.when(
      loading: () => const _LoadingBox(),
      error: (e, _) => ErrorCard(
        message: 'No se pudieron cargar las compras: $e',
        onRetry: () => ref.invalidate(purchasesReportV2Provider),
      ),
      data: (rows) {
        if (mode == ReportMode.graphic) {
          final byDay = <String, double>{};
          for (final r in rows) {
            final key = formatDate(r.purchaseDate);
            byDay.update(key, (v) => v + r.grandTotal,
                ifAbsent: () => r.grandTotal);
          }
          return _ReportCard(
            title: 'Compras — Total por día',
            child: _SimpleBarChart(
              points: [
                for (final e in byDay.entries)
                  (label: e.key, value: e.value),
              ],
              color: ReportCategory.compras.group.accent,
            ),
          );
        }
        final total = rows.fold<double>(0, (s, r) => s + r.grandTotal);

        const comprasCols = [
          'Fecha',
          'Proveedor',
          'Compras',
          'Subtotal',
          'ITBIS',
          'Total',
        ];
        final comprasRows = [
          for (final r in rows)
            [
              formatDate(r.purchaseDate),
              r.supplierName,
              '${r.purchasesCount}',
              money(r.subtotalTotal),
              money(r.taxTotal),
              money(r.grandTotal),
            ],
        ];

        final range = ref.read(reportDateRangeProvider);
        _publishExport(
          ref,
          fileBaseName: 'compras',
          build: () => ReportExportData(
            title: 'Compras — Resumen',
            dateFrom: range.from,
            dateTo: range.to,
            sections: [
              ReportSection(
                table: ReportTable(
                  columns: comprasCols,
                  rows: comprasRows,
                  numericColumns: const {2, 3, 4, 5},
                ),
                totals: [
                  ReportKv('Documentos', '${rows.length}'),
                  ReportKv('Total comprado', money(total), highlight: true),
                ],
              ),
            ],
          ),
        );

        return _ReportCard(
          title: 'Compras — Resumen',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _SimpleTable(columns: comprasCols, rows: comprasRows),
              const Divider(),
              _TotalsRow(items: {
                'Documentos': '${rows.length}',
                'Total comprado': money(total),
              }),
            ],
          ),
        );
      },
    );
  }
}

class _ProveedoresReport extends ConsumerWidget {
  const _ProveedoresReport();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(suppliersReportProvider);
    return async.when(
      loading: () => const _LoadingBox(),
      error: (e, _) => ErrorCard(
        message: 'No se pudieron cargar proveedores: $e',
        onRetry: () => ref.invalidate(suppliersReportProvider),
      ),
      data: (rows) {
        final totalDebt = rows.fold<double>(0, (s, r) => s + r.outstandingAmount);

        const provCols = [
          'Proveedor',
          'RNC',
          'Compras',
          'Total',
          'Pendiente',
          'Última',
        ];
        final provRows = [
          for (final r in rows)
            [
              r.supplierName,
              r.rnc ?? '—',
              '${r.purchasesCount}',
              money(r.purchasesTotal),
              money(r.outstandingAmount),
              r.lastPurchaseAt == null ? '—' : formatDate(r.lastPurchaseAt!),
            ],
        ];

        _publishExport(
          ref,
          fileBaseName: 'proveedores',
          build: () => ReportExportData(
            title: 'Proveedores',
            sections: [
              ReportSection(
                table: ReportTable(
                  columns: provCols,
                  rows: provRows,
                  numericColumns: const {2, 3, 4},
                ),
                totals: [
                  ReportKv('Proveedores', '${rows.length}'),
                  ReportKv('Deuda pendiente', money(totalDebt), highlight: true),
                ],
              ),
            ],
          ),
        );

        return _ReportCard(
          title: 'Proveedores',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _SimpleTable(columns: provCols, rows: provRows),
              const Divider(),
              _TotalsRow(items: {
                'Proveedores': '${rows.length}',
                'Deuda pendiente': money(totalDebt),
              }),
            ],
          ),
        );
      },
    );
  }
}

class _ClientesReport extends ConsumerWidget {
  const _ClientesReport();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(clientsReportProvider);
    return async.when(
      loading: () => const _LoadingBox(),
      error: (e, _) => ErrorCard(
        message: 'No se pudieron cargar los clientes: $e',
        onRetry: () => ref.invalidate(clientsReportProvider),
      ),
      data: (rows) {
        final totalSales = rows.fold<double>(0, (s, r) => s + r.salesTotal);

        const cliCols = [
          'Cliente',
          'Ventas',
          'Total',
          'Ticket prom.',
          'Saldo',
          'Última',
        ];
        final cliRows = [
          for (final r in rows)
            [
              r.clientName,
              '${r.salesCount}',
              money(r.salesTotal),
              money(r.avgTicket),
              money(r.balanceDue),
              r.lastSaleAt == null ? '—' : formatDate(r.lastSaleAt!),
            ],
        ];

        _publishExport(
          ref,
          fileBaseName: 'clientes',
          build: () => ReportExportData(
            title: 'Clientes — Top y frecuencia',
            sections: [
              ReportSection(
                table: ReportTable(
                  columns: cliCols,
                  rows: cliRows,
                  numericColumns: const {1, 2, 3, 4},
                ),
                totals: [
                  ReportKv('Clientes', '${rows.length}'),
                  ReportKv('Ventas totales', money(totalSales), highlight: true),
                ],
              ),
            ],
          ),
        );

        return _ReportCard(
          title: 'Clientes — Top y frecuencia',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _SimpleTable(columns: cliCols, rows: cliRows),
              const Divider(),
              _TotalsRow(items: {
                'Clientes': '${rows.length}',
                'Ventas totales': money(totalSales),
              }),
            ],
          ),
        );
      },
    );
  }
}

class _DescuentosReport extends ConsumerWidget {
  const _DescuentosReport();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(discountsReportProvider);
    return async.when(
      loading: () => const _LoadingBox(),
      error: (e, _) => ErrorCard(
        message: 'No se pudieron cargar los descuentos: $e',
        onRetry: () => ref.invalidate(discountsReportProvider),
      ),
      data: (rows) {
        final total = rows.fold<double>(0, (s, r) => s + r.discountAmount);

        const descCols = [
          'Fecha',
          '#',
          'Cliente',
          'Cajero',
          'Subtotal',
          'Desc.',
          '%',
        ];
        final descRows = [
          for (final r in rows)
            [
              formatDate(r.saleDate),
              r.saleNumber,
              r.clientName ?? '—',
              r.cashierName ?? '—',
              money(r.subtotal),
              money(r.discountAmount),
              '${r.discountPct.toStringAsFixed(1)}%',
            ],
        ];

        final range = ref.read(reportDateRangeProvider);
        _publishExport(
          ref,
          fileBaseName: 'descuentos',
          build: () => ReportExportData(
            title: 'Descuentos aplicados',
            dateFrom: range.from,
            dateTo: range.to,
            sections: [
              ReportSection(
                table: ReportTable(
                  columns: descCols,
                  rows: descRows,
                  numericColumns: const {4, 5, 6},
                ),
                totals: [
                  ReportKv('Descuentos', '${rows.length}'),
                  ReportKv('Total descontado', money(total), highlight: true),
                ],
              ),
            ],
          ),
        );

        return _ReportCard(
          title: 'Descuentos aplicados',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _SimpleTable(columns: descCols, rows: descRows),
              const Divider(),
              _TotalsRow(items: {
                'Descuentos': '${rows.length}',
                'Total descontado': money(total),
              }),
            ],
          ),
        );
      },
    );
  }
}

// ═════════════════════════════════════════════════════════════════════════
// ROUND 3 — DGII fiscal (606 / 607 / IT-1 / Cierre Z / Impuestos)
// ═════════════════════════════════════════════════════════════════════════

class _DgiiYearMonthPicker extends ConsumerWidget {
  const _DgiiYearMonthPicker();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final year = ref.watch(dgiiYearProvider);
    final month = ref.watch(dgiiMonthProvider);
    final now = DateTime.now();
    final years = [for (var y = now.year - 5; y <= now.year; y++) y];
    return Card(
      margin: const EdgeInsets.only(bottom: AppTokens.s12),
      child: Padding(
        padding: const EdgeInsets.all(AppTokens.s12),
        child: Wrap(
          spacing: AppTokens.s12,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            const Text('Período fiscal:',
                style: TextStyle(fontWeight: FontWeight.w700)),
            DropdownButton<int>(
              value: year,
              items: [for (final y in years) DropdownMenuItem(value: y, child: Text('$y'))],
              onChanged: (v) {
                if (v != null) ref.read(dgiiYearProvider.notifier).state = v;
              },
            ),
            DropdownButton<int>(
              value: month,
              items: [
                for (var m = 1; m <= 12; m++)
                  DropdownMenuItem(value: m, child: Text(_monthName(m))),
              ],
              onChanged: (v) {
                if (v != null) ref.read(dgiiMonthProvider.notifier).state = v;
              },
            ),
          ],
        ),
      ),
    );
  }

  static String _monthName(int m) {
    const names = [
      'Enero', 'Febrero', 'Marzo', 'Abril', 'Mayo', 'Junio',
      'Julio', 'Agosto', 'Septiembre', 'Octubre', 'Noviembre', 'Diciembre',
    ];
    return names[m - 1];
  }
}

/// ESTADO DE DIARIO — todas las ventas del período, día por día.
///
/// Es lo que el negocio le manda al contable a fin de mes: cada venta con su
/// NCF, cliente, subtotal, ITBIS y total, con el corte de cada día y el total
/// general. Se descarga en CSV, que abre directo en Excel.
///
/// No depende de las funciones fiscales (606/607): sale de `sales` a través
/// de `fetchDetailedSales`, que ya existía.
class _EstadoDiarioReport extends ConsumerWidget {
  const _EstadoDiarioReport();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(detailedSalesReportProvider);
    final range = ref.watch(reportDateRangeProvider);

    return async.when(
      loading: () => const Padding(
        padding: EdgeInsets.all(AppTokens.s32),
        child: Center(child: CircularProgressIndicator()),
      ),
      error: (e, _) => ErrorCard(
        message: 'No se pudo cargar el estado de diario: $e',
        onRetry: () => ref.invalidate(detailedSalesReportProvider),
      ),
      data: (rows) {
        // Solo ventas que existen fiscalmente: las anuladas no se declaran.
        final vivas = rows
            .where((r) => r.status != 'voided')
            .toList(growable: false)
          ..sort((a, b) => a.saleDate.compareTo(b.saleDate));

        final porDia = <DateTime, List<SaleDetailRow>>{};
        for (final r in vivas) {
          final dia = DateTime(r.saleDate.year, r.saleDate.month, r.saleDate.day);
          porDia.putIfAbsent(dia, () => []).add(r);
        }
        final dias = porDia.keys.toList()..sort();

        final subtotal = vivas.fold<double>(0, (s, r) => s + r.subtotal);
        final itbis = vivas.fold<double>(0, (s, r) => s + r.taxAmount);
        final total = vivas.fold<double>(0, (s, r) => s + r.totalAmount);
        final sinNcf = vivas.where((r) => (r.ncf ?? '').trim().isEmpty).length;

        return _ReportCard(
          title: 'Estado de Diario · ${formatDate(range.from)} a '
              '${formatDate(range.to)}',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Wrap(
                spacing: AppTokens.s12,
                runSpacing: AppTokens.s8,
                children: [
                  _MiniStat(label: 'Ventas', value: '${vivas.length}'),
                  _MiniStat(label: 'Días con ventas', value: '${dias.length}'),
                  _MiniStat(label: 'Subtotal', value: money(subtotal)),
                  _MiniStat(label: 'ITBIS', value: money(itbis)),
                  _MiniStat(label: 'Total', value: money(total)),
                ],
              ),
              if (sinNcf > 0) ...[
                const SizedBox(height: AppTokens.s12),
                Text(
                  '$sinNcf venta(s) sin NCF. Aparecen en el archivo para que '
                  'las revises, pero no son declarables como comprobante fiscal.',
                  style: const TextStyle(
                    color: AppTokens.warning,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
              const SizedBox(height: AppTokens.s12),
              Row(
                children: [
                  FilledButton.icon(
                    onPressed: vivas.isEmpty
                        ? null
                        : () async {
                            final messenger = ScaffoldMessenger.of(context);
                            final csv = buildEstadoDiarioCsv(dias, porDia);
                            final nombre = 'estado_diario_'
                                '${range.fromIso}_a_${range.toIso}';
                            final ok = await FileIoHelper.saveBytes(
                              // BOM UTF-8: sin esto Excel en Windows muestra
                              // los acentos rotos.
                              bytes: Uint8List.fromList(
                                [0xEF, 0xBB, 0xBF, ...utf8.encode(csv)],
                              ),
                              fileName: '$nombre.csv',
                              extension: 'csv',
                              dialogTitle: 'Guardar estado de diario',
                            );
                            if (!ok) return;
                            messenger.showSnackBar(
                              SnackBar(
                                backgroundColor: AppTokens.success,
                                content: Text(
                                  '$nombre.csv descargado '
                                  '(${vivas.length} ventas).',
                                  style: const TextStyle(
                                      color: AppTokens.successForeground),
                                ),
                              ),
                            );
                          },
                    icon: const Icon(Icons.download_rounded, size: 18),
                    label: const Text('Descargar CSV'),
                  ),
                ],
              ),
              const SizedBox(height: AppTokens.s16),
              for (final dia in dias) ...[
                _DiaHeader(dia: dia, ventas: porDia[dia]!),
                _SimpleTable(
                  columns: const [
                    'Venta',
                    'NCF',
                    'Cliente',
                    'Subtotal',
                    'ITBIS',
                    'Total',
                    'Estado',
                  ],
                  rows: [
                    for (final r in porDia[dia]!)
                      [
                        r.saleNumber,
                        (r.ncf ?? '').trim().isEmpty ? '—' : r.ncf!,
                        r.clientName ?? 'Consumidor Final',
                        money(r.subtotal),
                        money(r.taxAmount),
                        money(r.totalAmount),
                        r.status == 'credit' ? 'A crédito' : 'Pagada',
                      ],
                  ],
                ),
                const SizedBox(height: AppTokens.s16),
              ],
            ],
          ),
        );
      },
    );
  }
}

/// Encabezado de cada día con su corte: cuántas ventas y cuánto sumaron.
class _DiaHeader extends StatelessWidget {
  const _DiaHeader({required this.dia, required this.ventas});

  final DateTime dia;
  final List<SaleDetailRow> ventas;

  @override
  Widget build(BuildContext context) {
    final total = ventas.fold<double>(0, (s, r) => s + r.totalAmount);
    final itbis = ventas.fold<double>(0, (s, r) => s + r.taxAmount);

    return Padding(
      padding: const EdgeInsets.only(bottom: AppTokens.s8),
      child: Row(
        children: [
          Expanded(
            child: Text(
              formatDate(dia),
              style: Theme.of(context).textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w800,
                    color: AppTokens.brandBlueDark,
                  ),
            ),
          ),
          Text(
            '${ventas.length} venta(s) · ITBIS ${money(itbis)} · '
            'Total ${money(total)}',
            style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: AppTokens.textSecondary,
            ),
          ),
        ],
      ),
    );
  }
}

/// Cifra suelta del encabezado del reporte.
class _MiniStat extends StatelessWidget {
  const _MiniStat({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppTokens.s12,
        vertical: AppTokens.s8,
      ),
      decoration: BoxDecoration(
        color: AppTokens.secondary,
        borderRadius: BorderRadius.circular(AppTokens.radiusM),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(label,
              style: const TextStyle(
                  fontSize: 11, color: AppTokens.textSecondary)),
          Text(value,
              style: const TextStyle(
                  fontSize: 15, fontWeight: FontWeight.w800)),
        ],
      ),
    );
  }
}

/// Serializa los rows del 606 al formato TXT pipe-separated de DGII.
String _build606Txt(Map<String, dynamic> data) {
  final rnc = (data['rnc_negocio'] ?? '').toString();
  final period = (data['period'] ?? '').toString();
  final rows = (data['rows'] as List?) ?? const [];
  final buf = StringBuffer();
  buf.writeln('606|$rnc|$period|${rows.length}');
  for (final raw in rows) {
    final r = raw as Map;
    buf.writeln([
      r['rnc_proveedor'] ?? '',
      r['tipo_id'] ?? '',
      r['tipo_bien_servicio'] ?? '',
      r['ncf'] ?? '',
      r['ncf_modificado'] ?? '',
      r['fecha_comprobante'] ?? '',
      r['fecha_pago'] ?? '',
      r['monto_facturado'] ?? 0,
      r['itbis_facturado'] ?? 0,
    ].join('|'));
  }
  return buf.toString();
}

String _build607Txt(Map<String, dynamic> data) {
  final rnc = (data['rnc_negocio'] ?? '').toString();
  final period = (data['period'] ?? '').toString();
  final rows = (data['rows'] as List?) ?? const [];
  final buf = StringBuffer();
  buf.writeln('607|$rnc|$period|${rows.length}');
  for (final raw in rows) {
    final r = raw as Map;
    buf.writeln([
      r['rnc_cliente'] ?? '',
      r['tipo_id'] ?? '',
      r['ncf'] ?? '',
      r['ncf_modificado'] ?? '',
      r['tipo_ingreso'] ?? '',
      r['fecha_comprobante'] ?? '',
      r['monto_facturado'] ?? 0,
      r['itbis_facturado'] ?? 0,
      r['efectivo'] ?? 0,
      r['credito'] ?? 0,
    ].join('|'));
  }
  return buf.toString();
}

class _DgiiReportSection extends StatelessWidget {
  const _DgiiReportSection({
    required this.title,
    required this.data,
    required this.txtBuilder,
    required this.fileName,
  });

  final String title;
  final Map<String, dynamic> data;
  final String Function(Map<String, dynamic>) txtBuilder;
  final String fileName;

  @override
  Widget build(BuildContext context) {
    final rnc = (data['rnc_negocio'] ?? '').toString();
    final period = (data['period'] ?? '').toString();
    final count = (data['records_count'] as num?)?.toInt() ?? 0;
    final inconsistencies =
        (data['inconsistencies'] as List?) ?? const [];
    final inconsistenciesCount =
        (data['inconsistencies_count'] as num?)?.toInt() ?? 0;
    final rows = (data['rows'] as List?) ?? const [];

    return _ReportCard(
      title: '$title · Período $period',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Wrap(
            spacing: AppTokens.s12,
            runSpacing: AppTokens.s8,
            children: [
              _DgiiBadge('RNC: ${rnc.isEmpty ? "no configurado" : rnc}',
                  isWarning: rnc.isEmpty),
              _DgiiBadge('Registros válidos: $count'),
              _DgiiBadge(
                'Inconsistencias: $inconsistenciesCount',
                isWarning: inconsistenciesCount > 0,
              ),
            ],
          ),
          if (rnc.isEmpty)
            Padding(
              padding: const EdgeInsets.only(top: AppTokens.s8),
              child: Text(
                'Falta configurar el RNC en /configuracion antes de generar.',
                style: TextStyle(color: AppTokens.warning),
              ),
            ),
          // Sin RNC configurado el TXT saldría con la cabecera vacía y DGII lo
          // rechaza. Se explica en vez de dejar un botón muerto sin motivo.
          if (rnc.isEmpty) ...[
            const SizedBox(height: AppTokens.s12),
            Container(
              padding: const EdgeInsets.all(AppTokens.s12),
              decoration: BoxDecoration(
                color: AppTokens.warning.withValues(alpha: 0.10),
                borderRadius: BorderRadius.circular(AppTokens.radiusM),
                border: Border.all(
                  color: AppTokens.warning.withValues(alpha: 0.35),
                ),
              ),
              child: const Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(Icons.warning_amber_rounded,
                      size: 18, color: AppTokens.warning),
                  SizedBox(width: AppTokens.s8),
                  Expanded(
                    child: Text(
                      'Tu empresa no tiene RNC configurado. DGII exige el RNC '
                      'del contribuyente en la primera línea del archivo. '
                      'Configúralo en Configuración → Datos de la empresa '
                      'para poder descargar.',
                      style: TextStyle(fontSize: 12, height: 1.35),
                    ),
                  ),
                ],
              ),
            ),
          ],
          const SizedBox(height: AppTokens.s12),
          Row(
            children: [
              FilledButton.icon(
                onPressed: rnc.isEmpty || count == 0
                    ? null
                    : () async {
                        final messenger = ScaffoldMessenger.of(context);
                        final txt = txtBuilder(data);
                        // Archivo real, no portapapeles: en web descarga, en
                        // escritorio abre "Guardar como", en móvil comparte.
                        // DGII pide el TXT en UTF-8.
                        final saved = await FileIoHelper.saveBytes(
                          bytes: Uint8List.fromList(utf8.encode(txt)),
                          fileName: '$fileName.txt',
                          extension: 'txt',
                          dialogTitle: 'Guardar $fileName para DGII',
                        );
                        if (!saved) return;
                        if (context.mounted) {
                          messenger.showSnackBar(
                            SnackBar(
                              backgroundColor: AppTokens.success,
                              content: Text(
                                '$fileName.txt descargado ($count registros). '
                                'Súbelo a la oficina virtual de DGII.',
                                style: const TextStyle(
                                    color: AppTokens.successForeground),
                              ),
                            ),
                          );
                        }
                      },
                icon: const Icon(Icons.download_rounded, size: 18),
                label: Text('Descargar TXT ($fileName)'),
              ),
            ],
          ),
          if (inconsistenciesCount > 0) ...[
            const SizedBox(height: AppTokens.s16),
            Text(
              'Inconsistencias (excluidas del TXT)',
              style: Theme.of(context).textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w700,
                    color: AppTokens.destructive,
                  ),
            ),
            _SimpleTable(
              columns: const ['Detalle', 'Motivo'],
              rows: [
                for (final raw in inconsistencies)
                  if (raw is Map)
                    [
                      (raw['sale_number'] ??
                              raw['invoice_number'] ??
                              raw['supplier_name'] ??
                              raw['client_name'] ??
                              '—')
                          .toString(),
                      (raw['reason'] ?? '').toString(),
                    ],
              ],
            ),
          ],
          const SizedBox(height: AppTokens.s16),
          Text(
            'Vista previa ($count registros)',
            style: Theme.of(context).textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
          ),
          _SimpleTable(
            columns: const ['NCF', 'Fecha', 'Documento', 'Monto', 'ITBIS'],
            rows: [
              for (final raw in rows.take(50))
                if (raw is Map)
                  [
                    (raw['ncf'] ?? '').toString(),
                    (raw['fecha_comprobante'] ?? '').toString(),
                    (raw['rnc_proveedor'] ?? raw['rnc_cliente'] ?? '—')
                        .toString(),
                    money((raw['monto_facturado'] as num?)?.toDouble() ?? 0),
                    money((raw['itbis_facturado'] as num?)?.toDouble() ?? 0),
                  ],
            ],
          ),
        ],
      ),
    );
  }
}

class _DgiiBadge extends StatelessWidget {
  const _DgiiBadge(this.label, {this.isWarning = false});
  final String label;
  final bool isWarning;

  @override
  Widget build(BuildContext context) {
    final color = isWarning ? AppTokens.warning : AppTokens.primary;
    return Container(
      padding: const EdgeInsets.symmetric(
          horizontal: AppTokens.s10, vertical: AppTokens.s6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(label,
          style: TextStyle(color: color, fontWeight: FontWeight.w700)),
    );
  }
}

class _Dgii606Report extends ConsumerWidget {
  const _Dgii606Report();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(dgii606Provider);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const _DgiiYearMonthPicker(),
        async.when(
          loading: () => const _LoadingBox(),
          error: (e, _) => ErrorCard(
            message: 'No se pudo generar 606: $e',
            onRetry: () => ref.invalidate(dgii606Provider),
          ),
          data: (data) {
            final year = ref.read(dgiiYearProvider);
            final month = ref.read(dgiiMonthProvider);
            _publishDgiiExport(
              ref,
              data: data,
              year: year,
              month: month,
              fileBaseName: 'dgii_606',
              title: '606 — Compras DGII',
              proveedorOrCliente: 'Proveedor',
            );
            return _DgiiReportSection(
              title: '606 — Compras DGII',
              data: data,
              txtBuilder: _build606Txt,
              fileName:
                  'DGII_F_606_${(data['rnc_negocio'] ?? '').toString()}_'
                  '$year${month.toString().padLeft(2, "0")}.TXT',
            );
          },
        ),
      ],
    );
  }
}

class _Dgii607Report extends ConsumerWidget {
  const _Dgii607Report();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(dgii607Provider);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const _DgiiYearMonthPicker(),
        async.when(
          loading: () => const _LoadingBox(),
          error: (e, _) => ErrorCard(
            message: 'No se pudo generar 607: $e',
            onRetry: () => ref.invalidate(dgii607Provider),
          ),
          data: (data) {
            final year = ref.read(dgiiYearProvider);
            final month = ref.read(dgiiMonthProvider);
            _publishDgiiExport(
              ref,
              data: data,
              year: year,
              month: month,
              fileBaseName: 'dgii_607',
              title: '607 — Ventas DGII',
              proveedorOrCliente: 'Cliente',
            );
            return _DgiiReportSection(
              title: '607 — Ventas DGII',
              data: data,
              txtBuilder: _build607Txt,
              fileName:
                  'DGII_F_607_${(data['rnc_negocio'] ?? '').toString()}_'
                  '$year${month.toString().padLeft(2, "0")}.TXT',
            );
          },
        ),
      ],
    );
  }
}

class _DgiiIt1Report extends ConsumerWidget {
  const _DgiiIt1Report();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(dgiiIt1Provider);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const _DgiiYearMonthPicker(),
        async.when(
          loading: () => const _LoadingBox(),
          error: (e, _) => ErrorCard(
            message: 'No se pudo generar IT-1: $e',
            onRetry: () => ref.invalidate(dgiiIt1Provider),
          ),
          data: (data) {
            double d(String k) => (data[k] as num?)?.toDouble() ?? 0;
            final balance = d('itbis_balance');
            final dir = (data['balance_direction'] ?? 'cero').toString();
            final period = (data['period'] ?? '').toString();

            _publishExport(
              ref,
              fileBaseName: 'dgii_it1_$period',
              build: () => ReportExportData(
                title: 'IT-1 · Resumen mensual de ITBIS',
                subtitle: 'Período $period',
                sections: [
                  ReportSection(
                    title: 'Ventas',
                    kv: [
                      ReportKv('Ventas totales', money(d('sales_total'))),
                      ReportKv('Base gravada', money(d('sales_taxable'))),
                      ReportKv('Base exenta', money(d('sales_exempt'))),
                      ReportKv('ITBIS recibido', money(d('itbis_received'))),
                    ],
                  ),
                  ReportSection(
                    title: 'Compras',
                    kv: [
                      ReportKv('Compras totales', money(d('purchases_total'))),
                      ReportKv('ITBIS pagado', money(d('itbis_paid'))),
                    ],
                  ),
                  ReportSection(
                    title: 'Devoluciones',
                    kv: [
                      ReportKv('Devoluciones', money(d('returns_total'))),
                      ReportKv('ITBIS devuelto', money(d('returns_itbis'))),
                    ],
                  ),
                  ReportSection(
                    title: 'Resultado',
                    kv: [
                      ReportKv(
                        dir == 'pagar'
                            ? 'ITBIS a pagar'
                            : dir == 'favor'
                                ? 'ITBIS a favor (saldo)'
                                : 'Balance neutro',
                        money(balance.abs()),
                        highlight: true,
                      ),
                    ],
                  ),
                ],
              ),
            );

            return _ReportCard(
              title: 'IT-1 · Período $period',
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    'Resumen mensual de ITBIS',
                    style: Theme.of(context).textTheme.titleSmall?.copyWith(
                          color: AppTokens.mutedForeground,
                        ),
                  ),
                  const SizedBox(height: AppTokens.s8),
                  _KVRow('Ventas totales', money(d('sales_total'))),
                  _KVRow('Base gravada', money(d('sales_taxable'))),
                  _KVRow('Base exenta', money(d('sales_exempt'))),
                  _KVRow('ITBIS recibido', money(d('itbis_received'))),
                  const Divider(),
                  _KVRow('Compras totales', money(d('purchases_total'))),
                  _KVRow('ITBIS pagado', money(d('itbis_paid'))),
                  const Divider(),
                  _KVRow('Devoluciones', money(d('returns_total'))),
                  _KVRow('ITBIS devuelto', money(d('returns_itbis'))),
                  const Divider(thickness: 2),
                  Container(
                    padding: const EdgeInsets.all(AppTokens.s12),
                    decoration: BoxDecoration(
                      color: dir == 'pagar'
                          ? AppTokens.destructive.withValues(alpha: 0.12)
                          : dir == 'favor'
                              ? AppTokens.success.withValues(alpha: 0.12)
                              : AppTokens.muted,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Text(
                          dir == 'pagar'
                              ? 'ITBIS a pagar'
                              : dir == 'favor'
                                  ? 'ITBIS a favor (saldo)'
                                  : 'Balance neutro',
                          style: TextStyle(
                            fontWeight: FontWeight.w800,
                            color: dir == 'pagar'
                                ? AppTokens.destructive
                                : dir == 'favor'
                                    ? AppTokens.success
                                    : AppTokens.foreground,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          money(balance.abs()),
                          style: const TextStyle(
                            fontSize: 24,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            );
          },
        ),
      ],
    );
  }
}

class _CierreZReport extends ConsumerWidget {
  const _CierreZReport();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(fiscalZClosuresProvider);
    return async.when(
      loading: () => const _LoadingBox(),
      error: (e, _) => ErrorCard(
        message: 'No se pudo cargar los cierres Z: $e',
        onRetry: () => ref.invalidate(fiscalZClosuresProvider),
      ),
      data: (rows) {
        const zCols = ['#', 'Emitido', 'Tipo', 'Total ventas'];
        final zRows = [
          for (final r in rows)
            [
              r.closureNumber.toString().padLeft(5, '0'),
              formatDateTime(r.emittedAt),
              r.isComplementary ? 'Complementario' : 'Primario',
              _zClosureTotal(r),
            ],
        ];

        _publishExport(
          ref,
          fileBaseName: 'cierre_z',
          build: () => ReportExportData(
            title: 'Cierre Z Fiscal — Historial',
            sections: [
              ReportSection(
                table: ReportTable(
                  columns: zCols,
                  rows: zRows,
                  numericColumns: const {3},
                ),
                note: rows.isEmpty
                    ? 'Aún no se han emitido cierres Z fiscales en esta sucursal.'
                    : null,
              ),
            ],
          ),
        );

        return _ReportCard(
          title: 'Cierre Z Fiscal — Historial',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'Los cierres Z son inmutables una vez sellados. Para emitir '
                'uno nuevo, cierra la sesión de caja desde /caja y usa el '
                'botón "Sellar Z" en la fila de la sesión cerrada.',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: AppTokens.mutedForeground,
                    ),
              ),
              const SizedBox(height: AppTokens.s12),
              if (rows.isEmpty)
                const EmptyStateCard(
                  icon: Icons.lock_outline,
                  message:
                      'Aún no se han emitido cierres Z fiscales en esta sucursal.',
                )
              else
                _ZClosureTable(rows: rows),
            ],
          ),
        );
      },
    );
  }

  static String _zClosureTotal(FiscalZClosureRow r) {
    final salesByType = r.payload['sales_by_receipt_type'];
    if (salesByType is! List) return '—';
    final total = salesByType.fold<double>(0, (s, item) {
      if (item is Map) {
        return s + ((item['total'] as num?)?.toDouble() ?? 0);
      }
      return s;
    });
    return money(total);
  }
}

class _ImpuestosReport extends ConsumerWidget {
  const _ImpuestosReport({required this.mode});
  final ReportMode mode;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(taxBreakdownV2Provider);
    return async.when(
      loading: () => const _LoadingBox(),
      error: (e, _) => ErrorCard(
        message: 'No se pudo cargar impuestos: $e',
        onRetry: () => ref.invalidate(taxBreakdownV2Provider),
      ),
      data: (rows) {
        final byRate = <double, _TaxAgg>{};
        for (final r in rows) {
          byRate.update(
            r.taxRate,
            (a) {
              a.taxableBase += r.taxableBase;
              a.taxAmount += r.taxAmount;
              return a;
            },
            ifAbsent: () => _TaxAgg()
              ..taxableBase = r.taxableBase
              ..taxAmount = r.taxAmount,
          );
        }
        final entries = byRate.entries.toList()..sort((a, b) => b.key.compareTo(a.key));

        if (mode == ReportMode.graphic) {
          return _ReportCard(
            title: 'Impuestos — Por tasa',
            child: _SimpleBarChart(
              points: [
                for (final e in entries)
                  (
                    label: '${e.key.toStringAsFixed(0)}%',
                    value: e.value.taxAmount,
                  ),
              ],
              color: ReportCategory.impuestos.group.accent,
            ),
          );
        }

        final totalTax = entries.fold<double>(0, (s, e) => s + e.value.taxAmount);

        const impCols = ['Tasa', 'Base gravada', 'Impuesto'];
        final impRows = [
          for (final e in entries)
            [
              '${e.key.toStringAsFixed(0)}%',
              money(e.value.taxableBase),
              money(e.value.taxAmount),
            ],
        ];

        final range = ref.read(reportDateRangeProvider);
        _publishExport(
          ref,
          fileBaseName: 'impuestos_itbis',
          build: () => ReportExportData(
            title: 'Impuestos — Desglose ITBIS',
            dateFrom: range.from,
            dateTo: range.to,
            sections: [
              ReportSection(
                table: ReportTable(
                  columns: impCols,
                  rows: impRows,
                  numericColumns: const {1, 2},
                ),
                totals: [
                  ReportKv('Total impuesto', money(totalTax), highlight: true),
                ],
              ),
            ],
          ),
        );

        return _ReportCard(
          title: 'Impuestos — Desglose ITBIS',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _SimpleTable(columns: impCols, rows: impRows),
              const Divider(),
              _TotalsRow(items: {'Total impuesto': money(totalTax)}),
            ],
          ),
        );
      },
    );
  }
}

class _TaxAgg {
  double taxableBase = 0;
  double taxAmount = 0;
}

// ─────────────────────────────────────────────────────────────────────────
// Loading helper
// ─────────────────────────────────────────────────────────────────────────

class _LoadingBox extends StatelessWidget {
  const _LoadingBox();

  @override
  Widget build(BuildContext context) {
    return const Padding(
      padding: EdgeInsets.symmetric(vertical: AppTokens.s32),
      child: Center(child: CircularProgressIndicator()),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────
// Export: botón + helper
// ─────────────────────────────────────────────────────────────────────────

/// Helper que un leaf usa después de cargar sus datos para publicar el
/// snapshot exportable. Se llama desde el callback `data:` de `when()`,
/// envuelto en addPostFrameCallback para no setear state durante el build.
void _publishExport(
  WidgetRef ref, {
  required String fileBaseName,
  required ReportExportData Function() build,
}) {
  WidgetsBinding.instance.addPostFrameCallback((_) {
    ref.read(currentReportExportProvider.notifier).state =
        ReportExportSnapshot(
      fileBaseName: fileBaseName,
      buildData: build,
    );
  });
}

/// Tabla del historial de cierres Z con botón "Descargar PDF" por fila.
/// El PDF se genera transformando el `payload` (jsonb del snapshot fiscal)
/// a `ReportExportData` y reusando el `ReportExportService`.
class _ZClosureTable extends ConsumerWidget {
  const _ZClosureTable({required this.rows});

  final List<FiscalZClosureRow> rows;

  static const _rowHeight = 52.0;
  static const _maxVisibleRows = 10;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (rows.isEmpty) return const SizedBox.shrink();

    final header = Container(
      color: const Color(0xFFF8FAFC),
      padding: const EdgeInsets.symmetric(
          horizontal: AppTokens.s16, vertical: AppTokens.s10),
      child: const Row(
        children: [
          SizedBox(width: 80, child: _ZColLabel('#')),
          Expanded(flex: 3, child: _ZColLabel('Emitido')),
          Expanded(flex: 2, child: _ZColLabel('Tipo')),
          Expanded(
              flex: 2,
              child: _ZColLabel('Total ventas', align: TextAlign.right)),
          SizedBox(width: 110, child: _ZColLabel('Acciones')),
        ],
      ),
    );

    Widget rowAt(int index) {
      final r = rows[index];
      return Container(
        decoration: const BoxDecoration(
          border: Border(top: BorderSide(color: Color(0xFFE2E8F0))),
        ),
        padding: const EdgeInsets.symmetric(horizontal: AppTokens.s16),
        child: Row(
          children: [
            SizedBox(
              width: 80,
              child: Text(
                r.closureNumber.toString().padLeft(5, '0'),
                style: const TextStyle(
                    fontSize: 13, fontWeight: FontWeight.w600),
              ),
            ),
            Expanded(
              flex: 3,
              child: Text(
                formatDateTime(r.emittedAt),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 13),
              ),
            ),
            Expanded(
              flex: 2,
              child: Text(
                r.isComplementary ? 'Complementario' : 'Primario',
                style: const TextStyle(fontSize: 13),
              ),
            ),
            Expanded(
              flex: 2,
              child: Text(
                _CierreZReport._zClosureTotal(r),
                textAlign: TextAlign.right,
                style: const TextStyle(
                    fontSize: 13, fontWeight: FontWeight.w700),
              ),
            ),
            SizedBox(
              width: 110,
              child: OutlinedButton.icon(
                onPressed: () => _exportZClosurePdf(context, ref, r),
                icon: const Icon(Icons.picture_as_pdf_outlined, size: 16),
                label:
                    const Text('PDF', style: TextStyle(fontSize: 12)),
                style: OutlinedButton.styleFrom(
                  minimumSize: const Size(0, 30),
                  padding: const EdgeInsets.symmetric(horizontal: 10),
                ),
              ),
            ),
          ],
        ),
      );
    }

    if (rows.length <= _maxVisibleRows) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          header,
          for (int i = 0; i < rows.length; i++)
            SizedBox(height: _rowHeight, child: rowAt(i)),
        ],
      );
    }

    final viewportHeight = _maxVisibleRows * _rowHeight;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        header,
        SizedBox(
          height: viewportHeight,
          child: ListView.builder(
            itemCount: rows.length,
            itemExtent: _rowHeight,
            itemBuilder: (context, index) => rowAt(index),
          ),
        ),
      ],
    );
  }
}

class _ZColLabel extends StatelessWidget {
  const _ZColLabel(this.text, {this.align = TextAlign.left});

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
        color: Color(0xFF475569),
        letterSpacing: 0.3,
      ),
    );
  }
}

Future<void> _exportZClosurePdf(
  BuildContext context,
  WidgetRef ref,
  FiscalZClosureRow row,
) async {
    final settings = ref.read(appSettingsProvider).valueOrNull;
    final branchName = ref.read(shellCurrentBranchNameProvider).valueOrNull;
    try {
      final data = _buildZClosureExportData(row);
      final bytes = await ReportExportService().renderBytes(
        data: data,
        format: ReportExportFormat.pdf,
        settings: settings,
        branchName: branchName,
      );
      if (!context.mounted) return;
      final saved = await FileIoHelper.saveBytes(
        bytes: bytes,
        fileName: 'cierre_z_${row.closureNumber.toString().padLeft(5, '0')}.pdf',
        extension: 'pdf',
        dialogTitle: 'Guardar cierre Z',
      );
      if (!context.mounted) return;
      if (saved) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Cierre Z exportado.')),
        );
      }
    } catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error al exportar cierre Z: $e')),
      );
    }
}

/// Transforma el payload del snapshot Z al modelo de export compartido.
ReportExportData _buildZClosureExportData(FiscalZClosureRow row) {
  final p = row.payload;
  final session = (p['session'] as Map?) ?? const {};
  final salesByType =
      (p['sales_by_receipt_type'] as List?) ?? const [];
  final payments = (p['payments_by_method'] as Map?) ?? const {};
  final taxes = (p['tax_breakdown'] as Map?) ?? const {};
  final voids = (p['voids'] as Map?) ?? const {};

  double n(dynamic v) => (v as num?)?.toDouble() ?? 0;
  String? parseTs(dynamic v) {
    if (v == null) return null;
    final dt = DateTime.tryParse(v.toString());
    return dt == null ? v.toString() : formatDateTime(dt);
  }

  final salesRows = <List<String>>[
    for (final raw in salesByType)
      if (raw is Map)
        [
          _receiptTypeLabel((raw['receipt_type'] ?? '').toString()),
          '${raw['count'] ?? 0}',
          money(n(raw['subtotal'])),
          money(n(raw['tax'])),
          money(n(raw['total'])),
        ],
  ];

  final paymentRows = <List<String>>[
    for (final entry in payments.entries)
      [_paymentMethodLabel(entry.key.toString()), money(n(entry.value))],
  ];

  final salesTotal = salesByType.fold<double>(0, (s, raw) {
    if (raw is Map) return s + n(raw['total']);
    return s;
  });

  return ReportExportData(
    title: 'Cierre Z Fiscal #${row.closureNumber.toString().padLeft(5, '0')}',
    subtitle: row.isComplementary
        ? 'Cierre complementario · Emitido ${formatDateTime(row.emittedAt)}'
        : 'Cierre primario · Emitido ${formatDateTime(row.emittedAt)}',
    sections: [
      ReportSection(
        title: 'Sesión de caja',
        kv: [
          ReportKv('Apertura', parseTs(session['opened_at']) ?? '—'),
          ReportKv('Cierre', parseTs(session['closed_at']) ?? '—'),
          ReportKv('Efectivo inicial', money(n(session['opening_amount']))),
          ReportKv('Efectivo esperado', money(n(session['expected_amount']))),
          if (session['closing_amount'] != null)
            ReportKv('Cierre declarado', money(n(session['closing_amount']))),
          if (session['difference_amount'] != null)
            ReportKv(
              'Diferencia',
              money(n(session['difference_amount'])),
              highlight: true,
            ),
        ],
      ),
      ReportSection(
        title: 'Ventas por tipo de comprobante',
        table: ReportTable(
          columns: const ['Tipo', 'Cantidad', 'Subtotal', 'ITBIS', 'Total'],
          rows: salesRows,
          numericColumns: const {1, 2, 3, 4},
        ),
        totals: [
          ReportKv('Total ventas', money(salesTotal), highlight: true),
        ],
      ),
      ReportSection(
        title: 'Cobros por método de pago',
        table: ReportTable(
          columns: const ['Método', 'Total'],
          rows: paymentRows,
          numericColumns: const {1},
        ),
      ),
      ReportSection(
        title: 'Desglose ITBIS',
        kv: [
          ReportKv('Base gravada', money(n(taxes['taxable_amount']))),
          ReportKv('Base exenta', money(n(taxes['exempt_amount']))),
          ReportKv('ITBIS', money(n(taxes['tax_amount'])), highlight: true),
        ],
      ),
      ReportSection(
        title: 'Anulaciones',
        kv: [
          ReportKv('Cantidad', '${voids['count'] ?? 0}'),
          ReportKv('Monto', money(n(voids['amount']))),
        ],
        note:
            'Documento fiscal inmutable. Para correcciones emitir un cierre Z complementario.',
      ),
    ],
  );
}

String _receiptTypeLabel(String type) {
  switch (type) {
    case 'consumer_final':
      return 'Consumidor Final (B02)';
    case 'fiscal_credit':
      return 'Crédito Fiscal (B01)';
    case 'governmental':
      return 'Gubernamental (B15)';
    case 'special':
      return 'Régimen Especial (B14)';
    case 'export':
      return 'Exportación (B16)';
    default:
      return type;
  }
}

String _paymentMethodLabel(String method) {
  switch (method) {
    case 'cash':
      return 'Efectivo';
    case 'card':
      return 'Tarjeta';
    case 'transfer':
      return 'Transferencia';
    case 'credit':
      return 'Crédito';
    case 'check':
      return 'Cheque';
    default:
      return method;
  }
}

/// Publica un snapshot exportable para 606/607 con el formato común DGII:
/// metadata (RNC, período, registros válidos/inconsistencias) + tabla con
/// los primeros 200 registros para que quepa en el PDF/XLSX. El TXT oficial
/// sigue siendo el botón "Copiar TXT" del propio reporte.
void _publishDgiiExport(
  WidgetRef ref, {
  required Map<String, dynamic> data,
  required int year,
  required int month,
  required String fileBaseName,
  required String title,
  required String proveedorOrCliente,
}) {
  final rnc = (data['rnc_negocio'] ?? '').toString();
  final period = (data['period'] ?? '').toString();
  final count = (data['records_count'] as num?)?.toInt() ?? 0;
  final inconsistencies = (data['inconsistencies_count'] as num?)?.toInt() ?? 0;
  final rows = (data['rows'] as List?) ?? const [];

  final tableRows = <List<String>>[
    for (final raw in rows.take(200))
      if (raw is Map)
        [
          (raw['ncf'] ?? '').toString(),
          (raw['fecha_comprobante'] ?? '').toString(),
          (raw['rnc_proveedor'] ?? raw['rnc_cliente'] ?? '—').toString(),
          money((raw['monto_facturado'] as num?)?.toDouble() ?? 0),
          money((raw['itbis_facturado'] as num?)?.toDouble() ?? 0),
        ],
  ];

  _publishExport(
    ref,
    fileBaseName: '${fileBaseName}_$year${month.toString().padLeft(2, '0')}',
    build: () => ReportExportData(
      title: title,
      subtitle: 'Período $period',
      sections: [
        ReportSection(
          title: 'Resumen',
          kv: [
            ReportKv(
              'RNC negocio',
              rnc.isEmpty ? 'no configurado' : rnc,
            ),
            ReportKv('Período', period),
            ReportKv('Registros válidos', '$count'),
            ReportKv('Inconsistencias', '$inconsistencies'),
          ],
        ),
        ReportSection(
          title: 'Vista previa (primeros 200 registros)',
          table: ReportTable(
            columns: ['NCF', 'Fecha', 'RNC $proveedorOrCliente', 'Monto', 'ITBIS'],
            rows: tableRows,
            numericColumns: const {3, 4},
          ),
          note: rnc.isEmpty
              ? 'Falta configurar el RNC en /configuracion antes de generar el TXT DGII.'
              : null,
        ),
      ],
    ),
  );
}

String _timestamp() {
  final n = DateTime.now();
  return '${n.year}${n.month.toString().padLeft(2, '0')}'
      '${n.day.toString().padLeft(2, '0')}_'
      '${n.hour.toString().padLeft(2, '0')}'
      '${n.minute.toString().padLeft(2, '0')}';
}

/// Dos botones separados — "PDF" y "Excel" — para exportar el reporte
/// activo. Se deshabilitan si todavía no hay snapshot publicado.
class _ExportMenuButton extends ConsumerWidget {
  const _ExportMenuButton();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final snapshot = ref.watch(currentReportExportProvider);
    final enabled = snapshot != null;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        OutlinedButton.icon(
          onPressed: enabled
              ? () => _exportCurrentSnapshot(
                    context,
                    ref,
                    ReportExportFormat.pdf,
                  )
              : null,
          icon: const Icon(Icons.picture_as_pdf_outlined, size: 18),
          label: const Text('PDF'),
        ),
        const SizedBox(width: AppTokens.s8),
        OutlinedButton.icon(
          onPressed: enabled
              ? () => _exportCurrentSnapshot(
                    context,
                    ref,
                    ReportExportFormat.xlsx,
                  )
              : null,
          icon: const Icon(Icons.table_chart_outlined, size: 18),
          label: const Text('Excel'),
        ),
      ],
    );
  }
}

/// Helper compartido: lee el snapshot publicado, lo renderiza con el formato
/// pedido y dispara el "Guardar archivo". Lo usan tanto el botón del header
/// como los botones directos en las tarjetas Gráfico/Resumen.
Future<void> _exportCurrentSnapshot(
  BuildContext context,
  WidgetRef ref,
  ReportExportFormat format,
) async {
  final snap = ref.read(currentReportExportProvider);
  if (snap == null) return;
  final settings = ref.read(appSettingsProvider).valueOrNull;
  final branchName = ref.read(shellCurrentBranchNameProvider).valueOrNull;
  try {
    final bytes = await ReportExportService().renderBytes(
      data: snap.buildData(),
      format: format,
      settings: settings,
      branchName: branchName,
    );
    if (!context.mounted) return;
    final ext = format == ReportExportFormat.pdf ? 'pdf' : 'xlsx';
    final saved = await FileIoHelper.saveBytes(
      bytes: bytes,
      fileName: '${snap.fileBaseName}_${_timestamp()}.$ext',
      extension: ext,
      dialogTitle: 'Guardar reporte',
    );
    if (!context.mounted) return;
    if (saved) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Reporte exportado.')),
      );
    }
  } catch (e) {
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Error al exportar: $e')),
    );
  }
}
