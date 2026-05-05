import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import 'package:deadbolt/cubit/wallet_detail_cubit.dart';
import 'package:deadbolt/cubit/wallet_detail_session.dart';
import 'package:deadbolt/cubit/wallet_opener.dart';
import 'package:deadbolt/services/wallet_sync_service.dart';

class MockWalletOpener extends Mock implements WalletOpener {}

class MockWalletSyncService extends Mock implements WalletSyncService {}

void main() {
  late MockWalletOpener mockOpener;
  late MockWalletSyncService mockSyncService;

  setUp(() {
    mockOpener = MockWalletOpener();
    mockSyncService = MockWalletSyncService();
  });

  WalletDetailCubit makeCubit() => WalletDetailCubit(
        opener: mockOpener,
        syncService: mockSyncService,
      );

  group('WalletDetailCubit.load()', () {
    const walletPath = '/fake/path/wallet.db';

    test('emits NeedsPassword when opener returns WalletLoadNeedsPassword',
        () async {
      when(() => mockOpener.load(
            walletPath: any(named: 'walletPath'),
            password: any(named: 'password'),
            biometricUnlockReason: any(named: 'biometricUnlockReason'),
          )).thenAnswer((_) async => const WalletLoadNeedsPassword(isXpubKey: false));

      final cubit = makeCubit();
      await cubit.load(walletPath);

      expect(cubit.state, isA<WalletDetailNeedsPassword>());
      expect(
        (cubit.state as WalletDetailNeedsPassword).walletPath,
        walletPath,
      );

      await cubit.close();
    });

    test('emits WalletDetailError when opener throws', () async {
      when(() => mockOpener.load(
            walletPath: any(named: 'walletPath'),
            password: any(named: 'password'),
            biometricUnlockReason: any(named: 'biometricUnlockReason'),
          )).thenThrow(Exception('wallet not found'));

      final cubit = makeCubit();
      await cubit.load(walletPath);

      expect(cubit.state, isA<WalletDetailError>());
      expect(
        (cubit.state as WalletDetailError).message,
        contains('wallet not found'),
      );

      await cubit.close();
    });
  });

  group('WalletDetailCubit.registerWithSyncService()', () {
    test('does not crash when state is Initial', () {
      final cubit = makeCubit();
      expect(() => cubit.registerWithSyncService('tcp://localhost:50001'),
          returnsNormally);
      cubit.close();
    });
  });

  group('WalletDetailCubit initial state', () {
    test('starts in WalletDetailInitial', () {
      final cubit = makeCubit();
      expect(cubit.state, isA<WalletDetailInitial>());
      cubit.close();
    });
  });
}
