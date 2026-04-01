import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import 'package:deadbolt/cubit/settings_cubit.dart';
import 'package:deadbolt/cubit/wallet_list_cubit.dart';
import 'package:deadbolt/l10n/l10n.dart';
import 'package:deadbolt/screens/create_wallet_dialog.dart';
import 'package:deadbolt/screens/restore_from_seed_screen.dart';
import 'package:deadbolt/screens/simple_wallet_dialog.dart';
import 'package:deadbolt/screens/wallet_detail_screen.dart';
import 'package:deadbolt/services/wallet_service.dart';
import 'package:deadbolt/services/wallet_sync_service.dart';
import 'package:deadbolt/src/rust/api/model.dart';
import 'package:deadbolt/src/rust/api/wallet.dart' as rust_wallet;
import 'package:deadbolt/theme/app_theme.dart';
import 'package:deadbolt/utils/enum_formatters.dart';
import 'package:deadbolt/utils/toast_helper.dart';
import 'package:deadbolt/widgets/app_nav_drawer.dart';
import 'package:deadbolt/widgets/mfp_badge.dart';
import 'package:deadbolt/widgets/password_prompt_dialog.dart';
import 'package:deadbolt/widgets/dialog_helpers.dart';

enum _CreateMode { guided, fromDescriptor, fromProject, fromBackup, fromSeed }

class WalletListScreen extends StatelessWidget {
  final int navIndex;
  final void Function(int)? onNavigate;

  const WalletListScreen({super.key, this.navIndex = 0, this.onNavigate});

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;

    return Scaffold(
      drawer: onNavigate != null
          ? AppNavDrawer(selectedIndex: navIndex, onNavigate: onNavigate!)
          : null,
      appBar: AppBar(
        title: Text(l10n.walletsTitle),
        actions: [
          IconButton(
            icon: const Icon(Icons.add),
            tooltip: l10n.menuNew,
            onPressed: () => _showCreateDialog(context),
          ),
        ],
      ),
      body: SafeArea(
        child: BlocConsumer<WalletListCubit, WalletListState>(
          listenWhen: (prev, curr) {
            if (curr is! WalletListLoaded) return false;
            if (prev is! WalletListLoaded) return true;
            return !identical(prev.wallets, curr.wallets);
          },
          listener: (context, state) {
            if (state is! WalletListLoaded) return;
            final settings = context.read<SettingsCubit>().state;
            context.read<WalletSyncService>().initFromList(state.wallets, settings);
          },
          builder: (context, state) {
            return switch (state) {
              WalletListLoading() => Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const CircularProgressIndicator(),
                      const SizedBox(height: 16),
                      Text(
                        l10n.loadingWallets,
                        style: TextStyle(
                          color: Theme.of(context)
                              .colorScheme
                              .onSurface
                              .withAlpha(AppAlpha.mediumHigh),
                        ),
                      ),
                    ],
                  ),
                ),
              WalletListError(:final message) =>
                Center(child: Text(message)),
              WalletListLoaded(:final wallets) => wallets.isEmpty
                  ? _buildEmptyState(context)
                  : ListView.builder(
                      padding: const EdgeInsets.all(16),
                      itemCount: wallets.length,
                      itemBuilder: (context, index) => KeyedSubtree(
                        key: ValueKey(wallets[index].walletPath),
                        child: _buildWalletCard(context, wallets[index], state),
                      ),
                    ),
            };
          },
        ),
      ),
    );
  }

  Widget _buildEmptyState(BuildContext context) {
    final l10n = context.l10n;
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            l10n.noWallets,
            textAlign: TextAlign.center,
            style: TextStyle(
              color: Theme.of(context).colorScheme.onSurface.withAlpha(AppAlpha.secondary),
            ),
          ),
          const SizedBox(height: 24),
          FilledButton.icon(
            onPressed: () => _showCreateDialog(context),
            icon: const Icon(Icons.add),
            label: Text(l10n.menuNew),
          ),
        ],
      ),
    );
  }

  Widget _buildWalletCard(
      BuildContext context, APIWalletInfo wallet, WalletListLoaded state) {
    final l10n = context.l10n;
    final service = context.read<WalletService>();
    final isLocked = wallet.protection.needsPassword &&
        service.getCachedPassword(wallet.walletPath) == null;
    final lastSynced = wallet.lastSyncedAt != null
        ? DateTime.fromMillisecondsSinceEpoch(wallet.lastSyncedAt! * 1000)
        : null;
    final balance = state.balances[wallet.walletPath];
    final isSyncing = state.syncing.contains(wallet.walletPath);
    final totalSats = balance != null
        ? (balance.confirmed + balance.trustedPending + balance.untrustedPending)
            .toInt()
        : null;

    final card = Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: ListTile(
        title: Row(
          children: [
            Expanded(
              child: Text(
                wallet.name,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
            ),
            if (isSyncing) ...[
              const SizedBox(width: 8),
              const SizedBox(
                width: 14,
                height: 14,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            ],
            const SizedBox(width: 8),
            if (totalSats != null)
              Text(
                l10n.balanceSats(totalSats),
                style: const TextStyle(
                    fontWeight: FontWeight.w600, fontSize: 13),
              )
            else
              Text(
                l10n.walletBalanceUnknown,
                style: TextStyle(
                  fontSize: 13,
                  color: Theme.of(context)
                      .colorScheme
                      .onSurface
                      .withAlpha(AppAlpha.secondary),
                ),
              ),
          ],
        ),
        subtitle: Padding(
          padding: const EdgeInsets.only(top: 4),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  lastSynced != null
                      ? l10n.lastSynced(_formatDate(lastSynced))
                      : isLocked
                      ? l10n.walletPasswordProtected
                      : l10n.notYetSynced,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 12,
                    color: Theme.of(context)
                        .colorScheme
                        .onSurface
                        .withAlpha(AppAlpha.secondary),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              MfpBadge(
                label: localizedNetworkDisplayName(
                  context,
                  wallet.network.name,
                ),
                color: AppAccent.color,
                letterSpacing: 0.0,
              ),
            ],
          ),
        ),
        trailing: _buildCardActions(
            context, wallet, isLocked, isSyncing),
        onTap: () async {
          await Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => WalletDetailScreen(
                walletPath: wallet.walletPath,
                onNavigate: onNavigate,
              ),
            ),
          );
          // Refresh to pick up updated lastSyncedAt and lock/unlock state.
          if (context.mounted) {
            context.read<WalletListCubit>().refresh();
          }
        },
      ),
    );

    if (isLocked) {
      return Opacity(opacity: 0.65, child: card);
    }
    return card;
  }

  Widget _buildCardActions(BuildContext context, APIWalletInfo wallet,
      bool isLocked, bool isSyncing) {
    final l10n = context.l10n;
    final service = context.read<WalletService>();

    return PopupMenuButton<String>(
      icon: const Icon(Icons.more_vert, size: 20),
      tooltip: l10n.moreOptionsTooltip,
      onSelected: (value) {
        switch (value) {
          case 'sync':
            context.read<WalletListCubit>().syncWallet(wallet.walletPath);
          case 'lock':
            service.evictPassword(wallet.walletPath);
            context.read<WalletSyncService>().untrack(wallet.walletPath);
            context.read<WalletListCubit>().refresh();
          case 'delete':
            _confirmDelete(context, wallet);
        }
      },
      itemBuilder: (context) => [
        if (!isLocked && !isSyncing)
          PopupMenuItem(
            value: 'sync',
            child: Row(
              children: [
                const Icon(Icons.sync, size: 20),
                const SizedBox(width: 12),
                Text(l10n.syncTooltip),
              ],
            ),
          ),
        if (wallet.protection.needsPassword && !isLocked)
          PopupMenuItem(
            value: 'lock',
            child: Row(
              children: [
                const Icon(Icons.lock_outline, size: 20),
                const SizedBox(width: 12),
                Text(l10n.lockWallet),
              ],
            ),
          ),
        PopupMenuItem(
          value: 'delete',
          child: Row(
            children: [
              Icon(
                Icons.delete_outline,
                size: 20,
                color: Colors.red.withAlpha(AppAlpha.deleteAction),
              ),
              const SizedBox(width: 12),
              Text(
                l10n.delete,
                style:
                    TextStyle(color: Colors.red.withAlpha(AppAlpha.deleteAction)),
              ),
            ],
          ),
        ),
      ],
    );
  }

  String _formatDate(DateTime dt) {
    return '${dt.day}/${dt.month}/${dt.year} ${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
  }

  void _showCreateDialog(BuildContext context) async {
    final choice = await showSheet<_CreateMode>(context, (ctx) => Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 8),
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: Theme.of(ctx)
                      .colorScheme
                      .onSurfaceVariant
                      .withAlpha(80),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 8),
            ListTile(
              leading: const Icon(Icons.auto_awesome_outlined),
              title: Text(ctx.l10n.walletCreateGuided),
              subtitle: Text(ctx.l10n.walletCreateGuidedSub),
              onTap: () => Navigator.pop(ctx, _CreateMode.guided),
            ),
            ListTile(
              leading: const Icon(Icons.code_outlined),
              title: Text(ctx.l10n.walletCreateFromDescriptor),
              subtitle: Text(ctx.l10n.walletCreateFromDescriptorSub),
              onTap: () => Navigator.pop(ctx, _CreateMode.fromDescriptor),
            ),
            ListTile(
              leading: const Icon(Icons.design_services_outlined),
              title: Text(ctx.l10n.walletCreateFromProject),
              subtitle: Text(ctx.l10n.walletCreateFromProjectSub),
              onTap: () => Navigator.pop(ctx, _CreateMode.fromProject),
            ),
            ListTile(
              leading: const Icon(Icons.restore_outlined),
              title: Text(ctx.l10n.walletCreateFromBackup),
              subtitle: Text(ctx.l10n.walletCreateFromBackupSub),
              onTap: () => Navigator.pop(ctx, _CreateMode.fromBackup),
            ),
            ListTile(
              leading: const Icon(Icons.manage_search_outlined),
              title: Text(ctx.l10n.restoreFromSeedMenuLabel),
              subtitle: Text(ctx.l10n.scanAccountsNoActivitySubtitle),
              onTap: () => Navigator.pop(ctx, _CreateMode.fromSeed),
            ),
            const SizedBox(height: 8),
          ],
        ));

    if (choice == null || !context.mounted) return;

    final cubit = context.read<WalletListCubit>();
    String? walletPath;

    switch (choice) {
      case _CreateMode.guided:
        walletPath = await Navigator.push<String>(
          context,
          MaterialPageRoute(
            fullscreenDialog: true,
            builder: (_) => SimpleWalletDialog(cubit: cubit),
          ),
        );
      case _CreateMode.fromDescriptor:
        walletPath = await Navigator.push<String>(
          context,
          MaterialPageRoute(
            fullscreenDialog: true,
            builder: (_) => CreateWalletDialog(cubit: cubit),
          ),
        );
      case _CreateMode.fromProject:
        onNavigate?.call(1);
        return;
      case _CreateMode.fromBackup:
        await _importBackup(context);
        return;
      case _CreateMode.fromSeed:
        await RestoreFromSeedScreen.push(context);
        if (context.mounted) context.read<WalletListCubit>().refresh();
        return;
    }

    if (walletPath != null && context.mounted) {
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => WalletDetailScreen(walletPath: walletPath!),
        ),
      );
    }
  }

  Future<void> _importBackup(BuildContext context) async {
    // 1. Pick the .deadbolt file
    final result = await FilePicker.platform.pickFiles(
      type: FileType.any,
      withData: true,
    );
    if (result == null || result.files.isEmpty) return;
    final bytes = result.files.first.bytes;
    if (bytes == null) return;

    if (!context.mounted) return;

    // 2. Inspect backup to determine protection type
    APIProtectionType backupType;
    try {
      backupType = await rust_wallet.inspectWalletBackup(backupBytes: bytes);
    } catch (e) {
      if (context.mounted) showErrorToastException(context, e);
      return;
    }

    if (!context.mounted) return;

    // 3. Prompt for import credential
    String? importCredential;
    if (backupType == APIProtectionType.xpubKey) {
      importCredential = await showXpubUnlockDialog(context, walletPath: '');
    } else {
      importCredential = await showPasswordPrompt(
        context,
        title: 'Enter backup password',
        subtitle: 'This backup is password-protected.',
      );
    }
    if (importCredential == null) return;

    if (!context.mounted) return;

    // 4. Import
    try {
      final service = context.read<WalletService>();
      final deviceKey = await service.getOrCreateEncryptionKey();
      final walletsDir = await service.getWalletsDir();

      final info = await rust_wallet.importWalletBackup(
        backupBytes: bytes,
        importCredential: importCredential,
        deviceKeyHex: deviceKey,
        walletsDir: walletsDir,
      );

      if (!context.mounted) return;

      // Refresh list
      await context.read<WalletListCubit>().refresh();

      if (context.mounted) {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => WalletDetailScreen(walletPath: info.walletPath),
          ),
        );
      }
    } catch (e) {
      if (context.mounted) showErrorToastException(context, e);
    }
  }

  void _confirmDelete(BuildContext context, APIWalletInfo wallet) {
    final l10n = context.l10n;
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        titlePadding: kDialogTitlePadding,
        title: dialogCloseTitle(l10n.deleteWalletTitle, onClose: () => Navigator.pop(ctx), tooltip: l10n.cancel),
        content: Text(l10n.deleteWalletConfirm(wallet.name)),
        actions: [
          FilledButton(
            onPressed: () {
              context.read<WalletListCubit>().deleteWallet(wallet.walletPath);
              Navigator.pop(ctx);
            },
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            child: Text(l10n.delete),
          ),
        ],
      ),
    );
  }
}
