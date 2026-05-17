import 'dart:async';

import 'package:deadbolt/cubit/fiat_price_manager.dart'
    show FiatPriceManager, FiatPricesUpdate;
import 'package:deadbolt/cubit/wallet_deltas.dart';
import 'package:deadbolt/cubit/wallet_op_result.dart';
import 'package:deadbolt/src/rust/api/analyzer.dart' show analyzeDescriptor;
import 'package:deadbolt/src/rust/api/model.dart'
    show
        APIAddress,
        APICoinControl,
        APIHotKeyInfo,
        APIKeychain,
        APIPolicyPath,
        APIPsbtAnalysis,
        APIPsbtInfo;
import 'package:deadbolt/src/rust/api/model.dart' show APIRecipient;
import 'package:deadbolt/src/rust/api/wallet.dart' show ApiWallet;
import 'package:deadbolt/services/price_service.dart' show PriceProviderType;
import 'package:deadbolt/services/wallet_sync_service.dart' show WalletSyncEvent;
import 'package:deadbolt/config/constants.dart' show kPageSize;
import 'package:deadbolt/utils/date_format.dart' show formatDate;

// ---------------------------------------------------------------------------
// Abstract interface
// ---------------------------------------------------------------------------

/// Post-handle wallet operations: every interaction with an already-opened
/// [ApiWallet]. Owns the FFI handle plus the operational state that does not
/// belong in the cubit (fiat price service, debounce flags, PSBT analysis
/// memo).
///
/// This is the seam the cubit crosses for everything except the initial
/// open (handled by [WalletOpener]). Every method returns a
/// [WalletOpResult] — error propagation is explicit.
abstract class LoadedWallet {
  ApiWallet get handle;

  // ─── Chain & data layers ───────────────────────────────────────────────

  Future<WalletOpResult<SyncReload>> handleSyncEvent({
    required WalletSyncEvent event,
    required bool receiveLoaded,
    required bool changeLoaded,
    required bool utxosLoaded,
    required bool psbtsLoaded,
    required List<APIPsbtInfo> currentPsbts,
    required Map<int, APIPsbtAnalysis> currentAnalyses,
  });

  Future<WalletOpResult<ChainSnapshot>> rescan(String electrumUrl);
  Future<WalletOpResult<TransactionPageDelta>> loadMoreTransactions(int currentPage);
  Future<WalletOpResult<AddressUpdate>> loadAddresses(APIKeychain keychain);
  Future<WalletOpResult<CoinUpdate>> loadUtxos();
  Future<WalletOpResult<DescriptorSnapshot>> loadDescriptorAnalysis(String descriptor);
  Future<WalletOpResult<TransactionPageDelta>> refreshAfterLabelChange(int currentPage);
  Future<WalletOpResult<void>> revealMoreAddresses({required APIKeychain keychain, required int count});
  Future<APIAddress?> findNextUnusedAddress(Set<String> exclude);

  // ─── PSBTs ─────────────────────────────────────────────────────────────

  Future<WalletOpResult<PsbtSnapshot>> loadPsbts();
  WalletOpResult<APIPsbtInfo> createPsbt({
    required List<APIRecipient> recipients,
    int? maxRecipientIndex,
    required int feeAbsoluteSat,
    required List<APICoinControl> selectedUtxos,
    required List<APIPolicyPath> policyPath,
    required int spendPathId,
    required int threshold,
    required List<String> mfps,
    String? label,
    int? nlocktimeDeltaBlocks,
  });
  WalletOpResult<void> deletePsbt(int id);
  Future<WalletOpResult<PsbtImported>> importPsbt(String psbtBase64);
  Future<WalletOpResult<PsbtUpdated>> mergePsbt(int id, String signedPsbtBase64);
  Future<WalletOpResult<String>> broadcastPsbt(int id, String electrumUrl);

  // ─── Hot keys ──────────────────────────────────────────────────────────

  WalletOpResult<APIHotKeyInfo> addMnemonicKey(String mnemonic, String? passphrase);
  WalletOpResult<APIHotKeyInfo> addXprvKey(String xprv);
  WalletOpResult<void> deleteHotKey(String mfp);
  WalletOpResult<String?> revealHotKey(String mfp);
  WalletOpResult<String?> revealAddressWif(String address, String mfp);
  Future<WalletOpResult<PsbtUpdated>> signPsbtWithKey(int psbtId, String mfp);

  // ─── Fiat ──────────────────────────────────────────────────────────────

  String? setFiatConfig({
    required bool enabled,
    required String currency,
    required PriceProviderType provider,
  });

  Future<WalletOpResult<FiatPricesUpdate?>> fetchFiatPrices({
    required String currency,
    required bool enabled,
  });
}

// ---------------------------------------------------------------------------
// Implementation
// ---------------------------------------------------------------------------

class LoadedWalletImpl implements LoadedWallet {
  final ApiWallet _handle;
  final FiatPriceManager _fiat = FiatPriceManager();

  static const _pageSize = kPageSize;

  LoadedWalletImpl(this._handle);

  @override
  ApiWallet get handle => _handle;

  // ─── Chain & data layers ───────────────────────────────────────────────

  @override
  Future<WalletOpResult<SyncReload>> handleSyncEvent({
    required WalletSyncEvent event,
    required bool receiveLoaded,
    required bool changeLoaded,
    required bool utxosLoaded,
    required bool psbtsLoaded,
    required List<APIPsbtInfo> currentPsbts,
    required Map<int, APIPsbtAnalysis> currentAnalyses,
  }) async {
    if (event.isSyncing) {
      return const Ok(SyncReload.syncing());
    }
    if (event.error != null) {
      if (event.error!.contains('No such mempool or blockchain transaction')) {
        return const Ok(SyncReload.retry());
      }
      return Err(event.error!);
    }

    return guardAsync<SyncReload>(
      () async {
        final snapshot = await _fetchChain();
        final receive = receiveLoaded
            ? AddressUpdate(await _handle.getAddresses(keychain: APIKeychain.external_))
            : null;
        final change = changeLoaded
            ? AddressUpdate(await _handle.getAddresses(keychain: APIKeychain.internal))
            : null;
        final coins = utxosLoaded ? CoinUpdate(await _handle.getUtxos()) : null;

        PsbtSnapshot? psbtSnap;
        if (psbtsLoaded) {
          try {
            final psbts = await _handle.listPsbts();
            bool psbtListChanged() {
              if (psbts.length != currentPsbts.length) return true;
              final cached = <int, String>{
                for (final p in currentPsbts) p.id.toInt(): p.psbtBase64,
              };
              return psbts.any((p) => cached[p.id.toInt()] != p.psbtBase64);
            }

            final analyses = psbtListChanged()
                ? await analyzeAllPsbts(_handle, psbts)
                : currentAnalyses;
            psbtSnap = PsbtSnapshot(psbts: psbts, analyses: analyses);
          } catch (_) {}
        }

        return SyncReload(
          chain: ChainSnapshot(
            info: snapshot.info,
            balance: snapshot.balance,
            transactions: snapshot.transactions,
            tipHeight: snapshot.tipHeight,
          ),
          receive: receive,
          change: change,
          coins: coins,
          psbts: psbtSnap,
        );
      },
      tag: 'LoadedWallet.handleSyncEvent',
    );
  }

  @override
  Future<WalletOpResult<ChainSnapshot>> rescan(String electrumUrl) =>
      guardAsync<ChainSnapshot>(
        () async {
          await _handle.rescan(electrumUrl: electrumUrl);
          return await _fetchChain();
        },
        tag: 'LoadedWallet.rescan',
      );

  @override
  Future<WalletOpResult<TransactionPageDelta>> loadMoreTransactions(int currentPage) =>
      guardAsync<TransactionPageDelta>(
        () async {
          final page = await _handle.getTransactions(
            page: currentPage + 1,
            pageSize: _pageSize,
          );
          return TransactionPageDelta(page: page, currentPage: currentPage + 1);
        },
        tag: 'LoadedWallet.loadMoreTransactions',
      );

  @override
  Future<WalletOpResult<AddressUpdate>> loadAddresses(APIKeychain keychain) =>
      guardAsync<AddressUpdate>(
        () async => AddressUpdate(await _handle.getAddresses(keychain: keychain)),
        tag: 'LoadedWallet.loadAddresses',
      );

  @override
  Future<WalletOpResult<CoinUpdate>> loadUtxos() => guardAsync<CoinUpdate>(
        () async => CoinUpdate(await _handle.getUtxos()),
        tag: 'LoadedWallet.loadUtxos',
      );

  @override
  Future<WalletOpResult<DescriptorSnapshot>> loadDescriptorAnalysis(String descriptor) =>
      guardAsync<DescriptorSnapshot>(
        () async {
          final analysis = await analyzeDescriptor(descriptor: descriptor);
          final rawKeyLabels = await _handle.getKeyLabels();
          final rawPathLabels = await _handle.getPathLabels();
          return DescriptorSnapshot(
            analysis: analysis,
            keyLabels: {for (final e in rawKeyLabels) e.mfp: e.label},
            pathLabels: {for (final e in rawPathLabels) e.rustId: e.label},
          );
        },
        tag: 'LoadedWallet.loadDescriptorAnalysis',
      );

  @override
  Future<WalletOpResult<TransactionPageDelta>> refreshAfterLabelChange(int currentPage) =>
      guardAsync<TransactionPageDelta>(
        () async {
          final page = await _handle.getTransactions(
            page: 0,
            pageSize: _pageSize * (currentPage + 1),
          );
          return TransactionPageDelta(page: page, currentPage: currentPage);
        },
        tag: 'LoadedWallet.refreshAfterLabelChange',
      );

  @override
  Future<WalletOpResult<void>> revealMoreAddresses({
    required APIKeychain keychain,
    required int count,
  }) =>
      guardAsync<void>(
        () async => _handle.revealMoreAddresses(keychain: keychain, count: count),
        tag: 'LoadedWallet.revealMoreAddresses',
      );

  @override
  Future<APIAddress?> findNextUnusedAddress(Set<String> exclude) async {
    try {
      APIAddress? pick(List<APIAddress> addresses) {
        for (final addr in addresses) {
          if (addr.isUsed) continue;
          if (exclude.contains(addr.address)) continue;
          return addr;
        }
        return null;
      }

      var addresses = await _handle.getAddresses(keychain: APIKeychain.external_);
      final found = pick(addresses);
      if (found != null) return found;

      _handle.revealMoreAddresses(keychain: APIKeychain.external_, count: 20);
      addresses = await _handle.getAddresses(keychain: APIKeychain.external_);
      return pick(addresses);
    } catch (_) {
      return null;
    }
  }

  // ─── PSBTs ─────────────────────────────────────────────────────────────

  @override
  Future<WalletOpResult<PsbtSnapshot>> loadPsbts() =>
      guardAsync<PsbtSnapshot>(
        () async {
          final psbts = await _handle.listPsbts();
          final analyses = await analyzeAllPsbts(_handle, psbts);
          return PsbtSnapshot(psbts: psbts, analyses: analyses);
        },
        tag: 'LoadedWallet.loadPsbts',
      );

  @override
  WalletOpResult<APIPsbtInfo> createPsbt({
    required List<APIRecipient> recipients,
    int? maxRecipientIndex,
    required int feeAbsoluteSat,
    required List<APICoinControl> selectedUtxos,
    required List<APIPolicyPath> policyPath,
    required int spendPathId,
    required int threshold,
    required List<String> mfps,
    String? label,
    int? nlocktimeDeltaBlocks,
  }) =>
      guardSync<APIPsbtInfo>(
        () {
          var psbt = _handle.createPsbt(
            recipients: recipients,
            maxRecipientIndex: maxRecipientIndex,
            feeAbsoluteSat: BigInt.from(feeAbsoluteSat),
            selectedUtxos: selectedUtxos,
            policyPath: policyPath,
            spendPathId: spendPathId,
            threshold: threshold,
            mfps: mfps,
            nlocktimeDeltaBlocks: nlocktimeDeltaBlocks,
          );

          if (label != null && label.isNotEmpty) {
            try {
              psbt = _handle.setPsbtLabel(id: psbt.id.toInt(), label: label);
            } catch (_) {}
          }

          return psbt;
        },
        tag: 'LoadedWallet.createPsbt',
      );

  @override
  WalletOpResult<void> deletePsbt(int id) => guardSync<void>(
        () => _handle.deletePsbt(id: id),
        tag: 'LoadedWallet.deletePsbt',
      );

  @override
  Future<WalletOpResult<PsbtImported>> importPsbt(String psbtBase64) =>
      guardAsync<PsbtImported>(
        () async {
          final result = await _handle.importPsbt(psbtBase64: psbtBase64);
          final psbt = result.psbt;

          APIPsbtAnalysis? analysis;
          try {
            analysis = await _handle.analyzePsbt(
              psbtBase64: psbt.psbtBase64,
              mfps: psbt.mfps,
            );
          } catch (_) {}

          return PsbtImported(psbt: psbt, wasMerged: result.wasMerged, analysis: analysis);
        },
        tag: 'LoadedWallet.importPsbt',
      );

  @override
  Future<WalletOpResult<PsbtUpdated>> mergePsbt(int id, String signedPsbtBase64) =>
      guardAsync<PsbtUpdated>(
        () async {
          final updated = _handle.mergePsbt(id: id, signedPsbtBase64: signedPsbtBase64);
          APIPsbtAnalysis? analysis;
          try {
            analysis = await _handle.analyzePsbt(
              psbtBase64: updated.psbtBase64,
              mfps: updated.mfps,
            );
          } catch (_) {}
          return PsbtUpdated(psbt: updated, analysis: analysis);
        },
        tag: 'LoadedWallet.mergePsbt',
      );

  @override
  Future<WalletOpResult<String>> broadcastPsbt(int id, String electrumUrl) =>
      guardAsync<String>(
        () => _handle.broadcastPsbt(id: id, electrumUrl: electrumUrl),
        tag: 'LoadedWallet.broadcastPsbt',
      );

  // ─── Hot keys ──────────────────────────────────────────────────────────

  @override
  WalletOpResult<APIHotKeyInfo> addMnemonicKey(String mnemonic, String? passphrase) =>
      guardSync<APIHotKeyInfo>(
        () => _handle.addMnemonicKey(mnemonic: mnemonic, passphrase: passphrase),
        tag: 'LoadedWallet.addMnemonicKey',
      );

  @override
  WalletOpResult<APIHotKeyInfo> addXprvKey(String xprv) =>
      guardSync<APIHotKeyInfo>(
        () => _handle.addXprvKey(xprv: xprv),
        tag: 'LoadedWallet.addXprvKey',
      );

  @override
  WalletOpResult<void> deleteHotKey(String mfp) => guardSync<void>(
        () => _handle.deleteHotKey(mfp: mfp),
        tag: 'LoadedWallet.deleteHotKey',
      );

  @override
  WalletOpResult<String?> revealHotKey(String mfp) =>
      guardSync<String?>(
        () => _handle.revealHotKey(mfp: mfp),
        tag: 'LoadedWallet.revealHotKey',
      );

  @override
  WalletOpResult<String?> revealAddressWif(String address, String mfp) =>
      guardSync<String?>(
        () => _handle.deriveAddressWif(address: address, mfp: mfp),
        tag: 'LoadedWallet.revealAddressWif',
      );

  @override
  Future<WalletOpResult<PsbtUpdated>> signPsbtWithKey(int psbtId, String mfp) =>
      guardAsync<PsbtUpdated>(
        () async {
          final updated = _handle.signPsbtWithKey(psbtId: psbtId, mfp: mfp);
          APIPsbtAnalysis? analysis;
          try {
            analysis = await _handle.analyzePsbt(
              psbtBase64: updated.psbtBase64,
              mfps: updated.mfps,
            );
          } catch (_) {}
          return PsbtUpdated(psbt: updated, analysis: analysis);
        },
        tag: 'LoadedWallet.signPsbtWithKey',
      );

  // ─── Fiat ──────────────────────────────────────────────────────────────

  @override
  String? setFiatConfig({
    required bool enabled,
    required String currency,
    required PriceProviderType provider,
  }) =>
      _fiat.setFiatConfig(enabled: enabled, currency: currency, provider: provider);

  @override
  Future<WalletOpResult<FiatPricesUpdate?>> fetchFiatPrices({
    required String currency,
    required bool enabled,
  }) async {
    if (_fiat.isFetching || !enabled || _fiat.priceService == null) {
      if (_fiat.isFetching) _fiat.needsRefetch = true;
      return const Ok(null);
    }

    _fiat.isFetching = true;
    try {
      final service = _fiat.priceService!;
      final now = DateTime.now();

      final (missing, currentBtcPrice, existingStored) = await (
        _handle.getTxidsMissingFiat(currency: currency),
        service.getBtcPrice(currency, now),
        _handle.getFiatPrices(currency: currency),
      ).wait;

      final allPrices = <String, double>{
        for (final p in existingStored) p.txid: p.btcPrice,
      };

      if (missing.isNotEmpty) {
        final Map<String, ({DateTime time, List<String> txids})> byBucket = {};
        for (final tx in missing) {
          final time = tx.confirmationTime != null
              ? DateTime.fromMillisecondsSinceEpoch(tx.confirmationTime! * 1000)
              : now;
          final key = tx.confirmationTime != null
              ? formatDate(time.toUtc())
              : 'current';
          final bucket =
              byBucket.putIfAbsent(key, () => (time: time, txids: []));
          bucket.txids.add(tx.txid);
        }

        final entries = byBucket.entries.toList();
        final prices = await Future.wait(
          entries.map((e) => e.key == 'current'
              ? Future.value(currentBtcPrice)
              : service.getBtcPrice(currency, e.value.time)),
        );

        final storeFutures = <Future<void>>[];
        for (var i = 0; i < entries.length; i++) {
          final price = prices[i];
          if (price == null) continue;
          for (final txid in entries[i].value.txids) {
            allPrices[txid] = price;
            storeFutures.add(
              _handle.storeFiatPrice(
                txid: txid,
                currency: currency,
                btcPrice: price,
              ),
            );
          }
        }
        await Future.wait(storeFutures);
      }

      return Ok(FiatPricesUpdate(
        prices: allPrices,
        currentBtcPrice: currentBtcPrice,
      ));
    } catch (e) {
      return Err('LoadedWallet.fetchFiatPrices: $e');
    } finally {
      _fiat.isFetching = false;
      if (_fiat.needsRefetch) {
        _fiat.clearNeedsRefetch();
      }
    }
  }

  // ─── Internal helpers ──────────────────────────────────────────────────

  /// Fetch chain state (info + balance + transactions + tip) in parallel.
  Future<ChainSnapshot> _fetchChain() async {
    final (info, balance, transactions, tipHeight) = await (
      _handle.getInfo(),
      _handle.getBalance(),
      _handle.getTransactions(page: 0, pageSize: _pageSize),
      _handle.getTipHeight(),
    ).wait;
    return ChainSnapshot(
      info: info,
      balance: balance,
      transactions: transactions,
      tipHeight: tipHeight,
    );
  }
}

/// Analyze a list of PSBTs in parallel, returning a map from PSBT id to
/// analysis result. Errors on individual PSBTs are silently dropped so that
/// a single broken PSBT doesn't block the rest.
Future<Map<int, APIPsbtAnalysis>> analyzeAllPsbts(
  ApiWallet handle,
  List<APIPsbtInfo> psbts,
) async {
  final entries = await Future.wait(
    psbts.map((psbt) async {
      try {
        final analysis = await handle.analyzePsbt(
          psbtBase64: psbt.psbtBase64,
          mfps: psbt.mfps,
        );
        return MapEntry(psbt.id.toInt(), analysis);
      } catch (_) {
        return null;
      }
    }),
  );
  return Map.fromEntries(
    entries.whereType<MapEntry<int, APIPsbtAnalysis>>(),
  );
}
