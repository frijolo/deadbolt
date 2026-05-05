import 'package:flutter_bloc/flutter_bloc.dart';

import 'package:deadbolt/cubit/cubit_error_logger.dart';
import 'package:deadbolt/cubit/wallet_detail/lifecycle.dart';
import 'package:deadbolt/cubit/wallet_detail_session.dart' show PsbtList;
import 'package:deadbolt/cubit/wallet_detail_state.dart';
import 'package:deadbolt/cubit/wallet_op_result.dart' show Ok, Err;
import 'package:deadbolt/src/rust/api/model.dart';
import 'package:deadbolt/utils/hot_key_helpers.dart' show upsertHotKey, removeHotKey;

/// Hot key (mnemonic / xprv) CRUD + reveal + signing PSBTs locally.
mixin WalletDetailHotKeys
    on Cubit<WalletDetailState>, CubitErrorLogger, WalletDetailLifecycle {
  Future<APIHotKeyInfo?> addMnemonicKey(String mnemonic, String? passphrase) async {
    final current = loadedState;
    if (current == null) return null;
    final result = current.wallet.addMnemonicKey(mnemonic, passphrase);
    switch (result) {
      case Err(:final message):
        emit(current.copyWith(errorMessage: message));
        return null;
      case Ok(:final value):
        emit(current.copyWith(
          hotKeys: upsertHotKey(current.hotKeys, value),
        ));
        return value;
    }
  }

  Future<APIHotKeyInfo?> addXprvKey(String xprv) async {
    final current = loadedState;
    if (current == null) return null;
    final result = current.wallet.addXprvKey(xprv);
    switch (result) {
      case Err(:final message):
        emit(current.copyWith(errorMessage: message));
        return null;
      case Ok(:final value):
        emit(current.copyWith(
          hotKeys: upsertHotKey(current.hotKeys, value),
        ));
        return value;
    }
  }

  Future<void> deleteHotKey(String mfp) async {
    final current = loadedState;
    if (current == null) return;
    final result = current.wallet.deleteHotKey(mfp);
    switch (result) {
      case Err(:final message):
        emit(current.copyWith(errorMessage: message));
      case Ok():
        emit(current.copyWith(
          hotKeys: removeHotKey(current.hotKeys, mfp),
        ));
    }
  }

  Future<String?> revealHotKey(String mfp) async {
    final current = loadedState;
    if (current == null) return null;
    final result = current.wallet.revealHotKey(mfp);
    switch (result) {
      case Err(:final message):
        emit(current.copyWith(errorMessage: message));
        return null;
      case Ok(:final value):
        return value;
    }
  }

  Future<String?> revealAddressWif(String address, String mfp) async {
    final current = loadedState;
    if (current == null) return null;
    final result = current.wallet.revealAddressWif(address, mfp);
    switch (result) {
      case Err(:final message):
        emit(current.copyWith(errorMessage: message));
        return null;
      case Ok(:final value):
        return value;
    }
  }

  Future<APIPsbtInfo?> signPsbtWithKey(int psbtId, String mfp) async {
    final current = loadedState;
    if (current == null) return null;
    final result = await current.wallet.signPsbtWithKey(psbtId, mfp);
    switch (result) {
      case Err(:final message):
        emit(current.copyWith(errorMessage: message));
        return null;
      case Ok(:final value):
        final updatedPsbts = current.psbts
            .map((p) => p.id.toInt() == psbtId ? value.psbt : p)
            .toList();
        final updatedAnalyses = Map<int, APIPsbtAnalysis>.from(current.psbtAnalyses);
        if (value.analysis != null) updatedAnalyses[psbtId] = value.analysis!;
        emit(current.copyWith(
          psbts: PsbtList(psbts: updatedPsbts, analyses: updatedAnalyses, loaded: true),
        ));
        return value.psbt;
    }
  }
}
