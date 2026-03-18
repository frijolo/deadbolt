import 'package:flutter/material.dart';

import 'package:deadbolt/l10n/l10n.dart';

class AppNavDrawer extends StatelessWidget {
  final int selectedIndex;
  final void Function(int) onNavigate;

  const AppNavDrawer({
    super.key,
    required this.selectedIndex,
    required this.onNavigate,
  });

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return NavigationDrawer(
      selectedIndex: selectedIndex,
      onDestinationSelected: (i) {
        Navigator.pop(context);
        onNavigate(i);
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
      ],
    );
  }
}
