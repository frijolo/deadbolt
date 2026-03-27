import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import 'package:deadbolt/cubit/settings_cubit.dart';
import 'package:deadbolt/l10n/l10n.dart';
import 'package:deadbolt/src/rust/api/tor.dart' as tor_api;

class AppNavDrawer extends StatefulWidget {
  final int selectedIndex;
  final void Function(int) onNavigate;

  const AppNavDrawer({
    super.key,
    required this.selectedIndex,
    required this.onNavigate,
  });

  @override
  State<AppNavDrawer> createState() => _AppNavDrawerState();
}

class _AppNavDrawerState extends State<AppNavDrawer> {
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    // Poll Rust state every 2 s so the status tile updates while the drawer is open.
    _timer = Timer.periodic(const Duration(seconds: 2), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final torEnabled = context.watch<SettingsCubit>().state.torEnabled;
    final torConnected = torEnabled && tor_api.isTorRunning();

    return NavigationDrawer(
      selectedIndex: widget.selectedIndex,
      onDestinationSelected: (i) {
        Navigator.pop(context);
        widget.onNavigate(i);
      },
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(28, 16, 16, 10),
          child: Text(
            'Deadbolt',
            style: Theme.of(context).textTheme.titleSmall,
          ),
        ),
        NavigationDrawerDestination(
          icon: const Icon(Icons.account_balance_wallet_outlined),
          label: Text(l10n.navWallet),
        ),
        NavigationDrawerDestination(
          icon: const Icon(Icons.design_services_outlined),
          label: Text(l10n.navDesigner),
        ),
        NavigationDrawerDestination(
          icon: const Icon(Icons.settings_outlined),
          label: Text(l10n.settingsTitle),
        ),
        NavigationDrawerDestination(
          icon: const Icon(Icons.info_outline),
          label: Text(l10n.aboutTitle),
        ),
        if (torEnabled) ...[
          const Divider(indent: 16, endIndent: 16),
          _TorStatusTile(connected: torConnected),
        ],
      ],
    );
  }
}

class _TorStatusTile extends StatelessWidget {
  final bool connected;

  const _TorStatusTile({required this.connected});

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final cs = Theme.of(context).colorScheme;
    final color = connected ? cs.primary : cs.tertiary;

    final (frac, statusLine) = connected ? (1.0, '') : tor_api.torBootstrapProgress();
    final pct = (frac * 100).round();
    final label = connected
        ? l10n.torStatusConnected
        : pct > 0
            ? '${l10n.torStatusConnecting} $pct%'
            : l10n.torStatusConnecting;

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              if (!connected)
                SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2, color: color),
                )
              else
                Icon(Icons.security_outlined, size: 18, color: color),
              const SizedBox(width: 12),
              Text(
                label,
                style: Theme.of(context)
                    .textTheme
                    .labelMedium
                    ?.copyWith(color: color, fontWeight: FontWeight.w600),
              ),
            ],
          ),
          if (!connected && statusLine.isNotEmpty) ...[
            const SizedBox(height: 4),
            Padding(
              padding: const EdgeInsets.only(left: 28),
              child: Text(
                statusLine,
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                      color: cs.onSurfaceVariant,
                    ),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ],
      ),
    );
  }
}
