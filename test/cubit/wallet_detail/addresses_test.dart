import 'dart:async';

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

  test('loadAddresses(external) happy: receiveLoaded becomes true', () async {
    final cubit = await loadCubit(
      opener: opener, sync: sync, wallet: wallet,
      view: viewFixture(receiveLoaded: false),
    );
    when(() => wallet.loadAddresses(APIKeychain.external_))
        .thenAnswer((_) async => Ok(AddressUpdate([addressFixture('addr1')])));

    // ignore: invalid_use_of_protected_member
    await cubit.loadAddresses(APIKeychain.external_);

    final s = cubit.state as WalletDetailLoaded;
    expect(s.receiveAddressesLoaded, isTrue);
    expect(s.receiveAddresses, hasLength(1));
    await cubit.close();
  });

  test('loadAddresses error: emits errorMessage', () async {
    final cubit = await loadCubit(opener: opener, sync: sync, wallet: wallet);
    when(() => wallet.loadAddresses(any())).thenAnswer((_) async => const Err('ffi'));

    // ignore: invalid_use_of_protected_member
    await cubit.loadAddresses(APIKeychain.internal);

    expect((cubit.state as WalletDetailLoaded).errorMessage, contains('ffi'));
    await cubit.close();
  });

  test('selectAddressKeychain emits new selectedAddressKeychain', () async {
    final cubit = await loadCubit(opener: opener, sync: sync, wallet: wallet);
    cubit.selectAddressKeychain(1);
    expect((cubit.state as WalletDetailLoaded).selectedAddressKeychain, 1);
    await cubit.close();
  });

  test('getNextReceiveAddress returns null when wallet throws', () async {
    final cubit = await loadCubit(opener: opener, sync: sync, wallet: wallet);
    when(() => wallet.findNextUnusedAddress(any())).thenThrow(Exception('x'));
    final r = await cubit.getNextReceiveAddress();
    expect(r, isNull);
    await cubit.close();
  });
}
