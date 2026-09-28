import 'package:flutter_app/features/settings/data/settings_repository.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('próximo NCF al guardar la secuencia', () {
    test('sigue al último emitido', () {
      expect(nextNcfNumber(currentNumber: 250), 251);
    });

    test('nunca baja del inicio del rango autorizado', () {
      // Secuencia nueva autorizada desde el 300: el primero es el 300.
      expect(nextNcfNumber(currentNumber: 0, sequenceStart: 300), 300);
      // Ya emitió dentro del rango: sigue por donde va.
      expect(nextNcfNumber(currentNumber: 320, sequenceStart: 300), 321);
    });

    test('sin rango arranca en 1', () {
      expect(nextNcfNumber(currentNumber: 0), 1);
      expect(nextNcfNumber(currentNumber: 0, sequenceStart: 0), 1);
    });

    test('el caso de Soplasora: corregir "Número actual" sí cambia el NCF', () {
      // Estaba pegada en B0100000002 y el negocio va por el 45.
      expect(nextNcfNumber(currentNumber: 45), 46);
    });
  });
}
