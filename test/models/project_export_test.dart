import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:deadbolt/models/project_export.dart';

void main() {
  final sampleExport = ProjectExport(
    version: 1,
    exportedAt: DateTime(2024, 6, 15, 12, 0),
    name: 'My Wallet',
    descriptor: 'wpkh([abc12345/84h/0h/0h]xpub...)',
    keyLabels: {'abc12345': 'Hardware Key'},
    pathLabels: {'12345': 'Main Path'},
  );

  group('ProjectExport', () {
    test('round-trips through JSON', () {
      final json = sampleExport.toJsonString();
      final restored = ProjectExport.fromJsonString(json);

      expect(restored.version, 1);
      expect(restored.name, 'My Wallet');
      expect(restored.descriptor, 'wpkh([abc12345/84h/0h/0h]xpub...)');
      expect(restored.keyLabels, {'abc12345': 'Hardware Key'});
      expect(restored.pathLabels, {'12345': 'Main Path'});
      expect(restored.exportedAt, DateTime(2024, 6, 15, 12, 0));
    });

    test('toJson produces expected structure', () {
      final json = sampleExport.toJson();

      expect(json['version'], 1);
      expect(json['project']['name'], 'My Wallet');
      expect(json['project']['descriptor'],
          'wpkh([abc12345/84h/0h/0h]xpub...)');
      expect(json['keyLabels'], isA<Map>());
      expect(json['pathLabels'], isA<Map>());
      expect(json['exportedAt'], isA<String>());
    });

    test('rejects unsupported version', () {
      final json = jsonEncode({
        'version': 2,
        'exportedAt': '2024-06-15T12:00:00.000',
        'project': {'name': 'Test', 'descriptor': 'wpkh(...)'},
        'keyLabels': {},
        'pathLabels': {},
      });

      expect(
        () => ProjectExport.fromJsonString(json),
        throwsA(isA<FormatException>().having(
          (e) => e.message,
          'message',
          contains('Unsupported export version'),
        )),
      );
    });

    test('throws on missing project field', () {
      final json = jsonEncode({
        'version': 1,
        'exportedAt': '2024-06-15T12:00:00.000',
        'keyLabels': {},
        'pathLabels': {},
      });

      expect(
        () => ProjectExport.fromJsonString(json),
        throwsA(isA<TypeError>()),
      );
    });

    test('handles empty labels', () {
      final export = ProjectExport(
        version: 1,
        exportedAt: DateTime(2024),
        name: 'Empty',
        descriptor: 'wpkh(...)',
        keyLabels: {},
        pathLabels: {},
      );

      final restored = ProjectExport.fromJsonString(export.toJsonString());
      expect(restored.keyLabels, isEmpty);
      expect(restored.pathLabels, isEmpty);
    });
  });
}
