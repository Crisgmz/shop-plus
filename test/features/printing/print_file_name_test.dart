import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_app/features/printing/data/print_file_name.dart';
import 'package:flutter_app/features/printing/data/printing_models.dart';

/// Documento mínimo: solo importan tipo, número, contraparte y NCF.
PrintDocumentData _doc({
  required PrintDocumentType tipo,
  required String numero,
  String? contraparte,
  String? ncf,
}) =>
    PrintDocumentData(
      documentType: tipo,
      documentNumber: numero,
      issuedAt: DateTime(2026, 9, 16),
      branch: const PrintBranchIdentity(name: 'Shop+', taxId: '131000000'),
      customer: contraparte == null ? null : PrintParty(name: contraparte),
      ncf: ncf,
      items: const [
        PrintDocumentItem(
          description: 'Producto A',
          quantity: 1,
          unitPrice: 100,
          lineSubtotal: 100,
          lineTax: 18,
          lineTotal: 118,
        ),
      ],
      totals: const PrintTotals(subtotal: 100, tax: 18, total: 118),
    );

void main() {
  group('nombre del PDF · cómo se arma', () {
    test('cliente y terminal del comprobante', () {
      expect(
        buildPrintFileName(
          documentNumber: '000123',
          clientName: 'Juan Pérez',
          ncf: 'B0100000123',
        ),
        'Juan Pérez - 00000123',
      );
    });

    test('del NCF se queda con el secuencial, sin la serie', () {
      // El "01" de B01 son dígitos que NO pertenecen al secuencial.
      expect(
        buildPrintFileName(
          documentNumber: '000123',
          clientName: 'Colmado La Esquina',
          ncf: 'B0100000001',
        ),
        'Colmado La Esquina - 00000001',
      );
    });

    test('da igual cómo venga escrito el NCF', () {
      for (final ncf in ['B01-00000123', ' B01 00000123 ', 'b0100000123']) {
        expect(
          buildPrintFileName(
              documentNumber: '000123', clientName: 'Ana', ncf: ncf),
          'Ana - 00000123',
          reason: 'falló con "\$ncf"',
        );
      }
    });

    test('venta sin comprobante cae al número de venta', () {
      expect(
        buildPrintFileName(
            documentNumber: '000123', clientName: 'Ana', ncf: null),
        'Ana - 000123',
      );
      expect(
        buildPrintFileName(
            documentNumber: '000123', clientName: 'Ana', ncf: '  '),
        'Ana - 000123',
      );
    });

    test('sin contraparte se queda solo con el comprobante', () {
      expect(
        buildPrintFileName(documentNumber: '000123', ncf: 'B0100000123'),
        '00000123',
      );
    });

    test('no deja caracteres que el sistema operativo rechaza', () {
      final nombre = buildPrintFileName(
        documentNumber: '000123',
        clientName: 'Repuestos A/B: "El Rayo" <SRL>',
        ncf: 'B0100000123',
      );
      expect(nombre, isNot(matches(r'[\\/:*?"<>|]')));
      expect(nombre, endsWith('- 00000123'));
    });

    test('un nombre larguísimo se recorta pero el comprobante sobrevive', () {
      final nombre = buildPrintFileName(
        documentNumber: '000123',
        clientName: 'A' * 200,
        ncf: 'B0100000123',
      );
      expect(nombre, endsWith(' - 00000123'));
      expect(nombre.length, lessThan(70));
    });

    test('el conduce se distingue de la factura', () {
      expect(
        buildPrintFileName(
          documentNumber: '000123',
          clientName: 'Ana',
          ncf: 'B0100000123',
          withConduce: true,
        ),
        'Ana - 00000123-con-conduce',
      );
    });

    test('nunca devuelve vacío', () {
      expect(buildPrintFileName(documentNumber: ''), 'Documento');
    });
  });

  group('nombre del PDF · según el tipo de documento', () {
    test('factura con cliente', () {
      expect(
        printDocumentFileName(_doc(
          tipo: PrintDocumentType.fiscalInvoice,
          numero: '000123',
          contraparte: 'Juan Pérez',
          ncf: 'B0100000123',
        )),
        'Juan Pérez - 00000123',
      );
    });

    test('venta sin cliente ES a consumidor final', () {
      expect(
        printDocumentFileName(_doc(
          tipo: PrintDocumentType.saleReceipt,
          numero: '000123',
          ncf: 'B0200000077',
        )),
        'Consumidor Final - 00000077',
      );
    });

    test('una compra sin proveedor NO es un consumidor final', () {
      // Ahí falta un dato; inventarle "Consumidor Final" sería mentir.
      expect(
        printDocumentFileName(_doc(
          tipo: PrintDocumentType.purchaseOrder,
          numero: 'OC-000045',
        )),
        'OC-000045',
      );
    });

    test('una compra con proveedor lleva su nombre', () {
      expect(
        printDocumentFileName(_doc(
          tipo: PrintDocumentType.purchaseOrder,
          numero: 'OC-000045',
          contraparte: 'Distribuidora del Cibao',
        )),
        'Distribuidora del Cibao - OC-000045',
      );
    });

    test('una cotización sin cliente se queda con su código', () {
      expect(
        printDocumentFileName(_doc(
          tipo: PrintDocumentType.quote,
          numero: 'COT-000012',
        )),
        'COT-000012',
      );
    });
  });
}
