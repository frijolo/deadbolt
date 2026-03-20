import 'dart:convert';

import 'package:deadbolt/cubit/cubit_error_logger.dart';
import 'package:deadbolt/errors.dart';
import 'package:deadbolt/models/editable_models.dart';
import 'package:deadbolt/models/project_export.dart';
import 'package:deadbolt/models/timelock_types.dart';
import 'package:deadbolt/services/project_descriptor_service.dart';
import 'package:deadbolt/services/wallet_service.dart';
import 'package:deadbolt/utils/constants.dart';
import 'package:drift/drift.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import 'package:deadbolt/data/database.dart';
import 'package:deadbolt/src/rust/api/model.dart';
import 'package:deadbolt/src/rust/api/wallet.dart' as rust_wallet;

// Re-export editable models so existing imports of this file keep working.
export 'package:deadbolt/models/editable_models.dart';

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
  /// Hot signing keys stored in the encrypted project_seeds.db.
  final List<APIHotKeyInfo> hotKeys;

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
    List<APIHotKeyInfo>? hotKeys,
  }) : hotKeys = hotKeys ?? [];

  bool get isEditing => editedPaths != null && editedKeys != null;

  APIWalletType get currentWalletType =>
      editedWalletType ?? APIWalletType.values.byName(project.walletType);

  int get displayPathCount => (editedPaths ?? spendPaths).length;
  int get displayKeyCount => (editedKeys ?? keys).length;

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
    List<APIHotKeyInfo>? hotKeys,
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
      hotKeys: hotKeys ?? this.hotKeys,
    );
  }
}

class ProjectDetailError extends ProjectDetailState {
  final String message;
  ProjectDetailError(this.message);
}

// --- Helpers ---

List<APIHotKeyInfo> _upsertHotKey(List<APIHotKeyInfo> keys, APIHotKeyInfo info) =>
    [...keys.where((k) => k.mfp != info.mfp), info];

List<APIHotKeyInfo> _removeHotKey(List<APIHotKeyInfo> keys, String mfp) =>
    keys.where((k) => k.mfp != mfp).toList();

// --- Cubit ---

class ProjectDetailCubit extends Cubit<ProjectDetailState> with CubitErrorLogger {
  final AppDatabase _db;
  final ProjectDescriptorService _service;
  final WalletService? _walletService;
  final int projectId;

  final Map<String, int> _mfpColorMap = {};

  ProjectDetailCubit(
    this._db,
    this.projectId, {
    ProjectDescriptorService? service,
    WalletService? walletService,
  })  : _service = service ?? const ProjectDescriptorService(),
        _walletService = walletService,
        super(ProjectDetailLoading()) {
    load();
  }

  int getMfpColorIndex(String mfp) {
    return _mfpColorMap.putIfAbsent(mfp, () => _mfpColorMap.length);
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

      // Build color index map from keys
      for (final key in keys) {
        getMfpColorIndex(key.mfp);
      }

      // Load persisted hot keys from encrypted project_seeds.db
      final hotKeys = await _loadHotKeys();

      emit(ProjectDetailLoaded(
        project: project,
        keys: keys,
        spendPaths: spendPaths,
        keysExpanded: preserveKeysExpanded,
        spendPathsExpanded: preserveSpendPathsExpanded,
        hotKeys: hotKeys,
      ));

      // Always enter edit mode so keys and paths are immediately editable
      enterEditMode();
    } catch (e, st) {
      logError('ProjectDetailCubit.load()', e, st);
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
    final currentWalletType = s.currentWalletType;
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
    // Reset editable buffers to the last saved DB state without leaving edit mode
    final editablePaths = s.spendPaths.map(EditableSpendPath.fromDb).toList();
    final editableKeys = s.keys.map(EditableKey.fromDb).toList();
    final currentWalletType = s.currentWalletType;
    emit(s.copyWith(
      editedPaths: editablePaths,
      editedKeys: editableKeys,
      editedWalletType: currentWalletType,
      isDirty: false,
    ));
  }

  /// Generic helper: apply [update] to paths[index], auto-clear isKeyPath when
  /// the updated path is no longer eligible (e.g. became multisig or gained a
  /// timelock), then emit dirty state.
  void _updatePath(
    int index,
    EditableSpendPath Function(EditableSpendPath) update,
  ) {
    final s = state;
    if (s is! ProjectDetailLoaded || s.editedPaths == null) return;
    final paths = List.of(s.editedPaths!);
    final updated = update(paths[index]);
    paths[index] = !updated.canBeKeyPath && updated.isKeyPath
        ? updated.copyWith(isKeyPath: false)
        : updated;
    emit(s.copyWith(editedPaths: paths, isDirty: true));
  }

  void updatePathThreshold(int pathIndex, int value) =>
      _updatePath(pathIndex, (p) => p.copyWith(threshold: value));

  void addMfpToPath(int pathIndex, String mfp) =>
      _updatePath(pathIndex, (p) => p.copyWith(mfps: [...p.mfps, mfp]));

  void removeMfpFromPath(int pathIndex, String mfp) =>
      _updatePath(pathIndex, (p) => p.copyWith(mfps: p.mfps.where((m) => m != mfp).toList()));

  void updatePathTimelockMode(int pathIndex, TimelockMode mode) =>
      _updatePath(pathIndex, (p) => p.copyWith(timelockMode: mode));

  void updatePathRelTimelockType(int pathIndex, RelativeTimelockType type) =>
      _updatePath(pathIndex, (p) => p.copyWith(relTimelockType: type));

  void updatePathRelTimelockValue(int pathIndex, int value) =>
      _updatePath(pathIndex, (p) => p.copyWith(relTimelockValue: value));

  void updatePathAbsTimelockType(int pathIndex, AbsoluteTimelockType type) =>
      _updatePath(pathIndex, (p) => p.copyWith(absTimelockType: type));

  void updatePathAbsTimelockValue(int pathIndex, int value) =>
      _updatePath(pathIndex, (p) => p.copyWith(absTimelockValue: value));

  void updatePathIsKeyPath(int pathIndex, bool value) {
    final s = state;
    if (s is! ProjectDetailLoaded || s.editedPaths == null) return;
    final paths = List.of(s.editedPaths!);

    // If marking as key-path, unmark all other paths first
    if (value) {
      for (int i = 0; i < paths.length; i++) {
        if (i != pathIndex) paths[i] = paths[i].copyWith(isKeyPath: false);
      }
    }

    paths[pathIndex] = paths[pathIndex].copyWith(isKeyPath: value);
    emit(s.copyWith(editedPaths: paths, isDirty: true));
  }

  void updatePathPriority(int pathIndex, int priority) =>
      _updatePath(pathIndex, (p) => p.copyWith(priority: priority.clamp(0, 9)));

  Future<void> updatePathCustomName(int pathIndex, String? customName) async {
    final s = state;
    if (s is! ProjectDetailLoaded || s.editedPaths == null) return;
    final paths = List.of(s.editedPaths!);
    if (pathIndex < 0 || pathIndex >= paths.length) return;
    final path = paths[pathIndex];

    paths[pathIndex] = path.withCustomName(customName);
    // Relabeling does not affect the descriptor — update UI first, then persist.
    emit(s.copyWith(editedPaths: paths));

    if (path.originalDbId != null) {
      await _db.updateSpendPathName(path.originalDbId!, customName);
    }
  }

  /// Update the wallet type in edit mode
  void updateWalletType(APIWalletType walletType) {
    final s = state;
    if (s is! ProjectDetailLoaded || !s.isEditing) return;

    List<EditableSpendPath>? updatedPaths;
    final currentWalletType = s.currentWalletType;

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

    keys[index] = oldKey.withCustomName(customName);
    // Relabeling does not affect the descriptor — update UI first, then persist.
    emit(s.copyWith(editedKeys: keys));

    if (oldKey.originalDbId != null) {
      await (_db.update(_db.projectKeys)
            ..where((k) => k.id.equals(oldKey.originalDbId!)))
          .write(ProjectKeysCompanion(customName: Value(customName)));
    }
  }

  Future<void> updateKey(EditableKey updatedKey) async {
    final s = state;
    if (s is! ProjectDetailLoaded || s.editedKeys == null) return;

    final idx = s.editedKeys!.indexWhere((k) => k.mfp == updatedKey.mfp);
    if (idx == -1) return;

    final existing = s.editedKeys![idx];
    final dataChanged = existing.derivationPath != updatedKey.derivationPath ||
        existing.xpub != updatedKey.xpub;

    final replacement = EditableKey(
      originalDbId: existing.originalDbId,
      mfp: updatedKey.mfp,
      derivationPath: updatedKey.derivationPath,
      xpub: updatedKey.xpub,
      customName: existing.customName,
    );

    if (dataChanged && existing.originalDbId != null) {
      await (_db.update(_db.projectKeys)
            ..where((k) => k.id.equals(existing.originalDbId!)))
          .write(ProjectKeysCompanion(
        mfp: Value(replacement.mfp),
        derivationPath: Value(replacement.derivationPath),
        xpub: Value(replacement.xpub),
      ));
    }

    final keys = List.of(s.editedKeys!)..[idx] = replacement;
    emit(s.copyWith(editedKeys: keys, isDirty: dataChanged ? true : null));
  }

  // ---------------------------------------------------------------------------
  // Project hot-key (seed) management
  // ---------------------------------------------------------------------------

  Future<({String appDir, String deviceKey})> _getAppDirAndKey() async {
    final service = _walletService!;
    final appDir = await service.getAppSupportDir();
    final deviceKey = await service.getOrCreateEncryptionKey();
    return (appDir: appDir, deviceKey: deviceKey);
  }

  Future<List<APIHotKeyInfo>> _loadHotKeys() async {
    if (_walletService == null) return [];
    try {
      final (:appDir, :deviceKey) = await _getAppDirAndKey();
      return rust_wallet.listProjectHotKeys(
        appSupportDir: appDir,
        projectId: projectId,
        deviceKeyHex: deviceKey,
      );
    } catch (_) {
      return [];
    }
  }

  Future<APIHotKeyInfo?> addProjectMnemonicHotKey(
    String mnemonic,
    String? passphrase,
  ) async {
    if (_walletService == null) return null;
    final s = state;
    if (s is! ProjectDetailLoaded) return null;
    try {
      final (:appDir, :deviceKey) = await _getAppDirAndKey();
      final network = APINetwork.values.byName(s.project.network);
      final info = rust_wallet.addProjectMnemonicKey(
        appSupportDir: appDir,
        projectId: projectId,
        mnemonic: mnemonic,
        passphrase: passphrase,
        network: network,
        deviceKeyHex: deviceKey,
      );
      emit(s.copyWith(hotKeys: _upsertHotKey(s.hotKeys, info)));
      return info;
    } catch (e, st) {
      logError('ProjectDetailCubit.addProjectMnemonicHotKey()', e, st);
      emit(s.copyWith(errorMessage: formatRustError(e)));
      return null;
    }
  }

  Future<APIHotKeyInfo?> addProjectXprvHotKey(String xprv) async {
    if (_walletService == null) return null;
    final s = state;
    if (s is! ProjectDetailLoaded) return null;
    try {
      final (:appDir, :deviceKey) = await _getAppDirAndKey();
      final info = rust_wallet.addProjectXprvKey(
        appSupportDir: appDir,
        projectId: projectId,
        xprv: xprv,
        deviceKeyHex: deviceKey,
      );
      emit(s.copyWith(hotKeys: _upsertHotKey(s.hotKeys, info)));
      return info;
    } catch (e, st) {
      logError('ProjectDetailCubit.addProjectXprvHotKey()', e, st);
      emit(s.copyWith(errorMessage: formatRustError(e)));
      return null;
    }
  }

  Future<void> deleteProjectHotKey(String mfp) async {
    if (_walletService == null) return;
    final s = state;
    if (s is! ProjectDetailLoaded) return;
    try {
      final (:appDir, :deviceKey) = await _getAppDirAndKey();
      rust_wallet.deleteProjectHotKey(
        appSupportDir: appDir,
        projectId: projectId,
        mfp: mfp,
        deviceKeyHex: deviceKey,
      );
      emit(s.copyWith(hotKeys: _removeHotKey(s.hotKeys, mfp)));
    } catch (e, st) {
      logError('ProjectDetailCubit.deleteProjectHotKey()', e, st);
      emit(s.copyWith(errorMessage: formatRustError(e)));
    }
  }

  Future<String?> revealProjectSeed(String mfp) async {
    if (_walletService == null) return null;
    try {
      final (:appDir, :deviceKey) = await _getAppDirAndKey();
      return rust_wallet.revealProjectSeed(
        appSupportDir: appDir,
        projectId: projectId,
        mfp: mfp,
        deviceKeyHex: deviceKey,
      );
    } catch (e, st) {
      logError('ProjectDetailCubit.revealProjectSeed()', e, st);
      final s = state;
      if (s is ProjectDetailLoaded) {
        emit(s.copyWith(errorMessage: formatRustError(e)));
      }
      return null;
    }
  }

  List<String> _validatePaths(
    List<EditableSpendPath> paths,
    Set<String> availableMfps,
    bool isTaproot,
  ) {
    final errors = <String>[];
    for (var i = 0; i < paths.length; i++) {
      final path = paths[i];
      if (path.mfps.isEmpty) {
        errors.add('Spend path ${i + 1}: Must have at least one key');
      }
      for (final mfp in path.mfps) {
        if (!availableMfps.contains(mfp)) {
          errors.add('Spend path ${i + 1}: Key $mfp not found');
        }
      }
      if (path.threshold < 1) {
        errors.add('Spend path ${i + 1}: Threshold must be at least 1');
      }
      if (path.threshold > path.mfps.length) {
        errors.add('Spend path ${i + 1}: Threshold cannot exceed number of keys');
      }
    }
    if (isTaproot) {
      final keyPathCount = paths.where((p) => p.isKeyPath).length;
      if (keyPathCount > 1) {
        errors.add('Only one spend path can be marked as key-path in Taproot descriptors.');
      }
    }
    return errors;
  }

  List<APIPubKey> _buildApiKeys(List<EditableKey> editedKeys, Set<String> usedMfps) {
    return editedKeys
        .where((k) => usedMfps.contains(k.mfp))
        .map((k) => APIPubKey(
              mfp: k.mfp,
              derivationPath: k.derivationPath,
              xpub: k.xpub,
            ))
        .toList();
  }

  List<APISpendPathDef> _buildApiPaths(List<EditableSpendPath> editedPaths) {
    return editedPaths.map((ep) {
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
    }).toList();
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
      final walletType = s.currentWalletType;
      final isTaproot = walletType == APIWalletType.p2Tr;
      final availableMfps = s.editedKeys!.map((k) => k.mfp).toSet();
      final validationErrors = _validatePaths(s.editedPaths!, availableMfps, isTaproot);

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
        final rustId = await _service.calculateRustidFromTimelocks(
          threshold: ep.threshold,
          mfps: ep.mfps,
          timelockMode: ep.timelockMode,
          relType: ep.relTimelockType,
          relValue: ep.relTimelockValue,
          absType: ep.absTimelockType,
          absValue: ep.absTimelockValue,
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

      // Convert edited keys and paths to API types
      final usedMfps = s.editedPaths!.expand((p) => p.mfps).toSet();
      final apiKeys = _buildApiKeys(s.editedKeys!, usedMfps);
      final apiPaths = _buildApiPaths(s.editedPaths!);

      // Build new descriptor via Rust (walletType already declared above)
      final newDescriptor = await _service.buildDescriptor(
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
    } catch (e, st) {
      logError('ProjectDetailCubit.regenerateDescriptor()', e, st);
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
          await _service.analyzeDescriptor(newDescriptor);

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
    } catch (e, st) {
      logError('ProjectDetailCubit.updateDescriptorAndReanalyze()', e, st);
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

    final exportData = ProjectExport(
      version: 1,
      exportedAt: DateTime.now(),
      name: s.project.name,
      descriptor: s.project.descriptor,
      keyLabels: buildKeyLabels(s.keys),
      pathLabels: buildPathLabels(s.spendPaths),
    );

    final fileName =
        '${s.project.name.replaceAll(invalidFileNameCharsRegex, '_')}.deadbolt.json';
    return (jsonString: exportData.toJsonString(), fileName: fileName);
  }
}
