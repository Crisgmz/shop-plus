import 'package:supabase_flutter/supabase_flutter.dart';

class CashSessionEntity {
  CashSessionEntity({
    required this.id,
    required this.status,
    required this.openedAt,
    required this.openingAmount,
    required this.expectedAmount,
    required this.closingAmount,
    required this.differenceAmount,
    required this.notes,
    required this.closedAt,
    this.cashRegisterId,
  });

  final String id;
  final String status;
  final DateTime openedAt;
  final DateTime? closedAt;
  final double openingAmount;
  final double expectedAmount;
  final double? closingAmount;
  final double? differenceAmount;
  final String? notes;

  /// Caja sobre la que se abrió la sesión. Null para sesiones legacy
  /// abiertas antes del migration de cash_registers.
  final String? cashRegisterId;

  bool get isOpen => status == 'open';

  factory CashSessionEntity.fromMap(Map<String, dynamic> map) {
    return CashSessionEntity(
      id: (map['id'] ?? '').toString(),
      status: (map['status'] ?? '').toString(),
      openedAt:
          DateTime.tryParse((map['opened_at'] ?? '').toString()) ??
          DateTime.fromMillisecondsSinceEpoch(0),
      closedAt: map['closed_at'] == null
          ? null
          : DateTime.tryParse(map['closed_at'].toString()),
      openingAmount: _toDouble(map['opening_amount']),
      expectedAmount: _toDouble(map['expected_amount']),
      closingAmount: map['closing_amount'] == null
          ? null
          : _toDouble(map['closing_amount']),
      differenceAmount: map['difference_amount'] == null
          ? null
          : _toDouble(map['difference_amount']),
      notes: map['notes']?.toString(),
      cashRegisterId: _nullIfEmpty(map['cash_register_id']?.toString()),
    );
  }
}

class CashSessionMetrics {
  CashSessionMetrics({
    required this.totalPayments,
    required this.cashPayments,
    required this.totalExpenses,
    required this.cashExpenses,
    this.cardPayments = 0,
    this.transferPayments = 0,
    this.otherPayments = 0,
    this.salesTotal = 0,
    this.changeGiven = 0,
  });

  final double totalPayments;
  final double cashPayments;
  final double cardPayments;
  final double transferPayments;
  final double otherPayments;
  final double totalExpenses;
  final double cashExpenses;

  /// Total vendido en la sesión (suma de total_amount de las ventas).
  final double salesTotal;

  /// Cambio entregado en efectivo (sobrepagos). Sale del efectivo de la caja.
  final double changeGiven;

  double get netPayments => _round2(totalPayments - totalExpenses);

  /// Efectivo esperado = apertura + cobros en efectivo − gastos en efectivo
  /// − cambio entregado en efectivo.
  double expectedCashFromOpening(double openingAmount) {
    return _round2(
      openingAmount + cashPayments - cashExpenses - changeGiven,
    );
  }
}

class CashRegisterData {
  CashRegisterData({
    required this.openSession,
    required this.openMetrics,
    required this.recentSessions,
    this.pettyCashExpensesToday = 0,
  });

  final CashSessionEntity? openSession;
  final CashSessionMetrics? openMetrics;
  final List<CashSessionEntity> recentSessions;

  /// Total de gastos de CAJA CHICA registrados hoy en la sucursal. Informativo:
  /// los gastos se manejan en Caja Chica, no en la sesión de la caja principal.
  final double pettyCashExpensesToday;
}

/// Vista enriquecida de una caja para el panel del dueño: incluye nombre del
/// cajero y las métricas de la sesión (pagos, gastos, esperado).
class CashSessionOverview {
  CashSessionOverview({
    required this.session,
    required this.cashierName,
    required this.cashierId,
    required this.metrics,
  });

  final CashSessionEntity session;
  final String cashierName;
  final String cashierId;
  final CashSessionMetrics metrics;

  double get expectedCash =>
      metrics.expectedCashFromOpening(session.openingAmount);
}

/// Caja física/lógica configurada en una sucursal. Cada caja puede tener
/// varios usuarios asignados (cash_register_users) que pueden operarla.
class CashRegisterEntity {
  CashRegisterEntity({
    required this.id,
    required this.name,
    required this.isActive,
    required this.assignedUserIds,
  });

  final String id;
  final String name;
  final bool isActive;
  final List<String> assignedUserIds;

  factory CashRegisterEntity.fromMap(
    Map<String, dynamic> map,
    List<String> assignedUserIds,
  ) {
    return CashRegisterEntity(
      id: (map['id'] ?? '').toString(),
      name: (map['name'] ?? '').toString(),
      isActive: map['is_active'] != false,
      assignedUserIds: List<String>.unmodifiable(assignedUserIds),
    );
  }
}

/// Una sesión abierta del usuario actual con su info de caja asociada.
/// Útil para el picker cuando hay múltiples sesiones abiertas.
class MyOpenCashSession {
  MyOpenCashSession({
    required this.sessionId,
    required this.cashRegisterId,
    required this.registerName,
    required this.openedAt,
    required this.openingAmount,
  });

  final String sessionId;
  final String? cashRegisterId;
  final String registerName;
  final DateTime openedAt;
  final double openingAmount;

  factory MyOpenCashSession.fromMap(Map<String, dynamic> map) {
    return MyOpenCashSession(
      sessionId: (map['id'] ?? '').toString(),
      cashRegisterId: _nullIfEmpty(map['cash_register_id']?.toString()),
      registerName: (map['register_name'] ?? 'Caja sin asignar').toString(),
      openedAt:
          DateTime.tryParse((map['opened_at'] ?? '').toString()) ??
              DateTime.fromMillisecondsSinceEpoch(0),
      openingAmount: _toDouble(map['opening_amount']),
    );
  }
}

class OpenCashInput {
  OpenCashInput({required this.openingAmount, this.notes, this.cashRegisterId});

  final double openingAmount;
  final String? notes;

  /// Caja sobre la que se abre la sesión. Requerido cuando la sucursal
  /// tiene cajas configuradas. Si es null, cae al flujo legacy (sesión
  /// sin caja asignada).
  final String? cashRegisterId;
}

/// Movimiento manual de efectivo dentro de la sesión activa.
class CashMovementInput {
  CashMovementInput({
    required this.movementType,
    required this.amount,
    this.reason,
    this.notes,
  });

  /// 'deposit' | 'withdrawal' | 'adjustment' | 'opening_top_up'.
  final String movementType;
  final double amount;
  final String? reason;
  final String? notes;
}

class CashMovementEntity {
  CashMovementEntity({
    required this.id,
    required this.movementType,
    required this.amount,
    required this.occurredAt,
    this.reason,
    this.notes,
    this.performedBy,
  });

  factory CashMovementEntity.fromMap(Map<String, dynamic> map) {
    return CashMovementEntity(
      id: (map['id'] ?? '').toString(),
      movementType: (map['movement_type'] ?? '').toString(),
      amount: _toDouble(map['amount']),
      occurredAt:
          DateTime.tryParse((map['occurred_at'] ?? '').toString()) ??
              DateTime.now(),
      reason: map['reason']?.toString(),
      notes: map['notes']?.toString(),
      performedBy: map['performed_by']?.toString(),
    );
  }

  final String id;

  /// 'deposit' | 'withdrawal' | 'adjustment' | 'opening_top_up'.
  final String movementType;
  final double amount;
  final DateTime occurredAt;
  final String? reason;
  final String? notes;
  final String? performedBy;

  /// Delta con signo: positivo si suma a la caja, negativo si resta.
  double get signedAmount {
    switch (movementType) {
      case 'deposit':
      case 'opening_top_up':
      case 'adjustment':
        return amount;
      case 'withdrawal':
        return -amount;
      default:
        return 0;
    }
  }

  String get typeLabel {
    switch (movementType) {
      case 'deposit':
        return 'Depósito';
      case 'withdrawal':
        return 'Sangría';
      case 'adjustment':
        return 'Ajuste';
      case 'opening_top_up':
        return 'Refuerzo de apertura';
      default:
        return movementType;
    }
  }
}

class CloseCashInput {
  CloseCashInput({required this.closingAmount, this.notes});

  final double closingAmount;
  final String? notes;
}

class CashRegisterRepository {
  CashRegisterRepository(this._client);

  final SupabaseClient _client;

  /// Vista para admin/supervisor: TODAS las cajas abiertas de la sucursal
  /// (no solo la propia) con nombre del cajero y métricas. Útil para que el
  /// dueño vea cuánto lleva vendido cada uno.
  Future<List<CashSessionOverview>> fetchOpenSessionsOverview() async {
    final branchId = await _currentBranchId();
    if (branchId == null) return const [];

    final sessionRows = await _client
        .from('cash_sessions')
        .select(
          'id, status, opened_at, closed_at, opening_amount, expected_amount, '
          'closing_amount, difference_amount, notes, opened_by',
        )
        .eq('branch_id', branchId)
        .eq('status', 'open')
        .order('opened_at', ascending: false);

    if (sessionRows.isEmpty) return const [];

    // Nombres de cajeros en una sola query.
    final cashierIds = <String>{
      for (final r in sessionRows)
        ((r as Map)['opened_by'] ?? '').toString(),
    }..removeWhere((id) => id.isEmpty);
    final profileRows = cashierIds.isEmpty
        ? const <dynamic>[]
        : await _client
            .from('profiles')
            .select('id, full_name')
            .inFilter('id', cashierIds.toList());
    final namesById = <String, String>{
      for (final p in profileRows)
        ((p as Map)['id'] ?? '').toString():
            ((p)['full_name'] ?? '').toString(),
    };

    // Métricas por sesión (en serie — pocos cajeros normalmente).
    final overviews = <CashSessionOverview>[];
    for (final raw in sessionRows) {
      final row = Map<String, dynamic>.from(raw as Map);
      final session = CashSessionEntity.fromMap(row);
      final cashierId = (row['opened_by'] ?? '').toString();
      final metrics = await _fetchSessionMetrics(session.id, branchId);
      overviews.add(
        CashSessionOverview(
          session: session,
          cashierId: cashierId,
          cashierName: namesById[cashierId] ?? 'Cajero',
          metrics: metrics,
        ),
      );
    }
    return overviews;
  }

  /// [activeSessionId]: la caja que el usuario tiene seleccionada en el POS
  /// (`activeCashSessionIdProvider`). Cuando un mismo usuario tiene varias
  /// cajas abiertas a la vez, el cuadre/movimientos/cierre deben operar sobre
  /// ESA caja, no sobre "la última abierta". Si es null o ya no está abierta,
  /// cae a la última sesión abierta del usuario.
  Future<CashRegisterData> fetchData({String? activeSessionId}) async {
    final branchId = await _currentBranchId();
    if (branchId == null) {
      return CashRegisterData(
        openSession: null,
        openMetrics: null,
        recentSessions: const [],
      );
    }

    // Las tres cargas son independientes (solo `metrics` depende de la sesión
    // abierta) → en paralelo (3 round-trips → 1).
    final (openSession, recentSessions, pettyCashExpensesToday) = await (
      _fetchActiveOrLatestOpenSession(branchId, activeSessionId),
      _fetchRecentSessions(branchId),
      _fetchPettyCashExpensesToday(branchId),
    ).wait;

    CashSessionMetrics? metrics;
    if (openSession != null) {
      metrics = await _fetchSessionMetrics(openSession.id, branchId);
    }

    return CashRegisterData(
      openSession: openSession,
      openMetrics: metrics,
      recentSessions: recentSessions,
      pettyCashExpensesToday: pettyCashExpensesToday,
    );
  }

  /// Suma los gastos de CAJA CHICA registrados hoy en la sucursal. Es solo
  /// informativo para la tarjeta "Gastos" de la Caja: los gastos se llevan en
  /// Caja Chica, no en la sesión de la caja principal.
  Future<double> _fetchPettyCashExpensesToday(String branchId) async {
    final now = DateTime.now();
    final start = DateTime(now.year, now.month, now.day);
    final end = start.add(const Duration(days: 1));
    try {
      final rows = await _client
          .from('petty_cash_movements')
          .select('amount')
          .eq('branch_id', branchId)
          .eq('movement_type', 'expense')
          .gte('occurred_at', start.toUtc().toIso8601String())
          .lt('occurred_at', end.toUtc().toIso8601String());
      return _round2(
        rows.fold<double>(
          0,
          (sum, item) => sum + _toDouble((item as Map)['amount']),
        ),
      );
    } catch (_) {
      // Si la tabla de caja chica no existe aún en este entorno, no romper.
      return 0;
    }
  }

  Future<void> openSession(OpenCashInput input) async {
    final branchId = await _currentBranchId();
    if (branchId == null) {
      throw Exception('No hay sucursal asignada para este usuario.');
    }

    final userId = _client.auth.currentUser?.id;
    if (userId == null) {
      throw Exception('Sesión inválida. Inicia sesión de nuevo.');
    }

    final existing = await _fetchOpenSession(branchId);
    if (existing != null) {
      throw Exception('Ya existe una sesión de caja abierta.');
    }

    final openingAmount = _round2(input.openingAmount);

    await _client.from('cash_sessions').insert({
      'branch_id': branchId,
      'opened_by': userId,
      'status': 'open',
      'opened_at': DateTime.now().toUtc().toIso8601String(),
      'opening_amount': openingAmount,
      'expected_amount': openingAmount,
      'notes': _nullIfEmpty(input.notes),
    });
  }

  /// [cashSessionId]: la caja activa que se está cerrando. Si es null, cierra
  /// la última abierta del usuario (compatibilidad). Esto evita cerrar la
  /// caja equivocada cuando hay varias abiertas a la vez.
  Future<void> closeSession(CloseCashInput input, {String? cashSessionId}) async {
    final branchId = await _currentBranchId();
    if (branchId == null) {
      throw Exception('No hay sucursal asignada para este usuario.');
    }

    final userId = _client.auth.currentUser?.id;
    if (userId == null) {
      throw Exception('Sesión inválida. Inicia sesión de nuevo.');
    }

    final openSession =
        await _fetchActiveOrLatestOpenSession(branchId, cashSessionId);
    if (openSession == null) {
      throw Exception('No hay una sesión de caja abierta.');
    }

    final metrics = await _fetchSessionMetrics(openSession.id, branchId);
    final expected = metrics.expectedCashFromOpening(openSession.openingAmount);
    final closingAmount = _round2(input.closingAmount);
    final difference = _round2(closingAmount - expected);

    await _client
        .from('cash_sessions')
        .update({
          'status': 'closed',
          'closed_by': userId,
          'closed_at': DateTime.now().toUtc().toIso8601String(),
          'expected_amount': expected,
          'closing_amount': closingAmount,
          'difference_amount': difference,
          'notes': _nullIfEmpty(input.notes) ?? openSession.notes,
        })
        .eq('id', openSession.id)
        .eq('branch_id', branchId);
  }

  /// Resuelve qué sesión opera la pantalla de Caja. Prioriza la caja ACTIVA
  /// seleccionada en el POS; si no hay (o esa sesión ya no está abierta), cae
  /// a la última abierta del usuario. Evita "ligar" cajas cuando un mismo
  /// usuario tiene varias abiertas a la vez.
  Future<CashSessionEntity?> _fetchActiveOrLatestOpenSession(
    String branchId,
    String? activeSessionId,
  ) async {
    if (activeSessionId != null && activeSessionId.isNotEmpty) {
      final rows = await _client
          .from('cash_sessions')
          .select(
            'id, status, opened_at, closed_at, opening_amount, expected_amount, closing_amount, difference_amount, notes, cash_register_id',
          )
          .eq('id', activeSessionId)
          .eq('branch_id', branchId)
          .eq('status', 'open')
          .limit(1);
      if (rows.isNotEmpty) {
        return CashSessionEntity.fromMap(
          Map<String, dynamic>.from(rows.first as Map),
        );
      }
    }
    return _fetchOpenSession(branchId);
  }

  /// Sesión abierta DEL USUARIO ACTUAL (multi-caja). Cada cajero abre y
  /// cierra su propia caja.
  Future<CashSessionEntity?> _fetchOpenSession(String branchId) async {
    final userId = _client.auth.currentUser?.id;
    if (userId == null) return null;
    final rows = await _client
        .from('cash_sessions')
        .select(
          'id, status, opened_at, closed_at, opening_amount, expected_amount, closing_amount, difference_amount, notes, cash_register_id',
        )
        .eq('branch_id', branchId)
        .eq('status', 'open')
        .eq('opened_by', userId)
        .order('opened_at', ascending: false)
        .limit(1);

    if (rows.isEmpty) return null;
    return CashSessionEntity.fromMap(
      Map<String, dynamic>.from(rows.first as Map),
    );
  }

  /// Últimas 15 sesiones DEL USUARIO ACTUAL en la sucursal.
  Future<List<CashSessionEntity>> _fetchRecentSessions(String branchId) async {
    final userId = _client.auth.currentUser?.id;
    if (userId == null) return const [];
    final rows = await _client
        .from('cash_sessions')
        .select(
          'id, status, opened_at, closed_at, opening_amount, expected_amount, closing_amount, difference_amount, notes',
        )
        .eq('branch_id', branchId)
        .eq('opened_by', userId)
        .order('opened_at', ascending: false)
        .limit(15);

    return rows
        .map(
          (item) =>
              CashSessionEntity.fromMap(Map<String, dynamic>.from(item as Map)),
        )
        .toList(growable: false);
  }

  /// Métricas (cobros, gastos, breakdown efectivo) para una sesión específica.
  /// Útil para mostrar el detalle de cualquier sesión, abierta o cerrada.
  Future<CashSessionMetrics> fetchSessionMetrics(String cashSessionId) async {
    final branchId = await _currentBranchId();
    if (branchId == null) {
      return CashSessionMetrics(
        totalPayments: 0,
        cashPayments: 0,
        totalExpenses: 0,
        cashExpenses: 0,
      );
    }
    return _fetchSessionMetrics(cashSessionId, branchId);
  }

  Future<CashSessionMetrics> _fetchSessionMetrics(
    String cashSessionId,
    String branchId,
  ) async {
    // payments / expenses / sales de la sesión son independientes → en
    // paralelo (3 round-trips → 1). Esta función corre en la pantalla de Caja
    // y una vez por sesión en el resumen de cajas abiertas.
    final salesFuture = _client
        .from('sales')
        .select('total_amount, change_amount')
        .eq('branch_id', branchId)
        .eq('cash_session_id', cashSessionId)
        .neq('status', 'voided');
    final (payments, expenses, salesRows) = await (
      _client
          .from('payments')
          .select('amount, payment_method')
          .eq('branch_id', branchId)
          .eq('cash_session_id', cashSessionId),
      _client
          .from('expenses')
          .select('amount, payment_method')
          .eq('branch_id', branchId)
          .eq('cash_session_id', cashSessionId),
      salesFuture,
    ).wait;

    final totalPayments = _round2(
      payments.fold<double>(
        0,
        (sum, item) => sum + _toDouble((item as Map)['amount']),
      ),
    );

    double sumByMethod(bool Function(String m) test) => _round2(
          payments.fold<double>(0, (sum, item) {
            final row = item as Map;
            final method = (row['payment_method'] ?? '').toString();
            if (!test(method)) return sum;
            return sum + _toDouble(row['amount']);
          }),
        );

    final cashPayments = sumByMethod((m) => m == 'cash');
    final cardPayments = sumByMethod((m) => m == 'card');
    final transferPayments = sumByMethod((m) => m == 'transfer');
    // "Otro" = todo lo que no es efectivo/tarjeta/transferencia.
    final otherPayments = sumByMethod(
        (m) => m != 'cash' && m != 'card' && m != 'transfer');

    // Total vendido y cambio entregado (sobrepagos) de las ventas de la sesión.
    final salesTotal = _round2(salesRows.fold<double>(
        0, (sum, item) => sum + _toDouble((item as Map)['total_amount'])));
    final changeGiven = _round2(salesRows.fold<double>(
        0, (sum, item) => sum + _toDouble((item as Map)['change_amount'])));

    final totalExpenses = _round2(
      expenses.fold<double>(
        0,
        (sum, item) => sum + _toDouble((item as Map)['amount']),
      ),
    );

    final cashExpenses = _round2(
      expenses.fold<double>(0, (sum, item) {
        final row = item as Map;
        final method = (row['payment_method'] ?? '').toString();
        if (method != 'cash') return sum;
        return sum + _toDouble(row['amount']);
      }),
    );

    return CashSessionMetrics(
      totalPayments: totalPayments,
      cashPayments: cashPayments,
      cardPayments: cardPayments,
      transferPayments: transferPayments,
      otherPayments: otherPayments,
      salesTotal: salesTotal,
      changeGiven: changeGiven,
      totalExpenses: totalExpenses,
      cashExpenses: cashExpenses,
    );
  }

  /// Registra un movimiento manual de efectivo en la sesión activa.
  /// El trigger SQL ajusta `cash_sessions.expected_amount` automáticamente.
  /// [cashSessionId]: la caja activa sobre la que se registra el movimiento.
  /// Si es null, usa la última abierta del usuario (compatibilidad). Pasar la
  /// caja activa evita que un depósito/sangría caiga en otra caja del mismo
  /// usuario cuando tiene varias abiertas.
  Future<void> addMovement(
    CashMovementInput input, {
    String? cashSessionId,
  }) async {
    final branchId = await _currentBranchId();
    if (branchId == null) {
      throw Exception('No hay sucursal asignada para este usuario.');
    }
    final userId = _client.auth.currentUser?.id;
    if (userId == null) {
      throw Exception('Sesión inválida. Inicia sesión de nuevo.');
    }
    final openSession =
        await _fetchActiveOrLatestOpenSession(branchId, cashSessionId);
    if (openSession == null) {
      throw Exception(
        'No hay una sesión de caja abierta. Abre la caja primero.',
      );
    }
    if (input.amount <= 0) {
      throw Exception('El monto debe ser mayor que cero.');
    }

    await _client.from('cash_register_movements').insert({
      'branch_id': branchId,
      'cash_session_id': openSession.id,
      'movement_type': input.movementType,
      'amount': _round2(input.amount),
      'reason': _nullIfEmpty(input.reason),
      'notes': _nullIfEmpty(input.notes),
      'performed_by': userId,
    });
  }

  Future<List<CashMovementEntity>> fetchMovementsForSession(
    String cashSessionId,
  ) async {
    final branchId = await _currentBranchId();
    if (branchId == null) return const [];

    final rows = await _client
        .from('cash_register_movements')
        .select(
          'id, movement_type, amount, reason, notes, occurred_at, performed_by',
        )
        .eq('branch_id', branchId)
        .eq('cash_session_id', cashSessionId)
        .order('occurred_at', ascending: false);

    return rows
        .map((item) => CashMovementEntity.fromMap(
              Map<String, dynamic>.from(item as Map),
            ))
        .toList(growable: false);
  }

  /// Sella un cierre Z fiscal (inmutable) para una sesión de caja cerrada.
  /// Llama al RPC `seal_fiscal_z_closure` que valida que la sesión esté
  /// cerrada y que no exista ya un cierre Z primario para ella.
  /// Devuelve el UUID del cierre Z creado.
  Future<String> sealFiscalZClosure(String cashSessionId) async {
    final branchId = await _currentBranchId();
    if (branchId == null) {
      throw Exception('No hay sucursal asignada.');
    }
    final result = await _client.rpc(
      'seal_fiscal_z_closure',
      params: {
        'p_branch_id': branchId,
        'p_cash_session_id': cashSessionId,
      },
    );
    if (result == null) {
      throw Exception('No se pudo sellar el cierre Z.');
    }
    return result.toString();
  }

  Future<String?> currentOpenSessionId() async {
    final branchId = await _currentBranchId();
    if (branchId == null) return null;

    final openSession = await _fetchOpenSession(branchId);
    return openSession?.id;
  }

  Future<String?> _currentBranchId() async {
    final result = await _client.rpc('current_branch_id');
    if (result == null) return null;
    final value = result.toString();
    return value.isEmpty ? null : value;
  }

  // ── cash_registers (catálogo de cajas configurables por sucursal) ─────

  /// Trae todas las cajas activas de la sucursal con sus usuarios asignados.
  Future<List<CashRegisterEntity>> fetchCashRegisters() async {
    final branchId = await _currentBranchId();
    if (branchId == null) return const [];

    final registerRows = await _client
        .from('cash_registers')
        .select('id, name, is_active')
        .eq('branch_id', branchId)
        .eq('is_active', true)
        .order('name');

    if (registerRows.isEmpty) return const [];

    final registerIds = [
      for (final r in registerRows) ((r as Map)['id'] ?? '').toString(),
    ];

    final assignRows = await _client
        .from('cash_register_users')
        .select('cash_register_id, user_id, is_active')
        .inFilter('cash_register_id', registerIds)
        .eq('is_active', true);

    final byRegister = <String, List<String>>{
      for (final id in registerIds) id: <String>[],
    };
    for (final raw in assignRows) {
      final row = Map<String, dynamic>.from(raw as Map);
      final crId = (row['cash_register_id'] ?? '').toString();
      final uid = (row['user_id'] ?? '').toString();
      if (crId.isEmpty || uid.isEmpty) continue;
      byRegister[crId]?.add(uid);
    }

    return [
      for (final raw in registerRows)
        CashRegisterEntity.fromMap(
          Map<String, dynamic>.from(raw as Map),
          byRegister[((raw)['id'] ?? '').toString()] ?? const [],
        ),
    ];
  }

  /// Trae solo las cajas a las que el usuario actual está asignado y que
  /// están activas. Útil para el picker de "abrir caja".
  Future<List<CashRegisterEntity>> fetchMyCashRegisters() async {
    final userId = _client.auth.currentUser?.id;
    if (userId == null) return const [];
    final all = await fetchCashRegisters();
    return all
        .where((cr) => cr.assignedUserIds.contains(userId))
        .toList(growable: false);
  }

  /// Trae las sesiones de caja ABIERTAS a las que el usuario actual tiene
  /// acceso (cajas a las que está asignado vía cash_register_users), sin
  /// importar quién las abrió, más cualquier sesión propia (incluidas las
  /// legacy sin caja). Así, si el admin ya abrió una caja, el cajero la ve
  /// abierta y entra a ELLA en vez de abrir otra encima (2 cuadres).
  /// Une con cash_registers para obtener el nombre de cada caja.
  Future<List<MyOpenCashSession>> fetchMyOpenSessions() async {
    final branchId = await _currentBranchId();
    final userId = _client.auth.currentUser?.id;
    if (branchId == null || userId == null) return const [];

    // Cajas a las que el usuario está asignado.
    final myRegisters = await fetchMyCashRegisters();
    final myRegisterIds = myRegisters.map((cr) => cr.id).toList();

    final query = _client
        .from('cash_sessions')
        .select('id, cash_register_id, opened_at, opening_amount')
        .eq('branch_id', branchId)
        .eq('status', 'open');

    final filtered = myRegisterIds.isEmpty
        // Sin cajas asignadas → solo sus propias sesiones (modo legacy).
        ? query.eq('opened_by', userId)
        // Sesiones de mis cajas (de quien sea) + mis propias sesiones.
        : query.or(
            'cash_register_id.in.(${myRegisterIds.join(',')}),'
            'opened_by.eq.$userId',
          );

    final sessionRows = await filtered.order('opened_at', ascending: false);

    if (sessionRows.isEmpty) return const [];

    final registerIds = <String>{
      for (final r in sessionRows)
        ((r as Map)['cash_register_id'] ?? '').toString(),
    }..removeWhere((id) => id.isEmpty);

    final registerNames = <String, String>{};
    if (registerIds.isNotEmpty) {
      final registerRows = await _client
          .from('cash_registers')
          .select('id, name')
          .inFilter('id', registerIds.toList());
      for (final r in registerRows) {
        final row = Map<String, dynamic>.from(r as Map);
        registerNames[(row['id'] ?? '').toString()] =
            (row['name'] ?? '').toString();
      }
    }

    return sessionRows
        .map((raw) {
          final row = Map<String, dynamic>.from(raw as Map);
          final registerId = (row['cash_register_id'] ?? '').toString();
          row['register_name'] = registerNames[registerId] ?? 'Caja sin asignar';
          return MyOpenCashSession.fromMap(row);
        })
        .toList(growable: false);
  }

  /// Crea una caja nueva sin usuarios asignados todavía.
  Future<CashRegisterEntity> createCashRegister(String name) async {
    final branchId = await _currentBranchId();
    if (branchId == null) {
      throw Exception('No hay sucursal asignada.');
    }
    final trimmed = name.trim();
    if (trimmed.isEmpty) {
      throw Exception('El nombre de la caja es requerido.');
    }
    final row = await _client
        .from('cash_registers')
        .insert({
          'branch_id': branchId,
          'name': trimmed,
          'is_active': true,
        })
        .select('id, name, is_active')
        .single();
    return CashRegisterEntity.fromMap(Map<String, dynamic>.from(row), const []);
  }

  Future<void> renameCashRegister({
    required String cashRegisterId,
    required String newName,
  }) async {
    final trimmed = newName.trim();
    if (trimmed.isEmpty) {
      throw Exception('El nombre de la caja es requerido.');
    }
    await _client
        .from('cash_registers')
        .update({'name': trimmed})
        .eq('id', cashRegisterId);
  }

  /// Soft-delete: la marca inactiva (queda fuera del picker, pero las
  /// sesiones históricas siguen apuntando a ella).
  Future<void> deactivateCashRegister(String cashRegisterId) async {
    await _client
        .from('cash_registers')
        .update({'is_active': false})
        .eq('id', cashRegisterId);
  }

  /// Reemplaza la lista de usuarios asignados a una caja. Hace diff entre
  /// la lista actual y la nueva: inserta los que faltan, desactiva los que
  /// sobran. No borra filas para preservar el historial.
  Future<void> setCashRegisterUsers({
    required String cashRegisterId,
    required List<String> userIds,
  }) async {
    final newSet = userIds.toSet();

    final existingRows = await _client
        .from('cash_register_users')
        .select('user_id, is_active')
        .eq('cash_register_id', cashRegisterId);
    final existingActive = <String>{
      for (final r in existingRows)
        if ((r as Map)['is_active'] == true)
          ((r)['user_id'] ?? '').toString(),
    };
    final existingAll = <String>{
      for (final r in existingRows) ((r as Map)['user_id'] ?? '').toString(),
    };

    final toActivate = newSet.difference(existingActive);
    final toDeactivate = existingActive.difference(newSet);

    for (final uid in toActivate) {
      if (existingAll.contains(uid)) {
        // Fila ya existía pero inactiva → reactivar.
        await _client
            .from('cash_register_users')
            .update({'is_active': true})
            .eq('cash_register_id', cashRegisterId)
            .eq('user_id', uid);
      } else {
        await _client.from('cash_register_users').insert({
          'cash_register_id': cashRegisterId,
          'user_id': uid,
          'is_active': true,
        });
      }
    }

    for (final uid in toDeactivate) {
      await _client
          .from('cash_register_users')
          .update({'is_active': false})
          .eq('cash_register_id', cashRegisterId)
          .eq('user_id', uid);
    }
  }

  /// Abre una sesión sobre una caja específica vía RPC con validación de
  /// permiso. Reemplaza al INSERT directo cuando la sucursal tiene cajas
  /// configuradas. Devuelve el UUID de la cash_session creada.
  Future<String> openSessionForRegister(OpenCashInput input) async {
    if (input.cashRegisterId == null || input.cashRegisterId!.isEmpty) {
      throw Exception('Tienes que elegir una caja.');
    }
    final result = await _client.rpc(
      'open_cash_session_for_register',
      params: {
        'p_cash_register_id': input.cashRegisterId,
        'p_opening_amount': _round2(input.openingAmount),
        'p_notes': _nullIfEmpty(input.notes),
      },
    );
    if (result == null) {
      throw Exception('No se pudo abrir la sesión.');
    }
    return result.toString();
  }
}

String? _nullIfEmpty(String? value) {
  if (value == null) return null;
  final trimmed = value.trim();
  return trimmed.isEmpty ? null : trimmed;
}

double _toDouble(dynamic value) {
  if (value == null) return 0;
  if (value is double) return value;
  if (value is int) return value.toDouble();
  return double.tryParse(value.toString()) ?? 0;
}

double _round2(double value) => (value * 100).roundToDouble() / 100;
