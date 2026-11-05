import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/tokens.dart';
import '../../../shared/widgets/app_snackbar.dart';
import '../data/ecf_request_repository.dart';
import 'settings_providers.dart';

/// Captura la autorización e-NCF que la DGII entrega en PDF.
///
/// Pide la sucursal porque este POS consume las secuencias por sucursal,
/// mientras que la DGII autoriza el rango al RNC. Dos sucursales sobre el
/// mismo rango emitirían el mismo e-NCF dos veces: si el negocio tiene
/// varias, hay que repartir el rango entre ellas.
class EcfSequenceDialog extends ConsumerStatefulWidget {
  const EcfSequenceDialog({super.key, required this.branches});

  /// Sucursales de la empresa: la secuencia se asigna a una.
  final List<EcfBranch> branches;

  static Future<bool?> show(BuildContext context, List<EcfBranch> branches) {
    return showDialog<bool>(
      context: context,
      builder: (_) => EcfSequenceDialog(branches: branches),
    );
  }

  @override
  ConsumerState<EcfSequenceDialog> createState() => _EcfSequenceDialogState();
}

class _EcfSequenceDialogState extends ConsumerState<EcfSequenceDialog> {
  final _formKey = GlobalKey<FormState>();
  final _rangeStart = TextEditingController();
  final _rangeEnd = TextEditingController();
  final _authorization = TextEditingController();
  final _lastUsed = TextEditingController();

  String _ncfType = 'E31';
  String? _branchId;
  DateTime? _expiration;
  bool _saving = false;

  /// E31, E44 y E45 exigen la fecha de vencimiento: sin ella la DGII rechaza
  /// con el código 145.
  bool get _needsExpiration => const ['E31', 'E44', 'E45'].contains(_ncfType);

  @override
  void initState() {
    super.initState();
    _branchId = widget.branches.isNotEmpty ? widget.branches.first.id : null;
  }

  @override
  void dispose() {
    _rangeStart.dispose();
    _rangeEnd.dispose();
    _authorization.dispose();
    _lastUsed.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final branches = widget.branches;

    return AlertDialog(
      title: const Text('Cargar secuencia e-NCF'),
      content: SizedBox(
        width: 460,
        child: Form(
          key: _formKey,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Copia el rango tal como viene en la autorización que te dio '
                  'la DGII.',
                  style: TextStyle(color: AppTokens.mutedForeground),
                ),
                const SizedBox(height: AppTokens.s16),
                DropdownButtonFormField<String>(
                  initialValue: _ncfType,
                  decoration: const InputDecoration(
                    labelText: 'Tipo de comprobante',
                  ),
                  // E34 incluida: el servidor la guarda como nota de crédito
                  // (nunca como crédito fiscal, donde competía con la E31) y
                  // solo la usa la nota automática al anular una e-CF.
                  items: ecfTypeLabels.entries
                      .map(
                        (e) => DropdownMenuItem(
                          value: e.key,
                          child: Text('${e.key} — ${e.value}'),
                        ),
                      )
                      .toList(growable: false),
                  onChanged: _saving
                      ? null
                      : (v) => setState(() => _ncfType = v ?? 'E31'),
                ),
                const SizedBox(height: AppTokens.s12),
                if (branches.length > 1) ...[
                  DropdownButtonFormField<String>(
                    initialValue: _branchId,
                    decoration: const InputDecoration(
                      labelText: 'Sucursal que usa esta secuencia',
                      helperText:
                          'Cada sucursal necesita su propio rango: no se '
                          'puede compartir.',
                      helperMaxLines: 2,
                    ),
                    items: branches
                        .map(
                          (b) => DropdownMenuItem(
                            value: b.id,
                            child: Text(b.name),
                          ),
                        )
                        .toList(growable: false),
                    onChanged: _saving
                        ? null
                        : (v) => setState(() => _branchId = v),
                    validator: (v) =>
                        (v ?? '').isEmpty ? 'Elige la sucursal.' : null,
                  ),
                  const SizedBox(height: AppTokens.s12),
                ],
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: _number(
                        _rangeStart,
                        'Desde',
                        'El primer número del rango.',
                      ),
                    ),
                    const SizedBox(width: AppTokens.s12),
                    Expanded(
                      child: _number(
                        _rangeEnd,
                        'Hasta',
                        'El último número del rango.',
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: AppTokens.s12),
                InputDecorator(
                  decoration: InputDecoration(
                    labelText: _needsExpiration
                        ? 'Vence (obligatorio para $_ncfType)'
                        : 'Vence (opcional)',
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          _expiration == null
                              ? 'Sin fecha'
                              : _isoDate(_expiration!),
                          style: TextStyle(
                            color: _expiration == null
                                ? AppTokens.mutedForeground
                                : AppTokens.foreground,
                          ),
                        ),
                      ),
                      TextButton(
                        onPressed: _saving ? null : _pickDate,
                        child: const Text('Elegir'),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: AppTokens.s12),
                TextFormField(
                  controller: _authorization,
                  maxLength: 40,
                  decoration: const InputDecoration(
                    labelText: 'Número de autorización (opcional)',
                    counterText: '',
                  ),
                ),
                const SizedBox(height: AppTokens.s12),
                _number(
                  _lastUsed,
                  'Último número ya usado (opcional)',
                  'Solo si venías emitiendo esta secuencia fuera del sistema.',
                  required: false,
                ),
              ],
            ),
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _saving ? null : () => Navigator.of(context).pop(false),
          child: const Text('Cancelar'),
        ),
        FilledButton(
          onPressed: _saving ? null : _save,
          child: Text(_saving ? 'Guardando...' : 'Guardar'),
        ),
      ],
    );
  }

  Widget _number(
    TextEditingController controller,
    String label,
    String helper, {
    bool required = true,
  }) {
    return TextFormField(
      controller: controller,
      keyboardType: TextInputType.number,
      inputFormatters: [FilteringTextInputFormatter.digitsOnly],
      decoration: InputDecoration(
        labelText: label,
        helperText: helper,
        helperMaxLines: 2,
      ),
      validator: (v) {
        final raw = (v ?? '').trim();
        if (raw.isEmpty) return required ? 'Falta este número.' : null;
        if (int.tryParse(raw) == null) return 'Tiene que ser un número.';
        return null;
      },
    );
  }

  static String _isoDate(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-'
      '${d.month.toString().padLeft(2, '0')}-'
      '${d.day.toString().padLeft(2, '0')}';

  Future<void> _pickDate() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _expiration ?? DateTime(now.year + 1, 12, 31),
      firstDate: now,
      lastDate: DateTime(now.year + 10),
    );
    if (picked != null) setState(() => _expiration = picked);
  }

  Future<void> _save() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    if (_needsExpiration && _expiration == null) {
      AppSnackBar.error(
        context,
        '$_ncfType exige la fecha de vencimiento: sin ella la DGII rechaza '
        'el comprobante.',
      );
      return;
    }
    final branchId = _branchId;
    if (branchId == null) {
      AppSnackBar.error(
        context,
        'No hay sucursal a la que asignar la secuencia.',
      );
      return;
    }

    setState(() => _saving = true);
    try {
      await ref
          .read(ecfRequestRepositoryProvider)
          .saveSequence(
            EcfSequenceSubmission(
              branchId: branchId,
              ncfType: _ncfType,
              rangeStart: int.parse(_rangeStart.text.trim()),
              rangeEnd: int.parse(_rangeEnd.text.trim()),
              expirationDate: _expiration == null
                  ? null
                  : _isoDate(_expiration!),
              authorizationNumber: _authorization.text.trim().isEmpty
                  ? null
                  : _authorization.text.trim(),
              lastUsed: _lastUsed.text.trim().isEmpty
                  ? null
                  : int.parse(_lastUsed.text.trim()),
            ),
          );
      if (!mounted) return;
      Navigator.of(context).pop(true);
      AppSnackBar.success(context, 'Secuencia $_ncfType guardada.');
    } on EcfRequestException catch (e) {
      if (mounted) AppSnackBar.error(context, e.message);
    } catch (e) {
      if (mounted) AppSnackBar.error(context, 'No se pudo guardar', e);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }
}
