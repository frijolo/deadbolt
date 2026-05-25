import 'dart:async';

import 'package:flutter/foundation.dart' show debugPrint;
import 'package:flutter/widgets.dart'
    show AppLifecycleState, WidgetsBinding, WidgetsBindingObserver;

import 'package:deadbolt/config/app_settings_extensions.dart';
import 'package:deadbolt/cubit/settings_cubit.dart';
import 'package:deadbolt/errors.dart' show sanitizeForLog, formatRustError;
import 'package:deadbolt/services/background_broadcast_scheduler.dart';
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
  /// Results of auto-broadcast attempts that ran right after this sync.
  /// Empty when no PSBTs were flagged or no timelock matured during this tick.
  final List<APIAutoBroadcastResult> autoBroadcasted;

  const WalletSyncEvent({
    required this.walletPath,
    this.balance,
    this.walletInfo,
    this.isSyncing = false,
    this.error,
    this.autoBroadcasted = const [],
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
class WalletSyncService with WidgetsBindingObserver {
  final WalletService _walletService;
  final Map<String, _SyncEntry> _entries = {};
  final _controller = StreamController<WalletSyncEvent>.broadcast();

  /// True while the app is in `paused` / `hidden` AND the grace period has
  /// elapsed. Electrum subscriptions are torn down in this state to save
  /// battery; the bg-alarm scheduler covers auto-broadcast while minimised.
  /// Subscriptions resume on `resumed` with an immediate catch-up sync.
  bool _suspended = false;

  /// Pending suspension timer. We don't cut the subscriptions the instant
  /// the app goes background — users frequently swap apps for seconds
  /// (copying an address, checking a chat) and tearing down 20+ TCP+TLS
  /// connections only to re-handshake them moments later would be wasteful
  /// (and slow on the return path). Only if the app stays in background
  /// past [_suspendGrace] do we actually disconnect.
  Timer? _suspendTimer;
  static const Duration _suspendGrace = Duration(seconds: 120);

  WalletSyncService(this._walletService) {
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    switch (state) {
      case AppLifecycleState.paused:
      case AppLifecycleState.hidden:
        // Don't suspend yet — start the grace timer. If the user comes back
        // before it fires, we never tear anything down.
        _suspendTimer ??= Timer(_suspendGrace, () {
          _suspendTimer = null;
          if (!_suspended) {
            _suspended = true;
            _pauseSubscriptions();
          }
        });
      case AppLifecycleState.resumed:
        _suspendTimer?.cancel();
        _suspendTimer = null;
        if (_suspended) {
          _suspended = false;
          unawaited(_resumeSubscriptions());
        }
      default:
    }
  }

  void _pauseSubscriptions() {
    for (final entry in _entries.values) {
      entry.sub?.cancel();
      entry.sub = null;
    }
    debugPrint(
      '[WalletSyncService] paused — cancelled ${_entries.length} subscription(s)',
    );
  }

  Future<void> _resumeSubscriptions() async {
    debugPrint(
      '[WalletSyncService] resumed — restarting ${_entries.length} subscription(s)',
    );
    for (final walletPath in _entries.keys.toList()) {
      final entry = _entries[walletPath];
      if (entry == null) continue;
      // Trigger a catch-up sync first so the UI reflects any blocks that
      // arrived while we were paused, then re-subscribe for future pushes.
      unawaited(_syncOne(walletPath));
      entry.sub = entry.handle
          .startSubscription(electrumUrl: entry.electrumUrl)
          .listen(
        (_) {
          if (!entry.isSyncing) unawaited(_syncOne(walletPath));
        },
        onError: (_) => entry.sub = null,
        onDone: () => entry.sub = null,
      );
    }
  }

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
        debugPrint('[WalletSyncService] initFromList($path): ${sanitizeForLog(e.toString())}');
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
    WidgetsBinding.instance.removeObserver(this);
    _suspendTimer?.cancel();
    _suspendTimer = null;
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

    // Subscribe to Electrum notifications (new blocks + SPK activity) —
    // unless the app is currently in background, in which case we'll spin
    // up the subscription on resume to avoid running a TCP socket per
    // wallet while minimised. Battery > push latency in that state.
    if (!_suspended) {
      entry.sub = handle
          .startSubscription(electrumUrl: electrumUrl)
          .listen(
        (_) {
          if (!entry.isSyncing) unawaited(_syncOne(walletPath));
        },
        onError: (_) => entry.sub = null,
        onDone: () => entry.sub = null,
      );
    }
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

      // Run any pending auto-broadcasts now that the chain tip is up to date.
      // Failures here must not propagate — the wallet sync itself already
      // succeeded and the next tick will retry naturally.
      List<APIAutoBroadcastResult> autoBroadcasted = const [];
      try {
        autoBroadcasted = await entry.handle
            .tryAutoBroadcastDue(electrumUrl: entry.electrumUrl);
      } catch (e) {
        debugPrint(
          '[WalletSyncService] tryAutoBroadcastDue($walletPath): '
          '${sanitizeForLog(e.toString())}',
        );
      }

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
          autoBroadcasted: autoBroadcasted,
        ));
      }
      if (autoBroadcasted.isNotEmpty) {
        // Queue changed — next pause re-evaluates the next wake.
        BackgroundBroadcastScheduler.instance.refresh();
        // When the user has the app minimised but the foreground isolate
        // happens to broadcast (via the Electrum push subscription that
        // keeps running even in background), surface the same notification
        // the bg-alarm path would have posted. In-foreground broadcasts
        // are left silent so the UI handles them.
        unawaited(notifyForegroundBroadcasts(walletPath, info.name, autoBroadcasted));
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
