import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/tokens.dart';
import '../../../shared/formatters/formatters.dart';
import '../../../shared/widgets/empty_state.dart';
import '../../../shared/widgets/module_page.dart';
import '../data/sales_history_repository.dart';
import '../data/sales_repository.dart';
import '../domain/sale_checkout_service.dart'
    show fromCents, grossCents, taxCents;
import 'sales_history_providers.dart';
import 'sales_providers.dart';

/// Línea editable del carrito (estado mutable mientras se edita la venta).
class _EditCartItem {
  _EditCartItem({
    required this.product,
    required this.quantity,
    required this.unitPrice,
    required this.discountPct,
    this.chargesTax = true,
  });

  final SalesProduct product;
  double quantity;
  double unitPrice;
  double discountPct;

  /// La venta factura ITBIS. En `false` (venta sin comprobante) la tasa va a 0,
  /// igual que en `edit_sale_transactional`.
  final bool chargesTax;

  /// Tasa efectiva: 0 si la venta no factura o el producto está exento.
  double get _rate => chargesTax ? product.effectiveTaxRate : 0;

  bool get _taxIncluded => product.priceIncludesTax && _rate > 0;

  // En centavos enteros, igual que el POS y que el `numeric` de Postgres.
  double get _grossCents => grossCents(quantity, unitPrice);
  double get _discountCents => (_grossCents * (discountPct / 100))
      .roundToDouble()
      .clamp(0, _grossCents)
      .toDouble();
  double get _netCents => _grossCents - _discountCents;
  double get _taxCents => taxCents(_netCents, _rate, inclusive: _taxIncluded);

  double get lineGross => fromCents(_grossCents);
  double get lineDiscount => fromCents(_discountCents);
  double get lineSubtotal =>
      fromCents(_taxIncluded ? _netCents - _taxCents : _netCents);
  double get lineTax => fromCents(_taxCents);
  double get lineTotal =>
      fromCents(_taxIncluded ? _netCents : _netCents + _taxCents);

  Map<String, dynamic> toRpcItem() => {
        'product_id': product.id,
        'description': product.name,
        'quantity': quantity,
        'unit_price': unitPrice,
        'discount_pct': discountPct,
      };
}

class SalesEditPage extends ConsumerStatefulWidget {
  const SalesEditPage({super.key, required this.saleId});

  final String saleId;

  @override
  ConsumerState<SalesEditPage> createState() => _SalesEditPageState();
}

class _SalesEditPageState extends ConsumerState<SalesEditPage> {
  final List<_EditCartItem> _items = [];
  final _notesCtrl = TextEditingController();
  String? _clientId;
  String _paymentMethod = 'cash';
  String _originalPaymentMethod = 'cash';
  bool _initialized = false;
  bool _submitting = false;

  @override
  void dispose() {
    _notesCtrl.dispose();
    super.dispose();
  }

  /// False en ventas sin comprobante (nota de venta no fiscal): no llevan
  /// ITBIS. Espeja la regla de `edit_sale_transactional`, que es quien
  /// recalcula y guarda los totales.
  bool _chargesTax = true;

  double get _subtotal =>
      _items.fold<double>(0, (s, it) => s + it.lineSubtotal);
  double get _tax => _chargesTax
      ? _items.fold<double>(0, (s, it) => s + it.lineTax)
      : 0;
  double get _total => _subtotal + _tax;

  /// Carga inicial de los items de la venta en el estado local.
  void _hydrate(SalesHistoryDetail detail, List<SalesProduct> products) {
    if (_initialized) return;
    _initialized = true;

    final byId = {for (final p in products) p.id: p};
    // Se resuelve ANTES del bucle: cada línea lo necesita para su tasa.
    final chargesTax = detail.sale.receiptType != 'none';
    for (final si in detail.items) {
      final pid = si.productId;
      if (pid == null) continue;
      final product = byId[pid];
      if (product == null) continue;
      // El porcentaje se reconstruye desde el MONTO guardado. Antes se
      // deducía de `lineSubtotal`, pero con precio ITBIS-incluido ese subtotal
      // ya trae el impuesto extraído y salía un descuento inventado.
      final gross = si.quantity * si.unitPrice;
      final discPct = gross > 0
          ? (si.discountAmount / gross * 100).clamp(0, 100).toDouble()
          : 0.0;
      _items.add(_EditCartItem(
        product: product,
        quantity: si.quantity,
        unitPrice: si.unitPrice,
        discountPct: discPct,
        chargesTax: chargesTax,
      ));
    }
    _chargesTax = chargesTax;
    _clientId = detail.sale.clientId;
    _notesCtrl.text = detail.sale.notes ?? '';
    _paymentMethod = detail.paymentMethod ?? 'cash';
    _originalPaymentMethod = _paymentMethod;
  }

  Future<void> _addProduct() async {
    final productsAsync = ref.read(salesProductsProvider);
    final products = productsAsync.valueOrNull ?? const [];
    final picked = await showDialog<SalesProduct>(
      context: context,
      builder: (_) => _ProductPickerDialog(products: products),
    );
    if (picked == null) return;

    final existing = _items.indexWhere((it) => it.product.id == picked.id);
    setState(() {
      if (existing >= 0) {
        _items[existing].quantity += 1;
      } else {
        _items.add(_EditCartItem(
          product: picked,
          quantity: 1,
          unitPrice: picked.price,
          discountPct: 0,
          chargesTax: _chargesTax,
        ));
      }
    });
  }

  Future<void> _save() async {
    if (_items.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('La venta debe tener al menos un item.'),
        ),
      );
      return;
    }

    setState(() => _submitting = true);
    try {
      final repo = ref.read(salesHistoryRepositoryProvider);
      final result = await repo.editSale(
        saleId: widget.saleId,
        items: _items.map((it) => it.toRpcItem()).toList(),
        clientId: _clientId,
        clearClient: _clientId == null,
        notes: _notesCtrl.text,
        clearNotes: _notesCtrl.text.trim().isEmpty,
      );

      // Si el método de pago cambió, actualizar los payments en una segunda
      // llamada (el RPC editSale no lo modifica).
      if (_paymentMethod != _originalPaymentMethod) {
        await repo.updateSalePaymentMethod(
          saleId: widget.saleId,
          paymentMethod: _paymentMethod,
        );
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
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('No se pudo guardar: $e')),
      );
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final detailAsync = ref.watch(salesHistoryDetailProvider(widget.saleId));
    final productsAsync = ref.watch(salesProductsProvider);
    final clientsAsync = ref.watch(salesClientsProvider);

    return ModulePage(
      title: 'Editar venta',
      description: 'Modifica items, precios, descuentos, cliente y notas.',
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
        loading: () =>
            const Center(child: Padding(
              padding: EdgeInsets.all(48),
              child: CircularProgressIndicator(),
            )),
        error: (e, _) => ErrorCard(
          message: 'No se pudo cargar la venta: $e',
          onRetry: () =>
              ref.invalidate(salesHistoryDetailProvider(widget.saleId)),
        ),
        data: (detail) {
          if (detail == null) {
            return const _SaleNotFound();
          }
          return productsAsync.when(
            loading: () => const Center(
              child: Padding(
                padding: EdgeInsets.all(48),
                child: CircularProgressIndicator(),
              ),
            ),
            error: (e, _) => ErrorCard(
              message: 'No se pudieron cargar productos: $e',
              onRetry: () => ref.invalidate(salesProductsProvider),
            ),
            data: (products) {
              _hydrate(detail, products);
              return _EditForm(
                detail: detail,
                items: _items,
                clientId: _clientId,
                notesCtrl: _notesCtrl,
                paymentMethod: _paymentMethod,
                clientsAsync: clientsAsync,
                subtotal: _subtotal,
                tax: _tax,
                total: _total,
                onClientChanged: (v) => setState(() => _clientId = v),
                onPaymentMethodChanged: (v) =>
                    setState(() => _paymentMethod = v),
                onAddProduct: _addProduct,
                onRemoveItem: (i) => setState(() => _items.removeAt(i)),
                onItemChanged: () => setState(() {}),
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
    required this.items,
    required this.clientId,
    required this.notesCtrl,
    required this.paymentMethod,
    required this.clientsAsync,
    required this.subtotal,
    required this.tax,
    required this.total,
    required this.onClientChanged,
    required this.onPaymentMethodChanged,
    required this.onAddProduct,
    required this.onRemoveItem,
    required this.onItemChanged,
  });

  final SalesHistoryDetail detail;
  final List<_EditCartItem> items;
  final String? clientId;
  final TextEditingController notesCtrl;
  final String paymentMethod;
  final AsyncValue<List<SalesClient>> clientsAsync;
  final double subtotal;
  final double tax;
  final double total;
  final ValueChanged<String?> onClientChanged;
  final ValueChanged<String> onPaymentMethodChanged;
  final VoidCallback onAddProduct;
  final ValueChanged<int> onRemoveItem;
  final VoidCallback onItemChanged;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _Header(detail: detail),
        const SizedBox(height: AppTokens.s16),
        _ClientSelector(
          clientId: clientId,
          clientsAsync: clientsAsync,
          onChanged: onClientChanged,
        ),
        const SizedBox(height: AppTokens.s16),
        DropdownButtonFormField<String>(
          initialValue: paymentMethod,
          decoration: const InputDecoration(
            labelText: 'Método de pago',
            isDense: true,
            border: OutlineInputBorder(),
          ),
          items: const [
            DropdownMenuItem(value: 'cash', child: Text('Efectivo')),
            DropdownMenuItem(value: 'transfer', child: Text('Transferencia')),
            DropdownMenuItem(value: 'card', child: Text('Tarjeta')),
            DropdownMenuItem(value: 'mobile', child: Text('Pago móvil')),
            DropdownMenuItem(value: 'mixed', child: Text('Mixto')),
            DropdownMenuItem(value: 'credit', child: Text('Crédito')),
          ],
          onChanged: (v) {
            if (v != null) onPaymentMethodChanged(v);
          },
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
        if (items.isEmpty)
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
          Column(
            children: [
              for (var i = 0; i < items.length; i++)
                _EditableLineTile(
                  key: ValueKey('${items[i].product.id}-$i'),
                  item: items[i],
                  chargesTax: detail.sale.receiptType != 'none',
                  onRemove: () => onRemoveItem(i),
                  onChanged: onItemChanged,
                ),
            ],
          ),
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
      error: (e, _) => Text('Error al cargar clientes: $e'),
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

class _EditableLineTile extends StatefulWidget {
  const _EditableLineTile({
    super.key,
    required this.item,
    required this.chargesTax,
    required this.onRemove,
    required this.onChanged,
  });

  final _EditCartItem item;

  /// False en ventas sin comprobante: la línea muestra el subtotal, no el
  /// total con ITBIS, para que cuadre con el total del pie.
  final bool chargesTax;

  final VoidCallback onRemove;
  final VoidCallback onChanged;

  @override
  State<_EditableLineTile> createState() => _EditableLineTileState();
}

class _EditableLineTileState extends State<_EditableLineTile> {
  late final TextEditingController _qtyCtrl;
  late final TextEditingController _priceCtrl;
  late final TextEditingController _discCtrl;

  @override
  void initState() {
    super.initState();
    _qtyCtrl = TextEditingController(text: _fmt(widget.item.quantity));
    _priceCtrl = TextEditingController(text: _fmt(widget.item.unitPrice));
    _discCtrl = TextEditingController(text: _fmt(widget.item.discountPct));
  }

  @override
  void dispose() {
    _qtyCtrl.dispose();
    _priceCtrl.dispose();
    _discCtrl.dispose();
    super.dispose();
  }

  static String _fmt(double v) =>
      v == v.roundToDouble() ? v.toInt().toString() : v.toStringAsFixed(2);

  void _commitQty(String v) {
    final n = double.tryParse(v) ?? widget.item.quantity;
    widget.item.quantity = n.clamp(0.001, 999999).toDouble();
    widget.onChanged();
  }

  void _commitPrice(String v) {
    final n = double.tryParse(v) ?? widget.item.unitPrice;
    widget.item.unitPrice = n.clamp(0, 9999999).toDouble();
    widget.onChanged();
  }

  void _commitDisc(String v) {
    final n = double.tryParse(v) ?? widget.item.discountPct;
    widget.item.discountPct = n.clamp(0, 100).toDouble();
    widget.onChanged();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppTokens.border),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Expanded(
            flex: 4,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  widget.item.product.name,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontWeight: FontWeight.w600,
                    fontSize: 13,
                  ),
                ),
                Text(
                  'Stock: ${_fmt(widget.item.product.stock)}',
                  style: const TextStyle(
                    fontSize: 10,
                    color: AppTokens.mutedForeground,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: _MiniField(
              label: 'Cant.',
              controller: _qtyCtrl,
              onSubmit: _commitQty,
            ),
          ),
          const SizedBox(width: 6),
          Expanded(
            child: _MiniField(
              label: 'Precio',
              controller: _priceCtrl,
              suffix: r'$',
              onSubmit: _commitPrice,
            ),
          ),
          const SizedBox(width: 6),
          Expanded(
            child: _MiniField(
              label: 'Desc',
              controller: _discCtrl,
              suffix: '%',
              onSubmit: _commitDisc,
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                const Text(
                  'Total',
                  style: TextStyle(
                    fontSize: 10,
                    color: AppTokens.mutedForeground,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  money(
                    widget.chargesTax
                        ? widget.item.lineTotal
                        : widget.item.lineSubtotal,
                  ),
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w800,
                    color: Color(0xFF2563EB),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 4),
          IconButton(
            onPressed: widget.onRemove,
            icon: const Icon(
              Icons.close_rounded,
              size: 18,
              color: Color(0xFFF87171),
            ),
            visualDensity: VisualDensity.compact,
          ),
        ],
      ),
    );
  }
}

class _MiniField extends StatefulWidget {
  const _MiniField({
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
  State<_MiniField> createState() => _MiniFieldState();
}

class _MiniFieldState extends State<_MiniField> {
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
            color: AppTokens.mutedForeground,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 2),
        TextField(
          controller: widget.controller,
          focusNode: _focus,
          keyboardType:
              const TextInputType.numberWithOptions(decimal: true),
          style: const TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w600,
          ),
          onSubmitted: widget.onSubmit,
          decoration: InputDecoration(
            isDense: true,
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 6, vertical: 8),
            suffixText: widget.suffix,
            suffixStyle: const TextStyle(
              fontSize: 11,
              color: AppTokens.mutedForeground,
            ),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(6),
            ),
            filled: true,
            fillColor: Colors.white,
          ),
        ),
      ],
    );
  }
}

class _Totals extends StatelessWidget {
  const _Totals({
    required this.subtotal,
    required this.tax,
    required this.total,
    required this.paid,
  });

  final double subtotal;
  final double tax;
  final double total;
  final double paid;

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
            _row('Subtotal', money(subtotal)),
            _row('ITBIS', money(tax)),
            const Divider(),
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
