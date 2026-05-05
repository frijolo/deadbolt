import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';

import 'package:deadbolt/services/wallet_service.dart';

class _FakePathProvider extends PathProviderPlatform with MockPlatformInterfaceMixin {
  String supportPath;
  _FakePathProvider(this.supportPath);

  @override
  Future<String?> getApplicationSupportPath() async => supportPath;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;
  late WalletService service;
  late _FakePathProvider fakeProvider;

  void mockPathProvider(String supportPath) {
    fakeProvider.supportPath = supportPath;
  }

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('wallet_service_test_');
    fakeProvider = _FakePathProvider(tempDir.path);
    PathProviderPlatform.instance = fakeProvider;
    service = WalletService();
  });

  tearDown(() async {
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  group('CredentialCache - password', () {
    const path1 = '/wallets/a.db';
    const path2 = '/wallets/b.db';

    test('miss returns null', () {
      expect(service.getCachedPassword(path1), isNull);
      expect(service.isUnlocked(path1), isFalse);
    });

    test('hit returns stored password and isUnlocked true', () {
      service.cachePassword(path1, 'secret');
      expect(service.getCachedPassword(path1), 'secret');
      expect(service.isUnlocked(path1), isTrue);
    });

    test('caching the same path overwrites previous value', () {
      service.cachePassword(path1, 'first');
      service.cachePassword(path1, 'second');
      expect(service.getCachedPassword(path1), 'second');
    });

    test('evict by path removes only that entry', () {
      service.cachePassword(path1, 'p1');
      service.cachePassword(path2, 'p2');
      service.evictPassword(path1);
      expect(service.getCachedPassword(path1), isNull);
      expect(service.getCachedPassword(path2), 'p2');
      expect(service.isUnlocked(path1), isFalse);
      expect(service.isUnlocked(path2), isTrue);
    });

    test('evict on missing path is a no-op', () {
      expect(() => service.evictPassword('/nope'), returnsNormally);
    });

    test('clearAllCredentials wipes every entry', () {
      service.cachePassword(path1, 'p1');
      service.cachePassword(path2, 'p2');
      service.clearAllCredentials();
      expect(service.getCachedPassword(path1), isNull);
      expect(service.getCachedPassword(path2), isNull);
      expect(service.isUnlocked(path1), isFalse);
      expect(service.isUnlocked(path2), isFalse);
    });
  });

  group('CredentialCache - biometric key', () {
    const path1 = '/wallets/bio.db';
    final keyHex = 'a' * 64;
    final altKeyHex = '0123456789abcdef' * 4;

    test('miss returns null', () {
      expect(service.getCachedBiometricKey(path1), isNull);
      expect(service.isUnlocked(path1), isFalse);
    });

    test('round-trips hex through binary storage', () {
      service.cacheBiometricKey(path1, keyHex);
      expect(service.getCachedBiometricKey(path1), keyHex);
      expect(service.isUnlocked(path1), isTrue);
    });

    test('caching the same path overwrites previous value', () {
      service.cacheBiometricKey(path1, keyHex);
      service.cacheBiometricKey(path1, altKeyHex);
      expect(service.getCachedBiometricKey(path1), altKeyHex);
    });

    test('evict by path removes only that entry', () {
      service.cacheBiometricKey(path1, keyHex);
      service.cacheBiometricKey('/wallets/other.db', altKeyHex);
      service.evictBiometricKey(path1);
      expect(service.getCachedBiometricKey(path1), isNull);
      expect(service.getCachedBiometricKey('/wallets/other.db'), altKeyHex);
    });

    test('isUnlocked returns true when only biometric key is cached', () {
      service.cacheBiometricKey(path1, keyHex);
      expect(service.getCachedPassword(path1), isNull);
      expect(service.isUnlocked(path1), isTrue);
    });

    test('clearAllCredentials wipes biometric entries too', () {
      service.cachePassword('/wallets/pw.db', 'pw');
      service.cacheBiometricKey(path1, keyHex);
      service.clearAllCredentials();
      expect(service.getCachedBiometricKey(path1), isNull);
      expect(service.isUnlocked(path1), isFalse);
    });
  });

  group('EncryptionKeyManager - getOrCreateEncryptionKey', () {
    test('generates a 64-char hex key on first call and persists it', () async {
      final key = await service.getOrCreateEncryptionKey();
      expect(key.length, 64);
      expect(RegExp(r'^[0-9a-f]{64}$').hasMatch(key), isTrue);

      final keyFile = File(p.join(tempDir.path, '.wallet_key'));
      expect(await keyFile.exists(), isTrue);
      expect((await keyFile.readAsString()).trim(), key);
    });

    test('subsequent calls return the same persisted key', () async {
      final first = await service.getOrCreateEncryptionKey();
      final second = await service.getOrCreateEncryptionKey();
      final third = await WalletService().getOrCreateEncryptionKey();
      expect(second, first);
      expect(third, first);
    });

    test('regenerates the key when the on-disk value is malformed', () async {
      final keyFile = File(p.join(tempDir.path, '.wallet_key'));
      await keyFile.writeAsString('not-a-valid-key');
      final key = await service.getOrCreateEncryptionKey();
      expect(key.length, 64);
      expect(RegExp(r'^[0-9a-f]{64}$').hasMatch(key), isTrue);
      expect((await keyFile.readAsString()).trim(), key);
    });

    test('two services produce different keys when storage is independent',
        () async {
      final keyA = await service.getOrCreateEncryptionKey();

      final otherDir =
          await Directory.systemTemp.createTemp('wallet_service_test_alt_');
      mockPathProvider(otherDir.path);
      final keyB = await WalletService().getOrCreateEncryptionKey();

      expect(keyA.length, 64);
      expect(keyB.length, 64);
      expect(keyA, isNot(keyB));

      await otherDir.delete(recursive: true);
    });
  });

  group('directory helpers', () {
    test('getAppSupportDir returns the configured support path', () async {
      expect(await service.getAppSupportDir(), tempDir.path);
    });

    test('getWalletsDir creates the wallets subdirectory', () async {
      final walletsDir = await service.getWalletsDir();
      expect(walletsDir, p.join(tempDir.path, 'wallets'));
      expect(await Directory(walletsDir).exists(), isTrue);
    });
  });
}
