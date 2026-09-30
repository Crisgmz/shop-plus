import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/tokens.dart';
import '../../../shared/responsive/responsive_layout.dart';
import '../../../shared/widgets/app_snackbar.dart';
import '../../../shared/widgets/module_page.dart';
import '../../../shared/widgets/role_gate.dart';
import '../../cash_register/data/cash_register_repository.dart';
import '../../cash_register/presentation/cash_register_providers.dart';
import 'sales_page.dart';

/// Punto de entrada del módulo de Ventas.
///
/// Antes: `/ventas` mostraba directo el POS. El cajero usaba cualquier caja
/// implícita (sesión sin nombre).
///
/// Ahora: muestra primero el selector de cajas (como WilmaxPOS). Admin y
/// supervisor ven todas las cajas activas de la sucursal; el cajero solo ve
/// las que le fueron asignadas. Al elegir una caja se abre la sesión (si
/// no había) y se entra al POS sobre esa caja.
class SalesEntryPage extends ConsumerWidget {
  const SalesEntryPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Si ya hay una caja activa explícitamente seleccionada por el
    // usuario, vamos directo al POS. El picker se muestra para elegir
    // entre las cajas disponibles (abiertas o por abrir).
    final activeSessionId = ref.watch(activeCashSessionIdProvider);
    if (activeSessionId != null) {
      return const SalesPage();
    }
    return const _SalesCashRegisterPicker();
  }
}

class _SalesCashRegisterPicker extends ConsumerStatefulWidget {
  const _SalesCashRegisterPicker();

  @override
  ConsumerState<_SalesCashRegisterPicker> createState() =>
      _SalesCashRegisterPickerState();
}

class _SalesCashRegisterPickerState
    extends ConsumerState<_SalesCashRegisterPicker> {
  /// Se dispara una sola vez por vida del picker para evitar abrir el
  /// dialog en bucle cuando el cajero cancela y el widget hace rebuild.
  bool _autoTriggered = false;

  @override
  Widget build(BuildContext context) {
    final role = ref.watch(roleAccessProvider);
    final canSeeAll = role.isAdmin || role.isSupervisor;
    // Admin/supervisor ven el catálogo completo de la sucursal. El cajero
    // solo ve las cajas a las que está explícitamente asignado.
    final cajasAsync = canSeeAll
        ? ref.watch(cashRegistersProvider)
        : ref.watch(myCashRegistersProvider);

    // Sesiones abiertas del usuario actual (puede tener varias, una por
    // cada caja que abrió pero todavía no cerró).
    final mySessionsAsync = ref.watch(myOpenCashSessionsProvider);

    // Auto-entry: si el cajero tiene una sola caja asignada, entra
    // directo (a la sesión abierta si existe, o al dialog de apertura
    // si no). Admin/supervisor siempre ven el picker.
    final cajas = cajasAsync.valueOrNull;
    final mySessions = mySessionsAsync.valueOrNull;
    if (!canSeeAll &&
        !_autoTriggered &&
        cajas != null &&
        cajas.length == 1 &&
        mySessions != null) {
      _autoTriggered = true;
      final caja = cajas.first;
      MyOpenCashSession? existing;
      for (final s in mySessions) {
        if (s.cashRegisterId == caja.id) {
          existing = s;
          break;
        }
      }
      final existingCapture = existing;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        enterOrOpenCaja(context, ref, caja, existingCapture);
      });
    }

    return ModulePage(
      title: 'Ventas',
      description: canSeeAll
          ? 'Selecciona la caja desde donde vas a vender.'
          : 'Selecciona tu caja para empezar a vender.',
      actions: [
        OutlinedButton.icon(
          onPressed: () {
            ref.invalidate(cashRegistersProvider);
            ref.invalidate(myCashRegistersProvider);
            ref.invalidate(myOpenCashSessionsProvider);
            ref.invalidate(allOpenCashSessionsProvider);
            ref.invalidate(cashRegisterDataProvider);
          },
          icon: const Icon(Icons.refresh, size: 18),
          label: const Text('Actualizar'),
        ),
      ],
      child: cajasAsync.when(
        data: (cajas) {
          if (cajas.isEmpty) {
            return _EmptyState(canManage: canSeeAll);
          }
          // Mapa: cash_register_id → sessionId abierto del usuario actual.
          // Si la caja está aquí, el tap entra directo al POS (sin reabrir).
          final mySessionsByRegister = <String, MyOpenCashSession>{
            for (final s in mySessionsAsync.valueOrNull ?? const [])
              if (s.cashRegisterId != null) s.cashRegisterId!: s,
          };
          return _CashRegisterGrid(
            cajas: cajas,
            mySessionsByRegister: mySessionsByRegister,
            onPick: (caja, existingSession) =>
                enterOrOpenCaja(context, ref, caja, existingSession),
          );
        },
        loading: () => const Padding(
          padding: EdgeInsets.symmetric(vertical: 48),
          child: Center(child: CircularProgressIndicator()),
        ),
        error: (error, _) => Padding(
          padding: const EdgeInsets.symmetric(vertical: 48),
          child: Center(
            child: Text(
              'No se pudieron cargar las cajas: ${friendlyErrorMessage(error)}',
              style: const TextStyle(color: Color(0xFFEF4444)),
            ),
          ),
        ),
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.canManage});

  final bool canManage;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 48, horizontal: 16),
      child: Column(
        children: [
          const Icon(Icons.point_of_sale_outlined,
              size: 56, color: Color(0xFF94A3B8)),
          const SizedBox(height: AppTokens.s12),
          Text(
            canManage
                ? 'Todavía no hay cajas configuradas en esta sucursal.'
                : 'No tienes cajas asignadas. Pídele al administrador que te asigne una.',
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontSize: 15,
              color: Color(0xFF475569),
            ),
          ),
          if (canManage) ...[
            const SizedBox(height: AppTokens.s16),
            const Text(
              'Configura las cajas y sus cajeros en /configuración.',
              textAlign: TextAlign.center,
              style: TextStyle(color: Color(0xFF94A3B8), fontSize: 13),
            ),
          ],
        ],
      ),
    );
  }
}

/// Flujo compartido para entrar a una caja: si ya hay sesión abierta del
/// usuario en esa caja, la marca como activa; si no, abre el dialog para
/// ingresar el monto de apertura. Usado tanto por el tap manual del grid
/// como por el auto-entry cuando el cajero tiene una sola caja asignada.
Future<void> enterOrOpenCaja(
  BuildContext context,
  WidgetRef ref,
  CashRegisterEntity caja,
  MyOpenCashSession? existingSession,
) async {
  // Caso 1: el usuario YA tiene una sesión abierta en esta caja.
  // No abrimos nueva — solo seteamos como activa y vamos al POS.
  if (existingSession != null) {
    ref.read(activeCashSessionIdProvider.notifier).state =
        existingSession.sessionId;
    return;
  }

  // Caso 2: caja sin sesión abierta. Pedimos monto de apertura.
  final input = await showDialog<OpenCashInput>(
    context: context,
    builder: (_) => _OpenSessionForCajaDialog(caja: caja),
  );
  if (input == null) return;
  if (!context.mounted) return;

  final repository = ref.read(cashRegisterRepositoryProvider);
  try {
    final sessionId = await repository.openSessionForRegister(input);
    ref.read(activeCashSessionIdProvider.notifier).state = sessionId;
    ref.invalidate(cashRegisterDataProvider);
    ref.invalidate(myOpenCashSessionsProvider);
    ref.invalidate(allOpenCashSessionsProvider);
    if (!context.mounted) return;
    AppSnackBar.success(context, 'Caja "${caja.name}" abierta');
  } catch (error) {
    if (!context.mounted) return;
    AppSnackBar.error(context, 'No se pudo abrir la caja', error);
  }
}

class _CashRegisterGrid extends StatelessWidget {
  const _CashRegisterGrid({
    required this.cajas,
    required this.mySessionsByRegister,
    required this.onPick,
  });

  final List<CashRegisterEntity> cajas;

  /// Mapa cash_register_id → sesión abierta del usuario actual en esa
  /// caja. Si la caja está en este mapa, el tap entra directo al POS
  /// sin pedir dialog de apertura.
  final Map<String, MyOpenCashSession> mySessionsByRegister;

  /// Callback que dispara [enterOrOpenCaja] con el context/ref del padre.
  final Future<void> Function(
    CashRegisterEntity caja,
    MyOpenCashSession? existingSession,
  ) onPick;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        final columns = ResponsiveLayout.isMobile(context)
            ? 1
            : (width / 280).floor().clamp(1, 4);

        return GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          padding: const EdgeInsets.only(bottom: 24),
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: columns,
            mainAxisSpacing: 16,
            crossAxisSpacing: 16,
            mainAxisExtent: 140,
          ),
          itemCount: cajas.length,
          itemBuilder: (context, i) {
            final caja = cajas[i];
            final existingSession = mySessionsByRegister[caja.id];
            return _CashRegisterCard(
              caja: caja,
              hasOpenSession: existingSession != null,
              onTap: () => onPick(caja, existingSession),
            );
          },
        );
      },
    );
  }
}

class _CashRegisterCard extends StatelessWidget {
  const _CashRegisterCard({
    required this.caja,
    required this.onTap,
    required this.hasOpenSession,
  });

  final CashRegisterEntity caja;
  final VoidCallback onTap;
  final bool hasOpenSession;

  @override
  Widget build(BuildContext context) {
    final borderColor = hasOpenSession
        ? const Color(0xFF22C55E)
        : const Color(0xFFE2E8F0);
    final iconBgColor =
        hasOpenSession ? const Color(0xFF22C55E) : AppTokens.primary;

    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(AppTokens.radius),
      child: InkWell(
        borderRadius: BorderRadius.circular(AppTokens.radius),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.all(AppTokens.s16),
          decoration: BoxDecoration(
            border: Border.all(color: borderColor, width: hasOpenSession ? 2 : 1),
            borderRadius: BorderRadius.circular(AppTokens.radius),
          ),
          child: Row(
            children: [
              Container(
                width: 56,
                height: 56,
                decoration: BoxDecoration(
                  color: iconBgColor,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(
                  hasOpenSession ? Icons.lock_open : Icons.point_of_sale,
                  color: Colors.white,
                  size: 28,
                ),
              ),
              const SizedBox(width: AppTokens.s12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      caja.name,
                      style: const TextStyle(
                        fontWeight: FontWeight.w800,
                        fontSize: 16,
                        color: Color(0xFF1E293B),
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        Icon(
                          hasOpenSession
                              ? Icons.fiber_manual_record
                              : Icons.group_outlined,
                          size: 14,
                          color: hasOpenSession
                              ? const Color(0xFF22C55E)
                              : const Color(0xFF64748B),
                        ),
                        const SizedBox(width: 4),
                        Text(
                          hasOpenSession
                              ? 'Abierta — entrar'
                              : (caja.assignedUserIds.isEmpty
                                  ? 'Sin cajeros asignados'
                                  : '${caja.assignedUserIds.length} cajero(s)'),
                          style: TextStyle(
                            fontSize: 12,
                            color: hasOpenSession
                                ? const Color(0xFF16A34A)
                                : const Color(0xFF64748B),
                            fontWeight: hasOpenSession
                                ? FontWeight.w600
                                : FontWeight.w500,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const Icon(Icons.arrow_forward_ios,
                  size: 14, color: Color(0xFF94A3B8)),
            ],
          ),
        ),
      ),
    );
  }
}

/// Dialog de apertura para una caja concreta. Reusa el endpoint
/// `open_cash_session_for_register` que valida que el usuario actual esté
/// asignado a la caja (RLS + RPC).
class _OpenSessionForCajaDialog extends StatefulWidget {
  const _OpenSessionForCajaDialog({required this.caja});

  final CashRegisterEntity caja;

  @override
  State<_OpenSessionForCajaDialog> createState() =>
      _OpenSessionForCajaDialogState();
}

class _OpenSessionForCajaDialogState extends State<_OpenSessionForCajaDialog> {
  final _formKey = GlobalKey<FormState>();
  final _openingController = TextEditingController(text: '0');
  final _notesController = TextEditingController();

  @override
  void dispose() {
    _openingController.dispose();
    _notesController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text('Abrir ${widget.caja.name}'),
      content: SizedBox(
        width: ResponsiveLayout.isMobile(context) ? double.maxFinite : 380,
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextFormField(
                controller: _openingController,
                autofocus: true,
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
                decoration: const InputDecoration(
                  labelText: 'Monto de apertura',
                  prefixText: r'RD$ ',
                  border: OutlineInputBorder(),
                ),
                validator: (value) {
                  final parsed = double.tryParse(value ?? '');
                  if (parsed == null || parsed < 0) return 'Monto inválido';
                  return null;
                },
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _notesController,
                decoration: const InputDecoration(
                  labelText: 'Nota (opcional)',
                  border: OutlineInputBorder(),
                ),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancelar'),
        ),
        FilledButton(onPressed: _submit, child: const Text('Abrir caja')),
      ],
    );
  }

  void _submit() {
    if (!_formKey.currentState!.validate()) return;
    Navigator.of(context).pop(
      OpenCashInput(
        openingAmount: double.parse(_openingController.text),
        notes: _notesController.text,
        cashRegisterId: widget.caja.id,
      ),
    );
  }
}
