import 'dart:async';

import 'package:biometric_storage/biometric_storage.dart' show PromptInfo;

import 'package:deadbolt/cubit/wallet_detail_session.dart'
    show
        WalletDetailView,
        WalletInfo,
        TransactionPage,
        AddressView,
        CoinView,
        DescriptorView,
        PsbtList,
        FiatPrices,
        WalletLoadResult,
        WalletLoadSuccess,
        WalletLoadNeedsPassword;
import 'package:deadbolt/cubit/loaded_wallet.dart' show LoadedWalletImpl, analyzeAllPsbts;
import 'package:deadbolt/cubit/wallet_op_result.dart';
import 'package:deadbolt/cubit/wallet_session.dart' show WalletSession;
import 'package:deadbolt/services/biometric_keystore_service.dart'
    show BiometricKeystoreService;
import 'package:deadbolt/services/wallet_service.dart' show WalletService;
import 'package:deadbolt/services/wallet_sync_service.dart'
    show WalletSyncService;
import 'package:deadbolt/src/rust/api/model.dart'
    show
        APIHotKeyInfo,
        APIKeychain,
        APINetwork,
        APIProtectionType,
        APIPsbtAnalysis,
        APIPsbtInfo,
        APIPubKey,
        APISecurityLevel,
        APIWalletProtection;
import 'package:deadbolt/src/rust/api/wallet.dart'
    show ApiWallet, getWalletNetworkHint;
import 'package:deadbolt/utils/api_network_extensions.dart';

/// Pre-handle wallet operations: credential resolution, locking, biometric
/// slot management, and protection changes. Owns the [WalletSession] and
/// brokers all access to [WalletService] for the credential cache and
/// encryption key.
///
/// This is the seam the cubit crosses when a wallet has not yet been opened
/// (no [ApiWallet] handle). Once a [WalletLoadSuccess] is returned, the cubit
/// keeps the handle and crosses [LoadedWallet]'s seam for everything else.
abstract class WalletOpener {
  /// Resolve credentials for [walletPath] and, on success, build the initial
  /// snapshot used to populate [WalletDetailLoaded]. When credentials are
  /// missing, returns [WalletLoadNeedsPassword] with the network hint and
  /// xpub flag already resolved (the cubit no longer needs to re-fetch them).
  Future<WalletLoadResult> load({
    required String walletPath,
    String? password,
    String? biometricUnlockReason,
  });

  /// Evict cached credentials and untrack the wallet from the sync service.
  void lock(String walletPath);

  /// Register a new biometric slot. Returns the resulting `hasBiometricSlot`
  /// flag; an [Err] indicates the operation failed (e.g. user cancelled).
  Future<WalletOpResult<bool>> enableBiometricSlot({
    required String walletPath,
    required PromptInfo promptInfo,
  });

  /// Remove every biometric slot for [walletPath].
  Future<WalletOpResult<bool>> disableAllBiometricSlots(String walletPath);

  /// Apply a protection change as a single transaction: derive the device
  /// encryption key, call into the Rust handle, then refresh the credential
  /// cache (evict biometric, evict/cache password) so the in-memory state
  /// stays consistent with the on-disk wallet. On failure, returns [Err]
  /// (no silent `false` — see R13 in the refactor plan).
  ///
  /// [xpubKeys] is consulted only when [newProtectionType] is
  /// [APIProtectionType.xpubKey]: the first xpub becomes the new cached
  /// credential. When empty, the password cache is evicted.
  Future<WalletOpResult<APIWalletProtection>> changeProtection({
    required String walletPath,
    required ApiWallet handle,
    required APIProtectionType newProtectionType,
    String? newPassword,
    required APISecurityLevel securityLevel,
    List<APIPubKey>? xpubKeys,
  });

  /// Rename the wallet on disk. Requires the wallet to be unlocked (the
  /// service uses the cached credential to open the encrypted DB).
  Future<void> renameWallet({
    required String walletPath,
    required String name,
  });
}

class WalletOpenerImpl implements WalletOpener {
  final WalletService _service;
  final WalletSyncService _syncService;
  final WalletSession _session;

  WalletOpenerImpl({
    required WalletService service,
    required WalletSyncService syncService,
    BiometricKeystoreService? keystoreService,
  })  : _service = service,
        _syncService = syncService,
        _session = WalletSession(
          service: service,
          keystoreService: keystoreService ?? BiometricKeystoreService(),
        );

  @override
  Future<WalletLoadResult> load({
    required String walletPath,
    String? password,
    String? biometricUnlockReason,
  }) async {
    final credentialResult = await _session.loadCredential(
      walletPath: walletPath,
      password: password,
      biometricUnlockReason: biometricUnlockReason,
    );

    if (credentialResult.needsPassword) {
      APINetwork? network;
      if (credentialResult.isXpubKey) {
        final hint = await getWalletNetworkHint(walletPath: walletPath);
        network = apiNetworkFromName(hint);
      }
      return WalletLoadNeedsPassword(
        isXpubKey: credentialResult.isXpubKey,
        network: network,
      );
    }

    final handle = credentialResult.handle!;
    final view = await _buildInitialSnapshot(walletPath, handle);
    return WalletLoadSuccess(view, LoadedWalletImpl(handle));
  }

  @override
  void lock(String walletPath) {
    _session.lockWallet(walletPath);
    _syncService.untrack(walletPath);
  }

  @override
  Future<WalletOpResult<bool>> enableBiometricSlot({
    required String walletPath,
    required PromptInfo promptInfo,
  }) async {
    final result = await _session.enableBiometricSlot(
      walletPath: walletPath,
      promptInfo: promptInfo,
    );
    if (result.errorMessage != null) {
      return Err(result.errorMessage!);
    }
    return Ok(result.hasBiometricSlot);
  }

  @override
  Future<WalletOpResult<bool>> disableAllBiometricSlots(
    String walletPath,
  ) async {
    final result = await _session.disableAllBiometricSlots(walletPath);
    if (result.errorMessage != null) {
      return Err(result.errorMessage!);
    }
    return Ok(result.hasBiometricSlot);
  }

  @override
  Future<WalletOpResult<APIWalletProtection>> changeProtection({
    required String walletPath,
    required ApiWallet handle,
    required APIProtectionType newProtectionType,
    String? newPassword,
    required APISecurityLevel securityLevel,
    List<APIPubKey>? xpubKeys,
  }) {
    return guardAsync(
      () async {
        final keyHex = await _service.getOrCreateEncryptionKey();
        await handle.changeProtection(
          deviceKeyHex: keyHex,
          newProtectionType: newProtectionType,
          newPassword: newPassword,
          securityLevel: securityLevel,
        );

        _service.evictBiometricKey(walletPath);
        switch (newProtectionType) {
          case APIProtectionType.deviceKey:
            _service.evictPassword(walletPath);
          case APIProtectionType.userPassword:
            if (newPassword != null) {
              _service.cachePassword(walletPath, newPassword);
            }
          case APIProtectionType.xpubKey:
            if (xpubKeys != null && xpubKeys.isNotEmpty) {
              _service.cachePassword(walletPath, xpubKeys.first.xpub);
            } else {
              _service.evictPassword(walletPath);
            }
        }

        return APIWalletProtection(
          protectionType: newProtectionType,
          needsPassword: switch (newProtectionType) {
            APIProtectionType.deviceKey => false,
            APIProtectionType.userPassword => true,
            APIProtectionType.xpubKey => true,
          },
          securityLevel: securityLevel,
        );
      },
      tag: 'WalletOpener.changeProtection',
    );
  }

  @override
  Future<void> renameWallet({
    required String walletPath,
    required String name,
  }) {
    return _service.renameWallet(walletPath, name);
  }

  /// Build the initial [WalletDetailView] right after a successful credential
  /// resolution. Uses parallel `.wait` for the chain reads, then sequential
  /// reads for layers that benefit from a warm cache.
  Future<WalletDetailView> _buildInitialSnapshot(
    String walletPath,
    ApiWallet handle,
  ) async {
    const pageSize = 25;
    final (walletInfo, balance, txPage, tipHeight) = await (
      handle.getInfo(),
      handle.getBalance(),
      handle.getTransactions(page: 0, pageSize: pageSize),
      handle.getTipHeight(),
    ).wait;

    final receiveAddrs =
        await handle.getAddresses(keychain: APIKeychain.external_);
    final changeAddrs =
        await handle.getAddresses(keychain: APIKeychain.internal);
    final utxos = await handle.getUtxos();

    List<APIPsbtInfo> psbts;
    Map<int, APIPsbtAnalysis> analyses;
    try {
      psbts = await handle.listPsbts();
      analyses = await analyzeAllPsbts(handle, psbts);
    } catch (_) {
      psbts = [];
      analyses = {};
    }

    List<APIHotKeyInfo> hotKeys;
    try {
      final result = handle.listHotKeys();
      hotKeys = result.keys;
    } catch (_) {
      hotKeys = [];
    }

    bool hasBioSlot;
    try {
      hasBioSlot = await _service.hasBiometricSlots(walletPath);
    } catch (_) {
      hasBioSlot = false;
    }

    return WalletDetailView(
      info: WalletInfo(
        walletInfo: walletInfo,
        balance: balance,
        hasBiometricSlot: hasBioSlot,
        tipHeight: tipHeight,
      ),
      transactions: TransactionPage(
        transactions: txPage.transactions,
        totalCount: txPage.totalCount,
        hasMore: txPage.hasMore,
        currentPage: 0,
      ),
      addresses: AddressView(
        receiveAddresses: receiveAddrs,
        changeAddresses: changeAddrs,
        receiveLoaded: true,
        changeLoaded: true,
        selectedKeychain: 0,
      ),
      coins: CoinView(utxos: utxos, loaded: true),
      descriptor:
          const DescriptorView(keyLabels: {}, pathLabels: {}, loaded: false),
      psbts: PsbtList(psbts: psbts, analyses: analyses, loaded: true),
      hotKeys: hotKeys,
      fiat: const FiatPrices(prices: {}),
    );
  }

}
