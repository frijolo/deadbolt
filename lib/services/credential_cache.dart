import 'dart:typed_data';

/// In-session credential cache (RAM only, never persisted).
///
/// Holds passwords and biometric keys keyed by wallet path.
/// Cleared when the app terminates; no disk persistence.
class CredentialCache {
  final Map<String, String> _passwordCache = {};
  final Map<String, Uint8List> _biometricKeyCache = {};

  // -- Password --

  void cachePassword(String walletPath, String password) {
    _passwordCache[walletPath] = password;
  }

  String? getCachedPassword(String walletPath) => _passwordCache[walletPath];

  void evictPassword(String walletPath) {
    _passwordCache.remove(walletPath);
  }

  // -- Biometric key --

  void cacheBiometricKey(String walletPath, String keyHex) {
    evictBiometricKey(walletPath);
    final bytes = Uint8List(keyHex.length ~/ 2);
    for (var i = 0; i < bytes.length; i++) {
      bytes[i] = int.parse(keyHex.substring(i * 2, i * 2 + 2), radix: 16);
    }
    _biometricKeyCache[walletPath] = bytes;
  }

  String? getCachedBiometricKey(String walletPath) {
    final cached = _biometricKeyCache[walletPath];
    if (cached == null) return null;
    return _bytesToHex(cached);
  }

  void evictBiometricKey(String walletPath) {
    _biometricKeyCache.remove(walletPath);
  }

  // -- Query --

  bool isUnlocked(String walletPath) =>
      _passwordCache.containsKey(walletPath) ||
      _biometricKeyCache.containsKey(walletPath);

  void clearAllCredentials() {
    for (final key in [..._passwordCache.keys]) {
      evictPassword(key);
    }
    for (final key in [..._biometricKeyCache.keys]) {
      evictBiometricKey(key);
    }
  }

  static String _bytesToHex(List<int> bytes) =>
      bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
}
