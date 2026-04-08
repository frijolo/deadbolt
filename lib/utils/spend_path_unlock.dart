import 'package:deadbolt/src/rust/api/model.dart';

/// Result of checking whether a spend path is available for a given UTXO.
sealed class SpendPathStatus {}

/// The spend path is fully unlocked.
class SpendPathUnlocked extends SpendPathStatus {}

/// The UTXO is unconfirmed (in mempool); relative timelocks require on-chain confirmation.
class SpendPathUnconfirmed extends SpendPathStatus {}

/// The wallet has never been synced; timelock status cannot be evaluated.
class SpendPathNeedsSync extends SpendPathStatus {}

/// Locked by an absolute timelock; [remainingBlocks] > 0 for block-based,
/// [remainingSeconds] > 0 for timestamp-based (null when the other applies).
class SpendPathAbsLocked extends SpendPathStatus {
  final int? remainingBlocks;
  final int? remainingSeconds;
  final int unlockAtBlock;   // valid for block-based; 0 otherwise
  final int unlockAtSeconds; // Unix timestamp; valid for time-based; 0 otherwise

  SpendPathAbsLocked({
    this.remainingBlocks,
    this.remainingSeconds,
    required this.unlockAtBlock,
    required this.unlockAtSeconds,
  });
}

/// Locked by a relative timelock; [remainingBlocks] or [remainingSeconds]
/// indicates how much longer to wait.
class SpendPathRelLocked extends SpendPathStatus {
  final int? remainingBlocks; // null for time-based
  final int? remainingSeconds; // null for block-based

  SpendPathRelLocked({this.remainingBlocks, this.remainingSeconds});
}

/// Evaluates whether [path] is spendable for [utxo] at [tipHeight].
///
/// [tipHeight] == 0 means the wallet has not been synced yet.
SpendPathStatus spendPathStatus({
  required APISpendPath path,
  required APIUtxo utxo,
  required int tipHeight,
}) {
  final hasAbs = path.absTimelock.value > 0;
  final hasRel = path.relTimelock.value > 0;

  // No timelocks → always unlocked
  if (!hasAbs && !hasRel) return SpendPathUnlocked();

  // If wallet has never synced we cannot evaluate timelocks
  if (tipHeight == 0) {
    return hasRel
        ? SpendPathNeedsSync()
        : SpendPathAbsLocked(
            remainingBlocks: null,
            remainingSeconds: null,
            unlockAtBlock: 0,
            unlockAtSeconds: 0,
          );
  }

  // ── Absolute timelock ──────────────────────────────────────────────────────
  if (hasAbs) {
    if (path.absTimelock.timelockType == APIAbsoluteTimelockType.blocks) {
      final unlock = path.absTimelock.value;
      if (tipHeight < unlock) {
        return SpendPathAbsLocked(
          remainingBlocks: unlock - tipHeight,
          unlockAtBlock: unlock,
          unlockAtSeconds: 0,
        );
      }
    } else {
      // Timestamp-based
      final unlock = path.absTimelock.value; // Unix seconds
      final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
      if (now < unlock) {
        return SpendPathAbsLocked(
          remainingSeconds: unlock - now,
          unlockAtBlock: 0,
          unlockAtSeconds: unlock,
        );
      }
    }
  }

  // ── Relative timelock ──────────────────────────────────────────────────────
  if (hasRel) {
    if (!utxo.isConfirmed || utxo.confirmationHeight == null) {
      return SpendPathUnconfirmed();
    }

    final confirmedAt = utxo.confirmationHeight!.toInt();

    if (path.relTimelock.timelockType == APIRelativeTimelockType.blocks) {
      final required = path.relTimelock.value;
      final elapsed = tipHeight - confirmedAt;
      if (elapsed < required) {
        return SpendPathRelLocked(remainingBlocks: required - elapsed);
      }
    } else {
      // Time-based: value stored in seconds (units × 512)
      // Approximate remaining blocks: remainingSeconds / 600
      final requiredSeconds = path.relTimelock.value;
      // Approximate elapsed seconds via block count × 600s/block
      final elapsedSeconds = (tipHeight - confirmedAt) * 600;
      if (elapsedSeconds < requiredSeconds) {
        return SpendPathRelLocked(
          remainingSeconds: requiredSeconds - elapsedSeconds,
        );
      }
    }
  }

  return SpendPathUnlocked();
}

/// Returns the minimum remaining blocks across all locked paths, or null if none are locked.
int? nearestUnlockBlocks(List<(APISpendPath, SpendPathStatus)> statuses) {
  int? best;
  for (final (_, status) in statuses) {
    final blocks = switch (status) {
      SpendPathRelLocked(:final remainingBlocks) when remainingBlocks != null =>
        remainingBlocks,
      SpendPathAbsLocked(:final remainingBlocks) when remainingBlocks != null =>
        remainingBlocks,
      _ => null,
    };
    if (blocks != null && (best == null || blocks < best)) best = blocks;
  }
  return best;
}

/// Estimated unlock [DateTime] for [status], or null if already unlocked / no block info.
DateTime? estimatedUnlockDate(SpendPathStatus status) {
  return switch (status) {
    SpendPathRelLocked(:final remainingBlocks) when remainingBlocks != null =>
      DateTime.now().add(Duration(minutes: remainingBlocks * 10)),
    SpendPathAbsLocked(:final remainingBlocks) when remainingBlocks != null =>
      DateTime.now().add(Duration(minutes: remainingBlocks * 10)),
    SpendPathAbsLocked(:final unlockAtSeconds) when unlockAtSeconds > 0 =>
      DateTime.fromMillisecondsSinceEpoch(unlockAtSeconds * 1000),
    _ => null,
  };
}

/// Approximate age label for [ageBlocks]: "~3d", "~2mo", "~1y".
String formatCoinAge(int ageBlocks) {
  final days = (ageBlocks * 10 / 60 / 24).round();
  if (days < 1) return '<1d';
  if (days < 30) return '~${days}d';
  if (days < 365) return '~${days ~/ 30}mo';
  return '~${days ~/ 365}y';
}
