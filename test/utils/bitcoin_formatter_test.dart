import 'package:flutter_test/flutter_test.dart';
import 'package:deadbolt/models/timelock_types.dart';
import 'package:deadbolt/utils/bitcoin_formatter.dart';

void main() {
  group('formatRelativeTimelock', () {
    test('returns "0" when value is zero', () {
      expect(
        BitcoinFormatter.formatRelativeTimelock(
            RelativeTimelockType.blocks, 0),
        '0',
      );
      expect(
        BitcoinFormatter.formatRelativeTimelock(RelativeTimelockType.time, 0),
        '0',
      );
    });

    test('formats blocks with approximate duration', () {
      // 6 blocks × 10 min = 60 min = 1h
      expect(
        BitcoinFormatter.formatRelativeTimelock(
            RelativeTimelockType.blocks, 6),
        contains('+6 blocks'),
      );
      // 144 blocks × 10 min = 1440 min = 1d
      expect(
        BitcoinFormatter.formatRelativeTimelock(
            RelativeTimelockType.blocks, 144),
        contains('1d'),
      );
    });

    test('formats time type with 512-second units', () {
      // 512 seconds value => 1 unit, ~8 min
      final result = BitcoinFormatter.formatRelativeTimelock(
          RelativeTimelockType.time, 512);
      expect(result, contains('× 512s'));
    });
  });

  group('formatAbsoluteTimelock', () {
    test('returns "0" when value is zero', () {
      expect(
        BitcoinFormatter.formatAbsoluteTimelock(
            AbsoluteTimelockType.blocks, 0),
        '0',
      );
      expect(
        BitcoinFormatter.formatAbsoluteTimelock(
            AbsoluteTimelockType.timestamp, 0),
        '0',
      );
    });

    test('formats block height with approximate date', () {
      final result = BitcoinFormatter.formatAbsoluteTimelock(
          AbsoluteTimelockType.blocks, 840000);
      expect(result, startsWith('Block #840000'));
      expect(result, contains('~'));
    });

    test('formats timestamp as date string', () {
      // 2024-01-01 00:00 UTC
      final result = BitcoinFormatter.formatAbsoluteTimelock(
          AbsoluteTimelockType.timestamp, 1704067200);
      expect(result, contains('2024'));
    });
  });

  group('_formatDuration (via formatRelativeTimelock)', () {
    test('formats minutes', () {
      // 3 blocks × 10 min = 30 min
      expect(
        BitcoinFormatter.formatRelativeTimelock(
            RelativeTimelockType.blocks, 3),
        contains('30min'),
      );
    });

    test('formats hours and minutes', () {
      // 7 blocks × 10 min = 70 min = 1h 10min
      expect(
        BitcoinFormatter.formatRelativeTimelock(
            RelativeTimelockType.blocks, 7),
        contains('1h 10min'),
      );
    });

    test('formats days', () {
      // 144 blocks × 10 = 1440 min = 1d
      final result = BitcoinFormatter.formatRelativeTimelock(
          RelativeTimelockType.blocks, 144);
      expect(result, contains('1d'));
    });

    test('formats weeks', () {
      // 1008 blocks × 10 = 10080 min = 1w
      final result = BitcoinFormatter.formatRelativeTimelock(
          RelativeTimelockType.blocks, 1008);
      expect(result, contains('1w'));
    });

    test('formats months', () {
      // 4320 blocks × 10 = 43200 min = 1mo
      final result = BitcoinFormatter.formatRelativeTimelock(
          RelativeTimelockType.blocks, 4320);
      expect(result, contains('1mo'));
    });

    test('formats years', () {
      // 52560 blocks × 10 = 525600 min = 1y
      final result = BitcoinFormatter.formatRelativeTimelock(
          RelativeTimelockType.blocks, 52560);
      expect(result, contains('1y'));
    });
  });
}
