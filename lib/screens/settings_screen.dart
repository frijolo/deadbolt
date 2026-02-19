import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import 'package:deadbolt/cubit/settings_cubit.dart';
import 'package:deadbolt/l10n/l10n.dart';
import 'package:deadbolt/src/rust/api/model.dart';
import 'package:deadbolt/utils/enum_formatters.dart';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.settingsTitle),
      ),
      body: SafeArea(
        child: BlocBuilder<SettingsCubit, AppSettings>(
          builder: (context, settings) {
            final cubit = context.read<SettingsCubit>();
            return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              _buildSectionTitle(context, l10n.languageLabel),
              RadioGroup<Locale>(
                groupValue: settings.locale,
                onChanged: (v) => cubit.setLocale(v!),
                child: Column(
                  children: [
                    RadioListTile<Locale>(
                      title: Text(l10n.settingsLanguageEn),
                      value: const Locale('en'),
                    ),
                    RadioListTile<Locale>(
                      title: Text(l10n.settingsLanguageEs),
                      value: const Locale('es'),
                    ),
                  ],
                ),
              ),
              const Divider(),
              _buildSectionTitle(context, l10n.preferredNetworkLabel),
              RadioGroup<APINetwork>(
                groupValue: settings.network,
                onChanged: (v) => cubit.setNetwork(v!),
                child: Column(
                  children: [
                    for (final network in APINetwork.values)
                      RadioListTile<APINetwork>(
                        title: Text(localizedNetworkName(context, network)),
                        value: network,
                      ),
                  ],
                ),
              ),
              const Divider(),
              _buildSectionTitle(context, l10n.preferredWalletTypeLabel),
              RadioGroup<APIWalletType>(
                groupValue: settings.walletType,
                onChanged: (v) => cubit.setWalletType(v!),
                child: Column(
                  children: [
                    for (final type in [
                      APIWalletType.p2Tr,
                      APIWalletType.p2Wsh,
                      APIWalletType.p2Wpkh,
                      APIWalletType.p2Sh,
                      APIWalletType.p2ShWpkh,
                      APIWalletType.p2ShWsh,
                      APIWalletType.p2Pkh,
                    ])
                      RadioListTile<APIWalletType>(
                        title: Text(localizedWalletTypeName(context, type)),
                        value: type,
                      ),
                  ],
                ),
              ),
            ],
            );
          },
        ),
      ),
    );
  }

  Widget _buildSectionTitle(BuildContext context, String title) {
    return Padding(
      padding: const EdgeInsets.only(top: 8, bottom: 4),
      child: Text(
        title,
        style: Theme.of(context).textTheme.titleMedium?.copyWith(
              color: Colors.orange,
              fontWeight: FontWeight.bold,
            ),
      ),
    );
  }
}
