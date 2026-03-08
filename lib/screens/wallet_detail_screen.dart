import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:url_launcher/url_launcher.dart';

import 'package:deadbolt/cubit/settings_cubit.dart';
import 'package:deadbolt/cubit/wallet_detail_cubit.dart';
import 'package:deadbolt/l10n/l10n.dart';
import 'package:deadbolt/src/rust/api/model.dart';
export 'package:deadbolt/cubit/wallet_detail_cubit.dart' show APIUtxo;
import 'package:deadbolt/theme/app_theme.dart';
import 'package:deadbolt/utils/bitcoin_formatter.dart';
import 'package:deadbolt/utils/enum_formatters.dart';
import 'package:deadbolt/models/timelock_types.dart';
import 'package:deadbolt/utils/spend_path_unlock.dart';
import 'package:deadbolt/utils/toast_helper.dart';
import 'package:deadbolt/widgets/colored_address_text.dart';
import 'package:deadbolt/widgets/edit_name_dialog.dart';
import 'package:deadbolt/widgets/mfp_badge.dart';
import 'package:deadbolt/widgets/text_export_sheet.dart' show showTextExportSheet;
import 'package:deadbolt/screens/create_tx_screen.dart';
import 'package:deadbolt/screens/psbt_detail_screen.dart';

class WalletDetailScreen extends StatelessWidget {
  final String walletPath;

  const WalletDetailScreen({super.key, required this.walletPath});

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (context) => WalletDetailCubit()..load(walletPath),
      child: const _WalletDetailView(),
    );
  }
}

class _WalletDetailView extends StatefulWidget {
  const _WalletDetailView();

  @override
  State<_WalletDetailView> createState() => _WalletDetailViewState();
}

class _WalletDetailViewState extends State<_WalletDetailView> {
  bool _autoSyncStarted = false;

  void _maybeStartAutoSync(BuildContext context, WalletDetailState state) {
    if (_autoSyncStarted || state is! WalletDetailLoaded) return;
    _autoSyncStarted = true;
    final settings = context.read<SettingsCubit>().state;
    final electrumUrl = settings.electrumUrlForNetwork(state.walletInfo.network);
    context.read<WalletDetailCubit>().startAutoSync(electrumUrl);
  }

  @override
  Widget build(BuildContext context) {
    return BlocListener<WalletDetailCubit, WalletDetailState>(
      listener: _maybeStartAutoSync,
      child: BlocBuilder<WalletDetailCubit, WalletDetailState>(
        builder: (context, state) {
          return switch (state) {
          WalletDetailInitial() || WalletDetailLoading() => Scaffold(
              appBar: AppBar(),
              body: const Center(child: CircularProgressIndicator()),
            ),
          WalletDetailError(:final message) => Scaffold(
              appBar: AppBar(),
              body: Center(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Text(message),
                ),
              ),
            ),
          WalletDetailLoaded() => _buildLoaded(context, state),
        };
      },
    ));
  }

  void _onMenuAction(
    BuildContext context,
    _WalletMenuAction action,
    WalletDetailLoaded state,
  ) {
    switch (action) {
      case _WalletMenuAction.rescan:
        _confirmRescan(context, state);
    }
  }

  Future<void> _confirmRescan(
    BuildContext context,
    WalletDetailLoaded state,
  ) async {
    final l10n = context.l10n;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        titlePadding: const EdgeInsets.fromLTRB(24, 16, 8, 0),
        title: Row(
          children: [
            Expanded(child: Text(l10n.rescanConfirmTitle)),
            IconButton(
              icon: const Icon(Icons.close),
              tooltip: l10n.cancel,
              visualDensity: VisualDensity.compact,
              onPressed: () => Navigator.of(ctx).pop(false),
            ),
          ],
        ),
        content: Text(l10n.rescanConfirmBody),
        actions: [
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text(l10n.rescanButton),
          ),
        ],
      ),
    );
    if (confirmed == true && context.mounted) {
      final settings = context.read<SettingsCubit>().state;
      final electrumUrl =
          settings.electrumUrlForNetwork(state.walletInfo.network);
      context.read<WalletDetailCubit>().rescan(electrumUrl);
    }
  }

  Widget _buildLoaded(BuildContext context, WalletDetailLoaded state) {
    final l10n = context.l10n;
    final network = state.walletInfo.network;

    return Scaffold(
      appBar: AppBar(
        title: Text(state.walletInfo.name),
        actions: [
          MfpBadge(
            label: localizedNetworkDisplayName(context, network.name),
            color: AppAccent.color,
            letterSpacing: 0.0,
          ),
          const SizedBox(width: 4),
          PopupMenuButton<_WalletMenuAction>(
            tooltip: l10n.moreOptionsTooltip,
            onSelected: (action) => _onMenuAction(context, action, state),
            itemBuilder: (_) => [
              PopupMenuItem(
                value: _WalletMenuAction.rescan,
                child: Row(
                  children: [
                    const Icon(Icons.manage_search, size: 20),
                    const SizedBox(width: 12),
                    Text(l10n.rescanButton),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
      body: SafeArea(
        child: switch (state.selectedTab) {
          0 => _TransactionsView(state: state),
          1 => _AddressesView(state: state),
          2 => _CoinsView(state: state),
          _ => _DescriptorView(state: state),
        },
      ),
      floatingActionButton: state.selectedTab == 2
          ? _CreateTxFab(state: state)
          : null,
      bottomNavigationBar: NavigationBar(
        selectedIndex: state.selectedTab,
        onDestinationSelected: (index) =>
            context.read<WalletDetailCubit>().selectTab(index),
        destinations: [
          NavigationDestination(
            icon: const Icon(Icons.swap_horiz_outlined),
            selectedIcon: const Icon(Icons.swap_horiz),
            label: l10n.transactionsSection,
          ),
          NavigationDestination(
            icon: const Icon(Icons.account_balance_wallet_outlined),
            selectedIcon: const Icon(Icons.account_balance_wallet),
            label: l10n.addressesSection,
          ),
          NavigationDestination(
            icon: const Icon(Icons.toll_outlined),
            selectedIcon: const Icon(Icons.toll),
            label: l10n.coinsSection,
          ),
          NavigationDestination(
            icon: const Icon(Icons.schema_outlined),
            selectedIcon: const Icon(Icons.schema),
            label: l10n.descriptorTabLabel,
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────
// Transactions view (unchanged content, extracted to widget)
// ─────────────────────────────────────────────────────────────

class _TransactionsView extends StatelessWidget {
  final WalletDetailLoaded state;

  const _TransactionsView({required this.state});

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final network = state.walletInfo.network;

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        _BalanceCard(balance: state.balance),
        const SizedBox(height: 12),
        _SyncRow(
          walletInfo: state.walletInfo,
          isSyncing: state.isSyncing,
          network: network,
        ),
        const SizedBox(height: 16),
        Text(
          l10n.transactionsSection,
          style: Theme.of(context).textTheme.titleMedium?.copyWith(
                color: AppAccent.color,
                fontWeight: FontWeight.bold,
              ),
        ),
        const SizedBox(height: 8),
        // ── Unsigned transactions (PSBTs) ────────────────────────────────────
        ...state.psbts.map((psbt) {
          final analysis = state.psbtAnalyses[psbt.id.toInt()];
          return _PsbtTile(
            psbt: psbt,
            analysis: analysis,
            spendPaths: state.descriptorAnalysis?.spendPaths ?? [],
            keyLabels: state.keyLabels,
            pathLabels: state.pathLabels,
          );
        }),

        // ── Confirmed / mempool transactions ─────────────────────────────────
        if (state.transactions.isEmpty && state.psbts.isEmpty)
          Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Text(
                l10n.noTransactions,
                style: TextStyle(
                  color: Theme.of(context)
                      .colorScheme
                      .onSurface
                      .withAlpha(138),
                ),
              ),
            ),
          )
        else ...[
          ...([...state.transactions]
                ..sort((a, b) {
                  final aConfirmed = a.confirmationHeight != null;
                  final bConfirmed = b.confirmationHeight != null;
                  if (aConfirmed == bConfirmed) return 0;
                  return aConfirmed ? 1 : -1; // unconfirmed first
                }))
              .map((tx) => _TransactionTile(tx: tx, network: network)),
          if (state.hasMore)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: TextButton(
                onPressed: () => context
                    .read<WalletDetailCubit>()
                    .loadMoreTransactions(),
                child: Text(l10n.loadMore),
              ),
            ),
        ],
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────
// Addresses view
// ─────────────────────────────────────────────────────────────

class _AddressesView extends StatelessWidget {
  final WalletDetailLoaded state;

  const _AddressesView({required this.state});

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;

    return DefaultTabController(
      length: 2,
      initialIndex: state.selectedAddressKeychain,
      child: Column(
        children: [
          // Balance card + sync row at top
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
            child: Column(
              children: [
                _BalanceCard(balance: state.balance),
                const SizedBox(height: 12),
                _SyncRow(
                  walletInfo: state.walletInfo,
                  isSyncing: state.isSyncing,
                  network: state.walletInfo.network,
                ),
              ],
            ),
          ),
          // Receive / Change tab bar
          TabBar(
            onTap: (index) =>
                context.read<WalletDetailCubit>().selectAddressKeychain(index),
            tabs: [
              Tab(text: l10n.receiveAddresses),
              Tab(text: l10n.changeAddresses),
            ],
          ),
          Expanded(
            child: TabBarView(
              physics: const NeverScrollableScrollPhysics(),
              children: [
                _AddressList(
                  addresses: state.receiveAddresses,
                  loaded: state.receiveAddressesLoaded,
                  keychain: APIKeychain.external_,
                  network: state.walletInfo.network,
                ),
                _AddressList(
                  addresses: state.changeAddresses,
                  loaded: state.changeAddressesLoaded,
                  keychain: APIKeychain.internal,
                  network: state.walletInfo.network,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _AddressList extends StatelessWidget {
  final List<APIAddress> addresses;
  final bool loaded;
  final APIKeychain keychain;
  final APINetwork network;

  const _AddressList({
    required this.addresses,
    required this.loaded,
    required this.keychain,
    required this.network,
  });

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;

    if (!loaded) {
      return const Center(child: CircularProgressIndicator());
    }

    if (addresses.isEmpty) {
      return Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(
            l10n.noAddresses,
            textAlign: TextAlign.center,
            style: TextStyle(
              color: Theme.of(context).colorScheme.onSurface.withAlpha(138),
            ),
          ),
          const SizedBox(height: 16),
          FilledButton.tonal(
            onPressed: () =>
                context.read<WalletDetailCubit>().revealMoreAddresses(keychain),
            child: Text(l10n.revealMoreAddresses),
          ),
        ],
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      // +1 for the "reveal more" button at the end
      itemCount: addresses.length + 1,
      itemBuilder: (context, index) {
        if (index == addresses.length) {
          return Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: FilledButton.tonal(
              onPressed: () => context
                  .read<WalletDetailCubit>()
                  .revealMoreAddresses(keychain),
              child: Text(l10n.revealMoreAddresses),
            ),
          );
        }
        return _AddressTile(
          address: addresses[index],
          keychain: keychain,
          network: network,
        );
      },
    );
  }
}

class _AddressTile extends StatelessWidget {
  final APIAddress address;
  final APIKeychain keychain;
  final APINetwork network;

  const _AddressTile({
    required this.address,
    required this.keychain,
    required this.network,
  });

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final balanceSats = address.balanceSat.toInt();
    final hasBalance = balanceSats > 0;
    final isUsedEmpty = !hasBalance && address.isUsed;

    // Badge color: green = has funds, amber = used but empty, surface = fresh
    final badgeColor = hasBalance
        ? Colors.green
        : isUsedEmpty
            ? Colors.amber
            : Theme.of(context).colorScheme.onSurface.withAlpha(80);
    final badgeBg = hasBalance
        ? Colors.green.withAlpha(40)
        : isUsedEmpty
            ? Colors.amber.withAlpha(40)
            : Theme.of(context).colorScheme.surfaceContainerHighest;

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: badgeBg,
          child: Text(
            l10n.addressIndex(address.index.toInt()),
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.bold,
              color: badgeColor,
            ),
          ),
        ),
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (address.label?.isNotEmpty == true)
              Text(
                address.label!,
                style: const TextStyle(fontWeight: FontWeight.w500),
              ),
            ColoredAddressText(
              address: address.address,
              truncate: true,
            ),
          ],
        ),
        subtitle: hasBalance
            ? Text(
                l10n.addressBalanceSats(balanceSats),
                style: const TextStyle(
                  color: Colors.green,
                  fontWeight: FontWeight.w600,
                ),
              )
            : null,
        trailing: const Icon(Icons.chevron_right, size: 18),
        onTap: () => _showDetails(context),
      ),
    );
  }

  void _showDetails(BuildContext context) {
    showDialog<void>(
      context: context,
      builder: (ctx) => BlocProvider.value(
        value: context.read<WalletDetailCubit>(),
        child: _AddressDetailDialog(
          address: address,
          keychain: keychain,
          network: network,
        ),
      ),
    );
  }
}

class _AddressDetailDialog extends StatelessWidget {
  final APIAddress address;
  final APIKeychain keychain;
  final APINetwork network;

  const _AddressDetailDialog({
    required this.address,
    required this.keychain,
    required this.network,
  });

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final balanceSats = address.balanceSat.toInt();
    final settings = context.read<SettingsCubit>().state;
    final explorerUrl = settings.explorerAddressUrl(network, address.address);

    return AlertDialog(
      titlePadding: const EdgeInsets.fromLTRB(24, 16, 8, 0),
      title: Row(
        children: [
          Expanded(child: Text(l10n.addressDetailsTitle)),
          IconButton(
            icon: const Icon(Icons.close),
            tooltip: l10n.close,
            visualDensity: VisualDensity.compact,
            onPressed: () => Navigator.of(context).pop(),
          ),
        ],
      ),
      content: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            _DetailRow(
              label: l10n.addressLabelTitle,
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      address.label?.isNotEmpty == true ? address.label! : '—',
                      style: TextStyle(
                        color: address.label?.isNotEmpty == true
                            ? null
                            : Theme.of(context)
                                .colorScheme
                                .onSurface
                                .withAlpha(97),
                        fontStyle: address.label?.isNotEmpty == true
                            ? FontStyle.normal
                            : FontStyle.italic,
                      ),
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.edit, size: 16),
                    tooltip: l10n.edit,
                    onPressed: () {
                      Navigator.of(context).pop();
                      showDialog<void>(
                        context: context,
                        builder: (ctx) => BlocProvider.value(
                          value: context.read<WalletDetailCubit>(),
                          child: _AddressLabelEditDialog(
                            address: address.address,
                            keychain: keychain,
                            currentLabel: address.label ?? '',
                          ),
                        ),
                      );
                    },
                  ),
                ],
              ),
            ),
            _DetailRow(
              label: 'Index',
              child: Text(l10n.addressIndex(address.index.toInt())),
            ),
            _DetailRow(
              label: 'Address',
              child: Row(
                children: [
                  Expanded(
                    child: ColoredAddressText(address: address.address),
                  ),
                  IconButton(
                    icon: const Icon(Icons.share_outlined, size: 16),
                    tooltip: l10n.copyToClipboard,
                    visualDensity: VisualDensity.compact,
                    onPressed: () => showTextExportSheet(
                      context,
                      text: address.address,
                      fileName: 'address',
                      copiedMessage: l10n.copiedToClipboard,
                    ),
                  ),
                ],
              ),
            ),
            _DetailRow(
              label: l10n.balanceConfirmed,
              child: Text(
                l10n.addressBalanceSats(balanceSats),
                style: TextStyle(
                  color: balanceSats > 0 ? Colors.green : null,
                  fontWeight:
                      balanceSats > 0 ? FontWeight.bold : FontWeight.normal,
                ),
              ),
            ),
            if (address.txCount > 0)
              _DetailRow(
                label: l10n.transactionsSection,
                child: Text(l10n.addressTxCount(address.txCount.toInt())),
              ),
            if (explorerUrl.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Center(
                  child: FilledButton.icon(
                    onPressed: () => launchUrl(
                      Uri.parse(explorerUrl),
                      mode: LaunchMode.externalApplication,
                    ),
                    icon: const Icon(Icons.open_in_new, size: 16),
                    label: Text(l10n.openInExplorer),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _AddressLabelEditDialog extends StatefulWidget {
  final String address;
  final APIKeychain keychain;
  final String currentLabel;

  const _AddressLabelEditDialog({
    required this.address,
    required this.keychain,
    required this.currentLabel,
  });

  @override
  State<_AddressLabelEditDialog> createState() =>
      _AddressLabelEditDialogState();
}

class _AddressLabelEditDialogState extends State<_AddressLabelEditDialog> {
  late final TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.currentLabel);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _save(BuildContext context) {
    context.read<WalletDetailCubit>().setAddressLabel(
          widget.address,
          _controller.text.trim(),
          widget.keychain,
        );
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return AlertDialog(
      titlePadding: const EdgeInsets.fromLTRB(24, 16, 8, 0),
      title: Row(
        children: [
          Expanded(child: Text(l10n.addressLabelTitle)),
          IconButton(
            icon: const Icon(Icons.close),
            tooltip: l10n.cancel,
            visualDensity: VisualDensity.compact,
            onPressed: () => Navigator.of(context).pop(),
          ),
        ],
      ),
      content: TextField(
        controller: _controller,
        autofocus: true,
        decoration: InputDecoration(
          hintText: l10n.addressLabelHint,
          border: const OutlineInputBorder(),
        ),
        onSubmitted: (_) => _save(context),
      ),
      actions: [
        if (widget.currentLabel.isNotEmpty)
          TextButton(
            onPressed: () {
              context.read<WalletDetailCubit>().setAddressLabel(
                    widget.address,
                    '',
                    widget.keychain,
                  );
              Navigator.of(context).pop();
            },
            child: Text(
              l10n.addressLabelRemove,
              style: const TextStyle(color: Colors.red),
            ),
          ),
        FilledButton(
          onPressed: () => _save(context),
          child: Text(l10n.save),
        ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────
// Coins (UTXOs) view — with coin control selection
// ─────────────────────────────────────────────────────────────

class _CoinsView extends StatelessWidget {
  final WalletDetailLoaded state;

  const _CoinsView({required this.state});

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final network = state.walletInfo.network;

    if (!state.utxosLoaded) {
      return const Center(child: CircularProgressIndicator());
    }

    final utxos = state.utxos;
    final totalSats = utxos.fold<int>(0, (sum, u) => sum + u.valueSat.toInt());
    final selectedCount = state.selectedCoinIds.length;

    return ListView(
      // Extra bottom padding so the FAB doesn't cover the last item
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 100),
      children: [
        _BalanceCard(balance: state.balance),
        const SizedBox(height: 12),
        _SyncRow(
          walletInfo: state.walletInfo,
          isSyncing: state.isSyncing,
          network: network,
        ),
        const SizedBox(height: 16),
        Row(
          children: [
            Expanded(
              child: Text(
                selectedCount > 0
                    ? l10n.coinSelected(selectedCount)
                    : l10n.coinsSection,
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      color: selectedCount > 0
                          ? AppAccent.color
                          : AppAccent.color,
                      fontWeight: FontWeight.bold,
                    ),
              ),
            ),
            if (selectedCount > 0)
              TextButton(
                onPressed: () =>
                    context.read<WalletDetailCubit>().clearCoinSelection(),
                child: Text(l10n.coinSelectDone),
              )
            else if (utxos.isNotEmpty)
              Text(
                l10n.coinTotalCount(utxos.length),
                style: TextStyle(
                  fontSize: 12,
                  color: Theme.of(context).colorScheme.onSurface.withAlpha(138),
                ),
              ),
          ],
        ),
        if (utxos.isNotEmpty) ...[
          const SizedBox(height: 4),
          Text(
            l10n.coinTotalValue(totalSats),
            style: TextStyle(
              fontSize: 12,
              color: Theme.of(context).colorScheme.onSurface.withAlpha(138),
            ),
          ),
        ],
        const SizedBox(height: 8),
        if (utxos.isEmpty)
          Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Text(
                l10n.noCoins,
                style: TextStyle(
                  color: Theme.of(context).colorScheme.onSurface.withAlpha(138),
                ),
              ),
            ),
          )
        else
          ...utxos.map((utxo) {
            final coinId = '${utxo.txid}:${utxo.vout}';
            final isSelected = state.selectedCoinIds.contains(coinId);
            return _CoinTile(
              utxo: utxo,
              network: network,
              spendPaths: state.descriptorAnalysis?.spendPaths ?? [],
              tipHeight: state.tipHeight,
              keyLabels: state.keyLabels,
              isSelected: isSelected,
              onToggleSelect: () =>
                  context.read<WalletDetailCubit>().toggleCoinSelection(utxo),
            );
          }),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────
// Create Transaction FAB
// ─────────────────────────────────────────────────────────────

class _CreateTxFab extends StatelessWidget {
  final WalletDetailLoaded state;

  const _CreateTxFab({required this.state});

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final selectedCount = state.selectedCoinIds.length;

    final selectedUtxos = state.utxos
        .where((u) => state.selectedCoinIds.contains('${u.txid}:${u.vout}'))
        .toList();

    return FloatingActionButton.extended(
      onPressed: () {
        if (selectedUtxos.isEmpty) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(l10n.createTxSelectCoinsFirst),
              duration: const Duration(seconds: 2),
            ),
          );
          return;
        }
        CreateTxScreen.push(
          context,
          preSelectedUtxos: selectedUtxos,
          spendPaths: state.descriptorAnalysis?.spendPaths,
          keyLabels: state.keyLabels,
          pathLabels: state.pathLabels,
        );
      },
      icon: const Icon(Icons.send_outlined),
      label: Text(
        selectedCount > 0
            ? '${l10n.createTxTitle} ($selectedCount)'
            : l10n.createTxTitle,
      ),
    );
  }
}

class _CoinTile extends StatelessWidget {
  final APIUtxo utxo;
  final APINetwork network;
  final List<APISpendPath> spendPaths;
  final int tipHeight;
  final Map<String, String> keyLabels;
  final bool isSelected;
  final VoidCallback? onToggleSelect;

  const _CoinTile({
    required this.utxo,
    required this.network,
    required this.spendPaths,
    required this.tipHeight,
    required this.keyLabels,
    this.isSelected = false,
    this.onToggleSelect,
  });

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final sats = utxo.valueSat.toInt();
    final isChange = utxo.keychain == APIKeychain.internal;

    // Compute spend path statuses (only when we have paths with timelocks,
    // or always when spendPaths is non-empty so we show the summary)
    final statuses = spendPaths.isEmpty
        ? <(APISpendPath, SpendPathStatus)>[]
        : spendPaths
            .map((p) => (p, spendPathStatus(path: p, utxo: utxo, tipHeight: tipHeight)))
            .toList();

    final unlockedCount = statuses.where((s) => s.$2 is SpendPathUnlocked).length;
    final hasTimelocks = spendPaths.any(
      (p) => p.relTimelock.value > 0 || p.absTimelock.value > 0,
    );

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      color: isSelected
          ? Theme.of(context).colorScheme.primaryContainer.withAlpha(80)
          : null,
      child: ListTile(
        leading: onToggleSelect != null
            ? Checkbox(
                value: isSelected,
                onChanged: (_) => onToggleSelect!(),
              )
            : CircleAvatar(
                backgroundColor: isChange
                    ? Colors.amber.withAlpha(40)
                    : Colors.green.withAlpha(40),
                child: Icon(
                  isChange ? Icons.repeat : Icons.arrow_downward,
                  size: 18,
                  color: isChange ? Colors.amber : Colors.green,
                ),
              ),
        onTap: () => _showDetails(context, statuses),
        onLongPress: onToggleSelect,
        title: Text(
          '${BitcoinFormatter.formatNum(sats)} sats',
          style: const TextStyle(fontWeight: FontWeight.w600),
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ColoredAddressText(
              address: utxo.address,
              truncate: true,
            ),
            const SizedBox(height: 2),
            Row(
              children: [
                _StatusBadge(
                  label: utxo.isConfirmed ? l10n.txConfirmed : l10n.txUnconfirmed,
                  color: utxo.isConfirmed ? Colors.green : Colors.grey,
                ),
                const SizedBox(width: 6),
                _StatusBadge(
                  label: isChange ? l10n.coinKeychainChange : l10n.coinKeychainReceive,
                  color: isChange ? Colors.amber : Colors.green,
                ),
                // Show spend path summary only when there are timelocks
                if (hasTimelocks && spendPaths.isNotEmpty) ...[
                  const SizedBox(width: 6),
                  _SpendPathSummaryBadge(
                    unlockedCount: unlockedCount,
                    totalCount: spendPaths.length,
                  ),
                ],
              ],
            ),
          ],
        ),
        trailing: isSelected
            ? const Icon(Icons.check_circle, color: AppAccent.color, size: 20)
            : const Icon(Icons.chevron_right, size: 18),
      ),
    );
  }

  void _showDetails(
    BuildContext context,
    List<(APISpendPath, SpendPathStatus)> statuses,
  ) {
    showDialog<void>(
      context: context,
      builder: (ctx) => BlocProvider.value(
        value: context.read<WalletDetailCubit>(),
        child: _CoinDetailDialog(
          utxo: utxo,
          network: network,
          spendPathStatuses: statuses,
          keyLabels: keyLabels,
        ),
      ),
    );
  }
}

class _CoinDetailDialog extends StatelessWidget {
  final APIUtxo utxo;
  final APINetwork network;
  final List<(APISpendPath, SpendPathStatus)> spendPathStatuses;
  final Map<String, String> keyLabels;

  const _CoinDetailDialog({
    required this.utxo,
    required this.network,
    required this.spendPathStatuses,
    required this.keyLabels,
  });

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final settings = context.read<SettingsCubit>().state;
    final explorerUrl = settings.explorerTxUrl(network, utxo.txid);
    final isChange = utxo.keychain == APIKeychain.internal;
    final outpoint = '${utxo.txid}:${utxo.vout}';

    return AlertDialog(
      titlePadding: const EdgeInsets.fromLTRB(24, 16, 8, 0),
      title: Row(
        children: [
          Expanded(child: Text(l10n.coinDetailsTitle)),
          IconButton(
            icon: const Icon(Icons.close),
            tooltip: l10n.cancel,
            visualDensity: VisualDensity.compact,
            onPressed: () => Navigator.of(context).pop(),
          ),
        ],
      ),
      content: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            _DetailRow(
              label: l10n.coinValue,
              child: Text(
                '${BitcoinFormatter.formatNum(utxo.valueSat.toInt())} sats',
                style: const TextStyle(
                  fontWeight: FontWeight.bold,
                  color: Colors.green,
                ),
              ),
            ),
            _DetailRow(
              label: l10n.txConfirmed,
              child: Text(
                utxo.isConfirmed ? l10n.txConfirmed : l10n.txUnconfirmed,
                style: TextStyle(
                  color: utxo.isConfirmed ? Colors.green : Colors.grey,
                ),
              ),
            ),
            if (utxo.confirmationHeight != null)
              _DetailRow(
                label: l10n.txDetailsBlockHeight,
                child: Text('${utxo.confirmationHeight}'),
              ),
            _DetailRow(
              label: l10n.coinKeychain,
              child: Text(
                isChange ? l10n.coinKeychainChange : l10n.coinKeychainReceive,
              ),
            ),
            _DetailRow(
              label: l10n.coinAddress,
              child: Row(
                children: [
                  Expanded(
                    child: ColoredAddressText(address: utxo.address),
                  ),
                  IconButton(
                    icon: const Icon(Icons.share_outlined, size: 16),
                    tooltip: l10n.copyToClipboard,
                    visualDensity: VisualDensity.compact,
                    onPressed: () => showTextExportSheet(
                      context,
                      text: utxo.address,
                      fileName: 'address',
                      copiedMessage: l10n.copiedToClipboard,
                    ),
                  ),
                ],
              ),
            ),
            _DetailRow(
              label: l10n.coinOutpoint,
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      outpoint,
                      style: const TextStyle(fontFamily: 'monospace', fontSize: 11),
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.copy_outlined, size: 16),
                    tooltip: l10n.copyToClipboard,
                    visualDensity: VisualDensity.compact,
                    onPressed: () {
                      Clipboard.setData(ClipboardData(text: outpoint));
                      showSuccessToast(context, l10n.copiedToClipboard);
                    },
                  ),
                ],
              ),
            ),
            // ── Spend paths ───────────────────────────────────────────────
            if (spendPathStatuses.isNotEmpty) ...[
              const Divider(height: 20),
              Text(
                l10n.spendPathsAvailable,
                style: Theme.of(context).textTheme.labelLarge?.copyWith(
                      color: Theme.of(context).colorScheme.onSurface.withAlpha(178),
                    ),
              ),
              const SizedBox(height: 8),
              for (final (path, status) in spendPathStatuses)
                _SpendPathStatusRow(
                  path: path,
                  status: status,
                  keyLabels: keyLabels,
                ),
            ],
            if (explorerUrl.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Center(
                  child: FilledButton.icon(
                    onPressed: () => launchUrl(
                      Uri.parse(explorerUrl),
                      mode: LaunchMode.externalApplication,
                    ),
                    icon: const Icon(Icons.open_in_new, size: 16),
                    label: Text(l10n.openInExplorer),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────
// Shared widgets (balance card, sync row, tx tile, etc.)
// ─────────────────────────────────────────────────────────────

class _BalanceCard extends StatelessWidget {
  final APIBalance balance;

  const _BalanceCard({required this.balance});

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final totalSats = balance.confirmed +
        balance.trustedPending +
        balance.untrustedPending +
        balance.immature;
    final btcString =
        (totalSats.toDouble() / 100000000.0).toStringAsFixed(8);

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              l10n.balanceBtc(btcString),
              style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                _BalanceChip(
                  label: l10n.balanceConfirmed,
                  sats: balance.confirmed.toInt(),
                ),
                if (balance.trustedPending + balance.untrustedPending >
                    BigInt.zero) ...[
                  const SizedBox(width: 8),
                  _BalanceChip(
                    label: l10n.balancePending,
                    sats: (balance.trustedPending + balance.untrustedPending)
                        .toInt(),
                    dimmed: true,
                  ),
                ],
                if (balance.immature > BigInt.zero) ...[
                  const SizedBox(width: 8),
                  _BalanceChip(
                    label: l10n.balanceImmature,
                    sats: balance.immature.toInt(),
                    dimmed: true,
                  ),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _BalanceChip extends StatelessWidget {
  final String label;
  final int sats;
  final bool dimmed;

  const _BalanceChip({
    required this.label,
    required this.sats,
    this.dimmed = false,
  });

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: Theme.of(context).textTheme.labelSmall?.copyWith(
                color: Theme.of(context)
                    .colorScheme
                    .onSurface
                    .withAlpha(dimmed ? 97 : 178),
              ),
        ),
        Text(
          l10n.balanceSats(sats),
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: Theme.of(context)
                    .colorScheme
                    .onSurface
                    .withAlpha(dimmed ? 97 : 210),
              ),
        ),
      ],
    );
  }
}

class _SyncRow extends StatelessWidget {
  final APIWalletInfo walletInfo;
  final bool isSyncing;
  final APINetwork network;

  const _SyncRow({
    required this.walletInfo,
    required this.isSyncing,
    required this.network,
  });

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final settings = context.watch<SettingsCubit>().state;
    final electrumUrl = settings.electrumUrlForNetwork(network);

    final lastSynced = walletInfo.lastSyncedAt != null
        ? DateTime.fromMillisecondsSinceEpoch(walletInfo.lastSyncedAt! * 1000)
        : null;

    return Row(
      children: [
        Expanded(
          child: Text(
            lastSynced != null
                ? l10n.lastSynced(_formatDateTime(lastSynced))
                : l10n.notYetSynced,
            style: TextStyle(
              fontSize: 12,
              color:
                  Theme.of(context).colorScheme.onSurface.withAlpha(138),
            ),
          ),
        ),
        const SizedBox(width: 8),
        if (isSyncing)
          const SizedBox(
            width: 20,
            height: 20,
            child: CircularProgressIndicator(strokeWidth: 2),
          )
        else
          FilledButton.tonal(
            onPressed: () =>
                context.read<WalletDetailCubit>().sync(electrumUrl),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.sync, size: 18),
                const SizedBox(width: 8),
                Text(l10n.syncButton),
              ],
            ),
          ),
      ],
    );
  }

  String _formatDateTime(DateTime dt) {
    return '${dt.day}/${dt.month}/${dt.year} '
        '${dt.hour.toString().padLeft(2, '0')}:'
        '${dt.minute.toString().padLeft(2, '0')}';
  }
}

class _TransactionTile extends StatelessWidget {
  final APITransaction tx;
  final APINetwork network;

  const _TransactionTile({required this.tx, required this.network});

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final fee = tx.fee;
    final isSelfTransfer = tx.sent > BigInt.zero &&
        tx.received > BigInt.zero &&
        fee != null &&
        tx.sent - tx.received == fee;
    final isReceived = !isSelfTransfer && tx.received > tx.sent;
    final netSats = isSelfTransfer
        ? fee.toInt()
        : (isReceived ? tx.received - tx.sent : tx.sent - tx.received).toInt();
    final isConfirmed = tx.confirmationHeight != null;

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        leading: Icon(
          isSelfTransfer
              ? Icons.swap_horiz
              : isReceived
                  ? Icons.arrow_downward
                  : Icons.arrow_upward,
          color: isSelfTransfer
              ? Colors.blue
              : isReceived
                  ? Colors.green
                  : Colors.orange,
        ),
        title: GestureDetector(
          onTap: () => _editLabel(context),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                tx.label?.isNotEmpty == true
                    ? tx.label!
                    : isSelfTransfer
                        ? l10n.txSelfTransfer
                        : isReceived
                            ? l10n.txReceived
                            : l10n.txSent,
                style: const TextStyle(fontWeight: FontWeight.w500),
              ),
              if (tx.label?.isNotEmpty == true)
                Text(
                  isSelfTransfer
                      ? l10n.txSelfTransfer
                      : isReceived
                          ? l10n.txReceived
                          : l10n.txSent,
                  style: TextStyle(
                    fontSize: 11,
                    color: Theme.of(context)
                        .colorScheme
                        .onSurface
                        .withAlpha(138),
                  ),
                ),
            ],
          ),
        ),
        subtitle: Row(
          children: [
            Text(
              isSelfTransfer
                  ? '-${BitcoinFormatter.formatNum(netSats)} sats'
                  : '${isReceived ? '+' : '-'}${BitcoinFormatter.formatNum(netSats)} sats',
              style: TextStyle(
                color: isSelfTransfer
                    ? Colors.blue
                    : isReceived
                        ? Colors.green
                        : Colors.orange,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(width: 8),
            Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color:
                    (isConfirmed ? Colors.green : Colors.grey).withAlpha(40),
                borderRadius: BorderRadius.circular(4),
              ),
              child: Text(
                isConfirmed ? l10n.txConfirmed : l10n.txUnconfirmed,
                style: TextStyle(
                  fontSize: 10,
                  color: isConfirmed ? Colors.green : Colors.grey,
                ),
              ),
            ),
          ],
        ),
        trailing: const Icon(Icons.chevron_right, size: 18),
        onTap: () => _showDetails(context, isSelfTransfer, isReceived, netSats),
      ),
    );
  }

  void _editLabel(BuildContext context) {
    showDialog<void>(
      context: context,
      builder: (ctx) => BlocProvider.value(
        value: context.read<WalletDetailCubit>(),
        child: _LabelEditDialog(txid: tx.txid, currentLabel: tx.label ?? ''),
      ),
    );
  }

  void _showDetails(
    BuildContext context,
    bool isSelfTransfer,
    bool isReceived,
    int netSats,
  ) {
    showDialog<void>(
      context: context,
      builder: (ctx) => BlocProvider.value(
        value: context.read<WalletDetailCubit>(),
        child: _TxDetailDialog(
          tx: tx,
          network: network,
          isSelfTransfer: isSelfTransfer,
          isReceived: isReceived,
          netSats: netSats,
        ),
      ),
    );
  }
}

class _TxDetailDialog extends StatelessWidget {
  final APITransaction tx;
  final APINetwork network;
  final bool isSelfTransfer;
  final bool isReceived;
  final int netSats;

  const _TxDetailDialog({
    required this.tx,
    required this.network,
    required this.isSelfTransfer,
    required this.isReceived,
    required this.netSats,
  });

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final settings = context.read<SettingsCubit>().state;
    final explorerUrl = settings.explorerTxUrl(network, tx.txid);

    final confirmedAt = tx.confirmationTime != null
        ? DateTime.fromMillisecondsSinceEpoch(
            tx.confirmationTime!.toInt() * 1000)
        : null;

    final netLabel = isSelfTransfer
        ? '-${BitcoinFormatter.formatNum(netSats)} sats'
        : '${isReceived ? '+' : '-'}${BitcoinFormatter.formatNum(netSats)} sats';
    final netColor = isSelfTransfer
        ? Colors.blue
        : isReceived
            ? Colors.green
            : Colors.orange;

    return AlertDialog(
      titlePadding: const EdgeInsets.fromLTRB(24, 16, 8, 0),
      title: Row(
        children: [
          Expanded(child: Text(l10n.txDetailsTitle)),
          IconButton(
            icon: const Icon(Icons.close),
            tooltip: l10n.close,
            visualDensity: VisualDensity.compact,
            onPressed: () => Navigator.of(context).pop(),
          ),
        ],
      ),
      content: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            _DetailRow(
              label: l10n.txLabelTitle,
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      tx.label?.isNotEmpty == true ? tx.label! : '—',
                      style: TextStyle(
                        color: tx.label?.isNotEmpty == true
                            ? null
                            : Theme.of(context)
                                .colorScheme
                                .onSurface
                                .withAlpha(97),
                        fontStyle: tx.label?.isNotEmpty == true
                            ? FontStyle.normal
                            : FontStyle.italic,
                      ),
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.edit, size: 16),
                    tooltip: l10n.edit,
                    onPressed: () {
                      Navigator.of(context).pop();
                      showDialog<void>(
                        context: context,
                        builder: (ctx) => BlocProvider.value(
                          value: context.read<WalletDetailCubit>(),
                          child: _LabelEditDialog(
                            txid: tx.txid,
                            currentLabel: tx.label ?? '',
                          ),
                        ),
                      );
                    },
                  ),
                ],
              ),
            ),
            _DetailRow(
              label: l10n.txId,
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      tx.txid,
                      style: const TextStyle(
                          fontFamily: 'monospace', fontSize: 11),
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.copy_outlined, size: 16),
                    tooltip: l10n.copyToClipboard,
                    onPressed: () {
                      Clipboard.setData(ClipboardData(text: tx.txid));
                      showSuccessToast(context, l10n.copiedToClipboard);
                    },
                  ),
                ],
              ),
            ),
            _DetailRow(
              label: l10n.txDetailsNet,
              child: Text(
                netLabel,
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  color: netColor,
                ),
              ),
            ),
            if (tx.fee != null)
              _DetailRow(
                label: l10n.txDetailsFee,
                child: Text('${BitcoinFormatter.formatNum(tx.fee!.toInt())} sats'),
              ),
            _DetailRow(
              label: l10n.txDetailsGrossReceived,
              child: Text('${BitcoinFormatter.formatNum(tx.received.toInt())} sats'),
            ),
            _DetailRow(
              label: l10n.txDetailsGrossSent,
              child: Text('${BitcoinFormatter.formatNum(tx.sent.toInt())} sats'),
            ),
            _DetailRow(
              label: l10n.txConfirmed,
              child: Text(
                tx.confirmationHeight != null
                    ? l10n.txConfirmed
                    : l10n.txUnconfirmed,
                style: TextStyle(
                  color: tx.confirmationHeight != null
                      ? Colors.green
                      : Colors.grey,
                ),
              ),
            ),
            if (tx.confirmationHeight != null)
              _DetailRow(
                label: l10n.txDetailsBlockHeight,
                child: Text(BitcoinFormatter.formatNum(tx.confirmationHeight!.toInt())),
              ),
            if (confirmedAt != null)
              _DetailRow(
                label: l10n.txDetailsConfirmedAt,
                child: Text(_formatDateTime(confirmedAt)),
              ),
            if (explorerUrl.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Center(
                  child: FilledButton.icon(
                    onPressed: () => launchUrl(
                      Uri.parse(explorerUrl),
                      mode: LaunchMode.externalApplication,
                    ),
                    icon: const Icon(Icons.open_in_new, size: 16),
                    label: Text(l10n.openInExplorer),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  String _formatDateTime(DateTime dt) {
    return '${dt.day.toString().padLeft(2, '0')}/${dt.month.toString().padLeft(2, '0')}/${dt.year} '
        '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
  }
}

class _DetailRow extends StatelessWidget {
  final String label;
  final Widget child;

  const _DetailRow({required this.label, required this.child});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  color: Theme.of(context)
                      .colorScheme
                      .onSurface
                      .withAlpha(138),
                ),
          ),
          const SizedBox(height: 2),
          child,
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────
// Small status badge (confirmation, keychain)
// ─────────────────────────────────────────────────────────────

class _StatusBadge extends StatelessWidget {
  final String label;
  final Color color;

  const _StatusBadge({required this.label, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(top: 2),
      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
      decoration: BoxDecoration(
        color: color.withAlpha(40),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        label,
        style: TextStyle(fontSize: 10, color: color),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────
// Spend path summary badge shown on the coin tile
// ─────────────────────────────────────────────────────────────

class _SpendPathSummaryBadge extends StatelessWidget {
  final int unlockedCount;
  final int totalCount;

  const _SpendPathSummaryBadge({
    required this.unlockedCount,
    required this.totalCount,
  });

  @override
  Widget build(BuildContext context) {
    final allUnlocked = unlockedCount == totalCount;
    final color = allUnlocked ? Colors.green : AppAccent.color;
    return Container(
      margin: const EdgeInsets.only(top: 2),
      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
      decoration: BoxDecoration(
        color: color.withAlpha(40),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: color.withAlpha(80)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            allUnlocked ? Icons.lock_open : Icons.lock_outline,
            size: 9,
            color: color,
          ),
          const SizedBox(width: 3),
          Text(
            '$unlockedCount/$totalCount',
            style: TextStyle(
              fontSize: 10,
              color: color,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────
// Spend path status row shown inside the coin detail dialog
// ─────────────────────────────────────────────────────────────

class _SpendPathStatusRow extends StatelessWidget {
  final APISpendPath path;
  final SpendPathStatus status;
  final Map<String, String> keyLabels;

  const _SpendPathStatusRow({
    required this.path,
    required this.status,
    required this.keyLabels,
  });

  String _pathName() {
    if (path.mfps.isEmpty) return '…';
    final labels = path.mfps.map((m) => keyLabels[m] ?? m.toUpperCase()).toList();
    final prefix = path.threshold < path.mfps.length
        ? '${path.threshold}/${path.mfps.length} '
        : '';
    return '$prefix${labels.join(', ')}';
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final cs = Theme.of(context).colorScheme;

    final (icon, color, subtitle) = switch (status) {
      SpendPathUnlocked() => (
          Icons.lock_open,
          Colors.green,
          l10n.spendPathUnlocked,
        ),
      SpendPathNeedsConfirmation() => (
          Icons.hourglass_empty,
          Colors.amber,
          l10n.spendPathNeedsConfirmation,
        ),
      SpendPathAbsLocked(:final remainingBlocks, :final remainingSeconds) => (
          Icons.lock_outline,
          Colors.red,
          remainingBlocks != null
              ? l10n.spendPathLockedBlocks(remainingBlocks)
              : remainingSeconds != null
                  ? _formatRemainingTime(remainingSeconds)
                  : l10n.spendPathLocked,
        ),
      SpendPathRelLocked(:final remainingBlocks, :final remainingSeconds) => (
          Icons.lock_clock,
          Colors.orange,
          remainingBlocks != null
              ? l10n.spendPathLockedBlocks(remainingBlocks)
              : remainingSeconds != null
                  ? _formatRemainingTime(remainingSeconds)
                  : l10n.spendPathLocked,
        ),
    };

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 16, color: color),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _pathName(),
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                    color: cs.onSurface,
                  ),
                ),
                Text(
                  subtitle,
                  style: TextStyle(fontSize: 11, color: color),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  String _formatRemainingTime(int seconds) {
    if (seconds < 60) return '${seconds}s';
    if (seconds < 3600) return '${seconds ~/ 60}min';
    if (seconds < 86400) return '${seconds ~/ 3600}h';
    return '${seconds ~/ 86400}d';
  }
}

class _LabelEditDialog extends StatefulWidget {
  final String txid;
  final String currentLabel;

  const _LabelEditDialog({required this.txid, required this.currentLabel});

  @override
  State<_LabelEditDialog> createState() => _LabelEditDialogState();
}

class _LabelEditDialogState extends State<_LabelEditDialog> {
  late final TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.currentLabel);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _save(BuildContext context) {
    context
        .read<WalletDetailCubit>()
        .setTxLabel(widget.txid, _controller.text.trim());
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return AlertDialog(
      titlePadding: const EdgeInsets.fromLTRB(24, 16, 8, 0),
      title: Row(
        children: [
          Expanded(child: Text(l10n.txLabelTitle)),
          IconButton(
            icon: const Icon(Icons.close),
            tooltip: l10n.cancel,
            visualDensity: VisualDensity.compact,
            onPressed: () => Navigator.of(context).pop(),
          ),
        ],
      ),
      content: TextField(
        controller: _controller,
        autofocus: true,
        decoration: InputDecoration(
          hintText: l10n.txLabelHint,
          border: const OutlineInputBorder(),
        ),
        onSubmitted: (_) => _save(context),
      ),
      actions: [
        if (widget.currentLabel.isNotEmpty)
          TextButton(
            onPressed: () {
              context
                  .read<WalletDetailCubit>()
                  .setTxLabel(widget.txid, '');
              Navigator.of(context).pop();
            },
            child: Text(
              l10n.txLabelRemove,
              style: const TextStyle(color: Colors.red),
            ),
          ),
        FilledButton(
          onPressed: () => _save(context),
          child: Text(l10n.save),
        ),
      ],
    );
  }
}

enum _WalletMenuAction { rescan }

// ─────────────────────────────────────────────────────────────
// Descriptor view (tab 3)
// ─────────────────────────────────────────────────────────────

Color _walletColorForMfpIndex(BuildContext context, int index) {
  final ext = Theme.of(context).extension<KeyColorExtension>()!;
  return ext.keyColors[index % ext.keyColors.length];
}

class _DescriptorView extends StatelessWidget {
  final WalletDetailLoaded state;

  const _DescriptorView({required this.state});

  @override
  Widget build(BuildContext context) {
    if (!state.descriptorLoaded) {
      return const Center(child: CircularProgressIndicator());
    }

    final analysis = state.descriptorAnalysis;
    if (analysis == null) {
      return Center(
        child: Text(
          context.l10n.descriptorSectionTitle,
          style: TextStyle(
            color: Theme.of(context).colorScheme.onSurface.withAlpha(138),
          ),
        ),
      );
    }

    final isTaproot = analysis.walletType.name == 'p2Tr';

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        _buildDescriptorExpansion(context, analysis.descriptor),
        const SizedBox(height: 8),
        _WalletKeysSection(
          keys: analysis.keys,
          keyLabels: state.keyLabels,
          isTaproot: isTaproot,
        ),
        const SizedBox(height: 8),
        _WalletSpendPathsSection(
          paths: analysis.spendPaths,
          keys: analysis.keys,
          keyLabels: state.keyLabels,
          pathLabels: state.pathLabels,
          isTaproot: isTaproot,
        ),
      ],
    );
  }

  Widget _buildDescriptorExpansion(BuildContext context, String descriptor) {
    final l10n = context.l10n;
    return ExpansionTile(
      title: Text(
        l10n.descriptorSectionTitle,
        style: Theme.of(context).textTheme.titleMedium,
      ),
      tilePadding: EdgeInsets.zero,
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton(
            icon: const Icon(Icons.share_outlined, size: 16),
            tooltip: l10n.copyDescriptorTooltip,
            onPressed: () => showTextExportSheet(
              context,
              text: descriptor,
              fileName: 'descriptor',
              copiedMessage: l10n.descriptorCopied,
            ),
            visualDensity: VisualDensity.compact,
          ),
          const SizedBox(width: 8),
          const Icon(Icons.expand_more),
        ],
      ),
      children: [
        Padding(
          padding: const EdgeInsets.only(top: 8, bottom: 4),
          child: SelectableText(
            descriptor,
            style: TextStyle(
              fontFamily: 'monospace',
              fontSize: 12,
              color: Theme.of(context).colorScheme.onSurface.withAlpha(153),
            ),
          ),
        ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────
// Wallet keys section
// ─────────────────────────────────────────────────────────────

class _WalletKeysSection extends StatelessWidget {
  final List<APIPubKey> keys;
  final Map<String, String> keyLabels;
  final bool isTaproot;

  const _WalletKeysSection({
    required this.keys,
    required this.keyLabels,
    required this.isTaproot,
  });

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    if (keys.isEmpty) return const SizedBox.shrink();

    return ExpansionTile(
      title: Text(
        l10n.keysSection(keys.length),
        style: Theme.of(context).textTheme.titleMedium,
      ),
      tilePadding: EdgeInsets.zero,
      initiallyExpanded: true,
      children: [
        for (var i = 0; i < keys.length; i++)
          _WalletKeyCard(
            keyData: keys[i],
            mfpColor: _walletColorForMfpIndex(context, i),
            label: keyLabels[keys[i].mfp],
          ),
      ],
    );
  }
}

class _WalletKeyCard extends StatelessWidget {
  final APIPubKey keyData;
  final Color mfpColor;
  final String? label;

  const _WalletKeyCard({
    required this.keyData,
    required this.mfpColor,
    this.label,
  });

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final cs = Theme.of(context).colorScheme;

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header: MFP badge + label + copy
            Row(
              children: [
                MfpBadge(
                  label: keyData.mfp.toUpperCase(),
                  color: mfpColor,
                  letterSpacing: 0.5,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: GestureDetector(
                    onTap: () => _showLabelDialog(context),
                    child: Text(
                      label ?? l10n.tapToName,
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: label != null ? FontWeight.w600 : FontWeight.normal,
                        color: label != null
                            ? cs.onSurface
                            : cs.onSurface.withAlpha(97),
                        fontStyle: label != null ? FontStyle.normal : FontStyle.italic,
                      ),
                    ),
                  ),
                ),
                Icon(Icons.edit, size: 16, color: cs.onSurface.withAlpha(120)),
                IconButton(
                  icon: const Icon(Icons.share_outlined, size: 16),
                  tooltip: l10n.copyKeyspecTooltip,
                  visualDensity: VisualDensity.compact,
                  onPressed: () => showTextExportSheet(
                    context,
                    text: '[${keyData.mfp}/${keyData.derivationPath}]${keyData.xpub}',
                    fileName: 'keyspec',
                    copiedMessage: l10n.keyCopied,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            // Derivation path
            Row(
              children: [
                Text(
                  l10n.pathPrefix,
                  style: TextStyle(fontSize: 11, color: cs.onSurface.withAlpha(AppAlpha.muted)),
                ),
                Expanded(
                  child: Text(
                    keyData.derivationPath.isEmpty ? l10n.rootPath : keyData.derivationPath,
                    style: TextStyle(
                      fontSize: 12,
                      color: keyData.derivationPath.isEmpty
                          ? AppAccent.color
                          : cs.onSurface.withAlpha(AppAlpha.mediumHigh),
                      fontFamily: 'monospace',
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            // Xpub
            Row(
              children: [
                Text(
                  l10n.xpubPrefix,
                  style: TextStyle(fontSize: 11, color: cs.onSurface.withAlpha(AppAlpha.muted)),
                ),
                Expanded(
                  child: Text(
                    keyData.xpub,
                    style: TextStyle(
                      fontSize: 11,
                      color: cs.onSurface.withAlpha(AppAlpha.secondary),
                      fontFamily: 'monospace',
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  void _showLabelDialog(BuildContext context) {
    showEditNameDialog(
      context,
      title: context.l10n.keyNameDialogTitle,
      currentName: label,
      onSave: (name) =>
          context.read<WalletDetailCubit>().setWalletKeyLabel(keyData.mfp, name ?? ''),
    );
  }
}

// ─────────────────────────────────────────────────────────────
// Wallet spend paths section
// ─────────────────────────────────────────────────────────────

class _WalletSpendPathsSection extends StatelessWidget {
  final List<APISpendPath> paths;
  final List<APIPubKey> keys;
  final Map<String, String> keyLabels;
  final Map<int, String> pathLabels;
  final bool isTaproot;

  const _WalletSpendPathsSection({
    required this.paths,
    required this.keys,
    required this.keyLabels,
    required this.pathLabels,
    required this.isTaproot,
  });

  Color _colorForMfp(BuildContext context, String mfp) {
    final idx = keys.indexWhere((k) => k.mfp == mfp);
    return _walletColorForMfpIndex(context, idx < 0 ? 0 : idx);
  }

  String _keyLabel(String mfp) {
    return keyLabels[mfp] ?? mfp.toUpperCase();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    if (paths.isEmpty) return const SizedBox.shrink();

    return ExpansionTile(
      title: Text(
        l10n.spendPathsSection(paths.length),
        style: Theme.of(context).textTheme.titleMedium,
      ),
      tilePadding: EdgeInsets.zero,
      initiallyExpanded: true,
      children: [
        for (final path in paths)
          _WalletPathCard(
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

class _WalletPathCard extends StatelessWidget {
  final APISpendPath path;
  final String? label;
  final bool isTaproot;
  final Color Function(String mfp) mfpColorProvider;
  final String Function(String mfp) keyLabelProvider;

  const _WalletPathCard({
    required this.path,
    required this.isTaproot,
    required this.mfpColorProvider,
    required this.keyLabelProvider,
    this.label,
  });

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final cs = Theme.of(context).colorScheme;
    final isKeyPath = path.trDepth == -1;
    final hasRelTimelock = path.relTimelock.value > 0;
    final hasAbsTimelock = path.absTimelock.value > 0;
    final hasTimelock = hasRelTimelock || hasAbsTimelock;

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
        leading: _buildLeading(context),
        title: Padding(
          padding: const EdgeInsets.only(top: 4),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Name row + badges
              Row(
                children: [
                  Expanded(
                    child: GestureDetector(
                      onTap: () => _showLabelDialog(context),
                      child: Text(
                        label ?? l10n.tapToName,
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: label != null ? FontWeight.w600 : FontWeight.normal,
                          color: label != null
                              ? cs.onSurface
                              : cs.onSurface.withAlpha(97),
                          fontStyle: label != null ? FontStyle.normal : FontStyle.italic,
                        ),
                      ),
                    ),
                  ),
                  Icon(Icons.edit, size: 16, color: cs.onSurface.withAlpha(120)),
                  const SizedBox(width: 4),
                  if (hasTimelock) _buildTimelockBadge(context, hasRelTimelock),
                  if (isTaproot && isKeyPath) _buildKeyPathBadge(context),
                ],
              ),
              const SizedBox(height: 6),
              // MFP badges
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  for (final mfp in path.mfps)
                    MfpBadge(
                      label: keyLabelProvider(mfp),
                      color: mfpColorProvider(mfp),
                      letterSpacing: keyLabelProvider(mfp) == mfp.toUpperCase() ? 0.5 : 0.0,
                    ),
                ],
              ),
              // Fee metric
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Row(
                  children: [
                    const Icon(Icons.payments_outlined, size: 14, color: AppAccent.color),
                    const SizedBox(width: 4),
                    Text(
                      '${BitcoinFormatter.formatDouble(path.vbSweep, 2)} vB',
                      style: TextStyle(
                        fontSize: 11,
                        color: cs.onSurface.withAlpha(178),
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    if (path.trDepth >= 0) ...[
                      _buildSeparator(context),
                      const Icon(Icons.account_tree_outlined, size: 14, color: AppAccent.color),
                      const SizedBox(width: 4),
                      Text(
                        '${path.trDepth}',
                        style: TextStyle(fontSize: 11, color: cs.onSurface.withAlpha(178)),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildLeading(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final mfps = path.mfps;
    return Stack(
      alignment: Alignment.bottomCenter,
      clipBehavior: Clip.none,
      children: [
        CircleAvatar(
          radius: 18,
          backgroundColor: AppAccent.color.withAlpha(32),
          child: Icon(
            mfps.length == 1 ? Icons.key : Icons.diversity_3,
            color: AppAccent.color,
            size: 20,
          ),
        ),
        if (mfps.length > 1)
          Positioned(
            bottom: -10,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
              decoration: BoxDecoration(
                color: AppAccent.color.withAlpha(64),
                border: Border.all(color: AppAccent.color, width: 1),
                borderRadius: BorderRadius.circular(4),
              ),
              child: Text(
                '${path.threshold} of ${mfps.length}',
                style: TextStyle(
                  color: cs.onSurface.withAlpha(178),
                  fontSize: 10,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildTimelockBadge(BuildContext context, bool isRelative) {
    final hasRelTimelock = path.relTimelock.value > 0;
    final relType = path.relTimelock.timelockType == APIRelativeTimelockType.blocks
        ? RelativeTimelockType.blocks
        : RelativeTimelockType.time;
    final absType = path.absTimelock.timelockType == APIAbsoluteTimelockType.blocks
        ? AbsoluteTimelockType.blocks
        : AbsoluteTimelockType.timestamp;
    final label = hasRelTimelock
        ? BitcoinFormatter.formatRelativeTimelock(relType, path.relTimelock.value)
        : BitcoinFormatter.formatAbsoluteTimelock(absType, path.absTimelock.value);
    return Padding(
      padding: const EdgeInsets.only(left: 6),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
        decoration: BoxDecoration(
          color: AppAccent.color.withAlpha(24),
          borderRadius: BorderRadius.circular(4),
          border: Border.all(color: AppAccent.color.withAlpha(80)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              isRelative ? Icons.update : Icons.event_available,
              size: 10,
              color: AppAccent.color,
            ),
            const SizedBox(width: 3),
            Text(
              label,
              style: const TextStyle(
                fontSize: 9,
                fontWeight: FontWeight.bold,
                color: AppAccent.color,
                letterSpacing: 0.3,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildKeyPathBadge(BuildContext context) {
    final l10n = context.l10n;
    return Padding(
      padding: const EdgeInsets.only(left: 6),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
        decoration: BoxDecoration(
          color: Colors.blue.withAlpha(32),
          borderRadius: BorderRadius.circular(4),
          border: Border.all(color: Colors.blue.withAlpha(100)),
        ),
        child: Text(
          l10n.keyPathBadge,
          style: const TextStyle(
            fontSize: 9,
            fontWeight: FontWeight.bold,
            color: Colors.blue,
            letterSpacing: 0.5,
          ),
        ),
      ),
    );
  }

  Widget _buildSeparator(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8),
      child: Text(
        '|',
        style: TextStyle(color: Theme.of(context).colorScheme.onSurface.withAlpha(77)),
      ),
    );
  }

  void _showLabelDialog(BuildContext context) {
    showEditNameDialog(
      context,
      title: context.l10n.spendPathNameDialogTitle,
      currentName: label,
      onSave: (name) =>
          context.read<WalletDetailCubit>().setWalletPathLabel(path.id, name ?? ''),
    );
  }
}

// ─────────────────────────────────────────────────────────────
// PSBT tile — shown at the top of the transactions tab
// ─────────────────────────────────────────────────────────────

class _PsbtTile extends StatelessWidget {
  final APIPsbtInfo psbt;
  final APIPsbtAnalysis? analysis;
  final List<APISpendPath> spendPaths;
  final Map<String, String> keyLabels;
  final Map<int, String> pathLabels;

  const _PsbtTile({
    required this.psbt,
    required this.analysis,
    required this.spendPaths,
    required this.keyLabels,
    required this.pathLabels,
  });

  String _statusLabel(BuildContext context) {
    final l10n = context.l10n;
    if (analysis == null) return l10n.psbtStatusUnsigned;
    final signed = analysis!.signers.where((s) => s.hasSigned).length;
    if (analysis!.isFinalized || signed >= psbt.threshold.toInt()) {
      return l10n.psbtStatusSigned;
    }
    if (signed > 0) return l10n.psbtStatusPartial;
    return l10n.psbtStatusUnsigned;
  }

  Color _statusColor(BuildContext context) {
    if (analysis == null) return Theme.of(context).colorScheme.outline;
    final signed = analysis!.signers.where((s) => s.hasSigned).length;
    if (analysis!.isFinalized || signed >= psbt.threshold.toInt()) {
      return Colors.green;
    }
    if (signed > 0) return Colors.orange;
    return Theme.of(context).colorScheme.outline;
  }

  APISpendPath? _findSpendPath() {
    try {
      return spendPaths.firstWhere((p) => p.id == psbt.spendPathId.toInt());
    } catch (_) {
      return spendPaths.isNotEmpty ? spendPaths.first : null;
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final statusColor = _statusColor(context);
    final statusLabel = _statusLabel(context);
    final signed = analysis?.signers.where((s) => s.hasSigned).length ?? 0;

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: statusColor.withAlpha(40),
          child: Icon(Icons.lock_clock_outlined, size: 18, color: statusColor),
        ),
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                border: Border.all(color: statusColor),
                borderRadius: BorderRadius.circular(4),
              ),
              child: Text(
                statusLabel,
                style: TextStyle(
                  color: statusColor,
                  fontFamily: 'monospace',
                  fontSize: 10,
                  letterSpacing: 0.5,
                ),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Row(
                children: [
                  Text('→ ', style: Theme.of(context).textTheme.bodySmall),
                  Expanded(
                    child: ColoredAddressText(
                      address: psbt.recipient,
                      truncate: true,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        subtitle: Text(
          '${BitcoinFormatter.formatNum(psbt.amountSat.toInt())} sats'
          ' · ${l10n.psbtSignaturesTitle(signed, psbt.threshold, psbt.mfps.length)}',
          style: TextStyle(
            fontSize: 11,
            color: theme.colorScheme.onSurface.withAlpha(150),
          ),
        ),
        trailing: const Icon(Icons.chevron_right, size: 18),
        onTap: () {
          Navigator.of(context).push(
            MaterialPageRoute(
              builder: (_) => BlocProvider.value(
                value: context.read<WalletDetailCubit>(),
                child: PsbtDetailScreen(
                  psbt: psbt,
                  spendPath: _findSpendPath(),
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}
