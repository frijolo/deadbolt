// Background auto-broadcast scheduler (Android only).
//
// Wakes the app in the background to broadcast spaced-TX PSBTs whose
// `nLockTime` has matured. See WIP/background_broadcast_android.md.
//
// Lifecycle model:
//   - `paused` / `hidden`  → enumerate eligible wallets, schedule alarm.
//   - `resumed`             → cancel any pending alarm (foreground handles
//                             the broadcast loop via WalletSyncService).
//   - external triggers (refresh()) bump a dirty flag; the next pause
//     re-evaluates from scratch.
//
// Only DeviceKey (Type 0) wallets are eligible: they auto-unlock from
// `.wallet_key` without a user prompt. Other protection types are skipped.

import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:android_alarm_manager_plus/android_alarm_manager_plus.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:deadbolt/cubit/settings_cubit.dart';
import 'package:deadbolt/services/encryption_key_manager.dart';
import 'package:deadbolt/src/rust/api/background.dart' as bg_api;
import 'package:deadbolt/src/rust/api/model.dart';
import 'package:deadbolt/src/rust/api/wallet.dart' as wallet_api;
import 'package:deadbolt/src/rust/frb_generated.dart';
import 'package:deadbolt/utils/api_network_extensions.dart';

const int _alarmId = 0xDB01;

/// Post the "Transaction broadcast" / "Auto-broadcast failed" notification
/// for a set of results coming from the FOREGROUND `WalletSyncService`.
///
/// Only fires when the Activity is in background — when the user is in-app
/// we let the UI surface the broadcast (toast, list refresh) instead of
/// double-notifying. Android-only.
Future<void> notifyForegroundBroadcasts(
  String walletPath,
  String walletName,
  List<APIAutoBroadcastResult> results,
) async {
  if (!Platform.isAndroid) return;
  if (!BackgroundBroadcastScheduler.instance.isInBackground) return;
  if (results.isEmpty) return;
  // The bg scheduler may not have initialised the plugin in this process
  // path (no alarm has fired yet). Make sure it's ready before posting.
  await _initNotifications();
  await _notifyBroadcasts(walletPath, walletName, results);
}

/// Brand accent (matches the `Colors.orange` seed used by `AppTheme`).
const Color _brandColor = Color(0xFFFF9800);

/// Short delay used by the foreground when it schedules a wake. The bg
/// callback computes the real next delay from live wallet state.
const Duration _initialDelay = Duration(minutes: 1);

/// Minimum and maximum delay between successive bg callbacks (24h ceiling
/// acts as a heartbeat for very far-out nLockTimes).
const int _minDelaySecs = 60;
const int _maxDelaySecs = 24 * 3600;

/// Backoff used when every DeviceKey wallet failed to open this round
/// (typical cause: DB lock contention with the foreground isolate during the
/// 120s sync grace). Retry sooner than the matured-failure backoff because
/// the lock usually clears within minutes.
const int _openFailureBackoffSecs = 2 * 60;

/// SharedPreferences key for the matured-but-still-pending retry counter.
/// Persisted across alarms (each callback is a fresh isolate) so we can
/// back off when broadcasts keep failing for a tx whose nLockTime is in
/// the past (Electrum down, mempool conflict, BIP68 not yet final, etc.).
const String _kMaturedFailureCountKey = 'bgBroadcast.maturedFailureCount';

/// Exponential-ish backoff for matured-but-failed broadcasts. Capped at 1h
/// so a transient outage doesn't push the retry past the maturity heartbeat.
int _maturedBackoffSecs(int count) {
  switch (count) {
    case 0:
    case 1:
      return 5 * 60;
    case 2:
      return 15 * 60;
    case 3:
      return 30 * 60;
    default:
      return 60 * 60;
  }
}

/// Foreground-side scheduler. Singleton owned by `main.dart`.
class BackgroundBroadcastScheduler with WidgetsBindingObserver {
  BackgroundBroadcastScheduler._();
  static final BackgroundBroadcastScheduler instance =
      BackgroundBroadcastScheduler._();

  bool _initialised = false;
  bool _inBackground = false;

  /// Whether the app's Activity is currently in `paused` / `hidden` state.
  /// Used by foreground services (WalletSyncService) to decide whether to
  /// post a broadcast notification — when the user is actively in-app we
  /// stay silent and let the UI surface the result instead.
  bool get isInBackground => _inBackground;

  Future<void> init() async {
    if (!Platform.isAndroid) return;
    if (_initialised) return;
    _initialised = true;

    WidgetsBinding.instance.addObserver(this);

    try {
      await AndroidAlarmManager.initialize();
    } catch (e) {
      debugPrint('[bg-scheduler] alarm manager init FAIL: $e');
    }

    try {
      await _initNotifications();
    } catch (e) {
      debugPrint('[bg-scheduler] notifications init FAIL: $e');
    }

    try {
      final plugin = FlutterLocalNotificationsPlugin();
      final androidImpl = plugin.resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin>();
      await androidImpl?.requestNotificationsPermission();
    } catch (e) {
      debugPrint('[bg-scheduler] permission request FAIL: $e');
    }
  }

  /// Hook called after events that may change scheduler eligibility
  /// (commit, autoBroadcasted, wallet delete). Re-evaluates eligibility and
  /// (re)arms the alarm so a freshly-committed plan with a near-term
  /// nLockTime gets a wake even if the user never backgrounds the app
  /// between commit and device idle (lock-screen).
  void refresh() {
    if (!Platform.isAndroid) return;
    if (!_initialised) return;
    unawaited(_onPaused());
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (!Platform.isAndroid) return;
    switch (state) {
      case AppLifecycleState.paused:
      case AppLifecycleState.hidden:
        if (_inBackground) return;
        _inBackground = true;
        unawaited(_onPaused());
      case AppLifecycleState.resumed:
        _inBackground = false;
        unawaited(_onResumed());
      default:
    }
  }

  Future<void> _onPaused() async {
    try {
      final dir = (await getApplicationSupportDirectory()).path;
      final headers = await bg_api.listWalletHeaders(appSupportDir: dir);
      final hasDeviceKey = headers.any((h) => h.protectionType == 0);
      if (!hasDeviceKey) {
        await AndroidAlarmManager.cancel(_alarmId);
        return;
      }
      final when = DateTime.now().add(_initialDelay);
      await _scheduleAt(when);
    } catch (e) {
      debugPrint('[bg-scheduler] _onPaused error: $e');
    }
  }

  Future<void> _onResumed() async {
    try {
      await AndroidAlarmManager.cancel(_alarmId);
    } catch (_) {}
  }

  static Future<bool> _scheduleAt(DateTime when) {
    return AndroidAlarmManager.oneShotAt(
      when,
      _alarmId,
      bgBroadcastCallback,
      exact: false,
      wakeup: true,
      allowWhileIdle: true,
      rescheduleOnReboot: true,
    );
  }
}

// ---------------------------------------------------------------------------
// Background isolate entry point
// ---------------------------------------------------------------------------

@pragma('vm:entry-point')
Future<void> bgBroadcastCallback() async {
  debugPrint('[bg-scheduler] CALLBACK enter at ${DateTime.now()}');
  try {
    WidgetsFlutterBinding.ensureInitialized();
    // The bg callback may run in a FRESH isolate (process killed between
    // alarms). AndroidAlarmManager uses a per-isolate MethodChannel, so the
    // plugin must be initialised in this isolate before we can call
    // `oneShotAt` to chain the next wake. Without this the reschedule throws
    // MissingPluginException, the outer catch swallows it, and the alarm
    // chain dies until the user manually backgrounds the app again.
    try {
      await AndroidAlarmManager.initialize();
    } catch (e) {
      debugPrint('[bg-scheduler] callback AlarmManager.initialize FAIL: $e');
    }
    await _initNotifications();
    // AlarmManager may reuse the foreground isolate when the app process is
    // still alive, leaving RustLib already initialized. Skip the redundant
    // init() in that case — calling it twice throws StateError.
    if (!RustLib.instance.initialized) {
      await RustLib.init();
    }
    final dir = (await getApplicationSupportDirectory()).path;
    final keyHex = await EncryptionKeyManager().getOrCreateEncryptionKey();
    final prefs = await SharedPreferences.getInstance();

    final headers = await bg_api.listWalletHeaders(appSupportDir: dir);
    final deviceKeyWallets =
        headers.where((h) => h.protectionType == 0).toList();
    if (deviceKeyWallets.isEmpty) {
      debugPrint('[bg-scheduler] no DeviceKey wallets, exiting');
      return;
    }

    // Per-wallet wake calculation: each wallet's next wake delay is derived
    // from ITS OWN tip vs ITS OWN min locktime (different networks have wildly
    // different tip heights). We then take the minimum across all wallets.
    int? minDelaySecs;
    var pendingWallets = 0;
    var openedWallets = 0;
    var anyBroadcasted = false;
    var anyMaturedPending = false;

    for (final h in deviceKeyWallets) {
      try {
        final res = await _tickOne(h.walletPath, keyHex, prefs);
        if (res == null) continue;
        openedWallets++;
        if (res.broadcastedCount > 0) anyBroadcasted = true;
        if (res.pendingCount > 0) pendingWallets++;
        if (res.minLocktime == null) continue;
        final deltaBlocks = math.max(0, res.minLocktime! - res.tipHeight);
        if (deltaBlocks == 0 && res.pendingCount > 0) {
          // nLockTime in the past but the tx is still pending: the broadcast
          // attempt either failed (Electrum down, mempool conflict) or is
          // waiting on a BIP68 relative timelock that the bare locktime can't
          // express. Either way, retrying in 60s loops hot — apply backoff.
          anyMaturedPending = true;
        }
        final secs = (deltaBlocks * 600).clamp(_minDelaySecs, _maxDelaySecs);
        minDelaySecs =
            minDelaySecs == null ? secs : math.min(minDelaySecs, secs);
      } catch (e) {
        debugPrint('[bg-scheduler] tick failed for ${h.walletPath}: $e');
      }
    }

    // Reset the matured-failure backoff as soon as anything broadcasts.
    if (anyBroadcasted) {
      await prefs.remove(_kMaturedFailureCountKey);
    }

    // Decide whether to chain another alarm. Two reasons to reschedule:
    //   1. At least one wallet still has pending PSBTs (normal case).
    //   2. Every wallet open failed — most likely DB-lock contention with
    //      the foreground isolate. Without a retry the alarm chain would
    //      die until the user manually backgrounds the app again, so we
    //      reschedule with a short backoff to probe again.
    if (pendingWallets == 0 && openedWallets > 0) {
      debugPrint('[bg-scheduler] no pending PSBTs anywhere, no reschedule');
      return;
    }

    final int delaySecs;
    if (openedWallets == 0) {
      debugPrint('[bg-scheduler] every wallet open failed, retry in '
          '${_openFailureBackoffSecs}s');
      delaySecs = _openFailureBackoffSecs;
    } else if (anyMaturedPending && !anyBroadcasted) {
      final prev = prefs.getInt(_kMaturedFailureCountKey) ?? 0;
      final next = prev + 1;
      await prefs.setInt(_kMaturedFailureCountKey, next);
      delaySecs = _maturedBackoffSecs(next);
      debugPrint(
        '[bg-scheduler] matured-but-pending streak=$next, backoff=${delaySecs}s',
      );
    } else {
      // If we have at least one concrete future locktime, use the min delay;
      // otherwise (all pending PSBTs have lock_time=0 or rely only on BIP68
      // relative timelocks) fall back to the 24h heartbeat.
      delaySecs = minDelaySecs ?? _maxDelaySecs;
    }
    final delay = Duration(seconds: delaySecs);
    final next = DateTime.now().add(delay);
    debugPrint('[bg-scheduler] reschedule at $next (delay=$delay)');
    await BackgroundBroadcastScheduler._scheduleAt(next);
  } catch (e, st) {
    debugPrint('[bg-scheduler] CALLBACK error: $e\n$st');
  }
}

class _TickResult {
  final int tipHeight;
  final int? minLocktime;
  final int pendingCount;
  final int broadcastedCount;
  _TickResult({
    required this.tipHeight,
    required this.minLocktime,
    required this.pendingCount,
    required this.broadcastedCount,
  });
}

/// Open one DeviceKey wallet, sync, run auto-broadcast, return summary.
/// Returns `null` if the wallet could not be opened (e.g. file lock from
/// foreground isolate) — that wallet is skipped this round.
Future<_TickResult?> _tickOne(
  String walletPath,
  String deviceKeyHex,
  SharedPreferences prefs,
) async {
  late wallet_api.ApiWallet handle;
  try {
    handle = await wallet_api.openWallet(
      walletPath: walletPath,
      deviceKeyHex: deviceKeyHex,
      password: null,
      biometricKeyHex: null,
    );
  } catch (e) {
    debugPrint('[bg-scheduler] openWallet skipped $walletPath: $e');
    return null;
  }

  try {
    // Cheap probe: ask the wallet's local SQL state for pending PSBTs
    // BEFORE doing a network sync. If nothing is pending we can skip the
    // sync + broadcast attempt entirely — that's the common case for most
    // wallets, and the sync is the expensive step (1 wallet ≈ 5s).
    final preSummary = handle.autoBroadcastSummary();
    if (preSummary.pendingCount == 0) {
      return _TickResult(
        tipHeight: preSummary.tipHeight,
        minLocktime: null,
        pendingCount: 0,
        broadcastedCount: 0,
      );
    }

    final info = await handle.getInfo();
    final electrumUrl = _electrumUrlFor(info.network, prefs);
    handle.setElectrumUrl(url: electrumUrl);
    await handle.sync_(electrumUrl: electrumUrl);

    final broadcasted =
        await handle.tryAutoBroadcastDue(electrumUrl: electrumUrl);
    if (broadcasted.isNotEmpty) {
      debugPrint(
        '[bg-scheduler] $walletPath broadcasted ${broadcasted.length} tx(s)',
      );
      await _notifyBroadcasts(walletPath, info.name, broadcasted);
    }

    final summary = handle.autoBroadcastSummary();
    return _TickResult(
      tipHeight: summary.tipHeight,
      minLocktime: summary.minLocktime,
      pendingCount: summary.pendingCount,
      broadcastedCount: broadcasted.where((r) => r.txid != null).length,
    );
  } finally {
    // ApiWallet has no explicit close; dropping the last reference frees it.
    // The local `handle` goes out of scope when this function returns.
  }
}

String _electrumUrlFor(APINetwork net, SharedPreferences prefs) {
  final suffix = net.suffix;
  final key = 'electrum$suffix';
  return prefs.getString(key) ?? AppSettings.kElectrumDefaults[suffix]!;
}

// ---------------------------------------------------------------------------
// Notifications
// ---------------------------------------------------------------------------

const _kNotifChannelId = 'deadbolt_bg_broadcast';
const _kNotifChannelName = 'Background broadcasts';
const _kNotifChannelDesc =
    'Notifies when a scheduled transaction is broadcast in the background.';

/// Cached after the first init: which default icon the plugin actually
/// accepted. Notifications fall back to this when their custom icon can't
/// be resolved.
String _defaultIcon = '@mipmap/ic_launcher';

Future<void> _initNotifications() async {
  // Try the brand silhouette first; on resource-id failure (icon missing
  // from the built APK) fall back to the launcher mipmap so notifications
  // still appear (with a white square icon).
  final plugin = FlutterLocalNotificationsPlugin();
  try {
    const init = InitializationSettings(
      android: AndroidInitializationSettings('ic_stat_notification'),
    );
    await plugin.initialize(init);
    _defaultIcon = 'ic_stat_notification';
  } catch (e) {
    debugPrint('[bg-scheduler] notif custom icon REJECTED: $e — falling back to launcher');
    const fallback = InitializationSettings(
      android: AndroidInitializationSettings('@mipmap/ic_launcher'),
    );
    await plugin.initialize(fallback);
    _defaultIcon = '@mipmap/ic_launcher';
  }
}

Future<void> _notifyBroadcasts(
  String walletPath,
  String walletName,
  List<APIAutoBroadcastResult> results,
) async {
  final successes = results.where((r) => r.txid != null).toList();
  final failures = results.where((r) => r.error != null).toList();

  if (successes.isNotEmpty) {
    final title = successes.length == 1
        ? 'Transaction broadcast'
        : '${successes.length} transactions broadcast';
    final body = successes.length == 1
        ? '$walletName · ${successes.first.label?.isNotEmpty == true ? successes.first.label! : _shortTxid(successes.first.txid!)}'
        : walletName;
    final details = NotificationDetails(
      android: AndroidNotificationDetails(
        _kNotifChannelId,
        _kNotifChannelName,
        channelDescription: _kNotifChannelDesc,
        importance: Importance.defaultImportance,
        priority: Priority.defaultPriority,
        ticker: 'broadcast',
        icon: _defaultIcon,
        color: _brandColor,
      ),
    );
    final id = successes.first.txid.hashCode & 0x7fffffff;
    try {
      await FlutterLocalNotificationsPlugin().show(id, title, body, details);
    } catch (e) {
      debugPrint('[bg-scheduler] show() broadcast FAIL: $e');
    }
  }

  if (failures.isNotEmpty) {
    final title = failures.length == 1
        ? 'Auto-broadcast failed'
        : '${failures.length} auto-broadcasts failed';
    final firstErr = failures.first.error ?? '';
    final trimmed = firstErr.length > 140
        ? '${firstErr.substring(0, 137)}…'
        : firstErr;
    final body = '$walletName · $trimmed';
    final details = NotificationDetails(
      android: AndroidNotificationDetails(
        _kNotifChannelId,
        _kNotifChannelName,
        channelDescription: _kNotifChannelDesc,
        importance: Importance.defaultImportance,
        priority: Priority.defaultPriority,
        ticker: 'broadcast-fail',
        icon: _defaultIcon,
        color: _brandColor,
      ),
    );
    final id = ('fail-${failures.first.id}-$walletPath').hashCode & 0x7fffffff;
    try {
      await FlutterLocalNotificationsPlugin().show(id, title, body, details);
    } catch (e) {
      debugPrint('[bg-scheduler] show() broadcast-fail FAIL: $e');
    }
  }
}

String _shortTxid(String txid) =>
    txid.length <= 12 ? txid : '${txid.substring(0, 8)}…${txid.substring(txid.length - 4)}';

