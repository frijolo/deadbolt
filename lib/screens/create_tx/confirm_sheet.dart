import 'dart:typed_data';

import 'package:flutter/material.dart';

import 'package:deadbolt/config/constants.dart' show kMonospaceFontFamily;
import 'package:deadbolt/l10n/l10n.dart';
import 'package:deadbolt/utils/bitcoin_formatter.dart' show BitcoinFormatter;
import 'package:deadbolt/utils/op_return_encoding.dart';
import 'package:deadbolt/widgets/colored_group_text.dart';

// ─────────────────────────────────────────────────────────────
// Direct send confirmation sheet
// ─────────────────────────────────────────────────────────────

class DirectSendConfirmSheet extends StatelessWidget {
  const DirectSendConfirmSheet({
    super.key,
    required this.recipients,
    this.feeSat,
    this.changeSat,
    required this.feeRateSatPerVb,
    required this.onConfirm,
  });

  final List<({String address, int amountSat, Uint8List? opReturnData})> recipients;
  final int? feeSat;
  final int? changeSat;
  final double feeRateSatPerVb;
  final VoidCallback onConfirm;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    final feeText = feeSat != null
        ? '${BitcoinFormatter.formatNum(feeSat!)} sats'
            ' (${BitcoinFormatter.formatDouble(feeRateSatPerVb, 1)} sat/vB)'
        : '${BitcoinFormatter.formatDouble(feeRateSatPerVb, 1)} sat/vB';
    final totalAmount = recipients.fold(0, (s, r) => s + r.amountSat);
    final paymentRecipientCount =
        recipients.where((r) => r.opReturnData == null).length;

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Center(
            child: Container(
              width: 32,
              height: 4,
              margin: const EdgeInsets.only(bottom: 16),
              decoration: BoxDecoration(
                color: colorScheme.onSurface.withAlpha(60),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          Text(l10n.directSendConfirmTitle,
              style: theme.textTheme.titleMedium
                  ?.copyWith(fontWeight: FontWeight.bold)),
          const SizedBox(height: 16),
          // One row per recipient (always, for visual consistency).
          for (int i = 0; i < recipients.length; i++) ...[
            if (recipients[i].opReturnData != null)
              ConfirmRow(
                label: l10n.opReturnRecipientLabel,
                child: Text(
                  decodeOpReturnForDisplay(recipients[i].opReturnData!),
                  style: theme.textTheme.bodySmall
                      ?.copyWith(fontFamily: kMonospaceFontFamily),
                ),
              )
            else
              ConfirmRow(
                label: '${l10n.psbtRecipient} ${i + 1}',
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    ColoredGroupText(text: recipients[i].address),
                    const SizedBox(height: 2),
                    Text(
                      BitcoinFormatter.satsLabel(recipients[i].amountSat),
                      style: theme.textTheme.bodySmall,
                    ),
                  ],
                ),
              ),
            const SizedBox(height: 8),
          ],
          // Total amount row when >1 payment recipient.
          if (paymentRecipientCount > 1) ...[
            ConfirmRow(
              label: l10n.createTxTotalOut,
              child: Text(
                BitcoinFormatter.satsLabel(totalAmount),
                style: theme.textTheme.bodySmall,
              ),
            ),
            const SizedBox(height: 8),
          ],
          ConfirmRow(
            label: l10n.psbtFee,
            child: Text(feeText, style: theme.textTheme.bodySmall),
          ),
          if (changeSat != null) ...[
            const SizedBox(height: 8),
            ConfirmRow(
              label: l10n.createTxEstChange,
              child: Text(
                BitcoinFormatter.satsLabel(changeSat!),
                style: theme.textTheme.bodySmall,
              ),
            ),
          ],
          const SizedBox(height: 20),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: Text(l10n.cancel),
              ),
              const SizedBox(width: 8),
              FilledButton.icon(
                onPressed: onConfirm,
                icon: const Icon(Icons.send_outlined),
                label: Text(l10n.directSendConfirmAction),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────
// Confirm row helper widget
// ─────────────────────────────────────────────────────────────

class ConfirmRow extends StatelessWidget {
  const ConfirmRow({super.key, required this.label, required this.child});
  final String label;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 64,
          child: Text(label,
              style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurface.withAlpha(150))),
        ),
        Expanded(child: child),
      ],
    );
  }
}
