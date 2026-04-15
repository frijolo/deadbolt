import 'package:flutter/widgets.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:deadbolt/cubit/settings_cubit.dart';

/// Manages the app-level biometric lock state (locked / unlocked).
///
/// State is [bool]: true = locked, false = unlocked.
///
/// The cubit registers itself as a [WidgetsBindingObserver] to detect
/// app lifecycle transitions and lock the app after the configured timeout.
class BiometricLockCubit extends Cubit<bool> with WidgetsBindingObserver {
  final SettingsCubit _settings;
  DateTime? _pausedAt;

  BiometricLockCubit(this._settings) : super(false) {
    WidgetsBinding.instance.addObserver(this);
    _lockOnColdStart();
  }

  /// Reads SharedPreferences directly so we don't race against
  /// SettingsCubit's async _load().
  Future<void> _lockOnColdStart() async {
    final prefs = await SharedPreferences.getInstance();
    if (prefs.getBool('biometricLockEnabled') ?? false) emit(true);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    switch (state) {
      case AppLifecycleState.paused:
      case AppLifecycleState.hidden:
        _pausedAt = DateTime.now();
      case AppLifecycleState.resumed:
        _checkTimeout();
      default:
    }
  }

  void _checkTimeout() {
    if (!_settings.state.biometricLockEnabled) return;
    if (_pausedAt == null) return;
    final elapsed = DateTime.now().difference(_pausedAt!);
    final timeout = Duration(minutes: _settings.state.biometricTimeoutMinutes);
    if (elapsed >= timeout) emit(true);
    _pausedAt = null;
  }

  void unlock() => emit(false);

  @override
  Future<void> close() {
    WidgetsBinding.instance.removeObserver(this);
    return super.close();
  }
}
