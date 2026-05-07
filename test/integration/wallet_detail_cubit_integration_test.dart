/// Integration tests for [WalletDetailCubit] wired to real [WalletOpener] /
/// [WalletService] / [WalletSession] over a synthetic wallet on disk.
///
/// Validates the FRB seam end-to-end without electrum: opener resolves
/// credentials against a real Rust handle, cubit transitions through
/// Loading → Loaded / NeedsPassword as expected, and close() tears down
/// pending timers / subscriptions cleanly.
@Tags(['integration'])
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';

import 'package:deadbolt/cubit/wallet_detail_cubit.dart';
import 'package:deadbolt/services/wallet_service.dart';
import 'package:deadbolt/services/wallet_sync_service.dart';
import 'package:deadbolt/src/rust/api/model.dart';
import 'package:deadbolt/src/rust/frb_generated.dart';

const _mainnetDescriptor =
    'wsh(sortedmulti(2,'
    '[c449c5c5/48h/0h/0h/2h]'
    'xpub6Dtni7dearhzvCuQ3aZYC5VkDEnpjJjoCSJRxs2m6D63r1KzvgvAvQKypzqFpSZ2uaYfNx8HSgi63jcK4ZFgFCTVph1MTMZxP55L1am1Csn/<0;1>/*,'
    '[c61af686/48h/0h/0h/2h]'
    'xpub6EDTxSWtzPTBiQtxScLWm1sJ6By9QPrG6J5RvA3ZuKYHP1mfvyeyTG2Gy3CgnQ2ps5p6cgGTvuULfxuqQtSAvkVp9VyASus6pMFoe8mztCj/<0;1>/*'
    '))#0wct5td0';

class _FakePathProvider extends PathProviderPlatform with MockPlatformInterfaceMixin {
  String supportPath;
  _FakePathProvider(this.supportPath);

  @override
  Future<String?> getApplicationSupportPath() async => supportPath;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    if (!RustLib.instance.initialized) {
      await RustLib.init();
    }
  });

  late Directory tempDir;
  late WalletService service;
  late WalletSyncService syncService;
  late WalletDetailCubit cubit;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('wallet_detail_int_');
    PathProviderPlatform.instance = _FakePathProvider(tempDir.path);
    service = WalletService();
    syncService = WalletSyncService(service);
    cubit = WalletDetailCubit.create(service: service, syncService: syncService);
  });

  tearDown(() async {
    await cubit.close();
    syncService.dispose();
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  Future<APIWalletInfo> createDeviceKeyWallet() => service.createWallet(
        name: 'Detail Test',
        descriptor: _mainnetDescriptor,
        network: APINetwork.bitcoin,
        protectionType: APIProtectionType.deviceKey,
        securityLevel: APISecurityLevel.standard,
      );

  Future<APIWalletInfo> createPasswordWallet(String password) => service.createWallet(
        name: 'Password Detail Test',
        descriptor: _mainnetDescriptor,
        network: APINetwork.bitcoin,
        protectionType: APIProtectionType.userPassword,
        password: password,
        securityLevel: APISecurityLevel.standard,
      );

  test('load() on a DeviceKey wallet transitions Loading → Loaded with '
      'walletHandle and initial snapshot populated', () async {
    final info = await createDeviceKeyWallet();

    final states = <Type>[];
    final sub = cubit.stream.listen((s) => states.add(s.runtimeType));

    await cubit.load(info.walletPath);

    // Drain microtasks (descriptor analysis fires unawaited from load()).
    await Future<void>.delayed(Duration.zero);

    expect(states.first, WalletDetailLoading);
    expect(states.last, WalletDetailLoaded);

    final loaded = cubit.state as WalletDetailLoaded;
    expect(loaded.walletInfo.walletPath, info.walletPath);
    expect(loaded.walletInfo.name, 'Detail Test');
    expect(loaded.balance.confirmed, BigInt.zero);
    expect(loaded.utxos, isEmpty);
    expect(loaded.transactions, isEmpty);

    await sub.cancel();
  });

  test('load() with no credential on a UserPassword wallet emits '
      'WalletDetailNeedsPassword (no exception), and a follow-up load() with '
      'the correct password transitions to Loaded', () async {
    const password = 'integration-pw';
    final info = await createPasswordWallet(password);
    // Simulate a fresh-app start: no cached credential.
    service.evictPassword(info.walletPath);

    await cubit.load(info.walletPath);
    expect(cubit.state, isA<WalletDetailNeedsPassword>());
    final needs = cubit.state as WalletDetailNeedsPassword;
    expect(needs.walletPath, info.walletPath);
    expect(needs.isXpubKey, isFalse);

    await cubit.load(info.walletPath, password: password);
    expect(cubit.state, isA<WalletDetailLoaded>());
    expect((cubit.state as WalletDetailLoaded).walletInfo.name,
        'Password Detail Test');
  });

  test('lockWallet() evicts cached credentials so a subsequent load() with '
      'no password lands on NeedsPassword again', () async {
    const password = 'pw-roundtrip';
    final info = await createPasswordWallet(password);

    await cubit.load(info.walletPath, password: password);
    expect(cubit.state, isA<WalletDetailLoaded>());
    expect(service.getCachedPassword(info.walletPath), password);

    cubit.lockWallet();
    expect(service.getCachedPassword(info.walletPath), isNull);
    expect(syncService.isTracked(info.walletPath), isFalse);

    await cubit.load(info.walletPath);
    expect(cubit.state, isA<WalletDetailNeedsPassword>());
  });

  test('close() releases the cubit cleanly even if load() left an unawaited '
      'descriptor analysis in flight', () async {
    final info = await createDeviceKeyWallet();
    await cubit.load(info.walletPath);
    expect(cubit.isClosed, isFalse);

    await cubit.close();
    expect(cubit.isClosed, isTrue);
  });

  test('sync() on an empty DeviceKey wallet that is not registered with the '
      'sync service is a safe no-op (no exception, no state churn)', () async {
    final info = await createDeviceKeyWallet();
    await cubit.load(info.walletPath);

    final loaded = cubit.state as WalletDetailLoaded;
    final beforeIsSyncing = loaded.isSyncing;

    // Cubit.sync() delegates to syncService.syncWallet(); if the wallet was
    // never registered (no electrum URL configured for tests) it short-circuits.
    cubit.sync();
    await Future<void>.delayed(Duration.zero);

    expect(cubit.state, isA<WalletDetailLoaded>());
    expect((cubit.state as WalletDetailLoaded).isSyncing, beforeIsSyncing);
    expect(syncService.isTracked(info.walletPath), isFalse);
  });
}
