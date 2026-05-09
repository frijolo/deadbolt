import 'dart:async';
import 'package:deadbolt/config/constants.dart' show kMonospaceFontFamily;

import 'package:flutter/gestures.dart' show DragStartBehavior;
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:deadbolt/cubit/settings_cubit.dart';
import 'package:deadbolt/cubit/wallet_detail_cubit.dart';
import 'package:deadbolt/l10n/l10n.dart';
import 'package:deadbolt/screens/coin_selector_screen.dart';
import 'package:deadbolt/screens/create_tx/selected_path_card.dart';
import 'package:deadbolt/services/mempool_blocks_service.dart';
import 'package:deadbolt/src/rust/api/model.dart' show APISpendPath, APIUtxo, APIRelativeTimelockType;
import 'package:deadbolt/theme/app_theme.dart' show AppAlpha;
import 'package:deadbolt/models/timelock_types.dart' show AbsoluteTimelockType;
import 'package:deadbolt/src/rust/api/tor.dart' show isTorRunning, torSocksAddr;
import 'package:deadbolt/src/rust/api/wallet/descriptor_backup.dart' as rust_backup;
import 'package:deadbolt/utils/bitcoin_formatter.dart' show BitcoinFormatter;
import 'package:deadbolt/utils/spend_path_unlock.dart';
import 'package:deadbolt/utils/toast_helper.dart';
import 'package:deadbolt/utils/wallet_complexity.dart';
import 'package:deadbolt/widgets/copy_icon_button.dart';
import 'package:deadbolt/widgets/fee_histogram_widget.dart';
import 'package:deadbolt/widgets/fee_presets_widget.dart';
import 'package:deadbolt/widgets/hw_wallet_sheet.dart' show showHwSignSheet;
import 'package:deadbolt/widgets/loading_indicator.dart';
import 'package:deadbolt/widgets/text_export_sheet.dart' show showPsbtExportSheet;
import 'package:deadbolt/widgets/text_import_sheet.dart' show showPsbtImportSheet;



enum _Phase {
  loading,
  loadFailed,
  backupExists,
  utxoSelection,
  buildingPsbt,
  awaitingSignature,
  signingHotKey,
  confirmBroadcast,
  finalizing,
  done,
}

class OnchainBackupScreen extends StatefulWidget {
  final WalletDetailLoaded state;

  const OnchainBackupScreen({super.key, required this.state});

  static Future<void> push(
    BuildContext context, {
    required WalletDetailLoaded state,
  }) {
    return Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => BlocProvider.value(
          value: context.read<WalletDetailCubit>(),
          child: OnchainBackupScreen(state: state),
        ),
      ),
    );
  }

  @override
  State<OnchainBackupScreen> createState() => _OnchainBackupScreenState();
}

class _OnchainBackupScreenState extends State<OnchainBackupScreen> {
  _Phase _phase = _Phase.loading;
  String _loadingLabel = '';
  rust_backup.BackupParams? _backupParams;
  List<APIUtxo> _selectedUtxos = [];
  APISpendPath? _selectedPath;
  rust_backup.OnchainBackupPsbt? _onchainPsbt;
  String? _signedPsbt;
  rust_backup.OnchainBackupResult? _result;
  rust_backup.WalletBackupStatus? _backupStatus;
  double _feeRate = 1.0;
  final _feeRateController = TextEditingController(text: '1.0');

  FeePresets? _feePresets;
  int? _selectedPresetIndex;
  MempoolBlocksSnapshot? _blockSnapshot;
  Timer? _blockSnapshotTimer;
  bool _blockSnapshotPending = false;
  bool _initialized = false;

  @override
  void initState() {
    super.initState();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_initialized) {
      _initialized = true;
      _initParams();
      _loadFeePresets();
    }
  }

  @override
  void dispose() {
    _blockSnapshotTimer?.cancel();
    _feeRateController.dispose();
    super.dispose();
  }

  bool get _canPop => switch (_phase) {
        _Phase.loading => false,
        _Phase.loadFailed || _Phase.utxoSelection || _Phase.backupExists || _Phase.done => true,
        _ => false,
      };

  void _handleBackButton() {
    switch (_phase) {
      case _Phase.awaitingSignature:
        setState(() {
          _phase = _Phase.utxoSelection;
          _onchainPsbt = null;
        });
      case _Phase.confirmBroadcast:
        setState(() {
          _phase = _Phase.awaitingSignature;
          _signedPsbt = null;
        });
      default:
        break;
    }
  }

  String get _electrumUrl =>
      context.read<SettingsCubit>().state.electrumUrlForNetwork(
            widget.state.walletInfo.network,
          );

  Map<String, String> get _keyLabels => widget.state.keyLabels;

  List<APISpendPath> get _spendPaths =>
      widget.state.descriptorAnalysis?.spendPaths ?? [];

  String _pathLabel(APISpendPath path) {
    final userLabel = widget.state.pathLabels[path.id];
    if (userLabel != null && userLabel.isNotEmpty) return userLabel;
    final labels = _keyLabels;
    final keys = path.mfps
        .map((m) => labels[m] ?? m.substring(0, 4).toUpperCase())
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
      if (utxoMaxConfHeight == null) return null;
      if (tipHeight == 0) {
        return (
          icon: Icons.sync_disabled_outlined,
          text: l10n.psbtTimelockSyncRequired,
          color: theme.colorScheme.onSurface.withAlpha(AppAlpha.inactive),
        );
      }
      final relBlocks = path.relTimelock.value;
      final remaining = (utxoMaxConfHeight + relBlocks) - tipHeight - 1;
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

  void _loadFeePresets() {
    _refreshBlockSnapshot();
    _blockSnapshotTimer = Timer.periodic(
      const Duration(seconds: 5),
      (_) => _refreshBlockSnapshot(),
    );
  }

  void _refreshBlockSnapshot() {
    if (_phase != _Phase.utxoSelection) return;
    if (_blockSnapshotPending) return;
    _blockSnapshotPending = true;
    final settings = context.read<SettingsCubit>().state;
    final explorerBase =
        settings.explorerBaseForNetwork(widget.state.walletInfo.network);
    final socksAddr = isTorRunning() ? torSocksAddr() : null;
    MempoolBlocksService.getSnapshot(explorerBase, torSocksAddr: socksAddr)
        .then((s) {
      if (!mounted || s == null || identical(s, _blockSnapshot)) return;
      setState(() {
        _blockSnapshot = s;
        _feePresets = s.presetsFromSnapshot(settings.minFeeRate);
      });
    }).whenComplete(() => _blockSnapshotPending = false);
  }

  void _applyPreset(int index) {
    if (_feePresets == null) return;
    final rates = [_feePresets!.economy, _feePresets!.normal, _feePresets!.priority];
    setState(() {
      _selectedPresetIndex = index;
      _feeRate = rates[index];
      _feeRateController.text = rates[index].toStringAsFixed(1);
    });
  }

  Future<void> _openCoinSelector() async {
    final result = await CoinSelectorScreen.push(
      context,
      allUtxos: widget.state.utxos,
      network: widget.state.walletInfo.network,
      tipHeight: widget.state.tipHeight,
      initiallySelected: _selectedUtxos,
      keyLabels: _keyLabels,
    );
    if (result != null) {
      setState(() => _selectedUtxos = result);
    }
  }

  int get _commitVbytes {
    final params = _backupParams;
    if (params == null) return 0;
    final base = params.commitVbytes.toInt();
    final path = _selectedPath;
    final n = _selectedUtxos.length;
    if (path == null || n == 0) return base;
    return ((base * 4) - 230 + path.wuIn * n + 3) ~/ 4;
  }

  int get _revealVbytes => _backupParams?.revealVbytes.toInt() ?? 0;
  int get _packageVbytes => _commitVbytes + _revealVbytes;
  int get _totalFee => (_packageVbytes * _feeRate).ceil();

  // Delegated to Rust: same weight model and threshold logic as prepare_backup_psbt.
  int get _minUtxoSats {
    final params = _backupParams;
    if (params == null) return 0;
    return rust_backup.computeMinUtxoSats(
      commitVbytes: params.commitVbytes,
      revealVbytes: params.revealVbytes,
      nAnchors: params.participantCount,
      feeRateSatPerVb: _feeRate,
      minFeeRate: context.read<SettingsCubit>().state.minFeeRate,
    ).toInt();
  }

  int get _totalSelectedSats =>
      _selectedUtxos.fold(0, (sum, u) => sum + u.valueSat.toInt());

  bool get _utxoSufficient => _totalSelectedSats >= _minUtxoSats;

  bool get _hasTimelockedUtxo {
    final path = _selectedPath;
    if (path == null || widget.state.tipHeight == 0) return false;
    final hasTimelock = path.relTimelock.value > 0 || path.absTimelock.value > 0;
    if (!hasTimelock) return false;
    return _selectedUtxos.any((u) {
      final status = spendPathStatus(path: path, utxo: u, tipHeight: widget.state.tipHeight);
      return status is! SpendPathUnlocked;
    });
  }

  Future<void> _initParams() async {
    final l10n = context.l10n;
    try {
      // Check for existing backup first — it only needs the wallet descriptor
      // (free, local). This avoids the expensive computeBackupParams (Argon2id
      // for every participant) when a backup already exists.
      setState(() => _loadingLabel = l10n.onChainBackupChecking);
      final status = await widget.state.walletHandle.checkBackupHealth(
        electrumUrl: _electrumUrl,
      );
      if (!mounted) return;
      if (status.found) {
        setState(() {
          _backupStatus = status;
          _phase = _Phase.backupExists;
        });
        return;
      }

      // No existing backup — compute the backup params (expensive).
      setState(() => _loadingLabel = l10n.onChainBackupScanning);
      final params = await widget.state.walletHandle.computeBackupParams();
      if (!mounted) return;
      final paths = widget.state.descriptorAnalysis?.spendPaths ?? [];
      setState(() {
        _backupParams = params;
        _selectedUtxos = [];
        _selectedPath = paths.isNotEmpty ? paths.first : null;
        _phase = _Phase.utxoSelection;
      });
    } catch (e) {
      if (!mounted) return;
      showErrorToastException(e);
      setState(() => _phase = _Phase.loadFailed);
    }
  }

  Future<void> _doBuildPsbt() async {
    if (_selectedUtxos.isEmpty) return;
    setState(() => _phase = _Phase.buildingPsbt);
    try {
      final psbt = await widget.state.walletHandle.prepareBackupPsbt(
        utxoTxids: _selectedUtxos.map((u) => u.txid).toList(),
        utxoVouts: _selectedUtxos.map((u) => u.vout).toList(),
        feeRateSatPerVb: _feeRate,
        minFeeRate: context.read<SettingsCubit>().state.minFeeRate,
        policyPath: _selectedPath?.policyPath ?? [],
        spendPathId: _selectedPath?.id ?? 0,
      );
      if (!mounted) return;
      setState(() {
        _onchainPsbt = psbt;
        _phase = _Phase.awaitingSignature;
      });
    } catch (e) {
      if (!mounted) return;
      showErrorToastException(e);
      setState(() => _phase = _Phase.utxoSelection);
    }
  }

  void _doSignWithHotKey(String mfp) {
    final psbtBase64 = _onchainPsbt?.commitPsbtBase64 ?? '';
    if (psbtBase64.isEmpty) return;
    setState(() => _phase = _Phase.signingHotKey);
    try {
      final signed = widget.state.walletHandle.signBackupPsbt(
        psbtBase64: psbtBase64,
        mfp: mfp,
      );
      setState(() {
        _signedPsbt = signed;
        _phase = _Phase.confirmBroadcast;
      });
    } catch (e) {
      showErrorToastException(e);
      setState(() => _phase = _Phase.awaitingSignature);
    }
  }

  Future<void> _doSignWithHw() async {
    final psbtBase64 = _onchainPsbt?.commitPsbtBase64 ?? '';
    if (psbtBase64.isEmpty) return;
    final signed = await showHwSignSheet(
      context,
      psbtBase64: psbtBase64,
      network: widget.state.walletInfo.network,
      descriptor: widget.state.walletInfo.descriptor,
    );
    if (signed == null || !mounted) return;
    setState(() {
      _signedPsbt = signed;
      _phase = _Phase.confirmBroadcast;
    });
  }

  Future<void> _doImportSigned() async {
    final psbtBase64 = await showPsbtImportSheet(context);
    if (psbtBase64 == null || psbtBase64.isEmpty || !mounted) return;
    setState(() {
      _signedPsbt = psbtBase64;
      _phase = _Phase.confirmBroadcast;
    });
  }

  Future<void> _doFinalize(String signedPsbtBase64) async {
    final psbt = _onchainPsbt;
    if (psbt == null) return;
    setState(() => _phase = _Phase.finalizing);
    try {
      final result = await widget.state.walletHandle.finalizeBackup(
        signedCommitPsbtBase64: signedPsbtBase64,
        vaultTapscriptHex: psbt.vaultTapscriptHex,
        revealFeeSat: psbt.revealFeeSat,
        electrumUrl: _electrumUrl,
      );
      if (!mounted) return;
      setState(() {
        _result = result;
        _phase = _Phase.done;
      });
      if (mounted) showSuccessToast(context.l10n.onChainBackupSuccess);
    } catch (e) {
      if (!mounted) return;
      showErrorToastException(e);
      setState(() => _phase = _Phase.confirmBroadcast);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;

    return PopScope(
      canPop: _canPop,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) return;
        _handleBackButton();
      },
      child: Scaffold(
        appBar: AppBar(title: Text(l10n.onChainBackupTitle)),
        body: switch (_phase) {
          _Phase.loading => LoadingIndicator(message: _loadingLabel.isEmpty ? l10n.onChainBackupScanning : _loadingLabel),
          _Phase.loadFailed => _buildLoadRetry(context),
          _Phase.backupExists => _buildBackupExists(context),
          _Phase.buildingPsbt => LoadingIndicator(message: l10n.onChainBackupBuildingPsbt),
          _Phase.signingHotKey => LoadingIndicator(message: l10n.onChainBackupPublishing),
          _Phase.finalizing => LoadingIndicator(message: l10n.onChainBackupFinalizing),
          _Phase.utxoSelection => _buildUtxoSelection(context),
          _Phase.awaitingSignature => _buildAwaitingSignature(context),
          _Phase.confirmBroadcast => _buildConfirmBroadcast(context),
          _Phase.done => _buildDone(context),
        },
      ),
    );
  }

  Widget _buildUtxoSelection(BuildContext context) {
    final l10n = context.l10n;
    final cs = Theme.of(context).colorScheme;
    final ts = Theme.of(context).textTheme;
    final spendPaths = _spendPaths;
    final keyLabels = _keyLabels;
    final singlesig = isDescriptorTriviallyRecoverable(widget.state);
    final noteText = singlesig
        ? l10n.backupSinglesigShortNote
        : l10n.onChainBackupSecurityNote;
    final noteIcon = singlesig ? Icons.privacy_tip_outlined : Icons.info_outline;
    final noteColor = singlesig ? cs.error : cs.onSurfaceVariant;
    final utxoMaxConfHeight = _selectedUtxos
        .where((u) => u.confirmationHeight != null)
        .map((u) => u.confirmationHeight!.toInt())
        .fold<int?>(null, (m, h) => m == null || h > m ? h : m);

    return SingleChildScrollView(
      dragStartBehavior: DragStartBehavior.down,
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: cs.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(noteIcon, size: 16, color: noteColor),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    noteText,
                    style: ts.bodySmall?.copyWith(color: noteColor),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          Card(
            margin: EdgeInsets.zero,
            clipBehavior: Clip.antiAlias,
            child: InkWell(
              onTap: widget.state.utxos.isEmpty ? null : _openCoinSelector,
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Row(
                  children: [
                    const Icon(Icons.toll, size: 20),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Builder(builder: (context) {
                        final String label;
                        final Color? labelColor;
                        if (_selectedUtxos.isNotEmpty) {
                          label = l10n.createTxSelectedCoins(_selectedUtxos.length, _totalSelectedSats);
                          labelColor = null;
                        } else if (widget.state.utxos.isEmpty) {
                          label = l10n.noUtxosAvailable;
                          labelColor = cs.error;
                        } else {
                          label = l10n.coinSelectorNoCoinsSelected;
                          labelColor = null;
                        }
                        return Text(label, style: ts.bodyMedium?.copyWith(color: labelColor));
                      }),
                    ),
                    const Icon(Icons.chevron_right, size: 18),
                  ],
                ),
              ),
            ),
          ),
          if (_backupParams != null && !_utxoSufficient)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text(
                l10n.onChainBackupUtxoInsufficient(_minUtxoSats),
                style: ts.bodySmall?.copyWith(color: cs.error),
              ),
            ),
          if (_hasTimelockedUtxo)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text(
                l10n.onChainBackupTimelockedUtxo,
                style: ts.bodySmall?.copyWith(color: cs.error),
              ),
            ),
          const SizedBox(height: 12),
          FeeHistogramWidget(
            snapshot: _blockSnapshot,
            onFeeSelected: (rate) {
              setState(() {
                _feeRate = rate;
                _feeRateController.text = BitcoinFormatter.formatFeeRate(rate);
                _selectedPresetIndex = null;
              });
            },
          ),
          if (_blockSnapshot != null) const SizedBox(height: 4),
          buildFeePresetsSegments(_feePresets, _selectedPresetIndex, _applyPreset),
          if (_feePresets != null) const SizedBox(height: 8),
          TextField(
            controller: _feeRateController,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: InputDecoration(
              labelText: l10n.onChainBackupFeeRate,
              suffixText: 'sat/vB',
              border: const OutlineInputBorder(),
            ),
            onChanged: (v) {
              final parsed = double.tryParse(v);
              if (parsed != null && parsed > 0 && parsed != _feeRate) {
                setState(() {
                  _feeRate = parsed;
                  _selectedPresetIndex = null;
                });
              }
            },
          ),
          const SizedBox(height: 12),
          const Divider(height: 1),
          const SizedBox(height: 8),
          _FeeRow(label: l10n.onChainBackupTxFees(_totalFee, _packageVbytes)),
          if (spendPaths.isNotEmpty) ...[
            const SizedBox(height: 16),
            DropdownButtonFormField<APISpendPath>(
              initialValue: _selectedPath,
              decoration: InputDecoration(labelText: l10n.createTxSpendPath),
              items: spendPaths
                  .map((p) {
                    final lockStatus = _timelockStatus(
                      context, p, widget.state.tipHeight, utxoMaxConfHeight,
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
                              style: ts.bodySmall?.copyWith(color: lockStatus.color),
                            ),
                          ],
                        ],
                      ),
                    );
                  })
                  .toList(),
              onChanged: (p) => setState(() => _selectedPath = p),
            ),
            if (_selectedPath != null) ...[
              const SizedBox(height: 8),
              SelectedPathCard(
                path: _selectedPath!,
                tipHeight: widget.state.tipHeight,
                utxoMaxConfHeight: utxoMaxConfHeight,
                keyLabels: keyLabels,
              ),
            ],
          ],
          const SizedBox(height: 16),
          FilledButton.icon(
            icon: const Icon(Icons.build_outlined),
            label: Text(l10n.onChainBackupConfirmBuild),
            onPressed:
                (_selectedUtxos.isNotEmpty && _utxoSufficient && !_hasTimelockedUtxo)
                    ? _doBuildPsbt
                    : null,
          ),
        ],
      ),
    );
  }

  Widget _buildAwaitingSignature(BuildContext context) {
    final l10n = context.l10n;
    final cs = Theme.of(context).colorScheme;
    final ts = Theme.of(context).textTheme;
    final psbt = _onchainPsbt!;

    final visibleHotKeys = _selectedPath != null
        ? widget.state.hotKeys
            .where((k) => _selectedPath!.mfps.contains(k.mfp))
            .toList()
        : widget.state.hotKeys;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _FeeRow(label: l10n.onChainBackupTxFees(
            (psbt.commitFeeSat + psbt.revealFeeSat).toInt(),
            psbt.packageVbytes.toInt(),
          )),
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: cs.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.info_outline, size: 16, color: cs.onSurfaceVariant),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    l10n.onChainBackupSignCommitHint,
                    style: ts.bodySmall?.copyWith(color: cs.onSurfaceVariant),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          if (visibleHotKeys.isNotEmpty) ...[
            for (final hk in visibleHotKeys)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: FilledButton.icon(
                  icon: const Icon(Icons.vpn_key_outlined),
                  label: Text('${l10n.onChainBackupSignWithHotKey} (${hk.mfp.substring(0, 8)})'),
                  onPressed: () => _doSignWithHotKey(hk.mfp),
                ),
              ),
            const Divider(height: 16),
          ],
          OutlinedButton.icon(
            icon: const Icon(Icons.memory),
            label: Text(l10n.onChainBackupSignWithHw),
            onPressed: _doSignWithHw,
          ),
          const SizedBox(height: 8),
          OutlinedButton.icon(
            icon: const Icon(Icons.qr_code),
            label: Text(l10n.onChainBackupExportPsbt),
            onPressed: () {
              final psbtBase64 = _onchainPsbt?.commitPsbtBase64 ?? '';
              if (psbtBase64.isNotEmpty) {
                showPsbtExportSheet(context, psbtBase64: psbtBase64);
              }
            },
          ),
          const SizedBox(height: 8),
          FilledButton.icon(
            icon: const Icon(Icons.file_upload_outlined),
            label: Text(l10n.onChainBackupImportSigned),
            onPressed: _doImportSigned,
          ),
        ],
      ),
    );
  }

  Widget _buildConfirmBroadcast(BuildContext context) {
    final l10n = context.l10n;
    final cs = Theme.of(context).colorScheme;
    final ts = Theme.of(context).textTheme;
    final psbt = _onchainPsbt!;

    final commitFee = psbt.commitFeeSat.toInt();
    final revealFee = psbt.revealFeeSat.toInt();
    final vaultSats = psbt.vaultSats.toInt();
    final changeSat = psbt.changeSat.toInt();
    final packageVb = psbt.packageVbytes.toInt();
    final totalFee = commitFee + revealFee;
    final nAnchors = psbt.anchorCount;
    final revealChange = psbt.revealChangeSat.toInt();

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(Icons.warning_amber_outlined, size: 20, color: cs.primary),
              const SizedBox(width: 8),
              Text(l10n.onChainBackupConfirmBroadcastTitle, style: ts.titleSmall),
            ],
          ),
          const SizedBox(height: 12),
          Card(
            color: cs.surfaceContainerHighest,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(l10n.onChainBackupCommitTx, style: ts.labelMedium?.copyWith(color: cs.primary)),
                  const SizedBox(height: 8),
                  _FeeRow(label: l10n.onChainBackupVault(BitcoinFormatter.formatNum(vaultSats))),
                  _FeeRow(label: l10n.onChainBackupAnchors(nAnchors, 330)),
                  if (changeSat >= 330)
                    _FeeRow(label: l10n.onChainBackupChange(BitcoinFormatter.formatNum(changeSat))),
                  _FeeRow(label: l10n.onChainBackupCommitFee(BitcoinFormatter.formatNum(commitFee))),
                ],
              ),
            ),
          ),
          const SizedBox(height: 8),
          Card(
            color: cs.surfaceContainerHighest,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(l10n.onChainBackupRevealTx, style: ts.labelMedium?.copyWith(color: cs.primary)),
                  const SizedBox(height: 8),
                  _FeeRow(label: l10n.onChainBackupRevealFee(BitcoinFormatter.formatNum(revealFee))),
                  if (revealChange >= 330)
                    _FeeRow(label: l10n.onChainBackupRevealChange(BitcoinFormatter.formatNum(revealChange))),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: cs.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(8),
            ),
            child: _FeeRow(label: l10n.onChainBackupTxFees(totalFee, packageVb)),
          ),
          const SizedBox(height: 16),
          FilledButton.icon(
            icon: const Icon(Icons.upload_outlined),
            label: Text(l10n.onChainBackupBroadcast),
            onPressed: () {
              final signed = _signedPsbt;
              if (signed != null) _doFinalize(signed);
            },
          ),
        ],
      ),
    );
  }

  Widget _buildDone(BuildContext context) {
    final l10n = context.l10n;
    final r = _result!;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              const Icon(Icons.check_circle, color: Colors.green, size: 24),
              const SizedBox(width: 8),
              Text(l10n.onChainBackupSuccess,
                  style: Theme.of(context).textTheme.titleSmall),
            ],
          ),
          const SizedBox(height: 16),
          _TxidRow(label: l10n.onChainBackupCommitTx, txid: r.commitTxid),
          const SizedBox(height: 8),
          _TxidRow(label: l10n.onChainBackupRevealTx, txid: r.revealTxid),
        ],
      ),
    );
  }

  Widget _buildBackupExists(BuildContext context) {
    final l10n = context.l10n;
    final cs = Theme.of(context).colorScheme;
    final ts = Theme.of(context).textTheme;
    final status = _backupStatus!;
    final allReachable = status.anchorsReachable == status.anchorsTotal;
    final healthy = status.descriptorVerified && status.revealTxid != null && allReachable;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(
                healthy ? Icons.check_circle : Icons.warning_amber_outlined,
                size: 22,
                color: healthy ? Colors.green : cs.error,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  l10n.onChainBackupExists,
                  style: ts.titleSmall,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: cs.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (status.commitTxid != null) ...[
                  _TxidRow(
                    label: l10n.onChainBackupCommitTx,
                    txid: status.commitTxid!,
                  ),
                  const SizedBox(height: 8),
                ],
                if (status.revealTxid != null)
                  _TxidRow(
                    label: l10n.onChainBackupRevealTx,
                    txid: status.revealTxid!,
                  )
                else
                  Row(
                    children: [
                      Icon(Icons.hourglass_empty,
                          size: 14, color: cs.onSurfaceVariant),
                      const SizedBox(width: 6),
                      Text(
                        l10n.onChainBackupRevealPending,
                        style: ts.bodySmall
                            ?.copyWith(color: cs.onSurfaceVariant),
                      ),
                    ],
                  ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Icon(
                      allReachable ? Icons.link : Icons.link_off,
                      size: 14,
                      color: allReachable ? Colors.green : cs.error,
                    ),
                    const SizedBox(width: 6),
                    Text(
                      l10n.onChainBackupAnchorsHealth(
                        status.anchorsReachable,
                        status.anchorsTotal,
                      ),
                      style: ts.bodySmall?.copyWith(
                        color: allReachable ? Colors.green : cs.error,
                      ),
                    ),
                  ],
                ),
                if (status.descriptorVerified) ...[
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      const Icon(Icons.verified_outlined,
                          size: 14, color: Colors.green),
                      const SizedBox(width: 6),
                      Text(
                        l10n.onChainBackupDescriptorVerified,
                        style: ts.bodySmall
                            ?.copyWith(color: Colors.green),
                      ),
                    ],
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(height: 16),
          OutlinedButton.icon(
            icon: const Icon(Icons.add_circle_outline),
            label: Text(l10n.onChainBackupCreateNew),
            onPressed: () => setState(() => _phase = _Phase.utxoSelection),
          ),
        ],
      ),
    );
  }

  Widget _buildLoadRetry(BuildContext context) {
    final l10n = context.l10n;
    return Center(
      child: FilledButton(
        onPressed: () {
          setState(() {
            _backupParams = null;
            _selectedUtxos = [];
            _onchainPsbt = null;
            _signedPsbt = null;
            _phase = _Phase.loading;
          });
          _initParams();
        },
        child: Text(l10n.scanAccountsRetry),
      ),
    );
  }
}

class _FeeRow extends StatelessWidget {
  final String label;
  const _FeeRow({required this.label});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Text(label, style: Theme.of(context).textTheme.bodySmall),
    );
  }
}

class _TxidRow extends StatelessWidget {
  final String label;
  final String txid;

  const _TxidRow({required this.label, required this.txid});

  @override
  Widget build(BuildContext context) {
    final ts = Theme.of(context).textTheme;
    final cs = Theme.of(context).colorScheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: ts.labelSmall?.copyWith(color: cs.onSurfaceVariant)),
        const SizedBox(height: 2),
        Row(
          children: [
            Expanded(
              child: Text(
                txid,
                style: ts.bodySmall?.copyWith(fontFamily: kMonospaceFontFamily),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            CopyIconButton(text: txid),
          ],
        ),
      ],
    );
  }
}
