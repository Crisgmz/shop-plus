import 'package:supabase_flutter/supabase_flutter.dart';

import '../../printing/data/printing.dart';

class PurchaseSupplier {
  PurchaseSupplier({required this.id, required this.name});

  final String id;
  final String name;

  factory PurchaseSupplier.fromMap(Map<String, dynamic> map) {
    return PurchaseSupplier(
      id: (map['id'] ?? '').toString(),
      name: (map['legal_name'] ?? '').toString(),
    );
  }
}

class PurchaseProduct {
  PurchaseProduct({
    required this.id,
    required this.name,
    required this.cost,
    required this.price,
    required this.stock,
    this.sku,
    this.barcode,
    this.unit,
    this.imageUrl,
  });

  final String id;
  final String name;
  final double cost;
  final double price;
  final double stock;
  final String? sku;
  final String? barcode;
  final String? unit;
  final String? imageUrl;

  factory PurchaseProduct.fromMap(Map<String, dynamic> map) {
    return PurchaseProduct(
      id: (map['id'] ?? '').toString(),
      name: (map['name'] ?? '').toString(),
      cost: _toDouble(map['cost']),
      price: _toDouble(map['price']),
      stock: _toDouble(map['stock']),
      sku: map['sku']?.toString(),
      barcode: map['barcode']?.toString(),
      unit: (map['sale_unit'] ?? map['unit'])?.toString(),
      imageUrl: map['image_url']?.toString(),
    );
  }
}

class PurchaseSummary {
  PurchaseSummary({
    required this.id,
    required this.purchaseNumber,
    required this.invoiceNumber,
    required this.supplierName,
    required this.status,
    required this.purchaseDate,
    required this.totalAmount,
    this.paymentStatus = 'pending',
    this.purchaseCategory,
    this.expectedAt,
    this.receivedAt,
    this.linesCount = 0,
    this.itemsQuantity = 0,
    this.receivedQuantity = 0,
  });

  final String id;
  final String? purchaseNumber;
  final String? invoiceNumber;
  final String supplierName;
  final String status;
  final String paymentStatus;
  final String? purchaseCategory;
  final DateTime purchaseDate;
  final DateTime? expectedAt;
  final DateTime? receivedAt;
  final double totalAmount;
  final int linesCount;
  final double itemsQuantity;
  final double receivedQuantity;

  double get receiptProgress =>
      itemsQuantity <= 0 ? 0 : (receivedQuantity / itemsQuantity).clamp(0, 1);

  factory PurchaseSummary.fromMap(Map<String, dynamic> map) {
    return PurchaseSummary(
      id: (map['id'] ?? '').toString(),
      purchaseNumber: map['purchase_number']?.toString(),
      invoiceNumber: map['invoice_number']?.toString(),
      supplierName: (map['supplier_name'] ?? '-').toString(),
      status: (map['status'] ?? '').toString(),
      paymentStatus: (map['payment_status'] ?? 'pending').toString(),
      purchaseCategory: map['purchase_category']?.toString(),
      purchaseDate:
          DateTime.tryParse((map['purchase_date'] ?? '').toString()) ??
          DateTime.fromMillisecondsSinceEpoch(0),
      expectedAt: map['expected_at'] == null
          ? null
          : DateTime.tryParse(map['expected_at'].toString()),
      receivedAt: map['received_at'] == null
          ? null
          : DateTime.tryParse(map['received_at'].toString()),
      totalAmount: _toDouble(map['total_amount']),
      linesCount: _toInt(map['lines_count']),
      itemsQuantity: _toDouble(map['items_quantity']),
      receivedQuantity: _toDouble(map['received_quantity']),
    );
  }
}

class PurchaseLineInput {
  PurchaseLineInput({
    required this.product,
    required this.quantity,
    required this.unitCost,
    required this.taxRate,
    this.salePrice = 0,
    this.notes,
  });

  final PurchaseProduct product;
  // Editables en línea desde el diálogo de compra.
  double quantity;
  double unitCost;
  double taxRate;
  double salePrice;
  final String? notes;

  double get lineSubtotal => _round2(quantity * unitCost);
  double get lineTax => _round2(lineSubtotal * (taxRate / 100));
  double get lineTotal => _round2(lineSubtotal + lineTax);
}

class PurchaseCreateInput {
  PurchaseCreateInput({
    required this.supplierId,
    required this.purchaseDate,
    required this.items,
    this.invoiceNumber,
    this.notes,
    this.paymentStatus = 'pending',
    this.purchaseCategory,
    this.expectedAt,
    this.paidAmount,
  });

  final String supplierId;
  final DateTime purchaseDate;
  final List<PurchaseLineInput> items;
  final String? invoiceNumber;
  final String? notes;
  final String paymentStatus;
  final String? purchaseCategory;
  final DateTime? expectedAt;

  /// Monto pagado al proveedor al momento de crear la compra. Solo se usa
  /// cuando `paymentStatus == 'partial'`. Para 'paid' se paga el total y para
  /// 'pending' se paga 0 (queda como cuenta por pagar).
  final double? paidAmount;
}

class PurchaseItemDetail {
  PurchaseItemDetail({
    required this.description,
    required this.quantity,
    required this.unitCost,
    required this.taxRate,
    required this.lineSubtotal,
    required this.lineTax,
    required this.lineTotal,
    this.productId,
    this.sku,
    this.unitName,
  });

  final String? productId;
  final String description;
  final double quantity;
  final double unitCost;
  final double taxRate;
  final double lineSubtotal;
  final double lineTax;
  final double lineTotal;
  final String? sku;
  final String? unitName;
}

class PurchaseDetail {
  PurchaseDetail({
    required this.id,
    required this.supplierId,
    required this.supplierName,
    required this.purchaseDate,
    required this.status,
    required this.paymentStatus,
    required this.subtotal,
    required this.taxAmount,
    required this.totalAmount,
    required this.items,
    this.purchaseNumber,
    this.invoiceNumber,
    this.purchaseCategory,
    this.expectedAt,
    this.notes,
  });

  final String id;
  final String supplierId;
  final String supplierName;
  final String? purchaseNumber;
  final String? invoiceNumber;
  final DateTime purchaseDate;
  final String status;
  final String paymentStatus;
  final String? purchaseCategory;
  final DateTime? expectedAt;
  final String? notes;
  final double subtotal;
  final double taxAmount;
  final double totalAmount;
  final List<PurchaseItemDetail> items;
}

class PurchasesRepository {
  PurchasesRepository(this._client);

  final SupabaseClient _client;

  Future<List<PurchaseSupplier>> fetchSuppliers() async {
    final branchId = await _currentBranchId();
    if (branchId == null) return const [];

    final rows = await _client
        .from('suppliers')
        .select('id, legal_name')
        .eq('branch_id', branchId)
        .eq('is_active', true)
        .order('legal_name');

    return rows
        .map(
          (item) =>
              PurchaseSupplier.fromMap(Map<String, dynamic>.from(item as Map)),
        )
        .toList(growable: false);
  }

  Future<List<PurchaseProduct>> fetchProducts() async {
    final branchId = await _currentBranchId();
    if (branchId == null) return const [];

    final rows = await _client
        .from('products')
        .select('id, name, cost, price, stock, sku, barcode, sale_unit, unit, image_url')
        .eq('branch_id', branchId)
        .eq('is_active', true)
        .order('name');

    return rows
        .map(
          (item) =>
              PurchaseProduct.fromMap(Map<String, dynamic>.from(item as Map)),
        )
        .toList(growable: false);
  }

  Future<List<PurchaseSummary>> fetchPurchases() async {
    final branchId = await _currentBranchId();
    if (branchId == null) return const [];

    final rows = await _client
        .from('purchase_operational_view')
        .select(
          'id, purchase_number, invoice_number, supplier_name, status, '
          'payment_status, purchase_category, purchase_date, expected_at, '
          'received_at, total_amount, lines_count, items_quantity, received_quantity',
        )
        .eq('branch_id', branchId)
        .order('purchase_date', ascending: false)
        .limit(100);

    return rows
        .map(
          (item) =>
              PurchaseSummary.fromMap(Map<String, dynamic>.from(item as Map)),
        )
        .toList(growable: false);
  }

  Future<void> createPurchase(PurchaseCreateInput input) async {
    if (input.items.isEmpty) {
      throw Exception('Agrega al menos un artículo.');
    }

    final branchId = await _currentBranchId();
    if (branchId == null) {
      throw Exception('No hay sucursal asignada para este usuario.');
    }

    final subtotal = _round2(
      input.items.fold<double>(0, (sum, item) => sum + item.lineSubtotal),
    );
    final taxAmount = _round2(
      input.items.fold<double>(0, (sum, item) => sum + item.lineTax),
    );
    final totalAmount = _round2(subtotal + taxAmount);

    // Monto pagado ahora → saldo (cuenta por pagar) según el estado de pago:
    //   paid    → paga el total (no queda saldo).
    //   pending → paga 0 (queda todo como cuenta por pagar).
    //   partial → paga input.paidAmount (acotado a [0, total]).
    final double paidNow;
    switch (input.paymentStatus) {
      case 'paid':
        paidNow = totalAmount;
        break;
      case 'partial':
        paidNow = _round2(
          (input.paidAmount ?? 0).clamp(0, totalAmount).toDouble(),
        );
        break;
      default: // 'pending'
        paidNow = 0;
    }
    final balanceDue = _round2(totalAmount - paidNow);

    // Fecha de vencimiento: si queda saldo, la deriva de los días de crédito
    // del proveedor (payment_terms_days). Si no tiene términos, vence el mismo
    // día de la compra.
    String? dueDate;
    if (balanceDue > 0) {
      final termsDays = await _supplierPaymentTermsDays(branchId, input.supplierId);
      dueDate = input.purchaseDate
          .add(Duration(days: termsDays))
          .toIso8601String()
          .split('T')
          .first;
    }

    final purchaseNumber = _buildPurchaseNumber();

    final createdPurchase = await _client
        .from('purchases')
        .insert({
          'branch_id': branchId,
          'supplier_id': input.supplierId,
          'purchase_number': purchaseNumber,
          'invoice_number': _nullIfEmpty(input.invoiceNumber),
          'status': 'posted',
          'payment_status': input.paymentStatus,
          'purchase_category': _nullIfEmpty(input.purchaseCategory),
          'purchase_date': input.purchaseDate.toIso8601String().split('T').first,
          'expected_at': input.expectedAt?.toIso8601String(),
          'notes': _nullIfEmpty(input.notes),
          'subtotal': subtotal,
          'discount_amount': 0,
          'tax_amount': taxAmount,
          'total_amount': totalAmount,
          'paid_amount': paidNow,
          'balance_due': balanceDue,
          'due_date': dueDate,
        })
        .select('id')
        .single();

    final purchaseId = (createdPurchase['id'] ?? '').toString();
    if (purchaseId.isEmpty) {
      throw Exception('No se pudo crear la compra.');
    }

    await _insertPurchaseItems(purchaseId, branchId, input.items);
    await _applyProductCostsPrices(branchId, input.items);
  }

  /// Actualiza una compra existente: reemplaza sus items (el cascade/trigger de
  /// `purchase_items` revierte y vuelve a aplicar el stock) y recalcula totales.
  Future<void> updatePurchase(
    String purchaseId,
    PurchaseCreateInput input,
  ) async {
    if (input.items.isEmpty) {
      throw Exception('Agrega al menos un artículo.');
    }
    final branchId = await _currentBranchId();
    if (branchId == null) {
      throw Exception('No hay sucursal asignada para este usuario.');
    }

    final subtotal = _round2(
      input.items.fold<double>(0, (sum, item) => sum + item.lineSubtotal),
    );
    final taxAmount = _round2(
      input.items.fold<double>(0, (sum, item) => sum + item.lineTax),
    );
    final totalAmount = _round2(subtotal + taxAmount);

    // Conservar lo ya pagado (abonos reales al proveedor) y recalcular el saldo
    // contra el nuevo total, para que Cuentas por Pagar quede consistente.
    final existing = await _client
        .from('purchases')
        .select('paid_amount')
        .eq('id', purchaseId)
        .eq('branch_id', branchId)
        .single();
    final paid = _round2(_toDouble(existing['paid_amount']));
    final balanceDue =
        _round2((totalAmount - paid).clamp(0, totalAmount).toDouble());

    final updated = await _client
        .from('purchases')
        .update({
          'supplier_id': input.supplierId,
          'invoice_number': _nullIfEmpty(input.invoiceNumber),
          'payment_status': input.paymentStatus,
          'purchase_category': _nullIfEmpty(input.purchaseCategory),
          'purchase_date':
              input.purchaseDate.toIso8601String().split('T').first,
          'expected_at': input.expectedAt?.toIso8601String(),
          'notes': _nullIfEmpty(input.notes),
          'subtotal': subtotal,
          'discount_amount': 0,
          'tax_amount': taxAmount,
          'total_amount': totalAmount,
          'balance_due': balanceDue,
        })
        .eq('id', purchaseId)
        .eq('branch_id', branchId)
        .select('id');

    if (updated.isEmpty) {
      throw Exception('No se encontró la compra o no tienes permiso.');
    }

    // Borrar items viejos (el trigger resta su stock) e insertar los nuevos
    // (el trigger vuelve a sumar). El neto deja el stock correcto.
    await _client
        .from('purchase_items')
        .delete()
        .eq('purchase_id', purchaseId)
        .eq('branch_id', branchId);

    await _insertPurchaseItems(purchaseId, branchId, input.items);
    await _applyProductCostsPrices(branchId, input.items);
  }

  /// Elimina una compra. El `ON DELETE CASCADE` borra sus `purchase_items` y el
  /// trigger de stock revierte automáticamente las cantidades.
  Future<void> deletePurchase(String purchaseId) async {
    final branchId = await _currentBranchId();
    if (branchId == null) {
      throw Exception('No hay sucursal asignada para este usuario.');
    }
    await _client
        .from('purchases')
        .delete()
        .eq('id', purchaseId)
        .eq('branch_id', branchId);
  }

  /// Carga una compra con sus líneas y el proveedor, para ver/editar/imprimir.
  Future<PurchaseDetail?> fetchPurchaseDetail(String purchaseId) async {
    final branchId = await _currentBranchId();
    if (branchId == null) return null;

    final rows = await _client
        .from('purchases')
        .select(
          'id, supplier_id, purchase_number, invoice_number, purchase_date, '
          'status, payment_status, purchase_category, expected_at, notes, '
          'subtotal, tax_amount, total_amount',
        )
        .eq('id', purchaseId)
        .eq('branch_id', branchId)
        .limit(1);
    if (rows.isEmpty) return null;
    final p = Map<String, dynamic>.from(rows.first as Map);

    final supplierId = (p['supplier_id'] ?? '').toString();
    var supplierName = '-';
    if (supplierId.isNotEmpty) {
      final sup = await _client
          .from('suppliers')
          .select('legal_name')
          .eq('id', supplierId)
          .eq('branch_id', branchId)
          .limit(1);
      if (sup.isNotEmpty) {
        supplierName =
            (Map<String, dynamic>.from(sup.first as Map)['legal_name'] ?? '-')
                .toString();
      }
    }

    final itemRows = await _client
        .from('purchase_items')
        .select(
          'product_id, description, product_name_snapshot, sku_snapshot, '
          'unit_name, quantity, unit_cost, tax_rate, line_subtotal, line_tax, '
          'line_total',
        )
        .eq('purchase_id', purchaseId)
        .eq('branch_id', branchId)
        .order('created_at');

    final items = itemRows.map((raw) {
      final m = Map<String, dynamic>.from(raw as Map);
      return PurchaseItemDetail(
        productId: m['product_id']?.toString(),
        description:
            (m['product_name_snapshot'] ?? m['description'] ?? '').toString(),
        sku: m['sku_snapshot']?.toString(),
        unitName: m['unit_name']?.toString(),
        quantity: _toDouble(m['quantity']),
        unitCost: _toDouble(m['unit_cost']),
        taxRate: _toDouble(m['tax_rate']),
        lineSubtotal: _toDouble(m['line_subtotal']),
        lineTax: _toDouble(m['line_tax']),
        lineTotal: _toDouble(m['line_total']),
      );
    }).toList(growable: false);

    return PurchaseDetail(
      id: (p['id'] ?? '').toString(),
      supplierId: supplierId,
      supplierName: supplierName,
      purchaseNumber: p['purchase_number']?.toString(),
      invoiceNumber: p['invoice_number']?.toString(),
      purchaseDate:
          DateTime.tryParse((p['purchase_date'] ?? '').toString()) ??
              DateTime.now(),
      status: (p['status'] ?? '').toString(),
      paymentStatus: (p['payment_status'] ?? 'pending').toString(),
      purchaseCategory: p['purchase_category']?.toString(),
      expectedAt: p['expected_at'] == null
          ? null
          : DateTime.tryParse(p['expected_at'].toString()),
      notes: p['notes']?.toString(),
      subtotal: _toDouble(p['subtotal']),
      taxAmount: _toDouble(p['tax_amount']),
      totalAmount: _toDouble(p['total_amount']),
      items: items,
    );
  }

  /// Arma el trabajo de impresión de una compra (orden de compra) reutilizando
  /// la misma infraestructura de impresión de las ventas.
  Future<PreparedPrintJobData?> preparePurchasePrintJob(
    String purchaseId, {
    PrintPaperSize paperSize = PrintPaperSize.thermal80mm,
  }) async {
    final detail = await fetchPurchaseDetail(purchaseId);
    if (detail == null) return null;
    final branchId = await _currentBranchId();
    if (branchId == null) return null;

    final branchRows = await _client
        .from('branches')
        .select('name, address, phone')
        .eq('id', branchId)
        .limit(1);
    final branch = branchRows.isEmpty
        ? const <String, dynamic>{}
        : Map<String, dynamic>.from(branchRows.first as Map);

    final settingsRows =
        await _client.from('app_settings').select('company_tax_id').limit(1);
    final settings = settingsRows.isEmpty
        ? const <String, dynamic>{}
        : Map<String, dynamic>.from(settingsRows.first as Map);

    final document = PrintDocumentData(
      documentType: PrintDocumentType.purchaseOrder,
      documentNumber: detail.purchaseNumber ?? detail.id,
      issuedAt: detail.purchaseDate,
      branch: PrintBranchIdentity(
        name: (branch['name'] ?? 'Sucursal').toString(),
        address: branch['address']?.toString(),
        phone: branch['phone']?.toString(),
        taxId: settings['company_tax_id']?.toString(),
      ),
      customer: PrintParty(name: detail.supplierName),
      referenceNumber: detail.invoiceNumber,
      receiptTypeLabel: 'Compra',
      notes: detail.notes,
      showBarcode: false,
      items: detail.items
          .map(
            (it) => PrintDocumentItem(
              description: it.description,
              quantity: it.quantity,
              unitPrice: it.unitCost,
              lineSubtotal: it.lineSubtotal,
              lineTax: it.lineTax,
              lineTotal: it.lineTotal,
              sku: it.sku,
              unitLabel: it.unitName,
            ),
          )
          .toList(growable: false),
      totals: PrintTotals(
        subtotal: detail.subtotal,
        tax: detail.taxAmount,
        total: detail.totalAmount,
      ),
    );

    return PreparedPrintJobData(
      document: document,
      paperSize: paperSize,
      job: PrintJobDraft(
        branchId: branchId,
        documentType: PrintDocumentType.purchaseOrder,
        paperSize: paperSize,
        sourceTable: 'purchases',
        sourceId: detail.id,
        payload: const <String, dynamic>{},
      ),
      dispatchPayload: const <String, dynamic>{},
    );
  }

  Future<void> _insertPurchaseItems(
    String purchaseId,
    String branchId,
    List<PurchaseLineInput> items,
  ) async {
    final payload = items
        .map(
          (line) => {
            'purchase_id': purchaseId,
            'branch_id': branchId,
            'product_id': line.product.id,
            'description': line.product.name,
            'product_name_snapshot': line.product.name,
            'sku_snapshot': line.product.sku,
            'barcode_snapshot': line.product.barcode,
            'unit_name': line.product.unit,
            'quantity': line.quantity,
            'received_quantity': 0,
            'unit_cost': line.unitCost,
            'discount_amount': 0,
            'tax_rate': line.taxRate,
            'line_subtotal': line.lineSubtotal,
            'line_tax': line.lineTax,
            'line_total': line.lineTotal,
            'notes': _nullIfEmpty(line.notes),
          },
        )
        .toList(growable: false);
    await _client.from('purchase_items').insert(payload);
  }

  Future<void> _applyProductCostsPrices(
    String branchId,
    List<PurchaseLineInput> items,
  ) async {
    for (final line in items) {
      final update = <String, dynamic>{'cost': line.unitCost};
      // Solo actualizamos el precio de venta si se especificó uno (> 0),
      // para no borrar el precio existente del producto.
      if (line.salePrice > 0) {
        update['price'] = line.salePrice;
      }
      await _client
          .from('products')
          .update(update)
          .eq('id', line.product.id)
          .eq('branch_id', branchId);
    }
  }

  /// Días de crédito configurados para el proveedor (0 si no tiene o falla).
  Future<int> _supplierPaymentTermsDays(
    String branchId,
    String supplierId,
  ) async {
    try {
      final rows = await _client
          .from('suppliers')
          .select('payment_terms_days')
          .eq('id', supplierId)
          .eq('branch_id', branchId)
          .limit(1);
      if (rows.isEmpty) return 0;
      final value = (rows.first as Map)['payment_terms_days'];
      if (value is int) return value;
      return int.tryParse(value?.toString() ?? '') ?? 0;
    } catch (_) {
      return 0;
    }
  }

  Future<String?> _currentBranchId() async {
    final result = await _client.rpc('current_branch_id');
    if (result == null) return null;
    final value = result.toString();
    return value.isEmpty ? null : value;
  }
}

String _buildPurchaseNumber() {
  final now = DateTime.now();
  final y = now.year.toString();
  final m = now.month.toString().padLeft(2, '0');
  final d = now.day.toString().padLeft(2, '0');
  final hh = now.hour.toString().padLeft(2, '0');
  final mm = now.minute.toString().padLeft(2, '0');
  final ss = now.second.toString().padLeft(2, '0');
  final ms = now.millisecond.toString().padLeft(3, '0');
  return 'COMP-$y$m$d-$hh$mm$ss$ms';
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

double _round2(double value) => (value * 100).roundToDouble() / 100;

int _toInt(dynamic value) {
  if (value == null) return 0;
  if (value is int) return value;
  if (value is double) return value.toInt();
  return int.tryParse(value.toString()) ?? 0;
}
