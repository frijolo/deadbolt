import 'package:deadbolt/cubit/settings_cubit.dart';
import 'package:deadbolt/src/rust/api/model.dart';
import 'package:deadbolt/utils/api_network_extensions.dart';

/// Extension methods that move business logic out of [AppSettings].
///
/// These methods were previously instance methods on [AppSettings]. They have
/// been moved here to keep the data class focused on state representation
/// while keeping the lookup logic reusable across callers.
extension AppSettingsX on AppSettings {
  /// Returns the Electrum server URL for [net], using the persisted URL if
  /// available, falling back to the built-in default.
  String electrumUrlForNetwork(APINetwork net) {
    final suffix = net.suffix;
    return electrumUrls[suffix] ?? AppSettings.kElectrumDefaults[suffix]!;
  }

  /// Returns the explorer base URL for [net], using the persisted URL if
  /// available, falling back to the built-in default.
  String explorerBaseForNetwork(APINetwork net) {
    final suffix = net.suffix;
    return explorerUrls[suffix] ?? AppSettings.kExplorerDefaults[suffix]!;
  }

  /// Returns a block explorer URL for an address on [net].
  /// Returns an empty string if the explorer base URL is empty.
  String explorerAddressUrl(APINetwork net, String address) {
    final base = explorerBaseForNetwork(net);
    if (base.isEmpty) return '';
    return '$base/address/$address';
  }

  /// Returns a block explorer URL for a transaction on [net].
  /// Returns an empty string if the explorer base URL is empty.
  String explorerTxUrl(APINetwork net, String txid) {
    final base = explorerBaseForNetwork(net);
    if (base.isEmpty) return '';
    return '$base/tx/$txid';
  }
}
