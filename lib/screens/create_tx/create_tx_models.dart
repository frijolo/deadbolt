import 'dart:async';

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

  const TxSummary({
    required this.feeSats,
    required this.changeSats,
    required this.sendSats,
    required this.feeRate,
    required this.totalWu,
    required this.hasChange,
    this.insufficientFunds = false,
  });
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
  RecipientEntry();

  final addressCtrl = TextEditingController();
  final amountCtrl = TextEditingController();
  int? wu; // output weight units from addressOutputWu()

  /// Parses the amount field stripping thousands separators.
  int get rawAmount => int.tryParse(amountCtrl.text.replaceAll(',', '').trim()) ?? 0;
  bool editMode = true;
  bool resolvingWu = false;
  Timer? debounce;

  void dispose() {
    debounce?.cancel();
    addressCtrl.dispose();
    amountCtrl.dispose();
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
