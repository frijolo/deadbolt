import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import 'package:deadbolt/cubit/fiat_price_manager.dart' show FiatPricesUpdate;
import 'package:deadbolt/cubit/wallet_detail_cubit.dart';
import 'package:deadbolt/cubit/wallet_detail_session.dart';
import 'package:deadbolt/cubit/wallet_op_result.dart';
import 'package:deadbolt/cubit/wallet_deltas.dart';
import 'package:deadbolt/services/wallet_sync_service.dart';
import 'package:deadbolt/src/rust/api/model.dart';

import '_helpers.dart';

void main() {
  setUpAll(registerCommonFallbacks);

  late MockWalletOpener opener;
  late MockWalletSyncService sync;
  late MockLoadedWallet wallet;
  late StreamController<WalletSyncEvent> events;

  setUp(() {
    opener = MockWalletOpener();
    sync = MockWalletSyncService();
    wallet = MockLoadedWallet();
    events = StreamController<WalletSyncEvent>.broadcast();
    when(() => sync.events).thenAnswer((_) => events.stream);
    when(() => sync.registerHandle(any(), any(), any()))
        .thenAnswer((_) async {});
    when(() => sync.syncWallet(any())).thenAnswer((_) async {});
    when(() => sync.untrack(any())).thenReturn(null);
    stubLoadedDefaults(wallet);
    when(() => wallet.fetchFiatPrices(currency: any(named: 'currency'), enabled: any(named: 'enabled')))
        .thenAnswer((_) async => const Ok<FiatPricesUpdate?>(null));
  });

  tearDown(() async {
    await events.close();
  });

  group('lifecycle.load', () {
    test('happy: WalletLoadSuccess → WalletDetailLoaded', () async {
      final cubit = await loadCubit(
        opener: opener,
        sync: sync,
        wallet: wallet,
      );
      expect(cubit.state, isA<WalletDetailLoaded>());
      await cubit.close();
    });

    test('error: opener.load throws → WalletDetailError', () async {
      when(() => opener.load(
            walletPath: any(named: 'walletPath'),
            password: any(named: 'password'),
            biometricUnlockReason: any(named: 'biometricUnlockReason'),
          )).thenThrow(Exception('boom'));
      final cubit = WalletDetailCubit(opener: opener, syncService: sync);
      await cubit.load(walletPath);
      expect(cubit.state, isA<WalletDetailError>());
      await cubit.close();
    });

    test('NeedsPassword: opener returns WalletLoadNeedsPassword', () async {
      when(() => opener.load(
            walletPath: any(named: 'walletPath'),
            password: any(named: 'password'),
            biometricUnlockReason: any(named: 'biometricUnlockReason'),
          )).thenAnswer((_) async =>
              const WalletLoadNeedsPassword(isXpubKey: true, network: APINetwork.signet));
      final cubit = WalletDetailCubit(opener: opener, syncService: sync);
      await cubit.load(walletPath);
      final s = cubit.state as WalletDetailNeedsPassword;
      expect(s.isXpubKey, isTrue);
      expect(s.network, APINetwork.signet);
      await cubit.close();
    });
  });

  group('lifecycle.registerWithSyncService + sync events', () {
    test('routes events for matching walletPath; ignores others', () async {
      final cubit = await loadCubit(opener: opener, sync: sync, wallet: wallet);

      // Stub a successful chain reload from handleSyncEvent.
      when(() => wallet.handleSyncEvent(
            event: any(named: 'event'),
            receiveLoaded: any(named: 'receiveLoaded'),
            changeLoaded: any(named: 'changeLoaded'),
            utxosLoaded: any(named: 'utxosLoaded'),
            psbtsLoaded: any(named: 'psbtsLoaded'),
            currentPsbts: any(named: 'currentPsbts'),
            currentAnalyses: any(named: 'currentAnalyses'),
          )).thenAnswer((_) async => Ok(SyncReload(
            chain: ChainSnapshot(
              info: walletInfoFixture(),
              balance: balanceOf(42),
              transactions: emptyPage(),
              tipHeight: 200,
            ),
          )));

      cubit.registerWithSyncService('tcp://localhost:50001');
      verify(() => sync.registerHandle(walletPath, any(), 'tcp://localhost:50001')).called(1);

      // Event for another wallet — no state change.
      events.add(const WalletSyncEvent(walletPath: '/other.db', isSyncing: true));
      await Future.delayed(Duration.zero);
      expect((cubit.state as WalletDetailLoaded).isSyncing, isFalse);

      // isSyncing true for our wallet → state.isSyncing flips.
      events.add(const WalletSyncEvent(walletPath: walletPath, isSyncing: true));
      await Future.delayed(Duration.zero);
      expect((cubit.state as WalletDetailLoaded).isSyncing, isTrue);

      // Completed event → tip applied, isSyncing false.
      events.add(WalletSyncEvent(walletPath: walletPath, balance: balanceOf(42)));
      await Future.delayed(Duration.zero);
      final loaded = cubit.state as WalletDetailLoaded;
      expect(loaded.isSyncing, isFalse);
      expect(loaded.tipHeight, 200);

      await cubit.close();
    });

    test('handleSyncEvent Err → emits errorMessage and clears isSyncing', () async {
      final cubit = await loadCubit(opener: opener, sync: sync, wallet: wallet);
      when(() => wallet.handleSyncEvent(
            event: any(named: 'event'),
            receiveLoaded: any(named: 'receiveLoaded'),
            changeLoaded: any(named: 'changeLoaded'),
            utxosLoaded: any(named: 'utxosLoaded'),
            psbtsLoaded: any(named: 'psbtsLoaded'),
            currentPsbts: any(named: 'currentPsbts'),
            currentAnalyses: any(named: 'currentAnalyses'),
          )).thenAnswer((_) async => const Err('electrum down'));

      cubit.registerWithSyncService('tcp://x');
      events.add(WalletSyncEvent(walletPath: walletPath, balance: balanceOf(0)));
      await Future.delayed(Duration.zero);

      final loaded = cubit.state as WalletDetailLoaded;
      expect(loaded.errorMessage, contains('electrum down'));
      expect(loaded.isSyncing, isFalse);
      await cubit.close();
    });
  });

  group('lifecycle.selectTab', () {
    test('triggers loadAddresses on tab=2 when not loaded', () async {
      final view = viewFixture(receiveLoaded: false, changeLoaded: false);
      final cubit = await loadCubit(opener: opener, sync: sync, wallet: wallet, view: view);

      when(() => wallet.loadAddresses(any()))
          .thenAnswer((_) async => const Ok(AddressUpdate([])));

      cubit.selectTab(2);
      await Future.delayed(Duration.zero);

      verify(() => wallet.loadAddresses(APIKeychain.external_)).called(1);
      verify(() => wallet.loadAddresses(APIKeychain.internal)).called(1);
      await cubit.close();
    });

    test('no-op when same tab', () async {
      final cubit = await loadCubit(opener: opener, sync: sync, wallet: wallet);
      final before = cubit.state;
      cubit.selectTab(0);
      expect(cubit.state, same(before));
      await cubit.close();
    });
  });

  group('lifecycle.lockWallet + sync()', () {
    test('lockWallet delegates to opener.lock', () async {
      when(() => opener.lock(any())).thenReturn(null);
      final cubit = await loadCubit(opener: opener, sync: sync, wallet: wallet);
      cubit.lockWallet();
      verify(() => opener.lock(walletPath)).called(1);
      await cubit.close();
    });

    test('sync() delegates to syncService.syncWallet', () async {
      final cubit = await loadCubit(opener: opener, sync: sync, wallet: wallet);
      cubit.sync();
      verify(() => sync.syncWallet(walletPath)).called(1);
      await cubit.close();
    });

    test('clearError resets errorMessage on a loaded state with an error', () async {
      final cubit = await loadCubit(opener: opener, sync: sync, wallet: wallet);
      when(() => wallet.handleSyncEvent(
            event: any(named: 'event'),
            receiveLoaded: any(named: 'receiveLoaded'),
            changeLoaded: any(named: 'changeLoaded'),
            utxosLoaded: any(named: 'utxosLoaded'),
            psbtsLoaded: any(named: 'psbtsLoaded'),
            currentPsbts: any(named: 'currentPsbts'),
            currentAnalyses: any(named: 'currentAnalyses'),
          )).thenAnswer((_) async => const Err('boom'));

      cubit.registerWithSyncService('tcp://x');
      events.add(WalletSyncEvent(walletPath: walletPath, balance: balanceOf(0)));
      await Future.delayed(Duration.zero);

      expect((cubit.state as WalletDetailLoaded).errorMessage, isNotNull);
      cubit.clearError();
      expect((cubit.state as WalletDetailLoaded).errorMessage, isNull);
      await cubit.close();
    });
  });
}
