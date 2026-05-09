import 'package:deadbolt/cubit/loaded_wallet.dart' show LoadedWallet;
import 'package:deadbolt/cubit/wallet_detail/wallet_detail_update.dart';
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
import 'package:deadbolt/cubit/wallet_deltas.dart' show SyncReload;
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

  /// Rebuild [WalletDetailLoaded] after a successful sync reload.
  ///
  /// Every non-null field in [reload] replaces the corresponding value;
  /// null fields preserve the previous state. This factory centralizes the
  /// sync-path mapping so that adding a new state field forces a compile-time
  /// update here instead of silently being dropped in a [copyWith] chain.
  factory WalletDetailLoaded.fromSyncReload(
    WalletDetailLoaded previous,
    SyncReload reload,
  ) {
    final chain = reload.chain!;
    return WalletDetailLoaded._(
      info: WalletInfo(
        walletInfo: chain.info,
        balance: chain.balance,
        hasBiometricSlot: previous.hasBiometricSlot,
        tipHeight: chain.tipHeight,
      ),
      txPage: TransactionPage(
        transactions: chain.transactions.transactions,
        totalCount: chain.transactions.totalCount,
        hasMore: chain.transactions.hasMore,
        currentPage: 0,
      ),
      addresses: AddressView(
        receiveAddresses: reload.receive?.addresses ?? previous.receiveAddresses,
        changeAddresses: reload.change?.addresses ?? previous.changeAddresses,
        receiveLoaded: (reload.receive?.addresses.isNotEmpty == true) || previous.receiveAddressesLoaded,
        changeLoaded: (reload.change?.addresses.isNotEmpty == true) || previous.changeAddressesLoaded,
        selectedKeychain: previous.selectedAddressKeychain,
      ),
      coins: CoinView(
        utxos: reload.coins?.utxos ?? previous.utxos,
        loaded: (reload.coins?.utxos.isNotEmpty == true) || previous.utxosLoaded,
      ),
      psbts: PsbtList(
        psbts: reload.psbts?.psbts ?? previous.psbts,
        analyses: reload.psbts?.analyses ?? previous.psbtAnalyses,
        loaded: previous.psbtsLoaded,
      ),
      descriptor: previous._descriptor,
      hotKeys: previous._hotKeys,
      fiat: previous._fiat,
      wallet: previous.wallet,
      selectedTab: previous.selectedTab,
      selectedAddressKeychain: previous.selectedAddressKeychain,
      isSyncing: false,
      errorMessage: null,
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

  /// Apply a [WalletDetailUpdate] to produce a new [WalletDetailLoaded].
  ///
  /// Non-null fields in [update] replace the corresponding current values.
  /// This is the programmatic alternative to [copyWith] and is useful when
  /// the set of fields to update is computed at runtime.
  WalletDetailLoaded apply(WalletDetailUpdate update) {
    return WalletDetailLoaded._(
      info: update.info ?? _info,
      txPage: update.txPage ?? _txPage,
      addresses: update.addresses ?? _addresses,
      coins: update.coins ?? _coins,
      descriptor: update.descriptor ?? _descriptor,
      psbts: update.psbts ?? _psbts,
      hotKeys: update.hotKeys ?? _hotKeys,
      fiat: update.fiat ?? _fiat,
      wallet: wallet,
      selectedTab: update.selectedTab ?? selectedTab,
      selectedAddressKeychain: update.selectedAddressKeychain ?? selectedAddressKeychain,
      isSyncing: update.isSyncing ?? isSyncing,
      errorMessage: identical(update.errorMessage, _kUndef)
          ? errorMessage
          : update.errorMessage as String?,
    );
  }
}
