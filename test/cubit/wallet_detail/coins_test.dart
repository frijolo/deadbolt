import 'dart:async';

import 'package:flutter_rust_bridge/flutter_rust_bridge.dart' show Int64List;

import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import 'package:deadbolt/cubit/wallet_detail_cubit.dart';
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
    stubLoadedDefaults(wallet);
  });

  tearDown(() => events.close());

  APIUtxo utxo(String txid) => APIUtxo(
        txid: txid,
        vout: 0,
        valueSat: BigInt.from(1000),
        keychain: APIKeychain.external_,
        derivationIndex: 0,
        address: 'bc1q',
        isConfirmed: true,
        isAuto: false,
        pendingPsbtIds: Int64List(0),
      );

  test('loadUtxos happy: emits CoinView(loaded:true) with utxos', () async {
    final cubit = await loadCubit(
      opener: opener,
      sync: sync,
      wallet: wallet,
      view: viewFixture(utxosLoaded: false),
    );
    when(() => wallet.loadUtxos()).thenAnswer((_) async => Ok(CoinUpdate([utxo('a')])));

    // ignore: invalid_use_of_protected_member
    await cubit.loadUtxos();

    final s = cubit.state as WalletDetailLoaded;
    expect(s.utxosLoaded, isTrue);
    expect(s.utxos, hasLength(1));
    await cubit.close();
  });

  test('loadUtxos error: emits errorMessage', () async {
    final cubit = await loadCubit(opener: opener, sync: sync, wallet: wallet);
    when(() => wallet.loadUtxos()).thenAnswer((_) async => const Err('boom'));

    // ignore: invalid_use_of_protected_member
    await cubit.loadUtxos();

    expect((cubit.state as WalletDetailLoaded).errorMessage, contains('boom'));
    await cubit.close();
  });

  test('reloadCoinsIfLoaded no-op when utxos not loaded', () async {
    final cubit = await loadCubit(
      opener: opener,
      sync: sync,
      wallet: wallet,
      view: viewFixture(utxosLoaded: false),
    );
    // ignore: invalid_use_of_protected_member
    await cubit.reloadCoinsIfLoaded();
    verifyNever(() => wallet.loadUtxos());
    await cubit.close();
  });
}
