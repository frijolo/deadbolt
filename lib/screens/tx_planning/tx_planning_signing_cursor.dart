import 'package:deadbolt/cubit/tx_planning_cubit.dart'
    show APISpacedPlanSigningBundle;

/// Shared cursor + counting helpers for the spaced-plan batch signing
/// views (HW and QR). Both flows iterate the bundle's children; in
/// multisig the per-MFP variants are what keep the cursor honest
/// (skipping txs the active key has already signed even when the tx
/// isn't finalized because the threshold isn't met yet).
extension SpacedPlanSigningCursor on APISpacedPlanSigningBundle {
  /// Returns the first index `>= from` whose child is not yet
  /// finalized, or `children.length` if every remaining child is
  /// finalized.
  int firstUnfinalizedFrom(int from) {
    for (var i = from; i < children.length; i++) {
      if (!children[i].isFinalized) return i;
    }
    return children.length;
  }

  /// Returns the first index `>= from` whose child still needs a
  /// signature from [mfp]: skips finalized children AND children
  /// where [mfp] has already signed (`hasSigned == true`). Returns
  /// `children.length` when this key has nothing left to do.
  int firstPendingForMfp(int from, String mfp) {
    for (var i = from; i < children.length; i++) {
      final child = children[i];
      if (child.isFinalized) continue;
      var hasSigned = false;
      var inThreshold = false;
      for (final s in child.signers) {
        if (s.mfp != mfp) continue;
        inThreshold = true;
        hasSigned = s.hasSigned;
        break;
      }
      if (!inThreshold) continue;
      if (!hasSigned) return i;
    }
    return children.length;
  }

  /// Number of children where [mfp] has already signed.
  int signedCountForMfp(String mfp) {
    var n = 0;
    for (final child in children) {
      for (final s in child.signers) {
        if (s.mfp == mfp && s.hasSigned) {
          n++;
          break;
        }
      }
    }
    return n;
  }

  /// True when at least one child lists [mfp] in its signer set —
  /// i.e. this fingerprint belongs to the plan's threshold and not
  /// some foreign device the user accidentally plugged in.
  bool isKnownMfp(String mfp) {
    for (final child in children) {
      for (final s in child.signers) {
        if (s.mfp == mfp) return true;
      }
    }
    return false;
  }
}
