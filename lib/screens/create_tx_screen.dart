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
import 'package:deadbolt/services/fee_estimation_service.dart';
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

/// Formats a sats integer input with thousands separators (e.g. 1,234,567).
class _ThousandsSeparatorFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(
      TextEditingValue oldValue, TextEditingValue newValue) {
    final digits = newValue.text.replaceAll(',', '');
    if (digits.isEmpty) return newValue.copyWith(text: '');
    final n = int.tryParse(digits);
    if (n == null) return oldValue;
    final formatted = _fmt(n);
    return newValue.copyWith(
      text: formatted,
      selection: TextSelection.collapsed(offset: formatted.length),
    );
  }

  static String _fmt(int n) {
    final s = n.toString();
    final buf = StringBuffer();
    for (int i = 0; i < s.length; i++) {
      if (i > 0 && (s.length - i) % 3 == 0) buf.write(',');
      buf.write(s[i]);
    }
    return buf.toString();
  }
}

/// Holds the per-recipient state for the multi-output send form.
class _RecipientEntry {
  _RecipientEntry();

  final addressCtrl = TextEditingController();
  final amountCtrl = TextEditingController();
  int? wu; // output weight units from addressOutputWu()

  /// Parses the amount field stripping thousands separators.
  int get rawAmount => int.tryParse(amountCtrl.text.replaceAll(',', '').trim()) ?? 0;
  bool editMode = true;
  bool resolvingWu = false;
  Timer? debounce;

  void dispose() {
    debounce?.cancel();
    addressCtrl.dispose();
    amountCtrl.dispose();
  }
}

/// Screen for building an unsigned PSBT. Coin selection happens inside this
/// screen via [CoinSelectorScreen].
class CreateTxScreen extends StatefulWidget {
  final List<APIUtxo> allUtxos;
  final int tipHeight;
  final List<APISpendPath>? spendPaths;
  final Map<String, String> keyLabels;
  final Map<int, String> pathLabels;
  // CPFP mode: pre-selected UTXOs and recipient address.
  final List<APIUtxo> preSelectedUtxos;
  final String? preFilledRecipient;

  const CreateTxScreen({
    super.key,
    this.allUtxos = const [],
    this.tipHeight = 0,
    this.spendPaths,
    this.keyLabels = const {},
    this.pathLabels = const {},
    this.preSelectedUtxos = const [],
    this.preFilledRecipient,
  });

  static Future<void> push(
    BuildContext context, {
    List<APIUtxo> allUtxos = const [],
    int tipHeight = 0,
    List<APISpendPath>? spendPaths,
    Map<String, String> keyLabels = const {},
    Map<int, String> pathLabels = const {},
    List<APIUtxo> preSelectedUtxos = const [],
    String? preFilledRecipient,
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
            preSelectedUtxos: preSelectedUtxos,
            preFilledRecipient: preFilledRecipient,
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
  final _feeRateCtrl = TextEditingController(text: '1.0');
  final _totalFeeCtrl = TextEditingController();
  final _labelCtrl = TextEditingController();
  bool _creating = false;

  // Multi-recipient state.
  final List<_RecipientEntry> _recipients = [_RecipientEntry()];
  /// Index of the recipient that gets the wallet remainder (send-max semantics).
  /// null = every recipient has an explicit amount.
  int? _maxRecipientIndex;

  APISpendPath? _selectedPath;
  _FeeEditMode _feeEditMode = _FeeEditMode.none;

  // Selected UTXOs (chosen via CoinSelectorScreen)
  List<APIUtxo> _selectedUtxos = [];

  // RBF info: mempoolSpendingTxid -> APIRbfInfo (null while loading)
  final Map<String, APIRbfInfo?> _rbfInfos = {};

  // CPFP info: loaded once when unconfirmed UTXOs are selected (null while loading/unavailable).
  APICpfpInfo? _cpfpInfo;
  bool _cpfpInfoLoading = false;

  FeePresets? _feePresets;
  int? _selectedPresetIndex; // 0=economy, 1=normal, 2=priority; null=none

  // Focus nodes for the two fee fields — explicit requestFocus() is more reliable
  // than autofocus: true on desktop platforms.
  final _rateFocusNode = FocusNode();
  final _totalFocusNode = FocusNode();

  @override
  void initState() {
    super.initState();
    if (widget.spendPaths != null && widget.spendPaths!.isNotEmpty) {
      _selectedPath = widget.spendPaths!.first;
    }
    if (widget.preSelectedUtxos.isNotEmpty) {
      _selectedUtxos = List.of(widget.preSelectedUtxos);
      _updateRbfInfos();
    }
    if (widget.preFilledRecipient != null) {
      _recipients[0].addressCtrl.text = widget.preFilledRecipient!;
      _recipients[0].editMode = false;
      _maxRecipientIndex = 0;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _onRecipientChanged(widget.preFilledRecipient!, 0);
      });
    }
    _loadFeePresets();
  }

  APINetwork get _currentNetwork {
    final state = context.read<WalletDetailCubit>().state;
    return state is WalletDetailLoaded ? state.walletInfo.network : APINetwork.bitcoin;
  }

  void _loadFeePresets() {
    final explorerBase =
        context.read<SettingsCubit>().state.explorerBaseForNetwork(_currentNetwork);
    FeeEstimationService.getPresets(explorerBase).then((p) {
      if (mounted) setState(() => _feePresets = p);
    });
  }

  @override
  void dispose() {
    for (final entry in _recipients) {
      entry.dispose();
    }
    _feeRateCtrl.dispose();
    _totalFeeCtrl.dispose();
    _labelCtrl.dispose();
    _rateFocusNode.dispose();
    _totalFocusNode.dispose();
    super.dispose();
  }

  // ─── Fee callbacks ────────────────────────────────────────────────────────

  void _onFeeRateChanged(String _) => setState(() {
    _selectedPresetIndex = null;
  });
  void _onTotalFeeChanged(String _) => setState(() {});
  void _onAmountChanged(String _) => setState(() {});

  void _confirmRecipient(int index) {
    if (_recipients[index].addressCtrl.text.trim().isEmpty) return;
    setState(() => _recipients[index].editMode = false);
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
    // Fallback when summary is unavailable (missing coins / path / recipients).
    final path = _selectedPath;
    if (path == null) return;
    final n = _selectedUtxos.length;
    if (n == 0) return;
    final recipientsWu = _recipients.map((r) => r.wu ?? 0).fold(0, (s, w) => s + w);
    if (recipientsWu == 0) return;
    final wuNoChange = path.wuBase + n * path.wuIn + recipientsWu;
    _feeRateCtrl.text = (fee / (wuNoChange / 4.0)).toStringAsFixed(2);
  }

  // ─── RBF / CPFP helpers ──────────────────────────────────────────────────

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
    _loadCpfpInfo();
  }

  int _totalConflictFee(List<APIRbfInfo> infos) => infos.fold<int>(
        0,
        (s, i) => s + i.origFeeSat.toInt() + (i.descendantFeeSat?.toInt() ?? 0),
      );

  /// Loads CPFP ancestor fee info for all unconfirmed UTXOs' parent txids.
  /// Passes all unique parent txids so Rust can BFS the full ancestor chain.
  void _loadCpfpInfo() {
    final parentTxids = _selectedUtxos
        .where((u) => !u.isConfirmed)
        .map((u) => u.txid)
        .toSet()
        .toList();
    if (parentTxids.isEmpty) {
      setState(() { _cpfpInfo = null; _cpfpInfoLoading = false; });
      return;
    }
    setState(() => _cpfpInfoLoading = true);
    context.read<WalletDetailCubit>().getCpfpInfo(parentTxids).then((info) {
      if (mounted) setState(() { _cpfpInfo = info; _cpfpInfoLoading = false; });
    });
  }

  // ─── Helpers ─────────────────────────────────────────────────────────────

  int get _selectedSats =>
      _selectedUtxos.fold(0, (sum, u) => sum + u.valueSat.toInt());

  void _onRecipientChanged(String value, int index) {
    final entry = _recipients[index];
    entry.debounce?.cancel();
    final trimmed = value.trim();
    if (trimmed.isEmpty) {
      setState(() {
        entry.wu = null;
        entry.resolvingWu = false;
      });
      return;
    }
    setState(() => entry.resolvingWu = true);
    entry.debounce = Timer(const Duration(milliseconds: 400), () async {
      if (!mounted) return;
      try {
        final wu = await addressOutputWu(address: trimmed);
        if (mounted) {
          setState(() {
            entry.wu = wu.toInt();
            entry.resolvingWu = false;
          });
        }
      } catch (_) {
        if (mounted) setState(() { entry.wu = null; entry.resolvingWu = false; });
      }
    });
  }

  void _addRecipient() {
    setState(() {
      _recipients.add(_RecipientEntry());
    });
  }

  void _removeRecipient(int index) {
    setState(() {
      _recipients[index].dispose();
      if (_recipients.length == 1) {
        // Last entry: reset instead of remove.
        _recipients[0] = _RecipientEntry();
        _maxRecipientIndex = null;
      } else {
        _recipients.removeAt(index);
        // Fix MAX index after removal.
        if (_maxRecipientIndex != null) {
          if (_maxRecipientIndex == index) {
            _maxRecipientIndex = null;
          } else if (_maxRecipientIndex! > index) {
            _maxRecipientIndex = _maxRecipientIndex! - 1;
          }
        }
      }
    });
  }

  void _toggleMaxForEntry(int index) {
    setState(() {
      _maxRecipientIndex = (_maxRecipientIndex == index) ? null : index;
    });
  }

  // ─── Transaction estimate ────────────────────────────────────────────────

  _TxSummary? get _txSummary {
    final path = _selectedPath;
    if (path == null || _selectedUtxos.isEmpty) return null;
    // All entries must have WU resolved.
    if (_recipients.any((r) => r.wu == null)) return null;

    final n = _selectedUtxos.length;
    final totalIn = _selectedSats;
    final recipientsWu = _recipients.fold(0, (s, r) => s + r.wu!);
    final wuNoChange = path.wuBase + n * path.wuIn + recipientsWu;
    final wuWithChange = wuNoChange + path.wuOut;

    final hasDrain = _maxRecipientIndex != null;

    // Determine fee rate — branch by active edit mode.
    double? rate;
    if (_feeEditMode == _FeeEditMode.total) {
      final fee = int.tryParse(_totalFeeCtrl.text);
      if (fee == null || fee <= 0) return null;
      if (!hasDrain) {
        // Total explicit outputs. Pick denominator that matches actual tx structure.
        final totalAmount = _recipients.fold(0, (s, r) => s + r.rawAmount);
        final remainderIfExactFee = totalIn - totalAmount - fee;
        rate = remainderIfExactFee >= _dustLimit
            ? fee / (wuWithChange / 4.0) // change output present
            : fee / (wuNoChange / 4.0);  // no change output
      } else {
        rate = fee / (wuNoChange / 4.0); // drain: no change output
      }
    } else {
      rate = double.tryParse(_feeRateCtrl.text);
    }
    if (rate == null || rate <= 0) return null;

    if (hasDrain) {
      final fee = (rate * wuNoChange / 4.0).ceil();
      // Non-drain recipients have explicit amounts.
      final nonDrainAmount = _recipients
          .asMap()
          .entries
          .where((e) => e.key != _maxRecipientIndex)
          .fold(0, (s, e) => s + e.value.rawAmount);
      final drainAmount = totalIn - nonDrainAmount - fee;
      return _TxSummary(
        feeSats: fee,
        changeSats: 0,
        sendSats: drainAmount > 0 ? drainAmount : 0,
        feeRate: rate,
        totalWu: wuNoChange,
        hasChange: false,
        insufficientFunds: drainAmount <= 0,
      );
    }

    // All amounts explicit.
    final totalAmount = _recipients.fold(0, (s, r) => s + r.rawAmount);
    if (totalAmount <= 0) return null;

    final feeWithChange = (rate * wuWithChange / 4.0).ceil();
    final change = totalIn - totalAmount - feeWithChange;

    if (change >= _dustLimit) {
      return _TxSummary(
        feeSats: feeWithChange,
        changeSats: change,
        sendSats: totalAmount,
        feeRate: rate,
        totalWu: wuWithChange,
        hasChange: true,
      );
    } else {
      final feeNoChange = (rate * wuNoChange / 4.0).ceil();
      final leftover = totalIn - totalAmount - feeNoChange;
      if (leftover < 0) {
        return _TxSummary(
          feeSats: feeNoChange,
          changeSats: 0,
          sendSats: totalAmount,
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
        sendSats: totalAmount,
        feeRate: (feeNoChange + leftover) / (wuNoChange / 4.0),
        totalWu: wuNoChange,
        hasChange: false,
      );
    }
  }

  // ─── Actions ─────────────────────────────────────────────────────────────

  Future<void> _showWalletPickerSheet(int recipientIndex) async {
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
                          _fillAddressFromWallet(wallet.walletPath, recipientIndex);
                        },
                );
              }),
              const SizedBox(height: 8),
          ],
          );
      });
  }

  Future<void> _fillAddressFromWallet(String walletPath, int recipientIndex) async {
    final l10n = context.l10n;
    final cubit = context.read<WalletDetailCubit>();
    final walletState = cubit.state;

    // Addresses already assigned to other recipients — skip them so each
    // slot gets a distinct address even within the same wallet.
    final alreadyUsed = _recipients
        .asMap()
        .entries
        .where((e) => e.key != recipientIndex)
        .map((e) => e.value.addressCtrl.text.trim())
        .where((a) => a.isNotEmpty)
        .toSet();

    final String? address;
    if (walletState is WalletDetailLoaded &&
        walletPath == walletState.walletInfo.walletPath) {
      address = await cubit.getNextSelfPaymentAddress(alreadyUsed: alreadyUsed);
    } else {
      address = await cubit.getNextReceiveAddressFor(walletPath, alreadyUsed: alreadyUsed);
    }
    if (!mounted) return;
    if (address == null) {
      showErrorToast(context, l10n.createTxNoUnusedAddress);
      return;
    }
    final entry = _recipients[recipientIndex];
    entry.addressCtrl.text = address;
    setState(() => entry.editMode = false);
    _onRecipientChanged(address, recipientIndex);
  }

  Future<void> _openCoinSelector() async {
    final network = _currentNetwork;
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
    // Uses total conflict cluster fee: orig + any unconfirmed descendants (BIP-125 Rule 4).
    final summary = _txSummary;
    final totalConflictFee = _totalConflictFee(resolvedInfos);
    final int? actualNewVsize =
        summary != null ? (summary.totalWu / 4.0).ceil() : null;
    final int minFeeSat = actualNewVsize != null
        ? totalConflictFee + actualNewVsize
        : resolvedInfos.fold<int>(0, (m, i) => max(m, i.minFeeSat.toInt()));
    final bool absFeeTooLow = resolvedInfos.isNotEmpty &&
        summary != null &&
        !summary.insufficientFunds &&
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
                    if (info.descendantCount > 0) ...[
                      const SizedBox(height: 4),
                      _rbfRow(
                        l10n.rbfDescendants,
                        info.descendantFeeSat != null
                            ? '${info.descendantCount} tx${info.descendantCount > 1 ? 's' : ''}, ${info.descendantFeeSat} sats'
                            : '${info.descendantCount} tx${info.descendantCount > 1 ? 's' : ''} (fee unknown)',
                        dimColor,
                        theme,
                      ),
                    ],
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

  /// Banner shown when unconfirmed UTXOs are selected, displaying the CPFP package fee rate.
  /// Accounts for all ancestor txs transitively (parents, grandparents, …).
  Widget _buildCpfpBanner(BuildContext context) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    const accentColor = AppAccent.color;
    final cpfp = _cpfpInfo;
    final summary = _txSummary;

    // Effective package fee rate = (ancestor_fees + child_fee) / (ancestor_vsize + child_vsize).
    String effectiveRateText = '—';
    if (cpfp != null && summary != null) {
      final ancestorFee = cpfp.ancestorFeeSat?.toInt();
      final ancestorVsize = cpfp.ancestorVsize.toInt();
      final childFee = summary.feeSats;
      final childVsize = (summary.totalWu / 4.0).ceil();
      if (ancestorFee != null && (ancestorVsize + childVsize) > 0) {
        final effectiveRate = (ancestorFee + childFee) / (ancestorVsize + childVsize);
        effectiveRateText = '${effectiveRate.toStringAsFixed(1)} sat/vB';
      }
    }

    // Ancestor fee summary line.
    final String ancestorFeeText;
    if (cpfp != null) {
      if (cpfp.ancestorFeeSat != null) {
        ancestorFeeText =
            '${cpfp.ancestorFeeSat} sats  (${cpfp.ancestorFeeRateSatPerVb.toStringAsFixed(1)} sat/vB, ${cpfp.ancestorVsize} vB)';
      } else {
        ancestorFeeText = l10n.rbfUnknownFee;
      }
    } else {
      ancestorFeeText = _cpfpInfoLoading ? '…' : '—';
    }

    return Card(
      margin: EdgeInsets.zero,
      color: accentColor.withAlpha(AppAlpha.faint),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: accentColor.withAlpha(AppAlpha.pale)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.trending_up, size: 16, color: accentColor),
                const SizedBox(width: 6),
                Text(
                  l10n.cpfpBannerTitle,
                  style: theme.textTheme.labelMedium?.copyWith(color: accentColor),
                ),
              ],
            ),
            const SizedBox(height: 8),
            _rbfRow(
              l10n.cpfpParentFee,
              ancestorFeeText,
              colorScheme.onSurface.withAlpha(AppAlpha.secondary),
              theme,
            ),
            if (cpfp != null && cpfp.ancestorCount > 1) ...[
              const SizedBox(height: 4),
              _rbfRow(
                l10n.cpfpAncestorCount,
                '${cpfp.ancestorCount}',
                colorScheme.onSurface.withAlpha(AppAlpha.secondary),
                theme,
              ),
            ],
            const SizedBox(height: 4),
            _rbfRow(
              l10n.cpfpEffectiveRate,
              effectiveRateText,
              accentColor,
              theme,
            ),
          ],
        ),
      ),
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

  // ─── Recipients ──────────────────────────────────────────────────────────

  List<Widget> _buildRecipientList(
      BuildContext context, ThemeData theme, _TxSummary? summary) {
    final l10n = context.l10n;
    final colorScheme = theme.colorScheme;
    final dimColor = colorScheme.onSurface.withAlpha(AppAlpha.secondary);

    final widgets = <Widget>[];
    for (int i = 0; i < _recipients.length; i++) {
      final entry = _recipients[i];
      final isMax = _maxRecipientIndex == i;

      widgets.add(
        Container(
          margin: const EdgeInsets.only(bottom: 8),
          decoration: BoxDecoration(
            color: colorScheme.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(12),
          ),
          padding: const EdgeInsets.fromLTRB(12, 10, 8, 10),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Row 1: address field + wallet icon + × button
              Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Expanded(
                    child: entry.editMode
                        ? TextFormField(
                            controller: entry.addressCtrl,
                            autofocus: i == 0 && _recipients.length == 1,
                            decoration: InputDecoration(
                              hintText: l10n.createTxRecipientHint,
                              isDense: true,
                              filled: true,
                              fillColor: colorScheme.surface,
                            ),
                            keyboardType: TextInputType.text,
                            autocorrect: false,
                            onChanged: (v) => _onRecipientChanged(v, i),
                            onEditingComplete: () => _confirmRecipient(i),
                            onTapOutside: (_) => _confirmRecipient(i),
                          )
                        : InkWell(
                            onTap: () => setState(() => entry.editMode = true),
                            borderRadius: BorderRadius.circular(4),
                            child: Container(
                              width: double.infinity,
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 12, vertical: 10),
                              decoration: BoxDecoration(
                                color: colorScheme.surface,
                                borderRadius: BorderRadius.circular(4),
                                border: Border.all(
                                    color: colorScheme.outline.withAlpha(180)),
                              ),
                              child: Row(
                                children: [
                                  Expanded(
                                    child: ColoredGroupText(
                                      text: entry.addressCtrl.text,
                                      truncate: true,
                                    ),
                                  ),
                                  if (entry.resolvingWu)
                                    const Padding(
                                      padding: EdgeInsets.only(left: 6),
                                      child: SizedBox(
                                        width: 12,
                                        height: 12,
                                        child: CircularProgressIndicator(
                                            strokeWidth: 2),
                                      ),
                                    ),
                                ],
                              ),
                            ),
                          ),
                  ),
                  // Wallet picker icon
                  SizedBox(
                    width: 32,
                    height: 32,
                    child: IconButton(
                      padding: EdgeInsets.zero,
                      iconSize: 18,
                      icon: const Icon(Icons.account_balance_wallet_outlined),
                      color: colorScheme.onSurface.withAlpha(AppAlpha.secondary),
                      tooltip: l10n.createTxMyWalletsButton,
                      onPressed: () => _showWalletPickerSheet(i),
                    ),
                  ),
                  // × button
                  SizedBox(
                    width: 32,
                    height: 32,
                    child: IconButton(
                      padding: EdgeInsets.zero,
                      iconSize: 18,
                      icon: const Icon(Icons.close),
                      color: colorScheme.onSurface.withAlpha(AppAlpha.secondary),
                      onPressed: () => _removeRecipient(i),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              // Row 2: amount field + MAX chip
              Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Expanded(
                    child: isMax
                        ? Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 12, vertical: 10),
                            decoration: BoxDecoration(
                              color: colorScheme.surface,
                              borderRadius: BorderRadius.circular(4),
                              border: Border.all(
                                  color: colorScheme.primary.withAlpha(180)),
                            ),
                            child: Text(
                              (summary != null && !summary.insufficientFunds)
                                  ? '${BitcoinFormatter.formatNum(summary.sendSats)} sats'
                                  : '— sats',
                              style: theme.textTheme.bodyMedium?.copyWith(
                                  color: colorScheme.primary),
                            ),
                          )
                        : TextFormField(
                            controller: entry.amountCtrl,
                            autovalidateMode: AutovalidateMode.onUserInteraction,
                            decoration: InputDecoration(
                              hintText: l10n.createTxAmount,
                              suffixText: 'sats',
                              isDense: true,
                              filled: true,
                              fillColor: colorScheme.surface,
                            ),
                            keyboardType: TextInputType.number,
                            inputFormatters: [
                              FilteringTextInputFormatter.digitsOnly,
                              _ThousandsSeparatorFormatter(),
                            ],
                            onChanged: _onAmountChanged,
                            validator: (v) {
                              if (_maxRecipientIndex == i) return null;
                              if (v == null || v.trim().isEmpty) return l10n.createTxAmountRequired;
                              final n = int.tryParse(v.replaceAll(',', '').trim());
                              if (n == null || n <= 0) return l10n.createTxAmountInvalid;
                              return null;
                            },
                          ),
                  ),
                  const SizedBox(width: 6),
                  // MAX chip
                  GestureDetector(
                    onTap: () => _toggleMaxForEntry(i),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 150),
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
                      decoration: BoxDecoration(
                        color: isMax ? colorScheme.primary : colorScheme.surface,
                        border: Border.all(
                          color: isMax ? colorScheme.primary : colorScheme.outline,
                        ),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Text(
                        l10n.createTxMaxButton,
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: isMax
                              ? colorScheme.onPrimary
                              : colorScheme.onSurface.withAlpha(AppAlpha.mediumHigh),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      );
    }

    // "+ Add recipient" button
    widgets.add(
      TextButton.icon(
        onPressed: _addRecipient,
        icon: const Icon(Icons.add, size: 16),
        label: Text(l10n.createTxAddRecipient),
      ),
    );

    // Fee summary below the list
    if (summary != null) {
      final hasMultiple = _recipients.length > 1;
      widgets.add(const SizedBox(height: 4));
      widgets.add(
        Padding(
          padding: const EdgeInsets.only(left: 4),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (summary.insufficientFunds)
                Text(
                  l10n.createTxEstInsufficientFunds,
                  style: theme.textTheme.bodySmall?.copyWith(color: colorScheme.error),
                )
              else ...[
                if (hasMultiple)
                  Text(
                    '${l10n.createTxTotalOut}: ${BitcoinFormatter.formatNum(summary.sendSats)} sats',
                    style: theme.textTheme.bodySmall?.copyWith(color: dimColor),
                  ),
                if (summary.hasChange)
                  Text(
                    '${l10n.createTxEstChange}: ${BitcoinFormatter.formatNum(summary.changeSats)} sats',
                    style: theme.textTheme.bodySmall?.copyWith(color: dimColor),
                  ),
              ],
            ],
          ),
        ),
      );
    }

    return widgets;
  }

  // ─── Fee presets ──────────────────────────────────────────────────────────

  void _applyPreset(int index) {
    if (_feePresets == null) return;
    final rates = [_feePresets!.economy, _feePresets!.normal, _feePresets!.priority];
    setState(() {
      _selectedPresetIndex = index;
      _feeRateCtrl.text = rates[index].toStringAsFixed(1);
      _feeEditMode = _FeeEditMode.none;
    });
    final summary = _txSummary;
    if (summary != null) _totalFeeCtrl.text = summary.feeSats.toString();
  }

  Widget _buildFeePresets() {
    if (_feePresets == null) return const SizedBox.shrink();
    final presets = _feePresets!;
    final selected = _selectedPresetIndex != null ? {_selectedPresetIndex!} : <int>{};
    return SegmentedButton<int>(
      style: const ButtonStyle(visualDensity: VisualDensity.compact),
      showSelectedIcon: false,
      segments: [
        ButtonSegment(
          value: 0,
          icon: const Icon(Icons.hourglass_bottom, size: 14),
          label: Text('${presets.economy.toStringAsFixed(0)} sat/vB'),
        ),
        ButtonSegment(
          value: 1,
          icon: const Icon(Icons.schedule, size: 14),
          label: Text('${presets.normal.toStringAsFixed(0)} sat/vB'),
        ),
        ButtonSegment(
          value: 2,
          icon: const Icon(Icons.bolt, size: 14),
          label: Text('${presets.priority.toStringAsFixed(0)} sat/vB'),
        ),
      ],
      selected: selected,
      emptySelectionAllowed: true,
      onSelectionChanged: (Set<int> s) {
        if (s.isNotEmpty) _applyPreset(s.first);
      },
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

  /// Validates all form inputs. Returns `rate` on success, null if
  /// validation failed (errors are shown / fields opened inline).
  ({double rate})? _validateTxParams() {
    if (_selectedUtxos.isEmpty) {
      showErrorToast(context, context.l10n.createTxSelectCoinsFirst);
      return null;
    }
    // All recipients must have a non-empty address.
    for (int i = 0; i < _recipients.length; i++) {
      if (_recipients[i].addressCtrl.text.trim().isEmpty) {
        setState(() => _recipients[i].editMode = true);
        return null;
      }
    }
    if (_feeEditMode != _FeeEditMode.none) {
      if (_feeEditMode == _FeeEditMode.total) _syncRateFromTotal();
      setState(() => _feeEditMode = _FeeEditMode.none);
      return null;
    }
    final minFeeRate = context.read<SettingsCubit>().state.minFeeRate;
    final rate = double.tryParse(_feeRateCtrl.text.trim());
    if (rate == null || rate < minFeeRate) {
      setState(() => _feeEditMode = _FeeEditMode.rate);
      return null;
    }
    // Two independent RBF checks (Bitcoin Core ReplacementChecks):
    final resolvedRbfInfos = _rbfInfos.values.whereType<APIRbfInfo>().toList();
    if (resolvedRbfInfos.isNotEmpty) {
      // 1. ImprovesFeerateDiagram: new_rate must strictly exceed orig_rate.
      final maxOrigRate = resolvedRbfInfos.fold<double>(
        0.0,
        (m, i) => max(m, i.minFeeRateSatPerVb),
      );
      if (rate <= maxOrigRate) {
        showErrorToast(context, context.l10n.rbfFeeTooLow(maxOrigRate));
        setState(() => _feeEditMode = _FeeEditMode.rate);
        return null;
      }
      // 2. BIP-125 Rule 4 (PaysForRBF): new_fee must exceed conflict cluster fee + new_vsize.
      final summary = _txSummary;
      if (summary != null) {
        final newVsize = (summary.totalWu / 4.0).ceil();
        final totalConflict = _totalConflictFee(resolvedRbfInfos);
        if (summary.feeSats <= totalConflict + newVsize) {
          showErrorToast(context, context.l10n.rbfAbsFeeTooLow(totalConflict + newVsize + 1));
          setState(() => _feeEditMode = _FeeEditMode.total);
          return null;
        }
      }
    }
    if (!_formKey.currentState!.validate()) return null;
    if (_selectedPath == null) return null;
    return (rate: rate);
  }

  List<APICoinControl> _buildSelectedUtxos() =>
      _selectedUtxos.map((u) => APICoinControl(txid: u.txid, vout: u.vout)).toList();

  List<APIRecipient> _buildApiRecipients() =>
      _recipients.asMap().entries.map((e) {
        final amountSat = e.key == _maxRecipientIndex
            ? BigInt.zero
            : BigInt.from(e.value.rawAmount);
        return APIRecipient(
          address: e.value.addressCtrl.text.trim(),
          amountSat: amountSat,
        );
      }).toList();

  Future<void> _submit() async {
    final params = _validateTxParams();
    if (params == null) return;
    final rate = params.rate;

    final l10n = context.l10n;

    setState(() => _creating = true);
    try {
      final cubit = context.read<WalletDetailCubit>();

      final psbt = await cubit.createPsbt(
        recipients: _buildApiRecipients(),
        maxRecipientIndex: _maxRecipientIndex,
        feeRateSatPerVb: rate,
        selectedUtxos: _buildSelectedUtxos(),
        policyPath: _selectedPath!.policyPath,
        spendPathId: _selectedPath!.id,
        threshold: _selectedPath!.threshold,
        mfps: _selectedPath!.mfps,
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

  // ─── Direct send ─────────────────────────────────────────────────────────

  /// True when the selected path is single-sig, the hot key is available locally,
  /// and there is only one recipient (multi-recipient requires PSBT flow).
  bool _isDirectSendAvailable() {
    final path = _selectedPath;
    if (path == null || path.threshold != 1 || path.mfps.length != 1) return false;
    final s = context.read<WalletDetailCubit>().state;
    if (s is! WalletDetailLoaded) return false;
    return s.hotKeys.any((k) => k.mfp == path.mfps.first);
  }

  /// Validates inputs and shows a confirmation sheet before signing + broadcasting.
  Future<void> _confirmDirectSend() async {
    final params = _validateTxParams();
    if (params == null) return;
    final summary = _txSummary;
    // Build display recipients (drain recipient shows calculated sendSats).
    final displayRecipients = _recipients.asMap().entries.map((e) {
      final amount = (e.key == _maxRecipientIndex && summary != null && !summary.insufficientFunds)
          ? summary.sendSats
          : e.value.rawAmount;
      return (address: e.value.addressCtrl.text.trim(), amountSat: amount);
    }).toList();

    await showSheet<void>(context, (sheetCtx) {
      return _DirectSendConfirmSheet(
        recipients: displayRecipients,
        feeSat: summary?.feeSats,
        changeSat: (summary != null && summary.hasChange) ? summary.changeSats : null,
        feeRateSatPerVb: params.rate,
        onConfirm: () {
          Navigator.pop(sheetCtx);
          _executeDirectSend(params.rate);
        },
      );
    });
  }

  Future<void> _executeDirectSend(double rate) async {
    setState(() => _creating = true);
    try {
      final cubit = context.read<WalletDetailCubit>();
      final settings = context.read<SettingsCubit>().state;
      final electrumUrl = settings.electrumUrlForNetwork(_currentNetwork);
      final label = _labelCtrl.text.trim();
      final txid = await cubit.directSend(
        recipients: _buildApiRecipients(),
        maxRecipientIndex: _maxRecipientIndex,
        feeRateSatPerVb: rate,
        selectedUtxos: _buildSelectedUtxos(),
        policyPath: _selectedPath!.policyPath,
        spendPathId: _selectedPath!.id,
        threshold: _selectedPath!.threshold,
        mfps: _selectedPath!.mfps,
        label: label.isEmpty ? null : label,
        electrumUrl: electrumUrl,
      );
      if (mounted) {
        showSuccessToast(context, context.l10n.directSendSuccess(txid));
        Navigator.of(context).pop();
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
    final directSend = _isDirectSendAvailable();

    // Fee field inline validation.
    final minFeeRate = context.read<SettingsCubit>().state.minFeeRate;
    final resolvedRbfInfos = _rbfInfos.values.whereType<APIRbfInfo>().toList();
    final maxOrigRate =
        resolvedRbfInfos.fold<double>(0.0, (m, i) => max(m, i.minFeeRateSatPerVb));
    // Effective minimum rate: stricter of relay minimum and RBF diagram constraint.
    final effectiveMinRate =
        resolvedRbfInfos.isNotEmpty ? max(minFeeRate.toDouble(), maxOrigRate) : minFeeRate.toDouble();
    // Live display value for fee rate field — when editing total fee, show the
    // live back-computed rate from summary so the display and error check agree.
    final feeRateDisplay = _feeEditMode == _FeeEditMode.total
        ? (summary != null
            ? summary.feeRate.toStringAsFixed(2)
            : _feeRateCtrl.text)
        : _feeRateCtrl.text;
    final currentRate = double.tryParse(feeRateDisplay) ?? 0.0;

    // RBF absolute fee minimum (Rule 4) — depends on new tx size.
    // Uses total conflict cluster fee: orig + unconfirmed descendants.
    int rbfMinFeeSats = 0;
    if (resolvedRbfInfos.isNotEmpty && summary != null) {
      final newVsize = (summary.totalWu / 4.0).ceil();
      final totalConflict = _totalConflictFee(resolvedRbfInfos);
      rbfMinFeeSats = totalConflict + newVsize;
    }

    final String? rateErrorText =
        currentRate > 0 && currentRate <= effectiveMinRate
            ? 'min: ${effectiveMinRate.toStringAsFixed(2)} sat/vB'
            : null;

    final String? feeErrorText =
        rbfMinFeeSats > 0 && summary != null && !summary.insufficientFunds && summary.feeSats <= rbfMinFeeSats
            ? 'min: $rbfMinFeeSats sats'
            : null;
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

              // ── CPFP info banner (shown when unconfirmed UTXOs selected) ──
              if (_selectedUtxos.any((u) => !u.isConfirmed)) ...[
                _buildCpfpBanner(context),
                const SizedBox(height: 16),
              ],

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

              // ── Recipients ──
              ..._buildRecipientList(context, theme, summary),
              const SizedBox(height: 16),

              _buildFeePresets(),
              if (_feePresets != null) const SizedBox(height: 8),

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

              Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  FilledButton.icon(
                    onPressed: (_creating || _selectedPath == null)
                        ? null
                        : (directSend ? _confirmDirectSend : _submit),
                    icon: _creating
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : Icon(directSend
                            ? Icons.send_outlined
                            : Icons.receipt_long_outlined),
                    label: Text(
                        directSend ? l10n.directSendButton : l10n.createTxButton),
                  ),
                  if (directSend) ...[
                    const SizedBox(height: 8),
                    TextButton.icon(
                      onPressed: (_creating || _selectedPath == null) ? null : _submit,
                      icon: const Icon(Icons.receipt_long_outlined),
                      label: Text(l10n.createTxButton),
                    ),
                  ],
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _DirectSendConfirmSheet extends StatelessWidget {
  const _DirectSendConfirmSheet({
    required this.recipients,
    this.feeSat,
    this.changeSat,
    required this.feeRateSatPerVb,
    required this.onConfirm,
  });

  final List<({String address, int amountSat})> recipients;
  final int? feeSat;
  final int? changeSat;
  final double feeRateSatPerVb;
  final VoidCallback onConfirm;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    final feeText = feeSat != null
        ? '${BitcoinFormatter.formatNum(feeSat!)} sats'
            ' (${BitcoinFormatter.formatDouble(feeRateSatPerVb, 1)} sat/vB)'
        : '${BitcoinFormatter.formatDouble(feeRateSatPerVb, 1)} sat/vB';
    final totalAmount = recipients.fold(0, (s, r) => s + r.amountSat);

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Center(
            child: Container(
              width: 32,
              height: 4,
              margin: const EdgeInsets.only(bottom: 16),
              decoration: BoxDecoration(
                color: colorScheme.onSurface.withAlpha(60),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          Text(l10n.directSendConfirmTitle,
              style: theme.textTheme.titleMedium
                  ?.copyWith(fontWeight: FontWeight.bold)),
          const SizedBox(height: 16),
          // One row per recipient (always, for visual consistency).
          for (int i = 0; i < recipients.length; i++) ...[
            _ConfirmRow(
              label: '${l10n.psbtRecipient} ${i + 1}',
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  ColoredGroupText(text: recipients[i].address),
                  const SizedBox(height: 2),
                  Text(
                    '${BitcoinFormatter.formatNum(recipients[i].amountSat)} sats',
                    style: theme.textTheme.bodySmall,
                  ),
                ],
              ),
            ),
            const SizedBox(height: 8),
          ],
          // Total amount row when >1 recipient.
          if (recipients.length > 1) ...[
            _ConfirmRow(
              label: l10n.createTxTotalOut,
              child: Text(
                '${BitcoinFormatter.formatNum(totalAmount)} sats',
                style: theme.textTheme.bodySmall,
              ),
            ),
            const SizedBox(height: 8),
          ],
          _ConfirmRow(
            label: l10n.psbtFee,
            child: Text(feeText, style: theme.textTheme.bodySmall),
          ),
          if (changeSat != null) ...[
            const SizedBox(height: 8),
            _ConfirmRow(
              label: l10n.createTxEstChange,
              child: Text(
                '${BitcoinFormatter.formatNum(changeSat!)} sats',
                style: theme.textTheme.bodySmall,
              ),
            ),
          ],
          const SizedBox(height: 20),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: Text(l10n.cancel),
              ),
              const SizedBox(width: 8),
              FilledButton.icon(
                onPressed: onConfirm,
                icon: const Icon(Icons.send_outlined),
                label: Text(l10n.directSendConfirmAction),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _ConfirmRow extends StatelessWidget {
  const _ConfirmRow({required this.label, required this.child});
  final String label;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 64,
          child: Text(label,
              style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurface.withAlpha(150))),
        ),
        Expanded(child: child),
      ],
    );
  }
}
