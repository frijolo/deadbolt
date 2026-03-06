import 'dart:io';
import 'dart:math';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'package:deadbolt/src/rust/api/model.dart';
import 'package:deadbolt/src/rust/api/wallet.dart' as rust_wallet;

class WalletService {
  static const _keyFileName = '.wallet_key';

  Future<File> _keyFile() async {
    final dir = await getApplicationSupportDirectory();
    return File(p.join(dir.path, _keyFileName));
  }

  /// Returns the hex encryption key, generating and persisting it on first call.
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
    int? sourceProjectId,
  }) async {
    final walletsDir = await getWalletsDir();
    final keyHex = await getOrCreateEncryptionKey();
    return rust_wallet.createWallet(
      walletsDir: walletsDir,
      name: name.isEmpty ? 'Unnamed wallet' : name,
      descriptor: descriptor,
      network: network,
      sourceProjectId: sourceProjectId,
      encryptionKeyHex: keyHex,
    );
  }

  Future<APIWalletInfo> getWalletInfo(String walletPath) async {
    final keyHex = await getOrCreateEncryptionKey();
    return rust_wallet.getWalletInfo(
      walletPath: walletPath,
      encryptionKeyHex: keyHex,
    );
  }

  Future<void> renameWallet(String walletPath, String name) async {
    final keyHex = await getOrCreateEncryptionKey();
    await rust_wallet.renameWallet(
      walletPath: walletPath,
      name: name,
      encryptionKeyHex: keyHex,
    );
  }

  Future<void> deleteWallet(String walletPath) async {
    await rust_wallet.deleteWallet(walletPath: walletPath);
  }

  /// Open a wallet once — returns a live handle for balance/tx/sync calls.
  Future<rust_wallet.ApiWallet> openWallet(String walletPath) async {
    final keyHex = await getOrCreateEncryptionKey();
    return rust_wallet.openWallet(
      walletPath: walletPath,
      encryptionKeyHex: keyHex,
    );
  }
}
