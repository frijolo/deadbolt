import 'package:flutter_test/flutter_test.dart';
import 'package:deadbolt/errors.dart';

void main() {
  group('formatRustError', () {
    test('strips AnyhowException wrapper', () {
      final result =
          formatRustError('AnyhowException(Invalid descriptor format)');
      expect(result, 'Invalid descriptor format');
    });

    test('strips stack backtrace', () {
      final result = formatRustError(
          'Some error message\nStack backtrace:\n  0: foo\n  1: bar');
      expect(result, 'Some error message');
    });

    test('strips both wrapper and backtrace', () {
      final result = formatRustError(
          'AnyhowException(Parse failed\nStack backtrace:\n  0: ...)');
      expect(result, 'Parse failed');
    });

    test('handles real-world AnyhowException format', () {
      // Real Rust errors: the closing ) appears after the backtrace
      final result = formatRustError(
          'AnyhowException(Invalid descriptor\n\nStack backtrace:\n  0: core::panic\n)');
      expect(result, 'Invalid descriptor');
    });

    test('passes through plain errors unchanged', () {
      final result = formatRustError('Simple error');
      expect(result, 'Simple error');
    });

    test('trims whitespace', () {
      final result = formatRustError('  error with spaces  ');
      expect(result, 'error with spaces');
    });
  });

  group('sanitizeForLog', () {
    const xpub =
        'xpub661MyMwAqRbcFtXgS5sYJABqqG9YLmC1AEFVHtAeB7GHPR9T7R3vLXhNHGBBGNBhPfDpHfxGKbHtapCcVAPyVCTvEAHy8M8FP3FAYwmjKEP';
    const zpub =
        'zpub6rFR7y4Q2AijBEqTUquhVz398htDFrtymD9xYYfG1m4wAcvPhXNfE3EfH1r1ADqtfSdVCToUG868RvUUkgDKf31mGDtKsAYz2oz2AGutZYs';
    const bech32Addr = 'bc1qw508d6qejxtdg4y5r3zarvary0c5xw7kv8f3t4';
    const tb1Addr    = 'tb1qw508d6qejxtdg4y5r3zarvary0c5xw7kxpjzsx';

    test('redacts xpub from error message', () {
      final result = sanitizeForLog('Failed to parse $xpub: invalid checksum');
      expect(result, contains('[REDACTED]'));
      expect(result, isNot(contains('xpub6')));
    });

    test('redacts zpub from error message', () {
      final result = sanitizeForLog('Descriptor contains $zpub which is unknown');
      expect(result, contains('[REDACTED]'));
      expect(result, isNot(contains('zpub6')));
    });

    test('redacts mainnet bech32 address', () {
      final result = sanitizeForLog('UTXO at $bech32Addr is spent');
      expect(result, contains('[REDACTED]'));
      expect(result, isNot(contains('bc1q')));
    });

    test('redacts testnet bech32 address', () {
      final result = sanitizeForLog('Address $tb1Addr not found');
      expect(result, contains('[REDACTED]'));
      expect(result, isNot(contains('tb1q')));
    });

    test('leaves benign messages unchanged', () {
      const msg = 'Wallet sync failed: connection refused';
      expect(sanitizeForLog(msg), msg);
    });

    test('redacts multiple occurrences in one string', () {
      final result = sanitizeForLog('$xpub and $bech32Addr');
      expect(result, isNot(contains('xpub6')));
      expect(result, isNot(contains('bc1q')));
      expect(result.split('[REDACTED]').length - 1, greaterThanOrEqualTo(2));
    });
  });
}
