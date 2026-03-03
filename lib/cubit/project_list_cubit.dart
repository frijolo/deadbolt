import 'dart:async';
import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import 'package:deadbolt/data/database.dart';
import 'package:deadbolt/models/project_export.dart';
import 'package:deadbolt/services/project_descriptor_service.dart';
import 'package:deadbolt/src/rust/api/analyzer.dart' as rust_api;
import 'package:deadbolt/src/rust/api/model.dart';

typedef ProjectExportData = ({String jsonString, String fileName});

/// Characters not allowed in export file names.
final _invalidFileNameCharsRegex = RegExp(r'[^\w\s-]');

// --- States ---

sealed class ProjectListState {}

class ProjectListLoading extends ProjectListState {
  final String? message;
  ProjectListLoading({this.message});
}

class ProjectListLoaded extends ProjectListState {
  final List<Project> projects;
  ProjectListLoaded(this.projects);
}

class ProjectListError extends ProjectListState {
  final String message;
  ProjectListError(this.message);
}

// --- Cubit ---

class ProjectListCubit extends Cubit<ProjectListState> {
  final AppDatabase _db;
  final ProjectDescriptorService _service;
  StreamSubscription<List<Project>>? _subscription;

  ProjectListCubit(this._db, {ProjectDescriptorService? service})
      : _service = service ?? const ProjectDescriptorService(),
        super(ProjectListLoading()) {
    _watch();
  }

  void _logError(String context, Object error, StackTrace stackTrace) {
    debugPrint('════════════════════════════════════════════════════════════');
    debugPrint('ERROR in $context:');
    debugPrint('$error');
    debugPrint('Stack trace:');
    debugPrint('$stackTrace');
    debugPrint('════════════════════════════════════════════════════════════');
  }

  void _watch() {
    _subscription = _db.watchAllProjects().listen(
      (projects) => emit(ProjectListLoaded(projects)),
      onError: (e, stackTrace) {
        _logError('ProjectListCubit stream', e, stackTrace);
        emit(ProjectListError(e.toString()));
      },
    );
  }

  Future<int> createProject({
    required String descriptor,
    required String name,
  }) async {
    try {
      final result = await _service.analyzeDescriptor(descriptor);

      final projectId = await _db.insertProject(ProjectsCompanion.insert(
        name: name.isEmpty ? 'Unnamed project' : name,
        descriptor: result.descriptor,
        network: result.network.name,
        walletType: result.walletType.name,
      ));

      await _persistAnalysisResults(projectId, result);
      return projectId;
    } catch (e, stackTrace) {
      _logError('ProjectListCubit.createProject()', e, stackTrace);
      rethrow;
    }
  }

  /// Create an empty project to build from scratch
  Future<int> createEmptyProject({
    required String name,
    required APINetwork network,
    required APIWalletType walletType,
  }) async {
    try {
      final projectId = await _db.insertProject(ProjectsCompanion.insert(
        name: name,
        descriptor: '', // Empty descriptor - will be generated on first regenerate
        network: network.name,
        walletType: walletType.name,
      ));

      return projectId;
    } catch (e, stackTrace) {
      _logError('ProjectListCubit.createEmptyProject()', e, stackTrace);
      rethrow;
    }
  }

  Future<ProjectExportData> buildProjectExportData(int id) async {
    try {
      final project = await _db.getProject(id);
      final keys = await _db.getKeysForProject(id);
      final paths = await _db.getSpendPathsForProject(id);

      final keyLabels = <String, String>{};
      for (final key in keys) {
        if (key.customName != null) keyLabels[key.mfp] = key.customName!;
      }

      final pathLabels = <String, String>{};
      for (final path in paths) {
        if (path.customName != null) {
          pathLabels[path.rustId.toString()] = path.customName!;
        }
      }

      final exportData = ProjectExport(
        version: 1,
        exportedAt: DateTime.now(),
        name: project.name,
        descriptor: project.descriptor,
        keyLabels: keyLabels,
        pathLabels: pathLabels,
      );

      final fileName =
          '${project.name.replaceAll(_invalidFileNameCharsRegex, '_')}.deadbolt.json';
      return (jsonString: exportData.toJsonString(), fileName: fileName);
    } catch (e, stackTrace) {
      _logError('ProjectListCubit.buildProjectExportData()', e, stackTrace);
      rethrow;
    }
  }

  Future<void> deleteProject(int id) async {
    try {
      await _db.deleteProject(id);
    } catch (e, stackTrace) {
      _logError('ProjectListCubit.deleteProject()', e, stackTrace);
      rethrow;
    }
  }

  /// Import project from JSON string
  Future<int> importProject(String jsonString) async {
    try {
      final exportData = ProjectExport.fromJsonString(jsonString);
      final result = await _service.analyzeDescriptor(exportData.descriptor);

      final projectId = await _db.insertProject(ProjectsCompanion.insert(
        name: exportData.name,
        descriptor: result.descriptor,
        network: result.network.name,
        walletType: result.walletType.name,
      ));

      await _persistAnalysisResults(
        projectId,
        result,
        keyLabels: exportData.keyLabels,
        pathLabels: exportData.pathLabels,
      );
      return projectId;
    } catch (e, stackTrace) {
      _logError('ProjectListCubit.importProject()', e, stackTrace);
      rethrow;
    }
  }

  /// Inserts keys and spend paths for [projectId] from [result].
  ///
  /// Optional [keyLabels] (MFP → name) and [pathLabels] (rustId.toString() → name)
  /// are applied when importing existing label data (e.g. from a project export).
  Future<void> _persistAnalysisResults(
    int projectId,
    rust_api.APIAnalysisResult result, {
    Map<String, String?> keyLabels = const {},
    Map<String, String?> pathLabels = const {},
  }) async {
    final keyEntries = result.keys
        .map((k) => ProjectKeysCompanion.insert(
              projectId: projectId,
              mfp: k.mfp,
              derivationPath: k.derivationPath,
              xpub: k.xpub,
              customName: Value(keyLabels[k.mfp]),
            ))
        .toList();

    final pathEntries = result.spendPaths
        .map((sp) => ProjectSpendPathsCompanion.insert(
              projectId: projectId,
              rustId: sp.id,
              threshold: sp.threshold,
              mfps: jsonEncode(sp.mfps),
              relTimelockType: Value(sp.relTimelock.timelockType.name),
              relTimelockValue: Value(sp.relTimelock.value),
              absTimelockType: Value(sp.absTimelock.timelockType.name),
              absTimelockValue: Value(sp.absTimelock.value),
              wuBase: sp.wuBase,
              wuIn: sp.wuIn,
              wuOut: sp.wuOut,
              trDepth: sp.trDepth,
              vbSweep: sp.vbSweep,
              customName: Value(pathLabels[sp.id.toString()]),
            ))
        .toList();

    await _db.batch((batch) {
      batch.insertAll(_db.projectKeys, keyEntries);
      batch.insertAll(_db.projectSpendPaths, pathEntries);
    });
  }

  @override
  Future<void> close() {
    _subscription?.cancel();
    return super.close();
  }
}
