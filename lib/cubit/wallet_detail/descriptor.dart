import 'dart:async';

import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:meta/meta.dart';

import 'package:deadbolt/cubit/cubit_error_logger.dart';
import 'package:deadbolt/cubit/wallet_detail/lifecycle.dart';
import 'package:deadbolt/cubit/wallet_detail_session.dart'
    show DescriptorView, TransactionPage;
import 'package:deadbolt/cubit/wallet_detail_state.dart';
import 'package:deadbolt/src/rust/api/model.dart';

/// Descriptor analysis + tx/key/path label setters + BIP329 import/export.
///
/// Owns [refreshAllAfterLabelChange] because every label setter funnels
/// through it; also owns [loadDescriptorAnalysis] which is invoked from
/// lifecycle (`load`, `selectTab`) and rescan.
mixin WalletDetailDescriptor
    on Cubit<WalletDetailState>, CubitErrorLogger, WalletDetailLifecycle {
  @override
  @protected
  Future<void> loadDescriptorAnalysis() => runWalletOp(
        (s) => s.wallet.loadDescriptorAnalysis(s.walletInfo.descriptor),
        (s, value) => s.copyWith(
          descriptor: DescriptorView(
            analysis: value.analysis,
            keyLabels: value.keyLabels,
            pathLabels: value.pathLabels,
            loaded: true,
          ),
        ),
      );

  @override
  @protected
  Future<void> refreshAllAfterLabelChange() async {
    final current = loadedState;
    if (current == null) return;

    if (current.receiveAddressesLoaded) unawaited(loadAddresses(APIKeychain.external_));
    if (current.changeAddressesLoaded) unawaited(loadAddresses(APIKeychain.internal));
    if (current.utxosLoaded) unawaited(loadUtxos());

    await runWalletOp(
      (s) => s.wallet.refreshAfterLabelChange(s.currentPage),
      (s, value) => s.copyWith(
        txPage: TransactionPage(
          transactions: value.page.transactions,
          totalCount: value.page.totalCount,
          hasMore: value.page.hasMore,
          currentPage: s.currentPage,
        ),
      ),
    );
  }

  Future<void> setTxLabel(String txid, String label) async {
    final current = loadedState;
    if (current == null) return;
    current.walletHandle.setTxLabel(txid: txid, label: label);
    await refreshAllAfterLabelChange();
  }

  void setWalletKeyLabel(String mfp, String label) {
    final current = loadedState;
    if (current == null) return;
    current.walletHandle.setKeyLabel(mfp: mfp, label: label);
    final updated = Map<String, String>.from(current.keyLabels);
    if (label.isEmpty) {
      updated.remove(mfp);
    } else {
      updated[mfp] = label;
    }
    emit(current.copyWith(
      descriptor: DescriptorView(
        analysis: current.descriptorAnalysis,
        keyLabels: updated,
        pathLabels: current.pathLabels,
        loaded: current.descriptorLoaded,
      ),
    ));
  }

  void setWalletPathLabel(int rustId, String label) {
    final current = loadedState;
    if (current == null) return;
    current.walletHandle.setPathLabel(rustId: rustId, label: label);
    final updated = Map<int, String>.from(current.pathLabels);
    if (label.isEmpty) {
      updated.remove(rustId);
    } else {
      updated[rustId] = label;
    }
    emit(current.copyWith(
      descriptor: DescriptorView(
        analysis: current.descriptorAnalysis,
        keyLabels: current.keyLabels,
        pathLabels: updated,
        loaded: current.descriptorLoaded,
      ),
    ));
  }

  Future<String?> exportBip329Labels() async {
    final current = loadedState;
    if (current == null) return null;
    try {
      final lines = current.walletHandle.exportBip329();
      return lines.join('\n');
    } catch (e, st) {
      emitError('exportBip329Labels', e, st);
      return null;
    }
  }

  Future<bool> importBip329Labels(String content) async {
    final current = loadedState;
    if (current == null) return false;
    try {
      final lines = content
          .split('\n')
          .map((l) => l.trim())
          .where((l) => l.isNotEmpty)
          .toList();
      current.walletHandle.importBip329(lines: lines);
      await refreshAllAfterLabelChange();
      return true;
    } catch (e, st) {
      emitError('importBip329Labels', e, st);
      return false;
    }
  }
}
