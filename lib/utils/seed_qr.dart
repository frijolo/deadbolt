import 'dart:typed_data';

import 'package:deadbolt/src/rust/api/wallet.dart'
    show bip39Wordlist, bip39EntropyToMnemonic;

// Lazy cache; avoids repeated FFI round-trips for the full 2048-word list.
// Initialized on first use, which always occurs after RustLib.init().
List<String>? _wordlistCache;
List<String> get _wordlist => _wordlistCache ??= bip39Wordlist();

// Valid BIP39 word counts and their corresponding SeedQR sizes.
// Standard: wordCount × 4 ASCII digits.
// Compact:  wordCount × 4 / 3 entropy bytes (no checksum, per SeedSigner/Krux spec).
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

  final wordlist = _wordlist;
  final words = <String>[];
  for (int i = 0; i < wordCount; i++) {
    final idx = int.parse(s.substring(i * 4, i * 4 + 4));
    if (idx >= wordlist.length) return null;
    words.add(wordlist[idx]);
  }
  return words.join(' ');
}

/// Decodes a compact SeedQR payload (raw entropy bytes) to a BIP39 mnemonic.
///
/// Compact SeedQR stores only the raw entropy bits (no checksum).
/// Valid byte lengths: 16, 20, 24, 28, or 32 (for 12, 15, 18, 21, 24 words).
///
/// Returns the space-separated mnemonic, or null if [bytes] is not a valid
/// compact SeedQR payload.
String? decodeSeedQrCompact(Uint8List bytes) {
  // Entropy-only sizes per word count (wordCount * 4 / 3).
  const validEntropySizes = {16, 20, 24, 28, 32};
  if (!validEntropySizes.contains(bytes.length)) return null;

  try {
    return bip39EntropyToMnemonic(entropy: bytes);
  } catch (_) {
    return null;
  }
}

/// Encodes a BIP39 mnemonic to a standard SeedQR string.
///
/// Each word index is zero-padded to 4 decimal digits and concatenated.
/// 12 words → 48 chars, 24 words → 96 chars.
/// Scan the resulting string as a numeric QR code with error correction L.
String encodeSeedQrStandard(String mnemonic) {
  final wordlist = _wordlist;
  return mnemonic.trim().split(' ').map((w) {
    final idx = wordlist.indexOf(w);
    assert(idx >= 0, 'Word not in BIP39 wordlist: $w');
    return idx.toString().padLeft(4, '0');
  }).join();
}

/// Encodes a BIP39 mnemonic to a compact SeedQR byte payload.
///
/// Only the raw entropy bits are stored (checksum is dropped), matching the
/// SeedSigner/Krux compact SeedQR specification.
/// 12 words → 16 bytes, 24 words → 32 bytes.
/// The caller must encode these bytes in binary (byte) QR mode with error
/// correction L to produce a valid compact SeedQR.
Uint8List encodeSeedQrCompact(String mnemonic) {
  final wordlist = _wordlist;
  final words = mnemonic.trim().split(' ');
  // Pack all word indices (including checksum bits) into a temp buffer.
  final totalBits = words.length * 11;
  final temp = Uint8List((totalBits + 7) ~/ 8);
  for (int i = 0; i < words.length; i++) {
    final idx = wordlist.indexOf(words[i]);
    assert(idx >= 0, 'Word not in BIP39 wordlist: ${words[i]}');
    _writeBits(temp, i * 11, 11, idx);
  }
  // Return only the entropy bytes; the trailing checksum bits are discarded.
  final entropyBytes = words.length * 4 ~/ 3;
  return Uint8List.sublistView(temp, 0, entropyBytes);
}

/// Writes [count] bits of [value] into [bytes] starting at bit position
/// [startBit], MSB-first (big-endian bit ordering).
void _writeBits(Uint8List bytes, int startBit, int count, int value) {
  for (int i = 0; i < count; i++) {
    final pos = startBit + i;
    final byteIdx = pos >> 3;
    final bitIdx = 7 - (pos & 7);
    if ((value >> (count - 1 - i)) & 1 == 1) {
      bytes[byteIdx] |= 1 << bitIdx;
    }
  }
}
