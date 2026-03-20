import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:url_launcher/url_launcher.dart';

import 'package:deadbolt/cubit/settings_cubit.dart';
import 'package:deadbolt/cubit/wallet_detail_cubit.dart';
import 'package:deadbolt/l10n/l10n.dart';
import 'package:deadbolt/screens/psbt_detail_screen.dart';
import 'package:deadbolt/src/rust/api/model.dart';
import 'package:deadbolt/theme/app_theme.dart';
import 'package:deadbolt/utils/bitcoin_formatter.dart';
import 'package:deadbolt/utils/spend_path_unlock.dart';
import 'package:deadbolt/utils/toast_helper.dart';
import 'package:deadbolt/widgets/colored_address_text.dart';
import 'package:deadbolt/widgets/dialog_helpers.dart';
import 'package:deadbolt/widgets/hw_wallet_sheet.dart' show showHwVerifyAddressSheet;
import 'package:deadbolt/widgets/outpoint_text.dart';
import 'package:deadbolt/widgets/text_export_sheet.dart' show showTextExportSheet;

// ─────────────────────────────────────────────────────────────
// Dialog helper — preserves the WalletDetailCubit across dialog pushes
// ─────────────────────────────────────────────────────────────

/// Show a dialog that inherits the current [WalletDetailCubit] from [context].
void showWalletDialog(BuildContext context, Widget child) {
  final cubit = context.read<WalletDetailCubit>();
  showDialog<void>(
    context: context,
    builder: (ctx) => BlocProvider.value(value: cubit, child: child),
  );
}

// ─────────────────────────────────────────────────────────────
// Address detail dialog
// ─────────────────────────────────────────────────────────────

class AddressDetailDialog extends StatefulWidget {
  final APIAddress address;
  final APIKeychain keychain;
  final APINetwork network;

  const AddressDetailDialog({
    super.key,
    required this.address,
    required this.keychain,
    required this.network,
  });

  @override
  State<AddressDetailDialog> createState() => _AddressDetailDialogState();
}

class _AddressDetailDialogState extends State<AddressDetailDialog> {
  late final Future<APIAddressDetails> _future;

  @override
  void initState() {
    super.initState();
    _future = (context.read<WalletDetailCubit>().state as WalletDetailLoaded)
        .walletHandle
        .getAddressDetails(address: widget.address.address);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final address = widget.address;
    final keychain = widget.keychain;
    final network = widget.network;
    final balanceSats = address.balanceSat.toInt();
    final settings = context.read<SettingsCubit>().state;
    final explorerUrl = settings.explorerAddressUrl(network, address.address);
    final walletState = context.read<WalletDetailCubit>().state;
    final descriptor = walletState is WalletDetailLoaded
        ? walletState.walletInfo.descriptor
        : '';

    return AlertDialog(
      titlePadding: kDialogTitlePadding,
      title: dialogCloseTitle(l10n.addressDetailsTitle,
          onClose: () => Navigator.of(context).pop(), tooltip: l10n.close),
      content: SingleChildScrollView(
        child: SizedBox(
          width: double.maxFinite,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _DetailRow(
                label: l10n.addressLabelTitle,
                child: Row(
                  children: [
                    Expanded(
                      child: _LiveEffectiveLabelText(
                        resolve: (s) {
                          final match = [
                            ...s.receiveAddresses,
                            ...s.changeAddresses,
                          ]
                              .where((a) =>
                                  a.address == widget.address.address)
                              .firstOrNull;
                          final item = match ?? widget.address;
                          return (item.effectiveLabel, item.isAuto);
                        },
                        fallbackLabel: widget.address.effectiveLabel,
                        fallbackIsAuto: widget.address.isAuto,
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.edit, size: 16),
                      tooltip: l10n.edit,
                      onPressed: () {
                        final cubit = context.read<WalletDetailCubit>();
                        final l10n = context.l10n;
                        showWalletDialog(
                          context,
                          _LabelDialog(
                            title: l10n.addressLabelTitle,
                            hintText: l10n.addressLabelHint,
                            currentLabel: address.label ?? '',
                            removeLabel: l10n.addressLabelRemove,
                            onSave: (label) => cubit.setAddressLabel(
                                address.address, label, keychain),
                            onRemove: () => cubit.setAddressLabel(
                                address.address, '', keychain),
                          ),
                        );
                      },
                    ),
                  ],
                ),
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
              _DetailRowPair(
                label1: 'Index',
                child1: Text(l10n.addressIndex(address.index.toInt())),
                label2: l10n.balanceConfirmed,
                child2: Text(
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
              FutureBuilder<APIAddressDetails>(
                future: _future,
                builder: (context, snapshot) {
                  if (snapshot.connectionState == ConnectionState.waiting) {
                    return const LinearProgressIndicator();
                  }
                  if (!snapshot.hasData) return const SizedBox.shrink();
                  final details = snapshot.data!;
                  final relatedUtxos = details.relatedUtxos;
                  final relatedTxs = details.relatedTxs;
                  if (relatedUtxos.isEmpty && relatedTxs.isEmpty) {
                    return const SizedBox.shrink();
                  }
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (relatedUtxos.isNotEmpty) ...[
                        const Divider(height: 20),
                        Text(
                          l10n.relatedCoins,
                          style: Theme.of(context)
                              .textTheme
                              .labelLarge
                              ?.copyWith(
                                color: Theme.of(context)
                                    .colorScheme
                                    .onSurface
                                    .withAlpha(AppAlpha.mediumHigh),
                              ),
                        ),
                        const SizedBox(height: 6),
                        for (final u in relatedUtxos)
                          _RelatedCoinRow(utxo: u),
                      ],
                      if (relatedTxs.isNotEmpty) ...[
                        const Divider(height: 20),
                        Text(
                          l10n.relatedTransactions,
                          style: Theme.of(context)
                              .textTheme
                              .labelLarge
                              ?.copyWith(
                                color: Theme.of(context)
                                    .colorScheme
                                    .onSurface
                                    .withAlpha(AppAlpha.mediumHigh),
                              ),
                        ),
                        const SizedBox(height: 6),
                        for (final t in relatedTxs) _RelatedTxRow(tx: t),
                      ],
                    ],
                  );
                },
              ),
              Padding(
                padding: const EdgeInsets.only(top: 12),
                child: Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: () => showHwVerifyAddressSheet(
                          context,
                          descriptor: descriptor,
                          network: network,
                          keychain: keychain,
                          index: address.index,
                          address: address.address,
                        ),
                        icon: const Icon(Icons.memory, size: 16),
                        label: const Text('Verify on device'),
                      ),
                    ),
                    if (explorerUrl.isNotEmpty) ...[
                      const SizedBox(width: 8),
                      Expanded(
                        child: FilledButton.icon(
                          onPressed: () => launchUrl(
                            Uri.parse(explorerUrl),
                            mode: LaunchMode.externalApplication,
                          ),
                          icon: const Icon(Icons.open_in_new, size: 16),
                          label: Text(l10n.openInExplorer),
                        ),
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
}

// ─────────────────────────────────────────────────────────────
// Coin detail dialog
// ─────────────────────────────────────────────────────────────

class CoinDetailDialog extends StatefulWidget {
  final APIUtxo utxo;
  final APINetwork network;
  final List<(APISpendPath, SpendPathStatus)> spendPathStatuses;
  final Map<String, String> keyLabels;

  const CoinDetailDialog({
    super.key,
    required this.utxo,
    required this.network,
    required this.spendPathStatuses,
    required this.keyLabels,
  });

  @override
  State<CoinDetailDialog> createState() => _CoinDetailDialogState();
}

class _CoinDetailDialogState extends State<CoinDetailDialog> {
  late final Future<APIUtxoDetails> _future;

  @override
  void initState() {
    super.initState();
    _future = (context.read<WalletDetailCubit>().state as WalletDetailLoaded)
        .walletHandle
        .getUtxoDetails(txid: widget.utxo.txid, vout: widget.utxo.vout);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final utxo = widget.utxo;
    final network = widget.network;
    final spendPathStatuses = widget.spendPathStatuses;
    final keyLabels = widget.keyLabels;
    final settings = context.read<SettingsCubit>().state;
    final explorerUrl = settings.explorerTxUrl(network, utxo.txid);
    final isChange = utxo.keychain == APIKeychain.internal;
    final outpoint = '${utxo.txid}:${utxo.vout}';

    return AlertDialog(
      titlePadding: kDialogTitlePadding,
      title: dialogCloseTitle(l10n.coinDetailsTitle,
          onClose: () => Navigator.of(context).pop(), tooltip: l10n.cancel),
      content: SingleChildScrollView(
        child: SizedBox(
          width: double.maxFinite,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _DetailRow(
                label: l10n.coinLabelTitle,
                child: Row(
                  children: [
                    Expanded(
                      child: _LiveEffectiveLabelText(
                        resolve: (s) {
                          final match = s.utxos
                              .where((u) =>
                                  u.txid == widget.utxo.txid &&
                                  u.vout == widget.utxo.vout)
                              .firstOrNull;
                          final item = match ?? widget.utxo;
                          return (item.effectiveLabel, item.isAuto);
                        },
                        fallbackLabel: widget.utxo.effectiveLabel,
                        fallbackIsAuto: widget.utxo.isAuto,
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.edit, size: 16),
                      tooltip: l10n.edit,
                      onPressed: () {
                        final cubit = context.read<WalletDetailCubit>();
                        final l10n = context.l10n;
                        showWalletDialog(
                          context,
                          _LabelDialog(
                            title: l10n.coinLabelTitle,
                            hintText: l10n.coinLabelHint,
                            currentLabel: utxo.label ?? '',
                            removeLabel: l10n.coinLabelRemove,
                            onSave: (label) =>
                                cubit.setCoinLabel(utxo.txid, utxo.vout, label),
                            onRemove: () =>
                                cubit.setCoinLabel(utxo.txid, utxo.vout, ''),
                          ),
                        );
                      },
                    ),
                  ],
                ),
              ),
              _DetailRowPair(
                label1: l10n.coinValue,
                child1: Text(
                  '${BitcoinFormatter.formatNum(utxo.valueSat.toInt())} sats',
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    color: Colors.green,
                  ),
                ),
                label2: l10n.txConfirmed,
                child2: Text(
                  utxo.isConfirmed ? l10n.txConfirmed : l10n.txUnconfirmed,
                  style: TextStyle(
                    color: utxo.isConfirmed ? Colors.green : Colors.grey,
                  ),
                ),
              ),
              if (utxo.confirmationHeight != null)
                _DetailRowPair(
                  label1: l10n.txDetailsBlockHeight,
                  child1: Text('${utxo.confirmationHeight}'),
                  label2: l10n.coinKeychain,
                  child2: Text(
                    isChange
                        ? l10n.coinKeychainChange
                        : l10n.coinKeychainReceive,
                  ),
                )
              else
                _DetailRow(
                  label: l10n.coinKeychain,
                  child: Text(
                    isChange
                        ? l10n.coinKeychainChange
                        : l10n.coinKeychainReceive,
                  ),
                ),
              _DetailRow(
                label: l10n.coinOutpoint,
                child: Row(
                  children: [
                    Expanded(
                      child: OutpointText(
                          txid: utxo.txid, vout: utxo.vout, truncate: false),
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
              _DetailRow(
                label: l10n.coinAddress,
                child: Row(
                  children: [
                    Expanded(
                      child: InkWell(
                        onTap: () {
                          Navigator.of(context).pop();
                          showWalletDialog(
                              context,
                              _AddressDetailByStringDialog(
                                  address: utxo.address));
                        },
                        borderRadius: BorderRadius.circular(4),
                        child: FutureBuilder<APIUtxoDetails>(
                          future: _future,
                          builder: (ctx, snap) {
                            final lbl = snap.data?.addressEffectiveLabel;
                            return Row(
                              children: [
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      if (lbl != null && lbl.isNotEmpty)
                                        Padding(
                                          padding: const EdgeInsets.only(
                                              bottom: 2),
                                          child: _EffectiveLabelText(
                                            effectiveLabel: lbl,
                                            isAuto:
                                                snap.data!.addressLabelIsAuto,
                                          ),
                                        ),
                                      ColoredAddressText(
                                          address: utxo.address),
                                    ],
                                  ),
                                ),
                                const Icon(Icons.chevron_right, size: 14),
                              ],
                            );
                          },
                        ),
                      ),
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
              FutureBuilder<APIUtxoDetails>(
                future: _future,
                builder: (context, snapshot) {
                  if (snapshot.connectionState == ConnectionState.waiting) {
                    return const LinearProgressIndicator();
                  }
                  if (!snapshot.hasData) return const SizedBox.shrink();
                  final ctxo = snapshot.data!.creatingTx;
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Divider(height: 20),
                      Text(
                        l10n.relatedTransactions,
                        style:
                            Theme.of(context).textTheme.labelLarge?.copyWith(
                          color: Theme.of(context)
                              .colorScheme
                              .onSurface
                              .withAlpha(AppAlpha.mediumHigh),
                        ),
                      ),
                      const SizedBox(height: 6),
                      _RelatedTxRow(tx: ctxo),
                    ],
                  );
                },
              ),
              if (spendPathStatuses.isNotEmpty) ...[
                const Divider(height: 20),
                Text(
                  l10n.spendPathsAvailable,
                  style: Theme.of(context).textTheme.labelLarge?.copyWith(
                    color: Theme.of(context)
                        .colorScheme
                        .onSurface
                        .withAlpha(AppAlpha.mediumHigh),
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
              Builder(builder: (context) {
                final cubitState =
                    context.watch<WalletDetailCubit>().state;
                if (cubitState is! WalletDetailLoaded) {
                  return const SizedBox.shrink();
                }
                final pendingIds =
                    utxo.pendingPsbtIds.map((id) => id.toInt()).toSet();
                final pendingPsbts = cubitState.psbts
                    .where((p) => pendingIds.contains(p.id.toInt()))
                    .toList();
                if (pendingPsbts.isEmpty) return const SizedBox.shrink();
                final labelStyle =
                    Theme.of(context).textTheme.labelLarge?.copyWith(
                  color: Theme.of(context)
                      .colorScheme
                      .onSurface
                      .withAlpha(AppAlpha.mediumHigh),
                );
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Divider(height: 20),
                    Text(l10n.coinPendingPsbtsSection, style: labelStyle),
                    const SizedBox(height: 8),
                    for (final psbt in pendingPsbts)
                      _PendingPsbtRow(psbt: psbt),
                  ],
                );
              }),
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
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────
// Transaction detail dialog
// ─────────────────────────────────────────────────────────────

class TxDetailDialog extends StatefulWidget {
  final APITransaction tx;
  final APINetwork network;
  final bool isSelfTransfer;
  final bool isReceived;
  final int netSats;

  const TxDetailDialog({
    super.key,
    required this.tx,
    required this.network,
    required this.isSelfTransfer,
    required this.isReceived,
    required this.netSats,
  });

  @override
  State<TxDetailDialog> createState() => _TxDetailDialogState();
}

class _TxDetailDialogState extends State<TxDetailDialog> {
  late final Future<APITxDetails> _future;

  @override
  void initState() {
    super.initState();
    _future = (context.read<WalletDetailCubit>().state as WalletDetailLoaded)
        .walletHandle
        .getTxDetails(txid: widget.tx.txid);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final tx = widget.tx;
    final network = widget.network;
    final isSelfTransfer = widget.isSelfTransfer;
    final isReceived = widget.isReceived;
    final netSats = widget.netSats;
    final settings = context.read<SettingsCubit>().state;
    final explorerUrl = settings.explorerTxUrl(network, tx.txid);

    final confirmedAt = tx.confirmationTime != null
        ? DateTime.fromMillisecondsSinceEpoch(
            tx.confirmationTime!.toInt() * 1000,
          )
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
      titlePadding: kDialogTitlePadding,
      title: dialogCloseTitle(l10n.txDetailsTitle,
          onClose: () => Navigator.of(context).pop(), tooltip: l10n.close),
      content: SingleChildScrollView(
        child: SizedBox(
          width: double.maxFinite,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _DetailRow(
                label: l10n.txLabelTitle,
                child: Row(
                  children: [
                    Expanded(
                      child: _LiveEffectiveLabelText(
                        resolve: (s) {
                          final match = s.transactions
                              .where((t) => t.txid == widget.tx.txid)
                              .firstOrNull;
                          final item = match ?? widget.tx;
                          return (item.effectiveLabel, item.isAuto);
                        },
                        fallbackLabel: widget.tx.effectiveLabel,
                        fallbackIsAuto: widget.tx.isAuto,
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.edit, size: 16),
                      tooltip: l10n.edit,
                      onPressed: () {
                        final cubit = context.read<WalletDetailCubit>();
                        final l10n = context.l10n;
                        showWalletDialog(
                          context,
                          _LabelDialog(
                            title: l10n.txLabelTitle,
                            hintText: l10n.txLabelHint,
                            currentLabel: tx.label ?? '',
                            removeLabel: l10n.txLabelRemove,
                            onSave: (label) =>
                                cubit.setTxLabel(tx.txid, label),
                            onRemove: () => cubit.setTxLabel(tx.txid, ''),
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
                      child: OutpointText(txid: tx.txid, truncate: false),
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
              if (tx.fee != null)
                _DetailRowPair(
                  label1: l10n.txDetailsNet,
                  child1: Text(
                    netLabel,
                    style: TextStyle(
                        fontWeight: FontWeight.bold, color: netColor),
                  ),
                  label2: l10n.txDetailsFee,
                  child2: Text(
                    '${BitcoinFormatter.formatNum(tx.fee!.toInt())} sats',
                  ),
                )
              else
                _DetailRow(
                  label: l10n.txDetailsNet,
                  child: Text(
                    netLabel,
                    style: TextStyle(
                        fontWeight: FontWeight.bold, color: netColor),
                  ),
                ),
              _DetailRowPair(
                label1: l10n.txDetailsGrossReceived,
                child1: Text(
                  '${BitcoinFormatter.formatNum(tx.received.toInt())} sats',
                ),
                label2: l10n.txDetailsGrossSent,
                child2: Text(
                  '${BitcoinFormatter.formatNum(tx.sent.toInt())} sats',
                ),
              ),
              if (tx.confirmationHeight != null) ...[
                _DetailRowPair(
                  label1: l10n.txConfirmed,
                  child1: const Text(
                    'Confirmed',
                    style: TextStyle(color: Colors.green),
                  ),
                  label2: l10n.txDetailsBlockHeight,
                  child2: Text(
                    BitcoinFormatter.formatNum(
                        tx.confirmationHeight!.toInt()),
                  ),
                ),
                if (confirmedAt != null)
                  _DetailRow(
                    label: l10n.txDetailsConfirmedAt,
                    child: Text(_formatDateTime(confirmedAt)),
                  ),
              ] else
                _DetailRow(
                  label: l10n.txConfirmed,
                  child: Text(
                    l10n.txUnconfirmed,
                    style: const TextStyle(color: Colors.grey),
                  ),
                ),
              FutureBuilder<APITxDetails>(
                future: _future,
                builder: (context, snapshot) {
                  if (snapshot.connectionState == ConnectionState.waiting) {
                    return const LinearProgressIndicator();
                  }
                  if (!snapshot.hasData) return const SizedBox.shrink();
                  final details = snapshot.data!;
                  final relatedUtxos = details.relatedUtxos;
                  final inputAddresses = details.inputAddresses;
                  final outputAddresses = details.outputAddresses;
                  if (relatedUtxos.isEmpty &&
                      inputAddresses.isEmpty &&
                      outputAddresses.isEmpty) {
                    return const SizedBox.shrink();
                  }
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (relatedUtxos.isNotEmpty) ...[
                        const Divider(height: 20),
                        Text(
                          l10n.relatedCoins,
                          style: Theme.of(context)
                              .textTheme
                              .labelLarge
                              ?.copyWith(
                                color: Theme.of(context)
                                    .colorScheme
                                    .onSurface
                                    .withAlpha(AppAlpha.mediumHigh),
                              ),
                        ),
                        const SizedBox(height: 6),
                        for (final u in relatedUtxos)
                          _RelatedCoinRow(utxo: u),
                      ],
                      if (inputAddresses.isNotEmpty) ...[
                        const Divider(height: 20),
                        Text(
                          l10n.inputAddresses,
                          style: Theme.of(context)
                              .textTheme
                              .labelLarge
                              ?.copyWith(
                                color: Theme.of(context)
                                    .colorScheme
                                    .onSurface
                                    .withAlpha(AppAlpha.mediumHigh),
                              ),
                        ),
                        const SizedBox(height: 6),
                        for (final a in inputAddresses)
                          _RelatedAddressRow(address: a),
                      ],
                      if (outputAddresses.isNotEmpty) ...[
                        const Divider(height: 20),
                        Text(
                          l10n.relatedAddresses,
                          style: Theme.of(context)
                              .textTheme
                              .labelLarge
                              ?.copyWith(
                                color: Theme.of(context)
                                    .colorScheme
                                    .onSurface
                                    .withAlpha(AppAlpha.mediumHigh),
                              ),
                        ),
                        const SizedBox(height: 6),
                        for (final a in outputAddresses)
                          _RelatedAddressRow(address: a),
                      ],
                    ],
                  );
                },
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
      ),
    );
  }

  String _formatDateTime(DateTime dt) {
    return '${dt.day.toString().padLeft(2, '0')}/${dt.month.toString().padLeft(2, '0')}/${dt.year} '
        '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
  }
}

// ─────────────────────────────────────────────────────────────
// Related-entity rows
// ─────────────────────────────────────────────────────────────

class _RelatedAddressRow extends StatelessWidget {
  final APIRelatedAddress address;
  const _RelatedAddressRow({required this.address});

  void _showDetail(BuildContext context) {
    Navigator.of(context).pop();
    showWalletDialog(
        context, _AddressDetailByStringDialog(address: address.address));
  }

  @override
  Widget build(BuildContext context) {
    final a = address;
    final hasLabel = a.effectiveLabel?.isNotEmpty == true;
    final scheme = Theme.of(context).colorScheme;
    final inner = Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        children: [
          Icon(
            a.isMine
                ? Icons.account_balance_wallet_outlined
                : Icons.question_mark,
            size: 14,
          ),
          const SizedBox(width: 6),
          Expanded(
            child: hasLabel
                ? Text(
                    a.effectiveLabel!,
                    style: a.isAuto
                        ? TextStyle(
                            fontSize: 12,
                            fontStyle: FontStyle.italic,
                            color: scheme.outline,
                          )
                        : const TextStyle(
                            fontSize: 12, fontWeight: FontWeight.w500),
                    overflow: TextOverflow.ellipsis,
                  )
                : ColoredAddressText(address: a.address, truncate: true),
          ),
          const SizedBox(width: 6),
          if (a.valueSat != null)
            Text(
              '${BitcoinFormatter.formatNum(a.valueSat!.toInt())} sats',
              style: const TextStyle(fontSize: 11),
            )
          else
            Text(
              '? sats',
              style: TextStyle(
                fontSize: 11,
                color: Theme.of(context)
                    .colorScheme
                    .onSurface
                    .withAlpha(AppAlpha.muted),
                fontStyle: FontStyle.italic,
              ),
            ),
          if (a.isMine) ...[
            const SizedBox(width: 4),
            const Icon(Icons.chevron_right, size: 14),
          ],
        ],
      ),
    );
    if (a.isMine) {
      return InkWell(
        onTap: () => _showDetail(context),
        borderRadius: BorderRadius.circular(4),
        child: inner,
      );
    }
    return inner;
  }
}

class _RelatedCoinRow extends StatelessWidget {
  final APIRelatedUtxo utxo;
  const _RelatedCoinRow({required this.utxo});

  void _showDetail(BuildContext context) {
    Navigator.of(context).pop();
    showWalletDialog(context,
        _CoinDetailByOutpointDialog(txid: utxo.txid, vout: utxo.vout));
  }

  @override
  Widget build(BuildContext context) {
    final u = utxo;
    final scheme = Theme.of(context).colorScheme;
    final hasLabel = u.effectiveLabel?.isNotEmpty == true;

    return InkWell(
      onTap: () => _showDetail(context),
      borderRadius: BorderRadius.circular(4),
      child: Padding(
        padding: const EdgeInsets.only(bottom: 6),
        child: Row(
          children: [
            const Icon(Icons.toll, size: 14),
            const SizedBox(width: 6),
            Expanded(
              child: hasLabel
                  ? Text(
                      u.effectiveLabel!,
                      style: u.isAuto
                          ? TextStyle(
                              fontSize: 12,
                              fontStyle: FontStyle.italic,
                              color: scheme.outline,
                            )
                          : const TextStyle(
                              fontSize: 12, fontWeight: FontWeight.w500),
                      overflow: TextOverflow.ellipsis,
                    )
                  : OutpointText(txid: u.txid, vout: u.vout),
            ),
            const SizedBox(width: 6),
            Text(
              '${BitcoinFormatter.formatNum(u.valueSat.toInt())} sats',
              style: const TextStyle(fontSize: 11),
            ),
            const SizedBox(width: 4),
            const Icon(Icons.chevron_right, size: 14),
          ],
        ),
      ),
    );
  }
}

class _RelatedTxRow extends StatelessWidget {
  final APIRelatedTx tx;
  const _RelatedTxRow({required this.tx});

  void _showDetail(BuildContext context) {
    final cubitState = context.read<WalletDetailCubit>().state;
    if (cubitState is! WalletDetailLoaded) return;
    final network = cubitState.walletInfo.network;

    final fullTx = cubitState.transactions
        .where((t) => t.txid == tx.txid)
        .firstOrNull;

    final APITransaction apiTx;
    final bool isSelfTransfer;
    final bool isReceived;
    final int netSats;

    if (fullTx != null) {
      final fee = fullTx.fee;
      isSelfTransfer = fullTx.sent > BigInt.zero &&
          fullTx.received > BigInt.zero &&
          fee != null &&
          fullTx.sent - fullTx.received == fee;
      isReceived = !isSelfTransfer && fullTx.received > fullTx.sent;
      netSats = isSelfTransfer
          ? fee.toInt()
          : (isReceived
                  ? fullTx.received - fullTx.sent
                  : fullTx.sent - fullTx.received)
              .toInt();
      apiTx = fullTx;
    } else {
      final net = tx.addrReceived.toInt() - tx.addrSpent.toInt();
      isSelfTransfer = false;
      isReceived = net >= 0;
      netSats = net.abs();
      apiTx = APITransaction(
        txid: tx.txid,
        received: tx.addrReceived,
        sent: tx.addrSpent,
        fee: tx.fee,
        confirmationHeight: tx.confirmationHeight,
        confirmationTime: null,
        label: null,
        effectiveLabel: tx.effectiveLabel,
        isAuto: tx.isAuto,
      );
    }

    Navigator.of(context).pop();
    showWalletDialog(
      context,
      TxDetailDialog(
        tx: apiTx,
        network: network,
        isSelfTransfer: isSelfTransfer,
        isReceived: isReceived,
        netSats: netSats,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final net = tx.addrReceived.toInt() - tx.addrSpent.toInt();
    final hasLabel = tx.effectiveLabel?.isNotEmpty == true;
    final scheme = Theme.of(context).colorScheme;
    return InkWell(
      onTap: () => _showDetail(context),
      borderRadius: BorderRadius.circular(4),
      child: Padding(
        padding: const EdgeInsets.only(bottom: 6),
        child: Row(
          children: [
            const Icon(Icons.receipt_long, size: 14),
            const SizedBox(width: 6),
            Expanded(
              child: hasLabel
                  ? Text(
                      tx.effectiveLabel!,
                      style: tx.isAuto
                          ? TextStyle(
                              fontSize: 12,
                              fontStyle: FontStyle.italic,
                              color: scheme.outline,
                            )
                          : const TextStyle(
                              fontSize: 12, fontWeight: FontWeight.w500),
                      overflow: TextOverflow.ellipsis,
                    )
                  : OutpointText(txid: tx.txid),
            ),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  '${net >= 0 ? '+' : ''}${BitcoinFormatter.formatNum(net)} sats',
                  style: TextStyle(
                    fontSize: 11,
                    color: net >= 0 ? Colors.green : Colors.orange,
                  ),
                ),
                Text(
                  tx.confirmationHeight != null
                      ? '${tx.confirmationHeight}'
                      : l10n.txUnconfirmed,
                  style: TextStyle(
                    fontSize: 10,
                    color: tx.confirmationHeight != null
                        ? Theme.of(context)
                            .colorScheme
                            .onSurface
                            .withAlpha(AppAlpha.secondary)
                        : Colors.grey,
                  ),
                ),
              ],
            ),
            const SizedBox(width: 4),
            const Icon(Icons.chevron_right, size: 14),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────
// Lookup-by-reference dialogs (navigate from related-entity rows)
// ─────────────────────────────────────────────────────────────

/// Loads a UTXO by outpoint and shows its detail dialog.
class _CoinDetailByOutpointDialog extends StatefulWidget {
  final String txid;
  final int vout;
  const _CoinDetailByOutpointDialog({required this.txid, required this.vout});

  @override
  State<_CoinDetailByOutpointDialog> createState() =>
      _CoinDetailByOutpointDialogState();
}

class _CoinDetailByOutpointDialogState
    extends State<_CoinDetailByOutpointDialog> {
  late final Future<APIUtxoDetails> _future;

  @override
  void initState() {
    super.initState();
    _future = (context.read<WalletDetailCubit>().state as WalletDetailLoaded)
        .walletHandle
        .getUtxoDetails(txid: widget.txid, vout: widget.vout);
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<APIUtxoDetails>(
      future: _future,
      builder: (context, snapshot) {
        if (!snapshot.hasData) {
          return const AlertDialog(
            content: SizedBox(
              height: 80,
              child: Center(child: CircularProgressIndicator()),
            ),
          );
        }
        final state =
            context.read<WalletDetailCubit>().state as WalletDetailLoaded;
        final utxo = snapshot.data!.utxo;
        final spendPaths = state.descriptorAnalysis?.spendPaths ?? [];
        final statuses = spendPaths
            .map((p) => (
                  p,
                  spendPathStatus(
                    path: p,
                    utxo: utxo,
                    tipHeight: state.tipHeight,
                  ),
                ))
            .toList();
        return CoinDetailDialog(
          utxo: utxo,
          network: state.walletInfo.network,
          spendPathStatuses: statuses,
          keyLabels: state.keyLabels,
        );
      },
    );
  }
}

/// Loads an address by its string and shows its detail dialog.
class _AddressDetailByStringDialog extends StatefulWidget {
  final String address;
  const _AddressDetailByStringDialog({required this.address});

  @override
  State<_AddressDetailByStringDialog> createState() =>
      _AddressDetailByStringDialogState();
}

class _AddressDetailByStringDialogState
    extends State<_AddressDetailByStringDialog> {
  late final Future<APIAddressDetails> _future;

  @override
  void initState() {
    super.initState();
    _future = (context.read<WalletDetailCubit>().state as WalletDetailLoaded)
        .walletHandle
        .getAddressDetails(address: widget.address);
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<APIAddressDetails>(
      future: _future,
      builder: (context, snapshot) {
        if (!snapshot.hasData) {
          return const AlertDialog(
            content: SizedBox(
              height: 80,
              child: Center(child: CircularProgressIndicator()),
            ),
          );
        }
        final state =
            context.read<WalletDetailCubit>().state as WalletDetailLoaded;
        final details = snapshot.data!;
        return AddressDetailDialog(
          address: details.address,
          keychain: details.address.keychain,
          network: state.walletInfo.network,
        );
      },
    );
  }
}

// ─────────────────────────────────────────────────────────────
// Public shared utility widgets
// ─────────────────────────────────────────────────────────────

/// Small colored status badge (confirmation state, keychain type, etc.)
class StatusBadge extends StatelessWidget {
  final String label;
  final Color color;

  const StatusBadge({super.key, required this.label, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(top: 2),
      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
      decoration: BoxDecoration(
        color: color.withAlpha(AppAlpha.dim),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(label, style: TextStyle(fontSize: 10, color: color)),
    );
  }
}

/// Summary badge shown on the coin tile: unlocked/total spend paths.
class SpendPathSummaryBadge extends StatelessWidget {
  final int unlockedCount;
  final int totalCount;

  const SpendPathSummaryBadge({
    super.key,
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
        color: color.withAlpha(AppAlpha.dim),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: color.withAlpha(AppAlpha.pale)),
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
// Private shared widgets (used only within this file)
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
    final labels =
        path.mfps.map((m) => keyLabels[m] ?? m.toUpperCase()).toList();
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
      SpendPathUnconfirmed() => (
        Icons.hourglass_empty,
        Colors.amber,
        l10n.spendPathUnconfirmed,
      ),
      SpendPathNeedsSync() => (
        Icons.sync_disabled,
        Colors.grey,
        l10n.spendPathNeedsSync,
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
                Text(subtitle, style: TextStyle(fontSize: 11, color: color)),
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
                  .withAlpha(AppAlpha.secondary),
            ),
          ),
          const SizedBox(height: 2),
          child,
        ],
      ),
    );
  }
}

// Two _DetailRow widgets placed side by side (equal width columns)
class _DetailRowPair extends StatelessWidget {
  final String label1;
  final Widget child1;
  final String label2;
  final Widget child2;

  const _DetailRowPair({
    required this.label1,
    required this.child1,
    required this.label2,
    required this.child2,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(child: _DetailRow(label: label1, child: child1)),
        const SizedBox(width: 8),
        Expanded(child: _DetailRow(label: label2, child: child2)),
      ],
    );
  }
}

/// Shows an effective label with inherited styling (italic + outline) when [isAuto].
class _EffectiveLabelText extends StatelessWidget {
  final String? effectiveLabel;
  final bool isAuto;
  const _EffectiveLabelText(
      {required this.effectiveLabel, required this.isAuto});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final hasLabel = effectiveLabel?.isNotEmpty == true;
    if (!hasLabel) {
      return Text(
        '—',
        style: TextStyle(
          color: scheme.onSurface.withAlpha(AppAlpha.muted),
          fontStyle: FontStyle.italic,
        ),
      );
    }
    if (isAuto) {
      return Row(
        children: [
          Icon(Icons.label_outline, size: 14, color: scheme.outline),
          const SizedBox(width: 4),
          Expanded(
            child: Text(
              effectiveLabel!,
              style: TextStyle(
                  fontStyle: FontStyle.italic, color: scheme.outline),
            ),
          ),
        ],
      );
    }
    return Row(
      children: [
        const Icon(Icons.label, size: 14),
        const SizedBox(width: 4),
        Expanded(child: Text(effectiveLabel!)),
      ],
    );
  }
}

/// Rebuilds [_EffectiveLabelText] whenever [WalletDetailLoaded] state changes.
class _LiveEffectiveLabelText extends StatelessWidget {
  const _LiveEffectiveLabelText({
    required this.resolve,
    required this.fallbackLabel,
    required this.fallbackIsAuto,
  });

  final (String?, bool) Function(WalletDetailLoaded) resolve;
  final String? fallbackLabel;
  final bool fallbackIsAuto;

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<WalletDetailCubit, WalletDetailState>(
      buildWhen: (_, next) => next is WalletDetailLoaded,
      builder: (context, state) {
        final (label, isAuto) = state is WalletDetailLoaded
            ? resolve(state)
            : (fallbackLabel, fallbackIsAuto);
        return _EffectiveLabelText(effectiveLabel: label, isAuto: isAuto);
      },
    );
  }
}

/// Generic label-edit dialog used by address, coin, and tx label editors.
class _LabelDialog extends StatefulWidget {
  final String title;
  final String hintText;
  final String currentLabel;
  final String removeLabel;
  final ValueChanged<String> onSave;
  final VoidCallback? onRemove;

  const _LabelDialog({
    required this.title,
    required this.hintText,
    required this.currentLabel,
    required this.removeLabel,
    required this.onSave,
    this.onRemove,
  });

  @override
  State<_LabelDialog> createState() => _LabelDialogState();
}

class _LabelDialogState extends State<_LabelDialog> {
  late final TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController.fromValue(TextEditingValue(
      text: widget.currentLabel,
      selection:
          TextSelection.collapsed(offset: widget.currentLabel.length),
    ));
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _save(BuildContext context) {
    widget.onSave(_controller.text.trim());
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return AlertDialog(
      titlePadding: kDialogTitlePadding,
      title: dialogCloseTitle(widget.title,
          onClose: () => Navigator.of(context).pop(), tooltip: l10n.cancel),
      content: TextField(
        controller: _controller,
        autofocus: true,
        decoration: InputDecoration(
          hintText: widget.hintText,
          border: const OutlineInputBorder(),
        ),
        onSubmitted: (_) => _save(context),
        onTapOutside: (_) {
          final label = _controller.text.trim();
          if (label != widget.currentLabel) widget.onSave(label);
        },
      ),
      actions: [
        if (widget.currentLabel.isNotEmpty)
          TextButton(
            onPressed: () {
              widget.onRemove?.call();
              Navigator.of(context).pop();
            },
            child: Text(
              widget.removeLabel,
              style: const TextStyle(color: Colors.red),
            ),
          ),
        FilledButton(
            onPressed: () => _save(context), child: Text(l10n.save)),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────
// Pending PSBT row (shown inside the coin detail dialog)
// ─────────────────────────────────────────────────────────────

class _PendingPsbtRow extends StatelessWidget {
  final APIPsbtInfo psbt;

  const _PendingPsbtRow({required this.psbt});

  APISpendPath? _findSpendPath(List<APISpendPath> spendPaths) {
    try {
      return spendPaths.firstWhere((p) => p.id == psbt.spendPathId.toInt());
    } catch (_) {
      return spendPaths.isNotEmpty ? spendPaths.first : null;
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final effectiveLabel = psbt.effectiveLabel;
    final title = effectiveLabel != null && effectiveLabel.isNotEmpty
        ? effectiveLabel
        : psbt.recipient;

    return InkWell(
      borderRadius: BorderRadius.circular(8),
      onTap: () {
        final cubitState =
            context.read<WalletDetailCubit>().state as WalletDetailLoaded;
        final spendPath = _findSpendPath(
          cubitState.descriptorAnalysis?.spendPaths ?? [],
        );
        Navigator.of(context).pop();
        Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => BlocProvider.value(
              value: context.read<WalletDetailCubit>(),
              child: PsbtDetailScreen(psbt: psbt, spendPath: spendPath),
            ),
          ),
        );
      },
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(
          children: [
            Icon(Icons.lock_clock_outlined, size: 16, color: AppAccent.color),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  effectiveLabel != null && effectiveLabel.isNotEmpty
                      ? Text(
                          effectiveLabel,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontStyle: psbt.isAuto
                                ? FontStyle.italic
                                : FontStyle.normal,
                          ),
                        )
                      : ColoredAddressText(address: title, truncate: true),
                  Text(
                    '${BitcoinFormatter.formatNum(psbt.amountSat.toInt())} sats',
                    style: TextStyle(
                      fontSize: 11,
                      color: theme.colorScheme.onSurface
                          .withAlpha(AppAlpha.medium),
                    ),
                  ),
                ],
              ),
            ),
            Icon(
              Icons.chevron_right,
              size: 16,
              color: theme.colorScheme.onSurface.withAlpha(AppAlpha.border),
            ),
          ],
        ),
      ),
    );
  }
}
