import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import 'package:deadbolt/cubit/wallet_detail_cubit.dart';
import 'package:deadbolt/cubit/wallet_op_result.dart';
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
  });

  tearDown(() => events.close());

  test('addMnemonicKey happy: appends hot key to state', () async {
    final cubit = await loadCubit(opener: opener, sync: sync, wallet: wallet);
    final hk = hotKeyFixture('aabbccdd');
    when(() => wallet.addMnemonicKey(any(), any())).thenReturn(Ok(hk));

    final r = await cubit.addMnemonicKey('twelve words ...', null);
    expect(r, hk);
    expect((cubit.state as WalletDetailLoaded).hotKeys, contains(hk));
    await cubit.close();
  });

  test('addMnemonicKey error: emits errorMessage and returns null', () async {
    final cubit = await loadCubit(opener: opener, sync: sync, wallet: wallet);
    when(() => wallet.addMnemonicKey(any(), any())).thenReturn(const Err('bad'));
    final r = await cubit.addMnemonicKey('x', null);
    expect(r, isNull);
    expect((cubit.state as WalletDetailLoaded).errorMessage, contains('bad'));
    await cubit.close();
  });

  test('deleteHotKey happy: removes from state', () async {
    final hk = hotKeyFixture('aabbccdd');
    final cubit = await loadCubit(
      opener: opener, sync: sync, wallet: wallet,
      view: viewFixture(hotKeys: [hk]),
    );
    when(() => wallet.deleteHotKey('aabbccdd')).thenReturn(const Ok(null));

    await cubit.deleteHotKey('aabbccdd');
    expect((cubit.state as WalletDetailLoaded).hotKeys, isEmpty);
    await cubit.close();
  });

  test('revealHotKey happy returns wif; error returns null', () async {
    final cubit = await loadCubit(opener: opener, sync: sync, wallet: wallet);
    when(() => wallet.revealHotKey('mfp1')).thenReturn(const Ok('xprv...'));
    expect(await cubit.revealHotKey('mfp1'), 'xprv...');

    when(() => wallet.revealHotKey('mfp2')).thenReturn(const Err('locked'));
    expect(await cubit.revealHotKey('mfp2'), isNull);
    expect((cubit.state as WalletDetailLoaded).errorMessage, contains('locked'));
    await cubit.close();
  });
}
