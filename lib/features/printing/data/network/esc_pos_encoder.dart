import 'dart:typed_data';

/// Alineación horizontal para comandos ESC/POS (`ESC a n`).
enum PosAlign { left, center, right }

/// Codificador ESC/POS minimalista y autocontenido (sin dependencias externas
/// ni `dart:io`), pensado para impresoras térmicas de 80mm que aceptan el
/// estándar Epson ESC/POS por puerto crudo TCP (típicamente 9100).
///
/// Solo genera bytes — el transporte (socket TCP / USB) es responsabilidad de
/// otra capa, por lo que este archivo compila también en Web.
///
/// El texto se codifica a la página de códigos **CP850** (Latin-1 / Multilingüe)
/// que cubre los acentos del español dominicano (á é í ó ú ñ ¿ ¡ …). Los
/// caracteres fuera del mapa se reemplazan por `?`.
class EscPosEncoder {
  EscPosEncoder({this.columns = 48});

  /// Ancho del papel en caracteres con la fuente A.
  /// 80mm ≈ 48 columnas, 58mm ≈ 32 columnas.
  final int columns;

  final BytesBuilder _buffer = BytesBuilder();

  // ── Comandos base ──────────────────────────────────────────────────────────

  /// Inicializa la impresora y selecciona la tabla de caracteres CP850.
  EscPosEncoder reset() {
    _buffer.add(const [0x1B, 0x40]); // ESC @  → init
    _buffer.add(const [0x1B, 0x74, 0x02]); // ESC t 2 → code page CP850
    return this;
  }

  /// `ESC a n` — alineación.
  EscPosEncoder align(PosAlign a) {
    _buffer.add([0x1B, 0x61, a.index]);
    return this;
  }

  /// `ESC E n` — negrita (énfasis).
  EscPosEncoder bold(bool on) {
    _buffer.add([0x1B, 0x45, on ? 1 : 0]);
    return this;
  }

  /// `GS ! n` — multiplicador de tamaño. Cada eje admite x1 (false) o x2 (true).
  EscPosEncoder size({bool doubleWidth = false, bool doubleHeight = false}) {
    final n = (doubleWidth ? 0x10 : 0) | (doubleHeight ? 0x01 : 0);
    _buffer.add([0x1D, 0x21, n]);
    return this;
  }

  /// `ESC - n` — subrayado.
  EscPosEncoder underline(bool on) {
    _buffer.add([0x1B, 0x2D, on ? 1 : 0]);
    return this;
  }

  /// Escribe texto + salto de línea (codificado a CP850).
  EscPosEncoder text(String value) {
    _buffer.add(_encode(value));
    _buffer.add(const [0x0A]); // LF
    return this;
  }

  /// Escribe texto sin salto de línea.
  EscPosEncoder raw(String value) {
    _buffer.add(_encode(value));
    return this;
  }

  /// Avanza `n` líneas en blanco.
  EscPosEncoder feed([int n = 1]) {
    if (n <= 0) return this;
    _buffer.add([0x1B, 0x64, n.clamp(0, 255)]); // ESC d n
    return this;
  }

  /// Línea de guiones de ancho completo.
  EscPosEncoder divider([String char = '-']) {
    return text(char * columns);
  }

  /// Dos columnas justificadas a los extremos en el ancho del papel.
  /// Si la suma excede el ancho, recorta la izquierda.
  EscPosEncoder twoColumns(String left, String right) {
    final maxLeft = columns - right.length - 1;
    var l = left;
    if (l.length > maxLeft && maxLeft > 0) {
      l = l.substring(0, maxLeft);
    }
    final gap = columns - l.length - right.length;
    return text('$l${' ' * (gap < 1 ? 1 : gap)}$right');
  }

  /// Texto envuelto en múltiples líneas respetando el ancho de columna.
  EscPosEncoder wrapped(String value) {
    for (final line in _wrap(value, columns)) {
      text(line);
    }
    return this;
  }

  /// `GS V` — corte de papel (parcial por defecto, deja una pestaña).
  EscPosEncoder cut({bool partial = true}) {
    feed(3);
    _buffer.add([0x1D, 0x56, partial ? 0x42 : 0x00, 0x00]);
    return this;
  }

  /// `ESC p` — pulso para abrir la gaveta de efectivo (pin 2 por defecto).
  EscPosEncoder openCashDrawer({int pin = 0}) {
    _buffer.add([0x1B, 0x70, pin == 0 ? 0 : 1, 0x19, 0xFA]);
    return this;
  }

  /// Bytes acumulados listos para enviar al transporte.
  Uint8List bytes() => _buffer.toBytes();

  // ── Helpers ────────────────────────────────────────────────────────────────

  static List<String> _wrap(String value, int width) {
    final result = <String>[];
    for (final paragraph in value.split('\n')) {
      if (paragraph.isEmpty) {
        result.add('');
        continue;
      }
      var line = '';
      for (final word in paragraph.split(' ')) {
        if (line.isEmpty) {
          line = word;
        } else if (line.length + 1 + word.length <= width) {
          line = '$line $word';
        } else {
          result.add(line);
          line = word;
        }
        // Palabra individual más larga que el ancho: trocearla.
        while (line.length > width) {
          result.add(line.substring(0, width));
          line = line.substring(width);
        }
      }
      result.add(line);
    }
    return result;
  }

  static Uint8List _encode(String value) {
    final out = Uint8List(value.length);
    for (var i = 0; i < value.length; i++) {
      final code = value.codeUnitAt(i);
      if (code < 0x80) {
        out[i] = code;
      } else {
        out[i] = _cp850[code] ?? 0x3F; // '?'
      }
    }
    return out;
  }

  /// Subconjunto Unicode → CP850 cubriendo el español y símbolos comunes.
  static const Map<int, int> _cp850 = {
    0x00C7: 0x80, // Ç
    0x00FC: 0x81, // ü
    0x00E9: 0x82, // é
    0x00E2: 0x83, // â
    0x00E4: 0x84, // ä
    0x00E0: 0x85, // à
    0x00E7: 0x87, // ç
    0x00EA: 0x88, // ê
    0x00EB: 0x89, // ë
    0x00E8: 0x8A, // è
    0x00EF: 0x8B, // ï
    0x00EE: 0x8C, // î
    0x00C9: 0x90, // É
    0x00F4: 0x93, // ô
    0x00F6: 0x94, // ö
    0x00FB: 0x96, // û
    0x00F9: 0x97, // ù
    0x00D6: 0x99, // Ö
    0x00DC: 0x9A, // Ü
    0x00A3: 0x9C, // £
    0x00E1: 0xA0, // á
    0x00ED: 0xA1, // í
    0x00F3: 0xA2, // ó
    0x00FA: 0xA3, // ú
    0x00F1: 0xA4, // ñ
    0x00D1: 0xA5, // Ñ
    0x00AA: 0xA6, // ª
    0x00BA: 0xA7, // º
    0x00BF: 0xA8, // ¿
    0x00AE: 0xA9, // ®
    0x00AC: 0xAA, // ¬
    0x00A1: 0xAD, // ¡
    0x00AB: 0xAE, // «
    0x00BB: 0xAF, // »
    0x00C1: 0xB5, // Á
    0x00C2: 0xB6, // Â
    0x00C0: 0xB7, // À
    0x00A9: 0xB8, // ©
    0x00A2: 0xBD, // ¢
    0x00E3: 0xC6, // ã
    0x00C3: 0xC7, // Ã
    0x00F0: 0xD0, // ð
    0x00CD: 0xD6, // Í
    0x00CE: 0xD7, // Î
    0x00CF: 0xD8, // Ï
    0x00CC: 0xDE, // Ì
    0x00D3: 0xE0, // Ó
    0x00DF: 0xE1, // ß
    0x00D4: 0xE2, // Ô
    0x00D2: 0xE3, // Ò
    0x00F5: 0xE4, // õ
    0x00D5: 0xE5, // Õ
    0x00B5: 0xE6, // µ
    0x00DA: 0xE9, // Ú
    0x00DB: 0xEA, // Û
    0x00D9: 0xEB, // Ù
    0x00FD: 0xEC, // ý
    0x00DD: 0xED, // Ý
    0x00B0: 0xF8, // °
    0x00B7: 0xFA, // ·
    0x00B2: 0xFD, // ²
    0x20AC: 0x3F, // € (no existe en CP850 → '?')
  };
}
