import 'dart:convert';
import 'dart:typed_data';

import 'ecf_onboarding_models.dart';
import 'ecf_request_repository.dart';

/// El trámite de facturación electrónica paso a paso (Configuración →
/// Facturación electrónica): datos, certificado, Oficina Virtual,
/// certificación ante la DGII (postulación, set de pruebas, aprobaciones
/// comerciales, simulación, declaración jurada) y la marca de autorizado.
///
/// Portado del panel de MangoPOS
/// (`mangopos_administrador/lib/data/repositories/ecf_onboarding_repository.dart`).
/// Todo va a la misma Edge Function `ecf-onboarding` que la solicitud, por
/// [EcfRequestRepository.invoke]: misma empresa actual y mismos errores. Aquí
/// NO hay buscar, vincular ni dar de alta una empresa del proveedor: un
/// cliente no se puede enganchar a una empresa ajena; su alta la hace la
/// solicitud.
class EcfOnboardingRepository {
  EcfOnboardingRepository(this._requests);

  final EcfRequestRepository _requests;

  Future<Map<String, dynamic>> _call(
    String action, [
    Map<String, dynamic> params = const {},
  ]) => _requests.invoke({'action': action, ...params});

  Future<EcfOnboardingStatus> status() async {
    return EcfOnboardingStatus.fromJson(await _call('status'));
  }

  Future<void> saveData(EcfTaxpayerDraft draft) async {
    await _call('save_data', {'data': draft.toJson()});
  }

  /// Guarda o reemplaza el certificado cifrado con el que se firman las
  /// pruebas. El servidor exige el consentimiento explícito.
  Future<void> saveCertificate({
    required String filename,
    required Uint8List bytes,
    required String password,
  }) async {
    await _call('save_certificate', {
      'certificate': certificatePayload(filename, bytes, password),
      'accept_certificate_storage': true,
    });
  }

  /// Guarda o cambia el acceso a la Oficina Virtual (la clave, cifrada).
  Future<void> saveOfvCredentials({
    required String ofvUser,
    required String ofvPassword,
  }) async {
    await _call('save_ofv_credentials', {
      'ofv_user': ofvUser,
      'ofv_password': ofvPassword,
    });
  }

  /// Consulta auditada. La clave no viene en el estado y no se guarda en
  /// ningún provider.
  Future<EcfOfvCredentials> revealOfvPassword() async {
    final data = await _call('reveal_ofv_password');
    final password = data['ofv_password'];
    if (password is! String || password.isEmpty) {
      throw const EcfRequestException(
        'El servidor no devolvió la contraseña de la Oficina Virtual.',
      );
    }
    return EcfOfvCredentials(
      ofvUser: data['ofv_user'] as String?,
      ofvPassword: password,
    );
  }

  Future<EcfPostulationInfo> postulationInfo() async {
    return EcfPostulationInfo.fromJson(await _call('postulation_info'));
  }

  /// El proveedor firma el XML con el certificado que tiene de la empresa.
  /// Lo firmado se sube a la Oficina Virtual.
  Future<EcfSignedDocument> signDocument({
    required EcfSignKind kind,
    required String filename,
    required Uint8List bytes,
  }) async {
    final data = await _call('sign_document', {
      'kind': kind.code,
      'xml': {'filename': filename, 'content_base64': base64Encode(bytes)},
    });
    final signed = EcfSignedDocument.fromJson(kind, data);
    if (signed.url == null && signed.xmlBase64 == null) {
      throw const EcfRequestException(
        'El servidor no devolvió el XML firmado.',
      );
    }
    return signed;
  }

  /// Carga un Excel de la DGII (.xlsx, o una hoja en .csv): el de pruebas de
  /// datos e-CF ([setKind] `ecf`) o el de aprobaciones comerciales (`acecf`).
  /// Reemplaza el que hubiera de ese tipo; si el archivo es del otro, falla
  /// con `wrong_test_set`.
  Future<EcfTestSet> importTestSet({
    required String setKind,
    required String filename,
    required Uint8List bytes,
  }) async {
    final data = await _call('import_test_set', {
      'set_kind': setKind,
      'file': {'filename': filename, 'content_base64': base64Encode(bytes)},
    });
    return EcfTestSet.fromJson(_asMap(data['test_set']));
  }

  /// Un lote del envío a la DGII. Sin certificado explícito se firma con el
  /// guardado; si responde `more`, hay que volver a llamar.
  Future<EcfTestSetSendResult> sendTestSet({
    required String setKind,
    String? certificateFilename,
    Uint8List? certificateBytes,
    String? certificatePassword,
  }) async {
    final data = await _call('send_test_set', {
      'set_kind': setKind,
      'certificate': ?_optionalCertificate(
        certificateFilename,
        certificateBytes,
        certificatePassword,
      ),
    });
    return EcfTestSetSendResult.fromJson(data);
  }

  /// Paso 4 del portal: arma los e-CF de la simulación en las cantidades que
  /// pide el portal ({'31': 1, '32': 1, '32rfce': 1, …}). Volver a generar
  /// usa e-NCF nuevos.
  Future<EcfTestSet> generateSimulationSet({
    required Map<String, int> counts,
  }) async {
    final data = await _call('generate_simulation_set', {'counts': counts});
    return EcfTestSet.fromJson(_asMap(data['test_set']));
  }

  /// Consulta los envíos en proceso de un set (`ecf` o `sim`). Sin
  /// certificado usa la sesión con la DGII del último envío; si venció, la
  /// renueva con el certificado guardado, cuando existe.
  Future<EcfTestSet> checkTestSet({
    String setKind = 'ecf',
    String? certificateFilename,
    Uint8List? certificateBytes,
    String? certificatePassword,
  }) async {
    final data = await _call('check_test_set', {
      'set_kind': setKind,
      'certificate': ?_optionalCertificate(
        certificateFilename,
        certificateBytes,
        certificatePassword,
      ),
    });
    return EcfTestSet.fromJson(_asMap(data['test_set']));
  }

  /// XML firmado de un caso, como se mandó a la DGII, y los datos de su
  /// representación impresa (null en las aprobaciones comerciales).
  Future<({String filename, String xml, EcfPrintModel? print})> testCaseXml(
    String caseId,
  ) async {
    final data = await _call('test_case_xml', {'case_id': caseId});
    final xml = data['xml'];
    if (xml is! String || xml.isEmpty) {
      throw const EcfRequestException('El servidor no devolvió el XML.');
    }
    final print = data['print'];
    return (
      filename: (data['filename'] as String?) ?? '$caseId.xml',
      xml: xml,
      print: print is Map
          ? EcfPrintModel.fromJson(Map<String, dynamic>.from(print))
          : null,
    );
  }

  Future<void> setDgiiAuthorized(bool authorized) async {
    await _call('set_dgii_authorized', {'authorized': authorized});
  }

  static Map<String, dynamic> _asMap(Object? data) {
    if (data is Map) return Map<String, dynamic>.from(data);
    throw const EcfRequestException('Respuesta inesperada del servidor.');
  }

  /// Archivo + contraseña como los espera el servidor.
  static Map<String, dynamic> certificatePayload(
    String filename,
    Uint8List bytes,
    String password,
  ) {
    if (filename.isEmpty || bytes.isEmpty || password.isEmpty) {
      throw const EcfRequestException(
        'Elige el certificado e indica su contraseña.',
      );
    }
    return {
      'filename': filename,
      'content_base64': base64Encode(bytes),
      'password': password,
    };
  }

  /// Null = usar el certificado guardado en el servidor.
  static Map<String, dynamic>? _optionalCertificate(
    String? filename,
    Uint8List? bytes,
    String? password,
  ) {
    if (filename == null && bytes == null && password == null) return null;
    return certificatePayload(
      filename ?? '',
      bytes ?? Uint8List(0),
      password ?? '',
    );
  }
}
