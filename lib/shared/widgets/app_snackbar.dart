import 'package:flutter/material.dart';

import '../errors/friendly_error.dart';

export '../errors/friendly_error.dart' show friendlyErrorMessage;

/// Helpers para SnackBars consistentes en toda la app.
///
/// Antes: cada feature mostraba `SnackBar(content: Text('Error: $e'))` con
/// `e` formateado como `PostgrestException(message: ..., code: ..., hint:
/// null)`. Quedaba feo y filtraba detalles internos.
///
/// Ahora: `AppSnackBar.error(...)` traduce el error con
/// [friendlyErrorMessage] y aplica estilos (color por severidad, ícono,
/// esquinas redondeadas, flotante).
class AppSnackBar {
  AppSnackBar._();

  /// Mensaje neutro (gris oscuro).
  static void info(BuildContext context, String message) {
    _show(
      context,
      message: message,
      backgroundColor: const Color(0xFF1E293B),
      icon: Icons.info_outline_rounded,
    );
  }

  /// Operación exitosa (verde).
  static void success(BuildContext context, String message) {
    _show(
      context,
      message: message,
      backgroundColor: const Color(0xFF16A34A),
      icon: Icons.check_circle_outline_rounded,
    );
  }

  /// Operación fallida (rojo). Acepta cualquier `Object?` y lo traduce a un
  /// mensaje para el usuario (sin links, códigos ni texto técnico).
  static void error(BuildContext context, String title, [Object? error]) {
    final detail = friendlyErrorMessage(error);
    final message = detail.isEmpty ? title : '$title\n$detail';
    _show(
      context,
      message: message,
      backgroundColor: const Color(0xFFDC2626),
      icon: Icons.error_outline_rounded,
    );
  }

  static void _show(
    BuildContext context, {
    required String message,
    required Color backgroundColor,
    required IconData icon,
  }) {
    final messenger = ScaffoldMessenger.maybeOf(context);
    if (messenger == null) return;
    messenger.hideCurrentSnackBar();
    messenger.showSnackBar(
      SnackBar(
        behavior: SnackBarBehavior.floating,
        backgroundColor: backgroundColor,
        margin: const EdgeInsets.all(16),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        content: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: Colors.white, size: 20),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                message,
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
