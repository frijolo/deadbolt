import 'package:flutter/foundation.dart' show mapEquals;
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
  bool _showAlias = true;
  late String _aliasDescriptor;

  @override
  void initState() {
    super.initState();
    _aliasDescriptor =
        buildAliasDescriptor(widget.descriptor, widget.keyLabels);
  }

  @override
  void didUpdateWidget(DescriptorTab old) {
    super.didUpdateWidget(old);
    if (old.descriptor != widget.descriptor ||
        !mapEquals(old.keyLabels, widget.keyLabels)) {
      _aliasDescriptor =
          buildAliasDescriptor(widget.descriptor, widget.keyLabels);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final colors = Theme.of(context).colorScheme;

    final spans = _showAlias
        ? tokenizeAlias(_aliasDescriptor, colors)
        : tokenizeRaw(widget.descriptor, colors);

    return Column(
      children: [
        if (widget.isDirty)
          _StaleBanner(label: l10n.descriptorOutdatedBanner),
        _ModeToggle(
          showAlias: _showAlias,
          onToggle: (v) => setState(() => _showAlias = v),
        ),
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: ConstrainedBox(
              constraints: const BoxConstraints(minWidth: double.infinity),
              child: Card(
                margin: EdgeInsets.zero,
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: SelectableText.rich(
                    TextSpan(
                      style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
                      children: spans,
                    ),
                  ),
                ),
              ),
            ),
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

class _ModeToggle extends StatelessWidget {
  final bool showAlias;
  final ValueChanged<bool> onToggle;

  const _ModeToggle({required this.showAlias, required this.onToggle});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
      child: SegmentedButton<bool>(
        showSelectedIcon: false,
        segments: const [
          ButtonSegment(
            value: true,
            label: Text('Alias'),
            icon: Icon(Icons.label_outline, size: 14),
          ),
          ButtonSegment(
            value: false,
            label: Text('Raw'),
            icon: Icon(Icons.code, size: 14),
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
