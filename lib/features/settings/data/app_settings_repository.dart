// AppSettingsRepository: lectura y escritura del singleton `app_settings`.
//
// Patrón:
//   - fetch(): SELECT * FROM app_settings WHERE id = 1
//   - updateField(column, value): UPDATE one column. Auto-save por campo.
//   - updatePatch(patch): UPDATE varias columnas en una sola RPC.
//   - fetchAuditLog: lee últimas N entradas de `app_settings_audit` (admin).
//
// Errores:
//   - Si no hay sesión, lanza Exception.
//   - Si el RLS rechaza el update (no admin), Supabase lanza PostgrestException
//     que se propaga.

import 'dart:typed_data';

import 'package:supabase_flutter/supabase_flutter.dart';

import 'app_settings.dart';

class AppSettingsRepository {
  AppSettingsRepository(this._client);

  final SupabaseClient _client;

  static const _table = 'app_settings';
  static const _auditTable = 'app_settings_audit';

  /// Bucket compartido para assets globales de la empresa (logo, sello, firma).
  /// Reutiliza `product_images` (público + RLS para autenticados); los archivos
  /// de empresa se guardan bajo el prefijo `_company/` para diferenciarlos.
  static const _assetsBucket = 'product_images';

  /// Sube los bytes de un asset de empresa (logo, QR, etc.) a Storage y
  /// devuelve el URL público. El path se construye como
  /// `_company/<kind>-<timestamp>.<ext>`.
  Future<String> uploadCompanyLogo({
    required Uint8List bytes,
    required String extension,
    String kind = 'logo',
  }) async {
    final timestamp = DateTime.now().millisecondsSinceEpoch;
    final path = '_company/$kind-$timestamp.$extension';

    final storage = _client.storage.from(_assetsBucket);
    await storage.uploadBinary(
      path,
      bytes,
      fileOptions: FileOptions(
        upsert: false,
        contentType: _contentTypeFor(extension),
      ),
    );
    return storage.getPublicUrl(path);
  }

  String _contentTypeFor(String extension) {
    switch (extension.toLowerCase()) {
      case 'png':
        return 'image/png';
      case 'webp':
        return 'image/webp';
      case 'gif':
        return 'image/gif';
      default:
        return 'image/jpeg';
    }
  }

  /// Devuelve la fila de configuración de la empresa actual.
  ///
  /// Antes confiábamos solo en RLS para devolver la fila correcta. Eso
  /// fallaba mientras existían filas legacy con `company_id NULL` visibles
  /// para todos los usuarios — el `LIMIT 1` devolvía la legacy en vez de la
  /// del usuario. Ahora filtramos explícitamente por la empresa actual
  /// (`current_company_id`) para no depender del orden de Postgres.
  Future<AppSettings> fetch() async {
    final user = _client.auth.currentUser;
    if (user == null) {
      throw Exception('Debes iniciar sesión para leer la configuración.');
    }

    final companyId = await _currentCompanyId();
    if (companyId == null) {
      // Sin empresa asignada: usuario en proceso de onboarding o cuenta en
      // estado raro. Devolvemos defaults locales en vez de fallar.
      return const AppSettings(<String, dynamic>{});
    }

    final rows = await _client
        .from(_table)
        .select()
        .eq('company_id', companyId)
        .limit(1);

    if (rows.isEmpty) {
      return const AppSettings(<String, dynamic>{});
    }

    return AppSettings(Map<String, dynamic>.from(rows.first as Map));
  }

  Future<String?> _currentCompanyId() async {
    final result = await _client.rpc('current_company_id');
    if (result == null) return null;
    final value = result.toString();
    return value.isEmpty ? null : value;
  }

  /// Actualiza una sola columna y devuelve la fila completa actualizada.
  /// Lanza si el RLS bloquea (no admin).
  Future<AppSettings> updateField(String column, dynamic value) async {
    return updatePatch({column: value});
  }

  /// Actualiza múltiples columnas en un solo UPDATE.
  Future<AppSettings> updatePatch(Map<String, dynamic> patch) async {
    final user = _client.auth.currentUser;
    if (user == null) {
      throw Exception('Debes iniciar sesión para editar la configuración.');
    }
    if (patch.isEmpty) {
      return fetch();
    }

    final companyId = await _currentCompanyId();
    if (companyId == null) {
      throw Exception(
        'No hay empresa asignada para este usuario. Completa el onboarding.',
      );
    }

    final payload = <String, dynamic>{
      ...patch,
      'updated_by': user.id,
    };

    // Filtramos explícitamente por company_id para evitar tocar filas de
    // otras empresas (incluso si la RLS lo permitiera por alguna razón).
    final rows = await _client
        .from(_table)
        .update(payload)
        .eq('company_id', companyId)
        .select()
        .limit(1);

    if (rows.isEmpty) {
      throw Exception(
        'No se pudo actualizar la configuración. Verifica permisos.',
      );
    }
    return AppSettings(Map<String, dynamic>.from(rows.first as Map));
  }

  /// Devuelve las últimas N entradas de auditoría (solo admin por RLS).
  Future<List<AppSettingsAuditEntry>> fetchAuditLog({int limit = 100}) async {
    final rows = await _client
        .from(_auditTable)
        .select()
        .order('changed_at', ascending: false)
        .limit(limit);

    return rows
        .map(
          (item) => AppSettingsAuditEntry.fromMap(
            Map<String, dynamic>.from(item as Map),
          ),
        )
        .toList(growable: false);
  }
}
