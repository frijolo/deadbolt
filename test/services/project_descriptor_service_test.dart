import 'package:flutter_test/flutter_test.dart';
import 'package:deadbolt/models/editable_models.dart';
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

  group('validatePaths', () {
    EditableSpendPath path({
      int threshold = 1,
      List<String>? mfps,
      bool isKeyPath = false,
    }) => EditableSpendPath(threshold: threshold, mfps: mfps ?? ['aabbccdd'], isKeyPath: isKeyPath);

    test('returns no errors for a valid path', () {
      final errors = service.validatePaths(
        [path(threshold: 1, mfps: ['aabbccdd'])],
        {'aabbccdd'},
        false,
      );
      expect(errors, isEmpty);
    });

    test('flags empty mfps list', () {
      final errors = service.validatePaths(
        [path(mfps: [])],
        {'aabbccdd'},
        false,
      );
      expect(errors, contains('Spend path 1: Must have at least one key'));
    });

    test('flags unknown mfp', () {
      final errors = service.validatePaths(
        [path(mfps: ['ffffffff'])],
        {'aabbccdd'},
        false,
      );
      expect(errors.any((e) => e.contains('Key ffffffff not found')), isTrue);
    });

    test('flags threshold below 1', () {
      final errors = service.validatePaths(
        [path(threshold: 0, mfps: ['aabbccdd'])],
        {'aabbccdd'},
        false,
      );
      expect(errors.any((e) => e.contains('Threshold must be at least 1')), isTrue);
    });

    test('flags threshold above mfps count', () {
      final errors = service.validatePaths(
        [path(threshold: 3, mfps: ['aabbccdd'])],
        {'aabbccdd'},
        false,
      );
      expect(
        errors.any((e) => e.contains('Threshold cannot exceed number of keys')),
        isTrue,
      );
    });

    test('flags multiple key-paths in taproot', () {
      final errors = service.validatePaths(
        [
          path(isKeyPath: true),
          path(isKeyPath: true),
        ],
        {'aabbccdd'},
        true,
      );
      expect(
        errors.any((e) => e.contains('Only one spend path can be marked as key-path')),
        isTrue,
      );
    });

    test('allows multiple key-paths when not taproot', () {
      final errors = service.validatePaths(
        [
          path(isKeyPath: true),
          path(isKeyPath: true),
        ],
        {'aabbccdd'},
        false,
      );
      expect(errors, isEmpty);
    });

    test('reports multiple errors with 1-based path index', () {
      final errors = service.validatePaths(
        [
          path(threshold: 0, mfps: ['aabbccdd']),
          path(mfps: []),
        ],
        {'aabbccdd'},
        false,
      );
      expect(errors.any((e) => e.startsWith('Spend path 1:')), isTrue);
      expect(errors.any((e) => e.startsWith('Spend path 2:')), isTrue);
    });
  });

  group('buildApiKeys', () {
    EditableKey key(String mfp) => EditableKey(
          mfp: mfp,
          derivationPath: "m/86'/0'/0'",
          xpub: 'xpub-$mfp',
        );

    test('filters keys not referenced by any spend path', () {
      final keys = service.buildApiKeys(
        [key('aaaaaaaa'), key('bbbbbbbb'), key('cccccccc')],
        {'aaaaaaaa', 'cccccccc'},
      );
      expect(keys.map((k) => k.mfp).toList(), ['aaaaaaaa', 'cccccccc']);
    });

    test('preserves derivation path and xpub', () {
      final keys = service.buildApiKeys([key('aaaaaaaa')], {'aaaaaaaa'});
      expect(keys.single.derivationPath, "m/86'/0'/0'");
      expect(keys.single.xpub, 'xpub-aaaaaaaa');
    });

    test('returns empty when no mfps are used', () {
      final keys = service.buildApiKeys([key('aaaaaaaa')], <String>{});
      expect(keys, isEmpty);
    });
  });

  group('buildApiPaths', () {
    test('maps fields and resolves timelocks per mode', () {
      final paths = service.buildApiPaths([
        EditableSpendPath(
          threshold: 2,
          mfps: ['aaaa', 'bbbb'],
          timelockMode: TimelockMode.relative,
          relTimelockType: RelativeTimelockType.blocks,
          relTimelockValue: 144,
          absTimelockType: AbsoluteTimelockType.blocks,
          absTimelockValue: 999,
          isKeyPath: true,
          priority: 5,
        ),
        EditableSpendPath(
          threshold: 1,
          mfps: ['cccc'],
          timelockMode: TimelockMode.absolute,
          absTimelockType: AbsoluteTimelockType.timestamp,
          absTimelockValue: 1704067200,
          relTimelockValue: 999,
        ),
        EditableSpendPath(threshold: 1, mfps: ['dddd']),
      ]);

      expect(paths[0].threshold, 2);
      expect(paths[0].mfps, ['aaaa', 'bbbb']);
      expect(paths[0].isKeyPath, isTrue);
      expect(paths[0].priority, 5);
      expect(paths[0].relTimelock.value, 144);
      // absolute timelock zeroed because mode is relative
      expect(paths[0].absTimelock.value, 0);

      // mode absolute zeroes the relative timelock
      expect(paths[1].relTimelock.value, 0);
      expect(paths[1].absTimelock.value, 1704067200);
      expect(paths[1].absTimelock.timelockType, APIAbsoluteTimelockType.timestamp);

      // mode none zeroes both
      expect(paths[2].relTimelock.value, 0);
      expect(paths[2].absTimelock.value, 0);
    });
  });
}
