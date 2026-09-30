// Pantalla `/devoluciones`: historial básico de devoluciones de la
// sucursal actual. Lee de `returns` vía `salesRepositoryProvider.fetchRecentReturns`.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/tokens.dart';
import '../../../shared/errors/friendly_error.dart';
import '../../../shared/formatters/formatters.dart';
import '../../../shared/widgets/empty_state.dart';
import '../../../shared/widgets/module_page.dart';
import '../../sales/data/sales_repository.dart';
import '../../sales/presentation/sales_providers.dart';

final returnsHistoryProvider =
    FutureProvider.autoDispose<List<ReturnSummary>>((ref) async {
  final repo = ref.watch(salesRepositoryProvider);
  return repo.fetchRecentReturns(limit: 100);
});

class ReturnsPage extends ConsumerWidget {
  const ReturnsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final returnsAsync = ref.watch(returnsHistoryProvider);

    return ModulePage(
      title: 'Devoluciones',
      description: 'Historial de devoluciones registradas en la sucursal.',
      actions: [
        FilledButton.tonalIcon(
          onPressed: () {
            ref.read(posModeProvider.notifier).state = PosMode.returnMode;
            context.go('/ventas');
          },
          icon: const Icon(Icons.add, size: 18),
          label: const Text('Nueva devolución'),
        ),
        OutlinedButton.icon(
          onPressed: () => ref.invalidate(returnsHistoryProvider),
          icon: const Icon(Icons.refresh, size: 18),
          label: const Text('Actualizar'),
        ),
      ],
      child: returnsAsync.when(
        loading: () => const Padding(
          padding: EdgeInsets.symmetric(vertical: AppTokens.s32),
          child: Center(child: CircularProgressIndicator()),
        ),
        error: (error, _) => ErrorCard(
          message: 'No se pudo cargar el historial: ${friendlyErrorMessage(error)}',
          onRetry: () => ref.invalidate(returnsHistoryProvider),
        ),
        data: (items) {
          if (items.isEmpty) {
            return const EmptyStateCard(
              icon: Icons.assignment_return_outlined,
              message:
                  'Aún no hay devoluciones registradas. Procesa una desde el POS en modo Devolución.',
            );
          }
          return Card(
            margin: EdgeInsets.zero,
            child: Padding(
              padding: const EdgeInsets.symmetric(
                vertical: AppTokens.s8,
                horizontal: AppTokens.s4,
              ),
              child: Column(
                children: [
                  for (var i = 0; i < items.length; i++) ...[
                    _ReturnRow(item: items[i]),
                    if (i != items.length - 1)
                      const Divider(height: 1, color: AppTokens.border),
                  ],
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

class _ReturnRow extends StatelessWidget {
  const _ReturnRow({required this.item});

  final ReturnSummary item;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: AppTokens.s16,
        vertical: AppTokens.s12,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(AppTokens.s10),
            decoration: BoxDecoration(
              color: const Color(0xFFFEF2F2),
              borderRadius: BorderRadius.circular(8),
            ),
            child: const Icon(
              Icons.assignment_return_outlined,
              color: Color(0xFFEF4444),
              size: 20,
            ),
          ),
          const SizedBox(width: AppTokens.s12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(
                      item.returnNumber.isEmpty ? '—' : item.returnNumber,
                      style: const TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 14,
                      ),
                    ),
                    const SizedBox(width: AppTokens.s8),
                    Text(
                      formatDateTime(item.returnDate),
                      style: const TextStyle(
                        color: AppTokens.mutedForeground,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 2),
                Text(
                  '${item.itemsCount} línea(s)'
                  '${item.clientName != null ? " · ${item.clientName}" : ""}'
                  '${item.originalSaleId != null ? " · ref. ${_short(item.originalSaleId!)}" : ""}',
                  style: const TextStyle(
                    color: AppTokens.mutedForeground,
                    fontSize: 12,
                  ),
                ),
                if (item.notes != null && item.notes!.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Text(
                    item.notes!,
                    style: const TextStyle(
                      color: AppTokens.mutedForeground,
                      fontSize: 12,
                      fontStyle: FontStyle.italic,
                    ),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(width: AppTokens.s12),
          Text(
            '- ${money(item.totalAmount)}',
            style: const TextStyle(
              color: Color(0xFFEF4444),
              fontWeight: FontWeight.w800,
              fontSize: 15,
            ),
          ),
        ],
      ),
    );
  }

  String _short(String id) {
    if (id.length <= 8) return id;
    return '${id.substring(0, 4)}…${id.substring(id.length - 4)}';
  }
}
