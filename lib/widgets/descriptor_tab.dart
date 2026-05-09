import 'package:flutter/foundation.dart' show mapEquals;
import 'package:deadbolt/config/constants.dart' show kMonospaceFontFamily;
import 'package:flutter/material.dart';

import 'package:deadbolt/l10n/l10n.dart';
import 'package:deadbolt/theme/app_theme.dart';
import 'package:deadbolt/utils/export_sheet.dart';
import 'package:deadbolt/widgets/descriptor_span_builder.dart';

/// Descriptor tab used in both the project designer and the wallet detail view.
/// When [isDirty] is true, shows a banner indicating the descriptor is outdated.
class DescriptorTab extends StatefulWidget {
  final String descriptor;
  final bool isDirty;
  final Map<String, String> keyLabels;

  const DescriptorTab({
    super.key,
    required this.descriptor,
    this.isDirty = false,
    this.keyLabels = const {},
  });

  @override
  State<DescriptorTab> createState() => _DescriptorTabState();
}

class _DescriptorTabState extends State<DescriptorTab> {
  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;

    return Column(
      children: [
        if (widget.isDirty)
          _StaleBanner(label: l10n.descriptorOutdatedBanner),
        Expanded(
          child: DescriptorDisplay(
            descriptor: widget.descriptor,
            keyLabels: widget.keyLabels,
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
          child: SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: () => showDescriptorExportSheet(
                context,
                descriptor: widget.descriptor,
                fileName: 'descriptor',
                copiedMessage: l10n.descriptorCopied,
              ),
              icon: const Icon(Icons.file_upload_outlined, size: 18),
              label: Text(l10n.copyDescriptorTooltip),
              style: OutlinedButton.styleFrom(
                foregroundColor: AppAccent.color,
                side: BorderSide(color: AppAccent.color.withAlpha(AppAlpha.border)),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// Read-only tokenized view of a descriptor with an Alias/Raw toggle.
///
/// When [shrinkWrap] is false (default) the content fills its parent and
/// scrolls internally — used by [DescriptorTab]. When [shrinkWrap] is true the
/// widget sizes to its content with no inner scroll, suitable for embedding in
/// an outer scroll view (e.g. dialog forms).
class DescriptorDisplay extends StatefulWidget {
  final String descriptor;
  final Map<String, String> keyLabels;
  final bool shrinkWrap;

  const DescriptorDisplay({
    super.key,
    required this.descriptor,
    this.keyLabels = const {},
    this.shrinkWrap = false,
  });

  @override
  State<DescriptorDisplay> createState() => _DescriptorDisplayState();
}

class _DescriptorDisplayState extends State<DescriptorDisplay> {
  bool _showAlias = true;
  late String _aliasDescriptor;

  @override
  void initState() {
    super.initState();
    _aliasDescriptor =
        buildAliasDescriptor(widget.descriptor, widget.keyLabels);
  }

  @override
  void didUpdateWidget(DescriptorDisplay old) {
    super.didUpdateWidget(old);
    if (old.descriptor != widget.descriptor ||
        !mapEquals(old.keyLabels, widget.keyLabels)) {
      _aliasDescriptor =
          buildAliasDescriptor(widget.descriptor, widget.keyLabels);
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final l10n = context.l10n;

    final spans = _showAlias
        ? tokenizeAlias(_aliasDescriptor, colors)
        : tokenizeRaw(widget.descriptor, colors);

    final card = ConstrainedBox(
      constraints: const BoxConstraints(minWidth: double.infinity),
      child: Card(
        margin: EdgeInsets.zero,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: SelectableText.rich(
            TextSpan(
              style: const TextStyle(fontFamily: kMonospaceFontFamily, fontSize: 12),
              children: spans,
            ),
          ),
        ),
      ),
    );

    final toggle = _ModeToggle(
      showAlias: _showAlias,
      onToggle: (v) => setState(() => _showAlias = v),
      aliasLabel: l10n.descriptorViewAlias,
      rawLabel: l10n.descriptorViewRaw,
    );

    if (widget.shrinkWrap) {
      return Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          toggle,
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
            child: card,
          ),
        ],
      );
    }

    return Column(
      children: [
        toggle,
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: card,
          ),
        ),
      ],
    );
  }
}

class _ModeToggle extends StatelessWidget {
  final bool showAlias;
  final ValueChanged<bool> onToggle;
  final String aliasLabel;
  final String rawLabel;

  const _ModeToggle({
    required this.showAlias,
    required this.onToggle,
    required this.aliasLabel,
    required this.rawLabel,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
      child: SegmentedButton<bool>(
        showSelectedIcon: false,
        segments: [
          ButtonSegment(
            value: true,
            label: Text(aliasLabel),
            icon: const Icon(Icons.label_outline, size: 14),
          ),
          ButtonSegment(
            value: false,
            label: Text(rawLabel),
            icon: const Icon(Icons.code, size: 14),
          ),
        ],
        selected: {showAlias},
        onSelectionChanged: (s) => onToggle(s.first),
        style: SegmentedButton.styleFrom(
          textStyle: const TextStyle(fontSize: 12),
          visualDensity: VisualDensity.compact,
        ),
      ),
    );
  }
}

class _StaleBanner extends StatelessWidget {
  final String label;

  const _StaleBanner({required this.label});

  @override
  Widget build(BuildContext context) {
    const color = Colors.amber;
    return Container(
      width: double.infinity,
      color: color.withAlpha(AppAlpha.faint),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(
        children: [
          const Icon(Icons.warning_amber_rounded, size: 14, color: color),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              label,
              style: const TextStyle(fontSize: 11, color: color),
            ),
          ),
        ],
      ),
    );
  }
}
