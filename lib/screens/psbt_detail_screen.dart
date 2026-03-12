import 'dart:convert';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import 'package:deadbolt/cubit/settings_cubit.dart';
import 'package:deadbolt/cubit/wallet_detail_cubit.dart';
import 'package:deadbolt/l10n/l10n.dart';
import 'package:deadbolt/src/rust/api/model.dart';
import 'package:deadbolt/src/rust/api/wallet.dart' show stripPsbtForHw;
import 'package:deadbolt/models/timelock_types.dart';
import 'package:deadbolt/utils/bitcoin_formatter.dart' show BitcoinFormatter;
import 'package:deadbolt/errors.dart';
import 'package:deadbolt/utils/toast_helper.dart';
import 'package:deadbolt/widgets/colored_address_text.dart';
import 'package:deadbolt/widgets/mfp_badge.dart';
import 'package:deadbolt/widgets/text_export_sheet.dart' show showQrDialog;
import 'package:deadbolt/screens/qr_scanner_screen.dart';

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

  @override
  void initState() {
    super.initState();
    _psbt = widget.psbt;
  }

  APIPsbtAnalysis? get _analysis {
    final s = context.read<WalletDetailCubit>().state;
    if (s is WalletDetailLoaded) return s.psbtAnalyses[_psbt.id.toInt()];
    return null;
  }

  Map<String, String> get _keyLabels {
    final s = context.read<WalletDetailCubit>().state;
    if (s is WalletDetailLoaded) return s.keyLabels;
    return {};
  }

  int get _signedCount =>
      _analysis?.signers.where((s) => s.hasSigned).length ?? 0;

  bool get _isReadyToBroadcast =>
      _signedCount >= _psbt.threshold.toInt() ||
      (_analysis?.isFinalized ?? false);

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
                color: theme.colorScheme.onSurface.withAlpha(150),
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
        statusColor = theme.colorScheme.onSurface.withAlpha(120);
        statusIcon = Icons.sync_disabled_outlined;
      } else if (tipHeight == 0) {
        statusText = l10n.psbtTimelockSyncRequired;
        statusColor = theme.colorScheme.onSurface.withAlpha(120);
        statusIcon = Icons.sync_disabled_outlined;
      } else {
        final unlockBlock = confHeight + relBlocks;
        final remaining = unlockBlock - tipHeight;
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
          statusColor = theme.colorScheme.onSurface.withAlpha(120);
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
    final l10n = context.l10n;
    showModalBottomSheet<void>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.qr_code),
              title: Text(l10n.showQrCode),
              onTap: () async {
                Navigator.pop(ctx);
                // Strip non_witness_utxo and other non-essential fields to
                // reduce QR size. Falls back to original if stripping fails.
                final strippedBase64 = await stripPsbtForHw(
                  psbtBase64: _psbt.psbtBase64,
                ).catchError((_) => _psbt.psbtBase64);
                if (!context.mounted) return;
                // Animated BC-UR must use ur:crypto-psbt with raw binary bytes.
                // Static QR shows the base64 string (Krux, Coldcard accept both).
                showQrDialog(
                  context,
                  strippedBase64,
                  urBytes: base64Decode(strippedBase64),
                  urType: 'crypto-psbt',
                );
              },
            ),
            ListTile(
              leading: const Icon(Icons.copy_outlined),
              title: Text(l10n.copyToClipboard),
              onTap: () {
                Navigator.pop(ctx);
                Clipboard.setData(ClipboardData(text: _psbt.psbtBase64));
                showSuccessToast(context, l10n.psbtExportedCopied);
              },
            ),
            ListTile(
              leading: const Icon(Icons.save_alt_outlined),
              title: Text(l10n.saveAs),
              onTap: () async {
                Navigator.pop(ctx);
                await _saveToFile(context);
              },
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _saveToFile(BuildContext context) async {
    try {
      final bytes = base64Decode(_psbt.psbtBase64);
      final savedPath = await FilePicker.platform.saveFile(
        fileName: 'transaction.psbt',
        type: FileType.custom,
        allowedExtensions: ['psbt'],
        bytes: bytes,
      );
      if (savedPath == null) return;
      // On desktop, FilePicker may not write the bytes itself.
      if (!await File(savedPath).exists()) {
        await File(savedPath).writeAsBytes(bytes);
      }
      if (context.mounted) {
        showSuccessToast(context, context.l10n.savedToDownloads);
      }
    } catch (e) {
      if (context.mounted) showErrorToast(context, formatRustError(e));
    }
  }

  // ─── Import signed ────────────────────────────────────────────────────────

  void _importSigned(BuildContext context) {
    final l10n = context.l10n;
    showModalBottomSheet<void>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.qr_code_scanner),
              title: Text(l10n.psbtImportFromQr),
              onTap: () async {
                Navigator.pop(ctx);
                final scanned = await QrScannerScreen.push(context);
                if (scanned != null && context.mounted) {
                  _mergePsbt(context, scanned.trim());
                }
              },
            ),
            ListTile(
              leading: const Icon(Icons.file_open_outlined),
              title: Text(l10n.psbtImportFromFile),
              onTap: () async {
                Navigator.pop(ctx);
                await _importFromFile(context);
              },
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _importFromFile(BuildContext context) async {
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['psbt', 'txt'],
        withData: true,
      );
      if (result == null || result.files.first.bytes == null) return;
      final bytes = result.files.first.bytes!;
      // Try to decode as UTF-8 base64 first; if that fails, raw bytes → base64
      String psbtBase64;
      try {
        psbtBase64 = utf8.decode(bytes).trim();
        // Validate it's decodable base64
        base64Decode(psbtBase64);
      } catch (_) {
        psbtBase64 = base64Encode(bytes);
      }
      if (context.mounted) _mergePsbt(context, psbtBase64);
    } catch (e) {
      if (context.mounted) showErrorToast(context, formatRustError(e));
    }
  }

  Future<void> _mergePsbt(BuildContext context, String signedBase64) async {
    final l10n = context.l10n;
    try {
      final updated = await context
          .read<WalletDetailCubit>()
          .mergePsbt(_psbt.id.toInt(), signedBase64);
      if (updated != null) {
        setState(() => _psbt = updated);
        if (context.mounted) showSuccessToast(context, l10n.psbtMergeSuccess);
      }
    } catch (e) {
      if (context.mounted) {
        showErrorToast(context, formatRustError(e));
      }
    }
  }

  // ─── Broadcast ───────────────────────────────────────────────────────────

  Future<void> _broadcast(BuildContext context) async {
    final l10n = context.l10n;
    final settings = context.read<SettingsCubit>().state;
    final electrumUrl = settings.electrumUrlForNetwork(
      context.read<WalletDetailCubit>().state is WalletDetailLoaded
          ? (context.read<WalletDetailCubit>().state as WalletDetailLoaded)
              .walletInfo
              .network
          : settings.network,
    );

    setState(() => _broadcasting = true);
    try {
      final txid = await context
          .read<WalletDetailCubit>()
          .broadcastPsbt(_psbt.id.toInt(), electrumUrl);
      if (context.mounted) {
        showSuccessToast(context, l10n.psbtBroadcastSuccess(txid));
        Navigator.of(context).pop();
      }
    } catch (e) {
      if (context.mounted) {
        showErrorToast(context, formatRustError(e));
      }
    } finally {
      if (mounted) setState(() => _broadcasting = false);
    }
  }

  // ─── Delete ───────────────────────────────────────────────────────────────

  void _delete(BuildContext context) {
    final l10n = context.l10n;
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        titlePadding: const EdgeInsets.fromLTRB(24, 16, 8, 0),
        title: Row(
          children: [
            Expanded(child: Text(l10n.psbtDeleteTitle)),
            IconButton(
              icon: const Icon(Icons.close),
              tooltip: l10n.cancel,
              visualDensity: VisualDensity.compact,
              onPressed: () => Navigator.pop(ctx),
            ),
          ],
        ),
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
                  PopupMenuItem(
                    value: _PsbtMenuAction.delete,
                    child: Row(
                      children: [
                        const Icon(Icons.delete_outline, size: 20),
                        const SizedBox(width: 12),
                        Text(l10n.psbtDeleteTitle),
                      ],
                    ),
                  ),
                ],
              ),
            ],
          ),
          body: SafeArea(
            child: ListView(
              padding: const EdgeInsets.all(16),
              children: [
                // Status badge
                _StatusBadge(
                  analysis: analysis,
                  threshold: _psbt.threshold.toInt(),
                  mfpCount: _psbt.mfps.length,
                ),
                const SizedBox(height: 16),

                // Transaction details card
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _DetailRow(
                          label: l10n.psbtRecipient,
                          value: _psbt.recipient,
                          isAddress: true,
                        ),
                        const SizedBox(height: 8),
                        _DetailRow(
                          label: l10n.psbtAmount,
                          value: '${BitcoinFormatter.formatNum(_psbt.amountSat.toInt())} sats',
                        ),
                        const SizedBox(height: 8),
                        _DetailRow(
                          label: l10n.psbtFee,
                          value: '${BitcoinFormatter.formatNum(_psbt.feeSat.toInt())} sats',
                        ),
                        const SizedBox(height: 8),
                        _DetailRow(
                          label: l10n.psbtCreatedAt,
                          value: _formatDate(_psbt.createdAt.toInt()),
                        ),
                        if (spendPath != null)
                          ..._buildTimelockRows(
                            context,
                            spendPath,
                            state is WalletDetailLoaded ? state.tipHeight : 0,
                          ),
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
                      style: TextStyle(color: theme.colorScheme.onSurface.withAlpha(120)),
                    ),
                  )
                else
                  ...analysis.signers.map((signer) {
                    final label = keyLabels[signer.mfp];
                    final isOptional = !signer.hasSigned && signed >= threshold;
                    return _SignerRow(
                      mfp: signer.mfp,
                      label: label,
                      hasSigned: signer.hasSigned,
                      isOptional: isOptional,
                    );
                  }),

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
                const SizedBox(height: 16),
                FilledButton.icon(
                  onPressed: (_isReadyToBroadcast && !_broadcasting)
                      ? () => _broadcast(context)
                      : null,
                  icon: _broadcasting
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.send_outlined),
                  label: Text(l10n.psbtBroadcastButton),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

enum _PsbtMenuAction { delete }

String _formatDate(int unixSeconds) {
  final dt = DateTime.fromMillisecondsSinceEpoch(unixSeconds * 1000);
  return '${dt.year}-${dt.month.toString().padLeft(2, '0')}-'
      '${dt.day.toString().padLeft(2, '0')} '
      '${dt.hour.toString().padLeft(2, '0')}:'
      '${dt.minute.toString().padLeft(2, '0')}';
}

// ─── Sub-widgets ──────────────────────────────────────────────────────────────

class _StatusBadge extends StatelessWidget {
  final APIPsbtAnalysis? analysis;
  final int threshold;
  final int mfpCount;

  const _StatusBadge({
    required this.analysis,
    required this.threshold,
    required this.mfpCount,
  });

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final theme = Theme.of(context);

    if (analysis == null) {
      return const SizedBox.shrink();
    }

    final signed = analysis!.signers.where((s) => s.hasSigned).length;
    final String label;
    final Color color;

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
            fontFamily: 'monospace',
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

  const _SignerRow({
    required this.mfp,
    required this.label,
    required this.hasSigned,
    this.isOptional = false,
  });

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final Color color;
    final String statusText;

    if (hasSigned) {
      color = Colors.green;
      statusText = l10n.psbtSignerSigned;
    } else if (isOptional) {
      color = theme.colorScheme.onSurface.withAlpha(80);
      statusText = l10n.psbtSignerOptional;
    } else {
      color = theme.colorScheme.outline;
      statusText = l10n.psbtSignerMissing;
    }

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Icon(
            hasSigned ? Icons.check_circle : Icons.radio_button_unchecked,
            color: color,
            size: 20,
          ),
          const SizedBox(width: 8),
          MfpBadge(
            label: mfp.substring(0, 8).toUpperCase(),
            color: isOptional
                ? theme.colorScheme.onSurface.withAlpha(80)
                : theme.colorScheme.outline,
          ),
          const SizedBox(width: 8),
          if (label != null)
            Expanded(
              child: Text(
                label!,
                overflow: TextOverflow.ellipsis,
                style: isOptional
                    ? TextStyle(color: theme.colorScheme.onSurface.withAlpha(80))
                    : null,
              ),
            ),
          const Spacer(),
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
                ?.copyWith(color: theme.colorScheme.onSurface.withAlpha(150)),
          ),
        ),
        Expanded(
          child: isAddress
              ? ColoredAddressText(address: value)
              : Text(value, style: theme.textTheme.bodySmall),
        ),
      ],
    );
  }
}
