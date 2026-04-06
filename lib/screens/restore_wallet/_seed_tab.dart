import 'package:flutter/gestures.dart' show DragStartBehavior;
import 'package:flutter/material.dart';

import 'package:deadbolt/l10n/l10n.dart';
import 'package:deadbolt/src/rust/api/model.dart';
import 'package:deadbolt/utils/enum_formatters.dart';
import 'package:deadbolt/widgets/mnemonic_entry_field.dart';

import 'restore_wallet_screen.dart' show RestoreScriptType;

// ---------------------------------------------------------------------------
// Seed tab — mnemonic + passphrase input
// ---------------------------------------------------------------------------

typedef SeedScanCallback = void Function(
  String mnemonic,
  String? passphrase,
  RestoreScriptType? scriptFilter,
  bool nonStandardPaths,
  bool searchNostr,
);

class SeedTab extends StatefulWidget {
  final APINetwork network;
  final int accountGapLimit;
  final int addressGapLimit;
  final void Function(int) onAccountGapChanged;
  final void Function(int) onAddressGapChanged;
  final SeedScanCallback onScan;

  const SeedTab({
    super.key,
    required this.network,
    required this.accountGapLimit,
    required this.addressGapLimit,
    required this.onAccountGapChanged,
    required this.onAddressGapChanged,
    required this.onScan,
  });

  @override
  State<SeedTab> createState() => _SeedTabState();
}

class _SeedTabState extends State<SeedTab> {
  final _mnemonicController = TextEditingController();
  final _passphraseController = TextEditingController();
  bool _showPassphrase = false;
  RestoreScriptType? _scriptFilter;
  bool _nonStandardPaths = false;
  bool _searchNostr = true;

  @override
  void dispose() {
    _mnemonicController.dispose();
    _passphraseController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return ListView(
      dragStartBehavior: DragStartBehavior.down,
      padding: const EdgeInsets.all(16),
      children: [
        MnemonicEntryField(controller: _mnemonicController),
        const SizedBox(height: 12),
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
        const SizedBox(height: 16),
        Text(
          l10n.restoringToNetwork(localizedNetworkName(context, widget.network)),
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 16),
        Text(l10n.scriptTypeLabel,
            style: Theme.of(context).textTheme.labelMedium),
        const SizedBox(height: 8),
        SizedBox(
          width: double.infinity,
          child: SegmentedButton<RestoreScriptType?>(
            showSelectedIcon: false,
            segments: [
              ButtonSegment(value: null, label: Text(l10n.scanTypeAll)),
              ButtonSegment(
                  value: RestoreScriptType.legacy,
                  label: Text(l10n.scriptTypeLegacy)),
              ButtonSegment(
                  value: RestoreScriptType.nestedSegwit,
                  label: Text(l10n.scriptTypeNested)),
              ButtonSegment(
                  value: RestoreScriptType.nativeSegwit,
                  label: Text(l10n.scriptTypeSegwit)),
              ButtonSegment(
                  value: RestoreScriptType.taproot,
                  label: Text(l10n.scriptTypeTaproot)),
            ],
            selected: {_scriptFilter},
            onSelectionChanged: (v) =>
                setState(() => _scriptFilter = v.first),
          ),
        ),
        const SizedBox(height: 16),
        GapStepper(
          label: l10n.accountGapLimitLabel,
          value: widget.accountGapLimit,
          onDecrement: widget.accountGapLimit > 1
              ? () => widget.onAccountGapChanged(widget.accountGapLimit - 1)
              : null,
          onIncrement: widget.accountGapLimit < 100
              ? () => widget.onAccountGapChanged(widget.accountGapLimit + 1)
              : null,
        ),
        GapStepper(
          label: l10n.addressGapLimitLabel,
          value: widget.addressGapLimit,
          onDecrement: widget.addressGapLimit > 1
              ? () => widget.onAddressGapChanged(widget.addressGapLimit - 1)
              : null,
          onIncrement: widget.addressGapLimit < 100
              ? () => widget.onAddressGapChanged(widget.addressGapLimit + 1)
              : null,
        ),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: Text(l10n.scanNonStandardPathsLabel,
              style: Theme.of(context).textTheme.bodyMedium),
          subtitle: Text(l10n.scanNonStandardPathsHint,
              style: Theme.of(context).textTheme.bodySmall),
          value: _nonStandardPaths,
          onChanged: (v) => setState(() => _nonStandardPaths = v),
        ),
        const SizedBox(height: 16),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: Text(l10n.searchNostrLabel,
              style: Theme.of(context).textTheme.bodyMedium),
          subtitle: Text(l10n.searchNostrHint,
              style: Theme.of(context).textTheme.bodySmall),
          value: _searchNostr,
          onChanged: (v) => setState(() => _searchNostr = v),
        ),
        const SizedBox(height: 8),
        FilledButton(
          onPressed: () {
            final mnemonic = _mnemonicController.text.trim();
            if (mnemonic.isEmpty) return;
            final passphrase = _passphraseController.text.isEmpty
                ? null
                : _passphraseController.text;
            widget.onScan(
                mnemonic, passphrase, _scriptFilter, _nonStandardPaths, _searchNostr);
          },
          child: Text(l10n.scanAccountsAction),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Gap limit stepper (reusable across tabs)
// ---------------------------------------------------------------------------

class GapStepper extends StatelessWidget {
  final String label;
  final int value;
  final VoidCallback? onDecrement;
  final VoidCallback? onIncrement;

  const GapStepper({
    super.key,
    required this.label,
    required this.value,
    required this.onDecrement,
    required this.onIncrement,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Text(label, style: theme.textTheme.bodyMedium),
          const Spacer(),
          IconButton(
            icon: const Icon(Icons.remove_circle_outline, size: 20),
            onPressed: onDecrement,
            visualDensity: VisualDensity.compact,
          ),
          SizedBox(
            width: 36,
            child: Center(
              child: Text('$value', style: theme.textTheme.titleSmall),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.add_circle_outline, size: 20),
            onPressed: onIncrement,
            visualDensity: VisualDensity.compact,
          ),
        ],
      ),
    );
  }
}
