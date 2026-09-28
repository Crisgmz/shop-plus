/// Unidad base de cada producto (`products.unit_label`: "Paquete", "Unidad"…)
/// para imprimir las líneas sueltas de un documento que también trae cajas:
/// "6 Paquetes" junto a "1 Caja", no "6" a secas.
library;

import 'package:supabase_flutter/supabase_flutter.dart';

/// `{product_id: 'Paquete'}` de los productos que tienen unidad configurada.
/// Si la base todavía no tiene la columna (migración 86) o la consulta falla,
/// devuelve vacío: el documento cae a "Unidad" en vez de no imprimirse.
Future<Map<String, String>> fetchProductUnitLabels(
  SupabaseClient client,
  Iterable<String?> productIds,
) async {
  final ids = productIds
      .whereType<String>()
      .where((id) => id.trim().isNotEmpty)
      .toSet()
      .toList(growable: false);
  if (ids.isEmpty) return const {};
  try {
    final rows = await client
        .from('products')
        .select('id, unit_label')
        .inFilter('id', ids);
    final out = <String, String>{};
    for (final row in rows) {
      final label = row['unit_label']?.toString().trim() ?? '';
      if (label.isNotEmpty) out[row['id'].toString()] = label;
    }
    return out;
  } on PostgrestException {
    return const {};
  }
}
