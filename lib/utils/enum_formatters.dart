import 'package:flutter/widgets.dart';

import 'package:deadbolt/l10n/l10n.dart';
import 'package:deadbolt/src/rust/api/model.dart';

extension NetworkDisplay on APINetwork {
  String get displayName {
    return switch (this) {
      APINetwork.bitcoin => 'Mainnet',
      APINetwork.testnet => 'Testnet',
      APINetwork.testnet4 => 'Testnet4',
      APINetwork.signet => 'Signet',
      APINetwork.regtest => 'Regtest',
    };
  }
}

extension WalletTypeDisplay on APIWalletType {
  String get displayName {
    return switch (this) {
      APIWalletType.p2Pkh => 'Legacy (P2PKH)',
      APIWalletType.p2Wpkh => 'Segwit (P2WPKH)',
      APIWalletType.p2Sh => 'Legacy (P2SH)',
      APIWalletType.p2Wsh => 'Segwit (P2WSH)',
      APIWalletType.p2Tr => 'Taproot (P2TR)',
      APIWalletType.p2ShWpkh => 'Nested Segwit (P2SH-WPKH)',
      APIWalletType.p2ShWsh => 'Nested Segwit (P2SH-WSH)',
      APIWalletType.unknown => 'Unknown',
    };
  }
}

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

String walletTypeDisplayName(String walletType) {
  return switch (walletType) {
    'p2Pkh' => 'P2PKH',
    'p2Wpkh' => 'P2WPKH',
    'p2Sh' => 'P2SH',
    'p2Wsh' => 'P2WSH',
    'p2Tr' => 'P2TR',
    'p2ShWpkh' => 'P2SH-WPKH',
    'p2ShWsh' => 'P2SH-WSH',
    'unknown' => 'Unknown',
    _ => walletType,
  };
}
