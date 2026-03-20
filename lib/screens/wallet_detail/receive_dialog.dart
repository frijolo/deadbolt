import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:qr_flutter/qr_flutter.dart';

import 'package:deadbolt/cubit/wallet_detail_cubit.dart';
import 'package:deadbolt/l10n/l10n.dart';
import 'package:deadbolt/src/rust/api/model.dart';
import 'package:deadbolt/theme/app_theme.dart';
import 'package:deadbolt/utils/toast_helper.dart';
import 'package:deadbolt/widgets/colored_address_text.dart';
import 'package:deadbolt/widgets/dialog_helpers.dart';
import 'package:deadbolt/widgets/hw_wallet_sheet.dart' show showHwVerifyAddressSheet;

class ReceiveDialog extends StatefulWidget {
  final APIAddress address;

  const ReceiveDialog({super.key, required this.address});

  @override
  State<ReceiveDialog> createState() => _ReceiveDialogState();
}

class _ReceiveDialogState extends State<ReceiveDialog> {
  late APIAddress _address;
  late TextEditingController _labelController;
  bool _navigating = false;

  @override
  void initState() {
    super.initState();
    _address = widget.address;
    final initialLabel = _address.label ?? '';
    _labelController = TextEditingController.fromValue(TextEditingValue(
      text: initialLabel,
      selection: TextSelection.collapsed(offset: initialLabel.length),
    ));
  }

  @override
  void dispose() {
    _labelController.dispose();
    super.dispose();
  }

  bool _isEffectivelyUsed(APIAddress addr) =>
      addr.isUsed || (addr.label?.isNotEmpty == true);

  Future<void> _goToNext() async {
    if (_navigating) return;
    setState(() => _navigating = true);
    final cubit = context.read<WalletDetailCubit>();
    await cubit.ensureReceiveAddressLoaded();
    if (!mounted) return;

    var s = cubit.state;
    if (s is! WalletDetailLoaded) {
      setState(() => _navigating = false);
      return;
    }

    APIAddress? findNext(List<APIAddress> addrs) => addrs
        .where((a) => !_isEffectivelyUsed(a) && a.index > _address.index)
        .cast<APIAddress?>()
        .firstOrNull;

    var next = findNext(s.receiveAddresses);
    if (next == null) {
      await cubit.revealMoreAddresses(APIKeychain.external_);
      if (!mounted) return;
      s = cubit.state;
      if (s is WalletDetailLoaded) next = findNext(s.receiveAddresses);
    }

    if (!mounted) return;
    if (next != null) {
      setState(() {
        _address = next!;
        _labelController.text = next.label ?? '';
        _navigating = false;
      });
    } else {
      setState(() => _navigating = false);
      showErrorToast(context, context.l10n.noUnusedReceiveAddress);
    }
  }

  void _saveLabel(String label) {
    if (label == (_address.label ?? '')) return;
    context.read<WalletDetailCubit>().setAddressLabel(
          _address.address,
          label,
          APIKeychain.external_,
        );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final scheme = Theme.of(context).colorScheme;

    return AlertDialog(
      titlePadding: kDialogTitlePadding,
      title: dialogCloseTitle(l10n.walletReceiveButton,
          onClose: () => Navigator.of(context).pop(),
          tooltip: l10n.cancel),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 220,
                height: 220,
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(8),
                ),
                padding: const EdgeInsets.all(8),
                child: QrImageView(
                  data: _address.address,
                  version: QrVersions.auto,
                  errorCorrectionLevel: QrErrorCorrectLevel.M,
                  backgroundColor: Colors.white,
                ),
              ),
            ),
            const SizedBox(height: 12),
            Text(
              l10n.addressIndex(_address.index),
              style: TextStyle(
                fontSize: 12,
                color: scheme.onSurface.withAlpha(AppAlpha.secondary),
              ),
            ),
            const SizedBox(height: 4),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: scheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Center(
                child: ColoredAddressText(
                  address: _address.address,
                  fontSize: 12,
                ),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _labelController,
              decoration: InputDecoration(
                labelText: l10n.addressLabelTitle,
                hintText: l10n.addressLabelHint,
                isDense: true,
                border: const OutlineInputBorder(),
              ),
              onSubmitted: _saveLabel,
              onTapOutside: (_) => _saveLabel(_labelController.text.trim()),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    icon: const Icon(Icons.copy, size: 16),
                    label: Text(l10n.copyToClipboard),
                    onPressed: () {
                      Clipboard.setData(
                          ClipboardData(text: _address.address));
                      showSuccessToast(context, l10n.copiedToClipboard);
                    },
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: OutlinedButton.icon(
                    icon: const Icon(Icons.memory, size: 16),
                    label: const Text('Verify'),
                    onPressed: () => _verifyOnDevice(context),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
      actions: [
        _navigating
            ? const SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : TextButton.icon(
                icon: const Icon(Icons.skip_next, size: 18),
                label: Text(l10n.receiveNextAddress),
                onPressed: _goToNext,
              ),
      ],
    );
  }

  Future<void> _verifyOnDevice(BuildContext context) async {
    final state =
        context.read<WalletDetailCubit>().state as WalletDetailLoaded?;
    if (state == null) return;
    await showHwVerifyAddressSheet(
      context,
      descriptor: state.walletInfo.descriptor,
      network: state.walletInfo.network,
      keychain: APIKeychain.external_,
      index: _address.index,
      address: _address.address,
    );
  }
}
