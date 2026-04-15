import 'package:flutter/gestures.dart' show DragStartBehavior;
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import 'package:collection/collection.dart';
import 'package:biometric_storage/biometric_storage.dart';

import 'package:deadbolt/cubit/descriptor_sigs_cubit.dart';
import 'package:deadbolt/cubit/wallet_detail_cubit.dart';
import 'package:deadbolt/l10n/l10n.dart';
import 'package:deadbolt/screens/descriptor_sigs_screen.dart';
import 'package:deadbolt/services/biometric_keystore_service.dart';
import 'package:deadbolt/src/rust/api/model.dart' show APIProtectionType, APISecurityLevel;
import 'package:deadbolt/utils/toast_helper.dart';

extension _WalletDetailLoadedExt on WalletDetailLoaded {
  Set<String> get hotKeyMfpSet => hotKeys.map((k) => k.mfp).toSet();
}

// ---------------------------------------------------------------------------
// Entry point
// ---------------------------------------------------------------------------

/// Security hub screen grouping wallet encryption and descriptor signatures.
///
/// Push via [WalletSecurityScreen.push].
class WalletSecurityScreen extends StatefulWidget {
  const WalletSecurityScreen._();

  static Future<void> push(
    BuildContext context, {
    required WalletDetailCubit cubit,
  }) {
    return Navigator.of(context).push<void>(MaterialPageRoute(
      builder: (_) => BlocProvider.value(
        value: cubit,
        child: const WalletSecurityScreen._(),
      ),
    ));
  }

  @override
  State<WalletSecurityScreen> createState() => _WalletSecurityScreenState();
}

class _WalletSecurityScreenState extends State<WalletSecurityScreen> {
  DescriptorSigsCubit? _sigsCubit;

  @override
  void initState() {
    super.initState();
    _initSigsCubit();
  }

  void _initSigsCubit() {
    final walletState = context.read<WalletDetailCubit>().state;
    if (walletState is! WalletDetailLoaded) return;
    _sigsCubit = DescriptorSigsCubit(
      wallet: walletState.walletHandle,
      participatingKeys: walletState.descriptorAnalysis?.keys ?? [],
      hotKeyMfps: walletState.hotKeyMfpSet,
      network: walletState.walletInfo.network,
    )..load();
  }

  @override
  void dispose() {
    _sigsCubit?.close();
    super.dispose();
  }

  Future<void> _openManage(BuildContext ctx, WalletDetailLoaded state) async {
    final cubit = _sigsCubit;
    if (cubit == null) return;
    await DescriptorSigsScreen.push(ctx, cubit: cubit);
    if (mounted) cubit.load();
  }

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<WalletDetailCubit, WalletDetailState>(
      builder: (ctx, walletState) {
        return Scaffold(
          appBar: AppBar(
            title: Text(ctx.l10n.walletSecurityTitle),
          ),
          body: walletState is! WalletDetailLoaded
              ? const Center(child: CircularProgressIndicator())
              : _SecurityBody(
                  walletState: walletState,
                  sigsCubit: _sigsCubit,
                  onManageTap: () => _openManage(ctx, walletState),
                ),
        );
      },
    );
  }
}

// ---------------------------------------------------------------------------
// Body
// ---------------------------------------------------------------------------

class _SecurityBody extends StatelessWidget {
  final WalletDetailLoaded walletState;
  final DescriptorSigsCubit? sigsCubit;
  final VoidCallback onManageTap;

  const _SecurityBody({
    required this.walletState,
    required this.sigsCubit,
    required this.onManageTap,
  });

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return ListView(
      dragStartBehavior: DragStartBehavior.down,
      padding: const EdgeInsets.all(16),
      children: [
        _EncryptionSection(walletState: walletState),
        const SizedBox(height: 16),
        _SectionCard(
          title: l10n.descriptorSigsSection,
          icon: Icons.draw_outlined,
          action: IconButton(
            icon: const Icon(Icons.edit_outlined, size: 18),
            tooltip: l10n.manageSignatures,
            onPressed: onManageTap,
          ),
          child: sigsCubit == null
              ? const SizedBox.shrink()
              : BlocProvider.value(
                  value: sigsCubit!,
                  child: _DescriptorSigsSection(walletState: walletState),
                ),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Section card wrapper
// ---------------------------------------------------------------------------

class _SectionCard extends StatelessWidget {
  final String title;
  final IconData icon;
  final Widget? action;
  final Widget child;

  const _SectionCard({
    required this.title,
    required this.icon,
    this.action,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, size: 18, color: theme.colorScheme.primary),
                const SizedBox(width: 8),
                Text(
                  title,
                  style: theme.textTheme.titleSmall
                      ?.copyWith(color: theme.colorScheme.primary),
                ),
                const Spacer(),
                ?action,
              ],
            ),
            const SizedBox(height: 12),
            child,
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Encryption section (inline editing)
// ---------------------------------------------------------------------------

class _EncryptionSection extends StatefulWidget {
  final WalletDetailLoaded walletState;

  const _EncryptionSection({required this.walletState});

  @override
  State<_EncryptionSection> createState() => _EncryptionSectionState();
}

class _EncryptionSectionState extends State<_EncryptionSection> {
  late APIProtectionType _selected;
  late APISecurityLevel _level;
  // Committed (saved) values — updated on successful save.
  late APIProtectionType _currentProtection;
  late APISecurityLevel _currentLevel;

  bool _editing = false;
  final _formKey = GlobalKey<FormState>();
  final _passwordCtrl = TextEditingController();
  final _confirmCtrl = TextEditingController();
  bool _obscure = true;
  bool _obscureConfirm = true;
  bool _isSaving = false;

  // Biometric section state.
  final _keystoreService = BiometricKeystoreService();
  bool _biometricAvailable = false;
  late bool _hasBiometricSlot;
  bool _biometricLoading = false;

  @override
  void initState() {
    super.initState();
    final protection = widget.walletState.walletInfo.protection;
    _selected = protection.protectionType;
    _level = protection.securityLevel;
    _currentProtection = protection.protectionType;
    _currentLevel = protection.securityLevel;
    _hasBiometricSlot = widget.walletState.hasBiometricSlot;
    _checkBiometricAvailability();
  }

  @override
  void didUpdateWidget(_EncryptionSection old) {
    super.didUpdateWidget(old);
    // Sync external state changes when not editing (e.g. another screen changed
    // the protection, or a cubit reload after returning from another route).
    if (!_editing) {
      final newProt = widget.walletState.walletInfo.protection;
      if (newProt.protectionType != _currentProtection ||
          newProt.securityLevel != _currentLevel) {
        _currentProtection = newProt.protectionType;
        _currentLevel = newProt.securityLevel;
        _selected = newProt.protectionType;
        _level = newProt.securityLevel;
        _checkBiometricAvailability();
      }
    }
    if (widget.walletState.hasBiometricSlot != old.walletState.hasBiometricSlot) {
      _hasBiometricSlot = widget.walletState.hasBiometricSlot;
    }
  }

  @override
  void dispose() {
    _passwordCtrl.dispose();
    _confirmCtrl.dispose();
    super.dispose();
  }

  Future<void> _checkBiometricAvailability() async {
    if (_currentProtection == APIProtectionType.deviceKey) {
      if (mounted) setState(() => _biometricAvailable = false);
      return;
    }
    final available = await _keystoreService.isAvailable();
    if (mounted) setState(() => _biometricAvailable = available);
  }

  bool get _hasChanges =>
      _selected != _currentProtection || _level != _currentLevel;

  String _protectionLabel(AppLocalizations l10n, APIProtectionType type) =>
      switch (type) {
        APIProtectionType.deviceKey => l10n.protectionUnprotected,
        APIProtectionType.userPassword => l10n.protectionPassword,
        APIProtectionType.xpubKey => l10n.protectionXpub,
      };

  String _securityLevelLabel(AppLocalizations l10n, APISecurityLevel level) =>
      switch (level) {
        APISecurityLevel.standard => l10n.securityLevelStandard,
        APISecurityLevel.high => l10n.securityLevelHigh,
        APISecurityLevel.extreme => l10n.securityLevelExtreme,
      };

  void _enterEdit() => setState(() => _editing = true);

  void _cancelEdit() {
    setState(() {
      _editing = false;
      _selected = _currentProtection;
      _level = _currentLevel;
      _passwordCtrl.clear();
      _confirmCtrl.clear();
    });
  }

  Future<void> _save(BuildContext context) async {
    if (_isSaving || !_hasChanges) return;
    if (!(_formKey.currentState?.validate() ?? true)) return;

    setState(() => _isSaving = true);
    final cubit = context.read<WalletDetailCubit>();
    final ok = await cubit.changeProtection(
      newProtectionType: _selected,
      newPassword:
          _selected == APIProtectionType.userPassword ? _passwordCtrl.text : null,
      securityLevel: _level,
    );

    if (!context.mounted) return;
    if (ok) {
      final l10n = context.l10n;
      showSuccessToast(
          l10n.protectionChangedToast(_protectionLabel(l10n, _selected)));
      setState(() {
        _isSaving = false;
        _editing = false;
        _currentProtection = _selected;
        _currentLevel = _level;
        // Changing protection clears all biometric slots.
        _hasBiometricSlot = false;
        _passwordCtrl.clear();
        _confirmCtrl.clear();
      });
      _checkBiometricAvailability();
    } else {
      setState(() => _isSaving = false);
    }
  }

  Future<void> _onBiometricToggle(BuildContext context, bool enable) async {
    if (_biometricLoading) return;
    final l10n = context.l10n;
    final cubit = context.read<WalletDetailCubit>();

    if (enable) {
      // The biometric prompt is triggered inside enableBiometricSlot() by the
      // hardware-backed keystore write — no separate app-level challenge needed.
      setState(() => _biometricLoading = true);
      final promptInfo = PromptInfo(
        androidPromptInfo: AndroidPromptInfo(
          title: l10n.biometricWalletSectionTitle,
          subtitle: l10n.biometricWalletUnlockReason,
          negativeButton: l10n.cancel,
        ),
        iosPromptInfo: IosPromptInfo(
          saveTitle: l10n.biometricWalletSectionTitle,
          accessTitle: l10n.biometricWalletUnlockReason,
        ),
        macOsPromptInfo: IosPromptInfo(
          saveTitle: l10n.biometricWalletSectionTitle,
          accessTitle: l10n.biometricWalletUnlockReason,
        ),
      );
      await cubit.enableBiometricSlot(promptInfo);
      if (!context.mounted) return;
      final newState = cubit.state;
      setState(() {
        _hasBiometricSlot =
            newState is WalletDetailLoaded && newState.hasBiometricSlot;
        _biometricLoading = false;
      });
    } else {
      setState(() => _biometricLoading = true);
      await cubit.disableAllBiometricSlots();
      if (!context.mounted) return;
      setState(() {
        _hasBiometricSlot = false;
        _biometricLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final theme = Theme.of(context);

    return _SectionCard(
      title: l10n.encryptionSection,
      icon: Icons.lock_outlined,
      action: _editing
          ? null
          : IconButton(
              icon: const Icon(Icons.edit_outlined, size: 18),
              tooltip: l10n.changeProtectionMenu,
              onPressed: _enterEdit,
            ),
      child: Form(
        key: _formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (_editing) ...[
              // ── Edit form ────────────────────────────────────────────────
              Text(l10n.protectionLabel, style: theme.textTheme.labelMedium),
              const SizedBox(height: 8),
              SizedBox(
                width: double.infinity,
                child: SegmentedButton<APIProtectionType>(
                  showSelectedIcon: false,
                  segments: [
                    ButtonSegment(
                      value: APIProtectionType.deviceKey,
                      label: Text(l10n.protectionNone),
                    ),
                    ButtonSegment(
                      value: APIProtectionType.userPassword,
                      label: Text(l10n.protectionPassword),
                    ),
                    ButtonSegment(
                      value: APIProtectionType.xpubKey,
                      label: Text(l10n.protectionXpub),
                    ),
                  ],
                  selected: {_selected},
                  onSelectionChanged: _isSaving
                      ? null
                      : (v) => setState(() => _selected = v.first),
                ),
              ),
              if (_selected != APIProtectionType.deviceKey) ...[
                const SizedBox(height: 16),
                Text(l10n.securityLevelLabel, style: theme.textTheme.labelMedium),
                const SizedBox(height: 8),
                SizedBox(
                  width: double.infinity,
                  child: SegmentedButton<APISecurityLevel>(
                    showSelectedIcon: false,
                    segments: [
                      ButtonSegment(
                        value: APISecurityLevel.standard,
                        label: Text(l10n.securityLevelStandard),
                      ),
                      ButtonSegment(
                        value: APISecurityLevel.high,
                        label: Text(l10n.securityLevelHigh),
                      ),
                      ButtonSegment(
                        value: APISecurityLevel.extreme,
                        label: Text(l10n.securityLevelExtreme),
                      ),
                    ],
                    selected: {_level},
                    onSelectionChanged: _isSaving
                        ? null
                        : (v) => setState(() => _level = v.first),
                  ),
                ),
              ],
              if (_selected == APIProtectionType.userPassword) ...[
                const SizedBox(height: 12),
                TextFormField(
                  controller: _passwordCtrl,
                  obscureText: _obscure,
                  enabled: !_isSaving,
                  decoration: InputDecoration(
                    labelText: l10n.newPasswordLabel,
                    border: const OutlineInputBorder(),
                    suffixIcon: IconButton(
                      icon: Icon(
                          _obscure ? Icons.visibility_off : Icons.visibility),
                      onPressed: () => setState(() => _obscure = !_obscure),
                    ),
                  ),
                  validator: (v) {
                    if (_selected != APIProtectionType.userPassword) return null;
                    if (v == null || v.isEmpty) return l10n.validatorPasswordEmpty;
                    return null;
                  },
                ),
                const SizedBox(height: 8),
                TextFormField(
                  controller: _confirmCtrl,
                  obscureText: _obscureConfirm,
                  enabled: !_isSaving,
                  decoration: InputDecoration(
                    labelText: l10n.confirmPasswordLabel,
                    border: const OutlineInputBorder(),
                    suffixIcon: IconButton(
                      icon: Icon(_obscureConfirm
                          ? Icons.visibility_off
                          : Icons.visibility),
                      onPressed: () =>
                          setState(() => _obscureConfirm = !_obscureConfirm),
                    ),
                  ),
                  validator: (v) {
                    if (_selected != APIProtectionType.userPassword) return null;
                    if (v != _passwordCtrl.text) return l10n.validatorPasswordsNoMatch;
                    return null;
                  },
                ),
              ],
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: _isSaving ? null : _cancelEdit,
                      child: Text(l10n.cancel),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: FilledButton(
                      onPressed: _isSaving || !_hasChanges
                          ? null
                          : () => _save(context),
                      child: _isSaving
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : Text(l10n.changeButton),
                    ),
                  ),
                ],
              ),
            ] else ...[
              // ── View mode: current protection chips ───────────────────
              Wrap(
                spacing: 8,
                runSpacing: 4,
                children: [
                  Chip(
                    avatar: const Icon(Icons.password, size: 16),
                    label: Text(_protectionLabel(l10n, _currentProtection)),
                  ),
                  if (_currentProtection != APIProtectionType.deviceKey)
                    Chip(
                      avatar: const Icon(Icons.shield_outlined, size: 16),
                      label: Text(_securityLevelLabel(l10n, _currentLevel)),
                    ),
                ],
              ),
            ],

            // ── Biometric section (only in view mode) ─────────────────
            if (_biometricAvailable &&
                _currentProtection != APIProtectionType.deviceKey &&
                !_editing) ...[
              const SizedBox(height: 16),
              const Divider(height: 1),
              const SizedBox(height: 12),
              Row(
                children: [
                  const Icon(Icons.fingerprint, size: 20),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      l10n.biometricWalletSectionTitle,
                      style: theme.textTheme.labelMedium,
                    ),
                  ),
                  if (_biometricLoading)
                    const SizedBox(
                      width: 24,
                      height: 24,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  else
                    Switch(
                      value: _hasBiometricSlot,
                      onChanged: (v) => _onBiometricToggle(context, v),
                    ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Descriptor signatures section
// ---------------------------------------------------------------------------

class _DescriptorSigsSection extends StatelessWidget {
  final WalletDetailLoaded walletState;

  const _DescriptorSigsSection({required this.walletState});

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final keys = walletState.descriptorAnalysis?.keys ?? [];

    if (keys.isEmpty) {
      return Text(
        l10n.noParticipatingKeys,
        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
      );
    }

    return BlocBuilder<DescriptorSigsCubit, DescriptorSigsState>(
      builder: (ctx, state) {
        if (state is DescriptorSigsLoading) {
          return const Padding(
            padding: EdgeInsets.symmetric(vertical: 8),
            child: Center(child: CircularProgressIndicator()),
          );
        }
        if (state is! DescriptorSigsLoaded) return const SizedBox.shrink();

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ...keys.map((key) => _KeyStatusRow(
                  keyEntry: key,
                  sigs: state.sigs,
                )),
          ],
        );
      },
    );
  }
}

// ---------------------------------------------------------------------------
// Per-key status row
// ---------------------------------------------------------------------------

class _KeyStatusRow extends StatelessWidget {
  final APIPubKey keyEntry;
  final List<APIDescriptorSig> sigs;

  const _KeyStatusRow({required this.keyEntry, required this.sigs});

  @override
  Widget build(BuildContext context) {
    final sig = sigs.where((s) => s.mfp == keyEntry.mfp).firstOrNull;

    final cs = Theme.of(context).colorScheme;
    final (icon, color) = switch (sig) {
      null => (Icons.radio_button_unchecked, cs.onSurfaceVariant),
      APIDescriptorSig(isValid: true) => (Icons.check_circle_outline, cs.primary),
      _ => (Icons.cancel_outlined, cs.error),
    };

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Icon(icon, size: 18, color: color),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              keyEntry.mfp.toUpperCase(),
              style: Theme.of(context).textTheme.bodyMedium,
            ),
          ),
          if (keyEntry.derivationPath.isNotEmpty)
            Text(
              keyEntry.derivationPath,
              style: Theme.of(context)
                  .textTheme
                  .bodySmall
                  ?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant),
            ),
        ],
      ),
    );
  }
}
