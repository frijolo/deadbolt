import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:deadbolt/cubit/project_detail_cubit.dart';
import 'package:deadbolt/services/wallet_service.dart';
import 'package:deadbolt/theme/app_theme.dart';
import 'package:deadbolt/data/database.dart';
import 'package:deadbolt/l10n/l10n.dart';
import 'package:deadbolt/src/rust/api/model.dart';
import 'package:deadbolt/utils/enum_formatters.dart';
import 'package:deadbolt/utils/export_sheet.dart';
import 'package:deadbolt/utils/toast_helper.dart';
import 'package:deadbolt/screens/create_wallet_dialog.dart';
import 'package:deadbolt/widgets/add_key_dialog.dart';
import 'package:deadbolt/widgets/editable_path_card.dart';
import 'package:deadbolt/widgets/key_card.dart';
import 'package:deadbolt/widgets/descriptor_tab.dart';
import 'package:deadbolt/widgets/spend_path_edit_sheet.dart';
import 'package:deadbolt/widgets/popup_menu_helpers.dart';
import 'package:deadbolt/widgets/dialog_helpers.dart';

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
  final void Function(int)? onNavigate;

  const ProjectDetailScreen({
    super.key,
    required this.db,
    required this.projectId,
    this.onNavigate,
  });

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (ctx) => ProjectDetailCubit(
        db,
        projectId,
        walletService: ctx.read<WalletService>(),
      ),
      child: _ProjectDetailView(onNavigate: onNavigate),
    );
  }
}

class _ProjectDetailView extends StatelessWidget {
  final void Function(int)? onNavigate;

  const _ProjectDetailView({this.onNavigate});

  @override
  Widget build(BuildContext context) {
    return BlocListener<ProjectDetailCubit, ProjectDetailState>(
      listener: (context, state) {
        if (state is! ProjectDetailLoaded) return;

        handleTransientError(state.errorMessage,
            context.read<ProjectDetailCubit>().clearError);
        handleTransientSuccess(state.successMessage,
            context.read<ProjectDetailCubit>().clearSuccess);
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

    return PopScope(
      canPop: !state.isDirty,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _confirmDiscardEdits(context, cubit, state);
      },
      child: Scaffold(
      appBar: AppBar(
        title: GestureDetector(
          onTap: () => _editProjectName(context, cubit, project.name),
          child: Text(project.name),
        ),
        actions: [
          PopupMenuButton<String>(
            icon: const Icon(Icons.more_vert),
            tooltip: l10n.moreOptionsTooltip,
            offset: const Offset(0, 40),
            onSelected: (value) async {
              if (value == 'discard') {
                if (context.mounted) {
                  _confirmDiscardEdits(context, cubit, state);
                }
              } else if (value == 'export') {
                if (context.mounted) {
                  _showExportProjectSheet(context, cubit);
                }
              } else if (value == 'createWallet') {
                if (context.mounted) {
                  _createWalletFromProject(context, state.project);
                }
              }
            },
            itemBuilder: (context) => [
              if (state.isDirty)
                iconMenuItem(value: 'discard', icon: Icons.undo, label: l10n.discardChangesTooltip),
              iconMenuItem(value: 'export', icon: Icons.file_upload_outlined, label: l10n.export),
              iconMenuItem(value: 'createWallet', icon: Icons.account_balance_wallet_outlined, label: l10n.createWalletFromProject),
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
        child: DefaultTabController(
          length: 3,
          // For single-sig projects, start on the Keys tab so the user can
          // add their key first; the spend path is auto-populated afterward.
          initialIndex: walletPolicyFrom(state.currentWalletType) == WalletPolicy.singleSig ? 1 : 0,
          child: Column(
            children: [
              // Info header
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                child: _buildInfoHeader(context, cubit, state),
              ),
              // Tab bar — Spend Paths first, Descriptor last
              TabBar(
                tabs: [
                  Tab(text: l10n.spendPathsSection(state.displayPathCount)),
                  Tab(text: l10n.keysSection(state.displayKeyCount)),
                  Tab(text: l10n.descriptorLabel),
                ],
              ),
              // Tab content
              Expanded(
                child: TabBarView(
                  children: [
                    _SpendPathsSection(state: state, cubit: cubit),
                    _KeysSection(state: state, cubit: cubit),
                    DescriptorTab(
                      descriptor: project.descriptor,
                      isDirty: state.isDirty,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    ), // close Scaffold
    ); // close PopScope
  }

  Widget _buildInfoHeader(
    BuildContext context,
    ProjectDetailCubit cubit,
    ProjectDetailLoaded state,
  ) {
    final currentType = state.currentWalletType;

    return Row(
      children: [
        _buildBadge(context, localizedNetworkDisplayName(context, state.project.network)),
        const SizedBox(width: 8),
        _buildEditableWalletTypeBadge(context, cubit, state, currentType),
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
          color: AppAccent.color.withAlpha(AppAlpha.subtle),
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: AppAccent.color.withAlpha(AppAlpha.mediumLow)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              localizedWalletTypeName(context, currentType),
              style: TextStyle(
                fontSize: 12,
                color: Theme.of(context).colorScheme.onSurface.withAlpha(AppAlpha.mediumHigh),
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
        color: AppAccent.color.withAlpha(AppAlpha.subtle),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: AppAccent.color.withAlpha(AppAlpha.mediumLow)),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 12,
          color: Theme.of(context).colorScheme.onSurface.withAlpha(AppAlpha.mediumHigh),
        ),
      ),
    );
  }


  void _editProjectName(
      BuildContext context, ProjectDetailCubit cubit, String currentName) {
    final l10n = context.l10n;
    final controller = TextEditingController(text: currentName);
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        titlePadding: kDialogTitlePadding,
        title: dialogCloseTitle(l10n.projectNameDialogTitle, onClose: () => Navigator.pop(ctx), tooltip: l10n.cancel),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: InputDecoration(hintText: l10n.projectNameDialogTitle),
          onSubmitted: (_) {
            final name = controller.text.trim();
            if (name.isNotEmpty) cubit.updateProjectName(name);
            Navigator.pop(ctx);
          },
          onTapOutside: (_) {
            final name = controller.text.trim();
            if (name.isNotEmpty) cubit.updateProjectName(name);
          },
        ),
        actions: [
          FilledButton(
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
        titlePadding: kDialogTitlePadding,
        title: dialogCloseTitle(l10n.discardChangesDialogTitle, onClose: () => Navigator.pop(ctx), tooltip: l10n.cancel),
        content: Text(l10n.discardChangesContent),
        actions: [
          FilledButton(
            onPressed: () {
              Navigator.pop(ctx);
              cubit.discardEdits();
            },
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            child: Text(l10n.discard),
          ),
        ],
      ),
    );
  }

  Future<void> _createWalletFromProject(
          BuildContext context, Project project) =>
      createWalletFromProject(context, project, onNavigate: onNavigate);

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
    final editedKeys = state.editedKeys ?? [];

    return Column(
      children: [
        Expanded(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
            children: [
              for (final key in editedKeys)
                _buildEditableKey(context, key),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
          child: SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: () => showAddKeyDialog(context, cubit),
              icon: const Icon(Icons.add, size: 18),
              label: Text(l10n.addKeyButton),
              style: OutlinedButton.styleFrom(
                foregroundColor: AppAccent.color,
                side: BorderSide(color: AppAccent.color.withAlpha(AppAlpha.border)),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildEditableKey(BuildContext context, EditableKey key) {
    final isInUse = state.editedPaths!.any((path) => path.mfps.contains(key.mfp));
    final isHot = state.hotKeys.any((k) => k.mfp == key.mfp.toLowerCase());
    return KeyCard(
      mfp: key.mfp,
      derivationPath: key.derivationPath,
      xpub: key.xpub,
      label: key.customName,
      mfpColor: _colorForMfp(context, cubit, key.mfp),
      onNameSave: (name) => cubit.updateKeyCustomName(key.mfp, name),
      isDuplicateName: (name) => state.editedKeys!.any((k) =>
          k.mfp != key.mfp &&
          k.customName != null &&
          k.customName!.toLowerCase() == name.toLowerCase()),
      onDelete: () => cubit.removeKey(key.mfp),
      canDelete: !isInUse,
      isHot: isHot,
      onMakeHot: isHot
          ? null
          : () => showAddProjectPrivateKeySheet(
                context,
                cubit: cubit,
                expectedMfp: key.mfp,
                keyLabel: key.customName,
              ),
      onRevealSeed: isHot ? () => cubit.revealProjectSeed(key.mfp) : null,
      onDeletePrivateInfo: isHot ? () => cubit.deleteProjectHotKey(key.mfp) : null,
      network: isHot
          ? APINetwork.values.firstWhere(
              (n) => n.name == state.project.network,
              orElse: () => APINetwork.bitcoin,
            )
          : null,
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
    final editedPaths = state.editedPaths ?? [];
    final editedKeys = state.editedKeys ?? [];
    final isTaproot = state.currentWalletType == APIWalletType.p2Tr;

    return Column(
      children: [
        Expanded(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
            children: [
              for (var i = 0; i < editedPaths.length; i++)
                EditablePathCard(
                  index: i,
                  path: editedPaths[i],
                  availableKeys: editedKeys
                      .map((k) => k.toProjectKey(state.project.id))
                      .toList(),
                  mfpColorProvider: (mfp) => _colorForMfp(context, cubit, mfp),
                  isTaproot: isTaproot,
                  cubit: cubit,
                ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
          child: SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: () {
                final newIndex = editedPaths.length;
                cubit.addSpendPath();
                showSpendPathEditSheet(
                  context,
                  cubit: cubit,
                  index: newIndex,
                  isTaproot: isTaproot,
                );
              },
              icon: const Icon(Icons.add, size: 18),
              label: Text(l10n.addSpendPath),
              style: OutlinedButton.styleFrom(
                foregroundColor: AppAccent.color,
                side: BorderSide(color: AppAccent.color.withAlpha(AppAlpha.border)),
              ),
            ),
          ),
        ),
      ],
    );
  }
}
