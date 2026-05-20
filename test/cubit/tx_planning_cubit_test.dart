import 'dart:async';

import 'package:flutter_rust_bridge/flutter_rust_bridge_for_generated.dart'
    show Int64List;
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import 'package:deadbolt/cubit/tx_planning_cubit.dart';
import 'package:deadbolt/services/wallet_sync_service.dart';
import 'package:deadbolt/src/rust/api/model.dart'
    show
        APIAutoBroadcastResult,
        APIBatchSignFailure,
        APIBatchSignReport,
        APICommitSpacedPlanReport,
        APINetwork,
        APIPsbtSignerStatus,
        APIRecipient,
        APISignedChildPsbt,
        APISpacedPlanChildPsbt,
        APISpacedPlanDetail,
        APISpacedPlanDetailRow,
        APISpacedPlanParams,
        APISpacedPlanRow,
        APISpacedPlanSigningBundle,
        APISpacedPlanSummary;
import 'package:deadbolt/src/rust/api/wallet.dart' show ApiWallet;

class _MockApiWallet extends Mock implements ApiWallet {}

class _MockWalletSyncService extends Mock implements WalletSyncService {}

const _walletPath = '/wallets/src.db';

APISpacedPlanDetail _draftDetail({
  int planId = 1,
  List<APISpacedPlanDetailRow> rows = const [],
}) =>
    APISpacedPlanDetail(
      planId: planId,
      kind: 'MIGRATE',
      dstWalletPath: '/wallets/dst.db',
      status: 'DRAFT',
      createdAt: 1_700_000_000,
      updatedAt: 1_700_000_000,
      feerateMinMsatvb: BigInt.from(2000),
      feerateMaxMsatvb: BigInt.from(8000),
      delayBlocksMin: 1,
      delayBlocksMax: 100,
      splitProbability: 0.5,
      minSplitOutput: BigInt.from(100_000),
      spendPathId: 0,
      rows: rows,
    );

APISpacedPlanDetail _runningDetail({
  int planId = 1,
  List<APISpacedPlanDetailRow> rows = const [],
}) =>
    APISpacedPlanDetail(
      planId: planId,
      kind: 'MIGRATE',
      dstWalletPath: '/wallets/dst.db',
      status: 'SIGNED',
      createdAt: 1_700_000_000,
      updatedAt: 1_700_000_000,
      feerateMinMsatvb: BigInt.from(2000),
      feerateMaxMsatvb: BigInt.from(8000),
      delayBlocksMin: 1,
      delayBlocksMax: 100,
      splitProbability: 0.5,
      minSplitOutput: BigInt.from(100_000),
      spendPathId: 0,
      rows: rows,
    );

APISpacedPlanDetailRow _row(int psbtId) => APISpacedPlanDetailRow(
      psbtId: psbtId,
      utxoTxid: 'aa' * 32,
      utxoVout: 0,
      amountSat: BigInt.from(500_000),
      feeSat: BigInt.from(1_000),
      absNlocktime: 800_050,
      autoBroadcast: false,
      hasSpentInputs: false,
      recipients: [APIRecipient(address: 'addr', amountSat: BigInt.from(499_000))],
    );

void main() {
  late _MockApiWallet wallet;
  late _MockWalletSyncService syncService;
  late StreamController<WalletSyncEvent> events;

  setUp(() {
    wallet = _MockApiWallet();
    syncService = _MockWalletSyncService();
    events = StreamController<WalletSyncEvent>.broadcast();
    when(() => syncService.events).thenAnswer((_) => events.stream);
  });

  tearDown(() async {
    await events.close();
  });

  TxPlanningCubit build() => TxPlanningCubit(
        wallet: wallet,
        walletPath: _walletPath,
        syncService: syncService,
      );

  Future<void> letLoadSettle(TxPlanningCubit cubit) =>
      cubit.stream.firstWhere((s) => s is! TxPlanningLoading);

  // ---------------------------------------------------------------------------
  // load() routing
  // ---------------------------------------------------------------------------

  test('idle when no plans exist', () async {
    when(() => wallet.listSpacedPlans()).thenReturn([]);
    final cubit = build();
    await letLoadSettle(cubit);
    expect(cubit.state, isA<TxPlanningIdle>());
    expect((cubit.state as TxPlanningIdle).lastTerminal, isNull);
    await cubit.close();
  });

  test('idle with lastTerminal when latest plan is cancelled', () async {
    final cancelled = APISpacedPlanDetail(
      planId: 7,
      kind: 'MIGRATE',
      dstWalletPath: '/wallets/dst.db',
      status: 'CANCELLED',
      createdAt: 1,
      updatedAt: 2,
      feerateMinMsatvb: BigInt.zero,
      feerateMaxMsatvb: BigInt.zero,
      delayBlocksMin: 1,
      delayBlocksMax: 1,
      splitProbability: 0,
      minSplitOutput: BigInt.zero,
      spendPathId: 0,
      rows: const [],
    );
    when(() => wallet.listSpacedPlans()).thenReturn([cancelled]);
    final cubit = build();
    await letLoadSettle(cubit);
    final s = cubit.state as TxPlanningIdle;
    expect(s.lastTerminal?.planId, 7);
    await cubit.close();
  });

  test('draft state when latest plan is DRAFT', () async {
    final detail = _draftDetail(rows: [_row(10), _row(11)]);
    when(() => wallet.listSpacedPlans()).thenReturn([detail]);
    final cubit = build();
    await letLoadSettle(cubit);
    expect(cubit.state, isA<TxPlanningDraft>());
    expect((cubit.state as TxPlanningDraft).detail.planId, 1);
    await cubit.close();
  });

  test('draft carries signers map when prepareSpacedPlanPsbts succeeds',
      () async {
    final detail = _draftDetail(rows: [_row(10), _row(11)]);
    when(() => wallet.listSpacedPlans()).thenReturn([detail]);
    when(() => wallet.prepareSpacedPlanPsbts(planId: 1)).thenReturn(
      const APISpacedPlanSigningBundle(
        planId: 1,
        descriptor: 'wsh(...)',
        network: APINetwork.bitcoin,
        threshold: 2,
        mfps: ['aaaaaaaa', 'bbbbbbbb'],
        keyChanges: {'aaaaaaaa': 0, 'bbbbbbbb': 0},
        children: [
          APISpacedPlanChildPsbt(
            psbtId: 10,
            psbtB64: 'b64',
            signers: [
              APIPsbtSignerStatus(mfp: 'aaaaaaaa', hasSigned: true),
              APIPsbtSignerStatus(mfp: 'bbbbbbbb', hasSigned: false),
            ],
            isFinalized: false,
          ),
          APISpacedPlanChildPsbt(
            psbtId: 11,
            psbtB64: 'b64-2',
            signers: [
              APIPsbtSignerStatus(mfp: 'aaaaaaaa', hasSigned: false),
              APIPsbtSignerStatus(mfp: 'bbbbbbbb', hasSigned: false),
            ],
            isFinalized: false,
          ),
        ],
      ),
    );
    final cubit = build();
    await letLoadSettle(cubit);
    final s = cubit.state as TxPlanningDraft;
    expect(s.signers, isNotNull);
    expect(s.signers!.length, 2);
    expect(s.signers![10]!.first.hasSigned, isTrue);
    expect(s.signers![11]!.every((x) => !x.hasSigned), isTrue);
    await cubit.close();
  });

  test('running state when latest plan is SIGNED with children', () async {
    final detail = _runningDetail(rows: [_row(10)]);
    when(() => wallet.listSpacedPlans()).thenReturn([detail]);
    final cubit = build();
    await letLoadSettle(cubit);
    expect(cubit.state, isA<TxPlanningRunning>());
    await cubit.close();
  });

  test('terminal state when latest SIGNED plan has no remaining children',
      () async {
    final detail = _runningDetail(rows: const []);
    when(() => wallet.listSpacedPlans()).thenReturn([detail]);
    final cubit = build();
    await letLoadSettle(cubit);
    expect(cubit.state, isA<TxPlanningTerminal>());
    await cubit.close();
  });

  // ---------------------------------------------------------------------------
  // commit()
  // ---------------------------------------------------------------------------

  test('commit keeps draft + stores report when not fully signed', () async {
    final detail = _draftDetail(rows: [_row(10), _row(11)]);
    when(() => wallet.listSpacedPlans()).thenReturn([detail]);
    when(() => wallet.commitSpacedPlan(planId: 1)).thenReturn(
      APICommitSpacedPlanReport(
        planId: 1,
        committed: false,
        totalCount: 2,
        signedCount: 1,
        unsignedPsbtIds: Int64List.fromList([11]),
      ),
    );
    final cubit = build();
    await letLoadSettle(cubit);
    final report = await cubit.commit();
    expect(report?.committed, false);
    expect(cubit.state, isA<TxPlanningDraft>());
    expect((cubit.state as TxPlanningDraft).lastCommitReport?.signedCount, 1);
    await cubit.close();
  });

  test('commit transitions to running when fully signed', () async {
    final draftDetail = _draftDetail(rows: [_row(10)]);
    final signedDetail = _runningDetail(rows: [_row(10)]);
    when(() => wallet.listSpacedPlans()).thenReturn([draftDetail]);
    when(() => wallet.commitSpacedPlan(planId: 1)).thenReturn(
      APICommitSpacedPlanReport(
        planId: 1,
        committed: true,
        totalCount: 1,
        signedCount: 1,
        unsignedPsbtIds: Int64List(0),
      ),
    );
    when(() => wallet.getSpacedPlan(planId: 1)).thenReturn(signedDetail);
    final cubit = build();
    await letLoadSettle(cubit);
    final report = await cubit.commit();
    expect(report?.committed, true);
    expect(cubit.state, isA<TxPlanningRunning>());
    await cubit.close();
  });

  // ---------------------------------------------------------------------------
  // cancel()
  // ---------------------------------------------------------------------------

  test('cancel returns to idle and calls FFI with the active plan id',
      () async {
    final draftDetail = _draftDetail(rows: [_row(10)]);
    when(() => wallet.listSpacedPlans()).thenReturn([draftDetail]);
    when(() => wallet.cancelSpacedPlan(planId: 1)).thenReturn(null);
    final cubit = build();
    await letLoadSettle(cubit);

    // After cancel the next listSpacedPlans returns an empty list (the
    // plan vanished from the active set).
    when(() => wallet.listSpacedPlans()).thenReturn([]);
    await cubit.cancel();
    expect(cubit.state, isA<TxPlanningIdle>());
    verify(() => wallet.cancelSpacedPlan(planId: 1)).called(1);
    await cubit.close();
  });

  // ---------------------------------------------------------------------------
  // createPlan()
  // ---------------------------------------------------------------------------

  test('createPlan emits Draft on success', () async {
    when(() => wallet.listSpacedPlans()).thenReturn([]);
    final params = APISpacedPlanParams(
      dstWalletPath: '/wallets/dst.db',
      feerateMinMsatvb: BigInt.from(2000),
      feerateMaxMsatvb: BigInt.from(8000),
      delayBlocksMin: 1,
      delayBlocksMax: 100,
      splitProbability: 0,
      minSplitOutput: BigInt.from(100_000),
      spendPathId: 0,
      threshold: 2,
      mfps: const ['aaaaaaaa', 'bbbbbbbb'],
      policyPath: const [],
      dstAddresses: const ['addr1'],
      selectedUtxos: const [],
    );
    final summary = APISpacedPlanSummary(
      planId: 42,
      tipHeight: 800_000,
      rows: const <APISpacedPlanRow>[],
      totalAmountSat: BigInt.zero,
      totalFeeSat: BigInt.zero,
      droppedUtxoCount: 0,
    );
    final detail = _draftDetail(planId: 42, rows: [_row(10)]);
    when(() => wallet.planSpacedTxs(params: params)).thenReturn(summary);
    when(() => wallet.getSpacedPlan(planId: 42)).thenReturn(detail);

    final cubit = build();
    await letLoadSettle(cubit);
    final result = await cubit.createPlan(params);
    expect(result?.planId, 42);
    expect(cubit.state, isA<TxPlanningDraft>());
    expect((cubit.state as TxPlanningDraft).detail.planId, 42);
    await cubit.close();
  });

  // ---------------------------------------------------------------------------
  // Sync event handling
  // ---------------------------------------------------------------------------

  test('auto-broadcast event for a child triggers a refresh', () async {
    final signedDetail = _runningDetail(rows: [_row(10), _row(11)]);
    when(() => wallet.listSpacedPlans()).thenReturn([signedDetail]);
    final cubit = build();
    await letLoadSettle(cubit);
    expect(cubit.state, isA<TxPlanningRunning>());

    // Now wire a refresh that drops row 10 (broadcast happened).
    final afterDetail = _runningDetail(rows: [_row(11)]);
    when(() => wallet.listSpacedPlans()).thenReturn([afterDetail]);

    events.add(const WalletSyncEvent(
      walletPath: _walletPath,
      autoBroadcasted: [
        APIAutoBroadcastResult(id: 10, txid: 'cafebabe', error: null),
      ],
    ));

    // Wait for the cubit to absorb both the immediate broadcastedTxids
    // update and the follow-up refresh.
    await cubit.stream.firstWhere((s) =>
        s is TxPlanningRunning && s.detail.rows.length == 1);
    final s = cubit.state as TxPlanningRunning;
    expect(s.detail.rows.length, 1);
    expect(s.broadcastedTxids, contains('cafebabe'));
    await cubit.close();
  });

  // ---------------------------------------------------------------------------
  // signBatchWithHotKey()
  // ---------------------------------------------------------------------------

  test('signBatchWithHotKey returns success report and stays in Draft',
      () async {
    final draftDetail = _draftDetail(rows: [_row(10), _row(11)]);
    when(() => wallet.listSpacedPlans()).thenReturn([draftDetail]);
    when(() => wallet.signSpacedPlanWithHotKey(
          planId: 1,
          mfp: 'c449c5c5',
        )).thenReturn(APIBatchSignReport(
      planId: 1,
      total: 2,
      signedIds: Int64List.fromList([10, 11]),
      failed: const [],
    ));
    final refreshed = _draftDetail(rows: [_row(10), _row(11)]);
    when(() => wallet.getSpacedPlan(planId: 1)).thenReturn(refreshed);

    final cubit = build();
    await letLoadSettle(cubit);
    final report = await cubit.signBatchWithHotKey('c449c5c5');
    expect(report?.total, 2);
    expect(report?.signedIds.length, 2);
    expect(report?.failed, isEmpty);
    expect(cubit.state, isA<TxPlanningDraft>());
    await cubit.close();
  });

  test('signBatchWithHotKey keeps Draft and stores per-row failures',
      () async {
    final draftDetail = _draftDetail(rows: [_row(10), _row(11)]);
    when(() => wallet.listSpacedPlans()).thenReturn([draftDetail]);
    when(() => wallet.signSpacedPlanWithHotKey(
          planId: 1,
          mfp: 'deadbeef',
        )).thenReturn(APIBatchSignReport(
      planId: 1,
      total: 2,
      signedIds: Int64List(0),
      failed: const [
        APIBatchSignFailure(psbtId: 10, error: 'no signer for mfp deadbeef'),
        APIBatchSignFailure(psbtId: 11, error: 'no signer for mfp deadbeef'),
      ],
    ));
    when(() => wallet.getSpacedPlan(planId: 1)).thenReturn(draftDetail);

    final cubit = build();
    await letLoadSettle(cubit);
    final report = await cubit.signBatchWithHotKey('deadbeef');
    expect(cubit.state, isA<TxPlanningDraft>());
    expect(report?.signedIds, isEmpty);
    expect(report?.failed.length, 2);
    await cubit.close();
  });

  test('signBatchWithHotKey no-ops when state is not Draft', () async {
    when(() => wallet.listSpacedPlans()).thenReturn([]);
    final cubit = build();
    await letLoadSettle(cubit);
    expect(cubit.state, isA<TxPlanningIdle>());
    final report = await cubit.signBatchWithHotKey('c449c5c5');
    expect(report, isNull);
    // Guard violations no longer transition the cubit — UI is
    // state-aware and the call is defensive. The state stays Idle.
    expect(cubit.state, isA<TxPlanningIdle>());
    verifyNever(() => wallet.signSpacedPlanWithHotKey(
          planId: any(named: 'planId'),
          mfp: any(named: 'mfp'),
        ));
    await cubit.close();
  });

  // ---------------------------------------------------------------------------
  // prepareForBatchSigning() + applySignedPsbts()
  // ---------------------------------------------------------------------------

  test('prepareForBatchSigning returns the FFI bundle and keeps state',
      () async {
    final draftDetail = _draftDetail(rows: [_row(10)]);
    when(() => wallet.listSpacedPlans()).thenReturn([draftDetail]);
    const bundle = APISpacedPlanSigningBundle(
      planId: 1,
      descriptor: 'wsh(...)',
      network: APINetwork.bitcoin,
      threshold: 2,
      mfps: ['aaaaaaaa', 'bbbbbbbb'],
      keyChanges: {'aaaaaaaa': 0, 'bbbbbbbb': 0},
      children: [
        APISpacedPlanChildPsbt(
          psbtId: 10,
          psbtB64: 'b64',
          signers: [
            APIPsbtSignerStatus(mfp: 'aaaaaaaa', hasSigned: false),
          ],
          isFinalized: false,
        ),
      ],
    );
    when(() => wallet.prepareSpacedPlanPsbts(planId: 1)).thenReturn(bundle);
    final cubit = build();
    await letLoadSettle(cubit);
    final got = await cubit.prepareForBatchSigning();
    expect(got?.children.length, 1);
    expect(got?.children.first.psbtId, 10);
    expect(cubit.state, isA<TxPlanningDraft>());
    await cubit.close();
  });

  test('applySignedPsbts merges and returns per-row report', () async {
    final draftDetail = _draftDetail(rows: [_row(10), _row(11)]);
    when(() => wallet.listSpacedPlans()).thenReturn([draftDetail]);
    const input = [
      APISignedChildPsbt(psbtId: 10, signedB64: 'merged-10'),
      APISignedChildPsbt(psbtId: 11, signedB64: 'merged-11'),
    ];
    when(() => wallet.applySpacedPlanSignedPsbts(
          planId: 1,
          signed: input,
        )).thenReturn(APIBatchSignReport(
      planId: 1,
      total: 2,
      signedIds: Int64List.fromList([10]),
      failed: const [
        APIBatchSignFailure(psbtId: 11, error: 'merge error'),
      ],
    ));
    when(() => wallet.getSpacedPlan(planId: 1)).thenReturn(draftDetail);

    final cubit = build();
    await letLoadSettle(cubit);
    final report = await cubit.applySignedPsbts(input);
    expect(report?.signedIds.toList(), [BigInt.from(10)]);
    expect(report?.failed.first.psbtId, 11);
    expect(cubit.state, isA<TxPlanningDraft>());
    await cubit.close();
  });

  test('auto-broadcast event for a different wallet is ignored', () async {
    final signedDetail = _runningDetail(rows: [_row(10)]);
    when(() => wallet.listSpacedPlans()).thenReturn([signedDetail]);
    final cubit = build();
    await letLoadSettle(cubit);
    final stateBefore = cubit.state;

    events.add(const WalletSyncEvent(
      walletPath: '/wallets/other.db',
      autoBroadcasted: [
        APIAutoBroadcastResult(id: 10, txid: 'cafebabe', error: null),
      ],
    ));
    // Give the listener a microtask to run.
    await Future<void>.delayed(Duration.zero);
    expect(cubit.state, same(stateBefore));
    await cubit.close();
  });
}
