// Servicio que suscribe canales Postgres Realtime de Supabase y, ante
// cada evento, invalida los providers de Riverpod correspondientes para
// que la UI se actualice sola sin que el usuario tenga que refrescar.
//
// Patrón: por cada (tabla → set de providers) configurado en
// `_tableToProviders`, se abre un channel filtrado por la sucursal
// actual (branch_id=eq.<id>) y se invalidan los providers asociados al
// recibir INSERT/UPDATE/DELETE.
//
// Lifecycle:
//   - Se inicia desde [_RealtimeBootstrap] (lib/app/app.dart) cuando hay
//     branch_id disponible.
//   - Cuando el usuario cambia de sucursal, [reattach] re-suscribe con
//     el branch nuevo cancelando los canales viejos.
//   - Al hacer logout o cerrar la pestaña, [stop] cierra todo.
//
// Diseño:
//   - Una instancia por usuario (singleton del scope Riverpod).
//   - Los canales se nombran `realtime:<tabla>:<branchId>` para que
//     Supabase los multiplexee correctamente.
//   - Las invalidaciones se AGRUPAN ([InvalidationBatcher]): una venta
//     dispara una ráfaga de eventos y se aplican todos juntos una sola vez.
//   - Al RECONECTAR un canal se recarga lo suyo: los eventos del tiempo que
//     estuvo caído se perdieron.

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../features/auth/presentation/auth_providers.dart'
    show supabaseClientProvider;
import '../../features/cash_register/presentation/cash_register_providers.dart'
    show
        allOpenCashSessionsProvider,
        cashRegisterDataProvider,
        cashRegistersProvider,
        myCashRegistersProvider,
        myOpenCashSessionsProvider;
import '../../features/clients/presentation/clients_providers.dart'
    show clientsListProvider, customerBalancesProvider;
import '../../features/cobros/presentation/cobros_providers.dart'
    show cobrosPaymentsProvider, cobrosReceivablesProvider;
import '../../features/dashboard/presentation/dashboard_providers.dart'
    show
        dashboardChartProvider,
        dashboardCloseoutProvider,
        dashboardHeroKpisProvider,
        dashboardKpisProvider,
        dashboardPaymentBreakdownProvider;
import '../../features/expenses/presentation/expenses_providers.dart'
    show expenseSuppliersProvider, expensesListProvider;
import '../../features/fiscal_documents/presentation/fiscal_documents_providers.dart'
    show fiscalDocumentDetailProvider, fiscalDocumentsProvider;
import '../../features/inventory/presentation/inventory_providers.dart'
    show inventoryCategoriesProvider, inventoryProductsProvider;
import '../../features/payables/presentation/payables_providers.dart'
    show payablesListProvider, supplierPaymentsProvider;
import '../../features/petty_cash/presentation/petty_cash_providers.dart'
    show pettyCashDataProvider;
import '../../features/purchases/presentation/purchases_providers.dart'
    show
        purchaseProductsProvider,
        purchaseSuppliersProvider,
        purchasesListProvider;
import '../../features/quotations/presentation/quotations_providers.dart'
    show
        quotationClientsProvider,
        quotationDetailProvider,
        quotationProductsProvider,
        quotationsFoundationProvider;
import '../../features/reports/presentation/reports_providers.dart'
    show
        cashSessionsReportProvider,
        clientsReportProvider,
        commissionReportProvider,
        creditAgingReportProvider,
        currentPricesReportProvider,
        detailedSalesReportProvider,
        dgii606Provider,
        dgii607Provider,
        dgiiIt1Provider,
        discountsReportProvider,
        employeeProductivityProvider,
        expensesReportProvider,
        fiscalZClosuresProvider,
        hourlySalesReportProvider,
        inventoryMovementsReportProvider,
        inventoryStatusReportProvider,
        operationalCloseoutReportProvider,
        outgoingPaymentsReportProvider,
        paymentsReportProvider,
        plReportProvider,
        priceHistoryReportProvider,
        purchasesReportV2Provider,
        reportsDataProvider,
        salesByCategoryReportProvider,
        salesByItemReportProvider,
        salesDailyReportProvider,
        salesTaxBreakdownProvider,
        suppliersReportProvider,
        suspendedSalesReportProvider,
        taxBreakdownV2Provider,
        voidedSalesReportProvider;
import '../../features/returns/presentation/returns_page.dart'
    show returnsHistoryProvider;
import '../../features/sales/presentation/sales_history_providers.dart'
    show salesHistoryDetailProvider, salesHistoryPageProvider;
import '../../features/sales/presentation/sales_providers.dart'
    show
        ncfSequenceAvailableProvider,
        posDefaultReceiptTypeProvider,
        salesCategoriesProvider,
        salesClientsProvider,
        salesProductsProvider;
import '../../features/settings/presentation/settings_providers.dart'
    show settingsDataProvider;
import '../../features/suppliers/presentation/suppliers_providers.dart'
    show suppliersListProvider;
import '../../features/taxes/presentation/taxes_providers.dart'
    show taxesDataProvider;
import '../../shared/widgets/ncf_stock_banner.dart'
    show missingNcfCountProvider, ncfStockAlertsProvider;

/// Lista de providers que se invalidan ante un evento de cada tabla.
///
/// Mantener esto en un map único es a propósito: cuando agregas una tabla
/// nueva al realtime (en la migration SQL), solo hay un lugar aquí donde
/// declarar qué providers se enteran.
typedef _ProviderList = List<ProviderOrFamily>;

/// Junta las invalidaciones de una ráfaga de eventos y las aplica una vez.
///
/// Una venta de 10 productos dispara ~14 eventos: la venta, sus pagos, un
/// UPDATE de stock por producto y el NCF. Invalidar en cada uno hacía que
/// cualquier POS abierto en otra caja recargara el catálogo una docena de
/// veces por venta.
///
/// La ventana arranca con el PRIMER evento y los siguientes NO la alargan:
/// una ráfaga continua no puede dejar la pantalla congelada esperando
/// silencio. El retraso máximo de un cambio es [window].
class InvalidationBatcher {
  InvalidationBatcher({required this.window, required this.onFlush});

  final Duration window;
  final void Function(Set<ProviderOrFamily> providers) onFlush;

  final Set<ProviderOrFamily> _pending = {};
  Timer? _timer;

  bool get hasPending => _pending.isNotEmpty;

  void add(Iterable<ProviderOrFamily> providers) {
    _pending.addAll(providers);
    if (_pending.isEmpty) return;
    _timer ??= Timer(window, flush);
  }

  /// Aplica lo acumulado ya, sin esperar la ventana.
  void flush() {
    _timer?.cancel();
    _timer = null;
    if (_pending.isEmpty) return;
    final batch = Set<ProviderOrFamily>.of(_pending);
    _pending.clear();
    onFlush(batch);
  }

  /// Descarta lo acumulado. Al cambiar de sucursal o cerrar sesión, esas
  /// invalidaciones ya no significan nada — y aplicarlas sobre un container
  /// desechado lanzaría.
  void cancel() {
    _timer?.cancel();
    _timer = null;
    _pending.clear();
  }
}

class RealtimeInvalidator {
  RealtimeInvalidator(this._ref) {
    _batcher = InvalidationBatcher(window: batchWindow, onFlush: _invalidate);
  }

  final Ref _ref;
  final Map<String, RealtimeChannel> _channels = {};
  String? _attachedBranchId;
  late final InvalidationBatcher _batcher;

  /// Cuánto se esperan más eventos de la misma ráfaga antes de recargar.
  /// Corto para que se sienta inmediato; suficiente para agrupar un cobro.
  static const batchWindow = Duration(milliseconds: 400);

  /// Tablas cuyo canal ya se suscribió una vez con esta sucursal. Un segundo
  /// `subscribed` para la misma tabla es una RECONEXIÓN.
  final Set<String> _everSubscribed = {};

  /// Serializa attach/stop concurrentes. Sin este lock, dos llamadas
  /// rápidas a attach() (típico al loguearse + hidratar branches) podían
  /// solaparse y dejar canales huérfanos.
  Future<void>? _inFlight;

  /// Suscribe los canales filtrados por `branchId`. Si ya hay
  /// suscripciones activas para otro branch, las cierra y reabre.
  Future<void> attach(String? branchId) async {
    // Espera a que termine la operación previa antes de arrancar la nueva.
    final pending = _inFlight;
    if (pending != null) {
      await pending;
    }
    final op = _doAttach(branchId);
    _inFlight = op;
    try {
      await op;
    } finally {
      if (identical(_inFlight, op)) _inFlight = null;
    }
  }

  Future<void> _doAttach(String? branchId) async {
    if (branchId == null || branchId.isEmpty) {
      await _doStop();
      return;
    }
    if (_attachedBranchId == branchId && _channels.isNotEmpty) {
      return; // Ya suscriptos al branch correcto.
    }

    await _doStop();
    _attachedBranchId = branchId;

    final client = _ref.read(supabaseClientProvider);

    for (final entry in _tableToProviders.entries) {
      final table = entry.key;
      final providers = entry.value;

      final channel = client
          .channel('realtime:$table:$branchId')
          .onPostgresChanges(
            event: PostgresChangeEvent.all,
            schema: 'public',
            table: table,
            filter: PostgresChangeFilter(
              type: PostgresChangeFilterType.eq,
              column: 'branch_id',
              value: branchId,
            ),
            callback: (_) => _batcher.add(providers),
          )
          .subscribe((status, error) => _onStatus(table, status, error));
      _channels[table] = channel;
    }

    if (kDebugMode) {
      debugPrint(
        'RealtimeInvalidator: attached ${_channels.length} channels '
        'for branch $branchId',
      );
    }
  }

  /// La primera suscripción de un canal no recarga nada: los providers
  /// acaban de cargar datos frescos. Una RE-suscripción sí: mientras el canal
  /// estuvo caído (WiFi, laptop en reposo, pestaña en segundo plano) se
  /// perdieron eventos, y la única forma de no mostrar datos viejos es
  /// recargar lo que depende de esa tabla.
  void _onStatus(String table, RealtimeSubscribeStatus status, Object? error) {
    switch (status) {
      case RealtimeSubscribeStatus.subscribed:
        if (!_everSubscribed.add(table)) {
          _batcher.add(_tableToProviders[table] ?? const []);
        }
      case RealtimeSubscribeStatus.channelError:
      case RealtimeSubscribeStatus.timedOut:
        if (kDebugMode) {
          debugPrint('RealtimeInvalidator: $table → $status ($error)');
        }
      case RealtimeSubscribeStatus.closed:
        break;
    }
  }

  /// Equivalente a [attach] tras un cambio de sucursal.
  Future<void> reattach(String? newBranchId) => attach(newBranchId);

  /// Cierra todas las suscripciones (serializado con attach).
  Future<void> stop() async {
    final pending = _inFlight;
    if (pending != null) {
      await pending;
    }
    final op = _doStop();
    _inFlight = op;
    try {
      await op;
    } finally {
      if (identical(_inFlight, op)) _inFlight = null;
    }
  }

  Future<void> _doStop() async {
    _batcher.cancel();
    _everSubscribed.clear();
    if (_channels.isEmpty) {
      _attachedBranchId = null;
      return;
    }
    final client = _ref.read(supabaseClientProvider);
    for (final channel in _channels.values) {
      try {
        await client.removeChannel(channel);
      } catch (e) {
        if (kDebugMode) debugPrint('RealtimeInvalidator: unsubscribe error: $e');
      }
    }
    _channels.clear();
    _attachedBranchId = null;
  }

  void _invalidate(Set<ProviderOrFamily> providers) {
    for (final p in providers) {
      _ref.invalidate(p);
    }
    if (kDebugMode) {
      debugPrint(
        'RealtimeInvalidator: invalidated ${providers.length} providers',
      );
    }
  }

  /// Tablas a las que se suscribe. Debe coincidir con la migración 93.
  @visibleForTesting
  static Set<String> get subscribedTables => _tableToProviders.keys.toSet();

  /// Todos los providers que este servicio puede invalidar.
  @visibleForTesting
  static Iterable<ProviderOrFamily> get allProviders =>
      _tableToProviders.values.expand((list) => list);

  // ──────────────────────────────────────────────────────────────────────
  // Mapeo tabla → providers a invalidar
  //
  // Mantener sincronizado con la migración 93
  // (supabase/sql-next/20260916_93_realtime_todas_las_pantallas.sql): un test
  // compara las dos listas.
  //
  // SOLO providers de DATOS (FutureProvider / StreamProvider). Invalidar un
  // StateProvider le reinicia al usuario lo que eligió —el rango de fechas de
  // un reporte, el mes de la DGII— cada vez que alguien vende. El test también
  // lo impide.
  //
  // Invalidar de más es barato: un provider autoDispose sin pantalla abierta
  // no recarga nada. Invalidar de menos deja la pantalla vieja.
  // ──────────────────────────────────────────────────────────────────────

  /// Reportes que leen ventas, cobros y devoluciones.
  static final _ProviderList _salesReports = [
    reportsDataProvider,
    detailedSalesReportProvider,
    salesDailyReportProvider,
    salesByItemReportProvider,
    salesByCategoryReportProvider,
    hourlySalesReportProvider,
    salesTaxBreakdownProvider,
    taxBreakdownV2Provider,
    discountsReportProvider,
    voidedSalesReportProvider,
    suspendedSalesReportProvider,
    commissionReportProvider,
    employeeProductivityProvider,
    plReportProvider,
    operationalCloseoutReportProvider,
    paymentsReportProvider,
    cashSessionsReportProvider,
    creditAgingReportProvider,
    clientsReportProvider,
    fiscalZClosuresProvider,
    dgii607Provider,
    dgiiIt1Provider,
  ];

  /// Reportes que leen compras, gastos y pagos a suplidores.
  static final _ProviderList _purchaseReports = [
    reportsDataProvider,
    purchasesReportV2Provider,
    expensesReportProvider,
    outgoingPaymentsReportProvider,
    suppliersReportProvider,
    plReportProvider,
    operationalCloseoutReportProvider,
    dgii606Provider,
    dgiiIt1Provider,
  ];

  /// Reportes de inventario y precios.
  static final _ProviderList _inventoryReports = [
    inventoryStatusReportProvider,
    inventoryMovementsReportProvider,
    currentPricesReportProvider,
    priceHistoryReportProvider,
  ];

  static final Map<String, _ProviderList> _tableToProviders = {
    // ── Catálogo ──────────────────────────────────────────────────────────
    'products': [
      inventoryProductsProvider,
      salesProductsProvider,
      quotationProductsProvider,
      purchaseProductsProvider,
      ..._inventoryReports,
    ],
    'product_categories': [
      inventoryCategoriesProvider,
      salesCategoriesProvider,
    ],

    // ── Ventas y cobros ───────────────────────────────────────────────────
    'sales': [
      salesHistoryPageProvider,
      salesHistoryDetailProvider,
      dashboardKpisProvider,
      dashboardHeroKpisProvider,
      dashboardChartProvider,
      dashboardCloseoutProvider,
      dashboardPaymentBreakdownProvider,
      cobrosReceivablesProvider,
      customerBalancesProvider,
      cashRegisterDataProvider,
      fiscalDocumentsProvider,
      fiscalDocumentDetailProvider,
      taxesDataProvider,
      missingNcfCountProvider,
      ..._salesReports,
    ],
    'payments': [
      cobrosPaymentsProvider,
      cobrosReceivablesProvider,
      customerBalancesProvider,
      cashRegisterDataProvider,
      dashboardCloseoutProvider,
      dashboardHeroKpisProvider,
      dashboardPaymentBreakdownProvider,
      ..._salesReports,
    ],
    'returns': [
      returnsHistoryProvider,
      salesHistoryPageProvider,
      salesHistoryDetailProvider,
      dashboardCloseoutProvider,
      // El reembolso en efectivo baja el "Esperado en caja"…
      cashRegisterDataProvider,
      // …y el trigger de return_items devuelve el stock al producto.
      salesProductsProvider,
      inventoryProductsProvider,
      ..._salesReports,
    ],
    'clients': [
      clientsListProvider,
      salesClientsProvider,
      quotationClientsProvider,
      cobrosReceivablesProvider,
      customerBalancesProvider,
      clientsReportProvider,
    ],

    // ── Caja ──────────────────────────────────────────────────────────────
    'cash_sessions': [
      cashRegisterDataProvider,
      allOpenCashSessionsProvider,
      myOpenCashSessionsProvider,
      dashboardCloseoutProvider,
      cashSessionsReportProvider,
    ],
    'cash_register_movements': [
      cashRegisterDataProvider,
    ],
    'cash_registers': [
      cashRegistersProvider,
      myCashRegistersProvider,
      cashRegisterDataProvider,
    ],

    // ── Cotizaciones ──────────────────────────────────────────────────────
    'quotations': [
      quotationsFoundationProvider,
      quotationDetailProvider,
    ],
    'quotation_items': [
      quotationsFoundationProvider,
      quotationDetailProvider,
    ],

    // ── Compras, suplidores, gastos y cuentas por pagar ───────────────────
    'purchases': [
      purchasesListProvider,
      payablesListProvider,
      taxesDataProvider,
      ..._purchaseReports,
    ],
    'purchase_items': [
      purchasesListProvider,
      payablesListProvider,
    ],
    'suppliers': [
      suppliersListProvider,
      purchaseSuppliersProvider,
      expenseSuppliersProvider,
      payablesListProvider,
      suppliersReportProvider,
    ],
    'expenses': [
      expensesListProvider,
      // Un gasto pagado de la caja cambia su cuadre.
      cashRegisterDataProvider,
      ..._purchaseReports,
    ],
    'supplier_payments': [
      payablesListProvider,
      supplierPaymentsProvider,
      cashRegisterDataProvider,
      ..._purchaseReports,
    ],

    // ── Caja chica ────────────────────────────────────────────────────────
    'petty_cash_sessions': [
      pettyCashDataProvider,
    ],
    'petty_cash_movements': [
      pettyCashDataProvider,
      cashRegisterDataProvider,
    ],
    'petty_cash_categories': [
      pettyCashDataProvider,
    ],

    // ── Comprobantes fiscales ─────────────────────────────────────────────
    'ncf_sequences': [
      ncfSequenceAvailableProvider,
      posDefaultReceiptTypeProvider,
      ncfStockAlertsProvider,
      settingsDataProvider,
      taxesDataProvider,
    ],
  };
}

/// Provider singleton de RealtimeInvalidator (se crea al primer uso).
final realtimeInvalidatorProvider = Provider<RealtimeInvalidator>((ref) {
  final invalidator = RealtimeInvalidator(ref);
  ref.onDispose(invalidator.stop);
  return invalidator;
});
