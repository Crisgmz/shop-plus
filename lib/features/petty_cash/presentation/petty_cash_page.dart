// Pantalla `/caja-chica` (F8).
//
// Flujo:
//   - Sin sesión abierta → tarjeta "Abrir caja chica" con monto inicial.
//   - Con sesión abierta:
//       · KPIs (Apertura, Ingresos, Gastos, Esperado).
//       · Botón "Registrar movimiento" (income/expense/replenishment).
//       · Lista de movimientos de la sesión activa.
//       · Botón "Cerrar caja chica" con arqueo + diferencia.
//   - Sesiones recientes al pie.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/tokens.dart';
import '../../../shared/errors/friendly_error.dart';
import '../../../shared/formatters/formatters.dart';
import '../../../shared/widgets/empty_state.dart';
import '../../../shared/widgets/module_page.dart';
import '../../../shared/widgets/role_gate.dart';
import '../../../shared/widgets/ui_custom.dart';
import '../data/petty_cash_repository.dart';
import 'petty_cash_providers.dart';

class PettyCashPage extends ConsumerWidget {
  const PettyCashPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final dataAsync = ref.watch(pettyCashDataProvider);
    return ModulePage(
      title: 'Caja chica',
      description:
          'Apertura, gastos rápidos y arqueo. Independiente de la caja del POS.',
      actions: [
        OutlinedButton.icon(
          onPressed: () => ref.invalidate(pettyCashDataProvider),
          icon: const Icon(Icons.refresh, size: 18),
          label: const Text('Actualizar'),
        ),
      ],
      child: dataAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) => ErrorCard(
          message: 'No se pudo cargar caja chica: ${friendlyErrorMessage(error)}',
          onRetry: () => ref.invalidate(pettyCashDataProvider),
        ),
        data: (data) => _Body(data: data),
      ),
    );
  }
}

class _Body extends ConsumerWidget {
  const _Body({required this.data});
  final PettyCashData data;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (data.openSession == null)
          _ClosedHeroCard(onOpen: () => _onOpen(context, ref))
        else
          _OpenSessionCard(
            session: data.openSession!,
            movements: data.movements,
            categories: data.categories,
            onAddMovement: (type) =>
                _onAddMovement(context, ref, data.categories, type),
            onDeleteMovement: (m) => _onDeleteMovement(context, ref, m),
            onClose: () =>
                _onClose(context, ref, data.openSession!),
          ),
        const SizedBox(height: AppTokens.s24),
        _RecentSessionsTable(sessions: data.recentSessions),
      ],
    );
  }

  Future<void> _onOpen(BuildContext context, WidgetRef ref) async {
    final input = await showDialog<PettyCashOpenInput>(
      context: context,
      builder: (_) => const _OpenSessionDialog(),
    );
    if (input == null || !context.mounted) return;
    try {
      await ref.read(pettyCashRepositoryProvider).openSession(input);
      if (!context.mounted) return;
      ref.invalidate(pettyCashDataProvider);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Caja chica abierta.')),
      );
    } catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('No se pudo abrir caja chica: ${friendlyErrorMessage(e)}')),
      );
    }
  }

  Future<void> _onClose(
    BuildContext context,
    WidgetRef ref,
    PettyCashSession session,
  ) async {
    final input = await showDialog<PettyCashCloseInput>(
      context: context,
      builder: (_) => _CloseSessionDialog(expected: session.expectedAmount),
    );
    if (input == null || !context.mounted) return;
    try {
      await ref.read(pettyCashRepositoryProvider).closeSession(input);
      if (!context.mounted) return;
      ref.invalidate(pettyCashDataProvider);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Caja chica cerrada.')),
      );
    } catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('No se pudo cerrar caja chica: ${friendlyErrorMessage(e)}')),
      );
    }
  }

  Future<void> _onAddMovement(
    BuildContext context,
    WidgetRef ref,
    List<PettyCashCategory> categories,
    String type,
  ) async {
    final input = await showDialog<PettyCashMovementInput>(
      context: context,
      builder: (_) => _MovementDialog(
        movementType: type,
        categories: categories,
      ),
    );
    if (input == null || !context.mounted) return;
    try {
      await ref.read(pettyCashRepositoryProvider).addMovement(input);
      if (!context.mounted) return;
      ref.invalidate(pettyCashDataProvider);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            type == 'expense'
                ? 'Gasto registrado'
                : type == 'income'
                    ? 'Ingreso registrado'
                    : 'Movimiento registrado',
          ),
        ),
      );
    } catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(friendlyErrorMessage(e))),
      );
    }
  }

  Future<void> _onDeleteMovement(
    BuildContext context,
    WidgetRef ref,
    PettyCashMovement m,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Eliminar movimiento'),
        content: Text(
          'Eliminar ${m.typeLabel} de ${money(m.amount)}? El '
          'saldo esperado se ajustará automáticamente.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
                backgroundColor: AppTokens.destructive),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Eliminar'),
          ),
        ],
      ),
    );
    if (confirmed != true || !context.mounted) return;
    try {
      await ref.read(pettyCashRepositoryProvider).deleteMovement(m.id);
      if (!context.mounted) return;
      ref.invalidate(pettyCashDataProvider);
    } catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(friendlyErrorMessage(e))),
      );
    }
  }
}

// ─────────────────────────────────────────────────────────────────────────
// Tarjeta cerrada
// ─────────────────────────────────────────────────────────────────────────

class _ClosedHeroCard extends StatelessWidget {
  const _ClosedHeroCard({required this.onOpen});
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(AppTokens.s20),
      decoration: BoxDecoration(
        color: AppTokens.card,
        border: Border.all(color: AppTokens.border),
        borderRadius: BorderRadius.circular(AppTokens.radius),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'No hay caja chica abierta',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 6),
          const Text(
            'Abre una caja chica con un monto inicial para empezar a '
            'registrar gastos rápidos (transporte, papelería, etc.).',
            style: TextStyle(color: AppTokens.mutedForeground),
          ),
          const SizedBox(height: AppTokens.s16),
          FilledButton.icon(
            onPressed: onOpen,
            icon: const Icon(Icons.lock_open_outlined, size: 18),
            label: const Text('Abrir caja chica'),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────
// Sesión abierta
// ─────────────────────────────────────────────────────────────────────────

class _OpenSessionCard extends StatelessWidget {
  const _OpenSessionCard({
    required this.session,
    required this.movements,
    required this.categories,
    required this.onAddMovement,
    required this.onDeleteMovement,
    required this.onClose,
  });

  final PettyCashSession session;
  final List<PettyCashMovement> movements;
  final List<PettyCashCategory> categories;
  final ValueChanged<String> onAddMovement;
  final ValueChanged<PettyCashMovement> onDeleteMovement;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    final incomes = movements
        .where((m) => m.movementType != 'expense')
        .fold<double>(0, (s, m) => s + m.signedAmount);
    final expenses = movements
        .where((m) => m.movementType == 'expense')
        .fold<double>(0, (s, m) => s + m.amount);

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(AppTokens.s20),
      decoration: BoxDecoration(
        color: AppTokens.card,
        border: Border.all(color: AppTokens.border),
        borderRadius: BorderRadius.circular(AppTokens.radius),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Expanded(
                child: Text(
                  'Caja chica abierta',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
                ),
              ),
              OutlinedButton.icon(
                onPressed: () => onAddMovement('income'),
                icon: const Icon(Icons.add_circle_outline,
                    color: AppTokens.success, size: 18),
                label: const Text('Ingreso'),
              ),
              const SizedBox(width: 8),
              OutlinedButton.icon(
                onPressed: () => onAddMovement('expense'),
                icon: const Icon(Icons.remove_circle_outline,
                    color: AppTokens.destructive, size: 18),
                label: const Text('Gasto'),
              ),
              const SizedBox(width: 8),
              OutlinedButton.icon(
                onPressed: () => onAddMovement('replenishment'),
                icon: const Icon(Icons.account_balance_wallet_outlined,
                    size: 18),
                label: const Text('Reposición'),
              ),
              const SizedBox(width: 8),
              FilledButton.icon(
                onPressed: onClose,
                icon: const Icon(Icons.lock_outline, size: 18),
                label: const Text('Cerrar caja chica'),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            'Abierta: ${formatDateTime(session.openedAt)}',
            style: const TextStyle(color: AppTokens.mutedForeground),
          ),
          const SizedBox(height: AppTokens.s16),
          LayoutBuilder(
            builder: (context, constraints) {
              final cards = [
                KPICard(
                  label: 'Apertura',
                  value: money(session.openingAmount),
                  icon: Icons.lock_open_outlined,
                ),
                KPICard(
                  label: 'Ingresos / Reposición',
                  value: money(incomes),
                  icon: Icons.arrow_downward_rounded,
                ),
                KPICard(
                  label: 'Gastos',
                  value: money(expenses),
                  icon: Icons.arrow_upward_rounded,
                ),
                KPICard(
                  label: 'Esperado',
                  value: money(session.expectedAmount),
                  icon: Icons.account_balance_wallet_outlined,
                ),
              ];
              final cols = constraints.maxWidth >= 1024
                  ? 4
                  : constraints.maxWidth >= 720
                      ? 2
                      : 1;
              const gap = AppTokens.s12;
              final w = (constraints.maxWidth - gap * (cols - 1)) / cols;
              return Wrap(
                spacing: gap,
                runSpacing: gap,
                children: cards
                    .map((c) => SizedBox(width: w, child: c))
                    .toList(growable: false),
              );
            },
          ),
          const SizedBox(height: AppTokens.s20),
          const Text(
            'Movimientos de esta sesión',
            style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14),
          ),
          const SizedBox(height: 6),
          if (movements.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: AppTokens.s20),
              child: Text(
                'Aún no hay movimientos. Registra un ingreso o gasto.',
                style: TextStyle(color: AppTokens.mutedForeground),
              ),
            )
          else
            ListView.separated(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: movements.length,
              separatorBuilder: (_, _) =>
                  const Divider(height: 1, color: AppTokens.border),
              itemBuilder: (context, i) => _MovementTile(
                m: movements[i],
                onDelete: () => onDeleteMovement(movements[i]),
              ),
            ),
        ],
      ),
    );
  }
}

class _MovementTile extends ConsumerWidget {
  const _MovementTile({required this.m, required this.onDelete});

  final PettyCashMovement m;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final access = ref.watch(roleAccessProvider);
    final isOut = m.movementType == 'expense';
    final color = isOut ? AppTokens.destructive : AppTokens.success;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppTokens.s8),
      child: Row(
        children: [
          Container(
            width: 32,
            height: 32,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(
              isOut ? Icons.arrow_upward : Icons.arrow_downward,
              color: color,
              size: 18,
            ),
          ),
          const SizedBox(width: AppTokens.s12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${m.typeLabel}${m.categoryName != null ? "  ·  ${m.categoryName}" : ""}',
                  style: const TextStyle(
                      fontWeight: FontWeight.w700, fontSize: 13),
                ),
                Text(
                  '${formatDateTime(m.occurredAt)}'
                  '${m.payee != null && m.payee!.isNotEmpty ? "  ·  ${m.payee}" : ""}',
                  style: const TextStyle(
                    color: AppTokens.mutedForeground,
                    fontSize: 11,
                  ),
                ),
                if (m.description != null && m.description!.isNotEmpty)
                  Text(
                    m.description!,
                    style: const TextStyle(
                      color: AppTokens.mutedForeground,
                      fontSize: 11,
                      fontStyle: FontStyle.italic,
                    ),
                  ),
              ],
            ),
          ),
          Text(
            '${isOut ? "-" : "+"}${money(m.amount)}',
            style: TextStyle(
              color: color,
              fontWeight: FontWeight.w800,
              fontSize: 15,
            ),
          ),
          if (access.canManagePettyCash)
            IconButton(
              tooltip: 'Eliminar',
              onPressed: onDelete,
              icon: const Icon(Icons.delete_outline,
                  size: 18, color: AppTokens.destructive),
              visualDensity: VisualDensity.compact,
            ),
        ],
      ),
    );
  }
}

class _RecentSessionsTable extends StatelessWidget {
  const _RecentSessionsTable({required this.sessions});

  final List<PettyCashSession> sessions;

  @override
  Widget build(BuildContext context) {
    return DataTableShell(
      title: 'Sesiones recientes de caja chica',
      child: sessions.isEmpty
          ? const Padding(
              padding: EdgeInsets.all(AppTokens.s20),
              child: Text(
                'Aún no hay sesiones registradas.',
                style: TextStyle(color: AppTokens.mutedForeground),
              ),
            )
          : DataTable(
              headingRowColor:
                  WidgetStateProperty.all(AppTokens.background),
              columns: const [
                DataColumn(label: Text('Apertura')),
                DataColumn(label: Text('Cierre')),
                DataColumn(label: Text('Estado')),
                DataColumn(label: Text('Apertura'), numeric: true),
                DataColumn(label: Text('Esperado'), numeric: true),
                DataColumn(label: Text('Conteo'), numeric: true),
                DataColumn(label: Text('Diferencia'), numeric: true),
              ],
              rows: sessions
                  .map(
                    (s) => DataRow(cells: [
                      DataCell(Text(formatDateTime(s.openedAt))),
                      DataCell(Text(
                          s.closedAt == null ? '-' : formatDateTime(s.closedAt!))),
                      DataCell(StatusBadge(
                        label: s.isOpen ? 'Abierta' : 'Cerrada',
                        status: s.isOpen ? 'open' : 'closed',
                      )),
                      DataCell(Text(money(s.openingAmount))),
                      DataCell(Text(money(s.expectedAmount))),
                      DataCell(Text(
                          s.closingAmount == null ? '-' : money(s.closingAmount!))),
                      DataCell(Text(
                        s.differenceAmount == null
                            ? '-'
                            : money(s.differenceAmount!),
                        style: TextStyle(
                          fontWeight: FontWeight.w700,
                          color: s.differenceAmount != null &&
                                  s.differenceAmount! < 0
                              ? AppTokens.destructive
                              : null,
                        ),
                      )),
                    ]),
                  )
                  .toList(growable: false),
            ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────
// Diálogos
// ─────────────────────────────────────────────────────────────────────────

class _OpenSessionDialog extends StatefulWidget {
  const _OpenSessionDialog();

  @override
  State<_OpenSessionDialog> createState() => _OpenSessionDialogState();
}

class _OpenSessionDialogState extends State<_OpenSessionDialog> {
  final _formKey = GlobalKey<FormState>();
  final _amount = TextEditingController(text: '0');
  final _notes = TextEditingController();

  @override
  void dispose() {
    _amount.dispose();
    _notes.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Abrir caja chica'),
      content: Form(
        key: _formKey,
        child: SizedBox(
          width: 360,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextFormField(
                controller: _amount,
                autofocus: true,
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
                decoration: const InputDecoration(
                  labelText: 'Monto inicial',
                  prefixText: r'RD$ ',
                  border: OutlineInputBorder(),
                ),
                validator: (v) {
                  final n = double.tryParse((v ?? '').trim());
                  if (n == null || n < 0) return 'Monto inválido';
                  return null;
                },
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _notes,
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
        FilledButton(
          onPressed: () {
            if (!(_formKey.currentState?.validate() ?? false)) return;
            Navigator.pop(
              context,
              PettyCashOpenInput(
                openingAmount: double.parse(_amount.text.trim()),
                notes: _notes.text.trim(),
              ),
            );
          },
          child: const Text('Abrir'),
        ),
      ],
    );
  }
}

class _CloseSessionDialog extends StatefulWidget {
  const _CloseSessionDialog({required this.expected});

  final double expected;

  @override
  State<_CloseSessionDialog> createState() => _CloseSessionDialogState();
}

class _CloseSessionDialogState extends State<_CloseSessionDialog> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _amount;
  final _notes = TextEditingController();

  @override
  void initState() {
    super.initState();
    _amount = TextEditingController(text: widget.expected.toStringAsFixed(2));
  }

  @override
  void dispose() {
    _amount.dispose();
    _notes.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Cerrar caja chica'),
      content: Form(
        key: _formKey,
        child: SizedBox(
          width: 360,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'Esperado: ${money(widget.expected)}',
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _amount,
                autofocus: true,
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
                decoration: const InputDecoration(
                  labelText: 'Conteo físico',
                  prefixText: r'RD$ ',
                  border: OutlineInputBorder(),
                ),
                validator: (v) {
                  final n = double.tryParse((v ?? '').trim());
                  if (n == null || n < 0) return 'Monto inválido';
                  return null;
                },
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _notes,
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
        FilledButton(
          onPressed: () {
            if (!(_formKey.currentState?.validate() ?? false)) return;
            Navigator.pop(
              context,
              PettyCashCloseInput(
                closingAmount: double.parse(_amount.text.trim()),
                notes: _notes.text.trim(),
              ),
            );
          },
          child: const Text('Cerrar caja'),
        ),
      ],
    );
  }
}

class _MovementDialog extends StatefulWidget {
  const _MovementDialog({
    required this.movementType,
    required this.categories,
  });

  final String movementType;
  final List<PettyCashCategory> categories;

  @override
  State<_MovementDialog> createState() => _MovementDialogState();
}

class _MovementDialogState extends State<_MovementDialog> {
  final _formKey = GlobalKey<FormState>();
  final _amount = TextEditingController();
  final _description = TextEditingController();
  final _payee = TextEditingController();
  final _receipt = TextEditingController();
  String? _categoryId;

  @override
  void dispose() {
    _amount.dispose();
    _description.dispose();
    _payee.dispose();
    _receipt.dispose();
    super.dispose();
  }

  String get _title {
    switch (widget.movementType) {
      case 'income':
        return 'Registrar ingreso';
      case 'expense':
        return 'Registrar gasto';
      case 'replenishment':
        return 'Reposición de caja chica';
      default:
        return 'Movimiento';
    }
  }

  Color get _accent {
    switch (widget.movementType) {
      case 'income':
      case 'replenishment':
        return AppTokens.success;
      case 'expense':
        return AppTokens.destructive;
      default:
        return AppTokens.primary;
    }
  }

  @override
  Widget build(BuildContext context) {
    final isExpense = widget.movementType == 'expense';
    return AlertDialog(
      title: Text(_title),
      content: Form(
        key: _formKey,
        child: SizedBox(
          width: 420,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextFormField(
                controller: _amount,
                autofocus: true,
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
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
              if (isExpense) ...[
                const SizedBox(height: 12),
                DropdownButtonFormField<String?>(
                  initialValue: _categoryId,
                  decoration: const InputDecoration(
                    labelText: 'Categoría',
                    border: OutlineInputBorder(),
                  ),
                  items: [
                    const DropdownMenuItem(
                        value: null, child: Text('Sin categoría')),
                    ...widget.categories.map((c) => DropdownMenuItem(
                          value: c.id,
                          child: Text(c.name),
                        )),
                  ],
                  onChanged: (v) => setState(() => _categoryId = v),
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _payee,
                  decoration: const InputDecoration(
                    labelText: 'Pagado a (opcional)',
                    border: OutlineInputBorder(),
                  ),
                ),
              ],
              const SizedBox(height: 12),
              TextFormField(
                controller: _description,
                decoration: const InputDecoration(
                  labelText: 'Descripción',
                  border: OutlineInputBorder(),
                ),
                validator: (v) => (v == null || v.trim().isEmpty)
                    ? 'Requerido'
                    : null,
              ),
              if (isExpense) ...[
                const SizedBox(height: 12),
                TextFormField(
                  controller: _receipt,
                  decoration: const InputDecoration(
                    labelText: 'No. de recibo (opcional)',
                    border: OutlineInputBorder(),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancelar'),
        ),
        FilledButton(
          style: FilledButton.styleFrom(backgroundColor: _accent),
          onPressed: () {
            if (!(_formKey.currentState?.validate() ?? false)) return;
            Navigator.pop(
              context,
              PettyCashMovementInput(
                movementType: widget.movementType,
                amount: double.parse(_amount.text.trim()),
                categoryId: _categoryId,
                description: _description.text.trim(),
                payee: _payee.text.trim(),
                receiptReference: _receipt.text.trim(),
              ),
            );
          },
          child: const Text('Registrar'),
        ),
      ],
    );
  }
}
