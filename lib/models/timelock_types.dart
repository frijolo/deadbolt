import 'package:deadbolt/src/rust/api/model.dart';

enum RelativeTimelockType {
  blocks,
  time;

  String get displayName => this == blocks ? 'Blocks' : 'Time';

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

  String get displayName => this == blocks ? 'Blocks' : 'Timestamp';

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

  String get displayName {
    switch (this) {
      case TimelockMode.none:
        return 'No timelock';
      case TimelockMode.relative:
        return 'Relative';
      case TimelockMode.absolute:
        return 'Absolute';
    }
  }
}
