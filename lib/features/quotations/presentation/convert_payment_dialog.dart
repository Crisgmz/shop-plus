import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/theme/tokens.dart';
import '../../../shared/formatters/formatters.dart';

/// Cómo se cobra la venta que sale de una cotización: al contado con un
/// método de pago, o a crédito con un plazo en días.
class QuoteConversionChoice {
  const QuoteConversionChoice.cash(this.paymentMethod)
      : asCredit = false,
        creditDueDays = null;

  const QuoteConversionChoice.credit(int days)
      : asCredit = true,
        creditDueDays = days,
        paymentMethod = 'cash';

  /// Método del pago. En crédito no se usa: no entra dinero.
  final String paymentMethod;
  final bool asCredit;
  final int? creditDueDays;
}

/// Días de plazo escritos por el cajero, acotados igual que el servidor
/// (1..365). Vacío o inválido ⇒ el default de la empresa.
int clampCreditDays(String raw, int fallback) {
  final parsed = int.tryParse(raw.trim());
  return (parsed ?? fallback).clamp(1, 365);
}

/// Fecha de vencimiento. Se parte de la fecha UTC porque así la calcula
/// `convert_quotation_to_sale`; con la hora local, una venta hecha de noche
/// en RD mostraría un día menos que el que queda guardado.
DateTime creditDueDate(DateTime fromUtc, int days) =>
    DateTime(fromUtc.year, fromUtc.month, fromUtc.day + days);

/// Mensaje de confirmación después de convertir.
String quoteConversionMessage(
  String saleNumber,
  QuoteConversionChoice choice, {
  DateTime? nowUtc,
}) {
  if (!choice.asCredit) return 'Cotización convertida a venta $saleNumber.';
  final due = creditDueDate(
    nowUtc ?? DateTime.now().toUtc(),
    choice.creditDueDays ?? 30,
  );
  return 'Cotización convertida en venta a crédito $saleNumber. '
      'Vence el ${formatDate(due)}.';
}

/// Pregunta cómo se cobra la venta. Devuelve `null` si se cancela.
Future<QuoteConversionChoice?> showConvertPaymentDialog(
  BuildContext context, {
  required String quoteCode,
  required double total,
  required bool hasClient,
  bool creditAllowed = true,
  int defaultCreditDays = 30,
}) {
  return showDialog<QuoteConversionChoice>(
    context: context,
    builder: (_) => _ConvertPaymentDialog(
      quoteCode: quoteCode,
      total: total,
      hasClient: hasClient,
      creditAllowed: creditAllowed,
      defaultCreditDays: defaultCreditDays,
    ),
  );
}

class _ConvertPaymentDialog extends StatefulWidget {
  const _ConvertPaymentDialog({
    required this.quoteCode,
    required this.total,
    required this.hasClient,
    required this.creditAllowed,
    required this.defaultCreditDays,
  });

  final String quoteCode;
  final double total;
  final bool hasClient;
  final bool creditAllowed;
  final int defaultCreditDays;

  @override
  State<_ConvertPaymentDialog> createState() => _ConvertPaymentDialogState();
}

class _ConvertPaymentDialogState extends State<_ConvertPaymentDialog> {
  bool _asCredit = false;
  String _method = 'cash';
  late final TextEditingController _days =
      TextEditingController(text: widget.defaultCreditDays.toString());

  static const _methods = <({String value, String label})>[
    (value: 'cash', label: 'Efectivo'),
    (value: 'card', label: 'Tarjeta'),
    (value: 'transfer', label: 'Transferencia'),
    (value: 'mobile', label: 'Pago móvil'),
  ];

  @override
  void dispose() {
    _days.dispose();
    super.dispose();
  }

  int get _parsedDays => clampCreditDays(_days.text, widget.defaultCreditDays);

  /// A crédito sin cliente del catálogo no se puede: la deuda necesita una
  /// cuenta. Se deja elegir para poder explicar el motivo, pero no confirmar.
  bool get _canConfirm => !_asCredit || widget.hasClient;

  @override
  Widget build(BuildContext context) {
    final due = creditDueDate(DateTime.now().toUtc(), _parsedDays);

    return AlertDialog(
      title: const Text('Convertir a venta'),
      content: SizedBox(
        width: 380,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'La cotización ${widget.quoteCode} se convertirá en una venta '
              'por ${money(widget.total)} con sus líneas y montos actuales.',
            ),
            const SizedBox(height: AppTokens.s16),
            SegmentedButton<bool>(
              segments: [
                const ButtonSegment(
                  value: false,
                  label: Text('Contado'),
                  icon: Icon(Icons.payments_outlined),
                ),
                ButtonSegment(
                  value: true,
                  label: const Text('Crédito'),
                  icon: const Icon(Icons.schedule_outlined),
                  enabled: widget.creditAllowed,
                ),
              ],
              selected: {_asCredit},
              onSelectionChanged: (s) => setState(() => _asCredit = s.first),
            ),
            if (!widget.creditAllowed) ...[
              const SizedBox(height: AppTokens.s8),
              Text(
                'Las ventas a crédito están deshabilitadas en Configuración.',
                style: TextStyle(
                  fontSize: 12,
                  color: AppTokens.mutedForeground,
                ),
              ),
            ],
            const SizedBox(height: AppTokens.s16),
            if (!_asCredit)
              DropdownButtonFormField<String>(
                initialValue: _method,
                decoration: const InputDecoration(
                  labelText: 'Método de pago',
                  border: OutlineInputBorder(),
                ),
                items: [
                  for (final m in _methods)
                    DropdownMenuItem(value: m.value, child: Text(m.label)),
                ],
                onChanged: (value) {
                  if (value != null) setState(() => _method = value);
                },
              )
            else if (!widget.hasClient)
              Container(
                padding: const EdgeInsets.all(AppTokens.s12),
                decoration: BoxDecoration(
                  color: AppTokens.warning.withValues(alpha: 0.10),
                  borderRadius: BorderRadius.circular(AppTokens.radiusM),
                  border: Border.all(
                    color: AppTokens.warning.withValues(alpha: 0.35),
                  ),
                ),
                child: const Text(
                  'Para vender a crédito la cotización necesita un cliente '
                  'registrado. Un nombre escrito a mano no tiene cuenta donde '
                  'cargar la deuda: elige el cliente del catálogo y guarda la '
                  'cotización.',
                  style: TextStyle(fontSize: 12, height: 1.35),
                ),
              )
            else ...[
              TextField(
                controller: _days,
                keyboardType: TextInputType.number,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                decoration: const InputDecoration(
                  labelText: 'Días de plazo',
                  border: OutlineInputBorder(),
                ),
                onChanged: (_) => setState(() {}),
              ),
              const SizedBox(height: AppTokens.s8),
              Text(
                'Vence el ${formatDate(due)}. La venta queda pendiente en '
                'Cuentas por cobrar y suma al saldo del cliente.',
                style: TextStyle(
                  fontSize: 12,
                  color: AppTokens.mutedForeground,
                ),
              ),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancelar'),
        ),
        FilledButton(
          onPressed: _canConfirm
              ? () => Navigator.pop(
                    context,
                    _asCredit
                        ? QuoteConversionChoice.credit(_parsedDays)
                        : QuoteConversionChoice.cash(_method),
                  )
              : null,
          child: Text(_asCredit ? 'Convertir a crédito' : 'Convertir y cobrar'),
        ),
      ],
    );
  }
}
