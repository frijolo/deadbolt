import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import 'package:deadbolt/l10n/l10n.dart';
import 'package:deadbolt/cubit/wallet_detail_cubit.dart';
import 'package:deadbolt/utils/safe_file_name.dart' show safeFileBase;
import 'package:deadbolt/utils/toast_helper.dart';
import 'package:deadbolt/widgets/text_export_sheet.dart' show showTextExportSheet;
import 'package:deadbolt/screens/export_backup_dialog.dart' show showExportBackupDialog;

import 'package:deadbolt/utils/export_sheet.dart' show saveBytes, shareBytes, showDescriptorExportSheet;
import 'package:deadbolt/services/wallet_service.dart';
import 'package:deadbolt/src/rust/api/wallet/backup.dart' as rust_backup;
import 'package:deadbolt/src/rust/api/wallet/bed_backup.dart' as rust_bed;

enum ExportChoice { labels, descriptor, publishDescriptor, wallet }

Future<ExportChoice?> showExportChoiceSheet(BuildContext context) async {
  final l10n = context.l10n;
  return showModalBottomSheet<ExportChoice>(
    context: context,
    builder: (ctx) => SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ListTile(
            leading: const Icon(Icons.label_outline),
            title: Text(l10n.exportLabelsOption),
            onTap: () => Navigator.of(ctx).pop(ExportChoice.labels),
          ),
          ListTile(
            leading: const Icon(Icons.schema_outlined),
            title: Text(l10n.descriptorLabel),
            onTap: () => Navigator.of(ctx).pop(ExportChoice.descriptor),
          ),
          ListTile(
            leading: const Icon(Icons.cloud_outlined),
            title: Text(l10n.publishBackupMenu),
            onTap: () => Navigator.of(ctx).pop(ExportChoice.publishDescriptor),
          ),
          ListTile(
            leading: const Icon(Icons.save_alt_outlined),
            title: Text(l10n.walletExportLabel),
            onTap: () => Navigator.of(ctx).pop(ExportChoice.wallet),
          ),
          const SizedBox(height: 8),
        ],
      ),
    ),
  );
}

Future<void> exportLabels(
  BuildContext context,
  WalletDetailLoaded state,
) async {
  final cubit = context.read<WalletDetailCubit>();
  final l10n = context.l10n;
  final content = await cubit.exportBip329Labels();
  if (!context.mounted) return;
  if (content == null || content.isEmpty) {
    showErrorToast(l10n.exportBip329Empty);
    return;
  }
  final safeName = safeFileBase(state.walletInfo.name).toLowerCase();
  showTextExportSheet(
    context,
    text: content,
    fileName: '${safeName}_labels',
    copiedMessage: l10n.exportBip329Copied,
    fileExtension: 'jsonl',
    bigText: true,
  );
}

Future<void> exportDescriptor(
  BuildContext context,
  WalletDetailLoaded state,
) async {
  final l10n = context.l10n;
  final safeName = safeFileBase(state.walletInfo.name).toLowerCase();

  await showDescriptorExportSheet(
    context,
    descriptor: state.walletInfo.descriptor,
    fileName: '${safeName}_descriptor',
    copiedMessage: l10n.copiedToClipboard,
    extraItems: [
      (
        icon: Icons.lock_outline,
        label: l10n.bedExportOption,
        onTap: () => exportBedBackup(context, state),
      ),
    ],
  );
}

Future<void> exportBackup(
  BuildContext context,
  WalletDetailLoaded state,
) async {
  final walletPath = state.walletInfo.walletPath;
  final walletName = state.walletInfo.name;
  final service = context.read<WalletService>();
  final deviceKey = await service.getOrCreateEncryptionKey();
  final openPassword = service.getCachedPassword(walletPath);

  if (!context.mounted) return;

  final opts = await showExportBackupDialog(context);
  if (opts == null || !context.mounted) return;

  final List<int> backupBytes;
  final backupResult = await guard<List<int>>(
    context,
    () => rust_backup.exportWalletBackup(
      walletPath: walletPath,
      deviceKeyHex: deviceKey,
      openPassword: openPassword,
      exportProtection: opts.protectionType,
      exportPassword: opts.password,
      securityLevel: opts.securityLevel,
    ),
  );
  if (backupResult == null) return;
  backupBytes = backupResult;

  if (!context.mounted) return;

  final safeName = safeFileBase(walletName);
  final fileName = '$safeName.deadbolt';

  if (defaultTargetPlatform == TargetPlatform.android ||
      defaultTargetPlatform == TargetPlatform.iOS) {
    await shareBytes(
      context,
      Uint8List.fromList(backupBytes),
      fileName: fileName,
      mimeType: 'application/octet-stream',
      subject: fileName,
    );
  } else {
    await saveBytes(
      context,
      Uint8List.fromList(backupBytes),
      fileName: fileName,
    );
  }
}

Future<void> exportBedBackup(
  BuildContext context,
  WalletDetailLoaded state,
) async {
  final l10n = context.l10n;

  // The colocation warning must be acknowledged before export — on Android
  // a toast shown right before the native share sheet opens gets hidden
  // behind it, so this has to be a blocking dialog instead.
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Row(
        children: [
          Icon(Icons.info_outline,
              color: Theme.of(ctx).colorScheme.onSurfaceVariant),
          const SizedBox(width: 8),
          Expanded(child: Text(l10n.bedExportWarningTitle)),
        ],
      ),
      content: Text(l10n.bedExportColocationWarning),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx, false),
          child: Text(l10n.cancel),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(ctx, true),
          child: Text(l10n.bedExportWarningContinue),
        ),
      ],
    ),
  );
  if (confirmed != true || !context.mounted) return;

  final walletPath = state.walletInfo.walletPath;
  final walletName = state.walletInfo.name;
  final service = context.read<WalletService>();
  final deviceKey = await service.getOrCreateEncryptionKey();
  final openPassword = service.getCachedPassword(walletPath);

  if (!context.mounted) return;

  final result = await guard(
    context,
    () async => rust_bed.exportBedBackup(
      walletPath: walletPath,
      deviceKeyHex: deviceKey,
      password: openPassword,
    ),
  );
  if (result == null) return;

  if (!context.mounted) return;

  final safeName = safeFileBase(walletName);
  final fileName = '$safeName.bed';
  final backupBytes = Uint8List.fromList(result.backupBytes);

  if (defaultTargetPlatform == TargetPlatform.android ||
      defaultTargetPlatform == TargetPlatform.iOS) {
    await shareBytes(
      context,
      backupBytes,
      fileName: fileName,
      mimeType: 'application/octet-stream',
      subject: fileName,
    );
  } else {
    await saveBytes(context, backupBytes, fileName: fileName);
  }
}
