import 'dart:async';

import 'package:flutter/foundation.dart' show debugPrint;

import 'package:deadbolt/cubit/settings_cubit.dart';
import 'package:deadbolt/errors.dart';
import 'package:deadbolt/services/wallet_service.dart';
import 'package:deadbolt/src/rust/api/model.dart';
import 'package:deadbolt/src/rust/api/wallet.dart' show ApiWallet;

// ---------------------------------------------------------------------------
// Event
// ---------------------------------------------------------------------------

class WalletSyncEvent {
  final String walletPath;
  final APIBalance? balance;       // null when sync is in progress
  final APIWalletInfo? walletInfo; // null when sync is in progress
  final bool isSyncing;
  final String? error;             // non-null on sync failure

  const WalletSyncEvent({
    required this.walletPath,
    this.balance,
    this.walletInfo,
    this.isSyncing = false,
    this.error,
  });
}

// ---------------------------------------------------------------------------
// Private entry
// ---------------------------------------------------------------------------

class _SyncEntry {
  final ApiWallet handle;
  final String electrumUrl;
  StreamSubscription<bool>? sub;
  bool isSyncing = false;

  _SyncEntry(this.handle, this.electrumUrl);
}

// ---------------------------------------------------------------------------
// Service
// ---------------------------------------------------------------------------

/// Global singleton that owns open wallet handles and Electrum subscriptions
/// for all unlocked wallets. It is the only caller of [ApiWallet.sync_].
///
/// Consumers (WalletListCubit, WalletDetailCubit) listen to [events] to
/// receive balance/sync updates without ever calling sync themselves.
class WalletSyncService {
  final WalletService _walletService;
  final Map<String, _SyncEntry> _entries = {};
  final _controller = StreamController<WalletSyncEvent>.broadcast();

  WalletSyncService(this._walletService);

  /// Broadcast stream of sync events. Never errors; events are dropped if
  /// no listener is attached (broadcast semantics).
  Stream<WalletSyncEvent> get events => _controller.stream;

  bool isTracked(String walletPath) => _entries.containsKey(walletPath);

  // -------------------------------------------------------------------------
  // Public API
  // -------------------------------------------------------------------------

  /// Open and subscribe to every unlocked wallet not yet tracked.
  /// Idempotent: already-tracked wallets are skipped.
  /// Called by WalletListScreen when the wallet list loads.
  Future<void> initFromList(
    List<APIWalletInfo> wallets,
    AppSettings settings,
  ) async {
    for (final wallet in wallets) {
      final path = wallet.walletPath;
      if (_entries.containsKey(path)) continue;
      if (wallet.protection.needsPassword &&
          _walletService.getCachedPassword(path) == null) {
        continue;
      }

      final url = settings.electrumUrlForNetwork(wallet.network);
      try {
        final handle = await _walletService.openWallet(path);
        await _startTracking(path, handle, url);
      } catch (e) {
        // Log and continue — a single bad wallet must not block the others.
        debugPrint('[WalletSyncService] initFromList($path): $e');
      }
    }
  }

  /// Register a handle opened by WalletDetailCubit, replacing any previous
  /// entry for the same wallet. Starts a new subscription and emits an
  /// initial balance event immediately.
  Future<void> registerHandle(
    String walletPath,
    ApiWallet handle,
    String electrumUrl,
  ) async {
    // Cancel and drop any existing subscription for this wallet.
    final existing = _entries.remove(walletPath);
    existing?.sub?.cancel();
    await _startTracking(walletPath, handle, electrumUrl);
  }

  /// Trigger an immediate sync for a single wallet.
  /// No-op if the wallet is not tracked or already syncing.
  Future<void> syncWallet(String walletPath) async {
    final entry = _entries[walletPath];
    if (entry == null || entry.isSyncing) return;
    await _syncOne(walletPath);
  }

  /// Stop tracking a wallet (on delete or lock).
  /// Cancels the subscription; the handle becomes eligible for GC.
  void untrack(String walletPath) {
    final entry = _entries.remove(walletPath);
    entry?.sub?.cancel();
  }

  /// Cancel all subscriptions and close the event stream.
  /// Should be called only when the service itself is disposed.
  void dispose() {
    for (final e in _entries.values) {
      e.sub?.cancel();
    }
    _entries.clear();
    _controller.close();
  }

  // -------------------------------------------------------------------------
  // Private
  // -------------------------------------------------------------------------

  Future<void> _startTracking(
    String walletPath,
    ApiWallet handle,
    String electrumUrl,
  ) async {
    final entry = _SyncEntry(handle, electrumUrl);
    _entries[walletPath] = entry;

    // Store the Electrum URL on the handle so detail queries (address lookup,
    // tx details) can use it before the first sync completes.
    handle.setElectrumUrl(url: electrumUrl);

    // Emit initial balance and decide if an immediate sync is needed.
    // Both are local BDK cache reads — run them in parallel.
    final balanceFuture = handle.getBalance()
        .then<APIBalance?>((b) => b)
        .onError((_, _) => null);
    final infoFuture = handle.getInfo()
        .then<APIWalletInfo?>((i) => i)
        .onError((_, _) => null);
    final (balance, info) = await (balanceFuture, infoFuture).wait;

    if (balance != null && !_controller.isClosed) {
      _controller.add(WalletSyncEvent(
        walletPath: walletPath,
        balance: balance,
        isSyncing: false,
      ));
    }

    final ts = info?.lastSyncedAt;
    final needsSync = ts == null ||
        DateTime.now().difference(
              DateTime.fromMillisecondsSinceEpoch(ts * 1000),
            ) >
            const Duration(hours: 1);
    if (needsSync) unawaited(_syncOne(walletPath));

    // Subscribe to Electrum notifications (new blocks + SPK activity).
    entry.sub = handle
        .startSubscription(electrumUrl: electrumUrl)
        .listen(
      (_) {
        if (!entry.isSyncing) unawaited(_syncOne(walletPath));
      },
      onError: (_) => entry.sub = null,
      onDone: () => entry.sub = null,
    );
    // Guard: if untrack() was called during the awaits above, the entry is
    // no longer in _entries — cancel the subscription we just started.
    if (!_entries.containsKey(walletPath)) {
      entry.sub?.cancel();
    }
  }

  Future<void> _syncOne(String walletPath) async {
    final entry = _entries[walletPath];
    if (entry == null || entry.isSyncing) return;

    entry.isSyncing = true;
    if (!_controller.isClosed) {
      _controller.add(WalletSyncEvent(
        walletPath: walletPath,
        isSyncing: true,
      ));
    }

    try {
      await entry.handle.sync_(electrumUrl: entry.electrumUrl);
      final (balance, info) = await (
        entry.handle.getBalance(),
        entry.handle.getInfo(),
      ).wait;

      if (!_controller.isClosed) {
        _controller.add(WalletSyncEvent(
          walletPath: walletPath,
          balance: balance,
          walletInfo: info,
          isSyncing: false,
        ));
      }
    } catch (e) {
      if (!_controller.isClosed) {
        _controller.add(WalletSyncEvent(
          walletPath: walletPath,
          isSyncing: false,
          error: formatRustError(e),
        ));
      }
    } finally {
      entry.isSyncing = false;
    }
  }
}
