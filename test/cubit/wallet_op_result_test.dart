import 'package:flutter_test/flutter_test.dart';

import 'package:deadbolt/cubit/wallet_op_result.dart';

void main() {
  group('guardAsync', () {
    test('wraps a successful future in Ok', () async {
      final result = await guardAsync<int>(() async => 42);
      expect(result, isA<Ok<int>>());
      expect((result as Ok<int>).value, 42);
    });

    test('wraps a thrown error in Err with formatted message', () async {
      final result = await guardAsync<int>(
        () async => throw Exception('boom'),
        tag: 'unitTest',
      );
      expect(result, isA<Err<int>>());
      expect((result as Err<int>).message, contains('unitTest'));
      expect(result.message, contains('boom'));
    });
  });

  group('guardSync', () {
    test('wraps a successful body in Ok', () {
      final result = guardSync<String>(() => 'hello');
      expect(result, isA<Ok<String>>());
      expect((result as Ok<String>).value, 'hello');
    });

    test('wraps a thrown error in Err', () {
      final result = guardSync<int>(() => throw StateError('bad'));
      expect(result, isA<Err<int>>());
      expect((result as Err<int>).message, contains('bad'));
    });
  });
}
