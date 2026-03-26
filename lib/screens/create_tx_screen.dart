import 'dart:async';
import 'dart:math' show max;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import 'package:deadbolt/theme/app_theme.dart';
import 'package:deadbolt/cubit/settings_cubit.dart';
import 'package:deadbolt/cubit/wallet_detail_cubit.dart';
import 'package:deadbolt/cubit/wallet_list_cubit.dart';
import 'package:deadbolt/l10n/l10n.dart';
import 'package:deadbolt/services/wallet_service.dart';
import 'package:deadbolt/src/rust/api/analyzer.dart' show addressOutputWu;
import 'package:deadbolt/src/rust/api/model.dart';
import 'package:deadbolt/models/timelock_types.dart';
import 'package:deadbolt/utils/bitcoin_formatter.dart' show BitcoinFormatter;
import 'package:deadbolt/utils/toast_helper.dart';
import 'package:deadbolt/widgets/colored_group_text.dart';
import 'package:deadbolt/widgets/dialog_helpers.dart' show showSheet;
import 'package:deadbolt/widgets/mfp_badge.dart';
import 'package:deadbolt/screens/coin_selector_screen.dart';
import 'package:deadbolt/screens/psbt_detail_screen.dart';

// Outputs below this threshold are not created (absorbed into fee).
const _dustLimit = 546;

enum _FeeEditMode { none, rate, total }

/// Internal transaction estimate used to drive live fee/change display.
class _TxSummary {
  final int feeSats;
  final int changeSats;
  final int sendSats;
  final double feeRate;
  final int totalWu;
  final bool hasChange;
  final bool insufficientFunds;

  const _TxSummary({
    required this.feeSats,
    required this.changeSats,
    required this.sendSats,
    required this.feeRate,
    required this.totalWu,
    required this.hasChange,
    this.insufficientFunds = false,
  });
}

/// Screen for building an unsigned PSBT. Coin selection happens inside this
/// screen via [CoinSelectorScreen].
class CreateTxScreen extends StatefulWidget {
  final List<APIUtxo> allUtxos;
  final int tipHeight;
  final List<APISpendPath>? spendPaths;
  final Map<String, String> keyLabels;
  final Map<int, String> pathLabels;

  const CreateTxScreen({
    super.key,
    this.allUtxos = const [],
    this.tipHeight = 0,
    this.spendPaths,
    this.keyLabels = const {},
    this.pathLabels = const {},
  });

  static Future<void> push(
    BuildContext context, {
    List<APIUtxo> allUtxos = const [],
    int tipHeight = 0,
    List<APISpendPath>? spendPaths,
    Map<String, String> keyLabels = const {},
    Map<int, String> pathLabels = const {},
  }) {
    return Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder: (_) => BlocProvider.value(
          value: context.read<WalletDetailCubit>(),
          child: CreateTxScreen(
            allUtxos: allUtxos,
            tipHeight: tipHeight,
            spendPaths: spendPaths,
            keyLabels: keyLabels,
            pathLabels: pathLabels,
          ),
        ),
      ),
    );
  }

  @override
  State<CreateTxScreen> createState() => _CreateTxScreenState();
}

class _CreateTxScreenState extends State<CreateTxScreen> {
  final _formKey = GlobalKey<FormState>();
  final _recipientCtrl = TextEditingController();
  final _amountCtrl = TextEditingController();
  final _feeRateCtrl = TextEditingController(text: '1.0');
  final _totalFeeCtrl = TextEditingController();
  final _labelCtrl = TextEditingController();
  bool _creating = false;
  bool _sendMax = false;
  APISpendPath? _selectedPath;
  _FeeEditMode _feeEditMode = _FeeEditMode.none;
  bool _recipientEditMode = true; // starts in edit mode (empty address)

  // Selected UTXOs (chosen via CoinSelectorScreen)
  List<APIUtxo> _selectedUtxos = [];

  // RBF info: mempoolSpendingTxid -> APIRbfInfo (null while loading)
  final Map<String, APIRbfInfo?> _rbfInfos = {};

  // Focus nodes for the two fee fields — explicit requestFocus() is more reliable
  // than autofocus: true on desktop platforms.
  final _rateFocusNode = FocusNode();
  final _totalFocusNode = FocusNode();

  // Async resolution of recipient output WU via FFI.
  int? _recipientWu;
  bool _resolvingWu = false;
  Timer? _addrDebounce;

  @override
  void initState() {
    super.initState();
    if (widget.spendPaths != null && widget.spendPaths!.isNotEmpty) {
      _selectedPath = widget.spendPaths!.first;
    }
  }

  @override
  void dispose() {
    _addrDebounce?.cancel();
    _recipientCtrl.dispose();
    _amountCtrl.dispose();
    _feeRateCtrl.dispose();
    _totalFeeCtrl.dispose();
    _labelCtrl.dispose();
    _rateFocusNode.dispose();
    _totalFocusNode.dispose();
    super.dispose();
  }

  // ─── Fee callbacks ────────────────────────────────────────────────────────

  void _onFeeRateChanged(String _) => setState(() {});
  void _onTotalFeeChanged(String _) => setState(() {});
  void _onAmountChanged(String _) {
    if (!_sendMax) setState(() {});
  }

  void _confirmRecipient() {
    if (_recipientCtrl.text.trim().isEmpty) return;
    setState(() => _recipientEditMode = false);
  }

  /// Sync totalFee controller from current summary when confirming feeRate edit.
  void _confirmFeeRate() {
    final summary = _txSummary;
    if (summary != null) _totalFeeCtrl.text = summary.feeSats.toString();
    setState(() => _feeEditMode = _FeeEditMode.none);
  }

  /// Back-compute fee rate from user-entered total fee.
  /// Uses the actual tx weight from _txSummary (includes change output when present)
  /// to avoid rate drift when toggling between the two fee edit modes.
  void _syncRateFromTotal() {
    final fee = int.tryParse(_totalFeeCtrl.text);
    if (fee == null || fee <= 0) return;
    // Prefer the actual weight from the current summary — prevents upward drift.
    final summary = _txSummary;
    if (summary != null) {
      _feeRateCtrl.text = (fee / (summary.totalWu / 4.0)).toStringAsFixed(2);
      return;
    }
    // Fallback when summary is unavailable (missing coins / path / recipient).
    final path = _selectedPath;
    final wu = _recipientWu;
    if (path == null || wu == null) return;
    final n = _selectedUtxos.length;
    if (n == 0) return;
    final wuNoChange = path.wuBase + n * path.wuIn + wu;
    _feeRateCtrl.text = (fee / (wuNoChange / 4.0)).toStringAsFixed(2);
  }

  // ─── RBF helpers ─────────────────────────────────────────────────────────

  void _updateRbfInfos() {
    final cubit = context.read<WalletDetailCubit>();
    final txids = _selectedUtxos
        .map((u) => u.mempoolSpendingTxid)
        .whereType<String>()
        .toSet();
    // Remove stale entries.
    _rbfInfos.removeWhere((k, _) => !txids.contains(k));
    // Fetch new ones.
    for (final txid in txids) {
      if (!_rbfInfos.containsKey(txid)) {
        _rbfInfos[txid] = null;
        cubit.getRbfInfo(txid).then((info) {
          if (mounted) setState(() => _rbfInfos[txid] = info);
        });
      }
    }
  }

  // ─── Helpers ─────────────────────────────────────────────────────────────

  int get _selectedSats =>
      _selectedUtxos.fold(0, (sum, u) => sum + u.valueSat.toInt());

  void _onRecipientChanged(String value) {
    _addrDebounce?.cancel();
    final trimmed = value.trim();
    if (trimmed.isEmpty) {
      setState(() {
        _recipientWu = null;
        _resolvingWu = false;
      });
      return;
    }
    setState(() => _resolvingWu = true);
    _addrDebounce = Timer(const Duration(milliseconds: 400), () async {
      if (!mounted) return;
      try {
        final wu = await addressOutputWu(address: trimmed);
        if (mounted) {
          setState(() {
            _recipientWu = wu.toInt();
            _resolvingWu = false;
          });
        }
      } catch (_) {
        if (mounted) setState(() { _recipientWu = null; _resolvingWu = false; });
      }
    });
  }

  // ─── Transaction estimate ────────────────────────────────────────────────

  _TxSummary? get _txSummary {
    final path = _selectedPath;
    if (path == null || _selectedUtxos.isEmpty) return null;
    final recipientWu = _recipientWu;
    if (recipientWu == null) return null;

    final n = _selectedUtxos.length;
    final totalIn = _selectedSats;
    final wuNoChange = path.wuBase + n * path.wuIn + recipientWu;
    final wuWithChange = wuNoChange + path.wuOut;

    // Determine fee rate — branch by active edit mode.
    double? rate;
    if (_feeEditMode == _FeeEditMode.total) {
      final fee = int.tryParse(_totalFeeCtrl.text);
      if (fee == null || fee <= 0) return null;
      if (!_sendMax) {
        // Pick the denominator that matches the tx structure the user will actually get,
        // so feeSats == fee (no rounding drift when toggling between the two fee fields).
        final amountHint = int.tryParse(_amountCtrl.text) ?? 0;
        final remainderIfExactFee = totalIn - amountHint - fee;
        rate = remainderIfExactFee >= _dustLimit
            ? fee / (wuWithChange / 4.0) // change output present → exact fee
            : fee / (wuNoChange / 4.0);  // no change output
      } else {
        rate = fee / (wuNoChange / 4.0); // sendMax: no change output
      }
    } else {
      rate = double.tryParse(_feeRateCtrl.text);
    }
    if (rate == null || rate <= 0) return null;

    if (_sendMax) {
      final fee = (rate * wuNoChange / 4.0).ceil();
      final send = totalIn - fee;
      return _TxSummary(
        feeSats: fee,
        changeSats: 0,
        sendSats: send > 0 ? send : 0,
        feeRate: rate,
        totalWu: wuNoChange,
        hasChange: false,
        insufficientFunds: send <= 0,
      );
    }

    final amount = int.tryParse(_amountCtrl.text);
    if (amount == null || amount <= 0) return null;

    final feeWithChange = (rate * wuWithChange / 4.0).ceil();
    final change = totalIn - amount - feeWithChange;

    if (change >= _dustLimit) {
      return _TxSummary(
        feeSats: feeWithChange,
        changeSats: change,
        sendSats: amount,
        feeRate: rate,
        totalWu: wuWithChange,
        hasChange: true,
      );
    } else {
      final feeNoChange = (rate * wuNoChange / 4.0).ceil();
      final leftover = totalIn - amount - feeNoChange;
      if (leftover < 0) {
        return _TxSummary(
          feeSats: feeNoChange,
          changeSats: 0,
          sendSats: amount,
          feeRate: rate,
          totalWu: wuNoChange,
          hasChange: false,
          insufficientFunds: true,
        );
      }
      // Leftover dust goes to miner.
      return _TxSummary(
        feeSats: feeNoChange + leftover,
        changeSats: 0,
        sendSats: amount,
        feeRate: (feeNoChange + leftover) / (wuNoChange / 4.0),
        totalWu: wuNoChange,
        hasChange: false,
      );
    }
  }

  // ─── Actions ─────────────────────────────────────────────────────────────

  void _toggleSendMax() {
    setState(() {
      _sendMax = !_sendMax;
      if (!_sendMax) _amountCtrl.clear();
    });
  }

  Future<void> _showWalletPickerSheet() async {
    final l10n = context.l10n;
    final cubit = context.read<WalletDetailCubit>();
    final walletState = cubit.state;
    if (walletState is! WalletDetailLoaded) return;

    final currentPath = walletState.walletInfo.walletPath;
    final currentNetwork = walletState.walletInfo.network;

    final listState = context.read<WalletListCubit>().state;
    final allWallets = listState is WalletListLoaded ? listState.wallets : <APIWalletInfo>[];
    final service = context.read<WalletService>();

    // Filter to same-network wallets, current wallet first.
    final sameNetwork = allWallets
        .where((w) => w.network == currentNetwork)
        .toList()
      ..sort((a, b) {
        if (a.walletPath == currentPath) return -1;
        if (b.walletPath == currentPath) return 1;
        return 0;
      });

    if (!mounted) return;

    await showSheet<void>(context, (sheetCtx) {
        final theme = Theme.of(sheetCtx);
        return Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                child: Text(
                  l10n.createTxSelectDestWallet,
                  style: theme.textTheme.titleMedium,
                ),
              ),
              const Divider(height: 1),
              ...sameNetwork.map((wallet) {
                final isCurrent = wallet.walletPath == currentPath;
                final isLocked = wallet.protection.needsPassword &&
                    service.getCachedPassword(wallet.walletPath) == null;
                final name = isCurrent
                    ? l10n.createTxThisWallet
                    : wallet.name;
                return ListTile(
                  leading: isLocked
                      ? Icon(
                          Icons.lock_outline,
                          color: theme.colorScheme.onSurface.withAlpha(AppAlpha.inactive),
                        )
                      : isCurrent
                          ? Icon(Icons.account_balance_wallet_outlined,
                              color: theme.colorScheme.primary)
                          : const Icon(Icons.account_balance_wallet_outlined),
                  title: Text(
                    name,
                    style: isLocked
                        ? TextStyle(color: theme.colorScheme.onSurface.withAlpha(AppAlpha.inactive))
                        : null,
                  ),
                  enabled: !isLocked,
                  onTap: isLocked
                      ? null
                      : () {
                          Navigator.of(sheetCtx).pop();
                          _fillAddressFromWallet(wallet.walletPath);
                        },
                );
              }),
              const SizedBox(height: 8),
          ],
          );
      });
  }

  Future<void> _fillAddressFromWallet(String walletPath) async {
    final l10n = context.l10n;
    final cubit = context.read<WalletDetailCubit>();
    final walletState = cubit.state;
    final String? address;
    if (walletState is WalletDetailLoaded &&
        walletPath == walletState.walletInfo.walletPath) {
      address = await cubit.getNextSelfPaymentAddress();
    } else {
      address = await cubit.getNextReceiveAddressFor(walletPath);
    }
    if (!mounted) return;
    if (address == null) {
      showErrorToast(context, l10n.createTxNoUnusedAddress);
      return;
    }
    _recipientCtrl.text = address;
    _recipientEditMode = false;
    _onRecipientChanged(address);
  }

  Future<void> _openCoinSelector() async {
    final cubit = context.read<WalletDetailCubit>();
    final state = cubit.state;
    final network = state is WalletDetailLoaded
        ? state.walletInfo.network
        : APINetwork.bitcoin;
    final result = await CoinSelectorScreen.push(
      context,
      allUtxos: widget.allUtxos,
      selectedPath: _selectedPath,
      tipHeight: widget.tipHeight,
      initiallySelected: _selectedUtxos,
      keyLabels: widget.keyLabels,
      network: network,
    );
    if (result != null) {
      setState(() => _selectedUtxos = result);
      _updateRbfInfos();
    }
  }

  String _pathLabel(APISpendPath path) {
    final label = widget.pathLabels[path.id];
    if (label != null && label.isNotEmpty) return label;
    final keys = path.mfps
        .map((m) => widget.keyLabels[m] ?? m.substring(0, 4).toUpperCase())
        .join(' + ');
    final threshold = '${path.threshold}-of-${path.mfps.length}';
    return '$threshold ($keys)';
  }

  ({IconData icon, String text, Color color})? _timelockStatus(
    BuildContext context,
    APISpendPath path,
    int tipHeight,
    int? utxoMaxConfHeight,
  ) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final hasRel = path.relTimelock.value > 0;
    final hasAbs = path.absTimelock.value > 0;
    if (!hasRel && !hasAbs) return null;

    if (hasRel && path.relTimelock.timelockType == APIRelativeTimelockType.blocks) {
      final relBlocks = path.relTimelock.value;
      if (_selectedUtxos.isEmpty) return null;
      if (utxoMaxConfHeight == null || tipHeight == 0) {
        return (
          icon: Icons.sync_disabled_outlined,
          text: l10n.psbtTimelockSyncRequired,
          color: theme.colorScheme.onSurface.withAlpha(AppAlpha.inactive),
        );
      }
      final remaining = (utxoMaxConfHeight + relBlocks) - tipHeight;
      if (remaining > 0) {
        return (
          icon: Icons.lock_outline,
          text: l10n.psbtTimelockBlocksRemaining(
            remaining,
            BitcoinFormatter.formatDuration(remaining * 10),
          ),
          color: Colors.orange,
        );
      }
      return (
        icon: Icons.lock_open_outlined,
        text: l10n.spendPathUnlocked,
        color: Colors.green,
      );
    }

    if (hasAbs) {
      final absType = AbsoluteTimelockType.fromString(path.absTimelock.timelockType.name);
      final absValue = path.absTimelock.value;
      if (absType == AbsoluteTimelockType.blocks) {
        if (tipHeight == 0) {
          return (
            icon: Icons.sync_disabled_outlined,
            text: l10n.psbtTimelockSyncRequired,
            color: theme.colorScheme.onSurface.withAlpha(AppAlpha.inactive),
          );
        }
        final remaining = absValue - tipHeight;
        if (remaining > 0) {
          return (
            icon: Icons.lock_outline,
            text: l10n.psbtTimelockBlocksRemaining(
              remaining,
              BitcoinFormatter.formatDuration(remaining * 10),
            ),
            color: Colors.orange,
          );
        }
        return (
          icon: Icons.lock_open_outlined,
          text: l10n.spendPathUnlocked,
          color: Colors.green,
        );
      } else {
        final nowSecs = DateTime.now().millisecondsSinceEpoch ~/ 1000;
        final remaining = absValue - nowSecs;
        if (remaining > 0) {
          return (
            icon: Icons.lock_outline,
            text: l10n.psbtTimelockTimeRemaining(
              BitcoinFormatter.formatDuration(remaining ~/ 60),
            ),
            color: Colors.orange,
          );
        }
        return (
          icon: Icons.lock_open_outlined,
          text: l10n.spendPathUnlocked,
          color: Colors.green,
        );
      }
    }

    return null;
  }

  Widget _buildRbfCard(BuildContext context) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    final resolvedInfos = _rbfInfos.values.whereType<APIRbfInfo>().toList();
    final hasLoading = _rbfInfos.values.any((v) => v == null);

    // Rate constraint (fixed, from original txs — ImprovesFeerateDiagram).
    final maxOrigRate = resolvedInfos.fold<double>(
      0.0,
      (m, i) => max(m, i.minFeeRateSatPerVb),
    );
    final currentRate = double.tryParse(_feeRateCtrl.text) ?? 0.0;
    final rateTooLow = resolvedInfos.isNotEmpty && currentRate <= maxOrigRate;

    // Absolute fee constraint (Rule 4 — depends on new tx size).
    final summary = _txSummary;
    final totalOrigFee =
        resolvedInfos.fold<int>(0, (s, i) => s + i.origFeeSat.toInt());
    final int? actualNewVsize =
        summary != null ? (summary.totalWu / 4.0).ceil() : null;
    final int minFeeSat = actualNewVsize != null
        ? totalOrigFee + actualNewVsize
        : resolvedInfos.fold<int>(0, (m, i) => max(m, i.minFeeSat.toInt()));
    final bool absFeeTooLow = resolvedInfos.isNotEmpty &&
        summary != null &&
        summary.feeSats <= minFeeSat;

    final bool feeTooLow = rateTooLow || absFeeTooLow;
    final warningColor = feeTooLow ? colorScheme.error : AppAccent.color;

    return Card(
      margin: EdgeInsets.zero,
      color: warningColor.withAlpha(AppAlpha.faint),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: warningColor.withAlpha(AppAlpha.pale)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.warning_amber_rounded, size: 16, color: warningColor),
                const SizedBox(width: 6),
                Text(
                  l10n.rbfWarningTitle,
                  style: theme.textTheme.labelMedium?.copyWith(color: warningColor),
                ),
              ],
            ),
            const SizedBox(height: 8),
            if (resolvedInfos.isEmpty && hasLoading)
              Text(
                l10n.rbfUnknownFee,
                style: theme.textTheme.bodySmall,
              )
            else if (resolvedInfos.isNotEmpty) ...[
              Builder(builder: (ctx) {
                // For display, show the info of the spending tx with the highest fee
                // (i.e., strictest constraint).
                final info = resolvedInfos.reduce(
                  (a, b) => b.origFeeSat > a.origFeeSat ? b : a,
                );
                final dimColor = theme.colorScheme.onSurface.withAlpha(AppAlpha.secondary);
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _rbfRow(
                      l10n.rbfOriginalFee,
                      '${info.origFeeSat} sats  (${info.origFeeRateSatPerVb.toStringAsFixed(1)} sat/vB, ${info.origVsize} vB)',
                      dimColor,
                      theme,
                    ),
                    const SizedBox(height: 4),
                    _rbfRow(
                      l10n.rbfMinFee,
                      '> $minFeeSat sats${actualNewVsize == null ? ' ~' : ''}',
                      absFeeTooLow ? warningColor : dimColor,
                      theme,
                    ),
                    const SizedBox(height: 4),
                    _rbfRow(
                      l10n.rbfMinRate,
                      '> ${maxOrigRate.toStringAsFixed(1)} sat/vB',
                      rateTooLow ? warningColor : dimColor,
                      theme,
                    ),
                  ],
                );
              }),
            ],
          ],
        ),
      ),
    );
  }

  Widget _rbfRow(String label, String value, Color valueColor, ThemeData theme) {
    return Row(
      children: [
        SizedBox(
          width: 110,
          child: Text(
            label,
            style: theme.textTheme.bodySmall
                ?.copyWith(color: theme.colorScheme.onSurface.withAlpha(AppAlpha.secondary)),
          ),
        ),
        Expanded(
          child: Text(
            value,
            style: theme.textTheme.bodySmall?.copyWith(color: valueColor),
          ),
        ),
      ],
    );
  }

  Widget _buildSelectedPathCard(
    BuildContext context,
    APISpendPath path,
    int tipHeight,
    int? utxoMaxConfHeight,
  ) {
    final theme = Theme.of(context);

    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '${path.threshold}-of-${path.mfps.length}',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurface.withAlpha(AppAlpha.medium),
              ),
            ),
            const SizedBox(height: 8),
            ...path.mfps.map((mfp) {
              final label = widget.keyLabels[mfp];
              final display = mfp.substring(0, 8).toUpperCase();
              return Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Row(
                  children: [
                    MfpBadge(label: display, color: theme.colorScheme.outline),
                    if (label != null && label.isNotEmpty) ...[
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          label,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.bodySmall,
                        ),
                      ),
                    ],
                  ],
                ),
              );
            }),
          ],
        ),
      ),
    );
  }

  // ─── Fee inline-edit field ────────────────────────────────────────────────

  Widget _buildFeeField({
    required BuildContext context,
    required String labelText,
    required String suffixText,
    required TextEditingController controller,
    required _FeeEditMode thisMode,
    required String displayValue,
    required bool isDecimal,
    required VoidCallback onEditTap,
    required VoidCallback onDone,
    String? errorText,
  }) {
    if (_feeEditMode == thisMode) {
      return TextFormField(
        controller: controller,
        focusNode: isDecimal ? _rateFocusNode : _totalFocusNode,
        decoration: InputDecoration(
          labelText: labelText,
          suffixText: suffixText,
          errorText: errorText,
        ),
        keyboardType: isDecimal
            ? const TextInputType.numberWithOptions(decimal: true)
            : TextInputType.number,
        inputFormatters: isDecimal ? [] : [FilteringTextInputFormatter.digitsOnly],
        onChanged: isDecimal ? _onFeeRateChanged : _onTotalFeeChanged,
        onEditingComplete: onDone,
        onTapOutside: (_) => onDone(),
      );
    }
    return InkWell(
      onTap: onEditTap,
      child: InputDecorator(
        decoration: InputDecoration(
          labelText: labelText,
          suffixText: suffixText,
          errorText: errorText,
        ),
        isEmpty: false,
        child: Text(displayValue),
      ),
    );
  }

  // ─── Submit ───────────────────────────────────────────────────────────────

  Future<void> _submit() async {
    // Validate coin selection.
    if (_selectedUtxos.isEmpty) {
      showErrorToast(context, context.l10n.createTxSelectCoinsFirst);
      return;
    }

    // Validate recipient.
    if (_recipientCtrl.text.trim().isEmpty) {
      setState(() => _recipientEditMode = true);
      return;
    }

    // Confirm any pending fee edit before submitting.
    if (_feeEditMode != _FeeEditMode.none) {
      if (_feeEditMode == _FeeEditMode.total) _syncRateFromTotal();
      setState(() => _feeEditMode = _FeeEditMode.none);
      return;
    }

    final minFeeRate = context.read<SettingsCubit>().state.minFeeRate;
    final rate = double.tryParse(_feeRateCtrl.text.trim());
    if (rate == null || rate < minFeeRate) {
      setState(() => _feeEditMode = _FeeEditMode.rate);
      return;
    }

    // Two independent RBF checks (Bitcoin Core ReplacementChecks):
    final resolvedRbfInfos = _rbfInfos.values.whereType<APIRbfInfo>().toList();
    if (resolvedRbfInfos.isNotEmpty) {
      // 1. ImprovesFeerateDiagram: new_rate must strictly exceed orig_rate.
      //    Fixed — independent of new tx size.
      final maxOrigRate = resolvedRbfInfos.fold<double>(
        0.0,
        (m, i) => max(m, i.minFeeRateSatPerVb),
      );
      if (rate <= maxOrigRate) {
        showErrorToast(context, context.l10n.rbfFeeTooLow(maxOrigRate));
        setState(() => _feeEditMode = _FeeEditMode.rate);
        return;
      }

      // 2. BIP-125 Rule 4 (PaysForRBF): new_fee must strictly exceed orig_fee + new_vsize × 1.
      //    Depends on new tx size — checked only when estimate is available.
      final summary = _txSummary;
      if (summary != null) {
        final newVsize = (summary.totalWu / 4.0).ceil();
        final totalOrigFee =
            resolvedRbfInfos.fold<int>(0, (s, i) => s + i.origFeeSat.toInt());
        if (summary.feeSats <= totalOrigFee + newVsize) {
          showErrorToast(context, context.l10n.rbfFeeTooLow(maxOrigRate));
          setState(() => _feeEditMode = _FeeEditMode.rate);
          return;
        }
      }
    }

    if (!_formKey.currentState!.validate()) return;
    if (_selectedPath == null) return;

    final l10n = context.l10n;
    final amount = _sendMax ? 0 : (int.tryParse(_amountCtrl.text.trim()) ?? 0);

    setState(() => _creating = true);
    try {
      final cubit = context.read<WalletDetailCubit>();
      final selectedUtxos = _selectedUtxos
          .map((u) => APICoinControl(txid: u.txid, vout: u.vout))
          .toList();

      final psbt = await cubit.createPsbt(
        recipientAddress: _recipientCtrl.text.trim(),
        amountSat: amount,
        feeRateSatPerVb: rate,
        selectedUtxos: selectedUtxos,
        policyPath: _selectedPath!.policyPath,
        spendPathId: _selectedPath!.id,
        threshold: _selectedPath!.threshold,
        mfps: _selectedPath!.mfps,
        sendMax: _sendMax,
        label: _labelCtrl.text.trim(),
      );

      if (!mounted) return;
      if (psbt != null) {
        showSuccessToast(context, l10n.createTxSuccess);
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(
            builder: (_) => BlocProvider.value(
              value: cubit,
              child: PsbtDetailScreen(psbt: psbt, spendPath: _selectedPath),
            ),
          ),
        );
      }
    } catch (e) {
      if (mounted) showErrorToastException(context, e);
    } finally {
      if (mounted) setState(() => _creating = false);
    }
  }

  // ─── Build ────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final summary = _txSummary;
    final dimColor = theme.colorScheme.onSurface.withAlpha(AppAlpha.secondary);

    // Fee field inline validation.
    final minFeeRate = context.read<SettingsCubit>().state.minFeeRate;
    final resolvedRbfInfos = _rbfInfos.values.whereType<APIRbfInfo>().toList();
    final maxOrigRate =
        resolvedRbfInfos.fold<double>(0.0, (m, i) => max(m, i.minFeeRateSatPerVb));
    // Effective minimum rate: stricter of relay minimum and RBF diagram constraint.
    final effectiveMinRate =
        resolvedRbfInfos.isNotEmpty ? max(minFeeRate.toDouble(), maxOrigRate) : minFeeRate.toDouble();
    final currentRate = double.tryParse(_feeRateCtrl.text) ?? 0.0;

    // RBF absolute fee minimum (Rule 4) — depends on new tx size.
    int rbfMinFeeSats = 0;
    if (resolvedRbfInfos.isNotEmpty && summary != null) {
      final newVsize = (summary.totalWu / 4.0).ceil();
      final totalOrigFee =
          resolvedRbfInfos.fold<int>(0, (s, i) => s + i.origFeeSat.toInt());
      rbfMinFeeSats = totalOrigFee + newVsize;
    }

    final String? rateErrorText =
        currentRate > 0 && currentRate <= effectiveMinRate
            ? 'min: ${effectiveMinRate.toStringAsFixed(2)} sat/vB'
            : null;

    final String? feeErrorText =
        rbfMinFeeSats > 0 && summary != null && !summary.insufficientFunds && summary.feeSats <= rbfMinFeeSats
            ? 'min: $rbfMinFeeSats sats'
            : null;

    // Live display values for fee fields.
    final feeRateDisplay = _feeEditMode == _FeeEditMode.total
        ? (summary != null
            ? summary.feeRate.toStringAsFixed(2)
            : _feeRateCtrl.text)
        : _feeRateCtrl.text;
    // Total fee display: live from summary in all modes except when the user
    // is actively editing the total fee field.
    final totalFeeDisplay = _feeEditMode == _FeeEditMode.total
        ? (_totalFeeCtrl.text.isEmpty ? '—' : _totalFeeCtrl.text)
        : (summary?.feeSats.toString() ?? '—');

    // Max confirmation height of selected UTXOs — used for relative timelock display.
    final confirmedHeights = _selectedUtxos
        .where((u) => u.confirmationHeight != null)
        .map((u) => u.confirmationHeight!)
        .toList();
    final int? utxoMaxConfHeight =
        confirmedHeights.isEmpty ? null : confirmedHeights.reduce(max);

    return Scaffold(
      appBar: AppBar(title: Text(l10n.createTxTitle)),
      body: SafeArea(
        child: Form(
          key: _formKey,
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              // ── Coin selector ──
              Card(
                margin: const EdgeInsets.only(bottom: 16),
                clipBehavior: Clip.antiAlias,
                child: InkWell(
                  onTap: _openCoinSelector,
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Row(
                      children: [
                        const Icon(Icons.toll, size: 20),
                        const SizedBox(width: 8),
                        Expanded(
                          child: _selectedUtxos.isEmpty
                              ? Text(
                                  l10n.coinSelectorNoCoinsSelected,
                                  style: theme.textTheme.bodyMedium?.copyWith(
                                    color: theme.colorScheme.onSurface.withAlpha(AppAlpha.secondary),
                                    fontStyle: FontStyle.italic,
                                  ),
                                )
                              : Text(
                                  l10n.createTxSelectedCoins(
                                    _selectedUtxos.length,
                                    _selectedSats,
                                  ),
                                  style: theme.textTheme.bodyMedium,
                                ),
                        ),
                        const Icon(Icons.chevron_right, size: 18),
                      ],
                    ),
                  ),
                ),
              ),

              // ── RBF warning card (always 2 children — stable indices below) ──
              _rbfInfos.isNotEmpty
                  ? _buildRbfCard(context)
                  : const SizedBox.shrink(),
              SizedBox(height: _rbfInfos.isNotEmpty ? 16 : 0),

              // ── Label ──
              TextField(
                controller: _labelCtrl,
                decoration: InputDecoration(
                  labelText: l10n.txLabelTitle,
                  hintText: l10n.psbtLabelHint,
                  isDense: true,
                  border: const OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 16),

              // ── Recipient + Self button ──
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: _recipientEditMode
                        ? TextFormField(
                            controller: _recipientCtrl,
                            autofocus: true,
                            decoration: InputDecoration(
                              labelText: l10n.createTxRecipient,
                              hintText: l10n.createTxRecipientHint,
                            ),
                            keyboardType: TextInputType.text,
                            autocorrect: false,
                            onChanged: _onRecipientChanged,
                            onEditingComplete: _confirmRecipient,
                            onTapOutside: (_) => _confirmRecipient(),
                          )
                        : InkWell(
                            onTap: () => setState(() => _recipientEditMode = true),
                            child: InputDecorator(
                              decoration: InputDecoration(
                                labelText: l10n.createTxRecipient,
                                suffixIcon: _resolvingWu
                                    ? const Padding(
                                        padding: EdgeInsets.all(12),
                                        child: SizedBox(
                                          width: 14,
                                          height: 14,
                                          child: CircularProgressIndicator(strokeWidth: 2),
                                        ),
                                      )
                                    : null,
                              ),
                              isEmpty: false,
                              child: ColoredGroupText(
                                text: _recipientCtrl.text,
                                truncate: true,
                              ),
                            ),
                          ),
                  ),
                  const SizedBox(width: 8),
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: OutlinedButton(
                      onPressed: _showWalletPickerSheet,
                      style: OutlinedButton.styleFrom(
                        foregroundColor: theme.colorScheme.onSurface.withAlpha(AppAlpha.mediumHigh),
                        side: BorderSide(color: theme.colorScheme.outline),
                      ),
                      child: Text(l10n.createTxMyWalletsButton),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),

              // ── Amount + MAX toggle ──
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: _sendMax
                        ? InputDecorator(
                            decoration: InputDecoration(labelText: l10n.createTxSendMax),
                            isEmpty: false,
                            child: Text(
                              (summary != null && !summary.insufficientFunds)
                                  ? summary.sendSats.toString()
                                  : '—',
                              style: theme.textTheme.bodyLarge,
                            ),
                          )
                        : TextFormField(
                            controller: _amountCtrl,
                            decoration: InputDecoration(labelText: l10n.createTxAmount),
                            keyboardType: TextInputType.number,
                            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                            onChanged: _onAmountChanged,
                            validator: (v) {
                              if (_sendMax) return null;
                              if (v == null || v.trim().isEmpty) return l10n.createTxAmountRequired;
                              final n = int.tryParse(v.trim());
                              if (n == null || n <= 0) return l10n.createTxAmountInvalid;
                              return null;
                            },
                          ),
                  ),
                  const SizedBox(width: 8),
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: OutlinedButton(
                      onPressed: _toggleSendMax,
                      style: _sendMax
                          ? OutlinedButton.styleFrom(
                              backgroundColor: theme.colorScheme.primary,
                              foregroundColor: theme.colorScheme.onPrimary,
                              side: BorderSide(color: theme.colorScheme.primary),
                            )
                          : OutlinedButton.styleFrom(
                              foregroundColor: theme.colorScheme.onSurface.withAlpha(AppAlpha.mediumHigh),
                              side: BorderSide(color: theme.colorScheme.outline),
                            ),
                      child: Text(l10n.createTxMaxButton),
                    ),
                  ),
                ],
              ),

              // Amount sub-info — always present (stable slot prevents ListView index shifts).
              const SizedBox(height: 4),
              Padding(
                padding: const EdgeInsets.only(left: 12),
                child: summary == null
                    ? const SizedBox.shrink()
                    : summary.insufficientFunds
                        ? Text(
                            l10n.createTxEstInsufficientFunds,
                            style: theme.textTheme.bodySmall
                                ?.copyWith(color: theme.colorScheme.error),
                          )
                        : (!_sendMax && summary.hasChange)
                            ? Text(
                                '${l10n.createTxEstChange}: ${BitcoinFormatter.formatNum(summary.changeSats)} sats',
                                style: theme.textTheme.bodySmall?.copyWith(color: dimColor),
                              )
                            : const SizedBox.shrink(),
              ),

              const SizedBox(height: 16),

              // ── Fee fields (inline edit — only one active at a time) ──
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: _buildFeeField(
                      context: context,
                      labelText: l10n.createTxFeeRate,
                      suffixText: 'sat/vB',
                      controller: _feeRateCtrl,
                      thisMode: _FeeEditMode.rate,
                      displayValue: feeRateDisplay,
                      isDecimal: true,
                      errorText: rateErrorText,
                      onEditTap: () {
                        final rate = double.tryParse(feeRateDisplay) ?? 0.0;
                        _feeRateCtrl.text = rate <= effectiveMinRate
                            ? (effectiveMinRate + 0.01).toStringAsFixed(2)
                            : feeRateDisplay;
                        setState(() => _feeEditMode = _FeeEditMode.rate);
                        WidgetsBinding.instance.addPostFrameCallback((_) {
                          if (mounted) _rateFocusNode.requestFocus();
                        });
                      },
                      onDone: _confirmFeeRate,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _buildFeeField(
                      context: context,
                      labelText: l10n.createTxTotalFee,
                      suffixText: 'sats',
                      controller: _totalFeeCtrl,
                      thisMode: _FeeEditMode.total,
                      displayValue: totalFeeDisplay,
                      isDecimal: false,
                      errorText: feeErrorText,
                      onEditTap: () {
                        final feeSats = summary?.feeSats ?? 0;
                        _totalFeeCtrl.text = rbfMinFeeSats > 0 && feeSats <= rbfMinFeeSats
                            ? (rbfMinFeeSats + 1).toString()
                            : (feeSats > 0 ? feeSats.toString() : '');
                        setState(() => _feeEditMode = _FeeEditMode.total);
                        WidgetsBinding.instance.addPostFrameCallback((_) {
                          if (mounted) _totalFocusNode.requestFocus();
                        });
                      },
                      onDone: () {
                        _syncRateFromTotal();
                        setState(() => _feeEditMode = _FeeEditMode.none);
                      },
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),

              // ── Spend path selector ──
              if (widget.spendPaths == null || widget.spendPaths!.isEmpty)
                Padding(
                  padding: const EdgeInsets.only(bottom: 16),
                  child: Text(
                    l10n.createTxNoSpendPaths,
                    style: TextStyle(color: theme.colorScheme.error),
                  ),
                )
              else
                DropdownButtonFormField<APISpendPath>(
                  initialValue: _selectedPath,
                  decoration: InputDecoration(labelText: l10n.createTxSpendPath),
                  items: widget.spendPaths!
                      .map((p) {
                        final lockStatus = _timelockStatus(
                          context, p, widget.tipHeight, utxoMaxConfHeight,
                        );
                        return DropdownMenuItem(
                          value: p,
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Flexible(
                                child: Text(
                                  _pathLabel(p),
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                              if (lockStatus != null) ...[
                                const SizedBox(width: 6),
                                Icon(lockStatus.icon, size: 14, color: lockStatus.color),
                                const SizedBox(width: 3),
                                Text(
                                  lockStatus.text,
                                  style: theme.textTheme.bodySmall
                                      ?.copyWith(color: lockStatus.color),
                                ),
                              ],
                            ],
                          ),
                        );
                      })
                      .toList(),
                  onChanged: (p) => setState(() => _selectedPath = p),
                  validator: (v) => v == null ? l10n.createTxSpendPathHint : null,
                ),

              if (_selectedPath != null) ...[
                const SizedBox(height: 12),
                _buildSelectedPathCard(
                  context, _selectedPath!, widget.tipHeight, utxoMaxConfHeight,
                ),
              ],

              const SizedBox(height: 24),

              FilledButton.icon(
                onPressed: (_creating || _selectedPath == null) ? null : _submit,
                icon: _creating
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.receipt_long_outlined),
                label: Text(l10n.createTxButton),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
