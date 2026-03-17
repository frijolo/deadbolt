import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:bloc_test/bloc_test.dart';
import 'package:mocktail/mocktail.dart';

import 'package:deadbolt/cubit/project_detail_cubit.dart';
import 'package:deadbolt/data/database.dart';
import 'package:deadbolt/models/timelock_types.dart';
import 'package:deadbolt/services/project_descriptor_service.dart';
import 'package:deadbolt/src/rust/api/model.dart';

import '../test_utils.dart';

class MockProjectDescriptorService extends Mock
    implements ProjectDescriptorService {}

void main() {
  ensureSqlite3();

  late AppDatabase db;
  late MockProjectDescriptorService mockService;
  late int projectId;

  /// Insert a test project with one key and one spend path.
  Future<int> seedProject(AppDatabase db) async {
    final id = await db.insertProject(ProjectsCompanion.insert(
      name: 'Test Project',
      descriptor: 'wpkh([abc12345/84h/0h/0h]xpub123/*)',
      network: 'testnet',
      walletType: 'p2Wpkh',
    ));

    await db.batch((batch) {
      batch.insertAll(db.projectKeys, [
        ProjectKeysCompanion.insert(
          projectId: id,
          mfp: 'abc12345',
          derivationPath: "m/84'/0'/0'",
          xpub: 'xpub123',
        ),
      ]);
      batch.insertAll(db.projectSpendPaths, [
        ProjectSpendPathsCompanion.insert(
          projectId: id,
          rustId: 1001,
          threshold: 1,
          mfps: jsonEncode(['abc12345']),
          wuBase: 100,
          wuIn: 50,
          wuOut: 30,
          trDepth: 0,
          vbSweep: 120.0,
        ),
      ]);
    });
    return id;
  }

  setUp(() async {
    db = AppDatabase.inMemory();
    mockService = MockProjectDescriptorService();
    projectId = await seedProject(db);
  });

  tearDown(() async {
    await db.close();
  });

  group('ProjectDetailCubit — loading', () {
    blocTest<ProjectDetailCubit, ProjectDetailState>(
      'loads project data on construction and auto-enters edit mode',
      build: () => ProjectDetailCubit(db, projectId, service: mockService),
      expect: () => [
        // First emit: loaded from DB (not yet editing)
        isA<ProjectDetailLoaded>()
            .having((s) => s.project.name, 'name', 'Test Project')
            .having((s) => s.keys, 'keys', hasLength(1))
            .having((s) => s.spendPaths, 'spendPaths', hasLength(1))
            .having((s) => s.isEditing, 'isEditing', false),
        // Second emit: edit mode auto-entered
        isA<ProjectDetailLoaded>()
            .having((s) => s.isEditing, 'isEditing', true)
            .having((s) => s.editedKeys, 'editedKeys', hasLength(1))
            .having((s) => s.editedPaths, 'editedPaths', hasLength(1)),
      ],
    );

    blocTest<ProjectDetailCubit, ProjectDetailState>(
      'emits error for non-existent project',
      build: () => ProjectDetailCubit(db, 99999, service: mockService),
      expect: () => [
        isA<ProjectDetailError>(),
      ],
    );
  });

  group('ProjectDetailCubit — edit mode', () {
    blocTest<ProjectDetailCubit, ProjectDetailState>(
      'enterEditMode populates editable lists',
      build: () => ProjectDetailCubit(db, projectId, service: mockService),
      act: (cubit) async {
        await Future<void>.delayed(Duration.zero);
        cubit.enterEditMode();
      },
      verify: (cubit) {
        final s = cubit.state as ProjectDetailLoaded;
        expect(s.isEditing, true);
        expect(s.editedKeys, hasLength(1));
        expect(s.editedPaths, hasLength(1));
        expect(s.isDirty, false);
      },
    );

    blocTest<ProjectDetailCubit, ProjectDetailState>(
      'discardEdits resets editable state and stays in edit mode',
      build: () => ProjectDetailCubit(db, projectId, service: mockService),
      act: (cubit) async {
        await Future<void>.delayed(Duration.zero);
        cubit.discardEdits();
      },
      verify: (cubit) {
        final s = cubit.state as ProjectDetailLoaded;
        expect(s.isEditing, true);
        expect(s.isDirty, false);
        expect(s.editedPaths, isNotNull);
        expect(s.editedKeys, isNotNull);
      },
    );

    blocTest<ProjectDetailCubit, ProjectDetailState>(
      'enterEditMode is idempotent when already editing',
      build: () => ProjectDetailCubit(db, projectId, service: mockService),
      act: (cubit) async {
        await Future<void>.delayed(Duration.zero);
        cubit.enterEditMode();
        cubit.enterEditMode(); // should be no-op
      },
      verify: (cubit) {
        final s = cubit.state as ProjectDetailLoaded;
        expect(s.isEditing, true);
      },
    );
  });

  group('ProjectDetailCubit — spend path editing', () {
    blocTest<ProjectDetailCubit, ProjectDetailState>(
      'updatePathThreshold changes threshold and marks dirty',
      build: () => ProjectDetailCubit(db, projectId, service: mockService),
      act: (cubit) async {
        await Future<void>.delayed(Duration.zero);
        cubit.enterEditMode();
        cubit.updatePathThreshold(0, 2);
      },
      verify: (cubit) {
        final s = cubit.state as ProjectDetailLoaded;
        expect(s.editedPaths![0].threshold, 2);
        expect(s.isDirty, true);
      },
    );

    blocTest<ProjectDetailCubit, ProjectDetailState>(
      'addMfpToPath adds key to path',
      build: () => ProjectDetailCubit(db, projectId, service: mockService),
      act: (cubit) async {
        await Future<void>.delayed(Duration.zero);
        cubit.enterEditMode();
        cubit.addMfpToPath(0, 'def67890');
      },
      verify: (cubit) {
        final s = cubit.state as ProjectDetailLoaded;
        expect(s.editedPaths![0].mfps, contains('def67890'));
        expect(s.isDirty, true);
      },
    );

    blocTest<ProjectDetailCubit, ProjectDetailState>(
      'removeMfpFromPath removes key from path',
      build: () => ProjectDetailCubit(db, projectId, service: mockService),
      act: (cubit) async {
        await Future<void>.delayed(Duration.zero);
        cubit.enterEditMode();
        cubit.removeMfpFromPath(0, 'abc12345');
      },
      verify: (cubit) {
        final s = cubit.state as ProjectDetailLoaded;
        expect(s.editedPaths![0].mfps, isEmpty);
      },
    );

    blocTest<ProjectDetailCubit, ProjectDetailState>(
      'addSpendPath adds new empty path',
      build: () => ProjectDetailCubit(db, projectId, service: mockService),
      act: (cubit) async {
        await Future<void>.delayed(Duration.zero);
        cubit.enterEditMode();
        cubit.addSpendPath();
      },
      verify: (cubit) {
        final s = cubit.state as ProjectDetailLoaded;
        expect(s.editedPaths, hasLength(2));
        expect(s.editedPaths![1].mfps, isEmpty);
        expect(s.editedPaths![1].threshold, 1);
      },
    );

    blocTest<ProjectDetailCubit, ProjectDetailState>(
      'removeSpendPath removes path at index',
      build: () => ProjectDetailCubit(db, projectId, service: mockService),
      act: (cubit) async {
        await Future<void>.delayed(Duration.zero);
        cubit.enterEditMode();
        cubit.removeSpendPath(0);
      },
      verify: (cubit) {
        final s = cubit.state as ProjectDetailLoaded;
        expect(s.editedPaths, isEmpty);
      },
    );

    blocTest<ProjectDetailCubit, ProjectDetailState>(
      'updatePathTimelockMode changes mode',
      build: () => ProjectDetailCubit(db, projectId, service: mockService),
      act: (cubit) async {
        await Future<void>.delayed(Duration.zero);
        cubit.enterEditMode();
        cubit.updatePathTimelockMode(0, TimelockMode.relative);
      },
      verify: (cubit) {
        final s = cubit.state as ProjectDetailLoaded;
        expect(s.editedPaths![0].timelockMode, TimelockMode.relative);
      },
    );

    blocTest<ProjectDetailCubit, ProjectDetailState>(
      'updatePathRelTimelockValue changes value',
      build: () => ProjectDetailCubit(db, projectId, service: mockService),
      act: (cubit) async {
        await Future<void>.delayed(Duration.zero);
        cubit.enterEditMode();
        cubit.updatePathRelTimelockValue(0, 144);
      },
      verify: (cubit) {
        final s = cubit.state as ProjectDetailLoaded;
        expect(s.editedPaths![0].relTimelockValue, 144);
      },
    );

    blocTest<ProjectDetailCubit, ProjectDetailState>(
      'updatePathPriority clamps between 0 and 9',
      build: () => ProjectDetailCubit(db, projectId, service: mockService),
      act: (cubit) async {
        await Future<void>.delayed(Duration.zero);
        cubit.enterEditMode();
        cubit.updatePathPriority(0, 15);
      },
      verify: (cubit) {
        final s = cubit.state as ProjectDetailLoaded;
        expect(s.editedPaths![0].priority, 9);
      },
    );
  });

  group('ProjectDetailCubit — key-path handling', () {
    blocTest<ProjectDetailCubit, ProjectDetailState>(
      'updatePathIsKeyPath marks one path and unmarks others',
      build: () => ProjectDetailCubit(db, projectId, service: mockService),
      act: (cubit) async {
        await Future<void>.delayed(Duration.zero);
        cubit.enterEditMode();
        cubit.addSpendPath();
        // Add a key to the second path so canBeKeyPath works
        cubit.addMfpToPath(1, 'abc12345');
        cubit.updatePathIsKeyPath(0, true);
        cubit.updatePathIsKeyPath(1, true);
      },
      verify: (cubit) {
        final s = cubit.state as ProjectDetailLoaded;
        expect(s.editedPaths![0].isKeyPath, false);
        expect(s.editedPaths![1].isKeyPath, true);
      },
    );

    blocTest<ProjectDetailCubit, ProjectDetailState>(
      'adding timelock clears isKeyPath automatically',
      build: () => ProjectDetailCubit(db, projectId, service: mockService),
      act: (cubit) async {
        await Future<void>.delayed(Duration.zero);
        cubit.enterEditMode();
        cubit.updatePathIsKeyPath(0, true);
        // Adding timelock should clear isKeyPath since canBeKeyPath becomes false
        cubit.updatePathTimelockMode(0, TimelockMode.relative);
      },
      verify: (cubit) {
        final s = cubit.state as ProjectDetailLoaded;
        expect(s.editedPaths![0].isKeyPath, false);
      },
    );
  });

  group('ProjectDetailCubit — wallet type', () {
    blocTest<ProjectDetailCubit, ProjectDetailState>(
      'updateWalletType changes type and marks dirty',
      build: () => ProjectDetailCubit(db, projectId, service: mockService),
      act: (cubit) async {
        await Future<void>.delayed(Duration.zero);
        cubit.enterEditMode();
        cubit.updateWalletType(APIWalletType.p2Tr);
      },
      verify: (cubit) {
        final s = cubit.state as ProjectDetailLoaded;
        expect(s.editedWalletType, APIWalletType.p2Tr);
        expect(s.isDirty, true);
      },
    );

    blocTest<ProjectDetailCubit, ProjectDetailState>(
      'switching from taproot clears keypath flags',
      build: () => ProjectDetailCubit(db, projectId, service: mockService),
      act: (cubit) async {
        await Future<void>.delayed(Duration.zero);
        cubit.enterEditMode();
        cubit.updateWalletType(APIWalletType.p2Tr);
        cubit.updatePathIsKeyPath(0, true);
        cubit.updateWalletType(APIWalletType.p2Wsh);
      },
      verify: (cubit) {
        final s = cubit.state as ProjectDetailLoaded;
        expect(s.editedPaths![0].isKeyPath, false);
      },
    );

    test('getCompatibleWalletTypes returns all types for singlesig', () async {
      final cubit =
          ProjectDetailCubit(db, projectId, service: mockService);
      addTearDown(cubit.close);
      await Future<void>.delayed(Duration.zero);
      cubit.enterEditMode();

      final types = cubit.getCompatibleWalletTypes();
      expect(types, contains(APIWalletType.p2Wpkh));
      expect(types, contains(APIWalletType.p2Tr));
    });

    test('getCompatibleWalletTypes excludes wpkh for multisig', () async {
      final cubit =
          ProjectDetailCubit(db, projectId, service: mockService);
      addTearDown(cubit.close);
      await Future<void>.delayed(Duration.zero);
      cubit.enterEditMode();
      cubit.addMfpToPath(0, 'def67890');
      cubit.updatePathThreshold(0, 2);

      final types = cubit.getCompatibleWalletTypes();
      expect(types, isNot(contains(APIWalletType.p2Wpkh)));
      expect(types, contains(APIWalletType.p2Wsh));
    });
  });

  group('ProjectDetailCubit — naming', () {
    test('updateProjectName persists to database', () async {
      final cubit =
          ProjectDetailCubit(db, projectId, service: mockService);
      addTearDown(cubit.close);
      await Future<void>.delayed(Duration.zero);

      await cubit.updateProjectName('Renamed');

      // Allow reload to complete
      await Future<void>.delayed(Duration.zero);

      final s = cubit.state as ProjectDetailLoaded;
      expect(s.project.name, 'Renamed');
    });

    test('updateKeyName persists to database', () async {
      final cubit =
          ProjectDetailCubit(db, projectId, service: mockService);
      addTearDown(cubit.close);
      await Future<void>.delayed(Duration.zero);

      final s = cubit.state as ProjectDetailLoaded;
      await cubit.updateKeyName(s.keys.first.id, 'My HW Key');

      await Future<void>.delayed(Duration.zero);

      final updated = cubit.state as ProjectDetailLoaded;
      expect(updated.keys.first.customName, 'My HW Key');
    });

    test('updateSpendPathName persists to database', () async {
      final cubit =
          ProjectDetailCubit(db, projectId, service: mockService);
      addTearDown(cubit.close);
      await Future<void>.delayed(Duration.zero);

      final s = cubit.state as ProjectDetailLoaded;
      await cubit.updateSpendPathName(s.spendPaths.first.id, 'Main Path');

      await Future<void>.delayed(Duration.zero);

      final updated = cubit.state as ProjectDetailLoaded;
      expect(updated.spendPaths.first.customName, 'Main Path');
    });
  });

  group('ProjectDetailCubit — expand/collapse', () {
    blocTest<ProjectDetailCubit, ProjectDetailState>(
      'toggleKeysExpanded changes expansion state',
      build: () => ProjectDetailCubit(db, projectId, service: mockService),
      act: (cubit) async {
        await Future<void>.delayed(Duration.zero);
        cubit.toggleKeysExpanded(true);
      },
      verify: (cubit) {
        final s = cubit.state as ProjectDetailLoaded;
        expect(s.keysExpanded, true);
      },
    );

    blocTest<ProjectDetailCubit, ProjectDetailState>(
      'toggleSpendPathsExpanded changes expansion state',
      build: () => ProjectDetailCubit(db, projectId, service: mockService),
      act: (cubit) async {
        await Future<void>.delayed(Duration.zero);
        cubit.toggleSpendPathsExpanded(false);
      },
      verify: (cubit) {
        final s = cubit.state as ProjectDetailLoaded;
        expect(s.spendPathsExpanded, false);
      },
    );
  });

  group('ProjectDetailCubit — error/success clearing', () {
    blocTest<ProjectDetailCubit, ProjectDetailState>(
      'clearError removes error message',
      build: () => ProjectDetailCubit(db, projectId, service: mockService),
      act: (cubit) async {
        await Future<void>.delayed(Duration.zero);
        final s = cubit.state as ProjectDetailLoaded;
        // Manually inject an error message
        cubit.emit(s.copyWith(errorMessage: 'Test error'));
        cubit.clearError();
      },
      verify: (cubit) {
        final s = cubit.state as ProjectDetailLoaded;
        expect(s.errorMessage, isNull);
      },
    );

    blocTest<ProjectDetailCubit, ProjectDetailState>(
      'clearSuccess removes success message',
      build: () => ProjectDetailCubit(db, projectId, service: mockService),
      act: (cubit) async {
        await Future<void>.delayed(Duration.zero);
        final s = cubit.state as ProjectDetailLoaded;
        cubit.emit(s.copyWith(successMessage: 'Saved!'));
        cubit.clearSuccess();
      },
      verify: (cubit) {
        final s = cubit.state as ProjectDetailLoaded;
        expect(s.successMessage, isNull);
      },
    );
  });

  group('ProjectDetailCubit — export', () {
    test('buildExportPayload returns valid JSON', () async {
      final cubit =
          ProjectDetailCubit(db, projectId, service: mockService);
      addTearDown(cubit.close);
      await Future<void>.delayed(Duration.zero);

      final payload = cubit.buildExportPayload();
      expect(payload, isNotNull);
      expect(payload!.fileName, contains('Test Project'));
      expect(payload.fileName, endsWith('.deadbolt.json'));

      final decoded = jsonDecode(payload.jsonString) as Map<String, dynamic>;
      expect(decoded['version'], 1);
      expect(decoded['project']['name'], 'Test Project');
    });

    test('buildExportPayload returns null when not loaded', () async {
      final cubit =
          ProjectDetailCubit(db, projectId, service: mockService);
      // State is Loading at this point
      expect(cubit.buildExportPayload(), isNull);
      // Let load() complete before closing to avoid emit-after-close
      await Future<void>.delayed(Duration.zero);
      await cubit.close();
    });
  });

  group('ProjectDetailCubit — empty project auto-edit', () {
    test('auto-enters edit mode for empty descriptor', () async {
      final emptyId = await db.insertProject(ProjectsCompanion.insert(
        name: 'Empty',
        descriptor: '',
        network: 'testnet',
        walletType: 'p2Tr',
      ));

      final cubit =
          ProjectDetailCubit(db, emptyId, service: mockService);
      addTearDown(cubit.close);
      await Future<void>.delayed(Duration.zero);

      final s = cubit.state as ProjectDetailLoaded;
      expect(s.isEditing, true);
    });
  });

  group('ProjectDetailCubit — key management in edit mode', () {
    test('addKey inserts key to DB and editable list', () async {
      final cubit =
          ProjectDetailCubit(db, projectId, service: mockService);
      addTearDown(cubit.close);
      await Future<void>.delayed(Duration.zero);
      cubit.enterEditMode();

      await cubit.addKey(EditableKey(
        mfp: 'def67890',
        derivationPath: "m/84'/0'/0'",
        xpub: 'xpub456',
      ));

      final s = cubit.state as ProjectDetailLoaded;
      expect(s.editedKeys, hasLength(2));
      expect(s.editedKeys!.last.mfp, 'def67890');
      expect(s.editedKeys!.last.originalDbId, isNotNull);
    });

    test('removeKey removes key from DB and editable list', () async {
      final cubit =
          ProjectDetailCubit(db, projectId, service: mockService);
      addTearDown(cubit.close);
      await Future<void>.delayed(Duration.zero);
      cubit.enterEditMode();

      // First remove the key from all paths so it can be deleted
      cubit.removeMfpFromPath(0, 'abc12345');

      await cubit.removeKey('abc12345');

      final s = cubit.state as ProjectDetailLoaded;
      expect(s.editedKeys, isEmpty);
    });

    test('removeKey is no-op when key is in use', () async {
      final cubit =
          ProjectDetailCubit(db, projectId, service: mockService);
      addTearDown(cubit.close);
      await Future<void>.delayed(Duration.zero);
      cubit.enterEditMode();

      // Key is used in path, should not be removed
      await cubit.removeKey('abc12345');

      final s = cubit.state as ProjectDetailLoaded;
      expect(s.editedKeys, hasLength(1));
    });

    test('updateKeyCustomName persists name', () async {
      final cubit =
          ProjectDetailCubit(db, projectId, service: mockService);
      addTearDown(cubit.close);
      await Future<void>.delayed(Duration.zero);
      cubit.enterEditMode();

      await cubit.updateKeyCustomName('abc12345', 'Coldcard');

      final s = cubit.state as ProjectDetailLoaded;
      expect(s.editedKeys!.first.customName, 'Coldcard');
    });
  });

  group('ProjectDetailCubit — mfp color mapping', () {
    test('getMfpColorIndex returns consistent indices', () async {
      final cubit =
          ProjectDetailCubit(db, projectId, service: mockService);
      addTearDown(cubit.close);
      await Future<void>.delayed(Duration.zero);

      final idx1 = cubit.getMfpColorIndex('abc12345');
      final idx2 = cubit.getMfpColorIndex('def67890');
      final idx1Again = cubit.getMfpColorIndex('abc12345');

      expect(idx1, idx1Again);
      expect(idx1, isNot(idx2));
    });
  });

  group('ProjectDetailCubit — updatePathCustomName', () {
    test('sets custom name on path', () async {
      final cubit =
          ProjectDetailCubit(db, projectId, service: mockService);
      addTearDown(cubit.close);
      await Future<void>.delayed(Duration.zero);
      cubit.enterEditMode();

      cubit.updatePathCustomName(0, 'Recovery');

      final s = cubit.state as ProjectDetailLoaded;
      expect(s.editedPaths![0].customName, 'Recovery');
    });

    test('clears custom name with null', () async {
      final cubit =
          ProjectDetailCubit(db, projectId, service: mockService);
      addTearDown(cubit.close);
      await Future<void>.delayed(Duration.zero);
      cubit.enterEditMode();
      cubit.updatePathCustomName(0, 'Recovery');
      cubit.updatePathCustomName(0, null);

      final s = cubit.state as ProjectDetailLoaded;
      expect(s.editedPaths![0].customName, isNull);
    });
  });
}
