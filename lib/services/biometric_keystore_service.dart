import 'dart:math';

import 'package:biometric_storage/biometric_storage.dart';

import '../utils/hex_utils.dart';

/// Manages the platform-keystore side of biometric wallet slots.
///
/// Each biometric slot in the wallet's .meta file has a corresponding entry
/// here, stored using [BiometricStorage] — which on Android uses the Android
/// Keystore with `setUserAuthenticationRequired(true)`, and on iOS/macOS uses
/// Keychain with `kSecAccessControlBiometryCurrentSet`.
///
/// This means decrypting the stored key is a hardware-enforced operation: the
/// OS security chip verifies biometrics before allowing the cipher to run.
/// This is stronger than a simple app-level gate — the key cannot be read
/// without passing through the platform's biometric hardware even if the app
/// process is compromised (e.g. memory dump on a non-rooted device).
///
/// Security note: On a device with an unlocked bootloader or a custom OS, the
/// hardware security guarantees may be reduced. This risk is documented in the
/// UI and is equivalent to the risk of storing a cached password in RAM.
class BiometricKeystoreService {
  static String _storageName(String biometricId) =>
      'deadbolt_biometric_$biometricId';

  static final _initOptions = StorageFileInitOptions(
    // Require authentication on every use — no validity window.
    authenticationValidityDurationSeconds: -1,
    authenticationRequired: true,
    // Only real biometrics; disallow PIN/pattern/password fallback.
    // This is required when authenticationValidityDurationSeconds == -1.
    androidBiometricOnly: true,
    // Use .biometryCurrentSet: invalidates the entry if the enrolled
    // biometrics change (new fingerprint added, etc.).
    darwinBiometricOnly: true,
  );

  /// Returns true if the device has biometric hardware and enrolled biometrics.
  /// On Linux/desktop the answer is always false (no biometric hardware).
  Future<bool> isAvailable() async {
    final result = await BiometricStorage().canAuthenticate();
    return result == CanAuthenticateResponse.success;
  }

  /// Generates a random 32-byte hex key (64 hex chars) without storing it.
  /// Pass this to [WalletService.addBiometricSlot], then call [storeKey] with
  /// the slot ID returned by Rust to persist the key under the correct ID.
  String generateKey() {
    final rng = Random.secure();
    final keyBytes = List.generate(32, (_) => rng.nextInt(256));
    return bytesToHex(keyBytes);
  }

  /// Stores [keyHex] in hardware-backed biometric storage under [biometricId].
  /// [biometricId] must be the ID returned by Rust after registering the slot.
  /// This operation requires biometric authentication (the platform shows the
  /// biometric prompt as part of the write).
  Future<void> storeKey(
    String biometricId,
    String keyHex,
    PromptInfo promptInfo,
  ) async {
    final storage = await BiometricStorage().getStorage(
      _storageName(biometricId),
      options: _initOptions,
    );
    await storage.write(keyHex, promptInfo: promptInfo);
  }

  /// Reads the biometric key from hardware-backed storage.
  /// The platform's biometric hardware will enforce authentication before
  /// returning the key — [promptInfo] configures the OS-level prompt strings.
  /// Returns null if the entry does not exist, hardware is unavailable, or
  /// the user cancels / fails authentication.
  Future<String?> retrieveKey(
    String biometricId,
    PromptInfo promptInfo,
  ) async {
    try {
      final storage = await BiometricStorage().getStorage(
        _storageName(biometricId),
        options: _initOptions,
      );
      return await storage.read(promptInfo: promptInfo);
    } on AuthException {
      return null;
    } catch (_) {
      return null;
    }
  }

  /// Deletes the biometric key from the platform keystore.
  /// Does not require biometric authentication.
  Future<void> deleteKey(String biometricId) async {
    try {
      final storage = await BiometricStorage().getStorage(
        _storageName(biometricId),
        // No authentication required to delete — the user is already
        // authenticated at the app level when they disable biometric unlock.
        options: StorageFileInitOptions(authenticationRequired: false),
      );
      await storage.delete();
    } catch (_) {
      // Ignore: if the entry is already gone, that's fine.
    }
  }
}
