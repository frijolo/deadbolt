import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:deadbolt/src/rust/api/model.dart';
import 'package:deadbolt/theme/app_theme.dart';

class AppSettings {
  final Locale locale;
  final APINetwork network;
  final APIWalletType walletType;
  final AppTheme appTheme;

  const AppSettings({
    required this.locale,
    required this.network,
    required this.walletType,
    this.appTheme = AppTheme.system,
  });
}

class SettingsCubit extends Cubit<AppSettings> {
  static const _localeKey = 'locale';
  static const _networkKey = 'defaultNetwork';
  static const _walletTypeKey = 'defaultWalletType';
  static const _themeKey = 'appTheme';

  SettingsCubit()
      : super(const AppSettings(
          locale: Locale('en'),
          network: APINetwork.testnet,
          walletType: APIWalletType.p2Tr,
        )) {
    _load();
  }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    final localeCode = prefs.getString(_localeKey) ?? 'en';
    final networkName = prefs.getString(_networkKey) ?? APINetwork.testnet.name;
    final walletTypeName =
        prefs.getString(_walletTypeKey) ?? APIWalletType.p2Tr.name;
    final themeName = prefs.getString(_themeKey) ?? AppTheme.system.name;

    emit(AppSettings(
      locale: Locale(localeCode),
      network: APINetwork.values.byName(networkName),
      walletType: APIWalletType.values.byName(walletTypeName),
      appTheme: AppTheme.values.byName(themeName),
    ));
  }

  Future<void> setLocale(Locale locale) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_localeKey, locale.languageCode);
    emit(AppSettings(
      locale: locale,
      network: state.network,
      walletType: state.walletType,
      appTheme: state.appTheme,
    ));
  }

  Future<void> setNetwork(APINetwork network) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_networkKey, network.name);
    emit(AppSettings(
      locale: state.locale,
      network: network,
      walletType: state.walletType,
      appTheme: state.appTheme,
    ));
  }

  Future<void> setWalletType(APIWalletType walletType) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_walletTypeKey, walletType.name);
    emit(AppSettings(
      locale: state.locale,
      network: state.network,
      walletType: walletType,
      appTheme: state.appTheme,
    ));
  }

  Future<void> setAppTheme(AppTheme appTheme) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_themeKey, appTheme.name);
    emit(AppSettings(
      locale: state.locale,
      network: state.network,
      walletType: state.walletType,
      appTheme: appTheme,
    ));
  }
}
