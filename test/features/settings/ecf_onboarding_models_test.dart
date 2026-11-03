// Trámite e-CF paso a paso (Configuración → Facturación electrónica).
//
// Portado de las pruebas del panel de MangoPOS (ecf_onboarding_test,
// ecf_certificate_test, ecf_ofv_access_test). Lo que protege: que el paso que
// marca la página sea el real, que una secuencia que la DGII va a rechazar no
// cuente como lista, que el set de pruebas decida bien qué se puede hacer, y
// que ningún secreto (certificado, clave OFV) viaje de vuelta en save_data.

import 'package:flutter_app/features/settings/data/ecf_onboarding_models.dart';
import 'package:flutter_app/features/settings/data/ecf_request_repository.dart';
import 'package:flutter_test/flutter_test.dart';

Map<String, dynamic> _status({
  Map<String, dynamic>? onboarding,
  Map<String, dynamic>? settings,
  List<Map<String, dynamic>> sequences = const [],
  String stage = 'none',
}) => {
  'stage': stage,
  'onboarding': onboarding,
  'settings': settings,
  'company': null,
  'company_error': null,
  'sequences': sequences,
  'branches': [
    {'id': 'b1', 'name': 'Principal'},
  ],
  'environment': 'production',
};

const _data = {
  'rnc': '132941519',
  'legal_name': 'MARANATHA DE TODO PARA PISCINAS SRL',
  'fiscal_address': 'AV. PRINCIPAL 1',
  'requested_at': '2026-10-30T15:00:00Z',
};

Map<String, dynamic> _seq(
  String type, {
  int end = 1000,
  int current = 0,
  String? exp,
  bool active = true,
}) => {
  'id': 's-$type',
  'branch_id': 'b1',
  'ncf_type': type,
  'current_number': current,
  'range_end': end,
  'expiration_date': exp,
  'is_active': active,
};

void main() {
  group('paso actual', () {
    test('sin solicitud: paso 1', () {
      expect(EcfOnboardingStatus.fromJson(_status()).currentStep, 1);
    });

    test('pedida pero sin empresa con el proveedor: paso 2', () {
      final s = EcfOnboardingStatus.fromJson(
        _status(onboarding: _data, stage: 'company'),
      );
      expect(s.currentStep, 2);
    });

    test('empresa registrada, sin autorización DGII: paso 3', () {
      final s = EcfOnboardingStatus.fromJson(
        _status(
          onboarding: {..._data, 'alanube_company_id': '01M1'},
          settings: {'alanube_company_id': '01M1', 'mode': 'physical'},
          stage: 'certification',
        ),
      );
      expect(s.isCertified, isFalse);
      expect(s.currentStep, 3);
    });

    test('registrada en settings pero no en el borrador: no pide empresa', () {
      final s = EcfOnboardingStatus.fromJson(
        _status(
          onboarding: _data,
          settings: {'alanube_company_id': '01M1', 'mode': 'physical'},
        ),
      );
      expect(s.companyId, '01M1');
      expect(s.currentStep, 3);
    });

    test('marcada como autorizada, sin secuencias: paso 4', () {
      final s = EcfOnboardingStatus.fromJson(
        _status(
          onboarding: {
            ..._data,
            'alanube_company_id': '01M1',
            'dgii_authorized_at': '2026-10-31T15:00:00Z',
          },
        ),
      );
      expect(s.isCertified, isTrue);
      expect(s.currentStep, 4);
    });

    test('declaró que ya era emisor: cuenta como autorizada', () {
      final s = EcfOnboardingStatus.fromJson(
        _status(
          onboarding: {
            ..._data,
            'alanube_company_id': '01M1',
            'already_authorized': true,
          },
        ),
      );
      expect(s.isCertified, isTrue);
      expect(s.currentStep, 4);
    });

    test('con secuencia usable: paso 5', () {
      final s = EcfOnboardingStatus.fromJson(
        _status(
          onboarding: {..._data, 'alanube_company_id': '01M1'},
          sequences: [_seq('E32')],
        ),
      );
      expect(s.isCertified, isTrue);
      expect(s.currentStep, 5);
    });

    test('encendida: listo', () {
      final s = EcfOnboardingStatus.fromJson(
        _status(
          onboarding: {..._data, 'alanube_company_id': '01M1'},
          settings: {'alanube_company_id': '01M1', 'mode': 'hybrid'},
          sequences: [_seq('E32')],
          stage: 'active',
        ),
      );
      expect(s.ecfEnabled, isTrue);
      expect(s.stage, EcfRequestStage.active);
      expect(s.currentStep, 6);
    });

    test('modo physical no cuenta como encendida', () {
      final s = EcfOnboardingStatus.fromJson(
        _status(
          onboarding: {..._data, 'alanube_company_id': '01M1'},
          settings: {'alanube_company_id': '01M1', 'mode': 'physical'},
          sequences: [_seq('E32')],
        ),
      );
      expect(s.ecfEnabled, isFalse);
      expect(s.currentStep, 5);
    });
  });

  group('secuencias', () {
    test('E31 sin vencimiento no sirve (DGII 145)', () {
      final q = EcfSequence.fromJson(_seq('E31', end: 100));
      expect(q.missingExpiration, isTrue);
      expect(q.isUsable, isFalse);
    });

    test('E32 sin vencimiento sí sirve', () {
      expect(EcfSequence.fromJson(_seq('E32')).isUsable, isTrue);
    });

    test('agotada no sirve', () {
      final q = EcfSequence.fromJson(_seq('E32', end: 100, current: 100));
      expect(q.isUsable, isFalse);
    });

    test('vencida no sirve', () {
      final q = EcfSequence.fromJson(_seq('E31', exp: '2020-01-01'));
      expect(q.isExpired, isTrue);
      expect(q.isUsable, isFalse);
    });

    test('inactiva no sirve', () {
      expect(
        EcfSequence.fromJson(_seq('E32', active: false)).isUsable,
        isFalse,
      );
    });

    test('solo con E31 inválida no cuenta como lista', () {
      final s = EcfOnboardingStatus.fromJson(
        _status(
          onboarding: {
            ..._data,
            'alanube_company_id': '01M1',
            'dgii_authorized_at': '2026-10-31T15:00:00Z',
          },
          sequences: [_seq('E31', end: 100)],
        ),
      );
      expect(s.currentStep, 4);
    });
  });

  group('empresa con el proveedor', () {
    test('fecha del proveedor con espacio se parsea', () {
      final c = EcfCompany.fromJson({
        'id': '01M1',
        'certificate': {'name': 'FIRMA', 'end_date': '2027-04-23 21:30:54'},
        'webhooks_ok': true,
      });
      expect(c.certificateEndDate, DateTime(2027, 4, 23, 21, 30, 54));
      expect(c.hasCertificate, isTrue);
      expect(c.webhooksOk, isTrue);
    });
  });

  group('secretos', () {
    test('el estado solo lee los metadatos del certificado', () {
      final status = EcfOnboardingStatus.fromJson({
        'onboarding': {
          'certificate_filename': 'empresa.p12',
          'certificate_updated_at': '2026-10-27T18:00:00Z',
          'certificate_enc': 'v1:secreto-que-no-se-expone',
        },
      });
      expect(status.draft?.hasCertificate, isTrue);
      expect(status.draft?.certificateFilename, 'empresa.p12');
      expect(
        status.draft?.certificateUpdatedAt,
        DateTime.utc(2026, 10, 27, 18),
      );
      expect(status.draft!.toJson().keys, isNot(contains('certificate_enc')));
    });

    test('sin fecha o sin nombre no anuncia certificado', () {
      for (final row in <Map<String, dynamic>>[
        {},
        {'certificate_filename': 'empresa.p12'},
        {
          'certificate_filename': '',
          'certificate_updated_at': '2026-10-27T18:00:00Z',
        },
      ]) {
        expect(EcfTaxpayerDraft.fromJson(row).hasCertificate, isFalse);
      }
    });

    test('lee el usuario OFV y sabe si hay clave guardada', () {
      final draft = EcfTaxpayerDraft.fromJson({
        'ofv_user': 'usuario-prueba',
        'ofv_password_updated_at': '2026-10-27T18:00:00Z',
      });
      expect(draft.ofvUser, 'usuario-prueba');
      expect(draft.hasOfvPassword, isTrue);
      expect(EcfTaxpayerDraft.fromJson({'rnc': '1'}).hasOfvPassword, isFalse);
    });

    test('save_data no reenvía credenciales ni el certificado', () {
      final draft = EcfTaxpayerDraft.fromJson({
        'rnc': '132941519',
        'legal_name': 'EMPRESA DE PRUEBA',
        'ofv_user': 'usuario-prueba',
        'ofv_password_updated_at': '2026-10-27T18:00:00Z',
        'ofv_password': 'clave-prueba',
        'ofv_password_enc': 'v1:cifrado-prueba',
        'certificate_filename': 'empresa.p12',
      });
      expect(draft.toJson(), {
        'rnc': '132941519',
        'legal_name': 'EMPRESA DE PRUEBA',
        'trade_name': null,
        'fiscal_address': null,
        'province': null,
        'municipality': null,
        'email': null,
      });
    });

    test('la solicitud solo manda la clave OFV si se escribió', () {
      expect(
        const EcfRequestDetails(ofvUser: 'u').toJson(),
        isNot(contains('ofv_password')),
      );
      expect(
        const EcfRequestDetails(ofvUser: 'u', ofvPassword: '').toJson(),
        isNot(contains('ofv_password')),
      );
      expect(
        const EcfRequestDetails(ofvUser: 'u', ofvPassword: 'x').toJson(),
        containsPair('ofv_password', 'x'),
      );
      expect(
        EcfRequestDetails.fromJson({
          'ofv_password_saved': true,
        }).ofvPasswordSaved,
        isTrue,
      );
    });
  });

  group('certificación', () {
    Map<String, dynamic> testCase(
      String encf,
      String status, {
      String via = 'ecf',
      num? total,
      String? modifies,
      List<Map<String, dynamic>> messages = const [],
    }) => {
      'id': 'c-$encf',
      'position': 1,
      'case_id': '132941519$encf',
      'ecf_type': encf.substring(1, 3),
      'encf': encf,
      'total': total,
      'via': via,
      'modifies': modifies,
      'status': status,
      'messages': messages,
    };

    EcfTestSet testSet(List<Map<String, dynamic>> cases) {
      final s = EcfOnboardingStatus.fromJson({
        ..._status(onboarding: {..._data, 'alanube_company_id': '01M1'}),
        'test_set': {
          'filename': '132941519-08102026121048.xlsx',
          'loaded_at': '2026-10-08T16:10:48Z',
          'session_expires_at': '2026-10-08T17:10:48Z',
          'cases': cases,
        },
      });
      return s.testSet!;
    }

    test('cuenta estados y decide qué se puede hacer', () {
      final t = testSet([
        testCase('E310000000001', 'accepted', total: 1180),
        testCase('E320000000011', 'conditional', via: 'rfce', total: 40120),
        testCase('E320000000005', 'sent', total: 2282785.36),
        testCase('E340000000001', 'pending', modifies: 'E310000000001'),
        testCase(
          'E330000000001',
          'error',
          messages: [
            {'code': '400', 'message': 'Monto invalido'},
          ],
        ),
      ]);
      expect(t.filename, '132941519-08102026121048.xlsx');
      expect(t.sessionExpiresAt, isNotNull);
      expect(t.accepted, 2);
      expect(t.inProcess, 1);
      expect(t.toSend, 2);
      expect(t.summaries, 1);
      expect(t.canSend, isTrue);
      expect(t.canCheck, isTrue);
      expect(t.isComplete, isFalse);
      expect(t.failed.single.messages.single.message, 'Monto invalido');
      expect(t.cases[1].isSummary, isTrue);
      expect(t.cases[1].simulationCategory, '32rfce');
      expect(t.cases[2].simulationCategory, '32');
      expect(t.cases[1].hasXml, isTrue);
      expect(t.cases[3].hasXml, isFalse);
      expect(t.cases[2].total, 2282785.36);
    });

    test('un rechazo bloquea el envío hasta cargar otro set', () {
      final t = testSet([
        testCase('E310000000001', 'rejected'),
        testCase('E340000000001', 'pending'),
      ]);
      expect(t.rejected.single.statusLabel, 'Rechazado');
      expect(t.canSend, isFalse);
    });

    test('todo aceptado (con o sin observaciones) completa el set', () {
      final t = testSet([
        testCase('E310000000001', 'accepted'),
        testCase('E320000000011', 'conditional', via: 'rfce'),
      ]);
      expect(t.isComplete, isTrue);
      expect(t.canSend, isFalse);
      expect(t.canCheck, isFalse);
    });

    test('aprobaciones comerciales llegan aparte del set de e-CF', () {
      final s = EcfOnboardingStatus.fromJson({
        ..._status(onboarding: {..._data, 'alanube_company_id': '01M1'}),
        'test_set': null,
        'approval_set': {
          'kind': 'acecf',
          'filename': '132941519-09102026121152.xlsx',
          'cases': [
            testCase('E310000000001', 'accepted', via: 'acecf', total: 7080),
          ],
        },
      });
      expect(s.testSet, isNull);
      final a = s.approvalSet!;
      expect(a.isApprovals, isTrue);
      expect(a.cases.single.isApproval, isTrue);
      expect(a.isComplete, isTrue);
      expect(a.summaries, 0);
    });

    test('lote de envío: sigue mientras el servidor diga more', () {
      final r = EcfTestSetSendResult.fromJson({
        'sent': 3,
        'more': true,
        'stopped_reason': null,
        'test_set': {'cases': []},
      });
      expect(r.sent, 3);
      expect(r.more, isTrue);
      expect(r.testSet.isEmpty, isTrue);
    });

    test('datos de postulación', () {
      final info = EcfPostulationInfo.fromJson({
        'provider': {
          'software_type': 'EXTERNO',
          'software_name': 'Alanube',
          'software_version': '1',
          'provider_rnc': '132109122',
        },
        'company_urls': {
          'reception': 'https://r',
          'approval': 'https://a',
          'authentication': 'https://t',
        },
      });
      expect(info.providerRnc, '132109122');
      expect(info.authenticationUrl, 'https://t');
    });

    test('XML firmado: con o sin el archivo descargado por el servidor', () {
      final withXml = EcfSignedDocument.fromJson(EcfSignKind.postulation, {
        'signed_document_url': 'https://alanube/x.xml',
        'signed_xml_base64': 'PHhtbC8+',
        'signed_filename': 'postulacion-firmada.xml',
      });
      expect(withXml.xmlBase64, 'PHhtbC8+');
      expect(withXml.filename, 'postulacion-firmada.xml');

      final onlyUrl = EcfSignedDocument.fromJson(EcfSignKind.roles, {
        'signed_document_url': 'https://alanube/y.xml',
        'signed_xml_base64': null,
      });
      expect(onlyUrl.xmlBase64, isNull);
      expect(onlyUrl.url, 'https://alanube/y.xml');
    });
  });
}
