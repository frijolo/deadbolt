import 'dart:convert';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import 'package:deadbolt/errors.dart';
import 'package:deadbolt/l10n/l10n.dart';
import 'package:deadbolt/src/rust/api/analyzer.dart' show formatDescriptorForLiana;
import 'package:deadbolt/utils/toast_helper.dart';
import 'package:deadbolt/widgets/text_export_sheet.dart';

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
}) async {
  final lianaDescriptor = await formatDescriptorForLiana(descriptor: descriptor);

  String exportText = descriptor;
  if (lianaDescriptor != null && context.mounted) {
    final l10n = context.l10n;
    final useLiana = await showDialog<bool>(
      context: context,
      builder: (ctx) => SimpleDialog(
        title: Text(l10n.exportDescriptorFormatTitle),
        children: [
          SimpleDialogOption(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: ListTile(
              leading: const Icon(Icons.check_circle_outline),
              title: Text(l10n.exportDescriptorStandard),
              subtitle: Text(l10n.exportDescriptorStandardDesc),
            ),
          ),
          SimpleDialogOption(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: ListTile(
              leading: const Icon(Icons.schema_outlined),
              title: Text(l10n.exportDescriptorLiana),
              subtitle: Text(l10n.exportDescriptorLianaDesc),
            ),
          ),
        ],
      ),
    );
    if (useLiana == null || !context.mounted) return;
    if (useLiana) exportText = lianaDescriptor;
  }

  if (!context.mounted) return;
  showTextExportSheet(
    context,
    text: exportText,
    fileName: fileName,
    copiedMessage: copiedMessage,
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
  showModalBottomSheet<void>(
    context: context,
    builder: (ctx) => SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ListTile(
            leading: const Icon(Icons.copy_outlined),
            title: Text(l10n.copyToClipboard),
            onTap: () {
              Navigator.pop(ctx);
              Clipboard.setData(ClipboardData(text: jsonString));
              showSuccessToast(context, l10n.copiedToClipboard);
            },
          ),
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
                try {
                  final savedPath = await FilePicker.platform.saveFile(
                    fileName: fileName,
                    type: FileType.custom,
                    allowedExtensions: ['json'],
                  );
                  if (savedPath == null) return;
                  await File(savedPath).writeAsBytes(utf8.encode(jsonString));
                  if (context.mounted) {
                    showSuccessToast(context, l10n.savedToDownloads);
                  }
                } catch (e) {
                  if (context.mounted) {
                    showErrorToast(context, l10n.exportFailed(formatRustError(e)));
                  }
                }
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
                try {
                  final tempDir = await getTemporaryDirectory();
                  final file = File('${tempDir.path}/$fileName');
                  await file.writeAsString(jsonString);
                  final result = await SharePlus.instance.share(
                    ShareParams(
                      files: [XFile(file.path)],
                      subject: 'Export: $projectName',
                    ),
                  );
                  if (result.status == ShareResultStatus.success) {
                    if (context.mounted) {
                      showSuccessToast(context, l10n.projectExportedSuccess);
                    }
                  }
                } catch (e) {
                  if (context.mounted) {
                    showErrorToast(context, l10n.exportFailed(formatRustError(e)));
                  }
                }
              },
            ),
        ],
      ),
    ),
  );
}
