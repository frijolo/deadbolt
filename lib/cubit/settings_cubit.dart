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

  const AppSettings({
    required this.locale,
    required this.network,
    required this.walletType,
    this.appTheme = AppTheme.system,
    this.electrumMainnet = 'ssl://electrum.blockstream.info:50002',
    this.electrumTestnet = 'ssl://electrum.blockstream.info:60002',
    this.electrumTestnet4 = 'ssl://electrum.blockstream.info:60002',
    this.electrumSignet = 'ssl://mempool.space:60602',
    this.electrumRegtest = 'tcp://localhost:60401',
    this.explorerMainnet = 'https://mempool.space',
    this.explorerTestnet = 'https://mempool.space/testnet',
    this.explorerTestnet4 = 'https://mempool.space/testnet4',
    this.explorerSignet = 'https://mempool.space/signet',
    this.explorerRegtest = '',
    this.minFeeRate = 0.1,
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
    final base = switch (net) {
      APINetwork.bitcoin => explorerMainnet,
      APINetwork.testnet => explorerTestnet,
      APINetwork.testnet4 => explorerTestnet4,
      APINetwork.signet => explorerSignet,
      APINetwork.regtest => explorerRegtest,
    };
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
      minFeeRate:
          prefs.getDouble(_minFeeRateKey) ?? defaults.minFeeRate,
    ));
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
}
