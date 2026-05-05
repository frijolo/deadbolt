import 'package:deadbolt/src/rust/api/model.dart';
import 'package:deadbolt/src/rust/api/wallet.dart' as rust_wallet;
import 'package:deadbolt/services/wallet_service.dart';

/// Manages project hot-key (seed) operations via Rust FFI.
///
/// This class encapsulates all encrypted seed storage/retrieval logic,
/// keeping [ProjectDetailCubit] focused on UI state management.
class ProjectHotKeyManager {
  final WalletService _service;
  final int projectId;

  ProjectHotKeyManager(this._service, this.projectId);

  Future<String> get _appDir async => _service.getAppSupportDir();

  Future<String> get _deviceKey async => _service.getOrCreateEncryptionKey();

  /// Load all hot keys for this project from encrypted storage.
  Future<List<APIHotKeyInfo>> loadHotKeys() async {
    try {
      final appDir = await _appDir;
      final deviceKey = await _deviceKey;
      return rust_wallet.listProjectHotKeys(
        appSupportDir: appDir,
        projectId: projectId,
        deviceKeyHex: deviceKey,
      );
    } catch (_) {
      return [];
    }
  }

  /// Add a mnemonic seed as a hot key for this project.
  Future<APIHotKeyInfo> addMnemonic(
    String mnemonic, {
    String? passphrase,
    required APINetwork network,
  }) async {
    final appDir = await _appDir;
    final deviceKey = await _deviceKey;
    return rust_wallet.addProjectMnemonicKey(
      appSupportDir: appDir,
      projectId: projectId,
      mnemonic: mnemonic,
      passphrase: passphrase,
      network: network,
      deviceKeyHex: deviceKey,
    );
  }

  /// Add an xprv as a hot key for this project.
  Future<APIHotKeyInfo> addXprv(String xprv) async {
    final appDir = await _appDir;
    final deviceKey = await _deviceKey;
    return rust_wallet.addProjectXprvKey(
      appSupportDir: appDir,
      projectId: projectId,
      xprv: xprv,
      deviceKeyHex: deviceKey,
    );
  }

  /// Delete a hot key by MFP.
  Future<void> delete(String mfp) async {
    final appDir = await _appDir;
    final deviceKey = await _deviceKey;
    rust_wallet.deleteProjectHotKey(
      appSupportDir: appDir,
      projectId: projectId,
      mfp: mfp,
      deviceKeyHex: deviceKey,
    );
  }

  /// Reveal the seed for a hot key by MFP.
  Future<String?> reveal(String mfp) async {
    final appDir = await _appDir;
    final deviceKey = await _deviceKey;
    return rust_wallet.revealProjectSeed(
      appSupportDir: appDir,
      projectId: projectId,
      mfp: mfp,
      deviceKeyHex: deviceKey,
    );
  }
}
