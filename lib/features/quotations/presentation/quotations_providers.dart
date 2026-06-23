import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/web/kv_store.dart';
import '../../auth/presentation/auth_providers.dart';
import '../data/quotations_models.dart';
import '../data/quotations_repository.dart';

final quotationsRepositoryProvider = Provider<QuotationsRepository>((ref) {
  final client = ref.watch(supabaseClientProvider);
  return QuotationsRepository(client);
});

final quotationsSearchProvider = StateProvider<String>((ref) => '');

/// Snapshot del borrador de una cotización NUEVA (no aplica al editar una
/// existente, que se carga del servidor). Se guarda al salir de la pantalla
/// y se restaura al volver, para no perder el borrador al navegar.
class QuotationDraft {
  const QuotationDraft({
    this.items = const [],
    this.clientId,
    this.validUntil,
    this.status,
    this.notes = '',
  });

  final List<QuoteDraftLine> items;
  final String? clientId;
  final DateTime? validUntil;
  final QuoteStatus? status;
  final String notes;

  bool get isEmpty => items.isEmpty && notes.isEmpty && clientId == null;
}

/// Se hidrata del store al crearse (en web, de localStorage), así el borrador
/// de cotización nueva sobrevive una recarga de página, no solo la navegación.
final quotationDraftProvider = StateProvider<QuotationDraft>(
  (ref) => _decodeQuotationDraft(kvRead(_quotationDraftKey)) ??
      const QuotationDraft(),
);

const _quotationDraftKey = 'bpw.quotation_draft.v1';

/// Borra el borrador de cotización persistido (store global). Usar al cambiar
/// de usuario: la clave NO es por-usuario, así que sin esto el borrador del
/// usuario anterior reaparece. Invalidar `quotationDraftProvider` después.
void clearQuotationDraftStore() => kvRemove(_quotationDraftKey);

/// Persiste el borrador en el store. Si quedó vacío, borra la entrada.
void saveQuotationDraftToStore(QuotationDraft draft) {
  if (draft.isEmpty) {
    kvRemove(_quotationDraftKey);
  } else {
    kvWrite(_quotationDraftKey, _encodeQuotationDraft(draft));
  }
}

String _encodeQuotationDraft(QuotationDraft d) => jsonEncode({
      'clientId': d.clientId,
      'validUntil': d.validUntil?.toIso8601String(),
      'status': d.status?.name,
      'notes': d.notes,
      'items': [
        for (final it in d.items)
          {
            'product': _quoteProductToJson(it.product),
            'quantity': it.quantity,
          },
      ],
    });

QuotationDraft? _decodeQuotationDraft(String? raw) {
  if (raw == null || raw.isEmpty) return null;
  try {
    final map = jsonDecode(raw) as Map<String, dynamic>;
    final items = <QuoteDraftLine>[
      for (final e in (map['items'] as List? ?? const []))
        if (e is Map<String, dynamic>)
          QuoteDraftLine(
            product:
                QuoteCatalogProduct.fromMap(e['product'] as Map<String, dynamic>),
            quantity: (e['quantity'] as num).toDouble(),
          ),
    ];
    final statusName = map['status']?.toString();
    final validUntilRaw = map['validUntil']?.toString();
    return QuotationDraft(
      items: items,
      clientId: map['clientId']?.toString(),
      validUntil:
          validUntilRaw == null ? null : DateTime.tryParse(validUntilRaw),
      status: statusName == null
          ? null
          : QuoteStatus.values
              .where((s) => s.name == statusName)
              .cast<QuoteStatus?>()
              .firstWhere((_) => true, orElse: () => null),
      notes: map['notes']?.toString() ?? '',
    );
  } catch (_) {
    return null;
  }
}

Map<String, dynamic> _quoteProductToJson(QuoteCatalogProduct p) => {
      'id': p.id,
      'name': p.name,
      'sku': p.sku,
      'barcode': p.barcode,
      'description': p.description,
      'price': p.price,
      'tax_rate': p.taxRate,
      'stock': p.stock,
      'is_active': p.isActive,
    };

final quotationProductsProvider = FutureProvider<List<QuoteCatalogProduct>>((
  ref,
) async {
  final repository = ref.watch(quotationsRepositoryProvider);
  return repository.fetchProducts();
});

final quotationClientsProvider = FutureProvider<List<QuoteClientOption>>((
  ref,
) async {
  final repository = ref.watch(quotationsRepositoryProvider);
  return repository.fetchClients();
});

final quotationDetailProvider = FutureProvider.family<QuoteDetail, String>((
  ref,
  quoteId,
) async {
  final repository = ref.watch(quotationsRepositoryProvider);
  return repository.fetchQuoteDetail(quoteId);
});

final quotationsFoundationProvider = FutureProvider<QuoteFoundationBundle>((
  ref,
) async {
  final repository = ref.watch(quotationsRepositoryProvider);
  return repository.loadFoundation();
});
