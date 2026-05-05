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
  late MockApiWallet handle;
  late StreamController<WalletSyncEvent> events;

  setUp(() {
    opener = MockWalletOpener();
    sync = MockWalletSyncService();
    wallet = MockLoadedWallet();
    events = StreamController<WalletSyncEvent>.broadcast();
    when(() => sync.events).thenAnswer((_) => events.stream);
    handle = stubLoadedDefaults(wallet);
    when(() => wallet.loadUtxos()).thenAnswer((_) async => const Ok(CoinUpdate([])));
  });

  tearDown(() => events.close());

  test('loadPsbts happy: emits PsbtList loaded=true', () async {
    final cubit = await loadCubit(opener: opener, sync: sync, wallet: wallet);
    final p = psbtFixture(id: 1);
    when(() => wallet.loadPsbts()).thenAnswer((_) async => Ok(
          PsbtSnapshot(psbts: [p], analyses: {1: analysisFixture()}),
        ));

    await cubit.loadPsbts();
    final s = cubit.state as WalletDetailLoaded;
    expect(s.psbtsLoaded, isTrue);
    expect(s.psbts, hasLength(1));
    expect(s.psbtAnalyses[1], isNotNull);
    await cubit.close();
  });

  test('loadPsbts error: emits errorMessage', () async {
    final cubit = await loadCubit(opener: opener, sync: sync, wallet: wallet);
    when(() => wallet.loadPsbts()).thenAnswer((_) async => const Err('db locked'));
    await cubit.loadPsbts();
    expect((cubit.state as WalletDetailLoaded).errorMessage, contains('db locked'));
    await cubit.close();
  });

  test('deletePsbt happy: removes PSBT from list', () async {
    final p = psbtFixture(id: 7);
    final cubit = await loadCubit(
      opener: opener, sync: sync, wallet: wallet,
      view: viewFixture(psbts: [p]),
    );
    when(() => wallet.deletePsbt(7)).thenReturn(const Ok(null));

    cubit.deletePsbt(7);
    await Future.delayed(Duration.zero);
    expect((cubit.state as WalletDetailLoaded).psbts, isEmpty);
    await cubit.close();
  });

  test('importPsbt error: emits errorMessage and returns null', () async {
    final cubit = await loadCubit(opener: opener, sync: sync, wallet: wallet);
    when(() => wallet.importPsbt(any())).thenAnswer((_) async => const Err('not psbt'));
    final result = await cubit.importPsbt('xx');
    expect(result, isNull);
    expect((cubit.state as WalletDetailLoaded).errorMessage, 'not psbt');
    await cubit.close();
  });

  test('broadcastPsbt error: throws; happy: returns txid and reloads page', () async {
    final p = psbtFixture(id: 3);
    final cubit = await loadCubit(
      opener: opener, sync: sync, wallet: wallet,
      view: viewFixture(psbts: [p]),
    );
    when(() => wallet.broadcastPsbt(3, any())).thenAnswer((_) async => const Err('rejected'));
    expect(() => cubit.broadcastPsbt(3, 'tcp://x'), throwsA(isA<Exception>()));

    when(() => wallet.broadcastPsbt(3, any())).thenAnswer((_) async => const Ok('txid_abc'));
    when(() => handle.getTransactions(page: any(named: 'page'), pageSize: any(named: 'pageSize')))
        .thenAnswer((_) async => emptyPage());
    when(() => sync.syncWallet(any())).thenAnswer((_) async {});
    final r = await cubit.broadcastPsbt(3, 'tcp://x');
    expect(r, 'txid_abc');
    await cubit.close();
  });
}
