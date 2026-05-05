import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:deadbolt/cubit/project_list_cubit.dart';
import 'package:deadbolt/data/database.dart';
import 'package:deadbolt/screens/project_detail_screen.dart';
import 'package:deadbolt/utils/toast_helper.dart';
import 'package:deadbolt/errors.dart' show sanitizeForLog;

/// Handles the wallet-to-project migration flow.
///
/// Returns the [projectId] if a new project was created, or the existing
/// [projectId] if one already matched the descriptor. Returns null if
/// cancelled or the user navigated away mid-flow.
Future<int?> migrateWalletToProject({
  required BuildContext context,
  required String descriptor,
  required String walletName,
  required Map<String, String> keyLabels,
  required Map<int, String> pathLabels,
  required void Function(int) onNavigate,
}) async {
  final projectCubit = context.read<ProjectListCubit>();
  final db = context.read<AppDatabase>();

  final existingProject = projectCubit.state is ProjectListLoaded
      ? (projectCubit.state as ProjectListLoaded)
          .projects
          .where((p) => p.descriptor == descriptor)
          .firstOrNull
      : null;

  if (existingProject != null && context.mounted) {
    onNavigate.call(1);
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(
        builder: (_) => ProjectDetailScreen(
          db: db,
          projectId: existingProject.id,
        ),
      ),
    );
    return existingProject.id;
  }

  try {
    final projectId = await projectCubit.createProject(
      descriptor: descriptor,
      name: walletName,
    );
    if (!context.mounted) return null;
    await _copyWalletLabelsToProject(
      db: db,
      projectId: projectId,
      keyLabels: keyLabels,
      pathLabels: pathLabels,
    );
    if (!context.mounted) return null;
    onNavigate.call(1);
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(
        builder: (_) => ProjectDetailScreen(
          db: db,
          projectId: projectId,
        ),
      ),
    );
    return projectId;
  } catch (e) {
    if (context.mounted) {
      showErrorToastException(e);
    }
    return null;
  }
}

Future<void> _copyWalletLabelsToProject({
  required AppDatabase db,
  required int projectId,
  required Map<String, String> keyLabels,
  required Map<int, String> pathLabels,
}) async {
  try {
    final keys = await db.getKeysForProject(projectId);
    for (final key in keys) {
      final label = keyLabels[key.mfp];
      if (label != null && label.isNotEmpty) {
        await db.updateKeyName(key.id, label);
      }
    }
    final paths = await db.getSpendPathsForProject(projectId);
    for (final path in paths) {
      final label = pathLabels[path.rustId];
      if (label != null && label.isNotEmpty) {
        await db.updateSpendPathName(path.id, label);
      }
    }
  } catch (e, st) {
    debugPrint('Failed to copy wallet labels to project: ${sanitizeForLog(e.toString())}\n${sanitizeForLog(st.toString())}');
  }
}
