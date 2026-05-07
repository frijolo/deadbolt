import 'dart:convert';
import 'dart:typed_data';

import 'package:deadbolt/utils/hex_utils.dart';

/// Encode a user-typed OP_RETURN payload into raw bytes.
///
/// When [hex] is true, [input] is interpreted as a hex string (whitespace and
/// a leading "0x" are stripped). Otherwise it is encoded as UTF-8.
///
/// Throws [FormatException] when hex parsing fails.
Uint8List encodeOpReturnInput(String input, {required bool hex}) {
  if (hex) {
    var s = input.trim().replaceAll(RegExp(r'\s+'), '');
    if (s.startsWith('0x') || s.startsWith('0X')) s = s.substring(2);
    if (s.length.isOdd) {
      throw const FormatException('Hex string must have an even number of characters');
    }
    final out = Uint8List(s.length ~/ 2);
    for (var i = 0; i < out.length; i++) {
      final byte = int.tryParse(s.substring(i * 2, i * 2 + 2), radix: 16);
      if (byte == null) {
        throw FormatException('Invalid hex byte at position ${i * 2}');
      }
      out[i] = byte;
    }
    return out;
  }
  return Uint8List.fromList(utf8.encode(input));
}

/// Decode raw OP_RETURN bytes for display: returns UTF-8 if it round-trips and
/// every codepoint is printable; otherwise returns `0x...hex`.
String decodeOpReturnForDisplay(Uint8List data) {
  final decoded = decodeOpReturnDual(data);
  return decoded.text ?? decoded.hex;
}

/// Decode raw OP_RETURN bytes into both representations at once.
///
/// `text` is non-null only when the bytes round-trip as printable UTF-8. `hex`
/// is always present and prefixed with `0x` (or `0x` alone for empty input).
/// Use this when callers need both forms (e.g. a "copy as text / copy as hex"
/// chooser); use [decodeOpReturnForDisplay] when only the display form matters.
({String? text, String hex}) decodeOpReturnDual(Uint8List data) {
  final hex = '0x${bytesToHex(data)}';
  if (data.isEmpty) return (text: '', hex: hex);
  if (!looksLikePrintableUtf8(data)) return (text: null, hex: hex);
  return (text: utf8.decode(data), hex: hex);
}

/// True when [data] decodes as valid UTF-8 and contains only printable
/// codepoints (Unicode general-category L/N/P/S/Zs plus common whitespace).
/// Control characters other than \t/\n/\r make it return false.
bool looksLikePrintableUtf8(Uint8List data) {
  if (data.isEmpty) return false;
  final String decoded;
  try {
    decoded = utf8.decode(data, allowMalformed: false);
  } on FormatException {
    return false;
  }
  for (final rune in decoded.runes) {
    if (rune == 0x09 || rune == 0x0A || rune == 0x0D) continue;
    if (rune < 0x20) return false;
    if (rune == 0x7F) return false; // DEL
  }
  return true;
}
