import 'dart:io' show Platform;

import 'package:flutter/gestures.dart' show DragStartBehavior;
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import 'package:deadbolt/cubit/settings_cubit.dart';
import 'package:deadbolt/services/biometric_service.dart';
import 'package:deadbolt/l10n/l10n.dart';
import 'package:deadbolt/utils/toast_helper.dart';
import 'package:deadbolt/screens/nostr_relays_screen.dart';
import 'package:deadbolt/services/price_service.dart';
import 'package:deadbolt/widgets/wallet_type_picker.dart';
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
              dragStartBehavior: DragStartBehavior.down,
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 32),
              children: [
                _SectionCard(
                  title: l10n.settingsSectionAppearance,
                  icon: Icons.palette_outlined,
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
                    const Divider(height: 1, indent: 16, endIndent: 16),
                    _SettingsDropdown<Locale>(
                      label: l10n.languageLabel,
                      value: settings.locale,
                      items: [
                        (const Locale('en'), l10n.settingsLanguageEn),
                        (const Locale('es'), l10n.settingsLanguageEs),
                      ],
                      onChanged: cubit.setLocale,
                    ),
                  ],
                ),
                if (Platform.isAndroid)
                  _SecuritySection(settings: settings, cubit: cubit),
                _SectionCard(
                  title: l10n.settingsSectionDefaults,
                  icon: Icons.tune_outlined,
                  children: [
                    _SettingsDropdown<APINetwork>(
                      label: l10n.activeNetworkLabel,
                      value: settings.network,
                      items: [
                        for (final n in APINetwork.values)
                          (n, localizedNetworkName(context, n)),
                      ],
                      onChanged: cubit.setNetwork,
                    ),
                    const Divider(height: 1, indent: 16, endIndent: 16),
                    _WalletTypeSettingTile(
                      label: l10n.preferredWalletTypeLabel,
                      current: settings.walletType,
                      onChanged: cubit.setWalletType,
                    ),
                    const Divider(height: 1, indent: 16, endIndent: 16),
                    _InheritanceMinTimelockTile(settings: settings, cubit: cubit),
                  ],
                ),
                _SectionCard(
                  title: l10n.settingsSectionTransactions,
                  icon: Icons.receipt_long_outlined,
                  children: [
                    _MinFeeRateTile(settings: settings, cubit: cubit),
                    const Divider(height: 1, indent: 16, endIndent: 16),
                    _FiatSection(settings: settings, cubit: cubit),
                  ],
                ),
                _SectionCard(
                  title: l10n.settingsSectionConnectivity,
                  icon: Icons.wifi_outlined,
                  children: [
                    SwitchListTile(
                      title: Text(l10n.torLabel),
                      subtitle: Text(l10n.torSubtitle),
                      value: settings.torEnabled,
                      onChanged: cubit.setTorEnabled,
                    ),
                    const Divider(height: 1, indent: 16, endIndent: 16),
                    _ConnectivityUrlSection(
                      title: l10n.electrumSectionTitle,
                      hint: l10n.electrumUrlHint,
                      networkLabels: {
                        APINetwork.bitcoin: l10n.electrumNetworkMainnet,
                        APINetwork.testnet: l10n.electrumNetworkTestnet,
                        APINetwork.testnet4: l10n.electrumNetworkTestnet4,
                        APINetwork.signet: l10n.electrumNetworkSignet,
                        APINetwork.regtest: l10n.electrumNetworkRegtest,
                      },
                      currentUrlFor: settings.electrumUrlForNetwork,
                      defaultUrlFor: AppSettings.defaultElectrumUrlFor,
                      onSave: cubit.setElectrumUrl,
                    ),
                    const Divider(height: 1, indent: 16, endIndent: 16),
                    _ConnectivityUrlSection(
                      title: l10n.explorerSectionTitle,
                      hint: l10n.explorerUrlHint,
                      networkLabels: {
                        APINetwork.bitcoin: l10n.explorerNetworkMainnet,
                        APINetwork.testnet: l10n.explorerNetworkTestnet,
                        APINetwork.testnet4: l10n.explorerNetworkTestnet4,
                        APINetwork.signet: l10n.explorerNetworkSignet,
                        APINetwork.regtest: l10n.explorerNetworkRegtest,
                      },
                      currentUrlFor: settings.explorerBaseForNetwork,
                      defaultUrlFor: AppSettings.defaultExplorerUrlFor,
                      onSave: cubit.setExplorerUrl,
                    ),
                    const Divider(height: 1, indent: 16, endIndent: 16),
                    ListTile(
                      title: Text(l10n.nostrRelaysLabel),
                      subtitle: Text(l10n.nostrRelaysSubtitle),
                      trailing: const Icon(Icons.chevron_right),
                      onTap: () => Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => const NostrRelaysScreen(),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────
// Section card
// ─────────────────────────────────────────────────────────────

class _SectionCard extends StatelessWidget {
  final String title;
  final IconData icon;
  final List<Widget> children;

  const _SectionCard({
    required this.title,
    required this.icon,
    required this.children,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final ts = theme.textTheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(4, 20, 0, 8),
          child: Row(
            children: [
              Icon(icon, size: 14, color: cs.primary),
              const SizedBox(width: 6),
              Text(
                title.toUpperCase(),
                style: ts.labelSmall?.copyWith(
                  color: cs.primary,
                  letterSpacing: 1.1,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
        Card(
          margin: EdgeInsets.zero,
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
            side: BorderSide(color: cs.outlineVariant.withValues(alpha: 0.5)),
          ),
          clipBehavior: Clip.antiAlias,
          child: Column(children: children),
        ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────
// Connectivity — generic per-network URL section
// ─────────────────────────────────────────────────────────────

class _ConnectivityUrlSection extends StatelessWidget {
  final String title;
  final String hint;
  final Map<APINetwork, String> networkLabels;
  final String Function(APINetwork) currentUrlFor;
  final String Function(APINetwork) defaultUrlFor;
  final void Function(APINetwork, String) onSave;

  const _ConnectivityUrlSection({
    required this.title,
    required this.hint,
    required this.networkLabels,
    required this.currentUrlFor,
    required this.defaultUrlFor,
    required this.onSave,
  });

  @override
  Widget build(BuildContext context) {
    return ExpansionTile(
      tilePadding: const EdgeInsets.symmetric(horizontal: 16),
      childrenPadding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
      title: Text(title),
      children: [
        for (final entry in networkLabels.entries)
          _UrlField(
            label: entry.value,
            currentUrl: currentUrlFor(entry.key),
            defaultUrl: defaultUrlFor(entry.key),
            hint: hint,
            onSave: (url) => onSave(entry.key, url),
          ),
        const SizedBox(height: 4),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────
// Generic URL text field (replaces _ElectrumField + _ExplorerField)
// ─────────────────────────────────────────────────────────────

class _UrlField extends StatefulWidget {
  final String label;
  final String currentUrl;
  final String defaultUrl;
  final String hint;
  final void Function(String) onSave;

  const _UrlField({
    required this.label,
    required this.currentUrl,
    required this.defaultUrl,
    required this.hint,
    required this.onSave,
  });

  @override
  State<_UrlField> createState() => _UrlFieldState();
}

class _UrlFieldState extends State<_UrlField> {
  late final TextEditingController _controller;
  late final FocusNode _focusNode;
  bool _editing = false;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.currentUrl);
    _focusNode = FocusNode()..addListener(_onFocusChange);
  }

  @override
  void didUpdateWidget(_UrlField old) {
    super.didUpdateWidget(old);
    if (!_editing && old.currentUrl != widget.currentUrl) {
      _controller.text = widget.currentUrl;
    }
  }

  @override
  void dispose() {
    _focusNode.dispose();
    _controller.dispose();
    super.dispose();
  }

  void _onFocusChange() {
    if (!_focusNode.hasFocus) _save();
  }

  void _save() {
    if (!_editing) return;
    widget.onSave(_controller.text.trim());
    setState(() => _editing = false);
  }

  @override
  Widget build(BuildContext context) {
    final showRestore =
        widget.currentUrl.isEmpty && widget.defaultUrl.isNotEmpty;
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: TextField(
        controller: _controller,
        focusNode: _focusNode,
        decoration: InputDecoration(
          labelText: widget.label,
          hintText: widget.hint,
          border: const OutlineInputBorder(),
          suffixIcon: showRestore
              ? IconButton(
                  icon: const Icon(Icons.restore),
                  tooltip: context.l10n.restoreDefaults,
                  onPressed: () => widget.onSave(widget.defaultUrl),
                )
              : null,
        ),
        onTap: () => setState(() => _editing = true),
        onSubmitted: (_) => _save(),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────
// Generic dropdown row
// ─────────────────────────────────────────────────────────────

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
        onChanged: (v) {
          if (v != null) onChanged(v);
        },
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

// ─────────────────────────────────────────────────────────────
// Wallet type picker tile
// ─────────────────────────────────────────────────────────────

class _WalletTypeSettingTile extends StatefulWidget {
  final String label;
  final APIWalletType current;
  final ValueChanged<APIWalletType> onChanged;

  const _WalletTypeSettingTile({
    required this.label,
    required this.current,
    required this.onChanged,
  });

  @override
  State<_WalletTypeSettingTile> createState() => _WalletTypeSettingTileState();
}

class _WalletTypeSettingTileState extends State<_WalletTypeSettingTile> {
  late WalletPolicy _policy;
  late WalletAddressFormat _addressFormat;

  @override
  void initState() {
    super.initState();
    _policy = walletPolicyFrom(widget.current);
    _addressFormat = walletAddressFormatFrom(widget.current);
  }

  @override
  void didUpdateWidget(_WalletTypeSettingTile old) {
    super.didUpdateWidget(old);
    if (old.current != widget.current) {
      _policy = walletPolicyFrom(widget.current);
      _addressFormat = walletAddressFormatFrom(widget.current);
    }
  }

  @override
  Widget build(BuildContext context) {
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      title: Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Text(widget.label),
      ),
      subtitle: WalletTypePicker(
        policy: _policy,
        addressFormat: _addressFormat,
        onPolicyChanged: (p) {
          setState(() => _policy = p);
          widget.onChanged(walletTypeFromAxes(p, _addressFormat));
        },
        onFormatChanged: (f) {
          setState(() => _addressFormat = f);
          widget.onChanged(walletTypeFromAxes(_policy, f));
        },
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────
// Min fee rate tile
// ─────────────────────────────────────────────────────────────

class _MinFeeRateTile extends StatefulWidget {
  final AppSettings settings;
  final SettingsCubit cubit;

  const _MinFeeRateTile({required this.settings, required this.cubit});

  @override
  State<_MinFeeRateTile> createState() => _MinFeeRateTileState();
}

class _MinFeeRateTileState extends State<_MinFeeRateTile> {
  late final TextEditingController _controller;
  late final FocusNode _focusNode;
  bool _editing = false;

  @override
  void initState() {
    super.initState();
    _controller =
        TextEditingController(text: widget.settings.minFeeRate.toString());
    _focusNode = FocusNode()..addListener(_onFocusChange);
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
    _focusNode.dispose();
    _controller.dispose();
    super.dispose();
  }

  void _onFocusChange() {
    if (!_focusNode.hasFocus) _save();
  }

  void _save() {
    if (!_editing) return;
    final value = double.tryParse(_controller.text.trim());
    if (value != null && value > 0) {
      widget.cubit.setMinFeeRate(value);
    } else {
      _controller.text = widget.settings.minFeeRate.toString();
    }
    setState(() => _editing = false);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
      child: TextField(
        controller: _controller,
        focusNode: _focusNode,
        decoration: InputDecoration(
          labelText: l10n.settingsMinFeeRate,
          hintText: '0.1',
          suffixText: 'sat/vB',
          border: const OutlineInputBorder(),
        ),
        keyboardType: const TextInputType.numberWithOptions(decimal: true),
        onTap: () => setState(() => _editing = true),
        onSubmitted: (_) => _save(),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────
// Inheritance minimum timelock tile
// ─────────────────────────────────────────────────────────────

class _InheritanceMinTimelockTile extends StatefulWidget {
  final AppSettings settings;
  final SettingsCubit cubit;

  const _InheritanceMinTimelockTile(
      {required this.settings, required this.cubit});

  @override
  State<_InheritanceMinTimelockTile> createState() =>
      _InheritanceMinTimelockTileState();
}

class _InheritanceMinTimelockTileState
    extends State<_InheritanceMinTimelockTile> {
  late final TextEditingController _controller;
  late final FocusNode _focusNode;
  bool _editing = false;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(
        text: widget.settings.inheritanceMinTimelockBlocks.toString());
    _focusNode = FocusNode()..addListener(_onFocusChange);
  }

  @override
  void didUpdateWidget(_InheritanceMinTimelockTile old) {
    super.didUpdateWidget(old);
    if (!_editing &&
        old.settings.inheritanceMinTimelockBlocks !=
            widget.settings.inheritanceMinTimelockBlocks) {
      _controller.text =
          widget.settings.inheritanceMinTimelockBlocks.toString();
    }
  }

  @override
  void dispose() {
    _focusNode.dispose();
    _controller.dispose();
    super.dispose();
  }

  void _onFocusChange() {
    if (!_focusNode.hasFocus) _save();
  }

  void _save() {
    if (!_editing) return;
    final value = int.tryParse(_controller.text.trim());
    if (value != null && value > 0) {
      widget.cubit.setInheritanceMinTimelockBlocks(value);
    } else {
      _controller.text =
          widget.settings.inheritanceMinTimelockBlocks.toString();
    }
    setState(() => _editing = false);
  }

  void _showInfo(BuildContext context) {
    final l10n = context.l10n;
    showDialog<void>(
      context: context,
      builder: (_) => AlertDialog(
        title: Text(l10n.inheritanceMinTimelockInfoTitle),
        content: Text(l10n.inheritanceMinTimelockInfo),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(l10n.ok),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
      child: TextField(
        controller: _controller,
        focusNode: _focusNode,
        decoration: InputDecoration(
          labelText: l10n.inheritanceMinTimelockLabel,
          hintText: '144',
          suffixText: l10n.blocksUnit,
          suffixIcon: IconButton(
            icon: const Icon(Icons.info_outline, size: 18),
            tooltip: l10n.inheritanceMinTimelockInfoTitle,
            onPressed: () => _showInfo(context),
          ),
          border: const OutlineInputBorder(),
        ),
        keyboardType: TextInputType.number,
        onTap: () => setState(() => _editing = true),
        onSubmitted: (_) => _save(),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────
// Fiat values section
// ─────────────────────────────────────────────────────────────

class _FiatSection extends StatelessWidget {
  final AppSettings settings;
  final SettingsCubit cubit;

  const _FiatSection({required this.settings, required this.cubit});

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final currencies = currenciesForProvider(settings.fiatProvider);
    final effectiveCurrency = currencies.contains(settings.fiatCurrency)
        ? settings.fiatCurrency
        : currencies.first;

    return Column(
      children: [
        SwitchListTile(
          title: Text(l10n.fiatSectionTitle),
          subtitle: Text(l10n.fiatEnabledLabel),
          value: settings.fiatEnabled,
          onChanged: cubit.setFiatEnabled,
        ),
        if (settings.fiatEnabled) ...[
          const Divider(height: 1, indent: 16, endIndent: 16),
          _SettingsDropdown<PriceProviderType>(
            label: l10n.fiatProviderLabel,
            value: settings.fiatProvider,
            items: [
              (PriceProviderType.coinGecko, l10n.fiatProviderCoinGecko),
              (PriceProviderType.mempoolSpace, l10n.fiatProviderMempoolSpace),
            ],
            onChanged: cubit.setFiatProvider,
          ),
          const Divider(height: 1, indent: 16, endIndent: 16),
          _SettingsDropdown<String>(
            label: l10n.fiatCurrencyLabel,
            value: effectiveCurrency,
            items: [for (final c in currencies) (c, c.toUpperCase())],
            onChanged: cubit.setFiatCurrency,
          ),
        ],
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────
// Security section (Android-only): screenshot protection + biometric lock
// ─────────────────────────────────────────────────────────────

class _SecuritySection extends StatefulWidget {
  final AppSettings settings;
  final SettingsCubit cubit;

  const _SecuritySection({required this.settings, required this.cubit});

  @override
  State<_SecuritySection> createState() => _SecuritySectionState();
}

class _SecuritySectionState extends State<_SecuritySection> {
  late Future<bool> _biometricAvailableFuture;

  @override
  void initState() {
    super.initState();
    _biometricAvailableFuture =
        context.read<BiometricService>().isAvailable();
  }

  Future<void> _onBiometricToggle(BuildContext context, bool value) async {
    if (!value) {
      await widget.cubit.setBiometricLockEnabled(false);
      return;
    }
    final l10n = context.l10n;
    // Require a successful authentication challenge before enabling the lock.
    // This guarantees the user can unlock the app once it is locked.
    final service = context.read<BiometricService>();
    final success = await service.authenticate(l10n.biometricUnlockReason);
    if (!context.mounted) return;

    if (success) {
      await widget.cubit.setBiometricLockEnabled(true);
    } else {
      showErrorToast(l10n.biometricSetupFailed);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return FutureBuilder<bool>(
      future: _biometricAvailableFuture,
      builder: (context, snapshot) {
        final biometricAvailable = snapshot.data == true;
        return _SectionCard(
          title: l10n.settingsSectionSecurity,
          icon: Icons.lock_outline,
          children: [
            SwitchListTile(
              title: Text(l10n.screenshotProtectionLabel),
              subtitle: Text(l10n.screenshotProtectionSubtitle),
              value: widget.settings.screenshotProtection,
              onChanged: widget.cubit.setScreenshotProtection,
            ),
            if (biometricAvailable) ...[
              const Divider(height: 1, indent: 16, endIndent: 16),
              SwitchListTile(
                title: Text(l10n.biometricLockLabel),
                subtitle: Text(l10n.biometricLockSubtitle),
                value: widget.settings.biometricLockEnabled,
                onChanged: (v) => _onBiometricToggle(context, v),
              ),
              if (widget.settings.biometricLockEnabled) ...[
                const Divider(height: 1, indent: 16, endIndent: 16),
                _SettingsDropdown<int>(
                  label: l10n.biometricTimeoutLabel,
                  value: widget.settings.biometricTimeoutMinutes,
                  items: [
                    (0, l10n.biometricTimeoutImmediate),
                    (1, l10n.biometricTimeout1Min),
                    (5, l10n.biometricTimeout5Min),
                  ],
                  onChanged: widget.cubit.setBiometricTimeoutMinutes,
                ),
              ],
            ],
          ],
        );
      },
    );
  }
}
