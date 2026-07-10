import 'package:flutter/material.dart';

/// Método de pago elegido al convertir una cotización en venta pagada.
/// Devuelve el valor (`cash`, `card`, `transfer`, `mobile`) o `null` si se
/// cancela.
Future<String?> showConvertPaymentDialog(
  BuildContext context, {
  required String quoteCode,
}) {
  return showDialog<String>(
    context: context,
    builder: (_) => _ConvertPaymentDialog(quoteCode: quoteCode),
  );
}

class _ConvertPaymentDialog extends StatefulWidget {
  const _ConvertPaymentDialog({required this.quoteCode});

  final String quoteCode;

  @override
  State<_ConvertPaymentDialog> createState() => _ConvertPaymentDialogState();
}

class _ConvertPaymentDialogState extends State<_ConvertPaymentDialog> {
  String _method = 'cash';

  static const _methods = <({String value, String label})>[
    (value: 'cash', label: 'Efectivo'),
    (value: 'card', label: 'Tarjeta'),
    (value: 'transfer', label: 'Transferencia'),
    (value: 'mobile', label: 'Pago móvil'),
  ];

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Convertir a venta'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'La cotización ${widget.quoteCode} se convertirá en una venta '
            'PAGADA con sus líneas y montos actuales.\n\n'
            'Elige el método de pago:',
          ),
          const SizedBox(height: 16),
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
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancelar'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(context, _method),
          child: const Text('Convertir y cobrar'),
        ),
      ],
    );
  }
}
