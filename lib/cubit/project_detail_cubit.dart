import 'dart:convert';

import 'package:deadbolt/errors.dart';
import 'package:deadbolt/models/project_export.dart';
import 'package:deadbolt/models/timelock_types.dart';
import 'package:drift/drift.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import 'package:deadbolt/data/database.dart';
import 'package:deadbolt/src/rust/api/analyzer.dart';
import 'package:deadbolt/src/rust/api/model.dart';

// --- Editable models ---

class EditableKey {
  int? originalDbId;
  String mfp;
  String derivationPath;
  String xpub;
  String? customName;

  EditableKey({
    this.originalDbId,
    required this.mfp,
    required this.derivationPath,
    required this.xpub,
    this.customName,
  });

  EditableKey copyWith({
    String? mfp,
    String? derivationPath,
    String? xpub,
    String? customName,
  }) {
    return EditableKey(
      originalDbId: originalDbId,
      mfp: mfp ?? this.mfp,
      derivationPath: derivationPath ?? this.derivationPath,
      xpub: xpub ?? this.xpub,
      customName: customName ?? this.customName,
    );
  }

  static EditableKey fromDb(ProjectKey key) {
    return EditableKey(
      originalDbId: key.id,
      mfp: key.mfp,
      derivationPath: key.derivationPath,
      xpub: key.xpub,
      customName: key.customName,
    );
  }

  ProjectKey toProjectKey(int projectId) {
    return ProjectKey(
      id: originalDbId ?? 0,
      projectId: projectId,
      mfp: mfp,
      derivationPath: derivationPath,
      xpub: xpub,
      customName: customName,
    );
  }
}

class EditableSpendPath {
  int? originalDbId;
  int threshold;
  List<String> mfps;

  // Timelock configuration - only one can be active at a time
  TimelockMode timelockMode;

  // Relative timelock (used when timelockMode = relative)
  RelativeTimelockType relTimelockType;
  int relTimelockValue;

  // Absolute timelock (used when timelockMode = absolute)
  AbsoluteTimelockType absTimelockType;
  int absTimelockValue;

  String? customName;
  bool isKeyPath;
  int priority;

  EditableSpendPath({
    this.originalDbId,
    this.threshold = 1,
    List<String>? mfps,
    this.timelockMode = TimelockMode.none,
    this.relTimelockType = RelativeTimelockType.blocks,
    this.relTimelockValue = 0,
    this.absTimelockType = AbsoluteTimelockType.blocks,
    this.absTimelockValue = 0,
    this.customName,
    this.isKeyPath = false,
    this.priority = 0,
  }) : mfps = mfps ?? [];

  EditableSpendPath copyWith({
    int? threshold,
    List<String>? mfps,
    TimelockMode? timelockMode,
    RelativeTimelockType? relTimelockType,
    int? relTimelockValue,
    AbsoluteTimelockType? absTimelockType,
    int? absTimelockValue,
    String? customName,
    bool? isKeyPath,
    int? priority,
  }) {
    return EditableSpendPath(
      originalDbId: originalDbId,
      threshold: threshold ?? this.threshold,
      mfps: mfps ?? List.of(this.mfps),
      timelockMode: timelockMode ?? this.timelockMode,
      relTimelockType: relTimelockType ?? this.relTimelockType,
      relTimelockValue: relTimelockValue ?? this.relTimelockValue,
      absTimelockType: absTimelockType ?? this.absTimelockType,
      absTimelockValue: absTimelockValue ?? this.absTimelockValue,
      customName: customName ?? this.customName,
      isKeyPath: isKeyPath ?? this.isKeyPath,
      priority: priority ?? this.priority,
    );
  }

  static EditableSpendPath fromDb(ProjectSpendPath sp) {
    // Key-path is detected if trDepth == -1 (not a script path)
    final isKeyPath = sp.trDepth == -1;

    // Detect timelock mode based on values
    final TimelockMode mode;
    if (sp.relTimelockValue > 0 && sp.absTimelockValue > 0) {
      // Both set - prefer relative (shouldn't happen with new UI, but handle legacy data)
      mode = TimelockMode.relative;
    } else if (sp.relTimelockValue > 0) {
      mode = TimelockMode.relative;
    } else if (sp.absTimelockValue > 0) {
      mode = TimelockMode.absolute;
    } else {
      mode = TimelockMode.none;
    }

    return EditableSpendPath(
      originalDbId: sp.id,
      threshold: sp.threshold,
      mfps: (jsonDecode(sp.mfps) as List).cast<String>(),
      timelockMode: mode,
      relTimelockType: RelativeTimelockType.fromString(sp.relTimelockType),
      relTimelockValue: sp.relTimelockValue,
      absTimelockType: AbsoluteTimelockType.fromString(sp.absTimelockType),
      absTimelockValue: sp.absTimelockValue,
      customName: sp.customName,
      isKeyPath: isKeyPath,
      priority: sp.priority,
    );
  }

  /// Check if this path is eligible to be a key-path (singlesig, no timelocks)
  bool get canBeKeyPath =>
      threshold == 1 &&
      mfps.length == 1 &&
      timelockMode == TimelockMode.none;
}

// --- States ---

sealed class ProjectDetailState {}

class ProjectDetailLoading extends ProjectDetailState {
  final String? message;
  ProjectDetailLoading({this.message});
}

class ProjectDetailLoaded extends ProjectDetailState {
  final Project project;
  final List<ProjectKey> keys;
  final List<ProjectSpendPath> spendPaths;
  final List<EditableSpendPath>? editedPaths;
  final List<EditableKey>? editedKeys;
  final APIWalletType? editedWalletType;
  final bool isDirty;
  final bool keysExpanded;
  final bool spendPathsExpanded;
  final String? errorMessage;
  final String? successMessage;

  ProjectDetailLoaded({
    required this.project,
    required this.keys,
    required this.spendPaths,
    this.editedPaths,
    this.editedKeys,
    this.editedWalletType,
    this.isDirty = false,
    this.keysExpanded = false,
    this.spendPathsExpanded = true,
    this.errorMessage,
    this.successMessage,
  });

  bool get isEditing => editedPaths != null && editedKeys != null;

  ProjectDetailLoaded copyWith({
    List<EditableSpendPath>? editedPaths,
    List<EditableKey>? editedKeys,
    APIWalletType? editedWalletType,
    bool? isDirty,
    bool? keysExpanded,
    bool? spendPathsExpanded,
    String? errorMessage,
    String? successMessage,
    bool clearError = false,
    bool clearSuccess = false,
  }) {
    return ProjectDetailLoaded(
      project: project,
      keys: keys,
      spendPaths: spendPaths,
      editedPaths: editedPaths ?? this.editedPaths,
      editedKeys: editedKeys ?? this.editedKeys,
      editedWalletType: editedWalletType ?? this.editedWalletType,
      isDirty: isDirty ?? this.isDirty,
      keysExpanded: keysExpanded ?? this.keysExpanded,
      spendPathsExpanded: spendPathsExpanded ?? this.spendPathsExpanded,
      errorMessage: clearError ? null : (errorMessage ?? this.errorMessage),
      successMessage: clearSuccess ? null : (successMessage ?? this.successMessage),
    );
  }
}

class ProjectDetailError extends ProjectDetailState {
  final String message;
  ProjectDetailError(this.message);
}

// --- Cubit ---

class ProjectDetailCubit extends Cubit<ProjectDetailState> {
  final AppDatabase _db;
  final int projectId;

  final Map<String, Color> _mfpColorMap = {};

  static const List<Color> _palette = [
    Color(0xFFE53935), // red 600
    Color(0xFF43A047), // green 600
    Color(0xFF1E88E5), // blue 600
    Color(0xFFFFB300), // amber 600
    Color(0xFF00ACC1), // cyan 600
    Color(0xFF8E24AA), // purple 600
    Color(0xFFFB8C00), // orange 600
    Color(0xFF7CB342), // lightGreen 600
    Color(0xFF00897B), // teal 600
    Color(0xFF3949AB), // indigo 600
    Color(0xFF5E35B1), // deepPurple 600
    Color(0xFFD81B60), // pink 600
    Color(0xFFFF7043), // deepOrange 400
    Color(0xFFFDD835), // yellow 700
    Color(0xFFC0CA33), // lime 700
    Color(0xFF2E7D32), // green 800
    Color(0xFF26A69A), // teal 400
    Color(0xFF00838F), // cyan 800
    Color(0xFF1565C0), // blue 800
    Color(0xFF29B6F6), // lightBlue 400
    Color(0xFF9FA8DA), // indigo 300
    Color(0xFFCE93D8), // purple 300
    Color(0xFFF48FB1), // pink 300
    Color(0xFFE57373), // red 300
  ];

  ProjectDetailCubit(this._db, this.projectId)
      : super(ProjectDetailLoading()) {
    load();
  }

  Color getMfpColor(String mfp) {
    return _mfpColorMap.putIfAbsent(mfp, () {
      return _palette[_mfpColorMap.length % _palette.length];
    });
  }

  Future<void> load() async {
    try {
      // Preserve expansion states if reloading
      final currentState = state;
      final preserveKeysExpanded = currentState is ProjectDetailLoaded
          ? currentState.keysExpanded
          : false;
      final preserveSpendPathsExpanded = currentState is ProjectDetailLoaded
          ? currentState.spendPathsExpanded
          : true;

      emit(ProjectDetailLoading());
      final project = await _db.getProject(projectId);
      final keys = await _db.getKeysForProject(projectId);
      final spendPaths = await _db.getSpendPathsForProject(projectId);

      // Build color map from keys
      for (final key in keys) {
        getMfpColor(key.mfp);
      }

      emit(ProjectDetailLoaded(
        project: project,
        keys: keys,
        spendPaths: spendPaths,
        keysExpanded: preserveKeysExpanded,
        spendPathsExpanded: preserveSpendPathsExpanded,
      ));

      // Auto-enter edit mode for empty projects
      if (project.descriptor.isEmpty) {
        enterEditMode();
      }
    } catch (e) {
      emit(ProjectDetailError(formatRustError(e)));
    }
  }

  void toggleKeysExpanded(bool expanded) {
    final s = state;
    if (s is! ProjectDetailLoaded) return;
    emit(s.copyWith(keysExpanded: expanded));
  }

  void toggleSpendPathsExpanded(bool expanded) {
    final s = state;
    if (s is! ProjectDetailLoaded) return;
    emit(s.copyWith(spendPathsExpanded: expanded));
  }

  Future<void> updateProjectName(String name) async {
    await (_db.update(_db.projects)
          ..where((t) => t.id.equals(projectId)))
        .write(ProjectsCompanion(
      name: Value(name),
      updatedAt: Value(DateTime.now()),
    ));
    await load();
  }

  Future<void> updateKeyName(int keyId, String? name) async {
    await _db.updateKeyName(keyId, name);
    await load();
  }

  Future<void> updateSpendPathName(int pathId, String? name) async {
    await _db.updateSpendPathName(pathId, name);
    await load();
  }

  // --- Edit mode ---

  void enterEditMode() {
    final s = state;
    if (s is! ProjectDetailLoaded || s.isEditing) return;
    final editablePaths = s.spendPaths.map(EditableSpendPath.fromDb).toList();
    final editableKeys = s.keys.map(EditableKey.fromDb).toList();
    final currentWalletType = APIWalletType.values.byName(s.project.walletType);
    emit(s.copyWith(
      editedPaths: editablePaths,
      editedKeys: editableKeys,
      editedWalletType: currentWalletType,
      isDirty: false,
    ));
  }

  void discardEdits() {
    final s = state;
    if (s is! ProjectDetailLoaded) return;
    emit(ProjectDetailLoaded(
      project: s.project,
      keys: s.keys,
      spendPaths: s.spendPaths,
      keysExpanded: s.keysExpanded,
      spendPathsExpanded: s.spendPathsExpanded,
    ));
  }

  // Assigns [updated] to [paths[index]], clearing isKeyPath if the path is no
  // longer eligible (e.g. became multisig or gained a timelock).
  void _updatePathAndCheckKeyPath(
    List<EditableSpendPath> paths,
    int index,
    EditableSpendPath updated,
  ) {
    if (!updated.canBeKeyPath && updated.isKeyPath) {
      paths[index] = updated.copyWith(isKeyPath: false);
    } else {
      paths[index] = updated;
    }
  }

  void updatePathThreshold(int pathIndex, int value) {
    final s = state;
    if (s is! ProjectDetailLoaded || s.editedPaths == null) return;
    final paths = List.of(s.editedPaths!);
    _updatePathAndCheckKeyPath(paths, pathIndex, paths[pathIndex].copyWith(threshold: value));
    emit(s.copyWith(editedPaths: paths, isDirty: true));
  }

  void addMfpToPath(int pathIndex, String mfp) {
    final s = state;
    if (s is! ProjectDetailLoaded || s.editedPaths == null) return;
    final paths = List.of(s.editedPaths!);
    final newMfps = List.of(paths[pathIndex].mfps)..add(mfp);
    _updatePathAndCheckKeyPath(paths, pathIndex, paths[pathIndex].copyWith(mfps: newMfps));
    emit(s.copyWith(editedPaths: paths, isDirty: true));
  }

  void removeMfpFromPath(int pathIndex, String mfp) {
    final s = state;
    if (s is! ProjectDetailLoaded || s.editedPaths == null) return;
    final paths = List.of(s.editedPaths!);
    final newMfps = List.of(paths[pathIndex].mfps)..remove(mfp);
    paths[pathIndex] = paths[pathIndex].copyWith(mfps: newMfps);
    emit(s.copyWith(editedPaths: paths, isDirty: true));
  }

  void updatePathTimelockMode(int pathIndex, TimelockMode mode) {
    final s = state;
    if (s is! ProjectDetailLoaded || s.editedPaths == null) return;
    final paths = List.of(s.editedPaths!);
    _updatePathAndCheckKeyPath(paths, pathIndex, paths[pathIndex].copyWith(timelockMode: mode));
    emit(s.copyWith(editedPaths: paths, isDirty: true));
  }

  void updatePathRelTimelockType(int pathIndex, RelativeTimelockType type) {
    final s = state;
    if (s is! ProjectDetailLoaded || s.editedPaths == null) return;
    final paths = List.of(s.editedPaths!);
    paths[pathIndex] = paths[pathIndex].copyWith(relTimelockType: type);
    emit(s.copyWith(editedPaths: paths, isDirty: true));
  }

  void updatePathRelTimelockValue(int pathIndex, int value) {
    final s = state;
    if (s is! ProjectDetailLoaded || s.editedPaths == null) return;
    final paths = List.of(s.editedPaths!);
    _updatePathAndCheckKeyPath(paths, pathIndex, paths[pathIndex].copyWith(relTimelockValue: value));
    emit(s.copyWith(editedPaths: paths, isDirty: true));
  }

  void updatePathAbsTimelockType(int pathIndex, AbsoluteTimelockType type) {
    final s = state;
    if (s is! ProjectDetailLoaded || s.editedPaths == null) return;
    final paths = List.of(s.editedPaths!);
    paths[pathIndex] = paths[pathIndex].copyWith(absTimelockType: type);
    emit(s.copyWith(editedPaths: paths, isDirty: true));
  }

  void updatePathAbsTimelockValue(int pathIndex, int value) {
    final s = state;
    if (s is! ProjectDetailLoaded || s.editedPaths == null) return;
    final paths = List.of(s.editedPaths!);
    _updatePathAndCheckKeyPath(paths, pathIndex, paths[pathIndex].copyWith(absTimelockValue: value));
    emit(s.copyWith(editedPaths: paths, isDirty: true));
  }

  void updatePathIsKeyPath(int pathIndex, bool value) {
    final s = state;
    if (s is! ProjectDetailLoaded || s.editedPaths == null) return;
    final paths = List.of(s.editedPaths!);

    // If marking as key-path, unmark all other paths
    if (value) {
      for (int i = 0; i < paths.length; i++) {
        if (i != pathIndex) {
          paths[i] = paths[i].copyWith(isKeyPath: false);
        }
      }
    }

    paths[pathIndex] = paths[pathIndex].copyWith(isKeyPath: value);
    emit(s.copyWith(editedPaths: paths, isDirty: true));
  }

  void updatePathPriority(int pathIndex, int priority) {
    final s = state;
    if (s is! ProjectDetailLoaded || s.editedPaths == null) return;
    final paths = List.of(s.editedPaths!);
    paths[pathIndex] = paths[pathIndex].copyWith(priority: priority.clamp(0, 9));
    emit(s.copyWith(editedPaths: paths, isDirty: true));
  }

  void updatePathCustomName(int pathIndex, String? customName) {
    final s = state;
    if (s is! ProjectDetailLoaded || s.editedPaths == null) return;
    final paths = List.of(s.editedPaths!);
    final oldPath = paths[pathIndex];
    paths[pathIndex] = EditableSpendPath(
      originalDbId: oldPath.originalDbId,
      threshold: oldPath.threshold,
      mfps: oldPath.mfps,
      relTimelockType: oldPath.relTimelockType,
      relTimelockValue: oldPath.relTimelockValue,
      absTimelockType: oldPath.absTimelockType,
      absTimelockValue: oldPath.absTimelockValue,
      customName: customName,
      isKeyPath: oldPath.isKeyPath,
      priority: oldPath.priority,
    );
    emit(s.copyWith(editedPaths: paths, isDirty: true));
  }

  /// Update the wallet type in edit mode
  void updateWalletType(APIWalletType walletType) {
    final s = state;
    if (s is! ProjectDetailLoaded || !s.isEditing) return;

    List<EditableSpendPath>? updatedPaths;
    final currentWalletType = s.editedWalletType ?? APIWalletType.values.byName(s.project.walletType);

    // When changing wallet type, handle keypath states
    if (s.editedPaths != null) {
      // If changing FROM Taproot to another type, clear all keypath flags
      if (currentWalletType == APIWalletType.p2Tr && walletType != APIWalletType.p2Tr) {
        updatedPaths = s.editedPaths!
            .map((p) => p.copyWith(isKeyPath: false))
            .toList();
      }
      // If changing TO Taproot from another type, ensure all keypath flags start as false
      // (user can manually select which one should be keypath)
      else if (currentWalletType != APIWalletType.p2Tr && walletType == APIWalletType.p2Tr) {
        updatedPaths = s.editedPaths!
            .map((p) => p.copyWith(isKeyPath: false))
            .toList();
      }
    }

    emit(s.copyWith(
      editedWalletType: walletType,
      editedPaths: updatedPaths,
      isDirty: true,
    ));
  }

  /// Check if current spend paths represent single-sig (only one path with threshold=1, mfps.length=1)
  bool _isSingleSig(List<EditableSpendPath> paths) {
    return paths.length == 1 &&
           paths[0].threshold == 1 &&
           paths[0].mfps.length == 1;
  }

  /// Get compatible wallet types based on current spend paths
  List<APIWalletType> getCompatibleWalletTypes() {
    final s = state;
    if (s is! ProjectDetailLoaded || s.editedPaths == null) {
      return [];
    }

    final isSingleSig = _isSingleSig(s.editedPaths!);

    if (isSingleSig) {
      // Single-sig: all types are compatible
      return [
        APIWalletType.p2Wpkh,
        APIWalletType.p2ShWpkh,
        APIWalletType.p2Wsh,
        APIWalletType.p2ShWsh,
        APIWalletType.p2Sh,
        APIWalletType.p2Tr,
      ];
    } else {
      // Multi-sig: only complex types are compatible (no wpkh)
      return [
        APIWalletType.p2Wsh,
        APIWalletType.p2ShWsh,
        APIWalletType.p2Sh,
        APIWalletType.p2Tr,
      ];
    }
  }

  void addSpendPath() {
    final s = state;
    if (s is! ProjectDetailLoaded || s.editedPaths == null) return;
    final paths = List.of(s.editedPaths!)..add(EditableSpendPath());
    emit(s.copyWith(editedPaths: paths, isDirty: true));
  }

  void removeSpendPath(int pathIndex) {
    final s = state;
    if (s is! ProjectDetailLoaded || s.editedPaths == null) return;
    final paths = List.of(s.editedPaths!)..removeAt(pathIndex);
    emit(s.copyWith(editedPaths: paths, isDirty: true));
  }

  // --- Key management methods ---

  Future<void> addKey(EditableKey key) async {
    final s = state;
    if (s is! ProjectDetailLoaded || s.editedKeys == null) return;

    // Save the key to the database immediately
    final keyId = await _db.into(_db.projectKeys).insert(
      ProjectKeysCompanion.insert(
        projectId: projectId,
        mfp: key.mfp,
        derivationPath: key.derivationPath,
        xpub: key.xpub,
        customName: Value(key.customName),
      ),
    );

    // Update the editable key with the database ID
    final keyWithId = EditableKey(
      originalDbId: keyId,
      mfp: key.mfp,
      derivationPath: key.derivationPath,
      xpub: key.xpub,
      customName: key.customName,
    );

    final keys = List.of(s.editedKeys!)..add(keyWithId);
    emit(s.copyWith(editedKeys: keys, isDirty: true));
  }

  Future<void> removeKey(String mfp) async {
    final s = state;
    if (s is! ProjectDetailLoaded || s.editedKeys == null || s.editedPaths == null) return;

    // Note: This validation is also done in the UI (button is disabled),
    // but we keep it here as defensive programming
    final isInUse = s.editedPaths!.any((path) => path.mfps.contains(mfp));
    if (isInUse) return;

    // Find the key to get its database ID
    final keyToRemove = s.editedKeys!.firstWhere((k) => k.mfp == mfp);

    // Remove from database if it has a database ID
    if (keyToRemove.originalDbId != null) {
      await (_db.delete(_db.projectKeys)
            ..where((k) => k.id.equals(keyToRemove.originalDbId!)))
          .go();
    }

    final keys = List.of(s.editedKeys!)..removeWhere((k) => k.mfp == mfp);
    emit(s.copyWith(editedKeys: keys, isDirty: true));
  }

  Future<void> updateKeyCustomName(String mfp, String? customName) async {
    final s = state;
    if (s is! ProjectDetailLoaded || s.editedKeys == null) return;

    final keys = List.of(s.editedKeys!);
    final index = keys.indexWhere((k) => k.mfp == mfp);
    if (index == -1) return;

    final oldKey = keys[index];

    // Update in database if it has a database ID
    if (oldKey.originalDbId != null) {
      await (_db.update(_db.projectKeys)
            ..where((k) => k.id.equals(oldKey.originalDbId!)))
          .write(ProjectKeysCompanion(
        customName: Value(customName),
      ));
    }

    keys[index] = EditableKey(
      originalDbId: oldKey.originalDbId,
      mfp: oldKey.mfp,
      derivationPath: oldKey.derivationPath,
      xpub: oldKey.xpub,
      customName: customName,
    );
    emit(s.copyWith(editedKeys: keys, isDirty: true));
  }

  Future<void> regenerateDescriptor({
    required String buildingDescriptorMessage,
    required String buildingDescriptorMultiPathMessage,
    required String buildingComplexDescriptorMessage,
    required String analyzingDescriptorMessage,
    required String analyzingComplexDescriptorMessage,
    required String analyzingAndSavingMessage,
  }) async {
    final s = state;
    if (s is! ProjectDetailLoaded || s.editedPaths == null || s.editedKeys == null) return;

    // Save current state to restore on error
    final previousState = s;

    try {
      // Validate all paths before proceeding
      final validationErrors = <String>[];
      final walletType = s.editedWalletType ?? APIWalletType.values.byName(s.project.walletType);
      final isTaproot = walletType == APIWalletType.p2Tr;

      // Validate that all referenced MFPs exist in edited keys
      final availableMfps = s.editedKeys!.map((k) => k.mfp).toSet();
      for (var i = 0; i < s.editedPaths!.length; i++) {
        final path = s.editedPaths![i];
        if (path.mfps.isEmpty) {
          validationErrors.add('Spend path ${i + 1}: Must have at least one key');
        }
        // Check that all MFPs in path exist in available keys
        for (var mfp in path.mfps) {
          if (!availableMfps.contains(mfp)) {
            validationErrors.add('Spend path ${i + 1}: Key $mfp not found');
          }
        }
        if (path.threshold < 1) {
          validationErrors.add('Spend path ${i + 1}: Threshold must be at least 1');
        }
        if (path.threshold > path.mfps.length) {
          validationErrors
              .add('Spend path ${i + 1}: Threshold cannot exceed number of keys');
        }
      }

      // Taproot-specific validation: ensure only one key-path
      if (isTaproot) {
        final keyPathCount = s.editedPaths!.where((p) => p.isKeyPath).length;
        if (keyPathCount > 1) {
          validationErrors.add(
            'Only one spend path can be marked as key-path in Taproot descriptors.'
          );
        }
      }

      if (validationErrors.isNotEmpty) {
        // Show validation errors as toast, don't change state
        emit(s.copyWith(errorMessage: validationErrors.join('\n')));
        return;
      }

      // Show progress message for complex descriptors
      final pathCount = s.editedPaths!.length;
      final hasTimelocks = s.editedPaths!.any((p) =>
        p.timelockMode != TimelockMode.none
      );

      String buildMessage;
      String analyzeMessage;

      if (s.editedWalletType != APIWalletType.p2Tr && pathCount > 3 && hasTimelocks) {
        buildMessage = buildingComplexDescriptorMessage;
        analyzeMessage = analyzingComplexDescriptorMessage;
      } else if (pathCount > 3) {
        buildMessage = buildingDescriptorMultiPathMessage;
        analyzeMessage = analyzingDescriptorMessage;
      } else {
        buildMessage = buildingDescriptorMessage;
        analyzeMessage = analyzingDescriptorMessage;
      }

      emit(ProjectDetailLoading(message: buildMessage));

      // Build maps to preserve labels and priorities across regeneration
      // 1. Spend path names and priorities (by rustId)
      final editedPathNames = <int, String?>{};
      final editedPathPriorities = <int, int>{};
      for (final ep in s.editedPaths!) {
        // Only send the active timelock based on mode
        final relTimelock = ep.timelockMode == TimelockMode.relative
            ? APIRelativeTimelock(
                timelockType: ep.relTimelockType.toRust(),
                value: ep.relTimelockValue,
              )
            : APIRelativeTimelock(
                timelockType: APIRelativeTimelockType.blocks,
                value: 0,
              );

        final absTimelock = ep.timelockMode == TimelockMode.absolute
            ? APIAbsoluteTimelock(
                timelockType: ep.absTimelockType.toRust(),
                value: ep.absTimelockValue,
              )
            : APIAbsoluteTimelock(
                timelockType: APIAbsoluteTimelockType.blocks,
                value: 0,
              );

        final rustId = await calculateRustidFromTimelocks(
          threshold: ep.threshold,
          mfps: ep.mfps,
          relTimelock: relTimelock,
          absTimelock: absTimelock,
        );
        if (ep.customName != null) {
          editedPathNames[rustId] = ep.customName;
        }
        editedPathPriorities[rustId] = ep.priority;
      }

      // 2. Key names (by MFP) - including edited names not yet saved
      final editedKeyNames = <String, String?>{
        for (final k in s.editedKeys!) k.mfp: k.customName,
      };

      // Convert edited keys to API keys (only keys used in spend paths)
      final usedMfps = s.editedPaths!
          .expand((p) => p.mfps)
          .toSet();
      final apiKeys = s.editedKeys!
          .where((k) => usedMfps.contains(k.mfp))
          .map((k) => APIPubKey(
                mfp: k.mfp,
                derivationPath: k.derivationPath,
                xpub: k.xpub,
              ))
          .toList();

      // Convert edited paths to API spend path defs
      final apiPaths = s.editedPaths!
          .map((ep) {
            // Only send the active timelock based on mode
            final relTimelock = ep.timelockMode == TimelockMode.relative
                ? APIRelativeTimelock(
                    timelockType: ep.relTimelockType.toRust(),
                    value: ep.relTimelockValue,
                  )
                : APIRelativeTimelock(
                    timelockType: APIRelativeTimelockType.blocks,
                    value: 0,
                  );

            final absTimelock = ep.timelockMode == TimelockMode.absolute
                ? APIAbsoluteTimelock(
                    timelockType: ep.absTimelockType.toRust(),
                    value: ep.absTimelockValue,
                  )
                : APIAbsoluteTimelock(
                    timelockType: APIAbsoluteTimelockType.blocks,
                    value: 0,
                  );

            return APISpendPathDef(
              threshold: ep.threshold,
              mfps: ep.mfps,
              relTimelock: relTimelock,
              absTimelock: absTimelock,
              isKeyPath: ep.isKeyPath,
              priority: ep.priority,
            );
          })
          .toList();

      // Build new descriptor via Rust (walletType already declared above)
      final newDescriptor = await buildDescriptor(
        walletType: walletType,
        keys: apiKeys,
        spendPaths: apiPaths,
      );

      // Re-analyze and persist, passing edited names and unused keys
      final unusedKeys = s.editedKeys!
          .where((k) => !usedMfps.contains(k.mfp))
          .toList();

      await updateDescriptorAndReanalyze(
        newDescriptor,
        editedPathNames: editedPathNames,
        editedPathPriorities: editedPathPriorities,
        editedKeyNames: editedKeyNames,
        unusedKeys: unusedKeys,
        loadingMessage: analyzeMessage,
      );
    } catch (e) {
      // Show error as toast by restoring previous state with error message
      emit(previousState.copyWith(errorMessage: formatRustError(e)));
    }
  }

  Future<void> updateDescriptorAndReanalyze(
    String newDescriptor, {
    Map<int, String?>? editedPathNames,
    Map<int, int>? editedPathPriorities,
    Map<String, String?>? editedKeyNames,
    List<EditableKey>? unusedKeys,
    String? loadingMessage,
  }) async {
    // Save current state to restore on error
    final previousState = state;

    try {
      emit(ProjectDetailLoading(message: loadingMessage));

      // Load existing keys and paths to preserve custom names
      final existingKeys = await _db.getKeysForProject(projectId);
      final existingPaths = await _db.getSpendPathsForProject(projectId);

      // Build maps: MFP -> customName for keys
      final keyNameMap = <String, String?>{
        for (var k in existingKeys) k.mfp: k.customName,
      };

      // Build maps for spend paths: rustId -> customName, rustId -> priority
      final pathNameMap = <int, String?>{
        for (var p in existingPaths) p.rustId: p.customName,
      };
      final pathPriorityMap = <int, int>{
        for (var p in existingPaths) p.rustId: p.priority,
      };

      final result =
          await analyzeDescriptor(descriptor: newDescriptor.trim());

      // Create key entries, preserving customName from:
      // 1. Edited key names (priority - includes unsaved edits)
      // 2. Existing DB key names (fallback)
      final keyEntries = result.keys
          .map((k) {
            final customName = editedKeyNames?.containsKey(k.mfp) == true
                ? editedKeyNames![k.mfp]
                : keyNameMap[k.mfp];
            return ProjectKeysCompanion.insert(
              projectId: projectId,
              mfp: k.mfp,
              derivationPath: k.derivationPath,
              xpub: k.xpub,
              customName: Value(customName),
            );
          })
          .toList();

      // Add unused keys (keys not in any spend path but kept in project)
      if (unusedKeys != null) {
        for (final key in unusedKeys) {
          keyEntries.add(ProjectKeysCompanion.insert(
            projectId: projectId,
            mfp: key.mfp,
            derivationPath: key.derivationPath,
            xpub: key.xpub,
            customName: Value(key.customName),
          ));
        }
      }

      // Create path entries, preserving customName and priority from:
      // 1. Existing DB paths (by rustId)
      // 2. Edited paths (by calculated rustId) if provided
      final pathEntries = result.spendPaths.map((sp) {
        String? customName;
        int priority = 0;

        // First, try to match by rustId from existing DB paths
        customName = pathNameMap[sp.id];
        priority = pathPriorityMap[sp.id] ?? 0;

        // Edited values take precedence over DB values (include unsaved edits)
        if (editedPathNames != null && editedPathNames.containsKey(sp.id)) {
          customName = editedPathNames[sp.id];
        }
        if (editedPathPriorities != null && editedPathPriorities.containsKey(sp.id)) {
          priority = editedPathPriorities[sp.id]!;
        }

        return ProjectSpendPathsCompanion.insert(
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
          priority: Value(priority),
          customName: Value(customName),
        );
      }).toList();

      await _db.replaceAnalysisData(
        projectId: projectId,
        projectUpdate: ProjectsCompanion(
          descriptor: Value(result.descriptor),
          network: Value(result.network.name),
          walletType: Value(result.walletType.name),
          updatedAt: Value(DateTime.now()),
        ),
        newKeys: keyEntries,
        newPaths: pathEntries,
      );

      _mfpColorMap.clear();
      await load();
    } catch (e) {
      // Show error as toast by restoring previous state
      if (previousState is ProjectDetailLoaded) {
        emit(previousState.copyWith(errorMessage: formatRustError(e)));
      } else {
        // Fallback to error state if not in loaded state
        emit(ProjectDetailError(formatRustError(e)));
      }
    }
  }

  void clearError() {
    final s = state;
    if (s is ProjectDetailLoaded && s.errorMessage != null) {
      emit(s.copyWith(clearError: true));
    }
  }

  void clearSuccess() {
    final s = state;
    if (s is ProjectDetailLoaded && s.successMessage != null) {
      emit(s.copyWith(clearSuccess: true));
    }
  }

  /// Build export JSON and filename from current state (helper).
  /// Returns the export JSON string for the current state, or null if not loaded.
  ({String jsonString, String fileName})? buildExportPayload() {
    final s = state;
    if (s is! ProjectDetailLoaded) return null;

    final keyLabels = <String, String>{};
    for (final key in s.keys) {
      if (key.customName != null) keyLabels[key.mfp] = key.customName!;
    }

    final pathLabels = <String, String>{};
    for (final path in s.spendPaths) {
      if (path.customName != null) {
        pathLabels[path.rustId.toString()] = path.customName!;
      }
    }

    final exportData = ProjectExport(
      version: 1,
      exportedAt: DateTime.now(),
      name: s.project.name,
      descriptor: s.project.descriptor,
      keyLabels: keyLabels,
      pathLabels: pathLabels,
    );

    final fileName =
        '${s.project.name.replaceAll(RegExp(r'[^\w\s-]'), '_')}.deadbolt.json';
    return (jsonString: exportData.toJsonString(), fileName: fileName);
  }
}
