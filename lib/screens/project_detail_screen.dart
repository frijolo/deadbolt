import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import 'package:deadbolt/cubit/project_detail_cubit.dart';
import 'package:deadbolt/data/database.dart';
import 'package:deadbolt/errors.dart';
import 'package:deadbolt/src/rust/api/analyzer.dart';
import 'package:deadbolt/src/rust/api/model.dart';
import 'package:deadbolt/utils/enum_formatters.dart';
import 'package:deadbolt/utils/toast_helper.dart';
import 'package:deadbolt/widgets/editable_key_card.dart';
import 'package:deadbolt/widgets/editable_path_card.dart';
import 'package:deadbolt/widgets/key_card.dart';
import 'package:deadbolt/widgets/path_card.dart';

class ProjectDetailScreen extends StatelessWidget {
  final AppDatabase db;
  final int projectId;

  const ProjectDetailScreen({
    super.key,
    required this.db,
    required this.projectId,
  });

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (_) => ProjectDetailCubit(db, projectId),
      child: const _ProjectDetailView(),
    );
  }
}

class _ProjectDetailView extends StatelessWidget {
  const _ProjectDetailView();

  @override
  Widget build(BuildContext context) {
    return BlocListener<ProjectDetailCubit, ProjectDetailState>(
      listener: (context, state) {
        if (state is! ProjectDetailLoaded) return;

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
            ProjectDetailLoading() => Scaffold(
                appBar: AppBar(),
                body: const Center(child: CircularProgressIndicator()),
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
              tooltip: 'Discard changes',
              onPressed: () => _confirmDiscardEdits(context, cubit, state),
            )
          else
            PopupMenuButton<String>(
              icon: const Icon(Icons.more_vert),
              tooltip: 'More options',
              offset: const Offset(0, 40),
              onSelected: (value) async {
                if (value == 'edit') {
                  cubit.enterEditMode();
                } else if (value == 'export') {
                  await cubit.exportProject();
                }
              },
              itemBuilder: (context) => [
                const PopupMenuItem(
                  value: 'edit',
                  child: Row(
                    children: [
                      Icon(Icons.edit_outlined, size: 20),
                      SizedBox(width: 12),
                      Text('Edit'),
                    ],
                  ),
                ),
                const PopupMenuItem(
                  value: 'export',
                  child: Row(
                    children: [
                      Icon(Icons.file_upload_outlined, size: 20),
                      SizedBox(width: 12),
                      Text('Export'),
                    ],
                  ),
                ),
              ],
            ),
        ],
      ),
      floatingActionButton: state.isDirty
          ? FloatingActionButton.extended(
              onPressed: cubit.regenerateDescriptor,
              icon: const Icon(Icons.build_outlined),
              label: const Text('Build'),
              backgroundColor: Colors.orange,
            )
          : null,
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            // Info header with badges (wallet type badge is clickeable in edit mode)
            _buildInfoHeader(context, cubit, state, isEditing: isEditing),
            const SizedBox(height: 8),
            // Descriptor (expandable) - only in read mode, would be obsolete in edit mode
            if (!isEditing) ...[
              _buildDescriptorSection(context, project.descriptor),
              const SizedBox(height: 8),
            ],
            // Keys section
            _buildKeysSection(context, cubit, state),
          const SizedBox(height: 8),
          // Spend paths section
          _buildSpendPathsSection(context, cubit, state),
          ],
        ),
      ),
    );
  }

  Widget _buildKeysSection(
    BuildContext context,
    ProjectDetailCubit cubit,
    ProjectDetailLoaded state,
  ) {
    final isEditing = state.isEditing;
    final displayKeys = isEditing ? state.editedKeys! : state.keys;

    if (!isEditing && displayKeys.isEmpty) {
      return const SizedBox.shrink();
    }

    return ExpansionTile(
        key: const ValueKey('keys_expansion_tile'),
        title: Text(
          'Keys (${displayKeys.length})',
          style: Theme.of(context).textTheme.titleMedium?.copyWith(
                color: isEditing ? Colors.orange : null,
              ),
        ),
        tilePadding: EdgeInsets.zero,
        initiallyExpanded: state.keysExpanded,
        onExpansionChanged: (expanded) => cubit.toggleKeysExpanded(expanded),
        children: [
          if (isEditing) ...[
            // Editable mode: show EditableKeyCard with delete buttons
            for (final key in state.editedKeys!)
              _buildEditableKey(context, cubit, state, key),
            // Add key button
          Padding(
            padding: const EdgeInsets.only(top: 4, bottom: 8),
            child: OutlinedButton.icon(
              onPressed: () => _showAddKeyDialog(context, cubit),
              icon: const Icon(Icons.add, size: 18),
              label: const Text('Add key'),
              style: OutlinedButton.styleFrom(
                foregroundColor: Colors.orange,
                side: BorderSide(color: Colors.orange.withAlpha(100)),
              ),
            ),
          ),
        ] else ...[
          // Read-only mode: show KeyCard
          for (final key in state.keys)
            KeyCard(
              keyData: key,
              allKeys: state.keys,
              mfpColor: cubit.getMfpColor(key.mfp),
              onNameEdit: (name) => cubit.updateKeyName(key.id, name),
            ),
        ],
      ],
    );
  }

  Widget _buildEditableKey(
    BuildContext context,
    ProjectDetailCubit cubit,
    ProjectDetailLoaded state,
    EditableKey key,
  ) {
    final isInUse = state.editedPaths!.any((path) => path.mfps.contains(key.mfp));

    return EditableKeyCard(
      keyData: key,
      allKeys: state.editedKeys!,
      mfpColor: cubit.getMfpColor(key.mfp),
      onNameEdit: (name) => cubit.updateKeyCustomName(key.mfp, name),
      onDelete: () => cubit.removeKey(key.mfp),
      canDelete: !isInUse,
    );
  }

  void _showAddKeyDialog(BuildContext context, ProjectDetailCubit cubit) {
    final mfpController = TextEditingController();
    final pathController = TextEditingController();
    final xpubController = TextEditingController();
    final keyspecController = TextEditingController();
    String? errorText;
    bool useSeparateFields = false;

    // Get current state to access existing keys
    final currentState = cubit.state as ProjectDetailLoaded;
    final existingMfps = currentState.editedKeys!.map((k) => k.mfp.toLowerCase()).toSet();

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          title: const Text('Add Key'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Mode toggle
                SegmentedButton<bool>(
                  segments: const [
                    ButtonSegment(
                      value: true,
                      label: Text('Separate fields'),
                      icon: Icon(Icons.splitscreen, size: 16),
                    ),
                    ButtonSegment(
                      value: false,
                      label: Text('Full keyspec'),
                      icon: Icon(Icons.code, size: 16),
                    ),
                  ],
                  selected: {useSeparateFields},
                  onSelectionChanged: (Set<bool> newSelection) {
                    setDialogState(() {
                      useSeparateFields = newSelection.first;
                      errorText = null;
                    });
                  },
                  style: ButtonStyle(
                    visualDensity: VisualDensity.compact,
                  ),
                ),
                const SizedBox(height: 16),

                // Conditional content based on mode
                if (useSeparateFields) ...[
                  TextField(
                    controller: mfpController,
                    decoration: const InputDecoration(
                      labelText: 'Master Fingerprint (MFP)',
                      hintText: 'e.g., c449c5c5',
                    ),
                    textCapitalization: TextCapitalization.none,
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: pathController,
                    decoration: const InputDecoration(
                      labelText: 'Derivation Path',
                      hintText: 'e.g., 48h/0h/0h/2h',
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: xpubController,
                    decoration: const InputDecoration(
                      labelText: 'Extended Public Key (xpub)',
                      hintText: 'xpub6...',
                    ),
                    maxLines: 2,
                  ),
                ] else ...[
                  TextField(
                    controller: keyspecController,
                    decoration: const InputDecoration(
                      labelText: 'Full Keyspec',
                      hintText: '[c449c5c5/48h/0h/0h/2h]xpub6...',
                      helperText: 'Format: [mfp/path]xpub',
                      helperMaxLines: 2,
                    ),
                    maxLines: 3,
                    textCapitalization: TextCapitalization.none,
                  ),
                ],

                if (errorText != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Text(
                      errorText!,
                      style: const TextStyle(color: Colors.red, fontSize: 12),
                    ),
                  ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: () async {
                String mfp;
                String path;
                String xpub;

                if (useSeparateFields) {
                  // Separate fields mode
                  mfp = mfpController.text.trim().toLowerCase();
                  path = pathController.text.trim();
                  xpub = xpubController.text.trim();

                  if (mfp.isEmpty || path.isEmpty || xpub.isEmpty) {
                    setDialogState(() => errorText = 'All fields are required');
                    return;
                  }
                } else {
                  // Keyspec mode - parse the full keyspec
                  final keyspec = keyspecController.text.trim();

                  if (keyspec.isEmpty) {
                    setDialogState(() => errorText = 'Keyspec is required');
                    return;
                  }

                  // Parse keyspec format: [mfp/path]xpub
                  final match = RegExp(r'^\[([0-9a-fA-F]{8})/([^\]]+)\](.+)$')
                      .firstMatch(keyspec);

                  if (match == null) {
                    setDialogState(() =>
                      errorText = 'Invalid keyspec format. Expected: [mfp/path]xpub');
                    return;
                  }

                  mfp = match.group(1)!.toLowerCase();
                  path = match.group(2)!;
                  xpub = match.group(3)!;
                }

                // Check for duplicate MFP
                if (existingMfps.contains(mfp)) {
                  setDialogState(() => errorText = 'A key with MFP $mfp already exists');
                  return;
                }

                // Validate key with Rust (format + network compatibility)
                final network = APINetwork.values.byName(currentState.project.network);
                try {
                  await validateKey(
                    mfp: mfp,
                    derivationPath: path,
                    xpub: xpub,
                    network: network,
                  );
                } catch (e) {
                  setDialogState(() => errorText = formatRustError(e));
                  return;
                }

                // Check if widget is still mounted before using context
                if (!ctx.mounted) return;

                final newKey = EditableKey(
                  mfp: mfp,
                  derivationPath: path,
                  xpub: xpub,
                );

                cubit.addKey(newKey);
                Navigator.pop(ctx);
              },
              child: const Text('Add'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSpendPathsSection(
    BuildContext context,
    ProjectDetailCubit cubit,
    ProjectDetailLoaded state,
  ) {
    final isEditing = state.isEditing;
    final editedPaths = state.editedPaths;
    final editedKeys = state.editedKeys;

    final pathCount = isEditing ? editedPaths!.length : state.spendPaths.length;

    return ExpansionTile(
      key: const ValueKey('spend_paths_expansion_tile'),
      title: Text(
        'Spend paths ($pathCount)',
        style: Theme.of(context).textTheme.titleMedium?.copyWith(
              color: isEditing ? Colors.orange : null,
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
              mfpColorProvider: cubit.getMfpColor,
              onThresholdChanged: (v) => cubit.updatePathThreshold(i, v),
              onMfpAdded: (mfp) => cubit.addMfpToPath(i, mfp),
              onMfpRemoved: (mfp) => cubit.removeMfpFromPath(i, mfp),
              onRelTimelockChanged: (v) => cubit.updatePathRelTimelock(i, v),
              onAbsTimelockChanged: (v) => cubit.updatePathAbsTimelock(i, v),
              onDelete: () => cubit.removeSpendPath(i),
              isTaproot: (state.editedWalletType ??
                         APIWalletType.values.byName(state.project.walletType)) ==
                         APIWalletType.p2Tr,
              onKeyPathChanged: (v) => cubit.updatePathIsKeyPath(i, v),
              onNameEdit: (name) => cubit.updatePathCustomName(i, name),
            ),
          Padding(
            padding: const EdgeInsets.only(top: 4, bottom: 8),
            child: OutlinedButton.icon(
              onPressed: cubit.addSpendPath,
              icon: const Icon(Icons.add, size: 18),
              label: const Text('Add spend path'),
              style: OutlinedButton.styleFrom(
                foregroundColor: Colors.orange,
                side: BorderSide(color: Colors.orange.withAlpha(100)),
              ),
            ),
          ),
        ] else ...[
          for (final sp in state.spendPaths)
            PathCard(
              path: sp,
              keys: state.keys,
              mfpColorProvider: cubit.getMfpColor,
              onNameEdit: (name) => cubit.updateSpendPathName(sp.id, name),
              isTaproot: state.project.walletType.toUpperCase() == 'P2TR',
            ),
        ],
      ],
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
        _buildBadge(networkDisplayName(state.project.network)),
        const SizedBox(width: 8),
        if (isEditing)
          _buildEditableWalletTypeBadge(context, cubit, state, currentType)
        else
          _buildBadge(currentType.displayName),
      ],
    );
  }

  Widget _buildEditableWalletTypeBadge(
    BuildContext context,
    ProjectDetailCubit cubit,
    ProjectDetailLoaded state,
    APIWalletType currentType,
  ) {
    final compatibleTypes = cubit.getCompatibleWalletTypes();

    return PopupMenuButton<APIWalletType>(
      initialValue: currentType,
      onSelected: (newType) => cubit.updateWalletType(newType),
      offset: const Offset(0, 32),
      tooltip: 'Change wallet type',
      itemBuilder: (context) => compatibleTypes.map((type) {
        return PopupMenuItem<APIWalletType>(
          value: type,
          child: Text(
            type.displayName,
            style: const TextStyle(fontSize: 14),
          ),
        );
      }).toList(),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: Colors.orange.withAlpha(32),
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: Colors.orange.withAlpha(64)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              currentType.displayName,
              style: const TextStyle(fontSize: 12, color: Colors.white70),
            ),
            const SizedBox(width: 4),
            const Icon(
              Icons.edit,
              size: 12,
              color: Colors.orange,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBadge(String label) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: Colors.orange.withAlpha(32),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: Colors.orange.withAlpha(64)),
      ),
      child: Text(
        label,
        style: const TextStyle(fontSize: 12, color: Colors.white70),
      ),
    );
  }

  Widget _buildDescriptorSection(BuildContext context, String descriptor) {
    return ExpansionTile(
      title: Text(
        'Descriptor',
        style: Theme.of(context).textTheme.titleMedium,
      ),
      tilePadding: EdgeInsets.zero,
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton(
            icon: const Icon(Icons.copy, size: 18),
            tooltip: 'Copy descriptor',
            onPressed: () {
              Clipboard.setData(ClipboardData(text: descriptor));
              showSuccessToast(context, 'Descriptor copied');
            },
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
            style: const TextStyle(
              fontFamily: 'monospace',
              fontSize: 12,
              color: Colors.white60,
            ),
          ),
        ),
      ],
    );
  }

  void _editProjectName(
      BuildContext context, ProjectDetailCubit cubit, String currentName) {
    final controller = TextEditingController(text: currentName);
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Project name'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(hintText: 'Project name'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () {
              final name = controller.text.trim();
              if (name.isNotEmpty) {
                cubit.updateProjectName(name);
              }
              Navigator.pop(ctx);
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );
  }

  void _confirmDiscardEdits(
      BuildContext context, ProjectDetailCubit cubit, ProjectDetailLoaded state) {
    // Check if there are unsaved changes
    final hasChanges = state.isDirty;

    // If no changes, just discard
    if (!hasChanges) {
      cubit.discardEdits();
      return;
    }

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Discard changes?'),
        content: const Text(
          'You have unsaved changes. This action cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(ctx);
              cubit.discardEdits();
            },
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Discard'),
          ),
        ],
      ),
    );
  }

}
