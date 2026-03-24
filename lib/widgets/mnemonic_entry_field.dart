import 'package:flutter/material.dart';

import 'package:deadbolt/src/rust/api/wallet.dart'
    show bip39ValidLastWords, bip39Wordlist;

// Cached BIP39 wordlist loaded from Rust (loaded once on first use).
List<String>? _bip39Cache;
List<String> _wordlist() => _bip39Cache ??= bip39Wordlist();

/// Valid BIP39 mnemonic word counts.
const bip39ValidWordCounts = [12, 15, 18, 21, 24];

/// A mnemonic seed phrase entry widget with BIP39 autocomplete.
///
/// Shows word-count selector chips, a multi-line text field, a live word
/// progress counter, and a suggestion bar that:
///   - For intermediate words: filters the BIP39 wordlist by prefix.
///   - For the last word: returns only checksum-valid completions via Rust.
class MnemonicEntryField extends StatefulWidget {
  final TextEditingController controller;

  /// Called when the user changes the target word count.
  final void Function(int count)? onTargetWordCountChanged;

  /// Error text to show below the text field (e.g. from parent validation).
  final String? errorText;

  const MnemonicEntryField({
    super.key,
    required this.controller,
    this.onTargetWordCountChanged,
    this.errorText,
  });

  @override
  State<MnemonicEntryField> createState() => _MnemonicEntryFieldState();
}

class _MnemonicEntryFieldState extends State<MnemonicEntryField> {
  int _targetCount = 12;
  List<String> _suggestions = [];
  bool _loadingLastWord = false;

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_onTextChanged);
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onTextChanged);
    super.dispose();
  }

  void _onTextChanged() {
    _updateSuggestions();
  }

  /// Parses cursor position and returns (completedWordCount, currentPrefix).
  (int, String) _parsePosition() {
    final text = widget.controller.text;
    final sel = widget.controller.selection;
    final cursorPos = sel.isValid ? sel.baseOffset : text.length;
    final textToCursor = text.substring(0, cursorPos.clamp(0, text.length));

    final lastChar =
        textToCursor.isNotEmpty ? textToCursor[textToCursor.length - 1] : '';
    final endsWithSpace = lastChar == ' ' || lastChar == '\n';

    final tokens = textToCursor
        .trim()
        .split(RegExp(r'\s+'))
        .where((w) => w.isNotEmpty)
        .toList();

    if (endsWithSpace || textToCursor.isEmpty) {
      return (tokens.length, '');
    } else {
      final prefix = tokens.isEmpty ? '' : tokens.last;
      final completedCount = tokens.isEmpty ? 0 : tokens.length - 1;
      return (completedCount, prefix);
    }
  }

  void _updateSuggestions() {
    final (completedCount, prefix) = _parsePosition();
    final isLastWordPosition = completedCount == _targetCount - 1;

    if (isLastWordPosition) {
      // Get all words from the text for the partial mnemonic
      final allWords = widget.controller.text
          .trim()
          .split(RegExp(r'\s+'))
          .where((w) => w.isNotEmpty)
          .toList();
      // Pass the first (targetCount - 1) complete words to Rust
      final firstWords = allWords.take(_targetCount - 1).join(' ');

      setState(() => _loadingLastWord = true);
      // Sync call — runs on Dart isolate, fast enough for 2048 iterations
      final results = bip39ValidLastWords(
        partialWords: firstWords,
        prefix: prefix,
      );
      if (mounted) {
        setState(() {
          _suggestions = results;
          _loadingLastWord = false;
        });
      }
    } else if (prefix.isNotEmpty) {
      final prefixLower = prefix.toLowerCase();
      final matches = _wordlist()
          .where((w) => w.startsWith(prefixLower))
          .take(8)
          .toList();
      setState(() {
        _suggestions = matches;
        _loadingLastWord = false;
      });
    } else {
      setState(() {
        _suggestions = [];
        _loadingLastWord = false;
      });
    }
  }

  /// Replaces (or appends) the current partial word with [word] and moves
  /// the cursor past it.
  void _selectSuggestion(String word) {
    final text = widget.controller.text;
    final sel = widget.controller.selection;
    final cursorPos = sel.isValid ? sel.baseOffset : text.length;
    final textToCursor = text.substring(0, cursorPos.clamp(0, text.length));
    final textAfterCursor = text.substring(cursorPos.clamp(0, text.length));

    final lastChar =
        textToCursor.isNotEmpty ? textToCursor[textToCursor.length - 1] : '';
    final endsWithSpace = lastChar == ' ' || lastChar == '\n';

    String newBase;
    if (endsWithSpace || textToCursor.isEmpty) {
      newBase = '$textToCursor$word ';
    } else {
      final lastSpaceIdx = textToCursor.lastIndexOf(RegExp(r'\s'));
      final beforeCurrentWord =
          lastSpaceIdx == -1 ? '' : textToCursor.substring(0, lastSpaceIdx + 1);
      newBase = '$beforeCurrentWord$word ';
    }

    final newText = newBase + textAfterCursor.trimLeft();
    widget.controller.value = TextEditingValue(
      text: newText,
      selection: TextSelection.collapsed(offset: newBase.length),
    );
  }

  int get _wordCount {
    final words =
        widget.controller.text.trim().split(RegExp(r'\s+')).where((w) => w.isNotEmpty);
    return words.length;
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final wordCount = _wordCount;
    final isComplete = wordCount == _targetCount;

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Word count selector
        Row(
          children: [
            Text(
              'Words:',
              style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant),
            ),
            const SizedBox(width: 8),
            Wrap(
              spacing: 4,
              children: [
                for (final count in bip39ValidWordCounts)
                  ChoiceChip(
                    label: Text(
                      '$count',
                      style: const TextStyle(fontSize: 11),
                    ),
                    selected: _targetCount == count,
                    visualDensity: VisualDensity.compact,
                    padding: const EdgeInsets.symmetric(horizontal: 4),
                    onSelected: (_) {
                      setState(() => _targetCount = count);
                      widget.onTargetWordCountChanged?.call(count);
                      _updateSuggestions();
                    },
                  ),
              ],
            ),
          ],
        ),
        const SizedBox(height: 8),
        // Label + progress
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Text('Seed phrase'),
            Text(
              '$wordCount / $_targetCount',
              style: TextStyle(
                color: isComplete ? Colors.green : cs.onSurfaceVariant,
                fontWeight: FontWeight.bold,
                fontSize: 13,
              ),
            ),
          ],
        ),
        const SizedBox(height: 4),
        // Text field
        TextField(
          controller: widget.controller,
          maxLines: 4,
          autocorrect: false,
          enableSuggestions: false,
          keyboardType: TextInputType.visiblePassword,
          decoration: InputDecoration(
            border: const OutlineInputBorder(),
            hintText: 'word1 word2 word3 ...',
            errorText: widget.errorText,
          ),
        ),
        // Suggestion bar
        if (_loadingLastWord) ...[
          const SizedBox(height: 8),
          Row(
            children: [
              const SizedBox(
                width: 14,
                height: 14,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
              const SizedBox(width: 6),
              Text(
                'Checking checksum...',
                style: TextStyle(fontSize: 11, color: cs.onSurfaceVariant),
              ),
            ],
          ),
        ] else if (_suggestions.isNotEmpty) ...[
          const SizedBox(height: 8),
          SizedBox(
            height: 34,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: _suggestions.length,
              separatorBuilder: (_, _) => const SizedBox(width: 4),
              itemBuilder: (context, i) => ActionChip(
                label: Text(
                  _suggestions[i],
                  style: const TextStyle(fontSize: 12),
                ),
                visualDensity: VisualDensity.compact,
                padding: const EdgeInsets.symmetric(horizontal: 6),
                onPressed: () => _selectSuggestion(_suggestions[i]),
              ),
            ),
          ),
        ],
      ],
    );
  }
}
