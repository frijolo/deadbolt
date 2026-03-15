import 'package:flutter_bloc/flutter_bloc.dart';

import 'package:deadbolt/cubit/cubit_error_logger.dart';
import 'package:deadbolt/services/wallet_service.dart';
import 'package:deadbolt/src/rust/api/model.dart';

// --- States ---

sealed class WalletListState {}

class WalletListLoading extends WalletListState {}

class WalletListLoaded extends WalletListState {
  final List<APIWalletInfo> wallets;
  WalletListLoaded(this.wallets);
}

class WalletListError extends WalletListState {
  final String message;
  WalletListError(this.message);
}

// --- Cubit ---

class WalletListCubit extends Cubit<WalletListState> with CubitErrorLogger {
  final WalletService _service;

  WalletListCubit({WalletService? service})
      : _service = service ?? WalletService(),
        super(WalletListLoading()) {
    refresh();
  }

  Future<void> refresh() async {
    try {
      final wallets = await _service.listWallets();
      emit(WalletListLoaded(wallets));
    } catch (e, stackTrace) {
      logError('WalletListCubit.refresh()', e, stackTrace);
      emit(WalletListError(e.toString()));
    }
  }

  Future<String> createWallet({
    required String name,
    required String descriptor,
    required APINetwork network,
    int? sourceProjectId,
  }) async {
    try {
      final info = await _service.createWallet(
        name: name,
        descriptor: descriptor,
        network: network,
        sourceProjectId: sourceProjectId,
      );
      await refresh();
      return info.walletPath;
    } catch (e, stackTrace) {
      logError('WalletListCubit.createWallet()', e, stackTrace);
      rethrow;
    }
  }

  Future<void> deleteWallet(String walletPath) async {
    try {
      await _service.deleteWallet(walletPath);
      await refresh();
    } catch (e, stackTrace) {
      logError('WalletListCubit.deleteWallet()', e, stackTrace);
      rethrow;
    }
  }
}
