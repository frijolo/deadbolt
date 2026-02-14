import 'dart:convert';

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
