import 'dart:async';

import 'package:flutter_bloc/flutter_bloc.dart';

import 'package:deadbolt/cubit/cubit_error_logger.dart';
import 'package:deadbolt/cubit/wallet_detail/lifecycle.dart';
import 'package:deadbolt/cubit/wallet_detail_session.dart' show PsbtList, TransactionPage;
import 'package:deadbolt/cubit/wallet_detail_state.dart';
import 'package:deadbolt/config/constants.dart' show kPageSize;
import 'package:deadbolt/cubit/wallet_op_result.dart' show Ok, Err;
import 'package:deadbolt/src/rust/api/model.dart';

/// PSBT lifecycle: preview, RBF/CPFP info, CRUD, broadcast and the
/// "directSend" shortcut for hot single-sig wallets.
mixin WalletDetailPsbt
    on Cubit<WalletDetailState>, CubitErrorLogger, WalletDetailLifecycle {
  static const _pageSize = kPageSize;

  Future<APIRbfInfo?> getRbfInfo(String spendingTxid) async {
    final current = loadedState;
    if (current == null) return null;
    try {
      return await current.walletHandle.getRbfInfo(spendingTxid: spendingTxid);
    } catch (_) {
      return null;
    }
  }

  /// Stateless: build a tx preview (fee, change, send, weight, RBF min fee) without
  /// persisting a PSBT. Returns null if the wallet is not in a loaded state or the
  /// preview FFI throws (invalid input, etc.). Insufficient funds is a flag inside
  /// the preview, not an error.
  APITxPreview? previewPsbt({
    required List<APIRecipient> recipients,
    int? maxRecipientIndex,
    double? feeRateSatPerVb,
    BigInt? feeAbsoluteSat,
    required List<APICoinControl> selectedUtxos,
    required List<APIPolicyPath> policyPath,
    required int spendPathId,
    required List<APIRbfInfo> rbfInfos,
  }) {
    final current = loadedState;
    if (current == null) return null;
    try {
      return current.walletHandle.previewPsbt(
        recipients: recipients,
        maxRecipientIndex: maxRecipientIndex,
        feeRateSatPerVb: feeRateSatPerVb,
        feeAbsoluteSat: feeAbsoluteSat,
        selectedUtxos: selectedUtxos,
        policyPath: policyPath,
        spendPathId: spendPathId,
        rbfInfos: rbfInfos,
      );
    } catch (_) {
      return null;
    }
  }

  Future<dynamic> getCpfpInfo(List<String> parentTxids) async {
    final current = loadedState;
    if (current == null) return null;
    try {
      return await current.walletHandle.getCpfpInfo(parentTxids: parentTxids);
    } catch (_) {
      return null;
    }
  }

  Future<void> loadPsbts() => runWalletOp(
        (s) => s.wallet.loadPsbts(),
        (s, value) => s.copyWith(
          psbts: PsbtList(
            psbts: value.psbts,
            analyses: value.analyses,
            loaded: true,
          ),
        ),
      );

  Future<APIPsbtInfo?> createPsbt({
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
  }) async {
    final current = loadedState;
    if (current == null) return null;
    final result = current.wallet.createPsbt(
      recipients: recipients,
      maxRecipientIndex: maxRecipientIndex,
      feeAbsoluteSat: feeAbsoluteSat,
      selectedUtxos: selectedUtxos,
      policyPath: policyPath,
      spendPathId: spendPathId,
      threshold: threshold,
      mfps: mfps,
      label: label,
      nlocktimeDeltaBlocks: nlocktimeDeltaBlocks,
    );
    switch (result) {
      case Err(:final message):
        emit(current.copyWith(errorMessage: message));
        return null;
      case Ok(:final value):
        unawaited(loadPsbts().then((_) => reloadCoinsIfLoaded()));
        return value;
    }
  }

  /// Hot single-sig shortcut: create + sign + broadcast in one call.
  /// Lives in this mixin (not hot_keys) because the broadcast/recovery
  /// path is inseparable from the PSBT lifecycle.
  ///
  /// Returns `null` when [createPsbt] fails: the error has already been
  /// surfaced via `errorMessage`, so the caller must not display another
  /// error. Sign/broadcast errors still throw (broadcast preserves the
  /// `Future<String>` contract for the regular PSBT flow).
  Future<String?> directSend({
    required List<APIRecipient> recipients,
    int? maxRecipientIndex,
    required int feeAbsoluteSat,
    required List<APICoinControl> selectedUtxos,
    required List<APIPolicyPath> policyPath,
    required int spendPathId,
    required int threshold,
    required List<String> mfps,
    String? label,
    required String electrumUrl,
  }) async {
    final current = loadedState;
    if (current == null) {
      throw StateError('Wallet not loaded');
    }
    final psbt = await createPsbt(
      recipients: recipients,
      maxRecipientIndex: maxRecipientIndex,
      feeAbsoluteSat: feeAbsoluteSat,
      selectedUtxos: selectedUtxos,
      policyPath: policyPath,
      spendPathId: spendPathId,
      threshold: threshold,
      mfps: mfps,
      label: label,
    );
    if (psbt == null) return null;
    try {
      current.walletHandle.signPsbtWithKey(psbtId: psbt.id.toInt(), mfp: mfps.first);
    } catch (e, st) {
      logError('WalletDetailCubit.directSend() sign', e, st);
      rethrow;
    }
    return broadcastPsbt(psbt.id.toInt(), electrumUrl);
  }

  void deletePsbt(int id) {
    final current = loadedState;
    if (current == null) return;
    final result = current.wallet.deletePsbt(id);
    switch (result) {
      case Err(:final message):
        emit(current.copyWith(errorMessage: message));
      case Ok():
        emit(current.copyWith(
          psbts: PsbtList(
            psbts: current.psbts.where((p) => p.id.toInt() != id).toList(),
            analyses: Map<int, APIPsbtAnalysis>.from(current.psbtAnalyses)..remove(id),
            loaded: true,
          ),
        ));
        unawaited(reloadCoinsIfLoaded());
    }
  }

  APIPsbtInfo? setPsbtLabel(int id, String label) {
    final current = loadedState;
    if (current == null) return null;
    try {
      final updated = current.walletHandle.setPsbtLabel(id: id, label: label);
      emit(current.copyWith(
        psbts: PsbtList(
          psbts: current.psbts.map((p) => p.id.toInt() == id ? updated : p).toList(),
          analyses: current.psbtAnalyses,
          loaded: true,
        ),
      ));
      return updated;
    } catch (e, st) {
      logError('WalletDetailCubit.setPsbtLabel()', e, st);
      return null;
    }
  }

  APIPsbtInfo? setPsbtAutoBroadcast(int id, bool enabled) {
    final current = loadedState;
    if (current == null) return null;
    final existing = current.psbts.where((p) => p.id.toInt() == id).firstOrNull;
    if (existing != null && existing.autoBroadcast == enabled) return existing;
    try {
      final updated =
          current.walletHandle.setPsbtAutoBroadcast(id: id, enabled: enabled);
      emit(current.copyWith(
        psbts: PsbtList(
          psbts: current.psbts.map((p) => p.id.toInt() == id ? updated : p).toList(),
          analyses: current.psbtAnalyses,
          loaded: true,
        ),
      ));
      return updated;
    } catch (e, st) {
      logError('WalletDetailCubit.setPsbtAutoBroadcast()', e, st);
      return null;
    }
  }

  Future<APIImportPsbtResult?> importPsbt(String psbtBase64) async {
    final current = loadedState;
    if (current == null) return null;
    final result = await current.wallet.importPsbt(psbtBase64);
    switch (result) {
      case Err(:final message):
        emit(current.copyWith(errorMessage: message));
        return null;
      case Ok(:final value):
        final id = value.psbt.id.toInt();
        final updatedPsbts = value.wasMerged
            ? current.psbts.map((p) => p.id.toInt() == id ? value.psbt : p).toList()
            : [value.psbt, ...current.psbts];
        final analyses = value.analysis != null
            ? (Map<int, APIPsbtAnalysis>.from(current.psbtAnalyses)..[id] = value.analysis!)
            : current.psbtAnalyses;
        emit(current.copyWith(
          psbts: PsbtList(psbts: updatedPsbts, analyses: analyses, loaded: true),
        ));
        return APIImportPsbtResult(psbt: value.psbt, wasMerged: value.wasMerged);
    }
  }

  Future<APIPsbtInfo?> mergePsbt(int id, String signedPsbtBase64) async {
    final current = loadedState;
    if (current == null) return null;
    final result = await current.wallet.mergePsbt(id, signedPsbtBase64);
    switch (result) {
      case Err(:final message):
        emit(current.copyWith(errorMessage: message));
        return null;
      case Ok(:final value):
        final updatedPsbts = current.psbts
            .map((p) => p.id.toInt() == id ? value.psbt : p)
            .toList();
        final analyses = value.analysis != null
            ? (Map<int, APIPsbtAnalysis>.from(current.psbtAnalyses)..[id] = value.analysis!)
            : current.psbtAnalyses;
        emit(current.copyWith(
          psbts: PsbtList(psbts: updatedPsbts, analyses: analyses, loaded: true),
        ));
        return value.psbt;
    }
  }

  Future<String?> broadcastPsbt(int id, String electrumUrl) async {
    final current = loadedState;
    if (current == null) {
      throw StateError('Wallet not loaded');
    }
    final result = await current.wallet.broadcastPsbt(id, electrumUrl);
    switch (result) {
      case Err(:final message):
        emit(current.copyWith(errorMessage: message));
        return null;
      case Ok(:final value):
        final updatedPsbts = current.psbts.where((p) => p.id.toInt() != id).toList();
        final updatedAnalyses = Map<int, APIPsbtAnalysis>.from(current.psbtAnalyses)..remove(id);
        final page = await current.walletHandle.getTransactions(page: 0, pageSize: _pageSize);
        final after = loadedState;
        if (after != null) {
          emit(after.copyWith(
            psbts: PsbtList(psbts: updatedPsbts, analyses: updatedAnalyses, loaded: true),
            txPage: TransactionPage(
              transactions: page.transactions,
              totalCount: page.totalCount,
              hasMore: page.hasMore,
              currentPage: 0,
            ),
          ));
        }
        unawaited(syncService.syncWallet(current.walletInfo.walletPath));
        return value;
    }
  }
}
