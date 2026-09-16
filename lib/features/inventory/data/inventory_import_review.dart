import '../../../shared/formatters/formatters.dart';
import '../../../shared/packaging/product_packaging.dart';
import 'inventory_repository.dart';

/// Algo que una importación le haría a un producto que ya existe y que conviene
/// mirar antes de confirmar.
class InventoryImportWarning {
  const InventoryImportWarning({
    required this.sku,
    required this.name,
    required this.messages,
  });

  final String sku;
  final String name;
  final List<String> messages;
}

/// Compara las filas del archivo con el catálogo actual, por SKU.
///
/// La plantilla escribe `precio`, `stock` y `activo` directo sobre el producto,
/// en la unidad BASE. En un producto con empaque esa unidad es el paquete, pero
/// quien llena el archivo piensa en cajas: un precio o stock de caja en esas
/// columnas deshace la configuración sin ningún error. Y `activo` vacío cuenta
/// como "sí", así que el archivo reactiva los gemelos desactivados.
///
/// Devuelve un aviso por producto afectado, en el orden del archivo.
List<InventoryImportWarning> reviewImportAgainstCatalog({
  required List<InventoryProductInput> inputs,
  required List<InventoryProduct> catalog,
}) {
  final bySku = <String, InventoryProduct>{
    for (final product in catalog)
      if ((product.sku ?? '').trim().isNotEmpty) product.sku!.trim(): product,
  };

  final warnings = <InventoryImportWarning>[];
  for (final input in inputs) {
    final sku = input.sku?.trim() ?? '';
    final current = bySku[sku];
    if (current == null) continue;

    final messages = <String>[];

    if (!current.isActive && input.isActive) {
      messages.add('Está desactivado y el archivo lo vuelve a activar.');
    }

    final packaging = current.packaging;
    if (packaging.hasPacks) {
      final uom = packaging.largestUom;
      final large = packaging.labelFor(uom);
      final unit = packaging.effectiveUnitLabel.toLowerCase();
      final largePrice = packaging.priceFor(uom, current.price);

      // Un paquete que cuesta la mitad de la caja o más: ese número es de caja.
      if (input.price != current.price && input.price * 2 >= largePrice) {
        messages.add(
          'Precio ${money(input.price)} parece de ${large.toLowerCase()}: '
          'en la plantilla "precio" es por $unit '
          '(hoy ${money(current.price)}).',
        );
      }

      if (input.stock != current.stock) {
        messages.add(
          'Stock: ${_describe(packaging.describeStock, current.stock)} → '
          '${_describe(packaging.describeStock, input.stock)} '
          '(en la plantilla "stock" va en ${pluralLabel(unit, 2)}).',
        );
      }
    }

    if (messages.isNotEmpty) {
      warnings.add(
        InventoryImportWarning(
          sku: sku,
          name: current.name,
          messages: messages,
        ),
      );
    }
  }
  return warnings;
}

String _describe(String Function(double) describe, double stock) =>
    stock < 0 ? '-${describe(-stock)}' : describe(stock);
