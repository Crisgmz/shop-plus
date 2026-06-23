import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/tokens.dart';
import '../../../shared/formatters/formatters.dart';
import '../../../shared/responsive/responsive_layout.dart';
import '../../../shared/services/dgii_lookup_service.dart';
import '../../../shared/widgets/app_snackbar.dart';
import '../../../shared/widgets/ncf_stock_banner.dart';
import '../../../shared/widgets/print_receipt_dialog.dart';
import '../../../shared/widgets/role_gate.dart';
import '../../cash_register/presentation/cash_register_providers.dart';
import '../../clients/presentation/clients_providers.dart';
import '../../settings/presentation/app_settings_providers.dart';
import '../data/sales_repository.dart';
import 'sales_providers.dart';

class SalesPage extends ConsumerStatefulWidget {
  const SalesPage({super.key});

  @override
  ConsumerState<SalesPage> createState() => _SalesPageState();
}

class _SalesPageState extends ConsumerState<SalesPage> {
  final _searchController = TextEditingController();
  final _notesController = TextEditingController();
  final _saleNumberController = TextEditingController();

  final List<SaleCartItem> _cart = [];

  bool _isSubmitting = false;
  bool _showCart = false;
  // Default: vender sin comprobante (nota de venta no fiscal). El cajero elige
  // un comprobante fiscal (B02/B01/...) solo cuando el cliente lo pide.
  String _receiptType = 'none';
  // Método "primario" — se usa para el draft. El detalle del pago (mixto) se
  // arma en la página 2 (_PaymentDialog) al completar la venta.
  String _paymentMethod = 'cash';
  String? _clientId;

  /// Id de la cuenta GUARDADA (venta `pending`) reabierta en este carrito. Si
  /// no es null, al completar/guardar el POS descarta esa pendiente para
  /// devolver su stock reservado y no duplicarla. Viaja en el draft.
  String? _reopenedHeldSaleId;

  int get _cartLines => _cart.length;
  double get _cartSubtotal =>
      _cart.fold<double>(0, (sum, item) => sum + item.lineSubtotal);
  double get _cartTax =>
      _cart.fold<double>(0, (sum, item) => sum + item.lineTax);
  double get _cartTotal => _cartSubtotal + _cartTax;

  @override
  void initState() {
    super.initState();
    // Restaurar el carrito en curso si el cajero venía armando una venta y
    // navegó a otra sección. Ver [saleDraftProvider].
    final draft = ref.read(saleDraftProvider);
    _cart.addAll(draft.items);
    _receiptType = draft.receiptType;
    // El método primario SIEMPRE arranca en Efectivo; solo es a crédito si el
    // cajero elige "Crédito" como método.
    _paymentMethod = 'cash';
    _clientId = draft.clientId;
    _notesController.text = draft.notes;
    _reopenedHeldSaleId = draft.heldSaleId;

    // Default dinámico del comprobante: si la venta es fresca (sin elección
    // explícita aún) y la sucursal tiene secuencia B02 configurada, arrancar
    // en Consumidor Final (B02). Si no hay B02, queda "Sin comprobante".
    if (_cart.isEmpty && _receiptType == 'none' && _reopenedHeldSaleId == null) {
      WidgetsBinding.instance.addPostFrameCallback((_) async {
        if (!mounted) return;
        final hasB02 = await ref.read(b02SequenceAvailableProvider.future);
        if (!mounted) return;
        if (hasB02 && _receiptType == 'none' && _cart.isEmpty) {
          setState(() => _receiptType = 'consumer_final');
          _persistDraft();
        }
      });
    }
  }

  @override
  void dispose() {
    _searchController.dispose();
    _notesController.dispose();
    _saleNumberController.dispose();
    super.dispose();
  }

  /// Guarda un snapshot del carrito + cabecera en [saleDraftProvider]. Se
  /// llama tras cada cambio (no solo al salir) para que la venta en curso
  /// sobreviva la navegación a otra sección. Guardar en `dispose` no es
  /// confiable: escribir un provider mientras el widget se desmonta puede
  /// no propagarse.
  void _persistDraft() {
    final draft = SaleDraft(
      items: List<SaleCartItem>.from(_cart),
      receiptType: _receiptType,
      paymentMethod: _paymentMethod,
      clientId: _clientId,
      notes: _notesController.text,
      heldSaleId: _reopenedHeldSaleId,
    );
    ref.read(saleDraftProvider.notifier).state = draft;
    // Persistir también a localStorage (web) para sobrevivir recargas.
    saveSaleDraftToStore(draft);
  }

  @override
  Widget build(BuildContext context) {
    final productsAsync = ref.watch(salesProductsProvider);
    final categoriesAsync = ref.watch(salesCategoriesProvider);
    final clientsAsync = ref.watch(salesClientsProvider);
    final selectedCategoryId = ref.watch(salesSelectedCategoryProvider);
    final posMode = ref.watch(posModeProvider);
    final isMobile = ResponsiveLayout.isMobile(context);
    final padding = adaptivePadding(context);

    if (isMobile && _showCart) {
      return Scaffold(
        appBar: AppBar(
          title: Text(
            posMode == PosMode.sale
                ? 'Carrito de Venta'
                : 'Carrito de Devolución',
          ),
          leading: IconButton(
            icon: const Icon(Icons.arrow_back),
            onPressed: () => setState(() => _showCart = false),
          ),
        ),
        body: _buildCartPanel(clientsAsync),
      );
    }

    // Encabezado: título + Caja debajo, y el toggle Venta/Devolución a la
    // derecha (en su lugar de siempre). Vive sobre la columna de productos.
    final header = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: const [
                  Text(
                    'Punto de Venta',
                    style: TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.w900,
                      color: Color(0xFF1E293B),
                    ),
                  ),
                  SizedBox(height: 6),
                  _ActiveCashRegisterChip(),
                ],
              ),
            ),
            const SizedBox(width: AppTokens.s12),
            if (!isMobile)
              _PosModeToggle(mode: posMode, onChange: _changePosMode),
            if (isMobile && _cartLines > 0)
              Padding(
                padding: const EdgeInsets.only(left: 8),
                child: Badge(
                  label: Text('$_cartLines'),
                  child: IconButton(
                    icon: const Icon(Icons.shopping_cart_outlined),
                    onPressed: () => setState(() => _showCart = true),
                  ),
                ),
              ),
          ],
        ),
        if (isMobile) ...[
          const SizedBox(height: AppTokens.s8),
          _PosModeToggle(mode: posMode, onChange: _changePosMode),
        ],
        const SizedBox(height: AppTokens.s10),
        const NcfStockBanner(),
        if (posMode == PosMode.returnMode)
          Align(
            alignment: Alignment.centerRight,
            child: TextButton.icon(
              onPressed: () => context.push('/devoluciones'),
              icon: const Icon(Icons.history_rounded, size: 18),
              label: const Text('Historial'),
            ),
          ),
        const SizedBox(height: AppTokens.s12),
      ],
    );

    // Columna izquierda: header + buscador + grilla de productos.
    final leftColumn = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        header,
        _buildSearchBar(categoriesAsync, selectedCategoryId),
        const SizedBox(height: AppTokens.s12),
        Expanded(child: _buildProductGrid(productsAsync)),
      ],
    );

    return Padding(
      padding: padding,
      child: isMobile
          ? leftColumn
          // Desktop: el carrito sube hasta arriba (toda la altura) al lado de
          // los productos.
          : Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(flex: 5, child: leftColumn),
                const SizedBox(width: AppTokens.s24),
                Expanded(flex: 3, child: _buildCartPanel(clientsAsync)),
              ],
            ),
    );
  }

  Widget _buildSearchBar(
    AsyncValue<List<SalesCategory>> categoriesAsync,
    String? selectedCategoryId,
  ) {
    return Row(
      children: [
        Expanded(
          child: Container(
            height: 48,
            padding: const EdgeInsets.symmetric(horizontal: AppTokens.s16),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(AppTokens.radius),
              border: Border.all(color: const Color(0xFFE2E8F0)),
            ),
            child: Row(
              children: [
                const Icon(
                  Icons.search_rounded,
                  color: Color(0xFF94A3B8),
                  size: 20,
                ),
                const SizedBox(width: AppTokens.s12),
                Expanded(
                  child: TextField(
                    controller: _searchController,
                    onChanged: (v) =>
                        ref.read(salesSearchProvider.notifier).state = v,
                    // La pistola de código de barras "escribe" el código y
                    // manda Enter → lo agregamos directo al carrito.
                    onSubmitted: _onScanSubmitted,
                    textInputAction: TextInputAction.search,
                    decoration: const InputDecoration(
                      hintText: 'Buscar o escanear producto...',
                      border: InputBorder.none,
                      enabledBorder: InputBorder.none,
                      focusedBorder: InputBorder.none,
                      isDense: true,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(width: AppTokens.s10),
        categoriesAsync.when(
          data: (categories) => Container(
            height: 48,
            padding: const EdgeInsets.symmetric(horizontal: 12),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: const Color(0xFFE2E8F0)),
            ),
            child: DropdownButtonHideUnderline(
              child: DropdownButton<String?>(
                value: selectedCategoryId,
                hint: const Text('Categoría', style: TextStyle(fontSize: 13)),
                items: [
                  const DropdownMenuItem(value: null, child: Text('Todas')),
                  ...categories.map(
                    (c) => DropdownMenuItem(value: c.id, child: Text(c.name)),
                  ),
                ],
                onChanged: (v) =>
                    ref.read(salesSelectedCategoryProvider.notifier).state = v,
              ),
            ),
          ),
          loading: () => const SizedBox(
            width: 48,
            height: 48,
            child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
          ),
          error: (_, _) => const SizedBox.shrink(),
        ),
      ],
    );
  }

  Widget _buildProductGrid(AsyncValue<List<SalesProduct>> productsAsync) {
    return productsAsync.when(
      data: (_) {
        // El filtrado vive en salesFilteredProductsProvider — memoizado
        // por (productsAsync × search × categoryId). Evita recalcular en
        // cada keystroke / rebuild.
        final filtered = ref.watch(salesFilteredProductsProvider);
        if (filtered.isEmpty) {
          return const Center(child: Text('No hay productos.'));
        }

        return LayoutBuilder(
          builder: (context, constraints) {
            final columns = (constraints.maxWidth / 150).floor().clamp(2, 8);
            // mainAxisExtent fijo (vs childAspectRatio) permite a Flutter
            // saltar a cualquier fila sin medir las anteriores — mucho
            // más rápido en grids con muchos productos.
            final tileSize =
                ((constraints.maxWidth - (columns - 1) * 12) / columns).clamp(
                  110.0,
                  220.0,
                );
            return GridView.builder(
              padding: const EdgeInsets.only(bottom: 20),
              gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: columns,
                mainAxisSpacing: 12,
                crossAxisSpacing: 12,
                mainAxisExtent: tileSize,
              ),
              itemCount: filtered.length,
              itemBuilder: (context, index) => _ProductCard(
                key: ValueKey(filtered[index].id),
                product: filtered[index],
                onTap: () => _addProductToCart(filtered[index]),
              ),
            );
          },
        );
      },
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => Center(child: Text('Error: $e')),
    );
  }

  Widget _buildCartPanel(AsyncValue<List<SalesClient>> clientsAsync) {
    return Card(
      elevation: 0,
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: const BorderSide(color: Color(0xFFE2E8F0)),
      ),
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(AppTokens.s16),
            child: Column(
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      'Carrito ($_cartLines)',
                      style: const TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 16,
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10),
                      height: 32,
                      decoration: BoxDecoration(
                        color: const Color(0xFFF1F5F9),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: DropdownButtonHideUnderline(
                        child: DropdownButton<String>(
                          value: _receiptType,
                          icon: const Icon(
                            Icons.keyboard_arrow_down_rounded,
                            size: 18,
                          ),
                          style: const TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: Color(0xFF475569),
                          ),
                          items: const [
                            DropdownMenuItem(
                              value: 'none',
                              child: Text('Sin comprobante'),
                            ),
                            DropdownMenuItem(
                              value: 'consumer_final',
                              child: Text('Consumidor Final (B02)'),
                            ),
                            DropdownMenuItem(
                              value: 'fiscal_credit',
                              child: Text('Crédito Fiscal (B01)'),
                            ),
                            DropdownMenuItem(
                              value: 'governmental',
                              child: Text('Gubernamental (B15)'),
                            ),
                            DropdownMenuItem(
                              value: 'special',
                              child: Text('Régimen Especial (B14)'),
                            ),
                            DropdownMenuItem(
                              value: 'export',
                              child: Text('Exportación (B16)'),
                            ),
                          ],
                          onChanged: (v) {
                            setState(() => _receiptType = v!);
                            _persistDraft();
                          },
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                clientsAsync.when(
                  data: (clients) => Row(
                    children: [
                      Expanded(
                        child: _ClientSearchField(
                          currentId: _clientId,
                          clients: clients,
                          onChanged: _onClientChanged,
                        ),
                      ),
                      const SizedBox(width: 6),
                      IconButton(
                        tooltip: 'Nuevo cliente',
                        visualDensity: VisualDensity.compact,
                        icon: const Icon(
                          Icons.person_add_alt_1,
                          color: AppTokens.primary,
                        ),
                        onPressed: _onCreateClientInline,
                      ),
                    ],
                  ),
                  loading: () => const LinearProgressIndicator(),
                  error: (_, _) => const Text('Error al cargar clientes'),
                ),
                if (ref.watch(posModeProvider) == PosMode.returnMode) ...[
                  const SizedBox(height: 12),
                  _SaleNumberSearch(
                    controller: _saleNumberController,
                    isLoading: _isSubmitting,
                    onSearch: _loadSaleIntoReturn,
                  ),
                ],
              ],
            ),
          ),
          const Divider(height: 1),
          Expanded(
            child: _cart.isEmpty
                ? const Center(
                    child: Text(
                      'Carrito vacío',
                      style: TextStyle(color: Color(0xFF94A3B8)),
                    ),
                  )
                : ListView.builder(
                    padding: const EdgeInsets.all(AppTokens.s12),
                    itemCount: _cart.length,
                    itemBuilder: (context, i) => _CartLineTile(
                      key: ValueKey(_cart[i].product.id),
                      item: _cart[i],
                      onRemove: () => _removeItem(i),
                      onPriceChanged: (value) => _setUnitPrice(i, value),
                      onQuantityChanged: (value) => _setQty(i, value),
                      onDiscountChanged: (value) => _setDiscountPct(i, value),
                    ),
                  ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: AppTokens.s16,
              vertical: 8,
            ),
            child: TextField(
              controller: _notesController,
              onChanged: (_) => _persistDraft(),
              decoration: InputDecoration(
                hintText: 'Notas de venta...',
                hintStyle: const TextStyle(fontSize: 12),
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 8,
                ),
                filled: true,
                fillColor: const Color(0xFFF8FAFC),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: BorderSide.none,
                ),
              ),
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(
              horizontal: AppTokens.s16,
              vertical: AppTokens.s12,
            ),
            decoration: const BoxDecoration(
              color: Colors.white,
              border: Border(top: BorderSide(color: Color(0xFFE2E8F0))),
            ),
            child: Column(
              children: [
                _totalLine('Subtotal', money(_cartSubtotal)),
                const SizedBox(height: 2),
                _totalLine('ITBIS (18%)', money(_cartTax)),
                const SizedBox(height: 8),
                Builder(
                  builder: (context) {
                    final isReturn =
                        ref.watch(posModeProvider) == PosMode.returnMode;
                    final totalColor = isReturn
                        ? const Color(0xFFEF4444)
                        : const Color(0xFF2563EB);
                    final totalLabel = isReturn
                        ? '- ${money(_cartTotal)}'
                        : money(_cartTotal);
                    return Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text(
                          'Total',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w800,
                            color: Color(0xFF1E293B),
                          ),
                        ),
                        Text(
                          totalLabel,
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w900,
                            color: totalColor,
                          ),
                        ),
                      ],
                    );
                  },
                ),
                const SizedBox(height: 14),
                Builder(
                  builder: (context) {
                    final isReturn =
                        ref.watch(posModeProvider) == PosMode.returnMode;
                    final enabled = !_isSubmitting && _cart.isNotEmpty;
                    // Página 1: solo la venta. El botón muestra el total y, al
                    // tocarlo (en venta), abre la página 2 de cobro.
                    return Row(
                      children: [
                        Expanded(
                          child: SizedBox(
                            height: 50,
                            child: FilledButton.icon(
                              style: FilledButton.styleFrom(
                                backgroundColor: !enabled
                                    ? const Color(0xFF94A3B8)
                                    : (isReturn
                                          ? const Color(0xFFEF4444)
                                          : const Color(0xFF22C55E)),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(8),
                                ),
                              ),
                              onPressed: !enabled
                                  ? null
                                  : () => isReturn
                                        ? _processReturn()
                                        : _onCompletePressed(),
                              icon: _isSubmitting
                                  ? const SizedBox(
                                      width: 18,
                                      height: 18,
                                      child: CircularProgressIndicator(
                                        color: Colors.white,
                                        strokeWidth: 2,
                                      ),
                                    )
                                  : Icon(
                                      isReturn
                                          ? Icons.assignment_return_outlined
                                          : Icons.check_circle_outline,
                                      size: 18,
                                    ),
                              label: Text(
                                isReturn
                                    ? 'PROCESAR DEVOLUCIÓN'
                                    : 'COMPLETAR VENTA · ${money(_cartTotal)}',
                                style: const TextStyle(
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ),
                          ),
                        ),
                        // Guardar la cuenta como pendiente (cuenta abierta): la
                        // manda al historial en gris y libera el POS para el
                        // siguiente cliente. Solo en modo venta.
                        if (!isReturn) ...[
                          const SizedBox(width: 8),
                          SizedBox(
                            height: 50,
                            child: OutlinedButton.icon(
                              style: OutlinedButton.styleFrom(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 14,
                                ),
                                foregroundColor: const Color(0xFF6B7280),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(8),
                                  side: const BorderSide(
                                    color: Color(0xFFCBD5E1),
                                  ),
                                ),
                              ),
                              onPressed: !enabled ? null : _holdSale,
                              icon: const Icon(Icons.save_outlined, size: 18),
                              label: const Text(
                                'Guardar',
                                style: TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                          ),
                        ],
                        const SizedBox(width: 8),
                        SizedBox(
                          height: 50,
                          child: OutlinedButton(
                            style: OutlinedButton.styleFrom(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 14,
                              ),
                              foregroundColor: const Color(0xFFEF4444),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(8),
                                side: const BorderSide(
                                  color: Color(0xFFFECACA),
                                ),
                              ),
                            ),
                            onPressed: _isSubmitting ? null : _clearCart,
                            child: const Text(
                              'Cancelar',
                              style: TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        ),
                      ],
                    );
                  },
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _totalLine(String label, String value) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          label,
          style: const TextStyle(
            color: Color(0xFF64748B),
            fontSize: 13,
            fontWeight: FontWeight.w500,
          ),
        ),
        Text(
          value,
          style: const TextStyle(
            color: Color(0xFF1E293B),
            fontSize: 13,
            fontWeight: FontWeight.w700,
          ),
        ),
      ],
    );
  }

  /// Tier de precio del cliente actualmente seleccionado. Null si no hay
  /// cliente o si la lista de clientes aún no se cargó.
  String? _currentClientTier() {
    if (_clientId == null) return null;
    return ref.read(salesClientsByIdProvider)[_clientId!]?.priceTier;
  }

  /// Si el setting global "No permitir venta sin stock" está apagado, el
  /// cliente NO bloquea ventas por falta de stock — deja que el RPC lo
  /// valide (o lo permita). Si está prendido, refuerza la validación en UI
  /// para evitar viajes innecesarios al servidor.
  bool get _stockEnforced =>
      ref.read(appSettingsProvider).valueOrNull?.invDisallowNoStock ?? false;

  /// app_settings.inv_disallow_below_cost — si está prendido, no se permite
  /// vender ningún producto por debajo de su costo. Lo decide el dueño con el
  /// toggle de Ajustes › Inventario.
  bool get _belowCostEnforced =>
      ref.read(appSettingsProvider).valueOrNull?.invDisallowBelowCost ?? false;

  bool get _imeiModeEnabled =>
      ref.read(appSettingsProvider).valueOrNull?.invImeiMode ?? false;

  void _addProductToCart(SalesProduct product) {
    // Modo IMEI: si el producto maneja IMEIs y el toggle está activo, hay que
    // elegir cuáles equipos salen (cada IMEI = 1 unidad).
    if (_imeiModeEnabled && product.hasImeis) {
      _pickImeisAndAdd(product);
      return;
    }
    final index = _cart.indexWhere((item) => item.product.id == product.id);
    if (_stockEnforced &&
        index != -1 &&
        _cart[index].quantity + 1 > product.stock) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Sin stock suficiente')));
      return;
    }
    final tier = _currentClientTier();
    final price = product.priceFor(tier);
    setState(() {
      if (index == -1) {
        _cart.add(
          SaleCartItem(product: product, quantity: 1, unitPrice: price),
        );
      } else {
        final current = _cart[index];
        _cart[index] = SaleCartItem(
          product: current.product,
          quantity: current.quantity + 1,
          unitPrice: current.unitPrice,
          discountPct: current.discountPct,
          imeis: current.imeis,
        );
      }
    });
    _persistDraft();
  }

  void _clearSearch() {
    _searchController.clear();
    ref.read(salesSearchProvider.notifier).state = '';
  }

  /// La pistola escaneó un código (o el cajero presionó Enter). Si coincide con
  /// un IMEI → agrega ese equipo directo. Si coincide con código de barras/SKU
  /// → agrega el producto. Si no, deja el texto como filtro de búsqueda.
  void _onScanSubmitted(String raw) {
    final code = raw.trim();
    if (code.isEmpty) return;
    final products = ref.read(salesProductsProvider).valueOrNull ?? const [];

    // 1) ¿Es un IMEI? → agrega ese equipo directo (sin diálogo).
    for (final p in products) {
      if (p.imeis.contains(code)) {
        if (_selectedImeisFor(p.id).contains(code)) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Ese IMEI ya está en el carrito.')),
          );
        } else {
          _addImeiToCart(p, [code]);
        }
        _clearSearch();
        return;
      }
    }

    // 2) ¿Código de barras o SKU exacto? → agrega el producto.
    for (final p in products) {
      if ((p.barcode != null && p.barcode == code) ||
          (p.sku != null && p.sku == code)) {
        _addProductToCart(p);
        _clearSearch();
        return;
      }
    }
    // 3) Sin coincidencia exacta: se queda como filtro de búsqueda normal.
  }

  /// IMEIs que ya están en el carrito para este producto.
  Set<String> _selectedImeisFor(String productId) {
    for (final it in _cart) {
      if (it.product.id == productId) return it.imeis.toSet();
    }
    return const {};
  }

  /// Abre el selector de IMEIs (los que aún no están en el carrito) y agrega
  /// los elegidos. Cada IMEI suma 1 a la cantidad de la línea.
  Future<void> _pickImeisAndAdd(SalesProduct product) async {
    final already = _selectedImeisFor(product.id);
    final available = product.imeis
        .where((i) => !already.contains(i))
        .toList(growable: false);
    if (available.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Todos los IMEIs de este producto ya están en el carrito.',
          ),
        ),
      );
      return;
    }
    final selected = await showDialog<List<String>>(
      context: context,
      builder: (_) =>
          _ImeiPickerDialog(productName: product.name, imeis: available),
    );
    if (selected == null || selected.isEmpty || !mounted) return;
    _addImeiToCart(product, selected);
  }

  /// Agrega (o mezcla) una línea de producto con IMEIs seleccionados.
  void _addImeiToCart(SalesProduct product, List<String> imeis) {
    final tier = _currentClientTier();
    final price = product.priceFor(tier);
    setState(() {
      final index = _cart.indexWhere((it) => it.product.id == product.id);
      if (index == -1) {
        _cart.add(
          SaleCartItem(
            product: product,
            quantity: imeis.length.toDouble(),
            unitPrice: price,
            imeis: List<String>.from(imeis),
          ),
        );
      } else {
        final cur = _cart[index];
        final merged = [...cur.imeis, ...imeis];
        _cart[index] = SaleCartItem(
          product: cur.product,
          quantity: merged.length.toDouble(),
          unitPrice: cur.unitPrice,
          discountPct: cur.discountPct,
          imeis: merged,
        );
      }
    });
    _persistDraft();
  }

  /// Setea la cantidad a un valor específico (desde el input del cart line).
  /// Si es <= 0 elimina el item.
  void _setQty(int index, double value) {
    if (value <= 0) {
      _removeItem(index);
      return;
    }
    final item = _cart[index];
    if (_stockEnforced && value > item.product.stock) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Sin stock suficiente')));
      return;
    }
    setState(
      () => _cart[index] = SaleCartItem(
        product: item.product,
        quantity: value,
        unitPrice: item.unitPrice,
        discountPct: item.discountPct,
        imeis: item.imeis,
      ),
    );
    _persistDraft();
  }

  /// Setea el precio unitario de una línea (override manual).
  void _setUnitPrice(int index, double value) {
    if (value < 0) return;
    final item = _cart[index];
    if (_belowCostEnforced && value < item.product.cost) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Precio por debajo del costo (${money(item.product.cost)}).',
          ),
        ),
      );
    }
    setState(
      () => _cart[index] = SaleCartItem(
        product: item.product,
        quantity: item.quantity,
        unitPrice: value,
        discountPct: item.discountPct,
        imeis: item.imeis,
      ),
    );
    _persistDraft();
  }

  /// Setea el descuento porcentual de una línea (0-100).
  void _setDiscountPct(int index, double value) {
    final clamped = value.clamp(0, 100).toDouble();
    final item = _cart[index];
    setState(
      () => _cart[index] = SaleCartItem(
        product: item.product,
        quantity: item.quantity,
        unitPrice: item.unitPrice,
        discountPct: clamped,
        imeis: item.imeis,
      ),
    );
    _persistDraft();
  }

  /// Cuando cambia el cliente, re-precia las líneas del carrito según el
  /// nuevo tier. Si el nuevo cliente es null o "retail", vuelve al precio
  /// base de cada producto.
  void _onClientChanged(String? newId) {
    setState(() {
      _clientId = newId;
      if (_cart.isEmpty) return;
      final tier = newId == null
          ? null
          : ref.read(salesClientsByIdProvider)[newId]?.priceTier;
      for (var i = 0; i < _cart.length; i++) {
        final item = _cart[i];
        _cart[i] = SaleCartItem(
          product: item.product,
          quantity: item.quantity,
          unitPrice: item.product.priceFor(tier),
          discountPct: item.discountPct,
          imeis: item.imeis,
        );
      }
    });
    _persistDraft();
  }

  /// Crea un cliente rápido sin salir de la venta y lo selecciona.
  Future<void> _onCreateClientInline() async {
    final result = await showDialog<_QuickClientData>(
      context: context,
      builder: (_) => const _QuickClientDialog(),
    );
    if (result == null || !mounted) return;
    try {
      final id = await ref
          .read(clientsRepositoryProvider)
          .createQuickClient(
            fullName: result.name,
            phone: result.phone,
            documentNumber: result.document,
          );
      ref.invalidate(salesClientsProvider);
      await ref.read(salesClientsProvider.future);
      if (!mounted) return;
      _onClientChanged(id);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Cliente creado y seleccionado.')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('No se pudo crear el cliente: $e')),
      );
    }
  }

  void _removeItem(int index) {
    setState(() => _cart.removeAt(index));
    _persistDraft();
  }

  void _clearCart() {
    setState(() {
      _cart.clear();
      _notesController.clear();
      _clientId = null;
      _paymentMethod = 'cash';
      _reopenedHeldSaleId = null;
      _searchController.clear();
      ref.read(salesSearchProvider.notifier).state = '';
    });
    _persistDraft();
  }

  /// Guarda el carrito como una cuenta PENDIENTE (cuenta abierta). Reserva el
  /// stock, la deja en el historial en gris y limpia el POS para atender al
  /// siguiente cliente. No cobra ni entra al cierre de caja hasta completarla.
  Future<void> _holdSale() async {
    if (_cart.isEmpty) return;
    setState(() => _isSubmitting = true);
    try {
      final repo = ref.read(salesRepositoryProvider);
      final settings = ref.read(appSettingsProvider).valueOrNull;
      // Si esta cuenta venía reabierta, el backend reemplaza la pendiente
      // anterior conservando su MISMO número y liberando su stock, en una sola
      // operación. Así una cuenta abierta mantiene su número aunque se le sigan
      // agregando productos. _clearCart() limpia _reopenedHeldSaleId en éxito.
      final result = await repo.holdSale(
        HeldSaleInput(
          items: List.from(_cart),
          receiptType: _receiptType,
          clientId: _clientId,
          notes: _notesController.text.trim(),
          disallowNoStock: settings?.invDisallowNoStock ?? false,
          customerRequiredForSale: settings?.customerRequiredForSale ?? false,
          replaceHoldSaleId: _reopenedHeldSaleId,
        ),
      );
      ref.invalidate(salesProductsProvider);
      if (!mounted) return;
      _clearCart();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: const Color(0xFF16A34A),
          content: Text(
            'Cuenta guardada como pendiente (${result.saleNumber}).',
          ),
        ),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: Colors.red,
          content: Text('No se pudo guardar la cuenta: $error'),
        ),
      );
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  /// Abre la página 2 (diálogo de cobro con métodos divididos). Según el
  /// resultado, finaliza la venta normal o la manda a crédito.
  /// Pre-chequeo fiscal: un comprobante ≠ consumidor final (Crédito Fiscal,
  /// Gubernamental, Especial, Exportación) exige un cliente con RNC/cédula.
  /// Espeja la regla del trigger SQL `tg_sales_assert_fiscal_client` para
  /// avisar ANTES de abrir el cobro, en vez de fallar al confirmar.
  bool _assertFiscalClient() {
    if (_receiptType == 'none' || _receiptType == 'consumer_final') return true;
    final client = _clientId == null
        ? null
        : ref.read(salesClientsByIdProvider)[_clientId!];
    if (client != null && client.hasFiscalData) return true;
    AppSnackBar.error(
      context,
      client == null
          ? 'Para un comprobante fiscal debe seleccionar un cliente con RNC/cédula.'
          : 'El cliente "${client.fullName}" no tiene RNC/cédula. Edítalo o usa Consumidor Final.',
    );
    return false;
  }

  Future<void> _onCompletePressed() async {
    if (_cart.isEmpty) return;
    if (!_assertFiscalClient()) return;
    final result = await showDialog<_PaymentResult>(
      context: context,
      builder: (_) => _PaymentDialog(total: _cartTotal),
    );
    if (result == null || !mounted) return;
    if (result.asCredit) {
      await _confirmCreditCheckout();
    } else {
      await _checkout(asCredit: false, payments: result.payments);
    }
  }

  /// Abre un diálogo que pide los días de plazo (default desde settings) y
  /// luego ejecuta el checkout a crédito.
  Future<void> _confirmCreditCheckout() async {
    if (_cart.isEmpty) return;
    if (_clientId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Para ventas a crédito debe seleccionar un cliente.'),
        ),
      );
      return;
    }
    final settings = ref.read(appSettingsProvider).valueOrNull;
    final defaultDays = settings?.creditDefaultDays ?? 30;
    final controller = TextEditingController(text: defaultDays.toString());
    final today = DateTime.now();

    int parseDays() {
      final raw = int.tryParse(controller.text.trim()) ?? defaultDays;
      return raw.clamp(1, 365);
    }

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setLocal) {
          final days = parseDays();
          final due = today.add(Duration(days: days));
          return AlertDialog(
            title: const Text('Venta a crédito'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Total: ${money(_cartTotal)}',
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: controller,
                  keyboardType: TextInputType.number,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  decoration: const InputDecoration(
                    labelText: 'Días de plazo',
                    isDense: true,
                    border: OutlineInputBorder(),
                  ),
                  onChanged: (_) => setLocal(() {}),
                ),
                const SizedBox(height: 8),
                Text(
                  'Vence: ${due.day.toString().padLeft(2, '0')}/'
                  '${due.month.toString().padLeft(2, '0')}/${due.year}',
                  style: TextStyle(
                    fontSize: 12,
                    color: AppTokens.mutedForeground,
                  ),
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('Cancelar'),
              ),
              FilledButton.icon(
                onPressed: () => Navigator.pop(ctx, true),
                icon: const Icon(Icons.check, size: 18),
                label: const Text('Confirmar'),
              ),
            ],
          );
        },
      ),
    );

    if (confirmed == true) {
      await _checkout(asCredit: true, creditDueDays: parseDays());
    }
    controller.dispose();
  }

  Future<void> _checkout({
    required bool asCredit,
    int? creditDueDays,
    List<SalePaymentLine> payments = const [],
  }) async {
    if (_cart.isEmpty) return;
    if (asCredit && _clientId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Para ventas a crédito debe seleccionar un cliente.'),
        ),
      );
      return;
    }

    // app_settings.inv_disallow_below_cost — bloquea registrar la venta si
    // algún producto se está vendiendo por debajo de su costo (precio neto,
    // ya descontado). Solo aplica cuando el dueño activa el flag.
    if (_belowCostEnforced) {
      for (final item in _cart) {
        final netUnit = item.unitPrice * (1 - item.discountPct / 100);
        if (netUnit < item.product.cost) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              backgroundColor: Colors.red,
              content: Text(
                'No puedes vender ${item.product.name} por debajo del costo '
                '(${money(item.product.cost)}).',
              ),
            ),
          );
          return;
        }
      }
    }

    setState(() => _isSubmitting = true);
    try {
      final repo = ref.read(salesRepositoryProvider);
      final settings = ref.read(appSettingsProvider).valueOrNull;
      final pays = asCredit ? const <SalePaymentLine>[] : payments;
      // Para pago único, el método representativo es el de la línea efectiva.
      final repMethod = pays.isNotEmpty ? pays.first.method : 'cash';
      // Sobrepago = lo que el cliente pagó de más. Ese exceso se devuelve en
      // efectivo (sale de la caja), sin importar el método facturado, así que
      // lo mandamos para que el backend lo registre como cambio.
      final paySum = pays.fold<double>(0, (s, p) => s + p.amount);
      final change = paySum - _cartTotal;
      final result = await repo.checkoutSale(
        SaleCheckoutInput(
          items: List.from(_cart),
          receiptType: _receiptType,
          asCredit: asCredit,
          paymentMethod: asCredit ? null : repMethod,
          payments: pays,
          changeAmount: change > 0.005 ? change : 0,
          clientId: _clientId,
          notes: _notesController.text.trim(),
          disallowNoStock: settings?.invDisallowNoStock ?? false,
          customerRequiredForSale: settings?.customerRequiredForSale ?? false,
          creditAllowSales: settings?.creditAllowSales ?? true,
          creditDueDays: creditDueDays,
          cashSessionId: ref.read(activeCashSessionIdProvider),
          // Si esta venta viene de una cuenta GUARDADA reabierta, el backend la
          // absorbe: conserva su mismo número y libera su stock reservado. En
          // éxito, _clearCart() limpia _reopenedHeldSaleId.
          holdSaleIdToComplete: _reopenedHeldSaleId,
        ),
      );

      _clearCart();
      ref.invalidate(salesProductsProvider);

      if (!mounted) return;

      final printJob = result.preparedPrintJob;
      final printAfterSale = settings?.receiptPrintAfterSale ?? true;
      final disableConfirmation =
          settings?.saleDisableCompleteConfirmation ?? true;

      // Auto-imprimir si app_settings.receipt_print_after_sale = true.
      if (printJob != null && printAfterSale) {
        await PrintReceiptDialog.show(context, printJob);
        if (!mounted) return;
      }

      // Si app_settings.sale_disable_complete_confirmation = true, mostrar
      // solo un toast y no bloquear con un diálogo.
      if (disableConfirmation) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            backgroundColor: AppTokens.success,
            content: Text(
              result.ncf != null
                  ? 'Venta #${result.saleNumber} registrada. NCF: ${result.ncf}'
                  : 'Venta #${result.saleNumber} registrada.',
              style: const TextStyle(color: AppTokens.successForeground),
            ),
          ),
        );
      } else {
        await showDialog(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text('¡Venta exitosa!'),
            content: Text(
              result.ncf != null
                  ? 'Venta #${result.saleNumber} registrada correctamente.\n'
                        'Comprobante NCF: ${result.ncf}'
                  : 'Venta #${result.saleNumber} registrada correctamente.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('Cerrar'),
              ),
              if (printJob != null && !printAfterSale)
                FilledButton.icon(
                  onPressed: () {
                    Navigator.pop(ctx);
                    PrintReceiptDialog.show(context, printJob);
                  },
                  icon: const Icon(Icons.receipt_long_outlined, size: 18),
                  label: const Text('Ver recibo'),
                ),
            ],
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        AppSnackBar.error(context, 'No se pudo procesar la venta', e);
      }
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  /// Cambia entre modo Venta y Devolución.
  /// Si el carrito tiene items, pide confirmación antes de descartarlo.
  Future<void> _changePosMode(PosMode next) async {
    final current = ref.read(posModeProvider);
    if (current == next) return;

    if (_cart.isNotEmpty) {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Descartar carrito'),
          content: Text(
            'Tienes $_cartLines artículo(s) en el carrito. '
            'Cambiar de modo descartará el carrito actual. ¿Continuar?',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancelar'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Descartar'),
            ),
          ],
        ),
      );
      if (confirmed != true) return;
      _clearCart();
    }

    ref.read(posModeProvider.notifier).state = next;
  }

  /// Busca una venta por número y precarga sus items en el carrito (devolución).
  Future<void> _loadSaleIntoReturn(String saleNumber) async {
    final cleaned = saleNumber.trim();
    if (cleaned.isEmpty) return;

    setState(() => _isSubmitting = true);
    try {
      final repo = ref.read(salesRepositoryProvider);
      final result = await repo.fetchSaleForReturn(cleaned);
      if (!mounted) return;

      if (result == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'No se encontró la venta "$cleaned" en esta sucursal.',
            ),
            backgroundColor: const Color(0xFFEF4444),
          ),
        );
        return;
      }
      if (result.items.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'La venta no tiene items recuperables '
              '(¿productos inactivos o eliminados?).',
            ),
          ),
        );
        return;
      }

      setState(() {
        _cart
          ..clear()
          ..addAll(result.items);
        // Cliente original si aplica
        if (result.clientId != null && result.clientId!.isNotEmpty) {
          _clientId = result.clientId;
        }
        // Notas con referencia a la venta original
        _notesController.text = 'Devolución de venta ${result.saleNumber}';
        _saleNumberController.clear();
      });
      _persistDraft();

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: const Color(0xFF22C55E),
          content: Text(
            'Venta ${result.saleNumber} cargada · '
            '${result.items.length} línea(s).',
            style: const TextStyle(color: Colors.white),
          ),
        ),
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Error al cargar la venta: $e')));
      }
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  /// Procesa una devolución a partir del carrito actual.
  Future<void> _processReturn() async {
    if (_cart.isEmpty) return;

    setState(() => _isSubmitting = true);
    try {
      final repo = ref.read(salesRepositoryProvider);
      final result = await repo.processReturn(
        ReturnInput(
          items: List.from(_cart),
          clientId: _clientId,
          notes: _notesController.text.trim(),
        ),
      );

      _clearCart();
      ref.invalidate(salesProductsProvider);

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: const Color(0xFFEF4444),
          content: Text(
            'Devolución #${result.returnNumber} registrada · '
            '${result.itemsCount} artículo(s)'
            '${result.creditBalanceAdjusted ? " · saldo de cliente ajustado" : ""}.',
            style: const TextStyle(color: Colors.white),
          ),
        ),
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error al procesar devolución: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }
}

/// Datos del cliente rápido creado desde Ventas.
class _QuickClientData {
  const _QuickClientData({
    required this.name,
    required this.phone,
    required this.document,
  });

  final String name;
  final String phone;
  final String document;
}

/// Diálogo compacto para crear un cliente sin salir de la venta.
class _QuickClientDialog extends StatefulWidget {
  const _QuickClientDialog();

  @override
  State<_QuickClientDialog> createState() => _QuickClientDialogState();
}

class _QuickClientDialogState extends State<_QuickClientDialog> {
  final _formKey = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _phone = TextEditingController();
  final _doc = TextEditingController();
  final _dgii = DgiiLookupService();
  bool _rncLookupLoading = false;

  @override
  void dispose() {
    _name.dispose();
    _phone.dispose();
    _doc.dispose();
    super.dispose();
  }

  /// Consulta el RNC/cédula contra DGII y auto-completa el nombre.
  Future<void> _lookupRnc() async {
    final raw = _doc.text.trim();
    if (raw.isEmpty) {
      AppSnackBar.info(context, 'Escribe el RNC o cédula primero.');
      return;
    }
    setState(() => _rncLookupLoading = true);
    try {
      final info = await _dgii.lookupByRnc(raw);
      if (!mounted) return;
      if (info == null) {
        AppSnackBar.error(context, 'RNC/cédula no encontrado en DGII.');
        return;
      }
      final name = info.nombreRazonSocial ?? info.displayName;
      if (name != null && name.isNotEmpty && _name.text.trim().isEmpty) {
        setState(() => _name.text = name);
      }
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
    return AlertDialog(
      title: const Text('Nuevo cliente'),
      content: SizedBox(
        width: 360,
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextFormField(
                controller: _name,
                autofocus: true,
                textCapitalization: TextCapitalization.words,
                decoration: const InputDecoration(labelText: 'Nombre completo'),
                validator: (v) =>
                    (v ?? '').trim().isEmpty ? 'Campo requerido' : null,
              ),
              const SizedBox(height: 10),
              TextFormField(
                controller: _phone,
                keyboardType: TextInputType.phone,
                decoration: const InputDecoration(
                  labelText: 'Teléfono (opcional)',
                ),
              ),
              const SizedBox(height: 10),
              TextFormField(
                controller: _doc,
                keyboardType: TextInputType.number,
                onFieldSubmitted: (_) => _lookupRnc(),
                decoration: InputDecoration(
                  labelText: 'Cédula / RNC (opcional)',
                  suffixIcon: _rncLookupLoading
                      ? const Padding(
                          padding: EdgeInsets.all(10),
                          child: SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          ),
                        )
                      : IconButton(
                          tooltip: 'Buscar razón social en DGII',
                          icon: const Icon(Icons.search),
                          onPressed: _lookupRnc,
                        ),
                ),
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
        FilledButton(
          onPressed: () {
            if (!_formKey.currentState!.validate()) return;
            Navigator.of(context).pop(
              _QuickClientData(
                name: _name.text.trim(),
                phone: _phone.text.trim(),
                document: _doc.text.trim(),
              ),
            );
          },
          child: const Text('Crear'),
        ),
      ],
    );
  }
}

/// Selector de IMEIs al vender un producto serializado. Devuelve la lista de
/// IMEIs marcados, o null si se cancela.
class _ImeiPickerDialog extends StatefulWidget {
  const _ImeiPickerDialog({required this.productName, required this.imeis});

  final String productName;
  final List<String> imeis;

  @override
  State<_ImeiPickerDialog> createState() => _ImeiPickerDialogState();
}

class _ImeiPickerDialogState extends State<_ImeiPickerDialog> {
  final Set<String> _selected = {};

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text('IMEI · ${widget.productName}'),
      content: SizedBox(
        width: 380,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Selecciona los equipos que salen a la venta:',
              style: TextStyle(fontSize: 13, color: Color(0xFF64748B)),
            ),
            const SizedBox(height: 8),
            Flexible(
              child: SingleChildScrollView(
                child: Column(
                  children: [
                    for (final imei in widget.imeis)
                      CheckboxListTile(
                        dense: true,
                        contentPadding: EdgeInsets.zero,
                        controlAffinity: ListTileControlAffinity.leading,
                        value: _selected.contains(imei),
                        title: Text(
                          'IMEI  $imei',
                          style: const TextStyle(
                            fontFamily: 'monospace',
                            fontSize: 14,
                          ),
                        ),
                        onChanged: (v) => setState(() {
                          if (v == true) {
                            _selected.add(imei);
                          } else {
                            _selected.remove(imei);
                          }
                        }),
                      ),
                  ],
                ),
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
        FilledButton.icon(
          onPressed: _selected.isEmpty
              ? null
              : () => Navigator.of(context).pop(_selected.toList()),
          icon: const Icon(Icons.check_circle_outline, size: 18),
          label: Text('Confirmar (${_selected.length})'),
        ),
      ],
    );
  }
}

/// Una línea de pago en el carrito (pago dividido): método + monto editable.
class _PayLine {
  _PayLine({required this.method}) : amount = TextEditingController();

  String method;
  final TextEditingController amount;

  double get value {
    final raw = amount.text.trim().replaceAll(',', '');
    return double.tryParse(raw) ?? 0;
  }
}

/// Resultado de la página de pago: las líneas de pago (vacío si es crédito) y
/// si la venta debe ir a crédito.
class _PaymentResult {
  const _PaymentResult({required this.payments, required this.asCredit});

  final List<SalePaymentLine> payments;
  final bool asCredit;
}

/// Página 2 (diálogo) de cobro: métodos de pago divididos que suman el total.
/// Devuelve un [_PaymentResult] al confirmar, o null si se cancela.
class _PaymentDialog extends StatefulWidget {
  const _PaymentDialog({required this.total});

  final double total;

  @override
  State<_PaymentDialog> createState() => _PaymentDialogState();
}

class _PaymentDialogState extends State<_PaymentDialog> {
  final List<_PayLine> _lines = [];
  bool _touched = false;

  static const List<MapEntry<String, String>> _methods = [
    MapEntry('cash', 'Efectivo'),
    MapEntry('transfer', 'Transferencia'),
    MapEntry('card', 'Tarjeta'),
    MapEntry('other', 'Otro'),
    MapEntry('credit', 'Crédito'),
  ];

  @override
  void initState() {
    super.initState();
    _lines
      ..add(_PayLine(method: 'cash'))
      ..add(_PayLine(method: 'cash'));
    _sync();
  }

  @override
  void dispose() {
    for (final line in _lines) {
      line.amount.dispose();
    }
    super.dispose();
  }

  /// Cambio a devolver = lo que paga de más (suma de pagos − total).
  double get _change {
    final diff = _sum - widget.total;
    return diff > 0 ? diff : 0;
  }

  String _fmt(double v) {
    if (v <= 0) return '';
    return v == v.roundToDouble() ? v.toStringAsFixed(0) : v.toStringAsFixed(2);
  }

  void _sync() {
    final total = widget.total;
    if (!_touched) _lines.first.amount.text = _fmt(total);
    var sumEditable = 0.0;
    for (var i = 0; i < _lines.length - 1; i++) {
      sumEditable += _lines[i].value;
    }
    final remainder = total - sumEditable;
    _lines.last.amount.text = _fmt(remainder < 0 ? 0 : remainder);
  }

  double get _sum => _lines.fold<double>(0, (s, l) => s + l.value);
  // Válido cuando los pagos cubren el total (pueden pagar de más → cambio).
  bool get _valid => widget.total > 0 && _sum + 0.01 >= widget.total;
  bool get _anyCredit => _lines.any((l) => l.method == 'credit' && l.value > 0);

  List<SalePaymentLine> _payments() => _lines
      .where((l) => l.value > 0)
      .map((l) => SalePaymentLine(method: l.method, amount: l.value))
      .toList(growable: false);

  void _add() => setState(() {
    _lines.add(_PayLine(method: 'cash'));
    _sync();
  });

  void _remove(int i) {
    if (_lines.length <= 2) return;
    setState(() {
      _lines.removeAt(i).amount.dispose();
      _sync();
    });
  }

  void _onAmount() => setState(() {
    _touched = true;
    _sync();
  });

  @override
  Widget build(BuildContext context) {
    const contentPad = EdgeInsets.symmetric(horizontal: 10, vertical: 8);
    OutlineInputBorder border() => OutlineInputBorder(
      borderRadius: BorderRadius.circular(8),
      borderSide: const BorderSide(color: Color(0xFFCBD5E1)),
    );

    return AlertDialog(
      title: const Text('Completar venta'),
      content: SizedBox(
        width: 420,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  'Total a pagar',
                  style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
                ),
                Text(
                  money(widget.total),
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w900,
                    color: Color(0xFF2563EB),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            for (var i = 0; i < _lines.length; i++)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Row(
                  children: [
                    Expanded(
                      flex: 5,
                      child: SizedBox(
                        height: 40,
                        child: TextField(
                          controller: _lines[i].amount,
                          readOnly: i == _lines.length - 1,
                          style: const TextStyle(fontSize: 14),
                          keyboardType: const TextInputType.numberWithOptions(
                            decimal: true,
                          ),
                          onChanged: (_) => _onAmount(),
                          decoration: InputDecoration(
                            isDense: true,
                            contentPadding: contentPad,
                            hintText: i == _lines.length - 1
                                ? 'Resto'
                                : 'Monto',
                            prefixText: 'RD\$ ',
                            filled: i == _lines.length - 1,
                            fillColor: const Color(0xFFF1F5F9),
                            border: border(),
                            enabledBorder: border(),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      flex: 4,
                      child: SizedBox(
                        height: 40,
                        child: DropdownButtonFormField<String>(
                          initialValue: _lines[i].method,
                          isExpanded: true,
                          style: const TextStyle(
                            fontSize: 14,
                            color: Color(0xFF1E293B),
                          ),
                          decoration: InputDecoration(
                            isDense: true,
                            contentPadding: contentPad,
                            border: border(),
                            enabledBorder: border(),
                          ),
                          items: _methods
                              .map(
                                (m) => DropdownMenuItem(
                                  value: m.key,
                                  child: Text(
                                    m.value,
                                    style: const TextStyle(fontSize: 14),
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                              )
                              .toList(growable: false),
                          onChanged: (v) =>
                              setState(() => _lines[i].method = v ?? 'cash'),
                        ),
                      ),
                    ),
                    SizedBox(
                      width: 32,
                      child: i == _lines.length - 1
                          ? IconButton(
                              padding: EdgeInsets.zero,
                              visualDensity: VisualDensity.compact,
                              tooltip: 'Agregar método',
                              icon: const Icon(
                                Icons.add_circle_outline,
                                size: 22,
                                color: Color(0xFF2563EB),
                              ),
                              onPressed: _add,
                            )
                          : (_lines.length > 2
                                ? IconButton(
                                    padding: EdgeInsets.zero,
                                    visualDensity: VisualDensity.compact,
                                    tooltip: 'Quitar',
                                    icon: const Icon(
                                      Icons.remove_circle_outline,
                                      size: 20,
                                      color: Color(0xFFEF4444),
                                    ),
                                    onPressed: () => _remove(i),
                                  )
                                : null),
                    ),
                  ],
                ),
              ),
            if (_anyCredit)
              const Text(
                'Esta venta irá a crédito (requiere cliente).',
                style: TextStyle(
                  color: Color(0xFF2563EB),
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              )
            else if (!_valid && widget.total > 0)
              Text(
                'Falta ${money(widget.total - _sum)} para cubrir el total',
                style: const TextStyle(
                  color: Color(0xFFEF4444),
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
            // Valor a devolver = lo que pagó de más (cambio en efectivo).
            if (!_anyCredit) ...[
              const Divider(height: 20),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text(
                    'Valor a devolver (cambio)',
                    style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
                  ),
                  Text(
                    money(_change),
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w900,
                      color: _change > 0
                          ? const Color(0xFF2563EB)
                          : const Color(0xFF64748B),
                    ),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancelar'),
        ),
        FilledButton.icon(
          style: FilledButton.styleFrom(
            backgroundColor: const Color(0xFF22C55E),
          ),
          onPressed: (_valid || _anyCredit)
              ? () => Navigator.of(context).pop(
                  _PaymentResult(
                    payments: _anyCredit ? const [] : _payments(),
                    asCredit: _anyCredit,
                  ),
                )
              : null,
          icon: const Icon(Icons.check_circle_outline, size: 18),
          label: const Text(
            'Confirmar venta',
            style: TextStyle(fontWeight: FontWeight.w700),
          ),
        ),
      ],
    );
  }
}

class _PosModeToggle extends ConsumerWidget {
  const _PosModeToggle({required this.mode, required this.onChange});

  final PosMode mode;
  final Future<void> Function(PosMode next) onChange;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final access = ref.watch(roleAccessProvider);
    return Row(
      children: [
        _ModePill(
          label: 'Venta',
          icon: Icons.shopping_cart_outlined,
          color: const Color(0xFF22C55E),
          isActive: mode == PosMode.sale,
          onTap: () => onChange(PosMode.sale),
        ),
        if (access.canVoidSale) ...[
          const SizedBox(width: AppTokens.s10),
          _ModePill(
            label: 'Devolución',
            icon: Icons.assignment_return_outlined,
            color: const Color(0xFFEF4444),
            isActive: mode == PosMode.returnMode,
            onTap: () => onChange(PosMode.returnMode),
          ),
        ],
      ],
    );
  }
}

class _SaleNumberSearch extends StatelessWidget {
  const _SaleNumberSearch({
    required this.controller,
    required this.isLoading,
    required this.onSearch,
  });

  final TextEditingController controller;
  final bool isLoading;
  final Future<void> Function(String saleNumber) onSearch;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: const Color(0xFFFEF2F2),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xFFFCA5A5)),
      ),
      child: Row(
        children: [
          const Icon(
            Icons.assignment_return_outlined,
            size: 18,
            color: Color(0xFFEF4444),
          ),
          const SizedBox(width: AppTokens.s8),
          Expanded(
            child: TextField(
              controller: controller,
              enabled: !isLoading,
              textInputAction: TextInputAction.search,
              onSubmitted: onSearch,
              decoration: const InputDecoration(
                isDense: true,
                border: InputBorder.none,
                hintText: 'Número de venta original (ej: FA-00123)',
                hintStyle: TextStyle(fontSize: 13),
              ),
            ),
          ),
          IconButton(
            icon: const Icon(
              Icons.search_rounded,
              color: Color(0xFFEF4444),
              size: 20,
            ),
            tooltip: 'Cargar items de la venta',
            onPressed: isLoading ? null : () => onSearch(controller.text),
            visualDensity: VisualDensity.compact,
          ),
        ],
      ),
    );
  }
}

class _ModePill extends StatelessWidget {
  const _ModePill({
    required this.label,
    required this.icon,
    required this.color,
    required this.isActive,
    required this.onTap,
  });

  final String label;
  final IconData icon;
  final Color color;
  final bool isActive;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: isActive ? color : color.withValues(alpha: 0.18),
      borderRadius: BorderRadius.circular(24),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: AppTokens.s16,
            vertical: AppTokens.s10,
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 18, color: isActive ? Colors.white : color),
              const SizedBox(width: AppTokens.s8),
              Text(
                label,
                style: TextStyle(
                  color: isActive ? Colors.white : color,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ProductCard extends StatelessWidget {
  const _ProductCard({super.key, required this.product, required this.onTap});
  final SalesProduct product;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final initial = product.name.isNotEmpty
        ? product.name[0].toUpperCase()
        : '?';
    final isLowStock = product.stock <= 5;

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      // Stack para superponer el badge de stock en la esquina superior
      // derecha sin alterar el layout interior de la tarjeta.
      child: Stack(
        fit: StackFit.expand,
        children: [
          // Tarjeta plana: borde gris visible, fondo blanco, contenido
          // centrado (inicial grande, nombre y precio).
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.white,
              border: Border.all(color: const Color(0xFFCBD5E1), width: 1),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Imagen ocupa la mayor parte de la tarjeta: usa
                // AspectRatio para mantenerse cuadrada y Expanded para
                // adaptarse al alto disponible según las columnas.
                Expanded(
                  child: Center(
                    child: AspectRatio(
                      aspectRatio: 1,
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(10),
                        child: Container(
                          color: const Color(0xFFF1F5F9),
                          child:
                              product.imageUrl != null &&
                                  product.imageUrl!.trim().isNotEmpty
                              ? Image.network(
                                  product.imageUrl!,
                                  fit: BoxFit.cover,
                                  // Decodificar a tamaño de pantalla (2x
                                  // para retina). Evita gastar memoria
                                  // decodificando una imagen de 2MB para
                                  // un tile de 165 px.
                                  cacheWidth: 360,
                                  cacheHeight: 360,
                                  filterQuality: FilterQuality.medium,
                                  errorBuilder: (_, _, _) => Center(
                                    child: Text(
                                      initial,
                                      style: const TextStyle(
                                        color: Color(0xFF2563EB),
                                        fontWeight: FontWeight.w800,
                                        fontSize: 32,
                                      ),
                                    ),
                                  ),
                                )
                              : Center(
                                  child: Text(
                                    initial,
                                    style: const TextStyle(
                                      color: Color(0xFF2563EB),
                                      fontWeight: FontWeight.w800,
                                      fontSize: 32,
                                    ),
                                  ),
                                ),
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  product.name,
                  textAlign: TextAlign.center,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: Color(0xFF334155),
                    height: 1.2,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  money(product.price),
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w800,
                    color: Color(0xFF2563EB),
                  ),
                ),
                if (isLowStock) ...[
                  const SizedBox(height: 6),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 6,
                      vertical: 2,
                    ),
                    decoration: BoxDecoration(
                      color: const Color(0xFFFEE2E2),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: const Text(
                      'Bajo stock',
                      style: TextStyle(
                        fontSize: 9,
                        color: Color(0xFFB91C1C),
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
          Positioned(
            top: 8,
            right: 8,
            child: _StockBadge(stock: product.stock),
          ),
        ],
      ),
    );
  }
}

/// Badge circular con la cantidad en existencia. Color según nivel:
///   - rojo si 0
///   - ámbar si ≤ 5
///   - verde si > 5
class _StockBadge extends StatelessWidget {
  const _StockBadge({required this.stock});

  final double stock;

  @override
  Widget build(BuildContext context) {
    final (bg, fg) = switch (stock) {
      <= 0 => (const Color(0xFFDC2626), Colors.white),
      <= 5 => (const Color(0xFFF59E0B), Colors.white),
      _ => (const Color(0xFF16A34A), Colors.white),
    };
    // Formato: entero si es redondo, una decimal si no.
    final label = stock == stock.roundToDouble()
        ? stock.toInt().toString()
        : stock.toStringAsFixed(1);

    return Container(
      constraints: const BoxConstraints(minWidth: 22, minHeight: 22),
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(11),
        border: Border.all(color: Colors.white, width: 1.5),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.15),
            blurRadius: 3,
            offset: const Offset(0, 1),
          ),
        ],
      ),
      child: Center(
        child: Text(
          label,
          style: TextStyle(
            color: fg,
            fontSize: 11,
            fontWeight: FontWeight.w800,
            height: 1,
          ),
        ),
      ),
    );
  }
}

/// Línea del carrito con campos editables: Precio, Cantidad, Descuento y
/// Total calculado. Cada campo es un mini-TextField. Total se actualiza al
/// salir del foco de cualquiera de los inputs.
class _CartLineTile extends ConsumerStatefulWidget {
  const _CartLineTile({
    super.key,
    required this.item,
    required this.onRemove,
    required this.onPriceChanged,
    required this.onQuantityChanged,
    required this.onDiscountChanged,
  });

  final SaleCartItem item;
  final VoidCallback onRemove;
  final ValueChanged<double> onPriceChanged;
  final ValueChanged<double> onQuantityChanged;
  final ValueChanged<double> onDiscountChanged;

  @override
  ConsumerState<_CartLineTile> createState() => _CartLineTileState();
}

class _CartLineTileState extends ConsumerState<_CartLineTile> {
  late final TextEditingController _priceCtrl;
  late final TextEditingController _qtyCtrl;
  late final TextEditingController _discountCtrl;

  @override
  void initState() {
    super.initState();
    _priceCtrl = TextEditingController(text: _fmtNum(widget.item.unitPrice));
    _qtyCtrl = TextEditingController(text: _fmtNum(widget.item.quantity));
    _discountCtrl = TextEditingController(
      text: _fmtNum(widget.item.discountPct),
    );
  }

  @override
  void didUpdateWidget(covariant _CartLineTile oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Sincronizamos los controllers cuando el padre cambia el item desde
    // afuera (ej. tier-change re-pricia, suma de cantidad por re-add, etc.).
    if (oldWidget.item.unitPrice != widget.item.unitPrice) {
      _priceCtrl.text = _fmtNum(widget.item.unitPrice);
    }
    if (oldWidget.item.quantity != widget.item.quantity) {
      _qtyCtrl.text = _fmtNum(widget.item.quantity);
    }
    if (oldWidget.item.discountPct != widget.item.discountPct) {
      _discountCtrl.text = _fmtNum(widget.item.discountPct);
    }
  }

  @override
  void dispose() {
    _priceCtrl.dispose();
    _qtyCtrl.dispose();
    _discountCtrl.dispose();
    super.dispose();
  }

  static String _fmtNum(double v) {
    if (v == v.roundToDouble()) return v.toInt().toString();
    return v.toStringAsFixed(2);
  }

  @override
  Widget build(BuildContext context) {
    final item = widget.item;
    final isReturn = ref.watch(posModeProvider) == PosMode.returnMode;
    final bgColor = isReturn
        ? const Color(0xFFFEF2F2)
        : const Color(0xFFF8FAFC);

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Fila superior: nombre + botón quitar ──
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      item.product.name,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontWeight: FontWeight.w600,
                        fontSize: 13,
                        color: Color(0xFF1E293B),
                      ),
                    ),
                    Text(
                      'Inventario: ${_fmtNum(item.product.stock)}'
                      '${item.product.sku != null ? '  ·  SKU: ${item.product.sku}' : ''}',
                      style: const TextStyle(
                        fontSize: 10,
                        color: Color(0xFF94A3B8),
                      ),
                    ),
                    if (item.imeis.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(top: 4),
                        child: Wrap(
                          spacing: 4,
                          runSpacing: 4,
                          children: [
                            for (final imei in item.imeis)
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 6,
                                  vertical: 2,
                                ),
                                decoration: BoxDecoration(
                                  color: const Color(0xFFEFF6FF),
                                  borderRadius: BorderRadius.circular(4),
                                ),
                                child: Text(
                                  'IMEI $imei',
                                  style: const TextStyle(
                                    fontFamily: 'monospace',
                                    fontSize: 10,
                                    color: Color(0xFF2563EB),
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ),
                  ],
                ),
              ),
              IconButton(
                onPressed: widget.onRemove,
                icon: const Icon(
                  Icons.close_rounded,
                  size: 18,
                  color: Color(0xFFF87171),
                ),
                visualDensity: VisualDensity.compact,
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(),
              ),
            ],
          ),
          const SizedBox(height: 8),
          // ── Fila inferior: 4 campos (Precio, Cant, Desc, Total) ──
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Expanded(
                child: _CartField(
                  label: 'Precio',
                  controller: _priceCtrl,
                  suffix: r'$',
                  onSubmit: (raw) {
                    final v = double.tryParse(raw) ?? item.unitPrice;
                    widget.onPriceChanged(v);
                  },
                ),
              ),
              const SizedBox(width: 6),
              Expanded(
                child: _CartField(
                  label: 'Cantidad',
                  controller: _qtyCtrl,
                  onSubmit: (raw) {
                    final v = double.tryParse(raw) ?? item.quantity;
                    widget.onQuantityChanged(v);
                  },
                ),
              ),
              const SizedBox(width: 6),
              Expanded(
                child: _CartField(
                  label: 'Descuento',
                  controller: _discountCtrl,
                  suffix: '%',
                  onSubmit: (raw) {
                    final v = double.tryParse(raw) ?? item.discountPct;
                    widget.onDiscountChanged(v);
                  },
                ),
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Total',
                      style: TextStyle(
                        fontSize: 10,
                        color: Color(0xFF64748B),
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 6),
                      child: Text(
                        money(item.lineTotal),
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w800,
                          color: isReturn
                              ? const Color(0xFFEF4444)
                              : const Color(0xFF2563EB),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Mini-input usado dentro de la línea del carrito (Precio / Cant / Desc).
/// Tiene label arriba y commitea el valor al perder el foco o al presionar
/// enter para que setState del padre se dispare una sola vez por edición.
class _CartField extends StatefulWidget {
  const _CartField({
    required this.label,
    required this.controller,
    required this.onSubmit,
    this.suffix,
  });

  final String label;
  final TextEditingController controller;
  final ValueChanged<String> onSubmit;
  final String? suffix;

  @override
  State<_CartField> createState() => _CartFieldState();
}

class _CartFieldState extends State<_CartField> {
  late final FocusNode _focus;

  @override
  void initState() {
    super.initState();
    _focus = FocusNode();
    _focus.addListener(_onFocus);
  }

  void _onFocus() {
    if (!_focus.hasFocus) widget.onSubmit(widget.controller.text);
  }

  @override
  void dispose() {
    _focus.removeListener(_onFocus);
    _focus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          widget.label,
          style: const TextStyle(
            fontSize: 10,
            color: Color(0xFF64748B),
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 2),
        TextField(
          controller: widget.controller,
          focusNode: _focus,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          textAlignVertical: TextAlignVertical.center,
          style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
          onSubmitted: widget.onSubmit,
          decoration: InputDecoration(
            isDense: true,
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 6,
              vertical: 8,
            ),
            suffixText: widget.suffix,
            suffixStyle: const TextStyle(
              fontSize: 11,
              color: Color(0xFF94A3B8),
            ),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(6),
              borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(6),
              borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
            ),
            filled: true,
            fillColor: Colors.white,
          ),
        ),
      ],
    );
  }
}

/// Chip mostrando la caja sobre la que el cajero está vendiendo y un botón
/// para cerrarla. Se oculta si todavía no hay sesión / caja resueltas
/// (provider en loading o sin caja asociada — p.ej. sesiones legacy).
class _ActiveCashRegisterChip extends ConsumerWidget {
  const _ActiveCashRegisterChip();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final nameAsync = ref.watch(currentOpenCashRegisterNameProvider);
    final name = nameAsync.valueOrNull;
    if (name == null || name.isEmpty) return const SizedBox.shrink();

    return Container(
      margin: const EdgeInsets.only(left: 12),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: const Color(0xFFEFF6FF),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: const Color(0xFFBFDBFE)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.point_of_sale, size: 16, color: Color(0xFF1D4ED8)),
          const SizedBox(width: 6),
          Text(
            'Caja: $name',
            style: const TextStyle(
              fontWeight: FontWeight.w700,
              fontSize: 13,
              color: Color(0xFF1D4ED8),
            ),
          ),
          const SizedBox(width: 10),
          // Cambiar de caja (volver al picker sin cerrar).
          InkWell(
            onTap: () {
              ref.read(activeCashSessionIdProvider.notifier).state = null;
              ref.invalidate(myOpenCashSessionsProvider);
            },
            borderRadius: BorderRadius.circular(999),
            child: const Padding(
              padding: EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.arrow_back_rounded,
                    size: 16,
                    color: Color(0xFF1D4ED8),
                  ),
                  SizedBox(width: 4),
                  Text(
                    'Cambiar',
                    style: TextStyle(
                      fontWeight: FontWeight.w700,
                      fontSize: 12,
                      color: Color(0xFF1D4ED8),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Buscador de cliente que combina input por nombre + dropdown completo.
/// Cuando el campo está vacío o muestra el cliente actual, al hacer focus
/// se abre la lista completa (incluyendo "Cliente General"). Al escribir,
/// filtra in-memory por subcadena en el nombre.
class _ClientSearchField extends StatefulWidget {
  const _ClientSearchField({
    required this.currentId,
    required this.clients,
    required this.onChanged,
  });

  final String? currentId;
  final List<SalesClient> clients;
  final ValueChanged<String?> onChanged;

  @override
  State<_ClientSearchField> createState() => _ClientSearchFieldState();
}

class _ClientSearchFieldState extends State<_ClientSearchField> {
  static const _generalLabel = 'Cliente General (Contado)';

  final _textController = TextEditingController();
  final _focusNode = FocusNode();

  @override
  void initState() {
    super.initState();
    _textController.text = _labelForId(widget.currentId);
  }

  @override
  void didUpdateWidget(_ClientSearchField old) {
    super.didUpdateWidget(old);
    // Si el clientId cambió por código externo (ej. limpiar carrito,
    // cargar venta para devolución), sincronizar el texto — pero solo
    // si el campo no está enfocado para no pisar lo que el usuario
    // está escribiendo.
    if (old.currentId != widget.currentId && !_focusNode.hasFocus) {
      _textController.text = _labelForId(widget.currentId);
    }
  }

  @override
  void dispose() {
    _textController.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  String _labelForId(String? id) {
    if (id == null) return _generalLabel;
    for (final c in widget.clients) {
      if (c.id == id) return c.fullName;
    }
    return _generalLabel;
  }

  @override
  Widget build(BuildContext context) {
    return RawAutocomplete<_ClientOption>(
      textEditingController: _textController,
      focusNode: _focusNode,
      displayStringForOption: (o) => o.label,
      optionsBuilder: (textValue) {
        final all = <_ClientOption>[
          const _ClientOption(id: null, label: _generalLabel),
          for (final c in widget.clients)
            _ClientOption(id: c.id, label: c.fullName),
        ];
        final q = textValue.text.trim().toLowerCase();
        // Si el campo está vacío o todavía muestra el label actual,
        // mostramos todos los clientes (modo "dropdown").
        if (q.isEmpty || q == _labelForId(widget.currentId).toLowerCase()) {
          return all;
        }
        return all
            .where((o) => o.label.toLowerCase().contains(q))
            .toList(growable: false);
      },
      onSelected: (option) {
        widget.onChanged(option.id);
        _textController.text = option.label;
        _focusNode.unfocus();
      },
      fieldViewBuilder: (context, controller, focusNode, onSubmitted) {
        return Container(
          decoration: BoxDecoration(
            color: const Color(0xFFF8FAFC),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: const Color(0xFFE2E8F0)),
          ),
          child: TextField(
            controller: controller,
            focusNode: focusNode,
            style: const TextStyle(fontSize: 13),
            onTap: () => controller.selection = TextSelection(
              baseOffset: 0,
              extentOffset: controller.text.length,
            ),
            decoration: InputDecoration(
              isDense: true,
              hintText: 'Buscar cliente por nombre',
              hintStyle: const TextStyle(
                fontSize: 13,
                color: Color(0xFF94A3B8),
              ),
              prefixIcon: const Icon(
                Icons.person_search_rounded,
                size: 18,
                color: Color(0xFF64748B),
              ),
              suffixIcon: widget.currentId != null
                  ? IconButton(
                      icon: const Icon(Icons.close, size: 16),
                      tooltip: 'Volver a Cliente General',
                      splashRadius: 14,
                      onPressed: () {
                        widget.onChanged(null);
                        _textController.text = _generalLabel;
                        _focusNode.unfocus();
                      },
                    )
                  : const Icon(Icons.arrow_drop_down, color: Color(0xFF64748B)),
              border: InputBorder.none,
              contentPadding: const EdgeInsets.symmetric(vertical: 12),
            ),
          ),
        );
      },
      optionsViewBuilder: (context, onSelected, options) {
        return Align(
          alignment: Alignment.topLeft,
          child: Material(
            elevation: 4,
            borderRadius: BorderRadius.circular(8),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 280, maxWidth: 420),
              child: ListView.builder(
                shrinkWrap: true,
                padding: EdgeInsets.zero,
                itemCount: options.length,
                itemBuilder: (ctx, i) {
                  final o = options.elementAt(i);
                  final selected = o.id == widget.currentId;
                  return ListTile(
                    dense: true,
                    visualDensity: VisualDensity.compact,
                    selected: selected,
                    selectedTileColor: const Color(0xFFEFF6FF),
                    leading: Icon(
                      o.id == null
                          ? Icons.person_outline
                          : Icons.person_rounded,
                      size: 18,
                      color: selected
                          ? const Color(0xFF1D4ED8)
                          : const Color(0xFF64748B),
                    ),
                    title: Text(
                      o.label,
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: selected
                            ? FontWeight.w700
                            : FontWeight.w500,
                      ),
                    ),
                    trailing: selected
                        ? const Icon(
                            Icons.check_rounded,
                            size: 16,
                            color: Color(0xFF1D4ED8),
                          )
                        : null,
                    onTap: () => onSelected(o),
                  );
                },
              ),
            ),
          ),
        );
      },
    );
  }
}

class _ClientOption {
  const _ClientOption({required this.id, required this.label});
  final String? id;
  final String label;
}
