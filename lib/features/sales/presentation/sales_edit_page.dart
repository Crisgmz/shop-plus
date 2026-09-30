import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/tokens.dart';
import '../../../shared/errors/friendly_error.dart';
import '../../../shared/formatters/formatters.dart';
import '../../../shared/packaging/product_packaging.dart';
import '../../../shared/widgets/empty_state.dart';
import '../../../shared/widgets/module_page.dart';
import '../../settings/presentation/app_settings_providers.dart';
import '../data/sales_history_repository.dart';
import '../data/sales_repository.dart';
import 'cart_line_tile.dart';
import 'imei_picker_dialog.dart';
import 'sales_history_providers.dart';
import 'sales_providers.dart';

/// Una línea de la venta mientras se edita. Usa el mismo modelo que el
/// carrito del POS ([SaleCartItem]): presentación, tipo de precio, precio de
/// caja y descuento se calculan igual en las dos pantallas.
///
/// [id] no cambia mientras la pantalla está abierta: es la llave del widget
/// aunque la línea cambie de presentación o se borre otra antes que ella.
class _EditLine {
  _EditLine(this.id, this.item);

  final int id;
  SaleCartItem item;
}

/// Lo que viaja a `edit_sale_transactional` por cada línea: los mismos campos
/// que manda el checkout del POS.
Map<String, dynamic> _toRpcItem(SaleCartItem item) => {
      'product_id': item.product.id,
      'description': item.product.name,
      // En unidades base: el RPC devuelve y descuenta inventario con esto.
      'quantity': item.baseQuantity,
      'unit_price': item.unitPrice,
      // El MONTO, igual que el checkout: así el total guardado es el de la
      // pantalla al centavo. El porcentaje queda para funciones viejas.
      'discount_amount': item.lineDiscount,
      'discount_pct': item.discountPct,
      // Sin esto el RPC devolvería los equipos al inventario y la venta
      // quedaría sin IMEIs.
      if (item.imeis.isNotEmpty) 'imeis': item.imeis,
      // Sin esto el RPC cobraría unitario × unidades base y la caja perdería
      // su precio (migración 92).
      if (item.isPresentation) ...{
        'uom': item.uom.dbValue,
        'uom_factor': item.uomFactor,
        'uom_price': item.presentationPrice,
        'unit_name': item.presentationLabel,
      },
    };

class SalesEditPage extends ConsumerStatefulWidget {
  const SalesEditPage({super.key, required this.saleId});

  final String saleId;

  @override
  ConsumerState<SalesEditPage> createState() => _SalesEditPageState();
}

class _SalesEditPageState extends ConsumerState<SalesEditPage> {
  final List<_EditLine> _lines = [];
  var _nextLineId = 0;
  final _notesCtrl = TextEditingController();
  String? _clientId;
  String _receiptType = 'consumer_final';
  String _paymentMethod = 'cash';
  String _originalPaymentMethod = 'cash';
  bool _initialized = false;
  bool _submitting = false;

  /// Unidades base de cada producto que la venta tenía al abrirla. Al
  /// guardar, el RPC las devuelve al inventario antes de descontar las nuevas,
  /// así que cuentan como disponibles.
  final Map<String, double> _originalBase = {};

  /// IMEIs que la venta tenía al abrirla, por producto. Se pueden volver a
  /// agregar si se quitaron: al guardar, el RPC los devuelve al inventario
  /// antes de sacar los elegidos.
  final Map<String, Set<String>> _originalImeis = {};

  /// Líneas de la venta que no se pudieron cargar (producto borrado). El RPC
  /// reemplaza TODAS las líneas, así que guardar las eliminaría: mientras haya
  /// alguna, no se deja guardar.
  final List<String> _unloadableLines = [];

  @override
  void dispose() {
    _notesCtrl.dispose();
    super.dispose();
  }

  /// La venta factura ITBIS: no es sin comprobante y el cliente con que queda
  /// la paga. Espeja `edit_sale_transactional` (migraciones 83 y 91), que es
  /// quien recalcula y guarda los totales.
  bool get _chargesTax => _receiptType != 'none' && !_clientSkipsTax;

  /// Consumidor Final: los precios de las líneas se ven y se escriben con el
  /// ITBIS adentro, igual que en el POS.
  bool get _pricesIncludeTax =>
      _chargesTax && _receiptType == 'consumer_final';

  /// El cliente con que queda la venta no paga ITBIS ("Cobrar ITBIS" apagado o
  /// exento en su ficha).
  bool get _clientSkipsTax {
    final id = _clientId;
    if (id == null) return false;
    return ref.read(salesClientsByIdProvider)[id]?.skipsTax ?? false;
  }

  /// Tipo de precio del cliente elegido: con él entran los productos nuevos.
  String? get _clientTier {
    final id = _clientId;
    if (id == null) return null;
    return ref.read(salesClientsByIdProvider)[id]?.priceTier;
  }

  Iterable<SaleCartItem> get _items => _lines.map((l) => l.item);

  // Mismas cuentas que el POS: sin ITBIS la base es el neto completo.
  double get _subtotal => _chargesTax
      ? _items.fold<double>(0, (s, it) => s + it.lineSubtotal)
      : _items.fold<double>(0, (s, it) => s + it.lineNet);
  double get _tax =>
      _chargesTax ? _items.fold<double>(0, (s, it) => s + it.lineTax) : 0;
  double get _total => _subtotal + _tax;

  bool get _imeiModeEnabled =>
      ref.read(appSettingsProvider).valueOrNull?.invImeiMode ?? false;

  void _addLine(SaleCartItem item) =>
      _lines.add(_EditLine(_nextLineId++, item));

  void _snack(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  /// Carga inicial de los items de la venta en el estado local.
  void _hydrate(
    SalesHistoryDetail detail,
    List<SalesProduct> products,
    List<SalesProduct> lineProducts,
  ) {
    if (_initialized) return;
    _initialized = true;

    // Los del catálogo activo, más los de la venta aunque se hayan
    // desactivado después: sin ellos su línea desaparecía y se borraba.
    final byId = {
      for (final p in lineProducts) p.id: p,
      for (final p in products) p.id: p,
    };
    _receiptType = detail.sale.receiptType;
    _clientId = detail.sale.clientId;
    for (final si in detail.items) {
      final pid = si.productId;
      final product = pid == null ? null : byId[pid];
      if (pid == null || product == null) {
        _unloadableLines.add(si.description);
        continue;
      }
      // Igual que al reabrir una cuenta guardada: "4 Cajas" al precio de la
      // caja con que se cobró, con su tipo de precio y su descuento.
      final item = cartItemFromSaleLine(
        product: product,
        baseQuantity: si.quantity,
        unitPrice: si.unitPrice,
        discountAmount: si.discountAmount,
        uom: si.uom,
        uomFactor: si.uomFactor,
        uomPrice: si.uomPrice,
        imeis: si.imeis,
      );
      if (item == null) continue;
      _addLine(item);
      _originalBase[pid] = (_originalBase[pid] ?? 0) + si.quantity;
      if (si.imeis.isNotEmpty) {
        _originalImeis.putIfAbsent(pid, () => <String>{}).addAll(si.imeis);
      }
    }
    _notesCtrl.text = detail.sale.notes ?? '';
    _paymentMethod = detail.paymentMethod ?? 'cash';
    _originalPaymentMethod = _paymentMethod;
  }

  // ── Inventario ────────────────────────────────────────────────────────────
  // El RPC de edición SIEMPRE valida el stock de los productos que lo llevan
  // (no depende del ajuste "No permitir venta sin stock"), así que aquí se
  // valida igual para avisar antes de guardar.

  /// Unidades base disponibles de [product] para esta venta: el inventario
  /// actual más lo que la venta ya tenía.
  double _available(SalesProduct product) =>
      product.stock + (_originalBase[product.id] ?? 0);

  /// Unidades base de [productId] en las líneas, sumando presentaciones.
  double _baseInLines(String productId, {int? exceptIndex}) {
    var total = 0.0;
    for (var i = 0; i < _lines.length; i++) {
      if (i == exceptIndex) continue;
      final it = _lines[i].item;
      if (it.product.id == productId) total += it.baseQuantity;
    }
    return total;
  }

  /// Si [candidate] (la línea [index], o una nueva) cabe en el inventario.
  bool _fitsStock(SaleCartItem candidate, {int? index}) {
    final product = candidate.product;
    if (!product.tracksStock) return true;
    final total =
        _baseInLines(product.id, exceptIndex: index) + candidate.baseQuantity;
    if (total <= _available(product) + 0.0005) return true;
    _snack('Sin stock suficiente');
    return false;
  }

  /// Aviso (no bloquea), igual que el POS, si se vende bajo el costo.
  void _warnBelowCost(SalesProduct product, double unitPrice) {
    final enforced =
        ref.read(appSettingsProvider).valueOrNull?.invDisallowBelowCost ??
            false;
    if (enforced && unitPrice < product.cost) {
      _snack('Precio por debajo del costo (${money(product.cost)}).');
    }
  }

  // ── Cambios a una línea: mismas reglas que el carrito del POS ─────────────

  void _setQty(int index, double value) {
    if (value <= 0) {
      setState(() => _lines.removeAt(index));
      return;
    }
    final item = _lines[index].item;
    final next = item.copyWith(quantity: value);
    if (!_fitsStock(next, index: index)) return;
    if (!next.respectsMinimum) {
      _snack(item.product.packaging.minimumMessage());
      return;
    }
    setState(() => _lines[index].item = next);
  }

  /// En una línea por caja el campo ES el precio de la caja.
  void _setPrice(int index, double value) {
    if (value < 0) return;
    final item = _lines[index].item;
    _warnBelowCost(
      item.product,
      item.isPresentation
          ? ProductPackaging.unitPriceFromPresentation(value, item.uomFactor)
          : value,
    );
    setState(
      () => _lines[index].item = item.isPresentation
          ? item.copyWith(presentationPriceOverride: value)
          : item.copyWith(unitPrice: value),
    );
  }

  void _setDiscount(int index, double value) {
    final item = _lines[index].item;
    setState(
      () => _lines[index].item =
          item.copyWith(discountPct: value.clamp(0, 100).toDouble()),
    );
  }

  /// Detalle / Por Mayor / …: fija el precio al del producto para ese tipo.
  void _setPriceTier(int index, String tierKey) {
    final item = _lines[index].item;
    final newPrice = item.product.priceFor(tierKey);
    _warnBelowCost(item.product, newPrice);
    setState(
      () => _lines[index].item = item.copyWith(
        unitPrice: newPrice,
        priceTier: tierKey,
        clearPresentationPrice: true,
      ),
    );
  }

  /// Caja ↔ Paquete ↔ Suelto. Reinicia la cantidad (1, o la venta mínima si
  /// pasa a suelto) y, si ya hay una línea del producto en esa presentación,
  /// se suma a ella.
  void _setUom(int index, PackagingUom next) {
    final item = _lines[index].item;
    if (item.uom == next) return;
    final minUnits = item.product.packaging.minUnitQty ?? 0;
    final startQty =
        next == PackagingUom.unit && minUnits > 1 ? minUnits : 1.0;
    final candidate = item.copyWith(
      uom: next,
      quantity: startQty,
      clearPresentationPrice: true,
    );
    if (!_fitsStock(candidate, index: index)) return;
    final target = _lines.indexWhere(
      (l) =>
          l.item.product.id == item.product.id &&
          l.item.uom == next &&
          l.item.imeis.isEmpty,
    );
    setState(() {
      if (target == -1) {
        _lines[index].item = candidate;
      } else {
        final merged = _lines[target].item;
        _lines[target].item =
            merged.copyWith(quantity: merged.quantity + startQty);
        _lines.removeAt(index);
      }
    });
  }

  /// Quita un equipo de la línea: vuelve al inventario al guardar.
  void _removeImei(int index, String imei) {
    final item = _lines[index].item;
    if (item.imeis.length <= 1) return;
    final imeis = [...item.imeis]..remove(imei);
    setState(
      () => _lines[index].item = item.copyWith(
        imeis: imeis,
        quantity: imeis.length.toDouble(),
      ),
    );
  }

  // ── Agregar productos ─────────────────────────────────────────────────────

  /// IMEIs que se pueden agregar para [product]: los del inventario más los
  /// que ya tenía la venta, menos los que están en alguna línea.
  List<String> _availableImeis(SalesProduct product) {
    final used = {
      for (final it in _items)
        if (it.product.id == product.id) ...it.imeis,
    };
    return {...product.imeis, ...?_originalImeis[product.id]}
        .where((imei) => !used.contains(imei))
        .toList(growable: false);
  }

  /// Igual que el POS: entra por la presentación MAYOR que alcance el
  /// inventario (caja, si no paquete, si no suelto), al tipo de precio del
  /// cliente. Si ya hay una línea en esa presentación, le suma una.
  Future<void> _addProduct() async {
    final productsAsync = ref.read(salesProductsProvider);
    final products = productsAsync.valueOrNull ?? const [];
    final picked = await showDialog<SalesProduct>(
      context: context,
      builder: (_) => _ProductPickerDialog(products: products),
    );
    if (picked == null || !mounted) return;

    // Con el modo IMEI activo, un producto serializado se agrega eligiendo
    // qué equipos salen.
    if (_imeiModeEnabled &&
        (picked.hasImeis || _originalImeis.containsKey(picked.id))) {
      await _pickImeisAndAdd(picked);
      return;
    }

    final packaging = picked.packaging;
    final inLines = _baseInLines(picked.id);
    var uom = packaging.sellableUoms.first;
    if (picked.tracksStock) {
      for (final option in packaging.sellableUoms) {
        uom = option;
        if (inLines + packaging.factorFor(option) <= _available(picked)) break;
      }
    }
    // Una línea con IMEIs no suma unidades sueltas: su cantidad son sus
    // equipos.
    final index = _lines.indexWhere(
      (l) =>
          l.item.product.id == picked.id &&
          l.item.uom == uom &&
          l.item.imeis.isEmpty,
    );
    if (index >= 0) {
      _setQty(index, _lines[index].item.quantity + 1);
      return;
    }
    final minUnits = packaging.minUnitQty ?? 0;
    final tier = _clientTier ?? 'retail';
    final item = SaleCartItem(
      product: picked,
      quantity: uom == PackagingUom.unit && minUnits > 1 ? minUnits : 1.0,
      unitPrice: picked.priceFor(tier),
      priceTier: tier,
      uom: uom,
    );
    if (!_fitsStock(item)) return;
    setState(() => _addLine(item));
  }

  /// Elige equipos de [product] y los suma a su línea con IMEIs, o crea una.
  Future<void> _pickImeisAndAdd(SalesProduct product) async {
    final available = _availableImeis(product);
    if (available.isEmpty) {
      _snack('Todos los IMEIs de este producto ya están en la venta.');
      return;
    }
    final selected = await showDialog<List<String>>(
      context: context,
      builder: (_) =>
          ImeiPickerDialog(productName: product.name, imeis: available),
    );
    if (selected == null || selected.isEmpty || !mounted) return;

    setState(() {
      final existing = _lines.indexWhere(
        (l) => l.item.product.id == product.id && l.item.imeis.isNotEmpty,
      );
      if (existing >= 0) {
        final item = _lines[existing].item;
        final merged = [...item.imeis, ...selected];
        _lines[existing].item = item.copyWith(
          imeis: merged,
          quantity: merged.length.toDouble(),
        );
      } else {
        final tier = _clientTier ?? 'retail';
        _addLine(SaleCartItem(
          product: product,
          quantity: selected.length.toDouble(),
          unitPrice: product.priceFor(tier),
          priceTier: tier,
          imeis: selected,
        ));
      }
    });
  }

  /// Comprobante que exige cliente con RNC/cédula (todo menos Consumidor
  /// Final y sin comprobante). Espeja `tg_sales_assert_fiscal_client`.
  bool get _needsFiscalClient =>
      _receiptType != 'consumer_final' && _receiptType != 'none';

  /// Por qué el cliente elegido no sirve para el comprobante, o null.
  String? get _fiscalClientProblem {
    if (!_needsFiscalClient) return null;
    final id = _clientId;
    if (id == null) {
      return 'Esta factura tiene comprobante fiscal: necesita un cliente con '
          'RNC o cédula.';
    }
    final client = ref.read(salesClientsByIdProvider)[id];
    // Si la lista de clientes aún no cargó, decide el servidor.
    if (client == null) return null;
    if ((client.documentNumber ?? '').trim().isEmpty) {
      return '${client.fullName} no tiene RNC o cédula registrado, y esta '
          'factura tiene comprobante fiscal.';
    }
    return null;
  }

  Future<void> _save() async {
    if (_unloadableLines.isNotEmpty) {
      _snack('Esta venta tiene productos que ya no existen; no se puede '
          'editar sin perderlos.');
      return;
    }
    if (_lines.isEmpty) {
      _snack('La venta debe tener al menos un item.');
      return;
    }
    final fiscalProblem = _fiscalClientProblem;
    if (fiscalProblem != null) {
      _snack(fiscalProblem);
      return;
    }
    // Suelto por debajo del mínimo: el POS no deja cobrarlo, aquí tampoco.
    for (final it in _items) {
      if (!it.respectsMinimum) {
        _snack('${it.product.name}: ${it.product.packaging.minimumMessage()}');
        return;
      }
    }

    setState(() => _submitting = true);
    try {
      final repo = ref.read(salesHistoryRepositoryProvider);
      final result = await repo.editSale(
        saleId: widget.saleId,
        items: _items.map(_toRpcItem).toList(),
        clientId: _clientId,
        clearClient: _clientId == null,
        notes: _notesCtrl.text,
        clearNotes: _notesCtrl.text.trim().isEmpty,
        clientSkipsTax: _clientSkipsTax,
      );

      // Si el método de pago cambió, actualizar los payments en una segunda
      // llamada (el RPC editSale no lo modifica). La venta ya quedó guardada:
      // si esto falla, se dice así y no "No se pudo guardar".
      if (_paymentMethod != _originalPaymentMethod) {
        try {
          await repo.updateSalePaymentMethod(
            saleId: widget.saleId,
            paymentMethod: _paymentMethod,
          );
        } catch (e) {
          if (!mounted) return;
          ref.invalidate(salesHistoryDetailProvider(widget.saleId));
          _snack('La venta se guardó, pero no se pudo cambiar el método de '
              'pago: ${friendlyErrorMessage(e)}');
          return;
        }
      }
      if (!mounted) return;
      ref.invalidate(salesHistoryPageProvider);
      ref.invalidate(salesHistoryDetailProvider(widget.saleId));
      ref.invalidate(salesProductsProvider);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: AppTokens.success,
          content: Text(
            'Venta actualizada · Total ${money(result.totalAmount)}',
            style: const TextStyle(color: AppTokens.successForeground),
          ),
        ),
      );
      context.go('/ventas/historial');
    } catch (e) {
      if (!mounted) return;
      _snack('No se pudo guardar: ${friendlyErrorMessage(e)}');
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final detailAsync = ref.watch(salesHistoryDetailProvider(widget.saleId));
    final productsAsync = ref.watch(salesProductsProvider);
    final lineProductsAsync =
        ref.watch(saleLineProductsProvider(widget.saleId));
    final clientsAsync = ref.watch(salesClientsProvider);

    return ModulePage(
      title: 'Editar venta',
      description: 'Modifica productos, presentación, tipo de precio, '
          'descuentos, cliente y notas.',
      actions: [
        OutlinedButton.icon(
          onPressed: _submitting ? null : () => context.pop(),
          icon: const Icon(Icons.arrow_back, size: 18),
          label: const Text('Cancelar'),
        ),
        FilledButton.icon(
          onPressed: _submitting ? null : _save,
          icon: _submitting
              ? const SizedBox(
                  width: 14,
                  height: 14,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.check, size: 18),
          label: Text(_submitting ? 'Guardando…' : 'Guardar cambios'),
        ),
      ],
      child: detailAsync.when(
        loading: () => const Center(
          child: Padding(
            padding: EdgeInsets.all(48),
            child: CircularProgressIndicator(),
          ),
        ),
        error: (e, _) => ErrorCard(
          message: 'No se pudo cargar la venta: ${friendlyErrorMessage(e)}',
          onRetry: () =>
              ref.invalidate(salesHistoryDetailProvider(widget.saleId)),
        ),
        data: (detail) {
          if (detail == null) {
            return const _SaleNotFound();
          }
          // Solo ventas cobradas o a crédito. Una anulada ya devolvió todo y
          // una cuenta guardada se edita reabriéndola en el POS.
          final status = detail.sale.status;
          if (status != 'completed' && status != 'credit') {
            return _NotEditable(
              message: status == 'voided'
                  ? 'Esta venta está anulada: no se puede editar.'
                  : 'Esta venta no está cobrada. Una cuenta guardada se '
                      'edita reabriéndola en Ventas.',
            );
          }
          if (lineProductsAsync.isLoading && !lineProductsAsync.hasValue) {
            return const Center(
              child: Padding(
                padding: EdgeInsets.all(48),
                child: CircularProgressIndicator(),
              ),
            );
          }
          return productsAsync.when(
            loading: () => const Center(
              child: Padding(
                padding: EdgeInsets.all(48),
                child: CircularProgressIndicator(),
              ),
            ),
            error: (e, _) => ErrorCard(
              message: 'No se pudieron cargar productos: '
                  '${friendlyErrorMessage(e)}',
              onRetry: () => ref.invalidate(salesProductsProvider),
            ),
            data: (products) {
              _hydrate(
                detail,
                products,
                lineProductsAsync.valueOrNull ?? const [],
              );
              final shades = shadesByProduct([
                for (final line in _lines) line.item.product.id,
              ]);
              return _EditForm(
                detail: detail,
                lines: [
                  for (var i = 0; i < _lines.length; i++)
                    CartLineTile(
                      key: ValueKey(_lines[i].id),
                      shaded: shades[i],
                      item: _lines[i].item,
                      chargesTax: _chargesTax,
                      pricesIncludeTax: _pricesIncludeTax,
                      // Con IMEIs la cantidad son los equipos.
                      quantityReadOnly: _lines[i].item.imeis.isNotEmpty,
                      onRemove: () => setState(() => _lines.removeAt(i)),
                      onPriceChanged: (v) => _setPrice(i, v),
                      onQuantityChanged: (v) => _setQty(i, v),
                      onDiscountChanged: (v) => _setDiscount(i, v),
                      onPriceTierChanged: (tier) => _setPriceTier(i, tier),
                      onUomChanged: (uom) => _setUom(i, uom),
                      onRemoveImei: (imei) => _removeImei(i, imei),
                    ),
                ],
                warnings: [
                  if (_unloadableLines.isNotEmpty)
                    'No se puede guardar: ${_unloadableLines.join(', ')} ya '
                        'no existe en el inventario y se perdería.',
                  if (detail.sale.ncf != null)
                    'Factura con NCF ${detail.sale.ncf}: los cambios de '
                        'montos quedan en el 607 del mes de la venta. Para '
                        'devolver mercancía usa una devolución (nota de '
                        'crédito).',
                  ?_fiscalClientProblem,
                ],
                clientId: _clientId,
                notesCtrl: _notesCtrl,
                paymentMethod: _paymentMethod,
                clientsAsync: clientsAsync,
                subtotal: _subtotal,
                tax: _tax,
                total: _total,
                hideTaxBreakdown: _pricesIncludeTax,
                onClientChanged: (v) => setState(() => _clientId = v),
                onPaymentMethodChanged: (v) =>
                    setState(() => _paymentMethod = v),
                onAddProduct: _addProduct,
              );
            },
          );
        },
      ),
    );
  }
}

class _SaleNotFound extends StatelessWidget {
  const _SaleNotFound();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(48),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.search_off,
              size: 48,
              color: AppTokens.mutedForeground,
            ),
            const SizedBox(height: 12),
            const Text('Venta no encontrada.'),
            const SizedBox(height: 12),
            FilledButton(
              onPressed: () => context.go('/ventas/historial'),
              child: const Text('Volver al historial'),
            ),
          ],
        ),
      ),
    );
  }
}

class _EditForm extends StatelessWidget {
  const _EditForm({
    required this.detail,
    required this.lines,
    this.warnings = const [],
    required this.clientId,
    required this.notesCtrl,
    required this.paymentMethod,
    required this.clientsAsync,
    required this.subtotal,
    required this.tax,
    required this.total,
    this.hideTaxBreakdown = false,
    required this.onClientChanged,
    required this.onPaymentMethodChanged,
    required this.onAddProduct,
  });

  final SalesHistoryDetail detail;

  /// Una [CartLineTile] por línea de la venta.
  final List<Widget> lines;

  /// Avisos arriba del formulario (NCF, cliente sin RNC…).
  final List<String> warnings;
  final String? clientId;
  final TextEditingController notesCtrl;
  final String paymentMethod;
  final AsyncValue<List<SalesClient>> clientsAsync;
  final double subtotal;
  final double tax;
  final double total;

  /// Consumidor Final (B02): el ITBIS se cobra pero no se desglosa, igual que
  /// en el POS y en la factura.
  final bool hideTaxBreakdown;
  final ValueChanged<String?> onClientChanged;
  final ValueChanged<String> onPaymentMethodChanged;
  final VoidCallback onAddProduct;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _Header(detail: detail),
        for (final warning in warnings) ...[
          const SizedBox(height: AppTokens.s8),
          _Warning(warning),
        ],
        const SizedBox(height: AppTokens.s16),
        _ClientSelector(
          clientId: clientId,
          clientsAsync: clientsAsync,
          onChanged: onClientChanged,
        ),
        const SizedBox(height: AppTokens.s16),
        _PaymentMethodField(
          detail: detail,
          value: paymentMethod,
          onChanged: onPaymentMethodChanged,
        ),
        const SizedBox(height: AppTokens.s16),
        Row(
          children: [
            const Text(
              'Items',
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w700,
              ),
            ),
            const Spacer(),
            OutlinedButton.icon(
              onPressed: onAddProduct,
              icon: const Icon(Icons.add, size: 16),
              label: const Text('Agregar producto'),
            ),
          ],
        ),
        const SizedBox(height: AppTokens.s8),
        if (lines.isEmpty)
          Container(
            padding: const EdgeInsets.all(AppTokens.s20),
            decoration: BoxDecoration(
              border: Border.all(color: AppTokens.border),
              borderRadius: BorderRadius.circular(8),
            ),
            child: const Text(
              'La venta no tiene items. Agrega al menos uno antes de guardar.',
              style: TextStyle(color: AppTokens.mutedForeground),
            ),
          )
        else
          Column(children: lines),
        const SizedBox(height: AppTokens.s16),
        TextField(
          controller: notesCtrl,
          maxLines: 2,
          decoration: const InputDecoration(
            labelText: 'Notas',
            isDense: true,
            border: OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: AppTokens.s16),
        _Totals(
          subtotal: subtotal,
          tax: tax,
          total: total,
          hideTaxBreakdown: hideTaxBreakdown,
          // En ventas PAGADAS el pago sigue al total (queda saldada), igual
          // que hace el RPC al guardar. En crédito se conserva lo pagado y el
          // pendiente se recalcula contra el nuevo total.
          paid: detail.sale.status == 'completed'
              ? total
              : detail.sale.paidAmount,
        ),
      ],
    );
  }
}

/// Método de pago de la venta. Solo se puede cambiar cuando todos sus pagos
/// son de un mismo método: el RPC re-etiqueta TODOS los pagos, así que en un
/// pago dividido (efectivo + tarjeta) movía dinero de un método a otro. Y no
/// ofrece "Crédito" ni "Mixto": cambiar la etiqueta no convierte una venta
/// cobrada en una cuenta por cobrar, solo sacaba el dinero del cuadre.
class _PaymentMethodField extends StatelessWidget {
  const _PaymentMethodField({
    required this.detail,
    required this.value,
    required this.onChanged,
  });

  final SalesHistoryDetail detail;
  final String value;
  final ValueChanged<String> onChanged;

  static const _labels = {
    'cash': 'Efectivo',
    'transfer': 'Transferencia',
    'card': 'Tarjeta',
    'mobile': 'Pago móvil',
    'mixed': 'Mixto',
    'credit': 'Crédito',
    'credit_note': 'Nota de crédito',
  };
  static const _editable = ['cash', 'transfer', 'card', 'mobile'];

  String _label(String method) => _labels[method] ?? method;

  @override
  Widget build(BuildContext context) {
    final methods = detail.paymentMethods;
    String? readOnly;
    if (detail.paymentCount == 0) {
      readOnly = 'Sin pagos registrados. Los abonos se registran en Cobros.';
    } else if (methods.length > 1) {
      readOnly = 'Pago dividido (${methods.map(_label).join(' + ')}): no se '
          'cambia desde aquí.';
    } else if (!_editable.contains(value)) {
      readOnly = _label(value);
    }
    if (readOnly != null) {
      return InputDecorator(
        decoration: const InputDecoration(
          labelText: 'Método de pago',
          isDense: true,
          border: OutlineInputBorder(),
        ),
        child: Text(
          readOnly,
          style: const TextStyle(color: AppTokens.mutedForeground),
        ),
      );
    }
    return DropdownButtonFormField<String>(
      initialValue: value,
      decoration: const InputDecoration(
        labelText: 'Método de pago',
        isDense: true,
        border: OutlineInputBorder(),
      ),
      items: [
        for (final method in _editable)
          DropdownMenuItem(value: method, child: Text(_label(method))),
      ],
      onChanged: (v) {
        if (v != null) onChanged(v);
      },
    );
  }
}

/// Aviso en ámbar arriba del formulario.
class _Warning extends StatelessWidget {
  const _Warning(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(AppTokens.s12),
      decoration: BoxDecoration(
        color: AppTokens.warning.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppTokens.warning.withValues(alpha: 0.5)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(
            Icons.info_outline_rounded,
            size: 18,
            color: AppTokens.warning,
          ),
          const SizedBox(width: AppTokens.s8),
          Expanded(child: Text(text, style: const TextStyle(fontSize: 13))),
        ],
      ),
    );
  }
}

/// La venta existe pero no se puede editar (anulada, cuenta guardada…).
class _NotEditable extends StatelessWidget {
  const _NotEditable({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(48),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.block,
              size: 48,
              color: AppTokens.mutedForeground,
            ),
            const SizedBox(height: 12),
            Text(message, textAlign: TextAlign.center),
            const SizedBox(height: 12),
            FilledButton(
              onPressed: () => context.go('/ventas/historial'),
              child: const Text('Volver al historial'),
            ),
          ],
        ),
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.detail});

  final SalesHistoryDetail detail;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(AppTokens.s12),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppTokens.border),
      ),
      child: Wrap(
        spacing: 24,
        runSpacing: 6,
        children: [
          _KV('Número', detail.sale.saleNumber),
          _KV('Fecha', formatDateTime(detail.sale.saleDate)),
          if (detail.sale.ncf != null) _KV('NCF', detail.sale.ncf!),
          _KV('Estado', _statusLabel(detail.sale.status)),
          _KV('Pagado', money(detail.sale.paidAmount)),
        ],
      ),
    );
  }

  static String _statusLabel(String s) {
    switch (s) {
      case 'completed':
        return 'Pagada';
      case 'credit':
        return 'Crédito';
      case 'pending':
        return 'Pendiente';
      default:
        return s;
    }
  }
}

class _KV extends StatelessWidget {
  const _KV(this.k, this.v);
  final String k;
  final String v;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          '$k: ',
          style: const TextStyle(
            fontSize: 12,
            color: AppTokens.mutedForeground,
          ),
        ),
        Text(
          v,
          style: const TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w700,
          ),
        ),
      ],
    );
  }
}

class _ClientSelector extends StatelessWidget {
  const _ClientSelector({
    required this.clientId,
    required this.clientsAsync,
    required this.onChanged,
  });

  final String? clientId;
  final AsyncValue<List<SalesClient>> clientsAsync;
  final ValueChanged<String?> onChanged;

  @override
  Widget build(BuildContext context) {
    return clientsAsync.when(
      loading: () => const LinearProgressIndicator(),
      error: (e, _) => Text('Error al cargar clientes: ${friendlyErrorMessage(e)}'),
      data: (clients) => DropdownButtonFormField<String?>(
        initialValue: clientId,
        isExpanded: true,
        decoration: const InputDecoration(
          labelText: 'Cliente',
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
        onChanged: onChanged,
      ),
    );
  }
}

class _Totals extends StatelessWidget {
  const _Totals({
    required this.subtotal,
    required this.tax,
    required this.total,
    required this.paid,
    this.hideTaxBreakdown = false,
  });

  final double subtotal;
  final double tax;
  final double total;
  final double paid;
  final bool hideTaxBreakdown;

  @override
  Widget build(BuildContext context) {
    final balance = (total - paid).clamp(0, double.infinity);
    return Align(
      alignment: Alignment.centerRight,
      child: SizedBox(
        width: 280,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (!hideTaxBreakdown) ...[
              _row('Subtotal', money(subtotal)),
              _row('ITBIS', money(tax)),
              const Divider(),
            ],
            _row('Total', money(total), bold: true),
            const SizedBox(height: 8),
            _row('Pagado', money(paid)),
            if (balance > 0)
              _row('Pendiente', money(balance.toDouble()),
                  bold: true, danger: true),
          ],
        ),
      ),
    );
  }

  Widget _row(String label, String value, {bool bold = false, bool danger = false}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: TextStyle(
              fontSize: bold ? 14 : 12,
              fontWeight: bold ? FontWeight.w700 : FontWeight.w500,
              color: AppTokens.mutedForeground,
            ),
          ),
          Text(
            value,
            style: TextStyle(
              fontSize: bold ? 15 : 13,
              fontWeight: bold ? FontWeight.w800 : FontWeight.w600,
              color: danger
                  ? AppTokens.destructive
                  : (bold
                      ? const Color(0xFF2563EB)
                      : const Color(0xFF1E293B)),
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────
// Dialogo para elegir un producto a agregar
// ─────────────────────────────────────────────────────────────────────────

class _ProductPickerDialog extends StatefulWidget {
  const _ProductPickerDialog({required this.products});

  final List<SalesProduct> products;

  @override
  State<_ProductPickerDialog> createState() => _ProductPickerDialogState();
}

class _ProductPickerDialogState extends State<_ProductPickerDialog> {
  String _query = '';

  @override
  Widget build(BuildContext context) {
    final q = _query.trim().toLowerCase();
    final filtered = widget.products.where((p) {
      if (q.isEmpty) return p.isActive;
      if (!p.isActive) return false;
      return p.name.toLowerCase().contains(q) ||
          (p.sku ?? '').toLowerCase().contains(q) ||
          (p.barcode ?? '').toLowerCase().contains(q);
    }).take(50).toList(growable: false);

    return AlertDialog(
      title: const Text('Agregar producto'),
      content: SizedBox(
        width: 480,
        height: 480,
        child: Column(
          children: [
            TextField(
              autofocus: true,
              onChanged: (v) => setState(() => _query = v),
              decoration: const InputDecoration(
                prefixIcon: Icon(Icons.search, size: 18),
                hintText: 'Buscar por nombre, SKU o código de barras',
                isDense: true,
                border: OutlineInputBorder(),
              ),
              inputFormatters: [
                LengthLimitingTextInputFormatter(60),
              ],
            ),
            const SizedBox(height: 12),
            Expanded(
              child: filtered.isEmpty
                  ? const Center(
                      child: Text(
                        'Sin coincidencias.',
                        style:
                            TextStyle(color: AppTokens.mutedForeground),
                      ),
                    )
                  : ListView.builder(
                      itemCount: filtered.length,
                      itemBuilder: (_, i) {
                        final p = filtered[i];
                        return ListTile(
                          dense: true,
                          title: Text(p.name),
                          subtitle: Text(
                            'Precio: ${money(p.price)} · Stock: ${p.stock}',
                            style: const TextStyle(fontSize: 11),
                          ),
                          trailing: const Icon(Icons.add_circle_outline,
                              size: 18),
                          onTap: () => Navigator.pop(context, p),
                        );
                      },
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
      ],
    );
  }
}
