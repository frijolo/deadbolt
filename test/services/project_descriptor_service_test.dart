import 'package:flutter_test/flutter_test.dart';
import 'package:deadbolt/models/timelock_types.dart';
import 'package:deadbolt/services/project_descriptor_service.dart';
import 'package:deadbolt/src/rust/api/model.dart';

void main() {
  const service = ProjectDescriptorService();

  group('buildRelativeTimelock', () {
    test('returns active timelock when mode is relative', () {
      final result = service.buildRelativeTimelock(
        timelockMode: TimelockMode.relative,
        relTimelockType: RelativeTimelockType.blocks,
        relTimelockValue: 144,
      );
      expect(result.timelockType, APIRelativeTimelockType.blocks);
      expect(result.value, 144);
    });

    test('returns active timelock for time type', () {
      final result = service.buildRelativeTimelock(
        timelockMode: TimelockMode.relative,
        relTimelockType: RelativeTimelockType.time,
        relTimelockValue: 512,
      );
      expect(result.timelockType, APIRelativeTimelockType.time);
      expect(result.value, 512);
    });

    test('returns zero when mode is not relative', () {
      final result = service.buildRelativeTimelock(
        timelockMode: TimelockMode.absolute,
        relTimelockType: RelativeTimelockType.blocks,
        relTimelockValue: 144,
      );
      expect(result.timelockType, APIRelativeTimelockType.blocks);
      expect(result.value, 0);
    });

    test('returns zero when mode is none', () {
      final result = service.buildRelativeTimelock(
        timelockMode: TimelockMode.none,
        relTimelockType: RelativeTimelockType.blocks,
        relTimelockValue: 0,
      );
      expect(result.value, 0);
    });
  });

  group('buildAbsoluteTimelock', () {
    test('returns active timelock when mode is absolute', () {
      final result = service.buildAbsoluteTimelock(
        timelockMode: TimelockMode.absolute,
        absTimelockType: AbsoluteTimelockType.blocks,
        absTimelockValue: 840000,
      );
      expect(result.timelockType, APIAbsoluteTimelockType.blocks);
      expect(result.value, 840000);
    });

    test('returns active timelock for timestamp type', () {
      final result = service.buildAbsoluteTimelock(
        timelockMode: TimelockMode.absolute,
        absTimelockType: AbsoluteTimelockType.timestamp,
        absTimelockValue: 1704067200,
      );
      expect(result.timelockType, APIAbsoluteTimelockType.timestamp);
      expect(result.value, 1704067200);
    });

    test('returns zero when mode is not absolute', () {
      final result = service.buildAbsoluteTimelock(
        timelockMode: TimelockMode.relative,
        absTimelockType: AbsoluteTimelockType.blocks,
        absTimelockValue: 840000,
      );
      expect(result.timelockType, APIAbsoluteTimelockType.blocks);
      expect(result.value, 0);
    });

    test('returns zero when mode is none', () {
      final result = service.buildAbsoluteTimelock(
        timelockMode: TimelockMode.none,
        absTimelockType: AbsoluteTimelockType.blocks,
        absTimelockValue: 0,
      );
      expect(result.value, 0);
    });
  });
}
