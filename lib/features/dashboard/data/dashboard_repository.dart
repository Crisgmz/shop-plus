// Dashboard repository (PRD Dashboard 06).
//
// Tres RPCs Supabase:
//   - dashboard_v2_kpis(branch_id)         → 4 contadores (F1)
//   - dashboard_v2_sales_chart(branch_id, range) → serie temporal (F3)
//   - dashboard_v2_closeout(branch_id, date)     → 6 bloques (F4)
//
// El repositorio mantiene los DTOs ya públicos (`DashboardKpis`, `LatestSale`,
// `SalesSummaryPoint`) por compatibilidad con código legacy si lo hubiera,
// pero las nuevas pantallas usan los DTOs v2 (DashboardKpisV2, etc.).

import 'package:supabase_flutter/supabase_flutter.dart';

enum DashboardChartRange { month, week }

/// Hero KPIs (las 4 tarjetas de colores fuertes del Panel).
/// Origen: vista `dashboard_kpis_by_branch` en `03_reports_views.sql`.
class DashboardHeroKpis {
  const DashboardHeroKpis({
    required this.salesTodayAmount,
    required this.salesTodayCount,
    required this.salesMonthAmount,
    required this.salesMonthCount,
    required this.productsActive,
    required this.clientsActive,
  });

  factory DashboardHeroKpis.fromMap(Map<String, dynamic> map) {
    return DashboardHeroKpis(
      salesTodayAmount: _toDouble(map['sales_today_amount']),
      salesTodayCount: _toInt(map['sales_today_count']),
      salesMonthAmount: _toDouble(map['sales_month_amount']),
      salesMonthCount: _toInt(map['sales_month_count']),
      productsActive: _toInt(map['products_active']),
      clientsActive: _toInt(map['clients_active']),
    );
  }

  final double salesTodayAmount;
  final int salesTodayCount;
  final double salesMonthAmount;
  final int salesMonthCount;
  final int productsActive;
  final int clientsActive;

  static const empty = DashboardHeroKpis(
    salesTodayAmount: 0,
    salesTodayCount: 0,
    salesMonthAmount: 0,
    salesMonthCount: 0,
    productsActive: 0,
    clientsActive: 0,
  );
}

// ─────────────────────────────────────────────────────────────────────────
// DTOs v2 (PRD Dashboard 06)
// ─────────────────────────────────────────────────────────────────────────

class DashboardKpisV2 {
  const DashboardKpisV2({
    required this.totalVentas,
    required this.totalInventario,
    required this.totalClientes,
    required this.totalKits,
    this.partial = false,
  });

  factory DashboardKpisV2.fromMap(Map<String, dynamic> map) {
    return DashboardKpisV2(
      totalVentas: _toInt(map['total_ventas']),
      totalInventario: _toInt(map['total_inventario']),
      totalClientes: _toInt(map['total_clientes']),
      totalKits: _toInt(map['total_kits']),
      partial: map['partial'] == true,
    );
  }

  final int totalVentas;
  final int totalInventario;
  final int totalClientes;
  final int totalKits;
  final bool partial;
}

class DashboardChartPoint {
  const DashboardChartPoint({
    required this.date,
    required this.transactions,
    required this.total,
  });

  factory DashboardChartPoint.fromMap(Map<String, dynamic> map) {
    return DashboardChartPoint(
      date: DateTime.tryParse((map['date'] ?? '').toString()) ?? DateTime.now(),
      transactions: _toInt(map['transactions']),
      total: _toDouble(map['total']),
    );
  }

  final DateTime date;
  final int transactions;
  final double total;
}

class DashboardCloseoutSales {
  const DashboardCloseoutSales({
    required this.salesTotalNoTax,
    required this.salesTotalWithTax,
    required this.profit,
    required this.inventoryQtyOnHand,
    required this.inventoryValue,
    required this.breakdownByCategory,
    required this.transactionsCount,
    required this.avgTicket,
    required this.itemsSold,
    required this.taxAmount,
    required this.noTaxAmount,
    required this.cashAmount,
  });

  factory DashboardCloseoutSales.fromMap(Map<String, dynamic> map) {
    return DashboardCloseoutSales(
      salesTotalNoTax: _toDouble(map['sales_total_no_tax']),
      salesTotalWithTax: _toDouble(map['sales_total_with_tax']),
      profit: _toDouble(map['profit']),
      inventoryQtyOnHand: _toDouble(map['inventory_qty_on_hand']),
      inventoryValue: _toDouble(map['inventory_value']),
      breakdownByCategory: _toCategoryList(map['breakdown_by_category']),
      transactionsCount: _toInt(map['transactions_count']),
      avgTicket: _toDouble(map['avg_ticket']),
      itemsSold: _toDouble(map['items_sold']),
      taxAmount: _toDouble(map['tax_amount']),
      noTaxAmount: _toDouble(map['no_tax_amount']),
      cashAmount: _toDouble(map['cash_amount']),
    );
  }

  final double salesTotalNoTax;
  final double salesTotalWithTax;
  final double profit;
  final double inventoryQtyOnHand;
  final double inventoryValue;
  final List<DashboardCategoryAmount> breakdownByCategory;
  final int transactionsCount;
  final double avgTicket;
  final double itemsSold;
  final double taxAmount;
  final double noTaxAmount;
  final double cashAmount;
}

class DashboardCategoryAmount {
  const DashboardCategoryAmount({required this.name, required this.amount});

  factory DashboardCategoryAmount.fromMap(Map<String, dynamic> map) {
    return DashboardCategoryAmount(
      name: (map['name'] ?? '').toString(),
      amount: _toDouble(map['amount']),
    );
  }

  final String name;
  final double amount;
}

/// Distribución de la venta del día agrupada por método de pago.
/// Se calcula desde la tabla `payments` en `fetchPaymentBreakdown`.
class DashboardPaymentBreakdown {
  const DashboardPaymentBreakdown({
    required this.entries,
    required this.total,
  });

  final List<DashboardPaymentEntry> entries;
  final double total;

  static const empty = DashboardPaymentBreakdown(entries: [], total: 0);
}

class DashboardPaymentEntry {
  const DashboardPaymentEntry({
    required this.method,
    required this.label,
    required this.amount,
    required this.count,
  });

  final String method;
  final String label;
  final double amount;
  final int count;
}

class DashboardCloseoutCredit {
  const DashboardCloseoutCredit({
    required this.debits,
    required this.credits,
    required this.storeAccountBalanceTotal,
  });

  factory DashboardCloseoutCredit.fromMap(Map<String, dynamic> map) {
    return DashboardCloseoutCredit(
      debits: _toDouble(map['debits']),
      credits: _toDouble(map['credits']),
      storeAccountBalanceTotal: _toDouble(map['store_account_balance_total']),
    );
  }

  final double debits;
  final double credits;
  final double storeAccountBalanceTotal;
}

class DashboardCloseoutReturns {
  const DashboardCloseoutReturns({
    required this.returnsTotal,
    required this.breakdownByItem,
    required this.transactionsCount,
    required this.itemsReturned,
    required this.taxAmount,
    required this.returnsTableAvailable,
  });

  factory DashboardCloseoutReturns.fromMap(Map<String, dynamic> map) {
    final raw = map['breakdown_by_item'];
    final items = raw is List
        ? raw
              .map(
                (item) => DashboardReturnItem.fromMap(
                  Map<String, dynamic>.from(item as Map),
                ),
              )
              .toList(growable: false)
        : const <DashboardReturnItem>[];
    return DashboardCloseoutReturns(
      returnsTotal: _toDouble(map['returns_total']),
      breakdownByItem: items,
      transactionsCount: _toInt(map['transactions_count']),
      itemsReturned: _toDouble(map['items_returned']),
      taxAmount: _toDouble(map['tax_amount']),
      returnsTableAvailable: map['returns_table_available'] == true,
    );
  }

  final double returnsTotal;
  final List<DashboardReturnItem> breakdownByItem;
  final int transactionsCount;
  final double itemsReturned;
  final double taxAmount;

  /// Cuando false, los datos provienen del proxy `sales.status = voided` —
  /// la tabla `returns` (PRD F5) aún no existe.
  final bool returnsTableAvailable;
}

class DashboardReturnItem {
  const DashboardReturnItem({
    required this.description,
    required this.quantity,
    required this.amount,
  });

  factory DashboardReturnItem.fromMap(Map<String, dynamic> map) {
    return DashboardReturnItem(
      description: (map['description'] ?? '').toString(),
      quantity: _toDouble(map['quantity']),
      amount: _toDouble(map['amount']),
    );
  }

  final String description;
  final double quantity;
  final double amount;
}

class DashboardCloseoutPurchases {
  const DashboardCloseoutPurchases({
    required this.receivingsTotalNoTax,
    required this.receivingsTotalWithTax,
    required this.transactionsCount,
    required this.avgTicket,
    required this.itemsReceived,
    required this.taxAmount,
    required this.noTaxAmount,
  });

  factory DashboardCloseoutPurchases.fromMap(Map<String, dynamic> map) {
    return DashboardCloseoutPurchases(
      receivingsTotalNoTax: _toDouble(map['receivings_total_no_tax']),
      receivingsTotalWithTax: _toDouble(map['receivings_total_with_tax']),
      transactionsCount: _toInt(map['transactions_count']),
      avgTicket: _toDouble(map['avg_ticket']),
      itemsReceived: _toDouble(map['items_received']),
      taxAmount: _toDouble(map['tax_amount']),
      noTaxAmount: _toDouble(map['no_tax_amount']),
    );
  }

  final double receivingsTotalNoTax;
  final double receivingsTotalWithTax;
  final int transactionsCount;
  final double avgTicket;
  final double itemsReceived;
  final double taxAmount;
  final double noTaxAmount;
}

class DashboardCloseoutExpenses {
  const DashboardCloseoutExpenses({
    required this.expensesTotal,
    required this.transactionsCount,
  });

  factory DashboardCloseoutExpenses.fromMap(Map<String, dynamic> map) {
    return DashboardCloseoutExpenses(
      expensesTotal: _toDouble(map['expenses_total']),
      transactionsCount: _toInt(map['transactions_count']),
    );
  }

  final double expensesTotal;
  final int transactionsCount;
}

class DashboardCashMonitoring {
  const DashboardCashMonitoring({
    required this.enabled,
    this.sessionId,
    this.openedAt,
    this.closedAt,
    this.openingAmount,
    this.expectedAmount,
    this.closingAmount,
    this.differenceAmount,
    this.status,
  });

  factory DashboardCashMonitoring.fromMap(Map<String, dynamic> map) {
    return DashboardCashMonitoring(
      enabled: map['enabled'] == true,
      sessionId: map['session_id']?.toString(),
      openedAt: DateTime.tryParse(map['opened_at']?.toString() ?? ''),
      closedAt: DateTime.tryParse(map['closed_at']?.toString() ?? ''),
      openingAmount:
          map['opening_amount'] == null ? null : _toDouble(map['opening_amount']),
      expectedAmount:
          map['expected_amount'] == null ? null : _toDouble(map['expected_amount']),
      closingAmount:
          map['closing_amount'] == null ? null : _toDouble(map['closing_amount']),
      differenceAmount: map['difference_amount'] == null
          ? null
          : _toDouble(map['difference_amount']),
      status: map['status']?.toString(),
    );
  }

  final bool enabled;
  final String? sessionId;
  final DateTime? openedAt;
  final DateTime? closedAt;
  final double? openingAmount;
  final double? expectedAmount;
  final double? closingAmount;
  final double? differenceAmount;
  final String? status;
}

class DashboardCloseout {
  const DashboardCloseout({
    required this.date,
    required this.sales,
    required this.credit,
    required this.returns,
    required this.purchases,
    required this.expenses,
    required this.cashMonitoring,
    this.partial = false,
  });

  factory DashboardCloseout.fromMap(Map<String, dynamic> map) {
    return DashboardCloseout(
      date: DateTime.tryParse(map['date']?.toString() ?? '') ?? DateTime.now(),
      sales: DashboardCloseoutSales.fromMap(
        Map<String, dynamic>.from(map['sales'] as Map? ?? {}),
      ),
      credit: DashboardCloseoutCredit.fromMap(
        Map<String, dynamic>.from(map['credit'] as Map? ?? {}),
      ),
      returns: DashboardCloseoutReturns.fromMap(
        Map<String, dynamic>.from(map['returns'] as Map? ?? {}),
      ),
      purchases: DashboardCloseoutPurchases.fromMap(
        Map<String, dynamic>.from(map['purchases'] as Map? ?? {}),
      ),
      expenses: DashboardCloseoutExpenses.fromMap(
        Map<String, dynamic>.from(map['expenses'] as Map? ?? {}),
      ),
      cashMonitoring: DashboardCashMonitoring.fromMap(
        Map<String, dynamic>.from(map['cash_monitoring'] as Map? ?? {}),
      ),
      partial: map['partial'] == true,
    );
  }

  final DateTime date;
  final DashboardCloseoutSales sales;
  final DashboardCloseoutCredit credit;
  final DashboardCloseoutReturns returns;
  final DashboardCloseoutPurchases purchases;
  final DashboardCloseoutExpenses expenses;
  final DashboardCashMonitoring cashMonitoring;
  final bool partial;
}

// ─────────────────────────────────────────────────────────────────────────
// Repository
// ─────────────────────────────────────────────────────────────────────────

class DashboardRepository {
  DashboardRepository(this._client);

  final SupabaseClient _client;

  Future<DashboardKpisV2> fetchKpis() async {
    final result = await _client.rpc('dashboard_v2_kpis');
    final map = result is Map
        ? Map<String, dynamic>.from(result)
        : <String, dynamic>{};
    return DashboardKpisV2.fromMap(map);
  }

  /// Lee `dashboard_kpis_by_branch` filtrando por la sucursal actual del
  /// usuario. Devuelve los montos de hoy/mes y contadores activos.
  Future<DashboardHeroKpis> fetchHeroKpis() async {
    final branchIdResult = await _client.rpc('current_branch_id');
    final branchId = branchIdResult?.toString();
    if (branchId == null || branchId.isEmpty) {
      return DashboardHeroKpis.empty;
    }

    final rows = await _client
        .from('dashboard_kpis_by_branch')
        .select()
        .eq('branch_id', branchId)
        .limit(1);

    if (rows.isEmpty) return DashboardHeroKpis.empty;
    return DashboardHeroKpis.fromMap(
      Map<String, dynamic>.from(rows.first as Map),
    );
  }

  Future<List<DashboardChartPoint>> fetchSalesChart(
    DashboardChartRange range,
  ) async {
    final result = await _client.rpc(
      'dashboard_v2_sales_chart',
      params: {'p_range': range == DashboardChartRange.week ? 'week' : 'month'},
    );
    if (result is! List) return const [];
    return result
        .map((item) => DashboardChartPoint.fromMap(
              Map<String, dynamic>.from(item as Map),
            ))
        .toList(growable: false);
  }

  Future<DashboardCloseout> fetchCloseout(DateTime date) async {
    final iso = '${date.year.toString().padLeft(4, '0')}-'
        '${date.month.toString().padLeft(2, '0')}-'
        '${date.day.toString().padLeft(2, '0')}';
    final result = await _client.rpc(
      'dashboard_v2_closeout',
      params: {'p_date': iso},
    );
    final map = result is Map
        ? Map<String, dynamic>.from(result)
        : <String, dynamic>{};
    return DashboardCloseout.fromMap(map);
  }

  /// Distribución de los cobros del día agrupada por método de pago.
  /// Lee directamente de `payments` filtrando por la sucursal del usuario
  /// y el rango [day 00:00, day+1 00:00) en hora local.
  Future<DashboardPaymentBreakdown> fetchPaymentBreakdown(DateTime date) async {
    // Medianoche LOCAL convertida a UTC: `toIso8601String()` de una hora local
    // no lleva zona y el servidor la leía como UTC (el día corría 4 horas).
    final start = DateTime(date.year, date.month, date.day);
    final end = start.add(const Duration(days: 1));

    // Solo la sucursal actual: un usuario con varias sucursales veía la suma
    // de todas.
    final branch = await _client.rpc('current_branch_id');
    final branchId = branch?.toString() ?? '';
    if (branchId.isEmpty) {
      return const DashboardPaymentBreakdown(entries: [], total: 0);
    }

    final rows = await _client
        .from('payments')
        .select('payment_method, amount')
        .eq('branch_id', branchId)
        .gte('paid_at', start.toUtc().toIso8601String())
        .lt('paid_at', end.toUtc().toIso8601String());

    final totals = <String, double>{};
    final counts = <String, int>{};
    for (final row in rows) {
      final map = Map<String, dynamic>.from(row as Map);
      final method = (map['payment_method'] ?? '').toString();
      if (method.isEmpty) continue;
      final amount = _toDouble(map['amount']);
      totals[method] = (totals[method] ?? 0) + amount;
      counts[method] = (counts[method] ?? 0) + 1;
    }

    final entries = totals.entries
        .map((e) => DashboardPaymentEntry(
              method: e.key,
              label: _paymentMethodLabel(e.key),
              amount: e.value,
              count: counts[e.key] ?? 0,
            ))
        .toList()
      ..sort((a, b) => b.amount.compareTo(a.amount));

    final total = totals.values.fold<double>(0, (a, b) => a + b);
    return DashboardPaymentBreakdown(entries: entries, total: total);
  }

  String _paymentMethodLabel(String method) {
    switch (method) {
      case 'cash':
        return 'Efectivo';
      case 'card':
        return 'Tarjeta';
      case 'transfer':
        return 'Transferencia';
      case 'mobile':
        return 'Pago móvil';
      case 'credit':
        return 'Crédito';
      case 'mixed':
        return 'Mixto';
      default:
        return method;
    }
  }
}

// ─────────────────────────────────────────────────────────────────────────
// Helpers
// ─────────────────────────────────────────────────────────────────────────

double _toDouble(dynamic value) {
  if (value == null) return 0;
  if (value is double) return value;
  if (value is int) return value.toDouble();
  return double.tryParse(value.toString()) ?? 0;
}

int _toInt(dynamic value) {
  if (value == null) return 0;
  if (value is int) return value;
  if (value is double) return value.toInt();
  return int.tryParse(value.toString()) ?? 0;
}

List<DashboardCategoryAmount> _toCategoryList(dynamic value) {
  if (value is! List) return const [];
  return value
      .map((item) => DashboardCategoryAmount.fromMap(
            Map<String, dynamic>.from(item as Map),
          ))
      .toList(growable: false);
}
