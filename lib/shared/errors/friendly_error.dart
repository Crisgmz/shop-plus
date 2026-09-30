/// Traduce cualquier error a un mensaje para el usuario.
///
/// La pantalla NUNCA debe mostrar un error crudo: `PostgrestException(message:
/// duplicate key value violates unique constraint "products_sku_key", code:
/// 23505…)`, `ClientException: Failed to fetch, uri=https://…/rest/v1/…` o
/// `AuthApiException(message: Invalid login credentials…)` filtran links del
/// servidor, nombres de tablas y códigos que el cajero no entiende.
///
/// Reglas:
/// - Errores conocidos (credenciales, sin internet, duplicado, sin permiso,
///   sesión vencida…) → un mensaje claro en español.
/// - Mensajes propios de la app (`throw Exception('Stock insuficiente…')` o
///   `raise exception` de los RPC, escritos en español) → se muestran, sin
///   el prefijo "Exception: ", sin links y sin ids internos.
/// - Todo lo demás (inglés técnico, fallos de programación) → un mensaje
///   genérico. En modo debug el error original se imprime en consola.
library;

import 'dart:async' show TimeoutException;

import 'package:flutter/foundation.dart' show debugPrint, kDebugMode;
import 'package:supabase_flutter/supabase_flutter.dart'
    show
        AuthException,
        AuthInvalidJwtException,
        AuthRetryableFetchException,
        AuthSessionMissingException,
        AuthWeakPasswordException,
        FunctionException,
        PostgrestException,
        StorageException;

const genericErrorMessage = 'Ocurrió un error inesperado. Intenta de nuevo.';
const offlineErrorMessage =
    'No hay conexión con el servidor. Revisa tu internet e intenta de nuevo.';
const sessionExpiredMessage = 'Tu sesión expiró. Vuelve a iniciar sesión.';
const noPermissionMessage = 'No tienes permiso para realizar esta acción.';
const needsUpdateMessage =
    'Esta opción necesita una actualización del sistema. Contacta a soporte.';
const timeoutErrorMessage =
    'El servidor tardó demasiado en responder. Intenta de nuevo.';

const _wrongCredentials = 'Correo o contraseña incorrectos.';
const _accountExists = 'Ya existe una cuenta con ese correo.';
const _weakPassword =
    'La contraseña es muy débil. Usa una más larga, con letras y números.';
const _tooManyAttempts =
    'Demasiados intentos. Espera unos minutos e intenta de nuevo.';

/// Mensaje para el usuario a partir de cualquier error. `''` si es null.
String friendlyErrorMessage(Object? error) {
  if (error == null) return '';
  if (kDebugMode) debugPrint('[error] $error');

  return switch (error) {
    AuthException() => _auth(error),
    PostgrestException() => _postgrest(error),
    StorageException() => _storage(error),
    FunctionException() => _function(error),
    TimeoutException() => timeoutErrorMessage,
    FormatException() =>
      'Un dato o archivo tiene un formato que no se reconoce.',
    // `throw Exception('…')` de la app, o un texto lanzado tal cual.
    Exception() || String() => _clean(error.toString()),
    // Error (TypeError, StateError, RangeError…) es un fallo de programación:
    // su texto no le sirve al usuario.
    _ =>
      _looksOffline(error.toString())
          ? offlineErrorMessage
          : genericErrorMessage,
  };
}

// ── Autenticación ───────────────────────────────────────────────────────────

String _auth(AuthException error) {
  if (error is AuthRetryableFetchException) return offlineErrorMessage;
  if (error is AuthSessionMissingException ||
      error is AuthInvalidJwtException) {
    return sessionExpiredMessage;
  }
  if (error is AuthWeakPasswordException) return _weakPassword;

  switch (error.code) {
    case 'invalid_credentials':
      return _wrongCredentials;
    case 'email_not_confirmed':
      return 'Tu correo aún no está confirmado. Revisa tu bandeja de entrada.';
    case 'user_already_exists':
    case 'email_exists':
      return _accountExists;
    case 'weak_password':
      return _weakPassword;
    case 'same_password':
      return 'La nueva contraseña debe ser distinta de la actual.';
    case 'email_address_invalid':
      return 'El correo no es válido.';
    case 'user_not_found':
      return 'No existe una cuenta con ese correo.';
    case 'user_banned':
      return 'Tu usuario está desactivado. Contacta al administrador.';
    case 'signup_disabled':
    case 'email_provider_disabled':
      return 'El registro de cuentas está desactivado. Contacta al '
          'administrador.';
    case 'over_request_rate_limit':
    case 'over_email_send_rate_limit':
    case 'over_sms_send_rate_limit':
      return _tooManyAttempts;
    case 'session_not_found':
    case 'session_expired':
    case 'refresh_token_not_found':
    case 'refresh_token_already_used':
    case 'bad_jwt':
      return sessionExpiredMessage;
  }
  if (error.statusCode == '429') return _tooManyAttempts;
  // Servidores viejos no mandan `code`: se reconoce por el texto.
  return _knownPhrase(error.message) ??
      (_looksOffline(error.message)
          ? offlineErrorMessage
          : 'No se pudo validar tu cuenta. Intenta de nuevo.');
}

// ── Base de datos (PostgREST / Postgres) ────────────────────────────────────

String _postgrest(PostgrestException error) {
  final code = error.code ?? '';
  final raw = '${error.message} ${error.details ?? ''}'.toLowerCase();

  switch (code) {
    // JWT vencido o inválido.
    case 'PGRST301':
    case 'PGRST302':
    case 'PGRST303':
      return sessionExpiredMessage;
    case 'PGRST116':
      return 'No se encontró el registro. Puede que ya se haya eliminado.';
    // Función, tabla o columna que la base todavía no tiene: falta aplicar
    // una migración.
    case 'PGRST200':
    case 'PGRST202':
    case 'PGRST204':
    case 'PGRST205':
    case '42703':
    case '42P01':
    case '42883':
      return needsUpdateMessage;
    case '23505':
      return _duplicate(raw);
    case '23502':
      return 'Falta completar un dato obligatorio.';
    case '23514':
      return 'Uno de los datos no es válido. Revísalo e intenta de nuevo.';
    case '22P02':
    case '22007':
    case '22008':
      return 'Uno de los datos tiene un formato inválido.';
    case '22001':
      return 'Uno de los textos es demasiado largo.';
    case '22003':
      return 'Uno de los montos o cantidades está fuera de rango.';
    case '57014':
      return timeoutErrorMessage;
    case '40001':
    case '40P01':
    case '55P03':
      return 'Otro usuario estaba modificando lo mismo. Intenta de nuevo.';
  }

  // Los RPC de la app lanzan sus propios mensajes en español con estos
  // códigos ("Solo admin o supervisor pueden editar ventas."); esos sí se
  // muestran. Los de Postgres vienen en inglés y se traducen.
  if (code == '42501' ||
      raw.contains('row-level security') ||
      raw.contains('permission denied')) {
    return _ownMessage(error.message) ?? noPermissionMessage;
  }
  if (code == '23503') {
    return _ownMessage(error.message) ??
        (raw.contains('update or delete')
            ? 'No se puede eliminar porque está en uso en otros registros '
                  '(ventas, compras, etc.).'
            : 'Uno de los datos seleccionados ya no existe. Recarga la '
                  'pantalla e intenta de nuevo.');
  }
  if (raw.contains('jwt')) return sessionExpiredMessage;
  return _clean(error.message);
}

/// "Ya existe un producto con ese SKU." según el índice único que saltó.
String _duplicate(String raw) {
  if (raw.contains('barcode')) {
    return 'Ya existe un producto con ese código de barras.';
  }
  if (raw.contains('sku')) return 'Ya existe un producto con ese SKU.';
  if (raw.contains('rnc') || raw.contains('document_number')) {
    return 'Ya existe un registro con ese RNC o cédula.';
  }
  if (raw.contains('ncf')) return 'Ese NCF ya fue utilizado.';
  if (raw.contains('email')) return 'Ya existe un registro con ese correo.';
  if (raw.contains('name')) return 'Ya existe un registro con ese nombre.';
  return 'Ya existe un registro con esos datos.';
}

// ── Archivos (Storage) ──────────────────────────────────────────────────────

String _storage(StorageException error) {
  final raw = '${error.message} ${error.error ?? ''}'.toLowerCase();
  final status = error.statusCode ?? '';
  if (status == '413' || raw.contains('too large') || raw.contains('size')) {
    return 'El archivo es demasiado grande.';
  }
  if (status == '415' || raw.contains('mime')) {
    return 'Ese tipo de archivo no está permitido.';
  }
  if (status == '401' || status == '403' || raw.contains('jwt')) {
    return raw.contains('jwt') ? sessionExpiredMessage : noPermissionMessage;
  }
  if (status == '404' || raw.contains('not found')) {
    return 'No se encontró el archivo.';
  }
  if (status == '409' || raw.contains('already exists')) {
    return 'Ya existe un archivo con ese nombre.';
  }
  if (_looksOffline(raw)) return offlineErrorMessage;
  return 'No se pudo procesar el archivo. Intenta de nuevo.';
}

// ── Funciones del servidor (Edge Functions) ─────────────────────────────────

String _function(FunctionException error) {
  // La función puede responder `{ "error": "…" }` o `{ "message": "…" }`.
  final details = error.details;
  String? text;
  if (details is Map) {
    final value = details['error'] ?? details['message'] ?? details['msg'];
    if (value is String) text = value;
  } else if (details is String) {
    text = details;
  }
  if (text != null && text.trim().isNotEmpty) {
    final known = _knownPhrase(text) ?? _ownMessage(text);
    if (known != null) return known;
  }
  switch (error.status) {
    case 401:
      return sessionExpiredMessage;
    case 403:
      return noPermissionMessage;
    case 404:
      return needsUpdateMessage;
    case 409:
      return 'Ya existe un registro con esos datos.';
    case 429:
      return _tooManyAttempts;
  }
  return genericErrorMessage;
}

// ── Limpieza de textos ──────────────────────────────────────────────────────

/// Mensaje propio (español, sin nada técnico) o, si no, uno genérico.
String _clean(String raw) {
  var text = raw.trim();
  // "Exception: Exception: …" cuando se re-lanza envuelto.
  while (text.startsWith('Exception: ')) {
    text = text.substring('Exception: '.length).trim();
  }
  return _knownPhrase(text) ??
      (_looksOffline(text) ? offlineErrorMessage : null) ??
      _ownMessage(text) ??
      genericErrorMessage;
}

/// El texto sin links ni ids internos, si es un mensaje escrito para el
/// usuario. `null` si parece técnico.
String? _ownMessage(String raw) {
  var text = raw
      .replaceAll(RegExp(r'\buri=\S+'), '')
      .replaceAll(RegExp(r'https?://\S+'), '')
      .replaceAll(
        RegExp(
          r'\b[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}\b',
          caseSensitive: false,
        ),
        '',
      )
      .replaceAll(RegExp(r'\s+'), ' ')
      // "Producto no encontrado: ." → "Producto no encontrado."
      .replaceAll(RegExp(r'\s*[:,]\s*(?=[.)]|$)'), '')
      .replaceAllMapped(RegExp(r'\s+([.,)])'), (m) => m[1]!)
      .replaceAll(RegExp(r'\(\s*\)'), '')
      .trim();
  if (text.isEmpty || _looksTechnical(text)) return null;
  if (!RegExp(r'[.!?]$').hasMatch(text)) text = '$text.';
  return text;
}

/// Frases conocidas del servidor (en inglés) con su traducción.
String? _knownPhrase(String raw) {
  final text = raw.toLowerCase();
  if (text.contains('invalid login credentials') ||
      text.contains('invalid_credentials') ||
      text.contains('invalid email or password')) {
    return _wrongCredentials;
  }
  if (text.contains('email not confirmed')) {
    return 'Tu correo aún no está confirmado. Revisa tu bandeja de entrada.';
  }
  if (text.contains('already been registered') ||
      text.contains('already registered') ||
      text.contains('user already exists')) {
    return _accountExists;
  }
  if (text.contains('password should be') ||
      text.contains('password is too weak') ||
      text.contains('weak password')) {
    return _weakPassword;
  }
  if (text.contains('rate limit') || text.contains('too many requests')) {
    return _tooManyAttempts;
  }
  if (text.contains('jwt expired') ||
      text.contains('invalid refresh token') ||
      text.contains('refresh token not found')) {
    return sessionExpiredMessage;
  }
  return null;
}

bool _looksOffline(String raw) {
  final text = raw.toLowerCase();
  const markers = [
    'socketexception',
    'clientexception',
    'handshakeexception',
    'failed host lookup',
    'failed to fetch',
    'xmlhttprequest error',
    'connection refused',
    'connection reset',
    'connection closed',
    'connection failed',
    'connection abort',
    'network is unreachable',
    'no address associated',
    'network error',
  ];
  return markers.any(text.contains);
}

/// Texto que no fue escrito para el usuario: inglés técnico de Postgres o
/// de Dart, volcados de objetos, nombres internos.
bool _looksTechnical(String text) {
  final lower = text.toLowerCase();
  const markers = [
    'exception',
    'instance of',
    'null check',
    'is not a subtype',
    'nosuchmethod',
    'bad state',
    'invalid argument',
    'rangeerror',
    'statuscode',
    'code:',
    'pgrst',
    'violates',
    'constraint',
    'relation "',
    'column "',
    'function ',
    'syntax error',
    'jsonb',
    'uuid',
    'postgres',
    'supabase',
    'sql',
    'stack trace',
    '#0 ',
    'internal server error',
    'bad request',
    'not found',
    'unauthorized',
    'forbidden',
    'unexpected',
    'failed',
    'could not',
    'cannot ',
    'invalid input',
    'undefined',
    'schema',
  ];
  if (markers.any(lower.contains)) return true;
  // Los mensajes propios están en español; Postgres y el servidor responden
  // en inglés. Palabras sueltas que en español no existen lo delatan.
  // ("error" y "has" no: también son palabras en español.)
  const englishWords = [
    'the', 'of', 'is', 'to', 'for', 'with', 'and', 'does', 'was', 'be', //
    'an', 'must', 'already', 'user', 'value', 'not',
  ];
  final words = lower.split(RegExp(r'[^a-záéíóúñü]+'));
  return words.any(englishWords.contains);
}
