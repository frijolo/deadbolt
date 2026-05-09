import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:meta/meta.dart';

import 'package:deadbolt/cubit/cubit_error_logger.dart';
import 'package:deadbolt/services/wallet_service.dart';
import 'package:deadbolt/services/wallet_sync_service.dart';
import 'package:deadbolt/services/biometric_keystore_service.dart';

import 'package:deadbolt/cubit/wallet_detail/addresses.dart';
import 'package:deadbolt/cubit/wallet_detail/coins.dart';
import 'package:deadbolt/cubit/wallet_detail/descriptor.dart';
import 'package:deadbolt/cubit/wallet_detail/fiat.dart';
import 'package:deadbolt/cubit/wallet_detail/hot_keys.dart';
import 'package:deadbolt/cubit/wallet_detail/lifecycle.dart';
import 'package:deadbolt/cubit/wallet_detail/protection.dart';
import 'package:deadbolt/cubit/wallet_detail/psbt.dart';
import 'package:deadbolt/cubit/wallet_detail/rescan.dart';
import 'package:deadbolt/cubit/wallet_detail/transactions.dart';
import 'package:deadbolt/cubit/wallet_detail_state.dart';
import 'package:deadbolt/cubit/wallet_opener.dart' show WalletOpener, WalletOpenerImpl;

// Re-export state hierarchy so existing imports of wallet_detail_cubit.dart keep compiling
export 'package:deadbolt/cubit/wallet_detail_state.dart';

// Re-export for the screen
export 'package:deadbolt/src/rust/api/analyzer.dart' show APIAnalysisResult;
export 'package:deadbolt/src/rust/api/model.dart'
    show APIUtxo, APIPsbtInfo, APIPsbtAnalysis, APIPsbtSignerStatus, APICoinControl,
        APIPolicyPath, APITxDetails, APIUtxoDetails, APIAddressDetails, APIRelatedUtxo,
        APIRelatedTx, APIRelatedAddress, APIRbfInfo, APIImportPsbtResult, APIHotKeyInfo;

/// Orchestrates wallet detail through two seams:
///
///   * [WalletOpener] — pre-handle ops (credential resolution, lock,
///     biometric slots, protection changes). Returns a [LoadedWallet]
///     wrapped in [WalletLoadSuccess].
///   * [LoadedWallet] — every post-handle op (data loading, PSBTs, hot
///     keys, fiat). Carried inside [WalletDetailLoaded.wallet] and
///     accessed as `current.wallet.xxx()`.
///
/// Errors cross the seam as [WalletOpResult]; each domain mixin
/// pattern-matches `Ok`/`Err` exhaustively and surfaces `Err.message` via
/// [WalletDetailLoaded.errorMessage], which the screen consumes through
/// `handleTransientError` to show a toast.
///
/// Mixin order matters: [WalletDetailLifecycle] must come first (its
/// `emit` override and `loadedState` helper are used by every other mixin).
/// The remaining mixins are independent and ordered roughly by
/// read → mutate → cross-cutting.
class WalletDetailCubit extends Cubit<WalletDetailState>
    with
        CubitErrorLogger,
        WalletDetailLifecycle,
        WalletDetailTransactions,
        WalletDetailAddresses,
        WalletDetailCoins,
        WalletDetailDescriptor,
        WalletDetailPsbt,
        WalletDetailHotKeys,
        WalletDetailFiat,
        WalletDetailProtection,
        WalletDetailRescan {
  static const tabOverview = 0;
  static const tabTransactions = 1;
  static const tabAddresses = 2;
  static const tabCoins = 3;
  static const tabDescriptor = 4;

  final WalletOpener _opener;
  final WalletSyncService _syncService;

  @override
  @protected
  WalletOpener get opener => _opener;

  @override
  @protected
  WalletSyncService get syncService => _syncService;

  WalletDetailCubit({
    required WalletOpener opener,
    required WalletSyncService syncService,
  })  : _opener = opener,
        _syncService = syncService,
        super(WalletDetailInitial());

  /// Factory that ensures all modules share the same [WalletService] instance.
  factory WalletDetailCubit.create({
    WalletService? service,
    required WalletSyncService syncService,
    BiometricKeystoreService? biometricKeystoreService,
  }) {
    final svc = service ?? WalletService();
    return WalletDetailCubit(
      opener: WalletOpenerImpl(
        service: svc,
        syncService: syncService,
        keystoreService: biometricKeystoreService,
      ),
      syncService: syncService,
    );
  }
}
