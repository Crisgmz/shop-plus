import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_app/shared/errors/friendly_error.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

void main() {
  // El traductor imprime el error original en debug; aquí sobra.
  final originalDebugPrint = debugPrint;
  setUp(() => debugPrint = (String? message, {int? wrapWidth}) {});
  tearDown(() => debugPrint = originalDebugPrint);

  group('inicio de sesión', () {
    test('contraseña incorrecta', () {
      expect(
        friendlyErrorMessage(
          AuthApiException(
            'Invalid login credentials',
            statusCode: '400',
            code: 'invalid_credentials',
          ),
        ),
        'Correo o contraseña incorrectos.',
      );
    });

    test('servidor viejo sin código: se reconoce por el texto', () {
      expect(
        friendlyErrorMessage(AuthException('Invalid login credentials')),
        'Correo o contraseña incorrectos.',
      );
    });

    test('correo sin confirmar y cuenta repetida', () {
      expect(
        friendlyErrorMessage(
          AuthApiException('Email not confirmed',
              code: 'email_not_confirmed'),
        ),
        contains('correo aún no está confirmado'),
      );
      expect(
        friendlyErrorMessage(
          AuthApiException('User already registered',
              code: 'user_already_exists'),
        ),
        'Ya existe una cuenta con ese correo.',
      );
    });

    test('sin internet al iniciar sesión', () {
      expect(
        friendlyErrorMessage(
          AuthRetryableFetchException(
            message: 'ClientException: Failed to fetch, '
                'uri=https://supabase.busiposweb.com/auth/v1/token',
          ),
        ),
        offlineErrorMessage,
      );
    });
  });

  group('base de datos', () {
    test('duplicado: dice qué dato se repite', () {
      expect(
        friendlyErrorMessage(
          const PostgrestException(
            message: 'duplicate key value violates unique constraint '
                '"products_branch_sku_key"',
            code: '23505',
          ),
        ),
        'Ya existe un producto con ese SKU.',
      );
    });

    test('RLS de Postgres → sin permiso', () {
      expect(
        friendlyErrorMessage(
          const PostgrestException(
            message: 'new row violates row-level security policy for table '
                '"sales"',
            code: '42501',
          ),
        ),
        noPermissionMessage,
      );
    });

    test('mensaje propio de un RPC se muestra', () {
      expect(
        friendlyErrorMessage(
          const PostgrestException(
            message: 'Solo admin o supervisor pueden editar ventas.',
            code: '42501',
          ),
        ),
        'Solo admin o supervisor pueden editar ventas.',
      );
      expect(
        friendlyErrorMessage(
          const PostgrestException(
            message: 'Stock insuficiente para "VASOS PET 16 OZ": disponible 3 '
                'requerido 5',
            code: 'P0001',
          ),
        ),
        'Stock insuficiente para "VASOS PET 16 OZ": disponible 3 '
            'requerido 5.',
      );
    });

    test('un nombre de producto en inglés no esconde el mensaje', () {
      expect(
        friendlyErrorMessage(
          const PostgrestException(
            message: 'Stock insuficiente para "Cable USB to Lightning": '
                'disponible 1 requerido 3',
            code: '22023',
          ),
        ),
        'Stock insuficiente para "Cable USB to Lightning": disponible 1 '
            'requerido 3.',
      );
      // Pero un mensaje de Postgres sigue oculto aunque cite nombres.
      expect(
        friendlyErrorMessage(
          const PostgrestException(
            message: 'relation "public.returns_x" does not exist',
            code: 'XX000',
          ),
        ),
        genericErrorMessage,
      );
    });

    test('los ids internos no se muestran', () {
      expect(
        friendlyErrorMessage(
          const PostgrestException(
            message:
                'Producto no encontrado: 1b4e28ba-2fa1-11d2-883f-0016d3cca427',
            code: '23503',
          ),
        ),
        'Producto no encontrado.',
      );
    });

    test('borrar algo en uso', () {
      expect(
        friendlyErrorMessage(
          const PostgrestException(
            message: 'update or delete on table "clients" violates foreign '
                'key constraint "sales_client_id_fkey" on table "sales"',
            code: '23503',
          ),
        ),
        startsWith('No se puede eliminar porque está en uso'),
      );
    });

    test('función que la base no tiene y sesión vencida', () {
      expect(
        friendlyErrorMessage(
          const PostgrestException(
            message: 'Could not find the function public.x in the schema '
                'cache',
            code: 'PGRST202',
          ),
        ),
        needsUpdateMessage,
      );
      expect(
        friendlyErrorMessage(
          const PostgrestException(message: 'JWT expired', code: 'PGRST301'),
        ),
        sessionExpiredMessage,
      );
    });

    test('cualquier otro texto en inglés → genérico', () {
      expect(
        friendlyErrorMessage(
          const PostgrestException(
            message: 'value too long for type character varying(20)',
            code: 'XX000',
          ),
        ),
        genericErrorMessage,
      );
    });
  });

  group('red y otros', () {
    test('sin conexión, sin mostrar la dirección del servidor', () {
      expect(
        friendlyErrorMessage(
          const SocketException(
            'Failed host lookup: supabase.busiposweb.com',
          ),
        ),
        offlineErrorMessage,
      );
      expect(
        friendlyErrorMessage(
          Exception('ClientException: Failed to fetch, '
              'uri=https://supabase.busiposweb.com/rest/v1/sales'),
        ),
        offlineErrorMessage,
      );
    });

    test('tiempo agotado', () {
      expect(
        friendlyErrorMessage(TimeoutException('x')),
        timeoutErrorMessage,
      );
    });

    test('mensajes propios de la app, sin "Exception:" ni links', () {
      expect(
        friendlyErrorMessage(
          Exception('El RNC debe tener 9 dígitos (empresa) o 11 (cédula).'),
        ),
        'El RNC debe tener 9 dígitos (empresa) o 11 (cédula).',
      );
      expect(
        friendlyErrorMessage(
          Exception('No se pudo subir: '
              'https://supabase.busiposweb.com/storage/v1/object/logo.png'),
        ),
        'No se pudo subir.',
      );
    });

    test('fallos de programación → genérico', () {
      expect(friendlyErrorMessage(StateError('No element')),
          genericErrorMessage);
      expect(friendlyErrorMessage(ArgumentError('x')), genericErrorMessage);
    });

    test('edge function: usuario repetido y error interno', () {
      expect(
        friendlyErrorMessage(
          const FunctionException(
            status: 400,
            details: {
              'error': 'A user with this email address has already been '
                  'registered',
            },
          ),
        ),
        'Ya existe una cuenta con ese correo.',
      );
      expect(
        friendlyErrorMessage(
          const FunctionException(
            status: 500,
            details: {'error': 'relation "profiles" does not exist'},
          ),
        ),
        genericErrorMessage,
      );
    });

    test('archivo muy grande', () {
      expect(
        friendlyErrorMessage(
          const StorageException(
            'The object exceeded the maximum allowed size',
            statusCode: '413',
          ),
        ),
        'El archivo es demasiado grande.',
      );
    });

    test('null → vacío', () {
      expect(friendlyErrorMessage(null), '');
    });
  });
}
