import 'dart:async';
import 'dart:math' show max;

import 'package:flutter/gestures.dart' show DragStartBehavior;
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
import 'package:deadbolt/screens/qr_scanner_screen.dart';
import 'package:deadbolt/widgets/colored_group_text.dart';
import 'package:deadbolt/widgets/dialog_helpers.dart' show showSheet;
import 'package:deadbolt/widgets/fee_histogram_widget.dart';
import 'package:deadbolt/widgets/fee_presets_widget.dart';
import 'package:deadbolt/services/mempool_blocks_service.dart';
import 'package:deadbolt/src/rust/api/tor.dart' show isTorRunning, torSocksAddr;
import 'package:deadbolt/screens/coin_selector_screen.dart';
import 'package:deadbolt/screens/psbt_detail_screen.dart';
import 'package:deadbolt/screens/create_tx/create_tx_models.dart';
import 'package:deadbolt/screens/create_tx/confirm_sheet.dart';
import 'package:deadbolt/screens/create_tx/rbf_card.dart';
import 'package:deadbolt/screens/create_tx/cpfp_banner.dart';
import 'package:deadbolt/screens/create_tx/selected_path_card.dart';

// Outputs below this threshold are not created (absorbed into fee).
const _dustLimit = 546;

final _bitcoinUriPrefixRe = RegExp(r'^bitcoin:', caseSensitive: false);

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
  final List<RecipientEntry> _recipients = [RecipientEntry()];
  /// Index of the recipient that gets the wallet remainder (send-max semantics).
  /// null = every recipient has an explicit amount.
  int? _maxRecipientIndex;

  APISpendPath? _selectedPath;
  FeeEditMode _feeEditMode = FeeEditMode.none;

  // Selected UTXOs (chosen via CoinSelectorScreen)
  List<APIUtxo> _selectedUtxos = [];

  // RBF info: mempoolSpendingTxid -> APIRbfInfo (null while loading)
  final Map<String, APIRbfInfo?> _rbfInfos = {};

  // CPFP info: loaded once when unconfirmed UTXOs are selected (null while loading/unavailable).
  APICpfpInfo? _cpfpInfo;
  bool _cpfpInfoLoading = false;

  FeePresets? _feePresets;
  int? _selectedPresetIndex; // 0=economy, 1=normal, 2=priority; null=none

  MempoolBlocksSnapshot? _blockSnapshot;
  Timer? _blockSnapshotTimer;
  bool _blockSnapshotPending = false;

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
    _refreshBlockSnapshot();
    _blockSnapshotTimer = Timer.periodic(
      const Duration(seconds: 5),
      (_) => _refreshBlockSnapshot(),
    );
  }

  void _refreshBlockSnapshot() {
    if (_blockSnapshotPending) return;
    _blockSnapshotPending = true;
    final settings = context.read<SettingsCubit>().state;
    final explorerBase = settings.explorerBaseForNetwork(_currentNetwork);
    final socksAddr = isTorRunning() ? torSocksAddr() : null;
    MempoolBlocksService.getSnapshot(explorerBase, torSocksAddr: socksAddr)
        .then((s) {
      _blockSnapshotPending = false;
      if (!mounted) return;
      setState(() {
        _blockSnapshot = s;
        if (s != null) {
          _feePresets = s.presetsFromSnapshot(
            context.read<SettingsCubit>().state.minFeeRate,
          );
        }
      });
    });
  }

  @override
  void dispose() {
    _blockSnapshotTimer?.cancel();
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
    setState(() => _feeEditMode = FeeEditMode.none);
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
      _feeRateCtrl.text = _rateForExactSats(fee, summary.totalWu);
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
    _feeRateCtrl.text = _rateForExactSats(fee, wuNoChange);
  }

  /// Returns a sat/vB rate string floored at 8 decimal places such that
  /// ceil(rate × totalWu / 4) == feeSats exactly, avoiding the +1 sat drift
  /// that standard rounding causes when the 3rd decimal rounds up.
  static String _rateForExactSats(int feeSats, int totalWu) {
    final vbytes = totalWu / 4.0;
    final floored = (feeSats / vbytes * 1e8).floor() / 1e8;
    return floored.toStringAsFixed(8);
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
      } catch (e) {
        debugPrint('[wu resolve error] $e');
        if (mounted) setState(() { entry.wu = null; entry.resolvingWu = false; });
      }
    });
  }

  void _addRecipient() {
    setState(() {
      _recipients.add(RecipientEntry());
    });
  }

  void _removeRecipient(int index) {
    setState(() {
      _recipients[index].dispose();
      if (_recipients.length == 1) {
        // Last entry: reset instead of remove.
        _recipients[0] = RecipientEntry();
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

  TxSummary? get _txSummary {
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
    if (_feeEditMode == FeeEditMode.total) {
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
      return TxSummary(
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
      return TxSummary(
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
        return TxSummary(
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
      return TxSummary(
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
      showErrorToast(l10n.createTxNoUnusedAddress);
      return;
    }
    final entry = _recipients[recipientIndex];
    entry.addressCtrl.text = address;
    setState(() => entry.editMode = false);
    _onRecipientChanged(address, recipientIndex);
  }

  Future<void> _scanAddressForRecipient(int index) async {
    final scanned = await QrScannerScreen.push(context);
    if (scanned == null || !mounted) return;
    final address = scanned.trim().replaceFirst(_bitcoinUriPrefixRe, '');
    final entry = _recipients[index];
    entry.addressCtrl.text = address;
    entry.editMode = false;
    _onRecipientChanged(address, index);
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

  // ─── Recipients ──────────────────────────────────────────────────────────

  List<Widget> _buildRecipientList(
      BuildContext context, ThemeData theme, TxSummary? summary) {
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
                  SizedBox(
                    width: 32,
                    height: 32,
                    child: IconButton(
                      padding: EdgeInsets.zero,
                      iconSize: 18,
                      icon: const Icon(Icons.qr_code_scanner_outlined),
                      color: colorScheme.onSurface.withAlpha(AppAlpha.secondary),
                      tooltip: l10n.scanQrCode,
                      onPressed: () => _scanAddressForRecipient(i),
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
                              ThousandsSeparatorFormatter(),
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
      Align(
        alignment: Alignment.center,
        child: TextButton.icon(
          onPressed: _addRecipient,
          icon: const Icon(Icons.add, size: 16),
          label: Text(l10n.createTxAddRecipient),
        ),
      ),
    );

    // Fee summary below the list.
    // Always add exactly 2 widget slots so that the fee Row further down the
    // ListView stays at a stable position regardless of whether a summary is
    // available. Without this, emptying the fee-rate field makes summary go
    // null, the slots disappear, the Row shifts index, Flutter creates a new
    // element for it, and the TextFormField loses focus.
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
    } else {
      widgets.add(const SizedBox.shrink());
      widgets.add(const SizedBox.shrink());
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
      _feeEditMode = FeeEditMode.none;
    });
    final summary = _txSummary;
    if (summary != null) _totalFeeCtrl.text = summary.feeSats.toString();
  }

  // ─── Fee inline-edit field ────────────────────────────────────────────────

  Widget _buildFeeField({
    required BuildContext context,
    required String labelText,
    required String suffixText,
    required TextEditingController controller,
    required FeeEditMode thisMode,
    required String displayValue,
    required bool isDecimal,
    required VoidCallback onEditTap,
    required VoidCallback onDone,
    String? errorText,
    String? semanticsId,
  }) {
    final Widget field;
    if (_feeEditMode == thisMode) {
      field = TextFormField(
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
    } else {
      field = InkWell(
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
    if (semanticsId == null) return field;
    return Semantics(label: semanticsId, child: field);
  }

  // ─── Submit ───────────────────────────────────────────────────────────────

  /// Validates all form inputs. Returns `rate` and `feeSats` on success, null if
  /// validation failed (errors are shown / fields opened inline).
  ({double rate, int feeSats})? _validateTxParams() {
    if (_selectedUtxos.isEmpty) {
      showErrorToast(context.l10n.createTxSelectCoinsFirst);
      return null;
    }
    // All recipients must have a non-empty address.
    for (int i = 0; i < _recipients.length; i++) {
      if (_recipients[i].addressCtrl.text.trim().isEmpty) {
        setState(() => _recipients[i].editMode = true);
        return null;
      }
    }
    if (_feeEditMode != FeeEditMode.none) {
      if (_feeEditMode == FeeEditMode.total) _syncRateFromTotal();
      setState(() => _feeEditMode = FeeEditMode.none);
      return null;
    }
    final minFeeRate = context.read<SettingsCubit>().state.minFeeRate;
    final rate = double.tryParse(_feeRateCtrl.text.trim());
    if (rate == null || rate < minFeeRate) {
      setState(() => _feeEditMode = FeeEditMode.rate);
      return null;
    }
    // Two independent RBF checks (Bitcoin Core ReplacementChecks):
    final resolvedRbfInfos = _rbfInfos.values.whereType<APIRbfInfo>().toList();
    final summary = _txSummary;
    if (resolvedRbfInfos.isNotEmpty) {
      // 1. ImprovesFeerateDiagram: new_rate must strictly exceed orig_rate.
      final maxOrigRate = resolvedRbfInfos.fold<double>(
        0.0,
        (m, i) => max(m, i.minFeeRateSatPerVb),
      );
      if (rate <= maxOrigRate) {
        showErrorToast(context.l10n.rbfFeeTooLow(maxOrigRate));
        setState(() => _feeEditMode = FeeEditMode.rate);
        return null;
      }
      // 2. BIP-125 Rule 4 (PaysForRBF): new_fee must exceed conflict cluster fee + new_vsize.
      if (summary != null) {
        final newVsize = (summary.totalWu / 4.0).ceil();
        final totalConflict = _totalConflictFee(resolvedRbfInfos);
        if (summary.feeSats <= totalConflict + newVsize) {
          showErrorToast(context.l10n.rbfAbsFeeTooLow(totalConflict + newVsize + 1));
          setState(() => _feeEditMode = FeeEditMode.total);
          return null;
        }
      }
    }
    if (!_formKey.currentState!.validate()) return null;
    if (_selectedPath == null) return null;
    if (summary == null || summary.insufficientFunds) return null;
    return (rate: rate, feeSats: summary.feeSats);
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

    setState(() => _creating = true);
    try {
      final cubit = context.read<WalletDetailCubit>();

      final psbt = await cubit.createPsbt(
        recipients: _buildApiRecipients(),
        maxRecipientIndex: _maxRecipientIndex,
        feeAbsoluteSat: params.feeSats,
        selectedUtxos: _buildSelectedUtxos(),
        policyPath: _selectedPath!.policyPath,
        spendPathId: _selectedPath!.id,
        threshold: _selectedPath!.threshold,
        mfps: _selectedPath!.mfps,
        label: _labelCtrl.text.trim(),
      );

      if (!mounted) return;
      if (psbt != null) {
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
      if (mounted) showErrorToastException(e);
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
      return DirectSendConfirmSheet(
        recipients: displayRecipients,
        feeSat: summary?.feeSats,
        changeSat: (summary != null && summary.hasChange) ? summary.changeSats : null,
        feeRateSatPerVb: params.rate,
        onConfirm: () {
          Navigator.pop(sheetCtx);
          _executeDirectSend(params.feeSats);
        },
      );
    });
  }

  Future<void> _executeDirectSend(int feeSats) async {
    setState(() => _creating = true);
    try {
      final cubit = context.read<WalletDetailCubit>();
      final settings = context.read<SettingsCubit>().state;
      final electrumUrl = settings.electrumUrlForNetwork(_currentNetwork);
      final label = _labelCtrl.text.trim();
      final txid = await cubit.directSend(
        recipients: _buildApiRecipients(),
        maxRecipientIndex: _maxRecipientIndex,
        feeAbsoluteSat: feeSats,
        selectedUtxos: _buildSelectedUtxos(),
        policyPath: _selectedPath!.policyPath,
        spendPathId: _selectedPath!.id,
        threshold: _selectedPath!.threshold,
        mfps: _selectedPath!.mfps,
        label: label.isEmpty ? null : label,
        electrumUrl: electrumUrl,
      );
      if (mounted) {
        showSuccessToast(context.l10n.directSendSuccess(txid));
        Navigator.of(context).pop();
      }
    } catch (e) {
      if (mounted) showErrorToastException(e);
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
    // RBF requires rate > maxOrigRate; +0.01 is the smallest valid display step.
    final effectiveMinRate = resolvedRbfInfos.isNotEmpty
        ? max(minFeeRate.toDouble(), maxOrigRate) + 0.01
        : minFeeRate.toDouble();
    // Live display value for fee rate field — when editing total fee, show the
    // live back-computed rate from summary so the display and error check agree.
    // When the controller holds a high-precision internal value (stored by
    // _rateForExactSats), round to 2 dp for display so the user doesn't see
    // "0.91810345" instead of "0.92". Parse once to avoid a double round-trip.
    final double? parsedCtrlRate;
    final String feeRateDisplay;
    if (_feeEditMode == FeeEditMode.total) {
      feeRateDisplay = summary != null
          ? summary.feeRate.toStringAsFixed(2)
          : _feeRateCtrl.text;
      parsedCtrlRate = double.tryParse(feeRateDisplay);
    } else {
      parsedCtrlRate = double.tryParse(_feeRateCtrl.text);
      feeRateDisplay = parsedCtrlRate?.toStringAsFixed(2) ?? _feeRateCtrl.text;
    }
    final currentRate = parsedCtrlRate ?? 0.0;

    // BIP-125 Rule 4: new_fee > conflict_cluster + new_vsize; +1 is the smallest valid integer.
    int rbfMinFeeSats = 0;
    if (resolvedRbfInfos.isNotEmpty && summary != null) {
      final newVsize = (summary.totalWu / 4.0).ceil();
      final totalConflict = _totalConflictFee(resolvedRbfInfos);
      rbfMinFeeSats = totalConflict + newVsize + 1;
    }

    final String? rateErrorText =
        currentRate > 0 && currentRate < effectiveMinRate
            ? 'min: ${effectiveMinRate.toStringAsFixed(2)} sat/vB'
            : null;

    final String? feeErrorText =
        rbfMinFeeSats > 0 && summary != null && !summary.insufficientFunds && summary.feeSats < rbfMinFeeSats
            ? 'min: $rbfMinFeeSats sats'
            : null;
    // Total fee display: live from summary in all modes except when the user
    // is actively editing the total fee field.
    final totalFeeDisplay = _feeEditMode == FeeEditMode.total
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
            dragStartBehavior: DragStartBehavior.down,
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
                                    color: theme.colorScheme.error,
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
                  ? RbfCard(
                      rbfInfos: _rbfInfos,
                      feeRateText: _feeRateCtrl.text,
                      txSummary: _txSummary,
                    )
                  : const SizedBox.shrink(),
              SizedBox(height: _rbfInfos.isNotEmpty ? 16 : 0),

              // ── CPFP info banner (shown when unconfirmed UTXOs selected) ──
              if (_selectedUtxos.any((u) => !u.isConfirmed)) ...[
                CpfpBanner(
                  cpfpInfo: _cpfpInfo,
                  cpfpInfoLoading: _cpfpInfoLoading,
                  txSummary: _txSummary,
                ),
                const SizedBox(height: 16),
              ],

              // ── Label ──
              TextField(
                controller: _labelCtrl,
                decoration: InputDecoration(
                  labelText: l10n.txLabelTitle,
                  hintText: l10n.addressLabelHint,
                  isDense: true,
                  border: const OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 16),

              // ── Recipients ──
              ..._buildRecipientList(context, theme, summary),
              const SizedBox(height: 16),

              FeeHistogramWidget(
                snapshot: _blockSnapshot,
                onFeeSelected: (rate) {
                  setState(() {
                    _feeRateCtrl.text = BitcoinFormatter.formatFeeRate(rate);
                    _feeEditMode = FeeEditMode.none;
                    _selectedPresetIndex = null;
                  });
                  _confirmFeeRate();
                },
              ),
              if (_blockSnapshot != null) const SizedBox(height: 4),

              buildFeePresetsSegments(_feePresets, _selectedPresetIndex, _applyPreset),
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
                      thisMode: FeeEditMode.rate,
                      displayValue: feeRateDisplay,
                      isDecimal: true,
                      errorText: rateErrorText,
                      semanticsId: 'fee_rate_display',
                      onEditTap: () {
                        final rate = double.tryParse(feeRateDisplay) ?? 0.0;
                        _feeRateCtrl.text = rate < effectiveMinRate
                            ? effectiveMinRate.toStringAsFixed(2)
                            : feeRateDisplay;
                        setState(() => _feeEditMode = FeeEditMode.rate);
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
                      thisMode: FeeEditMode.total,
                      displayValue: totalFeeDisplay,
                      isDecimal: false,
                      errorText: feeErrorText,
                      semanticsId: 'total_fee_display',
                      onEditTap: () {
                        final feeSats = summary?.feeSats ?? 0;
                        _totalFeeCtrl.text = rbfMinFeeSats > 0 && feeSats < rbfMinFeeSats
                            ? rbfMinFeeSats.toString()
                            : (feeSats > 0 ? feeSats.toString() : '');
                        setState(() => _feeEditMode = FeeEditMode.total);
                        WidgetsBinding.instance.addPostFrameCallback((_) {
                          if (mounted) _totalFocusNode.requestFocus();
                        });
                      },
                      onDone: () {
                        _syncRateFromTotal();
                        setState(() => _feeEditMode = FeeEditMode.none);
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
                SelectedPathCard(
                  path: _selectedPath!,
                  tipHeight: widget.tipHeight,
                  utxoMaxConfHeight: utxoMaxConfHeight,
                  keyLabels: widget.keyLabels,
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
                        directSend ? l10n.walletSendButton : l10n.createTxButton),
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


