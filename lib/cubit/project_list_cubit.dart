import 'dart:async';
import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import 'package:deadbolt/data/database.dart';
import 'package:deadbolt/models/project_export.dart';
import 'package:deadbolt/src/rust/api/analyzer.dart';
import 'package:deadbolt/src/rust/api/model.dart';

// --- States ---

sealed class ProjectListState {}

class ProjectListLoading extends ProjectListState {}

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
  StreamSubscription<List<Project>>? _subscription;

  ProjectListCubit(this._db) : super(ProjectListLoading()) {
    _watch();
  }

  void _watch() {
    _subscription = _db.watchAllProjects().listen(
      (projects) => emit(ProjectListLoaded(projects)),
      onError: (e, stackTrace) {
        debugPrint('════════════════════════════════════════════════════════════');
        debugPrint('ERROR in ProjectListCubit stream:');
        debugPrint('$e');
        debugPrint('Stack trace:');
        debugPrint('$stackTrace');
        debugPrint('════════════════════════════════════════════════════════════');
        emit(ProjectListError(e.toString()));
      },
    );
  }

  Future<int> createProject({
    required String descriptor,
    required String name,
  }) async {
    try {
      final result = await analyzeDescriptor(descriptor: descriptor.trim());

      final projectId = await _db.insertProject(ProjectsCompanion.insert(
        name: name.isEmpty ? 'Unnamed project' : name,
        descriptor: result.descriptor,
        network: result.network.name,
        walletType: result.walletType.name,
      ));

      final keyEntries = result.keys
          .map((k) => ProjectKeysCompanion.insert(
                projectId: projectId,
                mfp: k.mfp,
                derivationPath: k.derivationPath,
                xpub: k.xpub,
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
              ))
          .toList();

      await _db.batch((batch) {
        batch.insertAll(_db.projectKeys, keyEntries);
        batch.insertAll(_db.projectSpendPaths, pathEntries);
      });

      return projectId;
    } catch (e, stackTrace) {
      debugPrint('════════════════════════════════════════════════════════════');
      debugPrint('ERROR in ProjectListCubit.createProject():');
      debugPrint('$e');
      debugPrint('Stack trace:');
      debugPrint('$stackTrace');
      debugPrint('════════════════════════════════════════════════════════════');
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
      debugPrint('════════════════════════════════════════════════════════════');
      debugPrint('ERROR in ProjectListCubit.createEmptyProject():');
      debugPrint('$e');
      debugPrint('Stack trace:');
      debugPrint('$stackTrace');
      debugPrint('════════════════════════════════════════════════════════════');
      rethrow;
    }
  }

  Future<void> deleteProject(int id) async {
    try {
      await _db.deleteProject(id);
    } catch (e, stackTrace) {
      debugPrint('════════════════════════════════════════════════════════════');
      debugPrint('ERROR in ProjectListCubit.deleteProject():');
      debugPrint('$e');
      debugPrint('Stack trace:');
      debugPrint('$stackTrace');
      debugPrint('════════════════════════════════════════════════════════════');
      rethrow;
    }
  }

  /// Import project from JSON string
  Future<int> importProject(String jsonString) async {
    try {
      // Parse export data
      final exportData = ProjectExport.fromJsonString(jsonString);

      // Analyze the descriptor
      final result = await analyzeDescriptor(descriptor: exportData.descriptor.trim());

      // Create project
      final projectId = await _db.insertProject(ProjectsCompanion.insert(
        name: exportData.name,
        descriptor: result.descriptor,
        network: result.network.name,
        walletType: result.walletType.name,
      ));

      // Create key entries with labels mapped by MFP
      final keyEntries = result.keys
          .map((k) => ProjectKeysCompanion.insert(
                projectId: projectId,
                mfp: k.mfp,
                derivationPath: k.derivationPath,
                xpub: k.xpub,
                customName: Value(exportData.keyLabels[k.mfp]),
              ))
          .toList();

      // Create path entries with labels mapped by rustId
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
                customName: Value(exportData.pathLabels[sp.id.toString()]),
              ))
          .toList();

      await _db.batch((batch) {
        batch.insertAll(_db.projectKeys, keyEntries);
        batch.insertAll(_db.projectSpendPaths, pathEntries);
      });

      return projectId;
    } catch (e, stackTrace) {
      debugPrint('════════════════════════════════════════════════════════════');
      debugPrint('ERROR in ProjectListCubit.importProject():');
      debugPrint('$e');
      debugPrint('Stack trace:');
      debugPrint('$stackTrace');
      debugPrint('════════════════════════════════════════════════════════════');
      rethrow;
    }
  }

  @override
  Future<void> close() {
    _subscription?.cancel();
    return super.close();
  }
}
