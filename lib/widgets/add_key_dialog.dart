import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'package:deadbolt/cubit/project_detail_cubit.dart';
import 'package:deadbolt/errors.dart';
import 'package:deadbolt/l10n/l10n.dart';
import 'package:deadbolt/screens/qr_scanner_screen.dart';
import 'package:deadbolt/src/rust/api/analyzer.dart';
import 'package:deadbolt/src/rust/api/model.dart';
import 'package:deadbolt/theme/app_theme.dart';

/// Pattern for parsing keyspec format: [mfp/path]xpub
final _keyspecPattern = RegExp(r'^\[([0-9a-fA-F]{8})/([^\]]+)\](.+)$');

void showAddKeyDialog(
  BuildContext context,
  ProjectDetailCubit cubit, {
  void Function(String mfp)? onKeyAdded,
}) {
  final l10n = context.l10n;
  final mfpController = TextEditingController();
  final pathController = TextEditingController();
  final xpubController = TextEditingController();
  final keyspecController = TextEditingController();
  String? errorText;
  bool useSeparateFields = false;

  // Get current state to access existing keys
  final currentState = cubit.state as ProjectDetailLoaded;
  final existingMfps =
      currentState.editedKeys!.map((k) => k.mfp.toLowerCase()).toSet();

  showDialog(
    context: context,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setDialogState) => AlertDialog(
        title: Text(l10n.addKeyDialogTitle),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Mode toggle
              SegmentedButton<bool>(
                segments: [
                  ButtonSegment(
                    value: true,
                    label: Text(l10n.separateFieldsMode),
                    icon: const Icon(Icons.splitscreen, size: 16),
                  ),
                  ButtonSegment(
                    value: false,
                    label: Text(l10n.fullKeyspecMode),
                    icon: const Icon(Icons.code, size: 16),
                  ),
                ],
                selected: {useSeparateFields},
                onSelectionChanged: (Set<bool> newSelection) {
                  setDialogState(() {
                    useSeparateFields = newSelection.first;
                    errorText = null;
                  });
                },
                style: const ButtonStyle(
                  visualDensity: VisualDensity.compact,
                ),
              ),
              const SizedBox(height: 16),

              // Conditional content based on mode
              if (useSeparateFields) ...[
                TextField(
                  controller: mfpController,
                  decoration: InputDecoration(
                    labelText: l10n.mfpLabel,
                    hintText: l10n.mfpHint,
                  ),
                  textCapitalization: TextCapitalization.none,
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: pathController,
                  decoration: InputDecoration(
                    labelText: l10n.derivationPathLabel,
                    hintText: l10n.derivationPathHint,
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: xpubController,
                  decoration: InputDecoration(
                    labelText: l10n.xpubLabel,
                    hintText: l10n.xpubHint,
                  ),
                  maxLines: 2,
                ),
              ] else ...[
                TextField(
                  controller: keyspecController,
                  decoration: InputDecoration(
                    labelText: l10n.fullKeyspecLabel,
                    hintText: l10n.fullKeyspecHint,
                    helperText: l10n.fullKeyspecHelperText,
                    helperMaxLines: 2,
                  ),
                  maxLines: 3,
                  textCapitalization: TextCapitalization.none,
                ),
                const SizedBox(height: 8),
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    if (!kIsWeb)
                      TextButton.icon(
                        icon: const Icon(Icons.qr_code_scanner, size: 16),
                        label: Text(l10n.scanQrCode),
                        style: TextButton.styleFrom(
                          foregroundColor: AppAccent.color,
                          visualDensity: VisualDensity.compact,
                        ),
                        onPressed: () async {
                          final result = await QrScannerScreen.push(ctx);
                          if (result != null) {
                            keyspecController.text = result.trim();
                          }
                        },
                      ),
                    TextButton.icon(
                      icon: const Icon(Icons.folder_open, size: 16),
                      label: Text(l10n.fromFile),
                      style: TextButton.styleFrom(
                        foregroundColor: AppAccent.color,
                        visualDensity: VisualDensity.compact,
                      ),
                      onPressed: () async {
                        final result = await FilePicker.platform.pickFiles(
                          type: FileType.any,
                          withData: true,
                        );
                        if (result == null || result.files.isEmpty) return;
                        final bytes = result.files.first.bytes;
                        if (bytes != null) {
                          keyspecController.text =
                              String.fromCharCodes(bytes).trim();
                        }
                      },
                    ),
                  ],
                ),
              ],

              if (errorText != null)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(
                    errorText!,
                    style: const TextStyle(color: Colors.red, fontSize: 12),
                  ),
                ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(l10n.cancel),
          ),
          TextButton(
            onPressed: () async {
              String mfp;
              String path;
              String xpub;

              if (useSeparateFields) {
                // Separate fields mode
                mfp = mfpController.text.trim().toLowerCase();
                path = pathController.text.trim();
                xpub = xpubController.text.trim();

                if (mfp.isEmpty || path.isEmpty || xpub.isEmpty) {
                  setDialogState(() => errorText = l10n.allFieldsRequired);
                  return;
                }
              } else {
                // Keyspec mode - parse the full keyspec
                final keyspec = keyspecController.text.trim();

                if (keyspec.isEmpty) {
                  setDialogState(() => errorText = l10n.keyspecRequired);
                  return;
                }

                // Parse keyspec format: [mfp/path]xpub
                final match = _keyspecPattern.firstMatch(keyspec);

                if (match == null) {
                  setDialogState(
                      () => errorText = l10n.invalidKeyspecFormat);
                  return;
                }

                mfp = match.group(1)!.toLowerCase();
                path = match.group(2)!;
                xpub = match.group(3)!;
              }

              // Check for duplicate MFP
              if (existingMfps.contains(mfp)) {
                setDialogState(() => errorText = l10n.duplicateMfp(mfp));
                return;
              }

              // Validate key with Rust (format + network compatibility)
              final network =
                  APINetwork.values.byName(currentState.project.network);
              try {
                await validateKey(
                  mfp: mfp,
                  derivationPath: path,
                  xpub: xpub,
                  network: network,
                );
              } catch (e) {
                setDialogState(() => errorText = formatRustError(e));
                return;
              }

              // Check if widget is still mounted before using context
              if (!ctx.mounted) return;

              final newKey = EditableKey(
                mfp: mfp,
                derivationPath: path,
                xpub: xpub,
              );

              await cubit.addKey(newKey);
              if (!ctx.mounted) return;
              onKeyAdded?.call(mfp);
              Navigator.pop(ctx);
            },
            child: Text(l10n.add),
          ),
        ],
      ),
    ),
  );
}
