/// Integration tests for [WalletService] against the real Rust backend.
///
/// Loads `librust_lib_deadbolt.so` (release build) via [RustLib.init] and
/// exercises create/open/delete round-trips on a tempdir, with no electrum.
/// Run as a normal Dart test:
///   flutter test test/integration/wallet_service_integration_test.dart
///
/// Prerequisite: `cargo build --release` (or any prior `flutter build linux`)
/// must have produced `rust/target/release/librust_lib_deadbolt.so`.
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';

import 'package:deadbolt/services/wallet_service.dart';
import 'package:deadbolt/src/rust/api/model.dart';
import 'package:deadbolt/src/rust/api/wallet.dart' as rust_wallet;
import 'package:deadbolt/src/rust/frb_generated.dart';

// Mainnet sortedmulti(2-of-2) descriptor lifted from queries_tests.rs.
// The two xpubs are valid for XpubKey protection (the password slot is one
// of these xpubs).
const _mainnetDescriptor =
    'wsh(sortedmulti(2,'
    '[c449c5c5/48h/0h/0h/2h]'
    'xpub6Dtni7dearhzvCuQ3aZYC5VkDEnpjJjoCSJRxs2m6D63r1KzvgvAvQKypzqFpSZ2uaYfNx8HSgi63jcK4ZFgFCTVph1MTMZxP55L1am1Csn/<0;1>/*,'
    '[c61af686/48h/0h/0h/2h]'
    'xpub6EDTxSWtzPTBiQtxScLWm1sJ6By9QPrG6J5RvA3ZuKYHP1mfvyeyTG2Gy3CgnQ2ps5p6cgGTvuULfxuqQtSAvkVp9VyASus6pMFoe8mztCj/<0;1>/*'
    '))#0wct5td0';

const _xpub1 =
    'xpub6Dtni7dearhzvCuQ3aZYC5VkDEnpjJjoCSJRxs2m6D63r1KzvgvAvQKypzqFpSZ2uaYfNx8HSgi63jcK4ZFgFCTVph1MTMZxP55L1am1Csn';

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

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('wallet_service_int_');
    PathProviderPlatform.instance = _FakePathProvider(tempDir.path);
    service = WalletService();
  });

  tearDown(() async {
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  group('create + open round-trip (real Rust backend)', () {
    test('DeviceKey: create then open with cached device key', () async {
      final info = await service.createWallet(
        name: 'DeviceKey Wallet',
        descriptor: _mainnetDescriptor,
        network: APINetwork.bitcoin,
        protectionType: APIProtectionType.deviceKey,
        securityLevel: APISecurityLevel.standard,
      );

      expect(info.name, 'DeviceKey Wallet');
      expect(info.network, APINetwork.bitcoin);
      expect(File(info.walletPath).existsSync(), isTrue);

      // No password required.
      expect(await service.walletRequiresPassword(info.walletPath), isFalse);
      expect(await service.walletRequiresXpub(info.walletPath), isFalse);

      // Open succeeds without password.
      final handle = await service.openWallet(info.walletPath);
      final fetched = await handle.getInfo();
      expect(fetched.name, 'DeviceKey Wallet');
      expect(fetched.walletPath, info.walletPath);
    });

    test('UserPassword: create with password, walletRequiresPassword true, '
        'open with correct password works, wrong password throws', () async {
      const password = 'correct-horse-battery';
      final info = await service.createWallet(
        name: 'Password Wallet',
        descriptor: _mainnetDescriptor,
        network: APINetwork.bitcoin,
        protectionType: APIProtectionType.userPassword,
        password: password,
        securityLevel: APISecurityLevel.standard,
      );

      expect(await service.walletRequiresPassword(info.walletPath), isTrue);
      expect(await service.walletRequiresXpub(info.walletPath), isFalse);

      // Open with correct password (cached) succeeds.
      final handle = await service.openWallet(info.walletPath, password: password);
      expect((await handle.getInfo()).name, 'Password Wallet');

      // Reopen on a fresh service with WRONG password throws — this is the
      // raw FFI behavior. The seam (WalletOpener.load) wraps this signal as
      // WalletLoadNeedsPassword via walletRequiresPassword, validated above.
      service.evictPassword(info.walletPath);
      final fresh = WalletService();
      await expectLater(
        fresh.openWallet(info.walletPath, password: 'wrong'),
        throwsA(anything),
      );
    });

    test('XpubKey: create with xpub-protection, walletRequiresXpub true, '
        'open with one of the registered xpubs as credential works', () async {
      final info = await service.createWallet(
        name: 'Xpub Wallet',
        descriptor: _mainnetDescriptor,
        network: APINetwork.bitcoin,
        protectionType: APIProtectionType.xpubKey,
        password: _xpub1,
        securityLevel: APISecurityLevel.standard,
      );

      expect(await service.walletRequiresPassword(info.walletPath), isTrue);
      expect(await service.walletRequiresXpub(info.walletPath), isTrue);

      // Network hint is exposed for the seam to populate WalletLoadNeedsPassword.
      final hint = await rust_wallet.getWalletNetworkHint(walletPath: info.walletPath);
      expect(hint, 'bitcoin');

      final handle = await service.openWallet(info.walletPath, password: _xpub1);
      expect((await handle.getInfo()).name, 'Xpub Wallet');
    });

    test('open without any credential on a UserPassword wallet throws — '
        'never silently succeeds', () async {
      final info = await service.createWallet(
        name: 'NeedsCred',
        descriptor: _mainnetDescriptor,
        network: APINetwork.bitcoin,
        protectionType: APIProtectionType.userPassword,
        password: 'pw',
        securityLevel: APISecurityLevel.standard,
      );

      // Fresh service — no cache.
      final fresh = WalletService();
      await expectLater(
        fresh.openWallet(info.walletPath),
        throwsA(anything),
      );
    });

    test('re-create at the same wallets_dir with the same name produces a '
        'distinct file (Rust appends a uuid; previous wallet is preserved)',
        () async {
      final first = await service.createWallet(
        name: 'Dup',
        descriptor: _mainnetDescriptor,
        network: APINetwork.bitcoin,
        protectionType: APIProtectionType.deviceKey,
        securityLevel: APISecurityLevel.standard,
      );
      final second = await service.createWallet(
        name: 'Dup',
        descriptor: _mainnetDescriptor,
        network: APINetwork.bitcoin,
        protectionType: APIProtectionType.deviceKey,
        securityLevel: APISecurityLevel.standard,
      );

      expect(first.walletPath, isNot(second.walletPath));
      expect(File(first.walletPath).existsSync(), isTrue);
      expect(File(second.walletPath).existsSync(), isTrue);

      final list = await service.listWallets();
      final paths = list.map((w) => w.walletPath).toSet();
      expect(paths, containsAll([first.walletPath, second.walletPath]));
    });

    test('delete removes the file; recreate at same dir works and produces '
        'a fresh, openable wallet', () async {
      final original = await service.createWallet(
        name: 'Cycle',
        descriptor: _mainnetDescriptor,
        network: APINetwork.bitcoin,
        protectionType: APIProtectionType.deviceKey,
        securityLevel: APISecurityLevel.standard,
      );
      expect(File(original.walletPath).existsSync(), isTrue);

      await service.deleteWallet(original.walletPath);
      expect(File(original.walletPath).existsSync(), isFalse);

      // listWallets no longer reports the deleted wallet.
      final remaining = await service.listWallets();
      expect(
        remaining.where((w) => w.walletPath == original.walletPath),
        isEmpty,
      );

      final reborn = await service.createWallet(
        name: 'Cycle',
        descriptor: _mainnetDescriptor,
        network: APINetwork.bitcoin,
        protectionType: APIProtectionType.deviceKey,
        securityLevel: APISecurityLevel.standard,
      );
      expect(File(reborn.walletPath).existsSync(), isTrue);

      final handle = await service.openWallet(reborn.walletPath);
      expect((await handle.getInfo()).name, 'Cycle');
    });
  });
}
