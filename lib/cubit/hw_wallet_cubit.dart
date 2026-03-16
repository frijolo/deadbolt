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

// ─── States ───────────────────────────────────────────────────────────────────

sealed class HwWalletState {}

/// No device connected or scanned.
class HwWalletIdle extends HwWalletState {}

/// Scanning for connected devices.
class HwWalletScanning extends HwWalletState {}

/// Devices found, waiting for the user to pick one.
class HwWalletDevicesFound extends HwWalletState {
  final List<APIHwDevice> devices;
  HwWalletDevicesFound(this.devices);
}

/// Connecting / pairing in progress.
class HwWalletConnecting extends HwWalletState {}

/// Pairing code available — show it to the user and wait for device confirm.
class HwWalletPairing extends HwWalletState {
  final String sessionId;
  final String pairingCode;
  HwWalletPairing({required this.sessionId, required this.pairingCode});
}

/// Waiting for device to confirm the pairing (user already sees the code).
class HwWalletConfirming extends HwWalletState {
  final String sessionId;
  final String pairingCode;
  HwWalletConfirming({required this.sessionId, required this.pairingCode});
}

/// Device is connected and ready for operations.
class HwWalletReady extends HwWalletState {
  final String sessionId;
  final String productString;
  final String rootFingerprint;
  HwWalletReady({
    required this.sessionId,
    required this.productString,
    required this.rootFingerprint,
  });
}

/// An operation (sign/register/get xpub) is in progress.
class HwWalletOperating extends HwWalletState {
  final String sessionId;
  final String productString;
  final String rootFingerprint;
  final String operationLabel;
  HwWalletOperating({
    required this.sessionId,
    required this.productString,
    required this.rootFingerprint,
    required this.operationLabel,
  });
}

/// Operation completed — carries the result.
sealed class HwWalletResult {}

class HwXpubResult extends HwWalletResult {
  final String descriptorKey; // "[mfp/path]xpub..."
  HwXpubResult(this.descriptorKey);
}

class HwSignedPsbtResult extends HwWalletResult {
  final String signedPsbtBase64;
  HwSignedPsbtResult(this.signedPsbtBase64);
}

class HwRegisteredResult extends HwWalletResult {}

class HwCheckRegistrationResult extends HwWalletResult {
  final bool isRegistered;
  HwCheckRegistrationResult(this.isRegistered);
}

class HwAddressDisplayedResult extends HwWalletResult {}

class HwWalletDone extends HwWalletState {
  final String sessionId;
  final String productString;
  final String rootFingerprint;
  final HwWalletResult result;
  HwWalletDone({
    required this.sessionId,
    required this.productString,
    required this.rootFingerprint,
    required this.result,
  });
}

class HwWalletError extends HwWalletState {
  final String message;
  final String? sessionId; // present if a session exists but errored
  HwWalletError({required this.message, this.sessionId});
}

// ─── Cubit ────────────────────────────────────────────────────────────────────

class HwWalletCubit extends Cubit<HwWalletState> {
  HwWalletCubit() : super(HwWalletIdle());

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

  /// Transitions back to [HwWalletReady] after an operation completes,
  /// keeping the sheet open for further actions.
  void returnToReady() {
    final s = state;
    if (s is HwWalletDone) {
      emit(HwWalletReady(
        sessionId: s.sessionId,
        productString: s.productString,
        rootFingerprint: s.rootFingerprint,
      ));
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

  // ── BTC operations ────────────────────────────────────────────────────────

  Future<void> getXpub({
    required String sessionId,
    required String productString,
    required String rootFingerprint,
    required String derivationPath,
    required APINetwork network,
  }) async {
    emit(HwWalletOperating(
      sessionId: sessionId,
      productString: productString,
      rootFingerprint: rootFingerprint,
      operationLabel: 'Exporting xpub…',
    ));
    try {
      final xpub = await _callHw(rust_hw.hwGetXpub(
        sessionId: sessionId,
        derivationPath: derivationPath,
        network: network,
      ));
      emit(HwWalletDone(
        sessionId: sessionId,
        productString: productString,
        rootFingerprint: rootFingerprint,
        result: HwXpubResult(xpub),
      ));
    } catch (e) {
      emit(HwWalletError(message: formatRustError(e), sessionId: sessionId));
    }
  }

  Future<void> registerDescriptor({
    required String sessionId,
    required String productString,
    required String rootFingerprint,
    required String walletName,
    required String policy,
    APINetwork network = APINetwork.bitcoin,
  }) async {
    emit(HwWalletOperating(
      sessionId: sessionId,
      productString: productString,
      rootFingerprint: rootFingerprint,
      operationLabel: 'Registering wallet on device…',
    ));
    try {
      await _callHw(rust_hw.hwRegisterDescriptor(
        sessionId: sessionId,
        walletName: walletName,
        policy: policy,
        network: network,
      ));
      emit(HwWalletDone(
        sessionId: sessionId,
        productString: productString,
        rootFingerprint: rootFingerprint,
        result: HwRegisteredResult(),
      ));
    } catch (e) {
      emit(HwWalletError(message: formatRustError(e), sessionId: sessionId));
    }
  }

  Future<void> checkRegistration({
    required String sessionId,
    required String productString,
    required String rootFingerprint,
    required String descriptor,
    APINetwork network = APINetwork.bitcoin,
  }) async {
    emit(HwWalletOperating(
      sessionId: sessionId,
      productString: productString,
      rootFingerprint: rootFingerprint,
      operationLabel: 'Checking registration…',
    ));
    try {
      final isRegistered = await _callHw(rust_hw.hwCheckRegistration(
        sessionId: sessionId,
        descriptor: descriptor,
        network: network,
      ));
      emit(HwWalletDone(
        sessionId: sessionId,
        productString: productString,
        rootFingerprint: rootFingerprint,
        result: HwCheckRegistrationResult(isRegistered),
      ));
    } catch (e) {
      emit(HwWalletError(message: formatRustError(e), sessionId: sessionId));
    }
  }

  Future<void> displayAddress({
    required String sessionId,
    required String productString,
    required String rootFingerprint,
    required String descriptor,
    required APINetwork network,
    required APIKeychain keychain,
    required int index,
  }) async {
    emit(HwWalletOperating(
      sessionId: sessionId,
      productString: productString,
      rootFingerprint: rootFingerprint,
      operationLabel: 'Confirm address on device…',
    ));
    try {
      await _callHw(rust_hw.hwDisplayAddress(
        sessionId: sessionId,
        descriptor: descriptor,
        network: network,
        keychain: keychain,
        index: index,
      ));
      emit(HwWalletDone(
        sessionId: sessionId,
        productString: productString,
        rootFingerprint: rootFingerprint,
        result: HwAddressDisplayedResult(),
      ));
    } catch (e) {
      emit(HwWalletError(message: formatRustError(e), sessionId: sessionId));
    }
  }

  Future<void> signPsbt({
    required String sessionId,
    required String productString,
    required String rootFingerprint,
    required String psbtBase64,
    required APINetwork network,
    String? descriptor,
  }) async {
    emit(HwWalletOperating(
      sessionId: sessionId,
      productString: productString,
      rootFingerprint: rootFingerprint,
      operationLabel: 'Confirm on device…',
    ));
    try {
      final signed = await _callHw(rust_hw.hwSignPsbt(
        sessionId: sessionId,
        psbtBase64: psbtBase64,
        network: network,
        descriptor: descriptor,
      ));
      emit(HwWalletDone(
        sessionId: sessionId,
        productString: productString,
        rootFingerprint: rootFingerprint,
        result: HwSignedPsbtResult(signed),
      ));
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
  Future<T> _callHw<T>(Future<T> operation) =>
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
