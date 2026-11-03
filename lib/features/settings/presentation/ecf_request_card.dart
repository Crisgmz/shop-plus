import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/tokens.dart';
import '../../../shared/widgets/app_snackbar.dart';
import '../data/ecf_request_repository.dart';
import 'ecf_onboarding_page.dart' show ecfOnboardingRoute;
import 'ecf_request_dialog.dart';
import 'ecf_sequence_dialog.dart';
import 'settings_providers.dart';

/// Facturación electrónica (e-CF) en Configuración.
///
/// Portado de mangospos (`ecf_request_card.dart`). Muestra en qué va el
/// trámite y qué toca hacer ahora — nada más. La etapa la DERIVA el servidor
/// de lo que ya existe (empresa registrada con el proveedor, autorización de
/// la DGII, secuencias e-NCF, modalidad), así que no hay un estado guardado
/// aparte que se pueda desincronizar de la realidad.
class EcfRequestCard extends ConsumerWidget {
  const EcfRequestCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final statusAsync = ref.watch(ecfRequestStatusProvider);

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: statusAsync.when(
          data: (status) => _Content(status: status),
          loading: () => const Center(
            child: Padding(
              padding: EdgeInsets.all(12),
              child: CircularProgressIndicator(),
            ),
          ),
          error: (error, _) => Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Facturación electrónica (e-CF)',
                style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16),
              ),
              const SizedBox(height: AppTokens.s8),
              Text(
                'No se pudo consultar el estado: $error',
                style: const TextStyle(color: AppTokens.mutedForeground),
              ),
              const SizedBox(height: AppTokens.s8),
              OutlinedButton.icon(
                onPressed: () => ref.invalidate(ecfRequestStatusProvider),
                icon: const Icon(Icons.refresh, size: 18),
                label: const Text('Reintentar'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Content extends ConsumerStatefulWidget {
  const _Content({required this.status});

  final EcfRequestStatus status;

  @override
  ConsumerState<_Content> createState() => _ContentState();
}

class _ContentState extends ConsumerState<_Content> {
  bool _busy = false;

  EcfRequestStatus get _status => widget.status;

  @override
  Widget build(BuildContext context) {
    final stage = _status.stage;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                'Facturación electrónica (e-CF)',
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            _StageChip(stage: stage),
          ],
        ),
        const SizedBox(height: 6),
        Text(
          _stageDescription(stage),
          style: const TextStyle(color: AppTokens.mutedForeground),
        ),

        if (_status.requestedAt != null) ...[
          const SizedBox(height: AppTokens.s12),
          _detail(
            'Solicitada',
            '${_status.requestedAt!.day.toString().padLeft(2, '0')}-'
                '${_status.requestedAt!.month.toString().padLeft(2, '0')}-'
                '${_status.requestedAt!.year}',
          ),
        ],

        if (_status.sequences.isNotEmpty) ...[
          const SizedBox(height: AppTokens.s16),
          const Text(
            'Secuencias e-NCF',
            style: TextStyle(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: AppTokens.s8),
          for (final seq in _status.sequences) _sequenceRow(seq),
        ],

        const SizedBox(height: AppTokens.s16),
        Wrap(
          spacing: AppTokens.s12,
          runSpacing: AppTokens.s8,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            ..._actionsFor(stage),
            // El trámite completo (certificado, Oficina Virtual, pruebas de
            // la DGII, secuencias y encendido) vive en su propia página.
            if (stage != EcfRequestStage.none)
              TextButton.icon(
                onPressed: _busy
                    ? null
                    : () => context.push(ecfOnboardingRoute),
                icon: const Icon(Icons.checklist_rtl, size: 18),
                label: const Text('Ver el trámite paso a paso'),
              ),
          ],
        ),
      ],
    );
  }

  List<Widget> _actionsFor(EcfRequestStage stage) {
    return switch (stage) {
      EcfRequestStage.none => [
        FilledButton.icon(
          onPressed: _busy ? null : _openRequest,
          icon: const Icon(Icons.bolt_outlined, size: 18),
          label: const Text('Solicitar facturación electrónica'),
        ),
      ],
      // La solicitud entró pero la empresa no quedó registrada con el
      // proveedor (RNC ya existente, o certificado rechazado): se puede
      // reintentar con el archivo o la contraseña correctos.
      EcfRequestStage.company => [
        const _Waiting('Estamos revisando tu solicitud. Te vamos a contactar.'),
        OutlinedButton.icon(
          onPressed: _busy ? null : _openRequest,
          icon: const Icon(Icons.refresh, size: 18),
          label: const Text('Reenviar con otro certificado'),
        ),
      ],
      EcfRequestStage.certification => [
        const _Waiting(
          'Falta la autorización de la DGII como emisor electrónico. '
          'Te acompañamos en el trámite.',
        ),
      ],
      EcfRequestStage.sequences => [
        FilledButton.icon(
          onPressed: _busy ? null : _openSequence,
          icon: const Icon(Icons.playlist_add, size: 18),
          label: const Text('Cargar secuencia e-NCF'),
        ),
      ],
      EcfRequestStage.activation => [
        FilledButton.icon(
          onPressed: _busy ? null : () => _setEnabled(true),
          icon: const Icon(Icons.power_settings_new, size: 18),
          label: const Text('Encender facturación electrónica'),
        ),
        OutlinedButton.icon(
          onPressed: _busy ? null : _openSequence,
          icon: const Icon(Icons.playlist_add, size: 18),
          label: const Text('Cargar otra secuencia'),
        ),
      ],
      EcfRequestStage.active => [
        OutlinedButton.icon(
          onPressed: _busy ? null : _openSequence,
          icon: const Icon(Icons.playlist_add, size: 18),
          label: const Text('Cargar secuencia e-NCF'),
        ),
        TextButton.icon(
          onPressed: _busy ? null : () => _setEnabled(false),
          icon: const Icon(Icons.power_settings_new, size: 18),
          label: const Text('Apagar'),
        ),
      ],
    };
  }

  static String _stageDescription(EcfRequestStage stage) => switch (stage) {
    EcfRequestStage.none =>
      'Emite tus facturas como comprobantes fiscales electrónicos ante la '
          'DGII. Para empezar, mándanos los datos de tu empresa y tu '
          'certificado de firma digital.',
    EcfRequestStage.company =>
      'Recibimos tu solicitud. Falta terminar el registro de tu empresa con '
          'el proveedor.',
    EcfRequestStage.certification =>
      'Tu empresa ya está registrada con el proveedor. Falta que la DGII te '
          'autorice como emisor electrónico.',
    EcfRequestStage.sequences =>
      'Ya estás autorizado. Carga la secuencia e-NCF que te entregó la DGII '
          'para poder emitir.',
    EcfRequestStage.activation =>
      'Todo listo. Al encenderla, tus ventas empiezan a salir como '
          'comprobantes electrónicos.',
    EcfRequestStage.active =>
      'Tus ventas salen como comprobantes fiscales electrónicos. Si el '
          'proveedor no responde, la venta no se detiene: el comprobante '
          'queda en cola y se emite después.',
  };

  Widget _detail(String label, String value) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    mainAxisSize: MainAxisSize.min,
    children: [
      Text(
        label,
        style: const TextStyle(fontSize: 12, color: AppTokens.mutedForeground),
      ),
      Text(value, style: const TextStyle(fontWeight: FontWeight.w600)),
    ],
  );

  Widget _sequenceRow(EcfSequence seq) {
    final branch = _status.branches
        .where((b) => b.id == seq.branchId)
        .map((b) => b.name)
        .firstOrNull;
    // Lo que importa de una secuencia es cuánto le queda: quedarse sin
    // números un sábado en la tarde para la caja.
    final low = seq.remaining <= 50;
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        children: [
          SizedBox(
            width: 52,
            child: Text(
              seq.ncfType,
              style: const TextStyle(fontWeight: FontWeight.w800),
            ),
          ),
          Expanded(
            child: Text(
              [
                if (branch != null && _status.branches.length > 1) branch,
                'quedan ${seq.remaining}',
                if (seq.expirationDate != null) 'vence ${seq.expirationDate}',
              ].join('  ·  '),
              style: TextStyle(
                fontSize: 12,
                color: low ? AppTokens.destructive : AppTokens.mutedForeground,
                fontWeight: low ? FontWeight.w700 : FontWeight.normal,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _openRequest() async {
    final sent = await EcfRequestDialog.show(context, _status);
    if (sent == true && mounted) {
      ref.invalidate(ecfRequestStatusProvider);
      ref.invalidate(companyEcfSettingsProvider);
    }
  }

  Future<void> _openSequence() async {
    final saved = await EcfSequenceDialog.show(context, _status.branches);
    if (saved == true && mounted) ref.invalidate(ecfRequestStatusProvider);
  }

  Future<void> _setEnabled(bool enabled) async {
    setState(() => _busy = true);
    try {
      await ref.read(ecfRequestRepositoryProvider).setEnabled(enabled);
      if (!mounted) return;
      ref.invalidate(ecfRequestStatusProvider);
      ref.invalidate(companyEcfSettingsProvider);
      AppSnackBar.success(
        context,
        enabled
            ? 'Facturación electrónica encendida.'
            : 'Facturación electrónica apagada. Vuelves a comprobantes en papel.',
      );
    } on EcfRequestException catch (e) {
      if (mounted) AppSnackBar.error(context, e.message);
    } catch (e) {
      if (mounted) AppSnackBar.error(context, 'No se pudo cambiar', e);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }
}

class _StageChip extends StatelessWidget {
  const _StageChip({required this.stage});

  final EcfRequestStage stage;

  @override
  Widget build(BuildContext context) {
    final (label, icon) = switch (stage) {
      EcfRequestStage.none => ('NCF físico', Icons.receipt_long_outlined),
      EcfRequestStage.company => ('En revisión', Icons.hourglass_empty),
      EcfRequestStage.certification => ('En trámite DGII', Icons.gavel_outlined),
      EcfRequestStage.sequences => ('Falta secuencia', Icons.playlist_add),
      EcfRequestStage.activation => ('Listo para encender', Icons.check_circle_outline),
      EcfRequestStage.active => ('e-CF activo', Icons.bolt),
    };
    return Chip(
      avatar: Icon(icon, size: 16),
      label: Text(label),
      visualDensity: VisualDensity.compact,
    );
  }
}

class _Waiting extends StatelessWidget {
  const _Waiting(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        const Icon(
          Icons.schedule,
          size: 16,
          color: AppTokens.mutedForeground,
        ),
        const SizedBox(width: 6),
        ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: Text(
            text,
            style: const TextStyle(color: AppTokens.mutedForeground),
          ),
        ),
      ],
    );
  }
}
