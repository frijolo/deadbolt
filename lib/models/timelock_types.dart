import 'package:deadbolt/src/rust/api/model.dart';

enum RelativeTimelockType {
  blocks,
  time;

  static RelativeTimelockType fromString(String s) {
    return values.firstWhere((e) => e.name == s.toLowerCase());
  }

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
