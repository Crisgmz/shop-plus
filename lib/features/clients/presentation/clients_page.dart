import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show PostgrestException;
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

import '../../../core/theme/tokens.dart';
import '../../../shared/formatters/formatters.dart';
import '../../../shared/responsive/responsive_layout.dart';
import '../../../shared/services/dgii_lookup_service.dart';
import '../../../shared/widgets/app_snackbar.dart';
import '../../../shared/widgets/empty_state.dart';
import '../../../shared/widgets/module_page.dart';
import '../../../shared/widgets/role_gate.dart';
import '../../../shared/widgets/ui_custom.dart';
import '../../inventory/data/file_io_helper.dart';
import '../../settings/presentation/app_settings_providers.dart';
import '../data/clients_excel_service.dart';
import '../data/clients_repository.dart';
import 'clients_providers.dart';

const _receiptTypeLabels = <String, String>{
  'consumer_final': 'Consumidor final',
  'fiscal_credit': 'Crédito fiscal',
  'governmental': 'Gubernamental',
  'special': 'Especial',
  'export': 'Exportación',
};

class ClientsPage extends ConsumerStatefulWidget {
  const ClientsPage({super.key});

  @override
  ConsumerState<ClientsPage> createState() => _ClientsPageState();
}

class _ClientsPageState extends ConsumerState<ClientsPage> {
  final _searchController = TextEditingController();

  /// IDs de clientes marcados con el checkbox para borrado masivo.
  final Set<String> _selectedIds = {};

  /// Evita guardar el mismo cliente dos veces si el usuario reintenta antes
  /// de que termine el primer guardado (red lenta) — causa de duplicados.
  bool _isSavingClient = false;

  @override
  void initState() {
    super.initState();
    // Restaurar la selección si el usuario la dejó a medias y navegó a otra
    // sección. Ver [clientsSelectionProvider].
    _selectedIds.addAll(ref.read(clientsSelectionProvider));
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  /// Conserva la selección en el provider tras cada cambio (no en `dispose`,
  /// que no es confiable) para no perderla al navegar a otra sección.
  void _persistSelection() {
    ref.read(clientsSelectionProvider.notifier).state = Set<String>.from(
      _selectedIds,
    );
  }

  void _clearSelection() {
    if (_selectedIds.isEmpty) return;
    setState(_selectedIds.clear);
    _persistSelection();
  }

  void _toggleSelected(String id, bool selected) {
    setState(() {
      if (selected) {
        _selectedIds.add(id);
      } else {
        _selectedIds.remove(id);
      }
    });
    _persistSelection();
  }

  void _toggleSelectAll(List<ClientEntity> filtered, bool selectAll) {
    setState(() {
      if (selectAll) {
        _selectedIds.addAll(filtered.map((c) => c.id));
      } else {
        _selectedIds.removeAll(filtered.map((c) => c.id));
      }
    });
    _persistSelection();
  }

  Future<void> _onDeleteSelected(List<ClientEntity> filtered) async {
    final selected = filtered
        .where((c) => _selectedIds.contains(c.id))
        .toList();
    if (selected.isEmpty) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Eliminar clientes'),
        content: Text(
          '¿Eliminar ${selected.length} cliente(s) seleccionado(s)?\n\n'
          'Los que tengan ventas o pagos registrados no se podrán borrar '
          'y se desactivarán en su lugar.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: AppTokens.error),
            onPressed: () => Navigator.pop(ctx, true),
            child: Text('Eliminar (${selected.length})'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    final repository = ref.read(clientsRepositoryProvider);
    var deleted = 0;
    var deactivated = 0;
    var failed = 0;
    for (final client in selected) {
      try {
        await repository.deleteClient(client.id);
        deleted++;
      } on PostgrestException catch (e) {
        // FK violation = tiene ventas/pagos → soft-delete.
        if (e.code == '23503') {
          try {
            await repository.setClientActive(
              clientId: client.id,
              isActive: false,
            );
            deactivated++;
          } catch (_) {
            failed++;
          }
        } else {
          failed++;
        }
      } catch (_) {
        failed++;
      }
    }

    if (!mounted) return;
    setState(_selectedIds.clear);
    _persistSelection();
    ref.invalidate(clientsListProvider);
    final parts = <String>[
      if (deleted > 0) '$deleted eliminado(s)',
      if (deactivated > 0) '$deactivated desactivado(s)',
      if (failed > 0) '$failed con error',
    ];
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(parts.isEmpty ? 'Sin cambios.' : parts.join('  ·  ')),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final clientsAsync = ref.watch(clientsListProvider);
    final showInactive = ref.watch(clientsShowInactiveProvider);

    return ModulePage(
      title: 'Clientes',
      description: 'Catálogo de clientes y cuentas por cobrar.',
      actions: [
        OutlinedButton.icon(
          onPressed: () => ref.invalidate(clientsListProvider),
          icon: const Icon(Icons.refresh, size: 18),
          label: const Text('Actualizar'),
        ),
        const SizedBox(width: AppTokens.s8),
        _buildExportMenu(),
        const SizedBox(width: AppTokens.s8),
        FilledButton.icon(
          onPressed: _onCreateClient,
          icon: const Icon(Icons.person_add_alt_1, size: 18),
          label: const Text('Nuevo cliente'),
        ),
      ],
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildFilterBar(showInactive),
          const SizedBox(height: AppTokens.s24),
          clientsAsync.when(
            data: (_) {
              // filtered y totalBalance viven en providers memoizados.
              final filtered = ref.watch(clientsFilteredProvider);
              final totalBalance = ref.watch(clientsFilteredBalanceProvider);

              final canSelect = ref.watch(roleAccessProvider).canDeleteRecord;
              final allSelected =
                  filtered.isNotEmpty &&
                  filtered.every((c) => _selectedIds.contains(c.id));
              final someSelected = filtered.any(
                (c) => _selectedIds.contains(c.id),
              );
              // Tristate: true=todos, null=algunos, false=ninguno.
              final bool? selectAllValue = allSelected
                  ? true
                  : (someSelected ? null : false);

              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _KpisGrid(
                    totalClients: filtered.length,
                    totalBalance: totalBalance,
                  ),
                  const SizedBox(height: AppTokens.s24),
                  Container(
                    decoration: BoxDecoration(
                      color: AppTokens.card,
                      borderRadius: BorderRadius.circular(AppTokens.radius),
                      border: Border.all(color: AppTokens.border),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Padding(
                          padding: const EdgeInsets.all(AppTokens.s20),
                          child: Row(
                            children: [
                              Text(
                                'Clientes (${filtered.length})',
                                style: const TextStyle(
                                  fontSize: 18,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              if (canSelect && _selectedIds.isNotEmpty) ...[
                                const SizedBox(width: AppTokens.s16),
                                Text(
                                  '${_selectedIds.length} seleccionado(s)',
                                  style: const TextStyle(
                                    color: AppTokens.mutedForeground,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                                const Spacer(),
                                TextButton(
                                  onPressed: _clearSelection,
                                  child: const Text('Cancelar'),
                                ),
                                const SizedBox(width: AppTokens.s8),
                                FilledButton.icon(
                                  style: FilledButton.styleFrom(
                                    backgroundColor: AppTokens.error,
                                  ),
                                  onPressed: () => _onDeleteSelected(filtered),
                                  icon: const Icon(
                                    Icons.delete_outline,
                                    size: 18,
                                  ),
                                  label: Text(
                                    'Eliminar (${_selectedIds.length})',
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ),
                        if (filtered.isEmpty)
                          const Padding(
                            padding: EdgeInsets.all(AppTokens.s20),
                            child: Text(
                              'No hay clientes que coincidan con el filtro.',
                              style: TextStyle(
                                color: AppTokens.mutedForeground,
                              ),
                            ),
                          )
                        else ...[
                          _ClientRowHeader(
                            showCheckbox: canSelect,
                            selectAllValue: selectAllValue,
                            onSelectAll: (v) =>
                                _toggleSelectAll(filtered, v ?? false),
                          ),
                          SizedBox(
                            // Altura del viewport para que ListView.builder
                            // virtualice: sólo renderiza los items visibles.
                            height: (MediaQuery.of(context).size.height * 0.6)
                                .clamp(360.0, double.infinity),
                            child: ListView.builder(
                              itemCount: filtered.length,
                              itemExtent: 56,
                              itemBuilder: (context, index) {
                                final client = filtered[index];
                                return _ClientRow(
                                  key: ValueKey(client.id),
                                  client: client,
                                  documentDisplay: _documentDisplay(client),
                                  entityLabel: _entityTypeLabel(
                                    client.entityType,
                                  ),
                                  showCheckbox: canSelect,
                                  selected: _selectedIds.contains(client.id),
                                  onSelectedChanged: (v) =>
                                      _toggleSelected(client.id, v ?? false),
                                  onEdit: () => _onEditClient(client),
                                  onHistory: () =>
                                      _onShowPaymentHistory(client),
                                  onToggle: () => _onToggleActive(client),
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
              message: 'No se pudieron cargar clientes: $error',
              onRetry: () => ref.invalidate(clientsListProvider),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFilterBar(bool showInactive) {
    final isMobile = ResponsiveLayout.isMobile(context);

    final searchField = TextField(
      controller: _searchController,
      onChanged: (value) =>
          ref.read(clientsSearchProvider.notifier).state = value,
      decoration: const InputDecoration(
        prefixIcon: Icon(Icons.search, size: 18),
        hintText: 'Buscar por nombre, documento, email o teléfono',
      ),
    );

    final filterChip = FilterChip(
      selected: showInactive,
      label: const Text('Mostrar inactivos'),
      onSelected: (value) =>
          ref.read(clientsShowInactiveProvider.notifier).state = value,
    );

    if (isMobile) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          searchField,
          const SizedBox(height: AppTokens.s12),
          filterChip,
        ],
      );
    }

    return Row(
      children: [
        Expanded(child: searchField),
        const SizedBox(width: AppTokens.s12),
        filterChip,
      ],
    );
  }

  String _documentDisplay(ClientEntity client) {
    final parts = [
      client.documentType ?? '',
      client.documentNumber ?? '',
    ].where((part) => part.isNotEmpty);
    return parts.isEmpty ? '-' : parts.join(': ');
  }

  Future<void> _onCreateClient() async {
    final input = await showDialog<ClientInput>(
      context: context,
      builder: (_) => const _ClientDialog(),
    );
    if (input == null || !mounted) return;
    await _saveClient(input, successMessage: 'Cliente creado');
  }

  Future<void> _onEditClient(ClientEntity client) async {
    final input = await showDialog<ClientInput>(
      context: context,
      builder: (_) => _ClientDialog(initial: client),
    );
    if (input == null || !mounted) return;
    await _saveClient(input, successMessage: 'Cliente actualizado');
  }

  Future<void> _saveClient(
    ClientInput input, {
    required String successMessage,
  }) async {
    // Guarda contra doble envío (evita insertar el mismo cliente 2 veces).
    if (_isSavingClient) return;

    // Al CREAR (sin id), avisar si ya hay un cliente con el mismo documento o
    // nombre. No bloquea: deja crear si el usuario insiste.
    if (input.id == null) {
      final duplicate = _findDuplicateClient(input);
      if (duplicate != null) {
        final doc = duplicate.documentNumber?.trim();
        final proceed = await _confirmDuplicate(
          title: 'Posible cliente duplicado',
          message:
              'Ya existe el cliente "${duplicate.fullName}"'
              '${doc != null && doc.isNotEmpty ? ' (Doc. $doc)' : ''}. '
              '¿Crear uno nuevo de todas formas?',
        );
        if (proceed != true || !mounted) return;
      }
    }

    _isSavingClient = true;
    final repository = ref.read(clientsRepositoryProvider);
    try {
      await repository.saveClient(input);
      if (!mounted) return;
      ref.invalidate(clientsListProvider);
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(successMessage)));
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('No se pudo guardar cliente: $error')),
      );
    } finally {
      _isSavingClient = false;
    }
  }

  /// Busca en la lista en memoria un cliente que probablemente sea el mismo
  /// que se está por crear: coincide número de documento o nombre completo.
  ClientEntity? _findDuplicateClient(ClientInput input) {
    final clients = ref.read(clientsListProvider).valueOrNull;
    if (clients == null) return null;

    final name = input.fullName.trim().toLowerCase();
    final doc = input.documentNumber?.trim().toLowerCase();

    for (final c in clients) {
      if (doc != null &&
          doc.isNotEmpty &&
          c.documentNumber?.trim().toLowerCase() == doc) {
        return c;
      }
      if (name.isNotEmpty && c.fullName.trim().toLowerCase() == name) {
        return c;
      }
    }
    return null;
  }

  /// Diálogo de confirmación reutilizable para avisos de posible duplicado.
  Future<bool?> _confirmDuplicate({
    required String title,
    required String message,
  }) {
    return showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Crear de todas formas'),
          ),
        ],
      ),
    );
  }

  Future<void> _onToggleActive(ClientEntity client) async {
    final repository = ref.read(clientsRepositoryProvider);
    try {
      await repository.setClientActive(
        clientId: client.id,
        isActive: !client.isActive,
      );
      if (!mounted) return;
      ref.invalidate(clientsListProvider);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            client.isActive ? 'Cliente desactivado' : 'Cliente activado',
          ),
        ),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('No se pudo actualizar cliente: $error')),
      );
    }
  }

  Future<void> _onShowPaymentHistory(ClientEntity client) async {
    await showDialog(
      context: context,
      builder: (_) => _PaymentHistoryDialog(client: client),
    );
  }

  // ─── Excel / PDF: plantilla, exportar, importar ────────────────────────────

  Widget _buildExportMenu() {
    return PopupMenuButton<String>(
      tooltip: 'Exportar / Importar',
      onSelected: (action) {
        switch (action) {
          case 'import':
            _onOpenImportDialog();
          case 'export':
            _onExportClients();
          case 'export_pdf':
            _onExportClientsPdf();
        }
      },
      itemBuilder: (_) => const [
        PopupMenuItem(
          value: 'import',
          child: ListTile(
            dense: true,
            contentPadding: EdgeInsets.zero,
            leading: Icon(Icons.file_upload_outlined, size: 18),
            title: Text('Importar / Actualizar'),
          ),
        ),
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
        style: OutlinedButton.styleFrom(foregroundColor: AppTokens.foreground),
      ),
    );
  }

  Future<void> _onExportClientsPdf() async {
    final List<ClientEntity> clients;
    try {
      clients = await ref.read(clientsListProvider.future);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('No se pudieron cargar clientes: $e')),
      );
      return;
    }
    if (!mounted) return;
    if (clients.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No hay clientes para exportar.')),
      );
      return;
    }

    try {
      final bytes = await _buildClientsPdf(clients);
      final saved = await FileIoHelper.saveBytes(
        bytes: bytes,
        fileName: 'clientes_${_timestamp()}.pdf',
        dialogTitle: 'Guardar Reporte de Clientes',
        extension: 'pdf',
      );
      if (!mounted) return;
      if (saved) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Reporte PDF exportado (${clients.length} clientes)'),
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

  Future<Uint8List> _buildClientsPdf(List<ClientEntity> clients) async {
    final pdf = pw.Document(
      theme: pw.ThemeData.withFont(
        base: await PdfGoogleFonts.robotoRegular(),
        bold: await PdfGoogleFonts.robotoBold(),
        italic: await PdfGoogleFonts.robotoItalic(),
      ),
    );

    final accent = PdfColor.fromInt(0xFF0D6EFD); // AppTokens.primary
    final muted = PdfColor.fromInt(0xFF66798E); // AppTokens.mutedForeground
    final borderCol = PdfColor.fromInt(0xFFE9ECEF);

    final totalBalance = clients.fold<double>(
      0,
      (sum, c) => sum + c.balanceDue,
    );

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
                  'REPORTE DE CLIENTES',
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
              'Shop+ — Sistema de Gestión Comercial',
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
                  'Shop+ — Reporte generado automáticamente',
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
                _buildPdfKpi(
                  'Total Clientes',
                  clients.length.toString(),
                  accent,
                ),
                _buildPdfKpi('Balance Pendiente', money(totalBalance), accent),
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
              0: pw.FlexColumnWidth(3), // Nombre
              1: pw.FlexColumnWidth(1.5), // Documento
              2: pw.FlexColumnWidth(1.5), // Teléfono
              3: pw.FlexColumnWidth(2), // Email
              4: pw.FlexColumnWidth(1.5), // Límite crédito
              5: pw.FlexColumnWidth(1.5), // Balance
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
                  _buildPdfTableHeaderCell('Nombre'),
                  _buildPdfTableHeaderCell('Documento'),
                  _buildPdfTableHeaderCell('Teléfono'),
                  _buildPdfTableHeaderCell('Email'),
                  _buildPdfTableHeaderCell(
                    'Límite crédito',
                    align: pw.TextAlign.right,
                  ),
                  _buildPdfTableHeaderCell(
                    'Balance',
                    align: pw.TextAlign.right,
                  ),
                ],
              ),
              // Rows
              ...List.generate(clients.length, (idx) {
                final c = clients[idx];
                final isEven = idx % 2 == 0;
                final bg = isEven
                    ? PdfColors.white
                    : PdfColor.fromInt(0xFFF8F9FA);

                return pw.TableRow(
                  decoration: pw.BoxDecoration(color: bg),
                  children: [
                    _buildPdfTableCellCell(c.fullName, isBold: true),
                    _buildPdfTableCellCell(c.documentNumber ?? '-'),
                    _buildPdfTableCellCell(c.phone ?? '-'),
                    _buildPdfTableCellCell(c.email ?? '-'),
                    _buildPdfTableCellCell(
                      money(c.creditLimit),
                      align: pw.TextAlign.right,
                    ),
                    _buildPdfTableCellCell(
                      money(c.balanceDue),
                      align: pw.TextAlign.right,
                      isAlert: c.balanceDue > 0,
                    ),
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

  pw.Widget _buildPdfTableHeaderCell(
    String text, {
    pw.TextAlign align = pw.TextAlign.left,
  }) {
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

  String _timestamp() {
    final n = DateTime.now();
    return '${n.year}${n.month.toString().padLeft(2, '0')}'
        '${n.day.toString().padLeft(2, '0')}_'
        '${n.hour.toString().padLeft(2, '0')}'
        '${n.minute.toString().padLeft(2, '0')}';
  }

  Future<void> _onOpenImportDialog() async {
    await showDialog<void>(
      context: context,
      builder: (_) => const _ImportClientsDialog(),
    );
  }

  Future<void> _onExportClients() async {
    final List<ClientEntity> clients;
    try {
      clients = await ref.read(clientsListProvider.future);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('No se pudieron cargar clientes: $e')),
      );
      return;
    }
    if (!mounted) return;
    if (clients.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No hay clientes para exportar.')),
      );
      return;
    }
    try {
      final bytes = ClientsExcelService().buildExport(clients: clients);
      final saved = await FileIoHelper.saveBytes(
        bytes: bytes,
        fileName: 'clientes_${_timestamp()}.xlsx',
        dialogTitle: 'Guardar clientes',
      );
      if (!mounted) return;
      if (saved) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Exportados ${clients.length} clientes.')),
        );
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('No se pudo exportar: $e')));
    }
  }
}

/// Diálogo de 2 pasos para importar / actualizar clientes por Excel.
///
/// Paso 1: descargar plantilla (clientes nuevos = vacía, o existentes =
/// listado actual pre-llenado para editar). Paso 2: subir el archivo lleno;
/// el documento/identificador decide si cada fila se crea o se actualiza.
class _ImportClientsDialog extends ConsumerStatefulWidget {
  const _ImportClientsDialog();

  @override
  ConsumerState<_ImportClientsDialog> createState() =>
      _ImportClientsDialogState();
}

class _ImportClientsDialogState extends ConsumerState<_ImportClientsDialog> {
  Uint8List? _pickedBytes;
  String? _pickedName;

  /// Operación en curso: 'new', 'existing' o 'process' (null = ninguna).
  String? _busy;

  bool get _isBusy => _busy != null;

  String _stamp() {
    final now = DateTime.now();
    String two(int n) => n.toString().padLeft(2, '0');
    return '${now.year}${two(now.month)}${two(now.day)}_'
        '${two(now.hour)}${two(now.minute)}';
  }

  void _snack(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _downloadNew() async {
    setState(() => _busy = 'new');
    try {
      final bytes = ClientsExcelService().buildTemplate();
      final saved = await FileIoHelper.saveBytes(
        bytes: bytes,
        fileName: 'plantilla_clientes_nuevos_${_stamp()}.xlsx',
        dialogTitle: 'Guardar plantilla de clientes nuevos',
      );
      if (saved) _snack('Plantilla para clientes nuevos generada');
    } catch (e) {
      _snack('No se pudo generar la plantilla: $e');
    } finally {
      if (mounted) setState(() => _busy = null);
    }
  }

  Future<void> _downloadExisting() async {
    setState(() => _busy = 'existing');
    try {
      final clients = await ref.read(clientsListProvider.future);
      if (clients.isEmpty) {
        _snack('No hay clientes existentes para actualizar.');
        return;
      }
      final bytes = ClientsExcelService().buildExport(clients: clients);
      final saved = await FileIoHelper.saveBytes(
        bytes: bytes,
        fileName: 'actualizar_clientes_existentes_${_stamp()}.xlsx',
        dialogTitle: 'Guardar plantilla de clientes existentes',
      );
      if (saved) {
        _snack('Plantilla con ${clients.length} clientes existentes generada');
      }
    } catch (e) {
      _snack('No se pudo generar la plantilla: $e');
    } finally {
      if (mounted) setState(() => _busy = null);
    }
  }

  Future<void> _pickFile() async {
    try {
      final picked = await FileIoHelper.pickXlsxFile();
      if (picked == null || !mounted) return;
      setState(() {
        _pickedBytes = picked.bytes;
        _pickedName = picked.name;
      });
    } catch (e) {
      _snack('No se pudo abrir el archivo: $e');
    }
  }

  Future<void> _process() async {
    final bytes = _pickedBytes;
    if (bytes == null) return;
    setState(() => _busy = 'process');
    try {
      final List<ClientEntity> existing;
      try {
        existing = await ref.read(clientsListProvider.future);
      } catch (e) {
        _snack('No se pudieron cargar clientes: $e');
        return;
      }

      final ClientImportParseResult parsed;
      try {
        parsed = ClientsExcelService().parseImport(
          bytes: bytes,
          existingClients: existing,
        );
      } catch (e) {
        _snack('Archivo inválido: $e');
        return;
      }

      if (parsed.totalRows == 0) {
        _snack('El archivo no contiene filas.');
        return;
      }

      if (!mounted) return;
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: const Text('Confirmar importación'),
          content: SizedBox(
            width: 480,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Filas leídas: ${parsed.totalRows}'),
                Text('Listas para importar: ${parsed.inputs.length}'),
                if (parsed.errors.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  const Text(
                    'Errores:',
                    style: TextStyle(fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 4),
                  ConstrainedBox(
                    constraints: const BoxConstraints(maxHeight: 200),
                    child: ListView(
                      shrinkWrap: true,
                      children: parsed.errors
                          .map(
                            (e) => Padding(
                              padding: const EdgeInsets.symmetric(vertical: 2),
                              child: Text(
                                'Fila ${e.rowNumber}: ${e.message}',
                                style: const TextStyle(
                                  fontSize: 12,
                                  color: AppTokens.destructive,
                                ),
                              ),
                            ),
                          )
                          .toList(),
                    ),
                  ),
                ],
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: const Text('Cancelar'),
            ),
            FilledButton(
              onPressed: parsed.inputs.isEmpty
                  ? null
                  : () => Navigator.of(dialogContext).pop(true),
              child: Text('Importar ${parsed.inputs.length}'),
            ),
          ],
        ),
      );
      if (confirmed != true || !mounted || parsed.inputs.isEmpty) return;

      try {
        final result = await ref
            .read(clientsRepositoryProvider)
            .bulkUpsertClients(parsed.inputs);
        if (!mounted) return;
        ref.invalidate(clientsListProvider);
        Navigator.of(context).pop();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            backgroundColor: AppTokens.success,
            content: Text(
              'Importación completa · ${result.created} nuevos, '
              '${result.updated} actualizados'
              '${result.errors.isNotEmpty ? " (${result.errors.length} con error)" : ""}.',
              style: const TextStyle(color: AppTokens.successForeground),
            ),
          ),
        );
      } catch (e) {
        _snack('Error al importar: $e');
      }
    } finally {
      if (mounted) setState(() => _busy = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isMobile = ResponsiveLayout.isMobile(context);
    return AlertDialog(
      title: const Text('Importar / Actualizar clientes'),
      content: SizedBox(
        width: isMobile ? double.maxFinite : 560,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _stepHeader(
                'Paso 1',
                'Descarga una plantilla, llénala con tus clientes y guárdala.',
              ),
              const SizedBox(height: AppTokens.s12),
              _downloadButton(
                icon: Icons.note_add_outlined,
                label: 'Plantilla para clientes NUEVOS',
                busyKey: 'new',
                onPressed: _downloadNew,
              ),
              const SizedBox(height: AppTokens.s8),
              _downloadButton(
                icon: Icons.edit_note_outlined,
                label: 'Plantilla para clientes EXISTENTES (actualizar)',
                busyKey: 'existing',
                onPressed: _downloadExisting,
              ),
              const SizedBox(height: AppTokens.s20),
              const Divider(height: 1),
              const SizedBox(height: AppTokens.s20),
              _stepHeader(
                'Paso 2',
                'Sube el archivo lleno para crear y actualizar clientes.',
              ),
              const SizedBox(height: AppTokens.s12),
              Row(
                children: [
                  Expanded(
                    child: InputDecorator(
                      decoration: const InputDecoration(
                        labelText: 'La ruta del archivo',
                        isDense: true,
                        border: OutlineInputBorder(),
                      ),
                      child: Text(
                        _pickedName ?? 'Ningún archivo seleccionado',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: _pickedName == null
                              ? AppTokens.mutedForeground
                              : AppTokens.foreground,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: AppTokens.s8),
                  OutlinedButton.icon(
                    onPressed: _isBusy ? null : _pickFile,
                    icon: const Icon(Icons.folder_open_outlined, size: 18),
                    label: const Text('Elegir archivo'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _isBusy ? null : () => Navigator.of(context).pop(),
          child: const Text('Cerrar'),
        ),
        FilledButton.icon(
          onPressed: (_pickedBytes == null || _isBusy) ? null : _process,
          icon: _busy == 'process'
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.upload_file_outlined, size: 18),
          label: const Text('Procesar'),
        ),
      ],
    );
  }

  Widget _stepHeader(String step, String description) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          step,
          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 2),
        Text(
          description,
          style: const TextStyle(
            color: AppTokens.mutedForeground,
            fontSize: 13,
          ),
        ),
      ],
    );
  }

  Widget _downloadButton({
    required IconData icon,
    required String label,
    required String busyKey,
    required VoidCallback onPressed,
  }) {
    final isBusy = _busy == busyKey;
    return SizedBox(
      width: double.infinity,
      child: FilledButton.tonalIcon(
        onPressed: _isBusy ? null : onPressed,
        icon: isBusy
            ? const SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : Icon(icon, size: 18),
        label: Align(alignment: Alignment.centerLeft, child: Text(label)),
        style: FilledButton.styleFrom(
          alignment: Alignment.centerLeft,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        ),
      ),
    );
  }
}

// ─── Payment history dialog ─────────────────────────────────────────────────

class _PaymentHistoryDialog extends ConsumerStatefulWidget {
  const _PaymentHistoryDialog({required this.client});

  final ClientEntity client;

  @override
  ConsumerState<_PaymentHistoryDialog> createState() =>
      _PaymentHistoryDialogState();
}

class _PaymentHistoryDialogState extends ConsumerState<_PaymentHistoryDialog> {
  late Future<List<ClientPaymentRow>> _future;

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  Future<List<ClientPaymentRow>> _load() async {
    final repo = ref.read(clientsRepositoryProvider);
    return repo.fetchPaymentsForClient(widget.client.id);
  }

  void _refresh() {
    setState(() => _future = _load());
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      insetPadding: const EdgeInsets.all(AppTokens.s24),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 720, maxHeight: 640),
        child: Padding(
          padding: const EdgeInsets.all(AppTokens.s20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  const Icon(Icons.payments_outlined, color: AppTokens.primary),
                  const SizedBox(width: AppTokens.s8),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Historial de pagos',
                          style: Theme.of(context).textTheme.titleMedium
                              ?.copyWith(fontWeight: FontWeight.w700),
                        ),
                        Text(
                          widget.client.fullName,
                          style: Theme.of(context).textTheme.bodySmall
                              ?.copyWith(color: AppTokens.mutedForeground),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    onPressed: _refresh,
                    icon: const Icon(Icons.refresh, size: 18),
                    tooltip: 'Actualizar',
                  ),
                  IconButton(
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.close, size: 20),
                  ),
                ],
              ),
              const Divider(height: AppTokens.s16),
              Expanded(
                child: FutureBuilder<List<ClientPaymentRow>>(
                  future: _future,
                  builder: (context, snap) {
                    if (snap.connectionState == ConnectionState.waiting) {
                      return const Center(child: CircularProgressIndicator());
                    }
                    if (snap.hasError) {
                      return Center(child: Text('Error: ${snap.error}'));
                    }
                    final rows = snap.data ?? const <ClientPaymentRow>[];
                    if (rows.isEmpty) {
                      return Center(
                        child: Text(
                          'Este cliente aún no tiene pagos registrados.',
                          style: TextStyle(color: AppTokens.mutedForeground),
                        ),
                      );
                    }
                    final total = rows.fold<double>(
                      0,
                      (sum, r) => sum + r.amount,
                    );
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Padding(
                          padding: const EdgeInsets.only(bottom: AppTokens.s12),
                          child: Row(
                            children: [
                              Text(
                                '${rows.length} pagos',
                                style: const TextStyle(
                                  color: AppTokens.mutedForeground,
                                ),
                              ),
                              const Spacer(),
                              Text(
                                'Total pagado: ${money(total)}',
                                style: const TextStyle(
                                  color: AppTokens.success,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                            ],
                          ),
                        ),
                        Expanded(
                          child: ListView.separated(
                            itemCount: rows.length,
                            separatorBuilder: (_, _) => const Divider(
                              height: 1,
                              color: AppTokens.border,
                            ),
                            itemBuilder: (context, i) => _PaymentRowTile(
                              row: rows[i],
                              onEdit: () => _onEdit(rows[i]),
                              onDelete: () => _onDelete(rows[i]),
                            ),
                          ),
                        ),
                      ],
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _onEdit(ClientPaymentRow row) async {
    final result = await showDialog<_EditPaymentResult>(
      context: context,
      builder: (_) => _EditPaymentDialog(row: row),
    );
    if (result == null || !mounted) return;
    try {
      await ref
          .read(clientsRepositoryProvider)
          .updatePayment(
            paymentId: row.id,
            amount: result.amount,
            paymentMethod: result.paymentMethod,
            reference: result.reference,
            notes: result.notes,
          );
      if (!mounted) return;
      _refresh();
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Pago actualizado')));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Error al actualizar: $e')));
    }
  }

  Future<void> _onDelete(ClientPaymentRow row) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Eliminar pago'),
        content: Text(
          '¿Eliminar el pago de ${money(row.amount)} '
          'del ${formatDate(row.paidAt)}? Esta acción no se puede deshacer.',
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
    if (confirmed != true || !mounted) return;
    try {
      await ref.read(clientsRepositoryProvider).deletePayment(row.id);
      if (!mounted) return;
      _refresh();
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Pago eliminado')));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Error al eliminar: $e')));
    }
  }
}

class _PaymentRowTile extends ConsumerWidget {
  const _PaymentRowTile({
    required this.row,
    required this.onEdit,
    required this.onDelete,
  });

  final ClientPaymentRow row;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final access = ref.watch(roleAccessProvider);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppTokens.s8),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(
                      money(row.amount),
                      style: const TextStyle(
                        fontWeight: FontWeight.w800,
                        fontSize: 15,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 2,
                      ),
                      decoration: BoxDecoration(
                        color: AppTokens.primary.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(
                        _methodLabel(row.paymentMethod),
                        style: const TextStyle(
                          fontSize: 11,
                          color: AppTokens.primary,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  '${formatDateTime(row.paidAt)}'
                  '${row.saleNumber != null ? " · Venta ${row.saleNumber}" : ""}',
                  style: const TextStyle(
                    color: AppTokens.mutedForeground,
                    fontSize: 12,
                  ),
                ),
                if (row.reference != null && row.reference!.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Text(
                      'Ref: ${row.reference}',
                      style: const TextStyle(
                        color: AppTokens.mutedForeground,
                        fontSize: 11,
                      ),
                    ),
                  ),
                if (row.notes != null && row.notes!.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Text(
                      row.notes!,
                      style: const TextStyle(
                        color: AppTokens.mutedForeground,
                        fontSize: 11,
                        fontStyle: FontStyle.italic,
                      ),
                    ),
                  ),
              ],
            ),
          ),
          IconButton(
            tooltip: 'Editar pago',
            onPressed: onEdit,
            icon: const Icon(Icons.edit_outlined, size: 18),
            visualDensity: VisualDensity.compact,
          ),
          if (access.canDeleteRecord)
            IconButton(
              tooltip: 'Eliminar pago',
              onPressed: onDelete,
              icon: const Icon(
                Icons.delete_outline,
                size: 18,
                color: AppTokens.destructive,
              ),
              visualDensity: VisualDensity.compact,
            ),
        ],
      ),
    );
  }

  String _methodLabel(String m) {
    switch (m) {
      case 'cash':
        return 'Efectivo';
      case 'card':
        return 'Tarjeta';
      case 'transfer':
        return 'Transferencia';
      case 'mobile':
        return 'Móvil';
      case 'credit':
        return 'Crédito';
      case 'mixed':
        return 'Mixto';
      default:
        return m;
    }
  }
}

class _EditPaymentResult {
  _EditPaymentResult({
    required this.amount,
    required this.paymentMethod,
    this.reference,
    this.notes,
  });

  final double amount;
  final String paymentMethod;
  final String? reference;
  final String? notes;
}

class _EditPaymentDialog extends StatefulWidget {
  const _EditPaymentDialog({required this.row});

  final ClientPaymentRow row;

  @override
  State<_EditPaymentDialog> createState() => _EditPaymentDialogState();
}

class _EditPaymentDialogState extends State<_EditPaymentDialog> {
  late final TextEditingController _amountController;
  late final TextEditingController _referenceController;
  late final TextEditingController _notesController;
  late String _method;

  @override
  void initState() {
    super.initState();
    _amountController = TextEditingController(
      text: widget.row.amount.toString(),
    );
    _referenceController = TextEditingController(
      text: widget.row.reference ?? '',
    );
    _notesController = TextEditingController(text: widget.row.notes ?? '');
    _method = widget.row.paymentMethod;
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
      title: const Text('Editar pago'),
      content: SizedBox(
        width: 360,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: _amountController,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              decoration: const InputDecoration(
                labelText: 'Monto',
                prefixText: r'RD$ ',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              initialValue: _method,
              decoration: const InputDecoration(
                labelText: 'Método',
                border: OutlineInputBorder(),
              ),
              items: const [
                DropdownMenuItem(value: 'cash', child: Text('Efectivo')),
                DropdownMenuItem(value: 'card', child: Text('Tarjeta')),
                DropdownMenuItem(
                  value: 'transfer',
                  child: Text('Transferencia'),
                ),
                DropdownMenuItem(value: 'mobile', child: Text('Pago móvil')),
                DropdownMenuItem(value: 'credit', child: Text('Crédito')),
              ],
              onChanged: (v) {
                if (v != null) setState(() => _method = v);
              },
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _referenceController,
              decoration: const InputDecoration(
                labelText: 'Referencia (opcional)',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
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
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancelar'),
        ),
        FilledButton(
          onPressed: () {
            final n = double.tryParse(_amountController.text.trim());
            if (n == null || n <= 0) {
              ScaffoldMessenger.of(
                context,
              ).showSnackBar(const SnackBar(content: Text('Monto inválido')));
              return;
            }
            Navigator.pop(
              context,
              _EditPaymentResult(
                amount: n,
                paymentMethod: _method,
                reference: _referenceController.text.trim(),
                notes: _notesController.text.trim(),
              ),
            );
          },
          child: const Text('Guardar'),
        ),
      ],
    );
  }
}

// ─── KPIs ────────────────────────────────────────────────────────────────────

/// Header de la tabla virtualizada de clientes — fijo arriba del
/// ListView.builder, no se duplica por fila.
class _ClientRowHeader extends StatelessWidget {
  const _ClientRowHeader({
    this.showCheckbox = false,
    this.selectAllValue = false,
    this.onSelectAll,
  });

  final bool showCheckbox;
  final bool? selectAllValue;
  final ValueChanged<bool?>? onSelectAll;

  @override
  Widget build(BuildContext context) {
    return Container(
      color: AppTokens.background,
      padding: const EdgeInsets.symmetric(
        horizontal: AppTokens.s16,
        vertical: AppTokens.s10,
      ),
      child: Row(
        children: [
          if (showCheckbox)
            SizedBox(
              width: 40,
              child: Checkbox(
                value: selectAllValue,
                tristate: true,
                onChanged: onSelectAll,
              ),
            ),
          const Expanded(flex: 3, child: _ColumnLabel('Nombre')),
          Expanded(flex: 2, child: _ColumnLabel('Tipo')),
          Expanded(flex: 2, child: _ColumnLabel('Documento')),
          Expanded(flex: 2, child: _ColumnLabel('Teléfono')),
          Expanded(flex: 3, child: _ColumnLabel('Email')),
          Expanded(
            flex: 2,
            child: _ColumnLabel('Crédito', align: TextAlign.right),
          ),
          Expanded(
            flex: 2,
            child: _ColumnLabel('Balance', align: TextAlign.right),
          ),
          Expanded(flex: 2, child: _ColumnLabel('Estado')),
          SizedBox(width: 140, child: _ColumnLabel('Acciones')),
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

/// Fila virtualizada de la tabla de clientes. Se usa con
/// `ListView.builder(itemExtent: 56)`.
class _ClientRow extends StatelessWidget {
  const _ClientRow({
    super.key,
    required this.client,
    required this.documentDisplay,
    required this.entityLabel,
    required this.onEdit,
    required this.onHistory,
    required this.onToggle,
    this.showCheckbox = false,
    this.selected = false,
    this.onSelectedChanged,
  });

  final ClientEntity client;
  final String documentDisplay;
  final String entityLabel;
  final VoidCallback onEdit;
  final VoidCallback onHistory;
  final VoidCallback onToggle;
  final bool showCheckbox;
  final bool selected;
  final ValueChanged<bool?>? onSelectedChanged;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: selected ? AppTokens.primary.withValues(alpha: 0.06) : null,
        border: const Border(top: BorderSide(color: AppTokens.border)),
      ),
      padding: const EdgeInsets.symmetric(horizontal: AppTokens.s16),
      child: Row(
        children: [
          if (showCheckbox)
            SizedBox(
              width: 40,
              child: Checkbox(value: selected, onChanged: onSelectedChanged),
            ),
          Expanded(
            flex: 3,
            child: Text(
              client.fullName,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
            ),
          ),
          Expanded(
            flex: 2,
            child: Text(
              entityLabel,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 13),
            ),
          ),
          Expanded(
            flex: 2,
            child: Text(
              documentDisplay,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
            ),
          ),
          Expanded(
            flex: 2,
            child: Text(
              client.phone ?? '-',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 13),
            ),
          ),
          Expanded(
            flex: 3,
            child: Text(
              client.email ?? '-',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 13),
            ),
          ),
          Expanded(
            flex: 2,
            child: Text(
              money(client.creditLimit),
              textAlign: TextAlign.right,
              style: const TextStyle(fontSize: 13),
            ),
          ),
          Expanded(
            flex: 2,
            child: Text(
              money(client.balanceDue),
              textAlign: TextAlign.right,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: client.balanceDue > 0 ? AppTokens.warning : null,
              ),
            ),
          ),
          Expanded(
            flex: 2,
            child: StatusBadge(
              label: client.isActive ? 'Activo' : 'Inactivo',
              status: client.isActive ? 'active' : 'inactive',
            ),
          ),
          SizedBox(
            width: 140,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                IconButton(
                  tooltip: 'Editar',
                  onPressed: onEdit,
                  icon: const Icon(
                    Icons.edit_outlined,
                    size: AppTokens.iconSizeS,
                  ),
                  visualDensity: VisualDensity.compact,
                ),
                IconButton(
                  tooltip: 'Historial de pagos',
                  onPressed: onHistory,
                  icon: const Icon(
                    Icons.payments_outlined,
                    size: AppTokens.iconSizeS,
                  ),
                  visualDensity: VisualDensity.compact,
                ),
                IconButton(
                  tooltip: client.isActive ? 'Desactivar' : 'Activar',
                  onPressed: onToggle,
                  icon: Icon(
                    client.isActive
                        ? Icons.block_outlined
                        : Icons.check_circle_outline,
                    size: AppTokens.iconSizeS,
                    color: client.isActive
                        ? AppTokens.destructive
                        : AppTokens.success,
                  ),
                  visualDensity: VisualDensity.compact,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _KpisGrid extends StatelessWidget {
  const _KpisGrid({required this.totalClients, required this.totalBalance});

  final int totalClients;
  final double totalBalance;

  @override
  Widget build(BuildContext context) {
    final cards = [
      KPICard(
        label: 'Clientes',
        value: totalClients.toString(),
        icon: Icons.people_outline_rounded,
        trend: 'Registrados',
      ),
      KPICard(
        label: 'Balance por cobrar',
        value: money(totalBalance),
        icon: Icons.attach_money_rounded,
        trend: 'Total pendiente',
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

// ─── Client dialog ───────────────────────────────────────────────────────────

class _ClientDialog extends ConsumerStatefulWidget {
  const _ClientDialog({this.initial});

  final ClientEntity? initial;

  @override
  ConsumerState<_ClientDialog> createState() => _ClientDialogState();
}

class _ClientDialogState extends ConsumerState<_ClientDialog> {
  final _formKey = GlobalKey<FormState>();

  // Datos generales
  late final TextEditingController _fullNameController;
  late final TextEditingController _firstNameController;
  late final TextEditingController _lastNameController;
  late final TextEditingController _companyNameController;
  late final TextEditingController _legalNameController;
  late final TextEditingController _documentTypeController;
  late final TextEditingController _documentNumberController;

  // Contacto
  late final TextEditingController _emailController;
  late final TextEditingController _phoneController;
  late final TextEditingController _secondaryPhoneController;

  // Dirección
  late final TextEditingController _addressLine1Controller;
  late final TextEditingController _addressLine2Controller;
  late final TextEditingController _cityController;
  late final TextEditingController _provinceController;
  late final TextEditingController _postalCodeController;
  late final TextEditingController _countryCodeController;
  late final TextEditingController _googleMapsUrlController;

  // Fiscal / Comercial
  late final TextEditingController _creditLimitController;
  late final TextEditingController _creditInvoiceLimitController;
  late final TextEditingController _birthdayController;
  late final TextEditingController _commentsController;

  late String _entityType;
  late String _priceTier;
  late String? _defaultReceiptType;
  late bool _isActive;
  late bool _taxExempt;
  late bool _chargeItbis;

  /// Consulta de RNC a DGII en curso.
  bool _rncLookupLoading = false;

  @override
  void initState() {
    super.initState();
    final c = widget.initial;

    _fullNameController = TextEditingController(text: c?.fullName ?? '');
    _firstNameController = TextEditingController(text: c?.firstName ?? '');
    _lastNameController = TextEditingController(text: c?.lastName ?? '');
    _companyNameController = TextEditingController(text: c?.companyName ?? '');
    _legalNameController = TextEditingController(text: c?.legalName ?? '');
    _documentTypeController = TextEditingController(
      text: c?.documentType ?? '',
    );
    _documentNumberController = TextEditingController(
      text: c?.documentNumber ?? '',
    );

    _emailController = TextEditingController(text: c?.email ?? '');
    _phoneController = TextEditingController(text: c?.phone ?? '');
    _secondaryPhoneController = TextEditingController(
      text: c?.secondaryPhone ?? '',
    );

    _addressLine1Controller = TextEditingController(
      text: c?.addressLine1 ?? c?.address ?? '',
    );
    _addressLine2Controller = TextEditingController(
      text: c?.addressLine2 ?? '',
    );
    _cityController = TextEditingController(text: c?.city ?? '');
    _provinceController = TextEditingController(text: c?.province ?? '');
    _postalCodeController = TextEditingController(text: c?.postalCode ?? '');
    _countryCodeController = TextEditingController(
      text: c?.countryCode ?? 'DO',
    );
    _googleMapsUrlController = TextEditingController(
      text: c?.googleMapsUrl ?? '',
    );

    _creditLimitController = TextEditingController(
      text: c == null ? '0' : c.creditLimit.toStringAsFixed(2),
    );
    _creditInvoiceLimitController = TextEditingController(
      text: (c?.creditInvoiceLimit ?? 0).toString(),
    );
    _birthdayController = TextEditingController(
      text: c?.birthday == null ? '' : _date(c!.birthday!),
    );
    _commentsController = TextEditingController(text: c?.comments ?? '');

    _entityType = c?.entityType ?? 'person';
    _priceTier = c?.priceTier ?? 'retail';
    _defaultReceiptType = c?.defaultReceiptType;
    _isActive = c?.isActive ?? true;
    _taxExempt = c?.taxExempt ?? false;
    _chargeItbis = c?.chargeItbis ?? true;
  }

  @override
  void dispose() {
    _fullNameController.dispose();
    _firstNameController.dispose();
    _lastNameController.dispose();
    _companyNameController.dispose();
    _legalNameController.dispose();
    _documentTypeController.dispose();
    _documentNumberController.dispose();
    _emailController.dispose();
    _phoneController.dispose();
    _secondaryPhoneController.dispose();
    _addressLine1Controller.dispose();
    _addressLine2Controller.dispose();
    _cityController.dispose();
    _provinceController.dispose();
    _postalCodeController.dispose();
    _countryCodeController.dispose();
    _googleMapsUrlController.dispose();
    _creditLimitController.dispose();
    _creditInvoiceLimitController.dispose();
    _birthdayController.dispose();
    _commentsController.dispose();
    super.dispose();
  }

  /// Consulta el RNC/cédula del campo "Número documento" contra DGII y
  /// auto-completa razón social, nombre comercial y tipo de documento.
  Future<void> _lookupRnc() async {
    final raw = _documentNumberController.text.trim();
    if (raw.isEmpty) {
      AppSnackBar.info(context, 'Escribe el RNC o cédula primero.');
      return;
    }
    setState(() => _rncLookupLoading = true);
    try {
      final info = await ref.read(dgiiLookupServiceProvider).lookupByRnc(raw);
      if (!mounted) return;
      if (info == null) {
        AppSnackBar.error(context, 'RNC/cédula no encontrado en DGII.');
        return;
      }
      setState(() {
        final name = info.nombreRazonSocial ?? info.displayName;
        if (name != null && name.isNotEmpty) {
          if (_legalNameController.text.trim().isEmpty) {
            _legalNameController.text = name;
          }
          if (_fullNameController.text.trim().isEmpty) {
            _fullNameController.text = name;
          }
        }
        final comercial = info.nombreComercial;
        if (comercial != null &&
            comercial.isNotEmpty &&
            _companyNameController.text.trim().isEmpty) {
          _companyNameController.text = comercial;
        }
        // Tipo de documento por longitud: 11 = cédula, 9 = RNC (empresa).
        final digits = raw.replaceAll(RegExp(r'[^0-9]'), '');
        if (_documentTypeController.text.trim().isEmpty) {
          _documentTypeController.text = digits.length == 11 ? 'cedula' : 'rnc';
        }
      });
      if (info.isActivo) {
        AppSnackBar.success(context, 'Encontrado: ${info.displayName ?? raw}');
      } else {
        AppSnackBar.info(
          context,
          'Encontrado (${info.estado ?? "estado desconocido"}): '
          '${info.displayName ?? raw}',
        );
      }
    } on InvalidRncException catch (e) {
      if (mounted) AppSnackBar.error(context, e.reason);
    } catch (e) {
      if (mounted) AppSnackBar.error(context, 'No se pudo consultar el RNC', e);
    } finally {
      if (mounted) setState(() => _rncLookupLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isMobile = ResponsiveLayout.isMobile(context);

    return AlertDialog(
      title: Text(widget.initial == null ? 'Nuevo cliente' : 'Editar cliente'),
      content: SizedBox(
        width: isMobile ? double.maxFinite : 580,
        child: Form(
          key: _formKey,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // ── Datos generales ──────────────────────────────────────
                _sectionHeader('Datos generales'),
                TextFormField(
                  controller: _fullNameController,
                  decoration: const InputDecoration(
                    labelText: 'Nombre completo / Razón comercial',
                  ),
                  validator: (value) {
                    if (value == null || value.trim().isEmpty) {
                      return 'Nombre requerido';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 10),
                _formRow(isMobile, [
                  TextFormField(
                    controller: _firstNameController,
                    decoration: const InputDecoration(labelText: 'Nombre'),
                  ),
                  TextFormField(
                    controller: _lastNameController,
                    decoration: const InputDecoration(labelText: 'Apellido'),
                  ),
                ]),
                const SizedBox(height: 10),
                DropdownButtonFormField<String>(
                  initialValue: _entityType,
                  decoration: const InputDecoration(
                    labelText: 'Tipo de entidad',
                  ),
                  items: const [
                    DropdownMenuItem(value: 'person', child: Text('Persona')),
                    DropdownMenuItem(value: 'company', child: Text('Empresa')),
                    DropdownMenuItem(
                      value: 'government',
                      child: Text('Gubernamental'),
                    ),
                  ],
                  onChanged: (value) {
                    if (value == null) return;
                    setState(() => _entityType = value);
                  },
                ),
                const SizedBox(height: 10),
                _formRow(isMobile, [
                  TextFormField(
                    controller: _companyNameController,
                    decoration: const InputDecoration(
                      labelText: 'Nombre empresa',
                    ),
                  ),
                  TextFormField(
                    controller: _legalNameController,
                    decoration: const InputDecoration(
                      labelText: 'Razón social',
                    ),
                  ),
                ]),
                const SizedBox(height: 10),
                _formRow(isMobile, [
                  TextFormField(
                    controller: _documentTypeController,
                    decoration: const InputDecoration(
                      labelText: 'Tipo doc. (cédula/rnc)',
                    ),
                  ),
                  TextFormField(
                    controller: _documentNumberController,
                    keyboardType: TextInputType.number,
                    onFieldSubmitted: (_) => _lookupRnc(),
                    decoration: InputDecoration(
                      labelText: 'Número documento',
                      helperText: 'RNC (9) o cédula (11). Busca en DGII.',
                      suffixIcon: _rncLookupLoading
                          ? const Padding(
                              padding: EdgeInsets.all(10),
                              child: SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              ),
                            )
                          : IconButton(
                              tooltip: 'Buscar razón social en DGII',
                              icon: const Icon(Icons.search),
                              onPressed: _lookupRnc,
                            ),
                    ),
                  ),
                ]),
                const SizedBox(height: 16),
                const Divider(),

                // ── Contacto ─────────────────────────────────────────────
                _sectionHeader('Contacto'),
                _formRow(isMobile, [
                  TextFormField(
                    controller: _emailController,
                    decoration: const InputDecoration(labelText: 'Correo'),
                    validator: (value) {
                      if (value == null || value.trim().isEmpty) return null;
                      if (!value.contains('@')) return 'Correo inválido';
                      return null;
                    },
                  ),
                  TextFormField(
                    controller: _phoneController,
                    decoration: const InputDecoration(labelText: 'Teléfono'),
                  ),
                ]),
                const SizedBox(height: 10),
                TextFormField(
                  controller: _secondaryPhoneController,
                  decoration: const InputDecoration(
                    labelText: 'Teléfono secundario',
                  ),
                ),
                const SizedBox(height: 16),
                const Divider(),

                // ── Dirección ────────────────────────────────────────────
                _sectionHeader('Dirección'),
                TextFormField(
                  controller: _addressLine1Controller,
                  decoration: const InputDecoration(labelText: 'Dirección'),
                ),
                const SizedBox(height: 10),
                TextFormField(
                  controller: _addressLine2Controller,
                  decoration: const InputDecoration(
                    labelText: 'Dirección (línea 2)',
                  ),
                ),
                const SizedBox(height: 10),
                _formRow(isMobile, [
                  TextFormField(
                    controller: _cityController,
                    decoration: const InputDecoration(labelText: 'Ciudad'),
                  ),
                  TextFormField(
                    controller: _provinceController,
                    decoration: const InputDecoration(labelText: 'Provincia'),
                  ),
                ]),
                const SizedBox(height: 10),
                _formRow(isMobile, [
                  TextFormField(
                    controller: _postalCodeController,
                    decoration: const InputDecoration(
                      labelText: 'Código postal',
                    ),
                  ),
                  TextFormField(
                    controller: _countryCodeController,
                    decoration: const InputDecoration(labelText: 'País'),
                  ),
                ]),
                const SizedBox(height: 10),
                TextFormField(
                  controller: _googleMapsUrlController,
                  decoration: const InputDecoration(
                    labelText: 'URL Google Maps (opcional)',
                  ),
                ),
                const SizedBox(height: 16),
                const Divider(),

                // ── Fiscal / Comercial ───────────────────────────────────
                _sectionHeader('Fiscal / Comercial'),
                _formRow(isMobile, [
                  TextFormField(
                    controller: _creditLimitController,
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    decoration: const InputDecoration(
                      labelText: 'Límite de crédito',
                    ),
                    validator: (value) {
                      final parsed = double.tryParse(value ?? '');
                      if (parsed == null || parsed < 0) {
                        return 'Límite inválido';
                      }
                      return null;
                    },
                  ),
                  TextFormField(
                    controller: _creditInvoiceLimitController,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                      labelText: 'Límite facturas crédito',
                    ),
                    validator: (value) {
                      final parsed = int.tryParse(value ?? '');
                      if (parsed == null || parsed < 0) {
                        return 'Valor inválido';
                      }
                      return null;
                    },
                  ),
                ]),
                const SizedBox(height: 10),
                _PriceTierDropdown(
                  value: _priceTier,
                  onChanged: (v) => setState(() => _priceTier = v),
                ),
                const SizedBox(height: 10),
                DropdownButtonFormField<String?>(
                  initialValue: _defaultReceiptType,
                  decoration: const InputDecoration(
                    labelText: 'Comprobante por defecto (opcional)',
                  ),
                  items: [
                    const DropdownMenuItem<String?>(
                      value: null,
                      child: Text('— Sin especificar —'),
                    ),
                    ..._receiptTypeLabels.entries.map(
                      (e) => DropdownMenuItem<String?>(
                        value: e.key,
                        child: Text(e.value),
                      ),
                    ),
                  ],
                  onChanged: (value) =>
                      setState(() => _defaultReceiptType = value),
                ),
                const SizedBox(height: 8),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  value: _chargeItbis,
                  onChanged: (value) => setState(() => _chargeItbis = value),
                  title: const Text('Cobrar ITBIS'),
                ),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  value: _taxExempt,
                  onChanged: (value) => setState(() => _taxExempt = value),
                  title: const Text('Exento de impuestos'),
                ),
                const SizedBox(height: 16),
                const Divider(),

                // ── Otros ────────────────────────────────────────────────
                _sectionHeader('Otros'),
                TextFormField(
                  controller: _birthdayController,
                  readOnly: true,
                  decoration: InputDecoration(
                    labelText: 'Fecha de nacimiento',
                    suffixIcon: IconButton(
                      onPressed: _pickBirthday,
                      icon: const Icon(Icons.calendar_today_outlined),
                    ),
                  ),
                ),
                const SizedBox(height: 10),
                TextFormField(
                  controller: _commentsController,
                  decoration: const InputDecoration(labelText: 'Comentarios'),
                  maxLines: 2,
                ),
                const SizedBox(height: 8),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  value: _isActive,
                  onChanged: (value) => setState(() => _isActive = value),
                  title: const Text('Activo'),
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

  Widget _sectionHeader(String label) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Text(
        label,
        style: Theme.of(context).textTheme.labelLarge?.copyWith(
          color: AppTokens.textSecondary,
          fontWeight: FontWeight.w700,
        ),
      ),
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

  Future<void> _pickBirthday() async {
    final now = DateTime.now();
    final parsed = _parseDate(_birthdayController.text) ?? now;
    final picked = await showDatePicker(
      context: context,
      initialDate: parsed,
      firstDate: DateTime(now.year - 120),
      lastDate: now,
    );
    if (picked == null) return;
    _birthdayController.text = _date(picked);
  }

  void _submit() {
    if (!_formKey.currentState!.validate()) return;

    Navigator.of(context).pop(
      ClientInput(
        id: widget.initial?.id,
        fullName: _fullNameController.text.trim(),
        firstName: _firstNameController.text.trim(),
        lastName: _lastNameController.text.trim(),
        companyName: _companyNameController.text.trim(),
        entityType: _entityType,
        legalName: _legalNameController.text.trim(),
        email: _emailController.text.trim(),
        phone: _phoneController.text.trim(),
        secondaryPhone: _secondaryPhoneController.text.trim(),
        address: _addressLine1Controller.text.trim(),
        addressLine1: _addressLine1Controller.text.trim(),
        addressLine2: _addressLine2Controller.text.trim(),
        city: _cityController.text.trim(),
        province: _provinceController.text.trim(),
        postalCode: _postalCodeController.text.trim(),
        countryCode: _countryCodeController.text.trim().isEmpty
            ? 'DO'
            : _countryCodeController.text.trim(),
        googleMapsUrl: _googleMapsUrlController.text.trim(),
        documentType: _documentTypeController.text.trim(),
        documentNumber: _documentNumberController.text.trim(),
        creditLimit: double.parse(_creditLimitController.text.trim()),
        creditInvoiceLimit: int.parse(
          _creditInvoiceLimitController.text.trim(),
        ),
        birthday: _parseDate(_birthdayController.text),
        comments: _commentsController.text.trim(),
        defaultReceiptType: _defaultReceiptType,
        priceTier: _priceTier,
        taxExempt: _taxExempt,
        chargeItbis: _chargeItbis,
        isActive: _isActive,
      ),
    );
  }
}

// ─── Helpers ─────────────────────────────────────────────────────────────────

String _entityTypeLabel(String type) {
  switch (type) {
    case 'person':
      return 'Persona';
    case 'company':
      return 'Empresa';
    case 'government':
      return 'Gubernamental';
    default:
      return type;
  }
}

String _date(DateTime value) {
  final day = value.day.toString().padLeft(2, '0');
  final month = value.month.toString().padLeft(2, '0');
  return '${value.year}-$month-$day';
}

DateTime? _parseDate(String? value) {
  final text = (value ?? '').trim();
  if (text.isEmpty) return null;
  return DateTime.tryParse(text);
}

// ─────────────────────────────────────────────────────────────────────────
// Dropdown de nivel de precio, alimentado por app_settings.sale_price_types.
// Mapeo posicional: índice 0 → tier_1, 1 → tier_2, 2 → tier_3. Más
// 'Detalle' (retail) como base siempre disponible. Valores legados
// ('wholesale', 'vip', etc.) se preservan como opción "(antiguo)".
// ─────────────────────────────────────────────────────────────────────────

const _kPriceTierBase = 'retail';
const _kPriceTierSlots = ['tier_1', 'tier_2', 'tier_3'];

class _PriceTierDropdown extends ConsumerWidget {
  const _PriceTierDropdown({required this.value, required this.onChanged});

  final String value;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settingsAsync = ref.watch(appSettingsProvider);
    final priceTypes = settingsAsync.valueOrNull?.salePriceTypes ?? const [];

    final labels = <String, String>{_kPriceTierBase: 'Detalle'};
    for (var i = 0; i < _kPriceTierSlots.length && i < priceTypes.length; i++) {
      final name = priceTypes[i].toString().trim();
      if (name.isEmpty) continue;
      labels[_kPriceTierSlots[i]] = name;
    }

    if (!labels.containsKey(value)) {
      labels[value] = '$value (antiguo)';
    }

    return DropdownButtonFormField<String>(
      initialValue: value,
      decoration: const InputDecoration(labelText: 'Nivel de precio'),
      items: [
        for (final entry in labels.entries)
          DropdownMenuItem(value: entry.key, child: Text(entry.value)),
      ],
      onChanged: (v) {
        if (v != null) onChanged(v);
      },
    );
  }
}
