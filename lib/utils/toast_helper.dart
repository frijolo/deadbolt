import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:deadbolt/errors.dart';
import 'package:deadbolt/l10n/l10n.dart';
import 'package:deadbolt/utils/root_scaffold_messenger.dart';

/// Show a success toast (green with check icon)
void showSuccessToast(BuildContext context, String message) {
  rootScaffoldMessengerKey.currentState?.showSnackBar(
    SnackBar(
      content: Row(
        children: [
          const Icon(Icons.check_circle, color: Colors.white, size: 20),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              message,
              style: const TextStyle(color: Colors.white),
            ),
          ),
        ],
      ),
      backgroundColor: Colors.green.shade700,
      duration: const Duration(seconds: 3),
      behavior: SnackBarBehavior.floating,
    ),
  );
}

/// Show an info toast (amber, neutral status)
void showInfoToast(BuildContext context, String message) {
  rootScaffoldMessengerKey.currentState?.showSnackBar(
    SnackBar(
      content: Row(
        children: [
          const Icon(Icons.info_outline, color: Colors.white, size: 20),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              message,
              style: const TextStyle(color: Colors.white),
            ),
          ),
        ],
      ),
      backgroundColor: Colors.amber.shade800,
      duration: const Duration(seconds: 4),
      behavior: SnackBarBehavior.floating,
    ),
  );
}

/// Show error toast + clear it via [clearError] when [errorMessage] is non-null.
/// Intended for BlocListeners that follow the `errorMessage / clearError()` pattern.
void handleTransientError(
  BuildContext context,
  String? errorMessage,
  VoidCallback clearError,
) {
  if (errorMessage != null) {
    showErrorToast(context, errorMessage);
    clearError();
  }
}

/// Show success toast + clear it via [clearSuccess] when [successMessage] is non-null.
void handleTransientSuccess(
  BuildContext context,
  String? successMessage,
  VoidCallback clearSuccess,
) {
  if (successMessage != null) {
    showSuccessToast(context, successMessage);
    clearSuccess();
  }
}

/// Show an error toast for a caught exception. Strips the AnyhowException wrapper
/// automatically via [formatRustError].
void showErrorToastException(BuildContext context, Object e) {
  showErrorToast(context, formatRustError(e));
}

/// Show an error toast (red with copy button)
void showErrorToast(BuildContext context, String message) {
  final copiedLabel = context.l10n.errorCopiedToClipboard;
  rootScaffoldMessengerKey.currentState?.showSnackBar(
    SnackBar(
      content: Row(
        children: [
          const Icon(Icons.error_outline, color: Colors.white, size: 20),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              message,
              style: const TextStyle(color: Colors.white),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.copy, color: Colors.white, size: 18),
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(),
            onPressed: () {
              Clipboard.setData(ClipboardData(text: message));
              rootScaffoldMessengerKey.currentState?.hideCurrentSnackBar();
              showSuccessToast(context, copiedLabel);
            },
          ),
        ],
      ),
      backgroundColor: Colors.red.shade800,
      duration: const Duration(seconds: 5),
      behavior: SnackBarBehavior.floating,
    ),
  );
}
