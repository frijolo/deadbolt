import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:deadbolt/cubit/project_detail_cubit.dart';
import 'package:deadbolt/data/database.dart';
import 'package:deadbolt/models/timelock_types.dart';

void main() {
  group('EditableKey', () {
    test('copyWith preserves original fields', () {
      final key = EditableKey(
        originalDbId: 1,
        mfp: 'abc12345',
        derivationPath: "m/84'/0'/0'",
        xpub: 'xpub123',
        customName: 'My Key',
      );

      final copied = key.copyWith(mfp: 'def67890');
      expect(copied.originalDbId, 1);
      expect(copied.mfp, 'def67890');
      expect(copied.derivationPath, "m/84'/0'/0'");
      expect(copied.xpub, 'xpub123');
      expect(copied.customName, 'My Key');
    });

    test('fromDb maps all fields', () {
      final dbKey = ProjectKey(
        id: 42,
        projectId: 1,
        mfp: 'abc12345',
        derivationPath: "m/84'/0'/0'",
        xpub: 'xpub123',
        customName: 'Hardware',
      );

      final editable = EditableKey.fromDb(dbKey);
      expect(editable.originalDbId, 42);
      expect(editable.mfp, 'abc12345');
      expect(editable.derivationPath, "m/84'/0'/0'");
      expect(editable.xpub, 'xpub123');
      expect(editable.customName, 'Hardware');
    });

    test('fromDb with null customName', () {
      final dbKey = ProjectKey(
        id: 1,
        projectId: 1,
        mfp: 'abc12345',
        derivationPath: "m/84'/0'/0'",
        xpub: 'xpub123',
        customName: null,
      );

      final editable = EditableKey.fromDb(dbKey);
      expect(editable.customName, isNull);
    });
  });

  group('EditableSpendPath', () {
    test('fromDb detects relative timelock mode', () {
      final sp = ProjectSpendPath(
        id: 1,
        projectId: 1,
        rustId: 100,
        threshold: 2,
        mfps: jsonEncode(['a', 'b']),
        relTimelockType: 'blocks',
        relTimelockValue: 144,
        absTimelockType: 'blocks',
        absTimelockValue: 0,
        wuBase: 100,
        wuIn: 50,
        wuOut: 30,
        trDepth: 0,
        vbSweep: 120.0,
        customName: 'Path 1',
        priority: 0,
      );

      final editable = EditableSpendPath.fromDb(sp);
      expect(editable.timelockMode, TimelockMode.relative);
      expect(editable.relTimelockValue, 144);
    });

    test('fromDb detects absolute timelock mode', () {
      final sp = ProjectSpendPath(
        id: 1,
        projectId: 1,
        rustId: 100,
        threshold: 1,
        mfps: jsonEncode(['a']),
        relTimelockType: 'blocks',
        relTimelockValue: 0,
        absTimelockType: 'timestamp',
        absTimelockValue: 1704067200,
        wuBase: 100,
        wuIn: 50,
        wuOut: 30,
        trDepth: 0,
        vbSweep: 120.0,
        customName: null,
        priority: 0,
      );

      final editable = EditableSpendPath.fromDb(sp);
      expect(editable.timelockMode, TimelockMode.absolute);
      expect(editable.absTimelockValue, 1704067200);
      expect(editable.absTimelockType, AbsoluteTimelockType.timestamp);
    });

    test('fromDb detects no timelock mode', () {
      final sp = ProjectSpendPath(
        id: 1,
        projectId: 1,
        rustId: 100,
        threshold: 1,
        mfps: jsonEncode(['a']),
        relTimelockType: 'blocks',
        relTimelockValue: 0,
        absTimelockType: 'blocks',
        absTimelockValue: 0,
        wuBase: 100,
        wuIn: 50,
        wuOut: 30,
        trDepth: 0,
        vbSweep: 120.0,
        customName: null,
        priority: 0,
      );

      final editable = EditableSpendPath.fromDb(sp);
      expect(editable.timelockMode, TimelockMode.none);
    });

    test('fromDb detects key-path from trDepth == -1', () {
      final sp = ProjectSpendPath(
        id: 1,
        projectId: 1,
        rustId: 100,
        threshold: 1,
        mfps: jsonEncode(['a']),
        relTimelockType: 'blocks',
        relTimelockValue: 0,
        absTimelockType: 'blocks',
        absTimelockValue: 0,
        wuBase: 100,
        wuIn: 50,
        wuOut: 30,
        trDepth: -1,
        vbSweep: 120.0,
        customName: null,
        priority: 0,
      );

      final editable = EditableSpendPath.fromDb(sp);
      expect(editable.isKeyPath, true);
    });

    test('fromDb detects script-path from trDepth >= 0', () {
      final sp = ProjectSpendPath(
        id: 1,
        projectId: 1,
        rustId: 100,
        threshold: 1,
        mfps: jsonEncode(['a']),
        relTimelockType: 'blocks',
        relTimelockValue: 0,
        absTimelockType: 'blocks',
        absTimelockValue: 0,
        wuBase: 100,
        wuIn: 50,
        wuOut: 30,
        trDepth: 2,
        vbSweep: 120.0,
        customName: null,
        priority: 0,
      );

      final editable = EditableSpendPath.fromDb(sp);
      expect(editable.isKeyPath, false);
    });

    test('canBeKeyPath is true for singlesig with no timelocks', () {
      final path = EditableSpendPath(
        threshold: 1,
        mfps: ['a'],
        timelockMode: TimelockMode.none,
      );
      expect(path.canBeKeyPath, true);
    });

    test('canBeKeyPath is false for multisig', () {
      final path = EditableSpendPath(
        threshold: 2,
        mfps: ['a', 'b'],
        timelockMode: TimelockMode.none,
      );
      expect(path.canBeKeyPath, false);
    });

    test('canBeKeyPath is false with timelocks', () {
      final path = EditableSpendPath(
        threshold: 1,
        mfps: ['a'],
        timelockMode: TimelockMode.relative,
        relTimelockValue: 10,
      );
      expect(path.canBeKeyPath, false);
    });

    test('canBeKeyPath is false when threshold=1 but multiple keys', () {
      final path = EditableSpendPath(
        threshold: 1,
        mfps: ['a', 'b'],
        timelockMode: TimelockMode.none,
      );
      expect(path.canBeKeyPath, false);
    });

    test('copyWith creates independent copy', () {
      final original = EditableSpendPath(
        threshold: 2,
        mfps: ['a', 'b'],
        timelockMode: TimelockMode.relative,
        relTimelockValue: 100,
      );

      final copied = original.copyWith(threshold: 3);
      expect(copied.threshold, 3);
      expect(copied.mfps, ['a', 'b']);
      expect(copied.timelockMode, TimelockMode.relative);
      expect(copied.relTimelockValue, 100);

      // Verify mfps list is a separate copy
      copied.mfps.add('c');
      expect(original.mfps, ['a', 'b']);
    });

    test('fromDb prefers relative when both timelocks are set', () {
      final sp = ProjectSpendPath(
        id: 1,
        projectId: 1,
        rustId: 100,
        threshold: 1,
        mfps: jsonEncode(['a']),
        relTimelockType: 'blocks',
        relTimelockValue: 10,
        absTimelockType: 'blocks',
        absTimelockValue: 500,
        wuBase: 100,
        wuIn: 50,
        wuOut: 30,
        trDepth: 0,
        vbSweep: 120.0,
        customName: null,
        priority: 3,
      );

      final editable = EditableSpendPath.fromDb(sp);
      expect(editable.timelockMode, TimelockMode.relative);
      expect(editable.priority, 3);
    });
  });
}
