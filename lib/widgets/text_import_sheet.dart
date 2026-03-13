import 'dart:convert' show base64Decode, base64Encode, utf8;

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:deadbolt/l10n/l10n.dart';
import 'package:deadbolt/screens/qr_scanner_screen.dart';
import 'package:deadbolt/utils/toast_helper.dart';

enum _ImportAction { clipboard, qr, file, text }

/// Shows a bottom sheet with four import options that mirror [showTextExportSheet]:
/// paste from clipboard, scan QR, load from file, and enter text manually.
/// Returns the imported text content, or null if cancelled.
Future<String?> showTextImportSheet(BuildContext context) async {
  final l10n = context.l10n;
  final action = await showModalBottomSheet<_ImportAction>(
    context: context,
    builder: (ctx) => SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ListTile(
            leading: const Icon(Icons.paste_outlined),
            title: Text(l10n.pasteFromClipboard),
            onTap: () => Navigator.pop(ctx, _ImportAction.clipboard),
          ),
          ListTile(
            leading: const Icon(Icons.qr_code_scanner),
            title: Text(l10n.scanQrCode),
            onTap: () => Navigator.pop(ctx, _ImportAction.qr),
          ),
          ListTile(
            leading: const Icon(Icons.file_open_outlined),
            title: Text(l10n.fromFile),
            onTap: () => Navigator.pop(ctx, _ImportAction.file),
          ),
          ListTile(
            leading: const Icon(Icons.edit_note),
            title: Text(l10n.pasteText),
            onTap: () => Navigator.pop(ctx, _ImportAction.text),
          ),
        ],
      ),
    ),
  );
  if (action == null || !context.mounted) return null;
  return switch (action) {
    _ImportAction.clipboard => _fromClipboard(context),
    _ImportAction.qr => _fromQr(context),
    _ImportAction.file => _fromFile(context),
    _ImportAction.text => _fromTextDialog(context),
  };
}

Future<String?> _fromClipboard(BuildContext context) async {
  final data = await Clipboard.getData(Clipboard.kTextPlain);
  final text = data?.text;
  if ((text == null || text.trim().isEmpty) && context.mounted) {
    showErrorToast(context, context.l10n.clipboardEmpty);
    return null;
  }
  return text;
}

Future<String?> _fromQr(BuildContext context) async {
  final scanned = await QrScannerScreen.push(context);
  final trimmed = scanned?.trim();
  return (trimmed == null || trimmed.isEmpty) ? null : trimmed;
}

Future<String?> _fromFile(BuildContext context) async {
  final l10n = context.l10n;
  try {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.any,
      withData: true,
    );
    if (result == null || result.files.isEmpty) return null;
    final bytes = result.files.first.bytes;
    if (bytes == null) {
      if (context.mounted) showErrorToast(context, l10n.couldNotReadFile);
      return null;
    }
    return utf8.decode(bytes, allowMalformed: true);
  } catch (e) {
    if (context.mounted) showErrorToast(context, e.toString());
    return null;
  }
}

Future<String?> _fromTextDialog(BuildContext context) async {
  final l10n = context.l10n;
  final controller = TextEditingController();
  final result = await showDialog<String>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(l10n.pasteText),
      content: TextField(
        controller: controller,
        maxLines: 8,
        autofocus: true,
        decoration: InputDecoration(
          hintText: l10n.pasteTextHint,
          border: const OutlineInputBorder(),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx),
          child: Text(l10n.cancel),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(ctx, controller.text),
          child: Text(l10n.importAction),
        ),
      ],
    ),
  );
  controller.dispose();
  final trimmed = result?.trim();
  return (trimmed == null || trimmed.isEmpty) ? null : trimmed;
}

/// Like [showTextImportSheet] but file reading is binary-aware:
/// UTF-8/base64 text PSBTs are returned as-is; binary PSBTs are base64-encoded.
/// Returns a base64 PSBT string, or null if cancelled / error.
Future<String?> showPsbtImportSheet(BuildContext context) async {
  final l10n = context.l10n;
  final action = await showModalBottomSheet<_ImportAction>(
    context: context,
    builder: (ctx) => SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ListTile(
            leading: const Icon(Icons.paste_outlined),
            title: Text(l10n.pasteFromClipboard),
            onTap: () => Navigator.pop(ctx, _ImportAction.clipboard),
          ),
          ListTile(
            leading: const Icon(Icons.qr_code_scanner),
            title: Text(l10n.scanQrCode),
            onTap: () => Navigator.pop(ctx, _ImportAction.qr),
          ),
          ListTile(
            leading: const Icon(Icons.file_open_outlined),
            title: Text(l10n.fromFile),
            onTap: () => Navigator.pop(ctx, _ImportAction.file),
          ),
          ListTile(
            leading: const Icon(Icons.edit_note),
            title: Text(l10n.pasteText),
            onTap: () => Navigator.pop(ctx, _ImportAction.text),
          ),
        ],
      ),
    ),
  );
  if (action == null || !context.mounted) return null;
  return switch (action) {
    _ImportAction.clipboard => _fromClipboard(context),
    _ImportAction.qr => _fromQr(context),
    _ImportAction.file => _psbtFromFile(context),
    _ImportAction.text => _fromTextDialog(context),
  };
}

/// Reads a file and returns its content as a base64 PSBT string.
/// Handles both text (base64) and binary PSBT formats.
Future<String?> _psbtFromFile(BuildContext context) async {
  final l10n = context.l10n;
  try {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.any,
      withData: true,
    );
    if (result == null || result.files.isEmpty) return null;
    final bytes = result.files.first.bytes;
    if (bytes == null) {
      if (context.mounted) showErrorToast(context, l10n.couldNotReadFile);
      return null;
    }
    // Try UTF-8 + valid base64 first (text PSBT); fall back to raw bytes → base64.
    try {
      final text = utf8.decode(bytes).trim();
      base64Decode(text); // throws if not valid base64
      return text;
    } catch (_) {
      return base64Encode(bytes);
    }
  } catch (e) {
    if (context.mounted) showErrorToast(context, e.toString());
    return null;
  }
}
