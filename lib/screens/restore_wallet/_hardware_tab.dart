import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import 'package:deadbolt/cubit/hw_wallet_cubit.dart';
import 'package:deadbolt/l10n/l10n.dart';
import 'package:deadbolt/src/rust/api/model.dart';
import 'package:deadbolt/theme/app_theme.dart';
import 'package:deadbolt/utils/enum_formatters.dart';
import 'package:deadbolt/widgets/gap_stepper.dart';
import 'package:deadbolt/widgets/mfp_badge.dart';

// ---------------------------------------------------------------------------
// Hardware tab — device connection + config before scan
// ---------------------------------------------------------------------------

typedef HwScanCallback = void Function(
    String sessionId, bool searchNostr, bool skipLegacy, bool searchOnChain);

class HardwareTab extends StatefulWidget {
  final APINetwork network;
  final int accountGapLimit;
  final int addressGapLimit;
  final void Function(int) onAccountGapChanged;
  final void Function(int) onAddressGapChanged;
  final HwScanCallback onScan;

  const HardwareTab({
    super.key,
    required this.network,
    required this.accountGapLimit,
    required this.addressGapLimit,
    required this.onAccountGapChanged,
    required this.onAddressGapChanged,
    required this.onScan,
  });

  @override
  State<HardwareTab> createState() => _HardwareTabState();
}

class _HardwareTabState extends State<HardwareTab> {
  bool _searchNostr = true;
  bool _skipLegacy = true;
  bool _searchOnChain = true;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return BlocBuilder<HwWalletCubit, HwWalletState>(
      builder: (context, state) {
        final cubit = context.read<HwWalletCubit>();
        if (state is! HwWalletReady) {
          return _buildConnectBody(l10n, state, cubit);
        }
        return _buildConfigBody(l10n, state);
      },
    );
  }

  // ── Connect phase ──────────────────────────────────────────────────────────

  Widget _buildConnectBody(
      AppLocalizations l10n, HwWalletState state, HwWalletCubit cubit) {
    return switch (state) {
      HwWalletScanning() ||
      HwWalletConnecting() ||
      HwWalletConfirming() ||
      HwWalletPairing() =>
        _buildSpinner(state),
      HwWalletDevicesFound(devices: final devices) when devices.isEmpty =>
        _buildNoDevices(l10n, cubit),
      HwWalletDevicesFound(devices: final devices) =>
        _buildDeviceList(l10n, devices, cubit),
      HwWalletError(message: final msg) => _buildHwError(l10n, msg, cubit),
      _ => _buildNoDevicePrompt(l10n, cubit),
    };
  }

  Widget _buildSpinner(HwWalletState state) {
    final label = switch (state) {
      HwWalletScanning() => context.l10n.hwWalletScanning,
      HwWalletConnecting() => context.l10n.hwWalletUnlockDevice,
      HwWalletPairing(pairingCode: final c) ||
      HwWalletConfirming(pairingCode: final c) =>
        '${context.l10n.hwWalletPairingCode}\n$c',
      _ => '…',
    };
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const CircularProgressIndicator(),
            const SizedBox(height: 24),
            Text(label, textAlign: TextAlign.center),
          ],
        ),
      ),
    );
  }

  Widget _buildNoDevicePrompt(AppLocalizations l10n, HwWalletCubit cubit) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.usb, size: 64),
            const SizedBox(height: 16),
            Text(l10n.hwDiscoveryNoDevice, textAlign: TextAlign.center),
            const SizedBox(height: 24),
            FilledButton.icon(
              icon: const Icon(Icons.refresh),
              label: Text(l10n.hwWalletScanDevices),
              onPressed: cubit.scanDevices,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildNoDevices(AppLocalizations l10n, HwWalletCubit cubit) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.usb_off, size: 64),
            const SizedBox(height: 16),
            Text(l10n.hwWalletNoDevices, textAlign: TextAlign.center),
            const SizedBox(height: 24),
            FilledButton.icon(
              icon: const Icon(Icons.refresh),
              label: Text(l10n.hwWalletScanDevices),
              onPressed: cubit.scanDevices,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDeviceList(
      AppLocalizations l10n, List<APIHwDevice> devices, HwWalletCubit cubit) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Text(l10n.hwWalletSelectDevice,
            style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 12),
        for (final d in devices)
          Card(
            margin: const EdgeInsets.only(bottom: 8),
            child: ListTile(
              leading: const Icon(Icons.usb),
              title: Text(d.productString),
              subtitle: Text(d.serialNumber,
                  style: Theme.of(context).textTheme.bodySmall),
              onTap: () => cubit.connectDevice(d.devicePath),
            ),
          ),
        const SizedBox(height: 8),
        TextButton.icon(
          icon: const Icon(Icons.refresh),
          label: Text(l10n.hwWalletScanDevices),
          onPressed: cubit.scanDevices,
        ),
      ],
    );
  }

  Widget _buildHwError(
      AppLocalizations l10n, String msg, HwWalletCubit cubit) {
    final errorColor = Theme.of(context).colorScheme.error;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.error_outline, size: 48, color: errorColor),
            const SizedBox(height: 16),
            Text(msg,
                style: TextStyle(color: errorColor),
                textAlign: TextAlign.center),
            const SizedBox(height: 24),
            FilledButton.icon(
              icon: const Icon(Icons.refresh),
              label: Text(l10n.hwWalletScanDevices),
              onPressed: cubit.scanDevices,
            ),
          ],
        ),
      ),
    );
  }

  // ── Config phase (device connected) ───────────────────────────────────────

  Widget _buildConfigBody(AppLocalizations l10n, HwWalletReady ready) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Row(children: [
          const Icon(Icons.usb, size: 18),
          const SizedBox(width: 8),
          Text(
            ready.productString,
            style: Theme.of(context)
                .textTheme
                .bodyMedium
                ?.copyWith(fontWeight: FontWeight.w600),
          ),
          const SizedBox(width: 8),
          MfpBadge(label: ready.rootFingerprint, color: AppAccent.color),
        ]),
        const SizedBox(height: 16),
        Text(
          l10n.restoringToNetwork(localizedNetworkName(context, widget.network)),
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 16),
        GapStepper(
          label: l10n.accountGapLimitLabel,
          value: widget.accountGapLimit,
          onDecrement: widget.accountGapLimit > 1
              ? () => widget.onAccountGapChanged(widget.accountGapLimit - 1)
              : null,
          onIncrement: widget.accountGapLimit < 100
              ? () => widget.onAccountGapChanged(widget.accountGapLimit + 1)
              : null,
        ),
        GapStepper(
          label: l10n.addressGapLimitLabel,
          value: widget.addressGapLimit,
          onDecrement: widget.addressGapLimit > 1
              ? () => widget.onAddressGapChanged(widget.addressGapLimit - 1)
              : null,
          onIncrement: widget.addressGapLimit < 100
              ? () => widget.onAddressGapChanged(widget.addressGapLimit + 1)
              : null,
        ),
        const SizedBox(height: 16),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: Text(l10n.searchNostrLabel,
              style: Theme.of(context).textTheme.bodyMedium),
          subtitle: Text(l10n.searchNostrHint,
              style: Theme.of(context).textTheme.bodySmall),
          value: _searchNostr,
          onChanged: (v) => setState(() => _searchNostr = v),
        ),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: Text(l10n.hwSkipLegacyLabel,
              style: Theme.of(context).textTheme.bodyMedium),
          subtitle: Text(l10n.hwSkipLegacyHint,
              style: Theme.of(context).textTheme.bodySmall),
          value: _skipLegacy,
          onChanged: (v) => setState(() => _skipLegacy = v),
        ),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: Text(l10n.onChainSearchLabel,
              style: Theme.of(context).textTheme.bodyMedium),
          subtitle: Text(l10n.onChainSearchHint,
              style: Theme.of(context).textTheme.bodySmall),
          value: _searchOnChain,
          onChanged: (v) => setState(() => _searchOnChain = v),
        ),
        const SizedBox(height: 8),
        FilledButton(
          onPressed: () => widget.onScan(
              ready.sessionId, _searchNostr, _skipLegacy, _searchOnChain),
          child: Text(l10n.hwDiscoveryStart),
        ),
      ],
    );
  }
}
