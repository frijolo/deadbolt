import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import 'package:deadbolt/cubit/wallet_detail_cubit.dart';
import 'package:deadbolt/cubit/wallet_op_result.dart';
import 'package:deadbolt/cubit/wallet_deltas.dart';
import 'package:deadbolt/cubit/wallet_detail_session.dart' show TransactionPage;
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

  test('loadMoreTransactions: no-op when !hasMore', () async {
    final cubit = await loadCubit(opener: opener, sync: sync, wallet: wallet);
    await cubit.loadMoreTransactions();
    verifyNever(() => wallet.loadMoreTransactions(any()));
    await cubit.close();
  });

  test('loadMoreTransactions happy: appends txs and increments page', () async {
    final view = viewFixture(
      transactions: const TransactionPage(
        transactions: [],
        totalCount: 30,
        hasMore: true,
        currentPage: 0,
      ),
    );
    final cubit = await loadCubit(opener: opener, sync: sync, wallet: wallet, view: view);

    when(() => wallet.loadMoreTransactions(0)).thenAnswer((_) async => const Ok(
          TransactionPageDelta(
            page: APITransactionPage(transactions: [], totalCount: 30, hasMore: false),
            currentPage: 1,
          ),
        ));

    await cubit.loadMoreTransactions();
    final s = cubit.state as WalletDetailLoaded;
    expect(s.currentPage, 1);
    expect(s.hasMore, isFalse);
    await cubit.close();
  });

  test('loadMoreTransactions error: emits errorMessage', () async {
    final view = viewFixture(
      transactions: const TransactionPage(
        transactions: [],
        totalCount: 30,
        hasMore: true,
        currentPage: 0,
      ),
    );
    final cubit = await loadCubit(opener: opener, sync: sync, wallet: wallet, view: view);
    when(() => wallet.loadMoreTransactions(any())).thenAnswer((_) async => const Err('net'));
    await cubit.loadMoreTransactions();
    expect((cubit.state as WalletDetailLoaded).errorMessage, contains('net'));
    await cubit.close();
  });
}
