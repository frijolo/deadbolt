import 'dart:async';

import 'package:flutter_bloc/flutter_bloc.dart';

import 'package:deadbolt/cubit/cubit_error_logger.dart';
import 'package:deadbolt/errors.dart';
import 'package:deadbolt/services/background_broadcast_scheduler.dart';
import 'package:deadbolt/services/wallet_service.dart';
import 'package:deadbolt/services/wallet_sync_service.dart';
import 'package:deadbolt/src/rust/api/model.dart';

// --- States ---

sealed class WalletListState {}

class WalletListLoading extends WalletListState {}

class WalletListLoaded extends WalletListState {
  final List<APIWalletInfo> wallets;
  final Map<String, APIBalance?> balances; // null = not yet known
  final Set<String> syncing;               // walletPaths currently syncing

  WalletListLoaded(
    this.wallets, {
    this.balances = const {},
    this.syncing = const {},
  });

  WalletListLoaded copyWith({
    List<APIWalletInfo>? wallets,
    Map<String, APIBalance?>? balances,
    Set<String>? syncing,
  }) =>
      WalletListLoaded(
        wallets ?? this.wallets,
        balances: balances ?? this.balances,
        syncing: syncing ?? this.syncing,
      );
}

class WalletListError extends WalletListState {
  final String message;
  WalletListError(this.message);
}

// --- Cubit ---

class WalletListCubit extends Cubit<WalletListState> with CubitErrorLogger {
  final WalletService _service;
  final WalletSyncService? _syncService;

  StreamSubscription<WalletSyncEvent>? _syncEventSub;

  WalletListCubit({WalletService? service, WalletSyncService? syncService})
      : _service = service ?? WalletService(),
        _syncService = syncService,
        super(WalletListLoading()) {
    _subscribeToSyncService();
    refresh();
  }

  void _subscribeToSyncService() {
    _syncEventSub = _syncService?.events.listen((event) {
      final s = state;
      if (s is! WalletListLoaded) return;

      if (event.isSyncing) {
        if (s.syncing.contains(event.walletPath)) return;
        emit(s.copyWith(syncing: {...s.syncing, event.walletPath}));
        return;
      }

      final walletWasSyncing = s.syncing.contains(event.walletPath);
      final hasNewBalance = event.balance != null;
      final hasNewWalletInfo = event.walletInfo != null;
      if (!walletWasSyncing && !hasNewBalance && !hasNewWalletInfo) return;

      final newSyncing = walletWasSyncing
          ? (Set<String>.from(s.syncing)..remove(event.walletPath))
          : s.syncing;
      final newBalances = hasNewBalance
          ? {...s.balances, event.walletPath: event.balance}
          : s.balances;
      final newWallets = hasNewWalletInfo
          ? s.wallets
              .map((w) =>
                  w.walletPath == event.walletPath ? event.walletInfo! : w)
              .toList()
          : s.wallets;

      emit(s.copyWith(
        wallets: newWallets,
        balances: newBalances,
        syncing: newSyncing,
      ));
    });
  }

  /// Delegate a manual sync request to the service.
  void syncWallet(String walletPath) => _syncService?.syncWallet(walletPath);

  Future<void> refresh() async {
    try {
      final wallets = await _service.listWallets();
      // Preserve cached balances for wallets still present in the list.
      final prev = state is WalletListLoaded
          ? (state as WalletListLoaded).balances
          : const <String, APIBalance?>{};
      final preserved = {
        for (final w in wallets)
          if (prev.containsKey(w.walletPath)) w.walletPath: prev[w.walletPath],
      };
      emit(WalletListLoaded(wallets, balances: preserved));
    } catch (e, stackTrace) {
      logError('WalletListCubit.refresh()', e, stackTrace);
      emit(WalletListError(formatRustError(e)));
    }
  }

  Future<String> createWallet({
    required String name,
    required String descriptor,
    required APINetwork network,
    APIProtectionType protectionType = APIProtectionType.deviceKey,
    String? password,
    APISecurityLevel securityLevel = APISecurityLevel.standard,
  }) async {
    try {
      final info = await _service.createWallet(
        name: name,
        descriptor: descriptor,
        network: network,
        protectionType: protectionType,
        password: password,
        securityLevel: securityLevel,
      );
      if (protectionType == APIProtectionType.userPassword && password != null) {
        _service.cachePassword(info.walletPath, password);
      }
      await refresh();
      return info.walletPath;
    } catch (e, stackTrace) {
      logError('WalletListCubit.createWallet()', e, stackTrace);
      rethrow;
    }
  }

  Future<void> deleteWallet(String walletPath) async {
    try {
      // Untrack before deleting so the Rust handle is dropped before the
      // SQLite files are removed (avoids file-in-use issues on some platforms).
      _syncService?.untrack(walletPath);
      await _service.deleteWallet(walletPath);
      await refresh();
      BackgroundBroadcastScheduler.instance.refresh();
    } catch (e, stackTrace) {
      logError('WalletListCubit.deleteWallet()', e, stackTrace);
      rethrow;
    }
  }

  @override
  Future<void> close() {
    _syncEventSub?.cancel();
    return super.close();
  }
}
