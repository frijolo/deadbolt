import 'dart:async';

import 'package:flutter/material.dart';

import 'package:deadbolt/config/constants.dart' show kMonospaceFontFamily;
import 'package:deadbolt/errors.dart';
import 'package:deadbolt/l10n/l10n.dart';
import 'package:deadbolt/src/rust/api/model.dart' show APINetwork;
import 'package:deadbolt/src/rust/api/wallet.dart' show validateMnemonic;

/// MFP preview for a known mnemonic in wallet mode.
///
/// Collects an optional BIP39 passphrase and live-validates the mnemonic
/// against [network] to derive the master fingerprint (MFP).
///
/// Used by:
///   * wallet mode "make hot" seed form,
///   * any context where only MFP validation is needed (no derivation path).
///
/// The widget does **not** own the mnemonic input field — callers pass the
/// mnemonic string in via [mnemonic]. The widget owns the passphrase UI.
///
/// [onMfpChanged] fires every time validation completes. Receives `null` while
/// validating or on error; a non-null [MfpPreview] when validation succeeds.
class MnemonicMfpPreview extends StatefulWidget {
  /// Mnemonic to validate (12/15/18/21/24 words separated by spaces).
  final String mnemonic;

  /// Bitcoin network — affects coin type in default paths.
  final APINetwork network;

  /// If non-null, the derived MFP must match this value (case-insensitive)
  /// for the preview to show a green check. Used for "make hot" flows.
  final String? expectedMfp;

  /// Initial value for the BIP39 passphrase field.
  final String initialPassphrase;

  /// Fired whenever the MFP preview changes.
  final ValueChanged<MfpPreview?>? onMfpChanged;

  const MnemonicMfpPreview({
    super.key,
    required this.mnemonic,
    required this.network,
    this.expectedMfp,
    this.initialPassphrase = '',
    this.onMfpChanged,
  });

  @override
  State<MnemonicMfpPreview> createState() => _MnemonicMfpPreviewState();
}

/// Result of MFP validation.
class MfpPreview {
  final String mfp;
  final bool matchesExpected;
  final String passphrase;

  const MfpPreview({required this.mfp, required this.matchesExpected, this.passphrase = ''});
}

class _MnemonicMfpPreviewState extends State<MnemonicMfpPreview> {
  late final TextEditingController _passphraseController;
  bool _showPassphrase = false;
  Timer? _debounce;
  String? _mfp;
  String? _error;
  bool _validating = false;
  bool _lastReportedNull = true;

  void _reportMfp(MfpPreview? p) {
    if (p == null) {
      if (_lastReportedNull) return;
      _lastReportedNull = true;
    } else {
      _lastReportedNull = false;
    }
    widget.onMfpChanged?.call(p);
  }

  @override
  void initState() {
    super.initState();
    _passphraseController =
        TextEditingController(text: widget.initialPassphrase);
    _passphraseController.addListener(_schedule);
    _schedule();
  }

  @override
  void didUpdateWidget(covariant MnemonicMfpPreview oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.mnemonic != widget.mnemonic) {
      _schedule();
    }
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _passphraseController.dispose();
    super.dispose();
  }

  void _schedule() {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 500), _validate);
  }

  Future<void> _validate() async {
    if (!mounted) return;
    final mnemonic = widget.mnemonic.trim();
    if (mnemonic.isEmpty) {
      setState(() {
        _mfp = null;
        _error = null;
        _validating = false;
      });
      _reportMfp(null);
      return;
    }

    setState(() {
      _validating = true;
      _error = null;
    });
    widget.onMfpChanged?.call(null);

    try {
      final info = await validateMnemonic(
        mnemonic: mnemonic,
        passphrase: _passphraseController.text.isEmpty
            ? null
            : _passphraseController.text,
        network: widget.network,
      );
      if (!mounted) return;
      final matches = widget.expectedMfp == null ||
          info.mfp.toLowerCase() == widget.expectedMfp!.toLowerCase();
      setState(() {
        _mfp = info.mfp;
        _error = null;
        _validating = false;
      });
      _reportMfp(
        MfpPreview(mfp: info.mfp, matchesExpected: matches, passphrase: _passphraseController.text),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _mfp = null;
        _error = formatRustError(e);
        _validating = false;
      });
      _reportMfp(null);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        TextField(
          controller: _passphraseController,
          obscureText: !_showPassphrase,
          decoration: InputDecoration(
            border: const OutlineInputBorder(),
            labelText: l10n.bip39PassphraseLabel,
            suffixIcon: IconButton(
              icon: Icon(
                  _showPassphrase ? Icons.visibility_off : Icons.visibility),
              onPressed: () =>
                  setState(() => _showPassphrase = !_showPassphrase),
            ),
          ),
        ),
        if (_validating) ...[
          const SizedBox(height: 8),
          Row(children: [
            const SizedBox(
                width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2)),
            const SizedBox(width: 8),
            Text(l10n.validating, style: const TextStyle(fontSize: 12)),
          ]),
        ] else if (_mfp != null && _error == null) ...[
          const SizedBox(height: 8),
          _buildMfpPreview(),
        ] else if (_error != null) ...[
          const SizedBox(height: 8),
          Text(_error!,
              style: const TextStyle(color: Colors.red, fontSize: 12)),
        ],
      ],
    );
  }

  Widget _buildMfpPreview() {
    final l10n = context.l10n;
    final expected = widget.expectedMfp;
    final matches = expected == null ||
        _mfp!.toLowerCase() == expected.toLowerCase();
    return Row(children: [
      Icon(
        matches ? Icons.check_circle : Icons.cancel,
        color: matches ? Colors.green : Colors.red,
        size: 16,
      ),
      const SizedBox(width: 4),
      if (matches)
        Text('MFP: $_mfp',
            style: const TextStyle(fontFamily: kMonospaceFontFamily))
      else
        Expanded(
          child: Text(
            l10n.wrongKeyMfp(_mfp!, expected),
            style: const TextStyle(
                color: Colors.red, fontSize: 12, fontFamily: kMonospaceFontFamily),
          ),
        ),
    ]);
  }
}
