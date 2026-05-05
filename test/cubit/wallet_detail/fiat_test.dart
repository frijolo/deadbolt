import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import 'package:deadbolt/cubit/fiat_price_manager.dart' show FiatPricesUpdate;
import 'package:deadbolt/cubit/wallet_detail_cubit.dart';
import 'package:deadbolt/cubit/wallet_op_result.dart';
import 'package:deadbolt/services/price_service.dart' show PriceProviderType;
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

  test('setFiatConfig same config: no-op (no emit)', () async {
    final cubit = await loadCubit(opener: opener, sync: sync, wallet: wallet);
    when(() => wallet.setFiatConfig(
        enabled: any(named: 'enabled'),
        currency: any(named: 'currency'),
        provider: any(named: 'provider'))).thenReturn(null);
    final before = cubit.state;
    await cubit.setFiatConfig(true, 'usd', PriceProviderType.coinGecko);
    expect(cubit.state, same(before));
    await cubit.close();
  });

  test('setFiatConfig disabled: clears fiat state', () async {
    final cubit = await loadCubit(opener: opener, sync: sync, wallet: wallet);
    when(() => wallet.setFiatConfig(
        enabled: any(named: 'enabled'),
        currency: any(named: 'currency'),
        provider: any(named: 'provider'))).thenReturn('disabled');
    await cubit.setFiatConfig(false, 'usd', PriceProviderType.coinGecko);
    final s = cubit.state as WalletDetailLoaded;
    expect(s.fiatCurrency, isNull);
    expect(s.fiatPrices, isEmpty);
    await cubit.close();
  });

  test('setFiatConfig new currency: emits currency and triggers fetchMissingFiatPrices', () async {
    final cubit = await loadCubit(opener: opener, sync: sync, wallet: wallet);
    when(() => wallet.setFiatConfig(
        enabled: any(named: 'enabled'),
        currency: any(named: 'currency'),
        provider: any(named: 'provider'))).thenReturn('eur');
    when(() => wallet.fetchFiatPrices(currency: any(named: 'currency'), enabled: any(named: 'enabled')))
        .thenAnswer((_) async => const Ok(FiatPricesUpdate(prices: {'tx': 1.0}, currentBtcPrice: 50000.0)));

    await cubit.setFiatConfig(true, 'eur', PriceProviderType.coinGecko);
    await Future.delayed(Duration.zero);
    final s = cubit.state as WalletDetailLoaded;
    expect(s.fiatCurrency, 'eur');
    expect(s.currentBtcPrice, 50000.0);
    await cubit.close();
  });

  test('fetchMissingFiatPrices error path emits errorMessage', () async {
    final cubit = await loadCubit(opener: opener, sync: sync, wallet: wallet);
    when(() => wallet.fetchFiatPrices(currency: any(named: 'currency'), enabled: any(named: 'enabled')))
        .thenAnswer((_) async => const Err('rate-limited'));
    // ignore: invalid_use_of_protected_member
    await cubit.fetchMissingFiatPrices();
    expect((cubit.state as WalletDetailLoaded).errorMessage, contains('rate-limited'));
    await cubit.close();
  });
}
