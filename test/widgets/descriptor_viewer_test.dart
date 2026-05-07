import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:deadbolt/l10n/app_localizations.dart';
import 'package:deadbolt/widgets/descriptor_tab.dart';

// Complex multisig descriptor reused from regression_02_multisig_wsh.py:
// wsh(multi(2, A, B, C)) — three signet xpubs, MFPs 4061aff0 / ff81be5d / f3d33d4f.
const _kComplexDescriptor =
    'wsh(multi(2,'
    '[4061aff0/48h/1h/0h/2h]'
    'tpubDFAv39stw4ELPsWiyqNL2UcFwruoVdX89CEpzJwb1TV3k9JgW6tLPUicWJvRT5iUSH7HHdt6rXtgRSX5TWJZqDcwJZZTtj1WTcHLUCC7eXC'
    '/<0;1>/*,'
    '[ff81be5d/48h/1h/0h/2h]'
    'tpubDDxjvuVfYHF4KcVyd5wkNS6pKJvg1x6CUtCRL3nRX2MDHKcja6M7YB7FYFYDkXzx8fL7k9bYi8XDpfPetqvd6ER2VYt1WsQSHYnhhT2EX7K'
    '/<0;1>/*,'
    '[f3d33d4f/48h/1h/0h/2h]'
    'tpubDFLYS7v5vvjyhLMotrmn6KzdN46jJ8ife9yD8DUMygtNCR4U389Wr46vJj7kG9bJPqFmLSet7hAP5fVJvyc97x9fhKZ7Zm9cTdvMxHqT55h'
    '/<0;1>/*))';

const _kMfpA = '4061aff0';
const _kMfpB = 'ff81be5d';
const _kMfpC = 'f3d33d4f';

const _kLabels = {
  _kMfpA: 'Alice',
  _kMfpB: 'Bob',
  _kMfpC: 'Carol',
};

Widget _wrap(Widget child, {double width = 600, double height = 800}) {
  return MaterialApp(
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    home: Scaffold(
      body: SizedBox(
        width: width,
        height: height,
        child: child,
      ),
    ),
  );
}

String _renderedText(WidgetTester tester) {
  final selectables = tester.widgetList<SelectableText>(find.byType(SelectableText));
  expect(selectables, isNotEmpty,
      reason: 'DescriptorDisplay should render at least one SelectableText');
  return selectables.first.textSpan!.toPlainText();
}

Future<void> _toggleTo(WidgetTester tester, String label) async {
  await tester.tap(find.text(label));
  await tester.pumpAndSettle();
}

void main() {
  group('DescriptorDisplay (complex wsh multisig)', () {
    testWidgets('alias mode without labels falls back to MFPs', (tester) async {
      await tester.pumpWidget(_wrap(
        const DescriptorDisplay(descriptor: _kComplexDescriptor),
      ));

      final text = _renderedText(tester);
      // No labels → alias mode shows @<mfp> placeholders, never the raw xpub.
      expect(text, contains('@$_kMfpA'));
      expect(text, contains('@$_kMfpB'));
      expect(text, contains('@$_kMfpC'));
      expect(text, isNot(contains('tpubDFAv39stw4ELPsWiyqNL2UcFwruoVdX89CE')));
    });

    testWidgets('alias mode with labels substitutes friendly names', (tester) async {
      await tester.pumpWidget(_wrap(
        const DescriptorDisplay(
          descriptor: _kComplexDescriptor,
          keyLabels: _kLabels,
        ),
      ));

      final text = _renderedText(tester);
      expect(text, contains('@Alice'));
      expect(text, contains('@Bob'));
      expect(text, contains('@Carol'));
      // Labels override MFPs: the raw fingerprints must NOT appear.
      expect(text, isNot(contains(_kMfpA)));
      expect(text, isNot(contains(_kMfpB)));
      expect(text, isNot(contains(_kMfpC)));
    });

    testWidgets('Raw toggle shows the unredacted descriptor', (tester) async {
      await tester.pumpWidget(_wrap(
        const DescriptorDisplay(
          descriptor: _kComplexDescriptor,
          keyLabels: _kLabels,
        ),
      ));

      await _toggleTo(tester, 'Raw');

      final text = _renderedText(tester);
      // Raw mode exposes MFPs and xpubs, never the @alias substitutions.
      expect(text, contains(_kMfpA));
      expect(text, contains('tpubDFAv39stw4ELPsWiyqNL2UcFwruoVdX89CE'));
      expect(text, isNot(contains('@Alice')));
    });

    testWidgets('toggling Alias → Raw → Alias is symmetric', (tester) async {
      await tester.pumpWidget(_wrap(
        const DescriptorDisplay(
          descriptor: _kComplexDescriptor,
          keyLabels: _kLabels,
        ),
      ));

      final initial = _renderedText(tester);
      expect(initial, contains('@Alice'));

      await _toggleTo(tester, 'Raw');
      expect(_renderedText(tester), contains(_kMfpA));

      await _toggleTo(tester, 'Alias');
      expect(_renderedText(tester), contains('@Alice'));
    });

    testWidgets('didUpdateWidget rebuilds alias when keyLabels change',
        (tester) async {
      await tester.pumpWidget(_wrap(
        const DescriptorDisplay(descriptor: _kComplexDescriptor),
      ));
      expect(_renderedText(tester), contains('@$_kMfpA'));

      await tester.pumpWidget(_wrap(
        const DescriptorDisplay(
          descriptor: _kComplexDescriptor,
          keyLabels: _kLabels,
        ),
      ));

      final updated = _renderedText(tester);
      expect(updated, contains('@Alice'));
      expect(updated, isNot(contains('@$_kMfpA')));
    });

    testWidgets('shrinkWrap=false uses internal SingleChildScrollView',
        (tester) async {
      await tester.pumpWidget(_wrap(
        const DescriptorDisplay(descriptor: _kComplexDescriptor),
      ));

      // Default mode keeps the legacy DescriptorTab layout: Expanded scroll.
      expect(find.byType(SingleChildScrollView), findsOneWidget);
    });

    testWidgets('shrinkWrap=true has no internal scroll view', (tester) async {
      await tester.pumpWidget(_wrap(
        const DescriptorDisplay(
          descriptor: _kComplexDescriptor,
          shrinkWrap: true,
        ),
      ));

      // Embedded mode lets the outer scroll handle overflow.
      expect(find.byType(SingleChildScrollView), findsNothing);
    });

    testWidgets('shrinkWrap=true renders inside a scrolling parent',
        (tester) async {
      await tester.pumpWidget(MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: ListView(
            children: const [
              DescriptorDisplay(
                descriptor: _kComplexDescriptor,
                keyLabels: _kLabels,
                shrinkWrap: true,
              ),
            ],
          ),
        ),
      ));

      expect(_renderedText(tester), contains('@Alice'));
    });
  });
}
