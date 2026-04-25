import 'package:flutter/material.dart';

import 'package:deadbolt/l10n/l10n.dart';
import 'package:deadbolt/utils/toast_helper.dart';

/// A compact icon-only copy button.
///
/// Uses [copyToClipboard] for public data and [copySecretAndScheduleClear]
/// for sensitive key material ([secret] = true).
class CopyIconButton extends StatelessWidget {
  const CopyIconButton({
    super.key,
    required this.text,
    this.secret = false,
    this.successMessage,
    this.size = 16.0,
  });

  final String text;
  final bool secret;

  /// Override the success toast message. Defaults to l10n.copiedToClipboard.
  final String? successMessage;

  final double size;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final msg = successMessage ?? l10n.copiedToClipboard;
    return IconButton(
      icon: Icon(Icons.copy_outlined, size: size),
      tooltip: l10n.copyToClipboard,
      visualDensity: VisualDensity.compact,
      onPressed: () async {
        if (secret) {
          await copySecretAndScheduleClear(text, successMessage: msg);
        } else {
          await copyToClipboard(text, successMessage: msg);
        }
      },
    );
  }
}
