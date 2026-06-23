// Consulta de contribuyentes contra el padrón RNC de la DGII (RD).
//
// La consulta se hace DEL LADO DEL SERVIDOR vía los RPC `rnc_lookup` /
// `rnc_search` (migración 57), que a su vez pegan a rnc.megaplus.com.do — un
// proxy público que cachea el padrón oficial de la DGII. Se hace server-side a
// propósito: la API de DGII/proxy NO envía cabeceras CORS, así que un GET
// directo desde el navegador (Flutter web) quedaría bloqueado. El RPC pasa por
// Supabase (CORS ok) y funciona en web, móvil y escritorio por igual.
//
// JSON de DGII (single):
//   {"error":false,"codigo_http":200,"cedula_rnc":"101-01063-2",
//    "nombre_razon_social":"BANCO POPULAR DOMINICANO S A BANCO MULTIPLE",
//    "nombre_comercial":"BANCO POPULAR DOMINICANO","estado":"ACTIVO",
//    "actividad_economica":"BANCOS MULTIPLES","facturador_electronico":"SI",...}

import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Datos devueltos por el padrón DGII para un contribuyente.
class DgiiCompanyInfo {
  /// RNC/cédula tal como lo devuelve DGII (puede venir formateado).
  final String rnc;

  /// Razón social registrada.
  final String? nombreRazonSocial;

  /// Nombre comercial / marca (puede estar vacío).
  final String? nombreComercial;

  /// `ACTIVO`, `DADO DE BAJA`, `SUSPENDIDO`, etc.
  final String? estado;

  /// Actividad económica primaria.
  final String? actividadEconomica;

  /// Régimen de pagos (`NORMAL`, `PST`, etc.).
  final String? regimenPagos;

  /// `SI` / `NO` — si el contribuyente está autorizado a emitir e-CF.
  final String? facturadorElectronico;

  const DgiiCompanyInfo({
    required this.rnc,
    this.nombreRazonSocial,
    this.nombreComercial,
    this.estado,
    this.actividadEconomica,
    this.regimenPagos,
    this.facturadorElectronico,
  });

  /// `true` si el contribuyente está reportado como activo. Otros estados
  /// (DADO DE BAJA, SUSPENDIDO) conviene avisarlos antes de facturarle.
  bool get isActivo => (estado ?? '').trim().toUpperCase() == 'ACTIVO';

  /// `true` si DGII lo tiene autorizado para facturación electrónica (e-CF).
  bool get esFacturadorElectronico =>
      (facturadorElectronico ?? '').trim().toUpperCase() == 'SI';

  /// Mejor nombre disponible: razón social si existe, si no el comercial.
  String? get displayName {
    final r = nombreRazonSocial?.trim();
    if (r != null && r.isNotEmpty) return r;
    return nombreComercial?.trim();
  }

  factory DgiiCompanyInfo.fromMap(Map<String, dynamic> map) {
    String? str(String key) {
      final v = map[key];
      if (v == null) return null;
      final s = v.toString().trim();
      return s.isEmpty ? null : s;
    }

    return DgiiCompanyInfo(
      rnc: (map['cedula_rnc'] ?? map['rnc'] ?? '').toString().trim(),
      nombreRazonSocial: str('nombre_razon_social'),
      nombreComercial: str('nombre_comercial'),
      estado: str('estado'),
      actividadEconomica: str('actividad_economica'),
      regimenPagos: str('regimen_de_pagos'),
      facturadorElectronico: str('facturador_electronico'),
    );
  }
}

/// Lanzada cuando el RNC no tiene formato válido (no son 9 ni 11 dígitos).
/// El caller la captura para avisar al usuario sin pegar la red.
class InvalidRncException implements Exception {
  final String reason;
  const InvalidRncException(this.reason);
  @override
  String toString() => reason;
}

class DgiiLookupService {
  final SupabaseClient _supabase;
  DgiiLookupService({SupabaseClient? supabase})
    : _supabase = supabase ?? Supabase.instance.client;

  /// Busca un contribuyente por RNC o cédula. Devuelve `null` si DGII no lo
  /// tiene registrado. Lanza [InvalidRncException] si el formato es inválido,
  /// o [Exception] si la red/servidor falla.
  Future<DgiiCompanyInfo?> lookupByRnc(String rnc) async {
    final cleaned = _normalize(rnc);
    if (cleaned.length != 9 && cleaned.length != 11) {
      throw const InvalidRncException(
        'El RNC debe tener 9 dígitos (empresa) o 11 (cédula).',
      );
    }

    final dynamic res;
    try {
      res = await _supabase.rpc('rnc_lookup', params: {'p_rnc': cleaned});
    } on PostgrestException catch (e) {
      // La función SQL lanza con mensaje legible (formato, error DGII, etc.).
      throw Exception(e.message);
    } catch (e) {
      throw Exception(
        'No se pudo conectar a DGII. Revisa tu conexión e intenta de nuevo.',
      );
    }

    if (res == null) return null; // no inscrito
    final map = _asMap(res);
    if (map == null) throw Exception('Respuesta inesperada de DGII.');

    if (map['error'] == true) {
      if (map['codigo_http'] == 404) return null;
      throw Exception(
        map['mensaje']?.toString() ?? 'Error desconocido de DGII.',
      );
    }
    return DgiiCompanyInfo.fromMap(map);
  }

  /// Búsqueda parcial por nombre/razón social. Devuelve lista vacía si no hay
  /// match, la consulta es corta (<3) o el servidor falla de forma recuperable.
  Future<List<DgiiCompanyInfo>> searchByName(String query) async {
    final q = query.trim();
    if (q.length < 3) return const <DgiiCompanyInfo>[];

    final dynamic res;
    try {
      res = await _supabase.rpc('rnc_search', params: {'p_query': q});
    } catch (_) {
      return const <DgiiCompanyInfo>[];
    }

    final map = _asMap(res);
    final results = map?['resultados'];
    if (results is! List) return const <DgiiCompanyInfo>[];
    return results
        .whereType<Map>()
        .map((e) => DgiiCompanyInfo.fromMap(Map<String, dynamic>.from(e)))
        .toList(growable: false);
  }

  /// El RPC devuelve jsonb → el cliente lo entrega como Map; tolera String.
  static Map<String, dynamic>? _asMap(dynamic v) {
    if (v == null) return null;
    if (v is Map) return Map<String, dynamic>.from(v);
    if (v is String) {
      try {
        final d = jsonDecode(v);
        return d is Map ? Map<String, dynamic>.from(d) : null;
      } catch (_) {
        return null;
      }
    }
    return null;
  }

  /// Deja solo dígitos (quita `-`, espacios, puntos).
  static String _normalize(String rnc) => rnc.replaceAll(RegExp(r'[^0-9]'), '');
}

/// Servicio singleton de consulta DGII.
final dgiiLookupServiceProvider = Provider<DgiiLookupService>(
  (ref) => DgiiLookupService(),
);
