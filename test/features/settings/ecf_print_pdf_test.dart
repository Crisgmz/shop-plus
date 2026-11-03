// La representación impresa de las pruebas de simulación se arma sin romperse
// con lo que manda el servidor (una sola página y con paginación) y el modelo
// lee bien sus datos. Portado del panel de MangoPOS (ecf_print_pdf_test).

import 'package:flutter_app/features/settings/data/ecf_onboarding_models.dart';
import 'package:flutter_app/features/settings/data/ecf_print_pdf.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pdf/widgets.dart' as pw;

Map<String, dynamic> _model({int items = 2}) => {
  'type_code': '34',
  'type_name': 'Nota de Crédito Electrónica',
  'encf': 'E340000000020',
  'due_date': null,
  'modified_encf': 'E310000000013',
  'modified_date': '09-10-2026',
  'modification': 'Corrige Texto del Comprobante Fiscal modificado',
  'modification_reason': 'Error en datos',
  'issuer': {
    'rnc': '132941519',
    'trade_name': 'Maranatha',
    'legal_name': 'MARANATHA DE TODO PARA PISCINAS SRL',
    'address': 'AV. PRINCIPAL 1',
    'municipality': 'SANTO DOMINGO ESTE',
    'province': 'SANTO DOMINGO',
    'issue_date': '09-10-2026',
  },
  'buyer': {'name': 'DOCUMENTOS ELECTRONICOS DE 03', 'rnc': '131880681'},
  'items': [
    for (var i = 1; i <= items; i++)
      {
        'line': '$i',
        'quantity': '1.00',
        'exempt': i.isEven,
        'description': 'Ítem $i',
        'unit': 'Unidad',
        'price': '100.0000',
        'itbis': i.isEven ? null : '18.00',
        'value': '100.00',
      },
  ],
  'adjustments': [
    {
      'description': 'Descuento por volumen',
      'kind': 'D',
      'percent': '10',
      'amount': '20.00',
    },
  ],
  'totals': {
    'taxed': '100.00',
    'exempt': '100.00',
    'itbis': '18.00',
    'total': '218.00',
  },
  'currency': {'code': 'USD', 'rate': '58.50', 'total': '3.73'},
  'signed_at': '09-10-2026 13:01:26',
  'security_code': 'bjV/1u',
  'qr_url':
      'https://ecf.dgii.gov.do/certecf/ConsultaTimbre?RncEmisor=132941519&ENCF=E340000000020',
  'consumer_summary': false,
};

void main() {
  test('modelo: lee emisor, cliente, detalle y QR', () {
    final m = EcfPrintModel.fromJson(_model());
    expect(m.typeName, 'Nota de Crédito Electrónica');
    expect(m.issuer.municipality, 'SANTO DOMINGO ESTE');
    expect(m.buyer!.rnc, '131880681');
    expect(m.items[1].exempt, isTrue);
    expect(m.items[0].itbis, '18.00');
    expect(m.adjustments.single.percent, '10');
    expect(m.currency!.code, 'USD');
    expect(m.securityCode, 'bjV/1u');
    expect(
      m.qrUrl,
      startsWith('https://ecf.dgii.gov.do/certecf/ConsultaTimbre'),
    );
  });

  test('PDF de una página y con paginación', () async {
    final font = pw.Font.helvetica();
    final bold = pw.Font.helveticaBold();
    final one = await buildEcfPrintPdf(
      EcfPrintModel.fromJson(_model()),
      font: font,
      boldFont: bold,
    );
    expect(String.fromCharCodes(one.take(5)), '%PDF-');
    final many = await buildEcfPrintPdf(
      EcfPrintModel.fromJson(_model(items: 120)),
      font: font,
      boldFont: bold,
    );
    expect(many.length, greaterThan(one.length));
  });
}
