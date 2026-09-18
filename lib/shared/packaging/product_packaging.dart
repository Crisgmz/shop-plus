/// Empaques de producto: caja → paquete → unidad.
///
/// El inventario guarda SIEMPRE la unidad más pequeña (`products.stock`).
/// Cajas y paquetes se derivan de ese número, nunca se guardan aparte: así es
/// imposible que las tres cifras se desincronicen.
///
///     1 caja = packsPerBox paquetes = packsPerBox × unitsPerPack unidades
///
/// Un producto sin `unitsPerPack` no tiene empaque y se comporta como siempre.
library;

/// Presentación en la que se vende o se compra una línea.
enum PackagingUom {
  unit,
  pack,
  box;

  String get dbValue => name;

  static PackagingUom fromDb(String? value) {
    switch ((value ?? '').trim().toLowerCase()) {
      case 'box':
        return PackagingUom.box;
      case 'pack':
        return PackagingUom.pack;
      default:
        return PackagingUom.unit;
    }
  }
}

/// Cuántas cajas, paquetes y unidades sueltas hay en un stock dado.
class StockBreakdown {
  const StockBreakdown({
    required this.boxes,
    required this.packs,
    required this.units,
  });

  final int boxes;
  final int packs;
  final double units;

  bool get isEmpty => boxes == 0 && packs == 0 && units == 0;
}

class ProductPackaging {
  const ProductPackaging({
    this.unitsPerPack,
    this.packsPerBox,
    this.unitLabel,
    this.packLabel,
    this.boxLabel,
    this.packPrice,
    this.boxPrice,
    this.minUnitQty,
    this.packTierPrices = const {},
  });

  /// Clave con que [packTierPrices] viaja en `products.metadata` (y en el
  /// mapa de [toMap]). No es una columna: se guarda en el jsonb para no
  /// depender de una migración.
  static const String packTierPricesKey = 'pack_tier_prices';

  /// Producto sin empaque: se vende y se cuenta por unidad, como siempre.
  static const ProductPackaging none = ProductPackaging();

  /// Presentaciones que ofrece el formulario de inventario. "Unidad" significa
  /// sin empaque; las demás se venden completas o sueltas por unidad.
  static const List<String> presentationNames = [
    'Unidad',
    'Empaque',
    'Paquete',
    'Caja',
  ];

  /// Nombre de la presentación con que se vende además de la unidad ("Caja",
  /// "Paquete"…), o `null` si el producto no tiene empaque.
  String? get presentationName => hasPacks ? effectivePackLabel : null;

  /// Precio unitario que corresponde a un precio por presentación.
  ///
  /// El precio UNITARIO manda: una presentación vale unitario × unidades, así
  /// que siempre cuadra al centavo con lo que calcula el checkout. Un precio
  /// de presentación que no se reparte exacto entre sus unidades se ajusta al
  /// centavo por unidad (una caja de 12 a 100.00 → 8.33 c/u → 99.96).
  static double unitPriceFromPresentation(
    double presentationPrice,
    double factor,
  ) =>
      factor <= 0 ? presentationPrice : _round2(presentationPrice / factor);

  /// Unidades base que trae un paquete. `null` ⇒ el producto no tiene empaque.
  final double? unitsPerPack;

  /// Paquetes que trae una caja. `null` ⇒ solo dos niveles (paquete/unidad).
  final double? packsPerBox;

  final String? unitLabel;
  final String? packLabel;
  final String? boxLabel;

  /// Precio de un paquete / una caja completos. `null` ⇒ no se vende así.
  final double? packPrice;
  final double? boxPrice;

  /// Mínimo de unidades base al vender SUELTO. Configurable por producto.
  /// No aplica a paquete ni caja completos.
  final double? minUnitQty;

  /// Precio del empaque completo (la caja, en este negocio) por tipo de
  /// precio: `{'tier_1': 2400.00}`. Un tipo sin precio propio cobra
  /// [packPrice], el del Detalle.
  final Map<String, double> packTierPrices;

  bool get hasPacks => (unitsPerPack ?? 0) > 0;
  bool get hasBoxes => hasPacks && (packsPerBox ?? 0) > 0;
  bool get isConfigured => hasPacks;

  String get effectiveUnitLabel => _clean(unitLabel) ?? 'Unidad';
  String get effectivePackLabel => _clean(packLabel) ?? 'Paquete';
  String get effectiveBoxLabel => _clean(boxLabel) ?? 'Caja';

  /// Unidades base que trae una caja completa.
  double? get unitsPerBox =>
      hasBoxes ? _round3(unitsPerPack! * packsPerBox!) : null;

  /// Presentaciones en las que este producto se puede vender, de mayor a menor.
  List<PackagingUom> get sellableUoms => [
        if (hasBoxes) PackagingUom.box,
        if (hasPacks) PackagingUom.pack,
        PackagingUom.unit,
      ];

  /// La presentación más grande en que se vende: la caja si hay tres niveles,
  /// el empaque si hay dos. Es la que se lee primero en el POS e inventario.
  PackagingUom get largestUom => sellableUoms.first;

  /// "Caja de 20 Paquetes". `null` si el producto no tiene empaque.
  String? get contentLabel {
    if (!hasPacks) return null;
    final units = factorFor(largestUom);
    return '${labelFor(largestUom)} de ${_num(units)} '
        '${_plural(effectiveUnitLabel, units)}';
  }

  /// Presentaciones grandes COMPLETAS en un stock (en unidades base): 1020
  /// paquetes con cajas de 20 → 51. Sin empaque, el stock entero.
  int wholeLargest(double stockInBaseUnits) {
    if (!hasPacks) return stockInBaseUnits.floor();
    final b = breakdown(stockInBaseUnits);
    return hasBoxes ? b.boxes : b.packs;
  }

  /// Cuántas unidades base representa UNA de esa presentación.
  double factorFor(PackagingUom uom) {
    switch (uom) {
      case PackagingUom.box:
        return unitsPerBox ?? 1;
      case PackagingUom.pack:
        return hasPacks ? unitsPerPack! : 1;
      case PackagingUom.unit:
        return 1;
    }
  }

  String labelFor(PackagingUom uom) {
    switch (uom) {
      case PackagingUom.box:
        return effectiveBoxLabel;
      case PackagingUom.pack:
        return effectivePackLabel;
      case PackagingUom.unit:
        return effectiveUnitLabel;
    }
  }

  /// Convierte una cantidad expresada en [uom] a unidades base.
  /// Es lo que viaja como `quantity` al backend, para que el trigger de stock
  /// descuente correcto sin necesidad de conocer los empaques.
  double toBaseUnits(double quantity, PackagingUom uom) =>
      _round3(quantity * factorFor(uom));

  /// Descompone un stock (en unidades base) en cajas + paquetes + unidades.
  ///
  ///     200 cajas de 40 paquetes de 25 vasos = 200_000 vasos
  ///     vender 10 paquetes (250 vasos) deja 199_750
  ///       → 199 cajas, 30 paquetes, 0 unidades
  StockBreakdown breakdown(double stockInBaseUnits) {
    if (!hasPacks) {
      return StockBreakdown(boxes: 0, packs: 0, units: _round3(stockInBaseUnits));
    }

    // En milésimas enteras: el stock es numeric(14,3) y así el floor no se va
    // por un pelo cuando el double no representa exacto el decimal.
    final totalMilli = _toMilli(stockInBaseUnits);
    if (totalMilli <= 0) {
      return const StockBreakdown(boxes: 0, packs: 0, units: 0);
    }

    var rest = totalMilli;
    var boxes = 0;

    final perBox = hasBoxes ? _toMilli(unitsPerBox!) : 0;
    if (perBox > 0) {
      boxes = rest ~/ perBox;
      rest = rest % perBox;
    }

    final perPack = _toMilli(unitsPerPack!);
    final packs = perPack > 0 ? rest ~/ perPack : 0;
    if (perPack > 0) rest = rest % perPack;

    return StockBreakdown(boxes: boxes, packs: packs, units: rest / 1000);
  }

  /// Texto corto para el POS: "199 Cajas · 30 Paquetes".
  /// Omite los niveles en cero salvo que todo sea cero.
  String describeStock(double stockInBaseUnits) {
    final b = breakdown(stockInBaseUnits);
    if (!hasPacks) return '${_num(stockInBaseUnits)} $effectiveUnitLabel';

    final parts = <String>[
      if (b.boxes > 0) '${b.boxes} ${_plural(effectiveBoxLabel, b.boxes)}',
      if (b.packs > 0) '${b.packs} ${_plural(effectivePackLabel, b.packs)}',
      if (b.units > 0) '${_num(b.units)} ${_plural(effectiveUnitLabel, b.units)}',
    ];
    if (parts.isEmpty) return '0 ${_plural(effectiveUnitLabel, 0)}';
    return parts.join(' · ');
  }

  /// Precio de una presentación. La caja y el paquete usan su precio propio si
  /// está configurado; si no, se deriva del precio unitario. Con [tier]
  /// ('tier_1'…'tier_10'), el empaque usa su precio para ese tipo si lo tiene.
  double priceFor(PackagingUom uom, double unitPrice, {String? tier}) {
    switch (uom) {
      case PackagingUom.box:
        return boxPrice ?? _round2(unitPrice * factorFor(uom));
      case PackagingUom.pack:
        return (tier == null ? null : packTierPrices[tier]) ??
            packPrice ??
            _round2(unitPrice * factorFor(uom));
      case PackagingUom.unit:
        return unitPrice;
    }
  }

  /// Cuánto sale cada unidad base comprando en [uom]: caja de 20 paquetes a
  /// RD$2,639.83 → RD$131.99 por paquete. Es lo que se compara con el precio
  /// suelto, que el negocio pone más caro. Redondeado al centavo: solo se
  /// muestra, nunca se cobra.
  double pricePerBaseUnit(
    PackagingUom uom,
    double unitPrice, {
    String? tier,
  }) {
    final factor = factorFor(uom);
    return factor <= 0
        ? unitPrice
        : _round2(priceFor(uom, unitPrice, tier: tier) / factor);
  }

  /// Si la venta suelta de [baseUnits] respeta el mínimo configurado.
  /// Paquetes y cajas completos nunca se bloquean.
  bool respectsMinimum(double baseUnits, PackagingUom uom) {
    if (uom != PackagingUom.unit) return true;
    final min = minUnitQty ?? 0;
    if (min <= 0) return true;
    return baseUnits >= min;
  }

  /// Mensaje para el cajero cuando no se respeta el mínimo.
  String minimumMessage() =>
      'La venta suelta mínima es ${_num(minUnitQty ?? 0)} '
      '${_plural(effectiveUnitLabel, minUnitQty ?? 0)}.';

  factory ProductPackaging.fromMap(Map<String, dynamic> map) {
    return ProductPackaging(
      unitsPerPack: _positive(map['units_per_pack']),
      packsPerBox: _positive(map['packs_per_box']),
      unitLabel: map['unit_label']?.toString(),
      packLabel: map['pack_label']?.toString(),
      boxLabel: map['box_label']?.toString(),
      packPrice: _positive(map['pack_price']),
      boxPrice: _positive(map['box_price']),
      minUnitQty: _positive(map['min_unit_qty']),
      // Del borrador del carrito viene suelto; de la base, dentro de metadata.
      packTierPrices: _tierPrices(
        map[packTierPricesKey] ??
            (map['metadata'] is Map
                ? (map['metadata'] as Map)[packTierPricesKey]
                : null),
      ),
    );
  }

  Map<String, dynamic> toMap() => {
        'units_per_pack': unitsPerPack,
        'packs_per_box': packsPerBox,
        'unit_label': _clean(unitLabel),
        'pack_label': _clean(packLabel),
        'box_label': _clean(boxLabel),
        'pack_price': packPrice,
        'box_price': boxPrice,
        'min_unit_qty': minUnitQty,
        // No es columna: el repositorio lo pasa a `metadata` al guardar.
        packTierPricesKey: packTierPrices,
      };

  ProductPackaging copyWith({
    double? unitsPerPack,
    double? packsPerBox,
    String? unitLabel,
    String? packLabel,
    String? boxLabel,
    double? packPrice,
    double? boxPrice,
    double? minUnitQty,
    Map<String, double>? packTierPrices,
  }) {
    return ProductPackaging(
      unitsPerPack: unitsPerPack ?? this.unitsPerPack,
      packsPerBox: packsPerBox ?? this.packsPerBox,
      unitLabel: unitLabel ?? this.unitLabel,
      packLabel: packLabel ?? this.packLabel,
      boxLabel: boxLabel ?? this.boxLabel,
      packPrice: packPrice ?? this.packPrice,
      boxPrice: boxPrice ?? this.boxPrice,
      minUnitQty: minUnitQty ?? this.minUnitQty,
      packTierPrices: packTierPrices ?? this.packTierPrices,
    );
  }
}

String? _clean(String? value) {
  final trimmed = value?.trim();
  return (trimmed == null || trimmed.isEmpty) ? null : trimmed;
}

/// `{'tier_1': 2400}` desde jsonb; descarta claves vacías y precios no
/// positivos.
Map<String, double> _tierPrices(dynamic raw) {
  if (raw is! Map) return const {};
  final out = <String, double>{};
  raw.forEach((key, value) {
    final price = _positive(value);
    final tier = key?.toString().trim() ?? '';
    if (tier.isNotEmpty && price != null) out[tier] = price;
  });
  return out;
}

double? _positive(dynamic value) {
  if (value == null) return null;
  final parsed = value is num
      ? value.toDouble()
      : double.tryParse(value.toString());
  if (parsed == null || parsed <= 0) return null;
  return parsed;
}

int _toMilli(double value) => (value * 1000).round();
double _round2(double value) => (value * 100).roundToDouble() / 100;
double _round3(double value) => (value * 1000).roundToDouble() / 1000;

String _num(double value) => value == value.roundToDouble()
    ? value.toInt().toString()
    : value.toStringAsFixed(3).replaceAll(RegExp(r'0+$'), '').replaceAll(RegExp(r'\.$'), '');

/// Pluraliza etiquetas cortas en español: Caja→Cajas, Unidad→Unidades.
String _plural(String label, num count) {
  if (count == 1) return label;
  final lower = label.toLowerCase();
  if (lower.endsWith('s')) return label;
  if (RegExp(r'[aeiouáéíóú]$').hasMatch(lower)) return '${label}s';
  return '${label}es';
}

/// Pluraliza una etiqueta de presentación para mostrarla con su cantidad:
/// "2 Cajas", "3 Unidades", "1 Paquete".
String pluralLabel(String label, num count) => _plural(label, count);
