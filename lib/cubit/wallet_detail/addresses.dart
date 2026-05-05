import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:meta/meta.dart';

import 'package:deadbolt/cubit/cubit_error_logger.dart';
import 'package:deadbolt/cubit/loaded_wallet.dart' show LoadedWalletImpl;
import 'package:deadbolt/cubit/wallet_detail/lifecycle.dart';
import 'package:deadbolt/cubit/wallet_detail_session.dart' show AddressView;
import 'package:deadbolt/cubit/wallet_detail_state.dart';
import 'package:deadbolt/cubit/wallet_op_result.dart' show Ok, Err;
import 'package:deadbolt/services/wallet_service.dart';
import 'package:deadbolt/src/rust/api/model.dart';

/// Address browsing, reveal, lookup and per-address label.
mixin WalletDetailAddresses
    on Cubit<WalletDetailState>, CubitErrorLogger, WalletDetailLifecycle {
  void selectAddressKeychain(int keychain) {
    final current = loadedState;
    if (current == null) return;
    emit(current.copyWith(selectedAddressKeychain: keychain));
  }

  Future<void> ensureReceiveAddressLoaded() async {
    final current = loadedState;
    if (current == null) return;
    if (!current.receiveAddressesLoaded) {
      await loadAddresses(APIKeychain.external_);
    }
    final afterLoad = loadedState;
    if (afterLoad == null) return;
    if (afterLoad.receiveAddresses.isEmpty) {
      final result = await current.wallet
          .revealMoreAddresses(keychain: APIKeychain.external_, count: 20);
      if (result is Err) {
        emit(current.copyWith(errorMessage: result.message));
        return;
      }
      await loadAddresses(APIKeychain.external_);
      sync();
    }
  }

  @override
  @protected
  Future<void> loadAddresses(APIKeychain keychain) => runWalletOp(
        (s) => s.wallet.loadAddresses(keychain),
        (s, value) => s.copyWith(
          addresses: keychain == APIKeychain.external_
              ? AddressView(
                  receiveAddresses: value.addresses,
                  changeAddresses: s.changeAddresses,
                  receiveLoaded: true,
                  changeLoaded: s.changeAddressesLoaded,
                  selectedKeychain: s.selectedAddressKeychain,
                )
              : AddressView(
                  receiveAddresses: s.receiveAddresses,
                  changeAddresses: value.addresses,
                  receiveLoaded: s.receiveAddressesLoaded,
                  changeLoaded: true,
                  selectedKeychain: s.selectedAddressKeychain,
                ),
        ),
      );

  Future<void> revealMoreAddresses(APIKeychain keychain) async {
    final current = loadedState;
    if (current == null) return;
    final result =
        await current.wallet.revealMoreAddresses(keychain: keychain, count: 20);
    switch (result) {
      case Err(:final message):
        emit(current.copyWith(errorMessage: message));
      case Ok():
        await loadAddresses(keychain);
    }
  }

  Future<void> setAddressLabel(String address, String label, APIKeychain keychain) async {
    final current = loadedState;
    if (current == null) return;
    current.walletHandle.setAddressLabel(address: address, label: label);
    await refreshAllAfterLabelChange();
  }

  Future<String?> getNextSelfPaymentAddress({Set<String> alreadyUsed = const {}}) async {
    final current = loadedState;
    if (current == null) return null;
    try {
      final psbtRecipients = current.psbts.map((p) => p.recipient).toSet();
      final addr = await current.wallet.findNextUnusedAddress(psbtRecipients.union(alreadyUsed));
      return addr?.address;
    } catch (_) {
      return null;
    }
  }

  /// Opens a different wallet ad-hoc (not the one currently loaded) just to
  /// resolve its next unused receive address. Used when composing a tx whose
  /// recipient is another wallet on the same device.
  Future<String?> getNextReceiveAddressFor(String walletPath, {Set<String> alreadyUsed = const {}}) async {
    try {
      final handle = await WalletService().openWallet(walletPath);
      final addr = await LoadedWalletImpl(handle).findNextUnusedAddress(alreadyUsed);
      return addr?.address;
    } catch (_) {
      return null;
    }
  }

  Future<APIAddress?> getNextReceiveAddress() async {
    final current = loadedState;
    if (current == null) return null;
    try {
      final psbtRecipients = current.psbts.map((p) => p.recipient).toSet();
      return await current.wallet.findNextUnusedAddress(psbtRecipients);
    } catch (_) {
      return null;
    }
  }
}
