import 'dart:async';

import 'package:flutter_bloc/flutter_bloc.dart';

import 'package:deadbolt/cubit/cubit_error_logger.dart';
import 'package:deadbolt/errors.dart';
import 'package:deadbolt/services/price_service.dart';
import 'package:deadbolt/services/wallet_service.dart';
import 'package:deadbolt/utils/hot_key_helpers.dart';
import 'package:deadbolt/src/rust/api/analyzer.dart' show analyzeDescriptor, APIAnalysisResult;
import 'package:deadbolt/src/rust/api/model.dart';
import 'package:deadbolt/src/rust/api/wallet.dart'
    show ApiWallet, getWalletNetworkHint;

// Re-export for the screen
export 'package:deadbolt/src/rust/api/analyzer.dart' show APIAnalysisResult;
export 'package:deadbolt/src/rust/api/model.dart'
    show APIUtxo, APIPsbtInfo, APIPsbtAnalysis, APIPsbtSignerStatus, APICoinControl,
        APIPolicyPath, APITxDetails, APIUtxoDetails, APIAddressDetails, APIRelatedUtxo,
        APIRelatedTx, APIRelatedAddress, APIRbfInfo, APIImportPsbtResult, APIHotKeyInfo;

// --- States ---

sealed class WalletDetailState {}

class WalletDetailInitial extends WalletDetailState {}

class WalletDetailLoading extends WalletDetailState {
  final String? message;
  WalletDetailLoading({this.message});
}

class WalletDetailLoaded extends WalletDetailState {
  final APIWalletInfo walletInfo;
  final APIBalance balance;
  final List<APITransaction> transactions;
  final int totalTransactions;
  final bool hasMore;
  final bool isSyncing;
  final int currentPage;
  final ApiWallet walletHandle;

  // Tab state: 0 = transactions, 1 = addresses, 2 = coins
  final int selectedTab;
  final int selectedAddressKeychain; // 0 = receive (External), 1 = change (Internal)
  final List<APIAddress> receiveAddresses;
  final List<APIAddress> changeAddresses;
  final bool receiveAddressesLoaded;
  final bool changeAddressesLoaded;

  // Coins tab state
  final List<APIUtxo> utxos;
  final bool utxosLoaded;

  // Current chain tip (0 = not yet synced)
  final int tipHeight;

  // Descriptor tab state (tab 3) — also used by coins tab
  final APIAnalysisResult? descriptorAnalysis;
  final Map<String, String> keyLabels;   // mfp -> label
  final Map<int, String> pathLabels;     // rustId -> label
  final bool descriptorLoaded;

  // PSBT / unsigned transactions
  final List<APIPsbtInfo> psbts;
  final Map<int, APIPsbtAnalysis> psbtAnalyses; // psbt.id -> analysis
  final bool psbtsLoaded;

  // Hot signing keys stored in this wallet
  final List<APIHotKeyInfo> hotKeys;

  // Fiat price data: txid -> BTC price in fiatCurrency at tx time (historical)
  final Map<String, double> fiatPrices;
  // Current BTC price for UTXO display (not stored in DB — always current)
  final double? currentBtcPrice;
  final String? fiatCurrency;

  // Transient error to show as toast (cleared after display)
  final String? errorMessage;

  WalletDetailLoaded({
    required this.walletInfo,
    required this.balance,
    required this.transactions,
    required this.totalTransactions,
    required this.hasMore,
    required this.walletHandle,
    this.isSyncing = false,
    this.currentPage = 0,
    this.selectedTab = 0,
    this.selectedAddressKeychain = 0,
    this.receiveAddresses = const [],
    this.changeAddresses = const [],
    this.receiveAddressesLoaded = false,
    this.changeAddressesLoaded = false,
    this.utxos = const [],
    this.utxosLoaded = false,
    this.tipHeight = 0,
    this.descriptorAnalysis,
    this.keyLabels = const {},
    this.pathLabels = const {},
    this.descriptorLoaded = false,
    this.psbts = const [],
    this.psbtAnalyses = const {},
    this.psbtsLoaded = false,
    this.hotKeys = const [],
    this.fiatPrices = const {},
    this.currentBtcPrice,
    this.fiatCurrency,
    this.errorMessage,
  });

  WalletDetailLoaded copyWith({
    APIWalletInfo? walletInfo,
    APIBalance? balance,
    List<APITransaction>? transactions,
    int? totalTransactions,
    bool? hasMore,
    bool? isSyncing,
    int? currentPage,
    ApiWallet? walletHandle,
    int? selectedTab,
    int? selectedAddressKeychain,
    List<APIAddress>? receiveAddresses,
    List<APIAddress>? changeAddresses,
    bool? receiveAddressesLoaded,
    bool? changeAddressesLoaded,
    List<APIUtxo>? utxos,
    bool? utxosLoaded,
    int? tipHeight,
    APIAnalysisResult? descriptorAnalysis,
    Map<String, String>? keyLabels,
    Map<int, String>? pathLabels,
    bool? descriptorLoaded,
    List<APIPsbtInfo>? psbts,
    Map<int, APIPsbtAnalysis>? psbtAnalyses,
    bool? psbtsLoaded,
    List<APIHotKeyInfo>? hotKeys,
    Map<String, double>? fiatPrices,
    Object? currentBtcPrice = _keep,
    Object? fiatCurrency = _keep,
    Object? errorMessage = _keep,
  }) {
    return WalletDetailLoaded(
      walletInfo: walletInfo ?? this.walletInfo,
      balance: balance ?? this.balance,
      transactions: transactions ?? this.transactions,
      totalTransactions: totalTransactions ?? this.totalTransactions,
      hasMore: hasMore ?? this.hasMore,
      isSyncing: isSyncing ?? this.isSyncing,
      currentPage: currentPage ?? this.currentPage,
      walletHandle: walletHandle ?? this.walletHandle,
      selectedTab: selectedTab ?? this.selectedTab,
      selectedAddressKeychain:
          selectedAddressKeychain ?? this.selectedAddressKeychain,
      receiveAddresses: receiveAddresses ?? this.receiveAddresses,
      changeAddresses: changeAddresses ?? this.changeAddresses,
      receiveAddressesLoaded:
          receiveAddressesLoaded ?? this.receiveAddressesLoaded,
      changeAddressesLoaded:
          changeAddressesLoaded ?? this.changeAddressesLoaded,
      utxos: utxos ?? this.utxos,
      utxosLoaded: utxosLoaded ?? this.utxosLoaded,
      tipHeight: tipHeight ?? this.tipHeight,
      descriptorAnalysis: descriptorAnalysis ?? this.descriptorAnalysis,
      keyLabels: keyLabels ?? this.keyLabels,
      pathLabels: pathLabels ?? this.pathLabels,
      descriptorLoaded: descriptorLoaded ?? this.descriptorLoaded,
      psbts: psbts ?? this.psbts,
      psbtAnalyses: psbtAnalyses ?? this.psbtAnalyses,
      psbtsLoaded: psbtsLoaded ?? this.psbtsLoaded,
      hotKeys: hotKeys ?? this.hotKeys,
      fiatPrices: fiatPrices ?? this.fiatPrices,
      currentBtcPrice: currentBtcPrice == _keep
          ? this.currentBtcPrice
          : currentBtcPrice as double?,
      fiatCurrency:
          fiatCurrency == _keep ? this.fiatCurrency : fiatCurrency as String?,
      errorMessage:
          errorMessage == _keep ? this.errorMessage : errorMessage as String?,
    );
  }

}

// Sentinel used by copyWith to distinguish "not provided" from explicit null.
const Object _keep = Object();

class WalletDetailNeedsPassword extends WalletDetailState {
  final String walletPath;
  /// True when the wallet uses XpubKey protection (prompts for xpub, not password).
  final bool isXpubKey;
  /// Network hint read from the meta sidecar (null when unavailable).
  final APINetwork? network;
  WalletDetailNeedsPassword(this.walletPath,
      {this.isXpubKey = false, this.network});
}

class WalletDetailError extends WalletDetailState {
  final String message;
  WalletDetailError(this.message);
}

// --- Cubit ---

class WalletDetailCubit extends Cubit<WalletDetailState> with CubitErrorLogger {
  final WalletService _service;
  static const _pageSize = 25;
  static const _revealCount = 20;
  static const _autoSyncInterval = Duration(minutes: 5);

  Timer? _syncTimer;
  Timer? _retryTimer;
  String? _electrumUrl;

  bool _fiatEnabled = false;
  String _fiatCurrency = 'usd';
  PriceService? _priceService;
  bool _isFetchingFiatPrices = false;
  // Set when a fetch is requested while one is already in progress; triggers a
  // re-fetch after the current one completes (e.g. currency changed mid-fetch).
  bool _needsFiatRefetch = false;

  WalletDetailCubit({WalletService? service})
      : _service = service ?? WalletService(),
        super(WalletDetailInitial());

  /// Starts a periodic 5-minute auto-sync timer. Only syncs immediately on
  /// open if the wallet has never synced or last sync was more than 1 hour ago.
  /// Safe to call multiple times (restarts the timer).
  void startAutoSync(String electrumUrl) {
    _electrumUrl = electrumUrl;
    _syncTimer?.cancel();
    // Store URL immediately so detail queries can use it before sync completes.
    if (state is WalletDetailLoaded) {
      (state as WalletDetailLoaded).walletHandle.setElectrumUrl(url: electrumUrl);
    }
    if (_syncNeededOnOpen()) sync(electrumUrl);
    _syncTimer = Timer.periodic(_autoSyncInterval, (_) => sync(electrumUrl));
  }

  bool _syncNeededOnOpen() {
    final s = state;
    if (s is! WalletDetailLoaded) return true;
    final ts = s.walletInfo.lastSyncedAt;
    if (ts == null) return true;
    final lastSynced = DateTime.fromMillisecondsSinceEpoch(ts * 1000);
    return DateTime.now().difference(lastSynced) > const Duration(hours: 1);
  }

  @override
  Future<void> close() {
    _syncTimer?.cancel();
    _retryTimer?.cancel();
    return super.close();
  }

  void clearError() {
    if (state is WalletDetailLoaded) {
      emit((state as WalletDetailLoaded).copyWith(errorMessage: null));
    }
  }

  void _emitError(String tag, Object e, StackTrace st) {
    logError(tag, e, st);
    if (state is WalletDetailLoaded) {
      emit((state as WalletDetailLoaded).copyWith(errorMessage: formatRustError(e)));
    }
  }

  /// Evict the cached password so the wallet will require re-authentication
  /// on next open. The caller is responsible for navigating away.
  void lockWallet() {
    final current = state;
    if (current is! WalletDetailLoaded) return;
    _service.evictPassword(current.walletInfo.walletPath);
  }

  Future<void> load(
    String walletPath, {
    String? password,
    String? openingMessage,
    String? loadingDataMessage,
  }) async {
    emit(WalletDetailLoading(message: openingMessage));
    try {
      if (password != null) _service.cachePassword(walletPath, password);
      // If no password is available (provided or cached), check upfront whether
      // one is required — avoids brittle string matching on the Rust error.
      final effectivePassword =
          password ?? _service.getCachedPassword(walletPath);
      if (effectivePassword == null) {
        // Check both flags in parallel — each reads the .meta sidecar once.
        final (needsPassword, isXpubKey) = await (
          _service.walletRequiresPassword(walletPath),
          _service.walletRequiresXpub(walletPath),
        ).wait;
        if (needsPassword) {
          APINetwork? network;
          if (isXpubKey) {
            final hint = await getWalletNetworkHint(walletPath: walletPath);
            network = hint != null ? APINetwork.values.where((n) => n.name == hint).firstOrNull : null;
          }
          emit(WalletDetailNeedsPassword(walletPath,
              isXpubKey: isXpubKey, network: network));
          return;
        }
      }
      final handle = await _service.openWallet(walletPath, password: effectivePassword);
      if (loadingDataMessage != null) emit(WalletDetailLoading(message: loadingDataMessage));
      // Load all local data in parallel before sync starts — avoids the BDK
      // mutex contention that would block address/UTXO reads during sync.
      final (walletInfo, balance, page, tipHeight, receiveAddrs, changeAddrs, utxos) = await (
        handle.getInfo(),
        handle.getBalance(),
        handle.getTransactions(page: 0, pageSize: _pageSize),
        handle.getTipHeight(),
        handle.getAddresses(keychain: APIKeychain.external_),
        handle.getAddresses(keychain: APIKeychain.internal),
        handle.getUtxos(),
      ).wait;

      // Load PSBTs eagerly
      List<APIPsbtInfo> psbts = [];
      Map<int, APIPsbtAnalysis> psbtAnalyses = {};
      try {
        psbts = await handle.listPsbts();
        psbtAnalyses = await _analyzePsbts(handle, psbts);
      } catch (e, st) {
        logError('WalletDetailCubit.load() PSBTs', e, st);
      }

      // Load hot keys
      List<APIHotKeyInfo> hotKeys = [];
      try {
        hotKeys = handle.listHotKeys();
      } catch (e, st) {
        logError('WalletDetailCubit.load() hotKeys', e, st);
      }

      emit(WalletDetailLoaded(
        walletHandle: handle,
        walletInfo: walletInfo,
        balance: balance,
        transactions: page.transactions,
        totalTransactions: page.totalCount,
        hasMore: page.hasMore,
        currentPage: 0,
        tipHeight: tipHeight,
        receiveAddresses: receiveAddrs,
        changeAddresses: changeAddrs,
        receiveAddressesLoaded: true,
        changeAddressesLoaded: true,
        utxos: utxos,
        utxosLoaded: true,
        psbts: psbts,
        psbtAnalyses: psbtAnalyses,
        psbtsLoaded: true,
        hotKeys: hotKeys,
      ));
      // Eagerly load descriptor analysis so PSBT navigation works from the
      // Transactions tab without needing to visit the Descriptor tab first.
      unawaited(_loadDescriptorAnalysis());
    } catch (e, stackTrace) {
      logError('WalletDetailCubit.load()', e, stackTrace);
      // Evict any cached credential so the prompt re-appears on next open
      // instead of failing silently with a cached bad credential.
      _service.evictPassword(walletPath);
      emit(WalletDetailError(formatRustError(e)));
    }
  }

  Future<void> sync(String electrumUrl) async {
    final current = state;
    if (current is! WalletDetailLoaded) return;

    emit(current.copyWith(isSyncing: true));
    try {
      final handle = current.walletHandle;

      await handle.sync_(electrumUrl: electrumUrl);

      final (walletInfo, balance, page, tipHeight) = await (
        handle.getInfo(),
        handle.getBalance(),
        handle.getTransactions(page: 0, pageSize: _pageSize),
        handle.getTipHeight(),
      ).wait;

      // Reload addresses/UTXOs too if they were already loaded (sync may reveal new ones)
      final receiveAddrs = current.receiveAddressesLoaded
          ? await handle.getAddresses(keychain: APIKeychain.external_)
          : null;
      final changeAddrs = current.changeAddressesLoaded
          ? await handle.getAddresses(keychain: APIKeychain.internal)
          : null;
      final utxos = current.utxosLoaded ? await handle.getUtxos() : null;

      // Reload PSBTs so utxoMaxConfHeight is recomputed from the updated chain state.
      List<APIPsbtInfo> psbts = current.psbts;
      Map<int, APIPsbtAnalysis> psbtAnalyses = current.psbtAnalyses;
      if (current.psbtsLoaded) {
        try {
          psbts = await handle.listPsbts();
          psbtAnalyses = await _analyzePsbts(handle, psbts);
        } catch (e, st) {
          logError('WalletDetailCubit.sync() PSBTs', e, st);
        }
      }

      // Read descriptor fields from the state at emit time, not from `current`
      // captured at sync start — _loadDescriptorAnalysis() may have finished
      // concurrently and we must not overwrite its result.
      final atEmit = state is WalletDetailLoaded ? state as WalletDetailLoaded : current;

      emit(WalletDetailLoaded(
        walletHandle: handle,
        walletInfo: walletInfo,
        balance: balance,
        transactions: page.transactions,
        totalTransactions: page.totalCount,
        hasMore: page.hasMore,
        isSyncing: false,
        currentPage: 0,
        tipHeight: tipHeight,
        selectedTab: atEmit.selectedTab,
        selectedAddressKeychain: atEmit.selectedAddressKeychain,
        receiveAddresses: receiveAddrs ?? atEmit.receiveAddresses,
        changeAddresses: changeAddrs ?? atEmit.changeAddresses,
        receiveAddressesLoaded: receiveAddrs != null || atEmit.receiveAddressesLoaded,
        changeAddressesLoaded: changeAddrs != null || atEmit.changeAddressesLoaded,
        utxos: utxos ?? atEmit.utxos,
        utxosLoaded: utxos != null || atEmit.utxosLoaded,
        descriptorAnalysis: atEmit.descriptorAnalysis,
        keyLabels: atEmit.keyLabels,
        pathLabels: atEmit.pathLabels,
        descriptorLoaded: atEmit.descriptorLoaded,
        psbts: psbts,
        psbtAnalyses: psbtAnalyses,
        psbtsLoaded: current.psbtsLoaded,
        hotKeys: atEmit.hotKeys,
        fiatPrices: atEmit.fiatPrices,
        fiatCurrency: atEmit.fiatCurrency,
      ));
      unawaited(_fetchMissingFiatPrices());
    } catch (e, stackTrace) {
      if (e.toString().contains('No such mempool or blockchain transaction')) {
        // Race condition: tx was just broadcast but the Electrum server hasn't
        // seen it yet. Silently schedule a retry in 15 seconds.
        if (state is WalletDetailLoaded) {
          emit((state as WalletDetailLoaded).copyWith(isSyncing: false));
        }
        _retryTimer?.cancel();
        _retryTimer = Timer(
          const Duration(seconds: 15),
          () => sync(electrumUrl),
        );
        return;
      }
      logError('WalletDetailCubit.sync()', e, stackTrace);
      if (state is WalletDetailLoaded) {
        emit((state as WalletDetailLoaded).copyWith(
          isSyncing: false,
          errorMessage: formatRustError(e),
        ));
      }
    }
  }

  Future<void> setTxLabel(String txid, String label) async {
    final current = state;
    if (current is! WalletDetailLoaded) return;
    current.walletHandle.setTxLabel(txid: txid, label: label);
    await _refreshAllAfterLabelChange();
  }

  Future<void> rescan(String electrumUrl) async {
    final current = state;
    if (current is! WalletDetailLoaded) return;

    emit(current.copyWith(isSyncing: true));
    try {
      final handle = current.walletHandle;

      await handle.rescan(electrumUrl: electrumUrl);

      final walletInfo = await handle.getInfo();
      final balance = await handle.getBalance();
      final page = await handle.getTransactions(page: 0, pageSize: _pageSize);

      final atEmit = state is WalletDetailLoaded ? state as WalletDetailLoaded : current;
      emit(WalletDetailLoaded(
        walletHandle: handle,
        walletInfo: walletInfo,
        balance: balance,
        transactions: page.transactions,
        totalTransactions: page.totalCount,
        hasMore: page.hasMore,
        isSyncing: false,
        currentPage: 0,
        selectedTab: atEmit.selectedTab,
        selectedAddressKeychain: atEmit.selectedAddressKeychain,
        // Reset addresses/coins — rescan may reveal new ones
        receiveAddressesLoaded: false,
        changeAddressesLoaded: false,
        utxosLoaded: false,
        hotKeys: atEmit.hotKeys,
      ));
    } catch (e, stackTrace) {
      logError('WalletDetailCubit.rescan()', e, stackTrace);
      if (state is WalletDetailLoaded) {
        emit((state as WalletDetailLoaded).copyWith(
          isSyncing: false,
          errorMessage: formatRustError(e),
        ));
      }
    }
  }

  Future<void> loadMoreTransactions() async {
    final current = state;
    if (current is! WalletDetailLoaded || !current.hasMore) return;

    try {
      final nextPage = current.currentPage + 1;
      final page = await current.walletHandle.getTransactions(
        page: nextPage,
        pageSize: _pageSize,
      );

      emit(current.copyWith(
        transactions: [...current.transactions, ...page.transactions],
        totalTransactions: page.totalCount,
        hasMore: page.hasMore,
        currentPage: nextPage,
      ));
    } catch (e, stackTrace) {
      _emitError('WalletDetailCubit.loadMoreTransactions()', e, stackTrace);
    }
  }

  /// Switch the bottom navigation tab. Lazily loads addresses/coins on first visit.
  void selectTab(int tab) {
    final current = state;
    if (current is! WalletDetailLoaded) return;
    if (current.selectedTab == tab) return;

    final updated = current.copyWith(selectedTab: tab);
    emit(updated);

    // Tab 0 = Overview, 1 = Transactions, 2 = Addresses, 3 = Coins, 4 = Descriptor
    if (tab == 2) {
      if (!current.receiveAddressesLoaded) {
        unawaited(_loadAddresses(APIKeychain.external_));
      }
      if (!current.changeAddressesLoaded) {
        unawaited(_loadAddresses(APIKeychain.internal));
      }
    } else if (tab == 3) {
      if (!current.utxosLoaded) {
        unawaited(_loadUtxos());
      }
      if (!current.descriptorLoaded) {
        unawaited(_loadDescriptorAnalysis());
      }
    } else if (tab == 4) {
      if (!current.descriptorLoaded) {
        unawaited(_loadDescriptorAnalysis());
      }
    }
  }

  /// Switch the receive/change sub-tab inside the addresses view.
  void selectAddressKeychain(int keychain) {
    final current = state;
    if (current is! WalletDetailLoaded) return;
    emit(current.copyWith(selectedAddressKeychain: keychain));
  }

  /// Ensures at least the receive (external) addresses are loaded.
  /// If no addresses have been revealed yet (fresh wallet), reveals some first
  /// and triggers a background sync to confirm they are unused on-chain.
  /// Used by the overview tab Receive button.
  Future<void> ensureReceiveAddressLoaded() async {
    final current = state;
    if (current is! WalletDetailLoaded) return;
    if (!current.receiveAddressesLoaded) {
      await _loadAddresses(APIKeychain.external_);
    }
    final afterLoad = state;
    if (afterLoad is! WalletDetailLoaded) return;
    if (afterLoad.receiveAddresses.isEmpty) {
      // Fresh wallet — no addresses revealed yet. Reveal a first batch and
      // kick off a background sync so we can confirm they are unused on-chain.
      await revealMoreAddresses(APIKeychain.external_);
      if (_electrumUrl != null) {
        // Fire-and-forget: don't block the receive dialog on network I/O.
        unawaited(sync(_electrumUrl!));
      }
    }
  }

  Future<void> _loadAddresses(APIKeychain keychain) async {
    final current = state;
    if (current is! WalletDetailLoaded) return;
    try {
      final addrs = await current.walletHandle.getAddresses(keychain: keychain);
      if (state is! WalletDetailLoaded) return;
      if (keychain == APIKeychain.external_) {
        emit((state as WalletDetailLoaded).copyWith(
          receiveAddresses: addrs,
          receiveAddressesLoaded: true,
        ));
      } else {
        emit((state as WalletDetailLoaded).copyWith(
          changeAddresses: addrs,
          changeAddressesLoaded: true,
        ));
      }
    } catch (e, stackTrace) {
      _emitError('WalletDetailCubit._loadAddresses()', e, stackTrace);
    }
  }

  Future<void> _loadUtxos() async {
    final current = state;
    if (current is! WalletDetailLoaded) return;
    try {
      final utxos = await current.walletHandle.getUtxos();
      if (state is! WalletDetailLoaded) return;
      emit((state as WalletDetailLoaded).copyWith(utxos: utxos, utxosLoaded: true));
    } catch (e, stackTrace) {
      _emitError('WalletDetailCubit._loadUtxos()', e, stackTrace);
    }
  }

  /// Reveal 20 more addresses beyond those already derived, then refresh the list.
  Future<void> revealMoreAddresses(APIKeychain keychain) async {
    final current = state;
    if (current is! WalletDetailLoaded) return;
    try {
      current.walletHandle.revealMoreAddresses(
        keychain: keychain,
        count: _revealCount,
      );
      // Reload full list after revealing
      await _loadAddresses(keychain);
    } catch (e, stackTrace) {
      _emitError('WalletDetailCubit.revealMoreAddresses()', e, stackTrace);
    }
  }

  Future<void> setAddressLabel(String address, String label, APIKeychain keychain) async {
    final current = state;
    if (current is! WalletDetailLoaded) return;
    current.walletHandle.setAddressLabel(address: address, label: label);
    await _refreshAllAfterLabelChange();
  }

  Future<void> setCoinLabel(String txid, int vout, String label) async {
    final current = state;
    if (current is! WalletDetailLoaded) return;
    current.walletHandle.setCoinLabel(txid: txid, vout: vout, label: label);
    await _refreshAllAfterLabelChange();
  }

  /// After any label change, refresh all loaded entity lists so that propagated
  /// (inherited) labels are reflected across all tabs immediately.
  Future<void> _refreshAllAfterLabelChange() async {
    final current = state;
    if (current is! WalletDetailLoaded) return;

    // Start address and UTXO reloads fire-and-forget (only if already loaded).
    if (current.receiveAddressesLoaded) unawaited(_loadAddresses(APIKeychain.external_));
    if (current.changeAddressesLoaded) unawaited(_loadAddresses(APIKeychain.internal));
    if (current.utxosLoaded) unawaited(_loadUtxos());

    // Reload transactions (page-aware, awaited so the tx tab is in sync).
    final page = await current.walletHandle.getTransactions(
      page: 0,
      pageSize: _pageSize * (current.currentPage + 1),
    );
    if (state is! WalletDetailLoaded) return;
    emit((state as WalletDetailLoaded).copyWith(
      transactions: page.transactions,
      totalTransactions: page.totalCount,
      hasMore: page.hasMore,
    ));
  }

  Future<void> _loadDescriptorAnalysis() async {
    final current = state;
    if (current is! WalletDetailLoaded) return;
    try {
      final descriptor = current.walletInfo.descriptor;
      final analysis = await analyzeDescriptor(descriptor: descriptor);
      final rawKeyLabels = await current.walletHandle.getKeyLabels();
      final rawPathLabels = await current.walletHandle.getPathLabels();
      final keyLabels = {
        for (final e in rawKeyLabels) e.mfp: e.label,
      };
      final pathLabels = {
        for (final e in rawPathLabels) e.rustId: e.label,
      };
      if (state is! WalletDetailLoaded) return;
      emit((state as WalletDetailLoaded).copyWith(
        descriptorAnalysis: analysis,
        keyLabels: keyLabels,
        pathLabels: pathLabels,
        descriptorLoaded: true,
      ));
    } catch (e, stackTrace) {
      logError('WalletDetailCubit._loadDescriptorAnalysis()', e, stackTrace);
    }
  }

  /// Analyze all [psbts] in parallel, returning a map of id → analysis.
  /// Per-PSBT errors are swallowed so a single bad PSBT doesn't block the rest.
  Future<Map<int, APIPsbtAnalysis>> _analyzePsbts(
    ApiWallet handle,
    List<APIPsbtInfo> psbts,
  ) async {
    final entries = await Future.wait(
      psbts.map((psbt) async {
        try {
          final analysis = await handle.analyzePsbt(
            psbtBase64: psbt.psbtBase64,
            mfps: psbt.mfps,
          );
          return MapEntry(psbt.id.toInt(), analysis);
        } catch (_) {
          return null;
        }
      }),
    );
    return Map.fromEntries(entries.whereType<MapEntry<int, APIPsbtAnalysis>>());
  }

  void setWalletKeyLabel(String mfp, String label) {
    final current = state;
    if (current is! WalletDetailLoaded) return;
    current.walletHandle.setKeyLabel(mfp: mfp, label: label);
    final updated = Map<String, String>.from(current.keyLabels);
    if (label.isEmpty) {
      updated.remove(mfp);
    } else {
      updated[mfp] = label;
    }
    emit(current.copyWith(keyLabels: updated));
  }

  void setWalletPathLabel(int rustId, String label) {
    final current = state;
    if (current is! WalletDetailLoaded) return;
    current.walletHandle.setPathLabel(rustId: rustId, label: label);
    final updated = Map<int, String>.from(current.pathLabels);
    if (label.isEmpty) {
      updated.remove(rustId);
    } else {
      updated[rustId] = label;
    }
    emit(current.copyWith(pathLabels: updated));
  }

  Future<String?> exportBip329Labels() async {
    final current = state;
    if (current is! WalletDetailLoaded) return null;
    try {
      final lines = current.walletHandle.exportBip329();
      return lines.join('\n');
    } catch (e, st) {
      _emitError('exportBip329Labels', e, st);
      return null;
    }
  }

  Future<bool> importBip329Labels(String content) async {
    final current = state;
    if (current is! WalletDetailLoaded) return false;
    try {
      final lines = content
          .split('\n')
          .map((l) => l.trim())
          .where((l) => l.isNotEmpty)
          .toList();
      current.walletHandle.importBip329(lines: lines);
      await _refreshAllAfterLabelChange();
      return true;
    } catch (e, st) {
      _emitError('importBip329Labels', e, st);
      return false;
    }
  }

  // ─── Coin loading ─────────────────────────────────────────────────────────

  /// Ensures UTXOs are loaded without switching tabs.
  /// No-op if already loaded.
  Future<void> ensureCoinsLoaded() async {
    final current = state;
    if (current is! WalletDetailLoaded) return;
    if (!current.utxosLoaded) await _loadUtxos();
    if (!current.descriptorLoaded) await _loadDescriptorAnalysis();
  }

  /// Force-reload coins if they were already loaded (so pending PSBT
  /// annotations stay in sync after PSBT lifecycle changes).
  Future<void> _reloadCoinsIfLoaded() async {
    final s = state;
    if (s is! WalletDetailLoaded || !s.utxosLoaded) return;
    emit(s.copyWith(utxosLoaded: false));
    await _loadUtxos();
  }


  /// Returns RBF constraints for the given mempool spending txid, or null on failure.
  Future<APIRbfInfo?> getRbfInfo(String spendingTxid) async {
    final current = state;
    if (current is! WalletDetailLoaded) return null;
    try {
      return await current.walletHandle.getRbfInfo(spendingTxid: spendingTxid);
    } catch (_) {
      return null;
    }
  }

  /// Returns fee info for the full unconfirmed ancestor package. Null on failure.
  Future<APICpfpInfo?> getCpfpInfo(List<String> parentTxids) async {
    final current = state;
    if (current is! WalletDetailLoaded) return null;
    try {
      return await current.walletHandle.getCpfpInfo(parentTxids: parentTxids);
    } catch (_) {
      return null;
    }
  }

  /// Returns the next unused external (receive) address that is not already
  /// reserved as the recipient of a pending unsigned PSBT.
  ///
  /// Mempool/unconfirmed transactions are already reflected in [APIAddress.isUsed]
  /// via BDK's sync. Unsigned PSBTs are checked explicitly via [psbts].
  /// If no unused address is found among revealed ones, new ones are revealed
  /// and the search retries once.
  Future<String?> getNextSelfPaymentAddress({Set<String> alreadyUsed = const {}}) async {
    final current = state;
    if (current is! WalletDetailLoaded) return null;
    try {
      final psbtRecipients = current.psbts.map((p) => p.recipient).toSet();
      final addr = await _nextUnusedAddress(
        current.walletHandle,
        exclude: psbtRecipients.union(alreadyUsed),
      );
      return addr?.address;
    } catch (_) {
      return null;
    }
  }

  /// Returns the next unused external address for any wallet by path.
  /// Used when the user picks a different wallet as the send destination.
  /// Unlike [getNextSelfPaymentAddress], does not filter by pending PSBTs —
  /// that wallet's PSBTs are managed separately.
  Future<String?> getNextReceiveAddressFor(String walletPath, {Set<String> alreadyUsed = const {}}) async {
    try {
      final handle = await _service.openWallet(walletPath);
      final addr = await _nextUnusedAddress(handle, exclude: alreadyUsed);
      return addr?.address;
    } catch (_) {
      return null;
    }
  }

  Future<APIAddress?> getNextReceiveAddress() async {
    final current = state;
    if (current is! WalletDetailLoaded) return null;
    try {
      final psbtRecipients = current.psbts.map((p) => p.recipient).toSet();
      return await _nextUnusedAddress(
        current.walletHandle,
        exclude: psbtRecipients,
      );
    } catch (_) {
      return null;
    }
  }

  /// Finds the first unused external address on [handle], skipping any in
  /// [exclude]. Reveals more addresses and retries once if all are used.
  Future<APIAddress?> _nextUnusedAddress(
    ApiWallet handle, {
    Set<String> exclude = const {},
  }) async {
    APIAddress? firstAvailable(List<APIAddress> addrs) {
      for (final addr in addrs) {
        if (!addr.isUsed &&
            !exclude.contains(addr.address) &&
            (addr.label == null || addr.label!.isEmpty)) {
          return addr;
        }
      }
      return null;
    }

    var addrs = await handle.getAddresses(keychain: APIKeychain.external_);
    final found = firstAvailable(addrs);
    if (found != null) return found;

    // All revealed addresses are used — reveal more and retry once.
    handle.revealMoreAddresses(keychain: APIKeychain.external_, count: _revealCount);
    addrs = await handle.getAddresses(keychain: APIKeychain.external_);
    return firstAvailable(addrs);
  }

  // ─── PSBTs ────────────────────────────────────────────────────────────────

  Future<void> loadPsbts() async {
    final current = state;
    if (current is! WalletDetailLoaded) return;
    try {
      final psbts = await current.walletHandle.listPsbts();
      final analyses = await _analyzePsbts(current.walletHandle, psbts);
      if (state is! WalletDetailLoaded) return;
      emit((state as WalletDetailLoaded).copyWith(
        psbts: psbts,
        psbtAnalyses: analyses,
        psbtsLoaded: true,
      ));
    } catch (e, st) {
      logError('WalletDetailCubit.loadPsbts()', e, st);
    }
  }

  /// Create a PSBT and save it. Returns the new [APIPsbtInfo] or null on error.
  Future<APIPsbtInfo?> createPsbt({
    required List<APIRecipient> recipients,
    int? maxRecipientIndex,
    required double feeRateSatPerVb,
    required List<APICoinControl> selectedUtxos,
    required List<APIPolicyPath> policyPath,
    required int spendPathId,
    required int threshold,
    required List<String> mfps,
    String? label,
  }) async {
    final current = state;
    if (current is! WalletDetailLoaded) return null;
    try {
      APIPsbtInfo psbt = current.walletHandle.createPsbt(
        recipients: recipients,
        maxRecipientIndex: maxRecipientIndex,
        feeRateSatPerVb: feeRateSatPerVb,
        selectedUtxos: selectedUtxos,
        policyPath: policyPath,
        spendPathId: spendPathId,
        threshold: threshold,
        mfps: mfps,
      );
      // Apply label synchronously before loadPsbts() dispatches to thread pool,
      // to avoid a race where listPsbts() reads the DB before the label is written.
      if (label != null && label.isNotEmpty) {
        psbt = setPsbtLabel(psbt.id.toInt(), label) ?? psbt;
      }
      unawaited(loadPsbts().then((_) => _reloadCoinsIfLoaded()));
      return psbt;
    } catch (e, st) {
      logError('WalletDetailCubit.createPsbt()', e, st);
      rethrow;
    }
  }

  /// Create, sign (with the single hot key), and broadcast in one step.
  /// Only valid for single-sig wallets where [mfps] has exactly one entry that
  /// matches an available hot key. Returns the txid; throws on any failure.
  Future<String> directSend({
    required List<APIRecipient> recipients,
    int? maxRecipientIndex,
    required double feeRateSatPerVb,
    required List<APICoinControl> selectedUtxos,
    required List<APIPolicyPath> policyPath,
    required int spendPathId,
    required int threshold,
    required List<String> mfps,
    String? label,
    required String electrumUrl,
  }) async {
    final current = state;
    if (current is! WalletDetailLoaded) throw StateError('Wallet not loaded');
    final psbt = await createPsbt(
      recipients: recipients,
      maxRecipientIndex: maxRecipientIndex,
      feeRateSatPerVb: feeRateSatPerVb,
      selectedUtxos: selectedUtxos,
      policyPath: policyPath,
      spendPathId: spendPathId,
      threshold: threshold,
      mfps: mfps,
      label: label,
    );
    if (psbt == null) throw StateError('Failed to create transaction');
    try {
      current.walletHandle.signPsbtWithKey(psbtId: psbt.id.toInt(), mfp: mfps.first);
    } catch (e, st) {
      logError('WalletDetailCubit.directSend() sign', e, st);
      rethrow;
    }
    return broadcastPsbt(psbt.id.toInt(), electrumUrl);
  }

  void deletePsbt(int id) {
    final current = state;
    if (current is! WalletDetailLoaded) return;
    try {
      current.walletHandle.deletePsbt(id: id);
      final updatedPsbts = current.psbts.where((p) => p.id.toInt() != id).toList();
      final updatedAnalyses = Map<int, APIPsbtAnalysis>.from(current.psbtAnalyses)
        ..remove(id);
      emit(current.copyWith(psbts: updatedPsbts, psbtAnalyses: updatedAnalyses));
      unawaited(_reloadCoinsIfLoaded());
    } catch (e, st) {
      logError('WalletDetailCubit.deletePsbt()', e, st);
    }
  }

  /// Set or clear the label for a PSBT. Pass empty string to clear.
  /// Returns the updated [APIPsbtInfo] or null on error.
  APIPsbtInfo? setPsbtLabel(int id, String label) {
    final current = state;
    if (current is! WalletDetailLoaded) return null;
    try {
      final updated = current.walletHandle.setPsbtLabel(id: id, label: label);
      final updatedPsbts = current.psbts
          .map((p) => p.id.toInt() == id ? updated : p)
          .toList();
      emit(current.copyWith(psbts: updatedPsbts));
      return updated;
    } catch (e, st) {
      logError('WalletDetailCubit.setPsbtLabel()', e, st);
      return null;
    }
  }

  /// Import a PSBT from an external base64 string.
  /// If a record with the same txid already exists, signatures are merged.
  /// Returns the result (with `wasMerged` flag) or null if wallet not loaded.
  Future<APIImportPsbtResult?> importPsbt(String psbtBase64) async {
    final current = state;
    if (current is! WalletDetailLoaded) return null;
    try {
      final result = await current.walletHandle.importPsbt(psbtBase64: psbtBase64);
      final psbt = result.psbt;
      final id = psbt.id.toInt();

      APIPsbtAnalysis? analysis;
      try {
        analysis = await current.walletHandle
            .analyzePsbt(psbtBase64: psbt.psbtBase64, mfps: psbt.mfps);
      } catch (e, st) {
        logError('WalletDetailCubit.importPsbt() analyze', e, st);
      }

      List<APIPsbtInfo> updatedPsbts;
      if (result.wasMerged) {
        updatedPsbts = current.psbts.map((p) => p.id.toInt() == id ? psbt : p).toList();
      } else {
        updatedPsbts = [psbt, ...current.psbts];
      }

      final updatedAnalyses = Map<int, APIPsbtAnalysis>.from(current.psbtAnalyses);
      if (analysis != null) updatedAnalyses[id] = analysis;

      emit(current.copyWith(psbts: updatedPsbts, psbtAnalyses: updatedAnalyses));
      return result;
    } catch (e, st) {
      logError('WalletDetailCubit.importPsbt()', e, st);
      rethrow;
    }
  }

  /// Merge signed PSBT into stored one and refresh analysis.
  Future<APIPsbtInfo?> mergePsbt(int id, String signedPsbtBase64) async {
    final current = state;
    if (current is! WalletDetailLoaded) return null;
    try {
      final updated = current.walletHandle.mergePsbt(
        id: id,
        signedPsbtBase64: signedPsbtBase64,
      );
      // Re-analyze
      APIPsbtAnalysis? analysis;
      try {
        analysis = await current.walletHandle
            .analyzePsbt(psbtBase64: updated.psbtBase64, mfps: updated.mfps);
      } catch (e, st) {
        logError('WalletDetailCubit.mergePsbt() analyze', e, st);
      }

      final updatedPsbts = current.psbts
          .map((p) => p.id.toInt() == id ? updated : p)
          .toList();
      final updatedAnalyses = Map<int, APIPsbtAnalysis>.from(current.psbtAnalyses);
      if (analysis != null) updatedAnalyses[id] = analysis;

      emit(current.copyWith(psbts: updatedPsbts, psbtAnalyses: updatedAnalyses));
      return updated;
    } catch (e, st) {
      logError('WalletDetailCubit.mergePsbt()', e, st);
      rethrow;
    }
  }

  Future<String> broadcastPsbt(int id, String electrumUrl) async {
    final current = state;
    if (current is! WalletDetailLoaded) {
      throw StateError('Wallet not loaded');
    }
    final txid = await current.walletHandle.broadcastPsbt(
      id: id,
      electrumUrl: electrumUrl,
    );
    // Remove from local list and trigger a tx refresh
    final updatedPsbts = current.psbts.where((p) => p.id.toInt() != id).toList();
    final updatedAnalyses = Map<int, APIPsbtAnalysis>.from(current.psbtAnalyses)
      ..remove(id);
    final page = await current.walletHandle.getTransactions(page: 0, pageSize: _pageSize);
    emit(current.copyWith(
      psbts: updatedPsbts,
      psbtAnalyses: updatedAnalyses,
      transactions: page.transactions,
      totalTransactions: page.totalCount,
      hasMore: page.hasMore,
      currentPage: 0,
    ));
    // Sync immediately after broadcast — sync reloads UTXOs when utxosLoaded
    // is true, so coins will reflect the mempool spending status correctly.
    final url = _electrumUrl ?? electrumUrl;
    unawaited(sync(url));
    return txid;
  }

  // ─── Hot key management ────────────────────────────────────────────────────

  /// Import a mnemonic as a signing key. Returns the new [APIHotKeyInfo] or null on error.
  Future<APIHotKeyInfo?> addMnemonicKey(String mnemonic, String? passphrase) async {
    final current = state;
    if (current is! WalletDetailLoaded) return null;
    try {
      final info = current.walletHandle.addMnemonicKey(
        mnemonic: mnemonic,
        passphrase: passphrase,
      );
      emit(current.copyWith(hotKeys: upsertHotKey(current.hotKeys, info)));
      return info;
    } catch (e, st) {
      _emitError('WalletDetailCubit.addMnemonicKey()', e, st);
      return null;
    }
  }

  /// Import a master xprv as a signing key. Returns the new [APIHotKeyInfo] or null on error.
  Future<APIHotKeyInfo?> addXprvKey(String xprv) async {
    final current = state;
    if (current is! WalletDetailLoaded) return null;
    try {
      final info = current.walletHandle.addXprvKey(xprv: xprv);
      emit(current.copyWith(hotKeys: upsertHotKey(current.hotKeys, info)));
      return info;
    } catch (e, st) {
      _emitError('WalletDetailCubit.addXprvKey()', e, st);
      return null;
    }
  }

  /// Remove a hot signing key by MFP.
  Future<void> deleteHotKey(String mfp) async {
    final current = state;
    if (current is! WalletDetailLoaded) return;
    try {
      current.walletHandle.deleteHotKey(mfp: mfp);
      emit(current.copyWith(hotKeys: removeHotKey(current.hotKeys, mfp)));
    } catch (e, st) {
      _emitError('WalletDetailCubit.deleteHotKey()', e, st);
    }
  }

  /// Reveal the stored seed phrase or xprv for a hot signing key.
  Future<String?> revealHotKey(String mfp) async {
    final current = state;
    if (current is! WalletDetailLoaded) return null;
    try {
      return current.walletHandle.revealHotKey(mfp: mfp);
    } catch (e, st) {
      _emitError('WalletDetailCubit.revealHotKey()', e, st);
      return null;
    }
  }

  /// Sign a PSBT with the hot key identified by [mfp]. Returns the updated [APIPsbtInfo] or null on error.
  Future<APIPsbtInfo?> signPsbtWithKey(int psbtId, String mfp) async {
    final current = state;
    if (current is! WalletDetailLoaded) return null;
    try {
      final updated = current.walletHandle.signPsbtWithKey(psbtId: psbtId, mfp: mfp);
      // Re-analyze signatures
      APIPsbtAnalysis? analysis;
      try {
        analysis = await current.walletHandle
            .analyzePsbt(psbtBase64: updated.psbtBase64, mfps: updated.mfps);
      } catch (e, st) {
        logError('WalletDetailCubit.signPsbtWithKey() analyze', e, st);
      }

      // Re-read state to avoid overwriting concurrent updates (e.g. a sync
      // that completed while analyzePsbt was awaiting).
      final latest = state is WalletDetailLoaded ? state as WalletDetailLoaded : current;
      final updatedPsbts = latest.psbts
          .map((p) => p.id.toInt() == psbtId ? updated : p)
          .toList();
      final updatedAnalyses = Map<int, APIPsbtAnalysis>.from(latest.psbtAnalyses);
      if (analysis != null) updatedAnalyses[psbtId] = analysis;
      emit(latest.copyWith(psbts: updatedPsbts, psbtAnalyses: updatedAnalyses));
      return updated;
    } catch (e, st) {
      _emitError('WalletDetailCubit.signPsbtWithKey()', e, st);
      return null;
    }
  }

  // ---------------------------------------------------------------------------
  // Protection management
  // ---------------------------------------------------------------------------

  /// Change the wallet's encryption scheme without export/import.
  ///
  /// Re-encrypts the SQLCipher database with a fresh key for forward secrecy.
  /// Returns `true` on success; on failure emits an error toast and returns `false`.
  Future<bool> changeProtection({
    required APIProtectionType newProtectionType,
    String? newPassword,
    APISecurityLevel securityLevel = APISecurityLevel.standard,
  }) async {
    final current = state;
    if (current is! WalletDetailLoaded) return false;

    try {
      final keyHex = await _service.getOrCreateEncryptionKey();
      await current.walletHandle.changeProtection(
        deviceKeyHex: keyHex,
        newProtectionType: newProtectionType,
        newPassword: newPassword,
        securityLevel: securityLevel,
      );

      // Update credential cache.
      final walletPath = current.walletInfo.walletPath;
      switch (newProtectionType) {
        case APIProtectionType.deviceKey:
          _service.evictPassword(walletPath);
        case APIProtectionType.userPassword:
          if (newPassword != null) _service.cachePassword(walletPath, newPassword);
        case APIProtectionType.xpubKey:
          _service.evictPassword(walletPath);
      }

      // Update walletInfo in-place — no need to re-open the wallet (which
      // would require the new credential). The wallet handle stays open.
      final newProtection = APIWalletProtection(
        protectionType: newProtectionType,
        needsPassword: switch (newProtectionType) {
          APIProtectionType.deviceKey => false,
          APIProtectionType.userPassword => true,
          APIProtectionType.xpubKey => true,
        },
        securityLevel: securityLevel,
      );
      final updatedInfo = APIWalletInfo(
        walletPath: current.walletInfo.walletPath,
        name: current.walletInfo.name,
        descriptor: current.walletInfo.descriptor,
        network: current.walletInfo.network,
        createdAt: current.walletInfo.createdAt,
        lastSyncedAt: current.walletInfo.lastSyncedAt,
        protection: newProtection,
      );
      emit(current.copyWith(walletInfo: updatedInfo));
      return true;
    } catch (e, st) {
      _emitError('WalletDetailCubit.changeProtection()', e, st);
      return false;
    }
  }

  // -------------------------------------------------------------------------
  // Fiat price support
  // -------------------------------------------------------------------------

  /// Update fiat configuration and trigger a price fetch for missing transactions.
  Future<void> setFiatConfig(
    bool enabled,
    String currency,
    PriceProviderType provider,
  ) async {
    final sameConfig = enabled == _fiatEnabled &&
        currency == _fiatCurrency &&
        provider == (_priceService?.providerType ?? PriceProviderType.coinGecko);
    if (sameConfig) return;

    _fiatEnabled = enabled;
    _fiatCurrency = currency;

    final s = state;
    if (s is! WalletDetailLoaded) return;

    if (!enabled) {
      _priceService = null;
      emit(s.copyWith(
        fiatPrices: const {},
        currentBtcPrice: null,
        fiatCurrency: null,
      ));
      return;
    }

    if (_priceService == null || _priceService!.providerType != provider) {
      _priceService = PriceService(provider);
    }
    // Emit the new currency immediately so the UI reflects the change
    // before the async price fetch completes.
    emit(s.copyWith(fiatCurrency: currency));
    unawaited(_fetchMissingFiatPrices());
  }

  /// Fetch BTC prices for any transactions that don't have a stored fiat price,
  /// then update the state. Skips if a fetch is already in progress.
  Future<void> _fetchMissingFiatPrices() async {
    if (_isFetchingFiatPrices) {
      _needsFiatRefetch = true;
      return;
    }
    if (!_fiatEnabled || _priceService == null) return;
    final s = state;
    if (s is! WalletDetailLoaded) return;

    _isFetchingFiatPrices = true;
    try {
      final service = _priceService!;
      final currency = _fiatCurrency;
      final now = DateTime.now();

      // Current price, missing-tx query, and existing DB prices run in parallel.
      final (missing, currentBtcPrice, existingStored) = await (
        s.walletHandle.getTxidsMissingFiat(currency: currency),
        service.getBtcPrice(currency, now),
        s.walletHandle.getFiatPrices(currency: currency),
      ).wait;

      // Build base map from prices already stored in DB (previous sessions).
      final allPrices = {for (final p in existingStored) p.txid: p.btcPrice};

      if (missing.isNotEmpty) {
        // Group txids by day bucket so we make one API call per unique date.
        final Map<String, ({DateTime time, List<String> txids})> byBucket = {};
        for (final tx in missing) {
          final time = tx.confirmationTime != null
              ? DateTime.fromMillisecondsSinceEpoch(tx.confirmationTime! * 1000)
              : now;
          final utc = time.toUtc();
          final key = tx.confirmationTime != null
              ? '${utc.year}-${utc.month.toString().padLeft(2, '0')}-${utc.day.toString().padLeft(2, '0')}'
              : 'current';
          final bucket =
              byBucket.putIfAbsent(key, () => (time: time, txids: []));
          bucket.txids.add(tx.txid);
        }

        // Fetch all unique day buckets in parallel.
        // Reuse currentBtcPrice for the 'current' bucket (unconfirmed txs).
        final entries = byBucket.entries.toList();
        final prices = await Future.wait(
          entries.map((e) => e.key == 'current'
              ? Future.value(currentBtcPrice)
              : service.getBtcPrice(currency, e.value.time)),
        );

        // Store newly fetched prices in DB in parallel and merge into map.
        final storeFutures = <Future<void>>[];
        for (var i = 0; i < entries.length; i++) {
          final price = prices[i];
          if (price == null) continue;
          for (final txid in entries[i].value.txids) {
            allPrices[txid] = price;
            storeFutures.add(
              s.walletHandle.storeFiatPrice(
                txid: txid,
                currency: currency,
                btcPrice: price,
              ),
            );
          }
        }
        await Future.wait(storeFutures);
      }

      if (state is WalletDetailLoaded) {
        final current = state as WalletDetailLoaded;
        emit(current.copyWith(
          fiatPrices: allPrices,
          currentBtcPrice: currentBtcPrice,
          fiatCurrency: currency,
        ));
      }
    } catch (e, st) {
      _emitError('WalletDetailCubit._fetchMissingFiatPrices()', e, st);
    } finally {
      _isFetchingFiatPrices = false;
      if (_needsFiatRefetch) {
        _needsFiatRefetch = false;
        unawaited(_fetchMissingFiatPrices());
      }
    }
  }
}
