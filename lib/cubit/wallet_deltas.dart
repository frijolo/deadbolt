import 'package:deadbolt/src/rust/api/analyzer.dart' show APIAnalysisResult;
import 'package:deadbolt/src/rust/api/model.dart'
    show
        APIAddress,
        APIBalance,
        APIPsbtAnalysis,
        APIPsbtInfo,
        APITransactionPage,
        APIUtxo,
        APIWalletInfo;

/// Delta types produced by [LoadedWallet] operations. Each delta carries only
/// what the operation produced — never reconstructed lists or maps that the
/// cubit already holds in its state. The cubit is responsible for applying
/// the delta to its [WalletDetailLoaded] state.
///
/// Supersedes the older `*Result` classes whose nullable fields conflated
/// "this op didn't produce X" with "X is missing".

/// Chain-side update produced by a successful sync or rescan.
class ChainSnapshot {
  final APIWalletInfo info;
  final APIBalance balance;
  final APITransactionPage transactions;
  final int tipHeight;

  const ChainSnapshot({
    required this.info,
    required this.balance,
    required this.transactions,
    required this.tipHeight,
  });
}

/// Address list refresh for a single keychain.
class AddressUpdate {
  final List<APIAddress> addresses;
  const AddressUpdate(this.addresses);
}

/// UTXO list refresh.
class CoinUpdate {
  final List<APIUtxo> utxos;
  const CoinUpdate(this.utxos);
}

/// PSBT list + analyses refresh.
class PsbtSnapshot {
  final List<APIPsbtInfo> psbts;
  final Map<int, APIPsbtAnalysis> analyses;
  const PsbtSnapshot({required this.psbts, required this.analyses});
}

/// Output of a sync event: any subset of the data layers may have refreshed.
/// Sub-objects are null when that layer was not previously loaded (the cubit
/// preserves its existing state for those).
class SyncReload {
  final ChainSnapshot? chain;
  final AddressUpdate? receive;
  final AddressUpdate? change;
  final CoinUpdate? coins;
  final PsbtSnapshot? psbts;
  final bool wasSyncing;
  final bool retryNeeded;

  const SyncReload({
    this.chain,
    this.receive,
    this.change,
    this.coins,
    this.psbts,
    this.wasSyncing = false,
    this.retryNeeded = false,
  });

  /// Marker for "sync started" event — no data refresh, just UI state.
  const SyncReload.syncing()
      : chain = null,
        receive = null,
        change = null,
        coins = null,
        psbts = null,
        wasSyncing = true,
        retryNeeded = false;

  /// Marker for the "missing tx" retry case — caller schedules a retry timer.
  const SyncReload.retry()
      : chain = null,
        receive = null,
        change = null,
        coins = null,
        psbts = null,
        wasSyncing = false,
        retryNeeded = true;
}

/// Output of [LoadedWallet.importPsbt].
class PsbtImported {
  final APIPsbtInfo psbt;
  final bool wasMerged;
  final APIPsbtAnalysis? analysis;

  const PsbtImported({
    required this.psbt,
    required this.wasMerged,
    this.analysis,
  });
}

/// Output of [LoadedWallet.mergePsbt] and [LoadedWallet.signPsbtWithKey].
class PsbtUpdated {
  final APIPsbtInfo psbt;
  final APIPsbtAnalysis? analysis;

  const PsbtUpdated({required this.psbt, this.analysis});
}

/// Output of [LoadedWallet.loadDescriptorAnalysis].
class DescriptorSnapshot {
  final APIAnalysisResult analysis;
  final Map<String, String> keyLabels;
  final Map<int, String> pathLabels;

  const DescriptorSnapshot({
    required this.analysis,
    required this.keyLabels,
    required this.pathLabels,
  });
}

/// Output of [LoadedWallet.loadMoreTransactions].
class TransactionPageDelta {
  final APITransactionPage page;
  final int currentPage;

  const TransactionPageDelta({required this.page, required this.currentPage});
}
