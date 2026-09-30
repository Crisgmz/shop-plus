import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/tokens.dart';
import '../../../shared/formatters/formatters.dart';
import '../../../shared/packaging/product_packaging.dart';
import '../../settings/presentation/app_settings_providers.dart';
import '../data/sales_repository.dart';

/// Un tipo de precio disponible para una línea del carrito: su clave de tier,
/// el nombre que ve el cajero y el precio que resulta para ese producto.
class PriceTypeOption {
  const PriceTypeOption({
    required this.key,
    required this.label,
    required this.price,
  });

  /// 'retail' (Detalle) | 'tier_1'..'tier_10'.
  final String key;
  final String label;
  final double price;
}

/// Tipos de precio disponibles para [product], según los nombres configurados
/// en `app_settings.sale_price_types`. Siempre incluye "Detalle" (precio base);
/// cada tier solo aparece si tiene un nombre configurado.
List<PriceTypeOption> priceTypeOptionsFor(
  SalesProduct product,
  List<dynamic> priceTypes,
) {
  final options = <PriceTypeOption>[
    PriceTypeOption(key: 'retail', label: 'Detalle', price: product.price),
  ];
  for (var i = 0; i < priceTypes.length && i < 10; i++) {
    final name = priceTypes[i].toString().trim();
    if (name.isEmpty) continue;
    final key = 'tier_${i + 1}';
    options.add(
      PriceTypeOption(key: key, label: name, price: product.priceFor(key)),
    );
  }
  return options;
}

/// Nombre visible de un tier: 'retail' → 'Detalle', 'tier_n' → nombre
/// configurado (o 'Detalle' si el tier ya no tiene nombre).
String priceTierLabel(String tierKey, List<dynamic> priceTypes) {
  if (tierKey == 'retail') return 'Detalle';
  final match = RegExp(r'^tier_(\d+)$').firstMatch(tierKey);
  if (match != null) {
    final idx = int.parse(match.group(1)!) - 1;
    if (idx >= 0 && idx < priceTypes.length) {
      final name = priceTypes[idx].toString().trim();
      if (name.isNotEmpty) return name;
    }
  }
  return 'Detalle';
}

/// Línea del carrito con campos editables: Precio, Cantidad, Descuento y
/// Total calculado. Cada campo es un mini-TextField. Total se actualiza al
/// salir del foco de cualquiera de los inputs.
///
/// La usan el POS y la edición de ventas: las dos eligen presentación (caja,
/// paquete, suelto) y tipo de precio de la misma forma.
class CartLineTile extends ConsumerStatefulWidget {
  const CartLineTile({
    super.key,
    required this.item,
    required this.chargesTax,
    this.pricesIncludeTax = false,
    required this.onRemove,
    required this.onPriceChanged,
    required this.onQuantityChanged,
    required this.onDiscountChanged,
    required this.onPriceTierChanged,
    required this.onUomChanged,
    this.isReturn = false,
    this.quantityReadOnly = false,
    this.onRemoveImei,
  });

  final SaleCartItem item;

  /// False en ventas sin comprobante: la línea muestra el subtotal, no el
  /// total con ITBIS, para que cuadre con el total del carrito.
  final bool chargesTax;

  /// Consumidor Final: el precio de la línea se muestra y se edita con el
  /// ITBIS adentro, para no desglosar el impuesto frente al cliente. Lo que se
  /// guarda sigue siendo el precio base del producto.
  final bool pricesIncludeTax;

  final VoidCallback onRemove;
  final ValueChanged<double> onPriceChanged;
  final ValueChanged<double> onQuantityChanged;
  final ValueChanged<double> onDiscountChanged;
  final ValueChanged<String> onPriceTierChanged;
  final ValueChanged<PackagingUom> onUomChanged;

  /// Línea de una devolución en el POS: se pinta en rojo.
  final bool isReturn;

  /// La cantidad solo se muestra. La edición de ventas lo usa en líneas con
  /// IMEIs, donde la cantidad son los equipos.
  final bool quantityReadOnly;

  /// Si no es null, cada IMEI (menos el último) trae una ✕ para quitarlo.
  final ValueChanged<String>? onRemoveImei;

  @override
  ConsumerState<CartLineTile> createState() => _CartLineTileState();
}

class _CartLineTileState extends ConsumerState<CartLineTile> {
  late final TextEditingController _priceCtrl;
  late final TextEditingController _qtyCtrl;
  late final TextEditingController _discountCtrl;

  @override
  void initState() {
    super.initState();
    // Precio de la presentación de la línea (la caja completa, o la unidad).
    _priceCtrl = TextEditingController(text: _fmtNum(_displayPrice));
    _qtyCtrl = TextEditingController(text: _fmtNum(widget.item.quantity));
    _discountCtrl = TextEditingController(
      text: _fmtNum(widget.item.discountPct),
    );
  }

  @override
  void didUpdateWidget(covariant CartLineTile oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Sincronizamos los controllers cuando el padre cambia el item desde
    // afuera (ej. tier-change re-pricia, suma de cantidad por re-add, etc.).
    final uomChanged = oldWidget.item.uom != widget.item.uom;
    if (uomChanged ||
        oldWidget.pricesIncludeTax != widget.pricesIncludeTax ||
        oldWidget.item.presentationPrice != widget.item.presentationPrice) {
      _priceCtrl.text = _fmtNum(_displayPrice);
    }
    if (uomChanged || oldWidget.item.quantity != widget.item.quantity) {
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

  /// Factor para pasar del precio base al que ve el cliente. 1 si la línea no
  /// esconde el impuesto o si el precio del producto ya lo trae adentro.
  double get _taxFactor {
    final item = widget.item;
    if (!widget.pricesIncludeTax ||
        item.product.priceIncludesTax ||
        item.taxRate <= 0) {
      return 1;
    }
    return 1 + item.taxRate / 100;
  }

  static double _round2(double v) => (v * 100).roundToDouble() / 100;

  double _withTax(double base) => _round2(base * _taxFactor);

  double get _displayPrice => _withTax(widget.item.presentationPrice);

  static String _fmtNum(double v) {
    if (v == v.roundToDouble()) return v.toInt().toString();
    return v.toStringAsFixed(2);
  }

  @override
  Widget build(BuildContext context) {
    final item = widget.item;
    final isReturn = widget.isReturn;
    final bgColor = isReturn
        ? const Color(0xFFFEF2F2)
        : const Color(0xFFF8FAFC);

    // Tipos de precio del producto (Detalle + tiers nombrados). Solo se muestra
    // el selector si hay más de una opción configurada en Ajustes.
    final priceTypes =
        ref.watch(appSettingsProvider).valueOrNull?.salePriceTypes ?? const [];
    final baseOptions = priceTypeOptionsFor(item.product, priceTypes);
    // En una línea de caja, cada tipo de precio muestra lo que cobraría la
    // caja con ese tipo, no el precio del paquete.
    final priceOptions = item.isPresentation
        ? [
            for (final o in baseOptions)
              PriceTypeOption(
                key: o.key,
                label: o.label,
                price: _withTax(
                  item.product.packaging.priceFor(
                    item.uom,
                    o.price,
                    tier: o.key,
                  ),
                ),
              ),
          ]
        : [
            for (final o in baseOptions)
              PriceTypeOption(
                key: o.key,
                label: o.label,
                price: _withTax(o.price),
              ),
          ];
    final currentPriceLabel = item.isCustomPrice
        ? 'Personalizado'
        : priceTierLabel(item.priceTier, priceTypes);

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
                      'Inventario: ${item.product.packaging.hasPacks ? item.product.packaging.describeStock(item.product.stock) : _fmtNum(item.product.stock)}'
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
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Text(
                                      'IMEI $imei',
                                      style: const TextStyle(
                                        fontFamily: 'monospace',
                                        fontSize: 10,
                                        color: Color(0xFF2563EB),
                                      ),
                                    ),
                                    if (widget.onRemoveImei != null &&
                                        item.imeis.length > 1)
                                      InkWell(
                                        onTap: () => widget.onRemoveImei!(imei),
                                        borderRadius: BorderRadius.circular(8),
                                        child: const Padding(
                                          padding: EdgeInsets.only(left: 2),
                                          child: Tooltip(
                                            message: 'Quitar de la venta',
                                            child: Icon(
                                              Icons.close_rounded,
                                              size: 12,
                                              color: Color(0xFF2563EB),
                                            ),
                                          ),
                                        ),
                                      ),
                                  ],
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
          if (priceOptions.length > 1 || item.product.packaging.hasPacks) ...[
            const SizedBox(height: 8),
            // Tipo de precio y presentación en la misma fila. En pantallas
            // angostas el Wrap baja el segundo chip en vez de desbordarse.
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                if (priceOptions.length > 1)
                  _buildPriceTypeChip(priceOptions, currentPriceLabel),
                if (item.product.packaging.hasPacks)
                  _buildPresentationChip(item),
              ],
            ),
          ],
          const SizedBox(height: 8),
          // ── Fila inferior: 4 campos (Precio, Cant, Desc, Total) ──
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Expanded(
                child: _CartField(
                  label: item.isPresentation
                      ? 'Precio ${item.presentationLabel.toLowerCase()}'
                      : 'Precio',
                  controller: _priceCtrl,
                  suffix: r'$',
                  onSubmit: (raw) {
                    final v = double.tryParse(raw);
                    // El campo se "envía" en cada blur: sin cambio no se toca
                    // el precio base, que al revertir el ITBIS podría moverse
                    // un centavo.
                    if (v == null || v == _displayPrice) return;
                    widget.onPriceChanged(_round2(v / _taxFactor));
                  },
                ),
              ),
              const SizedBox(width: 6),
              Expanded(
                child: _CartField(
                  label: item.isPresentation
                      ? pluralLabel(item.presentationLabel, 2)
                      : 'Cantidad',
                  controller: _qtyCtrl,
                  readOnly: widget.quantityReadOnly,
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
                        money(
                          widget.chargesTax ? item.lineTotal : item.lineNet,
                        ),
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

  /// Chip-selector de la presentación de la línea: la del producto ("Caja ·
  /// 12 u") o suelta por unidad. Mismo patrón que el chip de tipo de precio.
  Widget _buildPresentationChip(SaleCartItem item) {
    final packaging = item.product.packaging;
    String describe(PackagingUom uom) {
      final label = packaging.labelFor(uom);
      if (uom == PackagingUom.unit) return label;
      final units = packaging.factorFor(uom);
      final n = units == units.roundToDouble()
          ? units.toInt().toString()
          : units.toString();
      return '$label · $n u';
    }

    // Debajo de cada opción: cuánto sale el paquete dentro de la caja, o el
    // mínimo al vender suelto. Así se ve que suelto es más caro.
    String? detail(PackagingUom uom) {
      final unit = packaging.effectiveUnitLabel.toLowerCase();
      if (uom != PackagingUom.unit) {
        final perUnit = packaging.pricePerBaseUnit(
          uom,
          item.unitPrice,
          tier: item.priceTier,
        );
        return '${money(_withTax(perUnit))} por $unit';
      }
      final min = packaging.minUnitQty ?? 0;
      if (min <= 1) return null;
      final n = min == min.roundToDouble() ? min.toInt() : min;
      return 'Mínimo $n ${pluralLabel(unit, n)}';
    }

    return Align(
      alignment: Alignment.centerLeft,
      widthFactor: 1,
      child: PopupMenuButton<PackagingUom>(
        tooltip: 'Presentación',
        position: PopupMenuPosition.under,
        constraints: const BoxConstraints(minWidth: 220),
        itemBuilder: (ctx) => [
          for (final uom in packaging.sellableUoms)
            PopupMenuItem<PackagingUom>(
              value: uom,
              height: 48,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        describe(uom),
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: uom == item.uom
                              ? FontWeight.w700
                              : FontWeight.w500,
                        ),
                      ),
                      if (detail(uom) case final text?)
                        Text(
                          text,
                          style: const TextStyle(
                            fontSize: 11,
                            color: AppTokens.mutedForeground,
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(width: 12),
                  Text(
                    money(
                      packaging.priceFor(
                        uom,
                        item.unitPrice,
                        tier: item.priceTier,
                      ),
                    ),
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: Color(0xFF2563EB),
                    ),
                  ),
                ],
              ),
            ),
        ],
        onSelected: widget.onUomChanged,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(6),
            border: Border.all(color: const Color(0xFFE2E8F0)),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(
                Icons.inventory_2_outlined,
                size: 14,
                color: Color(0xFF64748B),
              ),
              const SizedBox(width: 6),
              Text(
                describe(item.uom),
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: Color(0xFF334155),
                ),
              ),
              const Icon(
                Icons.keyboard_arrow_down_rounded,
                size: 16,
                color: Color(0xFF64748B),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Chip-selector del tipo de precio de la línea. Un tap abre un menú con
  /// cada precio del producto (Detalle + tiers nombrados) y su monto. Al
  /// elegir uno, la línea se re-precia. `PopupMenuButton` es confiable en web
  /// (no depende del foco como un autocompletado).
  Widget _buildPriceTypeChip(
    List<PriceTypeOption> options,
    String currentLabel,
  ) {
    return Align(
      alignment: Alignment.centerLeft,
      widthFactor: 1,
      child: PopupMenuButton<String>(
        tooltip: 'Tipo de precio',
        position: PopupMenuPosition.under,
        constraints: const BoxConstraints(minWidth: 220),
        itemBuilder: (ctx) => [
          for (final o in options)
            PopupMenuItem<String>(
              value: o.key,
              height: 40,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Flexible(
                    child: Text(
                      o.label,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: o.key == widget.item.priceTier
                            ? FontWeight.w700
                            : FontWeight.w500,
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Text(
                    money(o.price),
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: Color(0xFF2563EB),
                    ),
                  ),
                ],
              ),
            ),
        ],
        onSelected: widget.onPriceTierChanged,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(6),
            border: Border.all(color: const Color(0xFFE2E8F0)),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(
                Icons.sell_outlined,
                size: 14,
                color: Color(0xFF64748B),
              ),
              const SizedBox(width: 6),
              Text(
                currentLabel,
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: Color(0xFF334155),
                ),
              ),
              const Icon(
                Icons.keyboard_arrow_down_rounded,
                size: 16,
                color: Color(0xFF64748B),
              ),
            ],
          ),
        ),
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
    this.readOnly = false,
  });

  final String label;
  final TextEditingController controller;
  final ValueChanged<String> onSubmit;
  final String? suffix;
  final bool readOnly;

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
          readOnly: widget.readOnly,
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
            fillColor: widget.readOnly ? AppTokens.muted : Colors.white,
          ),
        ),
      ],
    );
  }
}
