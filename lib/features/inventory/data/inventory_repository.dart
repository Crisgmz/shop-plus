import 'dart:typed_data';

import 'package:supabase_flutter/supabase_flutter.dart';

class InventoryCategory {
  InventoryCategory({
    required this.id,
    required this.name,
    this.colorHex,
    this.iconName,
    this.sortOrder = 0,
    this.parentId,
  });

  final String id;
  final String name;
  final String? colorHex;
  final String? iconName;
  final int sortOrder;
  final String? parentId;

  factory InventoryCategory.fromMap(Map<String, dynamic> map) {
    return InventoryCategory(
      id: (map['id'] ?? '').toString(),
      name: (map['name'] ?? '').toString(),
      colorHex: map['color_hex']?.toString(),
      iconName: map['icon_name']?.toString(),
      sortOrder: (map['sort_order'] as int?) ?? 0,
      parentId: map['parent_id']?.toString(),
    );
  }
}

class InventoryProduct {
  InventoryProduct({
    required this.id,
    required this.name,
    required this.sku,
    required this.barcode,
    required this.categoryId,
    required this.categoryName,
    required this.unit,
    required this.cost,
    required this.price,
    required this.taxRate,
    required this.stock,
    required this.minStock,
    required this.isActive,
    this.internalCode,
    this.brand,
    this.model,
    this.imageUrl,
    this.notes,
    this.isService = false,
    this.isTaxExempt = false,
    this.trackInventory = true,
    this.sizeLabel,
    this.variantName,
    this.purchaseUnit,
    this.reorderLevel = 0,
    this.maxStock = 0,
    this.allowNegativeStock = false,
    this.imeis = const <String>[],
    this.priceTier1,
    this.priceTier2,
    this.priceTier3,
    this.priceTier4,
    this.priceTier5,
    this.priceTier6,
    this.priceTier7,
    this.priceTier8,
    this.priceTier9,
    this.priceTier10,
  });

  final String id;
  final String name;
  final String? sku;
  final String? barcode;
  final String? categoryId;
  final String? categoryName;
  final String unit;
  final double cost;
  final double price;
  final double taxRate;
  final double stock;
  final double minStock;
  final bool isActive;

  final String? internalCode;
  final String? brand;
  final String? model;
  final String? imageUrl;
  final String? notes;
  final bool isService;
  final bool isTaxExempt;
  final bool trackInventory;
  final String? sizeLabel;
  final String? variantName;
  final String? purchaseUnit;
  final double reorderLevel;
  final double maxStock;
  final bool allowNegativeStock;

  /// IMEIs registrados del producto (celulares/dispositivos serializados).
  final List<String> imeis;

  final double? priceTier1;
  final double? priceTier2;
  final double? priceTier3;
  final double? priceTier4;
  final double? priceTier5;
  final double? priceTier6;
  final double? priceTier7;
  final double? priceTier8;
  final double? priceTier9;
  final double? priceTier10;

  /// Devuelve el precio del tier 1-10 (índice 1-based) o null si no está
  /// configurado.
  double? priceTier(int index) {
    switch (index) {
      case 1:
        return priceTier1;
      case 2:
        return priceTier2;
      case 3:
        return priceTier3;
      case 4:
        return priceTier4;
      case 5:
        return priceTier5;
      case 6:
        return priceTier6;
      case 7:
        return priceTier7;
      case 8:
        return priceTier8;
      case 9:
        return priceTier9;
      case 10:
        return priceTier10;
      default:
        return null;
    }
  }

  bool get isLowStock => !isService && trackInventory && stock <= minStock;

  factory InventoryProduct.fromMap(
    Map<String, dynamic> map,
    Map<String, String> categoryNames,
  ) {
    final categoryId = map['category_id']?.toString();

    return InventoryProduct(
      id: (map['id'] ?? '').toString(),
      name: (map['name'] ?? '').toString(),
      sku: map['sku']?.toString(),
      barcode: map['barcode']?.toString(),
      categoryId: categoryId,
      categoryName: categoryId == null ? null : categoryNames[categoryId],
      unit: (map['sale_unit'] ?? map['unit'] ?? 'unidad').toString(),
      cost: _toDouble(map['cost']),
      price: _toDouble(map['price']),
      taxRate: _toDouble(map['tax_rate']),
      stock: _toDouble(map['stock']),
      minStock: _toDouble(map['min_stock']),
      isActive: map['is_active'] == true,
      internalCode: map['internal_code']?.toString(),
      brand: map['brand']?.toString(),
      model: map['model']?.toString(),
      imageUrl: map['image_url']?.toString(),
      notes: map['notes']?.toString(),
      isService: map['is_service'] == true,
      isTaxExempt: map['is_tax_exempt'] == true,
      trackInventory: map['track_inventory'] != false,
      sizeLabel: map['size_label']?.toString(),
      variantName: map['variant_name']?.toString(),
      purchaseUnit: map['purchase_unit']?.toString(),
      reorderLevel: _toDouble(map['reorder_level']),
      maxStock: _toDouble(map['max_stock']),
      allowNegativeStock: map['allow_negative_stock'] == true,
      imeis: map['imeis'] is List
          ? (map['imeis'] as List)
              .map((e) => e.toString())
              .where((e) => e.trim().isNotEmpty)
              .toList(growable: false)
          : const <String>[],
      priceTier1: map['price_tier_1'] == null ? null : _toDouble(map['price_tier_1']),
      priceTier2: map['price_tier_2'] == null ? null : _toDouble(map['price_tier_2']),
      priceTier3: map['price_tier_3'] == null ? null : _toDouble(map['price_tier_3']),
      priceTier4: map['price_tier_4'] == null ? null : _toDouble(map['price_tier_4']),
      priceTier5: map['price_tier_5'] == null ? null : _toDouble(map['price_tier_5']),
      priceTier6: map['price_tier_6'] == null ? null : _toDouble(map['price_tier_6']),
      priceTier7: map['price_tier_7'] == null ? null : _toDouble(map['price_tier_7']),
      priceTier8: map['price_tier_8'] == null ? null : _toDouble(map['price_tier_8']),
      priceTier9: map['price_tier_9'] == null ? null : _toDouble(map['price_tier_9']),
      priceTier10: map['price_tier_10'] == null ? null : _toDouble(map['price_tier_10']),
    );
  }
}

class InventoryProductInput {
  InventoryProductInput({
    required this.name,
    required this.price,
    required this.cost,
    required this.stock,
    required this.minStock,
    required this.taxRate,
    required this.unit,
    required this.isActive,
    this.id,
    this.sku,
    this.barcode,
    this.categoryId,
    this.internalCode,
    this.brand,
    this.model,
    this.imageUrl,
    this.notes,
    this.isService = false,
    this.isTaxExempt = false,
    this.trackInventory = true,
    this.sizeLabel,
    this.variantName,
    this.purchaseUnit,
    this.reorderLevel = 0,
    this.maxStock = 0,
    this.allowNegativeStock = false,
    this.imeis = const <String>[],
    this.priceTier1,
    this.priceTier2,
    this.priceTier3,
    this.priceTier4,
    this.priceTier5,
    this.priceTier6,
    this.priceTier7,
    this.priceTier8,
    this.priceTier9,
    this.priceTier10,
  });

  final String? id;
  final String name;
  final String? sku;
  final String? barcode;
  final String? categoryId;
  final String unit;
  final double cost;
  final double price;
  final double taxRate;
  final double stock;
  final double minStock;
  final bool isActive;
  final String? internalCode;
  final String? brand;
  final String? model;
  final String? imageUrl;
  final String? notes;
  final bool isService;
  final bool isTaxExempt;
  final bool trackInventory;
  final String? sizeLabel;
  final String? variantName;
  final String? purchaseUnit;
  final double reorderLevel;
  final double maxStock;
  final bool allowNegativeStock;

  /// IMEIs del producto (celulares/dispositivos serializados).
  final List<String> imeis;

  final double? priceTier1;
  final double? priceTier2;
  final double? priceTier3;
  final double? priceTier4;
  final double? priceTier5;
  final double? priceTier6;
  final double? priceTier7;
  final double? priceTier8;
  final double? priceTier9;
  final double? priceTier10;

  /// Devuelve el precio del tier 1-10 (índice 1-based) o null.
  double? priceTier(int index) {
    switch (index) {
      case 1:
        return priceTier1;
      case 2:
        return priceTier2;
      case 3:
        return priceTier3;
      case 4:
        return priceTier4;
      case 5:
        return priceTier5;
      case 6:
        return priceTier6;
      case 7:
        return priceTier7;
      case 8:
        return priceTier8;
      case 9:
        return priceTier9;
      case 10:
        return priceTier10;
      default:
        return null;
    }
  }
}

class InventoryBulkUpsertError {
  InventoryBulkUpsertError({
    required this.inputIndex,
    required this.productName,
    required this.message,
  });

  final int inputIndex;
  final String productName;
  final String message;
}

class InventoryBulkUpsertResult {
  InventoryBulkUpsertResult({
    required this.inserted,
    required this.updated,
    required this.errors,
  });

  final int inserted;
  final int updated;
  final List<InventoryBulkUpsertError> errors;

  int get total => inserted + updated;
  bool get hasErrors => errors.isNotEmpty;
}

class InventoryRepository {
  InventoryRepository(this._client);

  final SupabaseClient _client;

  static const _imageBucket = 'product_images';

  /// Sube una imagen al bucket `product_images` y devuelve el URL público.
  /// El path se construye como `<branch_id>/<timestamp>-<random>.<ext>`.
  Future<String> uploadProductImage({
    required Uint8List bytes,
    required String extension,
  }) async {
    final branchId = await _currentBranchId() ?? 'no-branch';
    final timestamp = DateTime.now().millisecondsSinceEpoch;
    final rand = (timestamp % 1000000).toRadixString(36);
    final path = '$branchId/$timestamp-$rand.$extension';

    final storage = _client.storage.from(_imageBucket);
    await storage.uploadBinary(
      path,
      bytes,
      fileOptions: FileOptions(
        upsert: false,
        contentType: _contentTypeFor(extension),
      ),
    );
    return storage.getPublicUrl(path);
  }

  String _contentTypeFor(String extension) {
    switch (extension.toLowerCase()) {
      case 'png':
        return 'image/png';
      case 'webp':
        return 'image/webp';
      case 'gif':
        return 'image/gif';
      default:
        return 'image/jpeg';
    }
  }

  Future<List<InventoryCategory>> fetchCategories() async {
    final branchId = await _currentBranchId();
    if (branchId == null) return const [];

    final rows = await _client
        .from('product_categories')
        .select('id, name, color_hex, icon_name, sort_order, parent_id')
        .eq('branch_id', branchId)
        .eq('is_active', true)
        .order('sort_order')
        .order('name');

    return rows
        .map(
          (item) =>
              InventoryCategory.fromMap(Map<String, dynamic>.from(item as Map)),
        )
        .toList(growable: false);
  }

  /// Crea una nueva categoría de producto en la sucursal actual.
  Future<InventoryCategory> createCategory(String name) async {
    final branchId = await _currentBranchId();
    if (branchId == null) {
      throw Exception('No hay sucursal asignada para este usuario.');
    }
    final trimmed = name.trim();
    if (trimmed.isEmpty) {
      throw Exception('El nombre de la categoría es requerido.');
    }
    final row = await _client
        .from('product_categories')
        .insert({
          'branch_id': branchId,
          'name': trimmed,
          'is_active': true,
        })
        .select('id, name, color_hex, icon_name, sort_order, parent_id')
        .single();
    return InventoryCategory.fromMap(Map<String, dynamic>.from(row));
  }

  /// Renombra una categoría existente.
  Future<void> updateCategoryName({
    required String categoryId,
    required String newName,
  }) async {
    final branchId = await _currentBranchId();
    if (branchId == null) {
      throw Exception('No hay sucursal asignada para este usuario.');
    }
    final trimmed = newName.trim();
    if (trimmed.isEmpty) {
      throw Exception('El nombre de la categoría es requerido.');
    }
    await _client
        .from('product_categories')
        .update({'name': trimmed})
        .eq('id', categoryId)
        .eq('branch_id', branchId);
  }

  /// Borra una categoría. Si tiene productos vinculados, la DB la bloquea
  /// con FK violation (23503) — el caller puede caer a soft-delete con
  /// `setCategoryActive(false)`.
  Future<void> deleteCategory(String categoryId) async {
    final branchId = await _currentBranchId();
    if (branchId == null) {
      throw Exception('No hay sucursal asignada para este usuario.');
    }
    await _client
        .from('product_categories')
        .delete()
        .eq('id', categoryId)
        .eq('branch_id', branchId);
  }

  /// Soft-delete: marca la categoría como inactiva. Útil cuando deleteCategory
  /// falla por FK (la categoría tiene productos vinculados).
  Future<void> setCategoryActive({
    required String categoryId,
    required bool isActive,
  }) async {
    final branchId = await _currentBranchId();
    if (branchId == null) {
      throw Exception('No hay sucursal asignada para este usuario.');
    }
    await _client
        .from('product_categories')
        .update({'is_active': isActive})
        .eq('id', categoryId)
        .eq('branch_id', branchId);
  }

  Future<List<InventoryProduct>> fetchProducts() async {
    final branchId = await _currentBranchId();
    if (branchId == null) return const [];

    final categories = await fetchCategories();
    final categoryNames = <String, String>{
      for (final category in categories) category.id: category.name,
    };

    // Paginado: Supabase corta cada consulta en su tope (por defecto 1000
    // filas). Con catálogos grandes (miles de productos) traer "todo" en una
    // sola consulta dejaría fuera el resto. Pedimos en lotes avanzando por la
    // cantidad realmente devuelta hasta que una página venga vacía.
    const pageSize = 1000;
    final rows = <Map<String, dynamic>>[];
    var from = 0;
    while (true) {
      final page = await _client
          .from('products')
          .select(
            'id, name, sku, barcode, category_id, unit, sale_unit, cost, price, '
            'tax_rate, stock, min_stock, is_active, '
            'internal_code, brand, model, image_url, notes, '
            'is_service, is_tax_exempt, track_inventory, '
            'size_label, variant_name, purchase_unit, '
            'reorder_level, max_stock, allow_negative_stock, '
            'price_tier_1, price_tier_2, price_tier_3, price_tier_4, '
            'price_tier_5, price_tier_6, price_tier_7, price_tier_8, '
            'price_tier_9, price_tier_10, imeis',
          )
          .eq('branch_id', branchId)
          .order('name')
          .range(from, from + pageSize - 1);
      if (page.isEmpty) break;
      rows.addAll(page.map((e) => Map<String, dynamic>.from(e as Map)));
      from += page.length;
      if (page.length < pageSize) break;
    }

    return rows
        .map(
          (item) => InventoryProduct.fromMap(item, categoryNames),
        )
        .toList(growable: false);
  }

  Stream<List<InventoryProduct>> productsStream(Map<String, String> categoryNames) async* {
    final branchId = await _currentBranchId();
    if (branchId == null) {
      yield const [];
      return;
    }

    yield* _client
        .from('products')
        .stream(primaryKey: ['id'])
        .eq('branch_id', branchId)
        .map((rows) {
          final list = rows.map((item) {
            return InventoryProduct.fromMap(
              Map<String, dynamic>.from(item),
              categoryNames,
            );
          }).toList();
          list.sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
          return list;
        });
  }

  Future<void> saveProduct(InventoryProductInput input) async {
    final branchId = await _currentBranchId();
    if (branchId == null) {
      throw Exception('No hay sucursal asignada para este usuario.');
    }

    final payload = _buildProductPayload(input);

    if (input.id == null) {
      payload['branch_id'] = branchId;
      await _client.from('products').insert(payload);
      return;
    }

    await _client
        .from('products')
        .update(payload)
        .eq('id', input.id!)
        .eq('branch_id', branchId);
  }

  /// Registra un ajuste manual de inventario para llevar el stock del producto
  /// a [newStock]. Inserta en `inventory_movements`; el trigger del backend
  /// recalcula `products.stock`. Devuelve el delta aplicado (positivo o
  /// negativo). Si no hay diferencia, no inserta nada.
  Future<double> adjustStock({
    required String productId,
    required double currentStock,
    required double newStock,
    String? reason,
    String? notes,
  }) async {
    final branchId = await _currentBranchId();
    if (branchId == null) {
      throw Exception('No hay sucursal asignada para este usuario.');
    }
    final delta = double.parse((newStock - currentStock).toStringAsFixed(3));
    if (delta == 0) return 0;
    String? clean(String? v) =>
        (v == null || v.trim().isEmpty) ? null : v.trim();
    await _client.from('inventory_movements').insert({
      'branch_id': branchId,
      'product_id': productId,
      'movement_type': delta > 0 ? 'adjustment_in' : 'adjustment_out',
      'quantity': delta.abs(),
      'reason': clean(reason),
      'notes': clean(notes),
      'recorded_by': _client.auth.currentUser?.id,
    });
    return delta;
  }

  Future<InventoryBulkUpsertResult> bulkUpsertProducts(
    List<InventoryProductInput> inputs,
  ) async {
    final branchId = await _currentBranchId();
    if (branchId == null) {
      throw Exception('No hay sucursal asignada para este usuario.');
    }

    final skus = <String>{};
    for (final input in inputs) {
      final sku = input.sku?.trim();
      if (sku != null && sku.isNotEmpty) skus.add(sku);
    }

    final existingBySku = <String, String>{};
    if (skus.isNotEmpty) {
      final rows = await _client
          .from('products')
          .select('id, sku')
          .eq('branch_id', branchId)
          .inFilter('sku', skus.toList(growable: false));
      for (final row in rows) {
        final sku = row['sku']?.toString();
        final id = row['id']?.toString();
        if (sku != null && id != null) existingBySku[sku] = id;
      }
    }

    var inserted = 0;
    var updated = 0;
    final errors = <InventoryBulkUpsertError>[];

    for (var i = 0; i < inputs.length; i++) {
      final input = inputs[i];
      try {
        final sku = input.sku?.trim();
        final existingId = (sku != null && sku.isNotEmpty)
            ? existingBySku[sku]
            : null;
        final payload = _buildProductPayload(input);
        // El import no maneja IMEIs: no tocar la columna para no borrarlos.
        payload.remove('imeis');
        if (existingId == null) {
          payload['branch_id'] = branchId;
          await _client.from('products').insert(payload);
          inserted++;
        } else {
          await _client
              .from('products')
              .update(payload)
              .eq('id', existingId)
              .eq('branch_id', branchId);
          updated++;
        }
      } catch (error) {
        errors.add(
          InventoryBulkUpsertError(
            inputIndex: i,
            productName: input.name,
            message: error.toString(),
          ),
        );
      }
    }

    return InventoryBulkUpsertResult(
      inserted: inserted,
      updated: updated,
      errors: errors,
    );
  }

  Map<String, dynamic> _buildProductPayload(InventoryProductInput input) {
    final unitValue = input.unit.trim().isEmpty ? 'unidad' : input.unit.trim();
    return <String, dynamic>{
      'name': input.name.trim(),
      'sku': _nullIfEmpty(input.sku),
      'barcode': _nullIfEmpty(input.barcode),
      'category_id': _nullIfEmpty(input.categoryId),
      'unit': unitValue,
      'sale_unit': unitValue,
      'purchase_unit': _nullIfEmpty(input.purchaseUnit) ?? unitValue,
      'cost': input.cost,
      'price': input.price,
      'tax_rate': input.taxRate,
      'stock': input.stock,
      'min_stock': input.minStock,
      'reorder_level': input.reorderLevel,
      'max_stock': input.maxStock,
      'allow_negative_stock': input.allowNegativeStock,
      'is_active': input.isActive,
      'internal_code': _nullIfEmpty(input.internalCode),
      'brand': _nullIfEmpty(input.brand),
      'model': _nullIfEmpty(input.model),
      'size_label': _nullIfEmpty(input.sizeLabel),
      'variant_name': _nullIfEmpty(input.variantName),
      'image_url': _nullIfEmpty(input.imageUrl),
      'notes': _nullIfEmpty(input.notes),
      'is_service': input.isService,
      'is_tax_exempt': input.isTaxExempt,
      'track_inventory': input.trackInventory,
      'imeis': input.imeis,
      'price_tier_1': input.priceTier1 ?? input.price,
      'price_tier_2': input.priceTier2,
      'price_tier_3': input.priceTier3,
      'price_tier_4': input.priceTier4,
      'price_tier_5': input.priceTier5,
      'price_tier_6': input.priceTier6,
      'price_tier_7': input.priceTier7,
      'price_tier_8': input.priceTier8,
      'price_tier_9': input.priceTier9,
      'price_tier_10': input.priceTier10,
    };
  }

  Future<void> setProductActive({
    required String productId,
    required bool isActive,
  }) async {
    final branchId = await _currentBranchId();
    if (branchId == null) {
      throw Exception('No hay sucursal asignada para este usuario.');
    }

    await _client
        .from('products')
        .update({'is_active': isActive})
        .eq('id', productId)
        .eq('branch_id', branchId);
  }

  /// Borra el producto físicamente. Si tiene ventas/compras vinculadas la
  /// DB lo bloquea con FK violation (código 23503). El caller decide si
  /// hacer fallback a soft-delete.
  Future<void> deleteProduct(String productId) async {
    final branchId = await _currentBranchId();
    if (branchId == null) {
      throw Exception('No hay sucursal asignada para este usuario.');
    }

    await _client
        .from('products')
        .delete()
        .eq('id', productId)
        .eq('branch_id', branchId);
  }

  /// Historial unificado de movimientos de un producto:
  ///   - Ventas (sale_items) → salida
  ///   - Compras (purchase_items) → entrada
  ///   - Movimientos manuales (inventory_movements) → según tipo
  ///   - Devoluciones (return_items) → entrada
  Future<List<ProductMovementEntry>> fetchProductHistory(
    String productId, {
    int limit = 200,
  }) async {
    final branchId = await _currentBranchId();
    if (branchId == null) return const [];

    final entries = <ProductMovementEntry>[];

    // Las 4 fuentes del historial (ventas, compras, movimientos, devoluciones)
    // son independientes → en paralelo (4 round-trips → 1). El orden de
    // agregado no importa: `entries` se ordena por fecha al final.
    final (saleItems, purchaseItems, movements, returnItems) = await (
      _client
          .from('sale_items')
          .select(
            'quantity, line_total, created_at, sale_id, '
            'sales(sale_number, sale_date, status)',
          )
          .eq('branch_id', branchId)
          .eq('product_id', productId)
          .order('created_at', ascending: false)
          .limit(limit),
      _client
          .from('purchase_items')
          .select(
            'quantity, line_total, created_at, purchase_id, '
            'purchases(purchase_number, purchase_date, status)',
          )
          .eq('branch_id', branchId)
          .eq('product_id', productId)
          .order('created_at', ascending: false)
          .limit(limit),
      _client
          .from('inventory_movements')
          .select(
            'quantity, unit_cost, occurred_at, movement_type, reason, notes',
          )
          .eq('branch_id', branchId)
          .eq('product_id', productId)
          .order('occurred_at', ascending: false)
          .limit(limit),
      _client
          .from('return_items')
          .select(
            'quantity, line_total, created_at, return_id, '
            'returns(return_number, return_date)',
          )
          .eq('branch_id', branchId)
          .eq('product_id', productId)
          .order('created_at', ascending: false)
          .limit(limit),
    ).wait;

    // Ventas
    for (final raw in saleItems) {
      final row = Map<String, dynamic>.from(raw as Map);
      final sale = row['sales'];
      final saleStatus =
          sale is Map ? (sale['status'] ?? '').toString() : '';
      // Excluir voided del flujo de venta normal.
      if (saleStatus == 'voided') continue;
      entries.add(ProductMovementEntry(
        when: DateTime.tryParse(
              sale is Map
                  ? (sale['sale_date'] ?? row['created_at']).toString()
                  : row['created_at']?.toString() ?? '',
            ) ??
            DateTime.now(),
        kind: ProductMovementKind.sale,
        quantity: -_toDouble(row['quantity']),
        amount: _toDouble(row['line_total']),
        reference:
            sale is Map ? sale['sale_number']?.toString() : null,
      ));
    }

    // Compras
    for (final raw in purchaseItems) {
      final row = Map<String, dynamic>.from(raw as Map);
      final purchase = row['purchases'];
      final pStatus = purchase is Map
          ? (purchase['status'] ?? '').toString()
          : '';
      if (pStatus == 'cancelled') continue;
      entries.add(ProductMovementEntry(
        when: DateTime.tryParse(
              purchase is Map
                  ? (purchase['purchase_date'] ?? row['created_at'])
                      .toString()
                  : row['created_at']?.toString() ?? '',
            ) ??
            DateTime.now(),
        kind: ProductMovementKind.purchase,
        quantity: _toDouble(row['quantity']),
        amount: _toDouble(row['line_total']),
        reference: purchase is Map
            ? purchase['purchase_number']?.toString()
            : null,
      ));
    }

    // Movimientos manuales (mermas/ajustes/traslados)
    for (final raw in movements) {
      final row = Map<String, dynamic>.from(raw as Map);
      final type = (row['movement_type'] ?? '').toString();
      final qty = _toDouble(row['quantity']);
      final cost = _toDouble(row['unit_cost']);
      final isPositive = const {
        'adjustment_in',
        'transfer_in',
        'opening',
        'recount',
      }.contains(type);
      entries.add(ProductMovementEntry(
        when: DateTime.tryParse(row['occurred_at']?.toString() ?? '') ??
            DateTime.now(),
        kind: _movementKindFromType(type),
        quantity: isPositive ? qty : -qty,
        amount: qty * cost,
        reference: type,
        notes: row['reason']?.toString() ?? row['notes']?.toString(),
      ));
    }

    // Devoluciones
    for (final raw in returnItems) {
      final row = Map<String, dynamic>.from(raw as Map);
      final ret = row['returns'];
      entries.add(ProductMovementEntry(
        when: DateTime.tryParse(
              ret is Map
                  ? (ret['return_date'] ?? row['created_at']).toString()
                  : row['created_at']?.toString() ?? '',
            ) ??
            DateTime.now(),
        kind: ProductMovementKind.returnIn,
        quantity: _toDouble(row['quantity']),
        amount: _toDouble(row['line_total']),
        reference:
            ret is Map ? ret['return_number']?.toString() : null,
      ));
    }

    entries.sort((a, b) => b.when.compareTo(a.when));
    return entries;
  }

  Future<String?> _currentBranchId() async {
    final result = await _client.rpc('current_branch_id');
    if (result == null) return null;
    final value = result.toString();
    return value.isEmpty ? null : value;
  }
}

enum ProductMovementKind {
  sale,
  purchase,
  returnIn,
  waste,
  adjustmentIn,
  adjustmentOut,
  transferIn,
  transferOut,
  other;

  String get label {
    switch (this) {
      case ProductMovementKind.sale:
        return 'Venta';
      case ProductMovementKind.purchase:
        return 'Compra';
      case ProductMovementKind.returnIn:
        return 'Devolución';
      case ProductMovementKind.waste:
        return 'Merma';
      case ProductMovementKind.adjustmentIn:
        return 'Ajuste +';
      case ProductMovementKind.adjustmentOut:
        return 'Ajuste -';
      case ProductMovementKind.transferIn:
        return 'Traslado entrada';
      case ProductMovementKind.transferOut:
        return 'Traslado salida';
      case ProductMovementKind.other:
        return 'Otro';
    }
  }
}

ProductMovementKind _movementKindFromType(String type) {
  switch (type) {
    case 'waste':
    case 'breakage':
    case 'expired':
    case 'kitchen_return':
      return ProductMovementKind.waste;
    case 'adjustment_in':
    case 'opening':
    case 'recount':
      return ProductMovementKind.adjustmentIn;
    case 'adjustment_out':
      return ProductMovementKind.adjustmentOut;
    case 'transfer_in':
      return ProductMovementKind.transferIn;
    case 'transfer_out':
      return ProductMovementKind.transferOut;
    default:
      return ProductMovementKind.other;
  }
}

class ProductMovementEntry {
  ProductMovementEntry({
    required this.when,
    required this.kind,
    required this.quantity,
    required this.amount,
    this.reference,
    this.notes,
  });

  final DateTime when;
  final ProductMovementKind kind;

  /// Cantidad con signo: positivo = entrada, negativo = salida.
  final double quantity;
  final double amount;
  final String? reference;
  final String? notes;

  bool get isIncoming => quantity > 0;
}

String? _nullIfEmpty(String? value) {
  if (value == null) return null;
  final trimmed = value.trim();
  return trimmed.isEmpty ? null : trimmed;
}

double _toDouble(dynamic value) {
  if (value == null) return 0;
  if (value is double) return value;
  if (value is int) return value.toDouble();
  return double.tryParse(value.toString()) ?? 0;
}
