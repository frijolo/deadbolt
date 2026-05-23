import 'package:deadbolt/src/rust/api/model.dart';
import 'package:deadbolt/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

// ─────────────────────────────────────────────────────────────
// Fee edit mode
// ─────────────────────────────────────────────────────────────

enum FeeEditMode { none, rate, total }

// ─────────────────────────────────────────────────────────────
// Transaction summary (live fee/change display)
// ─────────────────────────────────────────────────────────────

/// Internal transaction estimate used to drive live fee/change display.
class TxSummary {
  final int feeSats;
  final int changeSats;
  final int sendSats;
  final double feeRate;
  final int totalWu;
  final bool hasChange;
  final bool insufficientFunds;
  final List<int> recipientAmountsSat;

  const TxSummary({
    required this.feeSats,
    required this.changeSats,
    required this.sendSats,
    required this.feeRate,
    required this.totalWu,
    required this.hasChange,
    this.insufficientFunds = false,
    this.recipientAmountsSat = const [],
  });

  /// Adapt a Rust-side preview into the TxSummary shape consumed by the fee widgets.
  factory TxSummary.fromPreview(APITxPreview p) => TxSummary(
        feeSats: p.feeSats.toInt(),
        changeSats: p.changeSats.toInt(),
        sendSats: p.sendSats.toInt(),
        feeRate: p.feeRateSatPerVb,
        totalWu: p.totalWu.toInt(),
        hasChange: p.hasChange,
        insufficientFunds: p.insufficientFunds,
        recipientAmountsSat:
            p.recipients.map((r) => r.amountSat.toInt()).toList(growable: false),
      );
}

// ─────────────────────────────────────────────────────────────
// Input formatters
// ─────────────────────────────────────────────────────────────

/// Formats a sats integer input with thousands separators (e.g. 1,234,567).
class ThousandsSeparatorFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(
      TextEditingValue oldValue, TextEditingValue newValue) {
    final digits = newValue.text.replaceAll(',', '');
    if (digits.isEmpty) return newValue.copyWith(text: '');
    final n = int.tryParse(digits);
    if (n == null) return oldValue;
    final formatted = _fmt(n);
    return newValue.copyWith(
      text: formatted,
      selection: TextSelection.collapsed(offset: formatted.length),
    );
  }

  static String _fmt(int n) {
    final s = n.toString();
    final buf = StringBuffer();
    for (int i = 0; i < s.length; i++) {
      if (i > 0 && (s.length - i) % 3 == 0) buf.write(',');
      buf.write(s[i]);
    }
    return buf.toString();
  }
}

// ─────────────────────────────────────────────────────────────
// Recipient entry
// ─────────────────────────────────────────────────────────────

/// Holds the per-recipient state for the multi-output send form.
class RecipientEntry {
  RecipientEntry({this.isOpReturn = false});

  final addressCtrl = TextEditingController();
  final amountCtrl = TextEditingController();

  /// True when this entry is an OP_RETURN data carrier (no address, no amount).
  final bool isOpReturn;

  /// OP_RETURN payload as typed by the user. Only used when [isOpReturn] is true.
  final opReturnCtrl = TextEditingController();

  /// When true, [opReturnCtrl] is interpreted as hex; otherwise as UTF-8 text.
  bool opReturnHexMode = false;

  /// Parses the amount field stripping thousands separators.
  int get rawAmount => int.tryParse(amountCtrl.text.replaceAll(',', '').trim()) ?? 0;
  bool editMode = true;

  void dispose() {
    addressCtrl.dispose();
    amountCtrl.dispose();
    opReturnCtrl.dispose();
  }
}

// ─────────────────────────────────────────────────────────────
// Shared layout helper (used by RbfCard and CpfpBanner)
// ─────────────────────────────────────────────────────────────

/// A two-column label/value row used inside fee-related cards.
Widget rbfRow(String label, String value, Color valueColor, ThemeData theme) {
  return Row(
    children: [
      SizedBox(
        width: 110,
        child: Text(
          label,
          style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurface.withAlpha(AppAlpha.secondary)),
        ),
      ),
      Expanded(
        child: Text(
          value,
          style: theme.textTheme.bodySmall?.copyWith(color: valueColor),
        ),
      ),
    ],
  );
}
