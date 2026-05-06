import 'dart:async';

import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:meta/meta.dart';

import 'package:deadbolt/cubit/cubit_error_logger.dart';
import 'package:deadbolt/cubit/wallet_detail_session.dart'
    show
        WalletInfo,
        TransactionPage,
        AddressView,
        CoinView,
        PsbtList,
        WalletLoadSuccess,
        WalletLoadNeedsPassword;
import 'package:deadbolt/cubit/wallet_detail_state.dart';
import 'package:deadbolt/cubit/wallet_op_result.dart' show Ok, Err, WalletOpResult;
import 'package:deadbolt/cubit/wallet_opener.dart' show WalletOpener;
import 'package:deadbolt/errors.dart';
import 'package:deadbolt/services/wallet_sync_service.dart';
import 'package:deadbolt/src/rust/api/model.dart' show APIKeychain;

/// Lifecycle handler: load/lock, sync subscription + retries, tab selection,
/// error helpers shared across all wallet-detail handlers.
///
/// Concrete cubit must provide [opener] and [syncService], and implement the
/// `@protected` data-loading methods that domain-specific mixins own
/// ([loadUtxos], [loadAddresses], [loadDescriptorAnalysis],
/// [fetchMissingFiatPrices]). During the staged refactor those still live in
/// the cubit body until their owning mixin is extracted.
mixin WalletDetailLifecycle on Cubit<WalletDetailState>, CubitErrorLogger {
  @protected
  WalletOpener get opener;

  @protected
  WalletSyncService get syncService;

  Timer? _retryTimer;
  StreamSubscription<WalletSyncEvent>? _syncEventSub;

  // ─── Data-loading hooks owned by other (future) mixins ──────────────────

  @protected
  Future<void> loadUtxos();

  @protected
  Future<void> loadAddresses(APIKeychain keychain);

  @protected
  Future<void> loadDescriptorAnalysis();

  @protected
  Future<void> fetchMissingFiatPrices();

  /// Owned by the descriptor mixin: re-runs address / coin / tx loaders after
  /// any label setter so all open views see the new label.
  @protected
  Future<void> refreshAllAfterLabelChange();

  /// Owned by the coins mixin: invalidates and reloads the UTXO view if it
  /// was already populated (otherwise a no-op). Called by PSBT create/delete
  /// to keep coin selection in sync with reservations.
  @protected
  Future<void> reloadCoinsIfLoaded();

  // ─── Shared helpers ──────────────────────────────────────────────────────

  /// Downcast helper: returns the loaded state or null if we're in any other
  /// state (initial / loading / error / needs-password).
  WalletDetailLoaded? get loadedState =>
      state is WalletDetailLoaded ? state as WalletDetailLoaded : null;

  /// Logs and surfaces an error as a transient toast on the loaded state.
  /// Silently drops if we're not loaded.
  @protected
  void emitError(String tag, Object e, StackTrace st) {
    logError(tag, e, st);
    final s = loadedState;
    if (s != null) emit(s.copyWith(errorMessage: formatRustError(e)));
  }

  /// Runs a wallet operation and reduces the [WalletOpResult] into a new
  /// emitted state. Centralizes the `current → result → after → emit copyWith`
  /// boilerplate that every domain mixin would otherwise repeat.
  ///
  /// - bails out silently if we transition out of [WalletDetailLoaded] before
  ///   or after the await.
  /// - on [Err], surfaces the message as a transient toast via `errorMessage`.
  /// - on [Ok], emits the state produced by [onOk] (called with the post-await
  ///   loaded state and the unwrapped value).
  @protected
  Future<void> runWalletOp<T>(
    Future<WalletOpResult<T>> Function(WalletDetailLoaded current) op,
    WalletDetailLoaded Function(WalletDetailLoaded after, T value) onOk,
  ) async {
    final current = loadedState;
    if (current == null) return;
    final result = await op(current);
    final after = loadedState;
    if (after == null) return;
    switch (result) {
      case Err(:final message):
        emit(after.copyWith(errorMessage: message));
      case Ok(:final value):
        emit(onOk(after, value));
    }
  }

  @override
  void emit(WalletDetailState state) {
    if (!isClosed) super.emit(state);
  }

  // ─── Wallet session ──────────────────────────────────────────────────────

  void registerWithSyncService(String electrumUrl) {
    final s = loadedState;
    if (s == null) return;
    unawaited(
      syncService.registerHandle(
        s.walletInfo.walletPath,
        s.walletHandle,
        electrumUrl,
      ),
    );

    _syncEventSub?.cancel();
    _syncEventSub = syncService.events
        .where((e) => e.walletPath == s.walletInfo.walletPath)
        .listen(_onSyncEvent);
  }

  Future<void> _onSyncEvent(WalletSyncEvent event) async {
    final s = loadedState;
    if (s == null) return;

    if (event.isSyncing) {
      emit(s.copyWith(isSyncing: true));
      return;
    }

    final result = await s.wallet.handleSyncEvent(
      event: event,
      receiveLoaded: s.receiveAddressesLoaded,
      changeLoaded: s.changeAddressesLoaded,
      utxosLoaded: s.utxosLoaded,
      psbtsLoaded: s.psbtsLoaded,
      currentPsbts: s.psbts,
      currentAnalyses: s.psbtAnalyses,
    );

    final reload = switch (result) {
      Err(:final message) => () {
          emit(s.copyWith(isSyncing: false, errorMessage: message));
          return null;
        }(),
      Ok(:final value) => value,
    };
    if (reload == null) return;

    if (reload.wasSyncing) {
      emit(s.copyWith(isSyncing: false));
      return;
    }
    if (reload.retryNeeded) {
      emit(s.copyWith(isSyncing: false));
      _retryTimer?.cancel();
      // Retry after 15 seconds when Electrum returns stale data (no such tx).
      // Rationale: Electrum mempool can take up to ~10s to propagate;
      // waiting 15s avoids thrashing on transient propagation delays.
      _retryTimer = Timer(const Duration(seconds: 15), sync);
      return;
    }

    final current = loadedState;
    if (current == null) return;

    final chain = reload.chain!;
    emit(current.copyWith(
      info: WalletInfo(
        walletInfo: chain.info,
        balance: chain.balance,
        hasBiometricSlot: current.hasBiometricSlot,
        tipHeight: chain.tipHeight,
      ),
      txPage: TransactionPage(
        transactions: chain.transactions.transactions,
        totalCount: chain.transactions.totalCount,
        hasMore: chain.transactions.hasMore,
        currentPage: 0,
      ),
      addresses: AddressView(
        receiveAddresses: reload.receive?.addresses ?? current.receiveAddresses,
        changeAddresses: reload.change?.addresses ?? current.changeAddresses,
        receiveLoaded: (reload.receive?.addresses.isNotEmpty == true) || current.receiveAddressesLoaded,
        changeLoaded: (reload.change?.addresses.isNotEmpty == true) || current.changeAddressesLoaded,
        selectedKeychain: current.selectedAddressKeychain,
      ),
      coins: CoinView(
        utxos: reload.coins?.utxos ?? current.utxos,
        loaded: (reload.coins?.utxos.isNotEmpty == true) || current.utxosLoaded,
      ),
      psbts: PsbtList(
        psbts: reload.psbts?.psbts ?? current.psbts,
        analyses: reload.psbts?.analyses ?? current.psbtAnalyses,
        loaded: current.psbtsLoaded,
      ),
      isSyncing: false,
      errorMessage: null,
    ));
    unawaited(fetchMissingFiatPrices());
  }

  @override
  Future<void> close() {
    _retryTimer?.cancel();
    _syncEventSub?.cancel();
    return super.close();
  }

  void clearError() {
    final s = loadedState;
    if (s != null) emit(s.copyWith(errorMessage: null));
  }

  Future<void> load(
    String walletPath, {
    String? password,
    String? openingMessage,
    String? loadingDataMessage,
    String? biometricUnlockReason,
  }) async {
    emit(WalletDetailLoading(message: openingMessage));
    try {
      final result = await opener.load(
        walletPath: walletPath,
        password: password,
        biometricUnlockReason: biometricUnlockReason,
      );

      if (result is WalletLoadNeedsPassword) {
        emit(WalletDetailNeedsPassword(walletPath, isXpubKey: result.isXpubKey, network: result.network));
        return;
      }

      final success = result as WalletLoadSuccess;
      if (loadingDataMessage != null) {
        emit(WalletDetailLoading(message: loadingDataMessage));
      }
      emit(WalletDetailLoaded.fromView(success.view, success.wallet));
      unawaited(loadDescriptorAnalysis());
    } catch (e, stackTrace) {
      logError('WalletDetailCubit.load()', e, stackTrace);
      // Defensive: ensure no stale credentials survive a failed open, so the
      // next tap re-prompts for password instead of replaying the failure.
      opener.lock(walletPath);
      emit(WalletDetailError(formatRustError(e)));
    }
  }

  void lockWallet() {
    final current = loadedState;
    if (current == null) return;
    opener.lock(current.walletInfo.walletPath);
  }

  void sync() {
    final s = loadedState;
    if (s == null) return;
    syncService.syncWallet(s.walletInfo.walletPath);
  }

  void selectTab(int tab) {
    final current = loadedState;
    if (current == null) return;
    if (current.selectedTab == tab) return;

    emit(current.copyWith(selectedTab: tab));

    if (tab == 3 && !current.utxosLoaded) {
      unawaited(loadUtxos());
    }
    if (tab == 3 && !current.descriptorLoaded) {
      unawaited(loadDescriptorAnalysis());
    }
    if (tab == 4 && !current.descriptorLoaded) {
      unawaited(loadDescriptorAnalysis());
    }
    if (tab == 2) {
      if (!current.receiveAddressesLoaded) {
        unawaited(loadAddresses(APIKeychain.external_));
      }
      if (!current.changeAddressesLoaded) {
        unawaited(loadAddresses(APIKeychain.internal));
      }
    }
  }
}
