import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:deadbolt/services/price_service.dart';
import 'package:deadbolt/src/rust/api/model.dart';
import 'package:deadbolt/src/rust/api/tor.dart' as tor_api;
import 'package:deadbolt/theme/app_theme.dart';

class AppSettings {
  final Locale locale;
  final APINetwork network;
  final APIWalletType walletType;
  final AppTheme appTheme;
  final String electrumMainnet;
  final String electrumTestnet;
  final String electrumTestnet4;
  final String electrumSignet;
  final String electrumRegtest;
  final String explorerMainnet;
  final String explorerTestnet;
  final String explorerTestnet4;
  final String explorerSignet;
  final String explorerRegtest;
  final double minFeeRate;
  final bool fiatEnabled;
  final String fiatCurrency;
  final PriceProviderType fiatProvider;
  final bool torEnabled;

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

  static String defaultElectrumUrlFor(APINetwork net) => switch (net) {
        APINetwork.bitcoin => kDefaultElectrumMainnet,
        APINetwork.testnet => kDefaultElectrumTestnet,
        APINetwork.testnet4 => kDefaultElectrumTestnet4,
        APINetwork.signet => kDefaultElectrumSignet,
        APINetwork.regtest => kDefaultElectrumRegtest,
      };

  static String defaultExplorerUrlFor(APINetwork net) => switch (net) {
        APINetwork.bitcoin => kDefaultExplorerMainnet,
        APINetwork.testnet => kDefaultExplorerTestnet,
        APINetwork.testnet4 => kDefaultExplorerTestnet4,
        APINetwork.signet => kDefaultExplorerSignet,
        APINetwork.regtest => kDefaultExplorerRegtest,
      };

  static const kDefaultInheritanceMinTimelock = 144; // ~1 day

  const AppSettings({
    required this.locale,
    required this.network,
    required this.walletType,
    this.appTheme = AppTheme.system,
    this.electrumMainnet = AppSettings.kDefaultElectrumMainnet,
    this.electrumTestnet = AppSettings.kDefaultElectrumTestnet,
    this.electrumTestnet4 = AppSettings.kDefaultElectrumTestnet4,
    this.electrumSignet = AppSettings.kDefaultElectrumSignet,
    this.electrumRegtest = AppSettings.kDefaultElectrumRegtest,
    this.explorerMainnet = AppSettings.kDefaultExplorerMainnet,
    this.explorerTestnet = AppSettings.kDefaultExplorerTestnet,
    this.explorerTestnet4 = AppSettings.kDefaultExplorerTestnet4,
    this.explorerSignet = AppSettings.kDefaultExplorerSignet,
    this.explorerRegtest = AppSettings.kDefaultExplorerRegtest,
    this.minFeeRate = 0.1,
    this.fiatEnabled = false,
    this.fiatCurrency = 'usd',
    this.fiatProvider = PriceProviderType.coinGecko,
    this.torEnabled = false,
    this.inheritanceMinTimelockBlocks = AppSettings.kDefaultInheritanceMinTimelock,
  });

  String electrumUrlForNetwork(APINetwork net) {
    return switch (net) {
      APINetwork.bitcoin => electrumMainnet,
      APINetwork.testnet => electrumTestnet,
      APINetwork.testnet4 => electrumTestnet4,
      APINetwork.signet => electrumSignet,
      APINetwork.regtest => electrumRegtest,
    };
  }

  String explorerBaseForNetwork(APINetwork net) {
    return switch (net) {
      APINetwork.bitcoin => explorerMainnet,
      APINetwork.testnet => explorerTestnet,
      APINetwork.testnet4 => explorerTestnet4,
      APINetwork.signet => explorerSignet,
      APINetwork.regtest => explorerRegtest,
    };
  }

  String explorerAddressUrl(APINetwork net, String address) {
    final base = explorerBaseForNetwork(net);
    if (base.isEmpty) return '';
    return '$base/address/$address';
  }

  String explorerTxUrl(APINetwork net, String txid) {
    final base = explorerBaseForNetwork(net);
    if (base.isEmpty) return '';
    return '$base/tx/$txid';
  }

  AppSettings copyWithElectrum(APINetwork network, String url) => switch (network) {
    APINetwork.bitcoin => copyWith(electrumMainnet: url),
    APINetwork.testnet => copyWith(electrumTestnet: url),
    APINetwork.testnet4 => copyWith(electrumTestnet4: url),
    APINetwork.signet => copyWith(electrumSignet: url),
    APINetwork.regtest => copyWith(electrumRegtest: url),
  };

  AppSettings copyWithExplorer(APINetwork network, String url) => switch (network) {
    APINetwork.bitcoin => copyWith(explorerMainnet: url),
    APINetwork.testnet => copyWith(explorerTestnet: url),
    APINetwork.testnet4 => copyWith(explorerTestnet4: url),
    APINetwork.signet => copyWith(explorerSignet: url),
    APINetwork.regtest => copyWith(explorerRegtest: url),
  };

  AppSettings copyWith({
    Locale? locale,
    APINetwork? network,
    APIWalletType? walletType,
    AppTheme? appTheme,
    String? electrumMainnet,
    String? electrumTestnet,
    String? electrumTestnet4,
    String? electrumSignet,
    String? electrumRegtest,
    String? explorerMainnet,
    String? explorerTestnet,
    String? explorerTestnet4,
    String? explorerSignet,
    String? explorerRegtest,
    double? minFeeRate,
    bool? fiatEnabled,
    String? fiatCurrency,
    PriceProviderType? fiatProvider,
    bool? torEnabled,
    int? inheritanceMinTimelockBlocks,
  }) {
    return AppSettings(
      locale: locale ?? this.locale,
      network: network ?? this.network,
      walletType: walletType ?? this.walletType,
      appTheme: appTheme ?? this.appTheme,
      electrumMainnet: electrumMainnet ?? this.electrumMainnet,
      electrumTestnet: electrumTestnet ?? this.electrumTestnet,
      electrumTestnet4: electrumTestnet4 ?? this.electrumTestnet4,
      electrumSignet: electrumSignet ?? this.electrumSignet,
      electrumRegtest: electrumRegtest ?? this.electrumRegtest,
      explorerMainnet: explorerMainnet ?? this.explorerMainnet,
      explorerTestnet: explorerTestnet ?? this.explorerTestnet,
      explorerTestnet4: explorerTestnet4 ?? this.explorerTestnet4,
      explorerSignet: explorerSignet ?? this.explorerSignet,
      explorerRegtest: explorerRegtest ?? this.explorerRegtest,
      minFeeRate: minFeeRate ?? this.minFeeRate,
      fiatEnabled: fiatEnabled ?? this.fiatEnabled,
      fiatCurrency: fiatCurrency ?? this.fiatCurrency,
      fiatProvider: fiatProvider ?? this.fiatProvider,
      torEnabled: torEnabled ?? this.torEnabled,
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
  static const _electrumMainnetKey = 'electrumMainnet';
  static const _electrumTestnetKey = 'electrumTestnet';
  static const _electrumTestnet4Key = 'electrumTestnet4';
  static const _electrumSignetKey = 'electrumSignet';
  static const _electrumRegtestKey = 'electrumRegtest';
  static const _explorerMainnetKey = 'explorerMainnet';
  static const _explorerTestnetKey = 'explorerTestnet';
  static const _explorerTestnet4Key = 'explorerTestnet4';
  static const _explorerSignetKey = 'explorerSignet';
  static const _explorerRegtestKey = 'explorerRegtest';
  static const _minFeeRateKey = 'minFeeRate';
  static const _fiatEnabledKey = 'fiatEnabled';
  static const _fiatCurrencyKey = 'fiatCurrency';
  static const _fiatProviderKey = 'fiatProvider';
  static const _torEnabledKey = 'torEnabled';
  static const _inheritanceMinTimelockKey = 'inheritanceMinTimelock';

  SharedPreferences? _prefs;

  Future<SharedPreferences> _getPrefs() async =>
      _prefs ??= await SharedPreferences.getInstance();

  static String _electrumKeyFor(APINetwork network) => switch (network) {
    APINetwork.bitcoin => _electrumMainnetKey,
    APINetwork.testnet => _electrumTestnetKey,
    APINetwork.testnet4 => _electrumTestnet4Key,
    APINetwork.signet => _electrumSignetKey,
    APINetwork.regtest => _electrumRegtestKey,
  };

  static String _explorerKeyFor(APINetwork network) => switch (network) {
    APINetwork.bitcoin => _explorerMainnetKey,
    APINetwork.testnet => _explorerTestnetKey,
    APINetwork.testnet4 => _explorerTestnet4Key,
    APINetwork.signet => _explorerSignetKey,
    APINetwork.regtest => _explorerRegtestKey,
  };

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

    emit(AppSettings(
      locale: Locale(localeCode),
      network: APINetwork.values.byName(networkName),
      walletType: APIWalletType.values.byName(walletTypeName),
      appTheme: AppTheme.values.byName(themeName),
      electrumMainnet:
          prefs.getString(_electrumMainnetKey) ?? defaults.electrumMainnet,
      electrumTestnet:
          prefs.getString(_electrumTestnetKey) ?? defaults.electrumTestnet,
      electrumTestnet4:
          prefs.getString(_electrumTestnet4Key) ?? defaults.electrumTestnet4,
      electrumSignet:
          prefs.getString(_electrumSignetKey) ?? defaults.electrumSignet,
      electrumRegtest:
          prefs.getString(_electrumRegtestKey) ?? defaults.electrumRegtest,
      explorerMainnet:
          prefs.getString(_explorerMainnetKey) ?? defaults.explorerMainnet,
      explorerTestnet:
          prefs.getString(_explorerTestnetKey) ?? defaults.explorerTestnet,
      explorerTestnet4:
          prefs.getString(_explorerTestnet4Key) ?? defaults.explorerTestnet4,
      explorerSignet:
          prefs.getString(_explorerSignetKey) ?? defaults.explorerSignet,
      explorerRegtest:
          prefs.getString(_explorerRegtestKey) ?? defaults.explorerRegtest,
      minFeeRate: prefs.getDouble(_minFeeRateKey) ?? defaults.minFeeRate,
      fiatEnabled: prefs.getBool(_fiatEnabledKey) ?? defaults.fiatEnabled,
      fiatCurrency: prefs.getString(_fiatCurrencyKey) ?? defaults.fiatCurrency,
      fiatProvider: PriceProviderType.values.byName(
          prefs.getString(_fiatProviderKey) ?? defaults.fiatProvider.name),
      torEnabled: prefs.getBool(_torEnabledKey) ?? defaults.torEnabled,
      inheritanceMinTimelockBlocks:
          prefs.getInt(_inheritanceMinTimelockKey) ??
              defaults.inheritanceMinTimelockBlocks,
    ));

    // Restore Tor state across restarts.
    if (prefs.getBool(_torEnabledKey) ?? false) {
      _applyTorEnabled(true);
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
