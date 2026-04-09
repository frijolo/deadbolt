import 'package:collection/collection.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import 'package:deadbolt/cubit/descriptor_sigs_cubit.dart';
import 'package:deadbolt/cubit/wallet_detail_cubit.dart';
import 'package:deadbolt/l10n/l10n.dart';
import 'package:deadbolt/screens/change_protection_dialog.dart';
import 'package:deadbolt/screens/descriptor_sigs_screen.dart';
import 'package:deadbolt/src/rust/api/model.dart' show APIProtectionType, APISecurityLevel;

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
      padding: const EdgeInsets.all(16),
      children: [
        _SectionCard(
          title: l10n.encryptionSection,
          icon: Icons.lock_outlined,
          action: IconButton(
            icon: const Icon(Icons.edit_outlined, size: 18),
            tooltip: l10n.changeProtectionMenu,
            onPressed: () => showChangeProtectionDialog(
              context,
              currentProtection: walletState.walletInfo.protection.protectionType,
              currentSecurityLevel: walletState.walletInfo.protection.securityLevel,
            ),
          ),
          child: _EncryptionSection(walletState: walletState),
        ),
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
// Encryption section
// ---------------------------------------------------------------------------

class _EncryptionSection extends StatelessWidget {
  final WalletDetailLoaded walletState;

  const _EncryptionSection({required this.walletState});

  String _protectionLabel(AppLocalizations l10n, APIProtectionType type) => switch (type) {
        APIProtectionType.deviceKey => l10n.protectionUnprotected,
        APIProtectionType.userPassword => l10n.protectionPassword,
        APIProtectionType.xpubKey => l10n.protectionXpub,
      };

  String _securityLevelLabel(AppLocalizations l10n, APISecurityLevel level) => switch (level) {
        APISecurityLevel.standard => l10n.securityLevelStandard,
        APISecurityLevel.high => l10n.securityLevelHigh,
        APISecurityLevel.extreme => l10n.securityLevelExtreme,
      };

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final protection = walletState.walletInfo.protection;

    return Wrap(
      spacing: 8,
      runSpacing: 4,
      children: [
        Chip(
          avatar: const Icon(Icons.password, size: 16),
          label: Text(_protectionLabel(l10n, protection.protectionType)),
        ),
        if (protection.protectionType == APIProtectionType.userPassword ||
            protection.protectionType == APIProtectionType.xpubKey)
          Chip(
            avatar: const Icon(Icons.shield_outlined, size: 16),
            label: Text(_securityLevelLabel(l10n, protection.securityLevel)),
          ),
      ],
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


