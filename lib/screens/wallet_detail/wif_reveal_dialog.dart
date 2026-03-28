import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:qr_flutter/qr_flutter.dart';

import 'package:deadbolt/cubit/wallet_detail_cubit.dart';
import 'package:deadbolt/l10n/l10n.dart';
import 'package:deadbolt/utils/toast_helper.dart';
import 'package:deadbolt/widgets/dialog_helpers.dart';

/// Shows a confirmation dialog before revealing WIF, then opens [_WifDisplayDialog].
///
/// Call this from any screen that has a [WalletDetailCubit] in scope.
Future<void> showWifExportFlow(
  BuildContext context, {
  required String address,
  required String mfp,
}) async {
  final l10n = context.l10n;
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('Export private key (WIF)'),
      content: const Text(
        'Make sure no one can see your screen. '
        'The WIF key gives full spending access to this address. '
        'Never share it with anyone.',
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx, false),
          child: Text(l10n.cancel),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(ctx, true),
          child: const Text('Show WIF'),
        ),
      ],
    ),
  );

  if (confirmed != true || !context.mounted) return;

  final cubit = context.read<WalletDetailCubit>();
  final wif = await cubit.revealAddressWif(address, mfp);
  if (wif == null || !context.mounted) return;

  await showDialog<void>(
    context: context,
    builder: (ctx) => _WifDisplayDialog(address: address, wif: wif),
  );
}

// ---------------------------------------------------------------------------

class _WifDisplayDialog extends StatelessWidget {
  final String address;
  final String wif;

  const _WifDisplayDialog({required this.address, required this.wif});

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final scheme = Theme.of(context).colorScheme;

    return AlertDialog(
      titlePadding: kDialogTitlePadding,
      title: dialogCloseTitle(
        'Private key (WIF)',
        onClose: () => Navigator.of(context).pop(),
        tooltip: l10n.cancel,
      ),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: scheme.errorContainer,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                children: [
                  Icon(Icons.warning_amber_outlined,
                      size: 18, color: scheme.onErrorContainer),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Never share this key. Anyone with it can spend these funds.',
                      style: TextStyle(
                        fontSize: 12,
                        color: scheme.onErrorContainer,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),

            Text('Address',
                style: TextStyle(
                    fontSize: 11,
                    color: scheme.onSurface.withAlpha(153))),
            const SizedBox(height: 4),
            SelectableText(
              address,
              style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
            ),
            const SizedBox(height: 16),

            Center(
              child: Container(
                width: 200,
                height: 200,
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(8),
                ),
                padding: const EdgeInsets.all(8),
                child: QrImageView(
                  data: wif,
                  version: QrVersions.auto,
                  errorCorrectionLevel: QrErrorCorrectLevel.M,
                  backgroundColor: Colors.white,
                ),
              ),
            ),
            const SizedBox(height: 16),

            Text('WIF private key',
                style: TextStyle(
                    fontSize: 11,
                    color: scheme.onSurface.withAlpha(153))),
            const SizedBox(height: 4),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: scheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(8),
              ),
              child: SelectableText(
                wif,
                style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton.icon(
          icon: const Icon(Icons.copy, size: 16),
          label: Text(l10n.copyToClipboard),
          onPressed: () {
            Clipboard.setData(ClipboardData(text: wif));
            Navigator.of(context).pop();
            showSuccessToast(context, l10n.copiedToClipboard);
          },
        ),
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(l10n.close),
        ),
      ],
    );
  }
}
