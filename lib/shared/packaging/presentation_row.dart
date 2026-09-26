/// Cómo se imprime una línea guardada con presentación (`sale_items`,
/// `quotation_items`): la fila trae la cantidad en unidades base y el
/// documento tiene que decir "2 Cajas", no "40".
library;

import 'product_packaging.dart';

/// Unidades base que representa UNA presentación de la fila. 1 = línea suelta.
double presentationFactor(Map<String, dynamic> row) {
  if (PackagingUom.fromDb(row['uom']?.toString()) == PackagingUom.unit) {
    return 1;
  }
  final factor = _toDouble(row['uom_factor']);
  return factor > 0 ? factor : 1;
}

/// Cantidad a imprimir: 2 (cajas) en vez de 40 (paquetes).
double presentationQuantity(Map<String, dynamic> row) {
  final factor = presentationFactor(row);
  final quantity = _toDouble(row['quantity']);
  return factor == 1 ? quantity : _round3(quantity / factor);
}

/// Precio de UNA presentación. Sale de `uom_price` (migración 92 para ventas,
/// 95 para cotizaciones), que guarda el precio con que se cobró la caja; solo
/// si falta se deriva del unitario.
double presentationUnitPrice(Map<String, dynamic> row) {
  final factor = presentationFactor(row);
  final price = _toDouble(row['unit_price']);
  if (factor == 1) return price;
  final stored = _toDouble(row['uom_price']);
  return stored > 0 ? stored : _round2(price * factor);
}

/// "Caja" para el documento; `null` en una línea suelta.
String? presentationLabelOf(Map<String, dynamic> row) {
  if (presentationFactor(row) == 1) return null;
  final name = row['unit_name']?.toString().trim();
  return (name == null || name.isEmpty) ? 'Presentación' : name;
}

double _toDouble(dynamic value) {
  if (value == null) return 0;
  if (value is num) return value.toDouble();
  return double.tryParse(value.toString()) ?? 0;
}

double _round2(double value) => (value * 100).roundToDouble() / 100;
double _round3(double value) => (value * 1000).roundToDouble() / 1000;
