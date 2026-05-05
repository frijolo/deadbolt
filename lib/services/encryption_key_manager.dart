import 'dart:io';
import 'dart:math';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// Manages the device encryption key (Type 0 key material).
///
/// The key is a 256-bit hex string stored in `.wallet_key` under the app
/// support directory. Generated on first call and persisted thereafter.
class EncryptionKeyManager {
  static const _keyFileName = '.wallet_key';

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

  /// Returns the app support directory path.
  Future<String> getAppSupportDir() async {
    final dir = await getApplicationSupportDirectory();
    return dir.path;
  }

  /// Returns (and creates if needed) the wallets subdirectory path.
  Future<String> getWalletsDir() async {
    final dir = await getApplicationSupportDirectory();
    final walletsDir = Directory(p.join(dir.path, 'wallets'));
    await walletsDir.create(recursive: true);
    return walletsDir.path;
  }

  String _generateSecureHex() {
    final rng = Random.secure();
    final bytes = List<int>.generate(32, (_) => rng.nextInt(256));
    return _bytesToHex(bytes);
  }

  static String _bytesToHex(List<int> bytes) =>
      bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
}
