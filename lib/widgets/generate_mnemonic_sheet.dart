import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:deadbolt/config/constants.dart' show kMonospaceFontFamily;
import 'package:deadbolt/errors.dart';
import 'package:deadbolt/l10n/l10n.dart';
import 'package:deadbolt/src/rust/api/model.dart';
import 'package:deadbolt/src/rust/api/wallet.dart' show generateMnemonic;
import 'package:deadbolt/widgets/keyspec.dart' show KeyspecResult;
import 'package:deadbolt/widgets/dialog_helpers.dart'
    show sheetCloseTitle, showSheet;
import 'package:deadbolt/widgets/mnemonic_confirm_step.dart';

/// Opens the three-step wizard that:
///   1. generates a fresh BIP39 mnemonic (12 or 24 words) using Rust's
///      [generateMnemonic],
///   2. forces the user to verify every word in a randomized prompt order
///      before continuing,
///   3. configures BIP39 passphrase + derivation path via [MnemonicConfirmStep]
///      and pops a [KeyspecResult].
///
/// Returns null if the user cancels at any point.
Future<KeyspecResult?> showGenerateMnemonicSheet(
  BuildContext context, {
  required APINetwork network,
  required APIWalletType walletType,
  int existingKeyCount = 0,
  bool isMultiPath = false,
}) {
  return showSheet<KeyspecResult>(
    context,
    (ctx) => _GenerateMnemonicSheet(
      network: network,
      walletType: walletType,
      existingKeyCount: existingKeyCount,
      isMultiPath: isMultiPath,
    ),
    isDismissible: false,
  );
}

enum _Step { generate, verify, confirm }

class _GenerateMnemonicSheet extends StatefulWidget {
  final APINetwork network;
  final APIWalletType walletType;
  final int existingKeyCount;
  final bool isMultiPath;

  const _GenerateMnemonicSheet({
    required this.network,
    required this.walletType,
    required this.existingKeyCount,
    required this.isMultiPath,
  });

  @override
  State<_GenerateMnemonicSheet> createState() => _GenerateMnemonicSheetState();
}

class _GenerateMnemonicSheetState extends State<_GenerateMnemonicSheet> {
  _Step _step = _Step.generate;
  int _wordCount = 12;

  /// Generated mnemonic (space-separated). Empty until step 1 is completed.
  String _mnemonic = '';
  List<String> _words = const [];
  String? _generateError;
  bool _generating = false;

  /// Shuffled list of zero-based word indexes (used in step 2).
  List<int> _shuffledIndexes = const [];

  KeyspecResult? _confirmResult;

  void _generate() {
    setState(() {
      _generateError = null;
      _generating = true;
    });
    try {
      final phrase = generateMnemonic(wordCount: _wordCount);
      setState(() {
        _mnemonic = phrase;
        _words = phrase.split(RegExp(r'\s+'));
        _generating = false;
      });
    } catch (e) {
      setState(() {
        _generateError = formatRustError(e);
        _generating = false;
      });
    }
  }

  void _onBackupConfirmed() {
    _reshuffle();
    setState(() => _step = _Step.verify);
  }

  void _reshuffle() {
    final indexes = List<int>.generate(_words.length, (i) => i);
    indexes.shuffle(Random.secure());
    _shuffledIndexes = indexes;
  }

  void _onVerified() {
    setState(() => _step = _Step.confirm);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final media = MediaQuery.of(context);

    return Padding(
      padding: EdgeInsets.only(bottom: media.viewInsets.bottom),
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: media.size.height * 0.92),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            sheetCloseTitle(
              context,
              _titleForStep(l10n),
              onClose: () => Navigator.pop(context),
              onBack: switch (_step) {
                _Step.generate => null,
                _Step.verify => () => setState(() => _step = _Step.generate),
                _Step.confirm => () => setState(() => _step = _Step.verify),
              },
            ),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                child: switch (_step) {
                  _Step.generate => _GenerateStep(
                      wordCount: _wordCount,
                      onWordCountChanged: (n) => setState(() {
                        _wordCount = n;
                        _mnemonic = '';
                        _words = const [];
                      }),
                      mnemonic: _mnemonic,
                      words: _words,
                      generating: _generating,
                      error: _generateError,
                      onGenerate: _generate,
                      onBackupConfirmed: _onBackupConfirmed,
                    ),
                  _Step.verify => _VerifyStep(
                      words: _words,
                      shuffledIndexes: _shuffledIndexes,
                      onReshuffle: () => setState(() => _reshuffle()),
                      onVerified: _onVerified,
                    ),
                  _Step.confirm => _ConfirmStep(
                      mnemonic: _mnemonic,
                      network: widget.network,
                      walletType: widget.walletType,
                      existingKeyCount: widget.existingKeyCount,
                      isMultiPath: widget.isMultiPath,
                      onResultChanged: (r) =>
                          setState(() => _confirmResult = r),
                      result: _confirmResult,
                      onDone: () => Navigator.pop(context, _confirmResult),
                    ),
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _titleForStep(AppLocalizations l10n) {
    return switch (_step) {
      _Step.generate => l10n.generateMnemonicStep1Title,
      _Step.verify => l10n.generateMnemonicStep2Title,
      _Step.confirm => l10n.generateMnemonicStep3Title,
    };
  }
}

// ----------------------------------------------------------------------------
// Step 1: Generate
// ----------------------------------------------------------------------------

class _GenerateStep extends StatelessWidget {
  final int wordCount;
  final ValueChanged<int> onWordCountChanged;
  final String mnemonic;
  final List<String> words;
  final bool generating;
  final String? error;
  final VoidCallback onGenerate;
  final VoidCallback onBackupConfirmed;

  const _GenerateStep({
    required this.wordCount,
    required this.onWordCountChanged,
    required this.mnemonic,
    required this.words,
    required this.generating,
    required this.error,
    required this.onGenerate,
    required this.onBackupConfirmed,
  });

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final theme = Theme.of(context);

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(l10n.generateMnemonicLengthLabel,
                style: theme.textTheme.labelMedium),
            const SizedBox(width: 12),
            Expanded(
              child: SegmentedButton<int>(
                showSelectedIcon: false,
                segments: [
                  ButtonSegment(
                      value: 12,
                      label: Text(l10n.generateMnemonicLength12)),
                  ButtonSegment(
                      value: 24,
                      label: Text(l10n.generateMnemonicLength24)),
                ],
                selected: {wordCount},
                onSelectionChanged: (s) => onWordCountChanged(s.first),
                style:
                    const ButtonStyle(visualDensity: VisualDensity.compact),
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        if (words.isEmpty) ...[
          if (error != null) ...[
            Text(error!,
                style: const TextStyle(color: Colors.red, fontSize: 13)),
            const SizedBox(height: 8),
          ],
          Center(
            child: FilledButton.icon(
              icon: generating
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.casino_outlined),
              label: Text(l10n.generateMnemonicGenerateButton),
              onPressed: generating ? null : onGenerate,
            ),
          ),
        ] else ...[
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: theme.colorScheme.errorContainer.withAlpha(120),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: theme.colorScheme.error),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.warning_amber_rounded,
                    color: theme.colorScheme.error),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    l10n.generateMnemonicWarning,
                    style: TextStyle(color: theme.colorScheme.onErrorContainer),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          _WordGrid(words: words),
          const SizedBox(height: 16),
          Row(
            children: [
              TextButton.icon(
                icon: const Icon(Icons.refresh),
                label: Text(l10n.generateMnemonicRegenerate),
                onPressed: generating ? null : onGenerate,
              ),
              const Spacer(),
              FilledButton(
                onPressed: onBackupConfirmed,
                child: Text(l10n.generateMnemonicBackupDone),
              ),
            ],
          ),
        ],
      ],
    );
  }
}

class _WordGrid extends StatelessWidget {
  final List<String> words;
  const _WordGrid({required this.words});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 3,
        mainAxisExtent: 36,
        crossAxisSpacing: 8,
        mainAxisSpacing: 4,
      ),
      itemCount: words.length,
      itemBuilder: (ctx, i) {
        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
          decoration: BoxDecoration(
            color: theme.colorScheme.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(6),
          ),
          child: Row(
            children: [
              SizedBox(
                width: 22,
                child: Text(
                  '${i + 1}.',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
              Expanded(
                child: SelectableText(
                  words[i],
                  style: const TextStyle(
                    fontFamily: kMonospaceFontFamily,
                    fontSize: 13,
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

// ----------------------------------------------------------------------------
// Step 2: Verify (all positions, randomized prompt order)
// ----------------------------------------------------------------------------

class _VerifyStep extends StatefulWidget {
  final List<String> words;
  final List<int> shuffledIndexes;
  final VoidCallback onReshuffle;
  final VoidCallback onVerified;

  const _VerifyStep({
    required this.words,
    required this.shuffledIndexes,
    required this.onReshuffle,
    required this.onVerified,
  });

  @override
  State<_VerifyStep> createState() => _VerifyStepState();
}

class _VerifyStepState extends State<_VerifyStep> {
  late List<TextEditingController> _controllers;
  bool _checked = false;

  @override
  void initState() {
    super.initState();
    _controllers = List.generate(
      widget.words.length,
      (_) => TextEditingController(),
    );
  }

  @override
  void didUpdateWidget(covariant _VerifyStep oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.shuffledIndexes != widget.shuffledIndexes) {
      for (final c in _controllers) {
        c.clear();
      }
      _checked = false;
    }
  }

  @override
  void dispose() {
    for (final c in _controllers) {
      c.dispose();
    }
    super.dispose();
  }

  bool _matches(int wordIndex) {
    final typed = _controllers[wordIndex].text.trim().toLowerCase();
    return typed == widget.words[wordIndex];
  }

  bool get _allMatch =>
      _controllers.asMap().entries.every((e) => _matches(e.key));

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final theme = Theme.of(context);

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(l10n.generateMnemonicVerifyIntro,
            style: theme.textTheme.bodyMedium),
        const SizedBox(height: 16),
        for (final wordIndex in widget.shuffledIndexes) ...[
          _VerifyField(
            position: wordIndex + 1,
            controller: _controllers[wordIndex],
            expected: widget.words[wordIndex],
            showErrorWhenInvalid: _checked,
          ),
          const SizedBox(height: 10),
        ],
        ListenableBuilder(
          listenable: Listenable.merge(_controllers),
          builder: (context, _) {
            final allMatch = _allMatch;
            return Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (_checked && !allMatch) ...[
                  Text(l10n.generateMnemonicVerifyError,
                      style: TextStyle(
                          color: theme.colorScheme.error, fontSize: 13)),
                  const SizedBox(height: 8),
                ],
                Row(
                  children: [
                    TextButton.icon(
                      icon: const Icon(Icons.shuffle),
                      label: Text(l10n.generateMnemonicShuffleAgain),
                      onPressed: widget.onReshuffle,
                    ),
                    const Spacer(),
                    FilledButton(
                      onPressed: () {
                        setState(() => _checked = true);
                        if (allMatch) widget.onVerified();
                      },
                      child: Text(l10n.generateMnemonicContinue),
                    ),
                  ],
                ),
              ],
            );
          },
        ),
      ],
    );
  }
}

class _VerifyField extends StatelessWidget {
  final int position;
  final TextEditingController controller;
  final String expected;
  final bool showErrorWhenInvalid;

  const _VerifyField({
    required this.position,
    required this.controller,
    required this.expected,
    required this.showErrorWhenInvalid,
  });

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final theme = Theme.of(context);

    return ValueListenableBuilder<TextEditingValue>(
      valueListenable: controller,
      builder: (context, value, _) {
        final typed = value.text.trim().toLowerCase();
        final hasInput = typed.isNotEmpty;
        final valid = typed == expected;

        Color? borderColor;
        if (hasInput) borderColor = valid ? Colors.green : null;
        if (showErrorWhenInvalid && !valid) {
          borderColor = theme.colorScheme.error;
        }

        return TextField(
          controller: controller,
          autocorrect: false,
          enableSuggestions: false,
          textCapitalization: TextCapitalization.none,
          inputFormatters: [
            FilteringTextInputFormatter.allow(RegExp(r'[a-z]')),
          ],
          style: const TextStyle(fontFamily: kMonospaceFontFamily),
          decoration: InputDecoration(
            isDense: true,
            labelText: l10n.generateMnemonicVerifyWordLabel(position),
            border: const OutlineInputBorder(),
            enabledBorder: borderColor != null
                ? OutlineInputBorder(
                    borderSide: BorderSide(color: borderColor, width: 2),
                  )
                : null,
            focusedBorder: borderColor != null
                ? OutlineInputBorder(
                    borderSide: BorderSide(color: borderColor, width: 2),
                  )
                : null,
            suffixIcon: hasInput && valid
                ? const Icon(Icons.check_circle, color: Colors.green, size: 20)
                : null,
          ),
        );
      },
    );
  }
}

// ----------------------------------------------------------------------------
// Step 3: Confirm — passphrase + derivation path + live derive
// ----------------------------------------------------------------------------

class _ConfirmStep extends StatelessWidget {
  final String mnemonic;
  final APINetwork network;
  final APIWalletType walletType;
  final int existingKeyCount;
  final bool isMultiPath;
  final ValueChanged<KeyspecResult?> onResultChanged;
  final KeyspecResult? result;
  final VoidCallback onDone;

  const _ConfirmStep({
    required this.mnemonic,
    required this.network,
    required this.walletType,
    required this.existingKeyCount,
    required this.isMultiPath,
    required this.onResultChanged,
    required this.result,
    required this.onDone,
  });

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        MnemonicConfirmStep(
          mnemonic: mnemonic,
          network: network,
          walletType: walletType,
          existingKeyCount: existingKeyCount,
          isMultiPath: isMultiPath,
          onResultChanged: onResultChanged,
        ),
        Row(
          children: [
            const Spacer(),
            FilledButton(
              onPressed: result == null ? null : onDone,
              child: Text(l10n.generateMnemonicDone),
            ),
          ],
        ),
      ],
    );
  }
}
