import 'package:deadbolt/src/rust/api/model.dart';

enum RelativeTimelockType {
  blocks,
  time;

  static RelativeTimelockType fromString(String s) {
    return values.firstWhere((e) => e.name == s.toLowerCase());
  }

  static RelativeTimelockType fromApi(APIRelativeTimelockType t) =>
      t == APIRelativeTimelockType.blocks
          ? RelativeTimelockType.blocks
          : RelativeTimelockType.time;

  APIRelativeTimelockType toRust() {
    return this == blocks
        ? APIRelativeTimelockType.blocks
        : APIRelativeTimelockType.time;
  }
}

enum AbsoluteTimelockType {
  blocks,
  timestamp;

  static AbsoluteTimelockType fromString(String s) {
    return values.firstWhere((e) => e.name == s.toLowerCase());
  }

  APIAbsoluteTimelockType toRust() {
    return this == blocks
        ? APIAbsoluteTimelockType.blocks
        : APIAbsoluteTimelockType.timestamp;
  }
}

enum TimelockMode {
  none,
  relative,
  absolute;
}

const kNoRelativeTimelock = APIRelativeTimelock(
  timelockType: APIRelativeTimelockType.blocks,
  value: 0,
);

const kNoAbsoluteTimelock = APIAbsoluteTimelock(
  timelockType: APIAbsoluteTimelockType.blocks,
  value: 0,
);

// ---------------------------------------------------------------------------
// Bitcoin consensus boundaries — must stay in sync with Rust
// (`rust/src/api/model.rs`, `APIAbsoluteTimelock` / `APIRelativeTimelock`).
// ---------------------------------------------------------------------------

/// nLockTime threshold from BIP-65: values below it are interpreted as block
/// heights, values >= it as Unix timestamps.
const int kAbsoluteLockTimeThreshold = 500000000;

/// Maximum block height for an absolute (height-based) timelock.
const int kAbsoluteMaxBlockHeight = kAbsoluteLockTimeThreshold - 1;

/// Maximum value (BIP-68 SEQUENCE_LOCKTIME_MASK) for a relative timelock,
/// applies to both block and time encodings before scaling.
const int kRelativeTimelockMax = 0xFFFF; // 65535
