import 'credential_cache.dart';
import 'encryption_key_manager.dart';

import 'package:deadbolt/src/rust/api/model.dart';
import 'package:deadbolt/src/rust/api/wallet.dart' as rust_wallet;

class WalletService {
  final CredentialCache credentialCache;
  final EncryptionKeyManager encryptionKeyManager;

  WalletService({
    CredentialCache? credentialCache,
    EncryptionKeyManager? encryptionKeyManager,
  })  : credentialCache = credentialCache ?? CredentialCache(),
        encryptionKeyManager = encryptionKeyManager ?? EncryptionKeyManager();

  // ---------------------------------------------------------------------------
  // Delegates — CredentialCache
  // ---------------------------------------------------------------------------

  void cachePassword(String walletPath, String password) =>
      credentialCache.cachePassword(walletPath, password);

  String? getCachedPassword(String walletPath) =>
      credentialCache.getCachedPassword(walletPath);

  void evictPassword(String walletPath) =>
      credentialCache.evictPassword(walletPath);

  void cacheBiometricKey(String walletPath, String keyHex) =>
      credentialCache.cacheBiometricKey(walletPath, keyHex);

  String? getCachedBiometricKey(String walletPath) =>
      credentialCache.getCachedBiometricKey(walletPath);

  void evictBiometricKey(String walletPath) =>
      credentialCache.evictBiometricKey(walletPath);

  void clearAllCredentials() => credentialCache.clearAllCredentials();

  bool isUnlocked(String walletPath) =>
      credentialCache.isUnlocked(walletPath);

  // ---------------------------------------------------------------------------
  // Delegates — EncryptionKeyManager
  // ---------------------------------------------------------------------------

  Future<String> getOrCreateEncryptionKey() async =>
      encryptionKeyManager.getOrCreateEncryptionKey();

  Future<String> getAppSupportDir() async =>
      encryptionKeyManager.getAppSupportDir();

  Future<String> getWalletsDir() async =>
      encryptionKeyManager.getWalletsDir();

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
