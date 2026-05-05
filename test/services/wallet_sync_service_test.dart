import 'dart:async';
import 'dart:ui' show Locale;

import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import 'package:deadbolt/cubit/settings_cubit.dart';
import 'package:deadbolt/services/wallet_service.dart';
import 'package:deadbolt/services/wallet_sync_service.dart';
import 'package:deadbolt/src/rust/api/model.dart';
import 'package:deadbolt/src/rust/api/wallet.dart' show ApiWallet;

class _MockWalletService extends Mock implements WalletService {}

class _MockApiWallet extends Mock implements ApiWallet {}

APIBalance _balance(int sats) => APIBalance(
      confirmed: BigInt.from(sats),
      trustedPending: BigInt.zero,
      untrustedPending: BigInt.zero,
      immature: BigInt.zero,
    );

APIWalletInfo _info({
  required String path,
  int? lastSyncedAt,
  APINetwork network = APINetwork.signet,
}) =>
    APIWalletInfo(
      walletPath: path,
      name: 'w',
      descriptor: 'tr(...)',
      network: network,
      createdAt: 0,
      lastSyncedAt: lastSyncedAt,
      protection: const APIWalletProtection(
        protectionType: APIProtectionType.deviceKey,
        needsPassword: false,
        securityLevel: APISecurityLevel.standard,
      ),
    );

/// Stub the side-effects that `_startTracking` performs on every wallet handle.
/// Returns the StreamController so tests can drive electrum notifications and
/// assert subscription cancellation by checking `hasListener`.
StreamController<bool> _stubHandle(
  _MockApiWallet handle, {
  required APIBalance balance,
  required APIWalletInfo info,
}) {
  final ctrl = StreamController<bool>.broadcast();
  when(() => handle.setElectrumUrl(url: any(named: 'url')))
      .thenReturn(null);
  when(() => handle.getBalance()).thenAnswer((_) async => balance);
  when(() => handle.getInfo()).thenAnswer((_) async => info);
  when(() => handle.startSubscription(
        electrumUrl: any(named: 'electrumUrl'),
      )).thenAnswer((_) => ctrl.stream);
  when(() => handle.sync_(electrumUrl: any(named: 'electrumUrl')))
      .thenAnswer((_) async {});
  return ctrl;
}

int _nowSecs() => DateTime.now().millisecondsSinceEpoch ~/ 1000;

void main() {
  late _MockWalletService walletService;
  late WalletSyncService service;

  const path = '/wallets/w.db';
  const electrumUrl = 'ssl://electrum.example:50002';

  setUp(() {
    walletService = _MockWalletService();
    service = WalletSyncService(walletService);
  });

  tearDown(() {
    // Tests may dispose explicitly; swallow the double-close to keep
    // teardown unconditional.
    try {
      service.dispose();
    } catch (_) {}
  });

  group('registerHandle', () {
    test('emits initial balance, triggers sync, and emits syncing→completed '
        'when wallet has never been synced', () async {
      final handle = _MockApiWallet();
      _stubHandle(
        handle,
        balance: _balance(0),
        info: _info(path: path, lastSyncedAt: null),
      );
      // After sync_, getBalance / getInfo are called again with updated data.
      final events = <WalletSyncEvent>[];
      final sub = service.events.listen(events.add);

      await service.registerHandle(path, handle, electrumUrl);
      // Let the unawaited _syncOne finish.
      await Future<void>.delayed(Duration.zero);
      await Future<void>.delayed(Duration.zero);

      expect(service.isTracked(path), isTrue);
      verify(() => handle.setElectrumUrl(url: electrumUrl)).called(1);
      verify(() => handle.sync_(electrumUrl: electrumUrl)).called(1);

      // initial: isSyncing=false, balance present
      // then syncing=true (no balance), then syncing=false (balance + info)
      expect(events.length, greaterThanOrEqualTo(3));
      expect(events.first.walletPath, path);
      expect(events.first.isSyncing, isFalse);
      expect(events.first.balance, isNotNull);
      expect(events.any((e) => e.isSyncing == true), isTrue);
      expect(events.last.isSyncing, isFalse);
      expect(events.last.walletInfo, isNotNull);

      await sub.cancel();
    });

    test('skips automatic sync when wallet was synced within the last hour',
        () async {
      final handle = _MockApiWallet();
      _stubHandle(
        handle,
        balance: _balance(123),
        info: _info(path: path, lastSyncedAt: _nowSecs() - 60),
      );

      await service.registerHandle(path, handle, electrumUrl);
      // Allow any micro-tasks to flush; sync_ must NOT be called.
      await Future<void>.delayed(Duration.zero);

      verifyNever(() => handle.sync_(electrumUrl: any(named: 'electrumUrl')));
    });

    test('replaces an existing entry: previous subscription is cancelled',
        () async {
      final first = _MockApiWallet();
      final firstCtrl = _stubHandle(
        first,
        balance: _balance(0),
        info: _info(path: path, lastSyncedAt: _nowSecs()),
      );

      await service.registerHandle(path, first, electrumUrl);
      await Future<void>.delayed(Duration.zero);
      expect(firstCtrl.hasListener, isTrue);

      final second = _MockApiWallet();
      _stubHandle(
        second,
        balance: _balance(0),
        info: _info(path: path, lastSyncedAt: _nowSecs()),
      );

      await service.registerHandle(path, second, electrumUrl);
      await Future<void>.delayed(Duration.zero);

      // Cancellation propagates through the broadcast controller.
      expect(firstCtrl.hasListener, isFalse);
    });
  });

  group('syncWallet', () {
    test('emits syncing→completed and calls sync_ exactly once', () async {
      final handle = _MockApiWallet();
      _stubHandle(
        handle,
        balance: _balance(10),
        info: _info(path: path, lastSyncedAt: _nowSecs()),
      );
      await service.registerHandle(path, handle, electrumUrl);
      await Future<void>.delayed(Duration.zero);
      // Drop the initial event; we only care about the explicit sync.
      final events = <WalletSyncEvent>[];
      final sub = service.events.listen(events.add);

      await service.syncWallet(path);
      await Future<void>.delayed(Duration.zero);

      verify(() => handle.sync_(electrumUrl: electrumUrl)).called(1);
      expect(events.first.isSyncing, isTrue);
      expect(events.last.isSyncing, isFalse);
      expect(events.last.walletInfo, isNotNull);
      await sub.cancel();
    });

    test('is a no-op when the same wallet is already syncing', () async {
      final handle = _MockApiWallet();
      _stubHandle(
        handle,
        balance: _balance(0),
        info: _info(path: path, lastSyncedAt: _nowSecs()),
      );
      // Make sync_ block on a completer so we can observe the in-flight state.
      final blocker = Completer<void>();
      when(() => handle.sync_(electrumUrl: any(named: 'electrumUrl')))
          .thenAnswer((_) => blocker.future);

      await service.registerHandle(path, handle, electrumUrl);
      await Future<void>.delayed(Duration.zero);

      final first = service.syncWallet(path);
      // Second call while first is still pending must short-circuit.
      await service.syncWallet(path);
      verify(() => handle.sync_(electrumUrl: electrumUrl)).called(1);

      blocker.complete();
      await first;
      // No additional sync_ call after the first completes.
      verifyNever(() => handle.sync_(electrumUrl: electrumUrl));
    });

    test('emits an error event when sync_ throws', () async {
      final handle = _MockApiWallet();
      _stubHandle(
        handle,
        balance: _balance(0),
        info: _info(path: path, lastSyncedAt: _nowSecs()),
      );
      when(() => handle.sync_(electrumUrl: any(named: 'electrumUrl')))
          .thenThrow(Exception('electrum down'));

      await service.registerHandle(path, handle, electrumUrl);
      await Future<void>.delayed(Duration.zero);
      final events = <WalletSyncEvent>[];
      final sub = service.events.listen(events.add);

      await service.syncWallet(path);
      await Future<void>.delayed(Duration.zero);

      expect(events.last.error, isNotNull);
      expect(events.last.error, contains('electrum down'));
      expect(events.last.isSyncing, isFalse);

      // Subsequent retry succeeds — verifies the entry is left in a usable
      // state (isSyncing reset in finally block).
      when(() => handle.sync_(electrumUrl: any(named: 'electrumUrl')))
          .thenAnswer((_) async {});
      await service.syncWallet(path);
      await Future<void>.delayed(Duration.zero);
      expect(events.last.error, isNull);
      expect(events.last.balance, isNotNull);

      await sub.cancel();
    });

    test('is a no-op for an unknown wallet path', () async {
      await service.syncWallet('/nope.db');
      // No events, no exceptions.
      expect(service.isTracked('/nope.db'), isFalse);
    });
  });

  group('untrack', () {
    test('cancels the electrum subscription and removes the entry', () async {
      final handle = _MockApiWallet();
      final ctrl = _stubHandle(
        handle,
        balance: _balance(0),
        info: _info(path: path, lastSyncedAt: _nowSecs()),
      );
      await service.registerHandle(path, handle, electrumUrl);
      await Future<void>.delayed(Duration.zero);
      expect(ctrl.hasListener, isTrue);

      service.untrack(path);

      expect(service.isTracked(path), isFalse);
      expect(ctrl.hasListener, isFalse);
    });

    test('untrack on unknown path is a silent no-op', () {
      expect(() => service.untrack('/missing.db'), returnsNormally);
    });
  });

  group('event routing across multiple wallets', () {
    test('events carry the walletPath of the wallet they describe', () async {
      const pathA = '/wallets/a.db';
      const pathB = '/wallets/b.db';
      final handleA = _MockApiWallet();
      final handleB = _MockApiWallet();
      _stubHandle(
        handleA,
        balance: _balance(1),
        info: _info(path: pathA, lastSyncedAt: _nowSecs()),
      );
      _stubHandle(
        handleB,
        balance: _balance(2),
        info: _info(path: pathB, lastSyncedAt: _nowSecs()),
      );

      await service.registerHandle(pathA, handleA, electrumUrl);
      await service.registerHandle(pathB, handleB, electrumUrl);
      await Future<void>.delayed(Duration.zero);

      final events = <WalletSyncEvent>[];
      final sub = service.events.listen(events.add);
      await service.syncWallet(pathB);
      await Future<void>.delayed(Duration.zero);

      expect(events, isNotEmpty);
      expect(events.every((e) => e.walletPath == pathB), isTrue);
      await sub.cancel();
    });
  });

  group('initFromList', () {
    const settings = AppSettings(
      locale: Locale('en'),
      network: APINetwork.signet,
      walletType: APIWalletType.p2Wpkh,
      electrumUrls: {'Signet': electrumUrl},
    );

    test('opens unlocked wallets and skips wallets that need a password '
        'without a cached credential', () async {
      const pathOpen = '/wallets/open.db';
      const pathLocked = '/wallets/locked.db';

      const infoOpen = APIWalletInfo(
        walletPath: pathOpen,
        name: 'open',
        descriptor: 'tr(...)',
        network: APINetwork.signet,
        createdAt: 0,
        protection: APIWalletProtection(
          protectionType: APIProtectionType.deviceKey,
          needsPassword: false,
          securityLevel: APISecurityLevel.standard,
        ),
      );
      const infoLocked = APIWalletInfo(
        walletPath: pathLocked,
        name: 'locked',
        descriptor: 'tr(...)',
        network: APINetwork.signet,
        createdAt: 0,
        protection: APIWalletProtection(
          protectionType: APIProtectionType.userPassword,
          needsPassword: true,
          securityLevel: APISecurityLevel.standard,
        ),
      );

      final handle = _MockApiWallet();
      _stubHandle(
        handle,
        balance: _balance(0),
        info: _info(path: pathOpen, lastSyncedAt: _nowSecs()),
      );
      when(() => walletService.getCachedPassword(pathLocked)).thenReturn(null);
      when(() => walletService.openWallet(pathOpen))
          .thenAnswer((_) async => handle);

      await service.initFromList([infoOpen, infoLocked], settings);
      await Future<void>.delayed(Duration.zero);

      expect(service.isTracked(pathOpen), isTrue);
      expect(service.isTracked(pathLocked), isFalse);
      verifyNever(() => walletService.openWallet(pathLocked));
    });

    test('skips wallets that are already tracked', () async {
      final handle = _MockApiWallet();
      _stubHandle(
        handle,
        balance: _balance(0),
        info: _info(path: path, lastSyncedAt: _nowSecs()),
      );
      await service.registerHandle(path, handle, electrumUrl);
      await Future<void>.delayed(Duration.zero);

      final info = _info(path: path, lastSyncedAt: _nowSecs());
      await service.initFromList([info], settings);

      verifyNever(() => walletService.openWallet(any()));
    });

    test('a single failing openWallet does not block the rest', () async {
      const pathOk = '/wallets/ok.db';
      const pathBad = '/wallets/bad.db';

      final infoOk = _info(path: pathOk, lastSyncedAt: _nowSecs());
      final infoBad = _info(path: pathBad, lastSyncedAt: _nowSecs());

      final handle = _MockApiWallet();
      _stubHandle(
        handle,
        balance: _balance(0),
        info: infoOk,
      );
      when(() => walletService.openWallet(pathBad))
          .thenThrow(Exception('disk full'));
      when(() => walletService.openWallet(pathOk))
          .thenAnswer((_) async => handle);

      await service.initFromList([infoBad, infoOk], settings);
      await Future<void>.delayed(Duration.zero);

      expect(service.isTracked(pathBad), isFalse);
      expect(service.isTracked(pathOk), isTrue);
    });
  });

  group('dispose', () {
    test('closes event stream and cancels every subscription', () async {
      final handle = _MockApiWallet();
      final ctrl = _stubHandle(
        handle,
        balance: _balance(0),
        info: _info(path: path, lastSyncedAt: _nowSecs()),
      );
      await service.registerHandle(path, handle, electrumUrl);
      await Future<void>.delayed(Duration.zero);

      service.dispose();

      expect(ctrl.hasListener, isFalse);
      expect(service.isTracked(path), isFalse);
    });
  });
}
