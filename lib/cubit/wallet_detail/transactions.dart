import 'package:flutter_bloc/flutter_bloc.dart';

import 'package:deadbolt/cubit/cubit_error_logger.dart';
import 'package:deadbolt/cubit/wallet_detail/lifecycle.dart';
import 'package:deadbolt/cubit/wallet_detail_session.dart' show TransactionPage;
import 'package:deadbolt/cubit/wallet_detail_state.dart';
import 'package:deadbolt/cubit/wallet_op_result.dart' show Ok, Err;

/// Read-side handler for the transactions tab pagination.
mixin WalletDetailTransactions
    on Cubit<WalletDetailState>, CubitErrorLogger, WalletDetailLifecycle {
  Future<void> loadMoreTransactions() async {
    final current = loadedState;
    if (current == null || !current.hasMore) return;

    final result = await current.wallet.loadMoreTransactions(current.currentPage);
    final after = loadedState;
    if (after == null) return;
    switch (result) {
      case Err(:final message):
        emit(after.copyWith(errorMessage: message));
      case Ok(:final value):
        emit(current.copyWith(
          txPage: TransactionPage(
            transactions: [...current.transactions, ...value.page.transactions],
            totalCount: value.page.totalCount,
            hasMore: value.page.hasMore,
            currentPage: value.currentPage,
          ),
        ));
    }
  }
}
