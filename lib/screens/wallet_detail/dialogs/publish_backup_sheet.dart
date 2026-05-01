import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:deadbolt/cubit/wallet_detail_cubit.dart';
import 'package:deadbolt/l10n/l10n.dart';
import 'package:deadbolt/screens/wallet_detail/dialogs/nostr_backup_sheet.dart';
import 'package:deadbolt/screens/wallet_detail/onchain_backup_screen.dart';
import 'package:deadbolt/widgets/dialog_helpers.dart';

Future<void> showPublishBackupSheet(
  BuildContext context, {
  required WalletDetailLoaded state,
}) {
  return showSheet(
    context,
    (ctx) => BlocProvider.value(
      value: context.read<WalletDetailCubit>(),
      child: _PublishBackupSheet(state: state),
    ),
  );
}

class _PublishBackupSheet extends StatelessWidget {
  final WalletDetailLoaded state;
  const _PublishBackupSheet({required this.state});

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const SheetHandle(),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
          child: Text(l10n.publishBackupTitle,
              style: Theme.of(context).textTheme.titleMedium),
        ),
        ListTile(
          leading: const Icon(Icons.cloud_outlined),
          title: const Text('Nostr'),
          subtitle: Text(l10n.nostrBackupSubtitle),
          onTap: () {
            Navigator.pop(context);
            showNostrBackupSheet(context, state: state);
          },
        ),
        ListTile(
          leading: const Icon(Icons.link),
          title: Text(l10n.onChainBackupTitle),
          subtitle: Text(l10n.onChainBackupSubtitle),
          onTap: () {
            Navigator.pop(context);
            OnchainBackupScreen.push(context, state: state);
          },
        ),
        const SizedBox(height: 8),
      ],
    );
  }
}
