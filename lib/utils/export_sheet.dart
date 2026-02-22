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
import 'package:deadbolt/utils/toast_helper.dart';

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
                  final result = await Share.shareXFiles(
                    [XFile(file.path)],
                    subject: 'Export: $projectName',
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
