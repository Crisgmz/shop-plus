import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/tokens.dart';
import '../../../shared/formatters/formatters.dart';
import '../../../shared/widgets/empty_state.dart';
import '../../../shared/widgets/module_page.dart';
import '../../../shared/widgets/ui_custom.dart';
import '../../inventory/data/file_io_helper.dart';
import '../data/taxes_excel_service.dart';
import '../data/taxes_repository.dart';
import 'taxes_providers.dart';

const _receiptLabels = <String, String>{
  'consumer_final': 'Consumidor final',
  'fiscal_credit': 'Crédito fiscal',
  'governmental': 'Gubernamental',
  'special': 'Especial',
  'export': 'Exportación',
};

class TaxesPage extends ConsumerWidget {
  const TaxesPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final range = ref.watch(taxesRangeProvider);
    final dataAsync = ref.watch(taxesDataProvider);

    return ModulePage(
      title: 'Impuestos',
      description: 'Resumen fiscal, NCF y exportes 606/607.',
      actions: [
        OutlinedButton.icon(
          onPressed: () => ref.invalidate(taxesDataProvider),
          icon: const Icon(Icons.refresh, size: 18),
          label: const Text('Actualizar'),
        ),
      ],
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            decoration: BoxDecoration(
              color: AppTokens.card,
              borderRadius: BorderRadius.circular(AppTokens.radius),
              border: Border.all(color: AppTokens.border),
            ),
            padding: const EdgeInsets.all(AppTokens.s16),
            child: Row(
              children: [
                Expanded(
                  child: _DateButton(
                    label: 'Desde',
                    value: formatDate(range.start),
                    onTap: () =>
                        _pickDate(context: context, ref: ref, isStart: true),
                  ),
                ),
                const SizedBox(width: AppTokens.s12),
                Expanded(
                  child: _DateButton(
                    label: 'Hasta',
                    value: formatDate(range.end),
                    onTap: () =>
                        _pickDate(context: context, ref: ref, isStart: false),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: AppTokens.s24),
          dataAsync.when(
            data: (data) {
              final kpis = data.kpis;
              final excel = TaxesExcelService();

              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _TaxKpis(kpis: kpis),
                  const SizedBox(height: AppTokens.s24),
                  Container(
                    decoration: BoxDecoration(
                      color: AppTokens.card,
                      borderRadius: BorderRadius.circular(AppTokens.radius),
                      border: Border.all(color: AppTokens.border),
                    ),
                    padding: const EdgeInsets.all(AppTokens.s16),
                    child: Wrap(
                      spacing: 10,
                      runSpacing: 10,
                      children: [
                        FilledButton.icon(
                          onPressed: data.purchases.isEmpty
                              ? null
                              : () => _exportExcel(
                                    context: context,
                                    report: '606',
                                    range: data.range,
                                    count: data.purchases.length,
                                    build: () => excel.build606(data.purchases),
                                  ),
                          icon: const Icon(Icons.download, size: 18),
                          label: const Text('Exportar 606'),
                        ),
                        FilledButton.icon(
                          onPressed: data.sales.isEmpty
                              ? null
                              : () => _exportExcel(
                                    context: context,
                                    report: '607',
                                    range: data.range,
                                    count: data.sales.length,
                                    build: () => excel.build607(
                                      data.sales,
                                      receiptLabel: (type) =>
                                          _receiptLabels[type] ?? type,
                                    ),
                                  ),
                          icon: const Icon(Icons.download, size: 18),
                          label: const Text('Exportar 607'),
                        ),
                        Text(
                          'Generado para ${formatDate(data.range.start)} - ${formatDate(data.range.end)}',
                          style: const TextStyle(
                            fontSize: 14,
                            color: AppTokens.mutedForeground,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: AppTokens.s24),
                  DataTableShell(
                    title: 'Secuencias NCF',
                    child: data.ncfItems.isEmpty
                        ? const Padding(
                            padding: EdgeInsets.all(AppTokens.s20),
                            child: Text(
                              'No hay secuencias NCF disponibles.',
                              style: TextStyle(color: AppTokens.mutedForeground),
                            ),
                          )
                        : DataTable(
                            columns: const [
                              DataColumn(label: Text('Tipo')),
                              DataColumn(label: Text('Prefijo')),
                              DataColumn(label: Text('Actual'), numeric: true),
                              DataColumn(label: Text('Máximo'), numeric: true),
                              DataColumn(label: Text('Disponible'), numeric: true),
                              DataColumn(label: Text('Vence')),
                              DataColumn(label: Text('Estado')),
                            ],
                            rows: data.ncfItems
                                .map(
                                  (item) => DataRow(
                                    cells: [
                                      DataCell(Text(
                                        _receiptLabels[item.receiptType] ?? item.receiptType,
                                      )),
                                      DataCell(Text(
                                        item.prefix,
                                        style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
                                      )),
                                      DataCell(Text(item.currentNumber.toString())),
                                      DataCell(Text(item.maxNumber?.toString() ?? '-')),
                                      DataCell(Text(item.available?.toString() ?? 'Ilimitado')),
                                      DataCell(Text(
                                        item.expiresOn == null ? '-' : formatDate(item.expiresOn!),
                                      )),
                                      DataCell(StatusBadge(
                                        label: item.isActive ? 'Activa' : 'Inactiva',
                                        status: item.isActive ? 'active' : 'inactive',
                                      )),
                                    ],
                                  ),
                                )
                                .toList(growable: false),
                          ),
                  ),
                  const SizedBox(height: AppTokens.s24),
                  LayoutBuilder(
                    builder: (context, constraints) {
                      final salesTable = _salesTable(context: context, data: data.sales);
                      final purchaseTable = _purchaseTable(context: context, data: data.purchases);
                      if (constraints.maxWidth < 800) {
                        return Column(
                          children: [
                            salesTable,
                            const SizedBox(height: AppTokens.s12),
                            purchaseTable,
                          ],
                        );
                      }
                      return Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(child: salesTable),
                          const SizedBox(width: AppTokens.s12),
                          Expanded(child: purchaseTable),
                        ],
                      );
                    },
                  ),
                ],
              );
            },
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (error, _) => ErrorCard(
              message: 'No se pudieron cargar impuestos: $error',
              onRetry: () => ref.invalidate(taxesDataProvider),
            ),
          ),
        ],
      ),
    );
  }

  Widget _salesTable({
    required BuildContext context,
    required List<TaxSaleRecord> data,
  }) {
    return DataTableShell(
      title: 'Detalle Ventas (607)',
      child: data.isEmpty
          ? const Padding(
              padding: EdgeInsets.all(AppTokens.s20),
              child: Text(
                'Sin ventas para el período seleccionado.',
                style: TextStyle(color: AppTokens.mutedForeground),
              ),
            )
          : DataTable(
              columns: const [
                DataColumn(label: Text('Fecha')),
                DataColumn(label: Text('Cliente')),
                DataColumn(label: Text('NCF')),
                DataColumn(label: Text('Total'), numeric: true),
                DataColumn(label: Text('ITBIS'), numeric: true),
              ],
              rows: data
                  .take(20)
                  .map(
                    (row) => DataRow(
                      cells: [
                        DataCell(Text(formatDate(row.saleDate))),
                        DataCell(Text(row.clientName)),
                        DataCell(Text(
                          row.ncf ?? '-',
                          style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
                        )),
                        DataCell(Text(money(row.totalAmount))),
                        DataCell(Text(money(row.taxAmount))),
                      ],
                    ),
                  )
                  .toList(growable: false),
            ),
    );
  }

  Widget _purchaseTable({
    required BuildContext context,
    required List<TaxPurchaseRecord> data,
  }) {
    return DataTableShell(
      title: 'Detalle Compras (606)',
      child: data.isEmpty
          ? const Padding(
              padding: EdgeInsets.all(AppTokens.s20),
              child: Text(
                'Sin compras para el período seleccionado.',
                style: TextStyle(color: AppTokens.mutedForeground),
              ),
            )
          : DataTable(
              columns: const [
                DataColumn(label: Text('Fecha')),
                DataColumn(label: Text('Suplidor')),
                DataColumn(label: Text('Factura')),
                DataColumn(label: Text('Total'), numeric: true),
                DataColumn(label: Text('ITBIS'), numeric: true),
              ],
              rows: data
                  .take(20)
                  .map(
                    (row) => DataRow(
                      cells: [
                        DataCell(Text(formatDate(row.purchaseDate))),
                        DataCell(Text(row.supplierName)),
                        DataCell(Text(row.invoiceNumber ?? '-')),
                        DataCell(Text(money(row.totalAmount))),
                        DataCell(Text(money(row.taxAmount))),
                      ],
                    ),
                  )
                  .toList(growable: false),
            ),
    );
  }

  Future<void> _pickDate({
    required BuildContext context,
    required WidgetRef ref,
    required bool isStart,
  }) async {
    final range = ref.read(taxesRangeProvider);
    final initialDate = isStart ? range.start : range.end;
    final picked = await showDatePicker(
      context: context,
      initialDate: initialDate,
      firstDate: DateTime(2020, 1, 1),
      lastDate: DateTime.now().add(const Duration(days: 365)),
    );
    if (picked == null) return;

    final current = ref.read(taxesRangeProvider);
    final newStart = isStart ? picked : current.start;
    final newEnd = isStart ? current.end : picked;
    if (newEnd.isBefore(newStart)) return;

    ref.read(taxesRangeProvider.notifier).state = TaxesDateRange(
      start: DateTime(newStart.year, newStart.month, newStart.day),
      end: DateTime(newEnd.year, newEnd.month, newEnd.day),
    );
  }

  Future<void> _exportExcel({
    required BuildContext context,
    required String report,
    required TaxesDateRange range,
    required int count,
    required Uint8List Function() build,
  }) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      final saved = await FileIoHelper.saveBytes(
        bytes: build(),
        fileName: '${report}_${_isoDate(range.start)}_a_${_isoDate(range.end)}.xlsx',
        extension: 'xlsx',
        dialogTitle: 'Guardar $report en Excel',
      );
      if (!saved) return;
      messenger.showSnackBar(
        SnackBar(content: Text('$report exportado a Excel ($count registros).')),
      );
    } catch (e) {
      messenger.showSnackBar(
        SnackBar(content: Text('No se pudo exportar a Excel: $e')),
      );
    }
  }

  static String _isoDate(DateTime d) =>
      '${d.year}${d.month.toString().padLeft(2, '0')}${d.day.toString().padLeft(2, '0')}';
}

class _TaxKpis extends StatelessWidget {
  const _TaxKpis({required this.kpis});

  final TaxKpis kpis;

  @override
  Widget build(BuildContext context) {
    final cards = [
      KPICard(
        label: 'Ventas gravadas',
        value: money(kpis.salesTotal),
        icon: Icons.trending_up_rounded,
        trend: '${kpis.salesCount} documentos',
      ),
      KPICard(
        label: 'ITBIS ventas',
        value: money(kpis.salesTax),
        icon: Icons.receipt_outlined,
        trend: 'Periodo seleccionado',
      ),
      KPICard(
        label: 'Compras',
        value: money(kpis.purchasesTotal),
        icon: Icons.shopping_bag_outlined,
        trend: '${kpis.purchasesCount} facturas',
      ),
      KPICard(
        label: 'ITBIS compras',
        value: money(kpis.purchasesTax),
        icon: Icons.receipt_long_outlined,
        trend: 'Periodo seleccionado',
      ),
    ];

    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth < 800) {
          return Wrap(
            spacing: AppTokens.s12,
            runSpacing: AppTokens.s12,
            children: cards
                .map((card) => SizedBox(
                      width: (constraints.maxWidth - AppTokens.s12) / 2,
                      child: card,
                    ))
                .toList(),
          );
        }
        return Row(
          children: [
            Expanded(child: cards[0]),
            const SizedBox(width: AppTokens.s12),
            Expanded(child: cards[1]),
            const SizedBox(width: AppTokens.s12),
            Expanded(child: cards[2]),
            const SizedBox(width: AppTokens.s12),
            Expanded(child: cards[3]),
          ],
        );
      },
    );
  }
}

class _DateButton extends StatelessWidget {
  const _DateButton({
    required this.label,
    required this.value,
    required this.onTap,
  });

  final String label;
  final String value;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return OutlinedButton.icon(
      onPressed: onTap,
      icon: const Icon(Icons.calendar_today_outlined, size: 16),
      label: Text('$label: $value'),
    );
  }
}
