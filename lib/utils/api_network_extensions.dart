import 'package:deadbolt/src/rust/api/model.dart';

/// Helpers around [APINetwork] to centralize patterns previously duplicated
/// across cubits, widgets and screens (parsing from a stored string,
/// checking for mainnet, deriving the BIP-44 coin type).
extension APINetworkX on APINetwork {
  /// `true` only for the production Bitcoin network.
  bool get isMainnet => this == APINetwork.bitcoin;

  /// BIP-44 coin type: `'0'` for mainnet, `'1'` for every test network.
  String get coinType => isMainnet ? '0' : '1';

  /// Capitalized network suffix used as a stable key in maps and
  /// SharedPreferences entries (e.g. `'Mainnet'`, `'Testnet4'`). Not localized.
  String get suffix => switch (this) {
        APINetwork.bitcoin => 'Mainnet',
        APINetwork.testnet => 'Testnet',
        APINetwork.testnet4 => 'Testnet4',
        APINetwork.signet => 'Signet',
        APINetwork.regtest => 'Regtest',
      };
}

/// Safe parser for a stored `APINetwork.name` string. Returns `null` when the
/// input is `null` or does not match any enum value, instead of throwing the
/// way `APINetwork.values.byName()` does.
APINetwork? apiNetworkFromName(String? name) {
  if (name == null) return null;
  for (final n in APINetwork.values) {
    if (n.name == name) return n;
  }
  return null;
}
