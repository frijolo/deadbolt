import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:file_picker/file_picker.dart';

import 'package:deadbolt/cubit/project_list_cubit.dart';
import 'package:deadbolt/data/database.dart';
import 'package:deadbolt/errors.dart';
import 'package:deadbolt/screens/about_screen.dart';
import 'package:deadbolt/screens/create_project_dialog.dart';
import 'package:deadbolt/screens/project_detail_screen.dart';
import 'package:deadbolt/src/rust/api/model.dart';
import 'package:deadbolt/utils/enum_formatters.dart';
import 'package:deadbolt/utils/toast_helper.dart';

class ProjectListScreen extends StatelessWidget {
  const ProjectListScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Projects'),
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
              }
            },
            itemBuilder: (context) => [
              const PopupMenuItem(
                value: 'new',
                child: Row(
                  children: [
                    Icon(Icons.add),
                    SizedBox(width: 8),
                    Text('New'),
                  ],
                ),
              ),
              const PopupMenuItem(
                value: 'import',
                child: Row(
                  children: [
                    Icon(Icons.file_download_outlined),
                    SizedBox(width: 8),
                    Text('Import'),
                  ],
                ),
              ),
              const PopupMenuItem(
                value: 'about',
                child: Row(
                  children: [
                    Icon(Icons.info_outline),
                    SizedBox(width: 8),
                    Text('About'),
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
                    if (message != null) ...[
                      const SizedBox(height: 16),
                      Text(
                        message,
                        style: const TextStyle(color: Colors.white70),
                      ),
                    ],
                  ],
                ),
              ),
            ProjectListError(:final message) =>
              Center(child: Text(message)),
            ProjectListLoaded(:final projects) => projects.isEmpty
                ? const Center(
                    child: Text(
                      'No projects yet.\nTap + to create one.',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: Colors.white54),
                    ),
                  )
                : ListView.builder(
                    padding: const EdgeInsets.all(16),
                    itemCount: projects.length,
                    itemBuilder: (context, index) =>
                        _buildProjectCard(context, projects[index]),
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
              _buildBadge(networkDisplayName(project.network)),
              const SizedBox(width: 8),
              _buildBadge(
                APIWalletType.values.byName(project.walletType).displayName,
              ),
            ],
          ),
        ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              _formatDate(project.updatedAt),
              style: const TextStyle(fontSize: 12, color: Colors.white38),
            ),
            const SizedBox(width: 8),
            IconButton(
              icon: const Icon(Icons.delete_outline, size: 20),
              color: Colors.red.withAlpha(180),
              onPressed: () => _confirmDelete(context, project),
              tooltip: 'Delete project',
              visualDensity: VisualDensity.compact,
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

  Widget _buildBadge(String label) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: Colors.orange.withAlpha(32),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: Colors.orange.withAlpha(64)),
      ),
      child: Text(
        label,
        style: const TextStyle(fontSize: 11, color: Colors.white70),
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
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete project'),
        content: Text('Delete "${project.name}"?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () {
              context.read<ProjectListCubit>().deleteProject(project.id);
              Navigator.pop(ctx);
            },
            child: const Text('Delete', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
  }

  Future<void> _showImportDialog(BuildContext context) async {
    try {
      // Get references before async gap
      final cubit = context.read<ProjectListCubit>();
      final db = context.read<AppDatabase>();

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
          showErrorToast(context, 'Could not read file');
        }
        return;
      }

      final jsonString = String.fromCharCodes(file.bytes!);

      // Import project
      final projectId = await cubit.importProject(jsonString);

      if (context.mounted) {
        showSuccessToast(context, 'Project imported successfully');

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
        showErrorToast(context, 'Import failed: ${formatRustError(e)}');
      }
    }
  }
}
