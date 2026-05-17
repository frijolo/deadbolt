import 'package:deadbolt/src/rust/api/model.dart';
import 'package:deadbolt/utils/date_format.dart';

extension APIPsbtInfoTimelock on APIPsbtInfo {
  /// True when [lockTime] is set and the chain tip has not yet reached it.
  /// Requires a known [tipHeight] (`0` means tip is unknown — never locked).
  bool isLockedByTimelock(int tipHeight) =>
      lockTime > 0 && tipHeight > 0 && tipHeight < lockTime;

  /// Projected unlock time assuming nominal 10-min blocks. Returns `null`
  /// when not locked at [tipHeight].
  DateTime? unlockEta(int tipHeight) =>
      isLockedByTimelock(tipHeight) ? etaFromBlocks(lockTime - tipHeight) : null;

  /// True when the signer threshold is met (or the PSBT is already fully
  /// finalized). Returns `false` when [analysis] is unavailable.
  bool isReadyToBroadcast(APIPsbtAnalysis? analysis) {
    if (analysis == null) return false;
    if (analysis.isFinalized) return true;
    final signed = analysis.signers.where((s) => s.hasSigned).length;
    return signed >= threshold.toInt();
  }
}
