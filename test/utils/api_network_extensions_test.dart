import 'package:flutter_test/flutter_test.dart';
import 'package:deadbolt/src/rust/api/model.dart';
import 'package:deadbolt/utils/api_network_extensions.dart';

void main() {
  group('APINetworkX.isMainnet', () {
    test('returns true only for bitcoin', () {
      expect(APINetwork.bitcoin.isMainnet, isTrue);
      expect(APINetwork.testnet.isMainnet, isFalse);
      expect(APINetwork.testnet4.isMainnet, isFalse);
      expect(APINetwork.signet.isMainnet, isFalse);
      expect(APINetwork.regtest.isMainnet, isFalse);
    });
  });

  group('APINetworkX.coinType', () {
    test("returns '0' for mainnet, '1' for everything else", () {
      expect(APINetwork.bitcoin.coinType, '0');
      expect(APINetwork.testnet.coinType, '1');
      expect(APINetwork.testnet4.coinType, '1');
      expect(APINetwork.signet.coinType, '1');
      expect(APINetwork.regtest.coinType, '1');
    });
  });

  group('APINetworkX.suffix', () {
    test('returns the capitalized network suffix', () {
      expect(APINetwork.bitcoin.suffix, 'Mainnet');
      expect(APINetwork.testnet.suffix, 'Testnet');
      expect(APINetwork.testnet4.suffix, 'Testnet4');
      expect(APINetwork.signet.suffix, 'Signet');
      expect(APINetwork.regtest.suffix, 'Regtest');
    });
  });

  group('apiNetworkFromName', () {
    test('returns the matching enum value', () {
      expect(apiNetworkFromName('bitcoin'), APINetwork.bitcoin);
      expect(apiNetworkFromName('testnet'), APINetwork.testnet);
      expect(apiNetworkFromName('signet'), APINetwork.signet);
    });

    test('returns null for null input', () {
      expect(apiNetworkFromName(null), isNull);
    });

    test('returns null for unknown name (no throw)', () {
      expect(apiNetworkFromName('mainnet'), isNull);
      expect(apiNetworkFromName(''), isNull);
      expect(apiNetworkFromName('garbage'), isNull);
    });
  });
}
