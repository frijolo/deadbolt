// Deadbolt — Hardware Wallet BTC Operations
//
// Bitcoin-specific operations: getXpub, registerDescriptor, checkRegistration,
// displayAddress, signPsbt. Each method emits operating state, calls the
// Rust FFI, and emits the done/error state.

import 'dart:async';
import 'dart:io' show Platform;

import 'package:flutter_bloc/flutter_bloc.dart';

import 'package:deadbolt/errors.dart';
import 'package:deadbolt/src/rust/api/hw_wallet.dart' as rust_hw;
import 'package:deadbolt/src/rust/api/model.dart';

import 'hw_wallet_states.dart';

/// Mixin que aporta los métodos de operación Bitcoin sobre un [Cubit].
///
/// Cada método llama a `emit()` (heredado de Cubit) y a `_callHw`
/// (inline: dispatch USB en Android, directo en desktop).
mixin HwWalletProtocol on Cubit<HwWalletState> {
  /// Wraps [operation] with the USB dispatch loop on Android; passes it
  /// through unchanged on other platforms.
  Future<T> _callHw<T>(Future<T> operation) =>
      Platform.isAndroid ? operation : operation;

  Future<void> getXpub({
    required String sessionId,
    required String productString,
    required String rootFingerprint,
    required String derivationPath,
    required APINetwork network,
  }) async {
    emit(HwWalletOperating(
      sessionId: sessionId,
      productString: productString,
      rootFingerprint: rootFingerprint,
      operationLabel: 'Exporting xpub…',
    ));
    try {
      final xpub = await _callHw(rust_hw.hwGetXpub(
        sessionId: sessionId,
        derivationPath: derivationPath,
        network: network,
      ));
      emit(HwWalletDone(
        sessionId: sessionId,
        productString: productString,
        rootFingerprint: rootFingerprint,
        result: HwXpubResult(xpub),
      ));
    } catch (e) {
      emit(HwWalletError(message: formatRustError(e), sessionId: sessionId));
    }
  }

  Future<void> registerDescriptor({
    required String sessionId,
    required String productString,
    required String rootFingerprint,
    required String walletName,
    required String policy,
    APINetwork network = APINetwork.bitcoin,
  }) async {
    emit(HwWalletOperating(
      sessionId: sessionId,
      productString: productString,
      rootFingerprint: rootFingerprint,
      operationLabel: 'Registering wallet on device…',
    ));
    try {
      await _callHw(rust_hw.hwRegisterDescriptor(
        sessionId: sessionId,
        walletName: walletName,
        policy: policy,
        network: network,
      ));
      emit(HwWalletDone(
        sessionId: sessionId,
        productString: productString,
        rootFingerprint: rootFingerprint,
        result: HwRegisteredResult(),
      ));
    } catch (e) {
      emit(HwWalletError(message: formatRustError(e), sessionId: sessionId));
    }
  }

  Future<void> checkRegistration({
    required String sessionId,
    required String productString,
    required String rootFingerprint,
    required String descriptor,
    APINetwork network = APINetwork.bitcoin,
  }) async {
    emit(HwWalletOperating(
      sessionId: sessionId,
      productString: productString,
      rootFingerprint: rootFingerprint,
      operationLabel: 'Checking registration…',
    ));
    try {
      final isRegistered = await _callHw(rust_hw.hwCheckRegistration(
        sessionId: sessionId,
        descriptor: descriptor,
        network: network,
      ));
      emit(HwWalletDone(
        sessionId: sessionId,
        productString: productString,
        rootFingerprint: rootFingerprint,
        result: HwCheckRegistrationResult(isRegistered),
      ));
    } catch (e) {
      emit(HwWalletError(message: formatRustError(e), sessionId: sessionId));
    }
  }

  Future<void> displayAddress({
    required String sessionId,
    required String productString,
    required String rootFingerprint,
    required String descriptor,
    required APINetwork network,
    required APIKeychain keychain,
    required int index,
  }) async {
    emit(HwWalletOperating(
      sessionId: sessionId,
      productString: productString,
      rootFingerprint: rootFingerprint,
      operationLabel: 'Confirm address on device…',
    ));
    try {
      await _callHw(rust_hw.hwDisplayAddress(
        sessionId: sessionId,
        descriptor: descriptor,
        network: network,
        keychain: keychain,
        index: index,
      ));
      emit(HwWalletDone(
        sessionId: sessionId,
        productString: productString,
        rootFingerprint: rootFingerprint,
        result: HwAddressDisplayedResult(),
      ));
    } catch (e) {
      emit(HwWalletError(message: formatRustError(e), sessionId: sessionId));
    }
  }

  Future<void> signPsbt({
    required String sessionId,
    required String productString,
    required String rootFingerprint,
    required String psbtBase64,
    required APINetwork network,
    String? descriptor,
    int? signerChainIndex,
  }) async {
    emit(HwWalletOperating(
      sessionId: sessionId,
      productString: productString,
      rootFingerprint: rootFingerprint,
      operationLabel: 'Confirm on device…',
    ));
    try {
      final signed = await _callHw(rust_hw.hwSignPsbt(
        sessionId: sessionId,
        psbtBase64: psbtBase64,
        network: network,
        descriptor: descriptor,
        signerChainIndex: signerChainIndex,
      ));
      emit(HwWalletDone(
        sessionId: sessionId,
        productString: productString,
        rootFingerprint: rootFingerprint,
        result: HwSignedPsbtResult(signed),
      ));
    } catch (e) {
      emit(HwWalletError(message: formatRustError(e), sessionId: sessionId));
    }
  }
}
