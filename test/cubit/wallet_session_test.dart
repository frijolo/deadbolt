import 'package:biometric_storage/biometric_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import 'package:deadbolt/cubit/wallet_session.dart';
import 'package:deadbolt/services/biometric_keystore_service.dart';
import 'package:deadbolt/services/wallet_service.dart';
import 'package:deadbolt/src/rust/api/model.dart' show APIBiometricSlot;
import 'package:deadbolt/src/rust/api/wallet.dart' show ApiWallet;

class MockWalletService extends Mock implements WalletService {}

class MockBiometricKeystoreService extends Mock
    implements BiometricKeystoreService {}

class MockApiWallet extends Mock implements ApiWallet {}

class _FakePromptInfo extends Fake implements PromptInfo {}

void main() {
  setUpAll(() {
    registerFallbackValue(_FakePromptInfo());
  });

  late MockWalletService service;
  late MockBiometricKeystoreService keystore;
  late WalletSession session;

  const walletPath = '/wallets/w.db';

  setUp(() {
    service = MockWalletService();
    keystore = MockBiometricKeystoreService();
    session = WalletSession(service: service, keystoreService: keystore);

    // Default void stubs.
    when(() => service.cachePassword(any(), any())).thenAnswer((_) {});
    when(() => service.cacheBiometricKey(any(), any())).thenAnswer((_) {});
    when(() => service.evictPassword(any())).thenAnswer((_) {});
    when(() => service.evictBiometricKey(any())).thenAnswer((_) {});
  });

  group('loadCredential', () {
    test('uses cached credential and opens wallet without checking password '
        'requirement', () async {
      final handle = MockApiWallet();
      when(() => service.isUnlocked(walletPath)).thenReturn(true);
      when(() => service.openWallet(walletPath))
          .thenAnswer((_) async => handle);

      final result = await session.loadCredential(walletPath: walletPath);

      expect(result.handle, same(handle));
      expect(result.needsPassword, isFalse);
      verifyNever(() => service.walletRequiresPassword(any()));
      verifyNever(() => service.walletRequiresXpub(any()));
    });

    test('caches provided password before opening', () async {
      final handle = MockApiWallet();
      when(() => service.isUnlocked(walletPath)).thenReturn(true);
      when(() => service.openWallet(walletPath))
          .thenAnswer((_) async => handle);

      await session.loadCredential(walletPath: walletPath, password: 'secret');

      verify(() => service.cachePassword(walletPath, 'secret')).called(1);
    });

    test('opens with device key when wallet does not need password', () async {
      final handle = MockApiWallet();
      when(() => service.isUnlocked(walletPath)).thenReturn(false);
      when(() => service.walletRequiresPassword(walletPath))
          .thenAnswer((_) async => false);
      when(() => service.walletRequiresXpub(walletPath))
          .thenAnswer((_) async => false);
      when(() => service.openWallet(walletPath))
          .thenAnswer((_) async => handle);

      final result = await session.loadCredential(walletPath: walletPath);

      expect(result.handle, same(handle));
      expect(result.needsPassword, isFalse);
    });

    test('returns needsPassword when no credential cached and no biometric '
        'reason given', () async {
      when(() => service.isUnlocked(walletPath)).thenReturn(false);
      when(() => service.walletRequiresPassword(walletPath))
          .thenAnswer((_) async => true);
      when(() => service.walletRequiresXpub(walletPath))
          .thenAnswer((_) async => false);

      final result = await session.loadCredential(walletPath: walletPath);

      expect(result.handle, isNull);
      expect(result.needsPassword, isTrue);
      expect(result.isXpubKey, isFalse);
      verifyNever(() => keystore.isAvailable());
      verifyNever(() => service.openWallet(any()));
    });

    test('propagates Rust errors from openWallet (e.g. wrong password)',
        () async {
      when(() => service.isUnlocked(walletPath)).thenReturn(true);
      when(() => service.openWallet(walletPath))
          .thenThrow(Exception('decryption failed'));

      expect(
        () => session.loadCredential(
          walletPath: walletPath,
          password: 'bad',
        ),
        throwsA(isA<Exception>()),
      );
    });

    group('biometric unlock path', () {
      setUp(() {
        when(() => service.isUnlocked(walletPath)).thenReturn(false);
        when(() => service.walletRequiresPassword(walletPath))
            .thenAnswer((_) async => true);
        when(() => service.walletRequiresXpub(walletPath))
            .thenAnswer((_) async => false);
      });

      test('opens wallet when biometric retrieval succeeds', () async {
        final handle = MockApiWallet();
        const slot = APIBiometricSlot(id: 'slot-1');
        when(() => keystore.isAvailable()).thenAnswer((_) async => true);
        when(() => service.hasBiometricSlots(walletPath))
            .thenAnswer((_) async => true);
        when(() => service.listBiometricSlots(walletPath))
            .thenAnswer((_) async => [slot]);
        when(() => keystore.retrieveKey(slot.id, any()))
            .thenAnswer((_) async => 'a' * 64);
        when(() => service.openWallet(walletPath))
            .thenAnswer((_) async => handle);

        final result = await session.loadCredential(
          walletPath: walletPath,
          biometricUnlockReason: 'Unlock',
        );

        expect(result.handle, same(handle));
        verify(() => service.cacheBiometricKey(walletPath, 'a' * 64))
            .called(1);
      });

      test('returns needsPassword when user cancels biometric prompt',
          () async {
        const slot = APIBiometricSlot(id: 'slot-1');
        when(() => keystore.isAvailable()).thenAnswer((_) async => true);
        when(() => service.hasBiometricSlots(walletPath))
            .thenAnswer((_) async => true);
        when(() => service.listBiometricSlots(walletPath))
            .thenAnswer((_) async => [slot]);
        // retrieveKey returns null on user cancel (per BiometricKeystoreService).
        when(() => keystore.retrieveKey(slot.id, any()))
            .thenAnswer((_) async => null);

        final result = await session.loadCredential(
          walletPath: walletPath,
          biometricUnlockReason: 'Unlock',
        );

        expect(result.handle, isNull);
        expect(result.needsPassword, isTrue);
        verifyNever(() => service.openWallet(any()));
      });

      test('falls through to password prompt when keystore is unavailable',
          () async {
        when(() => keystore.isAvailable()).thenAnswer((_) async => false);

        final result = await session.loadCredential(
          walletPath: walletPath,
          biometricUnlockReason: 'Unlock',
        );

        expect(result.needsPassword, isTrue);
        verifyNever(() => service.hasBiometricSlots(any()));
      });

      test('falls through to password prompt when wallet has no biometric '
          'slots', () async {
        when(() => keystore.isAvailable()).thenAnswer((_) async => true);
        when(() => service.hasBiometricSlots(walletPath))
            .thenAnswer((_) async => false);

        final result = await session.loadCredential(
          walletPath: walletPath,
          biometricUnlockReason: 'Unlock',
        );

        expect(result.needsPassword, isTrue);
        verifyNever(() => service.listBiometricSlots(any()));
      });

      test('tries next slot when openWallet fails for the first one and '
          'succeeds with the second', () async {
        final handle = MockApiWallet();
        const slot1 = APIBiometricSlot(id: 'slot-1');
        const slot2 = APIBiometricSlot(id: 'slot-2');
        when(() => keystore.isAvailable()).thenAnswer((_) async => true);
        when(() => service.hasBiometricSlots(walletPath))
            .thenAnswer((_) async => true);
        when(() => service.listBiometricSlots(walletPath))
            .thenAnswer((_) async => [slot1, slot2]);
        when(() => keystore.retrieveKey(slot1.id, any()))
            .thenAnswer((_) async => 'a' * 64);
        when(() => keystore.retrieveKey(slot2.id, any()))
            .thenAnswer((_) async => 'b' * 64);
        var firstCall = true;
        when(() => service.openWallet(walletPath)).thenAnswer((_) async {
          if (firstCall) {
            firstCall = false;
            throw Exception('first slot key invalid');
          }
          return handle;
        });

        final result = await session.loadCredential(
          walletPath: walletPath,
          biometricUnlockReason: 'Unlock',
        );

        expect(result.handle, same(handle));
        // Failed slot evicted before retrying.
        verify(() => service.evictBiometricKey(walletPath)).called(1);
      });

      test('returns needsPassword when retrieveKey returns null for all slots',
          () async {
        const slot1 = APIBiometricSlot(id: 'slot-1');
        const slot2 = APIBiometricSlot(id: 'slot-2');
        when(() => keystore.isAvailable()).thenAnswer((_) async => true);
        when(() => service.hasBiometricSlots(walletPath))
            .thenAnswer((_) async => true);
        when(() => service.listBiometricSlots(walletPath))
            .thenAnswer((_) async => [slot1, slot2]);
        when(() => keystore.retrieveKey(any(), any()))
            .thenAnswer((_) async => null);

        final result = await session.loadCredential(
          walletPath: walletPath,
          biometricUnlockReason: 'Unlock',
        );

        expect(result.handle, isNull);
        expect(result.needsPassword, isTrue);
      });
    });
  });

  group('lockWallet', () {
    test('evicts both password and biometric caches', () {
      session.lockWallet(walletPath);
      verify(() => service.evictPassword(walletPath)).called(1);
      verify(() => service.evictBiometricKey(walletPath)).called(1);
    });
  });

  group('enableBiometricSlot', () {
    const prompt = PromptInfo(
      androidPromptInfo: AndroidPromptInfo(
        title: 'Enable',
        negativeButton: 'Cancel',
      ),
    );

    test('happy path returns success and stores key under returned slot id',
        () async {
      when(() => keystore.generateKey()).thenReturn('c' * 64);
      when(() => service.addBiometricSlot(
            walletPath: walletPath,
            biometricKeyHex: 'c' * 64,
          )).thenAnswer((_) async => 'new-slot');
      when(() => keystore.storeKey('new-slot', 'c' * 64, any()))
          .thenAnswer((_) async {});

      final result = await session.enableBiometricSlot(
        walletPath: walletPath,
        promptInfo: prompt,
      );

      expect(result.hasBiometricSlot, isTrue);
      expect(result.errorMessage, isNull);
      verifyNever(() => service.removeBiometricSlot(
            walletPath: any(named: 'walletPath'),
            biometricId: any(named: 'biometricId'),
          ));
    });

    test('rolls back Rust slot when keystore storage fails', () async {
      when(() => keystore.generateKey()).thenReturn('c' * 64);
      when(() => service.addBiometricSlot(
            walletPath: walletPath,
            biometricKeyHex: 'c' * 64,
          )).thenAnswer((_) async => 'new-slot');
      when(() => keystore.storeKey('new-slot', 'c' * 64, any()))
          .thenThrow(Exception('keystore write failed'));
      when(() => service.removeBiometricSlot(
            walletPath: walletPath,
            biometricId: 'new-slot',
          )).thenAnswer((_) async {});

      final result = await session.enableBiometricSlot(
        walletPath: walletPath,
        promptInfo: prompt,
      );

      expect(result.hasBiometricSlot, isFalse);
      expect(result.errorMessage, contains('keystore write failed'));
      verify(() => service.removeBiometricSlot(
            walletPath: walletPath,
            biometricId: 'new-slot',
          )).called(1);
    });

    test('returns error when addBiometricSlot fails', () async {
      when(() => keystore.generateKey()).thenReturn('c' * 64);
      when(() => service.addBiometricSlot(
            walletPath: walletPath,
            biometricKeyHex: any(named: 'biometricKeyHex'),
          )).thenThrow(Exception('rust slot add failed'));

      final result = await session.enableBiometricSlot(
        walletPath: walletPath,
        promptInfo: prompt,
      );

      expect(result.hasBiometricSlot, isFalse);
      expect(result.errorMessage, contains('rust slot add failed'));
      verifyNever(() => keystore.storeKey(any(), any(), any()));
    });
  });

  group('disableAllBiometricSlots', () {
    test('removes every slot from Rust and the keystore', () async {
      const slots = [APIBiometricSlot(id: 's1'), APIBiometricSlot(id: 's2')];
      when(() => service.listBiometricSlots(walletPath))
          .thenAnswer((_) async => slots);
      when(() => service.removeBiometricSlot(
            walletPath: walletPath,
            biometricId: any(named: 'biometricId'),
          )).thenAnswer((_) async {});
      when(() => keystore.deleteKey(any())).thenAnswer((_) async {});

      final result = await session.disableAllBiometricSlots(walletPath);

      expect(result.hasBiometricSlot, isFalse);
      expect(result.errorMessage, isNull);
      verify(() => service.removeBiometricSlot(
            walletPath: walletPath,
            biometricId: 's1',
          )).called(1);
      verify(() => service.removeBiometricSlot(
            walletPath: walletPath,
            biometricId: 's2',
          )).called(1);
      verify(() => keystore.deleteKey('s1')).called(1);
      verify(() => keystore.deleteKey('s2')).called(1);
    });

    test('returns error when removal fails partway through', () async {
      const slots = [APIBiometricSlot(id: 's1')];
      when(() => service.listBiometricSlots(walletPath))
          .thenAnswer((_) async => slots);
      when(() => service.removeBiometricSlot(
            walletPath: walletPath,
            biometricId: 's1',
          )).thenThrow(Exception('rust remove failed'));

      final result = await session.disableAllBiometricSlots(walletPath);

      expect(result.hasBiometricSlot, isFalse);
      expect(result.errorMessage, contains('rust remove failed'));
    });

    test('handles empty slot list as success', () async {
      when(() => service.listBiometricSlots(walletPath))
          .thenAnswer((_) async => []);

      final result = await session.disableAllBiometricSlots(walletPath);

      expect(result.hasBiometricSlot, isFalse);
      expect(result.errorMessage, isNull);
      verifyNever(() => service.removeBiometricSlot(
            walletPath: any(named: 'walletPath'),
            biometricId: any(named: 'biometricId'),
          ));
    });
  });
}
