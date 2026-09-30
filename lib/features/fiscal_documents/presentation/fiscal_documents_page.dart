import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/tokens.dart';
import '../../../shared/errors/friendly_error.dart';
import '../../../shared/formatters/formatters.dart';
import '../../../shared/widgets/empty_state.dart';
import '../../../shared/widgets/module_page.dart';
import '../../../shared/widgets/role_gate.dart';
import '../../../shared/widgets/ui_custom.dart';
import '../data/fiscal_documents_repository.dart';
import 'fiscal_documents_providers.dart';

const _receiptLabels = <String, String>{
  'consumer_final': 'Consumidor Final',
  'fiscal_credit': 'Crédito Fiscal',
  'governmental': 'Gubernamental',
  'special': 'Especial',
  'export': 'Exportación',
};

const _statusLabels = <String, String>{
  'pending': 'Pendiente',
  'sent': 'Enviado',
  'approved': 'Aprobado',
  'rejected': 'Rechazado',
};

const _statusColors = <String, Color>{
  'pending': Color(0xFFF59E0B),
  'sent': Color(0xFF3B82F6),
  'approved': Color(0xFF22C55E),
  'rejected': Color(0xFFEF4444),
};

const _receiptTypes = <String>[
  'consumer_final',
  'fiscal_credit',
  'governmental',
  'special',
  'export',
];

const _statusOptions = <String>[
  'pending',
  'sent',
  'approved',
  'rejected',
];

class FiscalDocumentsPage extends ConsumerWidget {
  const FiscalDocumentsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final docsAsync = ref.watch(fiscalDocumentsProvider);
    final statusFilter = ref.watch(fiscalStatusFilterProvider);
    final receiptTypeFilter = ref.watch(fiscalReceiptTypeFilterProvider);
    final dateFrom = ref.watch(fiscalDateFromProvider);
    final dateTo = ref.watch(fiscalDateToProvider);

    return ModulePage(
      title: 'Comprobantes Fiscales',
      description: 'Documentos fiscales emitidos (NCF) por sucursal.',
      actions: [
        _DateRangeButton(
          dateFrom: dateFrom,
          dateTo: dateTo,
          onClear: () {
            ref.read(fiscalDateFromProvider.notifier).state = null;
            ref.read(fiscalDateToProvider.notifier).state = null;
          },
          onPick: (from, to) {
            ref.read(fiscalDateFromProvider.notifier).state = from;
            ref.read(fiscalDateToProvider.notifier).state = to;
          },
        ),
        const SizedBox(width: AppTokens.s8),
        _ReceiptTypeChip(selected: receiptTypeFilter),
        const SizedBox(width: AppTokens.s8),
        _StatusChip(selected: statusFilter),
        const SizedBox(width: AppTokens.s8),
        OutlinedButton.icon(
          onPressed: () => ref.invalidate(fiscalDocumentsProvider),
          icon: const Icon(Icons.refresh, size: 18),
          label: const Text('Actualizar'),
        ),
      ],
      child: docsAsync.when(
        data: (docs) => _DocsList(docs: docs),
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) => Card(
          child: Padding(
            padding: const EdgeInsets.all(AppTokens.s24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text('No se pudieron cargar los comprobantes: ${friendlyErrorMessage(error)}'),
                const SizedBox(height: AppTokens.s12),
                FilledButton.icon(
                  onPressed: () => ref.invalidate(fiscalDocumentsProvider),
                  icon: const Icon(Icons.refresh),
                  label: const Text('Reintentar'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _DateRangeButton extends StatelessWidget {
  const _DateRangeButton({
    required this.dateFrom,
    required this.dateTo,
    required this.onClear,
    required this.onPick,
  });

  final DateTime? dateFrom;
  final DateTime? dateTo;
  final VoidCallback onClear;
  final void Function(DateTime from, DateTime to) onPick;

  bool get _hasFilter => dateFrom != null || dateTo != null;

  @override
  Widget build(BuildContext context) {
    final label = _hasFilter
        ? '${dateFrom != null ? formatDate(dateFrom!) : '…'} – ${dateTo != null ? formatDate(dateTo!) : '…'}'
        : 'Rango fechas';

    return OutlinedButton.icon(
      onPressed: () async {
        if (_hasFilter) {
          onClear();
          return;
        }
        final range = await showDateRangePicker(
          context: context,
          firstDate: DateTime(2020),
          lastDate: DateTime(2100),
          initialDateRange: dateFrom != null && dateTo != null
              ? DateTimeRange(start: dateFrom!, end: dateTo!)
              : null,
        );
        if (range == null) return;
        onPick(range.start, range.end);
      },
      icon: Icon(
        _hasFilter ? Icons.close : Icons.date_range_outlined,
        size: 18,
      ),
      label: Text(label),
    );
  }
}

class _ReceiptTypeChip extends ConsumerWidget {
  const _ReceiptTypeChip({required this.selected});

  final String? selected;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return DropdownButtonHideUnderline(
      child: DropdownButton<String?>(
        value: selected,
        hint: const Text('Tipo comprobante'),
        isDense: true,
        borderRadius: BorderRadius.circular(AppTokens.radiusS),
        items: [
          const DropdownMenuItem(value: null, child: Text('Todos los tipos')),
          ..._receiptTypes.map(
            (type) => DropdownMenuItem(
              value: type,
              child: Text(_receiptLabels[type] ?? type),
            ),
          ),
        ],
        onChanged: (value) {
          ref.read(fiscalReceiptTypeFilterProvider.notifier).state = value;
        },
      ),
    );
  }
}

class _StatusChip extends ConsumerWidget {
  const _StatusChip({required this.selected});

  final String? selected;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return DropdownButtonHideUnderline(
      child: DropdownButton<String?>(
        value: selected,
        hint: const Text('Estado'),
        isDense: true,
        borderRadius: BorderRadius.circular(AppTokens.radiusS),
        items: [
          const DropdownMenuItem(value: null, child: Text('Todos los estados')),
          ..._statusOptions.map(
            (status) => DropdownMenuItem(
              value: status,
              child: Text(_statusLabels[status] ?? status),
            ),
          ),
        ],
        onChanged: (value) {
          ref.read(fiscalStatusFilterProvider.notifier).state = value;
        },
      ),
    );
  }
}

class _DocsList extends ConsumerWidget {
  const _DocsList({required this.docs});

  final List<FiscalDocument> docs;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (docs.isEmpty) {
      return const EmptyStateCard(
        icon: Icons.receipt_long_outlined,
        message: 'No se encontraron documentos fiscales para los filtros seleccionados.',
      );
    }

    return DataTableShell(
      title: 'Documentos fiscales (${docs.length})',
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: DataTable(
          columnSpacing: AppTokens.s16,
          columns: const [
            DataColumn(label: Text('NCF')),
            DataColumn(label: Text('Tipo')),
            DataColumn(label: Text('Estado')),
            DataColumn(label: Text('Cliente')),
            DataColumn(label: Text('Emisión')),
            DataColumn(label: Text('Total'), numeric: true),
            DataColumn(label: Text('ITBIS'), numeric: true),
          ],
          rows: docs.map((doc) => _buildRow(context, doc, ref)).toList(growable: false),
        ),
      ),
    );
  }

  DataRow _buildRow(BuildContext context, FiscalDocument doc, WidgetRef ref) {
    final statusColor =
        _statusColors[doc.fiscalStatus] ?? AppTokens.mutedForeground;
    final statusLabel = _statusLabels[doc.fiscalStatus] ?? doc.fiscalStatus;
    final receiptLabel =
        _receiptLabels[doc.receiptType] ?? _pretty(doc.receiptType);

    return DataRow(
      cells: [
        DataCell(
          GestureDetector(
            onTap: () => _showDetail(context, doc, ref),
            child: Text(
              doc.ncf,
              style: TextStyle(
                fontFamily: 'monospace',
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: Theme.of(context).colorScheme.primary,
                decoration: TextDecoration.underline,
              ),
            ),
          ),
        ),
        DataCell(Text(receiptLabel, style: const TextStyle(fontSize: 13))),
        DataCell(
          Container(
            padding: const EdgeInsets.symmetric(
              horizontal: AppTokens.s8,
              vertical: 3,
            ),
            decoration: BoxDecoration(
              color: statusColor.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(AppTokens.radiusS),
            ),
            child: Text(
              statusLabel,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: statusColor,
              ),
            ),
          ),
        ),
        DataCell(Text(
          doc.customerName ?? '—',
          style: const TextStyle(fontSize: 13),
          overflow: TextOverflow.ellipsis,
        )),
        DataCell(Text(
          formatDate(doc.issuedAt),
          style: const TextStyle(fontSize: 13),
        )),
        DataCell(Text(
          money(doc.totalAmount),
          style: const TextStyle(fontWeight: FontWeight.w700),
        )),
        DataCell(Text(money(doc.taxAmount))),
      ],
    );
  }

  void _showDetail(BuildContext context, FiscalDocument doc, WidgetRef ref) {
    showDialog<void>(
      context: context,
      builder: (_) => _FiscalDocDetailDialog(doc: doc, listRef: ref),
    );
  }
}

class _FiscalDocDetailDialog extends ConsumerStatefulWidget {
  const _FiscalDocDetailDialog({required this.doc, required this.listRef});

  final FiscalDocument doc;
  final WidgetRef listRef;

  @override
  ConsumerState<_FiscalDocDetailDialog> createState() =>
      _FiscalDocDetailDialogState();
}

class _FiscalDocDetailDialogState
    extends ConsumerState<_FiscalDocDetailDialog> {
  bool _voiding = false;

  Future<void> _onVoid() async {
    final reasonController = TextEditingController();

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Anular comprobante'),
        content: SizedBox(
          width: 400,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'Esta acción es irreversible. El NCF ${widget.doc.ncf} quedará marcado como anulado.',
                style: const TextStyle(color: AppTokens.mutedForeground),
              ),
              const SizedBox(height: AppTokens.s12),
              TextField(
                controller: reasonController,
                autofocus: true,
                decoration: const InputDecoration(
                  labelText: 'Razón de anulación *',
                  hintText: 'Ej: Error en monto, duplicado, etc.',
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: AppTokens.destructive,
            ),
            onPressed: () {
              if (reasonController.text.trim().isEmpty) return;
              Navigator.of(context).pop(true);
            },
            child: const Text('Anular'),
          ),
        ],
      ),
    );

    if (confirmed != true || !mounted) return;
    final reason = reasonController.text.trim();
    if (reason.isEmpty) return;

    setState(() => _voiding = true);
    try {
      final repo = ref.read(fiscalDocumentsRepositoryProvider);
      await repo.voidDocument(id: widget.doc.id, reason: reason);
      if (!mounted) return;
      widget.listRef.invalidate(fiscalDocumentsProvider);
      Navigator.of(context).pop();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Comprobante anulado.')),
      );
    } catch (error) {
      if (!mounted) return;
      setState(() => _voiding = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('No se pudo anular: ${friendlyErrorMessage(error)}')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final doc = widget.doc;
    final statusColor =
        _statusColors[doc.fiscalStatus] ?? AppTokens.mutedForeground;
    final statusLabel = _statusLabels[doc.fiscalStatus] ?? doc.fiscalStatus;
    final receiptLabel =
        _receiptLabels[doc.receiptType] ?? _pretty(doc.receiptType);
    final access = ref.watch(roleAccessProvider);
    final canVoid =
        !doc.isVoided && doc.fiscalStatus != 'voided' && access.canVoidSale;

    return AlertDialog(
      title: Row(
        children: [
          const Icon(Icons.receipt_long_outlined, size: 20),
          const SizedBox(width: AppTokens.s8),
          Expanded(
            child: Text(
              doc.ncf,
              style: const TextStyle(fontFamily: 'monospace', fontSize: 16),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          const SizedBox(width: AppTokens.s8),
          Container(
            padding: const EdgeInsets.symmetric(
              horizontal: AppTokens.s8,
              vertical: 3,
            ),
            decoration: BoxDecoration(
              color: statusColor.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(AppTokens.radiusS),
            ),
            child: Text(
              statusLabel,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: statusColor,
              ),
            ),
          ),
        ],
      ),
      content: SizedBox(
        width: 480,
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              _DetailSection(
                title: 'Comprobante',
                rows: [
                  _DetailRow('Tipo', receiptLabel),
                  _DetailRow('NCF', doc.ncf),
                  if (doc.sequenceNumber != null)
                    _DetailRow('Secuencia #', doc.sequenceNumber.toString()),
                  _DetailRow('Emisión', formatDateTime(doc.issuedAt)),
                  if (doc.expiresOn != null)
                    _DetailRow('Vence', formatDate(doc.expiresOn)),
                  if (doc.isVoided) ...[
                    _DetailRow('Anulado', formatDateTime(doc.voidedAt)),
                    if (doc.voidReason != null)
                      _DetailRow('Razón anulación', doc.voidReason!),
                  ],
                ],
              ),
              if (doc.customerName != null ||
                  doc.customerDocumentNumber != null) ...[
                const SizedBox(height: AppTokens.s16),
                _DetailSection(
                  title: 'Cliente',
                  rows: [
                    if (doc.customerName != null)
                      _DetailRow('Nombre', doc.customerName!),
                    if (doc.customerDocumentType != null &&
                        doc.customerDocumentNumber != null)
                      _DetailRow(
                        doc.customerDocumentType!.toUpperCase(),
                        doc.customerDocumentNumber!,
                      ),
                    if (doc.customerAddress != null)
                      _DetailRow('Dirección', doc.customerAddress!),
                  ],
                ),
              ],
              if (doc.issuerName != null) ...[
                const SizedBox(height: AppTokens.s16),
                _DetailSection(
                  title: 'Emisor',
                  rows: [
                    if (doc.issuerName != null)
                      _DetailRow('Nombre', doc.issuerName!),
                    if (doc.issuerTaxId != null)
                      _DetailRow('RNC', doc.issuerTaxId!),
                    if (doc.issuerAddress != null)
                      _DetailRow('Dirección', doc.issuerAddress!),
                  ],
                ),
              ],
              const SizedBox(height: AppTokens.s16),
              _DetailSection(
                title: 'Montos',
                rows: [
                  _DetailRow('Subtotal', money(doc.subtotal)),
                  if (doc.discountAmount > 0)
                    _DetailRow('Descuento', money(doc.discountAmount)),
                  if (doc.taxableAmount > 0)
                    _DetailRow('Monto gravable', money(doc.taxableAmount)),
                  if (doc.exemptAmount > 0)
                    _DetailRow('Exento', money(doc.exemptAmount)),
                  _DetailRow('ITBIS', money(doc.taxAmount)),
                  if (doc.serviceChargeAmount > 0)
                    _DetailRow('Serv./Ley', money(doc.serviceChargeAmount)),
                  _DetailRow('Total', money(doc.totalAmount), bold: true),
                ],
              ),
            ],
          ),
        ),
      ),
      actions: [
        if (canVoid)
          TextButton.icon(
            onPressed: _voiding ? null : _onVoid,
            icon: _voiding
                ? const SizedBox(
                    width: 14,
                    height: 14,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.block_outlined, size: 16),
            label: const Text('Anular'),
            style: TextButton.styleFrom(foregroundColor: AppTokens.destructive),
          ),
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cerrar'),
        ),
      ],
    );
  }
}

class _DetailSection extends StatelessWidget {
  const _DetailSection({required this.title, required this.rows});

  final String title;
  final List<_DetailRow> rows;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: const TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w700,
            color: AppTokens.mutedForeground,
            letterSpacing: 0.5,
          ),
        ),
        const SizedBox(height: AppTokens.s8),
        Container(
          decoration: BoxDecoration(
            color: AppTokens.card,
            borderRadius: BorderRadius.circular(AppTokens.radiusS),
            border: Border.all(color: AppTokens.border),
          ),
          child: Column(
            children: rows.map((row) => row.build(context)).toList(),
          ),
        ),
      ],
    );
  }
}

class _DetailRow {
  const _DetailRow(this.label, this.value, {this.bold = false});

  final String label;
  final String value;
  final bool bold;

  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: AppTokens.s12,
        vertical: AppTokens.s8,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 130,
            child: Text(
              label,
              style: const TextStyle(
                fontSize: 13,
                color: AppTokens.mutedForeground,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: TextStyle(
                fontSize: 13,
                fontWeight: bold ? FontWeight.w700 : FontWeight.normal,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

String _pretty(String value) {
  if (value.isEmpty) return '—';
  return value
      .split('_')
      .map((part) =>
          part.isEmpty ? part : '${part[0].toUpperCase()}${part.substring(1)}')
      .join(' ');
}
