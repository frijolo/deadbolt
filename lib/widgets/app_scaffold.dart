import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import 'package:deadbolt/cubit/wallet_list_cubit.dart';
import 'package:deadbolt/l10n/l10n.dart';
import 'package:deadbolt/screens/about_screen.dart';
import 'package:deadbolt/screens/project_list_screen.dart';
import 'package:deadbolt/screens/settings_screen.dart';
import 'package:deadbolt/screens/wallet_list_screen.dart';

class AppScaffold extends StatefulWidget {
  const AppScaffold({super.key});

  @override
  State<AppScaffold> createState() => _AppScaffoldState();
}

class _AppScaffoldState extends State<AppScaffold> {
  int _selectedIndex = 0;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final isWide = MediaQuery.sizeOf(context).width > 600;

    final destinations = [
      (icon: Icons.design_services_outlined, label: l10n.navDesigner),
      (icon: Icons.account_balance_wallet_outlined, label: l10n.navWallet),
      (icon: Icons.settings_outlined, label: l10n.settingsTitle),
      (icon: Icons.info_outline, label: l10n.aboutTitle),
    ];

    final body = IndexedStack(
      index: _selectedIndex,
      children: [
        const ProjectListScreen(),
        BlocProvider(
          create: (context) => WalletListCubit(),
          child: const WalletListScreen(),
        ),
        const SettingsScreen(),
        const AboutScreen(),
      ],
    );

    if (isWide) {
      return Scaffold(
        body: Row(
          children: [
            NavigationRail(
              selectedIndex: _selectedIndex,
              onDestinationSelected: (i) =>
                  setState(() => _selectedIndex = i),
              labelType: NavigationRailLabelType.all,
              destinations: destinations
                  .map((d) => NavigationRailDestination(
                        icon: Icon(d.icon),
                        label: Text(d.label),
                      ))
                  .toList(),
            ),
            const VerticalDivider(thickness: 1, width: 1),
            Expanded(child: body),
          ],
        ),
      );
    }

    return Scaffold(
      body: body,
      bottomNavigationBar: NavigationBar(
        selectedIndex: _selectedIndex,
        onDestinationSelected: (i) => setState(() => _selectedIndex = i),
        destinations: destinations
            .map((d) => NavigationDestination(
                  icon: Icon(d.icon),
                  label: d.label,
                ))
            .toList(),
      ),
    );
  }
}
