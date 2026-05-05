import 'package:deadbolt/models/editable_models.dart';
import 'package:deadbolt/models/timelock_types.dart';
import 'package:deadbolt/src/rust/api/analyzer.dart' as rust_api;
import 'package:deadbolt/src/rust/api/model.dart';

/// Service encapsulating all FFI calls and pure business logic for descriptor
/// analysis and building. Stateless — safe to call from any context.
///
/// The cubit uses this service for FFI operations and owns all state
/// management and database operations independently.
class ProjectDescriptorService {
  const ProjectDescriptorService();

  /// Analyze a descriptor string and return parsed keys and spend paths.
  Future<rust_api.APIAnalysisResult> analyzeDescriptor(String descriptor) {
    return rust_api.analyzeDescriptor(descriptor: descriptor.trim());
  }

  /// Build a descriptor from wallet type, keys, and spend path definitions.
  Future<String> buildDescriptor({
    required APIWalletType walletType,
    required List<APIPubKey> keys,
    required List<APISpendPathDef> spendPaths,
  }) {
    return rust_api.buildDescriptor(
      walletType: walletType,
      keys: keys,
      spendPaths: spendPaths,
    );
  }

  /// Validate a key and check its network compatibility.
  ///
  /// Throws an exception with a descriptive message if invalid.
  Future<void> validateKey({
    required String mfp,
    required String derivationPath,
    required String xpub,
    required APINetwork network,
  }) {
    return rust_api.validateKey(
      mfp: mfp,
      derivationPath: derivationPath,
      xpub: xpub,
      network: network,
    );
  }

  /// Calculate the deterministic rustId for a spend path from its semantic
  /// timelock values (type + value), rather than from raw consensus integers.
  Future<int> calculateRustidFromTimelocks({
    required int threshold,
    required List<String> mfps,
    required TimelockMode timelockMode,
    required RelativeTimelockType relType,
    required int relValue,
    required AbsoluteTimelockType absType,
    required int absValue,
  }) async {
    final relTimelock = buildRelativeTimelock(
      timelockMode: timelockMode,
      relTimelockType: relType,
      relTimelockValue: relValue,
    );
    final absTimelock = buildAbsoluteTimelock(
      timelockMode: timelockMode,
      absTimelockType: absType,
      absTimelockValue: absValue,
    );

    return rust_api.calculateRustidFromTimelocks(
      threshold: threshold,
      mfps: mfps,
      relTimelock: relTimelock,
      absTimelock: absTimelock,
    );
  }

  /// Build the [APIRelativeTimelock] value from an editable spend path's
  /// timelock settings, zeroing out inactive timelocks.
  APIRelativeTimelock buildRelativeTimelock({
    required TimelockMode timelockMode,
    required RelativeTimelockType relTimelockType,
    required int relTimelockValue,
  }) {
    if (timelockMode == TimelockMode.relative) {
      return APIRelativeTimelock(
        timelockType: relTimelockType.toRust(),
        value: relTimelockValue,
      );
    }
    return kNoRelativeTimelock;
  }

  /// Build the [APIAbsoluteTimelock] value from an editable spend path's
  /// timelock settings, zeroing out inactive timelocks.
  APIAbsoluteTimelock buildAbsoluteTimelock({
    required TimelockMode timelockMode,
    required AbsoluteTimelockType absTimelockType,
    required int absTimelockValue,
  }) {
    if (timelockMode == TimelockMode.absolute) {
      return APIAbsoluteTimelock(
        timelockType: absTimelockType.toRust(),
        value: absTimelockValue,
      );
    }
    return kNoAbsoluteTimelock;
  }

  /// Validate the structural integrity of edited spend paths against the
  /// keys available in the project. Returns a list of human-readable error
  /// messages; an empty list means the paths are valid.
  List<String> validatePaths(
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

  /// Convert edited keys into FFI [APIPubKey] values, filtering out keys
  /// not referenced by any active spend path.
  List<APIPubKey> buildApiKeys(List<EditableKey> editedKeys, Set<String> usedMfps) {
    return editedKeys
        .where((k) => usedMfps.contains(k.mfp))
        .map((k) => APIPubKey(
              mfp: k.mfp,
              derivationPath: k.derivationPath,
              xpub: k.xpub,
            ))
        .toList();
  }

  /// Convert edited spend paths into FFI [APISpendPathDef] values, applying
  /// the timelock-mode logic so inactive timelocks become no-ops.
  List<APISpendPathDef> buildApiPaths(List<EditableSpendPath> editedPaths) {
    return editedPaths.map((ep) {
      return APISpendPathDef(
        threshold: ep.threshold,
        mfps: ep.mfps,
        relTimelock: buildRelativeTimelock(
          timelockMode: ep.timelockMode,
          relTimelockType: ep.relTimelockType,
          relTimelockValue: ep.relTimelockValue,
        ),
        absTimelock: buildAbsoluteTimelock(
          timelockMode: ep.timelockMode,
          absTimelockType: ep.absTimelockType,
          absTimelockValue: ep.absTimelockValue,
        ),
        isKeyPath: ep.isKeyPath,
        priority: ep.priority,
      );
    }).toList();
  }
}
