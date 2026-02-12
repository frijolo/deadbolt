import 'package:flutter_test/flutter_test.dart';
import 'package:deadbolt/utils/enum_formatters.dart';

void main() {
  group('Enum formatters', () {
    test('networkDisplayName formats Bitcoin correctly', () {
      expect(networkDisplayName('bitcoin'), 'Mainnet');
      expect(networkDisplayName('testnet'), 'Testnet');
      expect(networkDisplayName('signet'), 'Signet');
      expect(networkDisplayName('regtest'), 'Regtest');
    });

    test('networkDisplayName handles unknown networks', () {
      expect(networkDisplayName('unknown'), 'unknown');
      expect(networkDisplayName(''), '');
    });
  });
}
