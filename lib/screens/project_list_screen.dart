import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:file_picker/file_picker.dart';

import 'package:deadbolt/cubit/project_list_cubit.dart';
import 'package:deadbolt/theme/app_theme.dart';
import 'package:deadbolt/data/database.dart';
import 'package:deadbolt/errors.dart';
import 'package:deadbolt/l10n/l10n.dart';
import 'package:deadbolt/screens/create_project_dialog.dart';
import 'package:deadbolt/screens/create_wallet_dialog.dart';
import 'package:deadbolt/screens/project_detail_screen.dart';
import 'package:deadbolt/screens/qr_scanner_screen.dart';
import 'package:deadbolt/src/rust/api/model.dart';
import 'package:deadbolt/utils/enum_formatters.dart';
import 'package:deadbolt/utils/export_sheet.dart';
import 'package:deadbolt/utils/toast_helper.dart';
import 'package:deadbolt/widgets/app_nav_drawer.dart';
import 'package:deadbolt/widgets/mfp_badge.dart';

class ProjectListScreen extends StatelessWidget {
  final int navIndex;
  final void Function(int)? onNavigate;

  const ProjectListScreen({super.key, this.navIndex = 0, this.onNavigate});

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return Scaffold(
      drawer: onNavigate != null
          ? AppNavDrawer(selectedIndex: navIndex, onNavigate: onNavigate!)
          : null,
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
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          l10n.noProjects,
                          textAlign: TextAlign.center,
                          style: TextStyle(color: Theme.of(context).colorScheme.onSurface.withAlpha(138)),
                        ),
                        const SizedBox(height: 24),
                        FilledButton.icon(
                          onPressed: () => _showCreateDialog(context),
                          icon: const Icon(Icons.add),
                          label: Text(l10n.menuNew),
                        ),
                      ],
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
              MfpBadge(
                label: localizedNetworkDisplayName(context, project.network),
                color: AppAccent.color,
                letterSpacing: 0.0,
              ),
              const SizedBox(width: 8),
              MfpBadge(
                label: localizedWalletTypeName(
                  context,
                  APIWalletType.values.byName(project.walletType),
                ),
                color: AppAccent.color,
                letterSpacing: 0.0,
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
                      ),
                    ),
                  );
                } else if (value == 'export') {
                  await _exportProject(context, project);
                } else if (value == 'createWallet') {
                  await _createWalletFromProject(context, project);
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
                  value: 'createWallet',
                  child: Row(
                    children: [
                      const Icon(Icons.account_balance_wallet_outlined, size: 20),
                      const SizedBox(width: 12),
                      Text(l10n.createWalletFromProject),
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

  Future<void> _createWalletFromProject(
          BuildContext context, Project project) =>
      createWalletFromProject(context, project);

  void _confirmDelete(BuildContext context, Project project) {
    final l10n = context.l10n;
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        titlePadding: const EdgeInsets.fromLTRB(24, 16, 8, 0),
        title: Row(
          children: [
            Expanded(child: Text(l10n.deleteProjectTitle)),
            IconButton(
              icon: const Icon(Icons.close),
              tooltip: l10n.cancel,
              visualDensity: VisualDensity.compact,
              onPressed: () => Navigator.pop(ctx),
            ),
          ],
        ),
        content: Text(l10n.deleteProjectConfirm(project.name)),
        actions: [
          FilledButton(
            onPressed: () {
              context.read<ProjectListCubit>().deleteProject(project.id);
              Navigator.pop(ctx);
            },
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            child: Text(l10n.delete),
          ),
        ],
      ),
    );
  }

  Future<void> _exportProject(BuildContext context, Project project) async {
    try {
      final data =
          await context.read<ProjectListCubit>().buildProjectExportData(project.id);

      if (!context.mounted) return;
      showProjectExportSheet(
        context,
        jsonString: data.jsonString,
        fileName: data.fileName,
        projectName: project.name,
      );
    } catch (e) {
      if (context.mounted) {
        showErrorToast(context, context.l10n.exportFailed(formatRustError(e)));
      }
    }
  }

  Future<void> _showImportDialog(BuildContext context) async {
    final l10n = context.l10n;
    await showModalBottomSheet<void>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.file_download_outlined),
              title: Text(l10n.importFromFile),
              onTap: () {
                Navigator.pop(ctx);
                _importFromFile(context);
              },
            ),
            ListTile(
              leading: const Icon(Icons.qr_code_scanner),
              title: Text(l10n.scanQrCode),
              onTap: () {
                Navigator.pop(ctx);
                _importFromQr(context);
              },
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _importFromFile(BuildContext context) async {
    try {
      final cubit = context.read<ProjectListCubit>();
      final db = context.read<AppDatabase>();
      final l10n = context.l10n;

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
      final projectId = await cubit.importProject(jsonString);

      if (context.mounted) {
        showSuccessToast(context, l10n.projectImportedSuccess);
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

  Future<void> _importFromQr(BuildContext context) async {
    try {
      final cubit = context.read<ProjectListCubit>();
      final db = context.read<AppDatabase>();

      final jsonString = await QrScannerScreen.push(context);
      if (jsonString == null || jsonString.isEmpty) return;

      final projectId = await cubit.importProject(jsonString);

      if (context.mounted) {
        showSuccessToast(context, context.l10n.projectImportedSuccess);
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
