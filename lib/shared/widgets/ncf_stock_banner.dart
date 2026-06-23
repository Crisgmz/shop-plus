// Banner global que avisa cuando alguna secuencia NCF de la sucursal actual
// está por agotarse o vencida. Lee la vista `vw_ncf_stock`.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme/tokens.dart';
import '../../features/auth/presentation/auth_providers.dart';

class NcfStockRow {
  const NcfStockRow({
    required this.receiptType,
    required this.prefix,
    required this.remaining,
    required this.isLowStock,
    required this.isExpired,
  });

  final String receiptType;
  final String prefix;
  final int? remaining;
  final bool isLowStock;
  final bool isExpired;

  factory NcfStockRow.fromMap(Map<String, dynamic> m) {
    return NcfStockRow(
      receiptType: (m['receipt_type'] ?? '').toString(),
      prefix: (m['prefix'] ?? '').toString(),
      remaining: (m['remaining'] as num?)?.toInt(),
      isLowStock: m['is_low_stock'] == true,
      isExpired: m['is_expired'] == true,
    );
  }
}

/// Devuelve solo las filas con alerta (vencidas o stock bajo). Si la vista
/// no existe (migración no aplicada) devuelve lista vacía.
final ncfStockAlertsProvider =
    FutureProvider.autoDispose<List<NcfStockRow>>((ref) async {
  final client = ref.watch(supabaseClientProvider);
  try {
    final result = await client
        .from('vw_ncf_stock')
        .select(
          'receipt_type, prefix, remaining, is_low_stock, is_expired, is_active',
        )
        .eq('is_active', true)
        .or('is_low_stock.eq.true,is_expired.eq.true');
    return (result as List)
        .map((row) => NcfStockRow.fromMap(row as Map<String, dynamic>))
        .toList(growable: false);
  } catch (_) {
    return const [];
  }
});

/// Cuenta las ventas YA emitidas (completed/credit) que quedaron SIN NCF en la
/// sucursal actual. Es la señal de que faltó una secuencia o se agotó: el
/// trigger no bloquea la venta, así que sin esta alerta la pérdida sería
/// silenciosa. El backfill (`bulk_assign_missing_ncfs`) las corrige.
final missingNcfCountProvider =
    FutureProvider.autoDispose<int>((ref) async {
  final client = ref.watch(supabaseClientProvider);
  try {
    final branchId = await client.rpc('current_branch_id');
    if (branchId == null) return 0;
    final rows = await client
        .from('sales')
        .select('id')
        .eq('branch_id', branchId)
        .inFilter('status', const ['completed', 'credit'])
        .or('ncf.is.null');
    return (rows as List).length;
  } catch (_) {
    return 0;
  }
});

class NcfStockBanner extends ConsumerWidget {
  const NcfStockBanner({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final missing = ref.watch(missingNcfCountProvider).valueOrNull ?? 0;
    final stockRows = ref.watch(ncfStockAlertsProvider).valueOrNull ?? const [];

    final banners = <Widget>[
      // Lo más urgente arriba: ventas ya emitidas sin comprobante.
      if (missing > 0) _missingNcfBanner(context, missing),
      if (stockRows.isNotEmpty) _stockBanner(context, stockRows),
    ];
    if (banners.isEmpty) return const SizedBox.shrink();
    return Column(children: banners);
  }

  Widget _missingNcfBanner(BuildContext context, int count) {
    const color = AppTokens.destructive;
    return _bannerShell(
      context,
      color: color,
      icon: Icons.receipt_long_outlined,
      headline: '$count venta(s) sin NCF',
      detail:
          'Se emitieron sin comprobante (faltó secuencia). Toca para asignar.',
    );
  }

  Widget _stockBanner(BuildContext context, List<NcfStockRow> rows) {
    final anyExpired = rows.any((r) => r.isExpired);
    final color = anyExpired ? AppTokens.destructive : AppTokens.warning;
    final details = rows
        .map((r) =>
            '${_label(r.receiptType)} (${r.prefix}): ${r.isExpired ? "vencida" : "quedan ${r.remaining ?? 0}"}')
        .join(' · ');
    return _bannerShell(
      context,
      color: color,
      icon: anyExpired ? Icons.error_outline : Icons.warning_amber_outlined,
      headline: anyExpired ? 'Secuencia NCF vencida' : 'Stock de NCF bajo',
      detail: '$details · Toca para configurar.',
    );
  }

  Widget _bannerShell(
    BuildContext context, {
    required Color color,
    required IconData icon,
    required String headline,
    required String detail,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: AppTokens.s12),
      child: InkWell(
        // La gestión de secuencias NCF (crear, y "Asignar faltantes") vive en
        // SettingsPage (/configuracion/cuenta), no en la config global.
        onTap: () => context.go('/configuracion/cuenta'),
        borderRadius: BorderRadius.circular(8),
        child: Container(
          padding: const EdgeInsets.all(AppTokens.s12),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.10),
            border: Border.all(color: color.withValues(alpha: 0.40)),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Row(
            children: [
              Icon(icon, color: color, size: 20),
              const SizedBox(width: AppTokens.s12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      headline,
                      style: TextStyle(
                        color: color,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(detail, style: const TextStyle(fontSize: 12)),
                  ],
                ),
              ),
              Icon(Icons.chevron_right, color: color, size: 20),
            ],
          ),
        ),
      ),
    );
  }

  static String _label(String type) {
    switch (type) {
      case 'consumer_final':
        return 'Consumidor Final';
      case 'fiscal_credit':
        return 'Crédito Fiscal';
      case 'governmental':
        return 'Gubernamental';
      case 'special':
        return 'Régimen Especial';
      case 'export':
        return 'Exportación';
      default:
        return type;
    }
  }
}
