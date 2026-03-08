import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import 'package:deadbolt/cubit/settings_cubit.dart';
import 'package:deadbolt/l10n/l10n.dart';
import 'package:deadbolt/src/rust/api/model.dart';
import 'package:deadbolt/theme/app_theme.dart';
import 'package:deadbolt/utils/enum_formatters.dart';
import 'package:deadbolt/widgets/app_nav_drawer.dart';

class SettingsScreen extends StatelessWidget {
  final int navIndex;
  final void Function(int)? onNavigate;

  const SettingsScreen({super.key, this.navIndex = 2, this.onNavigate});

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return Scaffold(
      drawer: onNavigate != null
          ? AppNavDrawer(selectedIndex: navIndex, onNavigate: onNavigate!)
          : null,
      appBar: AppBar(title: Text(l10n.settingsTitle)),
      body: SafeArea(
        child: BlocBuilder<SettingsCubit, AppSettings>(
          builder: (context, settings) {
            final cubit = context.read<SettingsCubit>();
            return ListView(
              padding: const EdgeInsets.symmetric(vertical: 8),
              children: [
                _SettingsDropdown<AppTheme>(
                  label: l10n.themeLabel,
                  value: settings.appTheme,
                  items: [
                    (AppTheme.system, l10n.themeSystem),
                    (AppTheme.light, l10n.themeLight),
                    (AppTheme.dark, l10n.themeDark),
                  ],
                  onChanged: cubit.setAppTheme,
                ),
                _SettingsDropdown<Locale>(
                  label: l10n.languageLabel,
                  value: settings.locale,
                  items: [
                    (const Locale('en'), l10n.settingsLanguageEn),
                    (const Locale('es'), l10n.settingsLanguageEs),
                  ],
                  onChanged: cubit.setLocale,
                ),
                _SettingsDropdown<APINetwork>(
                  label: l10n.preferredNetworkLabel,
                  value: settings.network,
                  items: [
                    for (final n in APINetwork.values)
                      (n, localizedNetworkName(context, n)),
                  ],
                  onChanged: cubit.setNetwork,
                ),
                _SettingsDropdown<APIWalletType>(
                  label: l10n.preferredWalletTypeLabel,
                  value: settings.walletType,
                  items: [
                    for (final t in [
                      APIWalletType.p2Tr,
                      APIWalletType.p2Wsh,
                      APIWalletType.p2Wpkh,
                      APIWalletType.p2Sh,
                      APIWalletType.p2ShWpkh,
                      APIWalletType.p2ShWsh,
                      APIWalletType.p2Pkh,
                    ])
                      (t, localizedWalletTypeName(context, t)),
                  ],
                  onChanged: cubit.setWalletType,
                ),
                const Divider(height: 1),
                _MinFeeRateTile(settings: settings, cubit: cubit),
                const Divider(height: 1),
                _ElectrumUrlSection(settings: settings, cubit: cubit),
                const Divider(height: 1),
                _ExplorerUrlSection(settings: settings, cubit: cubit),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _ElectrumUrlSection extends StatefulWidget {
  final AppSettings settings;
  final SettingsCubit cubit;

  const _ElectrumUrlSection({required this.settings, required this.cubit});

  @override
  State<_ElectrumUrlSection> createState() => _ElectrumUrlSectionState();
}

class _ElectrumUrlSectionState extends State<_ElectrumUrlSection> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final networkLabels = {
      APINetwork.bitcoin: l10n.electrumNetworkMainnet,
      APINetwork.testnet: l10n.electrumNetworkTestnet,
      APINetwork.testnet4: l10n.electrumNetworkTestnet4,
      APINetwork.signet: l10n.electrumNetworkSignet,
      APINetwork.regtest: l10n.electrumNetworkRegtest,
    };

    return Column(
      children: [
        ListTile(
          contentPadding: EdgeInsets.zero,
          title: Text(l10n.electrumSectionTitle),
          trailing: Icon(_expanded ? Icons.expand_less : Icons.expand_more),
          onTap: () => setState(() => _expanded = !_expanded),
        ),
        if (_expanded)
          for (final entry in networkLabels.entries)
            _ElectrumField(
              label: entry.value,
              currentUrl: widget.settings.electrumUrlForNetwork(entry.key),
              onSave: (url) => widget.cubit.setElectrumUrl(entry.key, url),
            ),
      ],
    );
  }
}

class _SettingsDropdown<T> extends StatelessWidget {
  final String label;
  final T value;
  final List<(T, String)> items;
  final void Function(T) onChanged;

  const _SettingsDropdown({
    required this.label,
    required this.value,
    required this.items,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return ListTile(
      title: Text(label),
      trailing: DropdownButton<T>(
        value: value,
        underline: const SizedBox.shrink(),
        alignment: AlignmentDirectional.centerEnd,
        onChanged: (v) { if (v != null) onChanged(v); },
        items: items
            .map((e) => DropdownMenuItem<T>(
                  value: e.$1,
                  child: Text(e.$2),
                ))
            .toList(),
      ),
    );
  }
}

class _ExplorerUrlSection extends StatefulWidget {
  final AppSettings settings;
  final SettingsCubit cubit;

  const _ExplorerUrlSection({required this.settings, required this.cubit});

  @override
  State<_ExplorerUrlSection> createState() => _ExplorerUrlSectionState();
}

class _ExplorerUrlSectionState extends State<_ExplorerUrlSection> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final networkLabels = {
      APINetwork.bitcoin: l10n.explorerNetworkMainnet,
      APINetwork.testnet: l10n.explorerNetworkTestnet,
      APINetwork.testnet4: l10n.explorerNetworkTestnet4,
      APINetwork.signet: l10n.explorerNetworkSignet,
      APINetwork.regtest: l10n.explorerNetworkRegtest,
    };

    return Column(
      children: [
        ListTile(
          contentPadding: EdgeInsets.zero,
          title: Text(l10n.explorerSectionTitle),
          trailing: Icon(_expanded ? Icons.expand_less : Icons.expand_more),
          onTap: () => setState(() => _expanded = !_expanded),
        ),
        if (_expanded)
          for (final entry in networkLabels.entries)
            _ExplorerField(
              label: entry.value,
              currentUrl: widget.settings.explorerBaseForNetwork(entry.key),
              onSave: (url) => widget.cubit.setExplorerUrl(entry.key, url),
            ),
      ],
    );
  }
}

class _ExplorerField extends StatefulWidget {
  final String label;
  final String currentUrl;
  final void Function(String) onSave;

  const _ExplorerField({
    required this.label,
    required this.currentUrl,
    required this.onSave,
  });

  @override
  State<_ExplorerField> createState() => _ExplorerFieldState();
}

class _ExplorerFieldState extends State<_ExplorerField> {
  late final TextEditingController _controller;
  bool _editing = false;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.currentUrl);
  }

  @override
  void didUpdateWidget(_ExplorerField old) {
    super.didUpdateWidget(old);
    if (!_editing && old.currentUrl != widget.currentUrl) {
      _controller.text = widget.currentUrl;
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: TextField(
        controller: _controller,
        decoration: InputDecoration(
          labelText: widget.label,
          hintText: l10n.explorerUrlHint,
          border: const OutlineInputBorder(),
          suffixIcon: IconButton(
            icon: const Icon(Icons.check, size: 18),
            tooltip: l10n.save,
            onPressed: () {
              widget.onSave(_controller.text.trim());
              setState(() => _editing = false);
              FocusScope.of(context).unfocus();
            },
          ),
        ),
        onTap: () => setState(() => _editing = true),
        onSubmitted: (url) {
          widget.onSave(url.trim());
          setState(() => _editing = false);
        },
      ),
    );
  }
}

class _MinFeeRateTile extends StatefulWidget {
  final AppSettings settings;
  final SettingsCubit cubit;

  const _MinFeeRateTile({required this.settings, required this.cubit});

  @override
  State<_MinFeeRateTile> createState() => _MinFeeRateTileState();
}

class _MinFeeRateTileState extends State<_MinFeeRateTile> {
  late final TextEditingController _controller;
  bool _editing = false;

  @override
  void initState() {
    super.initState();
    _controller =
        TextEditingController(text: widget.settings.minFeeRate.toString());
  }

  @override
  void didUpdateWidget(_MinFeeRateTile old) {
    super.didUpdateWidget(old);
    if (!_editing && old.settings.minFeeRate != widget.settings.minFeeRate) {
      _controller.text = widget.settings.minFeeRate.toString();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _save() {
    final value = double.tryParse(_controller.text.trim());
    if (value != null && value > 0) {
      widget.cubit.setMinFeeRate(value);
    } else {
      _controller.text = widget.settings.minFeeRate.toString();
    }
    setState(() => _editing = false);
    FocusScope.of(context).unfocus();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: TextField(
        controller: _controller,
        decoration: InputDecoration(
          labelText: l10n.settingsMinFeeRate,
          hintText: '0.1',
          suffixText: 'sat/vB',
          border: const OutlineInputBorder(),
          suffixIcon: IconButton(
            icon: const Icon(Icons.check, size: 18),
            tooltip: l10n.save,
            onPressed: _save,
          ),
        ),
        keyboardType: const TextInputType.numberWithOptions(decimal: true),
        onTap: () => setState(() => _editing = true),
        onSubmitted: (_) => _save(),
      ),
    );
  }
}

class _ElectrumField extends StatefulWidget {
  final String label;
  final String currentUrl;
  final void Function(String) onSave;

  const _ElectrumField({
    required this.label,
    required this.currentUrl,
    required this.onSave,
  });

  @override
  State<_ElectrumField> createState() => _ElectrumFieldState();
}

class _ElectrumFieldState extends State<_ElectrumField> {
  late final TextEditingController _controller;
  bool _editing = false;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.currentUrl);
  }

  @override
  void didUpdateWidget(_ElectrumField old) {
    super.didUpdateWidget(old);
    if (!_editing && old.currentUrl != widget.currentUrl) {
      _controller.text = widget.currentUrl;
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: TextField(
        controller: _controller,
        decoration: InputDecoration(
          labelText: widget.label,
          hintText: l10n.electrumUrlHint,
          border: const OutlineInputBorder(),
          suffixIcon: IconButton(
            icon: const Icon(Icons.check, size: 18),
            tooltip: l10n.save,
            onPressed: () {
              widget.onSave(_controller.text.trim());
              setState(() => _editing = false);
              FocusScope.of(context).unfocus();
            },
          ),
        ),
        onTap: () => setState(() => _editing = true),
        onSubmitted: (url) {
          widget.onSave(url.trim());
          setState(() => _editing = false);
        },
      ),
    );
  }
}
