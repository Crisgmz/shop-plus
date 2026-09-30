/// Tipos de anulación de comprobantes de la DGII (formato 608).
const dgiiVoidReasons = <(String, String)>[
  ('01', 'Deterioro de factura pre-impresa'),
  ('02', 'Errores de impresión (factura pre-impresa)'),
  ('03', 'Impresión defectuosa'),
  ('04', 'Corrección de la información'),
  ('05', 'Cambio de productos'),
  ('06', 'Devolución de productos'),
  ('07', 'Omisión de productos'),
  ('08', 'Errores en secuencia de NCF'),
  ('09', 'Por cese de operaciones'),
  ('10', 'Pérdida o hurto de talonarios'),
];

/// "04 · Corrección de la información", o el código si no se conoce.
String dgiiVoidReasonLabel(String? code) {
  for (final (c, label) in dgiiVoidReasons) {
    if (c == code) return '$c · $label';
  }
  return code ?? '';
}
