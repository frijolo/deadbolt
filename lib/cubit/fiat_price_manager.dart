import 'package:deadbolt/services/price_service.dart'
    show PriceProviderType, PriceService;

/// Operational fiat-price state for an opened wallet.
///
/// Owns the [PriceService] instance plus the in-flight / debounce flags. Lives
/// alongside [LoadedWalletImpl] so the cubit never has to track these fields.
class FiatPriceManager {
  PriceService? priceService;
  bool isFetching = false;
  bool needsRefetch = false;

  bool _enabled = false;
  String? _currency;
  PriceProviderType? _provider;

  /// Apply a new fiat configuration. Returns:
  /// - `null` if the config is unchanged (caller can short-circuit),
  /// - `'disabled'` if fiat just got turned off,
  /// - the new currency string otherwise.
  String? setFiatConfig({
    required bool enabled,
    required String currency,
    required PriceProviderType provider,
  }) {
    final sameConfig =
        enabled == _enabled && currency == _currency && provider == _provider;
    if (sameConfig) return null;

    _enabled = enabled;
    _currency = currency;
    _provider = provider;

    if (!enabled) {
      priceService = null;
      return 'disabled';
    }

    if (priceService == null || priceService!.providerType != provider) {
      priceService = PriceService(provider);
    }
    return currency;
  }

  void clearNeedsRefetch() {
    needsRefetch = false;
  }
}

class FiatPricesUpdate {
  final Map<String, double> prices;
  final double? currentBtcPrice;
  const FiatPricesUpdate({required this.prices, this.currentBtcPrice});
}
