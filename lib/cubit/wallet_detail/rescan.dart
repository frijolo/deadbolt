import 'dart:async';

import 'package:flutter_bloc/flutter_bloc.dart';

import 'package:deadbolt/cubit/cubit_error_logger.dart';
import 'package:deadbolt/cubit/wallet_detail/lifecycle.dart';
import 'package:deadbolt/cubit/wallet_detail_session.dart'
    show AddressView, CoinView, DescriptorView, TransactionPage, WalletInfo;
import 'package:deadbolt/cubit/wallet_detail_state.dart';
import 'package:deadbolt/cubit/wallet_op_result.dart' show Ok, Err;

/// Cross-domain reset: drops cached views and rehydrates from a full Electrum
/// rescan. Lives on its own because no other handler invalidates this many
/// sub-states atomically.
mixin WalletDetailRescan
    on Cubit<WalletDetailState>, CubitErrorLogger, WalletDetailLifecycle {
  Future<void> rescan(String electrumUrl) async {
    final current = loadedState;
    if (current == null) return;

    emit(current.copyWith(isSyncing: true));
    final result = await current.wallet.rescan(electrumUrl);
    final after = loadedState;
    if (after == null) return;
    switch (result) {
      case Err(:final message):
        emit(after.copyWith(
          isSyncing: false,
          errorMessage: message,
        ));
      case Ok(:final value):
        emit(current.copyWith(
          info: WalletInfo(
            walletInfo: value.info,
            balance: value.balance,
            hasBiometricSlot: current.hasBiometricSlot,
            tipHeight: value.tipHeight,
          ),
          txPage: TransactionPage(
            transactions: value.transactions.transactions,
            totalCount: value.transactions.totalCount,
            hasMore: value.transactions.hasMore,
            currentPage: 0,
          ),
          addresses: const AddressView(
            receiveAddresses: [],
            changeAddresses: [],
            receiveLoaded: false,
            changeLoaded: false,
            selectedKeychain: 0,
          ),
          coins: const CoinView(utxos: [], loaded: false),
          descriptor: const DescriptorView(keyLabels: {}, pathLabels: {}, loaded: false),
          isSyncing: false,
        ));
        unawaited(Future.wait([
          loadDescriptorAnalysis(),
          loadUtxos(),
        ]));
    }
  }
}
