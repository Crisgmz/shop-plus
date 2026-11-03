import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:supabase_flutter/supabase_flutter.dart';

/// Solicitud de facturación electrónica que hace el dueño desde Configuración.
///
/// Todo pasa por la Edge Function `ecf-onboarding`, que valida que quien pide
/// sea administrador de la empresa. El certificado viaja a Alanube en la misma
/// petición; si el cliente lo autoriza, además se guarda CIFRADO en el
/// servidor para firmar las pruebas de la DGII desde el trámite paso a paso
/// (`ecf_onboarding_repository.dart`). La clave de la Oficina Virtual es
/// opcional y también se guarda cifrada.
///
/// Portado de mangospos (`lib/data/repositories/ecf_request_repository.dart`),
/// que es donde este flujo ya está probado. Cambia la llave —acá la
/// facturación es de la EMPRESA (`company_id`), no de la sucursal— y el
/// formato de error, que sigue el del resto de funciones de esta app.

/// Tipos de e-CF que maneja el alta, con lo que significa cada uno.
const ecfTypeLabels = <String, String>{
  'E31': 'Crédito fiscal (cliente con RNC)',
  'E32': 'Consumo (consumidor final)',
  'E34': 'Nota de crédito',
  'E44': 'Régimen especial',
  'E45': 'Gubernamental',
};

/// Los que este POS emite hoy: sin E34, porque todavía no hay notas de crédito
/// electrónicas. Igual que `EMITTABLE_ECF_TYPES` en el servidor.
const emittableEcfTypes = ['E31', 'E32', 'E44', 'E45'];

/// En qué va la facturación electrónica de la empresa (lo deriva el servidor).
enum EcfRequestStage {
  /// Nunca la pidió.
  none,

  /// Pedida; falta registrar la empresa con el proveedor.
  company,

  /// Falta la autorización de la DGII.
  certification,

  /// Autorizada; faltan las secuencias e-NCF.
  sequences,

  /// Todo listo; falta encenderla.
  activation,

  /// Ya emite comprobantes electrónicos.
  active;

  static EcfRequestStage parse(String? raw) => EcfRequestStage.values.firstWhere(
    (s) => s.name == raw,
    orElse: () => EcfRequestStage.none,
  );
}

/// Datos del contribuyente tal como están en la DGII.
class EcfRequestData {
  const EcfRequestData({
    this.rnc,
    this.legalName,
    this.tradeName,
    this.fiscalAddress,
    this.province,
    this.municipality,
    this.email,
  });

  final String? rnc;
  final String? legalName;
  final String? tradeName;
  final String? fiscalAddress;
  final String? province;
  final String? municipality;
  final String? email;

  factory EcfRequestData.fromJson(Map<String, dynamic> json) => EcfRequestData(
    rnc: json['rnc'] as String?,
    legalName: json['legal_name'] as String?,
    tradeName: json['trade_name'] as String?,
    fiscalAddress: json['fiscal_address'] as String?,
    province: json['province'] as String?,
    municipality: json['municipality'] as String?,
    email: json['email'] as String?,
  );

  Map<String, dynamic> toJson() => {
    'rnc': rnc,
    'legal_name': legalName,
    'trade_name': tradeName,
    'fiscal_address': fiscalAddress,
    'province': province,
    'municipality': municipality,
    'email': email,
  };
}

/// Sucursal que declara el cliente en la solicitud (con su dirección).
class EcfRequestBranch {
  const EcfRequestBranch({this.name, required this.address});

  final String? name;
  final String address;

  factory EcfRequestBranch.fromJson(Map<String, dynamic> json) =>
      EcfRequestBranch(
        name: json['name'] as String?,
        address: (json['address'] ?? '').toString(),
      );

  Map<String, dynamic> toJson() => {'name': name, 'address': address};
}

/// Requisitos de la solicitud que no viajan al proveedor: son para quien hace
/// la certificación ante la DGII.
class EcfRequestDetails {
  const EcfRequestDetails({
    this.phone,
    this.legalRepName,
    this.branches = const [],
    this.ecfTypes = const [],
    this.ofvUser,
    this.ofvPassword,
    this.ofvPasswordSaved = false,
  });

  /// Teléfono de la empresa (el de quien coordina es el de contacto).
  final String? phone;
  final String? legalRepName;
  final List<EcfRequestBranch> branches;

  /// E31, E32...
  final List<String> ecfTypes;

  /// Usuario de la Oficina Virtual de la DGII.
  final String? ofvUser;

  /// Clave de la Oficina Virtual, solo al ENVIAR (opcional; el servidor la
  /// guarda cifrada). Nunca vuelve del servidor.
  final String? ofvPassword;

  /// El servidor ya tiene una clave guardada (lo dice `request_status`).
  final bool ofvPasswordSaved;

  factory EcfRequestDetails.fromJson(Map<String, dynamic> json) {
    final branches = json['branches'];
    final types = json['ecf_types'];
    return EcfRequestDetails(
      phone: json['phone'] as String?,
      legalRepName: json['legal_rep_name'] as String?,
      branches: branches is List
          ? [
              for (final b in branches)
                if (b is Map)
                  EcfRequestBranch.fromJson(Map<String, dynamic>.from(b)),
            ]
          : const [],
      ecfTypes:
          types is List ? types.map((t) => t.toString()).toList() : const [],
      ofvUser: json['ofv_user'] as String?,
      ofvPasswordSaved: json['ofv_password_saved'] == true,
    );
  }

  Map<String, dynamic> toJson() => {
    'phone': phone,
    'legal_rep_name': legalRepName,
    'branches': branches.map((b) => b.toJson()).toList(),
    'ecf_types': ecfTypes,
    'ofv_user': ofvUser,
    // Vacía no se manda: el servidor conserva la que tenga guardada.
    if (ofvPassword != null && ofvPassword!.isNotEmpty)
      'ofv_password': ofvPassword,
  };
}

/// Sucursal de la empresa, para decir dónde se usa una secuencia e-NCF.
class EcfBranch {
  const EcfBranch({required this.id, required this.name});

  final String id;
  final String name;

  factory EcfBranch.fromJson(Map<String, dynamic> json) => EcfBranch(
    id: (json['id'] ?? '').toString(),
    name: (json['name'] ?? '').toString(),
  );
}

/// Secuencia e-NCF ya cargada, como la ve la pantalla.
class EcfSequence {
  const EcfSequence({
    required this.id,
    required this.branchId,
    required this.ncfType,
    required this.currentNumber,
    required this.rangeEnd,
    required this.isActive,
    this.expirationDate,
  });

  final String id;
  final String branchId;
  final String ncfType;
  final int currentNumber;
  final int rangeEnd;
  final bool isActive;
  final String? expirationDate;

  /// Números que quedan por consumir de la autorización.
  int get remaining => rangeEnd - currentNumber;

  /// Tipos donde la DGII valida la fecha de vencimiento (código 145 si falta).
  static const typesRequiringExpiration = {'E31', 'E44', 'E45'};

  bool get missingExpiration =>
      typesRequiringExpiration.contains(ncfType) && expirationDate == null;

  bool get isExpired {
    final exp = DateTime.tryParse(expirationDate ?? '');
    if (exp == null) return false;
    final now = DateTime.now();
    return exp.isBefore(DateTime(now.year, now.month, now.day));
  }

  /// Sirve para emitir: activa, con números y sin trabas de vencimiento. Mismo
  /// criterio que `hasUsableEcfSequence` en el servidor.
  bool get isUsable =>
      isActive && remaining > 0 && !missingExpiration && !isExpired;

  factory EcfSequence.fromJson(Map<String, dynamic> json) => EcfSequence(
    id: (json['id'] ?? '').toString(),
    branchId: (json['branch_id'] ?? '').toString(),
    ncfType: (json['ncf_type'] ?? '').toString(),
    currentNumber: (json['current_number'] as num?)?.toInt() ?? 0,
    rangeEnd: (json['range_end'] as num?)?.toInt() ?? 0,
    isActive: json['is_active'] == true,
    expirationDate: json['expiration_date'] as String?,
  );
}

class EcfRequestStatus {
  const EcfRequestStatus({
    required this.stage,
    this.requestedAt,
    this.contactName,
    this.contactPhone,
    this.alreadyAuthorized,
    this.mode = 'physical',
    this.environment = 'sandbox',
    this.certificationStatus = 'pending',
    this.alanubeCompanyId,
    this.data = const EcfRequestData(),
    this.details = const EcfRequestDetails(),
    this.branches = const [],
    this.sequences = const [],
  });

  final EcfRequestStage stage;
  final DateTime? requestedAt;
  final String? contactName;
  final String? contactPhone;
  final bool? alreadyAuthorized;

  /// 'physical' | 'hybrid' | 'electronic'.
  final String mode;
  final String environment;
  final String certificationStatus;
  final String? alanubeCompanyId;

  /// Lo último que mandó (o lo que la app ya sabía): precarga el formulario.
  final EcfRequestData data;
  final EcfRequestDetails details;

  final List<EcfBranch> branches;
  final List<EcfSequence> sequences;

  bool get electronicEnabled => mode != 'physical';

  factory EcfRequestStatus.fromJson(Map<String, dynamic> json) {
    final data = json['data'];
    final details = json['details'];
    return EcfRequestStatus(
      stage: EcfRequestStage.parse(json['stage'] as String?),
      requestedAt: DateTime.tryParse(json['requested_at']?.toString() ?? ''),
      contactName: json['contact_name'] as String?,
      contactPhone: json['contact_phone'] as String?,
      alreadyAuthorized: json['already_authorized'] as bool?,
      mode: (json['mode'] ?? 'physical').toString(),
      environment: (json['environment'] ?? 'sandbox').toString(),
      certificationStatus: (json['certification_status'] ?? 'pending').toString(),
      alanubeCompanyId: json['alanube_company_id'] as String?,
      data: data is Map
          ? EcfRequestData.fromJson(Map<String, dynamic>.from(data))
          : const EcfRequestData(),
      details: details is Map
          ? EcfRequestDetails.fromJson(Map<String, dynamic>.from(details))
          : const EcfRequestDetails(),
      branches: (json['branches'] as List? ?? const [])
          .map((e) => EcfBranch.fromJson(Map<String, dynamic>.from(e as Map)))
          .toList(growable: false),
      sequences: (json['sequences'] as List? ?? const [])
          .map((e) => EcfSequence.fromJson(Map<String, dynamic>.from(e as Map)))
          .toList(growable: false),
    );
  }
}

/// Lo que se manda al solicitar la facturación electrónica.
class EcfRequestSubmission {
  const EcfRequestSubmission({
    required this.data,
    required this.details,
    required this.contactName,
    required this.contactPhone,
    required this.alreadyAuthorized,
    required this.certificateFilename,
    required this.certificateBytes,
    required this.certificatePassword,
    this.acceptCertificateStorage = false,
  });

  final EcfRequestData data;
  final EcfRequestDetails details;
  final String contactName;
  final String contactPhone;
  final bool alreadyAuthorized;
  final String certificateFilename;
  final Uint8List certificateBytes;
  final String certificatePassword;

  /// Autoriza guardar el certificado cifrado para firmar las pruebas de la
  /// DGII desde Configuración → Facturación electrónica. Sin esto, el
  /// certificado solo viaja al proveedor y se descarta.
  final bool acceptCertificateStorage;
}

/// Autorización e-NCF que la DGII entrega en PDF.
class EcfSequenceSubmission {
  const EcfSequenceSubmission({
    required this.branchId,
    required this.ncfType,
    required this.rangeStart,
    required this.rangeEnd,
    this.expirationDate,
    this.authorizationNumber,
    this.lastUsed,
  });

  final String branchId;
  final String ncfType;
  final int rangeStart;
  final int rangeEnd;

  /// AAAA-MM-DD. E31, E44 y E45 la exigen: sin ella la DGII rechaza (145).
  final String? expirationDate;
  final String? authorizationNumber;

  /// Último número ya consumido de esa autorización, si venía usándose fuera
  /// del sistema.
  final int? lastUsed;

  Map<String, dynamic> toJson() => {
    'ncf_type': ncfType,
    'range_start': rangeStart,
    'range_end': rangeEnd,
    'expiration_date': expirationDate,
    'authorization_number': authorizationNumber,
    'last_used': lastUsed,
  };
}

class EcfRequestResult {
  const EcfRequestResult({required this.companyRegistered, this.message});

  /// La empresa quedó registrada con el proveedor en este envío.
  final bool companyRegistered;

  /// Aviso del servidor cuando no se registró (por ejemplo, ya existía).
  final String? message;
}

class EcfRequestException implements Exception {
  const EcfRequestException(this.message, {this.code});

  final String message;
  final String? code;

  @override
  String toString() => message;
}

class EcfRequestRepository {
  EcfRequestRepository(this._client);

  final SupabaseClient _client;

  Future<String> _companyId() async {
    final id = await _client.rpc('current_company_id');
    final value = id?.toString() ?? '';
    if (value.isEmpty) {
      throw const EcfRequestException('No se pudo determinar la empresa actual.');
    }
    return value;
  }

  Future<EcfRequestStatus> status() async {
    final data = await invoke({'action': 'request_status'});
    return EcfRequestStatus.fromJson(data);
  }

  Future<EcfRequestResult> submit(EcfRequestSubmission s) async {
    final data = await invoke({
      'action': 'submit_request',
      'data': s.data.toJson(),
      'details': s.details.toJson(),
      'contact_name': s.contactName,
      'contact_phone': s.contactPhone,
      'already_authorized': s.alreadyAuthorized,
      'accept_terms': true,
      if (s.acceptCertificateStorage) 'accept_certificate_storage': true,
      'certificate': {
        'filename': s.certificateFilename,
        'content_base64': base64Encode(s.certificateBytes),
        'password': s.certificatePassword,
      },
    });
    return EcfRequestResult(
      companyRegistered: data['company_registered'] == true,
      message: data['message'] as String?,
    );
  }

  Future<void> saveSequence(EcfSequenceSubmission s) async {
    await invoke({
      'action': 'save_sequence',
      'branch_id': s.branchId,
      'sequence': s.toJson(),
    });
  }

  /// Enciende o apaga la modalidad e-CF. El servidor rechaza encenderla sin
  /// empresa registrada o sin una secuencia usable.
  Future<void> setEnabled(bool enabled) async {
    await invoke({'action': 'set_ecf_enabled', 'enabled': enabled});
  }

  /// Llama a `ecf-onboarding` con la empresa actual. La usa también
  /// `EcfOnboardingRepository` (el trámite paso a paso): una sola vía para el
  /// company_id y para traducir los errores.
  Future<Map<String, dynamic>> invoke(Map<String, dynamic> body) async {
    final companyId = await _companyId();
    try {
      final res = await _client.functions.invoke(
        'ecf-onboarding',
        body: {...body, 'company_id': companyId},
      );
      final data = res.data;
      if (data is Map) return Map<String, dynamic>.from(data);
      throw const EcfRequestException('Respuesta inesperada del servidor.');
    } on FunctionException catch (e) {
      throw describeFunctionError(e);
    }
  }

  /// La función devuelve `{ error, message, detail }`. Cuando el detalle trae
  /// la lista de lo que falta, se muestra eso: es más útil que un mensaje
  /// genérico frente a un formulario con ocho campos.
  ///
  /// Si la función no está publicada, Supabase cloud responde 404, pero el
  /// Supabase propio (Coolify) responde 500 desde su router `main` con
  /// `{ msg: "InvalidWorkerCreation: … could not find an appropriate
  /// entrypoint" }`. Las dos cosas significan lo mismo para el usuario.
  @visibleForTesting
  static EcfRequestException describeFunctionError(FunctionException e) {
    final details = e.details;
    if (details is Map) {
      final map = Map<String, dynamic>.from(details);
      final detail = map['detail'];
      final message = map['message']?.toString();
      if (detail is List && detail.isNotEmpty) {
        return EcfRequestException(
          detail.map((d) => d.toString()).join(' '),
          code: map['error']?.toString(),
        );
      }
      if (message != null && message.isNotEmpty) {
        return EcfRequestException(message, code: map['error']?.toString());
      }
    }
    final routerMsg = details is Map ? details['msg']?.toString() ?? '' : '';
    final notDeployed = e.status == 404 ||
        routerMsg.contains('could not find an appropriate entrypoint');
    return EcfRequestException(
      notDeployed
          ? 'El servidor todavía no tiene esta función disponible.'
          : 'No se pudo completar la solicitud. Intenta de nuevo.',
      code: notDeployed ? 'not_deployed' : null,
    );
  }
}
