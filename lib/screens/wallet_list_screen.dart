import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import 'package:deadbolt/cubit/wallet_list_cubit.dart';
import 'package:deadbolt/l10n/l10n.dart';
import 'package:deadbolt/screens/create_wallet_dialog.dart';
import 'package:deadbolt/screens/wallet_detail_screen.dart';
import 'package:deadbolt/src/rust/api/model.dart';
import 'package:deadbolt/theme/app_theme.dart';
import 'package:deadbolt/utils/enum_formatters.dart';
import 'package:deadbolt/widgets/mfp_badge.dart';

class WalletListScreen extends StatelessWidget {
  const WalletListScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;

    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.walletsTitle),
        actions: [
          PopupMenuButton<String>(
            icon: const Icon(Icons.more_vert),
            onSelected: (value) {
              if (value == 'new') _showCreateDialog(context);
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
                              .withAlpha(178),
                        ),
                      ),
                    ],
                  ),
                ),
              WalletListError(:final message) =>
                Center(child: Text(message)),
              WalletListLoaded(:final wallets) => wallets.isEmpty
                  ? Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            l10n.noWallets,
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              color: Theme.of(context)
                                  .colorScheme
                                  .onSurface
                                  .withAlpha(138),
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
                    )
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

  Widget _buildWalletCard(BuildContext context, APIWalletInfo wallet) {
    final l10n = context.l10n;
    final lastSynced = wallet.lastSyncedAt != null
        ? DateTime.fromMillisecondsSinceEpoch(wallet.lastSyncedAt! * 1000)
        : null;

    return Card(
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
                label: localizedNetworkDisplayName(context, wallet.network.name),
                color: AppAccent.color,
                letterSpacing: 0.0,
              ),
              const SizedBox(width: 8),
              Text(
                lastSynced != null
                    ? l10n.lastSynced(_formatDate(lastSynced))
                    : l10n.notYetSynced,
                style: TextStyle(
                  fontSize: 12,
                  color: Theme.of(context)
                      .colorScheme
                      .onSurface
                      .withAlpha(138),
                ),
              ),
            ],
          ),
        ),
        trailing: PopupMenuButton<String>(
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
                    color: Colors.red.withAlpha(180),
                  ),
                  const SizedBox(width: 12),
                  Text(
                    l10n.delete,
                    style: TextStyle(color: Colors.red.withAlpha(180)),
                  ),
                ],
              ),
            ),
          ],
        ),
        onTap: () => Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => WalletDetailScreen(walletPath: wallet.walletPath),
          ),
        ),
      ),
    );
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
        builder: (_) => CreateWalletDialog(cubit: cubit),
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

  void _confirmDelete(BuildContext context, APIWalletInfo wallet) {
    final l10n = context.l10n;
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        titlePadding: const EdgeInsets.fromLTRB(24, 16, 8, 0),
        title: Row(
          children: [
            Expanded(child: Text(l10n.deleteWalletTitle)),
            IconButton(
              icon: const Icon(Icons.close),
              tooltip: l10n.cancel,
              visualDensity: VisualDensity.compact,
              onPressed: () => Navigator.pop(ctx),
            ),
          ],
        ),
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
