import 'dart:async';

import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:meta/meta.dart';

import 'package:deadbolt/cubit/cubit_error_logger.dart';
import 'package:deadbolt/cubit/wallet_detail/lifecycle.dart';
import 'package:deadbolt/cubit/wallet_detail_session.dart' show FiatPrices;
import 'package:deadbolt/cubit/wallet_detail_state.dart';
import 'package:deadbolt/cubit/wallet_op_result.dart' show Ok, Err;
import 'package:deadbolt/services/price_service.dart' show PriceProviderType;

/// Fiat price configuration + lazy fetch of missing prices after sync.
mixin WalletDetailFiat
    on Cubit<WalletDetailState>, CubitErrorLogger, WalletDetailLifecycle {
  Future<void> setFiatConfig(
    bool enabled,
    String currency,
    PriceProviderType provider,
  ) async {
    final current = loadedState;
    if (current == null) return;

    final newCurrency = current.wallet.setFiatConfig(
      enabled: enabled,
      currency: currency,
      provider: provider,
    );

    if (newCurrency == null) return; // same config

    if (newCurrency == 'disabled') {
      emit(current.copyWith(
        fiat: const FiatPrices(prices: {}, currentBtcPrice: null, currency: null),
      ));
      return;
    }

    emit(current.copyWith(fiat: FiatPrices(
      prices: current.fiatPrices,
      currentBtcPrice: current.currentBtcPrice,
      currency: newCurrency,
    )));
    unawaited(fetchMissingFiatPrices());
  }

  @override
  @protected
  Future<void> fetchMissingFiatPrices() async {
    final s = loadedState;
    if (s == null) return;
    final result = await s.wallet.fetchFiatPrices(
      currency: s.fiatCurrency ?? 'usd',
      enabled: s.fiatCurrency != null,
    );
    final after = loadedState;
    if (after == null) return;
    switch (result) {
      case Err(:final message):
        emit(after.copyWith(errorMessage: message));
      case Ok(:final value):
        if (value == null) return; // no-op (already fetching, disabled)
        emit(after.copyWith(
          fiat: FiatPrices(
            prices: value.prices,
            currentBtcPrice: value.currentBtcPrice,
            currency: after.fiatCurrency,
          ),
        ));
    }
  }
}
