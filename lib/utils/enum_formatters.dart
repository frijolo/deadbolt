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

// For drift string-based values
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
