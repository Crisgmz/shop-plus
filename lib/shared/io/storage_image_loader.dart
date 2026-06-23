import 'package:flutter/foundation.dart' show debugPrint;
import 'package:supabase_flutter/supabase_flutter.dart';

/// Descarga los bytes de una imagen alojada en **Supabase Storage** a partir de
/// su URL pública. Web-safe (usa el SDK de Storage, no `dart:io`).
///
/// Devuelve `null` si el URL está vacío, no corresponde a Storage o la descarga
/// falla. Para logos subidos desde la app (caso normal) esto es suficiente; las
/// URLs externas arbitrarias no se soportan aquí a propósito (evita `dart:io`,
/// que rompe el build web).
Future<List<int>?> downloadStorageImageBytes(
  SupabaseClient client,
  String? url,
) async {
  if (url == null || url.trim().isEmpty) return null;
  final uri = Uri.tryParse(url.trim());
  if (uri == null) return null;

  final ref = _parseSupabaseStoragePath(uri);
  if (ref == null) return null;

  try {
    return await client.storage.from(ref.bucket).download(ref.path);
  } catch (error) {
    debugPrint('No se pudo bajar imagen de Supabase Storage: $error');
    return null;
  }
}

/// Extrae `(bucket, path)` de un URL público de Supabase Storage.
/// Formato esperado: `/storage/v1/object/public/<bucket>/<path...>`.
({String bucket, String path})? _parseSupabaseStoragePath(Uri uri) {
  final segments = uri.pathSegments;
  final idx = segments.indexOf('public');
  if (idx < 0 || idx + 1 >= segments.length) return null;
  if (idx < 3) return null;
  if (segments[idx - 3] != 'storage' ||
      segments[idx - 2] != 'v1' ||
      segments[idx - 1] != 'object') {
    return null;
  }
  final bucket = segments[idx + 1];
  if (bucket.isEmpty || idx + 2 > segments.length) return null;
  final path = segments.sublist(idx + 2).join('/');
  if (path.isEmpty) return null;
  return (bucket: bucket, path: path);
}
