import 'package:flutter/gestures.dart' show DragStartBehavior;
import 'package:flutter/material.dart';

import 'package:deadbolt/l10n/l10n.dart';
import 'package:deadbolt/src/rust/api/model.dart';
import 'package:deadbolt/utils/enum_formatters.dart';
import 'package:deadbolt/widgets/gap_stepper.dart';
import 'package:deadbolt/widgets/text_import_sheet.dart';

import 'restore_wallet_screen.dart' show RestoreScriptType;

// ---------------------------------------------------------------------------
// xpub tab — bare xpub or keyspec input
// ---------------------------------------------------------------------------

typedef XpubScanCallback = void Function(
  String xpub,
  RestoreScriptType? scriptFilter,
  bool searchNostr,
  bool searchOnChain,
);

class XpubTab extends StatefulWidget {
  final APINetwork network;
  final int accountGapLimit;
  final int addressGapLimit;
  final void Function(int) onAccountGapChanged;
  final void Function(int) onAddressGapChanged;
  final XpubScanCallback onScan;

  const XpubTab({
    super.key,
    required this.network,
    required this.accountGapLimit,
    required this.addressGapLimit,
    required this.onAccountGapChanged,
    required this.onAddressGapChanged,
    required this.onScan,
  });

  @override
  State<XpubTab> createState() => _XpubTabState();
}

class _XpubTabState extends State<XpubTab> {
  final _xpubController = TextEditingController();
  final _formKey = GlobalKey<FormState>();
  RestoreScriptType? _scriptFilter;
  bool _searchNostr = true;
  bool _searchOnChain = true;

  @override
  void dispose() {
    _xpubController.dispose();
    super.dispose();
  }

  Future<void> _importXpub() async {
    final result = await showTextImportSheet(context);
    if (result == null || !mounted) return;
    _xpubController.text = result.trim();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return Form(
      key: _formKey,
      child: ListView(
        dragStartBehavior: DragStartBehavior.down,
        padding: const EdgeInsets.all(16),
        children: [
          Text(l10n.restoreXpubEnterXpub,
              style: Theme.of(context).textTheme.bodyMedium),
          const SizedBox(height: 12),
          TextFormField(
            controller: _xpubController,
            decoration: InputDecoration(
              hintText: l10n.nostrRestoreXpubHint,
              border: const OutlineInputBorder(),
            ),
            minLines: 2,
            maxLines: 4,
            validator: (v) {
              if ((v ?? '').trim().isEmpty) return l10n.required;
              return null;
            },
          ),
          const SizedBox(height: 8),
          OutlinedButton.icon(
            icon: const Icon(Icons.download_outlined, size: 18),
            label: Text(l10n.importAction),
            onPressed: _importXpub,
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
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: Text(l10n.onChainSearchLabel,
                style: Theme.of(context).textTheme.bodyMedium),
            subtitle: Text(l10n.onChainSearchHint,
                style: Theme.of(context).textTheme.bodySmall),
            value: _searchOnChain,
            onChanged: (v) => setState(() => _searchOnChain = v),
          ),
          const SizedBox(height: 8),
          FilledButton(
            onPressed: () {
              if (!_formKey.currentState!.validate()) return;
              widget.onScan(_xpubController.text.trim(), _scriptFilter,
                  _searchNostr, _searchOnChain);
            },
            child: Text(l10n.restoreXpubScanButton),
          ),
        ],
      ),
    );
  }
}
