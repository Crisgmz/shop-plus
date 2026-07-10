import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/tokens.dart';
import '../../../shared/formatters/formatters.dart';
import '../../../shared/responsive/responsive_layout.dart';
import '../../cash_register/presentation/cash_register_providers.dart';
import '../data/quotations_models.dart';
import 'convert_payment_dialog.dart';
import 'quotations_providers.dart';

class QuotationCreatePage extends ConsumerStatefulWidget {
  const QuotationCreatePage({super.key, this.quoteId});

  final String? quoteId;

  bool get isEditing => quoteId != null && quoteId!.isNotEmpty;

  @override
  ConsumerState<QuotationCreatePage> createState() =>
      _QuotationCreatePageState();
}

class _QuotationCreatePageState extends ConsumerState<QuotationCreatePage> {
  final _searchController = TextEditingController();
  final _notesController = TextEditingController();
  final List<QuoteDraftLine> _items = [];

  String? _clientId;
  DateTime _validUntil = DateTime.now().add(const Duration(days: 15));
  QuoteStatus _status = QuoteStatus.draft;
  bool _isSubmitting = false;
  bool _isBootstrapping = false;
  bool _didBootstrap = false;
  // Cuando se guarda una cotización nueva, navegamos a su vista de edición.
  // En ese caso NO debemos volver a guardar el borrador en dispose (sería
  // restaurar líneas ya guardadas la próxima vez que se cree una nueva).
  bool _skipDraftPersist = false;
  String? _quoteCode;
  DateTime? _createdAt;
  String? _convertedSaleId;

  double get _subtotal => QuotationsMath.round2(
    _items.fold<double>(0, (sum, item) => sum + item.lineSubtotal),
  );
  double get _tax => QuotationsMath.round2(
    _items.fold<double>(0, (sum, item) => sum + item.lineTax),
  );
  double get _total => QuotationsMath.round2(_subtotal + _tax);

  bool get _canEditDocument => _status != QuoteStatus.converted;
  bool get _canDeleteDocument =>
      _status == QuoteStatus.draft ||
      _status == QuoteStatus.rejected ||
      _status == QuoteStatus.expired;
  bool get _canConvertDocument =>
      _status == QuoteStatus.approved &&
      _validUntil.isAfter(DateTime.now()) &&
      _convertedSaleId == null;

  @override
  void initState() {
    super.initState();
    // Restaurar el borrador de una cotización nueva si el usuario lo dejó a
    // medias y navegó a otra sección. No aplica al editar una existente.
    if (!widget.isEditing) {
      final draft = ref.read(quotationDraftProvider);
      _items.addAll(draft.items);
      _clientId = draft.clientId;
      if (draft.validUntil != null) _validUntil = draft.validUntil!;
      if (draft.status != null) _status = draft.status!;
      _notesController.text = draft.notes;
    }
  }

  @override
  void dispose() {
    _searchController.dispose();
    _notesController.dispose();
    super.dispose();
  }

  /// Guarda el borrador de la cotización NUEVA tras cada cambio (no en
  /// `dispose`, que no es confiable) para no perderlo al navegar. Al editar
  /// una existente no toca el borrador, y si ya se guardó tampoco
  /// (ver [_skipDraftPersist]).
  void _persistDraft() {
    if (widget.isEditing || _skipDraftPersist) return;
    final draft = QuotationDraft(
      items: List<QuoteDraftLine>.from(_items),
      clientId: _clientId,
      validUntil: _validUntil,
      status: _status,
      notes: _notesController.text,
    );
    ref.read(quotationDraftProvider.notifier).state = draft;
    // Persistir también a localStorage (web) para sobrevivir recargas.
    saveQuotationDraftToStore(draft);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (widget.isEditing && !_didBootstrap) {
      _didBootstrap = true;
      WidgetsBinding.instance.addPostFrameCallback((_) => _loadQuote());
    }
  }

  Future<void> _loadQuote() async {
    final quoteId = widget.quoteId;
    if (quoteId == null || quoteId.isEmpty) return;

    setState(() => _isBootstrapping = true);
    try {
      final detail = await ref.read(quotationDetailProvider(quoteId).future);
      final products = await ref.read(quotationProductsProvider.future);
      final productsById = {for (final p in products) p.id: p};

      if (!mounted) return;
      setState(() {
        _quoteCode = detail.code;
        _createdAt = detail.createdAt;
        _clientId = detail.clientId;
        _validUntil = detail.validUntil.toLocal();
        _status = detail.effectiveStatus == QuoteStatus.expired
            ? QuoteStatus.expired
            : detail.status;
        _convertedSaleId = detail.saleId;
        _notesController.text = detail.notes;
        _items
          ..clear()
          ..addAll(
            detail.items.map((item) {
              final product = productsById[item.productId] ??
                  QuoteCatalogProduct(
                    id: item.productId,
                    name: item.productName,
                    sku: item.productSku,
                    description: item.productDescription,
                    barcode: null,
                    price: item.unitPrice,
                    taxRate: item.taxRate,
                    stock: 0,
                    isActive: true,
                  );
              final gross = item.quantity * item.unitPrice;
              final discountPct = gross > 0
                  ? QuotationsMath.round2(item.discountAmount / gross * 100)
                  : 0.0;
              return QuoteDraftLine(
                product: product,
                quantity: item.quantity,
                unitPrice: item.unitPrice,
                discountPct: discountPct,
              );
            }),
          );
      });
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('No se pudo cargar la cotización: $error')),
      );
      context.pop();
    } finally {
      if (mounted) setState(() => _isBootstrapping = false);
    }
  }

  void _addItem(QuoteCatalogProduct product) {
    if (!_canEditDocument) return;
    setState(() {
      final index = _items.indexWhere((item) => item.product.id == product.id);
      if (index >= 0) {
        final current = _items[index];
        _items[index] = current.copyWith(quantity: current.quantity + 1);
      } else {
        _items.add(QuoteDraftLine(product: product, quantity: 1));
      }
    });
    _persistDraft();
  }

  void _updateQuantity(int index, double delta) {
    if (!_canEditDocument) return;
    setState(() {
      final current = _items[index];
      final nextQuantity = current.quantity + delta;
      if (nextQuantity <= 0) {
        _items.removeAt(index);
      } else {
        _items[index] = current.copyWith(quantity: nextQuantity);
      }
    });
    _persistDraft();
  }

  void _updatePrice(int index, double value) {
    if (!_canEditDocument) return;
    setState(() {
      _items[index] = _items[index].copyWith(unitPrice: value < 0 ? 0 : value);
    });
    _persistDraft();
  }

  void _updateDiscount(int index, double value) {
    if (!_canEditDocument) return;
    final clamped = value.clamp(0.0, 100.0);
    setState(() {
      _items[index] = _items[index].copyWith(discountPct: clamped);
    });
    _persistDraft();
  }

  Future<void> _pickValidUntil() async {
    if (!_canEditDocument) return;

    final picked = await showDatePicker(
      context: context,
      initialDate: _validUntil,
      firstDate: DateTime.now(),
      lastDate: DateTime.now().add(const Duration(days: 365)),
    );

    if (picked != null) {
      setState(() {
        _validUntil = DateTime(
          picked.year,
          picked.month,
          picked.day,
          23,
          59,
          59,
        );
        if (_status == QuoteStatus.expired && _validUntil.isAfter(DateTime.now())) {
          _status = QuoteStatus.draft;
        }
      });
      _persistDraft();
    }
  }

  Future<void> _handleSave() async {
    if (_items.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Agrega al menos un producto.')),
      );
      return;
    }

    setState(() => _isSubmitting = true);

    try {
      final repository = ref.read(quotationsRepositoryProvider);
      final input = QuoteCreateInput(
        clientId: _clientId,
        notes: _notesController.text,
        validUntil: _validUntil,
        status: _status,
        items: _items
            .map(
              (item) => QuoteCreateItem(
                productId: item.product.id,
                productName: item.product.name,
                productSku: item.product.sku,
                productDescription: item.product.description,
                quantity: item.quantity,
                unitPrice: item.unitPrice,
                taxRate: item.product.taxRate,
                discountAmount: item.discountAmount,
              ),
            )
            .toList(growable: false),
      );

      if (widget.isEditing) {
        await repository.updateQuote(widget.quoteId!, input);
        ref.invalidate(quotationDetailProvider(widget.quoteId!));
      } else {
        final createdId = await repository.createQuote(input);
        // La cotización quedó guardada: descartamos el borrador para que la
        // próxima "nueva" empiece en blanco y no lo re-guardamos en dispose.
        _skipDraftPersist = true;
        ref.read(quotationDraftProvider.notifier).state = const QuotationDraft();
        saveQuotationDraftToStore(const QuotationDraft());
        if (mounted) {
          context.go('/cotizaciones/$createdId');
        }
      }

      ref.invalidate(quotationsFoundationProvider);

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            widget.isEditing
                ? 'Cotización actualizada correctamente.'
                : 'Cotización guardada correctamente.',
          ),
        ),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error al guardar la cotización: $error')),
      );
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  Future<void> _handleDelete() async {
    final quoteId = widget.quoteId;
    if (quoteId == null) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Eliminar cotización'),
        content: Text(
          '¿Eliminar ${_quoteCode ?? 'esta cotización'}? Solo se recomienda cuando sigue siendo borrador, perdida o expirada.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(backgroundColor: AppTokens.error),
            child: const Text('Eliminar'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    try {
      await ref.read(quotationsRepositoryProvider).deleteQuote(quoteId);
      ref.invalidate(quotationsFoundationProvider);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Cotización eliminada.')),
      );
      context.go('/cotizaciones');
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('No se pudo eliminar: $error')),
      );
    }
  }

  Future<void> _handleConvert() async {
    final quoteId = widget.quoteId;
    if (quoteId == null) return;

    final method = await showConvertPaymentDialog(
      context,
      quoteCode: _quoteCode ?? 'la cotización',
    );

    if (method == null || !mounted) return;

    try {
      final result = await ref
          .read(quotationsRepositoryProvider)
          .convertToSale(
            quoteId,
            paymentMethod: method,
            cashSessionId: ref.read(activeCashSessionIdProvider),
          );
      ref.invalidate(quotationDetailProvider(quoteId));
      ref.invalidate(quotationsFoundationProvider);
      if (!mounted) return;
      setState(() {
        _status = QuoteStatus.converted;
        _convertedSaleId = result.saleId;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Cotización convertida a venta ${result.saleNumber}.'),
        ),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('No se pudo convertir: $error')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final productsAsync = ref.watch(quotationProductsProvider);
    final clientsAsync = ref.watch(quotationClientsProvider);
    final query = ref.watch(quotationsSearchProvider).trim().toLowerCase();
    final isMobile = ResponsiveLayout.isMobile(context);
    final padding = adaptivePadding(context);

    return Scaffold(
      backgroundColor: AppTokens.background,
      appBar: AppBar(
        title: Text(widget.isEditing ? 'Cotización' : 'Nueva cotización'),
        actions: [
          if (widget.isEditing && _canDeleteDocument)
            IconButton(
              onPressed: _isSubmitting ? null : _handleDelete,
              icon: const Icon(Icons.delete_outline_rounded),
              tooltip: 'Eliminar',
            ),
        ],
      ),
      body: _isBootstrapping
          ? const Center(child: CircularProgressIndicator())
          : Padding(
              padding: padding,
              child: ResponsiveLayout(
                mobile: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildHeader(context),
                    const SizedBox(height: AppTokens.s16),
                    _buildSearchBar(),
                    const SizedBox(height: AppTokens.s12),
                    Expanded(child: _buildProductGrid(productsAsync, query)),
                    const SizedBox(height: AppTokens.s12),
                    SizedBox(height: 420, child: _buildDetailsPanel(clientsAsync)),
                  ],
                ),
                desktop: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      flex: 5,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _buildHeader(context),
                          const SizedBox(height: AppTokens.s16),
                          _buildSearchBar(),
                          const SizedBox(height: AppTokens.s12),
                          Expanded(child: _buildProductGrid(productsAsync, query)),
                        ],
                      ),
                    ),
                    const SizedBox(width: AppTokens.s24),
                    Expanded(flex: 3, child: _buildDetailsPanel(clientsAsync)),
                  ],
                ),
              ),
            ),
      floatingActionButton: isMobile && _canEditDocument
          ? FloatingActionButton.extended(
              onPressed: _isSubmitting ? null : _handleSave,
              label: Text(widget.isEditing ? 'Guardar cambios' : 'Guardar'),
              icon: _isSubmitting
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.save_rounded),
            )
          : null,
    );
  }

  Widget _buildHeader(BuildContext context) {
    final statusColor = switch (_status) {
      QuoteStatus.draft => AppTokens.brandBlueDark,
      QuoteStatus.sent => AppTokens.info,
      QuoteStatus.underReview => AppTokens.warning,
      QuoteStatus.approved => AppTokens.success,
      QuoteStatus.rejected => AppTokens.error,
      QuoteStatus.expired => AppTokens.textMuted,
      QuoteStatus.converted => AppTokens.success,
    };

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: AppTokens.s12,
          runSpacing: AppTokens.s8,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            Text(
              widget.isEditing ? (_quoteCode ?? 'Cotización') : 'Nueva cotización',
              style: Theme.of(
                context,
              ).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w800),
            ),
            Container(
              padding: const EdgeInsets.symmetric(
                horizontal: AppTokens.s10,
                vertical: AppTokens.s6,
              ),
              decoration: BoxDecoration(
                color: statusColor.withValues(alpha: 0.10),
                borderRadius: BorderRadius.circular(AppTokens.radiusRound),
              ),
              child: Text(
                _status.label,
                style: TextStyle(
                  color: statusColor,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: AppTokens.s4),
        Text(
          widget.isEditing
              ? 'Consulta, edita, gestiona vigencia y convierte la cotización desde una sola pantalla.'
              : 'Prepara una propuesta comercial sin acoplarla al checkout de ventas.',
          style: Theme.of(
            context,
          ).textTheme.bodyMedium?.copyWith(color: AppTokens.textSecondary),
        ),
        if (_createdAt != null) ...[
          const SizedBox(height: AppTokens.s8),
          Text(
            'Creada el ${formatDate(_createdAt!)} · Vence ${formatDate(_validUntil)}',
            style: const TextStyle(
              color: AppTokens.textSecondary,
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildSearchBar() {
    return Container(
      height: 48,
      padding: const EdgeInsets.symmetric(horizontal: AppTokens.s16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(AppTokens.radius),
        border: Border.all(color: AppTokens.cardBorder),
      ),
      child: Row(
        children: [
          const Icon(
            Icons.search_rounded,
            color: AppTokens.textMuted,
            size: 20,
          ),
          const SizedBox(width: AppTokens.s12),
          Expanded(
            child: TextField(
              controller: _searchController,
              enabled: _canEditDocument,
              onChanged: (value) =>
                  ref.read(quotationsSearchProvider.notifier).state = value,
              decoration: const InputDecoration(
                hintText: 'Buscar producto...',
                border: InputBorder.none,
                enabledBorder: InputBorder.none,
                focusedBorder: InputBorder.none,
                isDense: true,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildProductGrid(
    AsyncValue<List<QuoteCatalogProduct>> productsAsync,
    String query,
  ) {
    return productsAsync.when(
      data: (products) {
        final filtered = products
            .where((product) {
              final matchesName = product.name.toLowerCase().contains(query);
              final matchesSku =
                  product.sku?.toLowerCase().contains(query) ?? false;
              final matchesBarcode =
                  product.barcode?.toLowerCase().contains(query) ?? false;
              return product.isActive &&
                  (query.isEmpty ||
                      matchesName ||
                      matchesSku ||
                      matchesBarcode);
            })
            .toList(growable: false);

        if (filtered.isEmpty) {
          return const Center(child: Text('No hay productos para cotizar.'));
        }

        return LayoutBuilder(
          builder: (context, constraints) {
            final columns = (constraints.maxWidth / 150).floor().clamp(2, 8);
            return GridView.builder(
              padding: const EdgeInsets.only(bottom: AppTokens.s12),
              gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: columns,
                mainAxisSpacing: AppTokens.s12,
                crossAxisSpacing: AppTokens.s12,
                childAspectRatio: 0.88,
              ),
              itemCount: filtered.length,
              itemBuilder: (context, index) => _ProductCard(
                product: filtered[index],
                disabled: !_canEditDocument,
                onTap: () => _addItem(filtered[index]),
              ),
            );
          },
        );
      },
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (error, _) =>
          Center(child: Text('Error cargando productos: $error')),
    );
  }

  Widget _buildDetailsPanel(AsyncValue<List<QuoteClientOption>> clientsAsync) {
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppTokens.radiusL),
        side: const BorderSide(color: AppTokens.cardBorder),
      ),
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(AppTokens.s16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Detalle comercial',
                  style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16),
                ),
                const SizedBox(height: AppTokens.s12),
                clientsAsync.when(
                  data: (clients) => _ClientSearchField(
                    currentId: _clientId,
                    clients: clients,
                    enabled: _canEditDocument,
                    onChanged: (value) {
                      setState(() => _clientId = value);
                      _persistDraft();
                    },
                  ),
                  loading: () => const LinearProgressIndicator(),
                  error: (error, _) => Text('Error cargando clientes: $error'),
                ),
                const SizedBox(height: AppTokens.s12),
                DropdownButtonFormField<QuoteStatus>(
                  initialValue: _status,
                  decoration: const InputDecoration(
                    labelText: 'Estado',
                    filled: true,
                    fillColor: AppTokens.secondary,
                    border: OutlineInputBorder(),
                  ),
                  items: QuoteStatus.values
                      .where((status) => status.canBeSelectedOnForm)
                      .map(
                        (status) => DropdownMenuItem<QuoteStatus>(
                          value: status,
                          child: Text(status.label),
                        ),
                      )
                      .toList(growable: false),
                  onChanged: _canEditDocument
                      ? (value) {
                          if (value != null) {
                            setState(() => _status = value);
                            _persistDraft();
                          }
                        }
                      : null,
                ),
                const SizedBox(height: AppTokens.s12),
                OutlinedButton.icon(
                  onPressed: _pickValidUntil,
                  icon: const Icon(Icons.event_available_outlined),
                  label: Text('Vigencia: ${formatDate(_validUntil)}'),
                ),
                if (_validUntil.isBefore(DateTime.now())) ...[
                  const SizedBox(height: AppTokens.s10),
                  const Text(
                    'Esta cotización ya está vencida. Ajusta la fecha de vigencia y guarda para reactivarla.',
                    style: TextStyle(
                      color: AppTokens.warning,
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ],
            ),
          ),
          const Divider(height: 1),
          Expanded(
            child: _items.isEmpty
                ? const Center(
                    child: Text(
                      'No hay líneas todavía.',
                      style: TextStyle(color: AppTokens.textMuted),
                    ),
                  )
                : ListView.builder(
                    padding: const EdgeInsets.all(AppTokens.s12),
                    itemCount: _items.length,
                    itemBuilder: (context, index) => _QuoteLineTile(
                      item: _items[index],
                      readOnly: !_canEditDocument,
                      onDecrease: () => _updateQuantity(index, -1),
                      onIncrease: () => _updateQuantity(index, 1),
                      onRemove: () =>
                          _updateQuantity(index, -_items[index].quantity),
                      onPriceChanged: (value) => _updatePrice(index, value),
                      onDiscountChanged: (value) =>
                          _updateDiscount(index, value),
                    ),
                  ),
          ),
          Padding(
            padding: const EdgeInsets.all(AppTokens.s16),
            child: TextField(
              controller: _notesController,
              enabled: _canEditDocument,
              maxLines: 3,
              onChanged: (_) => _persistDraft(),
              decoration: const InputDecoration(
                hintText: 'Notas comerciales, condiciones o alcance...',
                filled: true,
                fillColor: AppTokens.secondary,
                border: OutlineInputBorder(),
              ),
            ),
          ),
          const Divider(height: 1),
          Padding(
            padding: const EdgeInsets.all(AppTokens.s20),
            child: Column(
              children: [
                _totalLine('Subtotal', money(_subtotal)),
                const SizedBox(height: AppTokens.s4),
                _totalLine('Impuestos', money(_tax)),
                const SizedBox(height: AppTokens.s12),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text(
                      'Total',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    Text(
                      money(_total),
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w900,
                        color: AppTokens.brandBlueDark,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: AppTokens.s16),
                if (widget.isEditing) ...[
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: _canConvertDocument ? _handleConvert : null,
                          icon: const Icon(Icons.shopping_cart_checkout_rounded),
                          label: const Text('Convertir a venta'),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: AppTokens.s12),
                ],
                if (!ResponsiveLayout.isMobile(context))
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton(
                          onPressed: () => context.pop(),
                          child: const Text('Cerrar'),
                        ),
                      ),
                      const SizedBox(width: AppTokens.s12),
                      Expanded(
                        child: FilledButton.icon(
                          onPressed: _canEditDocument && !_isSubmitting
                              ? _handleSave
                              : null,
                          icon: _isSubmitting
                              ? const SizedBox(
                                  width: 16,
                                  height: 16,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: Colors.white,
                                  ),
                                )
                              : const Icon(Icons.save_rounded, size: 18),
                          label: Text(
                            widget.isEditing ? 'Guardar cambios' : 'Guardar',
                          ),
                        ),
                      ),
                    ],
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
            color: AppTokens.textSecondary,
            fontSize: 13,
            fontWeight: FontWeight.w500,
          ),
        ),
        Text(
          value,
          style: const TextStyle(
            color: AppTokens.textPrimary,
            fontSize: 13,
            fontWeight: FontWeight.w700,
          ),
        ),
      ],
    );
  }
}

class _ProductCard extends StatelessWidget {
  const _ProductCard({
    required this.product,
    required this.onTap,
    required this.disabled,
  });

  final QuoteCatalogProduct product;
  final VoidCallback onTap;
  final bool disabled;

  @override
  Widget build(BuildContext context) {
    final initial = product.name.isEmpty ? '?' : product.name[0].toUpperCase();

    return InkWell(
      onTap: disabled ? null : onTap,
      borderRadius: BorderRadius.circular(AppTokens.radiusL),
      child: Opacity(
        opacity: disabled ? 0.55 : 1,
        child: Container(
          padding: const EdgeInsets.all(AppTokens.s12),
          decoration: BoxDecoration(
            color: Colors.white,
            border: Border.all(color: AppTokens.cardBorder),
            borderRadius: BorderRadius.circular(AppTokens.radiusL),
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: AppTokens.secondary,
                  borderRadius: BorderRadius.circular(AppTokens.radius),
                ),
                child: Center(
                  child: Text(
                    initial,
                    style: const TextStyle(
                      color: AppTokens.brandBlueDark,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: AppTokens.s10),
              Text(
                product.name,
                textAlign: TextAlign.center,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: AppTokens.textPrimary,
                ),
              ),
              const SizedBox(height: AppTokens.s6),
              Text(
                money(product.price),
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w800,
                  color: AppTokens.brandBlueDark,
                ),
              ),
              const SizedBox(height: AppTokens.s4),
              Text(
                'Stock ${qty(product.stock)}',
                style: const TextStyle(
                  fontSize: 11,
                  color: AppTokens.textSecondary,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Línea de cotización con el mismo estilo del carrito de facturación:
/// tarjeta con nombre + campos Precio (editable) · Cantidad (+/-) ·
/// Descuento % (editable) · Total (calculado).
class _QuoteLineTile extends StatefulWidget {
  const _QuoteLineTile({
    required this.item,
    required this.onDecrease,
    required this.onIncrease,
    required this.onRemove,
    required this.onPriceChanged,
    required this.onDiscountChanged,
    required this.readOnly,
  });

  final QuoteDraftLine item;
  final VoidCallback onDecrease;
  final VoidCallback onIncrease;
  final VoidCallback onRemove;
  final ValueChanged<double> onPriceChanged;
  final ValueChanged<double> onDiscountChanged;
  final bool readOnly;

  @override
  State<_QuoteLineTile> createState() => _QuoteLineTileState();
}

class _QuoteLineTileState extends State<_QuoteLineTile> {
  late final TextEditingController _priceCtrl;
  late final TextEditingController _discountCtrl;

  @override
  void initState() {
    super.initState();
    _priceCtrl = TextEditingController(text: _fmt(widget.item.unitPrice));
    _discountCtrl = TextEditingController(text: _fmt(widget.item.discountPct));
  }

  @override
  void didUpdateWidget(covariant _QuoteLineTile old) {
    super.didUpdateWidget(old);
    if (old.item.unitPrice != widget.item.unitPrice) {
      _priceCtrl.text = _fmt(widget.item.unitPrice);
    }
    if (old.item.discountPct != widget.item.discountPct) {
      _discountCtrl.text = _fmt(widget.item.discountPct);
    }
  }

  @override
  void dispose() {
    _priceCtrl.dispose();
    _discountCtrl.dispose();
    super.dispose();
  }

  static String _fmt(double v) =>
      v == v.roundToDouble() ? v.toInt().toString() : v.toStringAsFixed(2);

  @override
  Widget build(BuildContext context) {
    final item = widget.item;
    return Container(
      margin: const EdgeInsets.only(bottom: AppTokens.s8),
      padding: const EdgeInsets.all(AppTokens.s10),
      decoration: BoxDecoration(
        color: AppTokens.secondary,
        borderRadius: BorderRadius.circular(AppTokens.radius),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      item.product.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontWeight: FontWeight.w600,
                        fontSize: 13,
                        color: AppTokens.textPrimary,
                      ),
                    ),
                    Text(
                      'ITBIS ${item.product.taxRate.toStringAsFixed(0)}%'
                      '${item.discountPct > 0 ? '  ·  Desc. ${_fmt(item.discountPct)}%' : ''}',
                      style: const TextStyle(
                        fontSize: 11,
                        color: AppTokens.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
              if (!widget.readOnly)
                IconButton(
                  onPressed: widget.onRemove,
                  icon: const Icon(
                    Icons.close_rounded,
                    size: 18,
                    color: AppTokens.error,
                  ),
                  visualDensity: VisualDensity.compact,
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                ),
            ],
          ),
          const SizedBox(height: AppTokens.s8),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Expanded(
                flex: 3,
                child: _MiniField(
                  label: 'Precio',
                  controller: _priceCtrl,
                  enabled: !widget.readOnly,
                  onCommit: (raw) => widget.onPriceChanged(
                    double.tryParse(raw) ?? item.unitPrice,
                  ),
                ),
              ),
              const SizedBox(width: 6),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const _MiniLabel('Cantidad'),
                  const SizedBox(height: 4),
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      _QtySmallBtn(
                        icon: Icons.remove,
                        onTap: widget.readOnly ? () {} : widget.onDecrease,
                      ),
                      SizedBox(
                        width: 30,
                        child: Center(
                          child: Text(
                            qty(item.quantity),
                            style: const TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 13,
                            ),
                          ),
                        ),
                      ),
                      _QtySmallBtn(
                        icon: Icons.add,
                        onTap: widget.readOnly ? () {} : widget.onIncrease,
                      ),
                    ],
                  ),
                ],
              ),
              const SizedBox(width: 6),
              Expanded(
                flex: 3,
                child: _MiniField(
                  label: 'Desc. %',
                  controller: _discountCtrl,
                  enabled: !widget.readOnly,
                  onCommit: (raw) => widget.onDiscountChanged(
                    double.tryParse(raw) ?? item.discountPct,
                  ),
                ),
              ),
              const SizedBox(width: 6),
              Expanded(
                flex: 3,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const _MiniLabel('Total'),
                    const SizedBox(height: 4),
                    SizedBox(
                      height: 36,
                      child: Align(
                        alignment: Alignment.centerRight,
                        child: Text(
                          money(item.lineTotal),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontWeight: FontWeight.w800,
                            fontSize: 13,
                            color: AppTokens.brandBlueDark,
                          ),
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

class _MiniLabel extends StatelessWidget {
  const _MiniLabel(this.text);
  final String text;

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: const TextStyle(
        fontSize: 10,
        color: AppTokens.textSecondary,
        fontWeight: FontWeight.w600,
      ),
    );
  }
}

/// Mini-campo numérico con etiqueta que confirma su valor al perder el foco o
/// al presionar enter (mismo comportamiento que el carrito de ventas).
class _MiniField extends StatefulWidget {
  const _MiniField({
    required this.label,
    required this.controller,
    required this.onCommit,
    this.enabled = true,
  });

  final String label;
  final TextEditingController controller;
  final ValueChanged<String> onCommit;
  final bool enabled;

  @override
  State<_MiniField> createState() => _MiniFieldState();
}

class _MiniFieldState extends State<_MiniField> {
  late final FocusNode _node;

  @override
  void initState() {
    super.initState();
    _node = FocusNode()..addListener(_onFocusChange);
  }

  void _onFocusChange() {
    if (!_node.hasFocus) widget.onCommit(widget.controller.text);
  }

  @override
  void dispose() {
    _node.removeListener(_onFocusChange);
    _node.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _MiniLabel(widget.label),
        const SizedBox(height: 4),
        SizedBox(
          height: 36,
          child: TextField(
            controller: widget.controller,
            focusNode: _node,
            enabled: widget.enabled,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            textAlign: TextAlign.right,
            style: const TextStyle(fontSize: 13),
            decoration: const InputDecoration(
              isDense: true,
              filled: true,
              fillColor: Colors.white,
              contentPadding:
                  EdgeInsets.symmetric(horizontal: 8, vertical: 8),
              border: OutlineInputBorder(),
              enabledBorder: OutlineInputBorder(
                borderSide: BorderSide(color: AppTokens.cardBorder),
              ),
            ),
            onSubmitted: widget.onCommit,
          ),
        ),
      ],
    );
  }
}

class _QtySmallBtn extends StatelessWidget {
  const _QtySmallBtn({required this.icon, required this.onTap});

  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(6),
      child: Container(
        width: 24,
        height: 24,
        decoration: BoxDecoration(
          color: Colors.white,
          border: Border.all(color: AppTokens.cardBorder),
          borderRadius: BorderRadius.circular(6),
        ),
        child: Icon(icon, size: 14, color: AppTokens.textSecondary),
      ),
    );
  }
}

class _QuoteClientPick {
  const _QuoteClientPick({required this.id, required this.label});
  final String? id;
  final String label;
}

/// Buscador de cliente escribible (mismo patrón que en ventas): al enfocar
/// muestra la lista completa y al escribir filtra por nombre. Permite elegir
/// "Cliente general" (id null).
class _ClientSearchField extends StatefulWidget {
  const _ClientSearchField({
    required this.currentId,
    required this.clients,
    required this.onChanged,
    required this.enabled,
  });

  final String? currentId;
  final List<QuoteClientOption> clients;
  final ValueChanged<String?> onChanged;
  final bool enabled;

  @override
  State<_ClientSearchField> createState() => _ClientSearchFieldState();
}

class _ClientSearchFieldState extends State<_ClientSearchField> {
  static const _generalLabel = 'Cliente general';

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
    return RawAutocomplete<_QuoteClientPick>(
      textEditingController: _textController,
      focusNode: _focusNode,
      displayStringForOption: (o) => o.label,
      optionsBuilder: (value) {
        if (!widget.enabled) return const Iterable<_QuoteClientPick>.empty();
        final all = <_QuoteClientPick>[
          const _QuoteClientPick(id: null, label: _generalLabel),
          for (final c in widget.clients)
            _QuoteClientPick(id: c.id, label: c.fullName),
        ];
        final q = value.text.trim().toLowerCase();
        if (q.isEmpty || q == _labelForId(widget.currentId).toLowerCase()) {
          return all;
        }
        return all.where((o) => o.label.toLowerCase().contains(q));
      },
      onSelected: (o) {
        widget.onChanged(o.id);
        _textController.text = o.label;
        _focusNode.unfocus();
      },
      fieldViewBuilder: (context, controller, focusNode, onSubmitted) {
        return TextField(
          controller: controller,
          focusNode: focusNode,
          enabled: widget.enabled,
          style: const TextStyle(fontSize: 14),
          onTap: () => controller.selection = TextSelection(
            baseOffset: 0,
            extentOffset: controller.text.length,
          ),
          decoration: InputDecoration(
            labelText: 'Cliente',
            filled: true,
            fillColor: AppTokens.secondary,
            border: const OutlineInputBorder(),
            prefixIcon: const Icon(Icons.person_search_rounded, size: 20),
            suffixIcon: widget.currentId != null
                ? IconButton(
                    icon: const Icon(Icons.close, size: 18),
                    tooltip: 'Volver a Cliente general',
                    onPressed: widget.enabled
                        ? () {
                            widget.onChanged(null);
                            _textController.text = _generalLabel;
                            _focusNode.unfocus();
                          }
                        : null,
                  )
                : const Icon(Icons.arrow_drop_down),
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
                    ),
                    title: Text(o.label, style: const TextStyle(fontSize: 13)),
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
