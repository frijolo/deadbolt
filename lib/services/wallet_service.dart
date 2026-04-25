import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import '../utils/hex_utils.dart';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'package:deadbolt/src/rust/api/model.dart';
import 'package:deadbolt/src/rust/api/wallet.dart' as rust_wallet;

class WalletService {
  static const _keyFileName = '.wallet_key';

  /// In-session cache: walletPath → password.
  /// Cleared when the app is terminated; never persisted to disk.
  final Map<String, String> _passwordCache = {};

  /// In-session cache: walletPath → biometric key hex.
  /// Allows re-opening a biometrically-protected wallet within the same session
  /// without triggering the hardware biometric prompt again.
  /// Same RAM-exposure risk as password caching; cleared on app termination.
  final Map<String, Uint8List> _biometricKeyCache = {};

  Future<File> _keyFile() async {
    final dir = await getApplicationSupportDirectory();
    return File(p.join(dir.path, _keyFileName));
  }

  /// Returns the hex device key, generating and persisting it on first call.
  Future<String> getOrCreateEncryptionKey() async {
    final file = await _keyFile();
    try {
      final key = (await file.readAsString()).trim();
      if (key.length == 64) return key;
    } on FileSystemException {
      // File does not exist yet; fall through to generate.
    }

    final key = _generateSecureHex();
    await file.writeAsString(key, flush: true);
    if (!Platform.isWindows) {
      await Process.run('chmod', ['600', file.path]);
    }
    return key;
  }

  String _generateSecureHex() {
    final rng = Random.secure();
    final bytes = List<int>.generate(32, (_) => rng.nextInt(256));
    return bytesToHex(bytes);
  }

  /// Returns the app support directory path.
  Future<String> getAppSupportDir() async {
    final dir = await getApplicationSupportDirectory();
    return dir.path;
  }

  /// Returns (and creates if needed) the wallets directory path.
  Future<String> getWalletsDir() async {
    final dir = await getApplicationSupportDirectory();
    final walletsDir = Directory(p.join(dir.path, 'wallets'));
    await walletsDir.create(recursive: true);
    return walletsDir.path;
  }

  // ---------------------------------------------------------------------------
  // Password cache
  // ---------------------------------------------------------------------------

  /// Store a password for this wallet path in the session cache.
  void cachePassword(String walletPath, String password) {
    _passwordCache[walletPath] = password;
  }

  /// Retrieve the cached password for a wallet, or null if not cached.
  String? getCachedPassword(String walletPath) => _passwordCache[walletPath];

  /// Remove a cached password (e.g. on wallet delete).
  void evictPassword(String walletPath) {
    _passwordCache.remove(walletPath);
  }

  // ---------------------------------------------------------------------------
  // Biometric key cache
  // ---------------------------------------------------------------------------

  void cacheBiometricKey(String walletPath, String keyHex) {
    evictBiometricKey(walletPath);
    // Decode once to binary so we store 32 bytes, not 64 ASCII chars.
    final bytes = Uint8List(keyHex.length ~/ 2);
    for (var i = 0; i < bytes.length; i++) {
      bytes[i] = int.parse(keyHex.substring(i * 2, i * 2 + 2), radix: 16);
    }
    _biometricKeyCache[walletPath] = bytes;
  }

  String? getCachedBiometricKey(String walletPath) {
    final cached = _biometricKeyCache[walletPath];
    if (cached == null) return null;
    return bytesToHex(cached);
  }

  void evictBiometricKey(String walletPath) {
    _biometricKeyCache.remove(walletPath);
  }

  /// Securely clears all cached passwords and biometric keys for all wallets.
  void clearAllCredentials() {
    for (final key in [..._passwordCache.keys]) {
      evictPassword(key);
    }
    for (final key in [..._biometricKeyCache.keys]) {
      evictBiometricKey(key);
    }
  }


  /// Returns true if a credential of any kind is cached for this wallet,
  /// meaning the wallet is already unlocked in this session.
  bool isUnlocked(String walletPath) =>
      _passwordCache.containsKey(walletPath) ||
      _biometricKeyCache.containsKey(walletPath);

  // ---------------------------------------------------------------------------
  // Wallet CRUD
  // ---------------------------------------------------------------------------

  Future<List<APIWalletInfo>> listWallets() async {
    final walletsDir = await getWalletsDir();
    final keyHex = await getOrCreateEncryptionKey();
    return rust_wallet.listWallets(
      walletsDir: walletsDir,
      encryptionKeyHex: keyHex,
    );
  }

  Future<APIWalletInfo> createWallet({
    required String name,
    required String descriptor,
    required APINetwork network,
    APIProtectionType protectionType = APIProtectionType.deviceKey,
    String? password,
    APISecurityLevel securityLevel = APISecurityLevel.standard,
  }) async {
    final walletsDir = await getWalletsDir();
    final keyHex = await getOrCreateEncryptionKey();
    return rust_wallet.createWallet(
      walletsDir: walletsDir,
      name: name.isEmpty ? 'Unnamed wallet' : name,
      descriptor: descriptor,
      network: network,
      deviceKeyHex: keyHex,
      protectionType: protectionType,
      password: password,
      securityLevel: securityLevel,
    );
  }

  Future<APIWalletInfo> getWalletInfo(String walletPath) async {
    final keyHex = await getOrCreateEncryptionKey();
    final password = getCachedPassword(walletPath);
    return rust_wallet.getWalletInfo(
      walletPath: walletPath,
      deviceKeyHex: keyHex,
      password: password,
    );
  }

  Future<void> renameWallet(String walletPath, String name) async {
    final keyHex = await getOrCreateEncryptionKey();
    final password = getCachedPassword(walletPath);
    await rust_wallet.renameWallet(
      walletPath: walletPath,
      name: name,
      deviceKeyHex: keyHex,
      password: password,
    );
  }

  Future<void> deleteWallet(String walletPath) async {
    evictPassword(walletPath);
    await rust_wallet.deleteWallet(walletPath: walletPath);
  }

  /// Open a wallet once — returns a live handle for balance/tx/sync calls.
  ///
  /// Credential resolution order:
  ///   1. Explicit [password] (also stored in cache for subsequent calls).
  ///   2. Cached password (UserPassword / XpubKey wallets).
  ///   3. Cached biometric key (wallets unlocked via hardware keystore this session).
  ///
  /// If no credential is available and the wallet requires one, Rust throws —
  /// callers should catch that, prompt the user, then call [cachePassword] or
  /// [cacheBiometricKey] and retry.
  Future<rust_wallet.ApiWallet> openWallet(
    String walletPath, {
    String? password,
  }) async {
    final keyHex = await getOrCreateEncryptionKey();
    if (password != null) cachePassword(walletPath, password);
    return rust_wallet.openWallet(
      walletPath: walletPath,
      deviceKeyHex: keyHex,
      password: getCachedPassword(walletPath),
      biometricKeyHex: getCachedBiometricKey(walletPath),
    );
  }

  /// True if the wallet requires a credential (password or xpub) to open.
  Future<bool> walletRequiresPassword(String walletPath) async {
    return rust_wallet.walletRequiresPassword(walletPath: walletPath);
  }

  /// True if the wallet uses XpubKey protection.
  Future<bool> walletRequiresXpub(String walletPath) async {
    return rust_wallet.walletRequiresXpub(walletPath: walletPath);
  }

  // ---------------------------------------------------------------------------
  // Biometric wallet slots
  // ---------------------------------------------------------------------------

  /// Adds a biometric slot to the wallet's .meta file.
  /// [biometricKeyHex] is the random 32-byte key already stored in secure
  /// storage. [currentCredential] is the wallet's existing password or xpub
  /// (may be omitted if already cached).
  /// Returns the slot ID to be used as the keystore key name.
  Future<String> addBiometricSlot({
    required String walletPath,
    required String biometricKeyHex,
    String? currentCredential,
  }) async {
    final keyHex = await getOrCreateEncryptionKey();
    return rust_wallet.addBiometricSlot(
      walletPath: walletPath,
      deviceKeyHex: keyHex,
      currentCredential: currentCredential ?? getCachedPassword(walletPath),
      biometricKeyHex: biometricKeyHex,
    );
  }

  /// Removes a biometric slot from the wallet's .meta file by ID.
  Future<void> removeBiometricSlot({
    required String walletPath,
    required String biometricId,
  }) =>
      rust_wallet.removeBiometricSlot(
        walletPath: walletPath,
        biometricId: biometricId,
      );

  /// Lists the biometric slot IDs registered for this wallet.
  Future<List<APIBiometricSlot>> listBiometricSlots(String walletPath) =>
      rust_wallet.listBiometricSlots(walletPath: walletPath);

  /// Returns true if the wallet has at least one biometric slot registered.
  Future<bool> hasBiometricSlots(String walletPath) =>
      rust_wallet.walletHasBiometricSlots(walletPath: walletPath);

  /// Add a new xpub slot to a XpubKey-protected wallet.
  Future<void> addXpubSlot({
    required String walletPath,
    required String mfp,
    required String xpub,
    required String currentXpub,
  }) async {
    final keyHex = await getOrCreateEncryptionKey();
    await rust_wallet.addXpubSlot(
      walletPath: walletPath,
      newMfp: mfp,
      newXpub: xpub,
      deviceKeyHex: keyHex,
      currentXpub: currentXpub,
    );
  }

  /// Remove an xpub slot by MFP from a XpubKey-protected wallet.
  Future<void> removeXpubSlot({
    required String walletPath,
    required String mfp,
  }) async {
    await rust_wallet.removeXpubSlot(walletPath: walletPath, mfp: mfp);
  }

  /// List registered xpub slots for a XpubKey-protected wallet.
  Future<List<APIXpubSlot>> listXpubSlots(String walletPath) async {
    return rust_wallet.listXpubSlots(walletPath: walletPath);
  }
}
