import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:file_picker/file_picker.dart';

import 'package:deadbolt/cubit/project_list_cubit.dart';
import 'package:deadbolt/data/database.dart';
import 'package:deadbolt/errors.dart';
import 'package:deadbolt/l10n/l10n.dart';
import 'package:deadbolt/screens/about_screen.dart';
import 'package:deadbolt/screens/create_project_dialog.dart';
import 'package:deadbolt/screens/project_detail_screen.dart';
import 'package:deadbolt/screens/settings_screen.dart';
import 'package:deadbolt/src/rust/api/model.dart';
import 'package:deadbolt/utils/enum_formatters.dart';
import 'package:deadbolt/utils/export_sheet.dart';
import 'package:deadbolt/utils/toast_helper.dart';

class ProjectListScreen extends StatelessWidget {
  const ProjectListScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.projectsTitle),
        actions: [
          PopupMenuButton<String>(
            icon: const Icon(Icons.more_vert),
            onSelected: (value) async {
              if (value == 'new') {
                _showCreateDialog(context);
              } else if (value == 'import') {
                await _showImportDialog(context);
              } else if (value == 'about') {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => const AboutScreen(),
                  ),
                );
              } else if (value == 'settings') {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => const SettingsScreen(),
                  ),
                );
              }
            },
            itemBuilder: (context) => [
              PopupMenuItem(
                value: 'new',
                child: Row(
                  children: [
                    const Icon(Icons.add),
                    const SizedBox(width: 8),
                    Text(l10n.menuNew),
                  ],
                ),
              ),
              PopupMenuItem(
                value: 'import',
                child: Row(
                  children: [
                    const Icon(Icons.file_download_outlined),
                    const SizedBox(width: 8),
                    Text(l10n.menuImport),
                  ],
                ),
              ),
              PopupMenuItem(
                value: 'settings',
                child: Row(
                  children: [
                    const Icon(Icons.settings_outlined),
                    const SizedBox(width: 8),
                    Text(l10n.menuSettings),
                  ],
                ),
              ),
              PopupMenuItem(
                value: 'about',
                child: Row(
                  children: [
                    const Icon(Icons.info_outline),
                    const SizedBox(width: 8),
                    Text(l10n.menuAbout),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
      body: SafeArea(
        child: BlocBuilder<ProjectListCubit, ProjectListState>(
          builder: (context, state) {
            return switch (state) {
            ProjectListLoading(:final message) => Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const CircularProgressIndicator(),
                    const SizedBox(height: 16),
                    Text(
                      message ?? context.l10n.loadingProjects,
                      style: TextStyle(color: Theme.of(context).colorScheme.onSurface.withAlpha(178)),
                    ),
                  ],
                ),
              ),
            ProjectListError(:final message) =>
              Center(child: Text(message)),
            ProjectListLoaded(:final projects) => projects.isEmpty
                ? Center(
                    child: Text(
                      l10n.noProjects,
                      textAlign: TextAlign.center,
                      style: TextStyle(color: Theme.of(context).colorScheme.onSurface.withAlpha(138)),
                    ),
                  )
                : ListView.builder(
                    padding: const EdgeInsets.all(16),
                    itemCount: projects.length,
                    itemBuilder: (context, index) => KeyedSubtree(
                      key: ValueKey(projects[index].id),
                      child: _buildProjectCard(context, projects[index]),
                    ),
                  ),
            };
          },
        ),
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => _showCreateDialog(context),
        child: const Icon(Icons.add),
      ),
    );
  }

  Widget _buildProjectCard(BuildContext context, Project project) {
    final l10n = context.l10n;
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: ListTile(
        title: Text(
          project.name,
          style: const TextStyle(fontWeight: FontWeight.w600),
        ),
        subtitle: Padding(
          padding: const EdgeInsets.only(top: 4),
          child: Row(
            children: [
              _buildBadge(context, localizedNetworkDisplayName(context, project.network)),
              const SizedBox(width: 8),
              _buildBadge(
                context,
                localizedWalletTypeName(
                  context,
                  APIWalletType.values.byName(project.walletType),
                ),
              ),
            ],
          ),
        ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              _formatDate(project.updatedAt),
              style: TextStyle(fontSize: 12, color: Theme.of(context).colorScheme.onSurface.withAlpha(97)),
            ),
            PopupMenuButton<String>(
              icon: const Icon(Icons.more_vert, size: 20),
              tooltip: l10n.moreOptionsTooltip,
              onSelected: (value) async {
                final db = context.read<AppDatabase>();
                if (value == 'edit') {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => ProjectDetailScreen(
                        db: db,
                        projectId: project.id,
                        initialAction: 'edit',
                      ),
                    ),
                  );
                } else if (value == 'export') {
                  await _exportProject(context, project);
                } else if (value == 'delete') {
                  _confirmDelete(context, project);
                }
              },
              itemBuilder: (context) => [
                PopupMenuItem(
                  value: 'edit',
                  child: Row(
                    children: [
                      const Icon(Icons.edit_outlined, size: 20),
                      const SizedBox(width: 12),
                      Text(l10n.edit),
                    ],
                  ),
                ),
                PopupMenuItem(
                  value: 'export',
                  child: Row(
                    children: [
                      const Icon(Icons.file_upload_outlined, size: 20),
                      const SizedBox(width: 12),
                      Text(l10n.export),
                    ],
                  ),
                ),
                PopupMenuItem(
                  value: 'delete',
                  child: Row(
                    children: [
                      Icon(
                        Icons.delete_outline,
                        size: 20,
                        color: Colors.red.withAlpha(180),
                      ),
                      const SizedBox(width: 12),
                      Text(
                        l10n.delete,
                        style: TextStyle(color: Colors.red.withAlpha(180)),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ],
        ),
        onTap: () => Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => ProjectDetailScreen(
              db: context.read<AppDatabase>(),
              projectId: project.id,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildBadge(BuildContext context, String label) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: Colors.orange.withAlpha(32),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: Colors.orange.withAlpha(64)),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 11,
          color: Theme.of(context).colorScheme.onSurface.withAlpha(178),
        ),
      ),
    );
  }

  String _formatDate(DateTime dt) {
    return '${dt.day}/${dt.month}/${dt.year}';
  }

  void _showCreateDialog(BuildContext context) async {
    final projectId = await Navigator.push<int>(
      context,
      MaterialPageRoute(
        fullscreenDialog: true,
        builder: (_) => CreateProjectDialog(
          cubit: context.read<ProjectListCubit>(),
        ),
      ),
    );
    if (projectId != null && context.mounted) {
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => ProjectDetailScreen(
            db: context.read<AppDatabase>(),
            projectId: projectId,
          ),
        ),
      );
    }
  }

  void _confirmDelete(BuildContext context, Project project) {
    final l10n = context.l10n;
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l10n.deleteProjectTitle),
        content: Text(l10n.deleteProjectConfirm(project.name)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(l10n.cancel),
          ),
          TextButton(
            onPressed: () {
              context.read<ProjectListCubit>().deleteProject(project.id);
              Navigator.pop(ctx);
            },
            child: Text(l10n.delete, style: const TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
  }

  Future<void> _exportProject(BuildContext context, Project project) async {
    final data =
        await context.read<ProjectListCubit>().buildProjectExportData(project.id);

    if (!context.mounted) return;
    if (data == null) {
      showErrorToast(context, context.l10n.exportFailed(''));
      return;
    }

    showProjectExportSheet(
      context,
      jsonString: data.jsonString,
      fileName: data.fileName,
      projectName: project.name,
    );
  }

  Future<void> _showImportDialog(BuildContext context) async {
    try {
      // Get references before async gap
      final cubit = context.read<ProjectListCubit>();
      final db = context.read<AppDatabase>();
      final l10n = context.l10n;

      // Pick file
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['json'],
        withData: true,
      );

      if (result == null || result.files.isEmpty) return;

      final file = result.files.first;
      if (file.bytes == null) {
        if (context.mounted) {
          showErrorToast(context, l10n.couldNotReadFile);
        }
        return;
      }

      final jsonString = String.fromCharCodes(file.bytes!);

      // Import project
      final projectId = await cubit.importProject(jsonString);

      if (context.mounted) {
        showSuccessToast(context, l10n.projectImportedSuccess);

        // Navigate to imported project
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => ProjectDetailScreen(
              db: db,
              projectId: projectId,
            ),
          ),
        );
      }
    } catch (e) {
      if (context.mounted) {
        showErrorToast(context, context.l10n.importFailed(formatRustError(e)));
      }
    }
  }
}
