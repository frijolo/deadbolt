// Deadbolt — Hardware Wallet Platform Abstraction
//
// Device connection (desktop/Android), pairing confirmation, disconnect,
// and the Android USB dispatch loop.

import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

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
  void returnToReady() {
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
    // Ensure USB permission is granted
    bool hasPermission = await AndroidHwChannel.requestPermission(deviceName);
    if (!hasPermission) {
      // Permission dialog was shown; wait briefly and re-check
      await Future<void>.delayed(const Duration(seconds: 1));
      hasPermission = await AndroidHwChannel.requestPermission(deviceName);
    }
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
      AndroidHwChannel.closeDevice();
    }
    emit(HwWalletIdle());
  }

  // ── Android dispatch loop ─────────────────────────────────────────────────

  /// Wraps [operation] with the USB dispatch loop on Android; passes it
  /// through unchanged on other platforms.
  ///
  /// This method is also called by [HwWalletProtocol] operations when they
  /// need to run a Rust FFI call through the USB dispatch loop on Android.
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

    protocolFuture.then(completer.complete).catchError((Object e, StackTrace st) {
      completer.completeError(e, st);
    });

    while (!completer.isCompleted) {
      final outgoing = await rust_hw.androidHwPollWritePacket();

      if (outgoing == null) {
        // Nothing pending — yield briefly.
        await Future<void>.delayed(const Duration(milliseconds: 1));
        continue;
      }

      if (outgoing.isEmpty) {
        // Read-needed sentinel: Rust is blocking on a USB read.
        if (!completer.isCompleted) {
          final incoming = await AndroidHwChannel.readPacket();
          await rust_hw.androidHwDeliverReadPacket(data: incoming);
        }
        continue;
      }

      // Non-empty: write this 64-byte HID packet to USB.
      await AndroidHwChannel.writePacket(Uint8List.fromList(outgoing));
    }

    return completer.future;
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
    } catch (_) {
      // Fall back to placeholder if session info is unavailable
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
