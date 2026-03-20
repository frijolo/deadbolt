import 'dart:convert';

import 'package:deadbolt/data/database.dart';

/// Build a {mfp → customName} map from a list of project keys.
Map<String, String> buildKeyLabels(List<ProjectKey> keys) => {
      for (final k in keys)
        if (k.customName != null) k.mfp: k.customName!,
    };

/// Build a {rustId → customName} map from a list of spend paths.
Map<String, String> buildPathLabels(List<ProjectSpendPath> paths) => {
      for (final p in paths)
        if (p.customName != null) p.rustId.toString(): p.customName!,
    };

/// Model for project export/import
class ProjectExport {
  final int version;
  final DateTime exportedAt;
  final String name;
  final String descriptor;
  final Map<String, String> keyLabels; // mfp -> customName
  final Map<String, String> pathLabels; // rustId (as string) -> customName

  const ProjectExport({
    required this.version,
    required this.exportedAt,
    required this.name,
    required this.descriptor,
    required this.keyLabels,
    required this.pathLabels,
  });

  Map<String, dynamic> toJson() => {
        'version': version,
        'exportedAt': exportedAt.toIso8601String(),
        'project': {
          'name': name,
          'descriptor': descriptor,
        },
        'keyLabels': keyLabels,
        'pathLabels': pathLabels,
      };

  factory ProjectExport.fromJson(Map<String, dynamic> json) {
    final version = json['version'] as int;
    if (version != 1) {
      throw FormatException('Unsupported export version: $version');
    }

    final project = json['project'] as Map<String, dynamic>;
    return ProjectExport(
      version: version,
      exportedAt: DateTime.parse(json['exportedAt'] as String),
      name: project['name'] as String,
      descriptor: project['descriptor'] as String,
      keyLabels: Map<String, String>.from(json['keyLabels'] as Map),
      pathLabels: Map<String, String>.from(json['pathLabels'] as Map),
    );
  }

  String toJsonString() => jsonEncode(toJson());

  factory ProjectExport.fromJsonString(String jsonString) {
    final json = jsonDecode(jsonString) as Map<String, dynamic>;
    return ProjectExport.fromJson(json);
  }
}
