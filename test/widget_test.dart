import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Basic widget test', () {
    testWidgets('Counter increments smoke test', (WidgetTester tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            appBar: AppBar(title: const Text('Test')),
            body: const Center(child: Text('Hello World')),
          ),
        ),
      );

      expect(find.text('Hello World'), findsOneWidget);
      expect(find.text('Test'), findsOneWidget);
    });
  });
}
