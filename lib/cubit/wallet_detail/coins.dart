import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:meta/meta.dart';

import 'package:deadbolt/cubit/cubit_error_logger.dart';
import 'package:deadbolt/cubit/wallet_detail/lifecycle.dart';
import 'package:deadbolt/cubit/wallet_detail_session.dart' show CoinView;
import 'package:deadbolt/cubit/wallet_detail_state.dart';

/// Coin (UTXO) loading + reload + per-coin label.
mixin WalletDetailCoins
    on Cubit<WalletDetailState>, CubitErrorLogger, WalletDetailLifecycle {
  @override
  @protected
  Future<void> loadUtxos() => runWalletOp(
        (s) => s.wallet.loadUtxos(),
        (s, value) => s.copyWith(
          coins: CoinView(utxos: value.utxos, loaded: true),
        ),
      );

  Future<void> ensureCoinsLoaded() async {
    final current = loadedState;
    if (current == null) return;
    if (!current.utxosLoaded) await loadUtxos();
    if (!current.descriptorLoaded) await loadDescriptorAnalysis();
  }

  @override
  @protected
  Future<void> reloadCoinsIfLoaded() async {
    final s = loadedState;
    if (s == null || !s.utxosLoaded) return;
    emit(s.copyWith(coins: const CoinView(utxos: [], loaded: false)));
    await loadUtxos();
  }

  Future<void> setCoinLabel(String txid, int vout, String label) async {
    final current = loadedState;
    if (current == null) return;
    current.walletHandle.setCoinLabel(txid: txid, vout: vout, label: label);
    await refreshAllAfterLabelChange();
  }
}
