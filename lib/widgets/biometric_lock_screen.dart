import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import 'package:deadbolt/cubit/biometric_lock_cubit.dart';
import 'package:deadbolt/l10n/l10n.dart';
import 'package:deadbolt/services/biometric_service.dart';
import 'package:deadbolt/utils/toast_helper.dart';

/// Full-screen lock overlay shown when biometric lock is active.
///
/// Automatically triggers the biometric prompt on mount. The back button
/// is disabled — the user must authenticate to access the app.
class BiometricLockScreen extends StatefulWidget {
  const BiometricLockScreen({super.key});

  @override
  State<BiometricLockScreen> createState() => _BiometricLockScreenState();
}

class _BiometricLockScreenState extends State<BiometricLockScreen> {
  bool _authenticating = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _authenticate());
  }

  Future<void> _authenticate() async {
    if (!mounted) return;

    // If already authenticating, cancel the stuck prompt before retrying.
    // This handles in-display sensors that may silently fail to activate.
    if (_authenticating) {
      final service = context.read<BiometricService>();
      await service.stop();
      if (!mounted) return;
    }

    setState(() => _authenticating = true);

    try {
      final service = context.read<BiometricService>();
      final l10n = context.l10n;
      final success = await service.authenticate(l10n.biometricUnlockReason);

      if (!mounted) return;
      setState(() => _authenticating = false);

      if (success) {
        context.read<BiometricLockCubit>().unlock();
      }
    } catch (e) {
      // Ensure the button is never permanently disabled if the plugin throws.
      if (!mounted) return;
      setState(() => _authenticating = false);
      showErrorToastException(e);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    return PopScope(
      canPop: false,
      child: Scaffold(
        backgroundColor: cs.surface,
        body: SafeArea(
          child: Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  Icons.lock_rounded,
                  size: 72,
                  color: cs.primary,
                ),
                const SizedBox(height: 24),
                Text(
                  'Deadbolt',
                  style: theme.textTheme.headlineMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                    color: cs.onSurface,
                  ),
                ),
                const SizedBox(height: 48),
                // Always enabled: tapping while a prompt is in progress cancels
                // and retries, which unblocks in-display sensor devices where
                // the system prompt may appear but the sensor never activates.
                FilledButton.icon(
                  onPressed: _authenticate,
                  icon: const Icon(Icons.fingerprint),
                  label: Text(l10n.biometricUnlockButton),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
