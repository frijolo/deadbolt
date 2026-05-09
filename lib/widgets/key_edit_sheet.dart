import 'package:flutter/material.dart';
import 'package:deadbolt/config/constants.dart' show kMonospaceFontFamily;

import 'package:deadbolt/l10n/l10n.dart';
import 'package:deadbolt/screens/seed_export_screen.dart';
import 'package:deadbolt/utils/toast_helper.dart'
    show copySecretAndScheduleClear;
import 'package:deadbolt/src/rust/api/model.dart' show APINetwork;
import 'package:deadbolt/theme/app_theme.dart';
import 'package:deadbolt/widgets/colored_group_text.dart';
import 'package:deadbolt/widgets/dialog_helpers.dart' show SheetHandle, showSheet;
import 'package:deadbolt/widgets/edit_name_dialog.dart';
import 'package:deadbolt/widgets/mfp_badge.dart';
import 'package:deadbolt/widgets/text_export_sheet.dart';

/// Opens a key detail / edit bottom sheet.
///
/// [onDelete] is only non-null when deletion is possible.
/// [canDelete] controls whether the delete button is enabled (key not in use).
/// [isHot] shows the private key section with view/delete actions.
void showKeySheet(
  BuildContext context, {
  required String mfp,
  required String? initialName,
  required String derivationPath,
  required String xpub,
  required Color mfpColor,
  required void Function(String? name) onNameSave,
  bool Function(String name)? isDuplicateName,
  VoidCallback? onDelete,
  bool canDelete = false,
  VoidCallback? onMakeHot,
  bool isHot = false,
  Future<String?> Function()? onRevealSeed,
  VoidCallback? onDeletePrivateInfo,
  /// Override the disclaimer shown before deleting private info.
  /// When null, [AppLocalizations.deletePrivateKeyDisclaimer] is used.
  String? deletePrivateInfoDisclaimer,
  /// Network for mnemonic export (enables SeedQR tab when provided).
  APINetwork? network,
}) {
  showSheet<void>(context, (_) => _KeySheetContent(
      mfp: mfp,
      initialName: initialName,
      derivationPath: derivationPath,
      xpub: xpub,
      mfpColor: mfpColor,
      onNameSave: onNameSave,
      isDuplicateName: isDuplicateName,
      onDelete: onDelete,
      canDelete: canDelete,
      onMakeHot: onMakeHot,
      isHot: isHot,
      onRevealSeed: onRevealSeed,
      onDeletePrivateInfo: onDeletePrivateInfo,
      deletePrivateInfoDisclaimer: deletePrivateInfoDisclaimer,
      network: network,
    ),
  );
}

class _KeySheetContent extends StatefulWidget {
  final String mfp;
  final String? initialName;
  final String derivationPath;
  final String xpub;
  final Color mfpColor;
  final void Function(String? name) onNameSave;
  final bool Function(String name)? isDuplicateName;
  final VoidCallback? onDelete;
  final bool canDelete;
  final VoidCallback? onMakeHot;
  final bool isHot;
  final Future<String?> Function()? onRevealSeed;
  final VoidCallback? onDeletePrivateInfo;
  final String? deletePrivateInfoDisclaimer;
  final APINetwork? network;

  const _KeySheetContent({
    required this.mfp,
    required this.initialName,
    required this.derivationPath,
    required this.xpub,
    required this.mfpColor,
    required this.onNameSave,
    this.isDuplicateName,
    this.onDelete,
    this.canDelete = false,
    this.onMakeHot,
    this.isHot = false,
    this.onRevealSeed,
    this.onDeletePrivateInfo,
    this.deletePrivateInfoDisclaimer,
    this.network,
  });

  @override
  State<_KeySheetContent> createState() => _KeySheetContentState();
}

class _KeySheetContentState extends State<_KeySheetContent> {
  late String? _currentName;

  @override
  void initState() {
    super.initState();
    _currentName = widget.initialName;
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final cs = Theme.of(context).colorScheme;

    return ConstrainedBox(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.sizeOf(context).height * 0.90,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SheetHandle(),
          Flexible(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildNameSection(context, cs, l10n),
                  const SizedBox(height: 16),
                  const Divider(),
                  const SizedBox(height: 8),
                  _buildInfoSection(context, cs, l10n),
                  if (widget.isHot) ...[
                    const SizedBox(height: 16),
                    const Divider(),
                    const SizedBox(height: 8),
                    _buildPrivateKeySection(context, cs, l10n),
                  ],
                  if (widget.onMakeHot != null) ...[
                    const SizedBox(height: 16),
                    const Divider(),
                    const SizedBox(height: 8),
                    _buildMakeHotButton(context),
                  ],
                  if (widget.onDelete != null) ...[
                    const SizedBox(height: 16),
                    const Divider(),
                    const SizedBox(height: 8),
                    _buildDeleteButton(context, l10n),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildNameSection(
      BuildContext context, ColorScheme cs, AppLocalizations l10n) {
    final hasName = _currentName != null;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          l10n.keyNameDialogTitle,
          style: TextStyle(fontSize: 11, color: cs.onSurface.withAlpha(AppAlpha.secondary)),
        ),
        const SizedBox(height: 4),
        GestureDetector(
          onTap: () => _showNameDialog(context),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  _currentName ?? widget.mfp.toUpperCase(),
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: hasName ? FontWeight.w600 : FontWeight.normal,
                    color:
                        hasName ? cs.onSurface : cs.onSurface.withAlpha(AppAlpha.muted),
                    fontStyle:
                        hasName ? FontStyle.normal : FontStyle.italic,
                  ),
                ),
              ),
              Icon(Icons.edit, size: 14, color: cs.onSurface.withAlpha(AppAlpha.inactive)),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildInfoSection(
      BuildContext context, ColorScheme cs, AppLocalizations l10n) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _InfoRow(
          label: l10n.keyFingerprintLabel,
          child: MfpBadge(
            label: widget.mfp.toUpperCase(),
            color: widget.mfpColor,
            letterSpacing: 0.5,
          ),
        ),
        _InfoRow(
          label: l10n.keyDerivPathLabel,
          child: Text(
            widget.derivationPath.isEmpty
                ? l10n.rootPath
                : widget.derivationPath,
            style: TextStyle(
              fontFamily: kMonospaceFontFamily,
              color: widget.derivationPath.isEmpty ? AppAccent.color : null,
            ),
          ),
        ),
        _InfoRow(
          label: l10n.keyXpubLabel,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: ColoredGroupText(text: widget.xpub, truncate: false, monospace: true),
              ),
              const SizedBox(width: 8),
              IconButton(
                icon: const Icon(Icons.ios_share, size: 18),
                tooltip: l10n.copyKeyspecTooltip,
                visualDensity: VisualDensity.compact,
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(),
                color: cs.onSurface.withAlpha(AppAlpha.muted),
                onPressed: () => showTextExportSheet(
                  context,
                  text:
                      '[${widget.mfp}/${widget.derivationPath}]${widget.xpub}',
                  fileName: 'keyspec',
                  copiedMessage: l10n.keyCopied,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildPrivateKeySection(
      BuildContext context, ColorScheme cs, AppLocalizations l10n) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          l10n.privateKeySection,
          style: TextStyle(
            fontSize: 11,
            color: cs.onSurface.withAlpha(AppAlpha.secondary),
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 10),
        if (widget.onRevealSeed != null)
          OutlinedButton.icon(
            onPressed: () => _confirmViewSeed(context, l10n),
            icon: const Icon(Icons.visibility_outlined, size: 18),
            label: Text(l10n.viewPrivateKeyButton),
            style: OutlinedButton.styleFrom(
              foregroundColor: cs.primary,
              minimumSize: const Size(double.infinity, 40),
              alignment: Alignment.centerLeft,
            ),
          ),
        if (widget.onDeletePrivateInfo != null) ...[
          const SizedBox(height: 8),
          OutlinedButton.icon(
            onPressed: () => _confirmDeletePrivateInfo(context, l10n),
            icon: const Icon(Icons.key_off_outlined, size: 18),
            label: Text(l10n.deletePrivateKeyButton),
            style: OutlinedButton.styleFrom(
              foregroundColor: cs.error,
              side: BorderSide(color: cs.error.withAlpha(AppAlpha.half)),
              minimumSize: const Size(double.infinity, 40),
              alignment: Alignment.centerLeft,
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildMakeHotButton(BuildContext context) {
    return OutlinedButton.icon(
      onPressed: () {
        Navigator.of(context).pop();
        widget.onMakeHot!();
      },
      icon: const Icon(Icons.local_fire_department_outlined, size: 18),
      label: Text(context.l10n.addPrivateKeyLabel),
      style: OutlinedButton.styleFrom(
        foregroundColor: AppAccent.color,
        side: BorderSide(color: AppAccent.color.withAlpha(AppAlpha.half)),
        minimumSize: const Size(double.infinity, 40),
      ),
    );
  }

  Widget _buildDeleteButton(BuildContext context, AppLocalizations l10n) {
    final can = widget.canDelete;
    return OutlinedButton.icon(
      onPressed: can
          ? () {
              Navigator.of(context).pop();
              widget.onDelete!();
            }
          : null,
      icon: Icon(
        can ? Icons.delete_outline : Icons.delete_forever_outlined,
        size: 18,
      ),
      label: Text(can ? l10n.removeKeyTooltip : l10n.keyInUseTooltip),
      style: OutlinedButton.styleFrom(
        foregroundColor: can ? Colors.red : null,
        side: BorderSide(
          color: can
              ? Colors.red.withAlpha(AppAlpha.half)
              : Colors.grey.withAlpha(AppAlpha.half),
        ),
      ),
    );
  }

  void _confirmViewSeed(BuildContext context, AppLocalizations l10n) {
    showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l10n.viewPrivateKeyButton),
        content: Text(l10n.viewPrivateKeyDisclaimer),
        actions: [
          Row(
            children: [
              Expanded(
                child: TextButton(
                  onPressed: () => Navigator.pop(ctx, false),
                  child: Text(l10n.cancel),
                ),
              ),
              Expanded(
                child: FilledButton(
                  onPressed: () => Navigator.pop(ctx, true),
                  child: Text(l10n.viewPrivateKeyConfirm),
                ),
              ),
            ],
          ),
        ],
      ),
    ).then((confirmed) async {
      if (confirmed != true) return;
      final seed = await widget.onRevealSeed!();
      if (seed == null || !context.mounted) return;
      _showSeedDialog(context, seed);
    });
  }

  void _showSeedDialog(BuildContext context, String seed) {
    final isMnemonic = !seed.startsWith('xprv') && !seed.startsWith('tprv');
    if (isMnemonic && widget.network != null) {
      final nav = Navigator.of(context);
      nav.pop(); // close the bottom sheet first
      nav.push(MaterialPageRoute<void>(
        builder: (_) => SeedExportScreen(
          mnemonic: seed,
          mfp: widget.mfp,
          network: widget.network!,
        ),
      ));
      return;
    }
    // Fallback: plain-text dialog for xprv keys or when network is not set.
    final l10n = context.l10n;
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l10n.seedPhraseDialogTitle),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SelectableText(
              seed,
              style: const TextStyle(fontFamily: kMonospaceFontFamily, fontSize: 13),
            ),
          ],
        ),
        actions: [
          TextButton.icon(
            onPressed: () async {
              await copySecretAndScheduleClear(
                seed,
                successMessage: l10n.seedPhraseCopied,
              );
              if (ctx.mounted) Navigator.pop(ctx);
            },
            icon: const Icon(Icons.copy, size: 16),
            label: Text(l10n.copyToClipboard),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(l10n.close),
          ),
        ],
      ),
    );
  }

  void _confirmDeletePrivateInfo(BuildContext context, AppLocalizations l10n) {
    final disclaimer =
        widget.deletePrivateInfoDisclaimer ?? l10n.deletePrivateKeyDisclaimer;
    showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l10n.deletePrivateKeyButton),
        content: Text(disclaimer),
        actions: [
          Row(
            children: [
              Expanded(
                child: TextButton(
                  onPressed: () => Navigator.pop(ctx, false),
                  child: Text(l10n.cancel),
                ),
              ),
              Expanded(
                child: FilledButton(
                  onPressed: () => Navigator.pop(ctx, true),
                  style: FilledButton.styleFrom(
                    backgroundColor: Theme.of(ctx).colorScheme.error,
                  ),
                  child: Text(l10n.deletePrivateKeyConfirm),
                ),
              ),
            ],
          ),
        ],
      ),
    ).then((confirmed) {
      if (confirmed != true) return;
      if (!context.mounted) return;
      Navigator.of(context).pop(); // close the sheet
      widget.onDeletePrivateInfo!();
    });
  }

  void _showNameDialog(BuildContext context) {
    showEditNameDialog(
      context,
      title: context.l10n.keyNameDialogTitle,
      currentName: _currentName,
      onSave: (name) {
        setState(() => _currentName = name);
        widget.onNameSave(name);
      },
      isDuplicate: widget.isDuplicateName,
    );
  }
}

/// Label + value row matching the _DetailRow style used in coin/tx detail dialogs.
class _InfoRow extends StatelessWidget {
  final String label;
  final Widget child;

  const _InfoRow({required this.label, required this.child});

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
              color: Theme.of(context).colorScheme.onSurface.withAlpha(AppAlpha.secondary),
            ),
          ),
          const SizedBox(height: 2),
          child,
        ],
      ),
    );
  }
}
