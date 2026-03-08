import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import 'package:deadbolt/services/wallet_service.dart';
import 'package:deadbolt/src/rust/api/analyzer.dart' show analyzeDescriptor;
import 'package:deadbolt/src/rust/api/analyzer.dart' show APIAnalysisResult;
import 'package:deadbolt/src/rust/api/model.dart';
import 'package:deadbolt/src/rust/api/wallet.dart' show ApiWallet;

// Re-export for the screen
export 'package:deadbolt/src/rust/api/analyzer.dart' show APIAnalysisResult;
export 'package:deadbolt/src/rust/api/model.dart'
    show APIUtxo, APIPsbtInfo, APIPsbtAnalysis, APIPsbtSignerStatus, APICoinControl,
        APIPolicyPath;

// --- States ---

sealed class WalletDetailState {}

class WalletDetailInitial extends WalletDetailState {}

class WalletDetailLoading extends WalletDetailState {}

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
    );
  }
}

class WalletDetailError extends WalletDetailState {
  final String message;
  WalletDetailError(this.message);
}

// --- Cubit ---

class WalletDetailCubit extends Cubit<WalletDetailState> {
  final WalletService _service;
  static const _pageSize = 25;
  static const _revealCount = 20;
  static const _autoSyncInterval = Duration(minutes: 5);

  Timer? _syncTimer;
  String? _electrumUrl;

  WalletDetailCubit({WalletService? service})
      : _service = service ?? WalletService(),
        super(WalletDetailInitial());

  /// Triggers an immediate sync and starts a periodic 5-minute auto-sync.
  /// Safe to call multiple times (restarts the timer).
  void startAutoSync(String electrumUrl) {
    _electrumUrl = electrumUrl;
    _syncTimer?.cancel();
    sync(electrumUrl);
    _syncTimer = Timer.periodic(_autoSyncInterval, (_) => sync(electrumUrl));
  }

  @override
  Future<void> close() {
    _syncTimer?.cancel();
    return super.close();
  }

  void _logError(String context, Object error, StackTrace stackTrace) {
    debugPrint('════════════════════════════════════════════════════════════');
    debugPrint('ERROR in $context:');
    debugPrint('$error');
    debugPrint('Stack trace:');
    debugPrint('$stackTrace');
    debugPrint('════════════════════════════════════════════════════════════');
  }

  Future<void> load(String walletPath) async {
    emit(WalletDetailLoading());
    try {
      final handle = await _service.openWallet(walletPath);
      final walletInfo = await handle.getInfo();
      final balance = await handle.getBalance();
      final page = await handle.getTransactions(page: 0, pageSize: _pageSize);
      final tipHeight = await handle.getTipHeight();

      // Load PSBTs eagerly
      List<APIPsbtInfo> psbts = [];
      Map<int, APIPsbtAnalysis> psbtAnalyses = {};
      try {
        psbts = await handle.listPsbts();
        for (final psbt in psbts) {
          try {
            psbtAnalyses[psbt.id.toInt()] =
                await handle.analyzePsbt(psbtBase64: psbt.psbtBase64, mfps: psbt.mfps);
          } catch (_) {}
        }
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
        psbts: psbts,
        psbtAnalyses: psbtAnalyses,
        psbtsLoaded: true,
      ));
      // Eagerly load descriptor analysis so PSBT navigation works from the
      // Transactions tab without needing to visit the Descriptor tab first.
      _loadDescriptorAnalysis();
    } catch (e, stackTrace) {
      _logError('WalletDetailCubit.load()', e, stackTrace);
      emit(WalletDetailError(e.toString()));
    }
  }

  Future<void> sync(String electrumUrl) async {
    final current = state;
    if (current is! WalletDetailLoaded) return;

    emit(current.copyWith(isSyncing: true));
    try {
      final handle = current.walletHandle;

      await handle.sync_(electrumUrl: electrumUrl);

      final walletInfo = await handle.getInfo();
      final balance = await handle.getBalance();
      final page = await handle.getTransactions(page: 0, pageSize: _pageSize);
      final tipHeight = await handle.getTipHeight();

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
          psbtAnalyses = {};
          for (final psbt in psbts) {
            try {
              psbtAnalyses[psbt.id.toInt()] =
                  await handle.analyzePsbt(psbtBase64: psbt.psbtBase64, mfps: psbt.mfps);
            } catch (_) {}
          }
        } catch (_) {}
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
      ));
    } catch (e, stackTrace) {
      _logError('WalletDetailCubit.sync()', e, stackTrace);
      if (state is WalletDetailLoaded) {
        emit((state as WalletDetailLoaded).copyWith(isSyncing: false));
      }
      emit(WalletDetailError(e.toString()));
    }
  }

  Future<void> setTxLabel(String txid, String label) async {
    final current = state;
    if (current is! WalletDetailLoaded) return;
    current.walletHandle.setTxLabel(txid: txid, label: label);
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
      ));
    } catch (e, stackTrace) {
      _logError('WalletDetailCubit.rescan()', e, stackTrace);
      if (state is WalletDetailLoaded) {
        emit((state as WalletDetailLoaded).copyWith(isSyncing: false));
      }
      emit(WalletDetailError(e.toString()));
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
      _logError('WalletDetailCubit.loadMoreTransactions()', e, stackTrace);
    }
  }

  /// Switch the bottom navigation tab. Lazily loads addresses/coins on first visit.
  void selectTab(int tab) {
    final current = state;
    if (current is! WalletDetailLoaded) return;
    if (current.selectedTab == tab) return;

    final updated = current.copyWith(selectedTab: tab);
    emit(updated);

    if (tab == 1) {
      if (!current.receiveAddressesLoaded) {
        _loadAddresses(APIKeychain.external_);
      }
      if (!current.changeAddressesLoaded) {
        _loadAddresses(APIKeychain.internal);
      }
    } else if (tab == 2) {
      if (!current.utxosLoaded) {
        _loadUtxos();
      }
      if (!current.descriptorLoaded) {
        _loadDescriptorAnalysis();
      }
    } else if (tab == 3) {
      if (!current.descriptorLoaded) {
        _loadDescriptorAnalysis();
      }
    }
  }

  /// Switch the receive/change sub-tab inside the addresses view.
  void selectAddressKeychain(int keychain) {
    final current = state;
    if (current is! WalletDetailLoaded) return;
    emit(current.copyWith(selectedAddressKeychain: keychain));
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
      _logError('WalletDetailCubit._loadAddresses()', e, stackTrace);
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
      _logError('WalletDetailCubit._loadUtxos()', e, stackTrace);
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
      _logError('WalletDetailCubit.revealMoreAddresses()', e, stackTrace);
    }
  }

  Future<void> setAddressLabel(String address, String label, APIKeychain keychain) async {
    final current = state;
    if (current is! WalletDetailLoaded) return;
    current.walletHandle.setAddressLabel(address: address, label: label);
    await _loadAddresses(keychain);
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
      _logError('WalletDetailCubit._loadDescriptorAnalysis()', e, stackTrace);
    }
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

  // ─── Coin loading ─────────────────────────────────────────────────────────

  /// Ensures UTXOs are loaded without switching tabs.
  /// No-op if already loaded.
  Future<void> ensureCoinsLoaded() async {
    final current = state;
    if (current is! WalletDetailLoaded) return;
    if (!current.utxosLoaded) _loadUtxos();
    if (!current.descriptorLoaded) await _loadDescriptorAnalysis();
  }

  /// Returns the next unused external (receive) address that is not already
  /// reserved as the recipient of a pending unsigned PSBT.
  ///
  /// Mempool/unconfirmed transactions are already reflected in [APIAddress.isUsed]
  /// via BDK's sync. Unsigned PSBTs are checked explicitly via [psbts].
  /// If no unused address is found among revealed ones, new ones are revealed
  /// and the search retries once.
  Future<String?> getNextSelfPaymentAddress() async {
    final current = state;
    if (current is! WalletDetailLoaded) return null;
    try {
      final psbtRecipients = current.psbts.map((p) => p.recipient).toSet();

      String? findIn(List<APIAddress> addrs) {
        for (final addr in addrs) {
          if (!addr.isUsed && !psbtRecipients.contains(addr.address)) {
            return addr.address;
          }
        }
        return null;
      }

      var addrs = await current.walletHandle.getAddresses(keychain: APIKeychain.external_);
      final found = findIn(addrs);
      if (found != null) return found;

      // All revealed addresses are used — reveal more and retry once.
      current.walletHandle.revealMoreAddresses(
        keychain: APIKeychain.external_,
        count: _revealCount,
      );
      addrs = await current.walletHandle.getAddresses(keychain: APIKeychain.external_);
      return findIn(addrs);
    } catch (_) {
      return null;
    }
  }

  // ─── PSBTs ────────────────────────────────────────────────────────────────

  Future<void> loadPsbts() async {
    final current = state;
    if (current is! WalletDetailLoaded) return;
    try {
      final psbts = await current.walletHandle.listPsbts();
      final analyses = <int, APIPsbtAnalysis>{};
      for (final psbt in psbts) {
        try {
          analyses[psbt.id.toInt()] = await current.walletHandle
              .analyzePsbt(psbtBase64: psbt.psbtBase64, mfps: psbt.mfps);
        } catch (_) {
          // skip analysis errors — show without status
        }
      }
      if (state is! WalletDetailLoaded) return;
      emit((state as WalletDetailLoaded).copyWith(
        psbts: psbts,
        psbtAnalyses: analyses,
        psbtsLoaded: true,
      ));
    } catch (e, st) {
      _logError('WalletDetailCubit.loadPsbts()', e, st);
    }
  }

  /// Create a PSBT and save it. Returns the new [APIPsbtInfo] or null on error.
  Future<APIPsbtInfo?> createPsbt({
    required String recipientAddress,
    required int amountSat,
    required double feeRateSatPerVb,
    required List<APICoinControl> selectedUtxos,
    required List<APIPolicyPath> policyPath,
    required int spendPathId,
    required int threshold,
    required List<String> mfps,
    bool sendMax = false,
  }) async {
    final current = state;
    if (current is! WalletDetailLoaded) return null;
    try {
      final psbt = current.walletHandle.createPsbt(
        recipientAddress: recipientAddress,
        amountSat: BigInt.from(amountSat),
        feeRateSatPerVb: feeRateSatPerVb,
        selectedUtxos: selectedUtxos,
        policyPath: policyPath,
        spendPathId: spendPathId,
        threshold: threshold,
        mfps: mfps,
        sendMax: sendMax,
      );
      unawaited(loadPsbts());
      return psbt;
    } catch (e, st) {
      _logError('WalletDetailCubit.createPsbt()', e, st);
      rethrow;
    }
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
    } catch (e, st) {
      _logError('WalletDetailCubit.deletePsbt()', e, st);
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
      } catch (_) {}

      final updatedPsbts = current.psbts
          .map((p) => p.id.toInt() == id ? updated : p)
          .toList();
      final updatedAnalyses = Map<int, APIPsbtAnalysis>.from(current.psbtAnalyses);
      if (analysis != null) updatedAnalyses[id] = analysis;

      emit(current.copyWith(psbts: updatedPsbts, psbtAnalyses: updatedAnalyses));
      return updated;
    } catch (e, st) {
      _logError('WalletDetailCubit.mergePsbt()', e, st);
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
    // Sync immediately after broadcast so balance and confirmations update.
    final url = _electrumUrl ?? electrumUrl;
    sync(url);
    return txid;
  }
}
