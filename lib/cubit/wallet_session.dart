import 'package:flutter/foundation.dart' show debugPrint;

import 'package:deadbolt/src/rust/api/model.dart' show APINetwork;
import 'package:deadbolt/src/rust/api/wallet.dart' show ApiWallet, getWalletNetworkHint;
import 'package:biometric_storage/biometric_storage.dart' show PromptInfo, AndroidPromptInfo, IosPromptInfo;
import 'package:deadbolt/services/biometric_keystore_service.dart';
import 'package:deadbolt/services/wallet_service.dart';
import 'package:deadbolt/errors.dart' show sanitizeForLog;
import 'package:deadbolt/utils/api_network_extensions.dart';

/// Result of credential resolution during wallet load.
class WalletLoadCredentialResult {
  /// The wallet handle if a credential was found and used to open the wallet.
  final ApiWallet? handle;

  /// True when the wallet needs password authentication.
  final bool needsPassword;

  /// True when the wallet uses XpubKey protection (prompts for xpub, not password).
  final bool isXpubKey;

  /// Network hint read from the .meta sidecar. Null when unavailable.
  final APINetwork? network;

  WalletLoadCredentialResult({
    this.handle,
    this.needsPassword = false,
    this.isXpubKey = false,
    this.network,
  });
}

/// Module that owns wallet session lifecycle: open, lock, biometric unlock.
///
/// All methods receive the current cubit state and wallet handle as parameters,
/// perform the operation, and return a result object. The cubit is responsible
/// for emitting state updates based on the returned result.
class WalletSession {
  final WalletService _service;
  final BiometricKeystoreService _keystoreService;

  WalletSession({
    required WalletService service,
    required BiometricKeystoreService keystoreService,
  })  : _service = service,
        _keystoreService = keystoreService;

  /// Resolve credentials and open the wallet.
  ///
  /// Returns a [WalletLoadCredentialResult] that tells the cubit what to do next:
  /// - [handle] is non-null: wallet opened successfully, cubit should emit WalletDetailLoaded
  /// - [needsPassword] is true + [handle] is null: cubit should emit WalletDetailNeedsPassword
  ///
  /// The [biometricUnlockReason] parameter provides a localized string for the
  /// biometric prompt. When provided and the wallet has biometric slots, biometric
  /// unlock is attempted before falling back to the password prompt.
  Future<WalletLoadCredentialResult> loadCredential({
    required String walletPath,
    String? password,
    String? biometricUnlockReason,
  }) async {
    // Cache provided password immediately so getCachedPassword sees it.
    if (password != null) {
      _service.cachePassword(walletPath, password);
    }

    // If no credential cached yet, check upfront whether one is required.
    final isUnlocked = _service.isUnlocked(walletPath);
    if (isUnlocked) {
      // Wallet is already unlocked (device key or cached credential) — open it.
      try {
        final handle = await _service.openWallet(walletPath);
        return WalletLoadCredentialResult(handle: handle);
      } catch (_) {
        // Cached credential did not open the wallet (e.g. wrong password just
        // provided). Evict so the next attempt re-prompts instead of looping
        // on the same bad credential.
        _service.evictPassword(walletPath);
        _service.evictBiometricKey(walletPath);
        rethrow;
      }
    }

    // Check both flags in parallel — each reads the .meta sidecar once.
    final (needsPassword, isXpubKey) = await (
      _service.walletRequiresPassword(walletPath),
      _service.walletRequiresXpub(walletPath),
    ).wait;

    if (needsPassword) {
      // Attempt hardware biometric unlock before showing the password prompt.
      if (biometricUnlockReason != null) {
        final handle = await _tryBiometricUnlock(walletPath, biometricUnlockReason);
        if (handle != null) {
          return WalletLoadCredentialResult(handle: handle);
        }
      }

      // No credential available — ask for password.
      APINetwork? network;
      if (isXpubKey) {
        final hint = await getWalletNetworkHint(walletPath: walletPath);
        network = apiNetworkFromName(hint);
      }
      return WalletLoadCredentialResult(
        needsPassword: true,
        isXpubKey: isXpubKey,
        network: network,
      );
    }

    // Wallet doesn't need password — open with device key.
    final handle = await _service.openWallet(walletPath);
    return WalletLoadCredentialResult(handle: handle);
  }

  /// Evict all cached credentials so the wallet will require re-authentication.
  void lockWallet(String walletPath) {
    _service.evictPassword(walletPath);
    _service.evictBiometricKey(walletPath);
  }

  /// Enables biometric unlock for the currently loaded wallet.
  ///
  /// Returns true on success, false on failure (error is logged by the cubit).
  Future<WalletBiometricResult> enableBiometricSlot({
    required String walletPath,
    required PromptInfo promptInfo,
  }) async {
    try {
      final keyHex = _keystoreService.generateKey();
      final slotId = await _service.addBiometricSlot(
        walletPath: walletPath,
        biometricKeyHex: keyHex,
      );
      try {
        await _keystoreService.storeKey(slotId, keyHex, promptInfo);
      } catch (e, _) {
        // Rollback: remove the Rust slot so .meta stays consistent.
        await _service.removeBiometricSlot(
          walletPath: walletPath,
          biometricId: slotId,
        );
        rethrow;
      }
      return WalletBiometricResult(hasBiometricSlot: true, errorMessage: null);
    } catch (e, _) {
      return WalletBiometricResult(
        hasBiometricSlot: false,
        errorMessage: 'WalletSession.enableBiometricSlot: $e',
      );
    }
  }

  /// Disables all biometric unlock slots for the currently loaded wallet.
  Future<WalletBiometricResult> disableAllBiometricSlots(
    String walletPath,
  ) async {
    try {
      final slots = await _service.listBiometricSlots(walletPath);
      for (final slot in slots) {
        await _service.removeBiometricSlot(
          walletPath: walletPath,
          biometricId: slot.id,
        );
        await _keystoreService.deleteKey(slot.id);
      }
      return WalletBiometricResult(hasBiometricSlot: false, errorMessage: null);
    } catch (e, _) {
      return WalletBiometricResult(
        hasBiometricSlot: false,
        errorMessage: 'WalletSession.disableAllBiometricSlots: $e',
      );
    }
  }

  /// Attempts to open the wallet using a registered biometric slot.
  Future<ApiWallet?> _tryBiometricUnlock(
    String walletPath,
    String localizedReason,
  ) async {
    try {
      if (!await _keystoreService.isAvailable()) return null;
      if (!await _service.hasBiometricSlots(walletPath)) return null;
      final slots = await _service.listBiometricSlots(walletPath);
      final promptInfo = PromptInfo(
        androidPromptInfo: AndroidPromptInfo(
          title: localizedReason,
          negativeButton: 'Cancel',
        ),
        iosPromptInfo: IosPromptInfo(accessTitle: localizedReason),
        macOsPromptInfo: IosPromptInfo(accessTitle: localizedReason),
      );
      for (final slot in slots) {
        final key = await _keystoreService.retrieveKey(slot.id, promptInfo);
        if (key == null) continue;
        try {
          _service.cacheBiometricKey(walletPath, key);
          return await _service.openWallet(walletPath);
        } catch (_) {
          _service.evictBiometricKey(walletPath);
          continue;
        }
      }
    } catch (e, st) {
      debugPrint('[WalletSession] biometric unlock failed: ${sanitizeForLog(e.toString())}\n${sanitizeForLog(st.toString())}');
    }
    return null;
  }
}

/// Result of biometric slot operations.
class WalletBiometricResult {
  final bool hasBiometricSlot;
  final String? errorMessage;

  WalletBiometricResult({
    required this.hasBiometricSlot,
    this.errorMessage,
  });
}
