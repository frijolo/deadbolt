import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:deadbolt/cubit/wallet_detail_cubit.dart';
import 'package:deadbolt/l10n/l10n.dart';
import 'package:deadbolt/screens/wallet_detail/dialogs/nostr_backup_sheet.dart';
import 'package:deadbolt/screens/wallet_detail/onchain_backup_screen.dart';
import 'package:deadbolt/utils/wallet_complexity.dart';
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

class _PublishBackupSheet extends StatefulWidget {
  final WalletDetailLoaded state;
  const _PublishBackupSheet({required this.state});

  @override
  State<_PublishBackupSheet> createState() => _PublishBackupSheetState();
}

class _PublishBackupSheetState extends State<_PublishBackupSheet> {
  bool _showOptions = false;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final cs = Theme.of(context).colorScheme;
    final ts = Theme.of(context).textTheme;
    final singlesig = isDescriptorTriviallyRecoverable(widget.state);

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const SheetHandle(),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
          child: Text(
            singlesig && !_showOptions
                ? l10n.publishBackupSinglesigTitle
                : l10n.publishBackupTitle,
            style: ts.titleMedium,
          ),
        ),
        if (singlesig && !_showOptions) ...[
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
            child: Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: cs.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(Icons.privacy_tip_outlined, size: 18, color: cs.primary),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      l10n.publishBackupSinglesigBody,
                      style: ts.bodySmall?.copyWith(color: cs.onSurfaceVariant),
                    ),
                  ),
                ],
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: Row(
              children: [
                Expanded(
                  child: TextButton(
                    onPressed: () => setState(() => _showOptions = true),
                    child: Text(l10n.publishBackupSinglesigContinue),
                  ),
                ),
              ],
            ),
          ),
        ] else ...[
          ListTile(
            leading: const Icon(Icons.cloud_outlined),
            title: const Text('Nostr'),
            subtitle: Text(l10n.nostrBackupSubtitle),
            onTap: () {
              Navigator.pop(context);
              showNostrBackupSheet(context, state: widget.state);
            },
          ),
          ListTile(
            leading: const Icon(Icons.link),
            title: Text(l10n.onChainBackupTitle),
            subtitle: Text(l10n.onChainBackupSubtitle),
            onTap: () {
              Navigator.pop(context);
              OnchainBackupScreen.push(context, state: widget.state);
            },
          ),
        ],
        const SizedBox(height: 8),
      ],
    );
  }
}
