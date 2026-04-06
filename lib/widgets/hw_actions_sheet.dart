import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import 'package:deadbolt/cubit/hw_wallet_cubit.dart';
import 'package:deadbolt/l10n/l10n.dart';
import 'package:deadbolt/src/rust/api/model.dart';
import 'package:deadbolt/utils/toast_helper.dart' show showErrorToast;
import 'package:deadbolt/widgets/dialog_helpers.dart' show SheetHandle, showSheet;
import 'package:deadbolt/widgets/hw_connection_widgets.dart';

/// Shows a bottom sheet for all hardware wallet actions on a wallet.
///
/// Opens with connection status at the top (restores any existing session
/// or scans for devices automatically). Action buttons are enabled only
/// when a device is connected.
///
/// [walletName] is used as the policy name when registering the wallet.
/// [descriptor] is the full wallet descriptor.
/// [network] is the wallet's network.
Future<void> showHwActionsSheet(
  BuildContext context, {
  required String walletName,
  required String descriptor,
  required APINetwork network,
}) {
  return showSheet<void>(context, (_) => BlocProvider(
    create: (_) => HwWalletCubit()..restoreOrScan(),
    child: _HwActionsSheet(
      walletName: walletName,
      descriptor: descriptor,
      network: network,
    ),
  ));
}

// ─── Sheet widget ──────────────────────────────────────────────────────────────

class _HwActionsSheet extends StatelessWidget {
  final String walletName;
  final String descriptor;
  final APINetwork network;

  const _HwActionsSheet({
    required this.walletName,
    required this.descriptor,
    required this.network,
  });

  @override
  Widget build(BuildContext context) {
    return BlocConsumer<HwWalletCubit, HwWalletState>(
      listener: (context, state) {
        if (state is HwWalletError) {
          showErrorToast(context, state.message);
          // If still connected (operation error), go back to ready.
          if (state.sessionId != null) {
            context.read<HwWalletCubit>().returnToReady();
          }
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
                  context.l10n.hwWalletTitle,
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 16),
                _buildConnectionSection(context, state),
                const Divider(height: 24),
                _buildActions(context, state),
              ],
            ),
          );
      },
    );
  }

  // ── Connection section ────────────────────────────────────────────────────

  Widget _buildConnectionSection(BuildContext context, HwWalletState state) {
    final cubit = context.read<HwWalletCubit>();

    return switch (state) {
      HwWalletReady(
        sessionId: final sid,
        productString: final prod,
        rootFingerprint: final mfp,
      ) ||
      HwWalletDone(
        sessionId: final sid,
        productString: final prod,
        rootFingerprint: final mfp,
      ) =>
        HwConnectedHeader(
          productString: prod,
          rootFingerprint: mfp,
          onDisconnect: () {
            cubit.disconnect(sid);
            Navigator.of(context).pop();
          },
        ),
      HwWalletScanning() =>
        HwStatusRow(icon: Icons.search, label: context.l10n.hwWalletScanning),
      HwWalletConnecting() =>
        HwStatusRow(icon: Icons.usb, label: context.l10n.hwWalletConnecting),
      HwWalletPairing(pairingCode: final code) => HwPairingView(code: code),
      HwWalletConfirming(pairingCode: final code) => HwPairingView(code: code),
      HwWalletOperating(operationLabel: final label) =>
        HwStatusRow(icon: Icons.memory, label: label, spinning: true),
      HwWalletDevicesFound(devices: final devices) when devices.isEmpty =>
        HwNoDevicesRow(onRefresh: cubit.scanDevices),
      HwWalletDevicesFound(devices: final devices) =>
        HwDeviceListSection(devices: devices, onTap: (d) => cubit.connectDevice(d.devicePath)),
      HwWalletError() ||
      HwWalletIdle() =>
        HwNoDevicesRow(onRefresh: cubit.scanDevices),
    };
  }

  // ── Action list ───────────────────────────────────────────────────────────

  Widget _buildActions(BuildContext context, HwWalletState state) {
    final cubit = context.read<HwWalletCubit>();

    final isPolicy = _isPolicyDescriptor(descriptor);

    final policySubtitle = isPolicy
        ? context.l10n.hwRegisterWalletSub
        : context.l10n.hwNotRequired;

    if (!isPolicy) {
      return Column(
        children: [
          ListTile(
            leading: const Icon(Icons.memory),
            title: Text(context.l10n.hwRegisterWallet),
            subtitle: Text(policySubtitle),
            enabled: false,
          ),
          ListTile(
            leading: const Icon(Icons.fact_check_outlined),
            title: Text(context.l10n.hwCheckRegistration),
            subtitle: Text(policySubtitle),
            enabled: false,
          ),
          const SizedBox(height: 8),
        ],
      );
    }

    // Inline result after an operation completes.
    if (state is HwWalletDone) {
      final result = state.result;
      final (String message, bool isSuccess) = switch (result) {
        HwRegisteredResult() => (context.l10n.hwWalletRegistered, true),
        HwCheckRegistrationResult(isRegistered: true) =>
          (context.l10n.hwWalletIsRegistered, true),
        HwCheckRegistrationResult(isRegistered: false) =>
          (context.l10n.hwWalletNotRegistered, false),
        _ => (context.l10n.hwWalletRegistered, true),
      };
      return _ResultPanel(
        message: message,
        isSuccess: isSuccess,
        onBack: cubit.returnToReady,
      );
    }

    final ready = state is HwWalletReady ? state : null;
    final isReady = ready != null;
    final sessionId = ready?.sessionId;
    final productString = ready?.productString ?? '';
    final rootFingerprint = ready?.rootFingerprint ?? '';

    return Column(
      children: [
        ListTile(
          leading: const Icon(Icons.memory),
          title: Text(context.l10n.hwRegisterWallet),
          subtitle: Text(context.l10n.hwRegisterWalletSub),
          enabled: isReady,
          onTap: isReady
              ? () => cubit.registerDescriptor(
                    sessionId: sessionId!,
                    productString: productString,
                    rootFingerprint: rootFingerprint,
                    walletName: walletName,
                    policy: descriptor,
                    network: network,
                  )
              : null,
        ),
        ListTile(
          leading: const Icon(Icons.fact_check_outlined),
          title: Text(context.l10n.hwCheckRegistration),
          subtitle: Text(context.l10n.hwCheckRegistrationSub),
          enabled: isReady,
          onTap: isReady
              ? () => cubit.checkRegistration(
                    sessionId: sessionId!,
                    productString: productString,
                    rootFingerprint: rootFingerprint,
                    descriptor: descriptor,
                    network: network,
                  )
              : null,
        ),
        const SizedBox(height: 8),
      ],
    );
  }
}

class _ResultPanel extends StatelessWidget {
  final String message;
  final bool isSuccess;
  final VoidCallback onBack;

  const _ResultPanel({
    required this.message,
    required this.isSuccess,
    required this.onBack,
  });

  @override
  Widget build(BuildContext context) {
    final color = isSuccess
        ? Theme.of(context).colorScheme.primary
        : Theme.of(context).colorScheme.secondary;
    final icon = isSuccess ? Icons.check_circle_outline : Icons.info_outline;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Column(
        children: [
          Row(
            children: [
              Icon(icon, color: color),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  message,
                  style: TextStyle(color: color),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Align(
            alignment: Alignment.centerRight,
            child: TextButton(
              onPressed: onBack,
              child: Text(context.l10n.backButton),
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Helpers ───────────────────────────────────────────────────────────────────

/// Returns true if [descriptor] describes a multi-key policy wallet that
/// requires registration on the BitBox02 (WSH multisig, taproot script-path,
/// miniscript). Returns false for single-key wallets.
bool _isPolicyDescriptor(String descriptor) {
  final d =
      descriptor.contains('#') ? descriptor.split('#').first : descriptor;
  if (d.startsWith('wpkh(') ||
      d.startsWith('sh(wpkh(') ||
      d.startsWith('pkh(')) {
    return false;
  }
  final xpubCount =
      RegExp(r'[xyYzZtuUvV]pub[1-9A-HJ-NP-Za-km-z]{79,108}')
          .allMatches(d)
          .map((m) => m.group(0))
          .toSet()
          .length;
  return xpubCount >= 2;
}
