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
}
