import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import 'package:deadbolt/cubit/wallet_detail_cubit.dart';
import 'package:deadbolt/l10n/l10n.dart';
import 'package:deadbolt/screens/create_tx_screen.dart';
import 'package:deadbolt/utils/toast_helper.dart';

export 'package:deadbolt/screens/wallet_detail/shared_detail_widgets.dart';
export 'package:deadbolt/screens/wallet_detail/dialogs/detail_dialogs.dart';

// ─────────────────────────────────────────────────────────────
// CPFP navigation helper
// ─────────────────────────────────────────────────────────────

/// Opens [CreateTxScreen] pre-loaded with [utxos] for CPFP acceleration.
Future<void> openCpfpTx(
  BuildContext context,
  WalletDetailLoaded walletState,
  List<APIUtxo> utxos,
) async {
  final l10n = context.l10n;
  final cubit = context.read<WalletDetailCubit>();
  final address = await cubit.getNextSelfPaymentAddress();
  if (!context.mounted) return;
  if (address == null) {
    showErrorToast(context, l10n.createTxNoUnusedAddress);
    return;
  }
  await CreateTxScreen.push(
    context,
    allUtxos: walletState.utxos,
    tipHeight: walletState.tipHeight,
    spendPaths: walletState.descriptorAnalysis?.spendPaths,
    keyLabels: walletState.keyLabels,
    pathLabels: walletState.pathLabels,
    preSelectedUtxos: utxos,
    preFilledRecipient: address,
  );
}
