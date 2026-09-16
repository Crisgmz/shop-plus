import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../auth/presentation/auth_providers.dart';
import '../data/reports_repository.dart';
import '../domain/report_category.dart';
import '../export/report_export_models.dart';

final reportPeriodProvider =
    StateProvider<ReportPeriod>((ref) => ReportPeriod.monthly);

final reportsRepositoryProvider = Provider<ReportsRepository>((ref) {
  final client = ref.watch(supabaseClientProvider);
  return ReportsRepository(client);
});

final reportsDataProvider = FutureProvider<ReportsData>((ref) async {
  final repository = ref.watch(reportsRepositoryProvider);
  final period = ref.watch(reportPeriodProvider);
  return repository.fetchReports(period);
});

final reportPresetsProvider = FutureProvider<List<ReportPreset>>((ref) async {
  final repository = ref.watch(reportsRepositoryProvider);
  return repository.fetchPresets();
});

final reportExportsProvider = FutureProvider<List<ReportExport>>((ref) async {
  final repository = ref.watch(reportsRepositoryProvider);
  return repository.fetchRecentExports();
});

final taxBreakdownFromProvider = StateProvider<DateTime?>((ref) {
  final now = DateTime.now();
  return DateTime(now.year, now.month, 1);
});
final taxBreakdownToProvider = StateProvider<DateTime?>((ref) => null);

final salesTaxBreakdownProvider =
    FutureProvider<List<SalesTaxRow>>((ref) async {
  final repository = ref.watch(reportsRepositoryProvider);
  final from = ref.watch(taxBreakdownFromProvider);
  final to = ref.watch(taxBreakdownToProvider);
  return repository.fetchSalesTaxBreakdown(from: from, to: to);
});

// ─────────────────────────────────────────────────────────────────────────
// PRD 07 v2: providers para la pantalla Reportes nueva.
// ─────────────────────────────────────────────────────────────────────────

/// Categoría seleccionada en el sidebar. Null = vista de bienvenida.
final reportCategoryProvider =
    StateProvider<ReportCategory?>((ref) => null);

/// Modo activo dentro de la categoría. Null = mostrar dual cards.
final reportModeProvider = StateProvider<ReportMode?>((ref) => null);

/// Rango de fecha actual del filtro (default: este mes).
final reportDateRangeProvider = StateProvider<ReportDateRange>((ref) {
  return ReportDateRange.fromPreset(ReportDateRangePreset.thisMonth);
});

/// Datos para los 6 reportes operativos del round 1.
final salesDailyReportProvider =
    FutureProvider.autoDispose<List<SalesDailyRow>>((ref) async {
  final repo = ref.watch(reportsRepositoryProvider);
  final range = ref.watch(reportDateRangeProvider);
  return repo.fetchSalesDaily(from: range.from, to: range.to);
});

final cashSessionsReportProvider =
    FutureProvider.autoDispose<List<CashSessionRow>>((ref) async {
  final repo = ref.watch(reportsRepositoryProvider);
  final range = ref.watch(reportDateRangeProvider);
  return repo.fetchCashSessions(from: range.from, to: range.to);
});

final paymentsReportProvider =
    FutureProvider.autoDispose<List<PaymentMethodRow>>((ref) async {
  final repo = ref.watch(reportsRepositoryProvider);
  final range = ref.watch(reportDateRangeProvider);
  return repo.fetchPaymentsByMethod(from: range.from, to: range.to);
});

final outgoingPaymentsReportProvider =
    FutureProvider.autoDispose<List<OutgoingPaymentRow>>((ref) async {
  final repo = ref.watch(reportsRepositoryProvider);
  final range = ref.watch(reportDateRangeProvider);
  return repo.fetchOutgoingPayments(from: range.from, to: range.to);
});

final suspendedSalesReportProvider =
    FutureProvider.autoDispose<List<SuspendedSaleRow>>((ref) async {
  final repo = ref.watch(reportsRepositoryProvider);
  final range = ref.watch(reportDateRangeProvider);
  return repo.fetchSuspendedSales(from: range.from, to: range.to);
});

/// Liquidación operativa (reusa el closeout del dashboard para el último día
/// del rango — los reportes operativos suelen ser de un día específico).
final operationalCloseoutReportProvider =
    FutureProvider.autoDispose<Map<String, dynamic>>((ref) async {
  final repo = ref.watch(reportsRepositoryProvider);
  final range = ref.watch(reportDateRangeProvider);
  return repo.fetchOperationalCloseout(date: range.to);
});

// ─── Round 2 providers ────────────────────────────────────────────────────

final employeeProductivityProvider =
    FutureProvider.autoDispose<List<EmployeeProductivityRow>>((ref) async {
  final repo = ref.watch(reportsRepositoryProvider);
  final r = ref.watch(reportDateRangeProvider);
  return repo.fetchEmployeeProductivity(from: r.from, to: r.to);
});

final commissionReportProvider =
    FutureProvider.autoDispose<Map<String, dynamic>>((ref) async {
  final repo = ref.watch(reportsRepositoryProvider);
  final r = ref.watch(reportDateRangeProvider);
  return repo.fetchCommission(from: r.from, to: r.to);
});

final inventoryStatusReportProvider =
    FutureProvider.autoDispose<List<InventoryStatusRow>>((ref) async {
  final repo = ref.watch(reportsRepositoryProvider);
  return repo.fetchInventoryStatus();
});

final salesByItemReportProvider =
    FutureProvider.autoDispose<List<SalesByItemRow>>((ref) async {
  final repo = ref.watch(reportsRepositoryProvider);
  final r = ref.watch(reportDateRangeProvider);
  return repo.fetchSalesByItem(from: r.from, to: r.to);
});

final salesByCategoryReportProvider =
    FutureProvider.autoDispose<List<SalesByCategoryRow>>((ref) async {
  final repo = ref.watch(reportsRepositoryProvider);
  final r = ref.watch(reportDateRangeProvider);
  return repo.fetchSalesByCategory(from: r.from, to: r.to);
});

final currentPricesReportProvider =
    FutureProvider.autoDispose<List<PriceRow>>((ref) async {
  final repo = ref.watch(reportsRepositoryProvider);
  return repo.fetchCurrentPrices();
});

final priceHistoryReportProvider =
    FutureProvider.autoDispose<List<PriceHistoryRow>>((ref) async {
  final repo = ref.watch(reportsRepositoryProvider);
  final r = ref.watch(reportDateRangeProvider);
  return repo.fetchPriceHistory(from: r.from, to: r.to);
});

final inventoryMovementsReportProvider =
    FutureProvider.autoDispose<List<InventoryMovementDailyRow>>((ref) async {
  final repo = ref.watch(reportsRepositoryProvider);
  final r = ref.watch(reportDateRangeProvider);
  return repo.fetchInventoryMovements(
    from: r.from,
    to: r.to,
    movementTypes: const [
      'waste',
      'breakage',
      'expired',
      'kitchen_return',
    ],
  );
});

final plReportProvider =
    FutureProvider.autoDispose<Map<String, dynamic>>((ref) async {
  final repo = ref.watch(reportsRepositoryProvider);
  final r = ref.watch(reportDateRangeProvider);
  return repo.fetchPl(from: r.from, to: r.to);
});

final creditAgingReportProvider =
    FutureProvider.autoDispose<List<CreditAgingRow>>((ref) async {
  final repo = ref.watch(reportsRepositoryProvider);
  return repo.fetchCreditAging();
});

final expensesReportProvider =
    FutureProvider.autoDispose<List<ExpensesByCategoryRow>>((ref) async {
  final repo = ref.watch(reportsRepositoryProvider);
  final r = ref.watch(reportDateRangeProvider);
  return repo.fetchExpensesByCategory(from: r.from, to: r.to);
});

final purchasesReportV2Provider =
    FutureProvider.autoDispose<List<PurchasesReportRow>>((ref) async {
  final repo = ref.watch(reportsRepositoryProvider);
  final r = ref.watch(reportDateRangeProvider);
  return repo.fetchPurchasesReport(from: r.from, to: r.to);
});

final suppliersReportProvider =
    FutureProvider.autoDispose<List<SuppliersReportRow>>((ref) async {
  final repo = ref.watch(reportsRepositoryProvider);
  return repo.fetchSuppliersReport();
});

final clientsReportProvider =
    FutureProvider.autoDispose<List<ClientsReportRow>>((ref) async {
  final repo = ref.watch(reportsRepositoryProvider);
  return repo.fetchClientsReport();
});

final discountsReportProvider =
    FutureProvider.autoDispose<List<DiscountRow>>((ref) async {
  final repo = ref.watch(reportsRepositoryProvider);
  final r = ref.watch(reportDateRangeProvider);
  return repo.fetchDiscounts(from: r.from, to: r.to);
});

final taxBreakdownV2Provider =
    FutureProvider.autoDispose<List<TaxBreakdownRow>>((ref) async {
  final repo = ref.watch(reportsRepositoryProvider);
  final r = ref.watch(reportDateRangeProvider);
  return repo.fetchTaxBreakdown(from: r.from, to: r.to);
});

// ─── Round 3 (DGII) providers ─────────────────────────────────────────────

/// Año seleccionado para reportes mensuales DGII. Default: año en curso.
final dgiiYearProvider =
    StateProvider<int>((ref) => DateTime.now().year);

/// Mes seleccionado (1-12). Default: mes anterior (los reportes DGII suelen
/// ser del mes cerrado).
final dgiiMonthProvider = StateProvider<int>((ref) {
  final now = DateTime.now();
  return now.month == 1 ? 12 : now.month - 1;
});

final dgii606Provider =
    FutureProvider.autoDispose<Map<String, dynamic>>((ref) async {
  final repo = ref.watch(reportsRepositoryProvider);
  final year = ref.watch(dgiiYearProvider);
  final month = ref.watch(dgiiMonthProvider);
  return repo.fetchDgii606(year: year, month: month);
});

final dgii607Provider =
    FutureProvider.autoDispose<Map<String, dynamic>>((ref) async {
  final repo = ref.watch(reportsRepositoryProvider);
  final year = ref.watch(dgiiYearProvider);
  final month = ref.watch(dgiiMonthProvider);
  return repo.fetchDgii607(year: year, month: month);
});

final dgiiIt1Provider =
    FutureProvider.autoDispose<Map<String, dynamic>>((ref) async {
  final repo = ref.watch(reportsRepositoryProvider);
  final year = ref.watch(dgiiYearProvider);
  final month = ref.watch(dgiiMonthProvider);
  return repo.fetchDgiiIt1(year: year, month: month);
});

final fiscalZClosuresProvider =
    FutureProvider.autoDispose<List<FiscalZClosureRow>>((ref) async {
  final repo = ref.watch(reportsRepositoryProvider);
  return repo.fetchFiscalZClosures();
});

/// Modelo del reporte actualmente visible, listo para exportar (PDF/XLSX).
/// Cada leaf de `/reportes` lo actualiza al renderizar. El header lee este
/// estado para decidir si habilitar el botón "Exportar".
final currentReportExportProvider = StateProvider<ReportExportSnapshot?>(
  (ref) => null,
);

/// Formato pendiente a auto-exportar al cargar el siguiente snapshot.
/// Se setea cuando el usuario clickea PDF/Excel en una tarjeta del Nivel 1
/// (dual cards Gráfico/Resumen). Al publicar el snapshot del Nivel 2, un
/// listener dispara la descarga y limpia este estado.
final pendingExportFormatProvider = StateProvider<String?>((ref) => null);

/// Snapshot del reporte exportable.
class ReportExportSnapshot {
  ReportExportSnapshot({
    required this.fileBaseName,
    required this.buildData,
    this.buildXlsx,
  });

  /// Nombre del archivo sin extensión (ej. 'ventas_resumen_20260513').
  final String fileBaseName;

  /// Función que construye `ReportExportData` al momento de exportar. Se
  /// usa una función (no el modelo directo) para que la metadata de
  /// compañía / sucursal se evalúe en tiempo de export, no de render.
  final ReportExportData Function() buildData;

  /// Excel propio del reporte (ej. 606/607 con todas sus columnas). Si es
  /// null, el Excel sale del renderer genérico a partir de [buildData].
  final Uint8List Function()? buildXlsx;
}

// ─── Sub-reportes de Ventas (PRD §F-Ventas) ──────────────────────────────

/// Sub-reporte activo dentro de la categoría Ventas. Null = mostrar lista.
final ventasSubReportProvider =
    StateProvider<VentasSubReport?>((ref) => null);

final detailedSalesReportProvider =
    FutureProvider.autoDispose<List<SaleDetailRow>>((ref) async {
  final repo = ref.watch(reportsRepositoryProvider);
  final r = ref.watch(reportDateRangeProvider);
  return repo.fetchDetailedSales(from: r.from, to: r.to);
});

final voidedSalesReportProvider =
    FutureProvider.autoDispose<List<SaleDetailRow>>((ref) async {
  final repo = ref.watch(reportsRepositoryProvider);
  final r = ref.watch(reportDateRangeProvider);
  return repo.fetchDetailedSales(from: r.from, to: r.to, voidedOnly: true);
});

final hourlySalesReportProvider =
    FutureProvider.autoDispose<List<HourlySalesRow>>((ref) async {
  final repo = ref.watch(reportsRepositoryProvider);
  final r = ref.watch(reportDateRangeProvider);
  return repo.fetchSalesByHour(from: r.from, to: r.to);
});
