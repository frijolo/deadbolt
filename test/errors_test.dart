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
}
