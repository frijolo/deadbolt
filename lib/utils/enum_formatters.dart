import 'package:flutter/widgets.dart';

import 'package:deadbolt/l10n/l10n.dart';
import 'package:deadbolt/src/rust/api/model.dart';

// ─── Two-axis wallet type selector model ──────────────────────────────────────

/// Spending policy dimension: single key vs complex script.
enum WalletPolicy { singleSig, miniscript }

/// Address format dimension: encoding of the output script.
enum WalletAddressFormat { legacy, segwit, nestedSegwit, taproot }

/// Derive the [WalletPolicy] axis from a concrete [APIWalletType].
WalletPolicy walletPolicyFrom(APIWalletType t) => switch (t) {
  APIWalletType.p2Pkh ||
  APIWalletType.p2Wpkh ||
  APIWalletType.p2ShWpkh ||
  APIWalletType.p2Tr => WalletPolicy.singleSig,
  _ => WalletPolicy.miniscript,
};

/// Derive the [WalletAddressFormat] axis from a concrete [APIWalletType].
WalletAddressFormat walletAddressFormatFrom(APIWalletType t) => switch (t) {
  APIWalletType.p2Pkh || APIWalletType.p2Sh => WalletAddressFormat.legacy,
  APIWalletType.p2Wpkh || APIWalletType.p2Wsh => WalletAddressFormat.segwit,
  APIWalletType.p2ShWpkh || APIWalletType.p2ShWsh => WalletAddressFormat.nestedSegwit,
  _ => WalletAddressFormat.taproot,
};

/// Reconstruct a concrete [APIWalletType] from the two selector axes.
APIWalletType walletTypeFromAxes(WalletPolicy policy, WalletAddressFormat format) =>
    switch ((policy, format)) {
      (WalletPolicy.singleSig,   WalletAddressFormat.legacy)       => APIWalletType.p2Pkh,
      (WalletPolicy.singleSig,   WalletAddressFormat.segwit)       => APIWalletType.p2Wpkh,
      (WalletPolicy.singleSig,   WalletAddressFormat.nestedSegwit) => APIWalletType.p2ShWpkh,
      (WalletPolicy.singleSig,   WalletAddressFormat.taproot)      => APIWalletType.p2Tr,
      (WalletPolicy.miniscript,  WalletAddressFormat.legacy)       => APIWalletType.p2Sh,
      (WalletPolicy.miniscript,  WalletAddressFormat.segwit)       => APIWalletType.p2Wsh,
      (WalletPolicy.miniscript,  WalletAddressFormat.nestedSegwit) => APIWalletType.p2ShWsh,
      // Taproot script-path (miniscript policy) also uses p2Tr — BDK has no separate type.
      (WalletPolicy.miniscript,  WalletAddressFormat.taproot)      => APIWalletType.p2Tr,
    };

// Context-aware localized network name (for APINetwork enum values)
String localizedNetworkName(BuildContext context, APINetwork network) {
  final l = context.l10n;
  return switch (network) {
    APINetwork.bitcoin => l.networkMainnet,
    APINetwork.testnet => l.networkTestnet,
    APINetwork.testnet4 => l.networkTestnet4,
    APINetwork.signet => l.networkSignet,
    APINetwork.regtest => l.networkRegtest,
  };
}

// Context-aware localized wallet type name (for APIWalletType enum values)
String localizedWalletTypeName(BuildContext context, APIWalletType type) {
  final l = context.l10n;
  return switch (type) {
    APIWalletType.p2Pkh => l.walletTypeP2pkh,
    APIWalletType.p2Wpkh => l.walletTypeP2wpkh,
    APIWalletType.p2Sh => l.walletTypeP2sh,
    APIWalletType.p2Wsh => l.walletTypeP2wsh,
    APIWalletType.p2Tr => l.walletTypeP2tr,
    APIWalletType.p2ShWpkh => l.walletTypeP2shWpkh,
    APIWalletType.p2ShWsh => l.walletTypeP2shWsh,
    APIWalletType.unknown => l.walletTypeUnknown,
  };
}

// Context-aware localized network name for drift string-based values
String localizedNetworkDisplayName(BuildContext context, String network) {
  final l = context.l10n;
  return switch (network) {
    'bitcoin' => l.networkMainnet,
    'testnet' => l.networkTestnet,
    'testnet4' => l.networkTestnet4,
    'signet' => l.networkSignet,
    'regtest' => l.networkRegtest,
    _ => network,
  };
}

// For drift string-based values (non-localized fallback)
String networkDisplayName(String network) {
  return switch (network) {
    'bitcoin' => 'Mainnet',
    'testnet' => 'Testnet',
    'testnet4' => 'Testnet4',
    'signet' => 'Signet',
    'regtest' => 'Regtest',
    _ => network,
  };
}
