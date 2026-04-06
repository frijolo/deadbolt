import 'package:flutter/material.dart';

import 'package:deadbolt/l10n/l10n.dart';
import 'package:deadbolt/src/rust/api/model.dart';
import 'package:deadbolt/theme/app_theme.dart';

/// Shared HW wallet connection sub-widgets used across HW action sheets.

class HwConnectedHeader extends StatelessWidget {
  final String productString;
  final String rootFingerprint;
  final VoidCallback onDisconnect;

  const HwConnectedHeader({
    super.key,
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
              Text(productString, style: Theme.of(context).textTheme.bodyLarge),
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
          label: Text(context.l10n.hwDisconnectButton),
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

class HwStatusRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool spinning;

  const HwStatusRow({
    super.key,
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
                color: Theme.of(context)
                    .colorScheme
                    .onSurface
                    .withAlpha(AppAlpha.secondary)),
        const SizedBox(width: 12),
        Text(label),
      ],
    );
  }
}

class HwNoDevicesRow extends StatelessWidget {
  final VoidCallback onRefresh;
  const HwNoDevicesRow({super.key, required this.onRefresh});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(Icons.usb_off,
            color: Theme.of(context)
                .colorScheme
                .onSurface
                .withAlpha(AppAlpha.secondary)),
        const SizedBox(width: 12),
        Expanded(child: Text(context.l10n.hwNoDevice)),
        TextButton.icon(
          icon: const Icon(Icons.refresh, size: 16),
          label: Text(context.l10n.hwScanButton),
          onPressed: onRefresh,
        ),
      ],
    );
  }
}

class HwDeviceListSection extends StatelessWidget {
  final List<APIHwDevice> devices;
  final void Function(APIHwDevice) onTap;

  const HwDeviceListSection({super.key, required this.devices, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(context.l10n.hwSelectDevice,
            style: Theme.of(context).textTheme.bodySmall),
        for (final d in devices)
          ListTile(
            dense: true,
            leading: const Icon(Icons.usb),
            title: Text(d.productString),
            subtitle: d.serialNumber.isNotEmpty ? Text(d.serialNumber) : null,
            trailing: const Icon(Icons.chevron_right, size: 16),
            onTap: () => onTap(d),
          ),
      ],
    );
  }
}

class HwPairingView extends StatelessWidget {
  final String code;
  const HwPairingView({super.key, required this.code});

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          context.l10n.hwPairingCompare,
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
