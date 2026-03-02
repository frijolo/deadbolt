import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:bloc_test/bloc_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:deadbolt/cubit/settings_cubit.dart';
import 'package:deadbolt/src/rust/api/model.dart';
import 'package:deadbolt/theme/app_theme.dart';

void main() {
  group('SettingsCubit', () {
    setUp(() {
      SharedPreferences.setMockInitialValues({});
    });

    test('initial state has sensible defaults', () {
      final cubit = SettingsCubit();
      addTearDown(cubit.close);

      expect(cubit.state.locale, const Locale('en'));
      expect(cubit.state.network, APINetwork.testnet);
      expect(cubit.state.walletType, APIWalletType.p2Tr);
      expect(cubit.state.appTheme, AppTheme.system);
    });

    blocTest<SettingsCubit, AppSettings>(
      'setLocale emits updated locale',
      setUp: () => SharedPreferences.setMockInitialValues({}),
      build: SettingsCubit.new,
      act: (cubit) => cubit.setLocale(const Locale('es')),
      // First emission is _load(), second is setLocale
      expect: () => [
        isA<AppSettings>(),
        isA<AppSettings>().having((s) => s.locale, 'locale', const Locale('es')),
      ],
    );

    blocTest<SettingsCubit, AppSettings>(
      'setNetwork emits updated network',
      setUp: () => SharedPreferences.setMockInitialValues({}),
      build: SettingsCubit.new,
      act: (cubit) => cubit.setNetwork(APINetwork.bitcoin),
      expect: () => [
        isA<AppSettings>(),
        isA<AppSettings>()
            .having((s) => s.network, 'network', APINetwork.bitcoin),
      ],
    );

    blocTest<SettingsCubit, AppSettings>(
      'setWalletType emits updated wallet type',
      setUp: () => SharedPreferences.setMockInitialValues({}),
      build: SettingsCubit.new,
      act: (cubit) => cubit.setWalletType(APIWalletType.p2Wsh),
      expect: () => [
        isA<AppSettings>(),
        isA<AppSettings>()
            .having((s) => s.walletType, 'walletType', APIWalletType.p2Wsh),
      ],
    );

    blocTest<SettingsCubit, AppSettings>(
      'setAppTheme emits updated theme',
      setUp: () => SharedPreferences.setMockInitialValues({}),
      build: SettingsCubit.new,
      act: (cubit) => cubit.setAppTheme(AppTheme.dark),
      expect: () => [
        isA<AppSettings>(),
        isA<AppSettings>()
            .having((s) => s.appTheme, 'appTheme', AppTheme.dark),
      ],
    );

    blocTest<SettingsCubit, AppSettings>(
      'loads persisted values from SharedPreferences',
      setUp: () => SharedPreferences.setMockInitialValues({
        'locale': 'es',
        'defaultNetwork': 'bitcoin',
        'defaultWalletType': 'p2Wsh',
        'appTheme': 'light',
      }),
      build: SettingsCubit.new,
      expect: () => [
        isA<AppSettings>()
            .having((s) => s.locale, 'locale', const Locale('es'))
            .having((s) => s.network, 'network', APINetwork.bitcoin)
            .having((s) => s.walletType, 'walletType', APIWalletType.p2Wsh)
            .having((s) => s.appTheme, 'appTheme', AppTheme.light),
      ],
    );

    test('setLocale persists to SharedPreferences', () async {
      SharedPreferences.setMockInitialValues({});
      final cubit = SettingsCubit();
      addTearDown(cubit.close);

      await cubit.setLocale(const Locale('de'));

      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('locale'), 'de');
    });
  });
}
