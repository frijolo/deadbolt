import 'dart:async';

import 'package:flutter_bloc/flutter_bloc.dart';

import 'package:deadbolt/cubit/cubit_error_logger.dart';
import 'package:deadbolt/errors.dart';
import 'package:biometric_storage/biometric_storage.dart';

import 'package:deadbolt/services/biometric_keystore_service.dart';
import 'package:deadbolt/services/price_service.dart';
import 'package:deadbolt/services/wallet_service.dart';
import 'package:deadbolt/services/wallet_sync_service.dart';
import 'package:deadbolt/utils/date_format.dart';
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

  // Whether this wallet has at least one biometric unlock slot registered.
  final bool hasBiometricSlot;

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
    this.hasBiometricSlot = false,
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
    bool? hasBiometricSlot,
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
      hasBiometricSlot: hasBiometricSlot ?? this.hasBiometricSlot,
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
  final WalletSyncService _syncService;
  final BiometricKeystoreService _keystoreService;
  static const _pageSize = 25;
  static const _revealCount = 20;
  static const tabOverview = 0;
  static const tabTransactions = 1;
  static const tabAddresses = 2;
  static const tabCoins = 3;
  static const tabDescriptor = 4;

  Timer? _retryTimer;
  StreamSubscription<WalletSyncEvent>? _syncEventSub;

  bool _fiatEnabled = false;
  String _fiatCurrency = 'usd';
  PriceService? _priceService;
  bool _isFetchingFiatPrices = false;
  // Set when a fetch is requested while one is already in progress; triggers a
  // re-fetch after the current one completes (e.g. currency changed mid-fetch).
  bool _needsFiatRefetch = false;

  WalletDetailCubit({
    WalletService? service,
    required WalletSyncService syncService,
    BiometricKeystoreService? biometricKeystoreService,
  })  : _service = service ?? WalletService(),
        _syncService = syncService,
        _keystoreService = biometricKeystoreService ?? BiometricKeystoreService(),
        super(WalletDetailInitial());

  @override
  void emit(WalletDetailState state) {
    if (!isClosed) super.emit(state);
  }

  // ─── Wallet session ──────────────────────────────────────────────────────

  /// Register the wallet handle with the global WalletSyncService and start
  /// listening to sync events for this wallet. Replaces startAutoSync.
  /// Called from _WalletDetailViewState._maybeStartAutoSync once the wallet loads.
  void registerWithSyncService(String electrumUrl) {
    final s = state;
    if (s is! WalletDetailLoaded) return;
    // Donate the handle to the service (replaces any handle from initFromList).
    // The service starts the subscription and emits an initial balance event.
    unawaited(
      _syncService.registerHandle(
        s.walletInfo.walletPath,
        s.walletHandle,
        electrumUrl,
      ),
    );

    // Listen to sync events for this specific wallet.
    _syncEventSub?.cancel();
    _syncEventSub = _syncService.events
        .where((e) => e.walletPath == s.walletInfo.walletPath)
        .listen(_onSyncEvent);
  }

  /// Handle a sync event from WalletSyncService.
  /// On completion: reloads transactions, addresses, UTXOs, PSBTs from the
  /// shared handle and updates the state. On error: emits an error toast.
  Future<void> _onSyncEvent(WalletSyncEvent event) async {
    final s = state;
    if (s is! WalletDetailLoaded) return;

    if (event.isSyncing) {
      emit(s.copyWith(isSyncing: true));
      return;
    }

    // Retry logic for broadcast race (tx not yet seen by Electrum server).
    if (event.error != null) {
      if (event.error!.contains('No such mempool or blockchain transaction')) {
        emit(s.copyWith(isSyncing: false));
        _retryTimer?.cancel();
        _retryTimer = Timer(const Duration(seconds: 15), sync);
        return;
      }
      emit(s.copyWith(isSyncing: false, errorMessage: event.error));
      return;
    }

    // Sync completed: reload all detail data from the (now-updated) handle.
    try {
      final handle = s.walletHandle;
      final (page, tipHeight) = await (
        handle.getTransactions(page: 0, pageSize: _pageSize),
        handle.getTipHeight(),
      ).wait;

      final receiveAddrs = s.receiveAddressesLoaded
          ? await handle.getAddresses(keychain: APIKeychain.external_)
          : null;
      final changeAddrs = s.changeAddressesLoaded
          ? await handle.getAddresses(keychain: APIKeychain.internal)
          : null;
      final utxos = s.utxosLoaded ? await handle.getUtxos() : null;

      List<APIPsbtInfo> psbts = s.psbts;
      Map<int, APIPsbtAnalysis> psbtAnalyses = s.psbtAnalyses;
      if (s.psbtsLoaded) {
        try {
          psbts = await handle.listPsbts();
          // Only re-analyze when count or content (id+psbtBase64) changed.
          // Skipping on identical lists avoids N FFI tasks on every Electrum ping.
          bool psbtListChanged() {
            if (psbts.length != s.psbts.length) return true;
            final cachedMap = {for (final p in s.psbts) p.id: p.psbtBase64};
            return psbts.any((p) => cachedMap[p.id] != p.psbtBase64);
          }

          if (psbtListChanged()) {
            psbtAnalyses = await _analyzePsbts(handle, psbts);
          }
        } catch (e, st) {
          logError('WalletDetailCubit._onSyncEvent() PSBTs', e, st);
        }
      }

      // Read latest state to avoid overwriting concurrent updates
      // (e.g. descriptor analysis loaded concurrently).
      final atEmit =
          state is WalletDetailLoaded ? state as WalletDetailLoaded : s;

      emit(atEmit.copyWith(
        walletHandle: handle,
        walletInfo: event.walletInfo,
        balance: event.balance,
        transactions: page.transactions,
        totalTransactions: page.totalCount,
        hasMore: page.hasMore,
        isSyncing: false,
        currentPage: 0,
        tipHeight: tipHeight,
        receiveAddresses: receiveAddrs,
        changeAddresses: changeAddrs,
        receiveAddressesLoaded: receiveAddrs != null || atEmit.receiveAddressesLoaded,
        changeAddressesLoaded: changeAddrs != null || atEmit.changeAddressesLoaded,
        utxos: utxos,
        utxosLoaded: utxos != null || atEmit.utxosLoaded,
        psbts: psbts,
        psbtAnalyses: psbtAnalyses,
        psbtsLoaded: atEmit.psbtsLoaded,
        errorMessage: null,
      ));
      unawaited(_fetchMissingFiatPrices());
    } catch (e, st) {
      _emitError('WalletDetailCubit._onSyncEvent()', e, st);
    }
  }

  @override
  Future<void> close() {
    _retryTimer?.cancel();
    _syncEventSub?.cancel();
    // WalletSyncService keeps the handle and subscription alive after close.
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

  /// Evict all cached credentials so the wallet will require re-authentication
  /// on next open. The caller is responsible for navigating away.
  void lockWallet() {
    final current = state;
    if (current is! WalletDetailLoaded) return;
    final path = current.walletInfo.walletPath;
    _service.evictPassword(path);
    _service.evictBiometricKey(path);
    _syncService.untrack(path);
  }

  Future<void> load(
    String walletPath, {
    String? password,
    String? openingMessage,
    String? loadingDataMessage,
    // Localized reason string shown in the biometric prompt.
    // When provided and the wallet has biometric slots, biometric unlock is
    // attempted before falling back to the password prompt.
    String? biometricUnlockReason,
  }) async {
    emit(WalletDetailLoading(message: openingMessage));
    try {
      if (password != null) _service.cachePassword(walletPath, password);
      // If no credential is cached yet, check upfront whether one is required
      // — avoids brittle string matching on the Rust error.
      ApiWallet? handle;
      if (!_service.isUnlocked(walletPath)) {
        // Check both flags in parallel — each reads the .meta sidecar once.
        final (needsPassword, isXpubKey) = await (
          _service.walletRequiresPassword(walletPath),
          _service.walletRequiresXpub(walletPath),
        ).wait;
        if (needsPassword) {
          // Attempt hardware biometric unlock before showing the password prompt.
          if (biometricUnlockReason != null) {
            handle = await _tryBiometricUnlock(walletPath, biometricUnlockReason);
          }
          if (handle == null) {
            // No credential available — ask for password.
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
      }
      handle ??= await _service.openWallet(walletPath);
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
      List<String> loadWarnings = [];
      try {
        psbts = await handle.listPsbts();
        psbtAnalyses = await _analyzePsbts(handle, psbts);
      } catch (e, st) {
        logError('WalletDetailCubit.load() PSBTs', e, st);
        loadWarnings.add(formatRustError(e));
      }

      // Load hot keys
      List<APIHotKeyInfo> hotKeys = [];
      try {
        final result = handle.listHotKeys();
        hotKeys = result.keys;
        if (result.corruptRows.isNotEmpty) {
          loadWarnings.add(
            'Lost ${result.corruptRows.length} signing key(s) due to database corruption',
          );
        }
      } catch (e, st) {
        logError('WalletDetailCubit.load() hotKeys', e, st);
        loadWarnings.add(formatRustError(e));
      }

      // Check biometric slot status (fast .meta read, non-critical)
      bool hasBioSlot = false;
      try {
        hasBioSlot = await _service.hasBiometricSlots(walletPath);
      } catch (_) {}

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
        hasBiometricSlot: hasBioSlot,
        errorMessage: loadWarnings.isNotEmpty
            ? loadWarnings.join('\n')
            : null,
      ));
      // Eagerly load descriptor analysis so PSBT navigation works from the
      // Transactions tab without needing to visit the Descriptor tab first.
      unawaited(_loadDescriptorAnalysis());
    } catch (e, stackTrace) {
      logError('WalletDetailCubit.load()', e, stackTrace);
      // Evict any cached credential so the prompt re-appears on next open
      // instead of failing silently with a cached bad credential.
      _service.evictPassword(walletPath);
      _service.evictBiometricKey(walletPath);
      emit(WalletDetailError(formatRustError(e)));
    }
  }

  /// Attempts to open the wallet using a registered biometric slot.
  ///
  /// Authentication is hardware-enforced: [BiometricKeystoreService.retrieveKey]
  /// triggers the platform's biometric prompt internally (Android Keystore /
  /// iOS Keychain). There is no separate app-level authentication step.
  /// Returns null if biometrics are unavailable, the user cancels, or no
  /// matching key is found in the hardware keystore.
  Future<ApiWallet?> _tryBiometricUnlock(
    String walletPath,
    String localizedReason,
  ) async {
    try {
      if (!await _keystoreService.isAvailable()) return null;
      if (!await _service.hasBiometricSlots(walletPath)) return null;
      final slots = await _service.listBiometricSlots(walletPath);
      final promptInfo = PromptInfo(
        androidPromptInfo: AndroidPromptInfo(
          title: localizedReason,
          negativeButton: 'Cancel',
        ),
        iosPromptInfo: IosPromptInfo(accessTitle: localizedReason),
        macOsPromptInfo: IosPromptInfo(accessTitle: localizedReason),
      );
      for (final slot in slots) {
        final key = await _keystoreService.retrieveKey(slot.id, promptInfo);
        if (key == null) continue;
        try {
          _service.cacheBiometricKey(walletPath, key);
          return await _service.openWallet(walletPath);
        } catch (_) {
          _service.evictBiometricKey(walletPath);
          continue;
        }
      }
    } catch (_) {}
    return null;
  }

  /// Enables biometric unlock for the currently loaded wallet.
  ///
  /// Flow:
  /// 1. Generate a random 32-byte key via [BiometricKeystoreService.generateKey].
  /// 2. Register a new biometric slot in the wallet's .meta file via Rust,
  ///    which returns the slot ID (UUID v4).
  /// 3. Store the key in the hardware-backed keystore under that ID.
  ///    The platform shows a biometric prompt at this point — [promptInfo]
  ///    provides the localized strings shown in that prompt.
  ///
  /// If Rust fails in step 2, nothing is written to the keystore.
  /// If the keystore write fails in step 3 (e.g. user cancels the prompt),
  /// the orphan slot in .meta is removed to keep state consistent.
  Future<void> enableBiometricSlot(PromptInfo promptInfo) async {
    final s = state;
    if (s is! WalletDetailLoaded) return;
    final walletPath = s.walletInfo.walletPath;
    try {
      final keyHex = _keystoreService.generateKey();
      final slotId = await _service.addBiometricSlot(
        walletPath: walletPath,
        biometricKeyHex: keyHex,
      );
      try {
        await _keystoreService.storeKey(slotId, keyHex, promptInfo);
      } catch (e, _) {
        // Rollback: remove the Rust slot so .meta stays consistent.
        await _service.removeBiometricSlot(
          walletPath: walletPath,
          biometricId: slotId,
        );
        rethrow;
      }
      emit(s.copyWith(hasBiometricSlot: true));
    } catch (e, st) {
      _emitError('WalletDetailCubit.enableBiometricSlot()', e, st);
    }
  }

  /// Disables all biometric unlock slots for the currently loaded wallet.
  /// Removes every slot from the .meta file and deletes the corresponding
  /// keys from the platform keystore.
  Future<void> disableAllBiometricSlots() async {
    final s = state;
    if (s is! WalletDetailLoaded) return;
    final walletPath = s.walletInfo.walletPath;
    try {
      final slots = await _service.listBiometricSlots(walletPath);
      for (final slot in slots) {
        await _service.removeBiometricSlot(
          walletPath: walletPath,
          biometricId: slot.id,
        );
        await _keystoreService.deleteKey(slot.id);
      }
      emit(s.copyWith(hasBiometricSlot: false));
    } catch (e, st) {
      _emitError('WalletDetailCubit.disableAllBiometricSlots()', e, st);
    }
  }

  /// Trigger an immediate sync via the global WalletSyncService.
  /// The actual data reload happens in [_onSyncEvent] when the service emits.
  void sync() {
    final s = state;
    if (s is! WalletDetailLoaded) return;
    _syncService.syncWallet(s.walletInfo.walletPath);
  }

  // ─── Transaction navigation ──────────────────────────────────────────────

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

      final (walletInfo, balance, page, tipHeight) = await (
        handle.getInfo(),
        handle.getBalance(),
        handle.getTransactions(page: 0, pageSize: _pageSize),
        handle.getTipHeight(),
      ).wait;

      final atEmit = state is WalletDetailLoaded ? state as WalletDetailLoaded : current;
      emit(atEmit.copyWith(
        walletHandle: handle,
        walletInfo: walletInfo,
        balance: balance,
        transactions: page.transactions,
        totalTransactions: page.totalCount,
        hasMore: page.hasMore,
        isSyncing: false,
        currentPage: 0,
        tipHeight: tipHeight,
        // Reset data and loaded flags — rescan may reveal new addresses/coins
        receiveAddresses: const [],
        changeAddresses: const [],
        receiveAddressesLoaded: false,
        changeAddressesLoaded: false,
        utxos: const [],
        utxosLoaded: false,
        descriptorLoaded: false,
      ));
      // Eagerly reload descriptor + coins so inheritance section is ready.
      unawaited(Future.wait([
        _loadDescriptorAnalysis(),
        _loadUtxos(),
      ]));
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

      if (state is! WalletDetailLoaded) return;
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

    if (tab == tabAddresses) {
      if (!current.receiveAddressesLoaded) {
        unawaited(_loadAddresses(APIKeychain.external_));
      }
      if (!current.changeAddressesLoaded) {
        unawaited(_loadAddresses(APIKeychain.internal));
      }
    } else if (tab == tabCoins) {
      if (!current.utxosLoaded) {
        unawaited(_loadUtxos());
      }
      if (!current.descriptorLoaded) {
        unawaited(_loadDescriptorAnalysis());
      }
    } else if (tab == tabDescriptor) {
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

  // ─── Address management ──────────────────────────────────────────────────

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
      // Fire-and-forget: don't block the receive dialog on network I/O.
      sync();
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

  // ─── Labels ──────────────────────────────────────────────────────────────

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


  // ─── RBF / CPFP ──────────────────────────────────────────────────────────

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
    required int feeAbsoluteSat,
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
        feeAbsoluteSat: BigInt.from(feeAbsoluteSat),
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
    required int feeAbsoluteSat,
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
      feeAbsoluteSat: feeAbsoluteSat,
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
    if (state is WalletDetailLoaded) {
      emit(current.copyWith(
        psbts: updatedPsbts,
        psbtAnalyses: updatedAnalyses,
        transactions: page.transactions,
        totalTransactions: page.totalCount,
        hasMore: page.hasMore,
        currentPage: 0,
      ));
    }
    // Sync immediately after broadcast — sync reloads UTXOs when utxosLoaded
    // is true, so coins will reflect the mempool spending status correctly.
    unawaited(_syncService.syncWallet(current.walletInfo.walletPath));
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

  /// Derive the WIF-encoded private key for a specific address in this wallet.
  Future<String?> revealAddressWif(String address, String mfp) async {
    final current = state;
    if (current is! WalletDetailLoaded) return null;
    try {
      return current.walletHandle.deriveAddressWif(address: address, mfp: mfp);
    } catch (e, st) {
      _emitError('WalletDetailCubit.revealAddressWif()', e, st);
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
      String? analyzeError;
      try {
        analysis = await current.walletHandle
            .analyzePsbt(psbtBase64: updated.psbtBase64, mfps: updated.mfps);
      } catch (e, st) {
        logError('WalletDetailCubit.signPsbtWithKey() analyze', e, st);
        analyzeError = formatRustError(e);
      }

      // Re-read state to avoid overwriting concurrent updates (e.g. a sync
      // that completed while analyzePsbt was awaiting).
      final latest = state is WalletDetailLoaded ? state as WalletDetailLoaded : current;
      final updatedPsbts = latest.psbts
          .map((p) => p.id.toInt() == psbtId ? updated : p)
          .toList();
      final updatedAnalyses = Map<int, APIPsbtAnalysis>.from(latest.psbtAnalyses);
      if (analysis != null) updatedAnalyses[psbtId] = analysis;
      emit(latest.copyWith(
        psbts: updatedPsbts,
        psbtAnalyses: updatedAnalyses,
        errorMessage: analyzeError,
      ));
      return updated;
    } catch (e, st) {
      _emitError('WalletDetailCubit.signPsbtWithKey()', e, st);
      return null;
    }
  }

  // ─── Protection management ──────────────────────────────────────────────

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
      // Changing protection always invalidates all biometric slots in Rust,
      // so evict the biometric key regardless of the new protection type.
      final walletPath = current.walletInfo.walletPath;
      _service.evictBiometricKey(walletPath);
      switch (newProtectionType) {
        case APIProtectionType.deviceKey:
          _service.evictPassword(walletPath);
        case APIProtectionType.userPassword:
          if (newPassword != null) _service.cachePassword(walletPath, newPassword);
        case APIProtectionType.xpubKey:
          // Cache the first xpub so biometric enrollment works in this session.
          // Mirrors UserPassword behaviour: the wallet stays open until app restart.
          // If descriptor analysis is unavailable, evict and let the user re-enter.
          final xpubKeys = current.descriptorAnalysis?.keys;
          if (xpubKeys != null && xpubKeys.isNotEmpty) {
            _service.cachePassword(walletPath, xpubKeys.first.xpub);
          } else {
            _service.evictPassword(walletPath);
          }
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

  // ─── Fiat price support ─────────────────────────────────────────────────

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
              ? formatDate(utc)
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
