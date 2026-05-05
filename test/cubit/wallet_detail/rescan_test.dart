import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import 'package:deadbolt/cubit/wallet_detail_cubit.dart';
import 'package:deadbolt/cubit/wallet_op_result.dart';
import 'package:deadbolt/cubit/wallet_deltas.dart';
import 'package:deadbolt/services/wallet_sync_service.dart';

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
    stubLoadedDefaults(wallet);
    when(() => wallet.loadUtxos()).thenAnswer((_) async => const Ok(CoinUpdate([])));
  });

  tearDown(() => events.close());

  test('rescan happy: applies ChainSnapshot, drops cached views, kicks loaders', () async {
    final cubit = await loadCubit(opener: opener, sync: sync, wallet: wallet);
    when(() => wallet.rescan(any())).thenAnswer((_) async => Ok(ChainSnapshot(
          info: walletInfoFixture(),
          balance: balanceOf(99),
          transactions: emptyPage(),
          tipHeight: 500,
        )));

    await cubit.rescan('tcp://x');
    final s = cubit.state as WalletDetailLoaded;
    expect(s.tipHeight, 500);
    expect(s.utxosLoaded, isFalse);
    expect(s.receiveAddressesLoaded, isFalse);
    expect(s.isSyncing, isFalse);
    await cubit.close();
  });

  test('rescan error: clears isSyncing and emits errorMessage', () async {
    final cubit = await loadCubit(opener: opener, sync: sync, wallet: wallet);
    when(() => wallet.rescan(any())).thenAnswer((_) async => const Err('rescan failed'));

    await cubit.rescan('tcp://x');
    final s = cubit.state as WalletDetailLoaded;
    expect(s.isSyncing, isFalse);
    expect(s.errorMessage, contains('rescan failed'));
    await cubit.close();
  });
}
