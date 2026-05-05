import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:file_picker/file_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;
import 'package:share_plus/share_plus.dart' show ShareParams, SharePlus, XFile;

import 'package:deadbolt/l10n/l10n.dart';
import 'package:deadbolt/cubit/wallet_detail_cubit.dart';
import 'package:deadbolt/utils/toast_helper.dart';
import 'package:deadbolt/widgets/text_export_sheet.dart' show showTextExportSheet;
import 'package:deadbolt/screens/export_backup_dialog.dart' show showExportBackupDialog;
import 'package:deadbolt/utils/export_sheet.dart' show showDescriptorExportSheet;
import 'package:deadbolt/services/wallet_service.dart';
import 'package:deadbolt/src/rust/api/wallet/backup.dart' as rust_backup;

enum ExportChoice { labels, descriptor, wallet, nostr }

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
            leading: const Icon(Icons.save_alt_outlined),
            title: Text(l10n.walletExportLabel),
            onTap: () => Navigator.of(ctx).pop(ExportChoice.wallet),
          ),
          ListTile(
            leading: const Icon(Icons.backup_outlined),
            title: Text(l10n.publishBackupMenu),
            onTap: () => Navigator.of(ctx).pop(ExportChoice.nostr),
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
  final safeName = state.walletInfo.name
      .replaceAll(RegExp(r'[^\w\-]'), '_')
      .toLowerCase();
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
  final safeName = state.walletInfo.name
      .replaceAll(RegExp(r'[^\w\-]'), '_')
      .toLowerCase();
  await showDescriptorExportSheet(
    context,
    descriptor: state.walletInfo.descriptor,
    fileName: '${safeName}_descriptor',
    copiedMessage: l10n.copiedToClipboard,
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
  try {
    backupBytes = await rust_backup.exportWalletBackup(
      walletPath: walletPath,
      deviceKeyHex: deviceKey,
      openPassword: openPassword,
      exportProtection: opts.protectionType,
      exportPassword: opts.password,
      securityLevel: opts.securityLevel,
    );
  } catch (e) {
    if (context.mounted) showErrorToastException(e);
    return;
  }

  if (!context.mounted) return;

  final safeName = walletName.replaceAll(RegExp(r'[^a-zA-Z0-9_-]'), '_');
  final fileName = '$safeName.deadbolt';

  if (defaultTargetPlatform == TargetPlatform.android ||
      defaultTargetPlatform == TargetPlatform.iOS) {
    try {
      final tempDir = await getTemporaryDirectory();
      final file = File(p.join(tempDir.path, fileName));
      await file.writeAsBytes(backupBytes);
      if (context.mounted) {
        await SharePlus.instance.share(
          ShareParams(
            files: [XFile(file.path, mimeType: 'application/octet-stream')],
            subject: fileName,
          ),
        );
      }
    } catch (e) {
      if (context.mounted) showErrorToastException(e);
    }
  } else {
    try {
      final savedPath = await FilePicker.platform.saveFile(
        fileName: fileName,
        type: FileType.any,
        bytes: Uint8List.fromList(backupBytes),
      );
      if (savedPath == null) return;
      await File(savedPath).writeAsBytes(backupBytes);
      if (context.mounted) showSuccessToast(context.l10n.backupSaved);
    } catch (e) {
      if (context.mounted) showErrorToastException(e);
    }
  }
}
