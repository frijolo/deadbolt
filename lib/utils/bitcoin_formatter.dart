class BitcoinFormatter {
  static String formatBitcoinTime(int blocks) {
    if (blocks <= 0) return "0min";

    int totalMins = blocks * 10;
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
