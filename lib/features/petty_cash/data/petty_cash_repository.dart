// Repositorio de caja chica (F8).
//
// Tablas Supabase (migración `20260509_16_operational_extensions.sql`):
//   - petty_cash_sessions   (apertura/cierre con UNIQUE por sucursal abierta)
//   - petty_cash_movements  (income/expense/replenishment/adjustment)
//   - petty_cash_categories (seed con 6 categorías default)
//
// El `expected_amount` de la sesión se mantiene actualizado por el trigger
// SQL `apply_petty_cash_movement`, así que aquí sólo hacemos CRUD.

import 'package:supabase_flutter/supabase_flutter.dart';

// ─────────────────────────────────────────────────────────────────────────
// DTOs
// ─────────────────────────────────────────────────────────────────────────

class PettyCashSession {
  PettyCashSession({
    required this.id,
    required this.status,
    required this.openedAt,
    required this.openingAmount,
    required this.expectedAmount,
    this.closedAt,
    this.closingAmount,
    this.differenceAmount,
    this.notes,
  });

  factory PettyCashSession.fromMap(Map<String, dynamic> map) {
    return PettyCashSession(
      id: (map['id'] ?? '').toString(),
      status: (map['status'] ?? '').toString(),
      openedAt: DateTime.tryParse(map['opened_at']?.toString() ?? '') ??
          DateTime.now(),
      closedAt: DateTime.tryParse(map['closed_at']?.toString() ?? ''),
      openingAmount: _toDouble(map['opening_amount']),
      expectedAmount: _toDouble(map['expected_amount']),
      closingAmount: map['closing_amount'] == null
          ? null
          : _toDouble(map['closing_amount']),
      differenceAmount: map['difference_amount'] == null
          ? null
          : _toDouble(map['difference_amount']),
      notes: map['notes']?.toString(),
    );
  }

  final String id;
  final String status;
  final DateTime openedAt;
  final DateTime? closedAt;
  final double openingAmount;
  final double expectedAmount;
  final double? closingAmount;
  final double? differenceAmount;
  final String? notes;

  bool get isOpen => status == 'open';
}

class PettyCashCategory {
  PettyCashCategory({
    required this.id,
    required this.name,
    this.description,
  });

  factory PettyCashCategory.fromMap(Map<String, dynamic> map) {
    return PettyCashCategory(
      id: (map['id'] ?? '').toString(),
      name: (map['name'] ?? '').toString(),
      description: map['description']?.toString(),
    );
  }

  final String id;
  final String name;
  final String? description;
}

class PettyCashMovement {
  PettyCashMovement({
    required this.id,
    required this.movementType,
    required this.amount,
    required this.occurredAt,
    this.categoryId,
    this.categoryName,
    this.description,
    this.payee,
    this.receiptReference,
  });

  factory PettyCashMovement.fromMap(Map<String, dynamic> map) {
    final cat = map['petty_cash_categories'];
    return PettyCashMovement(
      id: (map['id'] ?? '').toString(),
      movementType: (map['movement_type'] ?? '').toString(),
      amount: _toDouble(map['amount']),
      occurredAt: DateTime.tryParse(map['occurred_at']?.toString() ?? '') ??
          DateTime.now(),
      categoryId: map['category_id']?.toString(),
      categoryName: cat is Map ? cat['name']?.toString() : null,
      description: map['description']?.toString(),
      payee: map['payee']?.toString(),
      receiptReference: map['receipt_reference']?.toString(),
    );
  }

  final String id;
  final String movementType;
  final double amount;
  final DateTime occurredAt;
  final String? categoryId;
  final String? categoryName;
  final String? description;
  final String? payee;
  final String? receiptReference;

  double get signedAmount {
    switch (movementType) {
      case 'income':
      case 'replenishment':
      case 'adjustment':
        return amount;
      case 'expense':
        return -amount;
      default:
        return 0;
    }
  }

  String get typeLabel {
    switch (movementType) {
      case 'income':
        return 'Ingreso';
      case 'expense':
        return 'Gasto';
      case 'replenishment':
        return 'Reposición';
      case 'adjustment':
        return 'Ajuste';
      default:
        return movementType;
    }
  }
}

class PettyCashData {
  PettyCashData({
    required this.openSession,
    required this.recentSessions,
    required this.movements,
    required this.categories,
  });

  final PettyCashSession? openSession;
  final List<PettyCashSession> recentSessions;
  final List<PettyCashMovement> movements;
  final List<PettyCashCategory> categories;
}

class PettyCashOpenInput {
  PettyCashOpenInput({required this.openingAmount, this.notes});

  final double openingAmount;
  final String? notes;
}

class PettyCashCloseInput {
  PettyCashCloseInput({required this.closingAmount, this.notes});

  final double closingAmount;
  final String? notes;
}

class PettyCashMovementInput {
  PettyCashMovementInput({
    required this.movementType,
    required this.amount,
    this.categoryId,
    this.description,
    this.payee,
    this.receiptReference,
  });

  final String movementType;
  final double amount;
  final String? categoryId;
  final String? description;
  final String? payee;
  final String? receiptReference;
}

// ─────────────────────────────────────────────────────────────────────────
// Repository
// ─────────────────────────────────────────────────────────────────────────

class PettyCashRepository {
  PettyCashRepository(this._client);

  final SupabaseClient _client;

  Future<PettyCashData> fetchData() async {
    final branchId = await _currentBranchId();
    if (branchId == null) {
      return PettyCashData(
        openSession: null,
        recentSessions: const [],
        movements: const [],
        categories: const [],
      );
    }

    // Categorías, sesión abierta y sesiones recientes son independientes → en
    // paralelo (3 round-trips → 1). Los movimientos dependen de la sesión.
    final (categories, openSession, recentSessions) = await (
      _fetchCategories(branchId),
      _fetchOpenSession(branchId),
      _fetchRecentSessions(branchId),
    ).wait;
    final movements = openSession == null
        ? const <PettyCashMovement>[]
        : await fetchMovementsForSession(openSession.id);

    return PettyCashData(
      openSession: openSession,
      recentSessions: recentSessions,
      movements: movements,
      categories: categories,
    );
  }

  Future<void> openSession(PettyCashOpenInput input) async {
    final branchId = await _currentBranchId();
    if (branchId == null) {
      throw Exception('No hay sucursal asignada.');
    }
    final userId = _client.auth.currentUser?.id;
    if (userId == null) {
      throw Exception('Sesión inválida. Inicia sesión de nuevo.');
    }

    final existing = await _fetchOpenSession(branchId);
    if (existing != null) {
      throw Exception('Ya hay una caja chica abierta para esta sucursal.');
    }
    if (input.openingAmount < 0) {
      throw Exception('El monto de apertura no puede ser negativo.');
    }

    await _client.from('petty_cash_sessions').insert({
      'branch_id': branchId,
      'opened_by': userId,
      'status': 'open',
      'opening_amount': _round2(input.openingAmount),
      'expected_amount': _round2(input.openingAmount),
      'notes': _nullIfEmpty(input.notes),
    });
  }

  Future<void> closeSession(PettyCashCloseInput input) async {
    final branchId = await _currentBranchId();
    if (branchId == null) {
      throw Exception('No hay sucursal asignada.');
    }
    final userId = _client.auth.currentUser?.id;
    if (userId == null) {
      throw Exception('Sesión inválida.');
    }
    final openSession = await _fetchOpenSession(branchId);
    if (openSession == null) {
      throw Exception('No hay una caja chica abierta.');
    }
    final closingAmount = _round2(input.closingAmount);
    final difference = _round2(closingAmount - openSession.expectedAmount);

    await _client
        .from('petty_cash_sessions')
        .update({
          'status': 'closed',
          'closed_by': userId,
          'closed_at': DateTime.now().toUtc().toIso8601String(),
          'closing_amount': closingAmount,
          'difference_amount': difference,
          'notes': _nullIfEmpty(input.notes) ?? openSession.notes,
        })
        .eq('id', openSession.id)
        .eq('branch_id', branchId);
  }

  Future<void> addMovement(PettyCashMovementInput input) async {
    final branchId = await _currentBranchId();
    if (branchId == null) {
      throw Exception('No hay sucursal asignada.');
    }
    final openSession = await _fetchOpenSession(branchId);
    if (openSession == null) {
      throw Exception('Abre la caja chica antes de registrar movimientos.');
    }
    if (input.amount <= 0) {
      throw Exception('El monto debe ser mayor que cero.');
    }

    await _client.from('petty_cash_movements').insert({
      'petty_cash_session_id': openSession.id,
      'branch_id': branchId,
      'movement_type': input.movementType,
      'category_id': input.categoryId,
      'amount': _round2(input.amount),
      'description': _nullIfEmpty(input.description),
      'payee': _nullIfEmpty(input.payee),
      'receipt_reference': _nullIfEmpty(input.receiptReference),
    });
  }

  Future<void> deleteMovement(String movementId) async {
    final branchId = await _currentBranchId();
    if (branchId == null) {
      throw Exception('No hay sucursal asignada.');
    }
    await _client
        .from('petty_cash_movements')
        .delete()
        .eq('id', movementId)
        .eq('branch_id', branchId);
  }

  Future<List<PettyCashMovement>> fetchMovementsForSession(
    String sessionId,
  ) async {
    final branchId = await _currentBranchId();
    if (branchId == null) return const [];

    final rows = await _client
        .from('petty_cash_movements')
        .select(
          'id, movement_type, category_id, amount, description, payee, '
          'receipt_reference, occurred_at, '
          'petty_cash_categories(name)',
        )
        .eq('branch_id', branchId)
        .eq('petty_cash_session_id', sessionId)
        .order('occurred_at', ascending: false);

    return rows
        .map((item) => PettyCashMovement.fromMap(
              Map<String, dynamic>.from(item as Map),
            ))
        .toList(growable: false);
  }

  Future<PettyCashSession?> _fetchOpenSession(String branchId) async {
    final rows = await _client
        .from('petty_cash_sessions')
        .select()
        .eq('branch_id', branchId)
        .eq('status', 'open')
        .order('opened_at', ascending: false)
        .limit(1);
    if (rows.isEmpty) return null;
    return PettyCashSession.fromMap(
      Map<String, dynamic>.from(rows.first as Map),
    );
  }

  Future<List<PettyCashSession>> _fetchRecentSessions(String branchId) async {
    final rows = await _client
        .from('petty_cash_sessions')
        .select()
        .eq('branch_id', branchId)
        .order('opened_at', ascending: false)
        .limit(15);
    return rows
        .map((item) => PettyCashSession.fromMap(
              Map<String, dynamic>.from(item as Map),
            ))
        .toList(growable: false);
  }

  Future<List<PettyCashCategory>> _fetchCategories(String branchId) async {
    final rows = await _client
        .from('petty_cash_categories')
        .select('id, name, description')
        .eq('branch_id', branchId)
        .eq('is_active', true)
        .order('sort_order')
        .order('name');
    return rows
        .map((item) => PettyCashCategory.fromMap(
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
}

// ─────────────────────────────────────────────────────────────────────────
// Helpers
// ─────────────────────────────────────────────────────────────────────────

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
