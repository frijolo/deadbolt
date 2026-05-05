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

  test('loadDescriptorAnalysis happy: writes analysis to descriptor view', () async {
    final cubit = await loadCubit(opener: opener, sync: sync, wallet: wallet);
    when(() => wallet.loadDescriptorAnalysis(any())).thenAnswer((_) async => const Ok(
          DescriptorSnapshot(
            analysis: APIAnalysisResult(
              descriptor: 'tr(a)',
              network: APINetwork.signet,
              walletType: APIWalletType.p2Tr,
              keys: [],
              spendPaths: [],
            ),
            keyLabels: {'mfp': 'Alice'},
            pathLabels: {1: 'Co-sign'},
          ),
        ));

    // ignore: invalid_use_of_protected_member
    await cubit.loadDescriptorAnalysis();
    final s = cubit.state as WalletDetailLoaded;
    expect(s.descriptorLoaded, isTrue);
    expect(s.keyLabels['mfp'], 'Alice');
    expect(s.pathLabels[1], 'Co-sign');
    await cubit.close();
  });

  test('loadDescriptorAnalysis error: emits errorMessage', () async {
    final cubit = await loadCubit(opener: opener, sync: sync, wallet: wallet);
    when(() => wallet.loadDescriptorAnalysis(any())).thenAnswer((_) async => const Err('parse fail'));
    // ignore: invalid_use_of_protected_member
    await cubit.loadDescriptorAnalysis();
    expect((cubit.state as WalletDetailLoaded).errorMessage, contains('parse fail'));
    await cubit.close();
  });
}
