import 'package:biometric_storage/biometric_storage.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import 'package:deadbolt/cubit/cubit_error_logger.dart';
import 'package:deadbolt/cubit/wallet_detail/lifecycle.dart';
import 'package:deadbolt/cubit/wallet_detail_session.dart' show WalletInfo;
import 'package:deadbolt/cubit/wallet_detail_state.dart';
import 'package:deadbolt/cubit/wallet_op_result.dart' show Ok, Err;
import 'package:deadbolt/errors.dart' show formatRustError;
import 'package:deadbolt/src/rust/api/model.dart';

/// Biometric slot enable/disable + protection-tier change (DeviceKey /
/// UserPassword / XpubKey).
mixin WalletDetailProtection
    on Cubit<WalletDetailState>, CubitErrorLogger, WalletDetailLifecycle {
  Future<bool> enableBiometricSlot(String walletPath, PromptInfo promptInfo) async {
    final s = loadedState;
    if (s == null) return false;
    final result = await opener.enableBiometricSlot(
      walletPath: walletPath,
      promptInfo: promptInfo,
    );
    final hasSlot = switch (result) {
      Ok(:final value) => value,
      Err(:final message) => () {
          final err = loadedState;
          if (err != null) emit(err.copyWith(errorMessage: message));
          return false;
        }(),
    };
    final after = loadedState;
    if (after != null) {
      emit(after.copyWith(
        info: WalletInfo(
          walletInfo: s.walletInfo,
          balance: s.balance,
          hasBiometricSlot: hasSlot,
          tipHeight: s.tipHeight,
        ),
      ));
    }
    return hasSlot;
  }

  Future<bool> disableAllBiometricSlots(String walletPath) async {
    final s = loadedState;
    if (s == null) return false;
    final result = await opener.disableAllBiometricSlots(walletPath);
    final hasSlot = switch (result) {
      Ok(:final value) => value,
      Err(:final message) => () {
          final err = loadedState;
          if (err != null) emit(err.copyWith(errorMessage: message));
          return false;
        }(),
    };
    final after = loadedState;
    if (after != null) {
      emit(after.copyWith(
        info: WalletInfo(
          walletInfo: s.walletInfo,
          balance: s.balance,
          hasBiometricSlot: hasSlot,
          tipHeight: s.tipHeight,
        ),
      ));
    }
    return hasSlot;
  }

  Future<bool> changeProtection({
    required APIProtectionType newProtectionType,
    String? newPassword,
    APISecurityLevel securityLevel = APISecurityLevel.standard,
  }) async {
    final current = loadedState;
    if (current == null) return false;

    final result = await opener.changeProtection(
      walletPath: current.walletInfo.walletPath,
      handle: current.walletHandle,
      newProtectionType: newProtectionType,
      newPassword: newPassword,
      securityLevel: securityLevel,
      xpubKeys: current.descriptorAnalysis?.keys,
    );

    switch (result) {
      case Err(:final message):
        final err = loadedState;
        if (err != null) emit(err.copyWith(errorMessage: message));
        return false;
      case Ok(:final value):
        final updatedInfo = APIWalletInfo(
          walletPath: current.walletInfo.walletPath,
          name: current.walletInfo.name,
          descriptor: current.walletInfo.descriptor,
          network: current.walletInfo.network,
          createdAt: current.walletInfo.createdAt,
          lastSyncedAt: current.walletInfo.lastSyncedAt,
          protection: value,
        );
        emit(current.copyWith(
          info: WalletInfo(
            walletInfo: updatedInfo,
            balance: current.balance,
            hasBiometricSlot: current.hasBiometricSlot,
            tipHeight: current.tipHeight,
          ),
        ));
        return true;
    }
  }

  /// Update the wallet's display name on disk and reflect it in the loaded state.
  /// The wallet must be unlocked (UserPassword/XpubKey wallets need their
  /// credential cached). Returns true on success.
  Future<bool> renameWallet(String newName) async {
    final current = loadedState;
    if (current == null) return false;
    final trimmed = newName.trim();
    if (trimmed.isEmpty || trimmed == current.walletInfo.name) return false;

    try {
      await opener.renameWallet(
        walletPath: current.walletInfo.walletPath,
        name: trimmed,
      );
    } catch (e, st) {
      logError('WalletDetailProtection.renameWallet()', e, st);
      final err = loadedState;
      if (err != null) emit(err.copyWith(errorMessage: formatRustError(e)));
      return false;
    }

    final after = loadedState;
    if (after == null) return true;
    final updatedInfo = APIWalletInfo(
      walletPath: after.walletInfo.walletPath,
      name: trimmed,
      descriptor: after.walletInfo.descriptor,
      network: after.walletInfo.network,
      createdAt: after.walletInfo.createdAt,
      lastSyncedAt: after.walletInfo.lastSyncedAt,
      protection: after.walletInfo.protection,
    );
    emit(after.copyWith(
      info: WalletInfo(
        walletInfo: updatedInfo,
        balance: after.balance,
        hasBiometricSlot: after.hasBiometricSlot,
        tipHeight: after.tipHeight,
      ),
    ));
    return true;
  }
}
