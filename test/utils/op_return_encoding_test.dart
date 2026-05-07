import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:deadbolt/utils/op_return_encoding.dart';

void main() {
  group('encodeOpReturnInput', () {
    test('encodes UTF-8 text including multi-byte runes', () {
      final out = encodeOpReturnInput('hola Ñ', hex: false);
      expect(out, Uint8List.fromList(utf8.encode('hola Ñ')));
    });

    test('returns empty buffer for empty UTF-8 input', () {
      expect(encodeOpReturnInput('', hex: false), isEmpty);
    });

    test('parses lowercase, uppercase and mixed-case hex', () {
      expect(encodeOpReturnInput('deadbeef', hex: true),
          Uint8List.fromList([0xde, 0xad, 0xbe, 0xef]));
      expect(encodeOpReturnInput('DEADBEEF', hex: true),
          Uint8List.fromList([0xde, 0xad, 0xbe, 0xef]));
      expect(encodeOpReturnInput('DeAdBeEf', hex: true),
          Uint8List.fromList([0xde, 0xad, 0xbe, 0xef]));
    });

    test('strips 0x / 0X prefix and inner whitespace', () {
      final expected = Uint8List.fromList([0xde, 0xad, 0xbe, 0xef]);
      expect(encodeOpReturnInput('0xdeadbeef', hex: true), expected);
      expect(encodeOpReturnInput('0XDEADBEEF', hex: true), expected);
      expect(encodeOpReturnInput('  de ad\tbe\nef ', hex: true), expected);
    });

    test('throws on odd-length hex string', () {
      expect(() => encodeOpReturnInput('abc', hex: true),
          throwsA(isA<FormatException>()));
    });

    test('throws on non-hex characters', () {
      expect(() => encodeOpReturnInput('zz', hex: true),
          throwsA(isA<FormatException>()));
    });

    test('empty hex returns empty buffer', () {
      expect(encodeOpReturnInput('', hex: true), isEmpty);
      expect(encodeOpReturnInput('0x', hex: true), isEmpty);
    });
  });

  group('looksLikePrintableUtf8', () {
    test('false for empty input', () {
      expect(looksLikePrintableUtf8(Uint8List(0)), isFalse);
    });

    test('true for ASCII text', () {
      expect(looksLikePrintableUtf8(Uint8List.fromList(utf8.encode('hello'))),
          isTrue);
    });

    test('true for multi-byte UTF-8', () {
      expect(looksLikePrintableUtf8(Uint8List.fromList(utf8.encode('こんにちは'))),
          isTrue);
    });

    test('allows tab/newline/carriage-return whitespace', () {
      expect(
          looksLikePrintableUtf8(Uint8List.fromList(utf8.encode('a\tb\nc\rd'))),
          isTrue);
    });

    test('false on control characters (e.g. NUL, BEL, DEL)', () {
      expect(looksLikePrintableUtf8(Uint8List.fromList([0x00])), isFalse);
      expect(looksLikePrintableUtf8(Uint8List.fromList([0x07])), isFalse);
      expect(looksLikePrintableUtf8(Uint8List.fromList([0x7F])), isFalse);
    });

    test('false on invalid UTF-8 sequences', () {
      // 0xC3 0x28 is an invalid two-byte sequence.
      expect(looksLikePrintableUtf8(Uint8List.fromList([0xC3, 0x28])), isFalse);
    });
  });

  group('decodeOpReturnDual', () {
    test('returns text and hex for printable UTF-8', () {
      final r = decodeOpReturnDual(Uint8List.fromList(utf8.encode('hola')));
      expect(r.text, 'hola');
      expect(r.hex, '0x686f6c61');
    });

    test('returns null text for non-printable bytes', () {
      final r = decodeOpReturnDual(Uint8List.fromList([0x00, 0x01, 0x02]));
      expect(r.text, isNull);
      expect(r.hex, '0x000102');
    });

    test('empty input yields empty text and bare 0x', () {
      final r = decodeOpReturnDual(Uint8List(0));
      expect(r.text, '');
      expect(r.hex, '0x');
    });
  });

  group('decodeOpReturnForDisplay', () {
    test('returns UTF-8 when printable', () {
      expect(
          decodeOpReturnForDisplay(Uint8List.fromList(utf8.encode('ok'))), 'ok');
    });

    test('falls back to hex when not printable', () {
      expect(decodeOpReturnForDisplay(Uint8List.fromList([0x00, 0x01, 0x02])),
          '0x000102');
    });

    test('returns empty string for empty input', () {
      expect(decodeOpReturnForDisplay(Uint8List(0)), '');
    });

    test('round-trips with encodeOpReturnInput in UTF-8 mode', () {
      const sample = 'donate to OP_RETURN ✨';
      final encoded = encodeOpReturnInput(sample, hex: false);
      expect(decodeOpReturnForDisplay(encoded), sample);
    });
  });
}
