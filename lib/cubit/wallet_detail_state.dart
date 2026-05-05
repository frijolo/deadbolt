import 'package:deadbolt/cubit/loaded_wallet.dart' show LoadedWallet;
import 'package:deadbolt/cubit/wallet_detail_session.dart'
    show
        WalletDetailView,
        WalletInfo,
        TransactionPage,
        AddressView,
        CoinView,
        DescriptorView,
        PsbtList,
        FiatPrices;
import 'package:deadbolt/src/rust/api/analyzer.dart' show APIAnalysisResult;
import 'package:deadbolt/src/rust/api/model.dart';
import 'package:deadbolt/src/rust/api/wallet.dart' show ApiWallet;

const Object _kUndef = Object();

sealed class WalletDetailState {}

class WalletDetailInitial extends WalletDetailState {}

class WalletDetailLoading extends WalletDetailState {
  final String? message;
  WalletDetailLoading({this.message});
}

class WalletDetailNeedsPassword extends WalletDetailState {
  final String walletPath;
  final bool isXpubKey;
  final APINetwork? network;
  WalletDetailNeedsPassword(this.walletPath, {this.isXpubKey = false, this.network});
}

class WalletDetailError extends WalletDetailState {
  final String message;
  WalletDetailError(this.message);
}

class WalletDetailLoaded extends WalletDetailState {
  final WalletInfo _info;
  final TransactionPage _txPage;
  final AddressView _addresses;
  final CoinView _coins;
  final DescriptorView _descriptor;
  final PsbtList _psbts;
  final List<APIHotKeyInfo> _hotKeys;
  final FiatPrices _fiat;

  final LoadedWallet wallet;

  /// Direct FFI handle. Exposed for label setters, preview ops, and the sync
  /// service registration; everything else should go through [wallet].
  ApiWallet get walletHandle => wallet.handle;

  final bool isSyncing;

  final int selectedTab;
  final int selectedAddressKeychain;
  final String? errorMessage;

  WalletDetailView get view => WalletDetailView(
    info: _info,
    transactions: _txPage,
    addresses: _addresses,
    coins: _coins,
    descriptor: _descriptor,
    psbts: _psbts,
    hotKeys: _hotKeys,
    fiat: _fiat,
  );

  // Convenience getters for backward compat with screens
  APIWalletInfo get walletInfo => _info.walletInfo;
  APIBalance get balance => _info.balance;
  List<APITransaction> get transactions => _txPage.transactions;
  int get totalTransactions => _txPage.totalCount;
  bool get hasMore => _txPage.hasMore;
  int get currentPage => _txPage.currentPage;
  List<APIAddress> get receiveAddresses => _addresses.receiveAddresses;
  List<APIAddress> get changeAddresses => _addresses.changeAddresses;
  bool get receiveAddressesLoaded => _addresses.receiveLoaded;
  bool get changeAddressesLoaded => _addresses.changeLoaded;
  List<APIUtxo> get utxos => _coins.utxos;
  bool get utxosLoaded => _coins.loaded;
  int get tipHeight => _info.tipHeight;
  APIAnalysisResult? get descriptorAnalysis => _descriptor.analysis;
  Map<String, String> get keyLabels => _descriptor.keyLabels;
  Map<int, String> get pathLabels => _descriptor.pathLabels;
  bool get descriptorLoaded => _descriptor.loaded;
  List<APIPsbtInfo> get psbts => _psbts.psbts;
  Map<int, APIPsbtAnalysis> get psbtAnalyses => _psbts.analyses;
  bool get psbtsLoaded => _psbts.loaded;
  List<APIHotKeyInfo> get hotKeys => _hotKeys;
  Map<String, double> get fiatPrices => _fiat.prices;
  double? get currentBtcPrice => _fiat.currentBtcPrice;
  String? get fiatCurrency => _fiat.currency;
  bool get hasBiometricSlot => _info.hasBiometricSlot;

  WalletDetailLoaded._({
    required WalletInfo info,
    required TransactionPage txPage,
    required AddressView addresses,
    required CoinView coins,
    required DescriptorView descriptor,
    required PsbtList psbts,
    required List<APIHotKeyInfo> hotKeys,
    required FiatPrices fiat,
    required this.wallet,
    this.selectedTab = 0,
    this.selectedAddressKeychain = 0,
    this.isSyncing = false,
    this.errorMessage,
  })  : _info = info,
        _txPage = txPage,
        _addresses = addresses,
        _coins = coins,
        _descriptor = descriptor,
        _psbts = psbts,
        _hotKeys = hotKeys,
        _fiat = fiat;

  factory WalletDetailLoaded.fromView(WalletDetailView view, LoadedWallet wallet) {
    return WalletDetailLoaded._(
      info: view.info,
      txPage: view.transactions,
      addresses: view.addresses,
      coins: view.coins,
      descriptor: view.descriptor,
      psbts: view.psbts,
      hotKeys: view.hotKeys,
      fiat: view.fiat,
      wallet: wallet,
    );
  }

  WalletDetailLoaded copyWith({
    WalletInfo? info,
    TransactionPage? txPage,
    AddressView? addresses,
    CoinView? coins,
    DescriptorView? descriptor,
    PsbtList? psbts,
    List<APIHotKeyInfo>? hotKeys,
    FiatPrices? fiat,
    int? selectedTab,
    int? selectedAddressKeychain,
    bool? isSyncing,
    Object? errorMessage = _kUndef,
  }) {
    return WalletDetailLoaded._(
      info: info ?? _info,
      txPage: txPage ?? _txPage,
      addresses: addresses ?? _addresses,
      coins: coins ?? _coins,
      descriptor: descriptor ?? _descriptor,
      psbts: psbts ?? _psbts,
      hotKeys: hotKeys ?? _hotKeys,
      fiat: fiat ?? _fiat,
      wallet: wallet,
      selectedTab: selectedTab ?? this.selectedTab,
      selectedAddressKeychain: selectedAddressKeychain ?? this.selectedAddressKeychain,
      isSyncing: isSyncing ?? this.isSyncing,
      errorMessage: identical(errorMessage, _kUndef)
          ? this.errorMessage
          : errorMessage as String?,
    );
  }
}
