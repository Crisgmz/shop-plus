import 'package:flutter/material.dart';

import '../../../core/theme/tokens.dart';

/// Selector de IMEIs al vender un producto serializado. Devuelve la lista de
/// IMEIs marcados, o null si se cancela.
class ImeiPickerDialog extends StatefulWidget {
  const ImeiPickerDialog({
    super.key,
    required this.productName,
    required this.imeis,
  });

  final String productName;
  final List<String> imeis;

  @override
  State<ImeiPickerDialog> createState() => _ImeiPickerDialogState();
}

class _ImeiPickerDialogState extends State<ImeiPickerDialog> {
  final Set<String> _selected = {};

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text('IMEI · ${widget.productName}'),
      content: SizedBox(
        width: 380,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Selecciona los equipos que salen a la venta:',
              style: TextStyle(fontSize: 13, color: AppTokens.mutedForeground),
            ),
            const SizedBox(height: 8),
            Flexible(
              child: SingleChildScrollView(
                child: Column(
                  children: [
                    for (final imei in widget.imeis)
                      CheckboxListTile(
                        dense: true,
                        contentPadding: EdgeInsets.zero,
                        controlAffinity: ListTileControlAffinity.leading,
                        value: _selected.contains(imei),
                        title: Text(
                          'IMEI  $imei',
                          style: const TextStyle(
                            fontFamily: 'monospace',
                            fontSize: 14,
                          ),
                        ),
                        onChanged: (v) => setState(() {
                          if (v == true) {
                            _selected.add(imei);
                          } else {
                            _selected.remove(imei);
                          }
                        }),
                      ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancelar'),
        ),
        FilledButton.icon(
          onPressed: _selected.isEmpty
              ? null
              : () => Navigator.of(context).pop(_selected.toList()),
          icon: const Icon(Icons.check_circle_outline, size: 18),
          label: Text('Confirmar (${_selected.length})'),
        ),
      ],
    );
  }
}
