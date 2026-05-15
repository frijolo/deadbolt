import 'package:intl/intl.dart';

import 'package:deadbolt/models/timelock_types.dart';
import 'package:deadbolt/utils/date_format.dart';

class BitcoinFormatter {
  /// Format an integer with locale-aware thousands separators (e.g. 1,234,567).
  static String formatNum(int n) => NumberFormat.decimalPattern().format(n);

  /// Auto-generate a spend path display label from its participants.
  /// Returns "Name" for single-key paths, "M/N · Key1, Key2" for multisig.
  static String pathLabel(
    int threshold,
    List<String> mfps,
    String Function(String mfp) keyLabel,
  ) {
    if (mfps.isEmpty) return '';
    final names = mfps.map(keyLabel).toList();
    if (mfps.length == 1) return names.first;
    return '$threshold/${mfps.length} · ${names.join(', ')}';
  }

  /// Format a double with locale-aware thousands separators and fixed decimal places.
  static String formatDouble(double n, int decimalDigits) =>
      NumberFormat.decimalPatternDigits(decimalDigits: decimalDigits).format(n);

  /// Format a fee rate (sat/vB) with precision that scales with magnitude:
  /// < 10 → 2 decimals, 10–99 → 1 decimal, ≥ 100 → 0 decimals.
  static String formatFeeRate(double fee) {
    if (fee >= 100) return fee.toStringAsFixed(0);
    if (fee >= 10) return fee.toStringAsFixed(1);
    return fee.toStringAsFixed(2);
  }

  /// Convert satoshis to a BTC string with 8 decimal places (e.g. "0.00100000").
  static String satsToBtcString(int sats) => (sats / 1e8).toStringAsFixed(8);

  /// Convert [sats] to BTC value and format with [fiatPrice] and [currency].
  static String formatSatsFiat(int sats, double fiatPrice, String currency) =>
      formatFiat(sats / 1e8 * fiatPrice, currency);

  /// Format a fiat value with the currency code (e.g. "USD 1,234.56").
  /// Currencies with no decimals (JPY, KRW, etc.) are shown as integers.
  static String formatFiat(double value, String currency) {
    const noDecimals = {'jpy', 'krw', 'clp', 'vnd', 'idr', 'mmk', 'ngn'};
    final decimals = noDecimals.contains(currency.toLowerCase()) ? 0 : 2;
    return NumberFormat.currency(
      symbol: '${currency.toUpperCase()} ',
      decimalDigits: decimals,
    ).format(value);
  }


  static String formatRelativeTimelock(
      RelativeTimelockType type, int value) {
    if (value == 0) return '0';

    switch (type) {
      case RelativeTimelockType.blocks:
        final totalMins = value * 10;
        return '+$value blocks (~${formatDuration(totalMins)})';
      case RelativeTimelockType.time:
        final units = value ~/ 512;
        final totalMins = value ~/ 60;
        return '+$units × 512s (~${formatDuration(totalMins)})';
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
        return 'Block #$value (~${formatDate(approxDate)})';
      case AbsoluteTimelockType.timestamp:
        return formatTimestamp(value);
    }
  }

  static String formatDuration(int totalMins) {
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

  /// Format sats with thousands separator and optional sign prefix.
  ///
  /// Replaces the repeated pattern `'${BitcoinFormatter.formatNum(x)} sats'`
  /// and `'${isReceived ? '+' : '-'}${BitcoinFormatter.formatNum(x)} sats'`.
  static String satsLabel(int sats, {bool showSign = false}) {
    final formatted = formatNum(sats);
    if (showSign) {
      return sats >= 0 ? '+$formatted sats' : '-$formatted sats';
    }
    return '$formatted sats';
  }
}
