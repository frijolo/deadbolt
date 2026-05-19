import 'package:flutter/widgets.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import 'package:deadbolt/cubit/tx_planning_cubit.dart';

/// Derived view of which UTXOs are reserved by an active spaced TX plan
/// and how many sats are tied up. Read it from the cubit's current state
/// with [TxPlanningEarmarks.from] — the source of truth stays in Rust,
/// this is just the Dart-side projection the UI needs.
class TxPlanningEarmarks {
  /// "txid:vout" keys of every UTXO an active plan still holds.
  final Set<String> outpoints;

  /// Sum of input amounts across those UTXOs.
  final BigInt reservedSat;

  /// Plan id (`null` when no active plan).
  final int? planId;

  const TxPlanningEarmarks({
    required this.outpoints,
    required this.reservedSat,
    required this.planId,
  });

  /// `BigInt.zero` is not a const expression, so we can't make this a
  /// true `const`. A single `static final` instance is just as good for
  /// the "no active plan" sentinel.
  static final TxPlanningEarmarks empty = TxPlanningEarmarks(
    outpoints: const <String>{},
    reservedSat: BigInt.zero,
    planId: null,
  );

  bool get hasAny => outpoints.isNotEmpty;
  bool contains(String outpoint) => outpoints.contains(outpoint);

  /// Read the current earmarks from a [BuildContext]. Returns [empty]
  /// when no [TxPlanningCubit] has been provided up the widget tree —
  /// callers can therefore embed the earmark consumers (badge,
  /// breakdown) on screens that have not been wired through the
  /// planning cubit yet.
  static TxPlanningEarmarks of(BuildContext context) {
    try {
      final state = context.read<TxPlanningCubit>().state;
      return TxPlanningEarmarks.from(state);
    } on ProviderNotFoundException {
      return empty;
    }
  }

  /// Reactive variant of [of]. Returns [empty] when no [TxPlanningCubit]
  /// has been provided up the widget tree. Unlike [of], this uses
  /// `context.watch` so the caller rebuilds when the cubit emits a new
  /// state.
  static TxPlanningEarmarks ofWatch(BuildContext context) {
    try {
      final state = context.watch<TxPlanningCubit>().state;
      return TxPlanningEarmarks.from(state);
    } on ProviderNotFoundException {
      return empty;
    }
  }

  /// Build from the cubit's state. Returns [empty] for Idle / Loading /
  /// Terminal — earmarks only exist while a plan is DRAFT or RUNNING
  /// (the states that keep child PSBTs in `unsigned_txs`).
  factory TxPlanningEarmarks.from(TxPlanningState state) {
    final detail = switch (state) {
      TxPlanningDraft(:final detail) => detail,
      TxPlanningRunning(:final detail) => detail,
      _ => null,
    };
    if (detail == null) return empty;
    final outpoints = <String>{};
    var sats = BigInt.zero;
    for (final row in detail.rows) {
      outpoints.add('${row.utxoTxid}:${row.utxoVout}');
      sats += row.amountSat;
    }
    return TxPlanningEarmarks(
      outpoints: outpoints,
      reservedSat: sats,
      planId: detail.planId,
    );
  }
}

