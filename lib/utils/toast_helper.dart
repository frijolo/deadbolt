import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import 'package:deadbolt/cubit/settings_cubit.dart';
import 'package:deadbolt/errors.dart';
import 'package:deadbolt/l10n/l10n.dart';
import 'package:deadbolt/utils/root_navigator.dart';
import 'package:deadbolt/utils/security_channel.dart';

Timer? _secretClipboardTimer;

/// Returns the clipboard auto-clear duration derived from the biometric lock
/// timeout setting (converted from minutes to seconds). Falls back to 60 s if
/// the lock is disabled or its timeout is zero.
Duration _clipboardClearDuration() {
  final ctx = rootNavigatorKey.currentContext;
  if (ctx != null) {
    final settings = ctx.read<SettingsCubit>().state;
    if (settings.biometricLockEnabled && settings.biometricTimeoutMinutes > 0) {
      return Duration(seconds: settings.biometricTimeoutMinutes * 60);
    }
  }
  return const Duration(seconds: 60);
}

/// Copies [secret] to clipboard, marks it sensitive on Android 13+, shows a
/// success toast with the copy confirmation, then an info toast noting when the
/// clipboard will be auto-cleared. Clears the clipboard after the derived
/// timeout and shows a final info toast.
Future<void> copySecretAndScheduleClear(
  String secret, {
  required String successMessage,
}) async {
  _secretClipboardTimer?.cancel();

  final timeout = _clipboardClearDuration();
  final seconds = timeout.inSeconds;
  final ctx = rootNavigatorKey.currentContext;
  final clearNote = ctx != null ? ' · ${ctx.l10n.clipboardWillClear(seconds)}' : '';

  if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android) {
    try {
      await securityChannel.invokeMethod<void>('setSensitiveClipboard', secret);
    } catch (_) {
      await Clipboard.setData(ClipboardData(text: secret));
    }
  } else {
    await Clipboard.setData(ClipboardData(text: secret));
  }
  showSuccessToast('$successMessage$clearNote');

  _secretClipboardTimer = Timer(timeout, () {
    Clipboard.setData(const ClipboardData(text: ''));
    final clearCtx = rootNavigatorKey.currentContext;
    if (clearCtx != null) {
      showInfoToast(clearCtx.l10n.clipboardCleared);
    }
  });
}

/// Cancels the pending clipboard-clear timer and wipes the clipboard immediately.
/// Call when the app locks so secrets don't linger after lock.
void cancelSecretClipboard() {
  _secretClipboardTimer?.cancel();
  _secretClipboardTimer = null;
  Clipboard.setData(const ClipboardData(text: ''));
}

/// Copies [text] to clipboard and shows [successMessage]. For secrets use [copySecretAndScheduleClear].
Future<void> copyToClipboard(
  String text, {
  required String successMessage,
}) async {
  await Clipboard.setData(ClipboardData(text: text));
  showSuccessToast(successMessage);
}

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
  Offset _drag = Offset.zero;
  bool _dismissed = false;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 250),
    );
    _opacity = CurvedAnimation(parent: _ctrl, curve: Curves.easeOut);
    _ctrl.forward();

    _scheduleDismiss();
  }

  void _scheduleDismiss() {
    _timer?.cancel();
    final fadeDelay = widget.duration - const Duration(milliseconds: 250);
    _timer = Timer(fadeDelay > Duration.zero ? fadeDelay : widget.duration, () {
      if (mounted && !_dismissed) _ctrl.reverse().then((_) => widget.onDismiss());
    });
  }

  void _dismiss() {
    if (_dismissed) return;
    _dismissed = true;
    _timer?.cancel();
    widget.onDismiss();
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
    // viewInsetsOf covers keyboard; paddingOf covers safe area (home indicator,
    // nav bar). When keyboard is open paddingOf.bottom collapses to 0, so the
    // sum is always correct.
    final bottom = MediaQuery.viewInsetsOf(context).bottom +
        MediaQuery.paddingOf(context).bottom +
        16.0;

    return Positioned(
      bottom: bottom,
      left: 16,
      right: 16,
      child: GestureDetector(
        onPanUpdate: (details) {
          setState(() {
            final dx = _drag.dx + details.delta.dx;
            // Horizontal: free movement in both directions.
            // Vertical: only allow downward drag.
            final dy = (_drag.dy + details.delta.dy).clamp(0.0, double.infinity);
            _drag = Offset(dx, dy);
          });
        },
        onPanEnd: (details) {
          final vx = details.velocity.pixelsPerSecond.dx.abs();
          final vy = details.velocity.pixelsPerSecond.dy;
          if (_drag.dx.abs() > 80 || vx > 400 || _drag.dy > 48 || vy > 300) {
            _dismiss();
          } else {
            setState(() => _drag = Offset.zero);
            // Resume auto-dismiss timer on cancelled swipe.
            _scheduleDismiss();
          }
        },
        child: Transform.translate(
          offset: _drag,
          child: FadeTransition(
            opacity: _opacity,
            child: Material(
              color: widget.backgroundColor,
              borderRadius: BorderRadius.circular(4),
              elevation: 6,
              child: Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
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
                        icon: const Icon(Icons.copy,
                            color: Colors.white, size: 18),
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(),
                        onPressed: widget.onCopy,
                      ),
                      const SizedBox(width: 4),
                    ],
                    IconButton(
                      icon: const Icon(Icons.close,
                          color: Colors.white, size: 18),
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(),
                      onPressed: _dismiss,
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
