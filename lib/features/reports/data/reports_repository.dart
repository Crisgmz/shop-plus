import 'package:supabase_flutter/supabase_flutter.dart';

enum ReportPeriod { monthly, weekly }

class ReportSalesPoint {
  ReportSalesPoint({
    required this.periodStart,
    required this.periodLabel,
    required this.totalAmount,
    required this.transactionCount,
  });

  final DateTime periodStart;
  final String periodLabel;
  final double totalAmount;
  final int transactionCount;

  factory ReportSalesPoint.fromMap(Map<String, dynamic> map) {
    return ReportSalesPoint(
      periodStart: DateTime.tryParse((map['period_start'] ?? '').toString()) ??
          DateTime.fromMillisecondsSinceEpoch(0),
      periodLabel: (map['period_label'] ?? '').toString(),
      totalAmount: _toDouble(map['total_amount']),
      transactionCount: _toInt(map['transaction_count']),
    );
  }
}

class ReceivableReport {
  ReceivableReport({
    required this.invoicesOpen,
    required this.totalBalanceDue,
    required this.totalInvoiced,
    required this.totalCollected,
  });

  final int invoicesOpen;
  final double totalBalanceDue;
  final double totalInvoiced;
  final double totalCollected;

  factory ReceivableReport.fromMap(Map<String, dynamic> map) {
    return ReceivableReport(
      invoicesOpen: _toInt(map['invoices_open']),
      totalBalanceDue: _toDouble(map['total_balance_due']),
      totalInvoiced: _toDouble(map['total_invoiced']),
      totalCollected: _toDouble(map['total_collected']),
    );
  }
}

class LowStockReportItem {
  LowStockReportItem({
    required this.name,
    required this.sku,
    required this.stock,
    required this.minStock,
    required this.price,
  });

  final String name;
  final String? sku;
  final double stock;
  final double minStock;
  final double price;

  factory LowStockReportItem.fromMap(Map<String, dynamic> map) {
    return LowStockReportItem(
      name: (map['name'] ?? '').toString(),
      sku: map['sku']?.toString(),
      stock: _toDouble(map['stock']),
      minStock: _toDouble(map['min_stock']),
      price: _toDouble(map['price']),
    );
  }
}

class NcfUsageItem {
  NcfUsageItem({
    required this.receiptType,
    required this.prefix,
    required this.currentNumber,
    required this.maxNumber,
    required this.available,
    required this.expiresOn,
  });

  final String receiptType;
  final String prefix;
  final int currentNumber;
  final int? maxNumber;
  final int available;
  final DateTime? expiresOn;

  factory NcfUsageItem.fromMap(Map<String, dynamic> map) {
    return NcfUsageItem(
      receiptType: (map['receipt_type'] ?? '').toString(),
      prefix: (map['prefix'] ?? '').toString(),
      currentNumber: _toInt(map['current_number']),
      maxNumber: map['max_number'] == null ? null : _toInt(map['max_number']),
      available: _toInt(map['available']),
      expiresOn: map['expires_on'] == null
          ? null
          : DateTime.tryParse(map['expires_on'].toString()),
    );
  }
}

class ReportsData {
  ReportsData({
    required this.period,
    required this.salesPoints,
    required this.receivable,
    required this.lowStockItems,
    required this.ncfItems,
  });

  final ReportPeriod period;
  final List<ReportSalesPoint> salesPoints;
  final ReceivableReport? receivable;
  final List<LowStockReportItem> lowStockItems;
  final List<NcfUsageItem> ncfItems;
}

// ── Sales Tax Breakdown ───────────────────────────────────────────────────────

class SalesTaxRow {
  SalesTaxRow({
    required this.saleId,
    required this.saleNumber,
    required this.saleDate,
    required this.receiptType,
    required this.clientName,
    required this.taxableAmount,
    required this.exemptAmount,
    required this.taxAmount,
    required this.serviceChargeAmount,
    required this.totalAmount,
  });

  final String saleId;
  final String saleNumber;
  final DateTime saleDate;
  final String receiptType;
  final String clientName;
  final double taxableAmount;
  final double exemptAmount;
  final double taxAmount;
  final double serviceChargeAmount;
  final double totalAmount;

  factory SalesTaxRow.fromMap(Map<String, dynamic> map) {
    return SalesTaxRow(
      saleId: (map['sale_id'] ?? '').toString(),
      saleNumber: (map['sale_number'] ?? '').toString(),
      saleDate: DateTime.tryParse((map['sale_date'] ?? '').toString()) ??
          DateTime.fromMillisecondsSinceEpoch(0),
      receiptType: (map['receipt_type'] ?? '').toString(),
      clientName: (map['client_name'] ?? '').toString(),
      taxableAmount: _toDouble(map['taxable_amount']),
      exemptAmount: _toDouble(map['exempt_amount']),
      taxAmount: _toDouble(map['tax_amount']),
      serviceChargeAmount: _toDouble(map['service_charge_amount']),
      totalAmount: _toDouble(map['total_amount']),
    );
  }
}

// ── Report Presets ────────────────────────────────────────────────────────────

class ReportPreset {
  ReportPreset({
    required this.id,
    required this.branchId,
    required this.reportKey,
    required this.name,
    required this.isDefault,
    required this.isActive,
    this.description,
    this.filtersJson = const {},
  });

  final String id;
  final String branchId;
  final String reportKey;
  final String name;
  final String? description;
  final Map<String, dynamic> filtersJson;
  final bool isDefault;
  final bool isActive;

  factory ReportPreset.fromMap(Map<String, dynamic> map) {
    return ReportPreset(
      id: (map['id'] ?? '').toString(),
      branchId: (map['branch_id'] ?? '').toString(),
      reportKey: (map['report_key'] ?? '').toString(),
      name: (map['name'] ?? '').toString(),
      description: map['description']?.toString(),
      filtersJson: map['filters_json'] is Map
          ? Map<String, dynamic>.from(map['filters_json'] as Map)
          : const {},
      isDefault: map['is_default'] == true,
      isActive: map['is_active'] != false,
    );
  }
}

// ── Report Exports ────────────────────────────────────────────────────────────

class ReportExport {
  ReportExport({
    required this.id,
    required this.branchId,
    required this.reportKey,
    required this.exportFormat,
    required this.status,
    required this.requestedAt,
    this.generatedAt,
    this.expiresAt,
    this.downloadUrl,
    this.fileName,
    this.fileSizeBytes,
    this.errorMessage,
  });

  final String id;
  final String branchId;
  final String reportKey;
  final String exportFormat;
  final String status;
  final DateTime requestedAt;
  final DateTime? generatedAt;
  final DateTime? expiresAt;
  final String? downloadUrl;
  final String? fileName;
  final int? fileSizeBytes;
  final String? errorMessage;

  bool get isCompleted => status == 'completed';
  bool get isFailed => status == 'failed';
  bool get isPending => status == 'pending' || status == 'processing';
  bool get hasDownload => downloadUrl != null && downloadUrl!.isNotEmpty;

  factory ReportExport.fromMap(Map<String, dynamic> map) {
    return ReportExport(
      id: (map['id'] ?? '').toString(),
      branchId: (map['branch_id'] ?? '').toString(),
      reportKey: (map['report_key'] ?? '').toString(),
      exportFormat: (map['export_format'] ?? '').toString(),
      status: (map['status'] ?? 'pending').toString(),
      requestedAt:
          DateTime.tryParse((map['requested_at'] ?? '').toString()) ??
              DateTime.now(),
      generatedAt: map['generated_at'] == null
          ? null
          : DateTime.tryParse(map['generated_at'].toString()),
      expiresAt: map['expires_at'] == null
          ? null
          : DateTime.tryParse(map['expires_at'].toString()),
      downloadUrl: map['download_url']?.toString(),
      fileName: map['file_name']?.toString(),
      fileSizeBytes: map['file_size_bytes'] == null
          ? null
          : _toInt(map['file_size_bytes']),
      errorMessage: map['error_message']?.toString(),
    );
  }
}

class ReportsRepository {
  ReportsRepository(this._client);

  final SupabaseClient _client;

  Future<ReportsData> fetchReports(ReportPeriod period) async {
    final branchId = await _currentBranchId();

    final futures = await Future.wait<dynamic>([
      _fetchSalesPoints(branchId, period),
      _fetchReceivable(branchId),
      _fetchLowStock(branchId),
      _fetchNcfUsage(branchId),
    ]);

    return ReportsData(
      period: period,
      salesPoints: futures[0] as List<ReportSalesPoint>,
      receivable: futures[1] as ReceivableReport?,
      lowStockItems: futures[2] as List<LowStockReportItem>,
      ncfItems: futures[3] as List<NcfUsageItem>,
    );
  }

  Future<List<ReportSalesPoint>> _fetchSalesPoints(
    String? branchId,
    ReportPeriod period,
  ) async {
    final view = period == ReportPeriod.monthly
        ? 'sales_monthly_summary'
        : 'sales_weekly_summary';

    final rows = await (branchId == null
        ? _client.from(view).select().order('period_start')
        : _client
            .from(view)
            .select()
            .eq('branch_id', branchId)
            .order('period_start'));

    return rows
        .map((item) =>
            ReportSalesPoint.fromMap(Map<String, dynamic>.from(item as Map)))
        .toList(growable: false);
  }

  Future<ReceivableReport?> _fetchReceivable(String? branchId) async {
    final rows = await (branchId == null
        ? _client.from('accounts_receivable_summary').select().limit(1)
        : _client
            .from('accounts_receivable_summary')
            .select()
            .eq('branch_id', branchId)
            .limit(1));

    if (rows.isEmpty) return null;

    return ReceivableReport.fromMap(Map<String, dynamic>.from(rows.first as Map));
  }

  Future<List<LowStockReportItem>> _fetchLowStock(String? branchId) async {
    final rows = await (branchId == null
        ? _client.from('inventory_low_stock_view').select().limit(30)
        : _client
            .from('inventory_low_stock_view')
            .select()
            .eq('branch_id', branchId)
            .limit(30));

    return rows
        .map((item) =>
            LowStockReportItem.fromMap(Map<String, dynamic>.from(item as Map)))
        .toList(growable: false);
  }

  Future<List<NcfUsageItem>> _fetchNcfUsage(String? branchId) async {
    final rows = await (branchId == null
        ? _client.from('ncf_usage_summary').select().limit(30)
        : _client
            .from('ncf_usage_summary')
            .select()
            .eq('branch_id', branchId)
            .limit(30));

    return rows
        .map((item) => NcfUsageItem.fromMap(Map<String, dynamic>.from(item as Map)))
        .toList(growable: false);
  }

  Future<List<ReportPreset>> fetchPresets() async {
    final branchId = await _currentBranchId();
    if (branchId == null) return const [];

    final rows = await _client
        .from('report_presets')
        .select('id, branch_id, report_key, name, description, filters_json, is_default, is_active')
        .eq('branch_id', branchId)
        .eq('is_active', true)
        .order('is_default', ascending: false)
        .order('name');

    return rows
        .map((item) =>
            ReportPreset.fromMap(Map<String, dynamic>.from(item as Map)))
        .toList(growable: false);
  }

  Future<List<SalesTaxRow>> fetchSalesTaxBreakdown({
    DateTime? from,
    DateTime? to,
    int limit = 500,
  }) async {
    final branchId = await _currentBranchId();
    if (branchId == null) return const [];

    var query = _client
        .from('sales_tax_breakdown_view')
        .select(
          'sale_id, sale_number, sale_date, receipt_type, '
          'taxable_amount, exempt_amount, tax_amount, '
          'service_charge_amount, total_amount, client_name',
        )
        .eq('branch_id', branchId);

    if (from != null) {
      query = query.gte('sale_date', from.toIso8601String().split('T').first);
    }
    if (to != null) {
      query = query.lte('sale_date', to.toIso8601String().split('T').first);
    }

    final rows = await query
        .order('sale_date', ascending: false)
        .limit(limit);

    return rows
        .map((item) =>
            SalesTaxRow.fromMap(Map<String, dynamic>.from(item as Map)))
        .toList(growable: false);
  }

  Future<void> requestExport({
    required String reportKey,
    required String exportFormat,
  }) async {
    final branchId = await _currentBranchId();
    if (branchId == null) {
      throw Exception('No hay sucursal asignada para este usuario.');
    }

    await _client.from('report_exports').insert({
      'branch_id': branchId,
      'report_key': reportKey,
      'export_format': exportFormat,
      'status': 'pending',
    });
  }

  Future<List<ReportExport>> fetchRecentExports({int limit = 20}) async {
    final branchId = await _currentBranchId();
    if (branchId == null) return const [];

    final rows = await _client
        .from('report_exports')
        .select(
          'id, branch_id, report_key, export_format, status, '
          'requested_at, generated_at, expires_at, download_url, '
          'file_name, file_size_bytes, error_message',
        )
        .eq('branch_id', branchId)
        .order('requested_at', ascending: false)
        .limit(limit);

    return rows
        .map((item) =>
            ReportExport.fromMap(Map<String, dynamic>.from(item as Map)))
        .toList(growable: false);
  }

  // ───────────────────────────────────────────────────────────────────────
  // PRD 07 v2: lecturas para los 6 reportes operativos del round 1.
  // ───────────────────────────────────────────────────────────────────────

  /// Reporte maestro de ventas. Lee `mv_sales_daily` (vista wrapper con RLS
  /// `sales_daily_view`). Devuelve filas agregadas día/cajero/NCF.
  Future<List<SalesDailyRow>> fetchSalesDaily({
    required DateTime from,
    required DateTime to,
  }) async {
    final branchId = await _currentBranchId();
    if (branchId == null) return const [];

    final rows = await _client
        .from('sales_daily_view')
        .select()
        .eq('branch_id', branchId)
        .gte('sale_day', _isoDate(from))
        .lte('sale_day', _isoDate(to))
        .order('sale_day', ascending: true);

    return rows
        .map((item) => SalesDailyRow.fromMap(
              Map<String, dynamic>.from(item as Map),
            ))
        .toList(growable: false);
  }

  /// Sesiones de caja en el rango. Lee `cash_session_summary_view`.
  Future<List<CashSessionRow>> fetchCashSessions({
    required DateTime from,
    required DateTime to,
  }) async {
    final branchId = await _currentBranchId();
    if (branchId == null) return const [];

    final fromIso = _localStartOfDayUtcIso(from);
    final toIso = _localEndOfDayUtcIso(to);

    final rows = await _client
        .from('cash_session_summary_view')
        .select()
        .eq('branch_id', branchId)
        .gte('opened_at', fromIso)
        .lte('opened_at', toIso)
        .order('opened_at', ascending: false);

    return rows
        .map((item) => CashSessionRow.fromMap(
              Map<String, dynamic>.from(item as Map),
            ))
        .toList(growable: false);
  }

  /// Pagos recibidos en el rango (cobros). Lee `payments` agrupando por método.
  Future<List<PaymentMethodRow>> fetchPaymentsByMethod({
    required DateTime from,
    required DateTime to,
  }) async {
    final branchId = await _currentBranchId();
    if (branchId == null) return const [];

    final fromIso = _localStartOfDayUtcIso(from);
    final toIso = _localEndOfDayUtcIso(to);

    final rows = await _client
        .from('payments')
        .select('payment_method, amount')
        .eq('branch_id', branchId)
        .gte('paid_at', fromIso)
        .lte('paid_at', toIso);

    final byMethod = <String, _MutablePaymentBucket>{};
    for (final raw in rows) {
      final row = Map<String, dynamic>.from(raw as Map);
      final method = (row['payment_method'] ?? 'cash').toString();
      final amount = _toDouble(row['amount']);
      byMethod.update(
        method,
        (b) {
          b.total += amount;
          b.count += 1;
          return b;
        },
        ifAbsent: () => _MutablePaymentBucket(method: method)
          ..total = amount
          ..count = 1,
      );
    }

    return byMethod.values
        .map((b) => PaymentMethodRow(
              method: b.method,
              total: b.total,
              count: b.count,
            ))
        .toList(growable: false)
      ..sort((a, b) => b.total.compareTo(a.total));
  }

  /// "Pagos" salientes en el rango: gastos + compras pagadas.
  /// Para simplificar este round juntamos las dos fuentes y etiquetamos cada
  /// fila con su tipo.
  Future<List<OutgoingPaymentRow>> fetchOutgoingPayments({
    required DateTime from,
    required DateTime to,
  }) async {
    final branchId = await _currentBranchId();
    if (branchId == null) return const [];

    final fromIso = _isoDate(from);
    final toIso = _isoDate(to);

    final expenses = await _client
        .from('expenses')
        .select('expense_date, category, description, amount, payment_method')
        .eq('branch_id', branchId)
        .gte('expense_date', fromIso)
        .lte('expense_date', toIso)
        .order('expense_date', ascending: false);

    final purchases = await _client
        .from('purchases')
        .select('purchase_date, purchase_number, total_amount, status')
        .eq('branch_id', branchId)
        .gte('purchase_date', fromIso)
        .lte('purchase_date', toIso)
        .order('purchase_date', ascending: false);

    final out = <OutgoingPaymentRow>[];
    for (final raw in expenses) {
      final row = Map<String, dynamic>.from(raw as Map);
      out.add(OutgoingPaymentRow(
        date:
            DateTime.tryParse(row['expense_date']?.toString() ?? '') ??
                DateTime.now(),
        kind: 'Gasto',
        description: (row['description'] ?? row['category'] ?? 'Gasto')
            .toString(),
        amount: _toDouble(row['amount']),
        paymentMethod: row['payment_method']?.toString(),
      ));
    }
    for (final raw in purchases) {
      final row = Map<String, dynamic>.from(raw as Map);
      final status = (row['status'] ?? '').toString();
      if (status == 'cancelled' || status == 'draft') continue;
      out.add(OutgoingPaymentRow(
        date: DateTime.tryParse(row['purchase_date']?.toString() ?? '') ??
            DateTime.now(),
        kind: 'Compra',
        description: 'Compra ${row['purchase_number'] ?? ''}'.trim(),
        amount: _toDouble(row['total_amount']),
        paymentMethod: null,
      ));
    }
    out.sort((a, b) => b.date.compareTo(a.date));
    return out;
  }

  /// Ventas suspendidas / cuentas abiertas en el rango.
  Future<List<SuspendedSaleRow>> fetchSuspendedSales({
    required DateTime from,
    required DateTime to,
  }) async {
    final branchId = await _currentBranchId();
    if (branchId == null) return const [];

    final fromIso = _localStartOfDayUtcIso(from);
    final toIso = _localEndOfDayUtcIso(to);

    final rows = await _client
        .from('sales')
        .select(
          'id, sale_number, client_id, status, sale_date, total_amount, '
          'clients(full_name)',
        )
        .eq('branch_id', branchId)
        .or('status.eq.pending,status.eq.draft')
        .gte('sale_date', fromIso)
        .lte('sale_date', toIso)
        .order('sale_date', ascending: false);

    return rows
        .map((item) => SuspendedSaleRow.fromMap(
              Map<String, dynamic>.from(item as Map),
            ))
        .toList(growable: false);
  }

  /// Reusa el RPC del dashboard para liquidación operativa.
  Future<Map<String, dynamic>> fetchOperationalCloseout({
    required DateTime date,
  }) async {
    final result = await _client.rpc(
      'dashboard_v2_closeout',
      params: {'p_date': _isoDate(date)},
    );
    if (result is Map) {
      return Map<String, dynamic>.from(result);
    }
    return const {};
  }

  // ───────────────────────────────────────────────────────────────────────
  // PRD 07 Round 2: views adicionales
  // ───────────────────────────────────────────────────────────────────────

  Future<List<EmployeeProductivityRow>> fetchEmployeeProductivity({
    required DateTime from,
    required DateTime to,
  }) async {
    final branchId = await _currentBranchId();
    if (branchId == null) return const [];

    final rows = await _client
        .from('report_employees_view')
        .select()
        .eq('branch_id', branchId)
        .gte('sale_day', _isoDate(from))
        .lte('sale_day', _isoDate(to))
        .order('sales_total', ascending: false);

    return rows
        .map((item) => EmployeeProductivityRow.fromMap(
              Map<String, dynamic>.from(item as Map),
            ))
        .toList(growable: false);
  }

  Future<Map<String, dynamic>> fetchCommission({
    required DateTime from,
    required DateTime to,
  }) async {
    final result = await _client.rpc(
      'report_commission',
      params: {'p_from': _isoDate(from), 'p_to': _isoDate(to)},
    );
    if (result is Map) {
      return Map<String, dynamic>.from(result);
    }
    return const {};
  }

  Future<List<InventoryStatusRow>> fetchInventoryStatus() async {
    final branchId = await _currentBranchId();
    if (branchId == null) return const [];
    final rows = await _client
        .from('report_inventory_status_view')
        .select()
        .eq('branch_id', branchId)
        .order('inventory_value', ascending: false);
    return rows
        .map((item) => InventoryStatusRow.fromMap(
              Map<String, dynamic>.from(item as Map),
            ))
        .toList(growable: false);
  }

  Future<List<SalesByItemRow>> fetchSalesByItem({
    required DateTime from,
    required DateTime to,
  }) async {
    final branchId = await _currentBranchId();
    if (branchId == null) return const [];
    final rows = await _client
        .from('sales_by_item_view')
        .select()
        .eq('branch_id', branchId)
        .gte('sale_day', _isoDate(from))
        .lte('sale_day', _isoDate(to))
        .order('net_total', ascending: false);
    return rows
        .map((item) => SalesByItemRow.fromMap(
              Map<String, dynamic>.from(item as Map),
            ))
        .toList(growable: false);
  }

  Future<List<SalesByCategoryRow>> fetchSalesByCategory({
    required DateTime from,
    required DateTime to,
  }) async {
    final branchId = await _currentBranchId();
    if (branchId == null) return const [];
    final rows = await _client
        .from('sales_by_category_view')
        .select()
        .eq('branch_id', branchId)
        .gte('sale_day', _isoDate(from))
        .lte('sale_day', _isoDate(to))
        .order('net_total', ascending: false);
    return rows
        .map((item) => SalesByCategoryRow.fromMap(
              Map<String, dynamic>.from(item as Map),
            ))
        .toList(growable: false);
  }

  Future<List<PriceRow>> fetchCurrentPrices() async {
    final branchId = await _currentBranchId();
    if (branchId == null) return const [];
    final rows = await _client
        .from('report_current_prices_view')
        .select()
        .eq('branch_id', branchId)
        .order('name');
    return rows
        .map((item) => PriceRow.fromMap(
              Map<String, dynamic>.from(item as Map),
            ))
        .toList(growable: false);
  }

  Future<List<PriceHistoryRow>> fetchPriceHistory({
    required DateTime from,
    required DateTime to,
  }) async {
    final branchId = await _currentBranchId();
    if (branchId == null) return const [];
    final rows = await _client
        .from('vw_product_price_history_recent')
        .select()
        .eq('branch_id', branchId)
        .gte('changed_at', from.toUtc().toIso8601String())
        .lte('changed_at', to.toUtc().toIso8601String())
        .order('changed_at', ascending: false);
    return rows
        .map((item) => PriceHistoryRow.fromMap(
              Map<String, dynamic>.from(item as Map),
            ))
        .toList(growable: false);
  }

  Future<List<InventoryMovementDailyRow>> fetchInventoryMovements({
    required DateTime from,
    required DateTime to,
    List<String>? movementTypes,
  }) async {
    final branchId = await _currentBranchId();
    if (branchId == null) return const [];
    var query = _client
        .from('inventory_movements_daily_view')
        .select()
        .eq('branch_id', branchId)
        .gte('movement_day', _isoDate(from))
        .lte('movement_day', _isoDate(to));
    if (movementTypes != null && movementTypes.isNotEmpty) {
      query = query.inFilter('movement_type', movementTypes);
    }
    final rows = await query.order('movement_day', ascending: false);
    return rows
        .map((item) => InventoryMovementDailyRow.fromMap(
              Map<String, dynamic>.from(item as Map),
            ))
        .toList(growable: false);
  }

  Future<Map<String, dynamic>> fetchPl({
    required DateTime from,
    required DateTime to,
  }) async {
    final result = await _client.rpc(
      'report_pl',
      params: {'p_from': _isoDate(from), 'p_to': _isoDate(to)},
    );
    if (result is Map) {
      return Map<String, dynamic>.from(result);
    }
    return const {};
  }

  Future<List<CreditAgingRow>> fetchCreditAging() async {
    final branchId = await _currentBranchId();
    if (branchId == null) return const [];
    final rows = await _client
        .from('report_credit_aging_view')
        .select()
        .eq('branch_id', branchId)
        .order('days_overdue', ascending: false);
    return rows
        .map((item) => CreditAgingRow.fromMap(
              Map<String, dynamic>.from(item as Map),
            ))
        .toList(growable: false);
  }

  Future<List<ExpensesByCategoryRow>> fetchExpensesByCategory({
    required DateTime from,
    required DateTime to,
  }) async {
    final branchId = await _currentBranchId();
    if (branchId == null) return const [];
    final rows = await _client
        .from('report_expenses_view')
        .select()
        .eq('branch_id', branchId)
        .gte('expense_date', _isoDate(from))
        .lte('expense_date', _isoDate(to))
        .order('total', ascending: false);
    return rows
        .map((item) => ExpensesByCategoryRow.fromMap(
              Map<String, dynamic>.from(item as Map),
            ))
        .toList(growable: false);
  }

  Future<List<PurchasesReportRow>> fetchPurchasesReport({
    required DateTime from,
    required DateTime to,
  }) async {
    final branchId = await _currentBranchId();
    if (branchId == null) return const [];
    final rows = await _client
        .from('report_purchases_view')
        .select()
        .eq('branch_id', branchId)
        .gte('purchase_date', _isoDate(from))
        .lte('purchase_date', _isoDate(to))
        .order('purchase_date', ascending: false);
    return rows
        .map((item) => PurchasesReportRow.fromMap(
              Map<String, dynamic>.from(item as Map),
            ))
        .toList(growable: false);
  }

  Future<List<SuppliersReportRow>> fetchSuppliersReport() async {
    final branchId = await _currentBranchId();
    if (branchId == null) return const [];
    final rows = await _client
        .from('report_suppliers_view')
        .select()
        .eq('branch_id', branchId)
        .order('purchases_total', ascending: false);
    return rows
        .map((item) => SuppliersReportRow.fromMap(
              Map<String, dynamic>.from(item as Map),
            ))
        .toList(growable: false);
  }

  Future<List<ClientsReportRow>> fetchClientsReport() async {
    final branchId = await _currentBranchId();
    if (branchId == null) return const [];
    final rows = await _client
        .from('report_clients_view')
        .select()
        .eq('branch_id', branchId)
        .order('sales_total', ascending: false);
    return rows
        .map((item) => ClientsReportRow.fromMap(
              Map<String, dynamic>.from(item as Map),
            ))
        .toList(growable: false);
  }

  Future<List<DiscountRow>> fetchDiscounts({
    required DateTime from,
    required DateTime to,
  }) async {
    final branchId = await _currentBranchId();
    if (branchId == null) return const [];
    final fromIso = _localStartOfDayUtcIso(from);
    final toIso = _localEndOfDayUtcIso(to);
    final rows = await _client
        .from('report_discounts_view')
        .select()
        .eq('branch_id', branchId)
        .gte('sale_date', fromIso)
        .lte('sale_date', toIso)
        .order('discount_amount', ascending: false);
    return rows
        .map((item) => DiscountRow.fromMap(
              Map<String, dynamic>.from(item as Map),
            ))
        .toList(growable: false);
  }

  Future<List<TaxBreakdownRow>> fetchTaxBreakdown({
    required DateTime from,
    required DateTime to,
  }) async {
    final branchId = await _currentBranchId();
    if (branchId == null) return const [];
    final rows = await _client
        .from('report_tax_breakdown_view')
        .select()
        .eq('branch_id', branchId)
        .gte('sale_day', _isoDate(from))
        .lte('sale_day', _isoDate(to))
        .order('sale_day');
    return rows
        .map((item) => TaxBreakdownRow.fromMap(
              Map<String, dynamic>.from(item as Map),
            ))
        .toList(growable: false);
  }

  // ───────────────────────────────────────────────────────────────────────
  // PRD 07 Round 3: DGII fiscal
  // ───────────────────────────────────────────────────────────────────────

  Future<Map<String, dynamic>> fetchDgii606(
      {required int year, required int month}) async {
    final result = await _client.rpc('dgii_606_data',
        params: {'p_year': year, 'p_month': month});
    if (result is Map) return Map<String, dynamic>.from(result);
    return const {};
  }

  Future<Map<String, dynamic>> fetchDgii607(
      {required int year, required int month}) async {
    final result = await _client.rpc('dgii_607_data',
        params: {'p_year': year, 'p_month': month});
    if (result is Map) return Map<String, dynamic>.from(result);
    return const {};
  }

  Future<Map<String, dynamic>> fetchDgiiIt1(
      {required int year, required int month}) async {
    final result = await _client.rpc('dgii_it1_summary',
        params: {'p_year': year, 'p_month': month});
    if (result is Map) return Map<String, dynamic>.from(result);
    return const {};
  }

  // ───────────────────────────────────────────────────────────────────────
  // Sub-reportes de Ventas (PRD §F-Ventas) — detallado, eliminadas, time.
  // Lee directo de `sales` (real-time desde migración 15).
  // ───────────────────────────────────────────────────────────────────────

  /// Lista de ventas individuales con detalle para "Reportes Detallados".
  ///
  /// Nota: `sales.cashier_id` referencia `auth.users(id)`, no `profiles(id)`,
  /// así que PostgREST no resuelve un embed directo de profiles. Hacemos
  /// dos queries y mezclamos en Dart.
  Future<List<SaleDetailRow>> fetchDetailedSales({
    required DateTime from,
    required DateTime to,
    bool voidedOnly = false,
  }) async {
    final branchId = await _currentBranchId();
    if (branchId == null) return const [];
    final fromIso = _localStartOfDayUtcIso(from);
    final toIso = _localEndOfDayUtcIso(to);

    var query = _client
        .from('sales')
        .select(
          'id, sale_number, sale_date, receipt_type, ncf, status, '
          'subtotal, tax_amount, total_amount, discount_amount, '
          'paid_amount, balance_due, cashier_id, cash_session_id, '
          'clients(full_name)',
        )
        .eq('branch_id', branchId)
        .gte('sale_date', fromIso)
        .lte('sale_date', toIso);

    if (voidedOnly) {
      query = query.eq('status', 'voided');
    } else {
      // Para "Detallados" normales excluimos eliminadas (tienen su propio
      // sub-reporte) y las cuentas GUARDADAS ('pending'): no son ventas reales
      // todavía, no deben sumar al reporte hasta completarse.
      query = query.neq('status', 'voided').neq('status', 'pending');
    }

    final salesRows =
        await query.order('sale_date', ascending: false).limit(500);

    // Recolectar cashier_ids únicos y traer los nombres de profiles en una
    // sola query.
    final cashierIds = <String>{};
    for (final raw in salesRows) {
      final id = (raw as Map)['cashier_id']?.toString();
      if (id != null && id.isNotEmpty) cashierIds.add(id);
    }

    final cashierNames = <String, String>{};
    if (cashierIds.isNotEmpty) {
      final profiles = await _client
          .from('profiles')
          .select('id, full_name')
          .inFilter('id', cashierIds.toList(growable: false));
      for (final raw in profiles) {
        final row = Map<String, dynamic>.from(raw as Map);
        final id = row['id']?.toString();
        final name = row['full_name']?.toString();
        if (id != null && name != null && name.isNotEmpty) {
          cashierNames[id] = name;
        }
      }
    }

    // Nombre de la caja (registro) que hizo cada venta. La venta apunta a
    // cash_sessions.cash_session_id; la sesión apunta a cash_registers.
    final sessionIds = <String>{};
    final saleIds = <String>{};
    for (final raw in salesRows) {
      final m = raw as Map;
      final sid = m['cash_session_id']?.toString();
      if (sid != null && sid.isNotEmpty) sessionIds.add(sid);
      final id = m['id']?.toString();
      if (id != null && id.isNotEmpty) saleIds.add(id);
    }

    final registerNames = <String, String>{};
    if (sessionIds.isNotEmpty) {
      final sessions = await _client
          .from('cash_sessions')
          .select('id, cash_registers(name)')
          .inFilter('id', sessionIds.toList(growable: false));
      for (final raw in sessions) {
        final row = Map<String, dynamic>.from(raw as Map);
        final id = row['id']?.toString();
        final reg = row['cash_registers'];
        final name = reg is Map ? reg['name']?.toString() : null;
        if (id != null && name != null && name.isNotEmpty) {
          registerNames[id] = name;
        }
      }
    }

    // Ganancia por venta = subtotal - COGS, donde COGS = Σ(cantidad × costo).
    // El costo se toma del producto actual (mismo criterio que las vistas de
    // márgenes del sistema). sale_items no guarda snapshot de costo.
    final cogsBySale = <String, double>{};
    if (saleIds.isNotEmpty) {
      final items = await _client
          .from('sale_items')
          .select('sale_id, product_id, quantity')
          .inFilter('sale_id', saleIds.toList(growable: false));
      final productIds = <String>{};
      for (final raw in items) {
        final pid = (raw as Map)['product_id']?.toString();
        if (pid != null && pid.isNotEmpty) productIds.add(pid);
      }
      final productCosts = <String, double>{};
      if (productIds.isNotEmpty) {
        final products = await _client
            .from('products')
            .select('id, cost')
            .inFilter('id', productIds.toList(growable: false));
        for (final raw in products) {
          final row = Map<String, dynamic>.from(raw as Map);
          final id = row['id']?.toString();
          if (id != null) productCosts[id] = _toDouble(row['cost']);
        }
      }
      for (final raw in items) {
        final row = Map<String, dynamic>.from(raw as Map);
        final saleId = row['sale_id']?.toString();
        final pid = row['product_id']?.toString();
        if (saleId == null) continue;
        final qty = _toDouble(row['quantity']);
        final cost = productCosts[pid] ?? 0;
        cogsBySale[saleId] = (cogsBySale[saleId] ?? 0) + qty * cost;
      }
    }

    return salesRows.map((item) {
      final m = Map<String, dynamic>.from(item as Map);
      final cashierId = m['cashier_id']?.toString();
      // Inyectamos un pseudo-map `profiles` para que el factory de
      // SaleDetailRow lo lea sin ramas especiales.
      if (cashierId != null && cashierNames.containsKey(cashierId)) {
        m['profiles'] = {'full_name': cashierNames[cashierId]};
      }
      final sessionId = m['cash_session_id']?.toString();
      if (sessionId != null && registerNames.containsKey(sessionId)) {
        m['cash_register_name'] = registerNames[sessionId];
      }
      final saleId = m['id']?.toString();
      m['profit'] = _toDouble(m['subtotal']) - (cogsBySale[saleId] ?? 0);
      return SaleDetailRow.fromMap(m);
    }).toList(growable: false);
  }

  /// Ventas agregadas por hora del día para "Time Reports".
  Future<List<HourlySalesRow>> fetchSalesByHour({
    required DateTime from,
    required DateTime to,
  }) async {
    final branchId = await _currentBranchId();
    if (branchId == null) return const [];
    final fromIso = _localStartOfDayUtcIso(from);
    final toIso = _localEndOfDayUtcIso(to);

    final rows = await _client
        .from('sales')
        .select('sale_date, total_amount, tax_amount')
        .eq('branch_id', branchId)
        .eq('status', 'completed')
        .gte('sale_date', fromIso)
        .lte('sale_date', toIso);

    // Agrupar por hora del día (0-23) en zona local.
    final byHour = <int, _HourlyBucket>{};
    for (final raw in rows) {
      final row = Map<String, dynamic>.from(raw as Map);
      final date = DateTime.tryParse(row['sale_date']?.toString() ?? '');
      if (date == null) continue;
      final hour = date.toLocal().hour;
      byHour.update(
        hour,
        (b) {
          b.salesCount += 1;
          b.total += _toDouble(row['total_amount']);
          b.tax += _toDouble(row['tax_amount']);
          return b;
        },
        ifAbsent: () => _HourlyBucket()
          ..salesCount = 1
          ..total = _toDouble(row['total_amount'])
          ..tax = _toDouble(row['tax_amount']),
      );
    }

    final result = <HourlySalesRow>[];
    for (var h = 0; h < 24; h++) {
      final b = byHour[h];
      result.add(HourlySalesRow(
        hour: h,
        salesCount: b == null ? 0 : b.salesCount,
        total: b == null ? 0 : b.total,
        tax: b == null ? 0 : b.tax,
      ));
    }
    return result;
  }

  Future<List<FiscalZClosureRow>> fetchFiscalZClosures() async {
    final branchId = await _currentBranchId();
    if (branchId == null) return const [];
    final rows = await _client
        .from('fiscal_z_closures')
        .select('id, closure_number, emitted_at, payload, is_complementary')
        .eq('branch_id', branchId)
        .order('emitted_at', ascending: false)
        .limit(50);
    return rows
        .map((item) => FiscalZClosureRow.fromMap(
              Map<String, dynamic>.from(item as Map),
            ))
        .toList(growable: false);
  }

  Future<String?> _currentBranchId() async {
    final result = await _client.rpc('current_branch_id');
    if (result == null) return null;
    final value = result.toString();
    return value.isEmpty ? null : value;
  }

  static String _isoDate(DateTime d) {
    final y = d.year.toString().padLeft(4, '0');
    final m = d.month.toString().padLeft(2, '0');
    final day = d.day.toString().padLeft(2, '0');
    return '$y-$m-$day';
  }

  /// Inicio del día local en UTC ISO. Usar para comparar contra columnas
  /// `timestamptz` en queries. Sin esto, el filtro pierde transacciones de
  /// las últimas horas del día (RD = UTC-4: a las 8pm SDQ ya es 00:00 UTC).
  static String _localStartOfDayUtcIso(DateTime d) {
    return DateTime(d.year, d.month, d.day).toUtc().toIso8601String();
  }

  /// Fin del día local (23:59:59) en UTC ISO.
  static String _localEndOfDayUtcIso(DateTime d) {
    return DateTime(d.year, d.month, d.day, 23, 59, 59).toUtc().toIso8601String();
  }
}

// ───────────────────────────────────────────────────────────────────────
// DTOs para los 6 reportes operativos
// ───────────────────────────────────────────────────────────────────────

class SalesDailyRow {
  SalesDailyRow({
    required this.saleDay,
    required this.sellerUserId,
    required this.receiptType,
    required this.salesCount,
    required this.grossTotal,
    required this.itbisTotal,
    required this.serviceChargeTotal,
    required this.discountTotal,
    required this.netTotal,
  });

  factory SalesDailyRow.fromMap(Map<String, dynamic> map) {
    return SalesDailyRow(
      saleDay: DateTime.tryParse(map['sale_day']?.toString() ?? '') ??
          DateTime.now(),
      sellerUserId: map['seller_user_id']?.toString(),
      receiptType: (map['receipt_type'] ?? '').toString(),
      salesCount: _toInt(map['sales_count']),
      grossTotal: _toDouble(map['gross_total']),
      itbisTotal: _toDouble(map['itbis_total']),
      serviceChargeTotal: _toDouble(map['service_charge_total']),
      discountTotal: _toDouble(map['discount_total']),
      netTotal: _toDouble(map['net_total']),
    );
  }

  final DateTime saleDay;
  final String? sellerUserId;
  final String receiptType;
  final int salesCount;
  final double grossTotal;
  final double itbisTotal;
  final double serviceChargeTotal;
  final double discountTotal;
  final double netTotal;
}

class CashSessionRow {
  CashSessionRow({
    required this.cashSessionId,
    required this.openedAt,
    required this.status,
    required this.openingAmount,
    required this.expectedAmount,
    required this.salesCompleted,
    required this.salesVoided,
    required this.salesTotal,
    required this.cashCollected,
    required this.cardCollected,
    required this.transferCollected,
    required this.creditCollected,
    this.closedAt,
    this.closingAmount,
    this.differenceAmount,
  });

  factory CashSessionRow.fromMap(Map<String, dynamic> map) {
    return CashSessionRow(
      cashSessionId: (map['cash_session_id'] ?? '').toString(),
      openedAt: DateTime.tryParse(map['opened_at']?.toString() ?? '') ??
          DateTime.now(),
      closedAt: DateTime.tryParse(map['closed_at']?.toString() ?? ''),
      status: (map['status'] ?? 'open').toString(),
      openingAmount: _toDouble(map['opening_amount']),
      expectedAmount: _toDouble(map['expected_amount']),
      closingAmount: map['closing_amount'] == null
          ? null
          : _toDouble(map['closing_amount']),
      differenceAmount: map['difference_amount'] == null
          ? null
          : _toDouble(map['difference_amount']),
      salesCompleted: _toInt(map['sales_completed']),
      salesVoided: _toInt(map['sales_voided']),
      salesTotal: _toDouble(map['sales_total']),
      cashCollected: _toDouble(map['cash_collected']),
      cardCollected: _toDouble(map['card_collected']),
      transferCollected: _toDouble(map['transfer_collected']),
      creditCollected: _toDouble(map['credit_collected']),
    );
  }

  final String cashSessionId;
  final DateTime openedAt;
  final DateTime? closedAt;
  final String status;
  final double openingAmount;
  final double expectedAmount;
  final double? closingAmount;
  final double? differenceAmount;
  final int salesCompleted;
  final int salesVoided;
  final double salesTotal;
  final double cashCollected;
  final double cardCollected;
  final double transferCollected;
  final double creditCollected;
}

class PaymentMethodRow {
  PaymentMethodRow({
    required this.method,
    required this.total,
    required this.count,
  });

  final String method;
  final double total;
  final int count;

  String get methodLabel {
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

class OutgoingPaymentRow {
  OutgoingPaymentRow({
    required this.date,
    required this.kind,
    required this.description,
    required this.amount,
    this.paymentMethod,
  });

  final DateTime date;
  final String kind;
  final String description;
  final double amount;
  final String? paymentMethod;
}

class SuspendedSaleRow {
  SuspendedSaleRow({
    required this.saleId,
    required this.saleNumber,
    required this.status,
    required this.saleDate,
    required this.totalAmount,
    this.clientName,
  });

  factory SuspendedSaleRow.fromMap(Map<String, dynamic> map) {
    final clientMap = map['clients'];
    final clientName =
        clientMap is Map ? clientMap['full_name']?.toString() : null;
    return SuspendedSaleRow(
      saleId: (map['id'] ?? '').toString(),
      saleNumber: (map['sale_number'] ?? '').toString(),
      status: (map['status'] ?? '').toString(),
      saleDate: DateTime.tryParse(map['sale_date']?.toString() ?? '') ??
          DateTime.now(),
      totalAmount: _toDouble(map['total_amount']),
      clientName: clientName,
    );
  }

  final String saleId;
  final String saleNumber;
  final String status;
  final DateTime saleDate;
  final double totalAmount;
  final String? clientName;
}

class _MutablePaymentBucket {
  _MutablePaymentBucket({required this.method});
  final String method;
  double total = 0;
  int count = 0;
}

// ───────────────────────────────────────────────────────────────────────
// PRD 07 Round 2 DTOs
// ───────────────────────────────────────────────────────────────────────

class EmployeeProductivityRow {
  EmployeeProductivityRow({
    required this.employeeId,
    required this.employeeName,
    required this.salesCount,
    required this.salesTotal,
    required this.avgTicket,
    required this.itemsSold,
    required this.saleDay,
    this.lastSaleAt,
  });

  factory EmployeeProductivityRow.fromMap(Map<String, dynamic> map) {
    return EmployeeProductivityRow(
      employeeId: map['employee_id']?.toString(),
      employeeName: (map['employee_name'] ?? 'Sin asignar').toString(),
      salesCount: _toInt(map['sales_count']),
      salesTotal: _toDouble(map['sales_total']),
      avgTicket: _toDouble(map['avg_ticket']),
      itemsSold: _toDouble(map['items_sold']),
      saleDay: DateTime.tryParse(map['sale_day']?.toString() ?? '') ??
          DateTime.now(),
      lastSaleAt: DateTime.tryParse(map['last_sale_at']?.toString() ?? ''),
    );
  }

  final String? employeeId;
  final String employeeName;
  final int salesCount;
  final double salesTotal;
  final double avgTicket;
  final double itemsSold;
  final DateTime saleDay;
  final DateTime? lastSaleAt;
}

class InventoryStatusRow {
  InventoryStatusRow({
    required this.productId,
    required this.name,
    required this.stock,
    required this.minStock,
    required this.cost,
    required this.price,
    required this.inventoryValue,
    required this.isLowStock,
    required this.isOutOfStock,
    this.sku,
    this.barcode,
    this.categoryName,
  });

  factory InventoryStatusRow.fromMap(Map<String, dynamic> map) {
    return InventoryStatusRow(
      productId: (map['product_id'] ?? '').toString(),
      name: (map['name'] ?? '').toString(),
      sku: map['sku']?.toString(),
      barcode: map['barcode']?.toString(),
      categoryName: map['category_name']?.toString(),
      stock: _toDouble(map['stock']),
      minStock: _toDouble(map['min_stock']),
      cost: _toDouble(map['cost']),
      price: _toDouble(map['price']),
      inventoryValue: _toDouble(map['inventory_value']),
      isLowStock: map['is_low_stock'] == true,
      isOutOfStock: map['is_out_of_stock'] == true,
    );
  }

  final String productId;
  final String name;
  final String? sku;
  final String? barcode;
  final String? categoryName;
  final double stock;
  final double minStock;
  final double cost;
  final double price;
  final double inventoryValue;
  final bool isLowStock;
  final bool isOutOfStock;
}

class SalesByItemRow {
  SalesByItemRow({
    required this.productId,
    required this.productName,
    required this.unitsSold,
    required this.grossTotal,
    required this.netTotal,
    required this.salesCount,
    required this.saleDay,
  });

  factory SalesByItemRow.fromMap(Map<String, dynamic> map) {
    return SalesByItemRow(
      productId: (map['product_id'] ?? '').toString(),
      productName: (map['product_name'] ?? '').toString(),
      unitsSold: _toDouble(map['units_sold']),
      grossTotal: _toDouble(map['gross_total']),
      netTotal: _toDouble(map['net_total']),
      salesCount: _toInt(map['sales_count']),
      saleDay: DateTime.tryParse(map['sale_day']?.toString() ?? '') ??
          DateTime.now(),
    );
  }

  final String productId;
  final String productName;
  final double unitsSold;
  final double grossTotal;
  final double netTotal;
  final int salesCount;
  final DateTime saleDay;
}

class SalesByCategoryRow {
  SalesByCategoryRow({
    required this.categoryName,
    required this.unitsSold,
    required this.grossTotal,
    required this.netTotal,
    required this.saleDay,
    this.categoryId,
  });

  factory SalesByCategoryRow.fromMap(Map<String, dynamic> map) {
    return SalesByCategoryRow(
      categoryId: map['category_id']?.toString(),
      categoryName: (map['category_name'] ?? 'Sin categoría').toString(),
      unitsSold: _toDouble(map['units_sold']),
      grossTotal: _toDouble(map['gross_total']),
      netTotal: _toDouble(map['net_total']),
      saleDay: DateTime.tryParse(map['sale_day']?.toString() ?? '') ??
          DateTime.now(),
    );
  }

  final String? categoryId;
  final String categoryName;
  final double unitsSold;
  final double grossTotal;
  final double netTotal;
  final DateTime saleDay;
}

class PriceRow {
  PriceRow({
    required this.productId,
    required this.name,
    required this.cost,
    required this.price,
    this.sku,
    this.barcode,
    this.categoryName,
    this.marginPct,
    this.updatedAt,
  });

  factory PriceRow.fromMap(Map<String, dynamic> map) {
    return PriceRow(
      productId: (map['product_id'] ?? '').toString(),
      name: (map['name'] ?? '').toString(),
      sku: map['sku']?.toString(),
      barcode: map['barcode']?.toString(),
      categoryName: map['category_name']?.toString(),
      cost: _toDouble(map['cost']),
      price: _toDouble(map['price']),
      marginPct:
          map['margin_pct'] == null ? null : _toDouble(map['margin_pct']),
      updatedAt: DateTime.tryParse(map['updated_at']?.toString() ?? ''),
    );
  }

  final String productId;
  final String name;
  final String? sku;
  final String? barcode;
  final String? categoryName;
  final double cost;
  final double price;
  final double? marginPct;
  final DateTime? updatedAt;
}

class PriceHistoryRow {
  PriceHistoryRow({
    required this.id,
    required this.productId,
    required this.productName,
    required this.changedAt,
    required this.source,
    this.productSku,
    this.changedByName,
    this.oldPrice,
    this.newPrice,
    this.oldCost,
    this.newCost,
    this.priceDelta,
    this.costDelta,
    this.pricePctChange,
    this.costPctChange,
    this.changeReason,
  });

  factory PriceHistoryRow.fromMap(Map<String, dynamic> map) {
    double? d(dynamic v) => v == null ? null : _toDouble(v);
    return PriceHistoryRow(
      id: (map['id'] ?? '').toString(),
      productId: (map['product_id'] ?? '').toString(),
      productName: (map['product_name'] ?? '').toString(),
      productSku: map['product_sku']?.toString(),
      changedAt:
          DateTime.tryParse(map['changed_at']?.toString() ?? '') ??
              DateTime.fromMillisecondsSinceEpoch(0),
      changedByName: map['changed_by_name']?.toString(),
      oldPrice: d(map['old_price']),
      newPrice: d(map['new_price']),
      oldCost: d(map['old_cost']),
      newCost: d(map['new_cost']),
      priceDelta: d(map['price_delta']),
      costDelta: d(map['cost_delta']),
      pricePctChange: d(map['price_pct_change']),
      costPctChange: d(map['cost_pct_change']),
      changeReason: map['change_reason']?.toString(),
      source: (map['source'] ?? 'manual').toString(),
    );
  }

  final String id;
  final String productId;
  final String productName;
  final String? productSku;
  final DateTime changedAt;
  final String? changedByName;
  final double? oldPrice;
  final double? newPrice;
  final double? oldCost;
  final double? newCost;
  final double? priceDelta;
  final double? costDelta;
  final double? pricePctChange;
  final double? costPctChange;
  final String? changeReason;
  final String source;
}

class InventoryMovementDailyRow {
  InventoryMovementDailyRow({
    required this.movementDay,
    required this.movementType,
    required this.productId,
    required this.totalQuantity,
    required this.totalCost,
    required this.movementsCount,
  });

  factory InventoryMovementDailyRow.fromMap(Map<String, dynamic> map) {
    return InventoryMovementDailyRow(
      movementDay:
          DateTime.tryParse(map['movement_day']?.toString() ?? '') ??
              DateTime.now(),
      movementType: (map['movement_type'] ?? '').toString(),
      productId: (map['product_id'] ?? '').toString(),
      totalQuantity: _toDouble(map['total_quantity']),
      totalCost: _toDouble(map['total_cost']),
      movementsCount: _toInt(map['movements_count']),
    );
  }

  final DateTime movementDay;
  final String movementType;
  final String productId;
  final double totalQuantity;
  final double totalCost;
  final int movementsCount;
}

class CreditAgingRow {
  CreditAgingRow({
    required this.clientId,
    required this.clientName,
    required this.balanceDue,
    required this.creditLimit,
    required this.agingBucket,
    this.daysOverdue,
    this.oldestAt,
  });

  factory CreditAgingRow.fromMap(Map<String, dynamic> map) {
    return CreditAgingRow(
      clientId: (map['client_id'] ?? '').toString(),
      clientName: (map['client_name'] ?? '').toString(),
      balanceDue: _toDouble(map['balance_due']),
      creditLimit: _toDouble(map['credit_limit']),
      agingBucket: (map['aging_bucket'] ?? '—').toString(),
      daysOverdue:
          map['days_overdue'] == null ? null : _toInt(map['days_overdue']),
      oldestAt: DateTime.tryParse(map['oldest_at']?.toString() ?? ''),
    );
  }

  final String clientId;
  final String clientName;
  final double balanceDue;
  final double creditLimit;
  final String agingBucket;
  final int? daysOverdue;
  final DateTime? oldestAt;
}

class ExpensesByCategoryRow {
  ExpensesByCategoryRow({
    required this.expenseDate,
    required this.category,
    required this.count,
    required this.total,
  });

  factory ExpensesByCategoryRow.fromMap(Map<String, dynamic> map) {
    return ExpensesByCategoryRow(
      expenseDate:
          DateTime.tryParse(map['expense_date']?.toString() ?? '') ??
              DateTime.now(),
      category: (map['category'] ?? 'Sin categoría').toString(),
      count: _toInt(map['count']),
      total: _toDouble(map['total']),
    );
  }

  final DateTime expenseDate;
  final String category;
  final int count;
  final double total;
}

class PurchasesReportRow {
  PurchasesReportRow({
    required this.purchaseDate,
    required this.supplierName,
    required this.purchasesCount,
    required this.subtotalTotal,
    required this.taxTotal,
    required this.grandTotal,
    this.supplierId,
  });

  factory PurchasesReportRow.fromMap(Map<String, dynamic> map) {
    return PurchasesReportRow(
      purchaseDate:
          DateTime.tryParse(map['purchase_date']?.toString() ?? '') ??
              DateTime.now(),
      supplierId: map['supplier_id']?.toString(),
      supplierName: (map['supplier_name'] ?? '').toString(),
      purchasesCount: _toInt(map['purchases_count']),
      subtotalTotal: _toDouble(map['subtotal_total']),
      taxTotal: _toDouble(map['tax_total']),
      grandTotal: _toDouble(map['grand_total']),
    );
  }

  final DateTime purchaseDate;
  final String? supplierId;
  final String supplierName;
  final int purchasesCount;
  final double subtotalTotal;
  final double taxTotal;
  final double grandTotal;
}

class SuppliersReportRow {
  SuppliersReportRow({
    required this.supplierId,
    required this.supplierName,
    required this.purchasesCount,
    required this.purchasesTotal,
    required this.outstandingAmount,
    this.tradeName,
    this.rnc,
    this.lastPurchaseAt,
  });

  factory SuppliersReportRow.fromMap(Map<String, dynamic> map) {
    return SuppliersReportRow(
      supplierId: (map['supplier_id'] ?? '').toString(),
      supplierName: (map['supplier_name'] ?? '').toString(),
      tradeName: map['trade_name']?.toString(),
      rnc: map['rnc']?.toString(),
      purchasesCount: _toInt(map['purchases_count']),
      purchasesTotal: _toDouble(map['purchases_total']),
      outstandingAmount: _toDouble(map['outstanding_amount']),
      lastPurchaseAt:
          DateTime.tryParse(map['last_purchase_at']?.toString() ?? ''),
    );
  }

  final String supplierId;
  final String supplierName;
  final String? tradeName;
  final String? rnc;
  final int purchasesCount;
  final double purchasesTotal;
  final double outstandingAmount;
  final DateTime? lastPurchaseAt;
}

class ClientsReportRow {
  ClientsReportRow({
    required this.clientId,
    required this.clientName,
    required this.salesCount,
    required this.salesTotal,
    required this.avgTicket,
    required this.creditLimit,
    required this.balanceDue,
    this.phone,
    this.email,
    this.lastSaleAt,
  });

  factory ClientsReportRow.fromMap(Map<String, dynamic> map) {
    return ClientsReportRow(
      clientId: (map['client_id'] ?? '').toString(),
      clientName: (map['client_name'] ?? '').toString(),
      phone: map['phone']?.toString(),
      email: map['email']?.toString(),
      salesCount: _toInt(map['sales_count']),
      salesTotal: _toDouble(map['sales_total']),
      avgTicket: _toDouble(map['avg_ticket']),
      creditLimit: _toDouble(map['credit_limit']),
      balanceDue: _toDouble(map['balance_due']),
      lastSaleAt: DateTime.tryParse(map['last_sale_at']?.toString() ?? ''),
    );
  }

  final String clientId;
  final String clientName;
  final String? phone;
  final String? email;
  final int salesCount;
  final double salesTotal;
  final double avgTicket;
  final double creditLimit;
  final double balanceDue;
  final DateTime? lastSaleAt;
}

class DiscountRow {
  DiscountRow({
    required this.saleId,
    required this.saleNumber,
    required this.saleDate,
    required this.discountAmount,
    required this.subtotal,
    required this.totalAmount,
    required this.discountPct,
    this.clientName,
    this.cashierName,
  });

  factory DiscountRow.fromMap(Map<String, dynamic> map) {
    return DiscountRow(
      saleId: (map['sale_id'] ?? '').toString(),
      saleNumber: (map['sale_number'] ?? '').toString(),
      saleDate: DateTime.tryParse(map['sale_date']?.toString() ?? '') ??
          DateTime.now(),
      clientName: map['client_name']?.toString(),
      cashierName: map['cashier_name']?.toString(),
      discountAmount: _toDouble(map['discount_amount']),
      subtotal: _toDouble(map['subtotal']),
      totalAmount: _toDouble(map['total_amount']),
      discountPct: _toDouble(map['discount_pct']),
    );
  }

  final String saleId;
  final String saleNumber;
  final DateTime saleDate;
  final String? clientName;
  final String? cashierName;
  final double discountAmount;
  final double subtotal;
  final double totalAmount;
  final double discountPct;
}

class TaxBreakdownRow {
  TaxBreakdownRow({
    required this.saleDay,
    required this.taxRate,
    required this.salesCount,
    required this.itemsCount,
    required this.taxableBase,
    required this.taxAmount,
    required this.totalWithTax,
  });

  factory TaxBreakdownRow.fromMap(Map<String, dynamic> map) {
    return TaxBreakdownRow(
      saleDay: DateTime.tryParse(map['sale_day']?.toString() ?? '') ??
          DateTime.now(),
      taxRate: _toDouble(map['tax_rate']),
      salesCount: _toInt(map['sales_count']),
      itemsCount: _toDouble(map['items_count']),
      taxableBase: _toDouble(map['taxable_base']),
      taxAmount: _toDouble(map['tax_amount']),
      totalWithTax: _toDouble(map['total_with_tax']),
    );
  }

  final DateTime saleDay;
  final double taxRate;
  final int salesCount;
  final double itemsCount;
  final double taxableBase;
  final double taxAmount;
  final double totalWithTax;
}

class SaleDetailRow {
  SaleDetailRow({
    required this.saleId,
    required this.saleNumber,
    required this.saleDate,
    required this.receiptType,
    required this.status,
    required this.subtotal,
    required this.taxAmount,
    required this.totalAmount,
    required this.discountAmount,
    required this.paidAmount,
    required this.balanceDue,
    required this.profit,
    this.ncf,
    this.clientName,
    this.cashierName,
    this.cashRegisterName,
  });

  factory SaleDetailRow.fromMap(Map<String, dynamic> map) {
    final clients = map['clients'];
    final profiles = map['profiles'];
    return SaleDetailRow(
      saleId: (map['id'] ?? '').toString(),
      saleNumber: (map['sale_number'] ?? '').toString(),
      saleDate: DateTime.tryParse(map['sale_date']?.toString() ?? '') ??
          DateTime.now(),
      receiptType: (map['receipt_type'] ?? '').toString(),
      ncf: map['ncf']?.toString(),
      status: (map['status'] ?? '').toString(),
      subtotal: _toDouble(map['subtotal']),
      taxAmount: _toDouble(map['tax_amount']),
      totalAmount: _toDouble(map['total_amount']),
      discountAmount: _toDouble(map['discount_amount']),
      paidAmount: _toDouble(map['paid_amount']),
      balanceDue: _toDouble(map['balance_due']),
      profit: _toDouble(map['profit']),
      clientName: clients is Map ? clients['full_name']?.toString() : null,
      cashierName: profiles is Map ? profiles['full_name']?.toString() : null,
      cashRegisterName: map['cash_register_name']?.toString(),
    );
  }

  final String saleId;
  final String saleNumber;
  final DateTime saleDate;
  final String receiptType;
  final String? ncf;
  final String status;
  final double subtotal;
  final double taxAmount;
  final double totalAmount;
  final double discountAmount;
  final double paidAmount;
  final double balanceDue;
  final double profit;
  final String? clientName;
  final String? cashierName;
  final String? cashRegisterName;
}

class HourlySalesRow {
  HourlySalesRow({
    required this.hour,
    required this.salesCount,
    required this.total,
    required this.tax,
  });

  /// Hora del día 0-23 (zona local).
  final int hour;
  final int salesCount;
  final double total;
  final double tax;

  String get hourLabel => '${hour.toString().padLeft(2, '0')}:00';
}

class _HourlyBucket {
  int salesCount = 0;
  double total = 0;
  double tax = 0;
}

class FiscalZClosureRow {
  FiscalZClosureRow({
    required this.id,
    required this.closureNumber,
    required this.emittedAt,
    required this.payload,
    required this.isComplementary,
  });

  factory FiscalZClosureRow.fromMap(Map<String, dynamic> map) {
    final payloadRaw = map['payload'];
    final payload = payloadRaw is Map
        ? Map<String, dynamic>.from(payloadRaw)
        : const <String, dynamic>{};
    return FiscalZClosureRow(
      id: (map['id'] ?? '').toString(),
      closureNumber: _toInt(map['closure_number']),
      emittedAt: DateTime.tryParse(map['emitted_at']?.toString() ?? '') ??
          DateTime.now(),
      payload: payload,
      isComplementary: map['is_complementary'] == true,
    );
  }

  final String id;
  final int closureNumber;
  final DateTime emittedAt;
  final Map<String, dynamic> payload;
  final bool isComplementary;
}

int _toInt(dynamic value) {
  if (value == null) return 0;
  if (value is int) return value;
  if (value is double) return value.toInt();
  return int.tryParse(value.toString()) ?? 0;
}

double _toDouble(dynamic value) {
  if (value == null) return 0;
  if (value is double) return value;
  if (value is int) return value.toDouble();
  return double.tryParse(value.toString()) ?? 0;
}
