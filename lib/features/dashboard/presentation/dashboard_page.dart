// Dashboard PRD-Dashboard-001 sub-fases 2-5.
//
// Layout:
//   1) 4 KPI cards (cuentas) — F1
//   2) 5 quick actions con uno destacado en color de acento — F2
//   3) Gráfico de barras con toggle Mes / Semana — F3
//   4) Cierre del día detallado: 6 bloques con navegación día anterior /
//      siguiente día — F4
//
// Fuentes: 3 RPCs Supabase definidos en `20260509_10_dashboard_v2.sql`.

import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/tokens.dart';
import '../../../shared/errors/friendly_error.dart';
import '../../../shared/formatters/formatters.dart';
import '../../../shared/widgets/empty_state.dart';
import '../../../shared/widgets/module_page.dart';
import '../../../shared/widgets/ncf_stock_banner.dart';
import '../data/dashboard_repository.dart';
import 'dashboard_providers.dart';

class DashboardPage extends ConsumerWidget {
  const DashboardPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final heroAsync = ref.watch(dashboardHeroKpisProvider);
    final chartAsync = ref.watch(dashboardChartProvider);

    return ModulePage(
      title: 'Panel',
      description: 'Vista consolidada del negocio.',
      actions: [
        OutlinedButton.icon(
          onPressed: () {
            ref.invalidate(dashboardHeroKpisProvider);
            ref.invalidate(dashboardChartProvider);
          },
          icon: const Icon(Icons.refresh, size: 18),
          label: const Text('Actualizar'),
        ),
      ],
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const NcfStockBanner(),
          _HeroKpiGrid(heroAsync: heroAsync),
          const SizedBox(height: AppTokens.s16),
          const _ShortcutRow(),
          const SizedBox(height: AppTokens.s24),
          _QuickActions(),
          const SizedBox(height: AppTokens.s24),
          _SalesChartCard(chartAsync: chartAsync),
          const SizedBox(height: AppTokens.s48),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────
// F1 — KPI cards
// ─────────────────────────────────────────────────────────────────────────

// Paleta de las hero KPI cards (diseño original con fondos saturados).
const _kKpiOrange = Color(0xFFE26B30);
const _kKpiRed = Color(0xFFC13E3E);
const _kKpiGreen = Color(0xFF5FA760);
const _kKpiLavender = Color(0xFF8FA5CA);

class _HeroKpiGrid extends ConsumerWidget {
  const _HeroKpiGrid({required this.heroAsync});

  final AsyncValue<DashboardHeroKpis> heroAsync;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return heroAsync.when(
      loading: () => const _KpiSkeletonGrid(),
      error: (error, _) => ErrorCard(
        message: 'No se pudieron cargar los KPIs: ${friendlyErrorMessage(error)}',
        onRetry: () => ref.invalidate(dashboardHeroKpisProvider),
      ),
      data: (kpis) {
        void goToReports() => context.go('/reportes');
        return _KpiResponsiveGrid(
          children: [
            _HeroKpiCard(
              label: 'Ventas Hoy',
              value: money(kpis.salesTodayAmount),
              caption: '${kpis.salesTodayCount} '
                  '${kpis.salesTodayCount == 1 ? "transacción" : "transacciones"}',
              icon: Icons.shopping_cart_outlined,
              background: _kKpiOrange,
              onTap: goToReports,
            ),
            _HeroKpiCard(
              label: 'Ventas del Mes',
              value: money(kpis.salesMonthAmount),
              caption: '${kpis.salesMonthCount} '
                  '${kpis.salesMonthCount == 1 ? "venta este mes" : "ventas este mes"}',
              icon: Icons.trending_up_outlined,
              background: _kKpiRed,
              onTap: goToReports,
            ),
            _HeroKpiCard(
              label: 'Inventario',
              value: kpis.productsActive.toString(),
              caption: 'Productos activos',
              icon: Icons.inventory_2_outlined,
              background: _kKpiGreen,
              onTap: goToReports,
            ),
            _HeroKpiCard(
              label: 'Clientes',
              value: kpis.clientsActive.toString(),
              caption: 'Registrados',
              icon: Icons.people_outline,
              background: _kKpiLavender,
              onTap: goToReports,
            ),
          ],
        );
      },
    );
  }
}

class _HeroKpiCard extends StatelessWidget {
  const _HeroKpiCard({
    required this.label,
    required this.value,
    required this.caption,
    required this.icon,
    required this.background,
    required this.onTap,
  });

  final String label;
  final String value;
  final String caption;
  final IconData icon;
  final Color background;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: background,
      borderRadius: BorderRadius.circular(AppTokens.radius),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        splashColor: Colors.white.withValues(alpha: 0.16),
        highlightColor: Colors.white.withValues(alpha: 0.08),
        child: Padding(
          padding: const EdgeInsets.all(AppTokens.s20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      label,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.all(AppTokens.s8),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.18),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Icon(icon, color: Colors.white, size: 20),
                  ),
                ],
              ),
              const SizedBox(height: AppTokens.s24),
              Text(
                value,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 30,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: AppTokens.s8),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: AppTokens.s8,
                  vertical: AppTokens.s4,
                ),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.18),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  caption,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ShortcutRow extends StatelessWidget {
  const _ShortcutRow();

  @override
  Widget build(BuildContext context) {
    final shortcuts = <_Shortcut>[
      _Shortcut(
        label: 'Nueva Venta',
        icon: Icons.shopping_cart_outlined,
        path: '/ventas',
      ),
      _Shortcut(
        label: 'Comprobantes',
        icon: Icons.receipt_long_outlined,
        path: '/comprobantes',
      ),
      _Shortcut(
        label: 'Nueva Compra',
        icon: Icons.local_shipping_outlined,
        path: '/compras',
      ),
      _Shortcut(
        label: 'Reportes',
        icon: Icons.bar_chart_rounded,
        path: '/reportes',
      ),
      _Shortcut(
        label: 'Clientes',
        icon: Icons.people_outline,
        path: '/clientes',
      ),
      _Shortcut(
        label: 'Caja',
        icon: Icons.point_of_sale_outlined,
        path: '/caja',
      ),
    ];

    return LayoutBuilder(
      builder: (context, constraints) {
        final cols = constraints.maxWidth >= 1100
            ? 6
            : constraints.maxWidth >= 720
                ? 3
                : 2;
        const gap = AppTokens.s12;
        final itemWidth =
            (constraints.maxWidth - gap * (cols - 1)) / cols;
        return Wrap(
          spacing: gap,
          runSpacing: gap,
          children: shortcuts
              .map((s) => SizedBox(width: itemWidth, child: s))
              .toList(growable: false),
        );
      },
    );
  }
}

class _Shortcut extends StatelessWidget {
  const _Shortcut({
    required this.label,
    required this.icon,
    required this.path,
  });

  final String label;
  final IconData icon;
  final String path;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppTokens.card,
      borderRadius: BorderRadius.circular(10),
      child: InkWell(
        onTap: () => context.go(path),
        borderRadius: BorderRadius.circular(10),
        child: Container(
          padding: const EdgeInsets.symmetric(
            horizontal: AppTokens.s14,
            vertical: AppTokens.s12,
          ),
          decoration: BoxDecoration(
            border: Border.all(color: AppTokens.border),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Row(
            children: [
              Icon(icon, size: 18, color: AppTokens.mutedForeground),
              const SizedBox(width: AppTokens.s10),
              Expanded(
                child: Text(
                  label,
                  style: const TextStyle(
                    color: AppTokens.foreground,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              const Icon(
                Icons.chevron_right,
                size: 18,
                color: AppTokens.mutedForeground,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _KpiResponsiveGrid extends StatelessWidget {
  const _KpiResponsiveGrid({required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    final cols = width >= 1024
        ? 4
        : width >= 720
            ? 2
            : 1;

    return LayoutBuilder(
      builder: (context, constraints) {
        const gap = AppTokens.s16;
        final cardWidth =
            (constraints.maxWidth - gap * (cols - 1)) / cols;
        return Wrap(
          spacing: gap,
          runSpacing: gap,
          children: children
              .map((c) => SizedBox(width: cardWidth, child: c))
              .toList(growable: false),
        );
      },
    );
  }
}

class _KpiSkeletonGrid extends StatelessWidget {
  const _KpiSkeletonGrid();

  @override
  Widget build(BuildContext context) {
    return _KpiResponsiveGrid(
      children: List.generate(
        4,
        (_) => Card(
          margin: EdgeInsets.zero,
          child: Padding(
            padding: const EdgeInsets.all(AppTokens.s20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  height: 28,
                  width: 80,
                  decoration: BoxDecoration(
                    color: AppTokens.muted,
                    borderRadius: BorderRadius.circular(4),
                  ),
                ),
                const SizedBox(height: AppTokens.s8),
                Container(
                  height: 14,
                  width: 120,
                  decoration: BoxDecoration(
                    color: AppTokens.muted,
                    borderRadius: BorderRadius.circular(4),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────
// F2 — Quick Actions
// ─────────────────────────────────────────────────────────────────────────

class _QuickActions extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final actions = <_QuickAction>[
      _QuickAction(
        label: 'Informe de cierre de hoy',
        icon: Icons.access_time_outlined,
        accent: false,
        onTap: () => context.go('/panel/cierre'),
      ),
      _QuickAction(
        label: 'Resumen de artículos vendidos hoy',
        icon: Icons.assignment_outlined,
        accent: false,
        onTap: () => context.go('/reportes'),
      ),
      _QuickAction(
        label: 'Iniciar una nueva venta',
        icon: Icons.shopping_cart_outlined,
        accent: false,
        onTap: () => context.go('/ventas'),
      ),
      _QuickAction(
        label: 'Informe de ventas detallado de hoy',
        icon: Icons.bar_chart_rounded,
        accent: true,
        onTap: () => context.go('/reportes'),
      ),
      _QuickAction(
        label: 'Registrar nueva recepción / compra',
        icon: Icons.cloud_download_outlined,
        accent: false,
        onTap: () => context.go('/compras'),
      ),
    ];

    return LayoutBuilder(
      builder: (context, constraints) {
        final isWide = constraints.maxWidth >= 720;
        final cols = isWide ? 2 : 1;
        const gap = AppTokens.s12;
        final itemWidth =
            (constraints.maxWidth - gap * (cols - 1)) / cols;

        return Wrap(
          spacing: gap,
          runSpacing: gap,
          children: actions
              .map((a) => SizedBox(width: itemWidth, child: a))
              .toList(growable: false),
        );
      },
    );
  }
}

class _QuickAction extends StatelessWidget {
  const _QuickAction({
    required this.label,
    required this.icon,
    required this.onTap,
    required this.accent,
  });

  final String label;
  final IconData icon;
  final VoidCallback onTap;

  /// Botón destacado en el color primario (F2 — uno solo destacado).
  final bool accent;

  @override
  Widget build(BuildContext context) {
    final bg = accent ? AppTokens.primary : AppTokens.card;
    final fg = accent ? AppTokens.primaryForeground : AppTokens.foreground;
    final border = accent ? AppTokens.primary : AppTokens.border;

    return Material(
      color: bg,
      borderRadius: BorderRadius.circular(10),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(10),
        child: Container(
          padding: const EdgeInsets.symmetric(
            horizontal: AppTokens.s16,
            vertical: AppTokens.s14,
          ),
          decoration: BoxDecoration(
            border: Border.all(color: border),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Row(
            children: [
              Icon(icon, color: fg, size: 20),
              const SizedBox(width: AppTokens.s12),
              Expanded(
                child: Text(
                  label,
                  style: TextStyle(
                    color: fg,
                    fontWeight:
                        accent ? FontWeight.w700 : FontWeight.w600,
                  ),
                ),
              ),
              Icon(Icons.arrow_forward, color: fg, size: 18),
            ],
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────
// F3 — Sales chart Mes / Semana
// ─────────────────────────────────────────────────────────────────────────

class _SalesChartCard extends ConsumerWidget {
  const _SalesChartCard({required this.chartAsync});

  final AsyncValue<List<DashboardChartPoint>> chartAsync;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final range = ref.watch(dashboardChartRangeProvider);

    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(AppTokens.s20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    'Información de ventas',
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                  ),
                ),
                _RangeToggle(
                  active: range,
                  onChanged: (r) => ref
                      .read(dashboardChartRangeProvider.notifier)
                      .state = r,
                ),
              ],
            ),
            const SizedBox(height: AppTokens.s16),
            chartAsync.when(
              loading: () => const SizedBox(
                height: 280,
                child: Center(child: CircularProgressIndicator()),
              ),
              error: (error, _) => SizedBox(
                height: 280,
                child: Center(
                  child: Text('No se pudo cargar el gráfico: ${friendlyErrorMessage(error)}'),
                ),
              ),
              data: (points) => _BarChart(points: points, range: range),
            ),
          ],
        ),
      ),
    );
  }
}

class _RangeToggle extends StatelessWidget {
  const _RangeToggle({required this.active, required this.onChanged});

  final DashboardChartRange active;
  final ValueChanged<DashboardChartRange> onChanged;

  @override
  Widget build(BuildContext context) {
    return SegmentedButton<DashboardChartRange>(
      segments: const [
        ButtonSegment(
          value: DashboardChartRange.month,
          label: Text('Mes'),
        ),
        ButtonSegment(
          value: DashboardChartRange.week,
          label: Text('Semana'),
        ),
      ],
      selected: {active},
      onSelectionChanged: (set) => onChanged(set.first),
    );
  }
}

class _BarChart extends StatelessWidget {
  const _BarChart({required this.points, required this.range});

  final List<DashboardChartPoint> points;
  final DashboardChartRange range;

  @override
  Widget build(BuildContext context) {
    if (points.isEmpty) {
      return SizedBox(
        height: 240,
        child: Center(
          child: Text(
            'No hay ventas en el rango seleccionado.',
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: AppTokens.mutedForeground,
                ),
          ),
        ),
      );
    }

    final maxTransactions = points.fold<int>(
      0,
      (prev, item) => math.max(prev, item.transactions),
    );
    final topAxis = _roundAxisMax(maxTransactions);
    const chartHeight = 240.0;

    return SizedBox(
      height: chartHeight + 28,
      child: Column(
        children: [
          Expanded(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: points.map((point) {
                final ratio = topAxis == 0
                    ? 0.0
                    : point.transactions / topAxis;
                final barHeight = math.max(4.0, ratio * chartHeight);
                return Expanded(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 3),
                    child: Tooltip(
                      message:
                          '${formatDate(point.date)}\n${point.transactions} ventas · ${money(point.total)}',
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: [
                          Container(
                            height: barHeight,
                            decoration: BoxDecoration(
                              color: AppTokens.primary,
                              borderRadius: const BorderRadius.vertical(
                                top: Radius.circular(6),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                );
              }).toList(growable: false),
            ),
          ),
          const SizedBox(height: AppTokens.s4),
          Row(
            children: points.map((point) {
              return Expanded(
                child: Center(
                  child: Text(
                    range == DashboardChartRange.week
                        ? _weekdayShort(point.date)
                        : point.date.day.toString(),
                    style:
                        Theme.of(context).textTheme.labelSmall?.copyWith(
                              color: AppTokens.mutedForeground,
                            ),
                  ),
                ),
              );
            }).toList(growable: false),
          ),
        ],
      ),
    );
  }

  String _weekdayShort(DateTime d) {
    const labels = ['Lun', 'Mar', 'Mié', 'Jue', 'Vie', 'Sáb', 'Dom'];
    return labels[d.weekday - 1];
  }

  static int _roundAxisMax(int max) {
    if (max <= 5) return 5;
    if (max <= 10) return 10;
    if (max <= 20) return 20;
    if (max <= 50) return 50;
    return ((max / 50).ceil()) * 50;
  }
}

// F4 (Cierre del día) vive ahora en `closeout_page.dart` y se accede vía
// la quick action "Informe de cierre de hoy" → /panel/cierre.
