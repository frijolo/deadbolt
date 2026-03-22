import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import 'package:deadbolt/cubit/project_list_cubit.dart';
import 'package:deadbolt/cubit/wallet_list_cubit.dart';
import 'package:deadbolt/l10n/l10n.dart';
import 'package:deadbolt/screens/create_wallet_dialog.dart';
import 'package:deadbolt/screens/wallet_detail_screen.dart';
import 'package:deadbolt/services/wallet_service.dart';
import 'package:deadbolt/src/rust/api/model.dart';
import 'package:deadbolt/src/rust/api/wallet.dart' as rust_wallet;
import 'package:deadbolt/theme/app_theme.dart';
import 'package:deadbolt/utils/enum_formatters.dart';
import 'package:deadbolt/utils/toast_helper.dart';
import 'package:deadbolt/widgets/app_nav_drawer.dart';
import 'package:deadbolt/widgets/mfp_badge.dart';
import 'package:deadbolt/widgets/password_prompt_dialog.dart';
import 'package:deadbolt/widgets/dialog_helpers.dart';

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
          PopupMenuButton<String>(
            icon: const Icon(Icons.more_vert),
            onSelected: (value) {
              if (value == 'new') _showCreateDialog(context);
              if (value == 'import') _importBackup(context);
            },
            itemBuilder: (_) => [
              PopupMenuItem(
                value: 'new',
                child: Row(
                  children: [
                    const Icon(Icons.add),
                    const SizedBox(width: 8),
                    Text(l10n.menuNew),
                  ],
                ),
              ),
              const PopupMenuItem(
                value: 'import',
                child: Row(
                  children: [
                    Icon(Icons.restore_outlined),
                    SizedBox(width: 8),
                    Text('Import wallet'),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
      body: SafeArea(
        child: BlocBuilder<WalletListCubit, WalletListState>(
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
                        child: _buildWalletCard(context, wallets[index]),
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
    final projectState = context.watch<ProjectListCubit>().state;
    final hasProjects = projectState is ProjectListLoaded &&
        projectState.projects.any((p) => p.descriptor.isNotEmpty);

    if (hasProjects) {
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

    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              l10n.noWalletsGuidedTitle,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            Text(
              l10n.noWalletsGuidedBody,
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Theme.of(context).colorScheme.onSurface.withAlpha(AppAlpha.secondary),
              ),
            ),
            const SizedBox(height: 24),
            FilledButton.icon(
              onPressed: () => onNavigate?.call(1),
              icon: const Icon(Icons.design_services_outlined),
              label: Text(l10n.goToDesigner),
            ),
            const SizedBox(height: 12),
            OutlinedButton.icon(
              onPressed: () => _showCreateDialog(context),
              icon: const Icon(Icons.edit_outlined),
              label: Text(l10n.enterDescriptorManually),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildWalletCard(BuildContext context, APIWalletInfo wallet) {
    final l10n = context.l10n;
    final service = context.read<WalletService>();
    final isLocked = wallet.protection.needsPassword &&
        service.getCachedPassword(wallet.walletPath) == null;
    final lastSynced = wallet.lastSyncedAt != null
        ? DateTime.fromMillisecondsSinceEpoch(wallet.lastSyncedAt! * 1000)
        : null;

    final card = Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: ListTile(
        title: Text(
          wallet.name,
          style: const TextStyle(fontWeight: FontWeight.w600),
        ),
        subtitle: Padding(
          padding: const EdgeInsets.only(top: 4),
          child: Row(
            children: [
              MfpBadge(
                label: localizedNetworkDisplayName(
                  context,
                  wallet.network.name,
                ),
                color: AppAccent.color,
                letterSpacing: 0.0,
              ),
              const SizedBox(width: 8),
              Text(
                lastSynced != null
                    ? l10n.lastSynced(_formatDate(lastSynced))
                    : isLocked
                    ? l10n.walletPasswordProtected
                    : l10n.notYetSynced,
                style: TextStyle(
                  fontSize: 12,
                  color: Theme.of(context)
                      .colorScheme
                      .onSurface
                      .withAlpha(AppAlpha.secondary),
                ),
              ),
            ],
          ),
        ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (wallet.protection.needsPassword)
              IconButton(
                icon: Icon(
                  isLocked ? Icons.lock_outline : Icons.lock_open_outlined,
                  size: 20,
                  color: isLocked
                      ? Theme.of(context).colorScheme.onSurface.withAlpha(AppAlpha.inactive)
                      : null,
                ),
                tooltip: isLocked ? null : l10n.lockWallet,
                onPressed: isLocked
                    ? null
                    : () {
                        service.evictPassword(wallet.walletPath);
                        context.read<WalletListCubit>().refresh();
                      },
              ),
            PopupMenuButton<String>(
              icon: const Icon(Icons.more_vert, size: 20),
              tooltip: l10n.moreOptionsTooltip,
              onSelected: (value) {
                if (value == 'delete') {
                  _confirmDelete(context, wallet);
                }
              },
              itemBuilder: (context) => [
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
                        style: TextStyle(color: Colors.red.withAlpha(AppAlpha.deleteAction)),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ],
        ),
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

  String _formatDate(DateTime dt) {
    return '${dt.day}/${dt.month}/${dt.year} ${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
  }

  void _showCreateDialog(BuildContext context) async {
    final cubit = context.read<WalletListCubit>();
    final walletPath = await Navigator.push<String>(
      context,
      MaterialPageRoute(
        fullscreenDialog: true,
        builder: (_) => CreateWalletDialog(
          cubit: cubit,
          onGoToProjects: () => onNavigate?.call(1),
        ),
      ),
    );
    if (walletPath != null && context.mounted) {
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => WalletDetailScreen(walletPath: walletPath),
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
