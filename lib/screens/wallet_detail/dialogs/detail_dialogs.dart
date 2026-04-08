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
import 'package:deadbolt/utils/date_format.dart';
import 'package:deadbolt/utils/spend_path_unlock.dart';
import 'package:deadbolt/utils/toast_helper.dart';
import 'package:deadbolt/widgets/colored_group_text.dart';
import 'package:deadbolt/widgets/dialog_helpers.dart';
import 'package:deadbolt/widgets/hw_wallet_sheet.dart' show showHwVerifyAddressSheet;
import 'package:deadbolt/screens/wallet_detail/wif_reveal_dialog.dart' show showWifExportFlow;
import 'package:deadbolt/widgets/outpoint_text.dart';
import 'package:deadbolt/widgets/text_export_sheet.dart' show showTextExportSheet;
import 'package:deadbolt/screens/wallet_detail/shared_detail_widgets.dart';

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
    // WIF export is only meaningful for single-sig hot wallets.
    final hotKeys =
        walletState is WalletDetailLoaded ? walletState.hotKeys : const [];
    final singleHotMfp = hotKeys.length == 1 ? hotKeys.first.mfp : null;

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
              DetailRow(
                label: l10n.addressLabelTitle,
                child: Row(
                  children: [
                    Expanded(
                      child: LiveEffectiveLabelText(
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
                          LabelDialog(
                            title: l10n.addressLabelTitle,
                            hintText: l10n.addressLabelHint,
                            currentLabel: address.label ?? '',
                            removeLabel: l10n.addressLabelRemove,
                            onSave: (label) => cubit.setAddressLabel(
                                address.address, label, keychain),
                            onRemove: () => cubit.setAddressLabel(
                                address.address, '', keychain),
                          ),
                          barrierDismissible: false,
                        );
                      },
                    ),
                  ],
                ),
              ),
              DetailRow(
                label: l10n.coinAddress,
                child: Row(
                  children: [
                    Expanded(
                      child: ColoredGroupText(text: address.address),
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
                        extraItems: [
                          if (singleHotMfp != null)
                            (
                              icon: Icons.key_outlined,
                              label: l10n.wifExportTitle,
                              onTap: () => showWifExportFlow(
                                context,
                                address: address.address,
                                mfp: singleHotMfp,
                              ),
                            ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              DetailRowPair(
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
                DetailRow(
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
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    OutlinedButton.icon(
                      onPressed: () => showHwVerifyAddressSheet(
                        context,
                        descriptor: descriptor,
                        network: network,
                        keychain: keychain,
                        index: address.index,
                        address: address.address,
                      ),
                      icon: const Icon(Icons.memory, size: 16),
                      label: Text(context.l10n.verifyOnDeviceButton),
                    ),
                    if (explorerUrl.isNotEmpty) ...[
                      const SizedBox(height: 8),
                      FilledButton.icon(
                        onPressed: () => launchUrl(
                          Uri.parse(explorerUrl),
                          mode: LaunchMode.externalApplication,
                        ),
                        icon: const Icon(Icons.open_in_new, size: 16),
                        label: Text(l10n.openInExplorer),
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
    final tipHeight =
        (context.read<WalletDetailCubit>().state as WalletDetailLoaded)
            .tipHeight;

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
              DetailRow(
                label: l10n.coinLabelTitle,
                child: Row(
                  children: [
                    Expanded(
                      child: LiveEffectiveLabelText(
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
                          LabelDialog(
                            title: l10n.coinLabelTitle,
                            hintText: l10n.addressLabelHint,
                            currentLabel: utxo.label ?? '',
                            removeLabel: l10n.addressLabelRemove,
                            onSave: (label) =>
                                cubit.setCoinLabel(utxo.txid, utxo.vout, label),
                            onRemove: () =>
                                cubit.setCoinLabel(utxo.txid, utxo.vout, ''),
                          ),
                          barrierDismissible: false,
                        );
                      },
                    ),
                  ],
                ),
              ),
              DetailRowPair(
                label1: l10n.coinValue,
                child1: Text(
                  '${BitcoinFormatter.formatNum(utxo.valueSat.toInt())} sats',
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    color: Colors.green,
                  ),
                ),
                label2: l10n.coinConfirmations,
                child2: Text(
                  utxo.isConfirmed && tipHeight > 0
                      ? BitcoinFormatter.formatNum(
                          tipHeight - utxo.confirmationHeight!.toInt() + 1)
                      : l10n.txUnconfirmed,
                  style: TextStyle(
                    color: utxo.isConfirmed ? Colors.green : Colors.grey,
                    fontWeight:
                        utxo.isConfirmed ? FontWeight.bold : null,
                  ),
                ),
              ),
              if (utxo.confirmationHeight != null) ...[
                DetailRowPair(
                  label1: l10n.coinKeychain,
                  child1: Text(
                    isChange
                        ? l10n.coinKeychainChange
                        : l10n.coinKeychainReceive,
                  ),
                  label2: l10n.txDetailsConfirmedAt,
                  child2: Text(_formatDateOnly(utxo)),
                ),
                DetailRowPair(
                  label1: l10n.coinAgeLabel,
                  child1: Text(_formatAgeTime(utxo, tipHeight)),
                  label2: l10n.coinBlockNumber,
                  child2: Text(_formatConfirmationBlock(utxo)),
                ),
              ] else
                DetailRow(
                  label: l10n.coinKeychain,
                  child: Text(
                    isChange
                        ? l10n.coinKeychainChange
                        : l10n.coinKeychainReceive,
                  ),
                ),
              DetailRow(
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
              DetailRow(
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
                                          child: EffectiveLabelText(
                                            effectiveLabel: lbl,
                                            isAuto:
                                                snap.data!.addressLabelIsAuto,
                                          ),
                                        ),
                                      ColoredGroupText(
                                          text: utxo.address),
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
                  SpendPathStatusRow(
                    path: path,
                    status: status,
                    keyLabels: keyLabels,
                    tipHeight: tipHeight,
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
                  child: SizedBox(
                    width: double.infinity,
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

  static String _formatDateOnly(APIUtxo utxo) {
    if (utxo.confirmationTime == null) return '—';
    return formatTimestamp(utxo.confirmationTime!.toInt());
  }

  static String _formatAgeTime(APIUtxo utxo, int tipHeight) {
    if (tipHeight == 0 || utxo.confirmationHeight == null) return '—';
    final blocks = tipHeight - utxo.confirmationHeight!.toInt();
    return formatCoinAge(blocks);
  }

  static String _formatConfirmationBlock(APIUtxo utxo) {
    if (utxo.confirmationHeight == null) return '—';
    return BitcoinFormatter.formatNum(utxo.confirmationHeight!.toInt());
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
              DetailRow(
                label: l10n.txLabelTitle,
                child: Row(
                  children: [
                    Expanded(
                      child: LiveEffectiveLabelText(
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
                          LabelDialog(
                            title: l10n.txLabelTitle,
                            hintText: l10n.addressLabelHint,
                            currentLabel: tx.label ?? '',
                            removeLabel: l10n.addressLabelRemove,
                            onSave: (label) =>
                                cubit.setTxLabel(tx.txid, label),
                            onRemove: () => cubit.setTxLabel(tx.txid, ''),
                          ),
                          barrierDismissible: false,
                        );
                      },
                    ),
                  ],
                ),
              ),
              DetailRow(
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
                DetailRowPair(
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
                DetailRow(
                  label: l10n.txDetailsNet,
                  child: Text(
                    netLabel,
                    style: TextStyle(
                        fontWeight: FontWeight.bold, color: netColor),
                  ),
                ),
              DetailRowPair(
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
                DetailRowPair(
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
                  DetailRow(
                    label: l10n.txDetailsConfirmedAt,
                    child: Text(formatDateTime(confirmedAt)),
                  ),
              ] else
                DetailRow(
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
                  child: SizedBox(
                    width: double.infinity,
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
                : ColoredGroupText(text: a.address, truncate: true),
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
            const Icon(Icons.lock_clock_outlined, size: 16, color: AppAccent.color),
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
                      : ColoredGroupText(text: title, truncate: true),
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
