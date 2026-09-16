import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/tokens.dart';
import '../../../shared/formatters/formatters.dart';
import '../../../shared/widgets/empty_state.dart';
import '../../../shared/widgets/module_page.dart';
import '../../../shared/widgets/print_receipt_dialog.dart';
import '../../../shared/widgets/ui_custom.dart';
import '../data/sales_history_repository.dart';
import 'sales_history_providers.dart';
import 'sales_providers.dart';

class SalesHistoryPage extends ConsumerStatefulWidget {
  const SalesHistoryPage({super.key});

  @override
  ConsumerState<SalesHistoryPage> createState() => _SalesHistoryPageState();
}

class _SalesHistoryPageState extends ConsumerState<SalesHistoryPage> {
  final _searchController = TextEditingController();

  @override
  void initState() {
    super.initState();
    final initial = ref.read(salesHistoryFilterProvider).search;
    _searchController.text = initial;
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  void _setFilter(SalesHistoryFilter Function(SalesHistoryFilter) update) {
    final current = ref.read(salesHistoryFilterProvider);
    ref.read(salesHistoryFilterProvider.notifier).state = update(current);
    ref.read(salesHistoryPageIndexProvider.notifier).state = 0;
  }

  @override
  Widget build(BuildContext context) {
    final filter = ref.watch(salesHistoryFilterProvider);
    final pageIndex = ref.watch(salesHistoryPageIndexProvider);
    final pageAsync = ref.watch(salesHistoryPageProvider);

    return ModulePage(
      title: 'Historial de ventas',
      description:
          'Buscar, ver detalle, reimprimir o editar ventas anteriores.',
      actions: [
        OutlinedButton.icon(
          onPressed: () {
            ref.invalidate(salesHistoryPageProvider);
          },
          icon: const Icon(Icons.refresh, size: 18),
          label: const Text('Actualizar'),
        ),
      ],
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _FiltersBar(
            filter: filter,
            searchController: _searchController,
            onChanged: _setFilter,
          ),
          const SizedBox(height: AppTokens.s16),
          pageAsync.when(
            loading: () => const Padding(
              padding: EdgeInsets.symmetric(vertical: AppTokens.s32),
              child: Center(child: CircularProgressIndicator()),
            ),
            error: (e, _) => ErrorCard(
              message: 'No se pudo cargar el historial: $e',
              onRetry: () => ref.invalidate(salesHistoryPageProvider),
            ),
            data: (page) => Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                DataTableShell(
                  scrollable: false,
                  title: 'Ventas',
                  child: page.rows.isEmpty
                      ? const Padding(
                          padding: EdgeInsets.all(AppTokens.s20),
                          child: Text(
                            'No hay ventas con esos filtros.',
                            style: TextStyle(
                              color: AppTokens.mutedForeground,
                            ),
                          ),
                        )
                      : FlexTable(
                          // Cada venta en UNA fila. Lo de contenido
                          // predecible va a ancho fijo; el espacio que sobra
                          // es para lo que varía (cliente, caja, cobro).
                          singleLine: true,
                          minWidth: 1080,
                          columns: const [
                            FlexTableColumn(label: 'Fecha', width: 96),
                            FlexTableColumn(label: 'Número', width: 96),
                            FlexTableColumn(label: 'Cliente', flex: 3),
                            FlexTableColumn(label: 'NCF', width: 120),
                            FlexTableColumn(label: 'Estado', width: 100),
                            FlexTableColumn(label: 'Caja', flex: 2),
                            FlexTableColumn(label: 'Cobro', flex: 2),
                            FlexTableColumn(
                                label: 'Total', numeric: true, width: 116),
                            FlexTableColumn(
                                label: 'Ganancia', numeric: true, width: 116),
                            FlexTableColumn(label: 'Acciones', width: 124),
                          ],
                          rows: page.rows
                              .map((row) => [
                                    Text(formatDate(row.saleDate)),
                                    Text(
                                      row.saleNumber,
                                      style: const TextStyle(
                                        fontFamily: 'monospace',
                                        fontSize: 12,
                                      ),
                                    ),
                                    _TruncatedText(
                                      row.clientName ?? 'Cliente General',
                                      style: const TextStyle(
                                        fontWeight: FontWeight.w500,
                                      ),
                                    ),
                                    Text(
                                      row.ncf ?? '—',
                                      style: const TextStyle(
                                        fontFamily: 'monospace',
                                        fontSize: 12,
                                      ),
                                    ),
                                    _StatusChip(status: row.status),
                                    _TruncatedText(
                                        row.cashRegisterName ?? '—'),
                                    _paymentMethodsCell(
                                        row.paymentMethod, row.status),
                                    _MoneyCell(row.totalAmount),
                                    _MoneyCell(
                                      row.profit,
                                      weight: FontWeight.w600,
                                      color: _ink(row.profit < 0
                                          ? AppTokens.destructive
                                          : AppTokens.success),
                                    ),
                                    _RowActions(row: row),
                                  ])
                              .toList(growable: false),
                        ),
                ),
                const SizedBox(height: AppTokens.s12),
                _PaginationBar(
                  pageIndex: pageIndex,
                  hasMore: page.hasMore,
                  rowsInPage: page.rows.length,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Etiqueta de un único método de pago en español.
String _singleMethodLabel(String method) {
  switch (method) {
    case 'cash':
      return 'Efectivo';
    case 'card':
      return 'Tarjeta';
    case 'transfer':
      return 'Transferencia';
    case 'mobile':
      return 'Pago móvil';
    case 'other':
      return 'Otro';
    case 'credit':
      return 'Crédito';
    case 'mixed':
      return 'Mixto';
    default:
      return method;
  }
}

/// Celda de cobro en UNA línea: varios métodos van juntos ("Efectivo +
/// Transferencia") y el tooltip muestra el texto completo si no cabe. Si no hay
/// pagos pero la venta es a crédito, "Crédito".
Widget _paymentMethodsCell(String? method, String status) {
  final raw = method?.trim() ?? '';
  final labels = raw.isEmpty
      ? [status == 'credit' ? 'Crédito' : '—']
      : raw
          .split(',')
          .where((m) => m.trim().isNotEmpty)
          .map((m) => _singleMethodLabel(m.trim()))
          .toList(growable: false);
  return _TruncatedText(labels.join(' + '));
}

/// Texto de una línea que muestra el contenido completo al pasar el mouse.
/// Para las columnas que pueden cortarse con "…" (cliente, caja, cobro).
class _TruncatedText extends StatelessWidget {
  const _TruncatedText(this.text, {this.style});

  final String text;
  final TextStyle? style;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: text,
      waitDuration: const Duration(milliseconds: 500),
      child: Text(text, style: style),
    );
  }
}

/// Monto alineado a la derecha con dígitos de ancho fijo, para que las cifras
/// de una columna queden una debajo de la otra. Un monto que no cabe se
/// ACHICA en vez de cortarse: con "…" un RD$ 1,250,000.00 se leería mal.
class _MoneyCell extends StatelessWidget {
  const _MoneyCell(this.amount, {this.weight = FontWeight.w700, this.color});

  final double amount;
  final FontWeight weight;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    return FittedBox(
      fit: BoxFit.scaleDown,
      alignment: Alignment.centerRight,
      child: Text(
        money(amount),
        style: TextStyle(
          fontWeight: weight,
          color: color,
          fontFeatures: const [FontFeature.tabularFigures()],
        ),
      ),
    );
  }
}

/// Versión legible de un color de estado para usarlo como TEXTO. Los tokens
/// de éxito y advertencia son claros para fondo; como letra sobre blanco no
/// se leen bien. Se oscurecen hacia el color de texto, sin inventar un hex.
Color _ink(Color color) => Color.lerp(color, AppTokens.foreground, 0.35)!;

// ─────────────────────────────────────────────────────────────────────────
// Filtros: fechas + búsqueda + status
// ─────────────────────────────────────────────────────────────────────────

class _FiltersBar extends StatelessWidget {
  const _FiltersBar({
    required this.filter,
    required this.searchController,
    required this.onChanged,
  });

  final SalesHistoryFilter filter;
  final TextEditingController searchController;
  final void Function(SalesHistoryFilter Function(SalesHistoryFilter))
      onChanged;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: AppTokens.s12,
      runSpacing: AppTokens.s8,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        SizedBox(
          width: 280,
          child: TextField(
            controller: searchController,
            onSubmitted: (v) => onChanged((f) => f.copyWith(search: v)),
            decoration: InputDecoration(
              prefixIcon: const Icon(Icons.search, size: 18),
              hintText: 'Número de venta o NCF',
              isDense: true,
              border: const OutlineInputBorder(),
              suffixIcon: filter.search.isEmpty
                  ? null
                  : IconButton(
                      icon: const Icon(Icons.close, size: 16),
                      onPressed: () {
                        searchController.clear();
                        onChanged((f) => f.copyWith(search: ''));
                      },
                    ),
            ),
          ),
        ),
        _DateChip(
          label: 'Desde',
          value: filter.from,
          onChanged: (d) => onChanged((f) =>
              d == null ? f.copyWith(clearFrom: true) : f.copyWith(from: d)),
        ),
        _DateChip(
          label: 'Hasta',
          value: filter.to,
          onChanged: (d) => onChanged((f) =>
              d == null ? f.copyWith(clearTo: true) : f.copyWith(to: d)),
        ),
        _StatusFilter(
          active: filter.statuses,
          onChanged: (s) => onChanged((f) => f.copyWith(statuses: s)),
        ),
      ],
    );
  }
}

class _DateChip extends StatelessWidget {
  const _DateChip({
    required this.label,
    required this.value,
    required this.onChanged,
  });

  final String label;
  final DateTime? value;
  final ValueChanged<DateTime?> onChanged;

  @override
  Widget build(BuildContext context) {
    return OutlinedButton.icon(
      onPressed: () async {
        final now = DateTime.now();
        final picked = await showDatePicker(
          context: context,
          initialDate: value ?? now,
          firstDate: DateTime(now.year - 5),
          lastDate: DateTime(now.year + 1),
        );
        if (picked != null) onChanged(picked);
      },
      icon: const Icon(Icons.calendar_today, size: 16),
      label: Text(
        value == null ? label : '$label: ${formatDate(value!)}',
      ),
    );
  }
}

class _StatusFilter extends StatelessWidget {
  const _StatusFilter({required this.active, required this.onChanged});

  final List<String> active;
  final ValueChanged<List<String>> onChanged;

  static const _options = {
    'completed': 'Pagadas',
    'credit': 'A crédito',
    'pending': 'Pendientes',
  };

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 6,
      children: _options.entries.map((entry) {
        final selected = active.contains(entry.key);
        return FilterChip(
          label: Text(entry.value),
          selected: selected,
          onSelected: (s) {
            final next = List<String>.from(active);
            if (s) {
              next.add(entry.key);
            } else {
              next.remove(entry.key);
            }
            onChanged(next);
          },
        );
      }).toList(growable: false),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────
// Paginación
// ─────────────────────────────────────────────────────────────────────────

class _PaginationBar extends ConsumerWidget {
  const _PaginationBar({
    required this.pageIndex,
    required this.hasMore,
    required this.rowsInPage,
  });

  final int pageIndex;
  final bool hasMore;
  final int rowsInPage;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final first = pageIndex * SalesHistoryRepository.pageSize + 1;
    final last = first + rowsInPage - 1;
    return Row(
      mainAxisAlignment: MainAxisAlignment.end,
      children: [
        Text(
          rowsInPage == 0 ? 'Sin resultados' : 'Mostrando $first – $last',
          style: const TextStyle(
            fontSize: 12,
            color: AppTokens.mutedForeground,
          ),
        ),
        const SizedBox(width: AppTokens.s12),
        IconButton(
          tooltip: 'Página anterior',
          onPressed: pageIndex == 0
              ? null
              : () => ref
                  .read(salesHistoryPageIndexProvider.notifier)
                  .state = pageIndex - 1,
          icon: const Icon(Icons.chevron_left, size: 20),
        ),
        IconButton(
          tooltip: 'Página siguiente',
          onPressed: hasMore
              ? () => ref
                  .read(salesHistoryPageIndexProvider.notifier)
                  .state = pageIndex + 1
              : null,
          icon: const Icon(Icons.chevron_right, size: 20),
        ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────
// Chip de estado
// ─────────────────────────────────────────────────────────────────────────

class _StatusChip extends StatelessWidget {
  const _StatusChip({required this.status});

  final String status;

  @override
  Widget build(BuildContext context) {
    final (label, color) = switch (status) {
      'completed' => ('Pagada', AppTokens.success),
      'credit' => ('Crédito', AppTokens.warning),
      'pending' => ('Pendiente', AppTokens.mutedForeground),
      'voided' => ('Anulada', AppTokens.destructive),
      _ => (status, AppTokens.mutedForeground),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        label,
        maxLines: 1,
        softWrap: false,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          color: _ink(color),
          fontWeight: FontWeight.w700,
          fontSize: 11,
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────
// Acciones por fila
// ─────────────────────────────────────────────────────────────────────────

class _RowActions extends ConsumerWidget {
  const _RowActions({required this.row});

  final SalesHistoryRow row;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Cuentas GUARDADAS (pendientes): acciones propias — reabrir para cobrar o
    // descartar (devuelve el stock reservado). No aplica reimprimir/editar/
    // anular porque todavía no es una venta real.
    // Siempre tres espacios —dos acciones visibles y un menú— para que la
    // columna mida lo mismo en todas las filas y nunca baje a una segunda
    // línea. Lo destructivo va dentro del menú, lejos de un clic accidental.

    // Cuentas GUARDADAS (pendientes): reabrir para cobrar o descartar (devuelve
    // el stock reservado). No aplica reimprimir/editar/anular porque todavía no
    // es una venta real.
    if (row.status == 'pending') {
      return Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _ActionIcon(
            tooltip: 'Ver detalle',
            icon: Icons.visibility_outlined,
            onPressed: () => _showDetail(context, ref, row.id),
          ),
          _ActionIcon(
            tooltip: 'Reabrir para cobrar',
            icon: Icons.play_circle_outline,
            color: _ink(AppTokens.success),
            onPressed: () => _reopenHeldSale(context, ref, row),
          ),
          _MoreActions(
            items: const [
              _MenuAction('discard', 'Descartar cuenta (devuelve stock)',
                  Icons.delete_outline,
                  destructive: true),
            ],
            onSelected: (_) => _discardHeldSale(context, ref, row),
          ),
        ],
      );
    }

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        _ActionIcon(
          tooltip: 'Ver detalle',
          icon: Icons.visibility_outlined,
          onPressed: () => _showDetail(context, ref, row.id),
        ),
        _ActionIcon(
          tooltip: 'Reimprimir',
          icon: Icons.print_outlined,
          onPressed: () => _reprint(context, ref, row.id),
        ),
        _MoreActions(
          items: const [
            _MenuAction('notes', 'Editar notas / cliente', Icons.edit_outlined),
            _MenuAction('edit', 'Editar venta completa', Icons.edit_note),
            _MenuAction('void', 'Anular venta (devuelve stock)',
                Icons.delete_outline,
                destructive: true),
          ],
          onSelected: (action) {
            switch (action) {
              case 'notes':
                _editMetadata(context, ref, row);
              case 'edit':
                context.go('/ventas/historial/${row.id}/editar');
              case 'void':
                _voidSale(context, ref, row);
            }
          },
        ),
      ],
    );
  }

  /// Reabre una cuenta guardada: carga sus productos al carrito del POS y
  /// navega a Ventas. Al completarla allí, el POS descarta esta pendiente
  /// (devuelve su stock) y registra la venta real.
  Future<void> _reopenHeldSale(
    BuildContext context,
    WidgetRef ref,
    SalesHistoryRow row,
  ) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      final draft =
          await ref.read(salesRepositoryProvider).loadHeldSaleForReopen(row.id);
      if (draft == null || draft.items.isEmpty) {
        messenger.showSnackBar(const SnackBar(
          content: Text('No se pudo cargar la cuenta (sin productos válidos).'),
        ));
        return;
      }
      // Carga el carrito en el draft del POS y marca la cuenta como reabierta
      // (heldSaleId viaja en el draft y sobrevive recargas en web).
      final saleDraft = SaleDraft(
        items: draft.items,
        receiptType: draft.receiptType,
        clientId: draft.clientId,
        notes: draft.notes,
        heldSaleId: row.id,
      );
      ref.read(saleDraftProvider.notifier).state = saleDraft;
      saveSaleDraftToStore(saleDraft);
      if (!context.mounted) return;
      context.go('/ventas');
    } catch (error) {
      messenger.showSnackBar(
        SnackBar(content: Text('No se pudo reabrir la cuenta: $error')),
      );
    }
  }

  /// Descarta una cuenta guardada: devuelve el stock reservado y la elimina.
  Future<void> _discardHeldSale(
    BuildContext context,
    WidgetRef ref,
    SalesHistoryRow row,
  ) async {
    final messenger = ScaffoldMessenger.of(context);
    final saleLabel =
        row.saleNumber.isEmpty ? row.id.substring(0, 8) : row.saleNumber;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Descartar cuenta guardada'),
        content: Text(
          '¿Descartar la cuenta $saleLabel?\n\n'
          'Se devolverá el stock reservado y la cuenta desaparecerá del '
          'historial. Esta acción no se puede deshacer.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: AppTokens.error),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Descartar'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    try {
      await ref.read(salesRepositoryProvider).discardHeldSale(row.id);
      ref.invalidate(salesHistoryPageProvider);
      messenger.showSnackBar(
        const SnackBar(content: Text('Cuenta descartada y stock devuelto.')),
      );
    } catch (error) {
      messenger.showSnackBar(
        SnackBar(content: Text('No se pudo descartar: $error')),
      );
    }
  }

  Future<void> _voidSale(
    BuildContext context,
    WidgetRef ref,
    SalesHistoryRow row,
  ) async {
    final messenger = ScaffoldMessenger.of(context);
    final saleLabel = row.saleNumber.isEmpty
        ? row.id.substring(0, 8)
        : row.saleNumber;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Anular venta'),
        content: Text(
          '¿Anular la venta $saleLabel?\n\n'
          'Esto va a:\n'
          '• Devolver el stock de los productos vendidos\n'
          '• Borrar los pagos asociados\n'
          '• Marcar la venta como anulada (sale_status = voided)\n\n'
          'La acción no se puede deshacer.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: AppTokens.error),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Anular venta'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    try {
      await ref
          .read(salesHistoryRepositoryProvider)
          .voidSaleWithStockReturn(row.id);
      ref.invalidate(salesHistoryPageProvider);
      messenger.showSnackBar(
        const SnackBar(content: Text('Venta anulada y stock devuelto.')),
      );
    } catch (error) {
      messenger.showSnackBar(
        SnackBar(content: Text('No se pudo anular: $error')),
      );
    }
  }

  Future<void> _showDetail(
    BuildContext context,
    WidgetRef ref,
    String saleId,
  ) async {
    await showDialog(
      context: context,
      builder: (_) => _SaleDetailDialog(saleId: saleId),
    );
  }

  Future<void> _reprint(
    BuildContext context,
    WidgetRef ref,
    String saleId,
  ) async {
    try {
      final salesRepo = ref.read(salesRepositoryProvider);
      final job = await salesRepo.prepareCompletedSalePrintJob(
        saleId: saleId,
      );
      if (!context.mounted) return;
      if (job == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('No se pudo preparar la factura.')),
        );
        return;
      }
      // Conduce siempre disponible al reimprimir una venta.
      await PrintReceiptDialog.show(
        context,
        job,
        enableDeliveryNote: true,
      );
    } catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error al preparar impresión: $e')),
      );
    }
  }

  Future<void> _editMetadata(
    BuildContext context,
    WidgetRef ref,
    SalesHistoryRow row,
  ) async {
    final result = await showDialog<_MetadataEditResult>(
      context: context,
      builder: (_) => _MetadataEditDialog(row: row),
    );
    if (result == null || !context.mounted) return;

    try {
      await ref.read(salesHistoryRepositoryProvider).updateSaleMetadata(
            saleId: row.id,
            notes: result.notes,
            clientId: result.clientId,
            clearClient: result.clearClient,
          );
      ref.invalidate(salesHistoryPageProvider);
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Venta ${row.saleNumber} actualizada.')),
      );
    } catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('No se pudo actualizar: $e')),
      );
    }
  }
}

// ─────────────────────────────────────────────────────────────────────────
// Dialogo: detalle de venta
// ─────────────────────────────────────────────────────────────────────────

class _SaleDetailDialog extends ConsumerWidget {
  const _SaleDetailDialog({required this.saleId});

  final String saleId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final detailAsync = ref.watch(salesHistoryDetailProvider(saleId));
    return AlertDialog(
      title: const Text('Detalle de venta'),
      content: SizedBox(
        width: 640,
        child: detailAsync.when(
          loading: () => const SizedBox(
            height: 200,
            child: Center(child: CircularProgressIndicator()),
          ),
          error: (e, _) => Text('Error: $e'),
          data: (detail) {
            if (detail == null) return const Text('Venta no encontrada.');
            return SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _DetailKv('Número', detail.sale.saleNumber),
                  _DetailKv('Fecha', formatDateTime(detail.sale.saleDate)),
                  _DetailKv(
                    'Cliente',
                    detail.sale.clientName ?? 'Cliente General',
                  ),
                  if (detail.sale.ncf != null)
                    _DetailKv('NCF', detail.sale.ncf!),
                  if (detail.sale.notes != null)
                    _DetailKv('Notas', detail.sale.notes!),
                  const Divider(height: 24),
                  FlexTable(
                    columns: const [
                      FlexTableColumn(label: 'Producto', flex: 3),
                      FlexTableColumn(label: 'Cant.', numeric: true),
                      FlexTableColumn(label: 'P. unit.', numeric: true),
                      FlexTableColumn(label: 'Subtotal', numeric: true),
                      FlexTableColumn(label: 'ITBIS', numeric: true),
                      FlexTableColumn(label: 'Total', numeric: true),
                    ],
                    rows: detail.items
                        .map((it) => [
                              Text(it.description),
                              Text(_qty(it.quantity)),
                              Text(money(it.unitPrice)),
                              Text(money(it.lineSubtotal)),
                              Text(money(it.lineTax)),
                              Text(
                                money(it.lineTotal),
                                style: const TextStyle(
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ])
                        .toList(growable: false),
                  ),
                  const SizedBox(height: 16),
                  Align(
                    alignment: Alignment.centerRight,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Text('Subtotal: ${money(detail.subtotal)}'),
                        Text('ITBIS: ${money(detail.taxAmount)}'),
                        const SizedBox(height: 4),
                        Text(
                          'Total: ${money(detail.sale.totalAmount)}',
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                        Text(
                          'Pagado: ${money(detail.sale.paidAmount)}',
                          style: const TextStyle(fontSize: 12),
                        ),
                        if (detail.sale.balanceDue > 0)
                          Text(
                            'Pendiente: ${money(detail.sale.balanceDue)}',
                            style: const TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w700,
                              color: AppTokens.destructive,
                            ),
                          ),
                      ],
                    ),
                  ),
                ],
              ),
            );
          },
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cerrar'),
        ),
      ],
    );
  }

  String _qty(double v) =>
      v == v.roundToDouble() ? v.toInt().toString() : v.toStringAsFixed(2);
}

class _DetailKv extends StatelessWidget {
  const _DetailKv(this.k, this.v);
  final String k;
  final String v;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          SizedBox(
            width: 100,
            child: Text(
              k,
              style: const TextStyle(
                fontWeight: FontWeight.w600,
                fontSize: 12,
                color: AppTokens.mutedForeground,
              ),
            ),
          ),
          Expanded(child: Text(v, style: const TextStyle(fontSize: 13))),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────
// Dialogo: editar metadata (notas, cliente)
// ─────────────────────────────────────────────────────────────────────────

class _MetadataEditResult {
  _MetadataEditResult({
    required this.notes,
    required this.clientId,
    required this.clearClient,
  });
  final String? notes;
  final String? clientId;
  final bool clearClient;
}

class _MetadataEditDialog extends ConsumerStatefulWidget {
  const _MetadataEditDialog({required this.row});

  final SalesHistoryRow row;

  @override
  ConsumerState<_MetadataEditDialog> createState() =>
      _MetadataEditDialogState();
}

class _MetadataEditDialogState
    extends ConsumerState<_MetadataEditDialog> {
  late final TextEditingController _notesCtrl;
  String? _clientId;
  bool _initialized = false;

  @override
  void initState() {
    super.initState();
    _notesCtrl = TextEditingController(text: widget.row.notes ?? '');
    _clientId = widget.row.clientId;
  }

  @override
  void dispose() {
    _notesCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final clientsAsync = ref.watch(salesClientsProvider);
    if (!_initialized) {
      // Una sola inicialización tras tener los clientes (para mantener
      // consistencia de tipos en el dropdown).
      _initialized = true;
    }

    return AlertDialog(
      title: Text('Editar venta ${widget.row.saleNumber}'),
      content: SizedBox(
        width: 480,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Solo edita campos seguros (notas y cliente). Items, precios y '
              'NCF requieren editar la venta completa.',
              style: TextStyle(
                fontSize: 12,
                color: AppTokens.mutedForeground,
              ),
            ),
            const SizedBox(height: AppTokens.s16),
            const Text(
              'Cliente',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 4),
            clientsAsync.when(
              loading: () => const LinearProgressIndicator(),
              error: (e, _) => Text('Error al cargar: $e'),
              data: (clients) => DropdownButtonFormField<String?>(
                initialValue: _clientId,
                isExpanded: true,
                decoration: const InputDecoration(
                  isDense: true,
                  border: OutlineInputBorder(),
                ),
                items: [
                  const DropdownMenuItem(
                    value: null,
                    child: Text('Cliente General'),
                  ),
                  ...clients.map(
                    (c) => DropdownMenuItem(
                      value: c.id,
                      child: Text(c.fullName),
                    ),
                  ),
                ],
                onChanged: (v) => setState(() => _clientId = v),
              ),
            ),
            const SizedBox(height: AppTokens.s16),
            const Text(
              'Notas',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 4),
            TextField(
              controller: _notesCtrl,
              maxLines: 3,
              decoration: const InputDecoration(
                isDense: true,
                border: OutlineInputBorder(),
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancelar'),
        ),
        FilledButton(
          onPressed: () {
            final clear = _clientId == null;
            Navigator.pop(
              context,
              _MetadataEditResult(
                notes: _notesCtrl.text,
                clientId: clear ? null : _clientId,
                clearClient: clear,
              ),
            );
          },
          child: const Text('Guardar'),
        ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────
// Piezas de la columna de acciones
// ─────────────────────────────────────────────────────────────────────────

/// Botón de ícono compacto de 32 px: tres caben en la columna de acciones.
class _ActionIcon extends StatelessWidget {
  const _ActionIcon({
    required this.tooltip,
    required this.icon,
    required this.onPressed,
    this.color,
  });

  final String tooltip;
  final IconData icon;
  final VoidCallback onPressed;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    return IconButton(
      tooltip: tooltip,
      onPressed: onPressed,
      icon: Icon(icon, size: 18, color: color),
      padding: EdgeInsets.zero,
      constraints: const BoxConstraints.tightFor(width: 32, height: 32),
      visualDensity: VisualDensity.compact,
    );
  }
}

class _MenuAction {
  const _MenuAction(this.value, this.label, this.icon,
      {this.destructive = false});

  final String value;
  final String label;
  final IconData icon;
  final bool destructive;
}

/// Menú "⋮" con el mismo estilo que el de Clientes. Lo destructivo va
/// separado por una línea y en rojo.
class _MoreActions extends StatelessWidget {
  const _MoreActions({required this.items, required this.onSelected});

  final List<_MenuAction> items;
  final ValueChanged<String> onSelected;

  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<String>(
      tooltip: 'Más acciones',
      onSelected: onSelected,
      itemBuilder: (_) => [
        for (var i = 0; i < items.length; i++) ...[
          if (items[i].destructive && i > 0) const PopupMenuDivider(),
          PopupMenuItem<String>(
            value: items[i].value,
            child: ListTile(
              dense: true,
              contentPadding: EdgeInsets.zero,
              leading: Icon(
                items[i].icon,
                size: 18,
                color: items[i].destructive ? AppTokens.destructive : null,
              ),
              title: Text(
                items[i].label,
                style: items[i].destructive
                    ? const TextStyle(color: AppTokens.destructive)
                    : null,
              ),
            ),
          ),
        ],
      ],
      child: const SizedBox(
        width: 32,
        height: 32,
        child: Icon(Icons.more_vert, size: 18),
      ),
    );
  }
}
