import 'package:deadbolt/src/rust/api/analyzer.dart' show APIAnalysisResult;
import 'package:deadbolt/src/rust/api/model.dart' show APIAddress,
    APIBalance,
    APIHotKeyInfo,
    APIPsbtAnalysis,
    APIPsbtInfo,
    APINetwork,
    APITransaction,
    APIUtxo,
    APIWalletInfo;
import 'package:deadbolt/cubit/loaded_wallet.dart' show LoadedWallet;

// ─── Sub-state classes ──────────────────────────────────────────────────────

class WalletInfo {
  final APIWalletInfo walletInfo;
  final APIBalance balance;
  final bool hasBiometricSlot;
  final int tipHeight;

  const WalletInfo({
    required this.walletInfo,
    required this.balance,
    required this.hasBiometricSlot,
    required this.tipHeight,
  });
}

class TransactionPage {
  final List<APITransaction> transactions;
  final int totalCount;
  final bool hasMore;
  final int currentPage;

  const TransactionPage({
    required this.transactions,
    required this.totalCount,
    required this.hasMore,
    required this.currentPage,
  });
}

class AddressView {
  final List<APIAddress> receiveAddresses;
  final List<APIAddress> changeAddresses;
  final bool receiveLoaded;
  final bool changeLoaded;
  final int selectedKeychain;

  const AddressView({
    required this.receiveAddresses,
    required this.changeAddresses,
    required this.receiveLoaded,
    required this.changeLoaded,
    required this.selectedKeychain,
  });
}

class CoinView {
  final List<APIUtxo> utxos;
  final bool loaded;

  const CoinView({required this.utxos, required this.loaded});
}

class DescriptorView {
  final APIAnalysisResult? analysis;
  final Map<String, String> keyLabels;
  final Map<int, String> pathLabels;
  final bool loaded;

  const DescriptorView({
    this.analysis,
    required this.keyLabels,
    required this.pathLabels,
    required this.loaded,
  });
}

class PsbtList {
  final List<APIPsbtInfo> psbts;
  final Map<int, APIPsbtAnalysis> analyses;
  final bool loaded;

  const PsbtList({
    required this.psbts,
    required this.analyses,
    required this.loaded,
  });
}

class FiatPrices {
  final Map<String, double> prices;
  final double? currentBtcPrice;
  final String? currency;

  const FiatPrices({
    required this.prices,
    this.currentBtcPrice,
    this.currency,
  });
}

// ─── View interface ─────────────────────────────────────────────────────────

class WalletDetailView {
  final WalletInfo info;
  final TransactionPage transactions;
  final AddressView addresses;
  final CoinView coins;
  final DescriptorView descriptor;
  final PsbtList psbts;
  final List<APIHotKeyInfo> hotKeys;
  final FiatPrices fiat;

  const WalletDetailView({
    required this.info,
    required this.transactions,
    required this.addresses,
    required this.coins,
    required this.descriptor,
    required this.psbts,
    required this.hotKeys,
    required this.fiat,
  });
}

// ─── Load result types ──────────────────────────────────────────────────────

sealed class WalletLoadResult {
  const WalletLoadResult();
}

class WalletLoadSuccess extends WalletLoadResult {
  final WalletDetailView view;
  final LoadedWallet wallet;
  const WalletLoadSuccess(this.view, this.wallet);
}

class WalletLoadNeedsPassword extends WalletLoadResult {
  final bool isXpubKey;
  final APINetwork? network;
  const WalletLoadNeedsPassword({required this.isXpubKey, this.network});
}
