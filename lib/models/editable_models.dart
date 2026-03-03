import 'dart:convert';

import 'package:deadbolt/data/database.dart';
import 'package:deadbolt/models/timelock_types.dart';

// ---------------------------------------------------------------------------
// EditableKey
// ---------------------------------------------------------------------------

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

  /// Creates a copy with [name] as the custom name.
  /// Supports clearing the name by passing null.
  EditableKey withCustomName(String? name) => EditableKey(
        originalDbId: originalDbId,
        mfp: mfp,
        derivationPath: derivationPath,
        xpub: xpub,
        customName: name,
      );

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

// ---------------------------------------------------------------------------
// EditableSpendPath
// ---------------------------------------------------------------------------

class EditableSpendPath {
  int? originalDbId;
  int threshold;
  List<String> mfps;

  // Timelock configuration — only one can be active at a time
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

  /// Creates a copy with [name] as the custom name.
  /// Supports clearing the name by passing null.
  EditableSpendPath withCustomName(String? name) => EditableSpendPath(
        originalDbId: originalDbId,
        threshold: threshold,
        mfps: List.of(mfps),
        timelockMode: timelockMode,
        relTimelockType: relTimelockType,
        relTimelockValue: relTimelockValue,
        absTimelockType: absTimelockType,
        absTimelockValue: absTimelockValue,
        customName: name,
        isKeyPath: isKeyPath,
        priority: priority,
      );

  static EditableSpendPath fromDb(ProjectSpendPath sp) {
    // Key-path is detected if trDepth == -1 (not a script path)
    final isKeyPath = sp.trDepth == -1;

    // Detect timelock mode based on values
    final TimelockMode mode;
    if (sp.relTimelockValue > 0 && sp.absTimelockValue > 0) {
      // Both set — prefer relative (shouldn't happen with new UI, but handle legacy data)
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

  /// True when this path is eligible to be a key-path (singlesig, no timelocks).
  bool get canBeKeyPath =>
      threshold == 1 &&
      mfps.length == 1 &&
      timelockMode == TimelockMode.none;
}
