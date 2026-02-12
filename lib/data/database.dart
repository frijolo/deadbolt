import 'dart:io';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'tables.dart';

part 'database.g.dart';

@DriftDatabase(tables: [Projects, ProjectKeys, ProjectSpendPaths])
class AppDatabase extends _$AppDatabase {
  AppDatabase._internal(super.e);

  static AppDatabase? _instance;

  factory AppDatabase() {
    _instance ??= AppDatabase._internal(_openConnection());
    return _instance!;
  }

  @override
  int get schemaVersion => 1;

  // --- Projects ---

  Stream<List<Project>> watchAllProjects() {
    return (select(projects)..orderBy([(t) => OrderingTerm.desc(t.updatedAt)]))
        .watch();
  }

  Future<List<Project>> getAllProjects() => select(projects).get();

  Future<Project> getProject(int id) {
    return (select(projects)..where((t) => t.id.equals(id))).getSingle();
  }

  Future<int> insertProject(ProjectsCompanion entry) {
    return into(projects).insert(entry);
  }

  Future<bool> updateProject(ProjectsCompanion entry) {
    return update(projects).replace(entry);
  }

  Future<int> deleteProject(int id) {
    return transaction(() async {
      await (delete(projectKeys)..where((t) => t.projectId.equals(id))).go();
      await (delete(projectSpendPaths)..where((t) => t.projectId.equals(id)))
          .go();
      return (delete(projects)..where((t) => t.id.equals(id))).go();
    });
  }

  // --- Keys ---

  Future<List<ProjectKey>> getKeysForProject(int projectId) {
    return (select(projectKeys)
          ..where((t) => t.projectId.equals(projectId)))
        .get();
  }

  Future<void> updateKeyName(int keyId, String? name) {
    return (update(projectKeys)..where((t) => t.id.equals(keyId)))
        .write(ProjectKeysCompanion(customName: Value(name)));
  }

  // --- Spend Paths ---

  Future<List<ProjectSpendPath>> getSpendPathsForProject(int projectId) {
    return (select(projectSpendPaths)
          ..where((t) => t.projectId.equals(projectId)))
        .get();
  }

  Future<void> updateSpendPathName(int pathId, String? name) {
    return (update(projectSpendPaths)..where((t) => t.id.equals(pathId)))
        .write(ProjectSpendPathsCompanion(customName: Value(name)));
  }

  // --- Re-analysis ---

  Future<void> replaceAnalysisData({
    required int projectId,
    required ProjectsCompanion projectUpdate,
    required List<ProjectKeysCompanion> newKeys,
    required List<ProjectSpendPathsCompanion> newPaths,
  }) {
    return transaction(() async {
      // Delete old keys and spend paths
      await (delete(projectKeys)..where((t) => t.projectId.equals(projectId)))
          .go();
      await (delete(projectSpendPaths)
            ..where((t) => t.projectId.equals(projectId)))
          .go();

      // Update project row
      await (update(projects)..where((t) => t.id.equals(projectId)))
          .write(projectUpdate);

      // Insert new keys and spend paths
      await batch((batch) {
        batch.insertAll(projectKeys, newKeys);
        batch.insertAll(projectSpendPaths, newPaths);
      });
    });
  }
}

LazyDatabase _openConnection() {
  return LazyDatabase(() async {
    final dbFolder = await getApplicationDocumentsDirectory();
    final file = File(p.join(dbFolder.path, 'deadbolt.sqlite'));
    return NativeDatabase.createInBackground(file);
  });
}
