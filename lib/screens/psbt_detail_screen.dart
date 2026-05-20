import 'package:flutter/gestures.dart' show DragStartBehavior;
import 'package:deadbolt/config/constants.dart' show kMonospaceFontFamily;
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import 'package:deadbolt/theme/app_theme.dart';
import 'package:deadbolt/config/app_settings_extensions.dart';
import 'package:deadbolt/cubit/settings_cubit.dart';
import 'package:deadbolt/cubit/wallet_detail_cubit.dart';
import 'package:deadbolt/l10n/l10n.dart';
import 'package:deadbolt/src/rust/api/model.dart';
import 'package:deadbolt/models/timelock_types.dart';
import 'package:deadbolt/utils/bitcoin_formatter.dart' show BitcoinFormatter;
import 'package:deadbolt/utils/op_return_encoding.dart';
import 'package:deadbolt/utils/date_format.dart';
import 'package:deadbolt/utils/psbt_timelock.dart';
import 'package:deadbolt/utils/toast_helper.dart';
import 'package:deadbolt/widgets/colored_group_text.dart';
import 'package:deadbolt/widgets/mfp_badge.dart';
import 'package:deadbolt/widgets/hw_wallet_sheet.dart' show showHwSignSheet;
import 'package:deadbolt/widgets/text_export_sheet.dart' show showPsbtExportSheet;
import 'package:deadbolt/widgets/text_import_sheet.dart' show showPsbtImportSheet;
import 'package:deadbolt/widgets/popup_menu_helpers.dart';
import 'package:deadbolt/widgets/dialog_helpers.dart';

class PsbtDetailScreen extends StatefulWidget {
  final APIPsbtInfo psbt;
  final APISpendPath? spendPath;

  const PsbtDetailScreen({
    super.key,
    required this.psbt,
    this.spendPath,
  });

  @override
  State<PsbtDetailScreen> createState() => _PsbtDetailScreenState();
}

class _PsbtDetailScreenState extends State<PsbtDetailScreen> {
  late APIPsbtInfo _psbt;
  bool _broadcasting = false;
  late final TextEditingController _labelController;

  @override
  void initState() {
    super.initState();
    _psbt = widget.psbt;
    final initialLabel = _psbt.label ?? '';
    _labelController = TextEditingController.fromValue(TextEditingValue(
      text: initialLabel,
      selection: TextSelection.collapsed(offset: initialLabel.length),
    ));
  }

  @override
  void dispose() {
    _labelController.dispose();
    super.dispose();
  }

  WalletDetailLoaded? get _loadedState {
    final s = context.read<WalletDetailCubit>().state;
    return s is WalletDetailLoaded ? s : null;
  }

  APIPsbtAnalysis? get _analysis => _loadedState?.psbtAnalyses[_psbt.id.toInt()];
  Map<String, String> get _keyLabels => _loadedState?.keyLabels ?? {};
  List<APIHotKeyInfo> get _hotKeys => _loadedState?.hotKeys ?? [];

  int get _signedCount =>
      _analysis?.signers.where((s) => s.hasSigned).length ?? 0;

  bool get _isReadyToBroadcast => _psbt.isReadyToBroadcast(_analysis);

  // ─── Label ────────────────────────────────────────────────────────────────

  void _saveLabel(BuildContext context, String value) {
    final trimmed = value.trim();
    if (trimmed == (_psbt.label ?? '')) return;
    final updated = context
        .read<WalletDetailCubit>()
        .setPsbtLabel(_psbt.id.toInt(), trimmed);
    if (updated != null) setState(() => _psbt = updated);
  }

  // ─── Timelock ─────────────────────────────────────────────────────────────

  List<Widget> _buildTimelockRows(BuildContext context, APISpendPath path, int tipHeight) {
    final l10n = context.l10n;
    final hasRel = path.relTimelock.value > 0;
    final hasAbs = path.absTimelock.value > 0;
    if (!hasRel && !hasAbs) return const [];

    final String timelockText;
    if (hasRel) {
      timelockText = BitcoinFormatter.formatRelativeTimelock(
        RelativeTimelockType.fromString(path.relTimelock.timelockType.name),
        path.relTimelock.value,
      );
    } else {
      timelockText = BitcoinFormatter.formatAbsoluteTimelock(
        AbsoluteTimelockType.fromString(path.absTimelock.timelockType.name),
        path.absTimelock.value,
      );
    }

    final theme = Theme.of(context);
    final rows = <Widget>[
      const SizedBox(height: 8),
      Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 90,
            child: Text(
              l10n.psbtTimelockLabel,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurface.withAlpha(AppAlpha.medium),
              ),
            ),
          ),
          const Icon(Icons.lock_clock, size: 14, color: Colors.orange),
          const SizedBox(width: 4),
          Expanded(
            child: Text(
              timelockText,
              style: theme.textTheme.bodySmall?.copyWith(color: Colors.orange),
            ),
          ),
        ],
      ),
    ];

    // Status row for relative timelocks using the stored UTXO max confirmation height.
    if (hasRel &&
        path.relTimelock.timelockType == APIRelativeTimelockType.blocks) {
      final confHeight = _psbt.utxoMaxConfHeight?.toInt();
      final relBlocks = path.relTimelock.value;

      final String statusText;
      final Color statusColor;
      final IconData statusIcon;

      if (confHeight == null) {
        statusText = l10n.psbtTimelockSyncRequired;
        statusColor = theme.colorScheme.onSurface.withAlpha(AppAlpha.inactive);
        statusIcon = Icons.sync_disabled_outlined;
      } else if (tipHeight == 0) {
        statusText = l10n.psbtTimelockSyncRequired;
        statusColor = theme.colorScheme.onSurface.withAlpha(AppAlpha.inactive);
        statusIcon = Icons.sync_disabled_outlined;
      } else {
        final unlockBlock = confHeight + relBlocks;
        // BIP68 validates the spending tx against the candidate block (tip+1),
        // so the path is unlocked as soon as tip+1 >= unlockBlock.
        final remaining = unlockBlock - tipHeight - 1;
        if (remaining > 0) {
          statusText = l10n.psbtTimelockBlocksRemaining(
            remaining,
            BitcoinFormatter.formatDuration(remaining * 10),
          );
          statusColor = Colors.orange;
          statusIcon = Icons.lock_outline;
        } else {
          statusText = l10n.spendPathUnlocked;
          statusColor = Colors.green;
          statusIcon = Icons.lock_open_outlined;
        }
      }

      rows.addAll([
        const SizedBox(height: 4),
        Row(
          children: [
            const SizedBox(width: 90),
            Icon(statusIcon, size: 14, color: statusColor),
            const SizedBox(width: 4),
            Expanded(
              child: Text(
                statusText,
                style: theme.textTheme.bodySmall?.copyWith(color: statusColor),
              ),
            ),
          ],
        ),
      ]);
    }

    // Status row for absolute timelocks.
    if (hasAbs) {
      final absType = AbsoluteTimelockType.fromString(path.absTimelock.timelockType.name);
      final absValue = path.absTimelock.value;

      final String statusText;
      final Color statusColor;
      final IconData statusIcon;

      if (absType == AbsoluteTimelockType.blocks) {
        if (tipHeight == 0) {
          statusText = l10n.psbtTimelockSyncRequired;
          statusColor = theme.colorScheme.onSurface.withAlpha(AppAlpha.inactive);
          statusIcon = Icons.sync_disabled_outlined;
        } else {
          final remaining = absValue - tipHeight;
          if (remaining > 0) {
            statusText = l10n.psbtTimelockBlocksRemaining(
              remaining,
              BitcoinFormatter.formatDuration(remaining * 10),
            );
            statusColor = Colors.orange;
            statusIcon = Icons.lock_outline;
          } else {
            statusText = l10n.spendPathUnlocked;
            statusColor = Colors.green;
            statusIcon = Icons.lock_open_outlined;
          }
        }
      } else {
        // Timestamp
        final nowSecs = DateTime.now().millisecondsSinceEpoch ~/ 1000;
        final remaining = absValue - nowSecs;
        if (remaining > 0) {
          statusText = l10n.psbtTimelockTimeRemaining(
            BitcoinFormatter.formatDuration(remaining ~/ 60),
          );
          statusColor = Colors.orange;
          statusIcon = Icons.lock_outline;
        } else {
          statusText = l10n.spendPathUnlocked;
          statusColor = Colors.green;
          statusIcon = Icons.lock_open_outlined;
        }
      }

      rows.addAll([
        const SizedBox(height: 4),
        Row(
          children: [
            const SizedBox(width: 90),
            Icon(statusIcon, size: 14, color: statusColor),
            const SizedBox(width: 4),
            Expanded(
              child: Text(
                statusText,
                style: theme.textTheme.bodySmall?.copyWith(color: statusColor),
              ),
            ),
          ],
        ),
      ]);
    }

    return rows;
  }

  // ─── Export ───────────────────────────────────────────────────────────────

  void _exportPsbt(BuildContext context) {
    showPsbtExportSheet(
      context,
      psbtBase64: _psbt.psbtBase64,
    );
  }

  // ─── Import signed ────────────────────────────────────────────────────────

  Future<void> _importSigned(BuildContext context) async {
    final psbtBase64 = await showPsbtImportSheet(context);
    if (psbtBase64 == null || psbtBase64.isEmpty) return;
    if (context.mounted) _mergePsbt(context, psbtBase64);
  }

  Future<void> _mergePsbt(BuildContext context, String signedBase64) async {
    try {
      final updated = await context
          .read<WalletDetailCubit>()
          .mergePsbt(_psbt.id.toInt(), signedBase64);
      if (updated != null) {
        setState(() => _psbt = updated);
      }
    } catch (e) {
      if (context.mounted) {
        showErrorToastException(e);
      }
    }
  }

  // ─── Broadcast ───────────────────────────────────────────────────────────

  Future<void> _signLocallyWithKey(BuildContext context, String mfp) async {
    final updated =
        await context.read<WalletDetailCubit>().signPsbtWithKey(_psbt.id.toInt(), mfp);
    if (!context.mounted) return;
    if (updated != null) {
      setState(() => _psbt = updated);
    }
  }

  Future<void> _broadcast(BuildContext context) async {
    final l10n = context.l10n;
    final cubit = context.read<WalletDetailCubit>();
    final settings = context.read<SettingsCubit>().state;
    final network = _loadedState?.walletInfo.network ?? settings.network;
    final electrumUrl = settings.electrumUrlForNetwork(network);

    setState(() => _broadcasting = true);
    try {
      final txid = await cubit.broadcastPsbt(_psbt.id.toInt(), electrumUrl);
      if (!context.mounted) return;
      if (txid != null) {
        showSuccessToast(l10n.psbtBroadcastSuccess(txid));
        Navigator.of(context).pop();
      }
    } catch (e) {
      if (context.mounted) {
        showErrorToastException(e);
      }
    } finally {
      if (mounted) setState(() => _broadcasting = false);
    }
  }

  Widget _buildAutoBroadcastSwitch(
      BuildContext context, AppLocalizations l10n, DateTime? eta) {
    if (!_isReadyToBroadcast || eta == null) return const SizedBox.shrink();

    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: SwitchListTile.adaptive(
        contentPadding: EdgeInsets.zero,
        dense: true,
        value: _psbt.autoBroadcast,
        onChanged: (value) {
          final updated = context
              .read<WalletDetailCubit>()
              .setPsbtAutoBroadcast(_psbt.id.toInt(), value);
          if (updated != null) setState(() => _psbt = updated);
        },
        title: Text(l10n.psbtAutoBroadcastSwitch),
        subtitle: Text(
          l10n.psbtAutoBroadcastHint,
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurface.withAlpha(AppAlpha.inactive),
          ),
        ),
      ),
    );
  }

  Widget _buildBroadcastButton(BuildContext context, AppLocalizations l10n,
      DateTime? eta, int tipHeight) {
    final locked = eta != null;
    return FilledButton.icon(
      onPressed: (_isReadyToBroadcast && !_broadcasting && !locked)
          ? () => _broadcast(context)
          : null,
      icon: _broadcasting
          ? const SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          : Icon(locked ? Icons.hourglass_bottom : Icons.send_outlined),
      label: Text(
        locked
            ? l10n.psbtLockedTooltip(
                formatShortSlashed(eta),
                _psbt.blocksLeft(tipHeight),
              )
            : l10n.psbtBroadcastButton,
      ),
    );
  }

  // ─── Delete ───────────────────────────────────────────────────────────────

  // ─── Hardware wallet signing ───────────────────────────────────────────────

  Future<void> _signWithHw(BuildContext context) async {
    final loaded = _loadedState;
    final network = loaded?.walletInfo.network ?? APINetwork.bitcoin;
    final descriptor = loaded?.walletInfo.descriptor;

    // Per-MFP change index for the chosen spend path. Lets the device pick the
    // correct leaf in multi-leaf taproot descriptors.
    final spendPath = widget.spendPath ??
        loaded?.descriptorAnalysis?.spendPaths
            .where((p) => p.id == _psbt.spendPathId.toInt())
            .firstOrNull;
    final keyChanges = spendPath?.keyChanges;

    final signedBase64 = await showHwSignSheet(
      context,
      psbtBase64: _psbt.psbtBase64,
      network: network,
      descriptor: descriptor,
      keyChanges: keyChanges,
    );

    if (signedBase64 == null || !context.mounted) return;
    _mergePsbt(context, signedBase64);
  }

  void _delete(BuildContext context) {
    final l10n = context.l10n;
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        titlePadding: kDialogTitlePadding,
        title: dialogCloseTitle(l10n.psbtDeleteTitle, onClose: () => Navigator.pop(ctx), tooltip: l10n.cancel),
        content: Text(l10n.psbtDeleteConfirm),
        actions: [
          FilledButton(
            onPressed: () {
              context.read<WalletDetailCubit>().deletePsbt(_psbt.id.toInt());
              Navigator.pop(ctx);
              Navigator.of(context).pop();
            },
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            child: Text(l10n.delete),
          ),
        ],
      ),
    );
  }

  // ─── Build ────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final theme = Theme.of(context);

    return BlocBuilder<WalletDetailCubit, WalletDetailState>(
      builder: (context, state) {
        final keyLabels = _keyLabels;
        final analysis = _analysis;
        final signed = _signedCount;
        final threshold = _psbt.threshold.toInt();
        final total = _psbt.mfps.length;
        final tipHeight = state is WalletDetailLoaded ? state.tipHeight : 0;
        final unlockEta = _psbt.unlockEta(tipHeight);

        // Resolve spendPath: use constructor value, or look it up reactively
        // from the descriptor analysis (which may finish after navigation).
        final spendPath = widget.spendPath ??
            (state is WalletDetailLoaded
                ? state.descriptorAnalysis?.spendPaths
                    .where((p) => p.id == _psbt.spendPathId.toInt())
                    .firstOrNull
                : null);

        return Scaffold(
          appBar: AppBar(
            title: Text(l10n.psbtDetailTitle),
            actions: [
              PopupMenuButton<_PsbtMenuAction>(
                tooltip: l10n.moreOptionsTooltip,
                onSelected: (action) {
                  if (action == _PsbtMenuAction.delete) _delete(context);
                },
                itemBuilder: (_) => [
                  iconMenuItem(
                    value: _PsbtMenuAction.delete,
                    icon: Icons.delete_outline,
                    label: l10n.psbtDeleteTitle,
                    color: Colors.red.withAlpha(AppAlpha.deleteAction),
                  ),
                ],
              ),
            ],
          ),
          body: SafeArea(
            child: ListView(
              dragStartBehavior: DragStartBehavior.down,
              padding: const EdgeInsets.all(16),
              children: [
                // Spent inputs warning
                if (_psbt.hasSpentInputs) ...[
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.red.withAlpha(AppAlpha.faint),
                      border: Border.all(color: Colors.red.withAlpha(AppAlpha.inactive)),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Icon(Icons.error_outline, color: Colors.red, size: 18),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            l10n.psbtSpentInputsWarning,
                            style: theme.textTheme.bodySmall?.copyWith(color: Colors.red),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),
                ],
                // Status badge
                _StatusBadge(
                  analysis: analysis,
                  threshold: _psbt.threshold.toInt(),
                  mfpCount: _psbt.mfps.length,
                  hasSpentInputs: _psbt.hasSpentInputs,
                ),
                const SizedBox(height: 16),

                // Transaction details card
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: TextField(
                                controller: _labelController,
                                decoration: InputDecoration(
                                  labelText: l10n.txLabelTitle,
                                  hintText: l10n.addressLabelHint,
                                  isDense: true,
                                  border: const OutlineInputBorder(),
                                ),
                                onSubmitted: (v) => _saveLabel(context, v),
                                onTapOutside: (_) =>
                                    _saveLabel(context, _labelController.text),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        for (int i = 0; i < _psbt.recipients.length; i++) ...[
                          if (_psbt.recipients[i].opReturnData != null) ...[
                            _DetailRow(
                              label: l10n.opReturnRecipientLabel,
                              value: decodeOpReturnForDisplay(
                                  _psbt.recipients[i].opReturnData!),
                            ),
                            const SizedBox(height: 8),
                          ] else ...[
                            _DetailRow(
                              label: _psbt.recipients.length == 1
                                  ? l10n.psbtRecipient
                                  : '${l10n.psbtRecipient} ${i + 1}',
                              value: _psbt.recipients[i].address,
                              isAddress: true,
                            ),
                            const SizedBox(height: 4),
                            _DetailRow(
                              label: l10n.psbtAmount,
                               value:
                                   BitcoinFormatter.satsLabel(_psbt.recipients[i].amountSat.toInt()),
                            ),
                            const SizedBox(height: 8),
                          ],
                        ],
                        if (_psbt.recipients.length > 1) ...[
                          _DetailRow(
                            label: l10n.createTxTotalOut,
                            value:
                                BitcoinFormatter.satsLabel(_psbt.amountSat.toInt()),
                          ),
                        ],
                        const SizedBox(height: 8),
                        _DetailRow(
                          label: l10n.psbtFee,
                          value: BitcoinFormatter.satsLabel(_psbt.feeSat.toInt()),
                        ),
                        const SizedBox(height: 8),
                        _DetailRow(
                          label: l10n.psbtCreatedAt,
                          value: formatDateTimeFromUnix(_psbt.createdAt.toInt()),
                        ),
                        if (spendPath != null)
                          ..._buildTimelockRows(context, spendPath, tipHeight),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 16),

                // Signatures section
                Text(
                  l10n.psbtSignaturesTitle(signed, threshold, total),
                  style: theme.textTheme.titleMedium,
                ),
                const SizedBox(height: 8),

                if (analysis == null)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    child: Text(
                      '—',
                      style: TextStyle(color: theme.colorScheme.onSurface.withAlpha(AppAlpha.inactive)),
                    ),
                  )
                else
                  ...() {
                    final hotKeyMfps = _hotKeys.map((k) => k.mfp).toSet();
                    return analysis.signers.map((signer) {
                      final label = keyLabels[signer.mfp];
                      final isOptional = !signer.hasSigned && signed >= threshold;
                      // If the PSBT is finalized but partial_sigs were cleared (e.g. by an
                      // external signer), we can't tell who signed — show as "unknown".
                      final isUnknown = !signer.hasSigned && analysis.isFinalized;
                      return _SignerRow(
                        mfp: signer.mfp,
                        label: label,
                        hasSigned: signer.hasSigned,
                        isOptional: isOptional && !isUnknown,
                        isUnknown: isUnknown,
                        onSign: (hotKeyMfps.contains(signer.mfp) &&
                                !signer.hasSigned &&
                                !_isReadyToBroadcast)
                            ? () => _signLocallyWithKey(context, signer.mfp)
                            : null,
                      );
                    });
                  }(),

                const SizedBox(height: 24),

                // Action buttons — filled when signatures needed, outlined when ready to broadcast
                Row(
                  children: [
                    Expanded(
                      child: _isReadyToBroadcast
                          ? OutlinedButton.icon(
                              onPressed: () => _exportPsbt(context),
                              icon: const Icon(Icons.upload_outlined),
                              label: Text(l10n.psbtExportButton),
                            )
                          : FilledButton.tonal(
                              onPressed: () => _exportPsbt(context),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  const Icon(Icons.upload_outlined, size: 18),
                                  const SizedBox(width: 8),
                                  Text(l10n.psbtExportButton),
                                ],
                              ),
                            ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: _isReadyToBroadcast
                          ? OutlinedButton.icon(
                              onPressed: () => _importSigned(context),
                              icon: const Icon(Icons.download_outlined),
                              label: Text(l10n.psbtImportSignedButton),
                            )
                          : FilledButton.tonalIcon(
                              onPressed: () => _importSigned(context),
                              icon: const Icon(Icons.download_outlined),
                              label: Text(l10n.psbtImportSignedButton),
                            ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                // Sign directly with a connected hardware wallet
                OutlinedButton.icon(
                  onPressed: _isReadyToBroadcast
                      ? null // already signed; no need
                      : () => _signWithHw(context),
                  icon: const Icon(Icons.hardware_outlined, size: 18),
                  label: Text(l10n.signWithHwWallet),
                ),
                const SizedBox(height: 16),
                _buildAutoBroadcastSwitch(context, l10n, unlockEta),
                _buildBroadcastButton(context, l10n, unlockEta, tipHeight),
              ],
            ),
          ),
        );
      },
    );
  }
}

enum _PsbtMenuAction { delete }

// ─── Sub-widgets ──────────────────────────────────────────────────────────────

class _StatusBadge extends StatelessWidget {
  final APIPsbtAnalysis? analysis;
  final int threshold;
  final int mfpCount;
  final bool hasSpentInputs;

  const _StatusBadge({
    required this.analysis,
    required this.threshold,
    required this.mfpCount,
    required this.hasSpentInputs,
  });

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final theme = Theme.of(context);

    if (!hasSpentInputs && analysis == null) {
      return const SizedBox.shrink();
    }

    final String label;
    final Color color;

    if (hasSpentInputs) {
      label = l10n.psbtStatusSpent;
      color = Colors.red;
    } else {
      final signed = analysis!.signers.where((s) => s.hasSigned).length;
      if (analysis!.isFinalized || signed >= threshold) {
        label = l10n.psbtStatusSigned;
        color = Colors.green;
      } else if (signed > 0) {
        label = l10n.psbtStatusPartial;
        color = Colors.orange;
      } else {
        label = l10n.psbtStatusUnsigned;
        color = theme.colorScheme.outline;
      }
    }

    return Align(
      alignment: Alignment.centerLeft,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(
          border: Border.all(color: color),
          borderRadius: BorderRadius.circular(4),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: color,
            fontFamily: kMonospaceFontFamily,
            fontSize: 12,
            letterSpacing: 1,
          ),
        ),
      ),
    );
  }
}

class _SignerRow extends StatelessWidget {
  final String mfp;
  final String? label;
  final bool hasSigned;
  final bool isOptional;
  final bool isUnknown;
  final VoidCallback? onSign;

  const _SignerRow({
    required this.mfp,
    required this.label,
    required this.hasSigned,
    this.isOptional = false,
    this.isUnknown = false,
    this.onSign,
  });

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final Color color;
    final String statusText;
    final IconData icon;

    if (hasSigned) {
      color = Colors.green;
      statusText = l10n.psbtSignerSigned;
      icon = Icons.check_circle;
    } else if (isUnknown) {
      color = Colors.orange;
      statusText = l10n.psbtSignerUnknown;
      icon = Icons.help_outline;
    } else if (isOptional) {
      color = theme.colorScheme.onSurface.withAlpha(AppAlpha.pale);
      statusText = l10n.psbtSignerOptional;
      icon = Icons.radio_button_unchecked;
    } else {
      color = theme.colorScheme.outline;
      statusText = l10n.psbtSignerMissing;
      icon = Icons.radio_button_unchecked;
    }

    final dimmed = isOptional && !isUnknown;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Icon(icon, color: color, size: 20),
          const SizedBox(width: 8),
          MfpBadge(
            label: mfp.substring(0, 8).toUpperCase(),
            color: dimmed
                ? theme.colorScheme.onSurface.withAlpha(AppAlpha.pale)
                : theme.colorScheme.outline,
          ),
          const SizedBox(width: 8),
          if (label != null)
            Expanded(
              child: Text(
                label!,
                overflow: TextOverflow.ellipsis,
                style: dimmed
                    ? TextStyle(color: theme.colorScheme.onSurface.withAlpha(AppAlpha.pale))
                    : null,
              ),
            ),
          const Spacer(),
          if (onSign != null)
            FilledButton.tonalIcon(
              onPressed: onSign,
              icon: const Icon(Icons.key_outlined, size: 16),
              label: Text(l10n.signButton),
            )
          else
            Text(
              statusText,
              style: TextStyle(color: color, fontSize: 12),
            ),
        ],
      ),
    );
  }
}

class _DetailRow extends StatelessWidget {
  final String label;
  final String value;
  final bool isAddress;

  const _DetailRow({
    required this.label,
    required this.value,
    this.isAddress = false,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 90,
          child: Text(
            label,
            style: theme.textTheme.bodySmall
                ?.copyWith(color: theme.colorScheme.onSurface.withAlpha(AppAlpha.medium)),
          ),
        ),
        Expanded(
          child: isAddress
              ? ColoredGroupText(text: value)
              : Text(value, style: theme.textTheme.bodySmall),
        ),
      ],
    );
  }
}

