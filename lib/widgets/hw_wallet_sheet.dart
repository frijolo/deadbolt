
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import 'package:deadbolt/cubit/hw_wallet_cubit.dart';
import 'package:deadbolt/l10n/l10n.dart';
import 'package:deadbolt/src/rust/api/model.dart';
import 'package:deadbolt/utils/toast_helper.dart';
import 'package:deadbolt/widgets/colored_group_text.dart';
import 'package:deadbolt/widgets/dialog_helpers.dart' show SheetHandle, showSheet;
import 'package:deadbolt/widgets/hw_wallet_common.dart';

// re-export for callers that need the APIXpubSlot type
export 'package:deadbolt/src/rust/api/model.dart' show APIXpubSlot;

// re-export so callers can pattern-match on HwAddressDisplayedResult
export 'package:deadbolt/cubit/hw_wallet_cubit.dart' show HwAddressDisplayedResult;

// ─── Public helpers ───────────────────────────────────────────────────────────

/// Shows the hardware wallet bottom sheet in **sign PSBT** mode.
///
/// Returns the signed PSBT base64 string if signing succeeds, or `null` if
/// the user cancelled or an error occurred.
Future<String?> showHwSignSheet(
  BuildContext context, {
  required String psbtBase64,
  required APINetwork network,
  // Required for policy wallets (multisig, taproot script-path).
  // Pass null for simple single-key wallets.
  String? descriptor,
  // Per-MFP change index for the chosen spend path. Used in multi-leaf taproot
  // descriptors so the device signs the user-selected leaf instead of the first
  // one matching its fingerprint. Null disables filtering (single-leaf cases).
  Map<String, Uint32List>? keyChanges,
}) {
  return _showHwWalletSheet<String>(
    context,
    mode: _HwMode.sign,
    psbtBase64: psbtBase64,
    network: network,
    descriptor: descriptor,
    keyChanges: keyChanges,
  );
}

/// Shows the hardware wallet bottom sheet in **register wallet** mode.
///
/// Returns `true` if registration succeeded, or `null` if cancelled/failed.
Future<bool?> showHwRegisterSheet(
  BuildContext context, {
  required String walletName,
  required String policy,
  required APINetwork network,
}) {
  return _showHwWalletSheet<bool>(
    context,
    mode: _HwMode.register,
    walletName: walletName,
    policy: policy,
    network: network,
  );
}

/// Shows the hardware wallet bottom sheet in **check registration** mode.
///
/// Returns `true` if the descriptor is registered, `false` if not,
/// or `null` if the user cancelled.
Future<bool?> showHwCheckRegistrationSheet(
  BuildContext context, {
  required String descriptor,
  required APINetwork network,
}) {
  return _showHwWalletSheet<bool>(
    context,
    mode: _HwMode.checkRegistration,
    descriptor: descriptor,
    network: network,
  );
}

/// Shows the hardware wallet bottom sheet in **xpub export** mode.
///
/// Returns a descriptor key string `[mfp/path]xpub...` or `null`.
Future<String?> showHwXpubSheet(
  BuildContext context, {
  required String derivationPath,
  required APINetwork network,
}) {
  return _showHwWalletSheet<String>(
    context,
    mode: _HwMode.xpub,
    derivationPath: derivationPath,
    network: network,
  );
}

/// Shows the hardware wallet bottom sheet in **xpub unlock** mode.
///
/// Once the device is connected its root fingerprint is matched against [slots].
/// The matching slot's derivation path is used to derive the xpub automatically.
/// Returns a descriptor key string `[mfp/path]xpub...` or `null`.
Future<String?> showHwXpubUnlockSheet(
  BuildContext context, {
  required List<APIXpubSlot> slots,
  required APINetwork network,
}) {
  return _showHwWalletSheet<String>(
    context,
    mode: _HwMode.xpubUnlock,
    slots: slots,
    network: network,
  );
}

/// Shows the hardware wallet bottom sheet in **verify address** mode.
///
/// The device will display the address at [keychain]/[index] derived from
/// [descriptor] and wait for the user to confirm on its screen.
///
/// [address] is the Bitcoin address string shown to the user in the sheet
/// while the device displays it for comparison.
///
/// Returns `true` if the user confirmed on the device, or `null` if
/// cancelled or an error occurred.
Future<bool?> showHwVerifyAddressSheet(
  BuildContext context, {
  required String descriptor,
  required APINetwork network,
  required APIKeychain keychain,
  required int index,
  required String address,
}) {
  return _showHwWalletSheet<bool>(
    context,
    mode: _HwMode.verifyAddress,
    descriptor: descriptor,
    network: network,
    keychain: keychain,
    index: index,
    address: address,
  );
}

/// Shows the hardware wallet bottom sheet in **check-then-register** mode.
///
/// Connects the device, silently checks whether [policy] is already registered
/// under [walletName], and only prompts the user to register on-device if it is
/// not yet registered. Returns `true` once registered (or if already registered),
/// or `null` if the user cancelled.
Future<bool?> showHwCheckAndRegisterSheet(
  BuildContext context, {
  required String walletName,
  required String policy,
  required APINetwork network,
}) {
  return _showHwWalletSheet<bool>(
    context,
    mode: _HwMode.checkAndRegister,
    walletName: walletName,
    policy: policy,
    network: network,
  );
}

/// Shows the hardware wallet bottom sheet in **check-register-sign** mode.
///
/// Single sheet that: connects the device → silently checks registration of
/// [policy] under [walletName] → registers on-device only if needed → signs
/// [psbtBase64]. Returns the signed PSBT base64, or `null` if cancelled.
Future<String?> showHwCheckRegisterAndSignSheet(
  BuildContext context, {
  required String psbtBase64,
  required String walletName,
  required String policy,
  required APINetwork network,
}) {
  return _showHwWalletSheet<String>(
    context,
    mode: _HwMode.checkRegisterAndSign,
    psbtBase64: psbtBase64,
    walletName: walletName,
    policy: policy,
    network: network,
  );
}

/// Shows the hardware wallet bottom sheet in **connect-only** mode.
///
/// Guides the user through device detection and unlock, then auto-closes
/// leaving the active HW session available via [hwActiveSession].
///
/// Returns `true` once the device is ready, or `null` if the user cancelled.
Future<bool?> showHwConnectSheet(BuildContext context) {
  return _showHwWalletSheet<bool>(context, mode: _HwMode.connect);
}

Future<T?> _showHwWalletSheet<T>(
  BuildContext context, {
  required _HwMode mode,
  String? psbtBase64,
  String? derivationPath,
  APINetwork network = APINetwork.bitcoin,
  String? walletName,
  String? policy,
  String? descriptor,
  APIKeychain? keychain,
  int? index,
  String? address,
  List<APIXpubSlot>? slots,
  Map<String, Uint32List>? keyChanges,
}) {
  return showSheet<T>(context, (_) => BlocProvider(
    create: (_) => HwWalletCubit()..scanDevices(),
    child: _HwWalletSheet<T>(
      mode: mode,
      psbtBase64: psbtBase64,
      derivationPath: derivationPath,
      network: network,
      walletName: walletName,
      policy: policy,
      descriptor: descriptor,
      keychain: keychain,
      index: index,
      address: address,
      slots: slots,
      keyChanges: keyChanges,
    ),
  ));
}

// ─── Internal ─────────────────────────────────────────────────────────────────

enum _HwMode { sign, xpub, xpubUnlock, register, checkRegistration, verifyAddress, connect, checkAndRegister, checkRegisterAndSign }

class _HwWalletSheet<T> extends StatelessWidget {
  final _HwMode mode;
  final String? psbtBase64;
  final String? derivationPath;
  final APINetwork network;
  final String? walletName;
  final String? policy;
  final String? descriptor;
  final APIKeychain? keychain;
  final int? index;
  final String? address;
  final List<APIXpubSlot>? slots;
  final Map<String, Uint32List>? keyChanges;

  const _HwWalletSheet({
    super.key,
    required this.mode,
    this.psbtBase64,
    this.derivationPath,
    this.network = APINetwork.bitcoin,
    this.walletName,
    this.policy,
    this.descriptor,
    this.keychain,
    this.index,
    this.address,
    this.slots,
    this.keyChanges,
  });

  @override
  Widget build(BuildContext context) {
    return BlocConsumer<HwWalletCubit, HwWalletState>(
      listener: (context, state) {
        if (state is HwWalletDone) {
          final result = state.result;

          // checkAndRegister: after the silent check, either pop or register.
          if (mode == _HwMode.checkAndRegister && result is HwCheckRegistrationResult) {
            if (result.isRegistered) {
              Navigator.of(context).pop(true);
            } else {
              context.read<HwWalletCubit>().registerDescriptor(
                sessionId: state.sessionId,
                productString: state.productString,
                rootFingerprint: state.rootFingerprint,
                walletName: walletName!,
                policy: policy!,
                network: network,
              );
            }
            return;
          }

          // checkRegisterAndSign: check → [register if needed] → sign.
          if (mode == _HwMode.checkRegisterAndSign) {
            final cubit = context.read<HwWalletCubit>();
            if (result is HwCheckRegistrationResult) {
              if (!result.isRegistered) {
                cubit.registerDescriptor(
                  sessionId: state.sessionId,
                  productString: state.productString,
                  rootFingerprint: state.rootFingerprint,
                  walletName: walletName!,
                  policy: policy!,
                  network: network,
                );
              } else {
                cubit.signPsbt(
                  sessionId: state.sessionId,
                  productString: state.productString,
                  rootFingerprint: state.rootFingerprint,
                  psbtBase64: psbtBase64!,
                  network: network,
                  descriptor: policy,
                  signerChainIndices: keyChanges?[state.rootFingerprint],
                );
              }
              return;
            }
            if (result is HwRegisteredResult) {
              cubit.signPsbt(
                sessionId: state.sessionId,
                productString: state.productString,
                rootFingerprint: state.rootFingerprint,
                psbtBase64: psbtBase64!,
                network: network,
                descriptor: policy,
                signerChainIndices: keyChanges?[state.rootFingerprint],
              );
              return;
            }
            // HwSignedPsbtResult falls through to the generic pop below.
          }

          T? returnValue;
          if (result is HwSignedPsbtResult && T == String) {
            returnValue = result.signedPsbtBase64 as T?;
          } else if (result is HwXpubResult && T == String) {
            returnValue = result.descriptorKey as T?;
          } else if (result is HwRegisteredResult) {
            returnValue = true as T?;
          } else if (result is HwCheckRegistrationResult && T == bool) {
            returnValue = result.isRegistered as T?;
          } else if (result is HwAddressDisplayedResult) {
            returnValue = true as T?;
          }
          Navigator.of(context).pop(returnValue);
        }
        if (state is HwWalletError) {
          showErrorToast(state.message);
        }
      },
      builder: (context, state) {
        return Padding(
            padding: EdgeInsets.fromLTRB(
              16,
              0,
              16,
              MediaQuery.viewInsetsOf(context).bottom + 16,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const SheetHandle(),
                Text(
                  _sheetTitle(context),
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 16),
                _buildBody(context, state),
              ],
            ),
          );
      },
    );
  }

  String _sheetTitle(BuildContext context) {
    final l10n = context.l10n;
    return switch (mode) {
      _HwMode.sign || _HwMode.checkRegisterAndSign => l10n.signWithHwWallet,
      _HwMode.xpub => 'Export xpub from hardware wallet',
      _HwMode.xpubUnlock => 'Unlock with hardware wallet',
      _HwMode.register => 'Register wallet on hardware device',
      _HwMode.checkRegistration => 'Check registration on device',
      _HwMode.verifyAddress => 'Verify address on device',
      _HwMode.connect => 'Connect hardware wallet',
      _HwMode.checkAndRegister => 'Register wallet on hardware device',
    };
  }

  Widget _buildBody(BuildContext context, HwWalletState state) {
    final cubit = context.read<HwWalletCubit>();

    return switch (state) {
      // ── Scanning ─────────────────────────────────────────────────────────
      HwWalletScanning() => HwSpinner(label: context.l10n.hwWalletScanning),

      // ── No devices ───────────────────────────────────────────────────────
      HwWalletDevicesFound(devices: final devices) when devices.isEmpty =>
        HwEmptyDevices(onRefresh: cubit.scanDevices),

      // ── Device list ──────────────────────────────────────────────────────
      HwWalletDevicesFound(devices: final devices) => HwDeviceList(
          devices: devices,
          onRefresh: cubit.scanDevices,
          onTap: (d) => cubit.connectDevice(d.devicePath),
        ),

      // ── Connecting / waiting for PIN ─────────────────────────────────────
      HwWalletConnecting() =>
        HwSpinner(label: context.l10n.hwWalletUnlockDevice),

      // ── Pairing code visible on both screens ──────────────────────────────
      HwWalletPairing(pairingCode: final code) ||
      HwWalletConfirming(pairingCode: final code) =>
        HwPairingCode(code: code),

      // ── Ready ─────────────────────────────────────────────────────────────
      HwWalletReady(
        sessionId: final sid,
        productString: final prod,
        rootFingerprint: final mfp,
      ) =>
        _ReadyPanel(
          productString: prod,
          rootFingerprint: mfp,
          onAction: () => _runOperation(context, cubit, sid, prod, mfp),
          mode: mode,
        ),

      // ── Operating ────────────────────────────────────────────────────────
      HwWalletOperating(operationLabel: final label) =>
        mode == _HwMode.verifyAddress && address != null
            ? _VerifyAddressSpinner(label: label, address: address!)
            : HwSpinner(label: label),

      // ── Done (handled in listener — navigator pops before this renders)
      HwWalletDone() => const SizedBox.shrink(),

      // ── Error ─────────────────────────────────────────────────────────────
      HwWalletError(message: final msg, sessionId: final sid) => _ErrorPanel(
          message: msg,
          onRetry: cubit.scanDevices,
          onDisconnect: sid != null
              ? () {
                  cubit.disconnect(sid);
                  Navigator.of(context).pop();
                }
              : null,
        ),

      HwWalletIdle() => const SizedBox.shrink(),
    };
  }

  void _runOperation(
    BuildContext context,
    HwWalletCubit cubit,
    String sessionId,
    String productString,
    String rootFingerprint,
  ) {
    switch (mode) {
      case _HwMode.sign:
        if (psbtBase64 != null) {
          cubit.signPsbt(
            sessionId: sessionId,
            productString: productString,
            rootFingerprint: rootFingerprint,
            psbtBase64: psbtBase64!,
            network: network,
            descriptor: descriptor,
            signerChainIndices: keyChanges?[rootFingerprint],
          );
        }
      case _HwMode.xpub:
        if (derivationPath != null) {
          cubit.getXpub(
            sessionId: sessionId,
            productString: productString,
            rootFingerprint: rootFingerprint,
            derivationPath: derivationPath!,
            network: network,
          );
        }
      case _HwMode.xpubUnlock:
        final match = slots?.where((s) =>
            s.mfp.toLowerCase() == rootFingerprint.toLowerCase() &&
            s.derivationHint.isNotEmpty);
        if (match != null && match.isNotEmpty) {
          cubit.getXpub(
            sessionId: sessionId,
            productString: productString,
            rootFingerprint: rootFingerprint,
            derivationPath: match.first.derivationHint,
            network: network,
          );
        } else {
          showErrorToast(
            context.l10n.hwDeviceNotRegisteredForWallet(
              rootFingerprint.toUpperCase(),
            ),
          );
        }
      case _HwMode.register:
        if (walletName != null && policy != null) {
          cubit.registerDescriptor(
            sessionId: sessionId,
            productString: productString,
            rootFingerprint: rootFingerprint,
            walletName: walletName!,
            policy: policy!,
            network: network,
          );
        }
      case _HwMode.checkRegistration:
        if (descriptor != null) {
          cubit.checkRegistration(
            sessionId: sessionId,
            productString: productString,
            rootFingerprint: rootFingerprint,
            descriptor: descriptor!,
            network: network,
          );
        }
      case _HwMode.verifyAddress:
        if (descriptor != null && keychain != null && index != null) {
          cubit.displayAddress(
            sessionId: sessionId,
            productString: productString,
            rootFingerprint: rootFingerprint,
            descriptor: descriptor!,
            network: network,
            keychain: keychain!,
            index: index!,
          );
        }
      case _HwMode.connect:
        Navigator.of(context).pop(true);
      case _HwMode.checkAndRegister:
        // Silently check first; the listener handles the register-or-pop logic.
        if (policy != null) {
          cubit.checkRegistration(
            sessionId: sessionId,
            productString: productString,
            rootFingerprint: rootFingerprint,
            descriptor: policy!,
            network: network,
          );
        }
      case _HwMode.checkRegisterAndSign:
        // Silently check; the listener chains register (if needed) then sign.
        if (policy != null) {
          cubit.checkRegistration(
            sessionId: sessionId,
            productString: productString,
            rootFingerprint: rootFingerprint,
            descriptor: policy!,
            network: network,
          );
        }
    }
  }
}

// ─── Sub-widgets ──────────────────────────────────────────────────────────────

class _ReadyPanel extends StatelessWidget {
  final String productString;
  final String rootFingerprint;
  final VoidCallback onAction;
  final _HwMode mode;

  const _ReadyPanel({
    required this.productString,
    required this.rootFingerprint,
    required this.onAction,
    required this.mode,
  });

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final actionLabel = switch (mode) {
      _HwMode.sign => l10n.hwSignTransactionButton,
      _HwMode.checkRegisterAndSign => l10n.signButton,
      _HwMode.xpub => 'Export xpub',
      _HwMode.register => 'Register wallet',
      _HwMode.checkRegistration => 'Check registration',
      _HwMode.verifyAddress => 'Show address on device',
      _HwMode.xpubUnlock => 'Unlock wallet',
      _HwMode.connect => l10n.done,
      _HwMode.checkAndRegister => 'Register wallet',
    };

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        HwReadyHeader(
          productString: productString,
          rootFingerprint: rootFingerprint,
        ),
        const SizedBox(height: 16),
        FilledButton.icon(
          onPressed: onAction,
          icon: const Icon(Icons.memory),
          label: Text(actionLabel),
        ),
      ],
    );
  }
}

class _VerifyAddressSpinner extends StatelessWidget {
  final String label;
  final String address;
  const _VerifyAddressSpinner({required this.label, required this.address});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 16),
      child: Column(
        children: [
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Center(
              child: ColoredGroupText(text: address, fontSize: 13),
            ),
          ),
          const SizedBox(height: 20),
          const CircularProgressIndicator(),
          const SizedBox(height: 12),
          Text(label, textAlign: TextAlign.center),
        ],
      ),
    );
  }
}

class _ErrorPanel extends StatelessWidget {
  final String message;
  final VoidCallback onRetry;
  final VoidCallback? onDisconnect;

  const _ErrorPanel({
    required this.message,
    required this.onRetry,
    this.onDisconnect,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        HwErrorMessage(message: message),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            OutlinedButton.icon(
              onPressed: onRetry,
              icon: const Icon(Icons.refresh),
              label: Text(context.l10n.tryAgain),
            ),
            if (onDisconnect != null) ...[
              const SizedBox(width: 8),
              TextButton(
                onPressed: onDisconnect,
                child: Text(context.l10n.hwDisconnectButton),
              ),
            ],
          ],
        ),
        const SizedBox(height: 8),
      ],
    );
  }
}
