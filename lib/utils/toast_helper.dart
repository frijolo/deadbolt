import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:deadbolt/errors.dart';
import 'package:deadbolt/l10n/l10n.dart';
import 'package:deadbolt/utils/root_navigator.dart';

/// Show a success toast (green with check icon)
void showSuccessToast(String message) {
  _showOverlayToast(
    message: message,
    backgroundColor: Colors.green.shade700,
    icon: Icons.check_circle,
    duration: const Duration(seconds: 3),
  );
}

/// Show an info toast (amber, neutral status)
void showInfoToast(String message) {
  _showOverlayToast(
    message: message,
    backgroundColor: Colors.amber.shade800,
    icon: Icons.info_outline,
    duration: const Duration(seconds: 4),
  );
}

/// Show error toast + clear it via [clearError] when [errorMessage] is non-null.
/// Intended for BlocListeners that follow the `errorMessage / clearError()` pattern.
void handleTransientError(
  String? errorMessage,
  VoidCallback clearError,
) {
  if (errorMessage != null) {
    showErrorToast(errorMessage);
    clearError();
  }
}

/// Show success toast + clear it via [clearSuccess] when [successMessage] is non-null.
void handleTransientSuccess(
  String? successMessage,
  VoidCallback clearSuccess,
) {
  if (successMessage != null) {
    showSuccessToast(successMessage);
    clearSuccess();
  }
}

/// Show an error toast for a caught exception. Strips the AnyhowException wrapper
/// automatically via [formatRustError].
void showErrorToastException(Object e) {
  showErrorToast(formatRustError(e));
}

/// Show an error toast (red with copy button)
void showErrorToast(String message) {
  final copiedLabel =
      rootNavigatorKey.currentContext?.l10n.errorCopiedToClipboard ?? '';
  _showOverlayToast(
    message: message,
    backgroundColor: Colors.red.shade800,
    icon: Icons.error_outline,
    duration: const Duration(seconds: 5),
    onCopy: copiedLabel.isNotEmpty
        ? () {
            Clipboard.setData(ClipboardData(text: message));
            showSuccessToast(copiedLabel);
          }
        : null,
  );
}

void _showOverlayToast({
  required String message,
  required Color backgroundColor,
  required IconData icon,
  required Duration duration,
  VoidCallback? onCopy,
}) {
  final overlay = rootNavigatorKey.currentState?.overlay;
  if (overlay == null) return;

  late OverlayEntry entry;

  void dismiss() {
    if (entry.mounted) entry.remove();
  }

  entry = OverlayEntry(
    builder: (_) => _ToastOverlay(
      message: message,
      backgroundColor: backgroundColor,
      icon: icon,
      duration: duration,
      onDismiss: dismiss,
      onCopy: onCopy != null
          ? () {
              onCopy();
              dismiss();
            }
          : null,
    ),
  );

  overlay.insert(entry);
}

class _ToastOverlay extends StatefulWidget {
  final String message;
  final Color backgroundColor;
  final IconData icon;
  final Duration duration;
  final VoidCallback onDismiss;
  final VoidCallback? onCopy;

  const _ToastOverlay({
    required this.message,
    required this.backgroundColor,
    required this.icon,
    required this.duration,
    required this.onDismiss,
    this.onCopy,
  });

  @override
  State<_ToastOverlay> createState() => _ToastOverlayState();
}

class _ToastOverlayState extends State<_ToastOverlay>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late final CurvedAnimation _opacity;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 250),
    );
    _opacity = CurvedAnimation(parent: _ctrl, curve: Curves.easeOut);
    _ctrl.forward();

    final fadeDelay = widget.duration - const Duration(milliseconds: 250);
    _timer = Timer(fadeDelay > Duration.zero ? fadeDelay : widget.duration, () {
      if (mounted) _ctrl.reverse().then((_) => widget.onDismiss());
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    _opacity.dispose();
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.viewInsetsOf(context).bottom + 16.0;

    return Positioned(
      bottom: bottom,
      left: 16,
      right: 16,
      child: FadeTransition(
        opacity: _opacity,
        child: Material(
          color: widget.backgroundColor,
          borderRadius: BorderRadius.circular(4),
          elevation: 6,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            child: Row(
              children: [
                Icon(widget.icon, color: Colors.white, size: 20),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    widget.message,
                    style: const TextStyle(color: Colors.white),
                  ),
                ),
                if (widget.onCopy != null) ...[
                  IconButton(
                    icon: const Icon(Icons.copy, color: Colors.white, size: 18),
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                    onPressed: widget.onCopy,
                  ),
                  const SizedBox(width: 4),
                ],
                IconButton(
                  icon: const Icon(Icons.close, color: Colors.white, size: 18),
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                  onPressed: widget.onDismiss,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
