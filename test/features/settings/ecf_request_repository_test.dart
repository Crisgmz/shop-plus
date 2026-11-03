import 'package:flutter_app/features/settings/data/ecf_request_repository.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show FunctionException;

void main() {
  group('etapa de la solicitud', () {
    test('lee cada etapa que manda el servidor', () {
      for (final stage in EcfRequestStage.values) {
        expect(EcfRequestStage.parse(stage.name), stage);
      }
    });

    test('una etapa desconocida no rompe la pantalla', () {
      // El servidor puede agregar etapas antes de que se actualice la app.
      expect(EcfRequestStage.parse('etapa_nueva'), EcfRequestStage.none);
      expect(EcfRequestStage.parse(null), EcfRequestStage.none);
    });
  });

  group('respuesta de request_status', () {
    test('arma el estado completo', () {
      final status = EcfRequestStatus.fromJson({
        'stage': 'sequences',
        'requested_at': '2026-09-20T14:05:00Z',
        'contact_name': 'Hailerin',
        'contact_phone': '8295059592',
        'already_authorized': true,
        'mode': 'physical',
        'environment': 'production',
        'certification_status': 'certified',
        'alanube_company_id': '01J8ABC',
        'data': {'rnc': '131974602', 'legal_name': 'PRUEBA SRL'},
        'branches': [
          {'id': 'b1', 'name': 'Principal'},
        ],
        'sequences': [
          {
            'id': 's1',
            'branch_id': 'b1',
            'ncf_type': 'E31',
            'current_number': 40,
            'range_end': 100,
            'expiration_date': '2026-12-31',
            'is_active': true,
          },
        ],
      });

      expect(status.stage, EcfRequestStage.sequences);
      expect(status.requestedAt?.year, 2026);
      expect(status.alreadyAuthorized, isTrue);
      expect(status.electronicEnabled, isFalse);
      expect(status.data.rnc, '131974602');
      expect(status.branches.single.name, 'Principal');
      // Lo que la tarjeta muestra: cuánto le queda a la secuencia.
      expect(status.sequences.single.remaining, 60);
    });

    test('una respuesta mínima cae en los valores por defecto', () {
      final status = EcfRequestStatus.fromJson({'stage': 'none'});

      expect(status.stage, EcfRequestStage.none);
      expect(status.mode, 'physical');
      expect(status.branches, isEmpty);
      expect(status.sequences, isEmpty);
      expect(status.data.rnc, isNull);
      expect(status.requestedAt, isNull);
      expect(status.details.branches, isEmpty);
      expect(status.details.ecfTypes, isEmpty);
    });

    test('lee los requisitos que precargan el formulario', () {
      final status = EcfRequestStatus.fromJson({
        'stage': 'none',
        'details': {
          'phone': '8095550000',
          'legal_rep_name': 'Ana Pérez',
          'branches': [
            {'name': 'Principal', 'address': 'Calle Central 17B'},
            'basura que no es un mapa',
          ],
          'ecf_types': ['E31', 'E32'],
          'ofv_user': '131974602',
        },
      });

      expect(status.details.phone, '8095550000');
      expect(status.details.legalRepName, 'Ana Pérez');
      expect(status.details.branches.single.address, 'Calle Central 17B');
      expect(status.details.ecfTypes, ['E31', 'E32']);
      expect(status.details.ofvUser, '131974602');
    });

    test('modo híbrido cuenta como electrónica encendida', () {
      // 'hybrid' es e-CF con respaldo en papel: la venta no se cae si el
      // proveedor no responde.
      expect(
        EcfRequestStatus.fromJson({'stage': 'active', 'mode': 'hybrid'})
            .electronicEnabled,
        isTrue,
      );
    });
  });

  group('errores de la función', () {
    String describe(int status, Object? details) =>
        EcfRequestRepository.describeFunctionError(
          FunctionException(status: status, details: details),
        ).message;

    test('sin publicar en el Supabase propio no sale el mensaje genérico', () {
      // Lo que responde el router `main` de supabase.busiposweb.com cuando la
      // carpeta de la función no existe (28 oct 2026).
      expect(
        describe(500, {
          'msg': 'InvalidWorkerCreation: worker boot error: failed to '
              'bootstrap runtime: could not find an appropriate entrypoint',
        }),
        'El servidor todavía no tiene esta función disponible.',
      );
      expect(
        describe(404, {'message': ''}),
        'El servidor todavía no tiene esta función disponible.',
      );
    });

    test('el mensaje propio de la función manda', () {
      expect(
        describe(409, {'error': 'rnc_mismatch', 'message': 'El RNC no es.'}),
        'El RNC no es.',
      );
      expect(
        describe(422, {
          'message': 'x',
          'detail': ['Falta el RNC.', 'Falta el correo.'],
        }),
        'Falta el RNC. Falta el correo.',
      );
    });

    test('otro error del router sigue siendo genérico', () {
      expect(
        describe(401, {'msg': 'Invalid JWT'}),
        'No se pudo completar la solicitud. Intenta de nuevo.',
      );
    });
  });

  group('lo que se manda al servidor', () {
    test('la secuencia viaja con los nombres que espera la función', () {
      const submission = EcfSequenceSubmission(
        branchId: 'b1',
        ncfType: 'E31',
        rangeStart: 1,
        rangeEnd: 1000,
        expirationDate: '2026-12-31',
        authorizationNumber: 'AUT-9',
        lastUsed: 40,
      );

      expect(submission.toJson(), {
        'ncf_type': 'E31',
        'range_start': 1,
        'range_end': 1000,
        'expiration_date': '2026-12-31',
        'authorization_number': 'AUT-9',
        'last_used': 40,
      });
    });

    test('los datos del contribuyente van con las llaves de la DGII', () {
      const data = EcfRequestData(
        rnc: '131974602',
        legalName: 'PRUEBA SRL',
        tradeName: 'Prueba',
        fiscalAddress: 'Calle Central 17B',
        province: 'Santo Domingo',
        municipality: 'Santo Domingo Norte',
        email: 'a@b.com',
      );

      expect(data.toJson().keys, [
        'rnc',
        'legal_name',
        'trade_name',
        'fiscal_address',
        'province',
        'municipality',
        'email',
      ]);
    });

    test('los requisitos viajan sin clave de la Oficina Virtual', () {
      // La certificación es manual: la clave se pide aparte, nunca por aquí.
      const details = EcfRequestDetails(
        phone: '8095550000',
        legalRepName: 'Ana Pérez',
        branches: [EcfRequestBranch(name: 'Principal', address: 'Calle 1')],
        ecfTypes: ['E32'],
        ofvUser: '131974602',
      );

      expect(details.toJson(), {
        'phone': '8095550000',
        'legal_rep_name': 'Ana Pérez',
        'branches': [
          {'name': 'Principal', 'address': 'Calle 1'},
        ],
        'ecf_types': ['E32'],
        'ofv_user': '131974602',
      });
    });
  });
}
