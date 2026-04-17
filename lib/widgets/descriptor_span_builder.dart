import 'package:flutter/material.dart';

import 'package:deadbolt/theme/app_theme.dart';

const _kw =
    'sortedmulti|wpkh|wsh|and_v|and_b|and_n|or_c|or_b|or_d|or_i|thresh|multi|pkh|sh|tr';

// Operators that represent spending branches — each argument gets its own line.
const _breakingFunctions = {
  'or_d', 'or_c', 'or_b', 'or_i',
  'and_v', 'and_b', 'and_n',
  'thresh',
  'tr',
};

enum _FrameType { breaking, inline, brace }

String _indent(List<_FrameType> stack) =>
    '  ' * stack.where((f) => f != _FrameType.inline).length;

final _checksumRe = RegExp(r'(#[a-zA-Z0-9]+)$');
final _identCharRe = RegExp(r'[A-Za-z0-9_:]');

/// Formats a Bitcoin descriptor with indented branches, like code.
///
/// Branch operators (or_*, and_*, thresh, tr) and Taproot script sets break each
/// argument onto its own line. Everything else (wsh, sortedmulti, pk, etc.) stays
/// inline. Content inside fingerprint/path brackets and range tokens is never split.
String formatDescriptor(String descriptor) {
  final checksumMatch = _checksumRe.firstMatch(descriptor);
  final checksum = checksumMatch?.group(0) ?? '';
  final body = checksumMatch != null
      ? descriptor.substring(0, checksumMatch.start)
      : descriptor;

  final buf = StringBuffer();
  final stack = <_FrameType>[];
  var insideBracket = 0;
  var insideAngle = 0;
  var lastIdent = '';

  for (var i = 0; i < body.length; i++) {
    final ch = body[i];

    if (insideBracket > 0 || insideAngle > 0) {
      if (ch == '[') { insideBracket++; }
      else if (ch == ']') { insideBracket--; }
      else if (ch == '<') { insideAngle++; }
      else if (ch == '>') { insideAngle--; }
      buf.write(ch);
      continue;
    }

    switch (ch) {
      case '[':
        insideBracket++;
        buf.write(ch);
        lastIdent = '';
      case '<':
        insideAngle++;
        buf.write(ch);
        lastIdent = '';
      case '(':
        final isBreaking = _breakingFunctions.contains(lastIdent);
        stack.add(isBreaking ? _FrameType.breaking : _FrameType.inline);
        buf.write('(');
        lastIdent = '';
        if (isBreaking) {
          buf.write('\n');
          buf.write(_indent(stack));
        }
      case ',':
        buf.write(',');
        lastIdent = '';
        if (stack.isNotEmpty &&
            stack.last != _FrameType.inline) {
          buf.write('\n');
          buf.write(_indent(stack));
        }
      case ')':
        final wasBreaking = stack.isNotEmpty && stack.last == _FrameType.breaking;
        if (stack.isNotEmpty) stack.removeLast();
        if (wasBreaking) {
          buf.write('\n');
          buf.write(_indent(stack));
        }
        buf.write(')');
        lastIdent = '';
      case '{':
        stack.add(_FrameType.brace);
        buf.write('{');
        buf.write('\n');
        buf.write(_indent(stack));
        lastIdent = '';
      case '}':
        if (stack.isNotEmpty) stack.removeLast();
        buf.write('\n');
        buf.write(_indent(stack));
        buf.write('}');
        lastIdent = '';
      default:
        if (_identCharRe.hasMatch(ch)) {
          lastIdent += ch;
        } else {
          lastIdent = '';
        }
        buf.write(ch);
    }
  }

  buf.write(checksum);
  return buf.toString();
}

// BIP341 NUMS x-only pubkey — unspendable tap internal key per BIP341 §V.
const _numsHex =
    '50929b74c1a04954b78b4b6035e97a5e078a5a0f28ec96d547bfee9ace803ac0';

const _unspendableLabel = 'unspendable';

// Groups: 1=keyword, 2=[mfp/path], 3=NUMS_hex, 4=bare_xpub(NUMS),
//         5=normal_xpub, 6=change_path, 7=checksum, 8=number, 9=punctuation
final _rawRe = RegExp(
  '($_kw)(?=\\()'                                  // 1: keyword (only before '(')
  r'|(\[[0-9a-fA-F]{8}[^\]]*\])'                   // 2: [fingerprint/path]
  '|($_numsHex)'                                   // 3: raw NUMS point (legacy)
  r'|(?<!\])([A-Za-z]{1,4}pub[A-Za-z0-9]+)'       // 4: bare xpub = NUMS xpub
  r'|([A-Za-z]{1,4}pub[A-Za-z0-9]+)'              // 5: normal xpub (after ])
  r'|(/<[^>]+>/\*|/\d+/\*)'                        // 6: change/wildcard path
  r'|(#[a-zA-Z0-9]+)'                              // 7: checksum
  r'|(\b[0-9]+\b)'                                 // 8: threshold number
  r'|([(),])',                                      // 9: punctuation
);

// Groups: 1=keyword, 2=@alias, 3=checksum, 4=number, 5=punct
final _aliasRe = RegExp(
  '($_kw)(?=\\()'
  r'|(@[A-Za-z0-9_]+)'
  r'|(#[a-zA-Z0-9]+)'
  r'|(\b[0-9]+\b)'
  r'|([(),])',
);

final _keyEntryRe = RegExp(
  r'\[([0-9a-fA-F]{8})[^\]]*\][A-Za-z0-9]+'
  r'(?:/<[^>]+>/\*)?',
);

final _bareXpubRe = RegExp(
  r'(?<!\])[A-Za-z]{1,4}pub[A-Za-z0-9]+(?:/<[^>]+>/\*)?',
);

final _numsXpubRe = RegExp('$_numsHex(?:/<[^>]+>/\\*)?');

final _normalizeAliasRe = RegExp(r'[^A-Za-z0-9_]');

String _normalizeAlias(String alias) =>
    alias.replaceAll(_normalizeAliasRe, '_');

String buildAliasDescriptor(
    String descriptor, Map<String, String> keyLabels) {
  String result = descriptor.replaceAllMapped(_keyEntryRe, (m) {
    final mfp = m.group(1)!;
    final raw = keyLabels[mfp];
    final alias =
        (raw != null && raw.isNotEmpty) ? _normalizeAlias(raw) : mfp;
    return '@$alias';
  });
  result = result.replaceAll(_numsXpubRe, '@$_unspendableLabel');
  return result.replaceAll(_bareXpubRe, '@$_unspendableLabel');
}

/// Syntax-highlighted spans for the raw descriptor.
List<InlineSpan> tokenizeRaw(String descriptor, ColorScheme colors) =>
    _tokenize(formatDescriptor(descriptor), _rawRe, colors, isAlias: false);

/// Syntax-highlighted spans for the alias descriptor.
List<InlineSpan> tokenizeAlias(String aliasDescriptor, ColorScheme colors) =>
    _tokenize(formatDescriptor(aliasDescriptor), _aliasRe, colors, isAlias: true);

List<InlineSpan> _tokenize(
    String text, RegExp re, ColorScheme colors, {required bool isAlias}) {
  final spans = <InlineSpan>[];
  int pos = 0;

  for (final m in re.allMatches(text)) {
    if (m.start > pos) {
      spans.add(_s(
          text.substring(pos, m.start),
          colors.onSurface.withAlpha(AppAlpha.medium)));
    }

    final tok = m.group(0)!;
    final Color color;

    if (isAlias) {
      // Groups: 1=keyword, 2=@alias, 3=checksum, 4=number, 5=punct
      if (m.group(1) != null) {
        color = colors.primary;
      } else if (m.group(2) != null) {
        color = tok == '@$_unspendableLabel'
            ? colors.onSurface.withAlpha(AppAlpha.muted)
            : AppAccent.color;
      } else if (m.group(3) != null) {
        color = colors.onSurface.withAlpha(AppAlpha.hint);
      } else if (m.group(4) != null) {
        color = AppAccent.color;
      } else {
        color = colors.onSurface.withAlpha(AppAlpha.secondary);
      }
    } else {
      if (m.group(1) != null) {
        color = colors.primary;
      } else if (m.group(2) != null) {
        color = colors.secondary;
      } else if (m.group(3) != null || m.group(4) != null) {
        // NUMS point / bare NUMS xpub — muted to signal non-spendable
        color = colors.onSurface.withAlpha(AppAlpha.hint);
      } else if (m.group(5) != null) {
        color = colors.onSurface.withAlpha(AppAlpha.medium);
      } else if (m.group(6) != null) {
        color = colors.onSurface.withAlpha(AppAlpha.muted);
      } else if (m.group(7) != null) {
        color = colors.onSurface.withAlpha(AppAlpha.hint);
      } else if (m.group(8) != null) {
        color = AppAccent.color;
      } else {
        color = colors.onSurface.withAlpha(AppAlpha.secondary);
      }
    }

    spans.add(_s(tok, color));
    pos = m.end;
  }

  if (pos < text.length) {
    spans.add(_s(
        text.substring(pos), colors.onSurface.withAlpha(AppAlpha.medium)));
  }

  return spans;
}

TextSpan _s(String text, Color color) =>
    TextSpan(text: text, style: TextStyle(color: color));
