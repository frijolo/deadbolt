import 'dart:async';

import 'package:flutter/widgets.dart' show BuildContext;
import 'package:flutter_bloc/flutter_bloc.dart';

import 'package:deadbolt/cubit/cubit_error_logger.dart';
import 'package:deadbolt/cubit/wallet_list_cubit.dart';
import 'package:deadbolt/l10n/l10n.dart' show AppLocalizations;
import 'package:deadbolt/services/wallet_service.dart';
import 'package:deadbolt/services/wallet_sync_service.dart';
import 'package:deadbolt/utils/toast_helper.dart' show showErrorToastException;
import 'package:deadbolt/src/rust/api/model.dart'
    show
        APIBatchSignFailure,
        APIBatchSignReport,
        APICommitSpacedPlanReport,
        APIPsbtSignerStatus,
        APISignedChildPsbt,
        APISpacedPlanAddressLabel,
        APISpacedPlanDetail,
        APISpacedPlanParams,
        APISpacedPlanSigningBundle,
        APISpacedPlanSummary;
import 'package:deadbolt/src/rust/api/wallet.dart' show ApiWallet;
import 'package:flutter_rust_bridge/flutter_rust_bridge_for_generated.dart'
    show PlatformInt64;

export 'package:deadbolt/src/rust/api/model.dart'
    show
        APIBatchSignFailure,
        APIBatchSignReport,
        APICommitSpacedPlanReport,
        APIPsbtSignerStatus,
        APISignedChildPsbt,
        APISpacedPlanChildPsbt,
        APISpacedPlanDetail,
        APISpacedPlanDetailRow,
        APISpacedPlanParams,
        APISpacedPlanRow,
        APISpacedPlanSigningBundle,
        APISpacedPlanSummary;

// ---------------------------------------------------------------------------
// States
// ---------------------------------------------------------------------------

/// Where the source wallet sits in the spaced-TX flow. The `Idle` branch is
/// the default "no active plan" landing; the `Draft` / `Running` / `Terminal`
/// branches mirror the §3 state machine and each carries a fresh
/// [APISpacedPlanDetail] read from the Rust side.
sealed class TxPlanningState {
  const TxPlanningState();
}

class TxPlanningLoading extends TxPlanningState {
  const TxPlanningLoading();
}

class TxPlanningIdle extends TxPlanningState {
  /// Most recent terminal plan, if any — useful for "Last cancelled at X"
  /// hints on the idle screen. `null` until the user runs at least one
  /// plan in this wallet.
  final APISpacedPlanDetail? lastTerminal;
  const TxPlanningIdle({this.lastTerminal});
}

/// Rolling counter of a batch sign / merge attempt. Reset to `null` once
/// the user kicks off a new attempt; the new attempt's first emission
/// carries `signed = 0` and `failed = []` so the UI never shows mixed
/// state across batches.
class SignProgress {
  final int total;
  final int signed;
  final List<APIBatchSignFailure> failed;
  const SignProgress({
    required this.total,
    required this.signed,
    this.failed = const [],
  });

  factory SignProgress.fromReport(APIBatchSignReport report) => SignProgress(
        total: report.total,
        signed: report.signedIds.length,
        failed: report.failed,
      );

  bool get isComplete => signed == total && failed.isEmpty;
}

class TxPlanningDraft extends TxPlanningState {
  final APISpacedPlanDetail detail;
  /// Last commit attempt's report — `null` until the user pressed Commit
  /// at least once. Drives the "X of Y signed" badge on the draft view.
  final APICommitSpacedPlanReport? lastCommitReport;
  /// Last batch sign / merge result. `null` before the user picks a
  /// signer; populated by [TxPlanningCubit.signBatchWithHotKey] and
  /// [TxPlanningCubit.applySignedPsbts]. Distinct from
  /// [lastCommitReport] because commit audits *every* row's stored
  /// signatures, while a batch only covers the rows just submitted.
  final SignProgress? signProgress;
  /// Per-child analysed signer status, keyed by `psbtId`. Populated
  /// lazily by [TxPlanningCubit._refreshSignerSnapshot] after every
  /// state transition into Draft. `null` until the first snapshot
  /// lands or when prepareSpacedPlanPsbts fails — the view falls back
  /// to "unknown" badges in that case.
  final Map<int, List<APIPsbtSignerStatus>>? signers;
  const TxPlanningDraft(
    this.detail, {
    this.lastCommitReport,
    this.signProgress,
    this.signers,
  });

  TxPlanningDraft copyWith({
    APISpacedPlanDetail? detail,
    APICommitSpacedPlanReport? lastCommitReport,
    SignProgress? signProgress,
    Map<int, List<APIPsbtSignerStatus>>? signers,
  }) =>
      TxPlanningDraft(
        detail ?? this.detail,
        lastCommitReport: lastCommitReport ?? this.lastCommitReport,
        signProgress: signProgress ?? this.signProgress,
        signers: signers ?? this.signers,
      );
}

class TxPlanningRunning extends TxPlanningState {
  final APISpacedPlanDetail detail;
  /// Txids broadcast by the auto-broadcast loop since this state was
  /// entered. Children that disappear from `detail.rows` are the ones the
  /// running view should render as "Broadcast (txid…)" badges.
  final List<String> broadcastedTxids;
  const TxPlanningRunning(this.detail, {this.broadcastedTxids = const []});

  TxPlanningRunning copyWith({
    APISpacedPlanDetail? detail,
    List<String>? broadcastedTxids,
  }) =>
      TxPlanningRunning(
        detail ?? this.detail,
        broadcastedTxids: broadcastedTxids ?? this.broadcastedTxids,
      );
}

class TxPlanningTerminal extends TxPlanningState {
  final APISpacedPlanDetail detail;
  const TxPlanningTerminal(this.detail);
}

// ---------------------------------------------------------------------------
// Status helpers
// ---------------------------------------------------------------------------

/// Stable mapping between Rust's status strings and Dart enum. Keeps every
/// switch in this file (and the views) string-free.
enum TxPlanningStatus { draft, signed, running, done, cancelled, failed }

TxPlanningStatus parseTxPlanningStatus(String s) => switch (s) {
      'DRAFT' => TxPlanningStatus.draft,
      'SIGNED' => TxPlanningStatus.signed,
      'RUNNING' => TxPlanningStatus.running,
      'DONE' => TxPlanningStatus.done,
      'CANCELLED' => TxPlanningStatus.cancelled,
      'FAILED' => TxPlanningStatus.failed,
      _ => TxPlanningStatus.failed,
    };

bool _isTerminal(TxPlanningStatus s) =>
    s == TxPlanningStatus.done ||
    s == TxPlanningStatus.cancelled ||
    s == TxPlanningStatus.failed;

/// Human label for a plan's kind used in titles/headers.
///
/// - `Refresh` → just the localised "Refresh" word; the destination
///   is the wallet itself, so naming it adds no information.
/// - `Migrate` → `"Migration → <walletName>"` when [walletName] is
///   provided; falls back to plain `"Migration"` when it is `null`.
String formatPlanKindLabel(
  BuildContext context,
  APISpacedPlanDetail detail,
  AppLocalizations l, {
  String? walletName,
}) {
  if (detail.kind != 'MIGRATE') return l.txPlanningRefresh;
  if (walletName != null) return '${l.txPlanningMigrate} → $walletName';
  // Fallback: look up in the wallet list cubit (wallet may have been
  // deleted or list not loaded yet).
  final state = context.read<WalletListCubit>().state;
  if (state is! WalletListLoaded) return l.txPlanningMigrate;
  for (final w in state.wallets) {
    if (w.walletPath == detail.dstWalletPath) {
      return '${l.txPlanningMigrate} → ${w.name}';
    }
  }
  return l.txPlanningMigrate;
}

// ---------------------------------------------------------------------------
// Cubit
// ---------------------------------------------------------------------------

class TxPlanningCubit extends Cubit<TxPlanningState> with CubitErrorLogger {
  final ApiWallet _wallet;
  final String _walletPath;
  final WalletSyncService? _syncService;
  /// Used to re-open the destination wallet on cancel of a `Migrate`
  /// plan so the cubit can sweep the auto-labels it had written into
  /// the destination DB. `null` only in tests / in flows that don't
  /// need cross-wallet label maintenance.
  final WalletService? _walletService;

  StreamSubscription<WalletSyncEvent>? _syncEventSub;

  TxPlanningCubit({
    required ApiWallet wallet,
    required String walletPath,
    WalletSyncService? syncService,
    WalletService? walletService,
  })  : _wallet = wallet,
        _walletPath = walletPath,
        _syncService = syncService,
        _walletService = walletService,
        super(const TxPlanningLoading()) {
    _subscribeToSyncService();
    unawaited(load());
  }

  // -------------------------------------------------------------------------
  // Public API
  // -------------------------------------------------------------------------

  /// Read the most-recent plan (active or terminal) and route to the
  /// matching state. Safe to call at any time — used as a refresh after
  /// signing, cancel, or an auto-broadcast event.
  Future<void> load() async {
    // Yield once so callers that attach listeners after constructing the
    // cubit (the common case) observe every state change. Without this
    // the first `emit` would run synchronously inside the constructor's
    // microtask, before any listener has subscribed.
    await Future<void>.delayed(Duration.zero);
    try {
      final plans = _wallet.listSpacedPlans();
      // listSpacedPlans returns newest-first; the first row is what the UI
      // should land on.
      if (plans.isEmpty) {
        emit(const TxPlanningIdle());
        return;
      }
      final head = plans.first;
      final status = parseTxPlanningStatus(head.status);
      if (_isTerminal(status)) {
        // No active plan; show idle but surface the last terminal as
        // history.
        emit(TxPlanningIdle(lastTerminal: head));
        return;
      }
      // Carry over any in-memory broadcast badges from a previous
      // Running state so the user keeps seeing "tx X broadcast as <txid>"
      // across the refresh that the auto-broadcast event triggers.
      final priorTxids = switch (state) {
        TxPlanningRunning(broadcastedTxids: final t) => t,
        _ => const <String>[],
      };
      emit(_routeActive(head, status, priorTxids: priorTxids));
    } catch (e, st) {
      logError('TxPlanningCubit.load()', e, st);
      // Cubit is already past wallet-open; surface the failure as a
      // toast and land on Idle so the user can retry instead of being
      // stuck on a full-screen error.
      showErrorToastException(e);
      emit(const TxPlanningIdle());
    }
  }

  /// Compose + persist a new DRAFT plan. The caller is responsible for
  /// peeking [APISpacedPlanParams.dstAddresses] from the destination
  /// wallet ahead of time.
  ///
  /// For `Migrate` plans the caller must also pass [dstWallet] — the
  /// open handle of the destination wallet — so the cubit can mirror
  /// every child PSBT's label onto the destination's `address_labels`
  /// (the planner only writes them on the source DB, and source ≠
  /// destination in this mode). Failing to seed those labels is
  /// reported via toast but does not unwind the plan: the funds still
  /// move, only the per-address label inheritance on receive is lost.
  Future<APISpacedPlanSummary?> createPlan(
    APISpacedPlanParams params, {
    ApiWallet? dstWallet,
  }) async {
    try {
      final summary = _wallet.planSpacedTxs(params: params);
      if (dstWallet != null) {
        _seedDstAddressLabels(
          dstWallet: dstWallet,
          planId: summary.planId,
          summary: summary,
        );
      }
      // After plan_spaced_txs the plan is DRAFT in Rust; re-read the
      // detail so the state carries the canonical row.
      final detail = _wallet.getSpacedPlan(planId: summary.planId);
      emit(TxPlanningDraft(
        detail,
        signers: _signersSnapshotOrNull(detail.planId.toInt()),
      ));
      return summary;
    } catch (e, st) {
      logError('TxPlanningCubit.createPlan()', e, st);
      rethrow;
    }
  }

  /// Mirror each row's label onto the destination wallet's
  /// `address_labels` so the destination's UI surfaces meaningful
  /// names for incoming UTXOs. Best-effort: a failure here is shown
  /// as a toast and the plan creation is still considered successful.
  void _seedDstAddressLabels({
    required ApiWallet dstWallet,
    required PlatformInt64 planId,
    required APISpacedPlanSummary summary,
  }) {
    try {
      final entries = <APISpacedPlanAddressLabel>[];
      for (final row in summary.rows) {
        if (row.label.isEmpty) continue;
        for (final addr in row.recipientAddresses) {
          entries.add(APISpacedPlanAddressLabel(
            planId: planId,
            srcTxid: row.utxoTxid,
            srcVout: row.utxoVout,
            address: addr,
            label: row.label,
          ));
        }
      }
      if (entries.isEmpty) return;
      dstWallet.setSpacedPlanAddressLabels(entries: entries);
    } catch (e, st) {
      logError('TxPlanningCubit._seedDstAddressLabels()', e, st);
      showErrorToastException(e);
    }
  }

  /// Audit signatures on every child PSBT. On success transitions the
  /// state to [TxPlanningRunning]; on partial signing keeps the draft
  /// state and stores the report so the UI can render "X of Y signed".
  Future<APICommitSpacedPlanReport?> commit() async {
    final s = state;
    if (s is! TxPlanningDraft) return null;
    try {
      final report = _wallet.commitSpacedPlan(planId: s.detail.planId);
      if (!report.committed) {
        emit(s.copyWith(lastCommitReport: report));
        return report;
      }
      // Fully signed → re-read so the state carries `status = SIGNED`
      // and any post-commit auto_broadcast flags.
      final detail = _wallet.getSpacedPlan(planId: s.detail.planId);
      emit(_routeActive(detail, parseTxPlanningStatus(detail.status)));
      return report;
    } catch (e, st) {
      logError('TxPlanningCubit.commit()', e, st);
      rethrow;
    }
  }

  /// Discard every child PSBT and mark the plan CANCELLED. Returns to
  /// `Idle` on success. For `Migrate` plans, also sweeps the
  /// auto-labels this cubit had seeded onto the destination wallet's
  /// `address_labels` (best-effort: a failure to reopen the
  /// destination wallet only produces a toast, the source-side cancel
  /// always completes).
  Future<void> cancel() async {
    final s = state;
    final detail = switch (s) {
      TxPlanningDraft(detail: final d) => d,
      TxPlanningRunning(detail: final d) => d,
      _ => null,
    };
    if (detail == null) return;
    try {
      _wallet.cancelSpacedPlan(planId: detail.planId);
      await _clearDstAddressLabels(detail);
      await load();
    } catch (e, st) {
      logError('TxPlanningCubit.cancel()', e, st);
      rethrow;
    }
  }

  /// Re-open the destination wallet and wipe every auto-label tagged
  /// with this plan id. No-op for `Refresh` plans (the source DB
  /// already cleaned itself via `cancel_spaced_plan`) or when the
  /// destination handle can't be reopened (no cached credentials this
  /// session, [WalletService] missing in tests, etc.).
  Future<void> _clearDstAddressLabels(APISpacedPlanDetail detail) async {
    if (detail.kind != 'MIGRATE') return;
    final svc = _walletService;
    if (svc == null) return;
    try {
      final dst = await svc.openWallet(detail.dstWalletPath);
      dst.clearSpacedPlanLabels(planId: detail.planId);
    } catch (e, st) {
      logError('TxPlanningCubit._clearDstAddressLabels()', e, st);
      showErrorToastException(e);
    }
  }

  /// Sign every pending child PSBT of the current DRAFT plan with the
  /// hot key identified by `mfp`. Returns the FFI report so the caller
  /// can decide what to surface (the cubit also stores it on the new
  /// [TxPlanningDraft.signProgress]).
  ///
  /// Errors mid-batch don't abort: the Rust endpoint reports per-row
  /// failures, the cubit stays in Draft, and the UI can offer a retry.
  Future<APIBatchSignReport?> signBatchWithHotKey(String mfp) async {
    final s = state;
    if (s is! TxPlanningDraft) return null;
    try {
      final report = _wallet.signSpacedPlanWithHotKey(
        planId: s.detail.planId,
        mfp: mfp,
      );
      // Re-read so the next commit sees the freshly-merged signatures.
      final detail = _wallet.getSpacedPlan(planId: s.detail.planId);
      emit(TxPlanningDraft(
        detail,
        lastCommitReport: s.lastCommitReport,
        signProgress: SignProgress.fromReport(report),
        signers: _signersSnapshotOrNull(detail.planId.toInt()),
      ));
      return report;
    } catch (e, st) {
      logError('TxPlanningCubit.signBatchWithHotKey()', e, st);
      rethrow;
    }
  }

  /// Read every pending child PSBT of the current DRAFT plan together
  /// with plan-level signing context (descriptor / threshold / key
  /// changes). Used by the HW and QR batch flows in the widget layer to
  /// drive their signer once instead of opening the wallet per PSBT.
  ///
  /// Does not change the cubit's state — the caller still has to push
  /// the signed bundle back through [applySignedPsbts] for the merge.
  Future<APISpacedPlanSigningBundle?> prepareForBatchSigning() async {
    final s = state;
    if (s is! TxPlanningDraft) return null;
    try {
      return _wallet.prepareSpacedPlanPsbts(planId: s.detail.planId);
    } catch (e, st) {
      logError('TxPlanningCubit.prepareForBatchSigning()', e, st);
      rethrow;
    }
  }

  /// Merge an externally-signed batch (HW signer output / QR import)
  /// into the matching children of the current DRAFT plan. Mirrors
  /// [signBatchWithHotKey] for the report + state contract: never
  /// aborts on per-row errors, stays in Draft, stores progress.
  Future<APIBatchSignReport?> applySignedPsbts(
    List<APISignedChildPsbt> signed,
  ) async {
    final s = state;
    if (s is! TxPlanningDraft) return null;
    try {
      final report = _wallet.applySpacedPlanSignedPsbts(
        planId: s.detail.planId,
        signed: signed,
      );
      final detail = _wallet.getSpacedPlan(planId: s.detail.planId);
      emit(TxPlanningDraft(
        detail,
        lastCommitReport: s.lastCommitReport,
        signProgress: SignProgress.fromReport(report),
        signers: _signersSnapshotOrNull(detail.planId.toInt()),
      ));
      return report;
    } catch (e, st) {
      logError('TxPlanningCubit.applySignedPsbts()', e, st);
      rethrow;
    }
  }

  /// Manually re-read the active plan's detail. Used by the UI after the
  /// user signs a child PSBT via the existing PSBT-detail flow.
  Future<void> refresh() => load();

  @override
  Future<void> close() async {
    await _syncEventSub?.cancel();
    return super.close();
  }

  // -------------------------------------------------------------------------
  // Internals
  // -------------------------------------------------------------------------

  /// Best-effort fetch of the per-child signer snapshot used by the
  /// draft view to render per-row badges. Returns `null` (not throws)
  /// when prepareSpacedPlanPsbts fails — the view falls back to
  /// "unknown" badges in that case so an FFI hiccup never blocks the
  /// rest of the flow.
  Map<int, List<APIPsbtSignerStatus>>? _signersSnapshotOrNull(int planId) {
    try {
      final bundle = _wallet.prepareSpacedPlanPsbts(planId: planId);
      return {for (final c in bundle.children) c.psbtId.toInt(): c.signers};
    } catch (_) {
      return null;
    }
  }

  TxPlanningState _routeActive(
    APISpacedPlanDetail detail,
    TxPlanningStatus status, {
    List<String> priorTxids = const [],
  }) {
    switch (status) {
      case TxPlanningStatus.draft:
        return TxPlanningDraft(
          detail,
          signers: _signersSnapshotOrNull(detail.planId.toInt()),
        );
      case TxPlanningStatus.signed:
      case TxPlanningStatus.running:
        // Once every child has auto-broadcast, `rows` is empty — treat
        // the plan as terminal for UI purposes even before Rust tags it
        // DONE (the SIGNED → DONE transition lands in a follow-up).
        if (detail.rows.isEmpty) return TxPlanningTerminal(detail);
        return TxPlanningRunning(detail, broadcastedTxids: priorTxids);
      case TxPlanningStatus.done:
      case TxPlanningStatus.cancelled:
      case TxPlanningStatus.failed:
        return TxPlanningTerminal(detail);
    }
  }

  void _subscribeToSyncService() {
    _syncEventSub = _syncService?.events.listen((event) {
      if (event.walletPath != _walletPath) return;
      if (event.autoBroadcasted.isEmpty) return;
      final s = state;
      if (s is! TxPlanningRunning) return;
      final ourChildIds =
          s.detail.rows.map((r) => r.psbtId).toSet();
      final relevant = event.autoBroadcasted
          .where((r) => ourChildIds.contains(r.id))
          .toList();
      if (relevant.isEmpty) return;
      // We hold an interim "txid badges" snapshot while we kick off a
      // refresh; the refresh in turn re-routes the state once Rust's
      // view of the plan catches up.
      final newTxids = [
        ...s.broadcastedTxids,
        for (final r in relevant)
          if (r.txid != null) r.txid!,
      ];
      emit(s.copyWith(broadcastedTxids: newTxids));
      unawaited(load());
    });
  }
}
