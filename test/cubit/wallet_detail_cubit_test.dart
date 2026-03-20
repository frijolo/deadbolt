import 'package:flutter_test/flutter_test.dart';
import 'package:bloc_test/bloc_test.dart';
import 'package:mocktail/mocktail.dart';

import 'package:deadbolt/cubit/wallet_detail_cubit.dart';
import 'package:deadbolt/services/wallet_service.dart';

class MockWalletService extends Mock implements WalletService {}

void main() {
  late MockWalletService mockService;

  setUp(() {
    mockService = MockWalletService();
  });

  group('WalletDetailCubit.load()', () {
    const walletPath = '/fake/path/wallet.db';

    test('emits NeedsPassword when no password cached and wallet requires one',
        () async {
      when(() => mockService.getCachedPassword(walletPath)).thenReturn(null);
      when(() => mockService.walletRequiresPassword(walletPath))
          .thenAnswer((_) async => true);

      final cubit = WalletDetailCubit(service: mockService);
      await cubit.load(walletPath);

      expect(cubit.state, isA<WalletDetailNeedsPassword>());
      expect(
        (cubit.state as WalletDetailNeedsPassword).walletPath,
        walletPath,
      );

      await cubit.close();
    });

    test('emits WalletDetailError when openWallet throws', () async {
      when(() => mockService.getCachedPassword(walletPath)).thenReturn(null);
      when(() => mockService.walletRequiresPassword(walletPath))
          .thenAnswer((_) async => false);
      when(() => mockService.openWallet(walletPath, password: any(named: 'password')))
          .thenThrow(Exception('wallet not found'));

      final cubit = WalletDetailCubit(service: mockService);
      await cubit.load(walletPath);

      expect(cubit.state, isA<WalletDetailError>());
      expect(
        (cubit.state as WalletDetailError).message,
        contains('wallet not found'),
      );

      await cubit.close();
    });

    blocTest<WalletDetailCubit, WalletDetailState>(
      'emits [Loading, NeedsPassword] in order when password required',
      build: () {
        when(() => mockService.getCachedPassword(walletPath)).thenReturn(null);
        when(() => mockService.walletRequiresPassword(walletPath))
            .thenAnswer((_) async => true);
        return WalletDetailCubit(service: mockService);
      },
      act: (cubit) => cubit.load(walletPath),
      expect: () => [
        isA<WalletDetailLoading>(),
        isA<WalletDetailNeedsPassword>(),
      ],
    );

    blocTest<WalletDetailCubit, WalletDetailState>(
      'emits [Loading, Error] in order when openWallet throws',
      build: () {
        when(() => mockService.getCachedPassword(walletPath)).thenReturn(null);
        when(() => mockService.walletRequiresPassword(walletPath))
            .thenAnswer((_) async => false);
        when(() => mockService.openWallet(walletPath,
                password: any(named: 'password')))
            .thenThrow(Exception('disk error'));
        return WalletDetailCubit(service: mockService);
      },
      act: (cubit) => cubit.load(walletPath),
      expect: () => [
        isA<WalletDetailLoading>(),
        isA<WalletDetailError>(),
      ],
    );

    blocTest<WalletDetailCubit, WalletDetailState>(
      'skips password check when password is already cached',
      build: () {
        when(() => mockService.getCachedPassword(walletPath))
            .thenReturn('cached_password');
        when(() => mockService.openWallet(walletPath,
                password: any(named: 'password')))
            .thenThrow(Exception('open failed'));
        return WalletDetailCubit(service: mockService);
      },
      act: (cubit) => cubit.load(walletPath),
      verify: (_) {
        // walletRequiresPassword should NOT be called when a password is cached
        verifyNever(() => mockService.walletRequiresPassword(walletPath));
      },
      expect: () => [
        isA<WalletDetailLoading>(),
        isA<WalletDetailError>(),
      ],
    );

    blocTest<WalletDetailCubit, WalletDetailState>(
      'caches provided password before checking requirements',
      build: () {
        when(() => mockService.cachePassword(walletPath, 'my_pass'))
            .thenReturn(null);
        when(() => mockService.getCachedPassword(walletPath))
            .thenReturn('my_pass');
        when(() => mockService.openWallet(walletPath,
                password: any(named: 'password')))
            .thenThrow(Exception('open failed'));
        return WalletDetailCubit(service: mockService);
      },
      act: (cubit) => cubit.load(walletPath, password: 'my_pass'),
      verify: (_) {
        verify(() => mockService.cachePassword(walletPath, 'my_pass'))
            .called(1);
      },
      expect: () => [
        isA<WalletDetailLoading>(),
        isA<WalletDetailError>(),
      ],
    );
  });

  group('WalletDetailCubit.startAutoSync()', () {
    test('does not crash when state is Initial', () {
      final cubit = WalletDetailCubit(service: mockService);
      // Should not throw even though there is no loaded state
      expect(() => cubit.startAutoSync('tcp://localhost:50001'), returnsNormally);
      cubit.close();
    });
  });

  group('WalletDetailCubit initial state', () {
    test('starts in WalletDetailInitial', () {
      final cubit = WalletDetailCubit(service: mockService);
      expect(cubit.state, isA<WalletDetailInitial>());
      cubit.close();
    });
  });
}
