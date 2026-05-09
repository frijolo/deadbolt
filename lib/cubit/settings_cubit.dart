import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:deadbolt/services/price_service.dart';
import 'package:deadbolt/src/rust/api/model.dart';
import 'package:deadbolt/src/rust/api/tor.dart' as tor_api;
import 'package:deadbolt/theme/app_theme.dart';
import 'package:deadbolt/utils/api_network_extensions.dart';
import 'package:deadbolt/utils/security_channel.dart';

class AppSettings {
  final Locale locale;
  final APINetwork network;
  final APIWalletType walletType;
  final AppTheme appTheme;
  /// Electrum server URLs keyed by network suffix (e.g. 'Mainnet' → url).
  final Map<String, String> electrumUrls;

  /// Explorer base URLs keyed by network suffix (e.g. 'Mainnet' → url).
  final Map<String, String> explorerUrls;
  final double minFeeRate;
  final bool fiatEnabled;
  final String fiatCurrency;
  final PriceProviderType fiatProvider;
  final bool torEnabled;
  final bool screenshotProtection;
  final bool biometricLockEnabled;

  /// Minutes of background time before the app locks. 0 means immediately.
  final int biometricTimeoutMinutes;

  /// Minimum relative timelock (in blocks) for a spend path to be considered
  /// an inheritance path and shown in the inheritance status panel.
  /// Prevents short-timelock Taproot "signing combination" paths from being
  /// misidentified as heir paths.
  final int inheritanceMinTimelockBlocks;

  static const kDefaultElectrumMainnet = 'ssl://electrum.blockstream.info:50002';
  static const kDefaultElectrumTestnet = 'ssl://electrum.blockstream.info:60002';
  static const kDefaultElectrumTestnet4 = 'ssl://electrum.blockstream.info:60002';
  static const kDefaultElectrumSignet = 'ssl://mempool.space:60602';
  static const kDefaultElectrumRegtest = 'tcp://localhost:60401';

  static const kDefaultExplorerMainnet = 'https://mempool.space';
  static const kDefaultExplorerTestnet = 'https://mempool.space/testnet';
  static const kDefaultExplorerTestnet4 = 'https://mempool.space/testnet4';
  static const kDefaultExplorerSignet = 'https://mempool.space/signet';
  static const kDefaultExplorerRegtest = '';

  static String defaultElectrumUrlFor(APINetwork net) =>
      kElectrumDefaults[net.suffix]!;

  static String defaultExplorerUrlFor(APINetwork net) =>
      kExplorerDefaults[net.suffix]!;

  /// Default Electrum server URLs keyed by network suffix.
  static const Map<String, String> kElectrumDefaults = {
    'Mainnet': kDefaultElectrumMainnet,
    'Testnet': kDefaultElectrumTestnet,
    'Testnet4': kDefaultElectrumTestnet4,
    'Signet': kDefaultElectrumSignet,
    'Regtest': kDefaultElectrumRegtest,
  };

  /// Default explorer base URLs keyed by network suffix.
  static const Map<String, String> kExplorerDefaults = {
    'Mainnet': kDefaultExplorerMainnet,
    'Testnet': kDefaultExplorerTestnet,
    'Testnet4': kDefaultExplorerTestnet4,
    'Signet': kDefaultExplorerSignet,
    'Regtest': kDefaultExplorerRegtest,
  };

  static String electrumKeyFor(APINetwork net) => 'electrum${net.suffix}';
  static String explorerKeyFor(APINetwork net) => 'explorer${net.suffix}';

  static const kDefaultInheritanceMinTimelock = 144; // ~1 day

  const AppSettings({
    required this.locale,
    required this.network,
    required this.walletType,
    this.appTheme = AppTheme.system,
    Map<String, String>? electrumUrls,
    Map<String, String>? explorerUrls,
    this.minFeeRate = 0.1,
    this.fiatEnabled = false,
    this.fiatCurrency = 'usd',
    this.fiatProvider = PriceProviderType.coinGecko,
    this.torEnabled = false,
    this.screenshotProtection = true,
    this.biometricLockEnabled = false,
    this.biometricTimeoutMinutes = 1,
    this.inheritanceMinTimelockBlocks = AppSettings.kDefaultInheritanceMinTimelock,
  })  : electrumUrls = electrumUrls ?? kElectrumDefaults,
        explorerUrls = explorerUrls ?? kExplorerDefaults;

  AppSettings copyWithElectrum(APINetwork network, String url) {
    final updated = Map<String, String>.from(electrumUrls);
    updated[network.suffix] = url;
    return copyWith(electrumUrls: updated);
  }

  AppSettings copyWithExplorer(APINetwork network, String url) {
    final updated = Map<String, String>.from(explorerUrls);
    updated[network.suffix] = url;
    return copyWith(explorerUrls: updated);
  }

  AppSettings copyWith({
    Locale? locale,
    APINetwork? network,
    APIWalletType? walletType,
    AppTheme? appTheme,
    Map<String, String>? electrumUrls,
    Map<String, String>? explorerUrls,
    double? minFeeRate,
    bool? fiatEnabled,
    String? fiatCurrency,
    PriceProviderType? fiatProvider,
    bool? torEnabled,
    bool? screenshotProtection,
    bool? biometricLockEnabled,
    int? biometricTimeoutMinutes,
    int? inheritanceMinTimelockBlocks,
  }) {
    return AppSettings(
      locale: locale ?? this.locale,
      network: network ?? this.network,
      walletType: walletType ?? this.walletType,
      appTheme: appTheme ?? this.appTheme,
      electrumUrls: electrumUrls ?? this.electrumUrls,
      explorerUrls: explorerUrls ?? this.explorerUrls,
      minFeeRate: minFeeRate ?? this.minFeeRate,
      fiatEnabled: fiatEnabled ?? this.fiatEnabled,
      fiatCurrency: fiatCurrency ?? this.fiatCurrency,
      fiatProvider: fiatProvider ?? this.fiatProvider,
      torEnabled: torEnabled ?? this.torEnabled,
      screenshotProtection: screenshotProtection ?? this.screenshotProtection,
      biometricLockEnabled: biometricLockEnabled ?? this.biometricLockEnabled,
      biometricTimeoutMinutes: biometricTimeoutMinutes ?? this.biometricTimeoutMinutes,
      inheritanceMinTimelockBlocks:
          inheritanceMinTimelockBlocks ?? this.inheritanceMinTimelockBlocks,
    );
  }
}

class SettingsCubit extends Cubit<AppSettings> {
  static const _localeKey = 'locale';
  static const _networkKey = 'defaultNetwork';
  static const _walletTypeKey = 'defaultWalletType';
  static const _themeKey = 'appTheme';
  static const _minFeeRateKey = 'minFeeRate';
  static const _fiatEnabledKey = 'fiatEnabled';
  static const _fiatCurrencyKey = 'fiatCurrency';
  static const _fiatProviderKey = 'fiatProvider';
  static const _torEnabledKey = 'torEnabled';
  static const _screenshotProtectionKey = 'screenshotProtection';
  static const biometricLockKey = 'biometricLockEnabled';
  static const _biometricTimeoutKey = 'biometricTimeoutMinutes';
  static const _inheritanceMinTimelockKey = 'inheritanceMinTimelock';

  SharedPreferences? _prefs;

  Future<SharedPreferences> _getPrefs() async =>
      _prefs ??= await SharedPreferences.getInstance();

  static String _electrumKeyFor(APINetwork network) => AppSettings.electrumKeyFor(network);

  static String _explorerKeyFor(APINetwork network) => AppSettings.explorerKeyFor(network);

  SettingsCubit()
      : super(const AppSettings(
          locale: Locale('en'),
          network: APINetwork.testnet,
          walletType: APIWalletType.p2Tr,
        )) {
    _load();
  }

  Future<void> _load() async {
    const defaults = AppSettings(
      locale: Locale('en'),
      network: APINetwork.testnet,
      walletType: APIWalletType.p2Tr,
    );

    final prefs = await _getPrefs();
    final localeCode = prefs.getString(_localeKey) ?? 'en';
    final networkName = prefs.getString(_networkKey) ?? APINetwork.testnet.name;
    final walletTypeName =
        prefs.getString(_walletTypeKey) ?? APIWalletType.p2Tr.name;
    final themeName = prefs.getString(_themeKey) ?? AppTheme.system.name;

    // Build electrum URLs map: persisted values override defaults.
    final electrumUrls = <String, String>{};
    for (final entry in AppSettings.kElectrumDefaults.entries) {
      final key = 'electrum${entry.key}';
      electrumUrls[entry.key] = prefs.getString(key) ?? entry.value;
    }

    // Build explorer URLs map: persisted values override defaults.
    final explorerUrls = <String, String>{};
    for (final entry in AppSettings.kExplorerDefaults.entries) {
      final key = 'explorer${entry.key}';
      explorerUrls[entry.key] = prefs.getString(key) ?? entry.value;
    }

    emit(AppSettings(
      locale: Locale(localeCode),
      network: APINetwork.values.byName(networkName),
      walletType: APIWalletType.values.byName(walletTypeName),
      appTheme: AppTheme.values.byName(themeName),
      electrumUrls: electrumUrls,
      explorerUrls: explorerUrls,
      minFeeRate: prefs.getDouble(_minFeeRateKey) ?? defaults.minFeeRate,
      fiatEnabled: prefs.getBool(_fiatEnabledKey) ?? defaults.fiatEnabled,
      fiatCurrency: prefs.getString(_fiatCurrencyKey) ?? defaults.fiatCurrency,
      fiatProvider: PriceProviderType.values.byName(
          prefs.getString(_fiatProviderKey) ?? defaults.fiatProvider.name),
      torEnabled: prefs.getBool(_torEnabledKey) ?? defaults.torEnabled,
      screenshotProtection:
          prefs.getBool(_screenshotProtectionKey) ?? defaults.screenshotProtection,
      biometricLockEnabled:
          prefs.getBool(biometricLockKey) ?? defaults.biometricLockEnabled,
      biometricTimeoutMinutes:
          prefs.getInt(_biometricTimeoutKey) ?? defaults.biometricTimeoutMinutes,
      inheritanceMinTimelockBlocks:
          prefs.getInt(_inheritanceMinTimelockKey) ??
              defaults.inheritanceMinTimelockBlocks,
    ));

    // Restore Tor state across restarts.
    if (prefs.getBool(_torEnabledKey) ?? false) {
      _applyTorEnabled(true);
    }

    // If the user has screenshot protection disabled, clear the default FLAG_SECURE
    // that MainActivity sets on startup.
    final screenshotEnabled =
        prefs.getBool(_screenshotProtectionKey) ?? true;
    if (!screenshotEnabled) {
      _applyScreenshotProtection(false);
    }
  }

  Future<void> _applyTorEnabled(bool enabled) async {
    final dir = await getApplicationSupportDirectory();
    tor_api.setTorDataDir(path: dir.path);
    tor_api.setTorEnabled(enabled: enabled);
    if (enabled) {
      tor_api.startTor();
    } else {
      tor_api.stopTor();
    }
  }

  Future<void> setLocale(Locale locale) async {
    final prefs = await _getPrefs();
    await prefs.setString(_localeKey, locale.languageCode);
    emit(state.copyWith(locale: locale));
  }

  Future<void> setNetwork(APINetwork network) async {
    final prefs = await _getPrefs();
    await prefs.setString(_networkKey, network.name);
    emit(state.copyWith(network: network));
  }

  Future<void> setWalletType(APIWalletType walletType) async {
    final prefs = await _getPrefs();
    await prefs.setString(_walletTypeKey, walletType.name);
    emit(state.copyWith(walletType: walletType));
  }

  Future<void> setAppTheme(AppTheme appTheme) async {
    final prefs = await _getPrefs();
    await prefs.setString(_themeKey, appTheme.name);
    emit(state.copyWith(appTheme: appTheme));
  }

  Future<void> setExplorerUrl(APINetwork network, String url) async {
    final prefs = await _getPrefs();
    await prefs.setString(_explorerKeyFor(network), url);
    emit(state.copyWithExplorer(network, url));
  }

  Future<void> setMinFeeRate(double value) async {
    final prefs = await _getPrefs();
    await prefs.setDouble(_minFeeRateKey, value);
    emit(state.copyWith(minFeeRate: value));
  }

  Future<void> setElectrumUrl(APINetwork network, String url) async {
    final prefs = await _getPrefs();
    await prefs.setString(_electrumKeyFor(network), url);
    emit(state.copyWithElectrum(network, url));
  }

  Future<void> setFiatEnabled(bool enabled) async {
    final prefs = await _getPrefs();
    await prefs.setBool(_fiatEnabledKey, enabled);
    emit(state.copyWith(fiatEnabled: enabled));
  }

  Future<void> setFiatCurrency(String currency) async {
    final prefs = await _getPrefs();
    await prefs.setString(_fiatCurrencyKey, currency);
    emit(state.copyWith(fiatCurrency: currency));
  }

  Future<void> setTorEnabled(bool enabled) async {
    final prefs = await _getPrefs();
    await prefs.setBool(_torEnabledKey, enabled);
    await _applyTorEnabled(enabled);
    emit(state.copyWith(torEnabled: enabled));
  }

  Future<void> setInheritanceMinTimelockBlocks(int value) async {
    final prefs = await _getPrefs();
    await prefs.setInt(_inheritanceMinTimelockKey, value);
    emit(state.copyWith(inheritanceMinTimelockBlocks: value));
  }

  Future<void> _applyScreenshotProtection(bool enabled) async {
    if (!Platform.isAndroid) return;
    await securityChannel.invokeMethod<void>('setScreenshotProtection', enabled);
  }

  Future<void> setScreenshotProtection(bool enabled) async {
    final prefs = await _getPrefs();
    await prefs.setBool(_screenshotProtectionKey, enabled);
    await _applyScreenshotProtection(enabled);
    emit(state.copyWith(screenshotProtection: enabled));
  }

  Future<void> setBiometricLockEnabled(bool enabled) async {
    final prefs = await _getPrefs();
    await prefs.setBool(biometricLockKey, enabled);
    emit(state.copyWith(biometricLockEnabled: enabled));
  }

  Future<void> setBiometricTimeoutMinutes(int minutes) async {
    final prefs = await _getPrefs();
    await prefs.setInt(_biometricTimeoutKey, minutes);
    emit(state.copyWith(biometricTimeoutMinutes: minutes));
  }

  Future<void> setFiatProvider(PriceProviderType provider) async {
    final prefs = await _getPrefs();
    await prefs.setString(_fiatProviderKey, provider.name);
    // If current currency is not supported by new provider, reset to usd
    final supported = currenciesForProvider(provider);
    final newCurrency =
        supported.contains(state.fiatCurrency) ? state.fiatCurrency : 'usd';
    await prefs.setString(_fiatCurrencyKey, newCurrency);
    emit(state.copyWith(fiatProvider: provider, fiatCurrency: newCurrency));
  }
}
