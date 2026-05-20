import 'package:flutter/material.dart';

import 'package:deadbolt/config/constants.dart' show kMonospaceFontFamily;
import 'package:deadbolt/l10n/l10n.dart';
import 'package:deadbolt/src/rust/api/model.dart' show APIHwDevice;

/// Shared UI building blocks for hardware-wallet bottom sheets.
///
/// Used by both [showHwSignSheet] (single PSBT) and the spaced-plan
/// batch HW sheet so the two flows look identical at every stage of
/// the ceremony (scanning → device list → pairing → ready → operating
/// → error). Each widget is intentionally a leaf — the call sites
/// compose their own action rows around it.

class HwSpinner extends StatelessWidget {
  final String label;
  const HwSpinner({super.key, required this.label});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 16),
      child: Column(
        children: [
          const CircularProgressIndicator(),
          const SizedBox(height: 12),
          Text(label, textAlign: TextAlign.center),
        ],
      ),
    );
  }
}

class HwEmptyDevices extends StatelessWidget {
  final VoidCallback onRefresh;
  final Widget? trailing;
  const HwEmptyDevices({super.key, required this.onRefresh, this.trailing});

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 16),
          child: Text(l10n.hwWalletNoDevices, textAlign: TextAlign.center),
        ),
        OutlinedButton.icon(
          onPressed: onRefresh,
          icon: const Icon(Icons.refresh),
          label: Text(l10n.scanAgain),
        ),
        ?trailing,
      ],
    );
  }
}

class HwDeviceList extends StatelessWidget {
  final List<APIHwDevice> devices;
  final void Function(APIHwDevice) onTap;
  final VoidCallback onRefresh;
  final Widget? trailing;
  const HwDeviceList({
    super.key,
    required this.devices,
    required this.onTap,
    required this.onRefresh,
    this.trailing,
  });

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (final d in devices)
          ListTile(
            leading: const Icon(Icons.usb),
            title: Text(d.productString),
            subtitle: d.serialNumber.isNotEmpty ? Text(d.serialNumber) : null,
            trailing: const Icon(Icons.arrow_forward_ios, size: 16),
            onTap: () => onTap(d),
          ),
        const SizedBox(height: 8),
        TextButton.icon(
          onPressed: onRefresh,
          icon: const Icon(Icons.refresh, size: 18),
          label: Text(l10n.refresh),
        ),
        ?trailing,
      ],
    );
  }
}

class HwPairingCode extends StatelessWidget {
  final String code;
  const HwPairingCode({super.key, required this.code});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 16),
      child: Column(
        children: [
          Text(
            context.l10n.hwCompareCodeOnDevice,
            style: theme.textTheme.bodyMedium,
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 16),
          Text(
            code,
            style: theme.textTheme.headlineMedium?.copyWith(
              fontFamily: kMonospaceFontFamily,
              letterSpacing: 8,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 16),
          const CircularProgressIndicator(),
        ],
      ),
    );
  }
}

class HwReadyHeader extends StatelessWidget {
  final String productString;
  final String rootFingerprint;
  const HwReadyHeader({
    super.key,
    required this.productString,
    required this.rootFingerprint,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        const Icon(Icons.usb, color: Colors.green),
        const SizedBox(width: 8),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(productString, style: theme.textTheme.bodyLarge),
            if (rootFingerprint.isNotEmpty)
              Text(
                rootFingerprint,
                style: theme.textTheme.bodySmall?.copyWith(
                  fontFamily: kMonospaceFontFamily,
                ),
              ),
          ],
        ),
      ],
    );
  }
}

class HwErrorMessage extends StatelessWidget {
  final String message;
  const HwErrorMessage({super.key, required this.message});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Text(
        message,
        textAlign: TextAlign.center,
        style: TextStyle(color: cs.error),
      ),
    );
  }
}
