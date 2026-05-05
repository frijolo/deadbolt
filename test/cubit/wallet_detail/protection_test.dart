import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import 'package:deadbolt/cubit/wallet_detail_cubit.dart';
import 'package:deadbolt/cubit/wallet_op_result.dart';
import 'package:deadbolt/services/wallet_sync_service.dart';
import 'package:deadbolt/src/rust/api/model.dart';

import '_helpers.dart';

void main() {
  setUpAll(registerCommonFallbacks);

  late MockWalletOpener opener;
  late MockWalletSyncService sync;
  late MockLoadedWallet wallet;
  late StreamController<WalletSyncEvent> events;

  setUp(() {
    opener = MockWalletOpener();
    sync = MockWalletSyncService();
    wallet = MockLoadedWallet();
    events = StreamController<WalletSyncEvent>.broadcast();
    when(() => sync.events).thenAnswer((_) => events.stream);
    stubLoadedDefaults(wallet);
  });

  tearDown(() => events.close());

  test('enableBiometricSlot happy: hasBiometricSlot=true reflected in state', () async {
    final cubit = await loadCubit(opener: opener, sync: sync, wallet: wallet);
    when(() => opener.enableBiometricSlot(
          walletPath: any(named: 'walletPath'),
          promptInfo: any(named: 'promptInfo'),
        )).thenAnswer((_) async => const Ok(true));

    final r = await cubit.enableBiometricSlot(walletPath, FakePromptInfo());
    expect(r, isTrue);
    expect((cubit.state as WalletDetailLoaded).hasBiometricSlot, isTrue);
    await cubit.close();
  });

  test('enableBiometricSlot error: emits errorMessage and returns false', () async {
    final cubit = await loadCubit(opener: opener, sync: sync, wallet: wallet);
    when(() => opener.enableBiometricSlot(
          walletPath: any(named: 'walletPath'),
          promptInfo: any(named: 'promptInfo'),
        )).thenAnswer((_) async => const Err('user cancelled'));

    final r = await cubit.enableBiometricSlot(walletPath, FakePromptInfo());
    expect(r, isFalse);
    expect((cubit.state as WalletDetailLoaded).errorMessage, contains('user cancelled'));
    await cubit.close();
  });

  test('changeProtection happy: updates protection in walletInfo', () async {
    final cubit = await loadCubit(opener: opener, sync: sync, wallet: wallet);
    when(() => opener.changeProtection(
          walletPath: any(named: 'walletPath'),
          handle: any(named: 'handle'),
          newProtectionType: any(named: 'newProtectionType'),
          newPassword: any(named: 'newPassword'),
          securityLevel: any(named: 'securityLevel'),
          xpubKeys: any(named: 'xpubKeys'),
        )).thenAnswer((_) async => const Ok(APIWalletProtection(
              protectionType: APIProtectionType.userPassword,
              needsPassword: true,
              securityLevel: APISecurityLevel.standard,
            )));

    final r = await cubit.changeProtection(
      newProtectionType: APIProtectionType.userPassword,
      newPassword: 'pw',
    );
    expect(r, isTrue);
    expect((cubit.state as WalletDetailLoaded).walletInfo.protection.protectionType,
        APIProtectionType.userPassword);
    await cubit.close();
  });

  test('changeProtection error: returns false and emits errorMessage', () async {
    final cubit = await loadCubit(opener: opener, sync: sync, wallet: wallet);
    when(() => opener.changeProtection(
          walletPath: any(named: 'walletPath'),
          handle: any(named: 'handle'),
          newProtectionType: any(named: 'newProtectionType'),
          newPassword: any(named: 'newPassword'),
          securityLevel: any(named: 'securityLevel'),
          xpubKeys: any(named: 'xpubKeys'),
        )).thenAnswer((_) async => const Err('keystore unavailable'));

    final r = await cubit.changeProtection(newProtectionType: APIProtectionType.deviceKey);
    expect(r, isFalse);
    expect((cubit.state as WalletDetailLoaded).errorMessage, contains('keystore unavailable'));
    await cubit.close();
  });
}
