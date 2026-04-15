import 'package:local_auth/local_auth.dart';

class BiometricService {
  final LocalAuthentication _auth = LocalAuthentication();

  /// Returns true if the device supports biometric or device-credential auth.
  Future<bool> isAvailable() async {
    if (!await _auth.isDeviceSupported()) return false;
    final enrolled = await _auth.getAvailableBiometrics();
    return enrolled.isNotEmpty;
  }

  /// Cancels any in-progress authentication prompt.
  Future<bool> stop() => _auth.stopAuthentication();

  /// Prompts the user to authenticate. Falls back to device PIN/pattern/password
  /// via DEVICE_CREDENTIAL when biometrics fail or are unavailable.
  Future<bool> authenticate(String localizedReason) async {
    return _auth.authenticate(
      localizedReason: localizedReason,
      options: const AuthenticationOptions(
        // biometricOnly: false allows device credential (PIN/pattern/password) as fallback
        biometricOnly: false,
        // stickyAuth keeps the prompt alive when the app briefly loses focus
        stickyAuth: true,
      ),
    );
  }
}
