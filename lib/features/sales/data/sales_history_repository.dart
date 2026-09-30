import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../shared/packaging/product_packaging.dart';

class SalesHistoryRow {
  SalesHistoryRow({
    required this.id,
    required this.branchId,
    required this.saleNumber,
    required this.saleDate,
    required this.status,
    required this.receiptType,
    required this.totalAmount,
    required this.paidAmount,
    required this.balanceDue,
    required this.itemsCount,
    this.ncf,
    this.clientId,
    this.clientName,
    this.cashierName,
    this.cashRegisterName,
    this.profit = 0,
    this.paymentMethod,
    this.notes,
    this.dueDate,
  });

  final String id;
  final String branchId;
  final String saleNumber;
  final DateTime saleDate;
  final String status;
  final String receiptType;
  final double totalAmount;
  final double paidAmount;
  final double balanceDue;
  final int itemsCount;
  final String? ncf;
  final String? clientId;
  final String? clientName;
  final String? cashierName;
  final String? cashRegisterName;
  final double profit;
  final String? paymentMethod;
  final String? notes;
  final DateTime? dueDate;

  factory SalesHistoryRow.fromMap(Map<String, dynamic> map) {
    final rawDue = map['due_date']?.toString();
    return SalesHistoryRow(
      id: (map['id'] ?? '').toString(),
      branchId: (map['branch_id'] ?? '').toString(),
      saleNumber: (map['sale_number'] ?? '-').toString(),
      saleDate:
          DateTime.tryParse((map['sale_date'] ?? '').toString()) ??
          DateTime.fromMillisecondsSinceEpoch(0),
      status: (map['status'] ?? '').toString(),
      receiptType: (map['receipt_type'] ?? '').toString(),
      totalAmount: _d(map['total_amount']),
      paidAmount: _d(map['paid_amount']),
      balanceDue: _d(map['balance_due']),
      itemsCount: _i(map['items_count']),
      ncf: _s(map['ncf']),
      clientId: _s(map['client_id']),
      clientName: _s(map['client_name']),
      cashierName: _s(map['cashier_name']),
      cashRegisterName: _s(map['cash_register_name']),
      profit: _d(map['profit']),
      paymentMethod: _s(map['payment_method']),
      notes: _s(map['notes']),
      dueDate: rawDue == null || rawDue.isEmpty
          ? null
          : DateTime.tryParse(rawDue),
    );
  }
}

class SalesHistoryPage {
  SalesHistoryPage({
    required this.rows,
    required this.hasMore,
  });

  final List<SalesHistoryRow> rows;
  final bool hasMore;
}

class SalesHistoryFilter {
  const SalesHistoryFilter({
    this.from,
    this.to,
    this.search = '',
    this.statuses = const <String>[],
  });

  final DateTime? from;
  final DateTime? to;
  final String search;
  final List<String> statuses;

  SalesHistoryFilter copyWith({
    DateTime? from,
    DateTime? to,
    String? search,
    List<String>? statuses,
    bool clearFrom = false,
    bool clearTo = false,
  }) {
    return SalesHistoryFilter(
      from: clearFrom ? null : (from ?? this.from),
      to: clearTo ? null : (to ?? this.to),
      search: search ?? this.search,
      statuses: statuses ?? this.statuses,
    );
  }
}

class SalesHistoryRepository {
  SalesHistoryRepository(this._client);

  final SupabaseClient _client;

  /// Tamaño de página estándar para la lista de ventas anteriores.
  static const pageSize = 25;

  /// Trae una página de ventas con filtros + cantidad de items por venta.
  Future<SalesHistoryPage> fetchPage({
    required int pageIndex,
    SalesHistoryFilter filter = const SalesHistoryFilter(),
  }) async {
    final branchId = await _currentBranchId();
    if (branchId == null) {
      return SalesHistoryPage(rows: const [], hasMore: false);
    }

    // Clientes y cajeros no dependen entre sí → en paralelo (2 round-trips → 1).
    final (clientsById, cashiersById) =
        await (_loadClientsById(branchId), _loadCashiersById()).wait;

    final from = pageIndex * pageSize;
    final to = from + pageSize; // pedimos 1 extra para saber si hay más

    var query = _client
        .from('sales')
        .select(
          'id, branch_id, sale_number, sale_date, status, receipt_type, '
          'ncf, subtotal, total_amount, paid_amount, balance_due, due_date, '
          'client_id, cashier_id, cash_session_id, notes',
        )
        .eq('branch_id', branchId);
    // Nota: las ventas anuladas (voided) SÍ se incluyen — deben quedar en el
    // historial marcadas como "Anulada", no desaparecer.

    // Fechas LOCALES convertidas a UTC: sin zona, el servidor las leía como
    // UTC y el filtro corría 4 horas (las ventas de la noche caían fuera).
    if (filter.from != null) {
      final start = DateTime(
        filter.from!.year,
        filter.from!.month,
        filter.from!.day,
      );
      query = query.gte('sale_date', start.toUtc().toIso8601String());
    }
    if (filter.to != null) {
      // incluir todo el día
      final nextDay = DateTime(
        filter.to!.year,
        filter.to!.month,
        filter.to!.day + 1,
      );
      query = query.lt('sale_date', nextDay.toUtc().toIso8601String());
    }
    if (filter.statuses.isNotEmpty) {
      query = query.inFilter('status', filter.statuses);
    }
    final search = filter.search.trim();
    if (search.isNotEmpty) {
      // sale_number o ncf
      query = query.or(
        'sale_number.ilike.%$search%,ncf.ilike.%$search%',
      );
    }

    final rows = await query
        .order('sale_date', ascending: false)
        .range(from, to);

    final list = rows
        .map((row) => Map<String, dynamic>.from(row as Map))
        .toList(growable: false);

    final hasMore = list.length > pageSize;
    final page = hasMore ? list.sublist(0, pageSize) : list;

    // Enriquecimiento de la página: conteo de items, caja que hizo cada venta,
    // ganancia y método de cobro. Las cuatro son independientes y se resuelven
    // por ids de la página → en paralelo (4 round-trips → 1).
    final saleIds = page.map((m) => (m['id'] ?? '').toString()).toList();
    final sessionIds = page
        .map((m) => m['cash_session_id']?.toString())
        .whereType<String>()
        .where((s) => s.isNotEmpty)
        .toSet()
        .toList(growable: false);
    final (itemsCount, registerBySession, cogsBySale, methodBySale) = await (
      _loadItemsCount(branchId, saleIds),
      _loadRegisterNames(sessionIds),
      _loadCogsBySale(branchId, saleIds),
      _loadPaymentMethods(branchId, saleIds),
    ).wait;

    final result = page.map((m) {
      final id = (m['id'] ?? '').toString();
      final clientId = m['client_id']?.toString();
      final cashierId = m['cashier_id']?.toString();
      final sessionId = m['cash_session_id']?.toString();
      m['items_count'] = itemsCount[id] ?? 0;
      m['client_name'] =
          clientId == null ? null : clientsById[clientId];
      m['cashier_name'] =
          cashierId == null ? null : cashiersById[cashierId];
      m['cash_register_name'] =
          sessionId == null ? null : registerBySession[sessionId];
      m['profit'] = _d(m['subtotal']) - (cogsBySale[id] ?? 0);
      m['payment_method'] = methodBySale[id];
      return SalesHistoryRow.fromMap(m);
    }).toList(growable: false);

    return SalesHistoryPage(rows: result, hasMore: hasMore);
  }

  /// Edita la venta completa: reemplaza items, ajusta stock y recalcula
  /// totales. Vía RPC `edit_sale_transactional` para que todo ocurra en una
  /// sola transacción del backend.
  ///
  /// `items` debe ser una lista de mapas con: product_id, description,
  /// quantity, unit_price, discount_pct.
  Future<SalesEditResult> editSale({
    required String saleId,
    required List<Map<String, dynamic>> items,
    String? clientId,
    bool clearClient = false,
    String? notes,
    bool clearNotes = false,
    bool clientSkipsTax = false,
  }) async {
    final dynamic result;
    try {
      result = await _client.rpc(
        'edit_sale_transactional',
        params: {
          'p_sale_id': saleId,
          'p_items': items,
          'p_client_id': clientId,
          'p_clear_client': clearClient,
          'p_notes': notes,
          'p_clear_notes': clearNotes,
          // Solo si el cliente con que queda la venta no paga ITBIS (migración
          // 91). Mandarlo siempre rompería toda edición antes de la migración.
          if (clientSkipsTax) 'p_honor_client_tax': true,
        },
      );
    } on PostgrestException catch (error) {
      // Falta la migración 91 en la base.
      if (clientSkipsTax && error.code == 'PGRST202') {
        throw Exception(
          'Dejar esta venta sin ITBIS necesita una actualización del sistema. '
          'Contacta a soporte.',
        );
      }
      rethrow;
    }
    final map = Map<String, dynamic>.from(result as Map);
    return SalesEditResult(
      saleId: (map['sale_id'] ?? saleId).toString(),
      subtotal: _d(map['subtotal']),
      taxAmount: _d(map['tax_amount']),
      totalAmount: _d(map['total_amount']),
      paidAmount: _d(map['paid_amount']),
      balanceDue: _d(map['balance_due']),
      itemsCount: _i(map['items_count']),
    );
  }

  /// Anula una venta y devuelve el stock + borra los pagos asociados.
  /// Llama al RPC `void_sale_with_stock_return` que hace todo atómicamente
  /// dentro de una transacción. El trigger trg_sale_items_stock se encarga
  /// de sumar el stock devuelto al producto.
  ///
  /// [reasonCode] es el tipo de anulación de la DGII (01..10) para el 608
  /// (migración 97). Devuelve el efectivo que salió de la caja ABIERTA de
  /// quien anula: pasa cuando la venta se cobró en un turno ya cerrado.
  Future<double> voidSaleWithStockReturn(
    String saleId, {
    String? reasonCode,
  }) async {
    final dynamic result;
    try {
      result = await _client.rpc(
        'void_sale_with_stock_return',
        params: {'p_sale_id': saleId, 'p_reason_code': reasonCode},
      );
    } on PostgrestException catch (error) {
      // Base sin la migración 97: la firma con motivo no existe. Se anula con
      // la de siempre (sin motivo) en vez de bloquear.
      if (error.code != 'PGRST202') rethrow;
      await _client.rpc(
        'void_sale_with_stock_return',
        params: {'p_sale_id': saleId},
      );
      return 0;
    }
    if (result is Map) {
      return _d(result['cash_refunded_from_open_session']);
    }
    return 0;
  }

  /// Actualiza notas y/o cliente de una venta. No toca items ni totales.
  Future<void> updateSaleMetadata({
    required String saleId,
    String? notes,
    String? clientId,
    bool clearClient = false,
  }) async {
    final branchId = await _currentBranchId();
    if (branchId == null) {
      throw Exception('No hay sucursal asignada.');
    }
    final patch = <String, dynamic>{};
    if (notes != null) {
      final trimmed = notes.trim();
      patch['notes'] = trimmed.isEmpty ? null : trimmed;
    }
    if (clearClient) {
      patch['client_id'] = null;
    } else if (clientId != null) {
      patch['client_id'] = clientId;
    }
    if (patch.isEmpty) return;

    await _client
        .from('sales')
        .update(patch)
        .eq('id', saleId)
        .eq('branch_id', branchId);
  }

  /// Detalle de una venta con sus items, para mostrar en el viewer / edit.
  Future<SalesHistoryDetail?> fetchDetail(String saleId) async {
    final branchId = await _currentBranchId();
    if (branchId == null) return null;

    final saleRows = await _client
        .from('sales')
        .select(
          'id, branch_id, sale_number, sale_date, status, receipt_type, '
          'ncf, subtotal, tax_amount, total_amount, paid_amount, '
          'balance_due, due_date, client_id, client_name_snapshot, '
          'cashier_id, notes',
        )
        .eq('id', saleId)
        .eq('branch_id', branchId)
        .limit(1);
    if (saleRows.isEmpty) return null;
    final sale = Map<String, dynamic>.from(saleRows.first as Map);

    // Con la presentación de cada línea: sin ella "4 Cajas" se leían como 80
    // unidades al unitario y la edición recalculaba otro total. `uom_price`
    // llega con la migración 92; si falta, se relee sin esa columna, igual
    // que el recibo.
    const itemColumns =
        'id, product_id, description, quantity, unit_price, '
        'discount_amount, tax_rate, line_subtotal, line_tax, line_total, '
        'uom, uom_factor, unit_name, imeis';
    PostgrestList itemRows;
    try {
      itemRows = await _client
          .from('sale_items')
          .select('$itemColumns, uom_price')
          .eq('sale_id', saleId)
          .order('created_at');
    } on PostgrestException catch (error) {
      final missingUomPrice =
          error.code == '42703' && error.message.contains('uom_price');
      if (!missingUomPrice) rethrow;
      itemRows = await _client
          .from('sale_items')
          .select(itemColumns)
          .eq('sale_id', saleId)
          .order('created_at');
    }

    final clientId = sale['client_id']?.toString();
    // Sin ficha puede haber un nombre escrito a mano (venta que vino de una
    // cotización con cliente manual). Ver `client_name_snapshot`.
    String? clientName = _s(sale['client_name_snapshot']);
    if (clientId != null && clientId.isNotEmpty) {
      final clientRows = await _client
          .from('clients')
          .select('full_name')
          .eq('id', clientId)
          .limit(1);
      if (clientRows.isNotEmpty) {
        clientName =
            (clientRows.first as Map)['full_name']?.toString() ?? clientName;
      }
    }

    // Métodos de pago en el orden en que se registraron. El primario es el
    // primero; la edición necesita saber si hay más de uno para no aplastar un
    // pago dividido (efectivo + tarjeta) en un solo método.
    final paymentRows = await _client
        .from('payments')
        .select('payment_method')
        .eq('sale_id', saleId)
        .order('created_at');
    final paymentMethods = <String>[];
    for (final row in paymentRows) {
      final method = (row as Map)['payment_method']?.toString();
      if (method != null && !paymentMethods.contains(method)) {
        paymentMethods.add(method);
      }
    }
    final paymentMethod = paymentMethods.isEmpty ? null : paymentMethods.first;

    return SalesHistoryDetail(
      sale: SalesHistoryRow.fromMap({
        ...sale,
        'client_name': clientName,
        'items_count': itemRows.length,
      }),
      items: itemRows
          .map((row) => SalesHistoryItem.fromMap(
                Map<String, dynamic>.from(row as Map),
              ))
          .toList(growable: false),
      subtotal: _d(sale['subtotal']),
      taxAmount: _d(sale['tax_amount']),
      paymentMethod: paymentMethod,
      paymentMethods: paymentMethods,
      paymentCount: paymentRows.length,
    );
  }

  /// Cambia el método de pago de todos los `payments` de una venta.
  /// Llama al RPC `update_sale_payment_method` que valida acceso y rol.
  Future<int> updateSalePaymentMethod({
    required String saleId,
    required String paymentMethod,
  }) async {
    final result = await _client.rpc(
      'update_sale_payment_method',
      params: {
        'p_sale_id': saleId,
        'p_payment_method': paymentMethod,
      },
    );
    if (result is int) return result;
    return int.tryParse(result?.toString() ?? '') ?? 0;
  }

  Future<Map<String, int>> _loadItemsCount(
    String branchId,
    List<String> saleIds,
  ) async {
    if (saleIds.isEmpty) return const {};
    final rows = await _client
        .from('sale_items')
        .select('sale_id')
        .eq('branch_id', branchId)
        .inFilter('sale_id', saleIds);

    final counts = <String, int>{};
    for (final row in rows) {
      final sid = ((row as Map)['sale_id'] ?? '').toString();
      counts[sid] = (counts[sid] ?? 0) + 1;
    }
    return counts;
  }

  /// Nombre de la caja (cash_register) por cada cash_session_id.
  /// sales.cash_session_id -> cash_sessions.cash_register_id -> cash_registers.name
  Future<Map<String, String>> _loadRegisterNames(
    List<String> sessionIds,
  ) async {
    if (sessionIds.isEmpty) return const {};
    final rows = await _client
        .from('cash_sessions')
        .select('id, cash_registers(name)')
        .inFilter('id', sessionIds);
    final result = <String, String>{};
    for (final raw in rows) {
      final row = Map<String, dynamic>.from(raw as Map);
      final id = row['id']?.toString();
      final reg = row['cash_registers'];
      final name = reg is Map ? reg['name']?.toString() : null;
      if (id != null && name != null && name.isNotEmpty) {
        result[id] = name;
      }
    }
    return result;
  }

  /// COGS (costo de lo vendido) por venta = Σ(cantidad × costo del producto).
  /// La ganancia se calcula luego como subtotal - COGS, igual que las vistas
  /// de márgenes del sistema.
  Future<Map<String, double>> _loadCogsBySale(
    String branchId,
    List<String> saleIds,
  ) async {
    if (saleIds.isEmpty) return const {};
    final items = await _client
        .from('sale_items')
        .select('sale_id, product_id, quantity')
        .eq('branch_id', branchId)
        .inFilter('sale_id', saleIds);

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
        if (id != null) productCosts[id] = _d(row['cost']);
      }
    }

    final cogs = <String, double>{};
    for (final raw in items) {
      final row = Map<String, dynamic>.from(raw as Map);
      final sid = row['sale_id']?.toString();
      if (sid == null) continue;
      final qty = _d(row['quantity']);
      final cost = productCosts[row['product_id']?.toString()] ?? 0;
      cogs[sid] = (cogs[sid] ?? 0) + qty * cost;
    }
    return cogs;
  }

  /// Método de cobro por venta. Si hay varios métodos distintos en una misma
  /// venta lo marca como 'mixed'. Si no hay pagos registrados, queda null.
  Future<Map<String, String>> _loadPaymentMethods(
    String branchId,
    List<String> saleIds,
  ) async {
    if (saleIds.isEmpty) return const {};
    final rows = await _client
        .from('payments')
        .select('sale_id, payment_method')
        .eq('branch_id', branchId)
        .inFilter('sale_id', saleIds);

    final methods = <String, Set<String>>{};
    for (final raw in rows) {
      final row = Map<String, dynamic>.from(raw as Map);
      final sid = row['sale_id']?.toString();
      final method = row['payment_method']?.toString();
      if (sid == null || method == null || method.isEmpty) continue;
      methods.putIfAbsent(sid, () => <String>{}).add(method);
    }

    // Devolvemos los métodos usados unidos por coma (en orden de inserción),
    // ej. "cash,transfer". La UI los traduce y muestra "Efectivo + Transferencia".
    return {
      for (final entry in methods.entries) entry.key: entry.value.join(','),
    };
  }

  Future<Map<String, String>> _loadClientsById(String branchId) async {
    final rows = await _client
        .from('clients')
        .select('id, full_name')
        .eq('branch_id', branchId);
    return {
      for (final row in rows)
        ((row as Map)['id'] ?? '').toString():
            (row['full_name'] ?? '').toString(),
    };
  }

  Future<Map<String, String>> _loadCashiersById() async {
    final rows = await _client.from('profiles').select('id, full_name');
    return {
      for (final row in rows)
        ((row as Map)['id'] ?? '').toString():
            (row['full_name'] ?? '').toString(),
    };
  }

  Future<String?> _currentBranchId() async {
    final result = await _client.rpc('current_branch_id');
    if (result == null) return null;
    final value = result.toString();
    return value.isEmpty ? null : value;
  }
}

class SalesHistoryDetail {
  SalesHistoryDetail({
    required this.sale,
    required this.items,
    required this.subtotal,
    required this.taxAmount,
    this.paymentMethod,
    this.paymentMethods = const [],
    this.paymentCount = 0,
  });

  final SalesHistoryRow sale;
  final List<SalesHistoryItem> items;
  final double subtotal;
  final double taxAmount;

  /// Método de pago primario de la venta (de la primera fila en `payments`).
  /// Null si la venta no tiene pagos registrados todavía.
  final String? paymentMethod;

  /// Métodos distintos de todos sus pagos, en orden de registro.
  final List<String> paymentMethods;

  /// Cuántos pagos tiene (abonos incluidos).
  final int paymentCount;
}

class SalesEditResult {
  SalesEditResult({
    required this.saleId,
    required this.subtotal,
    required this.taxAmount,
    required this.totalAmount,
    required this.paidAmount,
    required this.balanceDue,
    required this.itemsCount,
  });

  final String saleId;
  final double subtotal;
  final double taxAmount;
  final double totalAmount;
  final double paidAmount;
  final double balanceDue;
  final int itemsCount;
}

class SalesHistoryItem {
  SalesHistoryItem({
    required this.id,
    required this.productId,
    required this.description,
    required this.quantity,
    required this.unitPrice,
    required this.taxRate,
    required this.discountAmount,
    required this.lineSubtotal,
    required this.lineTax,
    required this.lineTotal,
    this.uom = PackagingUom.unit,
    this.uomFactor = 1,
    this.uomPrice,
    this.unitName,
    this.imeis = const <String>[],
  });

  final String id;
  final String? productId;
  final String description;

  /// SIEMPRE en unidades base (4 cajas de 20 = 80). Ver [presentationQuantity].
  final double quantity;

  /// Unitario base. En una línea por presentación NO es lo que se cobró: el
  /// RPC cobra desde [uomPrice] (migración 92).
  final double unitPrice;
  final double taxRate;

  /// Presentación con que se vendió la línea y cuántas unidades base trae una.
  final PackagingUom uom;
  final double uomFactor;

  /// Precio de UNA presentación (la caja). Null en líneas sueltas y en ventas
  /// anteriores a la migración 92.
  final double? uomPrice;

  /// Cómo se llamó la presentación en la factura ("Caja").
  final String? unitName;

  /// Equipos vendidos en la línea. La edición tiene que reenviarlos: el RPC
  /// devuelve al inventario los de las líneas viejas y solo vuelve a sacar
  /// los que le llegan.
  final List<String> imeis;

  bool get isPresentation => uom != PackagingUom.unit && uomFactor > 0;

  /// Cantidad como se vendió: 80 unidades en cajas de 20 son 4 cajas.
  double get presentationQuantity => isPresentation
      ? (quantity / uomFactor * 1000).roundToDouble() / 1000
      : quantity;

  /// Precio de UNA presentación. Sin `uom_price` guardado se deriva del
  /// unitario, igual que el recibo.
  double get presentationPrice => isPresentation
      ? uomPrice ?? (unitPrice * uomFactor * 100).roundToDouble() / 100
      : unitPrice;

  /// "Caja". Si la venta no guardó el nombre, el genérico de la presentación.
  String get presentationLabel =>
      unitName ?? ProductPackaging.none.labelFor(uom);

  /// Descuento de la línea en pesos. Es el dato bueno para reconstruir el
  /// porcentaje al editar: con precio ITBIS-incluido, `lineSubtotal` ya viene
  /// con el impuesto extraído y deducirlo de ahí daba un descuento falso.
  final double discountAmount;
  final double lineSubtotal;
  final double lineTax;
  final double lineTotal;

  factory SalesHistoryItem.fromMap(Map<String, dynamic> map) {
    return SalesHistoryItem(
      id: (map['id'] ?? '').toString(),
      productId: _s(map['product_id']),
      description: (map['description'] ?? '').toString(),
      quantity: _d(map['quantity']),
      unitPrice: _d(map['unit_price']),
      taxRate: _d(map['tax_rate']),
      discountAmount: _d(map['discount_amount']),
      lineSubtotal: _d(map['line_subtotal']),
      lineTax: _d(map['line_tax']),
      lineTotal: _d(map['line_total']),
      uom: PackagingUom.fromDb(map['uom']?.toString()),
      uomFactor: _d(map['uom_factor']) > 0 ? _d(map['uom_factor']) : 1,
      uomPrice: map['uom_price'] == null ? null : _d(map['uom_price']),
      unitName: _s(map['unit_name']),
      imeis: map['imeis'] is List
          ? (map['imeis'] as List)
              .map((e) => e.toString().trim())
              .where((e) => e.isNotEmpty)
              .toList(growable: false)
          : const <String>[],
    );
  }
}

double _d(dynamic v) {
  if (v == null) return 0;
  if (v is num) return v.toDouble();
  return double.tryParse(v.toString()) ?? 0;
}

int _i(dynamic v) {
  if (v == null) return 0;
  if (v is int) return v;
  if (v is num) return v.toInt();
  return int.tryParse(v.toString()) ?? 0;
}

String? _s(dynamic v) {
  if (v == null) return null;
  final s = v.toString().trim();
  return s.isEmpty ? null : s;
}
