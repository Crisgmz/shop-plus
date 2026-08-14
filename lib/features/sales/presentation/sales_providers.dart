import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/web/kv_store.dart';
import '../../auth/presentation/auth_providers.dart';
import '../../settings/presentation/settings_providers.dart';
import '../data/sales_repository.dart';

final salesSearchProvider = StateProvider<String>((ref) => '');
final salesSelectedCategoryProvider = StateProvider<String?>((ref) => null);

/// True si la sucursal actual tiene una secuencia NCF de [receiptType] activa,
/// vigente y con stock. Si la vista no existe o falla, devuelve false (nunca
/// asume que hay comprobantes disponibles).
final ncfSequenceAvailableProvider =
    FutureProvider.autoDispose.family<bool, String>((ref, receiptType) async {
  final client = ref.watch(supabaseClientProvider);
  try {
    final rows = await client
        .from('vw_ncf_stock')
        .select('remaining, is_active, is_expired')
        .eq('receipt_type', receiptType)
        .eq('is_active', true)
        .eq('is_expired', false);
    return (rows as List).any((row) {
      final remaining = (row['remaining'] as num?)?.toInt();
      return remaining == null || remaining > 0; // null = secuencia sin tope
    });
  } catch (_) {
    return false;
  }
});

/// Comprobante con el que arranca cada venta nueva del POS.
///
/// Sale de Ajustes → Fiscal ("Tipo de comprobante por defecto",
/// `branch_fiscal_settings.default_receipt_type`). Si ese tipo necesita NCF y
/// la sucursal no tiene secuencia disponible, cae a 'none' (sin comprobante)
/// en vez de dejar que la venta falle al cobrar.
final posDefaultReceiptTypeProvider =
    FutureProvider.autoDispose<String>((ref) async {
  String configured;
  try {
    final fiscal =
        await ref.watch(settingsRepositoryProvider).fetchBranchFiscalSettings();
    configured = fiscal?.defaultReceiptType.trim() ?? '';
  } catch (_) {
    configured = '';
  }
  if (configured.isEmpty) configured = 'none';
  if (configured == 'none') return 'none';

  final available =
      await ref.watch(ncfSequenceAvailableProvider(configured).future);
  return available ? configured : 'none';
});

/// Modo del POS: venta normal o registro de devolución (PRD F5).
enum PosMode { sale, returnMode }

final posModeProvider = StateProvider<PosMode>((ref) => PosMode.sale);

/// Snapshot del carrito + cabecera de la venta en curso.
///
/// El POS guarda este snapshot al salir de la pantalla (en `dispose`) y lo
/// restaura al volver (en `initState`). Así, si el cajero arma una venta y
/// navega a otra sección, no pierde lo que estaba haciendo. El provider NO es
/// autoDispose a propósito: debe sobrevivir mientras la app esté abierta.
class SaleDraft {
  const SaleDraft({
    this.items = const [],
    this.receiptType = 'none',
    this.paymentMethod,
    this.clientId,
    this.notes = '',
    this.heldSaleId,
  });

  final List<SaleCartItem> items;
  final String receiptType;
  final String? paymentMethod;
  final String? clientId;
  final String notes;

  /// Id de la cuenta GUARDADA (venta `pending`) que se reabrió en el POS. Se
  /// setea desde el historial al "Reabrir" y viaja con el draft (sobrevive
  /// recargas en web). Al completar la venta, el POS descarta esa pendiente
  /// (devuelve su stock reservado) antes de registrar la venta real, para no
  /// duplicar la cuenta ni el stock. Null en una venta nueva normal.
  final String? heldSaleId;

  bool get isEmpty => items.isEmpty;
}

/// El provider se hidrata del store al crearse: en web lee de localStorage,
/// así el carrito sobrevive una recarga de página (F5 / banner "Actualizar"),
/// no solo la navegación entre secciones.
final saleDraftProvider = StateProvider<SaleDraft>(
  (ref) => _decodeSaleDraft(kvRead(_saleDraftKey)) ?? const SaleDraft(),
);

const _saleDraftKey = 'bpw.sale_draft.v1';

/// Borra el borrador persistido (store global). Usar al cambiar de usuario:
/// la clave NO es por-usuario, así que sin esto el carrito del usuario anterior
/// reaparece para el siguiente. El caller debe invalidar `saleDraftProvider`
/// después para que la memoria también se limpie.
void clearSaleDraftStore() => kvRemove(_saleDraftKey);

/// Persiste el borrador en el store. Llamar tras cada cambio del carrito.
/// Si el carrito quedó vacío y sin datos de cabecera, borra la entrada.
void saveSaleDraftToStore(SaleDraft draft) {
  if (draft.items.isEmpty &&
      draft.notes.isEmpty &&
      draft.clientId == null &&
      draft.paymentMethod == null &&
      draft.heldSaleId == null) {
    kvRemove(_saleDraftKey);
  } else {
    kvWrite(_saleDraftKey, _encodeSaleDraft(draft));
  }
}

String _encodeSaleDraft(SaleDraft d) => jsonEncode({
      'receiptType': d.receiptType,
      'paymentMethod': d.paymentMethod,
      'clientId': d.clientId,
      'notes': d.notes,
      'heldSaleId': d.heldSaleId,
      'items': [
        for (final it in d.items)
          {
            'product': _salesProductToJson(it.product),
            'quantity': it.quantity,
            'unitPrice': it.unitPrice,
            'discountPct': it.discountPct,
            'imeis': it.imeis,
            'priceTier': it.priceTier,
          },
      ],
    });

SaleDraft? _decodeSaleDraft(String? raw) {
  if (raw == null || raw.isEmpty) return null;
  try {
    final map = jsonDecode(raw) as Map<String, dynamic>;
    final items = <SaleCartItem>[
      for (final e in (map['items'] as List? ?? const []))
        if (e is Map<String, dynamic>)
          SaleCartItem(
            product:
                _salesProductFromJson(e['product'] as Map<String, dynamic>),
            quantity: (e['quantity'] as num).toDouble(),
            unitPrice: (e['unitPrice'] as num?)?.toDouble(),
            discountPct: (e['discountPct'] as num?)?.toDouble() ?? 0,
            imeis: (e['imeis'] as List?)
                    ?.map((x) => x.toString())
                    .toList(growable: false) ??
                const <String>[],
            priceTier: e['priceTier']?.toString() ?? 'retail',
          ),
    ];
    return SaleDraft(
      items: items,
      receiptType: map['receiptType']?.toString() ?? 'none',
      paymentMethod: map['paymentMethod']?.toString(),
      clientId: map['clientId']?.toString(),
      notes: map['notes']?.toString() ?? '',
      heldSaleId: map['heldSaleId']?.toString(),
    );
  } catch (_) {
    // JSON corrupto o de una versión vieja del modelo: empezar limpio.
    return null;
  }
}

Map<String, dynamic> _salesProductToJson(SalesProduct p) => {
      'id': p.id,
      'name': p.name,
      'sku': p.sku,
      'barcode': p.barcode,
      'category_id': p.categoryId,
      'category_name': p.categoryName,
      'price': p.price,
      'cost': p.cost,
      'tax_rate': p.taxRate,
      'stock': p.stock,
      'is_active': p.isActive,
      'price_tier_1': p.priceTier1,
      'price_tier_2': p.priceTier2,
      'price_tier_3': p.priceTier3,
      'price_tier_4': p.priceTier4,
      'price_tier_5': p.priceTier5,
      'price_tier_6': p.priceTier6,
      'price_tier_7': p.priceTier7,
      'price_tier_8': p.priceTier8,
      'price_tier_9': p.priceTier9,
      'price_tier_10': p.priceTier10,
      'image_url': p.imageUrl,
      'imeis': p.imeis,
    };

SalesProduct _salesProductFromJson(Map<String, dynamic> m) {
  // SalesProduct.fromMap deriva categoryName del mapa categoryNames; le
  // pasamos el par guardado para reconstruirlo idéntico.
  final categoryId = m['category_id']?.toString();
  final categoryName = m['category_name']?.toString();
  return SalesProduct.fromMap(m, {
    if (categoryId != null && categoryName != null) categoryId: categoryName,
  });
}

final salesRepositoryProvider = Provider<SalesRepository>((ref) {
  final client = ref.watch(supabaseClientProvider);
  return SalesRepository(client);
});

final salesCategoriesProvider = FutureProvider<List<SalesCategory>>((
  ref,
) async {
  final repository = ref.watch(salesRepositoryProvider);
  return repository.fetchCategories();
});

final salesProductsProvider = FutureProvider<List<SalesProduct>>((ref) async {
  final repository = ref.watch(salesRepositoryProvider);
  return repository.fetchProducts();
});

final salesClientsProvider = FutureProvider<List<SalesClient>>((ref) async {
  final repository = ref.watch(salesRepositoryProvider);
  return repository.fetchClients();
});

/// Productos filtrados por búsqueda + categoría, memoizado.
///
/// Antes el POS llamaba `_filterProducts(...)` en cada `build()` — un
/// O(n) por keystroke aunque la búsqueda no hubiera cambiado. Riverpod
/// cachea el resultado mientras los inputs no cambien.
final salesFilteredProductsProvider =
    Provider<List<SalesProduct>>((ref) {
  final productsAsync = ref.watch(salesProductsProvider);
  final products = productsAsync.valueOrNull;
  if (products == null) return const <SalesProduct>[];

  final rawQuery = ref.watch(salesSearchProvider).trim().toLowerCase();
  final categoryId = ref.watch(salesSelectedCategoryProvider);

  return products.where((p) {
    // Mostramos productos aunque tengan stock 0 (se ven con cantidad 0); solo
    // ocultamos los inactivos. El bloqueo de venta sin stock, si aplica, lo
    // maneja el setting "No permitir venta sin stock" al agregar al carrito.
    if (!p.isActive) return false;
    if (categoryId != null && p.categoryId != categoryId) return false;
    if (rawQuery.isEmpty) return true;
    return p.name.toLowerCase().contains(rawQuery) ||
        (p.sku?.toLowerCase().contains(rawQuery) ?? false) ||
        (p.barcode?.toLowerCase().contains(rawQuery) ?? false);
  }).toList(growable: false);
});

/// Map clientId → SalesClient para lookups O(1) en el POS.
/// Antes el POS hacía `clients.firstWhere((c) => c.id == _clientId)` en
/// cada cambio de cliente; con 1000+ clientes era O(n).
final salesClientsByIdProvider = Provider<Map<String, SalesClient>>((ref) {
  final clients = ref.watch(salesClientsProvider).valueOrNull ?? const [];
  return {for (final c in clients) c.id: c};
});
