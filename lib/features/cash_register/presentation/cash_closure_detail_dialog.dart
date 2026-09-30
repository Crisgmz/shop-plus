import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:printing/printing.dart';

import '../../../core/theme/tokens.dart';
import '../../../shared/formatters/formatters.dart';
import '../../shell/presentation/shell_providers.dart';
import '../data/cash_closure_pdf_builder.dart';
import '../data/cash_register_repository.dart';
import 'cash_register_providers.dart';

class CashClosureDetailDialog extends ConsumerStatefulWidget {
  const CashClosureDetailDialog({super.key, required this.session});

  final CashSessionEntity session;

  @override
  ConsumerState<CashClosureDetailDialog> createState() =>
      _CashClosureDetailDialogState();
}

class _CashClosureDetailDialogState
    extends ConsumerState<CashClosureDetailDialog> {
  late Future<_DetailBundle> _bundleFuture;

  @override
  void initState() {
    super.initState();
    _bundleFuture = _loadBundle();
  }

  Future<_DetailBundle> _loadBundle() async {
    final repo = ref.read(cashRegisterRepositoryProvider);
    final movements = await repo.fetchMovementsForSession(widget.session.id);
    final metrics = await repo.fetchSessionMetrics(widget.session.id);
    return _DetailBundle(movements: movements, metrics: metrics);
  }

  /// Web: el `await build()` previo rompía el user gesture y la ventana
  /// de impresión quedaba bloqueada. Generamos el PDF dentro de
  /// `onLayout` para que `Printing.layoutPdf` se llame inmediatamente
  /// al click.
  Future<void> _print(double widthMm, _DetailBundle bundle) async {
    final branchName = ref.read(shellCurrentBranchNameProvider).valueOrNull;
    final userInfo = ref.read(shellUserInfoProvider).valueOrNull;

    await Printing.layoutPdf(
      name: 'cierre-caja-${widget.session.id.substring(0, 8)}',
      onLayout: (_) => const CashClosurePdfBuilder().build(
        session: widget.session,
        metrics: bundle.metrics,
        movements: bundle.movements,
        widthMm: widthMm,
        branchName: branchName,
        cashierName: userInfo?.displayName,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 560, maxHeight: 720),
        child: FutureBuilder<_DetailBundle>(
          future: _bundleFuture,
          builder: (context, snapshot) {
            if (snapshot.connectionState != ConnectionState.done) {
              return const SizedBox(
                height: 260,
                child: Center(child: CircularProgressIndicator()),
              );
            }
            if (snapshot.hasError) {
              return Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.error_outline,
                        size: 48, color: AppTokens.destructive),
                    const SizedBox(height: 12),
                    Text('No se pudo cargar el detalle: ${snapshot.error}'),
                    const SizedBox(height: 12),
                    TextButton(
                      onPressed: () => Navigator.of(context).pop(),
                      child: const Text('Cerrar'),
                    ),
                  ],
                ),
              );
            }
            final bundle = snapshot.data!;
            return _DialogBody(
              session: widget.session,
              bundle: bundle,
              onPrint58: () => _print(58, bundle),
              onPrint80: () => _print(80, bundle),
            );
          },
        ),
      ),
    );
  }
}

class _DetailBundle {
  _DetailBundle({required this.movements, required this.metrics});

  final List<CashMovementEntity> movements;
  final CashSessionMetrics metrics;
}

class _DialogBody extends StatelessWidget {
  const _DialogBody({
    required this.session,
    required this.bundle,
    required this.onPrint58,
    required this.onPrint80,
  });

  final CashSessionEntity session;
  final _DetailBundle bundle;
  final VoidCallback onPrint58;
  final VoidCallback onPrint80;

  @override
  Widget build(BuildContext context) {
    final metrics = bundle.metrics;
    // Cerrada: el esperado que se guardó al cerrar. Recalcularlo con datos de
    // hoy (una anulación o un abono posteriores) dejaba "Esperado − Conteo"
    // distinto de la "Diferencia" guardada.
    final expectedCash = session.isOpen
        ? metrics.expectedCashFromOpening(session.openingAmount)
        : session.expectedAmount;
    final diff = session.differenceAmount;

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(24, 20, 16, 12),
          child: Row(
            children: [
              const Icon(Icons.point_of_sale_outlined,
                  color: AppTokens.primary),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Detalle de cierre de caja',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    Text(
                      'Sesión ${session.id.substring(0, 8).toUpperCase()} · '
                      '${session.isOpen ? "Abierta" : "Cerrada"}',
                      style: const TextStyle(
                        fontSize: 12,
                        color: AppTokens.mutedForeground,
                      ),
                    ),
                  ],
                ),
              ),
              IconButton(
                onPressed: () => Navigator.of(context).pop(),
                icon: const Icon(Icons.close),
              ),
            ],
          ),
        ),
        const Divider(height: 1),
        Flexible(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(24, 16, 24, 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _section('Sesión'),
                _kv('Apertura', formatDateTime(session.openedAt)),
                if (session.closedAt != null)
                  _kv('Cierre', formatDateTime(session.closedAt!)),
                if (session.notes != null && session.notes!.trim().isNotEmpty)
                  _kv('Notas', session.notes!.trim()),
                const SizedBox(height: 16),
                _section('Montos'),
                _kv('Monto apertura', money(session.openingAmount)),
                _kv('Total cobros', money(metrics.totalPayments)),
                _kv('  En efectivo', money(metrics.cashPayments)),
                _kv('Total gastos', money(metrics.totalExpenses)),
                _kv('  En efectivo', money(metrics.cashExpenses)),
                // Todo lo que mueve el efectivo esperado, para que la cuenta
                // se pueda seguir de arriba abajo.
                if (metrics.changeGiven > 0)
                  _kv('Cambio entregado', money(metrics.changeGiven)),
                if (metrics.supplierCashPayments > 0)
                  _kv('Pagos a proveedores',
                      money(metrics.supplierCashPayments)),
                if (metrics.cashRefunds > 0)
                  _kv('Devoluciones', money(metrics.cashRefunds)),
                if (metrics.cashDeposits > 0)
                  _kv('Depósitos', money(metrics.cashDeposits)),
                if (metrics.cashAdjustments > 0)
                  _kv('Ajustes', money(metrics.cashAdjustments)),
                if (metrics.cashWithdrawals > 0)
                  _kv('Sangrías', money(metrics.cashWithdrawals)),
                if (metrics.cashVoidRefunds > 0)
                  _kv('Anulaciones de turnos anteriores',
                      money(metrics.cashVoidRefunds)),
                const SizedBox(height: 12),
                _kv('Esperado en caja', money(expectedCash), bold: true),
                if (session.closingAmount != null)
                  _kv('Conteo cierre', money(session.closingAmount!),
                      bold: true),
                if (diff != null)
                  _kv(
                    'Diferencia',
                    money(diff),
                    bold: true,
                    valueColor:
                        diff < 0 ? AppTokens.destructive : const Color(0xFF16A34A),
                  ),
                if (bundle.movements.isNotEmpty) ...[
                  const SizedBox(height: 16),
                  _section('Movimientos manuales'),
                  for (final mv in bundle.movements)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 4),
                      child: Row(
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  mv.typeLabel,
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                                if (mv.reason != null &&
                                    mv.reason!.trim().isNotEmpty)
                                  Text(
                                    mv.reason!.trim(),
                                    style: const TextStyle(
                                      fontSize: 12,
                                      color: AppTokens.mutedForeground,
                                    ),
                                  ),
                                Text(
                                  formatDateTime(mv.occurredAt),
                                  style: const TextStyle(
                                    fontSize: 11,
                                    color: AppTokens.mutedForeground,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          Text(
                            money(mv.signedAmount),
                            style: TextStyle(
                              fontWeight: FontWeight.w700,
                              color: mv.signedAmount < 0
                                  ? AppTokens.destructive
                                  : null,
                            ),
                          ),
                        ],
                      ),
                    ),
                ],
              ],
            ),
          ),
        ),
        const Divider(height: 1),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              OutlinedButton.icon(
                onPressed: onPrint58,
                icon: const Icon(Icons.receipt_long, size: 18),
                label: const Text('Imprimir 58mm'),
              ),
              const SizedBox(width: 8),
              FilledButton.icon(
                onPressed: onPrint80,
                icon: const Icon(Icons.print_outlined, size: 18),
                label: const Text('Imprimir 80mm'),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _section(String label) => Padding(
        padding: const EdgeInsets.only(bottom: 6),
        child: Text(
          label.toUpperCase(),
          style: const TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w800,
            letterSpacing: 1,
            color: Color(0xFF64748B),
          ),
        ),
      );

  Widget _kv(
    String left,
    String right, {
    bool bold = false,
    Color? valueColor,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Text(
              left,
              style: TextStyle(
                fontSize: 13,
                fontWeight: bold ? FontWeight.w700 : FontWeight.w400,
                color: AppTokens.mutedForeground,
              ),
            ),
          ),
          Text(
            right,
            style: TextStyle(
              fontSize: 13,
              fontWeight: bold ? FontWeight.w700 : FontWeight.w500,
              color: valueColor,
            ),
          ),
        ],
      ),
    );
  }
}
