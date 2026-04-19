import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:deadbolt/cubit/settings_cubit.dart';
import 'package:deadbolt/services/wallet_service.dart';
import 'package:deadbolt/utils/toast_helper.dart' show cancelSecretClipboard;

/// Manages the app-level biometric lock state (locked / unlocked).
///
/// State is [bool]: true = locked, false = unlocked.
///
/// The cubit registers itself as a [WidgetsBindingObserver] to detect
/// app lifecycle transitions and lock the app after the configured timeout.
/// It also runs an inactivity timer that locks the app if no user interaction
/// is detected within [AppSettings.biometricTimeoutMinutes] minutes.
class BiometricLockCubit extends Cubit<bool> with WidgetsBindingObserver {
  final SettingsCubit _settings;
  final WalletService _walletService;
  DateTime? _pausedAt;
  Timer? _inactivityTimer;

  BiometricLockCubit(this._settings, this._walletService) : super(false) {
    WidgetsBinding.instance.addObserver(this);
    _lockOnColdStart();
  }

  /// Reads SharedPreferences directly so we don't race against
  /// SettingsCubit's async _load().
  Future<void> _lockOnColdStart() async {
    final prefs = await SharedPreferences.getInstance();
    if (prefs.getBool(SettingsCubit.biometricLockKey) ?? false) {
      _lock();
    } else {
      _scheduleInactivityTimer();
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    switch (state) {
      case AppLifecycleState.paused:
      case AppLifecycleState.hidden:
        _pausedAt = DateTime.now();
        _cancelInactivityTimer();
      case AppLifecycleState.resumed:
        _checkBackgroundTimeout();
        if (!this.state) _scheduleInactivityTimer();
      default:
    }
  }

  void _checkBackgroundTimeout() {
    if (!_settings.state.biometricLockEnabled) return;
    if (_pausedAt == null) return;
    final elapsed = DateTime.now().difference(_pausedAt!);
    final timeout = Duration(minutes: _settings.state.biometricTimeoutMinutes);
    if (elapsed >= timeout) _lock();
    _pausedAt = null;
  }

  void _lock() {
    _cancelInactivityTimer();
    _walletService.clearAllCredentials();
    cancelSecretClipboard();
    emit(true);
  }

  void _scheduleInactivityTimer() {
    if (!_settings.state.biometricLockEnabled) return;
    final minutes = _settings.state.biometricTimeoutMinutes;
    if (minutes <= 0) return;
    _cancelInactivityTimer();
    _inactivityTimer = Timer(Duration(minutes: minutes), _lock);
  }

  void _cancelInactivityTimer() {
    _inactivityTimer?.cancel();
    _inactivityTimer = null;
  }

  /// Called on any user interaction. Resets the inactivity timer.
  void resetInactivityTimer() {
    if (!_settings.state.biometricLockEnabled) return;
    if (state) return;
    _scheduleInactivityTimer();
  }

  void unlock() {
    emit(false);
    _scheduleInactivityTimer();
  }

  @override
  Future<void> close() {
    _cancelInactivityTimer();
    WidgetsBinding.instance.removeObserver(this);
    return super.close();
  }
}
