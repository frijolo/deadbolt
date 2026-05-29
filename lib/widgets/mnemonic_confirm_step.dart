import 'dart:async';

import 'package:flutter/material.dart';

import 'package:deadbolt/config/constants.dart' show kMonospaceFontFamily;
import 'package:deadbolt/errors.dart';
import 'package:deadbolt/l10n/l10n.dart';
import 'package:deadbolt/src/rust/api/model.dart';
import 'package:deadbolt/src/rust/api/wallet.dart' show deriveKeyspec;
import 'package:deadbolt/theme/app_theme.dart';
import 'package:deadbolt/utils/api_network_extensions.dart';
import 'package:deadbolt/widgets/derivation_path_helpers.dart';
import 'package:deadbolt/widgets/gap_stepper.dart';
import 'package:deadbolt/widgets/keyspec.dart' show KeyspecResult, kKeyspecPattern;

/// Configuration step for a known mnemonic: collects an optional BIP39
/// passphrase, an account index, and a derivation path. Lives-derives the
/// final keyspec (`[mfp/path]xpub`) every time any input changes (debounced).
///
/// Used by:
///   * the "Enter existing mnemonic" sub-flow,
///   * the wizard step 3 of `GenerateMnemonicSheet`.
///
/// The widget does **not** own the mnemonic input field — callers pass the
/// final mnemonic string in via [mnemonic]. The widget owns passphrase and
/// path UI internally.
///
/// [onResultChanged] fires every time the derivation succeeds or fails. When
/// it fires with a non-null [KeyspecResult] the caller can enable a "Done"
/// button; on null the result is unknown (deriving) or invalid.
class MnemonicConfirmStep extends StatefulWidget {
  /// Final mnemonic (12/15/18/21/24 words separated by spaces).
  final String mnemonic;

  /// Bitcoin network — affects coin type in default paths.
  final APINetwork network;

  /// Wallet script type that drives the default derivation path. When null,
  /// a generic m/86' path is used and the account stepper is hidden.
  final APIWalletType? walletType;

  /// Number of cosigners already present in the project (drives the BIP86
  /// vs BIP48 default for taproot).
  final int existingKeyCount;

  /// Forces the BIP48 multipath default (e.g. inheritance / miniscript).
  final bool isMultiPath;

  /// Path to suggest when [walletType] is null (e.g. wallet mode attaching a
  /// private key to an existing watch-only key). Avoids defaulting to BIP86
  /// on multisig wallets. Expected with or without the leading "m/".
  final String? fallbackPath;

  /// Show the account index stepper (only meaningful when [walletType] is set).
  final bool showAccountStepper;

  /// If non-null, the derived MFP must match this value (case-insensitive) for
  /// the result to be considered valid. Used for "edit key" / "make hot" flows.
  final String? requiredMfp;

  /// Initial value for the BIP39 passphrase field.
  final String initialPassphrase;

  /// Fired whenever the live-derive completes. Receives `null` while deriving
  /// or on error; a populated [KeyspecResult] when a valid keyspec is ready.
  final ValueChanged<KeyspecResult?>? onResultChanged;

  const MnemonicConfirmStep({
    super.key,
    required this.mnemonic,
    required this.network,
    this.walletType,
    this.existingKeyCount = 0,
    this.isMultiPath = false,
    this.fallbackPath,
    this.showAccountStepper = true,
    this.requiredMfp,
    this.initialPassphrase = '',
    this.onResultChanged,
  });

  @override
  State<MnemonicConfirmStep> createState() => _MnemonicConfirmStepState();
}

class _MnemonicConfirmStepState extends State<MnemonicConfirmStep> {
  late final TextEditingController _passphraseController;
  late final TextEditingController _pathController;
  bool _showPassphrase = false;

  int _accountIndex = 0;

  String? _derivedKeyspec;
  String? _deriveError;
  bool _deriving = false;
  Timer? _debounce;
  bool _lastReportedNull = true;

  void _reportResult(KeyspecResult? r) {
    if (r == null) {
      if (_lastReportedNull) return;
      _lastReportedNull = true;
    } else {
      _lastReportedNull = false;
    }
    widget.onResultChanged?.call(r);
  }

  @override
  void initState() {
    super.initState();
    _passphraseController =
        TextEditingController(text: widget.initialPassphrase);
    _pathController = TextEditingController(text: _initialPath());
    _passphraseController.addListener(_schedule);
    _pathController.addListener(_schedule);
    _schedule();
  }

  @override
  void didUpdateWidget(covariant MnemonicConfirmStep oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.mnemonic != widget.mnemonic) {
      _schedule();
    }
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _passphraseController.dispose();
    _pathController.dispose();
    super.dispose();
  }

  String _initialPath() {
    if (widget.walletType != null) {
      return defaultDerivationPath(
        widget.walletType!,
        widget.network,
        widget.existingKeyCount,
        isMultiPath: widget.isMultiPath,
      ).replaceFirst('m/', '');
    }
    final fallback = widget.fallbackPath;
    if (fallback != null && fallback.isNotEmpty) {
      return fallback.startsWith('m/') ? fallback.substring(2) : fallback;
    }
    return "86'/${widget.network.coinType}'/0'";
  }

  void _setAccountIndex(int i) {
    if (i < 0) return;
    if (widget.walletType == null) return;
    setState(() => _accountIndex = i);
    _pathController.text = defaultDerivationPath(
      widget.walletType!,
      widget.network,
      widget.existingKeyCount,
      isMultiPath: widget.isMultiPath,
      accountIndex: _accountIndex,
    ).replaceFirst('m/', '');
  }

  void _schedule() {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 500), _derive);
  }

  Future<void> _derive() async {
    if (!mounted) return;
    final mnemonic = widget.mnemonic.trim();
    final path = _pathController.text.trim();
    if (mnemonic.isEmpty || path.isEmpty) {
      setState(() {
        _derivedKeyspec = null;
        _deriveError = null;
        _deriving = false;
      });
      _reportResult(null);
      return;
    }

    setState(() {
      _deriving = true;
      _deriveError = null;
    });
    widget.onResultChanged?.call(null);

    try {
      final keyspec = await deriveKeyspec(
        mnemonic: mnemonic,
        passphrase: _passphraseController.text.isEmpty
            ? null
            : _passphraseController.text,
        derivationPath: path,
        network: widget.network,
      );
      if (!mounted) return;
      setState(() {
        _derivedKeyspec = keyspec;
        _deriving = false;
      });

      final match = kKeyspecPattern.firstMatch(keyspec);
      final derivedMfp = match?.group(1)?.toLowerCase();
      final required = widget.requiredMfp?.toLowerCase();
      final mfpOk = required == null || derivedMfp == required;
      if (mfpOk) {
        _reportResult((
          keyspec: keyspec,
          mnemonic: mnemonic,
          passphrase: _passphraseController.text.isEmpty
              ? null
              : _passphraseController.text,
          xprv: null,
        ));
      } else {
        _reportResult(null);
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _deriveError = formatRustError(e);
        _derivedKeyspec = null;
        _deriving = false;
      });
      _reportResult(null);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final paths = quickPaths(widget.walletType, widget.network,
        isMultiPath: widget.isMultiPath);

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
        const SizedBox(height: 12),
        if (widget.showAccountStepper && widget.walletType != null)
          GapStepper(
            label: l10n.accountIndexLabel,
            value: _accountIndex,
            onDecrement: _accountIndex > 0
                ? () => _setAccountIndex(_accountIndex - 1)
                : null,
            onIncrement: () => _setAccountIndex(_accountIndex + 1),
          ),
        TextField(
          controller: _pathController,
          decoration: InputDecoration(
            border: const OutlineInputBorder(),
            labelText: l10n.keyDerivPathLabel,
            hintText: "84'/0'/0'",
            helperText: l10n.derivPathWithoutLeading,
          ),
          style: const TextStyle(fontFamily: kMonospaceFontFamily),
        ),
        if (paths.isNotEmpty) ...[
          const SizedBox(height: 8),
          Wrap(
            spacing: 6,
            children: [
              for (final qp in paths)
                ActionChip(
                  label: Text(qp.label, style: const TextStyle(fontSize: 11)),
                  onPressed: () => _pathController.text = qp.path,
                  visualDensity: VisualDensity.compact,
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                ),
            ],
          ),
        ],
        const SizedBox(height: 12),
        ..._buildResult(l10n),
      ],
    );
  }

  List<Widget> _buildResult(AppLocalizations l10n) {
    if (_deriving) {
      return const [
        Center(child: CircularProgressIndicator()),
        SizedBox(height: 8),
      ];
    }
    if (_deriveError != null) {
      return [
        Text(_deriveError!,
            style: const TextStyle(color: Colors.red, fontSize: 13)),
        const SizedBox(height: 8),
      ];
    }
    if (_derivedKeyspec == null) return const [];

    final match = kKeyspecPattern.firstMatch(_derivedKeyspec!);
    final derivedMfp = match?.group(1)?.toLowerCase();
    final required = widget.requiredMfp?.toLowerCase();
    final mfpOk = required == null || derivedMfp == required;
    final color = mfpOk ? Colors.green : Colors.red;

    return [
      Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: color.withAlpha(AppAlpha.faint),
          border: Border.all(color: color.withAlpha(AppAlpha.pale)),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              Icon(mfpOk ? Icons.check_circle : Icons.cancel,
                  color: color, size: 16),
              const SizedBox(width: 6),
              Text(
                l10n.derivedKeyspecLabel,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                  color: color,
                ),
              ),
            ]),
            const SizedBox(height: 4),
            SelectableText(
              _derivedKeyspec!,
              style: const TextStyle(
                  fontFamily: kMonospaceFontFamily, fontSize: 12),
            ),
            if (!mfpOk) ...[
              const SizedBox(height: 6),
              Text(
                l10n.wrongKeyMfp(
                  (derivedMfp ?? '?').toUpperCase(),
                  required.toUpperCase(),
                ),
                style: const TextStyle(
                    fontSize: 11, fontFamily: kMonospaceFontFamily),
              ),
            ],
          ],
        ),
      ),
      const SizedBox(height: 8),
    ];
  }
}
