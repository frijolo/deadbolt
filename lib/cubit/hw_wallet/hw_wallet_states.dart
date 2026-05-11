import 'package:deadbolt/src/rust/api/model.dart';

// Deadbolt — Hardware Wallet States

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
