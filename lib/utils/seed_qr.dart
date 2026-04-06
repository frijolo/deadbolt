import 'dart:typed_data';

import 'package:deadbolt/src/rust/api/wallet.dart' show bip39Wordlist;

/// Extracts [count] bits from [bytes] starting at bit position [startBit],
/// reading MSB-first within each byte (big-endian bit ordering).
int _extractBits(Uint8List bytes, int startBit, int count) {
  int result = 0;
  for (int i = 0; i < count; i++) {
    final pos = startBit + i;
    final bit = (bytes[pos >> 3] >> (7 - (pos & 7))) & 1;
    result = (result << 1) | bit;
  }
  return result;
}

// Valid BIP39 word counts and their corresponding SeedQR sizes.
// Standard: wordCount × 4 ASCII digits.
// Compact:  ceil(wordCount × 11 / 8) bytes.
const _validWordCounts = [12, 15, 18, 21, 24];

/// Decodes a standard SeedQR string (digit-only) to a BIP39 mnemonic.
///
/// Standard SeedQR encodes each word index as a zero-padded 4-digit decimal
/// number (0000–2047). Valid lengths: 48, 60, 72, 84, or 96 characters.
///
/// Returns the space-separated mnemonic, or null if [text] is not a valid
/// standard SeedQR.
String? decodeSeedQrText(String text) {
  final s = text.trim();
  if (!RegExp(r'^\d+$').hasMatch(s)) return null;

  int? wordCount;
  for (final wc in _validWordCounts) {
    if (s.length == wc * 4) {
      wordCount = wc;
      break;
    }
  }
  if (wordCount == null) return null;

  final wordlist = bip39Wordlist();
  final words = <String>[];
  for (int i = 0; i < wordCount; i++) {
    final idx = int.parse(s.substring(i * 4, i * 4 + 4));
    if (idx >= wordlist.length) return null;
    words.add(wordlist[idx]);
  }
  return words.join(' ');
}

/// Decodes a compact SeedQR payload (raw bytes) to a BIP39 mnemonic.
///
/// Compact SeedQR packs each 11-bit word index consecutively, MSB-first.
/// Valid byte lengths: 17, 21, 25, 29, or 33 (for 12, 15, 18, 21, 24 words).
///
/// Returns the space-separated mnemonic, or null if [bytes] is not a valid
/// compact SeedQR payload.
String? decodeSeedQrCompact(Uint8List bytes) {
  int? wordCount;
  for (final wc in _validWordCounts) {
    if (bytes.length == (wc * 11 + 7) ~/ 8) {
      wordCount = wc;
      break;
    }
  }
  if (wordCount == null) return null;

  final wordlist = bip39Wordlist();
  final words = <String>[];
  for (int i = 0; i < wordCount; i++) {
    final idx = _extractBits(bytes, i * 11, 11);
    if (idx >= wordlist.length) return null;
    words.add(wordlist[idx]);
  }
  return words.join(' ');
}
