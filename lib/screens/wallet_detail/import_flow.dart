import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:deadbolt/l10n/l10n.dart';
import 'package:deadbolt/cubit/wallet_detail_cubit.dart';
import 'package:deadbolt/src/rust/api/model.dart';
import 'package:deadbolt/utils/toast_helper.dart';
import 'package:deadbolt/widgets/text_import_sheet.dart' show showTextImportSheet, showPsbtImportSheet;
import 'package:deadbolt/screens/sweep_wif_screen.dart';

enum _ImportChoice { labels, psbt, sweepWif }

Future<void> showImportChoiceSheet(
  BuildContext context, {
  required String walletPath,
  required APINetwork network,
}) async {
  final l10n = context.l10n;
  final choice = await showModalBottomSheet<_ImportChoice>(
    context: context,
    builder: (ctx) => SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ListTile(
            leading: const Icon(Icons.label_outline),
            title: Text(l10n.exportLabelsOption),
            onTap: () => Navigator.of(ctx).pop(_ImportChoice.labels),
          ),
          ListTile(
            leading: const Icon(Icons.receipt_long_outlined),
            title: Text(l10n.importPsbtOption),
            onTap: () => Navigator.of(ctx).pop(_ImportChoice.psbt),
          ),
          ListTile(
            leading: const Icon(Icons.vpn_key_outlined),
            title: Text(l10n.sweepWifTitle),
            onTap: () => Navigator.of(ctx).pop(_ImportChoice.sweepWif),
          ),
          const SizedBox(height: 8),
        ],
      ),
    ),
  );
  if (choice == null || !context.mounted) return;
  switch (choice) {
    case _ImportChoice.labels:
      await _importLabels(context);
    case _ImportChoice.psbt:
      await _importPsbt(context);
    case _ImportChoice.sweepWif:
      _openSweepWif(context, walletPath, network);
  }
}

Future<void> _importLabels(BuildContext context) async {
  final l10n = context.l10n;
  final content = await showTextImportSheet(context, bigText: true);
  if (content == null || content.trim().isEmpty) return;
  if (!context.mounted) return;
  final ok = await context.read<WalletDetailCubit>().importBip329Labels(content);
  if (context.mounted && ok) showSuccessToast(l10n.importBip329Success);
}

Future<void> _importPsbt(BuildContext context) async {
  final l10n = context.l10n;
  final psbtBase64 = await showPsbtImportSheet(context);
  if (psbtBase64 == null || psbtBase64.isEmpty) return;
  if (!context.mounted) return;
  final imported = await context.read<WalletDetailCubit>().importPsbt(psbtBase64);
  if (imported == null) return;
  if (context.mounted) {
    showSuccessToast(
      imported.wasMerged ? l10n.importPsbtMerged : l10n.importPsbtSaved,
    );
  }
}

void _openSweepWif(
  BuildContext context,
  String walletPath,
  APINetwork network,
) {
  final cubit = context.read<WalletDetailCubit>();
  SweepWifScreen.push(
    context,
    network: network,
    currentWalletPath: walletPath,
    getNextAddress: () => cubit.getNextReceiveAddress(),
    getAddressForWallet: (path) => cubit.getNextReceiveAddressFor(path),
    onSwept: () => cubit.sync(),
  );
}
