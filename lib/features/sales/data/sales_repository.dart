import 'dart:io' show HttpClient;

import 'package:flutter/foundation.dart' show debugPrint, kIsWeb;
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../printing/data/printing.dart';
import '../domain/sale_checkout_service.dart';

class SalesProduct {
  SalesProduct({
    required this.id,
    required this.name,
    required this.price,
    required this.cost,
    required this.taxRate,
    required this.stock,
    required this.isActive,
    this.sku,
    this.barcode,
    this.categoryId,
    this.categoryName,
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
    this.imageUrl,
    this.imeis = const <String>[],
    this.isService = false,
    this.isTaxExempt = false,
    this.allowNegativeStock = false,
    this.priceIncludesTax = false,
    this.trackInventory = true,
  });

  final String id;
  final String name;
  final String? sku;
  final String? barcode;
  final String? categoryId;
  final String? categoryName;
  final double price;
  final double cost;
  final double taxRate;
  final double stock;
  final bool isActive;
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
  final String? imageUrl;

  /// IMEIs disponibles del producto (celulares/dispositivos serializados).
  final List<String> imeis;

  /// Servicio (mano de obra, instalación): no maneja inventario, así que la
  /// validación de stock no aplica. El RPC de checkout lo respeta; el POS
  /// tiene que respetarlo igual o los servicios no se podrían vender.
  final bool isService;

  /// Exento de ITBIS. El RPC fuerza tasa 0 para estos productos: si el POS no
  /// lo espejara, la pantalla cobraría un impuesto que la venta no registra.
  final bool isTaxExempt;

  /// El dueño permite vender este producto aunque el stock quede negativo.
  final bool allowNegativeStock;

  /// El precio de venta ya trae el ITBIS adentro: el impuesto se EXTRAE en vez
  /// de agregarse encima. Si el POS no lo espejara, mostraría —y cobraría— un
  /// total mayor que el que registra el RPC.
  final bool priceIncludesTax;

  /// El producto lleva control de inventario. En `false` el RPC no valida
  /// stock ni lo descuenta.
  final bool trackInventory;

  /// Tasa realmente aplicable a este producto. Espeja la tasa efectiva del
  /// RPC: un producto exento no factura ITBIS aunque tenga tasa configurada.
  double get effectiveTaxRate => isTaxExempt ? 0 : taxRate;

  /// Si este producto debe validarse contra el stock disponible. Espeja la
  /// condición del RPC: ni servicios, ni productos sin control de inventario,
  /// ni los que permiten stock negativo.
  bool get tracksStock => !isService && trackInventory && !allowNegativeStock;

  /// Si el producto maneja IMEI (tiene al menos uno registrado).
  bool get hasImeis => imeis.isNotEmpty;

  /// Devuelve el precio efectivo según el tier del cliente.
  /// `tier`: 'retail' | 'tier_1'..'tier_10' | null.
  /// Si el tier no tiene precio configurado, cae al precio base.
  double priceFor(String? tier) {
    switch ((tier ?? 'retail').toLowerCase()) {
      case 'tier_1':
        return priceTier1 ?? price;
      case 'tier_2':
        return priceTier2 ?? price;
      case 'tier_3':
        return priceTier3 ?? price;
      case 'tier_4':
        return priceTier4 ?? price;
      case 'tier_5':
        return priceTier5 ?? price;
      case 'tier_6':
        return priceTier6 ?? price;
      case 'tier_7':
        return priceTier7 ?? price;
      case 'tier_8':
        return priceTier8 ?? price;
      case 'tier_9':
        return priceTier9 ?? price;
      case 'tier_10':
        return priceTier10 ?? price;
      default:
        return price;
    }
  }

  factory SalesProduct.fromMap(
    Map<String, dynamic> map,
    Map<String, String> categoryNames,
  ) {
    final categoryId = map['category_id']?.toString();

    double? optionalDouble(dynamic v) {
      if (v == null) return null;
      if (v is double) return v;
      if (v is int) return v.toDouble();
      return double.tryParse(v.toString());
    }

    return SalesProduct(
      id: (map['id'] ?? '').toString(),
      name: (map['name'] ?? '').toString(),
      sku: map['sku']?.toString(),
      barcode: map['barcode']?.toString(),
      categoryId: categoryId,
      categoryName: categoryId == null ? null : categoryNames[categoryId],
      price: _toDouble(map['price']),
      cost: _toDouble(map['cost']),
      taxRate: _toDouble(map['tax_rate']),
      stock: _toDouble(map['stock']),
      isActive: map['is_active'] == true,
      priceTier1: optionalDouble(map['price_tier_1']),
      priceTier2: optionalDouble(map['price_tier_2']),
      priceTier3: optionalDouble(map['price_tier_3']),
      priceTier4: optionalDouble(map['price_tier_4']),
      priceTier5: optionalDouble(map['price_tier_5']),
      priceTier6: optionalDouble(map['price_tier_6']),
      priceTier7: optionalDouble(map['price_tier_7']),
      priceTier8: optionalDouble(map['price_tier_8']),
      priceTier9: optionalDouble(map['price_tier_9']),
      priceTier10: optionalDouble(map['price_tier_10']),
      imageUrl: map['image_url']?.toString(),
      isService: map['is_service'] == true,
      isTaxExempt: map['is_tax_exempt'] == true,
      allowNegativeStock: map['allow_negative_stock'] == true,
      priceIncludesTax: map['price_includes_tax'] == true,
      // Ausente o null ⇒ true, igual que el `coalesce(track_inventory, true)`
      // del RPC.
      trackInventory: map['track_inventory'] != false,
      imeis: map['imeis'] is List
          ? (map['imeis'] as List)
              .map((e) => e.toString())
              .where((e) => e.trim().isNotEmpty)
              .toList(growable: false)
          : const <String>[],
    );
  }
}

class SalesCategory {
  SalesCategory({required this.id, required this.name});

  final String id;
  final String name;

  factory SalesCategory.fromMap(Map<String, dynamic> map) {
    return SalesCategory(
      id: (map['id'] ?? '').toString(),
      name: (map['name'] ?? '').toString(),
    );
  }
}

class SalesClient {
  SalesClient({
    required this.id,
    required this.fullName,
    this.priceTier = 'retail',
    this.documentNumber,
    this.legalName,
  });

  final String id;
  final String fullName;

  /// 'retail' | 'tier_1' | 'tier_2' | 'tier_3'.
  final String priceTier;

  /// RNC/cédula del cliente. Requerido para comprobantes fiscales
  /// (≠ consumidor final). Null/vacío si no se registró.
  final String? documentNumber;

  /// Razón social. Cae a [fullName] cuando se usa para fines fiscales.
  final String? legalName;

  /// Tiene los datos mínimos para emitir un comprobante fiscal (crédito
  /// fiscal, gubernamental, etc.): RNC/cédula presente. El nombre siempre
  /// existe vía [fullName]. Refleja la regla del trigger SQL
  /// `tg_sales_assert_fiscal_client`.
  bool get hasFiscalData =>
      (documentNumber != null && documentNumber!.trim().isNotEmpty);

  factory SalesClient.fromMap(Map<String, dynamic> map) {
    String? nz(dynamic v) {
      final s = v?.toString().trim() ?? '';
      return s.isEmpty ? null : s;
    }

    return SalesClient(
      id: (map['id'] ?? '').toString(),
      fullName: (map['full_name'] ?? '').toString(),
      priceTier: (map['price_tier'] ?? 'retail').toString(),
      documentNumber: nz(map['document_number']),
      legalName: nz(map['legal_name']),
    );
  }
}

class SaleCartItem {
  SaleCartItem({
    required this.product,
    required this.quantity,
    double? unitPrice,
    this.discountPct = 0,
    this.imeis = const <String>[],
    this.priceTier = 'retail',
  }) : unitPrice = unitPrice ?? product.price;

  final SalesProduct product;
  final double quantity;

  /// Precio aplicado a esta línea. Por defecto = `product.price`; cuando hay
  /// un cliente con tier asignado, el POS lo setea con `priceFor(tier)`.
  final double unitPrice;

  /// Descuento porcentual aplicado a esta línea (0-100). 0 = sin descuento.
  final double discountPct;

  /// IMEIs seleccionados para esta línea (celulares). Si no está vacío, la
  /// cantidad de la línea corresponde a la cantidad de IMEIs.
  final List<String> imeis;

  /// Nivel de precio elegido para esta línea: 'retail' (Detalle) o
  /// 'tier_1'..'tier_10'. El cajero puede cambiarlo por línea desde el
  /// carrito; también se hereda del tier del cliente al agregar el producto.
  /// Solo describe qué precio se aplicó — si el cajero edita el precio a mano,
  /// [unitPrice] deja de coincidir con `product.priceFor(priceTier)` y el POS
  /// lo muestra como "Personalizado".
  final String priceTier;

  /// True si el precio de la línea fue editado a mano y ya no corresponde al
  /// precio del tier seleccionado.
  bool get isCustomPrice =>
      (unitPrice - product.priceFor(priceTier)).abs() > 0.005;

  /// Tasa de ITBIS que se cobra en esta línea: 0 si el producto está exento,
  /// igual que el RPC. Cualquier cálculo o pantalla del POS debe usar ESTA;
  /// usar `product.taxRate` a secas cobra impuesto que el backend no registra.
  double get taxRate => product.effectiveTaxRate;

  // Toda la aritmética va en CENTAVOS ENTEROS (ver sale_checkout_service.dart):
  // es la única forma de que la pantalla dé exactamente lo mismo que el
  // `numeric` de Postgres. De estos getters sale el total que ve el cajero y
  // el monto que se manda como pagos: si difieren del RPC aunque sea un
  // centavo, el pago dividido rebota o la caja queda descuadrada.

  double get _lineGrossCents => grossCents(quantity, unitPrice);

  double get _lineDiscountCents => (_lineGrossCents * (discountPct / 100))
      .roundToDouble()
      .clamp(0, _lineGrossCents)
      .toDouble();

  /// Bruto después de descuento. Con precio exclusivo es la base imponible;
  /// con precio ITBIS-incluido es el TOTAL a cobrar de la línea.
  double get _lineNetCents => _lineGrossCents - _lineDiscountCents;

  bool get _taxIncluded => product.priceIncludesTax && taxRate > 0;

  double get _lineTaxCents =>
      taxCents(_lineNetCents, taxRate, inclusive: _taxIncluded);

  /// Bruto antes de descuento: cantidad × precio unitario.
  double get lineGross => fromCents(_lineGrossCents);

  /// Monto del descuento aplicado.
  double get lineDiscount => fromCents(_lineDiscountCents);

  /// Bruto menos descuento. Es lo que se cobra cuando la venta no factura
  /// ITBIS (sin comprobante), y el total de la línea con precio ITBIS-incluido.
  double get lineNet => fromCents(_lineNetCents);

  /// Base imponible de la línea (lo que factura sin ITBIS).
  double get lineSubtotal =>
      fromCents(_taxIncluded ? _lineNetCents - _lineTaxCents : _lineNetCents);

  /// ITBIS de la línea. Exclusivo: se agrega encima (base × t/100).
  /// Incluido: se EXTRAE del monto cobrado (neto × t/(100+t)), así el total
  /// queda exacto — 100.00 sigue siendo 100.00.
  double get lineTax => fromCents(_lineTaxCents);

  double get lineTotal =>
      fromCents(_taxIncluded ? _lineNetCents : _lineNetCents + _lineTaxCents);
}

/// Una línea de pago para ventas con pago mixto (varios métodos que suman el
/// total). `method` es un valor del enum payment_method
/// (cash | card | transfer | mobile | other).
class SalePaymentLine {
  const SalePaymentLine({required this.method, required this.amount});

  final String method;
  final double amount;

  Map<String, dynamic> toJson() => {'method': method, 'amount': amount};
}

class SaleCheckoutInput {
  SaleCheckoutInput({
    required this.items,
    required this.receiptType,
    required this.asCredit,
    this.paymentMethod,
    this.payments = const <SalePaymentLine>[],
    this.changeAmount = 0,
    this.clientId,
    this.notes,
    this.disallowNoStock = false,
    this.customerRequiredForSale = false,
    this.creditAllowSales = true,
    this.creditDueDays,
    this.cashSessionId,
    this.holdSaleIdToComplete,
  });

  final List<SaleCartItem> items;
  final String receiptType;
  final bool asCredit;
  final String? paymentMethod;

  /// Pago mixto: una o más líneas {método, monto}. Si está vacío, se usa
  /// `paymentMethod` por el total (flujo de pago único anterior).
  final List<SalePaymentLine> payments;

  /// Monto pagado de más (cambio a devolver en efectivo). Cuando es > 0, el
  /// repositorio fuerza el registro por líneas (`p_payments`) aunque haya un
  /// solo método: así el backend guarda `sales.change_amount` y la caja
  /// descuenta ese efectivo que el cajero sacó para devolver/dar de propina,
  /// sin importar si la venta se facturó en efectivo, tarjeta o transferencia.
  final double changeAmount;

  final String? clientId;
  final String? notes;

  /// app_settings.inv_disallow_no_stock
  final bool disallowNoStock;

  /// app_settings.customer_required_for_sale
  final bool customerRequiredForSale;

  /// app_settings.credit_allow_sales
  final bool creditAllowSales;

  /// Override del plazo de crédito en días para esta venta. Si `null`, el
  /// backend usa `app_settings.credit_default_days`. Solo aplica si `asCredit`.
  final int? creditDueDays;

  /// Sesión de caja explícita sobre la que registrar la venta. Cuando el
  /// usuario tiene varias cajas abiertas (migration 42), el cliente
  /// manda la sesión activa. Si es null, el RPC usa la más reciente.
  final String? cashSessionId;

  /// Id de la cuenta GUARDADA (venta `pending`) que esta venta completa. Cuando
  /// no es null, el backend la ABSORBE: reusa su mismo número, libera su stock
  /// reservado y la reemplaza por esta venta real, todo en una transacción. Así
  /// la cuenta reabierta conserva su número original al cobrarse.
  final String? holdSaleIdToComplete;
}

class SaleCheckoutResult {
  SaleCheckoutResult({
    required this.saleId,
    required this.saleNumber,
    required this.receiptType,
    required this.status,
    required this.subtotal,
    required this.taxAmount,
    required this.totalAmount,
    required this.paidAmount,
    required this.balanceDue,
    required this.itemsCount,
    this.cashSessionId,
    this.ncf,
    this.preparedPrintJob,
  });

  final String saleId;
  final String saleNumber;
  final String receiptType;
  final String status;
  final double subtotal;
  final double taxAmount;
  final double totalAmount;
  final double paidAmount;
  final double balanceDue;
  final int itemsCount;
  final String? cashSessionId;

  /// NCF asignado a la venta (lo pone el trigger SQL al emitirla). Null si la
  /// venta no llevó comprobante (p. ej. faltó secuencia) o no aplica.
  final String? ncf;

  final PreparedPrintJobData? preparedPrintJob;
}

class SalesRepository {
  SalesRepository(this._client);

  final SupabaseClient _client;
  static const SalePrintJobPreparationService _salePrintPreparationService =
      SalePrintJobPreparationService();
  static const SaleCheckoutService _saleCheckoutService = SaleCheckoutService();

  Future<List<SalesCategory>> fetchCategories() async {
    final branchId = await _currentBranchId();
    if (branchId == null) return const [];

    final rows = await _client
        .from('product_categories')
        .select('id, name')
        .eq('branch_id', branchId)
        .eq('is_active', true)
        .order('name');

    return rows
        .map(
          (item) =>
              SalesCategory.fromMap(Map<String, dynamic>.from(item as Map)),
        )
        .toList(growable: false);
  }

  Future<List<SalesProduct>> fetchProducts() async {
    final branchId = await _currentBranchId();
    if (branchId == null) return const [];

    final categories = await fetchCategories();
    final categoryNames = <String, String>{
      for (final category in categories) category.id: category.name,
    };

    // Paginado: Supabase corta cada consulta en su tope (por defecto 1000
    // filas). Con catálogos grandes (miles de productos) una sola consulta
    // dejaría fuera el resto y no aparecerían en el POS. Pedimos en lotes
    // avanzando por la cantidad devuelta hasta que una página venga vacía.
    const pageSize = 1000;
    final rows = <Map<String, dynamic>>[];
    var from = 0;
    while (true) {
      final page = await _client
          .from('products')
          .select(
            'id, name, sku, barcode, category_id, price, cost, tax_rate, stock, '
            'is_active, is_service, is_tax_exempt, allow_negative_stock, '
            'price_includes_tax, track_inventory, '
            'price_tier_1, price_tier_2, price_tier_3, '
            'price_tier_4, price_tier_5, price_tier_6, price_tier_7, '
            'price_tier_8, price_tier_9, price_tier_10, image_url, imeis',
          )
          .eq('branch_id', branchId)
          .eq('is_active', true)
          .order('name')
          .range(from, from + pageSize - 1);
      if (page.isEmpty) break;
      rows.addAll(page.map((e) => Map<String, dynamic>.from(e as Map)));
      from += page.length;
      if (page.length < pageSize) break;
    }

    return rows
        .map(
          (item) => SalesProduct.fromMap(item, categoryNames),
        )
        .toList(growable: false);
  }

  Future<List<SalesClient>> fetchClients() async {
    final branchId = await _currentBranchId();
    if (branchId == null) return const [];

    final rows = await _client
        .from('clients')
        .select('id, full_name, legal_name, document_number, price_tier')
        .eq('branch_id', branchId)
        .eq('is_active', true)
        .order('full_name');

    return rows
        .map(
          (item) => SalesClient.fromMap(Map<String, dynamic>.from(item as Map)),
        )
        .toList(growable: false);
  }

  Future<SaleCheckoutResult> checkoutSale(SaleCheckoutInput input) async {
    final branchId = await _currentBranchId();
    if (branchId == null) {
      throw Exception('No hay sucursal asignada para este usuario.');
    }

    final userId = _client.auth.currentUser?.id;
    if (userId == null) {
      throw Exception('La sesión no es válida. Inicia sesión de nuevo.');
    }

    final normalizedCheckout = _saleCheckoutService.normalize(
      SaleCheckoutServiceInput(
        items: input.items
            .map(
              (item) => SaleCheckoutSourceItem(
                product: SaleCheckoutSourceProduct(
                  id: item.product.id,
                  name: item.product.name,
                  // unitPrice ya respeta el tier del cliente si aplica
                  price: item.unitPrice,
                  taxRate: item.product.taxRate,
                  stock: item.product.stock,
                  isActive: item.product.isActive,
                  isService: item.product.isService,
                  isTaxExempt: item.product.isTaxExempt,
                  allowNegativeStock: item.product.allowNegativeStock,
                  priceIncludesTax: item.product.priceIncludesTax,
                  trackInventory: item.product.trackInventory,
                ),
                quantity: item.quantity,
                // El descuento de la línea viaja al RPC (migración 67). Antes
                // se quedaba aquí y la venta se registraba al precio completo.
                discountPct: item.discountPct,
                imeis: item.imeis,
              ),
            )
            .toList(growable: false),
        receiptType: input.receiptType,
        asCredit: input.asCredit,
        paymentMethod: input.paymentMethod,
        clientId: _nullIfEmpty(input.clientId),
        notes: input.notes,
        disallowNoStock: input.disallowNoStock,
        customerRequiredForSale: input.customerRequiredForSale,
        creditAllowSales: input.creditAllowSales,
      ),
    );

    final params = <String, dynamic>{
      'p_items': normalizedCheckout.toRpcItems(),
      'p_receipt_type': normalizedCheckout.receiptType,
      'p_as_credit': normalizedCheckout.asCredit,
      'p_payment_method': normalizedCheckout.paymentMethod,
      'p_client_id': normalizedCheckout.clientId,
      'p_notes': normalizedCheckout.notes,
      'p_credit_due_days': input.creditDueDays,
      'p_cash_session_id': _nullIfEmpty(input.cashSessionId),
      'p_hold_sale_id': _nullIfEmpty(input.holdSaleIdToComplete),
    };

    // Mandamos p_payments cuando hay 2+ métodos (pago mixto) o cuando se pagó
    // de más con un solo método (sobrepago). En ambos casos el backend (camino
    // split) registra el monto realmente entregado por método y guarda el
    // cambio en sales.change_amount; así la caja descuenta del efectivo
    // esperado lo que el cajero sacó para devolver, aunque la venta se haya
    // facturado en tarjeta o transferencia. p_payments solo existe tras la
    // migración 50/52, por eso la venta simple exacta sigue por el camino
    // único (no rompe si el app se despliega antes que la migración).
    final hasOverpay = input.changeAmount > 0.005;
    if (!input.asCredit && (input.payments.length >= 2 || hasOverpay)) {
      params['p_payments'] =
          input.payments.map((p) => p.toJson()).toList(growable: false);
    }

    final rpcResult = await _client.rpc(
      'checkout_sale_transactional',
      params: params,
    );

    final payload = Map<String, dynamic>.from(rpcResult as Map);
    final saleId = (payload['sale_id'] ?? '').toString();
    if (saleId.isEmpty) {
      throw Exception('No se pudo crear la venta.');
    }

    PreparedPrintJobData? preparedPrintJob;
    final status = (payload['status'] ?? '').toString();
    // Tanto las ventas completadas como las que quedan a crédito deben generar
    // recibo — el cliente necesita comprobante del saldo aunque no haya pagado.
    if (status == 'completed' || status == 'credit') {
      preparedPrintJob = await prepareCompletedSalePrintJob(saleId: saleId);
    }

    return SaleCheckoutResult(
      saleId: saleId,
      saleNumber: (payload['sale_number'] ?? '').toString(),
      receiptType: (payload['receipt_type'] ?? normalizedCheckout.receiptType)
          .toString(),
      status: status,
      subtotal: _toDouble(payload['subtotal']),
      taxAmount: _toDouble(payload['tax_amount']),
      totalAmount: _toDouble(payload['total_amount']),
      paidAmount: _toDouble(payload['paid_amount']),
      balanceDue: _toDouble(payload['balance_due']),
      itemsCount: _toInt(payload['items_count']),
      cashSessionId: _nullIfEmpty(payload['cash_session_id']?.toString()),
      // El NCF lo asigna el trigger durante el INSERT; lo recuperamos de la
      // venta que el preparador del recibo ya volvió a consultar (sin query
      // extra). El checkout RPC no lo devuelve en su payload.
      ncf: _nullIfEmpty(preparedPrintJob?.document.ncf),
      preparedPrintJob: preparedPrintJob,
    );
  }

  /// Guarda el carrito como una venta GUARDADA (cuenta abierta) en estado
  /// `pending`. Reserva el stock (el backend inserta las líneas y el trigger
  /// descuenta), pero NO crea caja, NO registra cobro y NO asigna NCF. Así la
  /// cuenta queda en el historial (chip gris "Pendiente") y NO entra al cierre
  /// de caja hasta que se reabra y se complete. Ver `hold_sale_transactional`.
  Future<HeldSaleResult> holdSale(HeldSaleInput input) async {
    final branchId = await _currentBranchId();
    if (branchId == null) {
      throw Exception('No hay sucursal asignada para este usuario.');
    }
    final userId = _client.auth.currentUser?.id;
    if (userId == null) {
      throw Exception('La sesión no es válida. Inicia sesión de nuevo.');
    }

    // Reutiliza la misma normalización/validación del checkout (productos
    // activos, cantidades, stock si el flag está activo, cliente requerido).
    final normalized = _saleCheckoutService.normalize(
      SaleCheckoutServiceInput(
        items: input.items
            .map(
              (item) => SaleCheckoutSourceItem(
                product: SaleCheckoutSourceProduct(
                  id: item.product.id,
                  name: item.product.name,
                  price: item.unitPrice,
                  taxRate: item.product.taxRate,
                  stock: item.product.stock,
                  isActive: item.product.isActive,
                  isService: item.product.isService,
                  isTaxExempt: item.product.isTaxExempt,
                  allowNegativeStock: item.product.allowNegativeStock,
                  priceIncludesTax: item.product.priceIncludesTax,
                  trackInventory: item.product.trackInventory,
                ),
                quantity: item.quantity,
                // El descuento de la línea viaja al RPC (migración 67). Antes
                // se quedaba aquí y la venta se registraba al precio completo.
                discountPct: item.discountPct,
                imeis: item.imeis,
              ),
            )
            .toList(growable: false),
        receiptType: input.receiptType,
        asCredit: false,
        clientId: _nullIfEmpty(input.clientId),
        notes: input.notes,
        disallowNoStock: input.disallowNoStock,
        customerRequiredForSale: input.customerRequiredForSale,
      ),
    );

    final rpcResult = await _client.rpc(
      'hold_sale_transactional',
      params: <String, dynamic>{
        'p_items': normalized.toRpcItems(),
        'p_receipt_type': normalized.receiptType,
        'p_client_id': normalized.clientId,
        'p_notes': normalized.notes,
        'p_replace_hold_sale_id': _nullIfEmpty(input.replaceHoldSaleId),
      },
    );

    final payload = Map<String, dynamic>.from(rpcResult as Map);
    final saleId = (payload['sale_id'] ?? '').toString();
    if (saleId.isEmpty) {
      throw Exception('No se pudo guardar la cuenta.');
    }
    return HeldSaleResult(
      saleId: saleId,
      saleNumber: (payload['sale_number'] ?? '').toString(),
      totalAmount: _toDouble(payload['total_amount']),
      itemsCount: _toInt(payload['items_count']),
    );
  }

  /// Descarta una cuenta GUARDADA (estado `pending`): devuelve el stock
  /// reservado y borra la fila. Solo opera sobre ventas pendientes.
  Future<void> discardHeldSale(String saleId) async {
    await _client.rpc('discard_held_sale', params: {'p_sale_id': saleId});
  }

  /// Carga una cuenta GUARDADA para reabrirla en el POS: devuelve sus líneas
  /// como [SaleCartItem] (preservando precio unitario e IMEIs) más el cliente,
  /// tipo de comprobante y notas. Devuelve `null` si no existe o no está
  /// pendiente. Los productos que ya no existan/estén inactivos se omiten.
  Future<HeldSaleDraftData?> loadHeldSaleForReopen(String saleId) async {
    final branchId = await _currentBranchId();
    if (branchId == null) return null;

    final saleRows = await _client
        .from('sales')
        .select('id, status, client_id, receipt_type, notes')
        .eq('id', saleId)
        .eq('branch_id', branchId)
        .limit(1);
    if (saleRows.isEmpty) return null;
    final sale = Map<String, dynamic>.from(saleRows.first as Map);
    if ((sale['status'] ?? '').toString() != 'pending') return null;

    final itemRows = await _client
        .from('sale_items')
        .select('product_id, quantity, unit_price, discount_amount, imeis')
        .eq('branch_id', branchId)
        .eq('sale_id', saleId)
        .order('created_at');

    final products = await fetchProducts();
    final productsById = {for (final p in products) p.id: p};

    final items = <SaleCartItem>[];
    for (final raw in itemRows) {
      final row = Map<String, dynamic>.from(raw as Map);
      final productId = row['product_id']?.toString();
      if (productId == null) continue;
      final product = productsById[productId];
      if (product == null) continue;
      final qty = _toDouble(row['quantity']);
      if (qty <= 0) continue;
      // El descuento se guarda en monto; el carrito trabaja en porcentaje.
      // Misma reconstrucción que hace la pantalla de editar venta.
      final unitPrice = _toDouble(row['unit_price']);
      final gross = qty * unitPrice;
      final discountAmount = _toDouble(row['discount_amount']);
      final discountPct = gross > 0
          ? (discountAmount / gross * 100).clamp(0, 100).toDouble()
          : 0.0;
      items.add(SaleCartItem(
        product: product,
        quantity: qty,
        unitPrice: unitPrice,
        discountPct: discountPct,
        imeis: row['imeis'] is List
            ? (row['imeis'] as List)
                .map((e) => e.toString())
                .where((e) => e.trim().isNotEmpty)
                .toList(growable: false)
            : const <String>[],
      ));
    }

    return HeldSaleDraftData(
      items: items,
      clientId: _nullIfEmpty(sale['client_id']?.toString()),
      receiptType: (sale['receipt_type'] ?? 'consumer_final').toString(),
      notes: sale['notes']?.toString() ?? '',
    );
  }

  Future<PreparedPrintJobData?> prepareCompletedSalePrintJob({
    required String saleId,
    PrintPaperSize paperSize = PrintPaperSize.thermal80mm,
  }) async {
    final saleRows = await _client
        .from('sales')
        .select(
          'id, branch_id, sale_number, sale_date, receipt_type, status, ncf, notes, '
          'subtotal, discount_amount, tax_amount, total_amount, paid_amount, balance_due, '
          'change_amount, service_charge_amount, taxable_amount, exempt_amount, '
          'client_id, client_name_snapshot, cashier_id, cash_session_id',
        )
        .eq('id', saleId)
        .limit(1);

    if (saleRows.isEmpty) return null;

    final sale = Map<String, dynamic>.from(saleRows.first as Map);
    final status = (sale['status'] ?? '').toString().trim().toLowerCase();
    // Permitimos imprimir tanto ventas pagadas como ventas a crédito.
    if (status != 'completed' && status != 'credit') {
      return null;
    }

    final branchId = (sale['branch_id'] ?? '').toString();
    if (branchId.isEmpty) {
      throw Exception('La venta no tiene sucursal asociada.');
    }

    final branchRows = await _client
        .from('branches')
        .select('name, address, phone')
        .eq('id', branchId)
        .limit(1);
    final branch = branchRows.isEmpty
        ? const <String, dynamic>{}
        : Map<String, dynamic>.from(branchRows.first as Map);

    // app_settings (multi-tenant: la RLS filtra a la fila de la empresa
    // del usuario). RNC, logo, ocultar barcode.
    // Se piden todas las columnas (no una lista explícita) para que la venta
    // NO se rompa si la migración de campos del emisor (company_address, etc.)
    // todavía no se aplicó: las columnas ausentes simplemente vienen nulas.
    final settingsRows = await _client.from('app_settings').select().limit(1);
    final settings = settingsRows.isEmpty
        ? const <String, dynamic>{}
        : Map<String, dynamic>.from(settingsRows.first as Map);

    final logoUrl = settings['company_logo_url']?.toString();
    debugPrint('Logo URL en app_settings: $logoUrl');
    final logoBytes = await _downloadBytes(logoUrl);
    debugPrint('Logo bytes descargados: ${logoBytes?.length ?? 0}');

    // QR del pie: descarga en runtime (como el logo) para no depender del
    // asset bundleado ni del caché del service worker en web.
    final qrBytes = await _downloadBytes(settings['company_qr_url']?.toString());

    // Cash session → nombre legible para "Caja registradora".
    final cashSessionId = sale['cash_session_id']?.toString();
    String? cashRegisterName;
    if (cashSessionId != null && cashSessionId.isNotEmpty) {
      final csRows = await _client
          .from('cash_sessions')
          .select('opened_at')
          .eq('id', cashSessionId)
          .limit(1);
      if (csRows.isNotEmpty) {
        final csMap = Map<String, dynamic>.from(csRows.first as Map);
        final openedAt =
            DateTime.tryParse((csMap['opened_at'] ?? '').toString());
        if (openedAt != null) {
          final local = openedAt.isUtc ? openedAt.toLocal() : openedAt;
          final mm = local.month.toString().padLeft(2, '0');
          final dd = local.day.toString().padLeft(2, '0');
          cashRegisterName = 'CAJA $mm$dd';
        } else {
          cashRegisterName = 'CAJA';
        }
      }
    }

    final clientId = sale['client_id']?.toString();
    Map<String, dynamic> client = const <String, dynamic>{};
    if (clientId != null && clientId.isNotEmpty) {
      final clientRows = await _client
          .from('clients')
          .select(
            'full_name, document_type, document_number, address, phone, email',
          )
          .eq('id', clientId)
          .eq('branch_id', branchId)
          .limit(1);
      if (clientRows.isNotEmpty) {
        client = Map<String, dynamic>.from(clientRows.first as Map);
      }
    }

    final cashierId = sale['cashier_id']?.toString();
    Map<String, dynamic> cashier = const <String, dynamic>{};
    if (cashierId != null && cashierId.isNotEmpty) {
      final cashierRows = await _client
          .from('profiles')
          .select('full_name')
          .eq('id', cashierId)
          .limit(1);
      if (cashierRows.isNotEmpty) {
        cashier = Map<String, dynamic>.from(cashierRows.first as Map);
      }
    }

    final itemRows = await _client
        .from('sale_items')
        .select(
          'description, quantity, unit_price, line_subtotal, line_tax, line_total, '
          'sku_snapshot, unit_name, imeis',
        )
        .eq('sale_id', saleId)
        .order('created_at');

    final paymentRows = await _client
        .from('payments')
        .select('payment_method, amount, reference')
        .eq('sale_id', saleId)
        .order('paid_at');

    final saleSource = SalePrintSource(
      saleId: (sale['id'] ?? saleId).toString(),
      branchId: branchId,
      saleNumber: (sale['sale_number'] ?? '').toString(),
      status: (sale['status'] ?? '').toString(),
      saleDate:
          DateTime.tryParse((sale['sale_date'] ?? '').toString()) ??
          DateTime.now(),
      receiptType: (sale['receipt_type'] ?? '').toString(),
      branchName: (branch['name'] ?? 'Sucursal').toString(),
      branchAddress: _firstNonEmpty([
        settings['company_address'],
        branch['address'],
      ]),
      branchPhone: _firstNonEmpty([
        settings['company_phone'],
        branch['phone'],
      ]),
      branchEmail: _firstNonEmpty([settings['company_email']]),
      branchTaxId: settings['company_tax_id']?.toString(),
      branchLogoBytes: logoBytes,
      qrBytes: qrBytes,
      bankInfo: _firstNonEmpty([settings['company_bank_info']]),
      signatoryName: _firstNonEmpty([settings['company_signatory_name']]),
      signatoryTitle: _firstNonEmpty([settings['company_signatory_title']]),
      observation: _firstNonEmpty([settings['invoice_observation']]),
      cashRegisterName: cashRegisterName,
      showBarcode: settings['receipt_hide_barcode'] != true,
      showItbis: settings['invoice_show_itbis'] != false,
      // Sin ficha de cliente puede haber un nombre escrito a mano: viene de la
      // cotización convertida (`quotations.client_display_name`) y se guardó en
      // `sales.client_name_snapshot`. Así la factura dice a quién se le vendió
      // en vez de "Consumidor Final".
      clientName: _firstNonEmpty([
        client['full_name'],
        sale['client_name_snapshot'],
      ]),
      clientDocument: _buildClientDocumentLabel(
        documentType: client['document_type']?.toString(),
        documentNumber: client['document_number']?.toString(),
      ),
      clientAddress: client['address']?.toString(),
      clientPhone: client['phone']?.toString(),
      clientEmail: client['email']?.toString(),
      cashierName: cashier['full_name']?.toString(),
      ncf: sale['ncf']?.toString(),
      notes: sale['notes']?.toString(),
      items: itemRows
          .map((row) => Map<String, dynamic>.from(row as Map))
          .map(
            (item) => SalePrintItemSource(
              description: () {
                final base = (item['description'] ?? '').toString();
                final imeis = item['imeis'] is List
                    ? (item['imeis'] as List)
                        .map((e) => e.toString())
                        .where((e) => e.trim().isNotEmpty)
                        .toList()
                    : const <String>[];
                return imeis.isEmpty
                    ? base
                    : '$base\nIMEI: ${imeis.join(", ")}';
              }(),
              quantity: _toDouble(item['quantity']),
              unitPrice: _toDouble(item['unit_price']),
              lineSubtotal: _toDouble(item['line_subtotal']),
              lineTax: _toDouble(item['line_tax']),
              lineTotal: _toDouble(item['line_total']),
              sku: item['sku_snapshot']?.toString(),
              unitLabel: item['unit_name']?.toString(),
            ),
          )
          .toList(growable: false),
      payments: paymentRows
          .map((row) => Map<String, dynamic>.from(row as Map))
          .map(
            (payment) => SalePrintPaymentSource(
              method: (payment['payment_method'] ?? '').toString(),
              amount: _toDouble(payment['amount']),
              reference: payment['reference']?.toString(),
            ),
          )
          .toList(growable: false),
      subtotal: _toDouble(sale['subtotal']),
      discountAmount: _toDouble(sale['discount_amount']),
      serviceChargeAmount: _toDouble(sale['service_charge_amount']),
      taxAmount: _toDouble(sale['tax_amount']),
      totalAmount: _toDouble(sale['total_amount']),
      paidAmount: _toDouble(sale['paid_amount']),
      balanceDue: _toDouble(sale['balance_due']),
      changeAmount: () {
        // Cambio devuelto: lo guarda el backend en change_amount (sobrepago).
        final stored = _toDouble(sale['change_amount']);
        if (stored > 0) return stored;
        final paid = _toDouble(sale['paid_amount']);
        final total = _toDouble(sale['total_amount']);
        return paid > total ? paid - total : null;
      }(),
    );

    return _salePrintPreparationService.prepareCompletedSaleReceipt(
      sale: saleSource,
      paperSize: paperSize,
    );
  }

  /// Busca una venta por número en la sucursal actual y devuelve sus líneas
  /// listas para precargar el carrito en modo devolución. Si no la encuentra,
  /// retorna null.
  Future<SaleLookupResult?> fetchSaleForReturn(String saleNumber) async {
    final branchId = await _currentBranchId();
    if (branchId == null) return null;
    final cleaned = saleNumber.trim();
    if (cleaned.isEmpty) return null;

    final rows = await _client
        .from('sales')
        .select('id, sale_number, client_id, status, total_amount')
        .eq('branch_id', branchId)
        .eq('sale_number', cleaned)
        .limit(1);

    if (rows.isEmpty) return null;
    final sale = Map<String, dynamic>.from(rows.first as Map);

    final itemRows = await _client
        .from('sale_items')
        .select(
          'product_id, description, quantity, unit_price, tax_rate, '
          'line_subtotal, line_total',
        )
        .eq('branch_id', branchId)
        .eq('sale_id', sale['id'])
        .order('created_at');

    final products = await fetchProducts();
    final productsById = {for (final p in products) p.id: p};

    final items = <SaleCartItem>[];
    for (final raw in itemRows) {
      final row = Map<String, dynamic>.from(raw as Map);
      final productId = row['product_id']?.toString();
      if (productId == null) continue;
      final product = productsById[productId];
      if (product == null) continue;
      final qty = (row['quantity'] is num)
          ? (row['quantity'] as num).toDouble()
          : double.tryParse(row['quantity']?.toString() ?? '') ?? 0;
      if (qty <= 0) continue;
      // Precio NETO realmente cobrado en esa línea: `unit_price` es el bruto,
      // así que si la venta llevaba descuento hay que partir del subtotal de
      // la línea. Devolver al precio del catálogo reembolsaría otro monto.
      final lineSubtotal = _toDoubleResult(row['line_subtotal']);
      final unitPrice = lineSubtotal > 0
          ? _round2(lineSubtotal / qty)
          : _toDoubleResult(row['unit_price']);
      items.add(
        SaleCartItem(product: product, quantity: qty, unitPrice: unitPrice),
      );
    }

    return SaleLookupResult(
      saleId: sale['id'].toString(),
      saleNumber: sale['sale_number']?.toString() ?? cleaned,
      clientId: sale['client_id']?.toString(),
      status: (sale['status'] ?? '').toString(),
      totalAmount: _toDoubleResult(sale['total_amount']),
      items: items,
    );
  }

  /// Lee las últimas devoluciones de la sucursal actual.
  Future<List<ReturnSummary>> fetchRecentReturns({int limit = 50}) async {
    final branchId = await _currentBranchId();
    if (branchId == null) return const [];

    final rows = await _client
        .from('returns')
        .select(
          'id, return_number, return_date, total_amount, tax_amount, '
          'notes, original_sale_id, '
          'clients(full_name), '
          'return_items(quantity)',
        )
        .eq('branch_id', branchId)
        .order('return_date', ascending: false)
        .limit(limit);

    return rows
        .map((item) => ReturnSummary.fromMap(
              Map<String, dynamic>.from(item as Map),
            ))
        .toList(growable: false);
  }

  /// Procesa una devolución desde el POS llamando al RPC `process_return`.
  /// El RPC inserta la cabecera + líneas y dispara el trigger que suma stock.
  /// Si la venta original fue a crédito y se proporciona cliente, descuenta
  /// `clients.balance_due` automáticamente.
  Future<ReturnProcessedResult> processReturn(ReturnInput input) async {
    if (input.items.isEmpty) {
      throw const SaleCheckoutValidationException(
        'No hay productos para devolver.',
      );
    }
    final user = _client.auth.currentUser;
    if (user == null) {
      throw Exception('La sesión no es válida. Inicia sesión de nuevo.');
    }

    final payload = {
      if (input.clientId != null && input.clientId!.isNotEmpty)
        'p_client_id': input.clientId,
      // Sin la venta original el RPC no puede ajustar `clients.balance_due`:
      // devolver mercancía de una venta a crédito no bajaba la deuda.
      if (input.originalSaleId != null && input.originalSaleId!.isNotEmpty)
        'p_original_sale_id': input.originalSaleId,
      if (input.notes != null && input.notes!.isNotEmpty)
        'p_notes': input.notes,
      if (input.cashSessionId != null && input.cashSessionId!.isNotEmpty)
        'p_cash_session_id': input.cashSessionId,
      'p_items': input.items
          .map((item) => {
                'product_id': item.product.id,
                'quantity': item.quantity,
                // El precio de la LÍNEA, no el del catálogo: si el producto
                // cambió de precio, se vendió con tier o con descuento, el
                // catálogo devuelve un monto distinto al que se cobró.
                'unit_price': item.unitPrice,
                'tax_rate': item.product.effectiveTaxRate,
              })
          .toList(growable: false),
    };

    final result = await _client.rpc('process_return', params: payload);
    if (result is! Map) {
      throw Exception('No se pudo procesar la devolución.');
    }
    return ReturnProcessedResult.fromMap(
      Map<String, dynamic>.from(result),
    );
  }

  Future<String?> _currentBranchId() async {
    final result = await _client.rpc('current_branch_id');
    if (result == null) return null;
    final value = result.toString();
    return value.isEmpty ? null : value;
  }

  /// Descarga los bytes de una URL pública (ej. logo de la empresa).
  ///
  /// Si la URL apunta a Supabase Storage (`/storage/v1/object/public/<bucket>/<path>`)
  /// usa el SDK de Supabase para bajarla — funciona en todas las plataformas
  /// (incluida web), reutiliza la sesión y respeta las políticas RLS. Para
  /// URLs externas cae a `dart:io HttpClient` (no disponible en web).
  /// Devuelve `null` ante cualquier error (el recibo se imprime sin logo).
  Future<List<int>?> _downloadBytes(String? url) async {
    if (url == null || url.trim().isEmpty) return null;
    final uri = Uri.tryParse(url.trim());
    if (uri == null || !uri.hasScheme) return null;

    // Caso 1: URL pública de Supabase Storage → usar SDK (funciona en web).
    final storageRef = _parseSupabaseStoragePath(uri);
    if (storageRef != null) {
      try {
        final bytes = await _client.storage
            .from(storageRef.bucket)
            .download(storageRef.path);
        return bytes;
      } catch (error) {
        debugPrint('No se pudo bajar logo de Supabase Storage: $error');
        if (kIsWeb) return null; // En web no hay fallback HTTP.
      }
    }

    // Caso 2: URL externa → HTTP plain (sólo nativo).
    if (kIsWeb) return null;
    try {
      final client = HttpClient();
      try {
        final request = await client.getUrl(uri);
        final response = await request.close();
        if (response.statusCode != 200) {
          debugPrint(
            'GET $uri devolvió ${response.statusCode} — logo no se descargó.',
          );
          return null;
        }
        final bytes = <int>[];
        await for (final chunk in response) {
          bytes.addAll(chunk);
        }
        return bytes;
      } finally {
        client.close(force: true);
      }
    } catch (error) {
      debugPrint('Error bajando logo desde $uri: $error');
      return null;
    }
  }

  /// Extrae `(bucket, path)` de un URL público de Supabase Storage.
  /// Formato esperado: `/storage/v1/object/public/<bucket>/<path...>`.
  /// Devuelve `null` si el URL no corresponde a Storage.
  ({String bucket, String path})? _parseSupabaseStoragePath(Uri uri) {
    final segments = uri.pathSegments;
    final idx = segments.indexOf('public');
    if (idx < 0 || idx + 1 >= segments.length) return null;
    if (idx < 3) return null;
    // Verificar que el prefijo sea /storage/v1/object/public/
    if (segments[idx - 3] != 'storage' ||
        segments[idx - 2] != 'v1' ||
        segments[idx - 1] != 'object') {
      return null;
    }
    final bucket = segments[idx + 1];
    if (bucket.isEmpty || idx + 2 > segments.length) return null;
    final path = segments.sublist(idx + 2).join('/');
    if (path.isEmpty) return null;
    return (bucket: bucket, path: path);
  }
}

/// Entrada para guardar una cuenta (venta suspendida) en estado `pending`.
class HeldSaleInput {
  HeldSaleInput({
    required this.items,
    required this.receiptType,
    this.clientId,
    this.notes,
    this.disallowNoStock = false,
    this.customerRequiredForSale = false,
    this.replaceHoldSaleId,
  });

  final List<SaleCartItem> items;
  final String receiptType;
  final String? clientId;
  final String? notes;
  final bool disallowNoStock;
  final bool customerRequiredForSale;

  /// Id de la cuenta GUARDADA que esta vuelve a guardar (re-guardado de una
  /// cuenta reabierta). Si no es null, el backend reusa su mismo número, libera
  /// su stock reservado y la reemplaza. Así la cuenta conserva su número aunque
  /// se le sigan agregando productos. Null = cuenta nueva.
  final String? replaceHoldSaleId;
}

/// Resultado de guardar una cuenta como pendiente.
class HeldSaleResult {
  HeldSaleResult({
    required this.saleId,
    required this.saleNumber,
    required this.totalAmount,
    required this.itemsCount,
  });

  final String saleId;
  final String saleNumber;
  final double totalAmount;
  final int itemsCount;
}

/// Datos de una cuenta guardada listos para reabrir en el POS.
class HeldSaleDraftData {
  HeldSaleDraftData({
    required this.items,
    required this.receiptType,
    required this.notes,
    this.clientId,
  });

  final List<SaleCartItem> items;
  final String receiptType;
  final String notes;
  final String? clientId;
}

class ReturnInput {
  ReturnInput({
    required this.items,
    this.clientId,
    this.originalSaleId,
    this.notes,
    this.cashSessionId,
  });

  final List<SaleCartItem> items;
  final String? clientId;
  final String? originalSaleId;
  final String? notes;

  /// Caja de la que sale el efectivo del reembolso. Sin esto el arqueo no
  /// descuenta lo devuelto y la caja aparece corta (migración 68).
  final String? cashSessionId;
}

/// Resultado de buscar una venta por número para precargar una devolución.
class SaleLookupResult {
  SaleLookupResult({
    required this.saleId,
    required this.saleNumber,
    required this.status,
    required this.totalAmount,
    required this.items,
    this.clientId,
  });

  final String saleId;
  final String saleNumber;
  final String? clientId;

  /// `'completed' | 'credit' | 'voided' | ...` (enum `sale_status`).
  final String status;
  final double totalAmount;
  final List<SaleCartItem> items;
}

/// Cabecera de devolución para el historial.
class ReturnSummary {
  ReturnSummary({
    required this.id,
    required this.returnNumber,
    required this.returnDate,
    required this.totalAmount,
    required this.taxAmount,
    required this.itemsCount,
    this.clientName,
    this.originalSaleId,
    this.notes,
  });

  factory ReturnSummary.fromMap(Map<String, dynamic> map) {
    final clientMap = map['clients'];
    final clientName = clientMap is Map
        ? clientMap['full_name']?.toString()
        : null;
    final itemsRaw = map['return_items'];
    final itemsCount = itemsRaw is List ? itemsRaw.length : 0;
    return ReturnSummary(
      id: (map['id'] ?? '').toString(),
      returnNumber: (map['return_number'] ?? '').toString(),
      returnDate: DateTime.tryParse(map['return_date']?.toString() ?? '') ??
          DateTime.now(),
      totalAmount: _toDoubleResult(map['total_amount']),
      taxAmount: _toDoubleResult(map['tax_amount']),
      itemsCount: itemsCount,
      clientName: clientName,
      originalSaleId: map['original_sale_id']?.toString(),
      notes: map['notes']?.toString(),
    );
  }

  final String id;
  final String returnNumber;
  final DateTime returnDate;
  final double totalAmount;
  final double taxAmount;
  final int itemsCount;
  final String? clientName;
  final String? originalSaleId;
  final String? notes;
}

class ReturnProcessedResult {
  ReturnProcessedResult({
    required this.returnId,
    required this.returnNumber,
    required this.totalAmount,
    required this.itemsCount,
    required this.creditBalanceAdjusted,
  });

  factory ReturnProcessedResult.fromMap(Map<String, dynamic> map) {
    return ReturnProcessedResult(
      returnId: (map['return_id'] ?? '').toString(),
      returnNumber: (map['return_number'] ?? '').toString(),
      totalAmount: _toDoubleResult(map['total_amount']),
      itemsCount: _toIntResult(map['items_count']),
      creditBalanceAdjusted: map['credit_balance_adjusted'] == true,
    );
  }

  final String returnId;
  final String returnNumber;
  final double totalAmount;
  final int itemsCount;
  final bool creditBalanceAdjusted;
}

double _toDoubleResult(dynamic value) {
  if (value == null) return 0;
  if (value is double) return value;
  if (value is int) return value.toDouble();
  return double.tryParse(value.toString()) ?? 0;
}

int _toIntResult(dynamic value) {
  if (value == null) return 0;
  if (value is int) return value;
  if (value is double) return value.toInt();
  return int.tryParse(value.toString()) ?? 0;
}

String? _nullIfEmpty(String? value) {
  if (value == null) return null;
  final trimmed = value.trim();
  return trimmed.isEmpty ? null : trimmed;
}

/// Primer valor no vacío de la lista (tras trim), o null. Para preferir un
/// campo de configuración sobre el de la sucursal.
String? _firstNonEmpty(List<dynamic> values) {
  for (final v in values) {
    final s = v?.toString().trim();
    if (s != null && s.isNotEmpty) return s;
  }
  return null;
}

String? _buildClientDocumentLabel({
  required String? documentType,
  required String? documentNumber,
}) {
  final normalizedNumber = _nullIfEmpty(documentNumber);
  if (normalizedNumber == null) return null;

  final normalizedType = _nullIfEmpty(documentType);
  if (normalizedType == null) return normalizedNumber;

  return '${normalizedType.toUpperCase()}: $normalizedNumber';
}

double _toDouble(dynamic value) {
  if (value == null) return 0;
  if (value is double) return value;
  if (value is int) return value.toDouble();
  return double.tryParse(value.toString()) ?? 0;
}

int _toInt(dynamic value) {
  if (value == null) return 0;
  if (value is int) return value;
  if (value is double) return value.round();
  return int.tryParse(value.toString()) ?? 0;
}

double _round2(double value) => (value * 100).roundToDouble() / 100;
