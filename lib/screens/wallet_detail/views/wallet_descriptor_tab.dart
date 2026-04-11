import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import 'package:deadbolt/cubit/wallet_detail_cubit.dart';
import 'package:deadbolt/l10n/l10n.dart';
import 'package:deadbolt/models/timelock_types.dart';
import 'package:deadbolt/src/rust/api/model.dart';
import 'package:deadbolt/src/rust/api/wallet.dart' show ApiWallet;
import 'package:deadbolt/theme/app_theme.dart';
import 'package:deadbolt/utils/bitcoin_formatter.dart';
import 'package:deadbolt/widgets/add_key_dialog.dart' show showAddPrivateKeySheet;
import 'package:deadbolt/widgets/descriptor_tab.dart';
import 'package:deadbolt/widgets/key_card.dart';
import 'package:deadbolt/widgets/loading_indicator.dart';
import 'package:deadbolt/widgets/mfp_badge.dart';
import 'package:deadbolt/widgets/path_card.dart'
    show PathTimelockBadge, PathKeyPathBadge;
import 'package:deadbolt/widgets/wallet_path_detail_sheet.dart'
    show showWalletPathSheet;

Color walletColorForMfpIndex(BuildContext context, int index) {
  final ext = Theme.of(context).extension<KeyColorExtension>()!;
  return ext.keyColors[index % ext.keyColors.length];
}

// ─────────────────────────────────────────────────────────────
// Descriptor view (tab 4)
// ─────────────────────────────────────────────────────────────

class DescriptorView extends StatelessWidget {
  final WalletDetailLoaded state;

  const DescriptorView({super.key, required this.state});

  @override
  Widget build(BuildContext context) {
    if (!state.descriptorLoaded) {
      return LoadingIndicator(message: context.l10n.analyzingDescriptorLoading);
    }

    final analysis = state.descriptorAnalysis;
    if (analysis == null) {
      return Center(
        child: Text(
          context.l10n.descriptorLabel,
          style: TextStyle(
            color: Theme.of(context).colorScheme.onSurface.withAlpha(AppAlpha.secondary),
          ),
        ),
      );
    }

    final isTaproot = analysis.walletType.name == 'p2Tr';
    final l10n = context.l10n;

    return DefaultTabController(
      length: 3,
      child: Column(
        children: [
          TabBar(
            tabs: [
              Tab(text: l10n.spendPathsSection(analysis.spendPaths.length)),
              Tab(text: l10n.keysSection(analysis.keys.length)),
              Tab(text: l10n.descriptorLabel),
            ],
          ),
          Expanded(
            child: TabBarView(
              children: [
                WalletSpendPathsTab(
                  paths: analysis.spendPaths,
                  keys: analysis.keys,
                  keyLabels: state.keyLabels,
                  pathLabels: state.pathLabels,
                  isTaproot: isTaproot,
                ),
                WalletKeysTab(
                  keys: analysis.keys,
                  keyLabels: state.keyLabels,
                  hotKeys: state.hotKeys,
                  wallet: state.walletHandle,
                  network: state.walletInfo.network,
                ),
                DescriptorTab(descriptor: analysis.descriptor),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────
// Wallet keys tab
// ─────────────────────────────────────────────────────────────

class WalletKeysTab extends StatefulWidget {
  final List<APIPubKey> keys;
  final Map<String, String> keyLabels;
  final List<APIHotKeyInfo> hotKeys;
  final ApiWallet wallet;
  final APINetwork network;

  const WalletKeysTab({
    super.key,
    required this.keys,
    required this.keyLabels,
    required this.hotKeys,
    required this.wallet,
    required this.network,
  });

  @override
  State<WalletKeysTab> createState() => _WalletKeysTabState();
}

class _WalletKeysTabState extends State<WalletKeysTab> {
  @override
  Widget build(BuildContext context) {
    final hotMfps = widget.hotKeys.map((k) => k.mfp).toSet();
    final cubit = context.read<WalletDetailCubit>();
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
      children: [
        ...List.generate(widget.keys.length, (i) {
          final k = widget.keys[i];
          final isHot = hotMfps.contains(k.mfp);
          return KeyCard(
            key: ValueKey(k.mfp),
            mfp: k.mfp,
            derivationPath: k.derivationPath,
            xpub: k.xpub,
            label: widget.keyLabels[k.mfp],
            mfpColor: walletColorForMfpIndex(context, i),
            isHot: isHot,
            onNameSave: (name) => cubit.setWalletKeyLabel(k.mfp, name ?? ''),
            onMakeHot: !isHot
                ? () => showAddPrivateKeySheet(
                      context,
                      cubit: cubit,
                      expectedMfp: k.mfp,
                      keyLabel: widget.keyLabels[k.mfp],
                    )
                : null,
            onRevealSeed: isHot ? () => cubit.revealHotKey(k.mfp) : null,
            onDeletePrivateInfo:
                isHot ? () => cubit.deleteHotKey(k.mfp) : null,
            deletePrivateInfoDisclaimer: context.l10n.deleteWalletPrivateKeyDisclaimer,
            network: isHot ? widget.network : null,
          );
        }),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────
// Wallet spend paths tab
// ─────────────────────────────────────────────────────────────

class WalletSpendPathsTab extends StatelessWidget {
  final List<APISpendPath> paths;
  final List<APIPubKey> keys;
  final Map<String, String> keyLabels;
  final Map<int, String> pathLabels;
  final bool isTaproot;

  const WalletSpendPathsTab({
    super.key,
    required this.paths,
    required this.keys,
    required this.keyLabels,
    required this.pathLabels,
    required this.isTaproot,
  });

  Color _colorForMfp(BuildContext context, String mfp) {
    final idx = keys.indexWhere((k) => k.mfp == mfp);
    return walletColorForMfpIndex(context, idx < 0 ? 0 : idx);
  }

  String _keyLabel(String mfp) => keyLabels[mfp] ?? mfp.toUpperCase();

  @override
  Widget build(BuildContext context) {
    if (paths.isEmpty) return const SizedBox.shrink();
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
      children: [
        for (final path in paths)
          WalletPathCard(
            path: path,
            label: pathLabels[path.id],
            isTaproot: isTaproot,
            mfpColorProvider: (mfp) => _colorForMfp(context, mfp),
            keyLabelProvider: _keyLabel,
          ),
      ],
    );
  }
}

class WalletPathCard extends StatelessWidget {
  final APISpendPath path;
  final String? label;
  final bool isTaproot;
  final Color Function(String mfp) mfpColorProvider;
  final String Function(String mfp) keyLabelProvider;

  const WalletPathCard({
    super.key,
    required this.path,
    required this.isTaproot,
    required this.mfpColorProvider,
    required this.keyLabelProvider,
    this.label,
  });

  String get _autoPathLabel =>
      BitcoinFormatter.pathLabel(path.threshold, path.mfps, keyLabelProvider);

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final isKeyPath = path.trDepth == -1;
    final hasRelTimelock = path.relTimelock.value > 0;
    final hasAbsTimelock = path.absTimelock.value > 0;
    final hasTimelock = hasRelTimelock || hasAbsTimelock;

    final relType = path.relTimelock.timelockType == APIRelativeTimelockType.blocks
        ? RelativeTimelockType.blocks
        : RelativeTimelockType.time;
    final absType = path.absTimelock.timelockType == APIAbsoluteTimelockType.blocks
        ? AbsoluteTimelockType.blocks
        : AbsoluteTimelockType.timestamp;
    final timelockLabel = hasRelTimelock
        ? BitcoinFormatter.formatRelativeTimelock(relType, path.relTimelock.value)
        : BitcoinFormatter.formatAbsoluteTimelock(absType, path.absTimelock.value);

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
        leading: _buildLeading(context),
        title: Row(
          children: [
            Expanded(
              child: Text(
                label ?? _autoPathLabel,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight:
                      label != null ? FontWeight.w600 : FontWeight.normal,
                  color: label != null
                      ? cs.onSurface
                      : cs.onSurface.withAlpha(AppAlpha.muted),
                  fontStyle:
                      label != null ? FontStyle.normal : FontStyle.italic,
                ),
              ),
            ),
            if (hasTimelock)
              PathTimelockBadge(isRelative: hasRelTimelock, label: timelockLabel),
            if (isTaproot && isKeyPath) const PathKeyPathBadge(),
          ],
        ),
        trailing: const Icon(Icons.chevron_right, size: 18),
        onTap: () => showWalletPathSheet(
          context,
          path: path,
          initialLabel: label,
          isTaproot: isTaproot,
          mfpColorProvider: mfpColorProvider,
          keyLabelProvider: keyLabelProvider,
          onLabelSave: (name) =>
              context.read<WalletDetailCubit>().setWalletPathLabel(
                path.id,
                name ?? '',
              ),
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 4),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                ...path.mfps.map((mfp) {
                  final label = keyLabelProvider(mfp);
                  return MfpBadge(
                    label: label,
                    color: mfpColorProvider(mfp),
                    letterSpacing: label == mfp.toUpperCase() ? 0.5 : 0.0,
                  );
                }),
              ],
            ),
            const SizedBox(height: 6),
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  const Icon(Icons.payments_outlined,
                      size: 13, color: AppAccent.color),
                  const SizedBox(width: 4),
                  Text(
                    '${BitcoinFormatter.formatDouble(path.vbSweep, 2)} vB',
                    style: TextStyle(
                      fontSize: 11,
                      color: cs.onSurface.withAlpha(AppAlpha.mediumHigh),
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  if (path.trDepth >= 0) ...[
                    _buildSeparator(context),
                    const Icon(Icons.account_tree_outlined,
                        size: 13, color: AppAccent.color),
                    const SizedBox(width: 4),
                    Text(
                      '${path.trDepth}',
                      style: TextStyle(
                          fontSize: 11,
                          color: cs.onSurface.withAlpha(AppAlpha.mediumHigh)),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildLeading(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final mfps = path.mfps;
    return SizedBox(
      width: 40,
      height: 40,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          CircleAvatar(
            radius: 18,
            backgroundColor: AppAccent.color.withAlpha(AppAlpha.subtle),
            child: Icon(
              mfps.length == 1 ? Icons.key : Icons.diversity_3,
              color: AppAccent.color,
              size: 20,
            ),
          ),
          if (mfps.length > 1)
            Positioned(
              right: -4,
              bottom: -4,
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                decoration: BoxDecoration(
                  color: AppAccent.color.withAlpha(AppAlpha.mediumLow),
                  border: Border.all(color: AppAccent.color, width: 1),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  '${path.threshold}/${mfps.length}',
                  style: TextStyle(
                    color: cs.onSurface.withAlpha(AppAlpha.mediumHigh),
                    fontSize: 9,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildSeparator(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8),
      child: Text(
        '|',
        style: TextStyle(
            color: Theme.of(context).colorScheme.onSurface.withAlpha(AppAlpha.hint)),
      ),
    );
  }
}
