/// Trámite de facturación electrónica (e-CF) de la empresa, paso a paso.
///
/// Espejo de la respuesta de la Edge Function `ecf-onboarding` (acción
/// `status`). Portado del panel de MangoPOS
/// (`mangopos_administrador/lib/domain/models/ecf_onboarding.dart`), donde el
/// mismo flujo lo hace un operador. Aquí lo hace el administrador de la
/// empresa sobre SU empresa, así que no hay dueño externo, ni POS ajena con la
/// que comparar, ni preflight de activación: la activación es el mismo botón
/// "Encender" de la tarjeta de Configuración.
///
/// Las reglas (validaciones, RNC contra el proveedor, secuencias) viven en el
/// servidor: aquí solo se presenta y se deriva en qué paso va.
library;

import 'ecf_request_repository.dart';

class EcfOnboardingStatus {
  const EcfOnboardingStatus({
    required this.stage,
    required this.environment,
    this.draft,
    this.settings,
    this.company,
    this.companyError,
    this.testSet,
    this.approvalSet,
    this.simulationSet,
    this.sequences = const [],
    this.branches = const [],
  });

  /// La etapa que deriva el servidor (la misma de la tarjeta).
  final EcfRequestStage stage;

  /// `production | sandbox`: sale de la cuenta del proveedor del servidor.
  final String environment;

  /// Lo que la empresa mandó y el avance del trámite (`ecf_onboarding`).
  /// Null si nunca lo pidió.
  final EcfTaxpayerDraft? draft;

  /// `company_ecf_settings`: el ID con el proveedor y la modalidad.
  final EcfProviderSettings? settings;

  /// La empresa como la tiene el proveedor (Alanube).
  final EcfCompany? company;

  /// Por qué no se pudo leer la empresa en el proveedor, si falló.
  final String? companyError;

  /// Set de pruebas de la DGII cargado. Solo viene mientras la certificación
  /// está en curso.
  final EcfTestSet? testSet;

  /// Aprobaciones comerciales de la DGII cargadas.
  final EcfTestSet? approvalSet;

  /// e-CF de la simulación (paso 4 del portal), generados desde el set de datos.
  final EcfTestSet? simulationSet;

  final List<EcfSequence> sequences;
  final List<EcfBranch> branches;

  bool get isProduction => environment == 'production';

  /// ID de la empresa con el proveedor.
  String? get companyId =>
      settings?.alanubeCompanyId ?? draft?.alanubeCompanyId;

  bool get hasRequest => draft?.requestedAt != null;
  bool get hasData => draft?.isCompleteForRegistration ?? false;
  bool get hasCompany => companyId != null;
  bool get hasSequences => sequences.any((s) => s.isUsable);

  /// Ya emite comprobantes electrónicos.
  bool get ecfEnabled =>
      hasCompany && (settings?.mode ?? 'physical') != 'physical';

  /// Autorizada por la DGII como emisor electrónico. Además de la marca de
  /// "La DGII ya lo autorizó", cuenta lo que declaró al pedirla, que el
  /// proveedor la tenga certificada, tener secuencias e-NCF o estar emitiendo:
  /// la DGII no entrega secuencias E a quien no autorizó.
  bool get isCertified =>
      draft?.dgiiAuthorizedAt != null ||
      draft?.alreadyAuthorized == true ||
      settings?.certificationStatus == 'certified' ||
      hasSequences ||
      ecfEnabled;

  /// Paso en curso (1–5); 6 cuando ya emite.
  int get currentStep {
    if (ecfEnabled) return 6;
    if (!hasCompany && !hasRequest && !hasData) return 1;
    if (!hasCompany) return 2;
    if (!isCertified) return 3;
    if (!hasSequences) return 4;
    return 5;
  }

  factory EcfOnboardingStatus.fromJson(Map<String, dynamic> json) {
    final draft = _map(json['onboarding']);
    final settings = _map(json['settings']);
    final company = _map(json['company']);
    final testSet = _map(json['test_set']);
    final approvalSet = _map(json['approval_set']);
    final simulationSet = _map(json['simulation_set']);
    return EcfOnboardingStatus(
      stage: EcfRequestStage.parse(json['stage'] as String?),
      environment: (json['environment'] as String?) ?? 'production',
      draft: draft == null ? null : EcfTaxpayerDraft.fromJson(draft),
      settings: settings == null
          ? null
          : EcfProviderSettings.fromJson(settings),
      company: company == null ? null : EcfCompany.fromJson(company),
      companyError: json['company_error'] as String?,
      testSet: testSet == null ? null : EcfTestSet.fromJson(testSet),
      approvalSet: approvalSet == null
          ? null
          : EcfTestSet.fromJson(approvalSet),
      simulationSet: simulationSet == null
          ? null
          : EcfTestSet.fromJson(simulationSet),
      sequences: ((json['sequences'] as List?) ?? const [])
          .whereType<Map>()
          .map((e) => EcfSequence.fromJson(Map<String, dynamic>.from(e)))
          .toList(growable: false),
      branches: ((json['branches'] as List?) ?? const [])
          .whereType<Map>()
          .map((e) => EcfBranch.fromJson(Map<String, dynamic>.from(e)))
          .toList(growable: false),
    );
  }
}

/// Datos del contribuyente y avance del trámite (`ecf_onboarding`). Los
/// secretos (certificado, clave de la OFV, sesión con la DGII) NUNCA vienen:
/// solo sus metadatos.
class EcfTaxpayerDraft {
  const EcfTaxpayerDraft({
    this.rnc,
    this.legalName,
    this.tradeName,
    this.fiscalAddress,
    this.province,
    this.municipality,
    this.email,
    this.alanubeCompanyId,
    this.companyLinkedVia,
    this.companyLinkedAt,
    this.postulationSignedAt,
    this.declarationSignedAt,
    this.rolesSignedAt,
    this.dgiiAuthorizedAt,
    this.requestedAt,
    this.contactName,
    this.contactPhone,
    this.alreadyAuthorized,
    this.ofvUser,
    this.ofvPasswordUpdatedAt,
    this.certificateFilename,
    this.certificateUpdatedAt,
  });

  final String? rnc;
  final String? legalName;
  final String? tradeName;
  final String? fiscalAddress;
  final String? province;
  final String? municipality;
  final String? email;
  final String? alanubeCompanyId;

  /// `registered` (la registró la app) | `existing` (ya existía).
  final String? companyLinkedVia;
  final DateTime? companyLinkedAt;

  // Certificación: cuándo se firmó cada XML DESDE AQUÍ. Firmar no es subirlo
  // a la Oficina Virtual; la verdad la tiene la DGII.
  final DateTime? postulationSignedAt;
  final DateTime? declarationSignedAt;
  final DateTime? rolesSignedAt;

  /// Marcado a mano con "La DGII ya lo autorizó".
  final DateTime? dgiiAuthorizedAt;

  /// Cuándo se pidió desde Configuración.
  final DateTime? requestedAt;
  final String? contactName;
  final String? contactPhone;

  /// Lo que declaró al pedirla: ya es emisor electrónico autorizado.
  final bool? alreadyAuthorized;

  /// Acceso a la Oficina Virtual de la DGII. La clave se consulta aparte y
  /// no forma parte del estado.
  final String? ofvUser;
  final DateTime? ofvPasswordUpdatedAt;

  bool get hasOfvPassword => ofvPasswordUpdatedAt != null;

  /// Solo metadatos: el archivo y su clave quedan cifrados en el servidor.
  final String? certificateFilename;
  final DateTime? certificateUpdatedAt;

  bool get hasCertificate =>
      _filled(certificateFilename) && certificateUpdatedAt != null;

  /// Lo mínimo que exige el alta con el proveedor.
  bool get isCompleteForRegistration =>
      _filled(rnc) && _filled(legalName) && _filled(fiscalAddress);

  factory EcfTaxpayerDraft.fromJson(Map<String, dynamic> json) {
    return EcfTaxpayerDraft(
      rnc: json['rnc'] as String?,
      legalName: json['legal_name'] as String?,
      tradeName: json['trade_name'] as String?,
      fiscalAddress: json['fiscal_address'] as String?,
      province: json['province'] as String?,
      municipality: json['municipality'] as String?,
      email: json['email'] as String?,
      alanubeCompanyId: json['alanube_company_id'] as String?,
      companyLinkedVia: json['company_linked_via'] as String?,
      companyLinkedAt: _date(json['company_linked_at']),
      postulationSignedAt: _date(json['postulation_signed_at']),
      declarationSignedAt: _date(json['declaration_signed_at']),
      rolesSignedAt: _date(json['roles_signed_at']),
      dgiiAuthorizedAt: _date(json['dgii_authorized_at']),
      requestedAt: _date(json['requested_at']),
      contactName: json['contact_name'] as String?,
      contactPhone: json['contact_phone'] as String?,
      alreadyAuthorized: json['already_authorized'] as bool?,
      ofvUser: json['ofv_user'] as String?,
      ofvPasswordUpdatedAt: _date(json['ofv_password_updated_at']),
      certificateFilename: json['certificate_filename'] as String?,
      certificateUpdatedAt: _date(json['certificate_updated_at']),
    );
  }

  /// Lo que manda `save_data`: solo los datos del contribuyente.
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

/// `company_ecf_settings` de la empresa.
class EcfProviderSettings {
  const EcfProviderSettings({
    required this.environment,
    required this.mode,
    required this.certificationStatus,
    this.alanubeCompanyId,
  });

  final String? alanubeCompanyId;
  final String environment;

  /// `physical | hybrid | electronic`.
  final String mode;
  final String certificationStatus;

  factory EcfProviderSettings.fromJson(Map<String, dynamic> json) {
    return EcfProviderSettings(
      alanubeCompanyId: json['alanube_company_id'] as String?,
      environment: (json['environment'] as String?) ?? 'production',
      mode: (json['mode'] as String?) ?? 'physical',
      certificationStatus:
          (json['certification_status'] as String?) ?? 'pending',
    );
  }
}

/// Acceso a la Oficina Virtual devuelto solo al consultarlo (queda auditado).
/// No se guarda en el estado ni en los providers.
class EcfOfvCredentials {
  const EcfOfvCredentials({required this.ofvPassword, this.ofvUser});

  final String? ofvUser;
  final String ofvPassword;
}

/// Empresa en el proveedor (resumen que arma el servidor, sin datos sensibles).
class EcfCompany {
  const EcfCompany({
    required this.id,
    this.name,
    this.tradeName,
    this.identification,
    this.address,
    this.certificationStep,
    this.certificateName,
    this.certificateIssuer,
    this.certificateEndDate,
    this.webhooksOk,
    this.receptionUrl,
    this.approvalUrl,
    this.authenticationUrl,
  });

  final String id;
  final String? name;
  final String? tradeName;
  final String? identification;
  final String? address;

  /// Contador del proveedor. OJO: no es confiable; la prueba es la
  /// autorización de la DGII.
  final int? certificationStep;
  final String? certificateName;
  final String? certificateIssuer;

  /// El proveedor la manda como "2027-04-23 21:30:54".
  final DateTime? certificateEndDate;

  /// Null cuando la respuesta no lo trae.
  final bool? webhooksOk;

  /// URLs que se registran en la postulación de la DGII.
  final String? receptionUrl;
  final String? approvalUrl;
  final String? authenticationUrl;

  bool get hasCertificate => certificateName != null;

  bool get certificateExpired =>
      certificateEndDate != null &&
      certificateEndDate!.isBefore(DateTime.now());

  factory EcfCompany.fromJson(Map<String, dynamic> json) {
    final cert = _map(json['certificate']);
    final urls = _map(json['company_urls']);
    return EcfCompany(
      id: (json['id'] ?? '').toString(),
      name: json['name'] as String?,
      tradeName: json['trade_name'] as String?,
      identification: json['identification']?.toString(),
      address: json['address'] as String?,
      certificationStep: (json['certification_step'] as num?)?.toInt(),
      certificateName: cert?['name'] as String?,
      certificateIssuer: cert?['issuer'] as String?,
      certificateEndDate: _date(cert?['end_date']),
      webhooksOk: json['webhooks_ok'] as bool?,
      receptionUrl: urls?['reception'] as String?,
      approvalUrl: urls?['approval'] as String?,
      authenticationUrl: urls?['authentication'] as String?,
    );
  }
}

/// Tipos de XML de habilitación que firma el proveedor.
enum EcfSignKind {
  postulation('postulation', 'XML de postulación'),
  declaration('declaration', 'Declaración jurada'),
  roles('roles', 'XML de asignación de roles');

  const EcfSignKind(this.code, this.label);
  final String code;
  final String label;
}

/// Resultado de firmar un XML de habilitación.
class EcfSignedDocument {
  const EcfSignedDocument({
    required this.kind,
    this.url,
    this.xmlBase64,
    this.filename,
  });

  final EcfSignKind kind;

  /// Enlace del proveedor al XML firmado (puede vencer).
  final String? url;

  /// El XML firmado, cuando el servidor lo pudo bajar del enlace.
  final String? xmlBase64;
  final String? filename;

  factory EcfSignedDocument.fromJson(
    EcfSignKind kind,
    Map<String, dynamic> json,
  ) {
    String? text(Object? v) => v is String && v.isNotEmpty ? v : null;
    return EcfSignedDocument(
      kind: kind,
      url: text(json['signed_document_url']),
      xmlBase64: text(json['signed_xml_base64']),
      filename: text(json['signed_filename']),
    );
  }
}

/// Set de pruebas de la DGII: el Excel que entrega su portal de certificación,
/// ya cargado. El servidor firma cada caso con el certificado de la empresa y
/// lo manda al ambiente CerteCF.
class EcfTestSet {
  const EcfTestSet({
    required this.cases,
    this.kind = 'ecf',
    this.filename,
    this.loadedAt,
    this.sessionExpiresAt,
  });

  /// `ecf` = pruebas de datos e-CF; `acecf` = pruebas de aprobación comercial;
  /// `sim` = pruebas de simulación e-CF.
  final String kind;
  final String? filename;
  final DateTime? loadedAt;

  bool get isApprovals => kind == 'acecf';
  bool get isSimulation => kind == 'sim';

  /// Mientras no venza, consultar a la DGII no pide el certificado.
  final DateTime? sessionExpiresAt;
  final List<EcfTestCase> cases;

  int count(bool Function(EcfTestCase c) test) => cases.where(test).length;

  int get accepted => count((c) => c.isAccepted);
  int get inProcess => count((c) => c.status == 'sent');
  int get toSend => count((c) => c.status == 'pending' || c.status == 'error');
  int get summaries => count((c) => c.isSummary);

  List<EcfTestCase> get rejected =>
      cases.where((c) => c.status == 'rejected').toList(growable: false);
  List<EcfTestCase> get failed =>
      cases.where((c) => c.status == 'error').toList(growable: false);

  bool get isEmpty => cases.isEmpty;

  /// La DGII aceptó todo (con o sin observaciones).
  bool get isComplete => cases.isNotEmpty && cases.every((c) => c.isAccepted);

  /// Un rechazo obliga a reiniciar el set en el portal de la DGII.
  bool get canSend => toSend > 0 && rejected.isEmpty;
  bool get canCheck => inProcess > 0;

  factory EcfTestSet.fromJson(Map<String, dynamic> json) {
    return EcfTestSet(
      kind: (json['kind'] as String?) ?? 'ecf',
      filename: json['filename'] as String?,
      loadedAt: _date(json['loaded_at']),
      sessionExpiresAt: _date(json['session_expires_at']),
      cases: ((json['cases'] as List?) ?? const [])
          .whereType<Map>()
          .map((e) => EcfTestCase.fromJson(Map<String, dynamic>.from(e)))
          .toList(growable: false),
    );
  }
}

/// Un comprobante del set (una fila de la hoja ECF).
class EcfTestCase {
  const EcfTestCase({
    required this.id,
    required this.position,
    required this.ecfType,
    required this.encf,
    required this.via,
    required this.status,
    required this.messages,
    this.total,
    this.modifies,
    this.trackId,
    this.securityCode,
    this.sentAt,
  });

  final String id;
  final int position;

  /// `31`, `32`… sin la E.
  final String ecfType;
  final String encf;
  final double? total;

  /// `ecf` → Recepción. `rfce` → E32 menor de 250 mil: va su resumen y el XML
  /// completo se sube a mano en el portal de la DGII. `acecf` → aprobación.
  final String via;

  /// `pending | sent | accepted | conditional | rejected | error`.
  final String status;
  final String? modifies;
  final String? trackId;
  final String? securityCode;
  final List<EcfDgiiMessage> messages;
  final DateTime? sentAt;

  bool get isSummary => via == 'rfce';

  /// Aprobación comercial (la empresa firma como compradora).
  bool get isApproval => via == 'acecf';

  /// Como lo cuenta el portal de la DGII en la simulación: el E32 se parte en
  /// `32` (desde 250 mil) y `32rfce` (menor, va como resumen).
  String get simulationCategory =>
      ecfType == '32' && isSummary ? '32rfce' : ecfType;
  bool get isAccepted => status == 'accepted' || status == 'conditional';

  /// Ya se firmó: hay XML para descargar.
  bool get hasXml => status == 'sent' || isAccepted || status == 'rejected';

  String get statusLabel {
    switch (status) {
      case 'pending':
        return 'Pendiente';
      case 'sent':
        return 'En proceso';
      case 'accepted':
        return 'Aceptado';
      case 'conditional':
        return 'Aceptado condicional';
      case 'rejected':
        return 'Rechazado';
      case 'error':
        return 'No se pudo enviar';
      default:
        return status;
    }
  }

  factory EcfTestCase.fromJson(Map<String, dynamic> json) {
    return EcfTestCase(
      id: (json['id'] ?? '').toString(),
      position: (json['position'] as num?)?.toInt() ?? 0,
      ecfType: (json['ecf_type'] as String?) ?? '',
      encf: (json['encf'] as String?) ?? '',
      total: (json['total'] as num?)?.toDouble(),
      via: (json['via'] as String?) ?? 'ecf',
      status: (json['status'] as String?) ?? 'pending',
      modifies: json['modifies'] as String?,
      trackId: json['track_id'] as String?,
      securityCode: json['security_code'] as String?,
      messages: ((json['messages'] as List?) ?? const [])
          .whereType<Map>()
          .map((e) => EcfDgiiMessage.fromJson(Map<String, dynamic>.from(e)))
          .toList(growable: false),
      sentAt: _date(json['sent_at']),
    );
  }
}

class EcfDgiiMessage {
  const EcfDgiiMessage({required this.message, this.code});

  final String? code;
  final String message;

  factory EcfDgiiMessage.fromJson(Map<String, dynamic> json) {
    return EcfDgiiMessage(
      code: json['code']?.toString(),
      message: (json['message'] as String?) ?? '',
    );
  }
}

/// Respuesta de un lote de `send_test_set`.
class EcfTestSetSendResult {
  const EcfTestSetSendResult({
    required this.sent,
    required this.more,
    required this.testSet,
    this.stoppedReason,
  });

  final int sent;

  /// Quedó trabajo: hay que volver a llamar con el mismo certificado.
  final bool more;
  final String? stoppedReason;
  final EcfTestSet testSet;

  factory EcfTestSetSendResult.fromJson(Map<String, dynamic> json) {
    return EcfTestSetSendResult(
      sent: (json['sent'] as num?)?.toInt() ?? 0,
      more: (json['more'] as bool?) ?? false,
      stoppedReason: json['stopped_reason'] as String?,
      testSet: EcfTestSet.fromJson(_map(json['test_set']) ?? const {}),
    );
  }
}

/// Datos de la representación impresa (RI) de un e-CF ya firmado, armados
/// por el servidor con lo mismo que se firmó (Informe Técnico e-CF de la DGII,
/// sección 18). Los montos vienen como en el XML.
class EcfPrintModel {
  const EcfPrintModel({
    required this.typeCode,
    required this.typeName,
    required this.encf,
    required this.issuer,
    required this.items,
    required this.adjustments,
    required this.totals,
    required this.signedAt,
    required this.securityCode,
    required this.qrUrl,
    required this.consumerSummary,
    this.dueDate,
    this.modifiedEncf,
    this.modifiedDate,
    this.modification,
    this.modificationReason,
    this.buyer,
    this.currency,
  });

  final String typeCode;

  /// En palabras: "Factura de Crédito Fiscal Electrónica"…
  final String typeName;
  final String encf;
  final String? dueDate;
  final String? modifiedEncf;
  final String? modifiedDate;

  /// Código de modificación en palabras.
  final String? modification;
  final String? modificationReason;
  final EcfPrintIssuer issuer;
  final EcfPrintBuyer? buyer;
  final List<EcfPrintItem> items;
  final List<EcfPrintAdjustment> adjustments;
  final EcfPrintTotals totals;
  final EcfPrintCurrency? currency;

  /// Fecha de firma digital, dd-MM-yyyy HH:mm:ss.
  final String signedAt;
  final String securityCode;
  final String qrUrl;

  /// Factura de consumo menor de 250 mil (QR de consulta de consumo).
  final bool consumerSummary;

  factory EcfPrintModel.fromJson(Map<String, dynamic> json) {
    final buyer = _map(json['buyer']);
    final currency = _map(json['currency']);
    return EcfPrintModel(
      typeCode: (json['type_code'] as String?) ?? '',
      typeName: (json['type_name'] as String?) ?? '',
      encf: (json['encf'] as String?) ?? '',
      dueDate: json['due_date'] as String?,
      modifiedEncf: json['modified_encf'] as String?,
      modifiedDate: json['modified_date'] as String?,
      modification: json['modification'] as String?,
      modificationReason: json['modification_reason'] as String?,
      issuer: EcfPrintIssuer.fromJson(_map(json['issuer']) ?? const {}),
      buyer: buyer == null ? null : EcfPrintBuyer.fromJson(buyer),
      items: ((json['items'] as List?) ?? const [])
          .whereType<Map>()
          .map((e) => EcfPrintItem.fromJson(Map<String, dynamic>.from(e)))
          .toList(growable: false),
      adjustments: ((json['adjustments'] as List?) ?? const [])
          .whereType<Map>()
          .map((e) => EcfPrintAdjustment.fromJson(Map<String, dynamic>.from(e)))
          .toList(growable: false),
      totals: EcfPrintTotals.fromJson(_map(json['totals']) ?? const {}),
      currency: currency == null ? null : EcfPrintCurrency.fromJson(currency),
      signedAt: (json['signed_at'] as String?) ?? '',
      securityCode: (json['security_code'] as String?) ?? '',
      qrUrl: (json['qr_url'] as String?) ?? '',
      consumerSummary: (json['consumer_summary'] as bool?) ?? false,
    );
  }
}

class EcfPrintIssuer {
  const EcfPrintIssuer({
    required this.rnc,
    this.tradeName,
    this.legalName,
    this.branch,
    this.address,
    this.municipality,
    this.province,
    this.phone,
    this.email,
    this.issueDate,
  });

  final String rnc;
  final String? tradeName;
  final String? legalName;
  final String? branch;
  final String? address;

  /// En palabras (el XML lleva el código de la DGII).
  final String? municipality;
  final String? province;
  final String? phone;
  final String? email;
  final String? issueDate;

  factory EcfPrintIssuer.fromJson(Map<String, dynamic> json) {
    return EcfPrintIssuer(
      rnc: (json['rnc'] as String?) ?? '',
      tradeName: json['trade_name'] as String?,
      legalName: json['legal_name'] as String?,
      branch: json['branch'] as String?,
      address: json['address'] as String?,
      municipality: json['municipality'] as String?,
      province: json['province'] as String?,
      phone: json['phone'] as String?,
      email: json['email'] as String?,
      issueDate: json['issue_date'] as String?,
    );
  }
}

class EcfPrintBuyer {
  const EcfPrintBuyer({this.name, this.rnc, this.foreignId});

  final String? name;
  final String? rnc;
  final String? foreignId;

  factory EcfPrintBuyer.fromJson(Map<String, dynamic> json) {
    return EcfPrintBuyer(
      name: json['name'] as String?,
      rnc: json['rnc'] as String?,
      foreignId: json['foreign_id'] as String?,
    );
  }
}

class EcfPrintItem {
  const EcfPrintItem({
    required this.line,
    required this.exempt,
    required this.description,
    this.quantity,
    this.detail,
    this.unit,
    this.price,
    this.itbis,
    this.discount,
    this.surcharge,
    this.value,
  });

  final String line;

  /// La RI pone "E" delante de la descripción de lo exento.
  final bool exempt;
  final String description;
  final String? quantity;
  final String? detail;
  final String? unit;
  final String? price;
  final String? itbis;
  final String? discount;
  final String? surcharge;
  final String? value;

  factory EcfPrintItem.fromJson(Map<String, dynamic> json) {
    return EcfPrintItem(
      line: (json['line'] as String?) ?? '',
      exempt: (json['exempt'] as bool?) ?? false,
      description: (json['description'] as String?) ?? '',
      quantity: json['quantity'] as String?,
      detail: json['detail'] as String?,
      unit: json['unit'] as String?,
      price: json['price'] as String?,
      itbis: json['itbis'] as String?,
      discount: json['discount'] as String?,
      surcharge: json['surcharge'] as String?,
      value: json['value'] as String?,
    );
  }
}

class EcfPrintAdjustment {
  const EcfPrintAdjustment({
    required this.description,
    required this.kind,
    this.percent,
    this.amount,
  });

  final String description;

  /// `D` descuento, `R` recargo.
  final String kind;
  final String? percent;
  final String? amount;

  factory EcfPrintAdjustment.fromJson(Map<String, dynamic> json) {
    return EcfPrintAdjustment(
      description: (json['description'] as String?) ?? '',
      kind: (json['kind'] as String?) ?? '',
      percent: json['percent'] as String?,
      amount: json['amount'] as String?,
    );
  }
}

class EcfPrintTotals {
  const EcfPrintTotals({
    this.taxed,
    this.exempt,
    this.itbis,
    this.additionalTaxes,
    this.itbisWithheld,
    this.isrWithheld,
    this.total,
  });

  final String? taxed;
  final String? exempt;
  final String? itbis;
  final String? additionalTaxes;
  final String? itbisWithheld;
  final String? isrWithheld;
  final String? total;

  factory EcfPrintTotals.fromJson(Map<String, dynamic> json) {
    return EcfPrintTotals(
      taxed: json['taxed'] as String?,
      exempt: json['exempt'] as String?,
      itbis: json['itbis'] as String?,
      additionalTaxes: json['additional_taxes'] as String?,
      itbisWithheld: json['itbis_withheld'] as String?,
      isrWithheld: json['isr_withheld'] as String?,
      total: json['total'] as String?,
    );
  }
}

class EcfPrintCurrency {
  const EcfPrintCurrency({required this.code, this.rate, this.total});

  final String code;
  final String? rate;
  final String? total;

  factory EcfPrintCurrency.fromJson(Map<String, dynamic> json) {
    return EcfPrintCurrency(
      code: (json['code'] as String?) ?? '',
      rate: json['rate'] as String?,
      total: json['total'] as String?,
    );
  }
}

/// Lo que se copia en el formulario de postulación de la Oficina Virtual.
class EcfPostulationInfo {
  const EcfPostulationInfo({
    this.softwareType,
    this.softwareName,
    this.softwareVersion,
    this.providerRnc,
    this.providerName,
    this.providerTradeName,
    this.receptionUrl,
    this.approvalUrl,
    this.authenticationUrl,
    this.companyError,
  });

  final String? softwareType;
  final String? softwareName;
  final String? softwareVersion;
  final String? providerRnc;
  final String? providerName;
  final String? providerTradeName;
  final String? receptionUrl;
  final String? approvalUrl;
  final String? authenticationUrl;
  final String? companyError;

  factory EcfPostulationInfo.fromJson(Map<String, dynamic> json) {
    final provider = _map(json['provider']) ?? const {};
    final urls = _map(json['company_urls']);
    return EcfPostulationInfo(
      softwareType: provider['software_type'] as String?,
      softwareName: provider['software_name'] as String?,
      softwareVersion: provider['software_version'] as String?,
      providerRnc: provider['provider_rnc'] as String?,
      providerName: provider['provider_name'] as String?,
      providerTradeName: provider['provider_trade_name'] as String?,
      receptionUrl: urls?['reception'] as String?,
      approvalUrl: urls?['approval'] as String?,
      authenticationUrl: urls?['authentication'] as String?,
      companyError: json['company_error'] as String?,
    );
  }
}

Map<String, dynamic>? _map(Object? v) =>
    v is Map ? Map<String, dynamic>.from(v) : null;

bool _filled(String? v) => v != null && v.trim().isNotEmpty;

DateTime? _date(Object? v) {
  if (v is! String || v.isEmpty) return null;
  return DateTime.tryParse(v.replaceFirst(' ', 'T'));
}
