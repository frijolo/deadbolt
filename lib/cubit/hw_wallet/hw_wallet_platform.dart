// Deadbolt — Hardware Wallet Platform Abstraction
//
// Device connection (desktop/Android), pairing confirmation, disconnect,
// and the Android USB dispatch loop.

import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'package:deadbolt/errors.dart';
import 'package:deadbolt/services/android_hw_channel.dart';
import 'package:deadbolt/src/rust/api/hw_wallet.dart' as rust_hw;
import 'package:deadbolt/src/rust/api/model.dart';

import 'hw_wallet_states.dart';

/// Mixin que aporta conexión, pairing, disconnect y dispatch loop.
///
/// Los métodos de esta mixin se mezclan directamente en [HwWalletCubit]
/// para que `emit` y `state` estén disponibles sin referencia explícita.
mixin HwWalletPlatform on Cubit<HwWalletState> {
  // ── USB lifecycle subscription (Android only) ─────────────────────────────

  StreamSubscription<HwUsbEvent>? _usbEventsSub;
  AppLifecycleListener? _lifecycleListener;

  /// Set to true when a detach is observed mid-operation so [_runWithDispatch]
  /// can exit cleanly instead of looping on stale channels. Also gates
  /// [returnToReady] so a fatal session loss never restores a Ready state.
  bool _detachCanceled = false;

  /// Initialises platform-level listeners (USB attach/detach on Android,
  /// app lifecycle for stale-session detection).
  /// Safe to call multiple times; subsequent calls are no-ops.
  void initPlatform() {
    if (!Platform.isAndroid) return;
    _usbEventsSub ??= AndroidHwChannel.events.listen(_onUsbEvent);
    _lifecycleListener ??= AppLifecycleListener(
      onResume: () => unawaited(_validateSessionOnResume()),
    );
  }

  Future<void> disposePlatform() async {
    await _usbEventsSub?.cancel();
    _usbEventsSub = null;
    _lifecycleListener?.dispose();
    _lifecycleListener = null;
  }

  /// Validates the active session on app resume.
  ///
  /// A detach/retach that happens while the app is backgrounded can leave the
  /// Kotlin side closed (via the broadcast receiver) without Dart ever seeing
  /// the event — or worse, with the device replugged under a new
  /// `/dev/bus/usb/00X/0YY` path. Either way the cubit's cached session is
  /// stale. We probe the plugin's liveness and, if dead, force a clean
  /// disconnect so the UI returns to a scannable state instead of failing on
  /// the next USB op.
  Future<void> _validateSessionOnResume() async {
    if (!Platform.isAndroid) return;
    final s = state;
    final hasSession =
        s is HwWalletReady || s is HwWalletOperating || s is HwWalletDone;
    if (!hasSession) return;
    final alive = await AndroidHwChannel.isSessionAlive().catchError((_) => false);
    if (alive) return;
    _invalidateSession('Hardware wallet was disconnected');
  }

  void _onUsbEvent(HwUsbEvent event) {
    switch (event) {
      case HwUsbDetached(:final wasOpen):
        if (wasOpen) _invalidateSession('Hardware wallet disconnected');
    }
  }

  /// Drops Rust+Kotlin transport state without touching cubit state.
  ///
  /// Invariant: any path that detects a dead transport (detach event, resume
  /// liveness probe, NOT_OPEN/DEVICE_DETACHED from the dispatch loop) must go
  /// through here so Rust+Kotlin stay in sync. `closeDevice` is unawaited and
  /// best-effort — by the time we reach here the device is already gone.
  void _invalidateTransport() {
    _detachCanceled = true;
    rust_hw.hwInvalidateActiveSession();
    unawaited(AndroidHwChannel.closeDevice().catchError((_) {}));
  }

  /// Drops transport state and emits a terminal [HwWalletError].
  void _invalidateSession(String message) {
    _invalidateTransport();
    if (isClosed) return;
    emit(HwWalletError(message: message));
  }

  // ── Session restore ───────────────────────────────────────────────────────

  /// Checks if a HW session is already active in Rust. If so, emits
  /// [HwWalletReady] immediately; otherwise scans for connected devices.
  Future<void> restoreOrScan() async {
    final info = rust_hw.hwActiveSession();
    if (info != null) {
      emit(HwWalletReady(
        sessionId: info.sessionId,
        productString: info.productString,
        rootFingerprint: info.rootFingerprint,
      ));
    } else {
      await scanDevices();
    }
  }

  /// Transitions back to [HwWalletReady] after an operation completes or errors,
  /// keeping the sheet open for further actions.
  ///
  /// Never restores Ready when [_detachCanceled] is true — a transport-level
  /// failure (detach, NOT_OPEN, etc.) invalidates the cached session, and
  /// pretending we're still connected would just produce another failure on
  /// the next op.
  void returnToReady() {
    if (_detachCanceled) return;
    final s = state;
    if (s is HwWalletDone) {
      emit(HwWalletReady(
        sessionId: s.sessionId,
        productString: s.productString,
        rootFingerprint: s.rootFingerprint,
      ));
    } else if (s is HwWalletError && s.sessionId != null) {
      // Session still exists after an operation error — restore ready state.
      unawaited(_emitReady(s.sessionId!));
    }
  }

  // ── Scanning ─────────────────────────────────────────────────────────────

  Future<void> scanDevices() async {
    _detachCanceled = false;
    emit(HwWalletScanning());
    try {
      final List<APIHwDevice> devices;
      if (Platform.isAndroid) {
        final androidDevices = await AndroidHwChannel.listDevices();
        devices = androidDevices
            .map((d) => APIHwDevice(
                  devicePath: d['deviceName'] ?? '',
                  productString: d['productName'] ?? 'BitBox02',
                  serialNumber: d['serialNumber'] ?? '',
                ))
            .toList();
      } else {
        devices = rust_hw.listHwDevices();
      }

      emit(HwWalletDevicesFound(devices));
    } catch (e) {
      emit(HwWalletError(message: formatRustError(e)));
    }
  }

  // ── Connection ────────────────────────────────────────────────────────────

  Future<void> connectDevice(String devicePath) async {
    _detachCanceled = false;
    emit(HwWalletConnecting());
    try {
      if (Platform.isAndroid) {
        await _connectAndroid(devicePath);
      } else {
        await _connectDesktop(devicePath);
      }
    } catch (e) {
      emit(HwWalletError(message: formatRustError(e)));
    }
  }

  Future<void> _connectDesktop(String devicePath) async {
    final noiseDir = await _noiseDir();
    final result = await rust_hw.connectHwDevice(
      devicePath: devicePath,
      noiseDir: noiseDir,
    );

    if (result.pairingCode != null) {
      // Show code and immediately start waiting for device-side confirmation.
      // The code appears on the BitBox screen as soon as wait_confirm is called,
      // so both screens show the code simultaneously — no button needed.
      emit(HwWalletPairing(
        sessionId: result.sessionId,
        pairingCode: result.pairingCode!,
      ));
      await _waitConfirm(result.sessionId, result.pairingCode!);
    } else {
      await _emitReady(result.sessionId);
    }
  }

  Future<void> _connectAndroid(String deviceName) async {
    _detachCanceled = false;
    // Awaits the permission broadcast on the Kotlin side (or its 60 s
    // timeout). Returns true only after the user actually accepts.
    final hasPermission = await AndroidHwChannel.requestPermission(deviceName);
    if (!hasPermission) {
      emit(HwWalletError(
        message: 'USB permission not granted. '
            'Please allow access when prompted and try again.',
      ));
      return;
    }

    // Open the USB HID device in Kotlin and flush any stale buffered packets.
    await AndroidHwChannel.openDevice(deviceName);
    await AndroidHwChannel.drainUsbBuffer();

    final noiseDir = await _noiseDir();

    // Run the Rust protocol and the USB dispatch loop concurrently.
    // The protocol future will block internally waiting on channels;
    // the dispatch loop pumps those channels.
    final protocolFuture = rust_hw.connectHwDeviceAndroid(
      deviceName: deviceName,
      noiseDir: noiseDir,
      productString: 'BitBox02',
    );

    final result = await _runWithDispatch(protocolFuture);

    if (result.pairingCode != null) {
      emit(HwWalletPairing(
        sessionId: result.sessionId,
        pairingCode: result.pairingCode!,
      ));
      await _waitConfirm(result.sessionId, result.pairingCode!);
    } else {
      await _emitReady(result.sessionId);
    }
  }

  // ── Pairing confirmation ───────────────────────────────────────────────────

  /// Starts waiting for the device to confirm the pairing code.
  ///
  /// Called automatically after the pairing code is shown — no user button
  /// press needed. The code appears on both the app and device simultaneously.
  Future<void> _waitConfirm(String sessionId, String pairingCode) async {
    emit(HwWalletConfirming(sessionId: sessionId, pairingCode: pairingCode));
    try {
      if (Platform.isAndroid) {
        await _runWithDispatch(
          rust_hw.waitHwPairingAndroid(sessionId: sessionId),
        );
      } else {
        await rust_hw.waitHwPairing(sessionId: sessionId);
      }
      await _emitReady(sessionId);
    } catch (e) {
      emit(HwWalletError(message: formatRustError(e), sessionId: sessionId));
    }
  }

  // ── Disconnect ────────────────────────────────────────────────────────────

  void disconnect([String? sessionId]) {
    final sid = sessionId ?? _currentSessionId();
    if (sid != null) {
      rust_hw.hwDisconnect(sessionId: sid);
    }
    if (Platform.isAndroid) {
      _detachCanceled = false;
      AndroidHwChannel.closeDevice();
    }
    emit(HwWalletIdle());
  }

  // ── Android dispatch loop ─────────────────────────────────────────────────

  /// Wraps [operation] with the USB dispatch loop on Android; passes it
  /// through unchanged on other platforms.
  ///
  /// Provides the implementation for the abstract [HwWalletProtocol.callHw]
  /// when both mixins are mixed into [HwWalletCubit].
  Future<T> callHw<T>(Future<T> operation) =>
      Platform.isAndroid ? _runWithDispatch(operation) : operation;

  /// Runs [protocolFuture] while concurrently pumping the USB I/O channels.
  ///
  /// Rust signals intent via `write_tx`:
  ///   - Non-empty vec → USB HID packet to write.
  ///   - Empty vec      → read-needed sentinel: Rust is now blocking on a USB
  ///                      read; Dart must read a packet and deliver it.
  ///
  /// This sentinel-based protocol correctly handles multi-packet U2F frames:
  /// U2fHidCommunication may call write() N times (all enqueued synchronously),
  /// then read() M times. Each read() call enqueues an empty sentinel so the
  /// dispatch loop knows to read USB rather than waiting for a new write.
  Future<T> _runWithDispatch<T>(Future<T> protocolFuture) async {
    final completer = Completer<T>();

    // Guarded completion: the dispatch loop may complete the completer first
    // via _handleDispatchPlatformError (e.g. on a USB write error); the
    // protocol future may then resolve with its own error and race here.
    protocolFuture.then((value) {
      if (!completer.isCompleted) completer.complete(value);
    }).catchError((Object e, StackTrace st) {
      if (!completer.isCompleted) completer.completeError(e, st);
    });

    while (!completer.isCompleted) {
      if (_detachCanceled) {
        // Device was unplugged mid-operation. Stop pumping channels; the
        // operation will surface its own error once it observes the broken
        // transport (or when the user retries from a clean state).
        completer.completeError(
          PlatformException(code: 'DEVICE_DETACHED', message: 'Hardware wallet disconnected'),
        );
        break;
      }

      final outgoing = await rust_hw.androidHwPollWritePacket();

      if (outgoing == null) {
        // Nothing pending — yield briefly. Rust is between sentinels (computing
        // the next message), which is typically sub-millisecond, so 5 ms is
        // imperceptible while keeping FFI poll churn at ~200/s instead of ~1000/s.
        await Future<void>.delayed(const Duration(milliseconds: 5));
        continue;
      }

      if (outgoing.isEmpty) {
        // Read-needed sentinel: Rust is blocking on a USB read.
        if (!completer.isCompleted) {
          try {
            final incoming = await AndroidHwChannel.readPacket();
            await rust_hw.androidHwDeliverReadPacket(data: incoming);
          } on PlatformException catch (e, st) {
            _handleDispatchPlatformError(e, st, completer);
            break;
          }
        }
        continue;
      }

      // Non-empty: write this 64-byte HID packet to USB.
      try {
        await AndroidHwChannel.writePacket(Uint8List.fromList(outgoing));
      } on PlatformException catch (e, st) {
        _handleDispatchPlatformError(e, st, completer);
        break;
      }
    }

    return completer.future;
  }

  /// Maps Kotlin-side USB errors to dispatch-loop outcomes.
  ///
  /// - `READ_CANCELED`: triggered by [closeActiveConnection] (detach handler or
  ///   explicit close). The detach handler has already invalidated state and
  ///   emitted an error; here we just unwind without surfacing a second one.
  /// - `DEVICE_DETACHED`: the connection went away while the worker thread was
  ///   blocked on bulkTransfer. Invalidate Rust state and surface a clear
  ///   error so the cubit returns to a scannable state.
  /// - anything else: propagate as-is.
  void _handleDispatchPlatformError<T>(
    PlatformException e,
    StackTrace st,
    Completer<T> completer,
  ) {
    switch (e.code) {
      case 'READ_CANCELED':
        if (!completer.isCompleted) {
          completer.completeError(
            PlatformException(code: 'READ_CANCELED', message: 'Operation canceled'),
            st,
          );
        }
        return;
      case 'DEVICE_DETACHED':
      case 'NOT_OPEN':
        // NOT_OPEN means Kotlin closed the connection out-of-band (typically
        // a backgrounded detach the EventChannel missed). Same teardown as
        // an explicit detach; the awaiting operation will emit HwWalletError.
        _invalidateTransport();
        if (!completer.isCompleted) completer.completeError(e, st);
        return;
      default:
        if (!completer.isCompleted) completer.completeError(e, st);
    }
  }

  // ── Helpers ───────────────────────────────────────────────────────────────

  String? _currentSessionId() {
    return switch (state) {
      HwWalletPairing(sessionId: final s) => s,
      HwWalletConfirming(sessionId: final s) => s,
      HwWalletReady(sessionId: final s) => s,
      HwWalletOperating(sessionId: final s) => s,
      HwWalletDone(sessionId: final s) => s,
      HwWalletError(sessionId: final s) => s,
      _ => null,
    };
  }

  /// Reads product string and root fingerprint from the connected session
  /// (stored in Rust) and emits HwWalletReady.
  Future<void> _emitReady(String sessionId) async {
    try {
      final info = rust_hw.getHwSessionInfo(sessionId: sessionId);
      emit(HwWalletReady(
        sessionId: sessionId,
        productString: info.productString,
        rootFingerprint: info.rootFingerprint,
      ));
    } catch (e) {
      emit(HwWalletReady(
        sessionId: sessionId,
        productString: 'BitBox02',
        rootFingerprint: '',
      ));
    }
  }

  Future<String> _noiseDir() async {
    final appDir = await getApplicationSupportDirectory();
    final dir = Directory(p.join(appDir.path, 'hw_pairing'));
    dir.createSync(recursive: true);
    return dir.path;
  }
}
