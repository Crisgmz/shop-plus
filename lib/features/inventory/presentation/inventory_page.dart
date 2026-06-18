import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show PostgrestException;

import '../../../core/theme/tokens.dart';
import '../../../shared/formatters/formatters.dart';
import '../../../shared/responsive/responsive_layout.dart';
import '../../../shared/widgets/empty_state.dart';
import '../../../shared/widgets/module_page.dart';
import '../../../shared/widgets/role_gate.dart';
import '../../../shared/widgets/ui_custom.dart';
import '../../settings/presentation/app_settings_providers.dart';
import '../data/file_io_helper.dart';
import '../data/inventory_excel_service.dart';
import '../data/inventory_repository.dart';
import 'inventory_providers.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

class InventoryPage extends ConsumerStatefulWidget {
  const InventoryPage({super.key});

  @override
  ConsumerState<InventoryPage> createState() => _InventoryPageState();
}

class _InventoryPageState extends ConsumerState<InventoryPage> {
  final _searchController = TextEditingController();

  /// IDs de productos marcados con el checkbox para borrado masivo.
  final Set<String> _selectedIds = {};

  /// Evita guardar el mismo producto dos veces si el usuario reintenta antes
  /// de que termine el primer guardado (red lenta) — causa de duplicados.
  bool _isSavingProduct = false;

  @override
  void initState() {
    super.initState();
    // Restaurar la selección de productos si el usuario la dejó a medias y
    // navegó a otra sección. Ver [inventorySelectionProvider].
    _selectedIds.addAll(ref.read(inventorySelectionProvider));
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  /// Conserva la selección en el provider tras cada cambio (no en `dispose`,
  /// que no es confiable) para no perderla al navegar a otra sección.
  void _persistSelection() {
    ref.read(inventorySelectionProvider.notifier).state =
        Set<String>.from(_selectedIds);
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

  /// Marca/desmarca todos los productos actualmente filtrados.
  void _toggleSelectAll(List<InventoryProduct> filtered, bool selectAll) {
    setState(() {
      if (selectAll) {
        _selectedIds.addAll(filtered.map((p) => p.id));
      } else {
        _selectedIds.removeAll(filtered.map((p) => p.id));
      }
    });
    _persistSelection();
  }

  @override
  Widget build(BuildContext context) {
    final productsAsync = ref.watch(inventoryProductsProvider);
    final categoriesAsync = ref.watch(inventoryCategoriesProvider);
    final lowStockOnly = ref.watch(inventoryLowStockOnlyProvider);
    final selectedCategoryId = ref.watch(inventorySelectedCategoryProvider);
    final isMobile = ResponsiveLayout.isMobile(context);

    return ModulePage(
      title: 'Inventario',
      description: 'Gestión centralizada de productos y existencias.',
      actions: [
        OutlinedButton.icon(
          onPressed: _refreshInventoryData,
          icon: const Icon(Icons.refresh, size: 18),
          label: const Text('Actualizar'),
        ),
        const SizedBox(width: AppTokens.s8),
        _buildExcelMenu(),
        const SizedBox(width: AppTokens.s8),
        if (ref.watch(roleAccessProvider).canEditPrices)
          FilledButton.icon(
            onPressed: _onCreateProduct,
            icon: const Icon(Icons.add, size: 18),
            label: const Text('Nuevo Producto'),
          ),
      ],
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Filter Bar
          Container(
            decoration: BoxDecoration(
              color: AppTokens.card,
              borderRadius: BorderRadius.circular(AppTokens.radius),
              border: Border.all(color: AppTokens.border),
            ),
            padding: const EdgeInsets.all(AppTokens.s16),
            child: isMobile
                ? Column(
                    children: [
                      _buildSearchField(),
                      const SizedBox(height: AppTokens.s12),
                      _buildCategoryDropdown(categoriesAsync, selectedCategoryId),
                      const SizedBox(height: AppTokens.s12),
                      _buildLowStockToggle(lowStockOnly),
                    ],
                  )
                : Row(
                    children: [
                      Expanded(flex: 3, child: _buildSearchField()),
                      const SizedBox(width: AppTokens.s16),
                      Expanded(
                        flex: 2,
                        child: _buildCategoryDropdown(categoriesAsync, selectedCategoryId),
                      ),
                      const SizedBox(width: AppTokens.s16),
                      _buildLowStockToggle(lowStockOnly),
                    ],
                  ),
          ),
          const SizedBox(height: AppTokens.s24),
          
          // Products List/Table — filtrado y KPIs viven en providers
          // memoizados (inventoryFilteredProductsProvider /
          // inventoryFilteredKpisProvider) para no recalcular en cada
          // keystroke ni en cada rebuild.
          productsAsync.when(
            data: (_) {
              final filtered = ref.watch(inventoryFilteredProductsProvider);
              final kpis = ref.watch(inventoryFilteredKpisProvider);
              final totalCostVal = kpis.totalCost;
              final totalPriceVal = kpis.totalPrice;
              final totalStockVal = kpis.totalStock;

              // Altura del viewport interno para que ListView.builder
              // VIRTUALICE: solo renderiza los items visibles en pantalla
              // + un pequeño buffer. Sin esta altura definida, el listView
              // se mediría entero y volveríamos al problema de renderizar
              // los 5000 productos a la vez.
              final viewportHeight =
                  MediaQuery.of(context).size.height * 0.6;

              final Widget mainContent;
              if (filtered.isEmpty) {
                mainContent = const EmptyStateCard(
                  icon: Icons.inventory_2_outlined,
                  message: 'No se encontraron productos con los filtros aplicados.',
                );
              } else if (isMobile) {
                mainContent = SizedBox(
                  height: viewportHeight,
                  child: ListView.separated(
                    itemCount: filtered.length,
                    // itemExtent permite saltar a cualquier índice sin
                    // medir los anteriores → scroll instantáneo en listas
                    // grandes.
                    separatorBuilder: (_, _) =>
                        const SizedBox(height: AppTokens.s12),
                    itemBuilder: (context, index) => _InventoryProductCard(
                      key: ValueKey(filtered[index].id),
                      product: filtered[index],
                      onEdit: () => _onEditProduct(filtered[index]),
                      onToggle: () => _onToggleActive(filtered[index]),
                    ),
                  ),
                );
              } else {
                final access = ref.watch(roleAccessProvider);
                final canSelect = access.canManageInventoryAdjustments;
                final allSelected = filtered.isNotEmpty &&
                    filtered.every((p) => _selectedIds.contains(p.id));
                final someSelected =
                    filtered.any((p) => _selectedIds.contains(p.id));
                // Tristate: true=todos, null=algunos, false=ninguno.
                final bool? selectAllValue =
                    allSelected ? true : (someSelected ? null : false);
                mainContent = Container(
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
                              'Productos (${filtered.length})',
                              style: const TextStyle(
                                  fontSize: 18, fontWeight: FontWeight.bold),
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
                                icon: const Icon(Icons.delete_outline, size: 18),
                                label: Text('Eliminar (${_selectedIds.length})'),
                              ),
                            ],
                          ],
                        ),
                      ),
                      _ProductRowHeader(
                        showCheckbox: canSelect,
                        selectAllValue: selectAllValue,
                        onSelectAll: (v) =>
                            _toggleSelectAll(filtered, v ?? false),
                      ),
                      SizedBox(
                        height: viewportHeight,
                        child: ListView.builder(
                          itemCount: filtered.length,
                          itemExtent: 56,
                          itemBuilder: (context, index) {
                            final product = filtered[index];
                            return _ProductRow(
                              key: ValueKey(product.id),
                              product: product,
                              canEdit: access.canEditPrices,
                              canDelete: access.canManageInventoryAdjustments,
                              showCheckbox: canSelect,
                              selected: _selectedIds.contains(product.id),
                              onSelectedChanged: (v) =>
                                  _toggleSelected(product.id, v ?? false),
                              onEdit: () => _onEditProduct(product),
                              onHistory: () => _onShowHistory(product),
                              onAdjust: () => _onAdjustStock(product),
                              onDelete: () => _onDelete(product),
                            );
                          },
                        ),
                      ),
                    ],
                  ),
                );
              }

              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _InventoryKpis(
                    totalCostValuation: totalCostVal,
                    totalPriceValuation: totalPriceVal,
                    totalStock: totalStockVal,
                  ),
                  const SizedBox(height: AppTokens.s24),
                  mainContent,
                ],
              );
            },
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (error, _) => ErrorCard(
              message: 'Error al cargar inventario: $error',
              onRetry: _refreshInventoryData,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSearchField() {
    return TextField(
      controller: _searchController,
      onChanged: (v) => ref.read(inventorySearchProvider.notifier).state = v,
      decoration: const InputDecoration(
        hintText: 'Buscar por nombre, SKU...',
        prefixIcon: Icon(Icons.search, size: 18),
      ),
    );
  }

  Widget _buildCategoryDropdown(AsyncValue<List<InventoryCategory>> categoriesAsync, String? selectedId) {
    return categoriesAsync.when(
      data: (categories) => DropdownButtonFormField<String>(
        initialValue: selectedId ?? '',
        decoration: const InputDecoration(labelText: 'Categoría'),
        items: [
          const DropdownMenuItem(value: '', child: Text('Todas las categorías')),
          ...categories.map(
            (c) => DropdownMenuItem(
              value: c.id,
              child: Row(
                children: [
                  if (c.colorHex != null) ...[
                    _CategoryColorDot(colorHex: c.colorHex!),
                    const SizedBox(width: 8),
                  ],
                  Text(c.name),
                ],
              ),
            ),
          ),
        ],
        onChanged: (v) => ref.read(inventorySelectedCategoryProvider.notifier).state = (v == null || v.isEmpty) ? null : v,
      ),
      loading: () => const LinearProgressIndicator(),
      error: (_, _) => const SizedBox.shrink(),
    );
  }

  Widget _buildLowStockToggle(bool value) {
    return FilterChip(
      selected: value,
      label: const Text('Bajo Stock'),
      onSelected: (v) => ref.read(inventoryLowStockOnlyProvider.notifier).state = v,
    );
  }


  Future<void> _refreshInventoryData() async {
    ref.invalidate(inventoryProductsProvider);
    ref.invalidate(inventoryCategoriesProvider);
    await Future.wait([
      ref.read(inventoryProductsProvider.future),
      ref.read(inventoryCategoriesProvider.future),
    ]);
  }

  Future<void> _onCreateProduct() async {
    final categories = await _readCategoriesOrShowError();
    if (categories == null || !mounted) return;

    final input = await showDialog<InventoryProductInput>(
      context: context,
      builder: (_) => _ProductDialog(categories: categories),
    );

    if (input == null || !mounted) return;

    await _saveProduct(input, successMessage: 'Producto creado');
  }

  Future<void> _onEditProduct(InventoryProduct product) async {
    final categories = await _readCategoriesOrShowError();
    if (categories == null || !mounted) return;

    final input = await showDialog<InventoryProductInput>(
      context: context,
      builder: (_) => _ProductDialog(categories: categories, initial: product),
    );

    if (input == null || !mounted) return;

    await _saveProduct(input, successMessage: 'Producto actualizado');
  }

  Future<void> _onAdjustStock(InventoryProduct product) async {
    final result = await showDialog<_StockAdjustResult>(
      context: context,
      builder: (_) => _StockAdjustDialog(product: product),
    );
    if (result == null || !mounted) return;

    final repository = ref.read(inventoryRepositoryProvider);
    try {
      final delta = await repository.adjustStock(
        productId: product.id,
        currentStock: product.stock,
        newStock: result.newStock,
        reason: result.reason,
        notes: result.notes,
      );
      if (!mounted) return;
      ref.invalidate(inventoryProductsProvider);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            delta == 0
                ? 'Sin cambios en el stock'
                : 'Stock ajustado (${delta > 0 ? '+' : ''}${qty(delta)})',
          ),
        ),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('No se pudo ajustar el stock: $error')),
      );
    }
  }

  Future<void> _onToggleActive(InventoryProduct product) async {
    final repository = ref.read(inventoryRepositoryProvider);

    try {
      await repository.setProductActive(
        productId: product.id,
        isActive: !product.isActive,
      );

      if (!mounted) return;

      ref.invalidate(inventoryProductsProvider);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            product.isActive ? 'Producto desactivado' : 'Producto activado',
          ),
        ),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('No se pudo actualizar estado: $error')),
      );
    }
  }

  Future<void> _onDeleteSelected(List<InventoryProduct> filtered) async {
    final selected =
        filtered.where((p) => _selectedIds.contains(p.id)).toList();
    if (selected.isEmpty) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Eliminar productos'),
        content: Text(
          '¿Eliminar ${selected.length} producto(s) seleccionado(s)?\n\n'
          'Los que tengan ventas o compras registradas no se podrán borrar '
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

    final repository = ref.read(inventoryRepositoryProvider);
    var deleted = 0;
    var deactivated = 0;
    var failed = 0;
    for (final product in selected) {
      try {
        await repository.deleteProduct(product.id);
        deleted++;
      } on PostgrestException catch (e) {
        // FK violation = tiene ventas/compras → soft-delete.
        if (e.code == '23503') {
          try {
            await repository.setProductActive(
              productId: product.id,
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
    ref.invalidate(inventoryProductsProvider);
    final parts = <String>[
      if (deleted > 0) '$deleted eliminado(s)',
      if (deactivated > 0) '$deactivated desactivado(s)',
      if (failed > 0) '$failed con error',
    ];
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          parts.isEmpty ? 'Sin cambios.' : parts.join('  ·  '),
        ),
      ),
    );
  }

  Future<void> _onDelete(InventoryProduct product) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Eliminar producto'),
        content: Text(
          '¿Eliminar "${product.name}"?\n\n'
          'Si el producto tiene ventas o compras registradas, no se podrá '
          'borrar y se desactivará en su lugar (queda fuera del POS y de '
          'las listas activas).',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: AppTokens.error),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Eliminar'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    final repository = ref.read(inventoryRepositoryProvider);
    try {
      await repository.deleteProduct(product.id);
      if (!mounted) return;
      ref.invalidate(inventoryProductsProvider);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Producto "${product.name}" eliminado')),
      );
    } on PostgrestException catch (e) {
      // Foreign key violation = el producto tiene ventas/compras. Caemos a
      // soft-delete y avisamos por qué.
      if (e.code == '23503') {
        try {
          await repository.setProductActive(
            productId: product.id,
            isActive: false,
          );
          if (!mounted) return;
          ref.invalidate(inventoryProductsProvider);
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                'Tenía ventas/compras vinculadas. Se desactivó en su lugar.',
              ),
            ),
          );
        } catch (innerError) {
          if (!mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('No se pudo desactivar: $innerError')),
          );
        }
      } else {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('No se pudo eliminar: ${e.message}')),
        );
      }
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('No se pudo eliminar: $error')),
      );
    }
  }

  Future<void> _onShowHistory(InventoryProduct product) async {
    await showDialog(
      context: context,
      builder: (_) => _ProductHistoryDialog(product: product),
    );
  }

  Future<void> _saveProduct(
    InventoryProductInput input, {
    required String successMessage,
  }) async {
    // Guarda contra doble envío (evita insertar el mismo producto 2 veces).
    if (_isSavingProduct) return;

    // Al CREAR (sin id), avisar si ya hay un producto con el mismo SKU,
    // código de barras o nombre. No bloquea: deja crear si el usuario insiste.
    if (input.id == null) {
      final duplicate = _findDuplicateProduct(input);
      if (duplicate != null) {
        final sku = duplicate.sku?.trim();
        final proceed = await _confirmDuplicate(
          title: 'Posible producto duplicado',
          message:
              'Ya existe el producto "${duplicate.name}"'
              '${sku != null && sku.isNotEmpty ? ' (SKU $sku)' : ''}. '
              '¿Crear uno nuevo de todas formas?',
        );
        if (proceed != true || !mounted) return;
      }
    }

    _isSavingProduct = true;
    final repository = ref.read(inventoryRepositoryProvider);

    try {
      await repository.saveProduct(input);
      if (!mounted) return;

      ref.invalidate(inventoryProductsProvider);
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(successMessage)));
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('No se pudo guardar producto: $error')),
      );
    } finally {
      _isSavingProduct = false;
    }
  }

  /// Busca en la lista en memoria un producto que probablemente sea el mismo
  /// que se está por crear: coincide SKU, código de barras o nombre.
  InventoryProduct? _findDuplicateProduct(InventoryProductInput input) {
    final products = ref.read(inventoryProductsProvider).valueOrNull;
    if (products == null) return null;

    final name = input.name.trim().toLowerCase();
    final sku = input.sku?.trim().toLowerCase();
    final barcode = input.barcode?.trim().toLowerCase();

    for (final p in products) {
      if (sku != null && sku.isNotEmpty && p.sku?.trim().toLowerCase() == sku) {
        return p;
      }
      if (barcode != null &&
          barcode.isNotEmpty &&
          p.barcode?.trim().toLowerCase() == barcode) {
        return p;
      }
      if (name.isNotEmpty && p.name.trim().toLowerCase() == name) {
        return p;
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

  Future<List<InventoryCategory>?> _readCategoriesOrShowError() async {
    try {
      return await ref.read(inventoryCategoriesProvider.future);
    } catch (error) {
      if (!mounted) return null;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('No se pudieron cargar categorías: $error')),
      );
      return null;
    }
  }

  Widget _buildExcelMenu() {
    return PopupMenuButton<String>(
      tooltip: 'Documentos',
      position: PopupMenuPosition.under,
      onSelected: (value) {
        switch (value) {
          case 'import':
            _onOpenImportDialog();
            break;
          case 'export':
            _onExportInventory();
            break;
          case 'export_pdf':
            _onExportInventoryPdf();
            break;
        }
      },
      itemBuilder: (_) => const [
        PopupMenuItem(
          value: 'import',
          child: ListTile(
            leading: Icon(Icons.file_upload_outlined),
            title: Text('Importar / Actualizar'),
            contentPadding: EdgeInsets.zero,
          ),
        ),
        PopupMenuItem(
          value: 'export',
          child: ListTile(
            leading: Icon(Icons.file_download_outlined),
            title: Text('Exportar a Excel'),
            contentPadding: EdgeInsets.zero,
          ),
        ),
        PopupMenuItem(
          value: 'export_pdf',
          child: ListTile(
            leading: Icon(Icons.picture_as_pdf_outlined),
            title: Text('Exportar a PDF'),
            contentPadding: EdgeInsets.zero,
          ),
        ),
      ],
      child: OutlinedButton.icon(
        onPressed: null,
        icon: const Icon(Icons.table_chart_outlined, size: 18),
        label: const Text('Excel / PDF'),
        style: OutlinedButton.styleFrom(
          foregroundColor: AppTokens.foreground,
          disabledForegroundColor: AppTokens.foreground,
        ),
      ),
    );
  }

  Future<void> _onOpenImportDialog() async {
    await showDialog<void>(
      context: context,
      builder: (_) => const _ImportInventoryDialog(),
    );
  }

  Future<void> _onExportInventory() async {
    final categories = await _readCategoriesOrShowError();
    if (categories == null || !mounted) return;

    final List<InventoryProduct> products;
    try {
      products = await ref.read(inventoryProductsProvider.future);
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('No se pudieron cargar productos: $error')),
      );
      return;
    }

    if (!mounted) return;
    if (products.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('No hay productos para exportar.'),
        ),
      );
      return;
    }

    try {
      final bytes = InventoryExcelService().buildExport(
        products: products,
        categories: categories,
      );
      final fileName = 'inventario_${_timestamp()}.xlsx';
      final saved = await FileIoHelper.saveBytes(
        bytes: bytes,
        fileName: fileName,
        dialogTitle: 'Guardar inventario',
      );
      if (!mounted) return;
      if (saved) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Inventario exportado (${products.length} productos)'),
          ),
        );
      }
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('No se pudo exportar: $error')),
      );
    }
  }

  String _timestamp() {
    final now = DateTime.now();
    String two(int n) => n.toString().padLeft(2, '0');
    return '${now.year}${two(now.month)}${two(now.day)}_${two(now.hour)}${two(now.minute)}';
  }

  Future<void> _onExportInventoryPdf() async {
    final List<InventoryProduct> products;
    try {
      products = await ref.read(inventoryProductsProvider.future);
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('No se pudieron cargar productos: $error')),
      );
      return;
    }

    if (!mounted) return;
    if (products.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No hay productos para exportar.')),
      );
      return;
    }

    final lowStockOnly = ref.read(inventoryLowStockOnlyProvider);
    final selectedCategoryId = ref.read(inventorySelectedCategoryProvider);
    final query = ref.read(inventorySearchProvider).trim().toLowerCase();

    final filtered = products.where((product) {
      if (lowStockOnly && !product.isLowStock) return false;
      if (selectedCategoryId != null && product.categoryId != selectedCategoryId) {
        return false;
      }
      if (query.isEmpty) return true;
      final searchable = [
        product.name,
        product.sku ?? '',
        product.barcode ?? '',
        product.categoryName ?? '',
      ].join(' ').toLowerCase();
      return searchable.contains(query);
    }).toList();

    if (filtered.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No hay productos filtrados para exportar.')),
      );
      return;
    }

    try {
      final bytes = await _buildInventoryPdf(filtered);
      final fileName = 'inventario_${_timestamp()}.pdf';
      final saved = await FileIoHelper.saveBytes(
        bytes: bytes,
        fileName: fileName,
        dialogTitle: 'Guardar reporte de inventario',
        extension: 'pdf',
      );
      if (!mounted) return;
      if (saved) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Reporte PDF exportado (${filtered.length} productos)'),
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

  Future<Uint8List> _buildInventoryPdf(List<InventoryProduct> products) async {
    final pdf = pw.Document(
      title: 'Reporte de Inventario',
      author: 'Shop+',
    );

    final theme = pw.ThemeData.withFont(
      base: await PdfGoogleFonts.robotoRegular(),
      bold: await PdfGoogleFonts.robotoBold(),
      italic: await PdfGoogleFonts.robotoItalic(),
    );

    final totalCostVal = products.fold<double>(0, (sum, p) => sum + (p.cost * p.stock));
    final totalPriceVal = products.fold<double>(0, (sum, p) => sum + (p.price * p.stock));
    final totalStockVal = products.fold<double>(0, (sum, p) => sum + p.stock);

    final accent = PdfColor.fromInt(0xFF0D6EFD); // AppTokens.primary
    final muted = PdfColor.fromInt(0xFF66798E);  // AppTokens.mutedForeground
    final borderCol = PdfColor.fromInt(0xFFE9ECEF);

    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.letter,
        theme: theme,
        margin: const pw.EdgeInsets.symmetric(horizontal: 36, vertical: 28),
        header: (ctx) {
          return pw.Container(
            margin: const pw.EdgeInsets.only(bottom: 12),
            padding: const pw.EdgeInsets.only(bottom: 8),
            decoration: pw.BoxDecoration(
              border: pw.Border(
                bottom: pw.BorderSide(color: accent, width: 1.5),
              ),
            ),
            child: pw.Row(
              mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
              children: [
                pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    pw.Text(
                      'Shop+',
                      style: pw.TextStyle(
                        fontSize: 14,
                        fontWeight: pw.FontWeight.bold,
                      ),
                    ),
                    pw.Text(
                      'Gestión de Inventario Centralizada',
                      style: pw.TextStyle(fontSize: 9, color: muted),
                    ),
                  ],
                ),
                pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.end,
                  children: [
                    pw.Text(
                      'REPORTE DE INVENTARIO',
                      style: pw.TextStyle(
                        fontSize: 16,
                        fontWeight: pw.FontWeight.bold,
                        color: accent,
                      ),
                    ),
                    pw.Text(
                      'Generado el: ${_fmtDateTime(DateTime.now())}',
                      style: pw.TextStyle(fontSize: 9, color: muted),
                    ),
                  ],
                ),
              ],
            ),
          );
        },
        footer: (ctx) {
          return pw.Container(
            margin: const pw.EdgeInsets.only(top: 12),
            padding: const pw.EdgeInsets.only(top: 6),
            decoration: pw.BoxDecoration(
              border: pw.Border(
                top: pw.BorderSide(color: muted, width: 0.5),
              ),
            ),
            child: pw.Row(
              children: [
                pw.Text(
                  'Shop+ · Reporte de Inventario',
                  style: pw.TextStyle(fontSize: 8, color: muted),
                ),
                pw.Spacer(),
                pw.Text(
                  'Página ${ctx.pageNumber} de ${ctx.pagesCount}',
                  style: pw.TextStyle(fontSize: 8, color: muted),
                ),
              ],
            ),
          );
        },
        build: (ctx) {
          return [
            // KPI summary boxes
            pw.Container(
              padding: const pw.EdgeInsets.all(10),
              decoration: pw.BoxDecoration(
                color: PdfColor.fromInt(0xFFF8F9FA),
                borderRadius: pw.BorderRadius.circular(4),
                border: pw.Border.all(color: borderCol, width: 0.5),
              ),
              margin: const pw.EdgeInsets.only(bottom: 16),
              child: pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceAround,
                children: [
                  _buildPdfKpi('Valor Total (Costo)', money(totalCostVal), accent),
                  _buildPdfKpi('Valor Total (Venta)', money(totalPriceVal), accent),
                  _buildPdfKpi('Existencias Totales', qty(totalStockVal), accent),
                  _buildPdfKpi('Productos', products.length.toString(), accent),
                ],
              ),
            ),
            
            // Inventory Table
            pw.Table(
              border: pw.TableBorder.all(color: borderCol, width: 0.5),
              columnWidths: const {
                0: pw.FlexColumnWidth(3), // Producto
                1: pw.FlexColumnWidth(1.5), // SKU
                2: pw.FlexColumnWidth(2), // Categoría
                3: pw.FlexColumnWidth(1.2), // Costo
                4: pw.FlexColumnWidth(1.2), // Precio
                5: pw.FlexColumnWidth(1), // Stock
                6: pw.FlexColumnWidth(1.5), // Total Costo
              },
              children: [
                // Header
                pw.TableRow(
                  decoration: pw.BoxDecoration(color: accent),
                  children: [
                    _buildPdfTableHeaderCell('Producto'),
                    _buildPdfTableHeaderCell('SKU'),
                    _buildPdfTableHeaderCell('Categoría'),
                    _buildPdfTableHeaderCell('Costo', align: pw.TextAlign.right),
                    _buildPdfTableHeaderCell('Precio', align: pw.TextAlign.right),
                    _buildPdfTableHeaderCell('Stock', align: pw.TextAlign.right),
                    _buildPdfTableHeaderCell('Val. Costo', align: pw.TextAlign.right),
                  ],
                ),
                // Rows
                ...List.generate(products.length, (index) {
                  final p = products[index];
                  final valCosto = p.cost * p.stock;
                  final isEven = index % 2 == 0;
                  final bg = isEven ? PdfColors.white : PdfColor.fromInt(0xFFF8F9FA);

                  return pw.TableRow(
                    decoration: pw.BoxDecoration(color: bg),
                    children: [
                      _buildPdfTableCellCell(p.name, isBold: true),
                      _buildPdfTableCellCell(p.sku ?? '-'),
                      _buildPdfTableCellCell(p.categoryName ?? '-'),
                      _buildPdfTableCellCell(money(p.cost), align: pw.TextAlign.right),
                      _buildPdfTableCellCell(money(p.price), align: pw.TextAlign.right),
                      _buildPdfTableCellCell(qty(p.stock), align: pw.TextAlign.right, isAlert: p.isLowStock),
                      _buildPdfTableCellCell(money(valCosto), align: pw.TextAlign.right),
                    ],
                  );
                }),
              ],
            ),
          ];
        },
      ),
    );

    return pdf.save();
  }

  pw.Widget _buildPdfKpi(String label, String value, PdfColor color) {
    return pw.Column(
      mainAxisSize: pw.MainAxisSize.min,
      crossAxisAlignment: pw.CrossAxisAlignment.center,
      children: [
        pw.Text(
          label,
          style: pw.TextStyle(
            fontSize: 8,
            color: PdfColor.fromInt(0xFF66798E),
            fontWeight: pw.FontWeight.bold,
          ),
        ),
        pw.SizedBox(height: 3),
        pw.Text(
          value,
          style: pw.TextStyle(
            fontSize: 12,
            fontWeight: pw.FontWeight.bold,
            color: color,
          ),
        ),
      ],
    );
  }

  pw.Widget _buildPdfTableHeaderCell(String text, {pw.TextAlign align = pw.TextAlign.left}) {
    return pw.Padding(
      padding: const pw.EdgeInsets.symmetric(horizontal: 4, vertical: 5),
      child: pw.Text(
        text,
        style: pw.TextStyle(
          fontSize: 8,
          fontWeight: pw.FontWeight.bold,
          color: PdfColors.white,
        ),
        textAlign: align,
      ),
    );
  }

  pw.Widget _buildPdfTableCellCell(
    String text, {
    pw.TextAlign align = pw.TextAlign.left,
    bool isBold = false,
    bool isAlert = false,
  }) {
    final alertColor = PdfColor.fromInt(0xFFDC3545); // AppTokens.error
    return pw.Padding(
      padding: const pw.EdgeInsets.symmetric(horizontal: 4, vertical: 4),
      child: pw.Text(
        text,
        style: pw.TextStyle(
          fontSize: 8,
          fontWeight: isBold || isAlert ? pw.FontWeight.bold : pw.FontWeight.normal,
          color: isAlert ? alertColor : PdfColor.fromInt(0xFF212529),
        ),
        textAlign: align,
      ),
    );
  }

  String _fmtDate(DateTime d) {
    return '${d.day.toString().padLeft(2, '0')}/'
        '${d.month.toString().padLeft(2, '0')}/'
        '${d.year}';
  }

  String _fmtDateTime(DateTime d) {
    final local = d.isUtc ? d.toLocal() : d;
    return '${_fmtDate(local)} '
        '${local.hour.toString().padLeft(2, '0')}:'
        '${local.minute.toString().padLeft(2, '0')}';
  }
}

/// Header de la tabla virtualizada de productos (desktop). Se mantiene
/// fijo arriba del ListView.builder que renderiza las filas; el header
/// no se duplica por fila como en DataTable, así que es prácticamente
/// gratis.
class _ProductRowHeader extends StatelessWidget {
  const _ProductRowHeader({
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
          horizontal: AppTokens.s16, vertical: AppTokens.s10),
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
          const Expanded(flex: 3, child: _ColumnLabel('Producto')),
          Expanded(flex: 2, child: _ColumnLabel('SKU')),
          Expanded(flex: 2, child: _ColumnLabel('Referencia')),
          Expanded(flex: 2, child: _ColumnLabel('Categoría')),
          Expanded(
              flex: 2,
              child:
                  _ColumnLabel('Costo', align: TextAlign.right)),
          Expanded(
              flex: 2,
              child:
                  _ColumnLabel('Precio', align: TextAlign.right)),
          Expanded(
              flex: 2,
              child:
                  _ColumnLabel('Stock', align: TextAlign.right)),
          const SizedBox(width: AppTokens.s16),
          Expanded(flex: 2, child: _ColumnLabel('Estado')),
          const SizedBox(
            width: 180,
            child: _ColumnLabel('Acciones', align: TextAlign.center),
          ),
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

/// Fila virtualizada de la tabla de productos (desktop). Se usa con
/// `ListView.builder(itemExtent: 56)` para que Flutter virtualice sin
/// medir cada fila.
class _ProductRow extends StatelessWidget {
  const _ProductRow({
    super.key,
    required this.product,
    required this.canEdit,
    required this.canDelete,
    required this.onEdit,
    required this.onHistory,
    required this.onAdjust,
    required this.onDelete,
    this.showCheckbox = false,
    this.selected = false,
    this.onSelectedChanged,
  });

  final InventoryProduct product;
  final bool canEdit;
  final bool canDelete;
  final VoidCallback onEdit;
  final VoidCallback onHistory;
  final VoidCallback onAdjust;
  final VoidCallback onDelete;
  final bool showCheckbox;
  final bool selected;
  final ValueChanged<bool?>? onSelectedChanged;

  @override
  Widget build(BuildContext context) {
    final lowStock = product.isLowStock;
    return Container(
      decoration: BoxDecoration(
        color: selected ? AppTokens.primary.withValues(alpha: 0.06) : null,
        border: const Border(
          top: BorderSide(color: AppTokens.border),
        ),
      ),
      padding: const EdgeInsets.symmetric(horizontal: AppTokens.s16),
      child: Row(
        children: [
          if (showCheckbox)
            SizedBox(
              width: 40,
              child: Checkbox(
                value: selected,
                onChanged: onSelectedChanged,
              ),
            ),
          Expanded(
            flex: 3,
            child: Text(
              product.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: lowStock ? AppTokens.error : null,
              ),
            ),
          ),
          Expanded(
            flex: 2,
            child: Text(
              product.sku ?? '-',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 13),
            ),
          ),
          Expanded(
            flex: 2,
            child: Text(
              product.internalCode ?? '-',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 13),
            ),
          ),
          Expanded(
            flex: 2,
            child: Text(
              product.categoryName ?? '-',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 13),
            ),
          ),
          Expanded(
            flex: 2,
            child: Text(
              money(product.cost),
              textAlign: TextAlign.right,
              style: const TextStyle(
                fontSize: 13,
                color: AppTokens.mutedForeground,
              ),
            ),
          ),
          Expanded(
            flex: 2,
            child: Text(
              money(product.price),
              textAlign: TextAlign.right,
              style: const TextStyle(fontSize: 13),
            ),
          ),
          Expanded(
            flex: 2,
            child: Text(
              qty(product.stock),
              textAlign: TextAlign.right,
              style: TextStyle(
                fontSize: 13,
                color: lowStock ? AppTokens.error : null,
                fontWeight: lowStock ? FontWeight.bold : null,
              ),
            ),
          ),
          const SizedBox(width: AppTokens.s16),
          Expanded(
            flex: 2,
            child: Align(
              alignment: Alignment.centerLeft,
              child: StatusBadge(
                label: product.isActive ? 'Activo' : 'Inactivo',
                status: product.isActive ? 'active' : 'inactive',
              ),
            ),
          ),
          SizedBox(
            width: 180,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (canEdit)
                  IconButton(
                    tooltip: 'Editar',
                    icon: const Icon(Icons.edit_outlined, size: 20),
                    onPressed: onEdit,
                    visualDensity: VisualDensity.compact,
                  ),
                if (canDelete)
                  IconButton(
                    tooltip: 'Ajustar stock',
                    icon: const Icon(Icons.tune_rounded, size: 20),
                    onPressed: onAdjust,
                    visualDensity: VisualDensity.compact,
                  ),
                IconButton(
                  tooltip: 'Historial',
                  icon: const Icon(Icons.history_rounded, size: 20),
                  onPressed: onHistory,
                  visualDensity: VisualDensity.compact,
                ),
                if (canDelete)
                  IconButton(
                    tooltip: 'Eliminar',
                    icon: const Icon(
                      Icons.delete_outline,
                      size: 20,
                      color: AppTokens.error,
                    ),
                    onPressed: onDelete,
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

/// Mobile card for a single product.
class _InventoryProductCard extends StatelessWidget {
  const _InventoryProductCard({
    super.key,
    required this.product,
    required this.onEdit,
    required this.onToggle,
  });

  final InventoryProduct product;
  final VoidCallback onEdit;
  final VoidCallback onToggle;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(AppTokens.s16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    product.name,
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 16,
                      color: product.isLowStock ? AppTokens.error : null,
                    ),
                  ),
                ),
                StatusBadge(
                  label: product.isActive ? 'Activo' : 'Inactivo',
                  status: product.isActive ? 'active' : 'inactive',
                ),
              ],
            ),
            const SizedBox(height: AppTokens.s8),
            Text(
              'SKU: ${product.sku ?? '-'} · ${product.categoryName ?? 'Sin categoría'}',
              style: const TextStyle(color: AppTokens.mutedForeground, fontSize: 13),
            ),
            const Divider(height: AppTokens.s24),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                _buildInfo('Precio', money(product.price)),
                _buildInfo('Stock', qty(product.stock), isBad: product.isLowStock),
              ],
            ),
            const SizedBox(height: AppTokens.s16),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                IconButton(
                  icon: const Icon(Icons.edit_outlined, size: 20),
                  onPressed: onEdit,
                ),
                IconButton(
                  icon: Icon(
                    product.isActive ? Icons.block : Icons.check_circle_outline,
                    size: 20,
                    color: product.isActive ? AppTokens.error : AppTokens.success,
                  ),
                  onPressed: onToggle,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildInfo(String label, String value, {bool isBad = false}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: const TextStyle(fontSize: 12, color: AppTokens.mutedForeground)),
        Text(
          value,
          style: TextStyle(
            fontWeight: FontWeight.bold,
            color: isBad ? AppTokens.error : null,
          ),
        ),
      ],
    );
  }
}

class _StockAdjustResult {
  const _StockAdjustResult({
    required this.newStock,
    this.reason,
    this.notes,
  });

  final double newStock;
  final String? reason;
  final String? notes;
}

/// Diálogo para ajustar el stock físico de un producto. El usuario ingresa el
/// nuevo conteo y el sistema registra un movimiento de inventario con la
/// diferencia (el backend recalcula el stock vía trigger).
class _StockAdjustDialog extends StatefulWidget {
  const _StockAdjustDialog({required this.product});

  final InventoryProduct product;

  @override
  State<_StockAdjustDialog> createState() => _StockAdjustDialogState();
}

class _StockAdjustDialogState extends State<_StockAdjustDialog> {
  late final TextEditingController _stockController;
  final _notesController = TextEditingController();
  String _reason = 'Conteo físico';

  static const _reasons = [
    'Conteo físico',
    'Mercancía dañada',
    'Producto vencido',
    'Merma',
    'Devolución',
    'Otro',
  ];

  @override
  void initState() {
    super.initState();
    _stockController =
        TextEditingController(text: qty(widget.product.stock));
  }

  @override
  void dispose() {
    _stockController.dispose();
    _notesController.dispose();
    super.dispose();
  }

  double? get _newStock => double.tryParse(_stockController.text.trim());

  @override
  Widget build(BuildContext context) {
    final current = widget.product.stock;
    final next = _newStock;
    final delta = next == null ? null : next - current;

    return AlertDialog(
      title: const Text('Ajustar stock'),
      content: SizedBox(
        width: 380,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              widget.product.name,
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: AppTokens.s4),
            Text(
              'Stock actual: ${qty(current)}',
              style: const TextStyle(color: AppTokens.mutedForeground),
            ),
            const SizedBox(height: AppTokens.s16),
            TextField(
              controller: _stockController,
              autofocus: true,
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
              decoration: const InputDecoration(
                labelText: 'Nuevo stock (conteo físico)',
              ),
              onChanged: (_) => setState(() {}),
            ),
            const SizedBox(height: AppTokens.s8),
            if (delta != null && delta != 0)
              Text(
                'Diferencia: ${delta > 0 ? '+' : ''}${qty(delta)}',
                style: TextStyle(
                  fontWeight: FontWeight.w600,
                  color: delta > 0 ? AppTokens.success : AppTokens.error,
                ),
              ),
            const SizedBox(height: AppTokens.s12),
            DropdownButtonFormField<String>(
              initialValue: _reason,
              decoration: const InputDecoration(labelText: 'Motivo'),
              items: _reasons
                  .map((r) => DropdownMenuItem(value: r, child: Text(r)))
                  .toList(growable: false),
              onChanged: (v) => setState(() => _reason = v ?? 'Conteo físico'),
            ),
            const SizedBox(height: AppTokens.s12),
            TextField(
              controller: _notesController,
              decoration: const InputDecoration(
                labelText: 'Notas (opcional)',
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancelar'),
        ),
        FilledButton(
          onPressed: (next == null || delta == 0)
              ? null
              : () => Navigator.of(context).pop(
                    _StockAdjustResult(
                      newStock: next,
                      reason: _reason,
                      notes: _notesController.text,
                    ),
                  ),
          child: const Text('Guardar ajuste'),
        ),
      ],
    );
  }
}

class _ProductDialog extends ConsumerStatefulWidget {
  const _ProductDialog({required this.categories, this.initial});

  final List<InventoryCategory> categories;
  final InventoryProduct? initial;

  @override
  ConsumerState<_ProductDialog> createState() => _ProductDialogState();
}

class _ProductDialogState extends ConsumerState<_ProductDialog> {
  final _formKey = GlobalKey<FormState>();

  late final TextEditingController _nameController;
  late final TextEditingController _skuController;
  late final TextEditingController _barcodeController;
  late final TextEditingController _internalCodeController;
  late final TextEditingController _unitController;
  late final TextEditingController _priceController;
  late final TextEditingController _costController;
  late final TextEditingController _stockController;
  late final TextEditingController _minStockController;
  late final TextEditingController _taxController;
  late final TextEditingController _brandController;
  late final TextEditingController _modelController;
  late final TextEditingController _notesController;
  late final TextEditingController _imageUrlController;
  final TextEditingController _imeiController = TextEditingController();
  final List<String> _imeis = [];
  /// Controllers de los 10 tiers de precio. Cada índice 0..9 corresponde al
  /// tier 1..10. Si el tier no está nombrado en app_settings.sale_price_types,
  /// el `_PriceTierFields` no renderiza ese input.
  late final List<TextEditingController> _priceTierControllers;

  String? _categoryId;
  bool _isActive = true;
  bool _isService = false;
  bool _isTaxExempt = false;
  bool _trackInventory = true;
  bool _uploadingImage = false;

  @override
  void initState() {
    super.initState();
    final product = widget.initial;

    _nameController = TextEditingController(text: product?.name ?? '');
    _skuController = TextEditingController(text: product?.sku ?? '');
    _barcodeController = TextEditingController(text: product?.barcode ?? '');
    _internalCodeController = TextEditingController(text: product?.internalCode ?? '');
    _unitController = TextEditingController(text: product?.unit ?? 'unidad');
    _priceController = TextEditingController(
      text: product == null ? '' : product.price.toString(),
    );
    _costController = TextEditingController(
      text: product == null ? '0' : product.cost.toString(),
    );
    _stockController = TextEditingController(
      text: product == null ? '0' : product.stock.toString(),
    );
    _minStockController = TextEditingController(
      text: product == null ? '0' : product.minStock.toString(),
    );
    _taxController = TextEditingController(
      text: product == null ? '18' : product.taxRate.toString(),
    );
    _brandController = TextEditingController(text: product?.brand ?? '');
    _modelController = TextEditingController(text: product?.model ?? '');
    _notesController = TextEditingController(text: product?.notes ?? '');
    _imageUrlController = TextEditingController(text: product?.imageUrl ?? '');
    _priceTierControllers = List.generate(
      10,
      (i) => TextEditingController(
        text: product?.priceTier(i + 1)?.toString() ?? '0',
      ),
    );

    _categoryId = product?.categoryId;
    _isActive = product?.isActive ?? true;
    _isService = product?.isService ?? false;
    _isTaxExempt = product?.isTaxExempt ?? false;
    _trackInventory = product?.trackInventory ?? true;
    _imeis.addAll(product?.imeis ?? const <String>[]);
  }

  void _addImei() {
    final value = _imeiController.text.trim();
    if (value.isEmpty || _imeis.contains(value)) {
      _imeiController.clear();
      return;
    }
    setState(() {
      _imeis.add(value);
      _imeiController.clear();
    });
  }

  @override
  void dispose() {
    _nameController.dispose();
    _skuController.dispose();
    _barcodeController.dispose();
    _internalCodeController.dispose();
    _unitController.dispose();
    _priceController.dispose();
    _costController.dispose();
    _stockController.dispose();
    _minStockController.dispose();
    _taxController.dispose();
    _brandController.dispose();
    _modelController.dispose();
    _notesController.dispose();
    _imageUrlController.dispose();
    _imeiController.dispose();
    for (final ctrl in _priceTierControllers) {
      ctrl.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isMobile = ResponsiveLayout.isMobile(context);

    return AlertDialog(
      title: Text(
        widget.initial == null ? 'Nuevo producto' : 'Editar producto',
      ),
      content: SizedBox(
        width: isMobile ? double.maxFinite : 560,
        child: Form(
          key: _formKey,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextFormField(
                  controller: _nameController,
                  decoration: const InputDecoration(labelText: 'Nombre'),
                  validator: (value) {
                    if (value == null || value.trim().isEmpty) {
                      return 'Ingresa el nombre';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 10),
                if (isMobile) ...[
                  TextFormField(
                    controller: _skuController,
                    decoration: const InputDecoration(labelText: 'SKU'),
                  ),
                  const SizedBox(height: 10),
                  TextFormField(
                    controller: _barcodeController,
                    decoration: const InputDecoration(
                      labelText: 'Código de barra',
                    ),
                  ),
                ] else
                  Row(
                    children: [
                      Expanded(
                        child: TextFormField(
                          controller: _skuController,
                          decoration: const InputDecoration(labelText: 'SKU'),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: TextFormField(
                          controller: _barcodeController,
                          decoration: const InputDecoration(
                            labelText: 'Código de barra',
                          ),
                        ),
                      ),
                    ],
                  ),
                const SizedBox(height: 10),
                TextFormField(
                  controller: _internalCodeController,
                  decoration: const InputDecoration(labelText: 'Código interno'),
                ),
                const SizedBox(height: 10),
                // IMEI: agregar uno o varios (para celulares/dispositivos).
                Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _imeiController,
                        decoration: InputDecoration(
                          labelText: _imeis.isEmpty
                              ? 'IMEI'
                              : 'IMEI (${_imeis.length} agregado'
                                  '${_imeis.length == 1 ? '' : 's'})',
                          hintText: 'Escribe un IMEI y presiona +',
                        ),
                        onSubmitted: (_) => _addImei(),
                      ),
                    ),
                    const SizedBox(width: 6),
                    IconButton(
                      tooltip: 'Agregar IMEI',
                      icon: const Icon(Icons.add_circle, color: AppTokens.primary),
                      onPressed: _addImei,
                    ),
                  ],
                ),
                if (_imeis.isNotEmpty) ...[
                  const SizedBox(height: 6),
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: [
                      for (final imei in _imeis)
                        Chip(
                          label: Text(imei,
                              style: const TextStyle(fontSize: 12)),
                          onDeleted: () => setState(() => _imeis.remove(imei)),
                          deleteIcon: const Icon(Icons.close, size: 16),
                          materialTapTargetSize:
                              MaterialTapTargetSize.shrinkWrap,
                          visualDensity: VisualDensity.compact,
                        ),
                    ],
                  ),
                ],
                const SizedBox(height: 10),
                DropdownButtonFormField<String>(
                  initialValue: _categoryId ?? '',
                  decoration: const InputDecoration(labelText: 'Categoría'),
                  items: [
                    const DropdownMenuItem<String>(
                      value: '',
                      child: Text('Sin categoría'),
                    ),
                    ...widget.categories.map(
                      (category) => DropdownMenuItem<String>(
                        value: category.id,
                        child: Row(
                          children: [
                            if (category.colorHex != null) ...[
                              _CategoryColorDot(colorHex: category.colorHex!),
                              const SizedBox(width: 8),
                            ],
                            Text(category.name),
                          ],
                        ),
                      ),
                    ),
                  ],
                  onChanged: (value) => setState(
                    () => _categoryId = (value == null || value.isEmpty)
                        ? null
                        : value,
                  ),
                ),
                const SizedBox(height: 10),
                _formRow(isMobile, [
                  TextFormField(
                    controller: _brandController,
                    decoration: const InputDecoration(labelText: 'Marca'),
                  ),
                  TextFormField(
                    controller: _modelController,
                    decoration: const InputDecoration(labelText: 'Modelo'),
                  ),
                ]),
                const SizedBox(height: 10),
                _formRow(isMobile, [
                  TextFormField(
                    controller: _priceController,
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    decoration: const InputDecoration(labelText: 'Precio'),
                    validator: (value) {
                      final parsed = double.tryParse(value ?? '');
                      if (parsed == null || parsed < 0) {
                        return 'Precio inválido';
                      }
                      return null;
                    },
                  ),
                  TextFormField(
                    controller: _costController,
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    decoration: const InputDecoration(labelText: 'Costo'),
                    validator: (value) {
                      final parsed = double.tryParse(value ?? '');
                      if (parsed == null || parsed < 0) {
                        return 'Costo inválido';
                      }
                      return null;
                    },
                  ),
                ]),
                const SizedBox(height: 10),
                _PriceTierFields(
                  isMobile: isMobile,
                  controllers: _priceTierControllers,
                ),
                const SizedBox(height: 10),
                _formRow(isMobile, [
                  TextFormField(
                    controller: _stockController,
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    decoration: const InputDecoration(labelText: 'Stock'),
                    validator: (value) {
                      final parsed = double.tryParse(value ?? '');
                      if (parsed == null) return 'Stock inválido';
                      return null;
                    },
                  ),
                  TextFormField(
                    controller: _minStockController,
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    decoration: const InputDecoration(
                      labelText: 'Stock mínimo',
                    ),
                    validator: (value) {
                      final parsed = double.tryParse(value ?? '');
                      if (parsed == null || parsed < 0) {
                        return 'Mínimo inválido';
                      }
                      return null;
                    },
                  ),
                ]),
                const SizedBox(height: 10),
                _formRow(isMobile, [
                  TextFormField(
                    controller: _taxController,
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    decoration: const InputDecoration(labelText: 'ITBIS %'),
                    validator: (value) {
                      final parsed = double.tryParse(value ?? '');
                      if (parsed == null || parsed < 0 || parsed > 100) {
                        return 'Impuesto inválido';
                      }
                      return null;
                    },
                  ),
                  TextFormField(
                    controller: _unitController,
                    decoration: const InputDecoration(labelText: 'Unidad'),
                    validator: (value) {
                      if (value == null || value.trim().isEmpty) {
                        return 'Unidad requerida';
                      }
                      return null;
                    },
                  ),
                ]),
                const SizedBox(height: 10),
                _ProductImagePicker(
                  controller: _imageUrlController,
                  uploading: _uploadingImage,
                  onPick: _pickAndUploadImage,
                  onClear: () =>
                      setState(() => _imageUrlController.text = ''),
                ),
                const SizedBox(height: 10),
                TextFormField(
                  controller: _notesController,
                  decoration: const InputDecoration(labelText: 'Notas'),
                  maxLines: 2,
                  minLines: 1,
                ),
                const SizedBox(height: 8),
                SwitchListTile(
                  value: _isActive,
                  onChanged: (value) => setState(() => _isActive = value),
                  title: const Text('Activo'),
                  contentPadding: EdgeInsets.zero,
                ),
                SwitchListTile(
                  value: _isService,
                  onChanged: (value) => setState(() {
                    _isService = value;
                    if (value) _trackInventory = false;
                  }),
                  title: const Text('Es servicio'),
                  subtitle: const Text('No lleva control de inventario físico'),
                  contentPadding: EdgeInsets.zero,
                ),
                SwitchListTile(
                  value: _isTaxExempt,
                  onChanged: (value) => setState(() => _isTaxExempt = value),
                  title: const Text('Exento de ITBIS'),
                  contentPadding: EdgeInsets.zero,
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

  /// On mobile, stack fields vertically; on desktop, side-by-side.
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

  void _submit() {
    if (!_formKey.currentState!.validate()) return;

    final input = InventoryProductInput(
      id: widget.initial?.id,
      name: _nameController.text,
      sku: _skuController.text,
      barcode: _barcodeController.text,
      internalCode: _internalCodeController.text,
      categoryId: _categoryId,
      unit: _unitController.text,
      cost: double.parse(_costController.text),
      price: double.parse(_priceController.text),
      taxRate: double.parse(_taxController.text),
      stock: double.parse(_stockController.text),
      minStock: double.parse(_minStockController.text),
      isActive: _isActive,
      brand: _brandController.text,
      model: _modelController.text,
      notes: _notesController.text,
      imageUrl: _imageUrlController.text,
      isService: _isService,
      isTaxExempt: _isTaxExempt,
      trackInventory: _trackInventory,
      imeis: List<String>.from(_imeis),
      priceTier1: _parseTier(_priceTierControllers[0].text),
      priceTier2: _parseTier(_priceTierControllers[1].text),
      priceTier3: _parseTier(_priceTierControllers[2].text),
      priceTier4: _parseTier(_priceTierControllers[3].text),
      priceTier5: _parseTier(_priceTierControllers[4].text),
      priceTier6: _parseTier(_priceTierControllers[5].text),
      priceTier7: _parseTier(_priceTierControllers[6].text),
      priceTier8: _parseTier(_priceTierControllers[7].text),
      priceTier9: _parseTier(_priceTierControllers[8].text),
      priceTier10: _parseTier(_priceTierControllers[9].text),
    );

    Navigator.of(context).pop(input);
  }

  double? _parseTier(String text) {
    final trimmed = text.trim();
    if (trimmed.isEmpty) return null;
    return double.tryParse(trimmed);
  }

  Future<void> _pickAndUploadImage() async {
    if (_uploadingImage) return;
    final picked = await FileIoHelper.pickImage();
    if (picked == null || !mounted) return;

    setState(() => _uploadingImage = true);
    try {
      final repo = ref.read(inventoryRepositoryProvider);
      final url = await repo.uploadProductImage(
        bytes: picked.bytes,
        extension: picked.extension,
      );
      if (!mounted) return;
      setState(() => _imageUrlController.text = url);
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('No se pudo subir la imagen: $error')),
      );
    } finally {
      if (mounted) setState(() => _uploadingImage = false);
    }
  }
}

class _ProductImagePicker extends StatelessWidget {
  const _ProductImagePicker({
    required this.controller,
    required this.uploading,
    required this.onPick,
    required this.onClear,
  });

  final TextEditingController controller;
  final bool uploading;
  final VoidCallback onPick;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: controller,
      builder: (context, _) {
        final url = controller.text.trim();
        final hasImage = url.isNotEmpty;

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Imagen del producto',
              style: Theme.of(context).textTheme.bodyMedium,
            ),
            const SizedBox(height: 6),
            Row(
              children: [
                Container(
                  width: 72,
                  height: 72,
                  decoration: BoxDecoration(
                    color: AppTokens.muted,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: AppTokens.border),
                  ),
                  clipBehavior: Clip.antiAlias,
                  child: hasImage
                      ? Image.network(
                          url,
                          fit: BoxFit.cover,
                          cacheWidth: 144,
                          cacheHeight: 144,
                          errorBuilder: (_, _, _) => const Icon(
                            Icons.broken_image_outlined,
                            color: AppTokens.mutedForeground,
                          ),
                        )
                      : const Icon(
                          Icons.image_outlined,
                          color: AppTokens.mutedForeground,
                        ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      OutlinedButton.icon(
                        onPressed: uploading ? null : onPick,
                        icon: uploading
                            ? const SizedBox(
                                width: 14,
                                height: 14,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              )
                            : const Icon(Icons.upload_outlined, size: 18),
                        label: Text(
                          uploading
                              ? 'Subiendo…'
                              : (hasImage
                                  ? 'Cambiar imagen'
                                  : 'Seleccionar imagen'),
                        ),
                      ),
                      if (hasImage)
                        TextButton.icon(
                          onPressed: uploading ? null : onClear,
                          icon: const Icon(Icons.close, size: 16),
                          label: const Text('Quitar'),
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ],
        );
      },
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────
// Campos de precio por nivel: etiquetas vienen de app_settings.sale_price_types.
// Un slot se oculta si no tiene nombre configurado y el producto tampoco
// tiene valor guardado en ese tier.
// ─────────────────────────────────────────────────────────────────────────

class _PriceTierFields extends ConsumerWidget {
  const _PriceTierFields({
    required this.isMobile,
    required this.controllers,
  });

  final bool isMobile;

  /// Lista de 10 controllers (uno por cada tier 1..10). Se renderiza solo
  /// el subconjunto que tiene nombre configurado en app_settings.sale_price_types.
  final List<TextEditingController> controllers;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final priceTypes =
        ref.watch(appSettingsProvider).valueOrNull?.salePriceTypes ?? const [];

    final maxTiers = controllers.length; // 10
    final rows = <Widget>[];
    for (var i = 0; i < maxTiers; i++) {
      final hasName = i < priceTypes.length &&
          priceTypes[i].toString().trim().isNotEmpty;
      if (!hasName) continue;
      final label = priceTypes[i].toString();
      rows.add(
        Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: TextFormField(
            controller: controllers[i],
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: InputDecoration(labelText: label),
            validator: (value) {
              if (value == null || value.trim().isEmpty) return null;
              final parsed = double.tryParse(value);
              if (parsed == null || parsed < 0) return 'Precio inválido';
              return null;
            },
          ),
        ),
      );
    }

    if (rows.isEmpty) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: rows,
    );
  }
}

/// Small colored circle shown next to category names when a color_hex is set.
class _CategoryColorDot extends StatelessWidget {
  const _CategoryColorDot({required this.colorHex});

  final String colorHex;

  @override
  Widget build(BuildContext context) {
    final color = _parseHex(colorHex);
    if (color == null) return const SizedBox.shrink();
    return Container(
      width: 10,
      height: 10,
      decoration: BoxDecoration(color: color, shape: BoxShape.circle),
    );
  }

  static Color? _parseHex(String hex) {
    final cleaned = hex.replaceAll('#', '');
    if (cleaned.length != 6 && cleaned.length != 8) return null;
    final value = int.tryParse(
      cleaned.length == 6 ? 'FF$cleaned' : cleaned,
      radix: 16,
    );
    return value == null ? null : Color(value);
  }
}

/// Diálogo de 2 pasos para importar / actualizar inventario por Excel.
///
/// Paso 1: descargar plantilla (artículos nuevos = vacía, o existentes =
/// inventario actual pre-llenado para editar). Paso 2: subir el archivo
/// lleno; la SKU decide si cada fila se crea o se actualiza.
class _ImportInventoryDialog extends ConsumerStatefulWidget {
  const _ImportInventoryDialog();

  @override
  ConsumerState<_ImportInventoryDialog> createState() =>
      _ImportInventoryDialogState();
}

class _ImportInventoryDialogState
    extends ConsumerState<_ImportInventoryDialog> {
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
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  Future<List<InventoryCategory>?> _categories() async {
    try {
      return await ref.read(inventoryCategoriesProvider.future);
    } catch (error) {
      _snack('No se pudieron cargar categorías: $error');
      return null;
    }
  }

  Future<void> _downloadNew() async {
    setState(() => _busy = 'new');
    try {
      final categories = await _categories();
      if (categories == null) return;
      final bytes = InventoryExcelService().buildTemplate(
        categories: categories,
      );
      final saved = await FileIoHelper.saveBytes(
        bytes: bytes,
        fileName: 'plantilla_articulos_nuevos_${_stamp()}.xlsx',
        dialogTitle: 'Guardar plantilla de artículos nuevos',
      );
      if (saved) _snack('Plantilla para artículos nuevos generada');
    } catch (error) {
      _snack('No se pudo generar la plantilla: $error');
    } finally {
      if (mounted) setState(() => _busy = null);
    }
  }

  Future<void> _downloadExisting() async {
    setState(() => _busy = 'existing');
    try {
      final categories = await _categories();
      if (categories == null) return;
      final products = await ref.read(inventoryProductsProvider.future);
      if (products.isEmpty) {
        _snack('No hay artículos existentes para actualizar.');
        return;
      }
      final bytes = InventoryExcelService().buildExport(
        products: products,
        categories: categories,
      );
      final saved = await FileIoHelper.saveBytes(
        bytes: bytes,
        fileName: 'actualizar_articulos_existentes_${_stamp()}.xlsx',
        dialogTitle: 'Guardar plantilla de artículos existentes',
      );
      if (saved) {
        _snack('Plantilla con ${products.length} artículos existentes generada');
      }
    } catch (error) {
      _snack('No se pudo generar la plantilla: $error');
    } finally {
      if (mounted) setState(() => _busy = null);
    }
  }

  Future<void> _pickFile() async {
    // Web: el picker requiere user gesture activo, así que se invoca
    // directo desde el onPressed sin awaits previos.
    try {
      final picked = await FileIoHelper.pickImportFile();
      if (picked == null || !mounted) return;
      setState(() {
        _pickedBytes = picked.bytes;
        _pickedName = picked.name;
      });
    } catch (error) {
      _snack('No se pudo abrir el archivo: $error');
    }
  }

  Future<void> _process() async {
    final bytes = _pickedBytes;
    if (bytes == null) return;
    setState(() => _busy = 'process');
    try {
      final categories = await _categories();
      if (categories == null) return;

      final isCsv = (_pickedName ?? '').toLowerCase().endsWith('.csv');
      final service = InventoryExcelService();
      final InventoryImportParseResult parsed;
      try {
        parsed = isCsv
            ? service.parseImportCsv(bytes: bytes, categories: categories)
            : service.parseImport(bytes: bytes, categories: categories);
      } catch (error) {
        _snack('Archivo inválido: $error');
        return;
      }

      if (parsed.totalRows == 0) {
        _snack('El archivo no contiene filas con datos.');
        return;
      }

      if (!mounted) return;
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (_) => _ImportPreviewDialog(parseResult: parsed),
      );
      if (confirmed != true || !mounted) return;
      if (parsed.inputs.isEmpty) return;

      final repository = ref.read(inventoryRepositoryProvider);
      final InventoryBulkUpsertResult result;
      try {
        result = await repository.bulkUpsertProducts(parsed.inputs);
      } catch (error) {
        _snack('Error durante la importación: $error');
        return;
      }

      if (!mounted) return;
      ref.invalidate(inventoryProductsProvider);
      // El diálogo de resultado se muestra encima; al cerrarse, cerramos
      // también este diálogo de importación.
      await showDialog<void>(
        context: context,
        builder: (_) => _ImportResultDialog(
          result: result,
          parseErrors: parsed.errors,
        ),
      );
      if (mounted) Navigator.of(context).pop();
    } finally {
      if (mounted) setState(() => _busy = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isMobile = ResponsiveLayout.isMobile(context);
    return AlertDialog(
      title: const Text('Importar / Actualizar inventario'),
      content: SizedBox(
        width: isMobile ? double.maxFinite : 560,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _stepHeader(
                'Paso 1',
                'Descarga una plantilla, llénala con tus artículos y guárdala.',
              ),
              const SizedBox(height: AppTokens.s12),
              _downloadButton(
                icon: Icons.note_add_outlined,
                label: 'Plantilla para artículos NUEVOS',
                busyKey: 'new',
                onPressed: _downloadNew,
              ),
              const SizedBox(height: AppTokens.s8),
              _downloadButton(
                icon: Icons.edit_note_outlined,
                label: 'Plantilla para artículos EXISTENTES (actualizar)',
                busyKey: 'existing',
                onPressed: _downloadExisting,
              ),
              const SizedBox(height: AppTokens.s20),
              const Divider(height: 1),
              const SizedBox(height: AppTokens.s20),
              _stepHeader(
                'Paso 2',
                'Sube el archivo lleno (.xlsx o .csv) para crear y actualizar. '
                    'La columna "sku" decide: si existe se actualiza, si no, se '
                    'crea. Si tu Excel da error al leerse, guárdalo como CSV y '
                    'súbelo.',
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
        label: Align(
          alignment: Alignment.centerLeft,
          child: Text(label),
        ),
        style: FilledButton.styleFrom(
          alignment: Alignment.centerLeft,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        ),
      ),
    );
  }
}

class _ImportPreviewDialog extends StatelessWidget {
  const _ImportPreviewDialog({required this.parseResult});

  final InventoryImportParseResult parseResult;

  @override
  Widget build(BuildContext context) {
    final hasValid = parseResult.inputs.isNotEmpty;
    final hasErrors = parseResult.errors.isNotEmpty;

    return AlertDialog(
      title: const Text('Vista previa de importación'),
      content: SizedBox(
        width: 480,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Filas leídas: ${parseResult.totalRows}\n'
              'Filas válidas: ${parseResult.inputs.length}\n'
              'Filas con error: ${parseResult.errors.length}',
            ),
            const SizedBox(height: AppTokens.s12),
            if (hasErrors) ...[
              const Text(
                'Errores detectados:',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: AppTokens.s8),
              ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 220),
                child: SingleChildScrollView(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: parseResult.errors
                        .map(
                          (e) => Padding(
                            padding: const EdgeInsets.only(
                              bottom: AppTokens.s4,
                            ),
                            child: Text(
                              'Fila ${e.rowNumber}: ${e.message}',
                              style: const TextStyle(
                                color: AppTokens.error,
                                fontSize: 13,
                              ),
                            ),
                          ),
                        )
                        .toList(),
                  ),
                ),
              ),
              const SizedBox(height: AppTokens.s12),
            ],
            if (hasValid)
              const Text(
                'Las filas válidas se importarán. Las filas con error se ignorarán.',
                style: TextStyle(color: AppTokens.mutedForeground),
              )
            else
              const Text(
                'No hay filas válidas para importar.',
                style: TextStyle(color: AppTokens.error),
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
          onPressed: hasValid
              ? () => Navigator.of(context).pop(true)
              : null,
          child: Text(
            hasValid ? 'Importar ${parseResult.inputs.length}' : 'Importar',
          ),
        ),
      ],
    );
  }
}

class _ImportResultDialog extends StatelessWidget {
  const _ImportResultDialog({
    required this.result,
    required this.parseErrors,
  });

  final InventoryBulkUpsertResult result;
  final List<InventoryImportRowError> parseErrors;

  @override
  Widget build(BuildContext context) {
    final hasDbErrors = result.errors.isNotEmpty;
    final hasParseErrors = parseErrors.isNotEmpty;

    return AlertDialog(
      title: const Text('Importación completada'),
      content: SizedBox(
        width: 480,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Productos creados: ${result.inserted}\n'
              'Productos actualizados: ${result.updated}',
            ),
            if (hasDbErrors || hasParseErrors) ...[
              const SizedBox(height: AppTokens.s12),
              const Text(
                'Errores:',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: AppTokens.s8),
              ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 220),
                child: SingleChildScrollView(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      ...parseErrors.map(
                        (e) => Padding(
                          padding: const EdgeInsets.only(
                            bottom: AppTokens.s4,
                          ),
                          child: Text(
                            'Fila ${e.rowNumber}: ${e.message}',
                            style: const TextStyle(
                              color: AppTokens.error,
                              fontSize: 13,
                            ),
                          ),
                        ),
                      ),
                      ...result.errors.map(
                        (e) => Padding(
                          padding: const EdgeInsets.only(
                            bottom: AppTokens.s4,
                          ),
                          child: Text(
                            '${e.productName}: ${e.message}',
                            style: const TextStyle(
                              color: AppTokens.error,
                              fontSize: 13,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
      actions: [
        FilledButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cerrar'),
        ),
      ],
    );
  }
}

/// Dialog que muestra el historial unificado de movimientos de un producto.
class _ProductHistoryDialog extends ConsumerStatefulWidget {
  const _ProductHistoryDialog({required this.product});

  final InventoryProduct product;

  @override
  ConsumerState<_ProductHistoryDialog> createState() =>
      _ProductHistoryDialogState();
}

class _ProductHistoryDialogState
    extends ConsumerState<_ProductHistoryDialog> {
  late Future<List<ProductMovementEntry>> _future;

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  Future<List<ProductMovementEntry>> _load() {
    return ref
        .read(inventoryRepositoryProvider)
        .fetchProductHistory(widget.product.id);
  }

  void _refresh() => setState(() => _future = _load());

  @override
  Widget build(BuildContext context) {
    return Dialog(
      insetPadding: const EdgeInsets.all(AppTokens.s24),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 760, maxHeight: 640),
        child: Padding(
          padding: const EdgeInsets.all(AppTokens.s20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  const Icon(Icons.history_rounded,
                      color: AppTokens.primary),
                  const SizedBox(width: AppTokens.s8),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Historial del producto',
                          style: Theme.of(context)
                              .textTheme
                              .titleMedium
                              ?.copyWith(fontWeight: FontWeight.w700),
                        ),
                        Text(
                          '${widget.product.name}'
                          '${widget.product.sku != null ? "  ·  SKU ${widget.product.sku}" : ""}',
                          style: Theme.of(context)
                              .textTheme
                              .bodySmall
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
                child: FutureBuilder<List<ProductMovementEntry>>(
                  future: _future,
                  builder: (context, snap) {
                    if (snap.connectionState == ConnectionState.waiting) {
                      return const Center(
                          child: CircularProgressIndicator());
                    }
                    if (snap.hasError) {
                      return Center(
                        child: Text('Error: ${snap.error}'),
                      );
                    }
                    final entries =
                        snap.data ?? const <ProductMovementEntry>[];
                    if (entries.isEmpty) {
                      return Center(
                        child: Text(
                          'Este producto aún no tiene movimientos.',
                          style: TextStyle(
                              color: AppTokens.mutedForeground),
                        ),
                      );
                    }
                    final totalIn = entries
                        .where((e) => e.isIncoming)
                        .fold<double>(0, (s, e) => s + e.quantity);
                    final totalOut = entries
                        .where((e) => !e.isIncoming)
                        .fold<double>(0, (s, e) => s + e.quantity.abs());
                    final runningStocks = List<double>.filled(entries.length, 0);
                    double currentStock = widget.product.stock;
                    for (int i = 0; i < entries.length; i++) {
                      runningStocks[i] = currentStock;
                      currentStock -= entries[i].quantity;
                    }
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Padding(
                          padding: const EdgeInsets.only(bottom: AppTokens.s12),
                          child: Row(
                            children: [
                              Text(
                                '${entries.length} movimientos',
                                style: const TextStyle(
                                    color: AppTokens.mutedForeground),
                              ),
                              const Spacer(),
                              Text(
                                'Entradas: ${qty(totalIn.toInt())}',
                                style: const TextStyle(
                                  color: AppTokens.success,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                              const SizedBox(width: 16),
                              Text(
                                'Salidas: ${qty(totalOut.toInt())}',
                                style: const TextStyle(
                                  color: AppTokens.destructive,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                              const SizedBox(width: 16),
                              Text(
                                'Stock actual: ${qty(widget.product.stock.toInt())}',
                                style: const TextStyle(
                                    fontWeight: FontWeight.w800),
                              ),
                            ],
                          ),
                        ),
                        // Column Headers Row
                        Padding(
                          padding: const EdgeInsets.only(bottom: AppTokens.s8),
                          child: Row(
                            children: [
                              const SizedBox(width: 44), // matches leading icon + spacing
                              const Expanded(
                                child: Text(
                                  'Detalle / Concepto',
                                  style: TextStyle(
                                    color: AppTokens.mutedForeground,
                                    fontSize: 12,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ),
                              SizedBox(
                                width: 80,
                                child: Text(
                                  'Entradas',
                                  textAlign: TextAlign.end,
                                  style: TextStyle(
                                    color: AppTokens.success.withValues(alpha: 0.85),
                                    fontSize: 12,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ),
                              const SizedBox(width: AppTokens.s12),
                              SizedBox(
                                width: 80,
                                child: Text(
                                  'Salidas',
                                  textAlign: TextAlign.end,
                                  style: TextStyle(
                                    color: AppTokens.destructive.withValues(alpha: 0.85),
                                    fontSize: 12,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ),
                              const SizedBox(width: AppTokens.s12),
                              const SizedBox(
                                width: 80,
                                child: Text(
                                  'Stock',
                                  textAlign: TextAlign.end,
                                  style: TextStyle(
                                    color: AppTokens.mutedForeground,
                                    fontSize: 12,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                        const Divider(height: 1, color: AppTokens.border),
                        Expanded(
                          child: ListView.separated(
                            itemCount: entries.length,
                            separatorBuilder: (_, _) => const Divider(
                              height: 1,
                              color: AppTokens.border,
                            ),
                            itemBuilder: (context, i) => _MovementTile(
                              entry: entries[i],
                              runningStock: runningStocks[i],
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
}

class _MovementTile extends StatelessWidget {
  const _MovementTile({
    required this.entry,
    required this.runningStock,
  });

  final ProductMovementEntry entry;
  final double runningStock;

  @override
  Widget build(BuildContext context) {
    final color = entry.isIncoming
        ? AppTokens.success
        : AppTokens.destructive;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppTokens.s10),
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
              entry.isIncoming
                  ? Icons.arrow_downward
                  : Icons.arrow_upward,
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
                  entry.kind.label,
                  style: const TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 14,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  '${formatDateTime(entry.when)}'
                  '${entry.reference != null ? "  ·  ${entry.reference}" : ""}',
                  style: const TextStyle(
                    color: AppTokens.mutedForeground,
                    fontSize: 12,
                  ),
                ),
                if (entry.notes != null && entry.notes!.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Text(
                      entry.notes!,
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
          // Column 1: Entradas (Green)
          SizedBox(
            width: 80,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                if (entry.isIncoming) ...[
                  Text(
                    '+${qty(entry.quantity)}',
                    style: const TextStyle(
                      color: AppTokens.success,
                      fontSize: 14,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  if (entry.amount > 0)
                    Text(
                      money(entry.amount),
                      style: const TextStyle(
                        color: AppTokens.mutedForeground,
                        fontSize: 11,
                      ),
                    ),
                ] else
                  const Text(
                    '-',
                    style: TextStyle(
                      color: AppTokens.mutedForeground,
                      fontSize: 14,
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(width: AppTokens.s12),

          // Column 2: Salidas (Red)
          SizedBox(
            width: 80,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                if (!entry.isIncoming) ...[
                  Text(
                    '-${qty(entry.quantity.abs())}',
                    style: const TextStyle(
                      color: AppTokens.destructive,
                      fontSize: 14,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  if (entry.amount > 0)
                    Text(
                      money(entry.amount),
                      style: const TextStyle(
                        color: AppTokens.mutedForeground,
                        fontSize: 11,
                      ),
                    ),
                ] else
                  const Text(
                    '-',
                    style: TextStyle(
                      color: AppTokens.mutedForeground,
                      fontSize: 14,
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(width: AppTokens.s12),

          // Column 3: Stock (Black)
          SizedBox(
            width: 80,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  qty(runningStock),
                  style: const TextStyle(
                    color: AppTokens.foreground,
                    fontSize: 14,
                    fontWeight: FontWeight.w800,
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

class _InventoryKpis extends StatelessWidget {
  const _InventoryKpis({
    required this.totalCostValuation,
    required this.totalPriceValuation,
    required this.totalStock,
  });

  final double totalCostValuation;
  final double totalPriceValuation;
  final double totalStock;

  @override
  Widget build(BuildContext context) {
    final cards = [
      KPICard(
        label: 'Valor Total de Inventario',
        value: money(totalCostValuation),
        icon: Icons.inventory_2_outlined,
        trend: 'Costo de adquisición',
      ),
      KPICard(
        label: 'Valor Total (Venta)',
        value: money(totalPriceValuation),
        icon: Icons.monetization_on_outlined,
        trend: 'Ingresos potenciales',
      ),
      KPICard(
        label: 'Existencias Totales',
        value: qty(totalStock),
        icon: Icons.grid_view_rounded,
        trend: 'Productos en almacén',
      ),
    ];

    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth < 600) {
          return Column(
            children: cards
                .map((card) => Padding(
                      padding: const EdgeInsets.only(bottom: AppTokens.s12),
                      child: card,
                    ))
                .toList(),
          );
        } else if (constraints.maxWidth < 900) {
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
          ],
        );
      },
    );
  }
}

