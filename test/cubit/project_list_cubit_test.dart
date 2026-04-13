import 'package:flutter_test/flutter_test.dart';
import 'package:bloc_test/bloc_test.dart';
import 'package:mocktail/mocktail.dart';

import 'package:deadbolt/cubit/project_list_cubit.dart';
import 'package:deadbolt/data/database.dart';
import 'package:deadbolt/services/project_descriptor_service.dart';
import 'package:deadbolt/src/rust/api/analyzer.dart';
import 'package:deadbolt/src/rust/api/model.dart';

import '../fixtures/sqlite_setup.dart';

class MockProjectDescriptorService extends Mock
    implements ProjectDescriptorService {}

void main() {
  ensureSqlite3();

  late AppDatabase db;
  late MockProjectDescriptorService mockService;

  const fakeAnalysisResult = APIAnalysisResult(
    descriptor: 'wpkh([abc12345/84h/0h/0h]xpub123/*)',
    network: APINetwork.testnet,
    walletType: APIWalletType.p2Wpkh,
    keys: [
      APIPubKey(
        mfp: 'abc12345',
        derivationPath: "m/84'/0'/0'",
        xpub: 'xpub123',
      ),
    ],
    spendPaths: [
      APISpendPath(
        id: 1001,
        policyPath: [],
        threshold: 1,
        mfps: ['abc12345'],
        relTimelock: APIRelativeTimelock(
          timelockType: APIRelativeTimelockType.blocks,
          value: 0,
        ),
        absTimelock: APIAbsoluteTimelock(
          timelockType: APIAbsoluteTimelockType.blocks,
          value: 0,
        ),
        wuBase: 100,
        wuIn: 50,
        wuOut: 30,
        trDepth: 0,
        vbSweep: 120.0,
      ),
    ],
  );

  setUp(() {
    db = AppDatabase.inMemory();
    mockService = MockProjectDescriptorService();

    when(() => mockService.analyzeDescriptor(any()))
        .thenAnswer((_) async => fakeAnalysisResult);
  });

  tearDown(() async {
    await db.close();
  });

  group('ProjectListCubit', () {
    blocTest<ProjectListCubit, ProjectListState>(
      'emits loaded with empty list initially',
      build: () => ProjectListCubit(db, service: mockService),
      expect: () => [isA<ProjectListLoaded>()],
    );

    blocTest<ProjectListCubit, ProjectListState>(
      'createProject analyzes descriptor and inserts project',
      build: () => ProjectListCubit(db, service: mockService),
      act: (cubit) async {
        // Wait for initial load
        await Future<void>.delayed(Duration.zero);
        await cubit.createProject(
          descriptor: 'wpkh([abc12345/84h/0h/0h]xpub123/*)',
          name: 'Test Wallet',
        );
      },
      verify: (cubit) {
        verify(() => mockService.analyzeDescriptor(any())).called(1);
        final state = cubit.state;
        expect(state, isA<ProjectListLoaded>());
        final loaded = state as ProjectListLoaded;
        expect(loaded.projects, hasLength(1));
        expect(loaded.projects.first.name, 'Test Wallet');
      },
    );

    blocTest<ProjectListCubit, ProjectListState>(
      'createEmptyProject inserts project without analysis',
      build: () => ProjectListCubit(db, service: mockService),
      act: (cubit) async {
        await Future<void>.delayed(Duration.zero);
        await cubit.createEmptyProject(
          name: 'Empty Wallet',
          network: APINetwork.testnet,
          walletType: APIWalletType.p2Tr,
        );
      },
      verify: (cubit) {
        verifyNever(() => mockService.analyzeDescriptor(any()));
        final loaded = cubit.state as ProjectListLoaded;
        expect(loaded.projects, hasLength(1));
        expect(loaded.projects.first.name, 'Empty Wallet');
        expect(loaded.projects.first.descriptor, '');
      },
    );

    blocTest<ProjectListCubit, ProjectListState>(
      'deleteProject removes project from list',
      build: () => ProjectListCubit(db, service: mockService),
      act: (cubit) async {
        await Future<void>.delayed(Duration.zero);
        final id = await cubit.createProject(
          descriptor: 'wpkh([abc12345/84h/0h/0h]xpub123/*)',
          name: 'To Delete',
        );
        await cubit.deleteProject(id);
      },
      verify: (cubit) {
        final loaded = cubit.state as ProjectListLoaded;
        expect(loaded.projects, isEmpty);
      },
    );

    blocTest<ProjectListCubit, ProjectListState>(
      'importProject parses JSON and creates project',
      build: () => ProjectListCubit(db, service: mockService),
      act: (cubit) async {
        await Future<void>.delayed(Duration.zero);
        const json = '{"version":1,"exportedAt":"2024-06-15T12:00:00.000",'
            '"project":{"name":"Imported","descriptor":"wpkh(...)"},'
            '"keyLabels":{},"pathLabels":{}}';
        await cubit.importProject(json);
      },
      verify: (cubit) {
        final loaded = cubit.state as ProjectListLoaded;
        expect(loaded.projects, hasLength(1));
        expect(loaded.projects.first.name, 'Imported');
      },
    );

    test('buildProjectExportData returns valid export', () async {
      final cubit = ProjectListCubit(db, service: mockService);
      addTearDown(cubit.close);

      await Future<void>.delayed(Duration.zero);
      final id = await cubit.createProject(
        descriptor: 'wpkh([abc12345/84h/0h/0h]xpub123/*)',
        name: 'Export Me',
      );

      final exportData = await cubit.buildProjectExportData(id);
      expect(exportData.jsonString, contains('"Export Me"'));
      expect(exportData.fileName, contains('Export Me'));
      expect(exportData.fileName, endsWith('.deadbolt.json'));
    });

    test('createProject with empty name defaults to Unnamed project', () async {
      final cubit = ProjectListCubit(db, service: mockService);
      addTearDown(cubit.close);

      await Future<void>.delayed(Duration.zero);
      await cubit.createProject(
        descriptor: 'wpkh([abc12345/84h/0h/0h]xpub123/*)',
        name: '',
      );

      final loaded = cubit.state as ProjectListLoaded;
      expect(loaded.projects.first.name, 'Unnamed project');
    });
  });
}
