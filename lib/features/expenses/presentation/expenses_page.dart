import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

import '../../../core/theme/tokens.dart';
import '../../../shared/formatters/formatters.dart';
import '../../../shared/responsive/responsive_layout.dart';
import '../../../shared/widgets/empty_state.dart';
import '../../../shared/widgets/module_page.dart';
import '../../../shared/widgets/print_receipt_dialog.dart';
import '../../../shared/widgets/ui_custom.dart';
import '../../cash_register/presentation/cash_register_providers.dart';
import '../../inventory/data/file_io_helper.dart';
import '../data/expenses_excel_service.dart';
import '../data/expenses_repository.dart';
import 'expenses_providers.dart';

class ExpensesPage extends ConsumerStatefulWidget {
  const ExpensesPage({super.key});

  @override
  ConsumerState<ExpensesPage> createState() => _ExpensesPageState();
}

class _ExpensesPageState extends ConsumerState<ExpensesPage> {
  final _searchController = TextEditingController();

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final expensesAsync = ref.watch(expensesListProvider);
    final query = ref.watch(expensesSearchProvider).trim().toLowerCase();

    return ModulePage(
      title: 'Gastos',
      description: 'Registra egresos operativos para controlar caja diaria.',
      actions: [
        OutlinedButton.icon(
          onPressed: () {
            ref.invalidate(expensesListProvider);
            ref.invalidate(expenseSuppliersProvider);
          },
          icon: const Icon(Icons.refresh, size: 18),
          label: const Text('Actualizar'),
        ),
        const SizedBox(width: AppTokens.s8),
        _buildExportMenu(),
        const SizedBox(width: AppTokens.s8),
        FilledButton.icon(
          onPressed: _onNewExpense,
          icon: const Icon(Icons.add_card_outlined, size: 18),
          label: const Text('Nuevo gasto'),
        ),
      ],
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          TextField(
            controller: _searchController,
            onChanged: (value) =>
                ref.read(expensesSearchProvider.notifier).state = value,
            decoration: const InputDecoration(
              prefixIcon: Icon(Icons.search, size: 18),
              hintText: 'Buscar por categoría, proveedor o descripción',
            ),
          ),
          const SizedBox(height: AppTokens.s24),
          expensesAsync.when(
            data: (expenses) {
              final filtered = expenses
                  .where((expense) {
                    if (query.isEmpty) return true;
                    final searchable = [
                      expense.category,
                      expense.supplierName ?? '',
                      expense.description ?? '',
                      expense.paymentMethod,
                    ].join(' ').toLowerCase();
                    return searchable.contains(query);
                  })
                  .toList(growable: false);

              final total = filtered.fold<double>(
                0,
                (sum, item) => sum + item.amount,
              );

              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _KpisGrid(count: filtered.length, total: total),
                  const SizedBox(height: AppTokens.s24),
                  DataTableShell(
                    title: 'Gastos (${filtered.length})',
                    child: filtered.isEmpty
                        ? const Padding(
                            padding: EdgeInsets.all(AppTokens.s20),
                            child: Text(
                              'No hay gastos registrados.',
                              style: TextStyle(color: AppTokens.mutedForeground),
                            ),
                          )
                        : DataTable(
                            columns: const [
                              DataColumn(label: Text('Fecha')),
                              DataColumn(label: Text('Categoría')),
                              DataColumn(label: Text('Proveedor')),
                              DataColumn(label: Text('Método')),
                              DataColumn(label: Text('Descripción')),
                              DataColumn(label: Text('Monto'), numeric: true),
                              DataColumn(label: Text('Acciones')),
                            ],
                            rows: filtered
                                .map(
                                  (expense) => DataRow(
                                    cells: [
                                      DataCell(Text(formatDate(expense.expenseDate))),
                                      DataCell(Text(
                                        expense.category,
                                        style: const TextStyle(fontWeight: FontWeight.w600),
                                      )),
                                      DataCell(Text(expense.supplierName ?? '-')),
                                      DataCell(Text(_pretty(expense.paymentMethod))),
                                      DataCell(Text(expense.description ?? '-')),
                                      DataCell(Text(
                                        money(expense.amount),
                                        style: const TextStyle(fontWeight: FontWeight.w700),
                                      )),
                                      DataCell(_ExpenseRowActions(
                                        onPrint: () => _onPrintExpense(expense),
                                        onEdit: () => _onEditExpense(expense),
                                        onDelete: () => _onDeleteExpense(expense),
                                      )),
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
              message: 'No se pudieron cargar gastos: $error',
              onRetry: () => ref.invalidate(expensesListProvider),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _onNewExpense() async {
    List<ExpenseSupplier> suppliers;
    try {
      suppliers = await ref.read(expenseSuppliersProvider.future);
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('No se pudo abrir formulario: $error')),
      );
      return;
    }

    if (!mounted) return;

    final input = await showDialog<ExpenseInput>(
      context: context,
      builder: (_) => _NewExpenseDialog(suppliers: suppliers),
    );

    if (input == null || !mounted) return;

    final repository = ref.read(expensesRepositoryProvider);

    try {
      await repository.createExpense(
        input,
        cashSessionId: ref.read(activeCashSessionIdProvider),
      );
      if (!mounted) return;

      ref.invalidate(expensesListProvider);
      // Refrescar la caja para que el gasto se refleje en su cuadre.
      ref.invalidate(cashRegisterDataProvider);
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Gasto registrado.')));
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('No se pudo registrar gasto: $error')),
      );
    }
  }

  /// Imprime el comprobante de gasto (egreso).
  Future<void> _onPrintExpense(ExpenseEntity expense) async {
    try {
      final job = await ref
          .read(expensesRepositoryProvider)
          .prepareExpenseReceipt(expense.id);
      if (!mounted) return;
      await PrintReceiptDialog.show(context, job);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('No se pudo preparar el comprobante: $e')),
      );
    }
  }

  /// Edita un gasto (reusa el formulario de "Nuevo gasto" prellenado).
  Future<void> _onEditExpense(ExpenseEntity expense) async {
    final List<ExpenseSupplier> suppliers;
    try {
      suppliers = await ref.read(expenseSuppliersProvider.future);
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('No se pudo abrir formulario: $error')),
      );
      return;
    }
    if (!mounted) return;

    final input = await showDialog<ExpenseInput>(
      context: context,
      builder: (_) => _NewExpenseDialog(suppliers: suppliers, initial: expense),
    );
    if (input == null || !mounted) return;

    try {
      await ref
          .read(expensesRepositoryProvider)
          .updateExpense(expense.id, input);
      if (!mounted) return;
      ref.invalidate(expensesListProvider);
      ref.invalidate(cashRegisterDataProvider);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Gasto actualizado.')),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('No se pudo actualizar el gasto: $error')),
      );
    }
  }

  /// Elimina un gasto (con confirmación).
  Future<void> _onDeleteExpense(ExpenseEntity expense) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Eliminar gasto'),
        content: Text(
          '¿Seguro que deseas eliminar el gasto "${expense.category}" '
          'de ${money(expense.amount)}?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: AppTokens.destructive,
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Eliminar'),
          ),
        ],
      ),
    );
    if (confirm != true || !mounted) return;

    try {
      await ref.read(expensesRepositoryProvider).deleteExpense(expense.id);
      if (!mounted) return;
      ref.invalidate(expensesListProvider);
      ref.invalidate(cashRegisterDataProvider);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Gasto eliminado.')),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('No se pudo eliminar el gasto: $error')),
      );
    }
  }

  // ─── Exportación Excel / PDF ──────────────────────────────────────────────

  Widget _buildExportMenu() {
    return PopupMenuButton<String>(
      tooltip: 'Exportar gastos',
      onSelected: (action) {
        switch (action) {
          case 'export':
            _onExportExpensesExcel();
          case 'export_pdf':
            _onExportExpensesPdf();
        }
      },
      itemBuilder: (_) => const [
        PopupMenuItem(
          value: 'export',
          child: ListTile(
            dense: true,
            contentPadding: EdgeInsets.zero,
            leading: Icon(Icons.table_chart_outlined, size: 18),
            title: Text('Exportar a Excel'),
          ),
        ),
        PopupMenuItem(
          value: 'export_pdf',
          child: ListTile(
            dense: true,
            contentPadding: EdgeInsets.zero,
            leading: Icon(Icons.picture_as_pdf_outlined, size: 18),
            title: Text('Exportar a PDF'),
          ),
        ),
      ],
      child: OutlinedButton.icon(
        onPressed: null,
        icon: const Icon(Icons.ios_share_rounded, size: 18),
        label: const Text('Exportar'),
        style: OutlinedButton.styleFrom(
          foregroundColor: AppTokens.foreground,
        ),
      ),
    );
  }

  Future<void> _onExportExpensesExcel() async {
    final List<ExpenseEntity> expenses;
    try {
      expenses = await ref.read(expensesListProvider.future);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('No se pudieron cargar gastos: $e')),
      );
      return;
    }
    if (!mounted) return;
    if (expenses.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No hay gastos para exportar.')),
      );
      return;
    }

    try {
      final bytes = ExpensesExcelService().buildExport(expenses: expenses);
      final saved = await FileIoHelper.saveBytes(
        bytes: bytes,
        fileName: 'gastos_${_timestamp()}.xlsx',
        dialogTitle: 'Guardar Gastos Excel',
        extension: 'xlsx',
      );
      if (!mounted) return;
      if (saved) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Gastos exportados a Excel (${expenses.length} gastos)'),
          ),
        );
      }
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('No se pudo exportar a Excel: $error')),
      );
    }
  }

  Future<void> _onExportExpensesPdf() async {
    final List<ExpenseEntity> expenses;
    try {
      expenses = await ref.read(expensesListProvider.future);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('No se pudieron cargar gastos: $e')),
      );
      return;
    }
    if (!mounted) return;
    if (expenses.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No hay gastos para exportar.')),
      );
      return;
    }

    try {
      final bytes = await _buildExpensesPdf(expenses);
      final saved = await FileIoHelper.saveBytes(
        bytes: bytes,
        fileName: 'gastos_${_timestamp()}.pdf',
        dialogTitle: 'Guardar Reporte de Gastos',
        extension: 'pdf',
      );
      if (!mounted) return;
      if (saved) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Reporte PDF exportado (${expenses.length} gastos)'),
          ),
        );
      }
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('No se pudo exportar a PDF: $error')),
      );
    }
  }

  Future<Uint8List> _buildExpensesPdf(List<ExpenseEntity> expenses) async {
    final pdf = pw.Document(
      theme: pw.ThemeData.withFont(
        base: await PdfGoogleFonts.robotoRegular(),
        bold: await PdfGoogleFonts.robotoBold(),
        italic: await PdfGoogleFonts.robotoItalic(),
      ),
    );

    final accent = PdfColor.fromInt(0xFF0D6EFD); // AppTokens.primary
    final muted = PdfColor.fromInt(0xFF66798E);  // AppTokens.mutedForeground
    final borderCol = PdfColor.fromInt(0xFFE9ECEF);

    final totalAmount = expenses.fold<double>(0, (sum, e) => sum + e.amount);

    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.letter,
        margin: const pw.EdgeInsets.all(32),
        header: (context) => pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.stretch,
          children: [
            pw.Row(
              mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
              children: [
                pw.Text(
                  'REPORTE DE GASTOS',
                  style: pw.TextStyle(
                    fontSize: 16,
                    fontWeight: pw.FontWeight.bold,
                    color: accent,
                  ),
                ),
                pw.Text(
                  formatDateTime(DateTime.now()),
                  style: pw.TextStyle(fontSize: 10, color: muted),
                ),
              ],
            ),
            pw.SizedBox(height: 4),
            pw.Text(
              'Busi Pos Web — Sistema de Gestión Comercial',
              style: pw.TextStyle(fontSize: 9, color: muted),
            ),
            pw.SizedBox(height: 12),
            pw.Divider(height: 1, color: borderCol),
            pw.SizedBox(height: 16),
          ],
        ),
        footer: (context) => pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.stretch,
          children: [
            pw.Divider(height: 1, color: borderCol),
            pw.SizedBox(height: 8),
            pw.Row(
              mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
              children: [
                pw.Text(
                  'Busi Pos Web — Reporte generado automáticamente',
                  style: pw.TextStyle(fontSize: 8, color: muted),
                ),
                pw.Text(
                  'Pág. ${context.pageNumber} de ${context.pagesCount}',
                  style: pw.TextStyle(fontSize: 8, color: muted),
                ),
              ],
            ),
          ],
        ),
        build: (context) => [
          // KPI summary
          pw.Container(
            padding: const pw.EdgeInsets.all(12),
            margin: const pw.EdgeInsets.only(bottom: 20),
            decoration: pw.BoxDecoration(
              color: PdfColor.fromInt(0xFFF8F9FA),
              borderRadius: const pw.BorderRadius.all(pw.Radius.circular(6)),
            ),
            child: pw.Row(
              mainAxisAlignment: pw.MainAxisAlignment.spaceAround,
              children: [
                _buildPdfKpi('Transacciones', expenses.length.toString(), accent),
                _buildPdfKpi('Monto Total', money(totalAmount), accent),
              ],
            ),
          ),

          // Table
          pw.Table(
            border: pw.TableBorder(
              bottom: pw.BorderSide(color: borderCol, width: 0.5),
              horizontalInside: pw.BorderSide(color: borderCol, width: 0.5),
            ),
            columnWidths: const {
              0: pw.FlexColumnWidth(1.5), // Fecha
              1: pw.FlexColumnWidth(2),   // Categoría
              2: pw.FlexColumnWidth(2.5), // Proveedor
              3: pw.FlexColumnWidth(2),   // Método
              4: pw.FlexColumnWidth(3),   // Descripción
              5: pw.FlexColumnWidth(1.8), // Monto
            },
            children: [
              // Header
              pw.TableRow(
                decoration: pw.BoxDecoration(
                  color: accent,
                  borderRadius: const pw.BorderRadius.only(
                    topLeft: pw.Radius.circular(4),
                    topRight: pw.Radius.circular(4),
                  ),
                ),
                children: [
                  _buildPdfTableHeaderCell('Fecha'),
                  _buildPdfTableHeaderCell('Categoría'),
                  _buildPdfTableHeaderCell('Proveedor'),
                  _buildPdfTableHeaderCell('Método'),
                  _buildPdfTableHeaderCell('Descripción'),
                  _buildPdfTableHeaderCell('Monto', align: pw.TextAlign.right),
                ],
              ),
              // Rows
              ...List.generate(expenses.length, (idx) {
                final e = expenses[idx];
                return pw.TableRow(
                  children: [
                    _buildPdfTableCellCell(formatDate(e.expenseDate)),
                    _buildPdfTableCellCell(e.category, isBold: true),
                    _buildPdfTableCellCell(e.supplierName ?? '-'),
                    _buildPdfTableCellCell(_pretty(e.paymentMethod)),
                    _buildPdfTableCellCell(e.description ?? '-'),
                    _buildPdfTableCellCell(money(e.amount), align: pw.TextAlign.right, isBold: true),
                  ],
                );
              }),
            ],
          ),
        ],
      ),
    );

    return pdf.save();
  }

  String _timestamp() {
    final n = DateTime.now();
    return '${n.year}${n.month.toString().padLeft(2, '0')}'
        '${n.day.toString().padLeft(2, '0')}_'
        '${n.hour.toString().padLeft(2, '0')}'
        '${n.minute.toString().padLeft(2, '0')}';
  }

  pw.Widget _buildPdfKpi(String label, String value, PdfColor color) {
    return pw.Column(
      mainAxisSize: pw.MainAxisSize.min,
      children: [
        pw.Text(
          label.toUpperCase(),
          style: pw.TextStyle(
            fontSize: 8,
            fontWeight: pw.FontWeight.bold,
            color: PdfColor.fromInt(0xFF66798E),
          ),
        ),
        pw.SizedBox(height: 4),
        pw.Text(
          value,
          style: pw.TextStyle(
            fontSize: 14,
            fontWeight: pw.FontWeight.bold,
            color: color,
          ),
        ),
      ],
    );
  }

  pw.Widget _buildPdfTableHeaderCell(String text, {pw.TextAlign align = pw.TextAlign.left}) {
    return pw.Padding(
      padding: const pw.EdgeInsets.symmetric(vertical: 8, horizontal: 6),
      child: pw.Text(
        text,
        textAlign: align,
        style: pw.TextStyle(
          color: PdfColors.white,
          fontSize: 8,
          fontWeight: pw.FontWeight.bold,
        ),
      ),
    );
  }

  pw.Widget _buildPdfTableCellCell(
    String text, {
    pw.TextAlign align = pw.TextAlign.left,
    bool isBold = false,
    bool isAlert = false,
  }) {
    return pw.Padding(
      padding: const pw.EdgeInsets.symmetric(vertical: 6, horizontal: 6),
      child: pw.Text(
        text,
        textAlign: align,
        style: pw.TextStyle(
          fontSize: 8,
          fontWeight: isBold ? pw.FontWeight.bold : pw.FontWeight.normal,
          color: isAlert ? PdfColor.fromInt(0xFFDC3545) : PdfColors.black,
        ),
      ),
    );
  }
}

class _KpisGrid extends StatelessWidget {
  const _KpisGrid({required this.count, required this.total});

  final int count;
  final double total;

  @override
  Widget build(BuildContext context) {
    final cards = [
      KPICard(
        label: 'Transacciones',
        value: count.toString(),
        icon: Icons.receipt_outlined,
        trend: 'Gastos registrados',
      ),
      KPICard(
        label: 'Total listado',
        value: money(total),
        icon: Icons.wallet_outlined,
        trend: 'Monto total',
      ),
    ];

    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth < AppTokens.breakpointCompact) {
          return Column(
            children: [cards[0], const SizedBox(height: AppTokens.s12), cards[1]],
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

class _NewExpenseDialog extends StatefulWidget {
  const _NewExpenseDialog({required this.suppliers, this.initial});

  final List<ExpenseSupplier> suppliers;

  /// Si viene, el diálogo actúa en modo edición (prellenado).
  final ExpenseEntity? initial;

  @override
  State<_NewExpenseDialog> createState() => _NewExpenseDialogState();
}

class _NewExpenseDialogState extends State<_NewExpenseDialog> {
  final _formKey = GlobalKey<FormState>();
  final _categoryController = TextEditingController();
  final _descriptionController = TextEditingController();
  final _amountController = TextEditingController(text: '0');

  String _paymentMethod = 'cash';
  String? _supplierId;
  DateTime _expenseDate = DateTime.now();

  @override
  void initState() {
    super.initState();
    final initial = widget.initial;
    if (initial != null) {
      _categoryController.text = initial.category;
      _descriptionController.text = initial.description ?? '';
      _amountController.text = initial.amount == initial.amount.roundToDouble()
          ? initial.amount.toInt().toString()
          : initial.amount.toStringAsFixed(2);
      const methods = ['cash', 'card', 'transfer', 'mobile'];
      _paymentMethod =
          methods.contains(initial.paymentMethod) ? initial.paymentMethod : 'cash';
      _supplierId = (initial.supplierId != null &&
              widget.suppliers.any((s) => s.id == initial.supplierId))
          ? initial.supplierId
          : null;
      _expenseDate = initial.expenseDate;
    }
  }

  @override
  void dispose() {
    _categoryController.dispose();
    _descriptionController.dispose();
    _amountController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isMobile = ResponsiveLayout.isMobile(context);

    return AlertDialog(
      title: Text(widget.initial == null ? 'Nuevo gasto' : 'Editar gasto'),
      content: SizedBox(
        width: isMobile ? double.maxFinite : 520,
        child: Form(
          key: _formKey,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextFormField(
                  controller: _categoryController,
                  decoration: const InputDecoration(labelText: 'Categoría'),
                  validator: (value) {
                    if (value == null || value.trim().isEmpty) {
                      return 'Categoría requerida';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 10),
                DropdownButtonFormField<String>(
                  initialValue: _supplierId ?? '',
                  decoration: const InputDecoration(labelText: 'Proveedor (opcional)'),
                  items: [
                    const DropdownMenuItem<String>(value: '', child: Text('Sin proveedor')),
                    ...widget.suppliers.map(
                      (supplier) => DropdownMenuItem<String>(
                        value: supplier.id,
                        child: Text(supplier.name),
                      ),
                    ),
                  ],
                  onChanged: (value) => setState(
                    () => _supplierId = (value == null || value.isEmpty) ? null : value,
                  ),
                ),
                const SizedBox(height: 10),
                _formRow(isMobile, [
                  DropdownButtonFormField<String>(
                    initialValue: _paymentMethod,
                    decoration: const InputDecoration(labelText: 'Método de pago'),
                    items: const [
                      DropdownMenuItem(value: 'cash', child: Text('Efectivo')),
                      DropdownMenuItem(value: 'card', child: Text('Tarjeta')),
                      DropdownMenuItem(value: 'transfer', child: Text('Transferencia')),
                      DropdownMenuItem(value: 'mobile', child: Text('Pago móvil')),
                    ],
                    onChanged: (value) {
                      if (value == null) return;
                      setState(() => _paymentMethod = value);
                    },
                  ),
                  TextFormField(
                    readOnly: true,
                    controller: TextEditingController(text: formatDate(_expenseDate)),
                    decoration: InputDecoration(
                      labelText: 'Fecha',
                      suffixIcon: IconButton(
                        onPressed: _pickDate,
                        icon: const Icon(Icons.calendar_month_outlined),
                      ),
                    ),
                  ),
                ]),
                const SizedBox(height: 10),
                TextFormField(
                  controller: _amountController,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  decoration: const InputDecoration(labelText: 'Monto'),
                  validator: (value) {
                    final parsed = double.tryParse(value ?? '');
                    if (parsed == null || parsed <= 0) return 'Monto inválido';
                    return null;
                  },
                ),
                const SizedBox(height: 10),
                TextFormField(
                  controller: _descriptionController,
                  decoration: const InputDecoration(labelText: 'Descripción'),
                ),
              ],
            ),
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancelar'),
        ),
        FilledButton(onPressed: _submit, child: const Text('Guardar')),
      ],
    );
  }

  Widget _formRow(bool isMobile, List<Widget> children) {
    if (isMobile) {
      return Column(
        children:
            children.expand((w) => [w, const SizedBox(height: 10)]).toList()
              ..removeLast(),
      );
    }
    return Row(
      children:
          children
              .expand((w) => [Expanded(child: w), const SizedBox(width: 10)])
              .toList()
            ..removeLast(),
    );
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _expenseDate,
      firstDate: DateTime(2020),
      lastDate: DateTime(2100),
    );
    if (picked == null) return;
    setState(() => _expenseDate = picked);
  }

  void _submit() {
    if (!_formKey.currentState!.validate()) return;

    Navigator.of(context).pop(
      ExpenseInput(
        category: _categoryController.text,
        paymentMethod: _paymentMethod,
        amount: double.parse(_amountController.text),
        expenseDate: _expenseDate,
        description: _descriptionController.text,
        supplierId: _supplierId,
      ),
    );
  }
}

/// Botones de acción por fila de gasto: imprimir comprobante, editar, eliminar.
class _ExpenseRowActions extends StatelessWidget {
  const _ExpenseRowActions({
    required this.onPrint,
    required this.onEdit,
    required this.onDelete,
  });

  final VoidCallback onPrint;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        IconButton(
          tooltip: 'Imprimir comprobante',
          onPressed: onPrint,
          icon: const Icon(Icons.print_outlined, size: 18),
          visualDensity: VisualDensity.compact,
          constraints: const BoxConstraints(),
          padding: const EdgeInsets.all(6),
        ),
        IconButton(
          tooltip: 'Editar',
          onPressed: onEdit,
          icon: const Icon(Icons.edit_outlined, size: 18),
          visualDensity: VisualDensity.compact,
          constraints: const BoxConstraints(),
          padding: const EdgeInsets.all(6),
        ),
        IconButton(
          tooltip: 'Eliminar',
          onPressed: onDelete,
          icon: const Icon(Icons.delete_outline_rounded, size: 18),
          color: AppTokens.destructive,
          visualDensity: VisualDensity.compact,
          constraints: const BoxConstraints(),
          padding: const EdgeInsets.all(6),
        ),
      ],
    );
  }
}

String _pretty(String value) {
  if (value.isEmpty) return '-';
  return value
      .split('_')
      .map((part) => part.isEmpty ? part : '${part[0].toUpperCase()}${part.substring(1)}')
      .join(' ');
}
