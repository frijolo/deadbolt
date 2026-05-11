// Deadbolt — Hardware Wallet cubit (public API).
//
// This barrel re-exports all types so existing imports of
// `package:deadbolt/cubit/hw_wallet_cubit.dart` continue working.
// The cubit class mixes in HwWalletPlatform + HwWalletProtocol
// for connection and BTC operation methods.


import 'package:flutter_bloc/flutter_bloc.dart';

import 'hw_wallet/hw_wallet_protocol.dart';
import 'hw_wallet/hw_wallet_platform.dart';
import 'hw_wallet/hw_wallet_states.dart';

// ─── Re-exports for callers ─────────────────────────────────────────────────

// State hierarchy — all states needed by BlocBuilder/BlocConsumer callers
export 'hw_wallet/hw_wallet_states.dart';

// BTC operation result types — callers pattern-match on these
export 'hw_wallet/hw_wallet_states.dart' show HwWalletResult, HwXpubResult, HwSignedPsbtResult, HwRegisteredResult, HwCheckRegistrationResult, HwAddressDisplayedResult;

// ─── Cubit ────────────────────────────────────────────────────────────────────

/// Manages the full hardware wallet lifecycle: scan → connect → pair → operate.
///
/// Connection/platform logic is provided by [HwWalletPlatform] mixin.
/// BTC operations (getXpub, registerDescriptor, signPsbt, etc.) by
/// [HwWalletProtocol] mixin.
class HwWalletCubit extends Cubit<HwWalletState>
    with HwWalletPlatform, HwWalletProtocol {
  HwWalletCubit() : super(HwWalletIdle());
}
