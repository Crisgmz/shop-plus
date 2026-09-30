import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:printing/printing.dart';

import '../../../core/theme/tokens.dart';
import '../../../shared/errors/friendly_error.dart';
import '../../../shared/formatters/formatters.dart';
import '../../../shared/responsive/responsive_layout.dart';
import '../../../shared/widgets/empty_state.dart';
import '../../../shared/widgets/module_page.dart';
import '../../../shared/widgets/role_gate.dart';
import '../../../shared/widgets/ui_custom.dart';
import '../../shell/presentation/shell_providers.dart';
import '../data/cash_closure_pdf_builder.dart';
import '../data/cash_register_repository.dart';
import 'cash_closure_detail_dialog.dart';
import 'cash_register_providers.dart';

class CashRegisterPage extends ConsumerStatefulWidget {
  const CashRegisterPage({super.key});

  @override
  ConsumerState<CashRegisterPage> createState() => _CashRegisterPageState();
}

class _CashRegisterPageState extends ConsumerState<CashRegisterPage> {
  @override
  Widget build(BuildContext context) {
    final dataAsync = ref.watch(cashRegisterDataProvider);

    return ModulePage(
      title: 'Caja',
      description: 'Apertura, arqueo, diferencias y cierre diario.',
      actions: [
        OutlinedButton.icon(
          onPressed: () => ref.invalidate(cashRegisterDataProvider),
          icon: const Icon(Icons.refresh, size: 18),
          label: const Text('Actualizar'),
        ),
      ],
      child: dataAsync.when(
        data: (data) {
          final openSession = data.openSession;
          final metrics = data.openMetrics;
          final accessAsync = ref.watch(shellAccessProfileProvider);
          final role = accessAsync.valueOrNull?.roleCode;
          final canSeeAllCashiers = role == 'admin' || role == 'supervisor';

          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (openSession == null)
                _noSessionCard()
              else
                _openSessionCard(
                  openSession,
                  metrics,
                  data.pettyCashExpensesToday,
                ),
              if (canSeeAllCashiers) ...[
                const SizedBox(height: AppTokens.s24),
                const _AllCashiersPanel(),
              ],
              const SizedBox(height: AppTokens.s24),
              DataTableShell(
                title: 'Sesiones recientes',
                child: data.recentSessions.isEmpty
                    ? const Padding(
                        padding: EdgeInsets.all(AppTokens.s20),
                        child: Text(
                          'Aún no hay sesiones registradas.',
                          style: TextStyle(color: AppTokens.mutedForeground),
                        ),
                      )
                    : DataTable(
                        columns: const [
                          DataColumn(label: Text('Apertura')),
                          DataColumn(label: Text('Cierre')),
                          DataColumn(label: Text('Estado')),
                          DataColumn(label: Text('Monto apertura'), numeric: true),
                          DataColumn(label: Text('Esperado'), numeric: true),
                          DataColumn(label: Text('Conteo cierre'), numeric: true),
                          DataColumn(label: Text('Diferencia'), numeric: true),
                          DataColumn(label: Text('Acciones')),
                        ],
                        rows: data.recentSessions
                            .map(
                              (session) => DataRow(
                                cells: [
                                  DataCell(Text(formatDateTime(session.openedAt))),
                                  DataCell(Text(
                                    session.closedAt == null
                                        ? '-'
                                        : formatDateTime(session.closedAt!),
                                  )),
                                  DataCell(StatusBadge(
                                    label: session.isOpen ? 'Abierta' : 'Cerrada',
                                    status: session.isOpen ? 'open' : 'closed',
                                  )),
                                  DataCell(Text(money(session.openingAmount))),
                                  DataCell(Text(money(session.expectedAmount))),
                                  DataCell(Text(
                                    session.closingAmount == null
                                        ? '-'
                                        : money(session.closingAmount!),
                                  )),
                                  DataCell(Text(
                                    session.differenceAmount == null
                                        ? '-'
                                        : money(session.differenceAmount!),
                                    style: TextStyle(
                                      fontWeight: FontWeight.w700,
                                      color: session.differenceAmount != null &&
                                              session.differenceAmount! < 0
                                          ? AppTokens.destructive
                                          : null,
                                    ),
                                  )),
                                  DataCell(
                                    Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        IconButton(
                                          tooltip: 'Ver detalle',
                                          onPressed: () =>
                                              _onViewDetail(session),
                                          icon: const Icon(
                                            Icons.visibility_outlined,
                                            size: 18,
                                          ),
                                          visualDensity:
                                              VisualDensity.compact,
                                          padding: EdgeInsets.zero,
                                          constraints: const BoxConstraints(
                                            minWidth: 32,
                                            minHeight: 32,
                                          ),
                                        ),
                                        if (!session.isOpen) ...[
                                          const SizedBox(width: 4),
                                          PopupMenuButton<double>(
                                            tooltip:
                                                'Reimprimir cierre',
                                            onSelected: (widthMm) =>
                                                _onReprint(
                                              session,
                                              widthMm,
                                            ),
                                            itemBuilder: (_) => const [
                                              PopupMenuItem<double>(
                                                value: 58,
                                                child:
                                                    Text('Imprimir 58mm'),
                                              ),
                                              PopupMenuItem<double>(
                                                value: 80,
                                                child:
                                                    Text('Imprimir 80mm'),
                                              ),
                                            ],
                                            child: const Padding(
                                              padding: EdgeInsets.all(6),
                                              child: Icon(
                                                Icons.print_outlined,
                                                size: 18,
                                              ),
                                            ),
                                          ),
                                        ],
                                        if (!session.isOpen) ...[
                                          const SizedBox(width: 4),
                                          RoleGate(
                                            allowed: const {
                                              'admin',
                                              'supervisor'
                                            },
                                            child: OutlinedButton.icon(
                                              onPressed: () =>
                                                  _onSealZ(session.id),
                                              icon: const Icon(
                                                  Icons.lock_outline,
                                                  size: 14),
                                              label: const Text(
                                                'Sellar Z',
                                                style: TextStyle(fontSize: 12),
                                              ),
                                              style: OutlinedButton.styleFrom(
                                                minimumSize: const Size(0, 28),
                                                padding: const EdgeInsets
                                                    .symmetric(horizontal: 8),
                                                tapTargetSize:
                                                    MaterialTapTargetSize
                                                        .shrinkWrap,
                                                foregroundColor:
                                                    AppTokens.primary,
                                              ),
                                            ),
                                          ),
                                        ],
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                            )
                            .toList(growable: false),
                      ),
              ),
            ],
          );
        },
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) => ErrorCard(
          message: 'No se pudo cargar caja: ${friendlyErrorMessage(error)}',
          onRetry: () => ref.invalidate(cashRegisterDataProvider),
        ),
      ),
    );
  }

  Widget _noSessionCard() {
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: AppTokens.card,
        borderRadius: BorderRadius.circular(AppTokens.radius),
        border: Border.all(color: AppTokens.border),
      ),
      padding: const EdgeInsets.all(AppTokens.s20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'No hay caja abierta',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w600,
              color: AppTokens.foreground,
            ),
          ),
          const SizedBox(height: AppTokens.s8),
          const Text(
            'Abre una caja para empezar a registrar movimientos del turno.',
            style: TextStyle(color: AppTokens.mutedForeground),
          ),
          const SizedBox(height: AppTokens.s16),
          FilledButton.icon(
            onPressed: _onOpenSession,
            icon: const Icon(Icons.lock_open_outlined, size: 18),
            label: const Text('Abrir caja'),
          ),
        ],
      ),
    );
  }

  Widget _openSessionCard(
    CashSessionEntity openSession,
    CashSessionMetrics? metrics,
    double pettyCashExpensesToday,
  ) {
    final expectedCash = metrics == null
        ? openSession.expectedAmount
        : metrics.expectedCashFromOpening(openSession.openingAmount);

    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: AppTokens.card,
        borderRadius: BorderRadius.circular(AppTokens.radius),
        border: Border.all(color: AppTokens.border),
      ),
      padding: const EdgeInsets.all(AppTokens.s20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Expanded(
                child: Text(
                  'Caja abierta',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: AppTokens.foreground,
                  ),
                ),
              ),
              OutlinedButton.icon(
                onPressed: () => _onCashMovement(openSession.id, 'deposit'),
                icon: const Icon(Icons.add_circle_outline,
                    size: 18, color: Color(0xFF22C55E)),
                label: const Text('Agregar efectivo'),
              ),
              const SizedBox(width: 8),
              OutlinedButton.icon(
                onPressed: () =>
                    _onCashMovement(openSession.id, 'withdrawal'),
                icon: const Icon(Icons.remove_circle_outline,
                    size: 18, color: Color(0xFFEF4444)),
                label: const Text('Sangría'),
              ),
              const SizedBox(width: 8),
              FilledButton.icon(
                onPressed: () => _onCloseSession(openSession.id),
                icon: const Icon(Icons.lock_outline, size: 18),
                label: const Text('Cerrar caja'),
              ),
            ],
          ),
          const SizedBox(height: AppTokens.s8),
          Text(
            'Abierta: ${formatDateTime(openSession.openedAt)}',
            style: const TextStyle(color: AppTokens.mutedForeground),
          ),
          const SizedBox(height: AppTokens.s16),
          LayoutBuilder(
            builder: (context, constraints) {
              final cards = [
                KPICard(
                  label: 'Apertura',
                  value: money(openSession.openingAmount),
                  icon: Icons.lock_open_outlined,
                ),
                KPICard(
                  label: 'Ingreso efectivo',
                  value: money(metrics?.cashPayments ?? 0),
                  icon: Icons.payments_outlined,
                ),
                KPICard(
                  label: 'Transferencia',
                  value: money(metrics?.transferPayments ?? 0),
                  icon: Icons.account_balance_outlined,
                ),
                KPICard(
                  label: 'Tarjeta',
                  value: money(metrics?.cardPayments ?? 0),
                  icon: Icons.credit_card_outlined,
                ),
                KPICard(
                  label: 'Otro',
                  value: money(metrics?.otherPayments ?? 0),
                  icon: Icons.more_horiz_rounded,
                ),
                KPICard(
                  // Gastos registrados contra ESTA sesión de caja (tabla
                  // expenses con cash_session_id). El efectivo de estos gastos
                  // ya baja del esperado.
                  label: 'Gastos caja (hoy)',
                  value: money(metrics?.totalExpenses ?? 0),
                  icon: Icons.savings_outlined,
                ),
                KPICard(
                  label: 'Cambio devuelto',
                  value: money(metrics?.changeGiven ?? 0),
                  icon: Icons.currency_exchange_rounded,
                ),
                KPICard(
                  label: 'Total de venta',
                  value: money(metrics?.salesTotal ?? 0),
                  icon: Icons.point_of_sale_outlined,
                ),
                KPICard(
                  label: 'Esperado en caja',
                  value: money(expectedCash),
                  icon: Icons.account_balance_wallet_outlined,
                ),
              ];
              final width = constraints.maxWidth;
              final crossAxisCount = width >= 900 ? 3 : width >= 500 ? 2 : 1;
              final cardWidth = (width - (crossAxisCount - 1) * 12) / crossAxisCount;
              return Wrap(
                spacing: 12,
                runSpacing: 12,
                children: cards.map((c) => SizedBox(width: cardWidth, child: c)).toList(),
              );
            },
          ),
        ],
      ),
    );
  }

  Future<void> _onOpenSession() async {
    // Cargar las cajas a las que el usuario tiene acceso. Si hay cajas
    // configuradas en la sucursal, exigimos que elija una.
    final myCajas =
        await ref.read(myCashRegistersProvider.future).catchError((_) {
      return <CashRegisterEntity>[];
    });

    if (!mounted) return;

    final input = await showDialog<OpenCashInput>(
      context: context,
      builder: (_) => _OpenSessionDialog(availableCajas: myCajas),
    );

    if (input == null || !mounted) return;

    final repository = ref.read(cashRegisterRepositoryProvider);

    try {
      if (input.cashRegisterId != null && input.cashRegisterId!.isNotEmpty) {
        // Flujo nuevo: vía RPC que valida acceso a la caja.
        await repository.openSessionForRegister(input);
      } else {
        // Sin cajas configuradas → flujo legacy (sesión sin caja asignada).
        await repository.openSession(input);
      }
      if (!mounted) return;

      ref.invalidate(cashRegisterDataProvider);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Caja abierta correctamente.')),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('No se pudo abrir caja: ${friendlyErrorMessage(error)}')));
    }
  }

  Future<void> _onCloseSession(String sessionId) async {
    final input = await showDialog<CloseCashInput>(
      context: context,
      builder: (_) => const _CloseSessionDialog(),
    );

    if (input == null || !mounted) return;

    final repository = ref.read(cashRegisterRepositoryProvider);

    try {
      await repository.closeSession(input, cashSessionId: sessionId);
      if (!mounted) return;

      // Si la caja que se cerró era la activa, deseleccionarla para que el POS
      // pida elegir caja de nuevo en vez de quedar apuntando a una cerrada.
      if (ref.read(activeCashSessionIdProvider) == sessionId) {
        ref.read(activeCashSessionIdProvider.notifier).state = null;
      }
      ref.invalidate(cashRegisterDataProvider);
      ref.invalidate(myOpenCashSessionsProvider);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Caja cerrada correctamente.')),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('No se pudo cerrar caja: ${friendlyErrorMessage(error)}')));
    }
  }

  Future<void> _onViewDetail(CashSessionEntity session) async {
    await showDialog<void>(
      context: context,
      builder: (_) => CashClosureDetailDialog(session: session),
    );
  }

  /// Reimprime un cierre de caja sin abrir el dialog de detalle. Acceso
  /// directo desde el botón de la fila — mismo PDF que el detalle.
  ///
  /// Importante para Flutter Web: `Printing.layoutPdf` se llama
  /// inmediatamente en el callback del click (sin awaits previos) para
  /// preservar el "user gesture" que Chrome/Edge exigen para abrir la
  /// ventana de impresión. Los fetches y la generación del PDF ocurren
  /// dentro de `onLayout`, que se ejecuta una vez la ventana ya está
  /// abierta.
  Future<void> _onReprint(
    CashSessionEntity session,
    double widthMm,
  ) async {
    final messenger = ScaffoldMessenger.of(context);
    final repo = ref.read(cashRegisterRepositoryProvider);
    final branchName = ref.read(shellCurrentBranchNameProvider).valueOrNull;
    final userInfo = ref.read(shellUserInfoProvider).valueOrNull;

    try {
      await Printing.layoutPdf(
        name: 'cierre-caja-${session.id.substring(0, 8)}',
        onLayout: (_) async {
          final movements = await repo.fetchMovementsForSession(session.id);
          final metrics = await repo.fetchSessionMetrics(session.id);
          return const CashClosurePdfBuilder().build(
            session: session,
            metrics: metrics,
            movements: movements,
            widthMm: widthMm,
            branchName: branchName,
            cashierName: userInfo?.displayName,
          );
        },
      );
    } catch (error) {
      messenger.showSnackBar(
        SnackBar(content: Text('No se pudo reimprimir: ${friendlyErrorMessage(error)}')),
      );
    }
  }

  /// Sella un cierre Z fiscal (inmutable) para una sesión ya cerrada.
  /// Pide confirmación explícita porque la operación no se puede revertir
  /// (sólo se puede emitir un cierre Z "complementario").
  Future<void> _onSealZ(String cashSessionId) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Sellar cierre Z fiscal'),
        content: const Text(
          'El cierre Z queda inmutable una vez sellado. Cualquier corrección '
          'requiere emitir un cierre Z complementario. ¿Continuar?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancelar'),
          ),
          FilledButton.icon(
            style: FilledButton.styleFrom(
              backgroundColor: AppTokens.primary,
            ),
            onPressed: () => Navigator.pop(ctx, true),
            icon: const Icon(Icons.lock_outline, size: 18),
            label: const Text('Sellar Z'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    final repository = ref.read(cashRegisterRepositoryProvider);
    try {
      final closureId = await repository.sealFiscalZClosure(cashSessionId);
      if (!mounted) return;
      ref.invalidate(cashRegisterDataProvider);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: AppTokens.primary,
          content: Text(
            'Cierre Z sellado · ${closureId.substring(0, 8)}…',
            style: const TextStyle(color: Colors.white),
          ),
        ),
      );
    } catch (error) {
      if (!mounted) return;
      // Si ya existe un cierre Z para esta sesión, el RPC lo bloquea.
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('No se pudo sellar el cierre Z: ${friendlyErrorMessage(error)}')),
      );
    }
  }

  /// Diálogo para agregar (deposit) o retirar (withdrawal) efectivo de la
  /// sesión activa. El trigger SQL ajusta `expected_amount` automáticamente.
  Future<void> _onCashMovement(String sessionId, String movementType) async {
    final input = await showDialog<CashMovementInput>(
      context: context,
      builder: (_) => _CashMovementDialog(movementType: movementType),
    );
    if (input == null || !mounted) return;

    final repository = ref.read(cashRegisterRepositoryProvider);
    try {
      await repository.addMovement(input, cashSessionId: sessionId);
      if (!mounted) return;
      ref.invalidate(cashRegisterDataProvider);
      final label = movementType == 'deposit'
          ? 'Efectivo agregado a la caja'
          : 'Sangría registrada';
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: movementType == 'deposit'
              ? const Color(0xFF22C55E)
              : const Color(0xFFEF4444),
          content: Text(
            '$label · ${money(input.amount)}',
            style: const TextStyle(color: Colors.white),
          ),
        ),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('No se pudo registrar el movimiento: ${friendlyErrorMessage(error)}')),
      );
    }
  }
}

class _CashMovementDialog extends StatefulWidget {
  const _CashMovementDialog({required this.movementType});

  final String movementType;

  @override
  State<_CashMovementDialog> createState() => _CashMovementDialogState();
}

class _CashMovementDialogState extends State<_CashMovementDialog> {
  final _formKey = GlobalKey<FormState>();
  final _amountController = TextEditingController();
  final _reasonController = TextEditingController();
  final _notesController = TextEditingController();

  @override
  void dispose() {
    _amountController.dispose();
    _reasonController.dispose();
    _notesController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isDeposit = widget.movementType == 'deposit';
    final accent =
        isDeposit ? const Color(0xFF22C55E) : const Color(0xFFEF4444);
    return AlertDialog(
      title: Row(
        children: [
          Icon(
            isDeposit
                ? Icons.add_circle_outline
                : Icons.remove_circle_outline,
            color: accent,
          ),
          const SizedBox(width: 8),
          Text(isDeposit ? 'Agregar efectivo' : 'Sangría / Retiro'),
        ],
      ),
      content: Form(
        key: _formKey,
        child: SizedBox(
          width: 360,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextFormField(
                controller: _amountController,
                autofocus: true,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                decoration: const InputDecoration(
                  labelText: 'Monto',
                  prefixText: r'RD$ ',
                  border: OutlineInputBorder(),
                ),
                validator: (v) {
                  final n = double.tryParse((v ?? '').trim());
                  if (n == null || n <= 0) return 'Monto inválido';
                  return null;
                },
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _reasonController,
                decoration: InputDecoration(
                  labelText: 'Motivo',
                  hintText: isDeposit
                      ? 'p.ej. Apertura adicional del dueño'
                      : 'p.ej. Depósito al banco',
                  border: const OutlineInputBorder(),
                ),
                validator: (v) =>
                    (v == null || v.trim().isEmpty) ? 'Requerido' : null,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _notesController,
                maxLines: 2,
                decoration: const InputDecoration(
                  labelText: 'Notas (opcional)',
                  border: OutlineInputBorder(),
                ),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancelar'),
        ),
        FilledButton.icon(
          style: FilledButton.styleFrom(backgroundColor: accent),
          onPressed: () {
            if (!(_formKey.currentState?.validate() ?? false)) return;
            Navigator.pop(
              context,
              CashMovementInput(
                movementType: widget.movementType,
                amount: double.parse(_amountController.text.trim()),
                reason: _reasonController.text.trim(),
                notes: _notesController.text.trim(),
              ),
            );
          },
          icon: Icon(
            isDeposit ? Icons.check : Icons.arrow_outward,
            size: 18,
          ),
          label: Text(isDeposit ? 'Agregar' : 'Retirar'),
        ),
      ],
    );
  }
}

class _OpenSessionDialog extends StatefulWidget {
  const _OpenSessionDialog({required this.availableCajas});

  /// Cajas a las que el usuario actual tiene acceso. Si está vacío, el
  /// dialog cae al flujo legacy (sin selector de caja). Si tiene al menos
  /// una, el usuario tiene que elegir cuál abre.
  final List<CashRegisterEntity> availableCajas;

  @override
  State<_OpenSessionDialog> createState() => _OpenSessionDialogState();
}

class _OpenSessionDialogState extends State<_OpenSessionDialog> {
  final _formKey = GlobalKey<FormState>();
  final _openingController = TextEditingController(text: '0');
  final _notesController = TextEditingController();
  String? _selectedCajaId;

  @override
  void initState() {
    super.initState();
    if (widget.availableCajas.length == 1) {
      _selectedCajaId = widget.availableCajas.first.id;
    }
  }

  @override
  void dispose() {
    _openingController.dispose();
    _notesController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final hasCajas = widget.availableCajas.isNotEmpty;
    return AlertDialog(
      title: const Text('Abrir caja'),
      content: SizedBox(
        width: ResponsiveLayout.isMobile(context) ? double.maxFinite : 380,
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (hasCajas) ...[
                DropdownButtonFormField<String>(
                  initialValue: _selectedCajaId,
                  decoration: const InputDecoration(labelText: 'Caja'),
                  items: [
                    for (final caja in widget.availableCajas)
                      DropdownMenuItem(value: caja.id, child: Text(caja.name)),
                  ],
                  onChanged: (v) => setState(() => _selectedCajaId = v),
                  validator: (v) {
                    if (v == null || v.isEmpty) return 'Elige una caja';
                    return null;
                  },
                ),
                const SizedBox(height: 10),
              ],
              TextFormField(
                controller: _openingController,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                decoration: const InputDecoration(labelText: 'Monto de apertura'),
                validator: (value) {
                  final parsed = double.tryParse(value ?? '');
                  if (parsed == null || parsed < 0) return 'Monto inválido';
                  return null;
                },
              ),
              const SizedBox(height: 10),
              TextFormField(
                controller: _notesController,
                decoration: const InputDecoration(labelText: 'Nota (opcional)'),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancelar'),
        ),
        FilledButton(onPressed: _submit, child: const Text('Abrir')),
      ],
    );
  }

  void _submit() {
    if (!_formKey.currentState!.validate()) return;

    Navigator.of(context).pop(
      OpenCashInput(
        openingAmount: double.parse(_openingController.text),
        notes: _notesController.text,
        cashRegisterId: _selectedCajaId,
      ),
    );
  }
}

class _CloseSessionDialog extends StatefulWidget {
  const _CloseSessionDialog();

  @override
  State<_CloseSessionDialog> createState() => _CloseSessionDialogState();
}

class _CloseSessionDialogState extends State<_CloseSessionDialog> {
  final _notesController = TextEditingController();

  // Denominaciones del peso dominicano (de mayor a menor).
  static const List<int> _denoms = [2000, 1000, 500, 200, 100, 50, 25, 10, 5, 1];
  late final Map<int, TextEditingController> _qty = {
    for (final d in _denoms) d: TextEditingController(),
  };

  @override
  void dispose() {
    _notesController.dispose();
    for (final c in _qty.values) {
      c.dispose();
    }
    super.dispose();
  }

  int _qtyOf(int d) => int.tryParse(_qty[d]!.text.trim()) ?? 0;
  double get _total =>
      _denoms.fold<double>(0, (sum, d) => sum + d * _qtyOf(d));

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Cerrar caja'),
      content: SizedBox(
        width: ResponsiveLayout.isMobile(context) ? double.maxFinite : 440,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              'Cuenta el efectivo por denominación:',
              style:
                  TextStyle(fontSize: 13, color: AppTokens.mutedForeground),
            ),
            const SizedBox(height: 8),
            const Row(
              children: [
                Expanded(
                    flex: 3,
                    child: Text('Denominación',
                        style: TextStyle(
                            fontSize: 12, fontWeight: FontWeight.w700))),
                Expanded(
                    flex: 2,
                    child: Text('Cantidad',
                        style: TextStyle(
                            fontSize: 12, fontWeight: FontWeight.w700))),
                Expanded(
                    flex: 3,
                    child: Text('Subtotal',
                        textAlign: TextAlign.right,
                        style: TextStyle(
                            fontSize: 12, fontWeight: FontWeight.w700))),
              ],
            ),
            const Divider(height: 14),
            Flexible(
              child: SingleChildScrollView(
                child: Column(
                  children: [
                    for (final d in _denoms)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 6),
                        child: Row(
                          children: [
                            Expanded(
                              flex: 3,
                              child: Text(money(d.toDouble()),
                                  style: const TextStyle(
                                      fontWeight: FontWeight.w600)),
                            ),
                            Expanded(
                              flex: 2,
                              child: SizedBox(
                                height: 38,
                                child: TextField(
                                  controller: _qty[d],
                                  keyboardType: TextInputType.number,
                                  textAlign: TextAlign.center,
                                  onChanged: (_) => setState(() {}),
                                  decoration: const InputDecoration(
                                    isDense: true,
                                    hintText: '0',
                                    contentPadding: EdgeInsets.symmetric(
                                        horizontal: 8, vertical: 8),
                                    border: OutlineInputBorder(),
                                  ),
                                ),
                              ),
                            ),
                            Expanded(
                              flex: 3,
                              child: Text(
                                money(d * _qtyOf(d).toDouble()),
                                textAlign: TextAlign.right,
                                style: const TextStyle(
                                    color: AppTokens.mutedForeground),
                              ),
                            ),
                          ],
                        ),
                      ),
                  ],
                ),
              ),
            ),
            const Divider(height: 14),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text('Total contado',
                    style: TextStyle(
                        fontSize: 16, fontWeight: FontWeight.w800)),
                Text(money(_total),
                    style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w900,
                        color: Color(0xFF2563EB))),
              ],
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _notesController,
              decoration: const InputDecoration(labelText: 'Nota (opcional)'),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancelar'),
        ),
        FilledButton(onPressed: _submit, child: const Text('Cerrar')),
      ],
    );
  }

  void _submit() {
    Navigator.of(context).pop(
      CloseCashInput(
        closingAmount: _total,
        notes: _notesController.text,
      ),
    );
  }
}

/// Panel para admin/supervisor: muestra TODAS las cajas abiertas de la
/// sucursal con nombre del cajero, hora de apertura, monto vendido y
/// efectivo esperado. Útil para que el dueño vea cuánto lleva cada uno.
class _AllCashiersPanel extends ConsumerWidget {
  const _AllCashiersPanel();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final overviewsAsync = ref.watch(allOpenCashSessionsProvider);
    // scrollable: false porque manejamos nuestro propio SingleChildScrollView
    // horizontal alrededor del DataTable (el shell aplicaba un scroll horizontal
    // que dejaba al Column padre con ancho infinito → BoxConstraints(w=∞)).
    return DataTableShell(
      title: 'Todas las cajas abiertas',
      scrollable: false,
      child: overviewsAsync.when(
        loading: () => const Padding(
          padding: EdgeInsets.all(AppTokens.s16),
          child: Center(child: CircularProgressIndicator()),
        ),
        error: (e, _) => Padding(
          padding: const EdgeInsets.all(AppTokens.s16),
          child: Text('No se pudieron cargar las cajas: ${friendlyErrorMessage(e)}'),
        ),
        data: (overviews) {
          if (overviews.isEmpty) {
            return const Padding(
              padding: EdgeInsets.all(AppTokens.s20),
              child: Text(
                'No hay cajas abiertas en este momento.',
                style: TextStyle(color: AppTokens.mutedForeground),
              ),
            );
          }
          final totalSold = overviews.fold<double>(
            0,
            (sum, o) => sum + o.metrics.totalPayments,
          );
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              LayoutBuilder(
                builder: (context, constraints) => SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: ConstrainedBox(
                    constraints: BoxConstraints(
                      minWidth: constraints.maxWidth.isFinite
                          ? constraints.maxWidth
                          : 0,
                    ),
                    child: DataTable(
                  columns: const [
                    DataColumn(label: Text('Cajero')),
                    DataColumn(label: Text('Apertura')),
                    DataColumn(
                      label: Text('Monto apertura'),
                      numeric: true,
                    ),
                    DataColumn(label: Text('Vendido'), numeric: true),
                    DataColumn(label: Text('Gastos'), numeric: true),
                    DataColumn(
                      label: Text('Efectivo esperado'),
                      numeric: true,
                    ),
                  ],
                  rows: [
                    for (final o in overviews)
                      DataRow(cells: [
                        DataCell(Text(
                          o.cashierName,
                          style: const TextStyle(
                            fontWeight: FontWeight.w600,
                          ),
                        )),
                        DataCell(Text(formatDateTime(o.session.openedAt))),
                        DataCell(Text(money(o.session.openingAmount))),
                        DataCell(Text(
                          money(o.metrics.totalPayments),
                          style: const TextStyle(
                            fontWeight: FontWeight.w700,
                            color: Color(0xFF16A34A),
                          ),
                        )),
                        DataCell(Text(money(o.metrics.totalExpenses))),
                        DataCell(Text(
                          money(o.expectedCash),
                          style: const TextStyle(fontWeight: FontWeight.w700),
                        )),
                      ]),
                  ],
                    ),
                  ),
                ),
              ),
              // Footer de ancho completo: etiqueta a la izquierda y total a la
              // derecha, con borde superior, para que cubra toda la fila.
              Container(
                width: double.infinity,
                margin: const EdgeInsets.only(top: AppTokens.s8),
                padding: const EdgeInsets.symmetric(
                  horizontal: AppTokens.s16,
                  vertical: AppTokens.s12,
                ),
                decoration: const BoxDecoration(
                  color: Color(0xFFF8FAFC),
                  border: Border(top: BorderSide(color: AppTokens.border)),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      'Total vendido por todas las cajas',
                      style: TextStyle(
                        color: AppTokens.mutedForeground,
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    Text(
                      money(totalSold),
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w900,
                        color: Color(0xFF2563EB),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}
