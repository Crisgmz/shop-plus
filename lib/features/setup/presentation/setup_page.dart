import 'package:flutter/foundation.dart' show kDebugMode;
import 'package:flutter/material.dart';

import '../../../core/config/env.dart';

class SetupPage extends StatelessWidget {
  const SetupPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: DecoratedBox(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0xFF0D5BD7), Color(0xFF084AA8)],
          ),
        ),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 680),
            child: Card(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Al usuario no se le muestran variables ni direcciones
                    // del servidor: eso es para quien compila la app.
                    if (!kDebugMode) ...[
                      Text(
                        'La aplicación no está disponible',
                        style: Theme.of(context).textTheme.headlineSmall
                            ?.copyWith(fontWeight: FontWeight.w700),
                      ),
                      const SizedBox(height: 12),
                      const Text(
                        'Esta instalación no está configurada correctamente. '
                        'Contacta a soporte.',
                      ),
                    ] else ...[
                      Text(
                        'Configura Supabase',
                        style: Theme.of(context).textTheme.headlineSmall
                            ?.copyWith(fontWeight: FontWeight.w700),
                      ),
                      const SizedBox(height: 12),
                      const Text(
                        'Faltan variables de entorno para iniciar la app. Ejecuta con --dart-define.',
                      ),
                      const SizedBox(height: 16),
                      SelectableText(
                        'flutter run --dart-define=SUPABASE_URL=TU_URL --dart-define=SUPABASE_PUBLISHABLE_KEY=TU_PUBLISHABLE_KEY',
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          fontFamily: 'monospace',
                        ),
                      ),
                      const SizedBox(height: 16),
                      Text(
                        'SUPABASE_URL: ${Env.supabaseUrl.isEmpty ? 'No definida' : 'Definida'}',
                      ),
                      Text(
                        'SUPABASE_KEY (anon/publishable): ${Env.supabaseAnonKey.isEmpty ? 'No definida' : 'Definida'}',
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
