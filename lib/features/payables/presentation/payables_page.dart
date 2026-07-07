import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/tokens.dart';
import '../../../shared/formatters/formatters.dart';
import '../../../shared/responsive/responsive_layout.dart';
import '../../../shared/widgets/empty_state.dart';
import '../../../shared/widgets/module_page.dart';
import '../../../shared/widgets/ui_custom.dart';
import '../../settings/presentation/app_settings_providers.dart';
import '../data/payables_repository.dart';
import 'payables_providers.dart';

class PayablesPage extends ConsumerStatefulWidget {
  const PayablesPage({super.key});

  @override
  ConsumerState<PayablesPage> createState() => _PayablesPageState();
}

class _PayablesPageState extends ConsumerState<PayablesPage> {
  final _searchController = TextEditingController();

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final payablesAsync = ref.watch(payablesListProvider);
    final paymentsAsync = ref.watch(supplierPaymentsProvider);
    final filterMode = ref.watch(payablesFilterProvider);
    final warnDays =
        ref.watch(appSettingsProvider).valueOrNull?.creditWarnDays ?? 7;

    return ModulePage(
      title: 'Cuentas por pagar',
      description: 'Gestiona deudas a proveedores y pagos realizados.',
      actions: [
        OutlinedButton.icon(
          onPressed: _refreshData,
          icon: const Icon(Icons.refresh, size: 18),
          label: const Text('Actualizar'),
        ),
      ],
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          TextField(
            controller: _searchController,
            onChanged: (value) =>
                ref.read(payablesSearchProvider.notifier).state = value,
            decoration: const InputDecoration(
              prefixIcon: Icon(Icons.search, size: 18),
              hintText: 'Buscar por proveedor, compra o factura',
            ),
          ),
          const SizedBox(height: AppTokens.s16),
          payablesAsync.when(
            data: (_) {
              final summary = ref.watch(payablesCategorySummaryProvider);
              final filtered = ref.watch(payablesFilteredProvider);
              final totalDue = ref.watch(payablesFilteredTotalDueProvider);

              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _KpisGrid(bills: filtered.length, totalDue: totalDue),
                  const SizedBox(height: AppTokens.s16),
                  _PayablesFilterBar(
                    active: filterMode,
                    countAll: summary.countAll,
                    countNearDue: summary.countNearDue,
                    countOverdue: summary.countOverdue,
                    onChanged: (mode) =>
                        ref.read(payablesFilterProvider.notifier).state = mode,
                  ),
                  const SizedBox(height: AppTokens.s16),
                  Container(
                    decoration: BoxDecoration(
                      color: AppTokens.card,
                      borderRadius: BorderRadius.circular(AppTokens.radius),
                      border: Border.all(color: AppTokens.border),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Padding(
                          padding: EdgeInsets.all(AppTokens.s20),
                          child: Text(
                            'Cuentas por pagar',
                            style: TextStyle(
                                fontSize: 18, fontWeight: FontWeight.bold),
                          ),
                        ),
                        if (filtered.isEmpty)
                          const Padding(
                            padding: EdgeInsets.all(AppTokens.s20),
                            child: Text(
                              'No hay cuentas por pagar.',
                              style: TextStyle(
                                  color: AppTokens.mutedForeground),
                            ),
                          )
                        else ...[
                          const _PayableRowHeader(),
                          SizedBox(
                            height: (MediaQuery.of(context).size.height * 0.55)
                                .clamp(360.0, double.infinity),
                            child: ListView.builder(
                              itemCount: filtered.length,
                              itemExtent: 56,
                              itemBuilder: (context, index) {
                                final item = filtered[index];
                                return _PayableRow(
                                  key: ValueKey(item.id),
                                  purchase: item,
                                  warnDays: warnDays,
                                  onView: () => _onViewDetail(item),
                                  onPay: () => _onRegisterPayment(item),
                                );
                              },
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ],
              );
            },
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (error, _) => ErrorCard(
              message: 'No se pudieron cargar cuentas por pagar: $error',
              onRetry: _refreshData,
            ),
          ),
          const SizedBox(height: AppTokens.s24),
          paymentsAsync.when(
            data: (payments) {
              return DataTableShell(
                scrollable: false,
                title: 'Pagos a proveedores recientes',
                child: payments.isEmpty
                    ? const Padding(
                        padding: EdgeInsets.all(AppTokens.s20),
                        child: Text(
                          'No hay pagos registrados.',
                          style: TextStyle(color: AppTokens.mutedForeground),
                        ),
                      )
                    : FlexTable(
                        columns: const [
                          FlexTableColumn(label: 'Fecha'),
                          FlexTableColumn(label: 'Compra', flex: 2),
                          FlexTableColumn(label: 'Proveedor', flex: 2),
                          FlexTableColumn(label: 'Método'),
                          FlexTableColumn(label: 'Monto', numeric: true),
                          FlexTableColumn(label: 'Referencia', flex: 2),
                        ],
                        rows: payments
                            .map((payment) => [
                                  Text(formatDate(payment.paidAt)),
                                  Text(payment.purchaseNumber),
                                  Text(payment.supplierName),
                                  Text(_pretty(payment.paymentMethod)),
                                  Text(
                                    money(payment.amount),
                                    style: const TextStyle(
                                        fontWeight: FontWeight.w700),
                                  ),
                                  Text(payment.reference ?? '-'),
                                ])
                            .toList(growable: false),
                      ),
              );
            },
            loading: () => const SizedBox.shrink(),
            error: (error, _) => ErrorCard(
              message: 'No se pudieron cargar pagos: $error',
              onRetry: _refreshData,
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _refreshData() async {
    ref.invalidate(payablesListProvider);
    ref.invalidate(supplierPaymentsProvider);
    await Future.wait([
      ref.read(payablesListProvider.future),
      ref.read(supplierPaymentsProvider.future),
    ]);
  }

  Future<void> _onRegisterPayment(PayablePurchase purchase) async {
    final input = await showDialog<PayablePaymentInput>(
      context: context,
      builder: (_) => _RegisterPaymentDialog(purchase: purchase),
    );

    if (input == null || !mounted) return;

    final repository = ref.read(payablesRepositoryProvider);
    try {
      await repository.registerPayment(input);
      if (!mounted) return;
      ref.invalidate(payablesListProvider);
      ref.invalidate(supplierPaymentsProvider);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Pago aplicado a ${purchase.purchaseNumber}')),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('No se pudo registrar pago: $error')),
      );
    }
  }

  Future<void> _onViewDetail(PayablePurchase purchase) async {
    await showDialog(
      context: context,
      builder: (_) => _PayableViewerDialog(purchase: purchase),
    );
  }
}

class _PayablesFilterBar extends StatelessWidget {
  const _PayablesFilterBar({
    required this.active,
    required this.countAll,
    required this.countNearDue,
    required this.countOverdue,
    required this.onChanged,
  });

  final PayablesFilter active;
  final int countAll;
  final int countNearDue;
  final int countOverdue;
  final ValueChanged<PayablesFilter> onChanged;

  @override
  Widget build(BuildContext context) {
    return SegmentedButton<PayablesFilter>(
      style: SegmentedButton.styleFrom(
        visualDensity: VisualDensity.compact,
        textStyle: const TextStyle(fontSize: 13),
      ),
      segments: [
        ButtonSegment(
          value: PayablesFilter.all,
          icon: const Icon(Icons.list_alt_outlined, size: 16),
          label: Text('Todas ($countAll)'),
        ),
        ButtonSegment(
          value: PayablesFilter.nearDue,
          icon: const Icon(Icons.schedule_outlined, size: 16),
          label: Text('Próximas a vencer ($countNearDue)'),
        ),
        ButtonSegment(
          value: PayablesFilter.overdue,
          icon: const Icon(Icons.warning_amber_rounded, size: 16),
          label: Text('Vencidas ($countOverdue)'),
        ),
      ],
      selected: {active},
      onSelectionChanged: (s) => onChanged(s.first),
      showSelectedIcon: false,
    );
  }
}

class _PayableRowHeader extends StatelessWidget {
  const _PayableRowHeader();

  @override
  Widget build(BuildContext context) {
    return Container(
      color: AppTokens.background,
      padding: const EdgeInsets.symmetric(
          horizontal: AppTokens.s16, vertical: AppTokens.s10),
      child: const Row(
        children: [
          Expanded(flex: 2, child: _ColumnLabel('Fecha')),
          Expanded(flex: 2, child: _ColumnLabel('Compra')),
          Expanded(flex: 3, child: _ColumnLabel('Proveedor')),
          Expanded(flex: 2, child: _ColumnLabel('Vence')),
          Expanded(flex: 2, child: _ColumnLabel('Total', align: TextAlign.right)),
          Expanded(
              flex: 2, child: _ColumnLabel('Saldo', align: TextAlign.right)),
          SizedBox(width: 150, child: _ColumnLabel('Acciones')),
        ],
      ),
    );
  }
}

class _ColumnLabel extends StatelessWidget {
  const _ColumnLabel(this.text, {this.align = TextAlign.left});

  final String text;
  final TextAlign align;

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      textAlign: align,
      style: const TextStyle(
        fontSize: 12,
        fontWeight: FontWeight.w700,
        color: AppTokens.mutedForeground,
        letterSpacing: 0.3,
      ),
    );
  }
}

class _PayableRow extends StatelessWidget {
  const _PayableRow({
    super.key,
    required this.purchase,
    required this.warnDays,
    required this.onView,
    required this.onPay,
  });

  final PayablePurchase purchase;
  final int warnDays;
  final VoidCallback onView;
  final VoidCallback onPay;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        border: Border(top: BorderSide(color: AppTokens.border)),
      ),
      padding: const EdgeInsets.symmetric(horizontal: AppTokens.s16),
      child: Row(
        children: [
          Expanded(
            flex: 2,
            child: Text(
              formatDate(purchase.purchaseDate),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 13),
            ),
          ),
          Expanded(
            flex: 2,
            child: Text(
              purchase.purchaseNumber,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 13),
            ),
          ),
          Expanded(
            flex: 3,
            child: Text(
              purchase.supplierName,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
            ),
          ),
          Expanded(
            flex: 2,
            child: _DueDateLabel(purchase: purchase, warnDays: warnDays),
          ),
          Expanded(
            flex: 2,
            child: Text(
              money(purchase.totalAmount),
              textAlign: TextAlign.right,
              style: const TextStyle(fontSize: 13),
            ),
          ),
          Expanded(
            flex: 2,
            child: Text(
              money(purchase.balanceDue),
              textAlign: TextAlign.right,
              style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: AppTokens.destructive,
              ),
            ),
          ),
          SizedBox(
            width: 150,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                IconButton(
                  tooltip: 'Ver detalle',
                  onPressed: onView,
                  icon: const Icon(Icons.visibility_outlined, size: 18),
                  visualDensity: VisualDensity.compact,
                ),
                FilledButton.icon(
                  onPressed: onPay,
                  icon: const Icon(Icons.attach_money, size: 16),
                  label: const Text('Pagar'),
                  style: FilledButton.styleFrom(
                    minimumSize: const Size(0, 30),
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _DueDateLabel extends StatelessWidget {
  const _DueDateLabel({required this.purchase, required this.warnDays});

  final PayablePurchase purchase;
  final int warnDays;

  @override
  Widget build(BuildContext context) {
    final due = purchase.dueDate;
    if (due == null) {
      return const Text(
        'Sin plazo',
        style: TextStyle(color: AppTokens.mutedForeground, fontSize: 12),
      );
    }
    final days = purchase.daysUntilDue!;
    final isOverdue = days < 0;
    final isNear = !isOverdue && days <= warnDays;
    final color = isOverdue
        ? AppTokens.destructive
        : isNear
            ? AppTokens.warning
            : AppTokens.mutedForeground;
    final subtitle = isOverdue
        ? 'Vencido hace ${-days}d'
        : days == 0
            ? 'Vence hoy'
            : 'En ${days}d';

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Text(
          formatDate(due),
          style: TextStyle(
              fontSize: 12, color: color, fontWeight: FontWeight.w600),
        ),
        Text(subtitle, style: TextStyle(fontSize: 11, color: color)),
      ],
    );
  }
}

class _PayableViewerDialog extends StatelessWidget {
  const _PayableViewerDialog({required this.purchase});

  final PayablePurchase purchase;

  @override
  Widget build(BuildContext context) {
    return Dialog(
      insetPadding: const EdgeInsets.all(AppTokens.s24),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 480),
        child: Padding(
          padding: const EdgeInsets.all(AppTokens.s20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  const Icon(Icons.inventory_2_outlined,
                      color: AppTokens.primary),
                  const SizedBox(width: AppTokens.s8),
                  Expanded(
                    child: Text(
                      'Compra ${purchase.purchaseNumber}',
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w700,
                          ),
                    ),
                  ),
                  IconButton(
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.close, size: 20),
                  ),
                ],
              ),
              const Divider(),
              _kv('Proveedor', purchase.supplierName),
              _kv('Fecha', formatDate(purchase.purchaseDate)),
              if (purchase.invoiceNumber != null)
                _kv('Factura', purchase.invoiceNumber!),
              if (purchase.dueDate != null)
                _kv('Vence', formatDate(purchase.dueDate!)),
              _kv('Total', money(purchase.totalAmount), highlight: true),
              _kv('Pagado', money(purchase.paidAmount)),
              _kv('Saldo', money(purchase.balanceDue), danger: true),
              const SizedBox(height: AppTokens.s16),
              OutlinedButton.icon(
                onPressed: () => Navigator.pop(context),
                icon: const Icon(Icons.close, size: 18),
                label: const Text('Cerrar'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _kv(String label, String value,
      {bool highlight = false, bool danger = false}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppTokens.s4),
      child: Row(
        children: [
          Expanded(
            child: Text(label,
                style: const TextStyle(color: AppTokens.mutedForeground)),
          ),
          Text(
            value,
            style: TextStyle(
              fontWeight: highlight ? FontWeight.w800 : FontWeight.w700,
              fontSize: highlight ? 16 : 14,
              color: danger
                  ? AppTokens.destructive
                  : (highlight ? AppTokens.primary : AppTokens.foreground),
            ),
          ),
        ],
      ),
    );
  }
}

class _KpisGrid extends StatelessWidget {
  const _KpisGrid({required this.bills, required this.totalDue});

  final int bills;
  final double totalDue;

  @override
  Widget build(BuildContext context) {
    final cards = [
      KPICard(
        label: 'Facturas por pagar',
        value: bills.toString(),
        icon: Icons.receipt_long_outlined,
        trend: 'Por pagar',
      ),
      KPICard(
        label: 'Total por pagar',
        value: money(totalDue),
        icon: Icons.access_time_rounded,
        trend: 'Saldo pendiente',
      ),
    ];

    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth < AppTokens.breakpointCompact) {
          return Column(
            children: [
              cards[0],
              const SizedBox(height: AppTokens.s12),
              cards[1],
            ],
          );
        }
        return Row(
          children: [
            Expanded(child: cards[0]),
            const SizedBox(width: AppTokens.s12),
            Expanded(child: cards[1]),
          ],
        );
      },
    );
  }
}

class _RegisterPaymentDialog extends StatefulWidget {
  const _RegisterPaymentDialog({required this.purchase});

  final PayablePurchase purchase;

  @override
  State<_RegisterPaymentDialog> createState() => _RegisterPaymentDialogState();
}

class _RegisterPaymentDialogState extends State<_RegisterPaymentDialog> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _amountController;
  final _referenceController = TextEditingController();
  final _notesController = TextEditingController();

  String _paymentMethod = 'cash';

  @override
  void initState() {
    super.initState();
    _amountController = TextEditingController(
      text: widget.purchase.balanceDue.toStringAsFixed(2),
    );
  }

  @override
  void dispose() {
    _amountController.dispose();
    _referenceController.dispose();
    _notesController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Registrar pago a proveedor'),
      content: SizedBox(
        width: ResponsiveLayout.isMobile(context) ? double.maxFinite : 420,
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  'Compra: ${widget.purchase.purchaseNumber}\n'
                  'Proveedor: ${widget.purchase.supplierName}\n'
                  'Saldo: ${money(widget.purchase.balanceDue)}',
                ),
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _amountController,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                decoration: const InputDecoration(labelText: 'Monto a pagar'),
                validator: (value) {
                  final amount = double.tryParse(value ?? '');
                  if (amount == null || amount <= 0) {
                    return 'Monto inválido';
                  }
                  if (amount > widget.purchase.balanceDue) {
                    return 'No puede exceder el saldo';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 10),
              DropdownButtonFormField<String>(
                initialValue: _paymentMethod,
                decoration: const InputDecoration(labelText: 'Método de pago'),
                items: const [
                  DropdownMenuItem(value: 'cash', child: Text('Efectivo')),
                  DropdownMenuItem(
                      value: 'transfer', child: Text('Transferencia')),
                  DropdownMenuItem(value: 'check', child: Text('Cheque')),
                  DropdownMenuItem(value: 'card', child: Text('Tarjeta')),
                ],
                onChanged: (value) {
                  if (value == null) return;
                  setState(() => _paymentMethod = value);
                },
              ),
              const SizedBox(height: 10),
              TextFormField(
                controller: _referenceController,
                decoration: const InputDecoration(labelText: 'Referencia'),
              ),
              const SizedBox(height: 10),
              TextFormField(
                controller: _notesController,
                decoration: const InputDecoration(labelText: 'Nota'),
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
        FilledButton(onPressed: _submit, child: const Text('Aplicar pago')),
      ],
    );
  }

  void _submit() {
    if (!_formKey.currentState!.validate()) return;

    Navigator.of(context).pop(
      PayablePaymentInput(
        purchaseId: widget.purchase.id,
        amount: double.parse(_amountController.text),
        paymentMethod: _paymentMethod,
        reference: _referenceController.text,
        notes: _notesController.text,
      ),
    );
  }
}

String _pretty(String value) {
  if (value.isEmpty) return '-';
  return value
      .split('_')
      .map(
        (part) => part.isEmpty
            ? part
            : '${part[0].toUpperCase()}${part.substring(1)}',
      )
      .join(' ');
}
