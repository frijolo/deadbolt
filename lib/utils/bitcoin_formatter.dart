import 'package:deadbolt/models/timelock_types.dart';

class BitcoinFormatter {
  static String formatRelativeTimelock(
      RelativeTimelockType type, int value) {
    if (value == 0) return '0';

    switch (type) {
      case RelativeTimelockType.blocks:
        final totalMins = value * 10;
        return '+$value blocks (~${_formatDuration(totalMins)})';
      case RelativeTimelockType.time:
        final units = value ~/ 512;
        final totalMins = value ~/ 60;
        return '+$units × 512s (~${_formatDuration(totalMins)})';
    }
  }

  static String formatAbsoluteTimelock(
      AbsoluteTimelockType type, int value) {
    if (value == 0) return '0';

    switch (type) {
      case AbsoluteTimelockType.blocks:
        // Approximate date: Genesis block (0) = 2009-01-03, ~144 blocks/day
        final genesisDate = DateTime(2009, 1, 3);
        final daysFromGenesis = value / 144;
        final approxDate = genesisDate.add(Duration(days: daysFromGenesis.round()));
        return 'Block #$value (~${approxDate.year}-${approxDate.month.toString().padLeft(2, '0')}-${approxDate.day.toString().padLeft(2, '0')})';
      case AbsoluteTimelockType.timestamp:
        final date = DateTime.fromMillisecondsSinceEpoch(value * 1000);
        return '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')} ${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}';
    }
  }

  static String _formatDuration(int totalMins) {
    if (totalMins <= 0) return "0min";

    const int minInHour = 60;
    const int minInDay = 1440;
    const int minInWeek = 10080;
    const int minInMonth = 43200;
    const int minInYear = 525600;

    if (totalMins >= minInYear) {
      int y = totalMins ~/ minInYear;
      int mo = (totalMins % minInYear) ~/ minInMonth;
      return (y < 2 && mo > 0) ? "${y}y ${mo}mo" : "${y}y";
    }

    if (totalMins >= minInMonth) {
      int mo = totalMins ~/ minInMonth;
      int w = (totalMins % minInMonth) ~/ minInWeek;
      return (mo < 6 && w > 0) ? "${mo}mo ${w}w" : "${mo}mo";
    }

    if (totalMins >= minInWeek) {
      int w = totalMins ~/ minInWeek;
      int d = (totalMins % minInWeek) ~/ minInDay;
      return (w < 4 && d > 0) ? "${w}w ${d}d" : "${w}w";
    }

    if (totalMins >= minInDay) {
      int d = totalMins ~/ minInDay;
      int h = (totalMins % minInDay) ~/ minInHour;
      return (d < 3 && h > 0) ? "${d}d ${h}h" : "${d}d";
    }

    if (totalMins >= minInHour) {
      int h = totalMins ~/ minInHour;
      int m = totalMins % minInHour;
      return (h < 12 && m > 0) ? "${h}h ${m}min" : "${h}h";
    }

    return "${totalMins}min";
  }
}
