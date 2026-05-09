import 'package:deadbolt/cubit/wallet_detail_session.dart'
    show
        WalletInfo,
        TransactionPage,
        AddressView,
        CoinView,
        DescriptorView,
        PsbtList,
        FiatPrices;
import 'package:deadbolt/src/rust/api/model.dart' show APIHotKeyInfo;

/// Immutable update payload for [WalletDetailLoaded.apply].
///
/// All fields default to `null`. The `errorMessage` field uses the sentinel
/// [_kUndef] to mean "not set" (preserving the current value), matching the
/// behavior of [WalletDetailLoaded.copyWith].
///
/// Usage:
/// ```dart
/// final update = WalletDetailUpdate(isSyncing: true, selectedTab: 2);
/// emit(current.apply(update));
/// ```
final class WalletDetailUpdate {
  const WalletDetailUpdate({
    this.info,
    this.txPage,
    this.addresses,
    this.coins,
    this.descriptor,
    this.psbts,
    this.hotKeys,
    this.fiat,
    this.selectedTab,
    this.selectedAddressKeychain,
    this.isSyncing,
    this.errorMessage,
  });

  final WalletInfo? info;
  final TransactionPage? txPage;
  final AddressView? addresses;
  final CoinView? coins;
  final DescriptorView? descriptor;
  final PsbtList? psbts;
  final List<APIHotKeyInfo>? hotKeys;
  final FiatPrices? fiat;
  final int? selectedTab;
  final int? selectedAddressKeychain;
  final bool? isSyncing;
  final Object? errorMessage;
}
