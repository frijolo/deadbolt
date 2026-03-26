import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import 'package:deadbolt/theme/app_theme.dart';
import 'package:deadbolt/cubit/hw_wallet_cubit.dart';
import 'package:deadbolt/src/rust/api/model.dart';
import 'package:deadbolt/utils/toast_helper.dart' show showErrorToast;

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
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    isDismissible: true,
    builder: (_) => BlocProvider(
      create: (_) => HwWalletCubit()..restoreOrScan(),
      child: _HwActionsSheet(
        walletName: walletName,
        descriptor: descriptor,
        network: network,
      ),
    ),
  );
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
        return SafeArea(
          top: false,
          child: Padding(
            padding: EdgeInsets.fromLTRB(
              16,
              8,
              16,
              MediaQuery.of(context).viewInsets.bottom + 16,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Drag handle
                Center(
                  child: Container(
                    width: 40,
                    height: 4,
                    margin: const EdgeInsets.only(bottom: 16),
                    decoration: BoxDecoration(
                      color: Theme.of(context).colorScheme.outlineVariant,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                Text(
                  'Hardware wallet',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 16),
                _buildConnectionSection(context, state),
                const Divider(height: 24),
                _buildActions(context, state),
              ],
            ),
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
        _ConnectedHeader(
          productString: prod,
          rootFingerprint: mfp,
          onDisconnect: () {
            cubit.disconnect(sid);
            Navigator.of(context).pop();
          },
        ),
      HwWalletScanning() =>
        const _StatusRow(icon: Icons.search, label: 'Scanning for devices…'),
      HwWalletConnecting() =>
        const _StatusRow(icon: Icons.usb, label: 'Connecting…'),
      HwWalletPairing(pairingCode: final code) => _PairingView(code: code),
      HwWalletConfirming(pairingCode: final code) => _PairingView(code: code),
      HwWalletOperating(operationLabel: final label) =>
        _StatusRow(icon: Icons.memory, label: label, spinning: true),
      HwWalletDevicesFound(devices: final devices) when devices.isEmpty =>
        _NoDevicesRow(onRefresh: cubit.scanDevices),
      HwWalletDevicesFound(devices: final devices) =>
        _DeviceListSection(devices: devices, onTap: (d) => cubit.connectDevice(d.devicePath)),
      HwWalletError() ||
      HwWalletIdle() =>
        _NoDevicesRow(onRefresh: cubit.scanDevices),
    };
  }

  // ── Action list ───────────────────────────────────────────────────────────

  Widget _buildActions(BuildContext context, HwWalletState state) {
    final cubit = context.read<HwWalletCubit>();

    final isPolicy = _isPolicyDescriptor(descriptor);

    final policySubtitle = isPolicy
        ? 'Register this policy on the device'
        : 'Not required for single-key wallets';

    if (!isPolicy) {
      return Column(
        children: [
          ListTile(
            leading: const Icon(Icons.memory),
            title: const Text('Register wallet'),
            subtitle: Text(policySubtitle),
            enabled: false,
          ),
          ListTile(
            leading: const Icon(Icons.fact_check_outlined),
            title: const Text('Check registration'),
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
        HwRegisteredResult() => ('Wallet registered on device.', true),
        HwCheckRegistrationResult(isRegistered: true) =>
          ('Wallet is registered on this device.', true),
        HwCheckRegistrationResult(isRegistered: false) =>
          ('Wallet is NOT registered on this device.', false),
        _ => ('Done.', true),
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
          title: const Text('Register wallet'),
          subtitle: const Text('Register this policy on the device'),
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
          title: const Text('Check registration'),
          subtitle: const Text('Verify if this policy is registered'),
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

// ─── Sub-widgets ───────────────────────────────────────────────────────────────

class _ConnectedHeader extends StatelessWidget {
  final String productString;
  final String rootFingerprint;
  final VoidCallback onDisconnect;

  const _ConnectedHeader({
    required this.productString,
    required this.rootFingerprint,
    required this.onDisconnect,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        const Icon(Icons.usb, color: Colors.green),
        const SizedBox(width: 8),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(productString,
                  style: Theme.of(context).textTheme.bodyLarge),
              if (rootFingerprint.isNotEmpty)
                Text(
                  rootFingerprint,
                  style: Theme.of(context)
                      .textTheme
                      .bodySmall
                      ?.copyWith(fontFamily: 'monospace'),
                ),
            ],
          ),
        ),
        OutlinedButton.icon(
          onPressed: onDisconnect,
          icon: const Icon(Icons.usb_off, size: 16),
          label: const Text('Disconnect'),
          style: OutlinedButton.styleFrom(
            foregroundColor: Theme.of(context).colorScheme.error,
            side: BorderSide(
                color: Theme.of(context).colorScheme.error.withAlpha(AppAlpha.pale)),
          ),
        ),
      ],
    );
  }
}

class _StatusRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool spinning;

  const _StatusRow({
    required this.icon,
    required this.label,
    this.spinning = false,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        spinning
            ? const SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : Icon(icon,
                color: Theme.of(context).colorScheme.onSurface.withAlpha(AppAlpha.secondary)),
        const SizedBox(width: 12),
        Text(label),
      ],
    );
  }
}

class _NoDevicesRow extends StatelessWidget {
  final VoidCallback onRefresh;
  const _NoDevicesRow({required this.onRefresh});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(Icons.usb_off,
            color: Theme.of(context).colorScheme.onSurface.withAlpha(AppAlpha.secondary)),
        const SizedBox(width: 12),
        const Expanded(child: Text('No device connected')),
        TextButton.icon(
          icon: const Icon(Icons.refresh, size: 16),
          label: const Text('Scan'),
          onPressed: onRefresh,
        ),
      ],
    );
  }
}

class _DeviceListSection extends StatelessWidget {
  final List<APIHwDevice> devices;
  final void Function(APIHwDevice) onTap;

  const _DeviceListSection({required this.devices, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Select a device:',
            style: Theme.of(context).textTheme.bodySmall),
        for (final d in devices)
          ListTile(
            dense: true,
            leading: const Icon(Icons.usb),
            title: Text(d.productString),
            subtitle:
                d.serialNumber.isNotEmpty ? Text(d.serialNumber) : null,
            trailing: const Icon(Icons.chevron_right, size: 16),
            onTap: () => onTap(d),
          ),
      ],
    );
  }
}

class _PairingView extends StatelessWidget {
  final String code;
  const _PairingView({required this.code});

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          'Compare with device screen and confirm:',
          style: Theme.of(context).textTheme.bodySmall,
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 12),
        Text(
          code,
          style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                fontFamily: 'monospace',
                letterSpacing: 8,
                fontWeight: FontWeight.bold,
              ),
        ),
        const SizedBox(height: 12),
        const SizedBox(
          width: 20,
          height: 20,
          child: CircularProgressIndicator(strokeWidth: 2),
        ),
        const SizedBox(height: 4),
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
              child: const Text('Back'),
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
