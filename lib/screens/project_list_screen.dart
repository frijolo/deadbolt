import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:deadbolt/cubit/project_list_cubit.dart';
import 'package:deadbolt/cubit/settings_cubit.dart';
import 'package:deadbolt/theme/app_theme.dart';
import 'package:deadbolt/data/database.dart';
import 'package:deadbolt/errors.dart';
import 'package:deadbolt/l10n/l10n.dart';
import 'package:deadbolt/screens/create_project_dialog.dart';
import 'package:deadbolt/screens/create_wallet_dialog.dart';
import 'package:deadbolt/screens/project_detail_screen.dart';
import 'package:deadbolt/src/rust/api/model.dart';
import 'package:deadbolt/utils/enum_formatters.dart';
import 'package:deadbolt/utils/export_sheet.dart';
import 'package:deadbolt/utils/toast_helper.dart';
import 'package:deadbolt/widgets/app_nav_drawer.dart';
import 'package:deadbolt/widgets/mfp_badge.dart';
import 'package:deadbolt/widgets/dialog_helpers.dart';
import 'package:deadbolt/widgets/text_import_sheet.dart';

enum _ProjectCreateMode { fromScratch, fromDescriptor, importProject }

class ProjectListScreen extends StatefulWidget {
  final int navIndex;
  final void Function(int)? onNavigate;

  const ProjectListScreen({super.key, this.navIndex = 0, this.onNavigate});

  @override
  State<ProjectListScreen> createState() => _ProjectListScreenState();
}

class _ProjectListScreenState extends State<ProjectListScreen> {
  SharedPreferences? _prefs;
  final Map<String, List<String>> _orderByTier = {};
  bool _reorderMode = false;

  static String _orderKey(bool isMainnet) =>
      isMainnet ? 'project_order_mainnet' : 'project_order_testnet';

  @override
  void initState() {
    super.initState();
    _loadOrder();
  }

  Future<void> _loadOrder() async {
    final prefs = _prefs ??= await SharedPreferences.getInstance();
    if (!mounted) return;
    setState(() {
      _orderByTier['mainnet'] = prefs.getStringList(_orderKey(true)) ?? [];
      _orderByTier['testnet'] = prefs.getStringList(_orderKey(false)) ?? [];
    });
  }

  List<Project> _applyOrder(List<Project> filtered, bool isMainnet) {
    final tierKey = isMainnet ? 'mainnet' : 'testnet';
    final savedOrder = _orderByTier[tierKey] ?? [];
    if (savedOrder.isEmpty) return filtered;

    final byId = {for (final p in filtered) p.id.toString(): p};
    final ordered = <Project>[];
    for (final idStr in savedOrder) {
      final p = byId.remove(idStr);
      if (p != null) ordered.add(p);
    }
    ordered.addAll(byId.values);
    return ordered;
  }

  Future<void> _onReorder(
      bool isMainnet, List<Project> current, int oldIndex, int newIndex) async {
    if (newIndex > oldIndex) newIndex--;
    final list = [...current];
    final item = list.removeAt(oldIndex);
    list.insert(newIndex, item);
    final ids = list.map((p) => p.id.toString()).toList();
    final tierKey = isMainnet ? 'mainnet' : 'testnet';
    setState(() => _orderByTier[tierKey] = ids);
    final prefs = _prefs ??= await SharedPreferences.getInstance();
    await prefs.setStringList(_orderKey(isMainnet), ids);
  }

  void _showNetworkTierPicker(BuildContext context, AppSettings settings) {
    final settingsCubit = context.read<SettingsCubit>();
    final isCurrentlyMainnet = settings.network == APINetwork.bitcoin;
    final l10n = context.l10n;
    showDialog(
      context: context,
      builder: (ctx) => SimpleDialog(
        title: Text(l10n.selectNetworkTooltip),
        children: [
          RadioGroup<bool>(
            groupValue: isCurrentlyMainnet,
            onChanged: (value) {
              if (value == true) {
                settingsCubit.setNetwork(APINetwork.bitcoin);
              } else if (!isCurrentlyMainnet) {
                // Already on testnet — no network change needed.
              } else {
                settingsCubit.setNetwork(APINetwork.testnet);
              }
              Navigator.pop(ctx);
            },
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                RadioListTile<bool>(
                  title: Text(l10n.networkMainnet),
                  value: true,
                ),
                RadioListTile<bool>(
                  title: Text(l10n.networkTestnet),
                  value: false,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final settings = context.watch<SettingsCubit>().state;

    return Scaffold(
      drawer: widget.onNavigate != null
          ? AppNavDrawer(selectedIndex: widget.navIndex, onNavigate: widget.onNavigate!)
          : null,
      appBar: AppBar(
        title: Text(l10n.projectsTitle),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 4),
            child: Center(
              child: GestureDetector(
                onTap: () => _showNetworkTierPicker(context, settings),
                child: MfpBadge(
                  label: settings.network == APINetwork.bitcoin
                      ? l10n.networkMainnet
                      : l10n.networkTestnet,
                  color: AppAccent.color,
                  letterSpacing: 0.0,
                ),
              ),
            ),
          ),
          IconButton(
            icon: Icon(_reorderMode ? Icons.check : Icons.swap_vert),
            tooltip: _reorderMode ? l10n.done : l10n.reorderProjects,
            onPressed: () => setState(() => _reorderMode = !_reorderMode),
          ),
          IconButton(
            icon: const Icon(Icons.add),
            tooltip: l10n.menuNew,
            onPressed: () => _showCreateSheet(context),
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
                      style: TextStyle(color: Theme.of(context).colorScheme.onSurface.withAlpha(AppAlpha.mediumHigh)),
                    ),
                  ],
                ),
              ),
            ProjectListError(:final message) =>
              Center(child: Text(message)),
            ProjectListLoaded(:final projects) => _buildLoadedBody(
                context, projects, settings),
            };
          },
        ),
      ),
    );
  }

  Widget _buildLoadedBody(BuildContext context,
      List<Project> allProjects, AppSettings settings) {
    final l10n = context.l10n;
    final currentIsMainnet = settings.network == APINetwork.bitcoin;
    final visibleProjects = _applyOrder(
      allProjects
          .where((p) => (p.network == APINetwork.bitcoin.name) == currentIsMainnet)
          .toList(),
      currentIsMainnet,
    );
    final hiddenCount = allProjects.length - visibleProjects.length;

    if (visibleProjects.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              l10n.noProjects,
              textAlign: TextAlign.center,
              style: TextStyle(
                  color: Theme.of(context)
                      .colorScheme
                      .onSurface
                      .withAlpha(AppAlpha.secondary)),
            ),
            if (hiddenCount > 0) ...[
              const SizedBox(height: 8),
              Text(
                l10n.walletsHiddenOnOtherNetworks(hiddenCount),
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 12,
                  color: Theme.of(context)
                      .colorScheme
                      .onSurface
                      .withAlpha(AppAlpha.secondary),
                ),
              ),
            ],
            const SizedBox(height: 24),
            FilledButton.icon(
              onPressed: () => _showCreateSheet(context),
              icon: const Icon(Icons.add),
              label: Text(l10n.menuNew),
            ),
          ],
        ),
      );
    }

    final hiddenBanner = hiddenCount > 0
        ? Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
            child: Row(
              children: [
                Icon(
                  Icons.info_outline,
                  size: 14,
                  color: Theme.of(context)
                      .colorScheme
                      .onSurface
                      .withAlpha(AppAlpha.secondary),
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    l10n.walletsHiddenOnOtherNetworks(hiddenCount),
                    style: TextStyle(
                      fontSize: 12,
                      color: Theme.of(context)
                          .colorScheme
                          .onSurface
                          .withAlpha(AppAlpha.secondary),
                    ),
                  ),
                ),
              ],
            ),
          )
        : null;

    final list = _reorderMode
        ? ReorderableListView.builder(
            padding: const EdgeInsets.all(16),
            buildDefaultDragHandles: false,
            itemCount: visibleProjects.length,
            onReorder: (oldIndex, newIndex) =>
                _onReorder(currentIsMainnet, visibleProjects, oldIndex, newIndex),
            itemBuilder: (context, index) => KeyedSubtree(
              key: ValueKey(visibleProjects[index].id),
              child: _buildProjectCard(context, visibleProjects[index], index),
            ),
          )
        : ListView.builder(
            padding: const EdgeInsets.all(16),
            itemCount: visibleProjects.length,
            itemBuilder: (context, index) => KeyedSubtree(
              key: ValueKey(visibleProjects[index].id),
              child: _buildProjectCard(context, visibleProjects[index], index),
            ),
          );

    if (hiddenBanner == null) {
      return list;
    }

    return Column(
      children: [
        hiddenBanner,
        Expanded(child: list),
      ],
    );
  }

  Widget _buildProjectCard(BuildContext context, Project project, int index) {
    final l10n = context.l10n;
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: ListTile(
        leading: _reorderMode
            ? ReorderableDragStartListener(
                index: index,
                child: Icon(
                  Icons.drag_handle,
                  color: Theme.of(context)
                      .colorScheme
                      .onSurface
                      .withAlpha(AppAlpha.secondary),
                ),
              )
            : null,
        title: Text(
          project.name,
          style: const TextStyle(fontWeight: FontWeight.w600),
        ),
        subtitle: Padding(
          padding: const EdgeInsets.only(top: 4),
          child: MfpBadge(
            label: localizedWalletTypeName(
              context,
              APIWalletType.values.byName(project.walletType),
            ),
            color: AppAccent.color,
            letterSpacing: 0.0,
          ),
        ),
        trailing: _reorderMode
            ? null
            : Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    _formatDate(project.updatedAt),
                    style: TextStyle(fontSize: 12, color: Theme.of(context).colorScheme.onSurface.withAlpha(AppAlpha.muted)),
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
                              onNavigate: widget.onNavigate,
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
                              color: Colors.red.withAlpha(AppAlpha.deleteAction),
                            ),
                            const SizedBox(width: 12),
                            Text(
                              l10n.delete,
                              style: TextStyle(color: Colors.red.withAlpha(AppAlpha.deleteAction)),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ],
              ),
        onTap: _reorderMode
            ? null
            : () => Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => ProjectDetailScreen(
                      db: context.read<AppDatabase>(),
                      projectId: project.id,
                      onNavigate: widget.onNavigate,
                    ),
                  ),
                ),
      ),
    );
  }

  String _formatDate(DateTime dt) {
    return '${dt.day}/${dt.month}/${dt.year}';
  }

  Future<void> _showCreateSheet(BuildContext context) async {
    final choice = await showSheet<_ProjectCreateMode>(context, (ctx) => Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 8),
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: Theme.of(ctx).colorScheme.onSurfaceVariant.withAlpha(80),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 8),
            ListTile(
              leading: const Icon(Icons.add_circle_outline),
              title: Text(ctx.l10n.projectCreateFromScratch),
              subtitle: Text(ctx.l10n.projectCreateFromScratchSub),
              onTap: () => Navigator.pop(ctx, _ProjectCreateMode.fromScratch),
            ),
            ListTile(
              leading: const Icon(Icons.code_outlined),
              title: Text(ctx.l10n.walletCreateFromDescriptor),
              subtitle: Text(ctx.l10n.projectCreateFromDescriptorSub),
              onTap: () => Navigator.pop(ctx, _ProjectCreateMode.fromDescriptor),
            ),
            ListTile(
              leading: const Icon(Icons.file_download_outlined),
              title: Text(ctx.l10n.projectCreateImport),
              subtitle: Text(ctx.l10n.projectCreateImportSub),
              onTap: () => Navigator.pop(ctx, _ProjectCreateMode.importProject),
            ),
            const SizedBox(height: 8),
          ],
        ));

    if (choice == null || !context.mounted) return;

    switch (choice) {
      case _ProjectCreateMode.fromScratch:
      case _ProjectCreateMode.fromDescriptor:
        final mode = choice == _ProjectCreateMode.fromScratch
            ? CreateMode.fromScratch
            : CreateMode.importDescriptor;
        final projectId = await Navigator.push<int>(
          context,
          MaterialPageRoute(
            fullscreenDialog: true,
            builder: (_) => CreateProjectDialog(
              cubit: context.read<ProjectListCubit>(),
              mode: mode,
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
                onNavigate: widget.onNavigate,
              ),
            ),
          );
        }
      case _ProjectCreateMode.importProject:
        await _showImportDialog(context);
    }
  }

  Future<void> _createWalletFromProject(
          BuildContext context, Project project) =>
      createWalletFromProject(context, project, onNavigate: widget.onNavigate);

  void _confirmDelete(BuildContext context, Project project) {
    final l10n = context.l10n;
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        titlePadding: kDialogTitlePadding,
        title: dialogCloseTitle(l10n.deleteProjectTitle, onClose: () => Navigator.pop(ctx), tooltip: l10n.cancel),
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
        showErrorToast(context.l10n.exportFailed(formatRustError(e)));
      }
    }
  }

  Future<void> _showImportDialog(BuildContext context) async {
    final jsonString = await showTextImportSheet(context, bigText: true);
    if (jsonString == null || jsonString.isEmpty || !context.mounted) return;
    await _importProject(context, jsonString);
  }

  Future<void> _importProject(BuildContext context, String jsonString) async {
    try {
      final cubit = context.read<ProjectListCubit>();
      final db = context.read<AppDatabase>();
      final projectId = await cubit.importProject(jsonString);

      if (context.mounted) {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => ProjectDetailScreen(
              db: db,
              projectId: projectId,
              onNavigate: widget.onNavigate,
            ),
          ),
        );
      }
    } catch (e) {
      if (context.mounted) {
        showErrorToast(context.l10n.importFailed(formatRustError(e)));
      }
    }
  }
}
