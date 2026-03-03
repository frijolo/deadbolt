import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:deadbolt/cubit/project_detail_cubit.dart';
import 'package:deadbolt/theme/app_theme.dart';
import 'package:deadbolt/data/database.dart';
import 'package:deadbolt/l10n/l10n.dart';
import 'package:deadbolt/src/rust/api/model.dart';
import 'package:deadbolt/utils/enum_formatters.dart';
import 'package:deadbolt/utils/export_sheet.dart';
import 'package:deadbolt/utils/toast_helper.dart';
import 'package:deadbolt/widgets/add_key_dialog.dart';
import 'package:deadbolt/widgets/editable_key_card.dart';
import 'package:deadbolt/widgets/editable_path_card.dart';
import 'package:deadbolt/widgets/key_card.dart';
import 'package:deadbolt/widgets/path_card.dart';
import 'package:deadbolt/widgets/text_export_sheet.dart';

// ---------------------------------------------------------------------------
// Helper: resolve a color for an MFP using the cubit index + theme palette.
// ---------------------------------------------------------------------------

Color _colorForMfp(BuildContext context, ProjectDetailCubit cubit, String mfp) {
  final ext = Theme.of(context).extension<KeyColorExtension>()!;
  final idx = cubit.getMfpColorIndex(mfp);
  return ext.keyColors[idx % ext.keyColors.length];
}

// ---------------------------------------------------------------------------
// Screen entry point
// ---------------------------------------------------------------------------

class ProjectDetailScreen extends StatelessWidget {
  final AppDatabase db;
  final int projectId;
  final String? initialAction;

  const ProjectDetailScreen({
    super.key,
    required this.db,
    required this.projectId,
    this.initialAction,
  });

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (_) => ProjectDetailCubit(db, projectId),
      child: _ProjectDetailView(initialAction: initialAction),
    );
  }
}

class _ProjectDetailView extends StatefulWidget {
  final String? initialAction;

  const _ProjectDetailView({this.initialAction});

  @override
  State<_ProjectDetailView> createState() => _ProjectDetailViewState();
}

class _ProjectDetailViewState extends State<_ProjectDetailView> {
  bool _initialActionTriggered = false;

  @override
  Widget build(BuildContext context) {
    return BlocListener<ProjectDetailCubit, ProjectDetailState>(
      listener: (context, state) {
        if (state is! ProjectDetailLoaded) return;

        // Enter edit mode automatically when requested (e.g. from project list)
        if (!_initialActionTriggered && widget.initialAction == 'edit') {
          _initialActionTriggered = true;
          final cubit = context.read<ProjectDetailCubit>();
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (!mounted) return;
            cubit.enterEditMode();
          });
        }

        // Show error toast
        if (state.errorMessage != null) {
          showErrorToast(context, state.errorMessage!);
          context.read<ProjectDetailCubit>().clearError();
        }

        // Show success toast
        if (state.successMessage != null) {
          showSuccessToast(context, state.successMessage!);
          context.read<ProjectDetailCubit>().clearSuccess();
        }
      },
      child: BlocBuilder<ProjectDetailCubit, ProjectDetailState>(
        builder: (context, state) {
          return switch (state) {
            ProjectDetailLoading(:final message) => Scaffold(
                appBar: AppBar(),
                body: Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const CircularProgressIndicator(),
                      if (message != null) ...[
                        const SizedBox(height: 24),
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 32),
                          child: Text(
                            message,
                            textAlign: TextAlign.center,
                            style: Theme.of(context).textTheme.bodyLarge,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ProjectDetailError(:final message) => Scaffold(
                appBar: AppBar(),
                body: Center(child: Text(message)),
              ),
            ProjectDetailLoaded() => _buildLoaded(context, state),
          };
        },
      ),
    );
  }

  Widget _buildLoaded(BuildContext context, ProjectDetailLoaded state) {
    final l10n = context.l10n;
    final cubit = context.read<ProjectDetailCubit>();
    final project = state.project;
    final isEditing = state.isEditing;

    return Scaffold(
      appBar: AppBar(
        title: GestureDetector(
          onTap: () => _editProjectName(context, cubit, project.name),
          child: Text(project.name),
        ),
        actions: [
          if (isEditing)
            IconButton(
              icon: const Icon(Icons.close),
              tooltip: l10n.discardChangesTooltip,
              onPressed: () => _confirmDiscardEdits(context, cubit, state),
            )
          else
            PopupMenuButton<String>(
              icon: const Icon(Icons.more_vert),
              tooltip: l10n.moreOptionsTooltip,
              offset: const Offset(0, 40),
              onSelected: (value) async {
                if (value == 'edit') {
                  cubit.enterEditMode();
                } else if (value == 'export') {
                  if (context.mounted) {
                    _showExportProjectSheet(context, cubit);
                  }
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
              ],
            ),
        ],
      ),
      floatingActionButton: state.isDirty
          ? FloatingActionButton.extended(
              onPressed: () => cubit.regenerateDescriptor(
                buildingDescriptorMessage: l10n.buildingDescriptor,
                buildingDescriptorMultiPathMessage: l10n.buildingDescriptorMultiPath,
                buildingComplexDescriptorMessage: l10n.buildingComplexDescriptor,
                analyzingDescriptorMessage: l10n.analyzingDescriptorLoading,
                analyzingComplexDescriptorMessage: l10n.analyzingComplexDescriptor,
                analyzingAndSavingMessage: l10n.analyzingAndSaving,
              ),
              icon: const Icon(Icons.build_outlined),
              label: Text(l10n.buildFabLabel),
              backgroundColor: AppAccent.color,
            )
          : null,
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            // Info header with badges (wallet type badge is clickable in edit mode)
            _buildInfoHeader(context, cubit, state, isEditing: isEditing),
            const SizedBox(height: 8),
            // Descriptor (expandable) — only in read mode
            if (!isEditing) ...[
              _buildDescriptorSection(context, project.descriptor),
              const SizedBox(height: 8),
            ],
            // Keys section
            _KeysSection(state: state, cubit: cubit),
            const SizedBox(height: 8),
            // Spend paths section
            _SpendPathsSection(state: state, cubit: cubit),
          ],
        ),
      ),
    );
  }

  Widget _buildInfoHeader(
    BuildContext context,
    ProjectDetailCubit cubit,
    ProjectDetailLoaded state, {
    required bool isEditing,
  }) {
    final currentType = isEditing
        ? (state.editedWalletType ??
            APIWalletType.values.byName(state.project.walletType))
        : APIWalletType.values.byName(state.project.walletType);

    return Row(
      children: [
        _buildBadge(context, localizedNetworkDisplayName(context, state.project.network)),
        const SizedBox(width: 8),
        if (isEditing)
          _buildEditableWalletTypeBadge(context, cubit, state, currentType)
        else
          _buildBadge(context, localizedWalletTypeName(context, currentType)),
      ],
    );
  }

  Widget _buildEditableWalletTypeBadge(
    BuildContext context,
    ProjectDetailCubit cubit,
    ProjectDetailLoaded state,
    APIWalletType currentType,
  ) {
    final l10n = context.l10n;
    final compatibleTypes = cubit.getCompatibleWalletTypes();

    return PopupMenuButton<APIWalletType>(
      initialValue: currentType,
      onSelected: (newType) => cubit.updateWalletType(newType),
      offset: const Offset(0, 32),
      tooltip: l10n.changeWalletTypeTooltip,
      itemBuilder: (context) => compatibleTypes.map((type) {
        return PopupMenuItem<APIWalletType>(
          value: type,
          child: Text(
            localizedWalletTypeName(context, type),
            style: const TextStyle(fontSize: 14),
          ),
        );
      }).toList(),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: AppAccent.color.withAlpha(32),
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: AppAccent.color.withAlpha(64)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              localizedWalletTypeName(context, currentType),
              style: TextStyle(
                fontSize: 12,
                color: Theme.of(context).colorScheme.onSurface.withAlpha(178),
              ),
            ),
            const SizedBox(width: 4),
            const Icon(
              Icons.edit,
              size: 12,
              color: AppAccent.color,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBadge(BuildContext context, String label) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: AppAccent.color.withAlpha(32),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: AppAccent.color.withAlpha(64)),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 12,
          color: Theme.of(context).colorScheme.onSurface.withAlpha(178),
        ),
      ),
    );
  }

  Widget _buildDescriptorSection(BuildContext context, String descriptor) {
    final l10n = context.l10n;
    return ExpansionTile(
      title: Text(
        l10n.descriptorSectionTitle,
        style: Theme.of(context).textTheme.titleMedium,
      ),
      tilePadding: EdgeInsets.zero,
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton(
            icon: const Icon(Icons.ios_share, size: 18),
            tooltip: l10n.copyDescriptorTooltip,
            onPressed: () => showTextExportSheet(
              context,
              text: descriptor,
              fileName: 'descriptor',
              copiedMessage: l10n.descriptorCopied,
            ),
            visualDensity: VisualDensity.compact,
          ),
          const SizedBox(width: 8),
          // Chevron icon placeholder to maintain alignment
          const Icon(Icons.expand_more),
        ],
      ),
      children: [
        Padding(
          padding: const EdgeInsets.only(top: 8),
          child: SelectableText(
            descriptor,
            style: TextStyle(
              fontFamily: 'monospace',
              fontSize: 12,
              color: Theme.of(context).colorScheme.onSurface.withAlpha(153),
            ),
          ),
        ),
      ],
    );
  }

  void _editProjectName(
      BuildContext context, ProjectDetailCubit cubit, String currentName) {
    final l10n = context.l10n;
    final controller = TextEditingController(text: currentName);
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l10n.projectNameDialogTitle),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: InputDecoration(hintText: l10n.projectNameDialogTitle),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(l10n.cancel),
          ),
          TextButton(
            onPressed: () {
              final name = controller.text.trim();
              if (name.isNotEmpty) {
                cubit.updateProjectName(name);
              }
              Navigator.pop(ctx);
            },
            child: Text(l10n.save),
          ),
        ],
      ),
    );
  }

  void _confirmDiscardEdits(
      BuildContext context, ProjectDetailCubit cubit, ProjectDetailLoaded state) {
    if (!state.isDirty) {
      cubit.discardEdits();
      return;
    }

    final l10n = context.l10n;
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l10n.discardChangesDialogTitle),
        content: Text(l10n.discardChangesContent),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(l10n.cancel),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(ctx);
              cubit.discardEdits();
            },
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: Text(l10n.discard),
          ),
        ],
      ),
    );
  }

  void _showExportProjectSheet(BuildContext context, ProjectDetailCubit cubit) {
    final payload = cubit.buildExportPayload();
    if (payload == null) return;
    final state = cubit.state;
    final projectName =
        state is ProjectDetailLoaded ? state.project.name : '';
    showProjectExportSheet(
      context,
      jsonString: payload.jsonString,
      fileName: payload.fileName,
      projectName: projectName,
    );
  }
}

// ---------------------------------------------------------------------------
// Private sub-widgets
// ---------------------------------------------------------------------------

class _KeysSection extends StatelessWidget {
  final ProjectDetailLoaded state;
  final ProjectDetailCubit cubit;

  const _KeysSection({required this.state, required this.cubit});

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final isEditing = state.isEditing;
    final displayKeys = isEditing ? state.editedKeys! : state.keys;

    if (!isEditing && displayKeys.isEmpty) {
      return const SizedBox.shrink();
    }

    return ExpansionTile(
      key: const ValueKey('keys_expansion_tile'),
      title: Text(
        l10n.keysSection(displayKeys.length),
        style: Theme.of(context).textTheme.titleMedium?.copyWith(
              color: isEditing ? AppAccent.color : null,
            ),
      ),
      tilePadding: EdgeInsets.zero,
      initiallyExpanded: state.keysExpanded,
      onExpansionChanged: (expanded) => cubit.toggleKeysExpanded(expanded),
      children: [
        if (isEditing) ...[
          for (final key in state.editedKeys!)
            _buildEditableKey(context, key),
          Padding(
            padding: const EdgeInsets.only(top: 4, bottom: 8),
            child: OutlinedButton.icon(
              onPressed: () => showAddKeyDialog(context, cubit),
              icon: const Icon(Icons.add, size: 18),
              label: Text(l10n.addKeyButton),
              style: OutlinedButton.styleFrom(
                foregroundColor: AppAccent.color,
                side: BorderSide(color: AppAccent.color.withAlpha(100)),
              ),
            ),
          ),
        ] else ...[
          for (final key in state.keys)
            KeyCard(
              keyData: key,
              allKeys: state.keys,
              mfpColor: _colorForMfp(context, cubit, key.mfp),
              onNameEdit: (name) => cubit.updateKeyName(key.id, name),
            ),
        ],
      ],
    );
  }

  Widget _buildEditableKey(BuildContext context, EditableKey key) {
    final isInUse = state.editedPaths!.any((path) => path.mfps.contains(key.mfp));
    return EditableKeyCard(
      keyData: key,
      allKeys: state.editedKeys!,
      mfpColor: _colorForMfp(context, cubit, key.mfp),
      onNameEdit: (name) => cubit.updateKeyCustomName(key.mfp, name),
      onDelete: () => cubit.removeKey(key.mfp),
      canDelete: !isInUse,
    );
  }
}

class _SpendPathsSection extends StatelessWidget {
  final ProjectDetailLoaded state;
  final ProjectDetailCubit cubit;

  const _SpendPathsSection({required this.state, required this.cubit});

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final isEditing = state.isEditing;
    final editedPaths = state.editedPaths;
    final editedKeys = state.editedKeys;

    final pathCount = isEditing ? editedPaths!.length : state.spendPaths.length;

    return ExpansionTile(
      key: const ValueKey('spend_paths_expansion_tile'),
      title: Text(
        l10n.spendPathsSection(pathCount),
        style: Theme.of(context).textTheme.titleMedium?.copyWith(
              color: isEditing ? AppAccent.color : null,
            ),
      ),
      tilePadding: EdgeInsets.zero,
      initiallyExpanded: state.spendPathsExpanded,
      onExpansionChanged: (expanded) => cubit.toggleSpendPathsExpanded(expanded),
      children: [
        if (isEditing && editedPaths != null && editedKeys != null) ...[
          for (var i = 0; i < editedPaths.length; i++)
            EditablePathCard(
              index: i,
              path: editedPaths[i],
              availableKeys: editedKeys
                  .map((k) => k.toProjectKey(state.project.id))
                  .toList(),
              mfpColorProvider: (mfp) => _colorForMfp(context, cubit, mfp),
              onThresholdChanged: (v) => cubit.updatePathThreshold(i, v),
              onMfpAdded: (mfp) => cubit.addMfpToPath(i, mfp),
              onMfpRemoved: (mfp) => cubit.removeMfpFromPath(i, mfp),
              onTimelockModeChanged: (m) => cubit.updatePathTimelockMode(i, m),
              onRelTimelockTypeChanged: (t) =>
                  cubit.updatePathRelTimelockType(i, t),
              onRelTimelockValueChanged: (v) =>
                  cubit.updatePathRelTimelockValue(i, v),
              onAbsTimelockTypeChanged: (t) =>
                  cubit.updatePathAbsTimelockType(i, t),
              onAbsTimelockValueChanged: (v) =>
                  cubit.updatePathAbsTimelockValue(i, v),
              onDelete: () => cubit.removeSpendPath(i),
              onAddNewKey: () => showAddKeyDialog(
                context,
                cubit,
                onKeyAdded: (mfp) => cubit.addMfpToPath(i, mfp),
              ),
              isTaproot: (state.editedWalletType ??
                         APIWalletType.values.byName(state.project.walletType)) ==
                         APIWalletType.p2Tr,
              onKeyPathChanged: (v) => cubit.updatePathIsKeyPath(i, v),
              onNameEdit: (name) => cubit.updatePathCustomName(i, name),
              onPriorityChanged: (p) => cubit.updatePathPriority(i, p),
            ),
          Padding(
            padding: const EdgeInsets.only(top: 4, bottom: 8),
            child: OutlinedButton.icon(
              onPressed: cubit.addSpendPath,
              icon: const Icon(Icons.add, size: 18),
              label: Text(l10n.addSpendPath),
              style: OutlinedButton.styleFrom(
                foregroundColor: AppAccent.color,
                side: BorderSide(color: AppAccent.color.withAlpha(100)),
              ),
            ),
          ),
        ] else ...[
          for (final sp in state.spendPaths)
            PathCard(
              path: sp,
              keys: state.keys,
              mfpColorProvider: (mfp) => _colorForMfp(context, cubit, mfp),
              onNameEdit: (name) => cubit.updateSpendPathName(sp.id, name),
              isTaproot: state.project.walletType.toUpperCase() == 'P2TR',
            ),
        ],
      ],
    );
  }
}
