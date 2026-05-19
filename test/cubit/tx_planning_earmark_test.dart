import 'package:flutter_rust_bridge/flutter_rust_bridge_for_generated.dart'
    show Int64List;
import 'package:flutter_test/flutter_test.dart';

import 'package:deadbolt/cubit/tx_planning_cubit.dart';
import 'package:deadbolt/screens/tx_planning/tx_planning_earmark.dart';
import 'package:deadbolt/src/rust/api/model.dart'
    show APICommitSpacedPlanReport, APIRecipient;

APISpacedPlanDetail _detail({
  required String status,
  required List<APISpacedPlanDetailRow> rows,
  int planId = 1,
}) =>
    APISpacedPlanDetail(
      planId: planId,
      kind: 'MIGRATE',
      dstWalletPath: '/dst.db',
      status: status,
      createdAt: 0,
      updatedAt: 0,
      feerateMinMsatvb: BigInt.zero,
      feerateMaxMsatvb: BigInt.zero,
      delayBlocksMin: 1,
      delayBlocksMax: 1,
      splitProbability: 0,
      minSplitOutput: BigInt.zero,
      spendPathId: 0,
      rows: rows,
    );

APISpacedPlanDetailRow _row(String txid, int vout, int amount) =>
    APISpacedPlanDetailRow(
      psbtId: 1,
      utxoTxid: txid,
      utxoVout: vout,
      amountSat: BigInt.from(amount),
      feeSat: BigInt.zero,
      absNlocktime: 0,
      autoBroadcast: false,
      hasSpentInputs: false,
      recipients: [APIRecipient(address: 'addr', amountSat: BigInt.zero)],
    );

void main() {
  test('empty when state is Idle / Loading / Terminal', () {
    final cases = [
      const TxPlanningLoading(),
      const TxPlanningIdle(),
      TxPlanningTerminal(_detail(status: 'CANCELLED', rows: const [])),
    ];
    for (final s in cases) {
      final e = TxPlanningEarmarks.from(s);
      expect(e.hasAny, false, reason: '$s should be empty');
      expect(e.outpoints, isEmpty);
      expect(e.reservedSat, BigInt.zero);
      expect(e.planId, isNull);
    }
  });

  test('collects outpoints and sums amounts from Draft state', () {
    final detail = _detail(
      status: 'DRAFT',
      rows: [
        _row('aa' * 32, 0, 500_000),
        _row('bb' * 32, 1, 300_000),
      ],
    );
    final e = TxPlanningEarmarks.from(TxPlanningDraft(detail));
    expect(e.hasAny, true);
    expect(e.outpoints, hasLength(2));
    expect(e.contains('${'aa' * 32}:0'), true);
    expect(e.contains('${'bb' * 32}:1'), true);
    expect(e.reservedSat, BigInt.from(800_000));
    expect(e.planId, 1);
  });

  test('Running state also produces earmarks', () {
    final detail = _detail(
      status: 'SIGNED',
      rows: [_row('cc' * 32, 0, 100_000)],
    );
    final e = TxPlanningEarmarks.from(TxPlanningRunning(detail));
    expect(e.contains('${'cc' * 32}:0'), true);
    expect(e.reservedSat, BigInt.from(100_000));
  });

  test('Draft with stale commit report still earmarks rows', () {
    final detail = _detail(
      status: 'DRAFT',
      rows: [_row('dd' * 32, 0, 50_000)],
    );
    final report = APICommitSpacedPlanReport(
      planId: 1,
      committed: false,
      totalCount: 1,
      signedCount: 0,
      unsignedPsbtIds: Int64List.fromList([1]),
    );
    final e = TxPlanningEarmarks.from(
      TxPlanningDraft(detail, lastCommitReport: report),
    );
    expect(e.contains('${'dd' * 32}:0'), true);
  });
}
