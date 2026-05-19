import 'package:flutter/material.dart';

import 'package:deadbolt/l10n/l10n.dart';
import 'package:deadbolt/src/rust/api/model.dart';
import 'package:deadbolt/theme/app_theme.dart';
import 'package:deadbolt/utils/bitcoin_formatter.dart' show BitcoinFormatter;
import 'package:deadbolt/models/timelock_types.dart' show AbsoluteTimelockType;

/// Shared display helpers for the spend-path dropdown used by
/// `create_tx_screen.dart` and `tx_planning/tx_planning_idle_view.dart`.
///
/// Keeping the two pickers in lockstep prevents the planning flow from
/// drifting away from the send flow's UX — `pathLabel` and
/// `pathTimelockStatus` are the dropdown's identity bits (label + the
/// lock/unlock indicator next to each option).

/// Friendly name for the dropdown item. Falls back to a
/// `{threshold}-of-{N} ({keys})` summary when no explicit `pathLabels`
/// entry is set.
String pathLabel(
  APISpendPath path, {
  required Map<String, String> keyLabels,
  required Map<int, String> pathLabels,
}) {
  final explicit = pathLabels[path.id];
  if (explicit != null && explicit.isNotEmpty) return explicit;
  final keys = path.mfps
      .map((m) => keyLabels[m] ?? m.substring(0, 4).toUpperCase())
      .join(' + ');
  final threshold = '${path.threshold}-of-${path.mfps.length}';
  return '$threshold ($keys)';
}

/// Lock / unlock indicator shown next to each dropdown item.
///
/// Returns `null` when the path has no timelock — the dropdown row then
/// renders without an icon. The tuple shape mirrors the inline record
/// that used to live on `create_tx_screen.dart`'s `_timelockStatus`.
///
/// `utxoMaxConfHeight` is the highest confirmation height across the
/// UTXOs the user wants to spend with this path; needed only for
/// relative-block timelocks (BIP68). Pass `null` when the caller hasn't
/// resolved the selection yet — relative-block paths fall through to a
/// "sync required" hint in that case.
({IconData icon, String text, Color color})? pathTimelockStatus(
  BuildContext context,
  APISpendPath path, {
  required int tipHeight,
  required int? utxoMaxConfHeight,
  required bool hasSelectedUtxos,
}) {
  final l10n = context.l10n;
  final theme = Theme.of(context);
  final hasRel = path.relTimelock.value > 0;
  final hasAbs = path.absTimelock.value > 0;
  if (!hasRel && !hasAbs) return null;

  if (hasRel && path.relTimelock.timelockType == APIRelativeTimelockType.blocks) {
    final relBlocks = path.relTimelock.value;
    if (!hasSelectedUtxos) return null;
    if (utxoMaxConfHeight == null || tipHeight == 0) {
      return (
        icon: Icons.sync_disabled_outlined,
        text: l10n.psbtTimelockSyncRequired,
        color: theme.colorScheme.onSurface.withAlpha(AppAlpha.inactive),
      );
    }
    final remaining = (utxoMaxConfHeight + relBlocks) - tipHeight - 1;
    if (remaining > 0) {
      return (
        icon: Icons.lock_outline,
        text: l10n.psbtTimelockBlocksRemaining(
          remaining,
          BitcoinFormatter.formatDuration(remaining * 10),
        ),
        color: Colors.orange,
      );
    }
    return (
      icon: Icons.lock_open_outlined,
      text: l10n.spendPathUnlocked,
      color: Colors.green,
    );
  }

  if (hasAbs) {
    final absType = AbsoluteTimelockType.fromString(path.absTimelock.timelockType.name);
    final absValue = path.absTimelock.value;
    if (absType == AbsoluteTimelockType.blocks) {
      if (tipHeight == 0) {
        return (
          icon: Icons.sync_disabled_outlined,
          text: l10n.psbtTimelockSyncRequired,
          color: theme.colorScheme.onSurface.withAlpha(AppAlpha.inactive),
        );
      }
      final remaining = absValue - tipHeight;
      if (remaining > 0) {
        return (
          icon: Icons.lock_outline,
          text: l10n.psbtTimelockBlocksRemaining(
            remaining,
            BitcoinFormatter.formatDuration(remaining * 10),
          ),
          color: Colors.orange,
        );
      }
      return (
        icon: Icons.lock_open_outlined,
        text: l10n.spendPathUnlocked,
        color: Colors.green,
      );
    } else {
      final nowSecs = DateTime.now().millisecondsSinceEpoch ~/ 1000;
      final remaining = absValue - nowSecs;
      if (remaining > 0) {
        return (
          icon: Icons.lock_outline,
          text: l10n.psbtTimelockTimeRemaining(
            BitcoinFormatter.formatDuration(remaining ~/ 60),
          ),
          color: Colors.orange,
        );
      }
      return (
        icon: Icons.lock_open_outlined,
        text: l10n.spendPathUnlocked,
        color: Colors.green,
      );
    }
  }

  return null;
}
