import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:bloc_test/bloc_test.dart';
import 'package:mocktail/mocktail.dart';

import 'package:deadbolt/cubit/wallet_list_cubit.dart';
import 'package:deadbolt/services/wallet_service.dart';
import 'package:deadbolt/src/rust/api/model.dart';

class MockWalletService extends Mock implements WalletService {}

const _fakeWallet = APIWalletInfo(
  walletPath: '/fake/wallets/mywallet',
  name: 'Test Wallet',
  descriptor: 'wpkh([abc12345/84h/0h/0h]xpub123/*)',
  network: APINetwork.bitcoin,
  createdAt: 0,
  lastSyncedAt: null,
  protection: APIWalletProtection(
    protectionType: APIProtectionType.deviceKey,
    needsPassword: false,
    securityLevel: APISecurityLevel.standard,
  ),
);

void main() {
  late MockWalletService mockService;

  setUpAll(() {
    // Mocktail requires fallback values for non-primitive FFI types used with any().
    registerFallbackValue(APINetwork.bitcoin);
    registerFallbackValue(APIProtectionType.deviceKey);
    registerFallbackValue(APISecurityLevel.standard);
  });

  setUp(() {
    mockService = MockWalletService();
  });

  // ---------------------------------------------------------------------------
  // Initial state
  // ---------------------------------------------------------------------------

  group('WalletListCubit initial state', () {
    test('starts in WalletListLoading before first refresh completes',
        () async {
      // Hold refresh in-flight so the state stays Loading
      final completer = Completer<List<APIWalletInfo>>();
      when(() => mockService.listWallets())
          .thenAnswer((_) => completer.future);

      final cubit = WalletListCubit(service: mockService);
      expect(cubit.state, isA<WalletListLoading>());

      // Unblock refresh so the cubit can close cleanly
      completer.complete([]);
      await Future<void>.delayed(Duration.zero);
      await cubit.close();
    });
  });

  // ---------------------------------------------------------------------------
  // refresh()
  // ---------------------------------------------------------------------------

  group('WalletListCubit.refresh()', () {
    blocTest<WalletListCubit, WalletListState>(
      'emits Loaded with empty list when service returns no wallets',
      build: () {
        when(() => mockService.listWallets()).thenAnswer((_) async => []);
        return WalletListCubit(service: mockService);
      },
      expect: () => [isA<WalletListLoaded>()],
      verify: (cubit) {
        final state = cubit.state as WalletListLoaded;
        expect(state.wallets, isEmpty);
      },
    );

    blocTest<WalletListCubit, WalletListState>(
      'emits Loaded containing returned wallets',
      build: () {
        when(() => mockService.listWallets())
            .thenAnswer((_) async => [_fakeWallet]);
        return WalletListCubit(service: mockService);
      },
      expect: () => [isA<WalletListLoaded>()],
      verify: (cubit) {
        final state = cubit.state as WalletListLoaded;
        expect(state.wallets.length, 1);
        expect(state.wallets.first.name, 'Test Wallet');
      },
    );

    blocTest<WalletListCubit, WalletListState>(
      // thenAnswer with async throw ensures the exception is asynchronous so
      // blocTest can subscribe before the error state is emitted.
      'emits Error when listWallets throws',
      build: () {
        when(() => mockService.listWallets())
            .thenAnswer((_) async => throw Exception('disk read error'));
        return WalletListCubit(service: mockService);
      },
      expect: () => [isA<WalletListError>()],
      verify: (cubit) {
        final state = cubit.state as WalletListError;
        expect(state.message, contains('disk read error'));
      },
    );

    blocTest<WalletListCubit, WalletListState>(
      'emits Loaded again when refresh() is called manually',
      build: () {
        when(() => mockService.listWallets()).thenAnswer((_) async => []);
        return WalletListCubit(service: mockService);
      },
      act: (cubit) async {
        await Future<void>.delayed(Duration.zero); // let constructor refresh finish
        await cubit.refresh();
      },
      // First Loaded = constructor refresh; second = manual call
      expect: () => [isA<WalletListLoaded>(), isA<WalletListLoaded>()],
    );
  });

  // ---------------------------------------------------------------------------
  // createWallet()
  // ---------------------------------------------------------------------------

  group('WalletListCubit.createWallet()', () {
    blocTest<WalletListCubit, WalletListState>(
      'calls service.createWallet and refreshes list on success',
      build: () {
        when(() => mockService.listWallets()).thenAnswer((_) async => []);
        when(() => mockService.createWallet(
              name: any(named: 'name'),
              descriptor: any(named: 'descriptor'),
              network: any(named: 'network'),
              protectionType: any(named: 'protectionType'),
              password: any(named: 'password'),
              securityLevel: any(named: 'securityLevel'),
            )).thenAnswer((_) async => _fakeWallet);
        return WalletListCubit(service: mockService);
      },
      act: (cubit) async {
        await Future<void>.delayed(Duration.zero);
        await cubit.createWallet(
          name: 'My Wallet',
          descriptor: 'wpkh([abc12345/84h/0h/0h]xpub123/*)',
          network: APINetwork.bitcoin,
        );
      },
      verify: (_) {
        verify(() => mockService.createWallet(
              name: 'My Wallet',
              descriptor: 'wpkh([abc12345/84h/0h/0h]xpub123/*)',
              network: APINetwork.bitcoin,
              protectionType: APIProtectionType.deviceKey,
              password: null,
              securityLevel: APISecurityLevel.standard,
            )).called(1);
      },
    );

    test('returns the walletPath from the created wallet', () async {
      when(() => mockService.listWallets()).thenAnswer((_) async => []);
      when(() => mockService.createWallet(
            name: any(named: 'name'),
            descriptor: any(named: 'descriptor'),
            network: any(named: 'network'),
            protectionType: any(named: 'protectionType'),
            password: any(named: 'password'),
            securityLevel: any(named: 'securityLevel'),
          )).thenAnswer((_) async => _fakeWallet);

      final cubit = WalletListCubit(service: mockService);
      await cubit.stream.first; // wait for initial refresh

      final path = await cubit.createWallet(
        name: 'My Wallet',
        descriptor: 'wpkh(...)',
        network: APINetwork.bitcoin,
      );

      expect(path, _fakeWallet.walletPath);
      await cubit.close();
    });

    test('caches password when protectionType is userPassword', () async {
      when(() => mockService.listWallets()).thenAnswer((_) async => []);
      when(() => mockService.createWallet(
            name: any(named: 'name'),
            descriptor: any(named: 'descriptor'),
            network: any(named: 'network'),
            protectionType: any(named: 'protectionType'),
            password: any(named: 'password'),
            securityLevel: any(named: 'securityLevel'),
          )).thenAnswer((_) async => _fakeWallet);
      when(() => mockService.cachePassword(any(), any())).thenReturn(null);

      final cubit = WalletListCubit(service: mockService);
      await cubit.stream.first;

      await cubit.createWallet(
        name: 'Protected Wallet',
        descriptor: 'wpkh(...)',
        network: APINetwork.bitcoin,
        protectionType: APIProtectionType.userPassword,
        password: 'my_secret',
      );

      verify(() =>
              mockService.cachePassword(_fakeWallet.walletPath, 'my_secret'))
          .called(1);
      await cubit.close();
    });

    test('does NOT cache password for deviceKey protection type', () async {
      when(() => mockService.listWallets()).thenAnswer((_) async => []);
      when(() => mockService.createWallet(
            name: any(named: 'name'),
            descriptor: any(named: 'descriptor'),
            network: any(named: 'network'),
            protectionType: any(named: 'protectionType'),
            password: any(named: 'password'),
            securityLevel: any(named: 'securityLevel'),
          )).thenAnswer((_) async => _fakeWallet);

      final cubit = WalletListCubit(service: mockService);
      await cubit.stream.first;

      await cubit.createWallet(
        name: 'Device Wallet',
        descriptor: 'wpkh(...)',
        network: APINetwork.bitcoin,
        protectionType: APIProtectionType.deviceKey,
      );

      verifyNever(() => mockService.cachePassword(any(), any()));
      await cubit.close();
    });

    test('rethrows when service.createWallet throws', () async {
      when(() => mockService.listWallets()).thenAnswer((_) async => []);
      when(() => mockService.createWallet(
            name: any(named: 'name'),
            descriptor: any(named: 'descriptor'),
            network: any(named: 'network'),
            protectionType: any(named: 'protectionType'),
            password: any(named: 'password'),
            securityLevel: any(named: 'securityLevel'),
          )).thenAnswer((_) async => throw Exception('create failed'));

      final cubit = WalletListCubit(service: mockService);
      await cubit.stream.first;

      await expectLater(
        cubit.createWallet(
          name: 'Bad',
          descriptor: 'wpkh(...)',
          network: APINetwork.bitcoin,
        ),
        throwsA(isA<Exception>()),
      );
      await cubit.close();
    });
  });

  // ---------------------------------------------------------------------------
  // deleteWallet()
  // ---------------------------------------------------------------------------

  group('WalletListCubit.deleteWallet()', () {
    const walletPath = '/fake/wallets/mywallet';

    blocTest<WalletListCubit, WalletListState>(
      'calls service.deleteWallet and refreshes list on success',
      build: () {
        when(() => mockService.listWallets()).thenAnswer((_) async => []);
        when(() => mockService.deleteWallet(walletPath))
            .thenAnswer((_) async {});
        return WalletListCubit(service: mockService);
      },
      act: (cubit) async {
        await Future<void>.delayed(Duration.zero);
        await cubit.deleteWallet(walletPath);
      },
      verify: (_) {
        verify(() => mockService.deleteWallet(walletPath)).called(1);
      },
    );

    test('rethrows when service.deleteWallet throws', () async {
      when(() => mockService.listWallets()).thenAnswer((_) async => []);
      when(() => mockService.deleteWallet(walletPath))
          .thenAnswer((_) async => throw Exception('delete failed'));

      final cubit = WalletListCubit(service: mockService);
      await cubit.stream.first;

      await expectLater(
        cubit.deleteWallet(walletPath),
        throwsA(isA<Exception>()),
      );
      await cubit.close();
    });
  });
}
