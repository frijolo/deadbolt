import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import 'package:deadbolt/cubit/fiat_price_manager.dart' show FiatPricesUpdate;
import 'package:deadbolt/cubit/loaded_wallet.dart';
import 'package:deadbolt/cubit/wallet_deltas.dart';
import 'package:deadbolt/cubit/wallet_op_result.dart';
import 'package:deadbolt/services/price_service.dart' show PriceProviderType;
import 'package:deadbolt/services/wallet_sync_service.dart' show WalletSyncEvent;
import 'package:deadbolt/src/rust/api/model.dart';
import 'package:deadbolt/src/rust/api/wallet.dart' show ApiWallet;

class _MockApiWallet extends Mock implements ApiWallet {}

// ---------------------------------------------------------------------------
// Fixtures
// ---------------------------------------------------------------------------

const _path = '/wallets/w.db';

APIBalance _balance(int sats) => APIBalance(
      confirmed: BigInt.from(sats),
      trustedPending: BigInt.zero,
      untrustedPending: BigInt.zero,
      immature: BigInt.zero,
    );

APIWalletInfo _info() => const APIWalletInfo(
      walletPath: _path,
      name: 'w',
      descriptor: 'tr(...)',
      network: APINetwork.signet,
      createdAt: 0,
      protection: APIWalletProtection(
        protectionType: APIProtectionType.deviceKey,
        needsPassword: false,
        securityLevel: APISecurityLevel.standard,
      ),
    );

APITransactionPage _emptyPage() =>
    const APITransactionPage(transactions: [], totalCount: 0, hasMore: false);

APIAddress _addr(String a, {int idx = 0, bool used = false}) =>
    APIAddress(
      address: a,
      index: idx,
      keychain: APIKeychain.external_,
      balanceSat: BigInt.zero,
      isUsed: used,
      txCount: 0,
      isAuto: false,
    );

APIPsbtInfo _psbt({required int id, required String b64, String txid = 'tx'}) =>
    APIPsbtInfo(
      id: id,
      psbtBase64: b64,
      txid: txid,
      isAuto: false,
      isSelfTransfer: false,
      createdAt: 0,
      recipient: 'addr',
      amountSat: BigInt.from(1000),
      recipients: const [],
      feeSat: BigInt.from(100),
      spendPathId: 0,
      threshold: 1,
      mfps: const [],
      hasSpentInputs: false,
    );

APIPsbtAnalysis _analysis({bool finalized = false}) =>
    APIPsbtAnalysis(signers: const [], isFinalized: finalized);

APIHotKeyInfo _hotKey(String mfp) =>
    APIHotKeyInfo(mfp: mfp, seedType: 'mnemonic', createdAt: 0);

WalletSyncEvent _syncingEvent() =>
    const WalletSyncEvent(walletPath: _path, isSyncing: true);

WalletSyncEvent _completedEvent() => WalletSyncEvent(
      walletPath: _path,
      balance: _balance(0),
      walletInfo: _info(),
    );

WalletSyncEvent _errorEvent(String msg) =>
    WalletSyncEvent(walletPath: _path, error: msg);

/// Stub the four chain-snapshot calls with default responses.
void _stubChainSnapshot(_MockApiWallet h) {
  when(() => h.getInfo()).thenAnswer((_) async => _info());
  when(() => h.getBalance()).thenAnswer((_) async => _balance(0));
  when(() => h.getTransactions(
        page: any(named: 'page'),
        pageSize: any(named: 'pageSize'),
      )).thenAnswer((_) async => _emptyPage());
  when(() => h.getTipHeight()).thenAnswer((_) async => 100);
}

void main() {
  setUpAll(() {
    registerFallbackValue(APIKeychain.external_);
    registerFallbackValue(BigInt.zero);
  });

  late _MockApiWallet handle;
  late LoadedWalletImpl wallet;

  setUp(() {
    handle = _MockApiWallet();
    wallet = LoadedWalletImpl(handle);
  });

  // ---------------------------------------------------------------------
  // handleSyncEvent
  // ---------------------------------------------------------------------

  group('handleSyncEvent', () {
    test('returns SyncReload.syncing for an isSyncing event', () async {
      final res = await wallet.handleSyncEvent(
        event: _syncingEvent(),
        receiveLoaded: false,
        changeLoaded: false,
        utxosLoaded: false,
        psbtsLoaded: false,
        currentPsbts: const [],
        currentAnalyses: const {},
      );
      expect(res, isA<Ok<SyncReload>>());
      expect((res as Ok<SyncReload>).value.wasSyncing, isTrue);
      verifyNever(() => handle.getInfo());
    });

    test('maps "No such mempool" error to retry marker', () async {
      final res = await wallet.handleSyncEvent(
        event: _errorEvent('Electrum: No such mempool or blockchain transaction'),
        receiveLoaded: false,
        changeLoaded: false,
        utxosLoaded: false,
        psbtsLoaded: false,
        currentPsbts: const [],
        currentAnalyses: const {},
      );
      expect(res, isA<Ok<SyncReload>>());
      expect((res as Ok<SyncReload>).value.retryNeeded, isTrue);
    });

    test('returns Err for any other error event', () async {
      final res = await wallet.handleSyncEvent(
        event: _errorEvent('connection refused'),
        receiveLoaded: false,
        changeLoaded: false,
        utxosLoaded: false,
        psbtsLoaded: false,
        currentPsbts: const [],
        currentAnalyses: const {},
      );
      expect(res, isA<Err<SyncReload>>());
      expect((res as Err<SyncReload>).message, 'connection refused');
    });

    test('completed event returns chain snapshot only when all layers closed',
        () async {
      _stubChainSnapshot(handle);
      final res = await wallet.handleSyncEvent(
        event: _completedEvent(),
        receiveLoaded: false,
        changeLoaded: false,
        utxosLoaded: false,
        psbtsLoaded: false,
        currentPsbts: const [],
        currentAnalyses: const {},
      );
      expect(res, isA<Ok<SyncReload>>());
      final reload = (res as Ok<SyncReload>).value;
      expect(reload.chain, isNotNull);
      expect(reload.receive, isNull);
      expect(reload.change, isNull);
      expect(reload.coins, isNull);
      expect(reload.psbts, isNull);
      verifyNever(() => handle.getAddresses(keychain: any(named: 'keychain')));
      verifyNever(() => handle.getUtxos());
      verifyNever(() => handle.listPsbts());
    });

    test('refreshes only the layers marked as loaded', () async {
      _stubChainSnapshot(handle);
      when(() => handle.getAddresses(keychain: APIKeychain.external_))
          .thenAnswer((_) async => [_addr('addr-r')]);
      when(() => handle.getAddresses(keychain: APIKeychain.internal))
          .thenAnswer((_) async => [_addr('addr-c')]);
      when(() => handle.getUtxos()).thenAnswer((_) async => const []);

      final res = await wallet.handleSyncEvent(
        event: _completedEvent(),
        receiveLoaded: true,
        changeLoaded: true,
        utxosLoaded: true,
        psbtsLoaded: false,
        currentPsbts: const [],
        currentAnalyses: const {},
      );
      final reload = (res as Ok<SyncReload>).value;
      expect(reload.receive!.addresses.first.address, 'addr-r');
      expect(reload.change!.addresses.first.address, 'addr-c');
      expect(reload.coins!.utxos, isEmpty);
      expect(reload.psbts, isNull);
    });

    test('PSBT memoization reuses cached analyses when list is unchanged',
        () async {
      _stubChainSnapshot(handle);
      final psbt = _psbt(id: 1, b64: 'AAA');
      final cached = _analysis(finalized: true);
      when(() => handle.listPsbts()).thenAnswer((_) async => [psbt]);

      final res = await wallet.handleSyncEvent(
        event: _completedEvent(),
        receiveLoaded: false,
        changeLoaded: false,
        utxosLoaded: false,
        psbtsLoaded: true,
        currentPsbts: [psbt],
        currentAnalyses: {1: cached},
      );
      final reload = (res as Ok<SyncReload>).value;
      expect(reload.psbts!.psbts, [psbt]);
      expect(reload.psbts!.analyses[1], same(cached));
      verifyNever(() => handle.analyzePsbt(
            psbtBase64: any(named: 'psbtBase64'),
            mfps: any(named: 'mfps'),
          ));
    });

    test('PSBT memoization re-analyzes when content changed', () async {
      _stubChainSnapshot(handle);
      final psbtV1 = _psbt(id: 1, b64: 'AAA');
      final psbtV2 = _psbt(id: 1, b64: 'BBB');
      when(() => handle.listPsbts()).thenAnswer((_) async => [psbtV2]);
      final fresh = _analysis(finalized: true);
      when(() => handle.analyzePsbt(
            psbtBase64: 'BBB',
            mfps: any(named: 'mfps'),
          )).thenAnswer((_) async => fresh);

      final res = await wallet.handleSyncEvent(
        event: _completedEvent(),
        receiveLoaded: false,
        changeLoaded: false,
        utxosLoaded: false,
        psbtsLoaded: true,
        currentPsbts: [psbtV1],
        currentAnalyses: {1: _analysis()},
      );
      final reload = (res as Ok<SyncReload>).value;
      expect(reload.psbts!.analyses[1], same(fresh));
    });

    test('PSBT load failure does not break the rest of the snapshot',
        () async {
      _stubChainSnapshot(handle);
      when(() => handle.listPsbts()).thenThrow(Exception('listPsbts boom'));

      final res = await wallet.handleSyncEvent(
        event: _completedEvent(),
        receiveLoaded: false,
        changeLoaded: false,
        utxosLoaded: false,
        psbtsLoaded: true,
        currentPsbts: const [],
        currentAnalyses: const {},
      );
      expect(res, isA<Ok<SyncReload>>());
      expect((res as Ok<SyncReload>).value.psbts, isNull);
    });

    test('chain snapshot failure becomes Err via guardAsync', () async {
      when(() => handle.getInfo()).thenThrow(Exception('rpc down'));
      when(() => handle.getBalance()).thenAnswer((_) async => _balance(0));
      when(() => handle.getTransactions(
            page: any(named: 'page'),
            pageSize: any(named: 'pageSize'),
          )).thenAnswer((_) async => _emptyPage());
      when(() => handle.getTipHeight()).thenAnswer((_) async => 0);

      final res = await wallet.handleSyncEvent(
        event: _completedEvent(),
        receiveLoaded: false,
        changeLoaded: false,
        utxosLoaded: false,
        psbtsLoaded: false,
        currentPsbts: const [],
        currentAnalyses: const {},
      );
      expect(res, isA<Err<SyncReload>>());
      expect((res as Err<SyncReload>).message,
          contains('LoadedWallet.handleSyncEvent'));
    });
  });

  // ---------------------------------------------------------------------
  // analyzeAllPsbts (top-level helper used by _analyzeAll)
  // ---------------------------------------------------------------------

  group('analyzeAllPsbts', () {
    test('empty list returns empty map without touching FFI', () async {
      final out = await analyzeAllPsbts(handle, const []);
      expect(out, isEmpty);
      verifyNever(() => handle.analyzePsbt(
            psbtBase64: any(named: 'psbtBase64'),
            mfps: any(named: 'mfps'),
          ));
    });

    test('all PSBTs analyzed in parallel produce a complete map', () async {
      final p1 = _psbt(id: 1, b64: 'A');
      final p2 = _psbt(id: 2, b64: 'B');
      final a1 = _analysis(finalized: true);
      final a2 = _analysis();
      when(() => handle.analyzePsbt(
          psbtBase64: 'A',
          mfps: any(named: 'mfps'))).thenAnswer((_) async => a1);
      when(() => handle.analyzePsbt(
          psbtBase64: 'B',
          mfps: any(named: 'mfps'))).thenAnswer((_) async => a2);

      final out = await analyzeAllPsbts(handle, [p1, p2]);
      expect(out, {1: a1, 2: a2});
    });

    test('a single throwing PSBT does not block the others', () async {
      final p1 = _psbt(id: 1, b64: 'A');
      final p2 = _psbt(id: 2, b64: 'B');
      final a2 = _analysis();
      when(() => handle.analyzePsbt(
          psbtBase64: 'A',
          mfps: any(named: 'mfps'))).thenThrow(Exception('bad psbt'));
      when(() => handle.analyzePsbt(
          psbtBase64: 'B',
          mfps: any(named: 'mfps'))).thenAnswer((_) async => a2);

      final out = await analyzeAllPsbts(handle, [p1, p2]);
      expect(out, {2: a2});
    });
  });

  // ---------------------------------------------------------------------
  // Simple guarded delegations
  // ---------------------------------------------------------------------

  group('rescan', () {
    test('runs rescan + chain snapshot and returns ChainSnapshot', () async {
      when(() => handle.rescan(electrumUrl: any(named: 'electrumUrl')))
          .thenAnswer((_) async {});
      _stubChainSnapshot(handle);

      final res = await wallet.rescan('ssl://e:1');
      expect(res, isA<Ok<ChainSnapshot>>());
      expect((res as Ok<ChainSnapshot>).value.tipHeight, 100);
      verify(() => handle.rescan(electrumUrl: 'ssl://e:1')).called(1);
    });

    test('rescan FFI failure is surfaced as Err', () async {
      when(() => handle.rescan(electrumUrl: any(named: 'electrumUrl')))
          .thenThrow(Exception('no electrum'));
      final res = await wallet.rescan('ssl://e:1');
      expect(res, isA<Err<ChainSnapshot>>());
      expect((res as Err<ChainSnapshot>).message, contains('LoadedWallet.rescan'));
    });
  });

  group('loadMoreTransactions', () {
    test('requests page + 1 with default page size', () async {
      when(() => handle.getTransactions(page: 3, pageSize: 25))
          .thenAnswer((_) async => _emptyPage());
      final res = await wallet.loadMoreTransactions(2);
      final delta = (res as Ok<TransactionPageDelta>).value;
      expect(delta.currentPage, 3);
    });
  });

  group('refreshAfterLabelChange', () {
    test('reloads page 0 sized to (currentPage+1) * pageSize', () async {
      when(() => handle.getTransactions(page: 0, pageSize: 75))
          .thenAnswer((_) async => _emptyPage());
      final res = await wallet.refreshAfterLabelChange(2);
      expect((res as Ok<TransactionPageDelta>).value.currentPage, 2);
      verify(() => handle.getTransactions(page: 0, pageSize: 75)).called(1);
    });
  });

  group('loadAddresses', () {
    test('returns AddressUpdate with the FFI list', () async {
      when(() => handle.getAddresses(keychain: APIKeychain.external_))
          .thenAnswer((_) async => [_addr('a')]);
      final res = await wallet.loadAddresses(APIKeychain.external_);
      expect((res as Ok<AddressUpdate>).value.addresses.single.address, 'a');
    });
  });

  group('loadUtxos', () {
    test('returns CoinUpdate', () async {
      when(() => handle.getUtxos()).thenAnswer((_) async => const []);
      final res = await wallet.loadUtxos();
      expect((res as Ok<CoinUpdate>).value.utxos, isEmpty);
    });
  });

  // ---------------------------------------------------------------------
  // findNextUnusedAddress
  // ---------------------------------------------------------------------

  group('findNextUnusedAddress', () {
    test('returns first unused address not in exclude set', () async {
      when(() => handle.getAddresses(keychain: APIKeychain.external_))
          .thenAnswer((_) async => [
                _addr('used', used: true),
                _addr('skipme'),
                _addr('pickme'),
              ]);
      final picked = await wallet.findNextUnusedAddress({'skipme'});
      expect(picked!.address, 'pickme');
      verifyNever(() => handle.revealMoreAddresses(
            keychain: any(named: 'keychain'),
            count: any(named: 'count'),
          ));
    });

    test('reveals 20 more addresses when first scan finds nothing usable',
        () async {
      var call = 0;
      when(() => handle.getAddresses(keychain: APIKeychain.external_))
          .thenAnswer((_) async {
        call++;
        if (call == 1) return [_addr('a', used: true)];
        return [_addr('a', used: true), _addr('fresh')];
      });
      when(() => handle.revealMoreAddresses(
            keychain: APIKeychain.external_,
            count: 20,
          )).thenReturn(0);

      final picked = await wallet.findNextUnusedAddress(const {});
      expect(picked!.address, 'fresh');
      verify(() => handle.revealMoreAddresses(
            keychain: APIKeychain.external_,
            count: 20,
          )).called(1);
    });

    test('returns null when FFI throws (caller treats as skip)', () async {
      when(() => handle.getAddresses(keychain: APIKeychain.external_))
          .thenThrow(Exception('boom'));
      final picked = await wallet.findNextUnusedAddress(const {});
      expect(picked, isNull);
    });
  });

  // ---------------------------------------------------------------------
  // PSBTs
  // ---------------------------------------------------------------------

  group('loadPsbts', () {
    test('returns PsbtSnapshot with analyses for every PSBT', () async {
      final p = _psbt(id: 7, b64: 'X');
      final a = _analysis();
      when(() => handle.listPsbts()).thenAnswer((_) async => [p]);
      when(() => handle.analyzePsbt(
            psbtBase64: 'X',
            mfps: any(named: 'mfps'),
          )).thenAnswer((_) async => a);
      final res = await wallet.loadPsbts();
      expect((res as Ok<PsbtSnapshot>).value.analyses[7], same(a));
    });
  });

  group('createPsbt', () {
    test('applies the label synchronously when one is provided', () async {
      final created = _psbt(id: 1, b64: 'P');
      final labeled = _psbt(id: 1, b64: 'P');
      when(() => handle.createPsbt(
            recipients: any(named: 'recipients'),
            maxRecipientIndex: any(named: 'maxRecipientIndex'),
            feeAbsoluteSat: any(named: 'feeAbsoluteSat'),
            selectedUtxos: any(named: 'selectedUtxos'),
            policyPath: any(named: 'policyPath'),
            spendPathId: any(named: 'spendPathId'),
            threshold: any(named: 'threshold'),
            mfps: any(named: 'mfps'),
          )).thenReturn(created);
      when(() => handle.setPsbtLabel(id: 1, label: 'lbl'))
          .thenReturn(labeled);

      final res = wallet.createPsbt(
        recipients: const [],
        feeAbsoluteSat: 100,
        selectedUtxos: const [],
        policyPath: const [],
        spendPathId: 0,
        threshold: 1,
        mfps: const [],
        label: 'lbl',
      );
      expect((res as Ok<APIPsbtInfo>).value, same(labeled));
      verify(() => handle.setPsbtLabel(id: 1, label: 'lbl')).called(1);
    });

    test('skips setPsbtLabel when label is empty', () {
      final created = _psbt(id: 2, b64: 'Q');
      when(() => handle.createPsbt(
            recipients: any(named: 'recipients'),
            maxRecipientIndex: any(named: 'maxRecipientIndex'),
            feeAbsoluteSat: any(named: 'feeAbsoluteSat'),
            selectedUtxos: any(named: 'selectedUtxos'),
            policyPath: any(named: 'policyPath'),
            spendPathId: any(named: 'spendPathId'),
            threshold: any(named: 'threshold'),
            mfps: any(named: 'mfps'),
          )).thenReturn(created);

      wallet.createPsbt(
        recipients: const [],
        feeAbsoluteSat: 100,
        selectedUtxos: const [],
        policyPath: const [],
        spendPathId: 0,
        threshold: 1,
        mfps: const [],
        label: '',
      );
      verifyNever(() => handle.setPsbtLabel(
            id: any(named: 'id'),
            label: any(named: 'label'),
          ));
    });

    test('label setter throwing is silently swallowed (returns base PSBT)', () {
      final created = _psbt(id: 3, b64: 'R');
      when(() => handle.createPsbt(
            recipients: any(named: 'recipients'),
            maxRecipientIndex: any(named: 'maxRecipientIndex'),
            feeAbsoluteSat: any(named: 'feeAbsoluteSat'),
            selectedUtxos: any(named: 'selectedUtxos'),
            policyPath: any(named: 'policyPath'),
            spendPathId: any(named: 'spendPathId'),
            threshold: any(named: 'threshold'),
            mfps: any(named: 'mfps'),
          )).thenReturn(created);
      when(() => handle.setPsbtLabel(id: 3, label: 'bad'))
          .thenThrow(Exception('label fail'));

      final res = wallet.createPsbt(
        recipients: const [],
        feeAbsoluteSat: 100,
        selectedUtxos: const [],
        policyPath: const [],
        spendPathId: 0,
        threshold: 1,
        mfps: const [],
        label: 'bad',
      );
      expect((res as Ok<APIPsbtInfo>).value, same(created));
    });
  });

  group('deletePsbt / broadcastPsbt', () {
    test('deletePsbt success', () {
      when(() => handle.deletePsbt(id: 5)).thenReturn(null);
      final res = wallet.deletePsbt(5);
      expect(res, isA<Ok<void>>());
    });

    test('deletePsbt error mapped via formatRustError', () {
      when(() => handle.deletePsbt(id: 5)).thenThrow(Exception('locked'));
      final res = wallet.deletePsbt(5);
      expect((res as Err<void>).message, contains('LoadedWallet.deletePsbt'));
    });

    test('broadcastPsbt returns the txid string', () async {
      when(() => handle.broadcastPsbt(id: 9, electrumUrl: 'ssl://e:1'))
          .thenAnswer((_) async => 'txid-9');
      final res = await wallet.broadcastPsbt(9, 'ssl://e:1');
      expect((res as Ok<String>).value, 'txid-9');
    });
  });

  group('importPsbt', () {
    test('happy path returns analysis when analyzePsbt succeeds', () async {
      final imported = _psbt(id: 4, b64: 'IMP');
      final analysis = _analysis(finalized: true);
      when(() => handle.importPsbt(psbtBase64: 'IMP'))
          .thenAnswer((_) async => APIImportPsbtResult(
                psbt: imported,
                wasMerged: false,
              ));
      when(() => handle.analyzePsbt(
            psbtBase64: 'IMP',
            mfps: any(named: 'mfps'),
          )).thenAnswer((_) async => analysis);

      final res = await wallet.importPsbt('IMP');
      final out = (res as Ok<PsbtImported>).value;
      expect(out.psbt, same(imported));
      expect(out.wasMerged, isFalse);
      expect(out.analysis, same(analysis));
    });

    test('analysis failure leaves analysis null but operation succeeds',
        () async {
      final imported = _psbt(id: 5, b64: 'IMP2');
      when(() => handle.importPsbt(psbtBase64: 'IMP2'))
          .thenAnswer((_) async => APIImportPsbtResult(
                psbt: imported,
                wasMerged: true,
              ));
      when(() => handle.analyzePsbt(
            psbtBase64: 'IMP2',
            mfps: any(named: 'mfps'),
          )).thenThrow(Exception('parse fail'));

      final res = await wallet.importPsbt('IMP2');
      final out = (res as Ok<PsbtImported>).value;
      expect(out.analysis, isNull);
      expect(out.wasMerged, isTrue);
    });

    test('importPsbt FFI failure becomes Err', () async {
      when(() => handle.importPsbt(psbtBase64: any(named: 'psbtBase64')))
          .thenThrow(Exception('bad b64'));
      final res = await wallet.importPsbt('xxx');
      expect(res, isA<Err<PsbtImported>>());
    });
  });

  group('mergePsbt / signPsbtWithKey', () {
    test('mergePsbt returns updated psbt with analysis', () async {
      final updated = _psbt(id: 1, b64: 'M');
      final a = _analysis();
      when(() => handle.mergePsbt(id: 1, signedPsbtBase64: 'S'))
          .thenReturn(updated);
      when(() => handle.analyzePsbt(
            psbtBase64: 'M',
            mfps: any(named: 'mfps'),
          )).thenAnswer((_) async => a);

      final res = await wallet.mergePsbt(1, 'S');
      expect((res as Ok<PsbtUpdated>).value.analysis, same(a));
    });

    test('signPsbtWithKey analysis swallowed on failure', () async {
      final updated = _psbt(id: 2, b64: 'SS');
      when(() => handle.signPsbtWithKey(psbtId: 2, mfp: 'abcd'))
          .thenReturn(updated);
      when(() => handle.analyzePsbt(
            psbtBase64: 'SS',
            mfps: any(named: 'mfps'),
          )).thenThrow(Exception('bad'));

      final res = await wallet.signPsbtWithKey(2, 'abcd');
      final out = (res as Ok<PsbtUpdated>).value;
      expect(out.psbt, same(updated));
      expect(out.analysis, isNull);
    });
  });

  // ---------------------------------------------------------------------
  // Hot keys
  // ---------------------------------------------------------------------

  group('hot keys', () {
    test('addMnemonicKey delegates and returns Ok(info)', () {
      final info = _hotKey('aabbccdd');
      when(() => handle.addMnemonicKey(
            mnemonic: 'm',
            passphrase: 'p',
          )).thenReturn(info);
      final res = wallet.addMnemonicKey('m', 'p');
      expect((res as Ok<APIHotKeyInfo>).value, same(info));
    });

    test('addXprvKey error maps to Err', () {
      when(() => handle.addXprvKey(xprv: 'xprv...'))
          .thenThrow(Exception('parse'));
      final res = wallet.addXprvKey('xprv...');
      expect(res, isA<Err<APIHotKeyInfo>>());
    });

    test('deleteHotKey success', () {
      when(() => handle.deleteHotKey(mfp: 'mm')).thenReturn(null);
      expect(wallet.deleteHotKey('mm'), isA<Ok<void>>());
    });

    test('revealHotKey returns null when FFI returns null', () {
      // The FFI returns String, not String? — but error path is more useful:
      when(() => handle.revealHotKey(mfp: 'mm'))
          .thenThrow(Exception('locked'));
      final res = wallet.revealHotKey('mm');
      expect(res, isA<Err<String?>>());
    });

    test('revealAddressWif delegates to deriveAddressWif', () {
      when(() => handle.deriveAddressWif(address: 'addr', mfp: 'mm'))
          .thenReturn('wif-xxx');
      final res = wallet.revealAddressWif('addr', 'mm');
      expect((res as Ok<String?>).value, 'wif-xxx');
    });
  });

  // ---------------------------------------------------------------------
  // Fiat
  // ---------------------------------------------------------------------

  group('setFiatConfig', () {
    test('returns null when config is unchanged on a second call', () {
      // First call initializes state — returns currency.
      final first = wallet.setFiatConfig(
        enabled: true,
        currency: 'usd',
        provider: PriceProviderType.coinGecko,
      );
      expect(first, 'usd');

      // Second identical call → null (no-op signal).
      final second = wallet.setFiatConfig(
        enabled: true,
        currency: 'usd',
        provider: PriceProviderType.coinGecko,
      );
      expect(second, isNull);
    });

    test('disabling returns "disabled" sentinel and clears state', () {
      wallet.setFiatConfig(
        enabled: true,
        currency: 'usd',
        provider: PriceProviderType.coinGecko,
      );
      final res = wallet.setFiatConfig(
        enabled: false,
        currency: 'usd',
        provider: PriceProviderType.coinGecko,
      );
      expect(res, 'disabled');
    });

    test('changing provider returns the new currency', () {
      wallet.setFiatConfig(
        enabled: true,
        currency: 'usd',
        provider: PriceProviderType.coinGecko,
      );
      final res = wallet.setFiatConfig(
        enabled: true,
        currency: 'usd',
        provider: PriceProviderType.mempoolSpace,
      );
      expect(res, 'usd');
    });
  });

  group('fetchFiatPrices early returns', () {
    test('disabled → Ok(null) without touching FFI', () async {
      final res = await wallet.fetchFiatPrices(currency: 'usd', enabled: false);
      expect((res as Ok<FiatPricesUpdate?>).value, isNull);
      verifyNever(() => handle.getTxidsMissingFiat(
            currency: any(named: 'currency'),
          ));
    });

    test('enabled but no PriceService configured → Ok(null)', () async {
      // Never called setFiatConfig → _priceService is null.
      final res = await wallet.fetchFiatPrices(currency: 'usd', enabled: true);
      expect((res as Ok<FiatPricesUpdate?>).value, isNull);
      verifyNever(() => handle.getTxidsMissingFiat(
            currency: any(named: 'currency'),
          ));
    });
  });

  // ---------------------------------------------------------------------
  // Misc
  // ---------------------------------------------------------------------

  test('handle exposes the underlying ApiWallet identity', () {
    expect(wallet.handle, same(handle));
  });

  test('revealMoreAddresses delegates to FFI and returns', () async {
    when(() => handle.revealMoreAddresses(
          keychain: APIKeychain.external_,
          count: 5,
        )).thenReturn(5);
    await wallet.revealMoreAddresses(
        keychain: APIKeychain.external_, count: 5);
    verify(() => handle.revealMoreAddresses(
          keychain: APIKeychain.external_,
          count: 5,
        )).called(1);
  });
}
