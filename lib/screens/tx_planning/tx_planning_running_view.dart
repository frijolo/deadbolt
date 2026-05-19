import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import 'package:deadbolt/cubit/tx_planning_cubit.dart';
import 'package:deadbolt/l10n/l10n.dart';
import 'package:deadbolt/utils/date_format.dart'
    show etaFromBlocks, formatShortSlashed;
import 'package:deadbolt/utils/toast_helper.dart' show showErrorToastException;

/// Running view: signed plan, auto-broadcast loop in charge. Per-row badge
/// states are derived from `auto_broadcast` + `has_spent_inputs`. The
/// `broadcastedTxids` list carries the in-memory snapshot of txids the
/// sync loop has just emitted (those rows have already vanished from
/// `detail.rows` but the badge persists for the user to acknowledge).
class TxPlanningRunningView extends StatelessWidget {
  final APISpacedPlanDetail detail;
  final List<String> broadcastedTxids;
  final int tipHeight;

  const TxPlanningRunningView({
    super.key,
    required this.detail,
    required this.broadcastedTxids,
    required this.tipHeight,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _header(context),
        Expanded(
          child: ListView.separated(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            itemCount: detail.rows.length,
            separatorBuilder: (_, _) => const SizedBox(height: 4),
            itemBuilder: (_, i) =>
                _RunningRowTile(row: detail.rows[i], tipHeight: tipHeight),
          ),
        ),
        if (broadcastedTxids.isNotEmpty) _recentBroadcasts(context),
        _footer(context),
      ],
    );
  }

  Widget _header(BuildContext context) {
    final l10n = context.l10n;
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Card(
        color: cs.secondaryContainer,
        child: ListTile(
          leading: const Icon(Icons.lock_clock),
          title: Text(
            l10n.txPlanningPlanHeader(
              detail.planId.toInt(),
              formatPlanKindLabel(context, detail, l10n)),
          ),
          subtitle: Text(l10n.txPlanningRunningSubtitle(detail.rows.length)),
        ),
      ),
    );
  }

  Widget _recentBroadcasts(BuildContext context) {
    final l10n = context.l10n;
    final cs = Theme.of(context).colorScheme;
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: cs.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            l10n.txPlanningJustBroadcast,
            style: Theme.of(context).textTheme.labelLarge,
          ),
          const SizedBox(height: 4),
          for (final txid in broadcastedTxids)
            Text('• ${_shorten(txid)}',
                style: Theme.of(context).textTheme.bodySmall),
        ],
      ),
    );
  }

  Widget _footer(BuildContext context) {
    final l10n = context.l10n;
    return Padding(
      padding: const EdgeInsets.all(16),
      child: OutlinedButton.icon(
        onPressed: () => _confirmCancel(context),
        icon: const Icon(Icons.close),
        label: Text(l10n.txPlanningStopButton),
      ),
    );
  }

  Future<void> _confirmCancel(BuildContext context) async {
    final l10n = context.l10n;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l10n.txPlanningStopDialogTitle),
        content: Text(l10n.txPlanningStopDialogBody),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text(l10n.txPlanningKeepRunningButton),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text(l10n.txPlanningStopShortButton),
          ),
        ],
      ),
    );
    if (ok == true && context.mounted) {
      try {
        await context.read<TxPlanningCubit>().cancel();
      } catch (e) {
        showErrorToastException(e);
      }
    }
  }

  String _shorten(String s) =>
      s.length > 16 ? '${s.substring(0, 8)}…${s.substring(s.length - 4)}' : s;
}

class _RunningRowTile extends StatelessWidget {
  final APISpacedPlanDetailRow row;
  final int tipHeight;
  const _RunningRowTile({required this.row, required this.tipHeight});

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final cs = Theme.of(context).colorScheme;
    final (icon, label, color) = switch (row) {
      _ when row.hasSpentInputs => (
          Icons.error_outline,
          l10n.txPlanningRowInputsSpent,
          cs.error,
        ),
      _ when row.autoBroadcast => (
          Icons.schedule,
          _armedLabel(l10n, row.absNlocktime),
          cs.primary,
        ),
      _ => (Icons.pause_circle, l10n.txPlanningRowIdle, cs.outline),
    };
    return Card(
      child: ListTile(
        leading: Icon(icon, color: color),
        title: Text(
          l10n.txPlanningRowAmountTitle(
            row.amountSat.toInt(),
            row.psbtId.toInt(),
          ),
        ),
        subtitle: Text(label, style: TextStyle(color: color)),
      ),
    );
  }

  /// Subtitle for an armed row: `YYYY/MM/DD HH:MM (NNN blocks left)`.
  /// Falls back to the block-height-only label when the wallet hasn't
  /// produced a chain tip yet (e.g. initial sync), since we can't
  /// project an ETA without it.
  String _armedLabel(AppLocalizations l10n, int targetHeight) {
    if (tipHeight > 0) {
      final blocksLeft = targetHeight - tipHeight;
      if (blocksLeft > 0) {
        return l10n.txPlanningRowArmedEta(
          formatShortSlashed(etaFromBlocks(blocksLeft)),
          blocksLeft,
        );
      }
    }
    return l10n.txPlanningRowArmed(targetHeight);
  }
}
