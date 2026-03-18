import 'dart:io';
import 'dart:math';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'package:deadbolt/src/rust/api/model.dart';
import 'package:deadbolt/src/rust/api/wallet.dart' as rust_wallet;

class WalletService {
  static const _keyFileName = '.wallet_key';

  /// In-session cache: walletPath → password.
  /// Cleared when the app is terminated; never persisted to disk.
  final Map<String, String> _passwordCache = {};

  Future<File> _keyFile() async {
    final dir = await getApplicationSupportDirectory();
    return File(p.join(dir.path, _keyFileName));
  }

  /// Returns the hex device key, generating and persisting it on first call.
  Future<String> getOrCreateEncryptionKey() async {
    final file = await _keyFile();
    if (file.existsSync()) {
      final key = file.readAsStringSync().trim();
      if (key.length == 64) return key;
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
    return bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
  }

  /// Returns (and creates if needed) the wallets directory path.
  Future<String> getWalletsDir() async {
    final dir = await getApplicationSupportDirectory();
    final walletsDir = Directory(p.join(dir.path, 'wallets'));
    if (!walletsDir.existsSync()) {
      walletsDir.createSync(recursive: true);
    }
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
  /// If the wallet requires a password and none is cached, throws.
  /// Callers should catch the error and request the password from the user,
  /// then call `cachePassword` and retry.
  Future<rust_wallet.ApiWallet> openWallet(
    String walletPath, {
    String? password,
  }) async {
    final keyHex = await getOrCreateEncryptionKey();
    // Use explicitly provided password, or fall back to cache.
    final pwd = password ?? getCachedPassword(walletPath);
    return rust_wallet.openWallet(
      walletPath: walletPath,
      deviceKeyHex: keyHex,
      password: pwd,
    );
  }

  /// True if the wallet's .meta marks it as UserPassword protected.
  Future<bool> walletRequiresPassword(String walletPath) async {
    return rust_wallet.walletRequiresPassword(walletPath: walletPath);
  }
}
