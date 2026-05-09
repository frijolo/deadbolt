import 'package:flutter/gestures.dart' show DragStartBehavior;
import 'package:deadbolt/config/constants.dart' show kMonospaceFontFamily;
import 'package:flutter/material.dart';
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
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (ctx) => const _WifConfirmDialog(),
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

class _WifConfirmDialog extends StatefulWidget {
  const _WifConfirmDialog();

  @override
  State<_WifConfirmDialog> createState() => _WifConfirmDialogState();
}

class _WifConfirmDialogState extends State<_WifConfirmDialog> {
  final _controller = TextEditingController();
  bool _confirmed = false;

  @override
  void initState() {
    super.initState();
    _controller.addListener(_onChanged);
  }

  void _onChanged() {
    final phrase = context.l10n.wifExportConfirmPhrase;
    final ok = _controller.text.trim().toLowerCase() == phrase.toLowerCase();
    if (ok != _confirmed) setState(() => _confirmed = ok);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final scheme = Theme.of(context).colorScheme;
    final phrase = l10n.wifExportConfirmPhrase;

    return AlertDialog(
      title: Text(l10n.wifExportTitle),
      content: SingleChildScrollView(
        dragStartBehavior: DragStartBehavior.down,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: scheme.errorContainer,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(Icons.warning_amber_rounded,
                      size: 20, color: scheme.onErrorContainer),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      l10n.wifExportWarning,
                      style: TextStyle(
                        fontSize: 13,
                        color: scheme.onErrorContainer,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),
            Text(
              l10n.wifExportTypeToConfirm,
              style: TextStyle(
                fontSize: 12,
                color: scheme.onSurface.withAlpha(153),
              ),
            ),
            const SizedBox(height: 4),
            Text(
              phrase,
              style: TextStyle(
                fontSize: 13,
                fontStyle: FontStyle.italic,
                color: scheme.onSurface.withAlpha(180),
              ),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _controller,
              autofocus: true,
              autocorrect: false,
              enableSuggestions: false,
              decoration: InputDecoration(
                hintText: phrase,
                isDense: true,
                border: const OutlineInputBorder(),
                suffixIcon: _confirmed
                    ? Icon(Icons.check_circle,
                        color: scheme.primary, size: 18)
                    : null,
              ),
              style: const TextStyle(fontSize: 13),
              onSubmitted: _confirmed
                  ? (_) => Navigator.pop(context, true)
                  : null,
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: Text(l10n.cancel),
        ),
        FilledButton(
          onPressed:
              _confirmed ? () => Navigator.pop(context, true) : null,
          child: Text(l10n.wifExportShowButton),
        ),
      ],
    );
  }
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
        l10n.sweepWifPrivateKeySection,
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
                      l10n.wifDisplayWarning,
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

            Text(l10n.coinAddress,
                style: TextStyle(
                    fontSize: 11,
                    color: scheme.onSurface.withAlpha(153))),
            const SizedBox(height: 4),
            SelectableText(
              address,
              style: const TextStyle(fontFamily: kMonospaceFontFamily, fontSize: 12),
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

            Text(l10n.wifPrivateKeyLabel,
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
                style: const TextStyle(fontFamily: kMonospaceFontFamily, fontSize: 12),
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton.icon(
          icon: const Icon(Icons.copy, size: 16),
          label: Text(l10n.copyToClipboard),
          onPressed: () async {
            await copySecretAndScheduleClear(
              wif,
              successMessage: context.l10n.keyCopied,
            );
            if (context.mounted) Navigator.of(context).pop();
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
