import 'dart:convert';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import 'package:deadbolt/errors.dart';
import 'package:deadbolt/l10n/l10n.dart';
import 'package:deadbolt/src/rust/api/analyzer.dart' show formatDescriptorForLiana;
import 'package:deadbolt/utils/toast_helper.dart';
import 'package:deadbolt/widgets/descriptor_tab.dart' show DescriptorDisplay;
import 'package:deadbolt/widgets/dialog_helpers.dart' show SheetHandle, showSheet;
import 'package:deadbolt/widgets/text_export_sheet.dart' show ExportSheetAction, showTextExportSheet, showQrDialog;
import 'package:deadbolt/screens/wallet_detail/dialogs/publish_backup_sheet.dart' show showPublishBackupSheet;
import 'package:deadbolt/cubit/wallet_detail_cubit.dart' show WalletDetailLoaded;

/// Shows the Liana/Standard format dialog when the descriptor has a NUMS
/// unspendable key, then opens the export sheet with the chosen text.
///
/// If the descriptor doesn't require a format choice (not TR with NUMS key),
/// jumps straight to the export sheet.
Future<void> showDescriptorExportSheet(
  BuildContext context, {
  required String descriptor,
  required String fileName,
  required String copiedMessage,
  WalletDetailLoaded? state,
}) async {
  final lianaDescriptor = await formatDescriptorForLiana(descriptor: descriptor);

  String exportText = descriptor;
  if (lianaDescriptor != null && context.mounted) {
    final l10n = context.l10n;
    final useLiana = await showSheet<bool>(context, (ctx) => Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SheetHandle(),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 4),
          child: Text(
            l10n.exportDescriptorFormatTitle,
            style: Theme.of(ctx).textTheme.titleMedium,
          ),
        ),
        ListTile(
          leading: const Icon(Icons.check_circle_outline),
          title: Text(l10n.exportDescriptorStandard),
          subtitle: Text(l10n.exportDescriptorStandardDesc),
          onTap: () => Navigator.pop(ctx, false),
        ),
        ListTile(
          leading: const Icon(Icons.schema_outlined),
          title: Text(l10n.exportDescriptorLiana),
          subtitle: Text(l10n.exportDescriptorLianaDesc),
          onTap: () => Navigator.pop(ctx, true),
        ),
        const SizedBox(height: 8),
      ],
    ));
    if (useLiana == null || !context.mounted) return;
    if (useLiana) exportText = lianaDescriptor;
  }

  if (!context.mounted) return;

  final l10n = context.l10n;
  final extraItems = state != null
      ? [
          (
            icon: Icons.cloud_outlined,
            label: l10n.publishBackupMenu,
            onTap: () => showPublishBackupSheet(context, state: state),
          ),
        ]
      : <ExportSheetAction>[];

  showTextExportSheet(
    context,
    text: exportText,
    fileName: fileName,
    copiedMessage: copiedMessage,
    extraItems: extraItems,
    showAsTextBuilder: (ctx, text) => DescriptorDisplay(
      descriptor: text,
      shrinkWrap: true,
    ),
  );
}

/// Shows a bottom sheet with export options (clipboard, save-as, share).
/// Works the same from the project list and project detail screens.
void showProjectExportSheet(
  BuildContext context, {
  required String jsonString,
  required String fileName,
  required String projectName,
}) {
  final l10n = context.l10n;
  showSheet<void>(context, (ctx) => Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SheetHandle(),
          ListTile(
            leading: const Icon(Icons.qr_code),
            title: Text(l10n.showQrCode),
            onTap: () {
              Navigator.pop(ctx);
              showQrDialog(context, jsonString);
            },
          ),
          if (!kIsWeb &&
              defaultTargetPlatform != TargetPlatform.android &&
              defaultTargetPlatform != TargetPlatform.iOS)
            ListTile(
              leading: const Icon(Icons.download_outlined),
              title: Text(l10n.saveAs),
              onTap: () async {
                Navigator.pop(ctx);
                await saveBytes(context, utf8.encode(jsonString), fileName: fileName, allowedExtensions: ['json']);
              },
            ),
          if (kIsWeb ||
              defaultTargetPlatform == TargetPlatform.android ||
              defaultTargetPlatform == TargetPlatform.iOS)
            ListTile(
              leading: const Icon(Icons.share_outlined),
              title: Text(l10n.shareFile),
              onTap: () async {
                Navigator.pop(ctx);
                await shareBytes(context, utf8.encode(jsonString), fileName: fileName, subject: 'Export: $projectName');
              },
            ),
          const SizedBox(height: 8),
      ],
    ),
  );
}

/// Share [bytes] as a file via the system share sheet.
///
/// Writes [bytes] to a temporary file and calls [SharePlus.share].
/// On failure, shows an error toast if [context] is still mounted.
Future<void> shareBytes(
  BuildContext context,
  Uint8List bytes, {
  required String fileName,
  String? mimeType,
  String? subject,
}) async {
  try {
    final tempDir = await getTemporaryDirectory();
    final file = File('${tempDir.path}/$fileName');
    await file.writeAsBytes(bytes);
    await SharePlus.instance.share(
      ShareParams(
        files: [XFile(file.path, mimeType: mimeType)],
        subject: subject,
      ),
    );
  } catch (e) {
    if (context.mounted) {
      final l10n = context.l10n;
      showErrorToast(l10n.exportFailed(formatRustError(e)));
    }
  }
}

/// Save [bytes] to disk via [FilePicker].
///
/// Returns `true` if the user confirmed a save path, `false` if cancelled.
/// On failure, shows an error toast if [context] is still mounted.
Future<bool> saveBytes(
  BuildContext context,
  Uint8List bytes, {
  required String fileName,
  String? fileType,
  List<String>? allowedExtensions,
}) async {
  try {
    final savedPath = await FilePicker.platform.saveFile(
      fileName: fileName,
      type: fileType != null ? FileType.custom : FileType.any,
      allowedExtensions: allowedExtensions,
      bytes: bytes,
    );
    if (savedPath == null) return false;
    await File(savedPath).writeAsBytes(bytes);
    if (context.mounted) {
      showSuccessToast(context.l10n.backupSaved);
    }
    return true;
  } catch (e) {
    if (context.mounted) {
      showErrorToastException(e);
    }
    return false;
  }
}
