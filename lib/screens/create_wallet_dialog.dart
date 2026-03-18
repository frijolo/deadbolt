import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import 'package:deadbolt/cubit/project_list_cubit.dart';
import 'package:deadbolt/cubit/wallet_list_cubit.dart';
import 'package:deadbolt/data/database.dart';
import 'package:deadbolt/errors.dart';
import 'package:deadbolt/screens/create_project_dialog.dart';
import 'package:deadbolt/screens/qr_scanner_screen.dart';
import 'package:deadbolt/screens/wallet_detail_screen.dart';
import 'package:deadbolt/services/wallet_service.dart';
import 'package:deadbolt/l10n/l10n.dart';
import 'package:deadbolt/src/rust/api/analyzer.dart' as rust_analyzer;
import 'package:deadbolt/src/rust/api/model.dart';
import 'package:deadbolt/utils/enum_formatters.dart';
import 'package:deadbolt/utils/toast_helper.dart';

/// Opens [CreateWalletDialog] pre-filled with [project], then navigates to
/// [WalletDetailScreen] on success.  Shows an error toast if [project] has no
/// descriptor.
Future<void> createWalletFromProject(
    BuildContext context, Project project) async {
  if (project.descriptor.isEmpty) {
    showErrorToast(context, context.l10n.projectHasNoDescriptor);
    return;
  }
  final cubit = WalletListCubit();
  final walletPath = await Navigator.push<String>(
    context,
    MaterialPageRoute(
      fullscreenDialog: true,
      builder: (_) => BlocProvider.value(
        value: cubit,
        child: CreateWalletDialog(cubit: cubit, preselectedProject: project),
      ),
    ),
  );
  if (walletPath != null && context.mounted) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => WalletDetailScreen(walletPath: walletPath),
      ),
    );
  }
}

enum _SourceMode { fromProject, manual }

class CreateWalletDialog extends StatefulWidget {
  final WalletListCubit cubit;
  final Project? preselectedProject;

  const CreateWalletDialog({
    super.key,
    required this.cubit,
    this.preselectedProject,
  });

  @override
  State<CreateWalletDialog> createState() => _CreateWalletDialogState();
}

class _CreateWalletDialogState extends State<CreateWalletDialog> {
  final _nameController = TextEditingController();
  final _descriptorController = TextEditingController();
  final _formKey = GlobalKey<FormState>();

  _SourceMode _sourceMode = _SourceMode.fromProject;
  Project? _selectedProject;
  APINetwork _selectedNetwork = APINetwork.testnet;
  bool _isCreating = false;

  // Sentinel used to detect "New project" selection in the dropdown.
  static final _newProjectSentinel = Project(
    id: -1,
    name: '',
    descriptor: '',
    network: 'bitcoin',
    walletType: 'p2wpkh',
    createdAt: DateTime.fromMillisecondsSinceEpoch(0),
    updatedAt: DateTime.fromMillisecondsSinceEpoch(0),
  );

  @override
  void initState() {
    super.initState();
    if (widget.preselectedProject != null) {
      final p = widget.preselectedProject!;
      _sourceMode = _SourceMode.fromProject;
      _selectedProject = p;
      _nameController.text = p.name;
      _selectedNetwork = APINetwork.values.byName(p.network);
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    _descriptorController.dispose();
    super.dispose();
  }

  String get _activeDescriptor => _sourceMode == _SourceMode.fromProject
      ? (_selectedProject?.descriptor ?? '')
      : _descriptorController.text.trim();

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;

    return Scaffold(
      appBar: AppBar(title: Text(l10n.createWalletTitle)),
      body: SafeArea(
        child: Form(
          key: _formKey,
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              // Name
              TextFormField(
                controller: _nameController,
                decoration: InputDecoration(
                  labelText: l10n.walletNameLabel,
                  border: const OutlineInputBorder(),
                ),
                validator: (v) => (v == null || v.trim().isEmpty)
                    ? l10n.walletNameRequired
                    : null,
              ),
              const SizedBox(height: 16),

              // Source mode
              Text(l10n.sourceProjectLabel,
                  style: Theme.of(context).textTheme.titleSmall),
              RadioGroup<_SourceMode>(
                groupValue: _sourceMode,
                onChanged: (v) => setState(() => _sourceMode = v!),
                child: Row(
                  children: [
                    Radio<_SourceMode>(value: _SourceMode.fromProject),
                    Text(l10n.sourceProjectFromProject),
                    const SizedBox(width: 24),
                    Radio<_SourceMode>(value: _SourceMode.manual),
                    Text(l10n.sourceProjectManual),
                  ],
                ),
              ),
              const SizedBox(height: 8),

              // Project selector (fromProject mode only)
              if (_sourceMode == _SourceMode.fromProject)
                _buildProjectSelector(context),

              // Descriptor input (manual mode only)
              if (_sourceMode == _SourceMode.manual) ...[
                Row(
                  children: [
                    Text(l10n.descriptorLabel,
                        style: Theme.of(context).textTheme.titleSmall),
                    const Spacer(),
                    if (!kIsWeb)
                      IconButton(
                        icon: const Icon(Icons.qr_code_scanner, size: 18),
                        tooltip: l10n.scanQrCode,
                        onPressed: _scanDescriptorQr,
                        visualDensity: VisualDensity.compact,
                        padding: EdgeInsets.zero,
                      ),
                    IconButton(
                      icon: const Icon(Icons.folder_open, size: 18),
                      tooltip: l10n.fromFile,
                      onPressed: _importDescriptorFromFile,
                      visualDensity: VisualDensity.compact,
                      padding: EdgeInsets.zero,
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                TextFormField(
                  controller: _descriptorController,
                  maxLines: 4,
                  decoration: InputDecoration(
                    hintText: l10n.descriptorHint,
                    border: const OutlineInputBorder(),
                  ),
                  style: const TextStyle(fontFamily: 'monospace', fontSize: 13),
                  validator: (v) => (v == null || v.trim().isEmpty)
                      ? l10n.descriptorEmpty
                      : null,
                ),
                const SizedBox(height: 16),
              ],

              // Network — always shown so the user can pick the exact
              // testnet variant (testnet / testnet4 / signet / regtest)
              _buildNetworkDropdown(context),

              const SizedBox(height: 24),

              if (_isCreating)
                const Center(child: CircularProgressIndicator())
              else
                FilledButton(
                  onPressed: _onCreate,
                  child: Text(l10n.createWalletButton),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildProjectSelector(BuildContext context) {
    final l10n = context.l10n;
    final projectState = context.watch<ProjectListCubit>().state;

    if (projectState is! ProjectListLoaded) {
      return const SizedBox.shrink();
    }

    final projects = projectState.projects
        .where((p) => p.descriptor.isNotEmpty)
        .toList();

    final primary = Theme.of(context).colorScheme.primary;

    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: DropdownButtonFormField<Project>(
        key: ValueKey(_selectedProject),
        initialValue: _selectedProject,
        decoration: InputDecoration(
          labelText: l10n.selectProjectLabel,
          border: const OutlineInputBorder(),
        ),
        items: [
          DropdownMenuItem(
            value: _newProjectSentinel,
            child: Row(
              children: [
                Icon(Icons.add_circle_outline, size: 16, color: primary),
                const SizedBox(width: 8),
                Text(l10n.newProjectEntry,
                    style: TextStyle(color: primary)),
              ],
            ),
          ),
          ...projects.map((p) => DropdownMenuItem(
                value: p,
                child: Text(
                    '${p.name} (${localizedNetworkDisplayName(context, p.network)})'),
              )),
        ],
        onChanged: (p) {
          if (identical(p, _newProjectSentinel)) {
            _openCreateProjectDialog(context);
            return;
          }
          setState(() {
            _selectedProject = p;
            if (p != null && _nameController.text.isEmpty) {
              _nameController.text = p.name;
            }
            // Pre-fill network from the project; user can still override below
            if (p != null) {
              _selectedNetwork = APINetwork.values.byName(p.network);
            }
          });
        },
        validator: (v) =>
            (v == null || identical(v, _newProjectSentinel))
                ? l10n.selectProjectLabel
                : null,
      ),
    );
  }

  Future<void> _openCreateProjectDialog(BuildContext context) async {
    final projectCubit = context.read<ProjectListCubit>();
    final projectId = await Navigator.push<int>(
      context,
      MaterialPageRoute(
        fullscreenDialog: true,
        builder: (_) => CreateProjectDialog(cubit: projectCubit),
      ),
    );
    if (projectId == null || !mounted) return;

    final state = projectCubit.state;
    if (state is! ProjectListLoaded) return;

    final newProject =
        state.projects.where((p) => p.id == projectId).firstOrNull;
    if (newProject == null) return;

    setState(() {
      _selectedProject = newProject;
      if (_nameController.text.isEmpty) {
        _nameController.text = newProject.name;
      }
      if (newProject.descriptor.isNotEmpty) {
        _selectedNetwork = APINetwork.values.byName(newProject.network);
      }
    });
  }

  Widget _buildNetworkDropdown(BuildContext context) {
    final l10n = context.l10n;
    return DropdownButtonFormField<APINetwork>(
      key: ValueKey(_selectedNetwork),
      initialValue: _selectedNetwork,
      decoration: InputDecoration(
        labelText: l10n.networkLabel,
        border: const OutlineInputBorder(),
      ),
      items: APINetwork.values
          .map((n) => DropdownMenuItem(
                value: n,
                child: Text(localizedNetworkName(context, n)),
              ))
          .toList(),
      onChanged: (n) => setState(() => _selectedNetwork = n!),
    );
  }

  Future<void> _scanDescriptorQr() async {
    final result = await QrScannerScreen.push(context);
    if (result != null && mounted) {
      _descriptorController.text = result.trim();
    }
  }

  Future<void> _importDescriptorFromFile() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.any,
      withData: true,
    );
    if (result == null || result.files.isEmpty) return;
    final bytes = result.files.first.bytes;
    if (bytes == null) return;
    if (mounted) {
      _descriptorController.text = String.fromCharCodes(bytes).trim();
    }
  }

  Future<void> _onCreate() async {
    if (!_formKey.currentState!.validate()) return;

    final desc = _activeDescriptor;
    // Capture db before any async gap so context is safe to use
    final db = context.read<AppDatabase>();

    // Validate descriptor ↔ network compatibility via Rust before any async work
    if (desc.isNotEmpty) {
      try {
        await rust_analyzer.validateDescriptorNetwork(
          descriptor: desc,
          network: _selectedNetwork,
        );
      } catch (e) {
        if (mounted) showErrorToast(context, formatRustError(e));
        return;
      }
    }

    setState(() => _isCreating = true);
    try {
      final walletPath = await widget.cubit.createWallet(
        name: _nameController.text.trim(),
        descriptor: desc,
        network: _selectedNetwork,
      );

      if (_sourceMode == _SourceMode.fromProject && _selectedProject != null) {
        await _copyProjectLabels(_selectedProject!, walletPath, db);
      }

      if (mounted) Navigator.pop(context, walletPath);
    } catch (e) {
      setState(() => _isCreating = false);
      if (mounted) showErrorToast(context, formatRustError(e));
    }
  }

  Future<void> _copyProjectLabels(
      Project project, String walletPath, AppDatabase db) async {
    try {
      final (keys, paths) = await (
        db.getKeysForProject(project.id),
        db.getSpendPathsForProject(project.id),
      ).wait;

      final labeledKeys =
          keys.where((k) => k.customName != null && k.customName!.isNotEmpty);
      final labeledPaths =
          paths.where((p) => p.customName != null && p.customName!.isNotEmpty);

      if (labeledKeys.isEmpty && labeledPaths.isEmpty) return;

      final handle = await WalletService().openWallet(walletPath);
      for (final key in labeledKeys) {
        handle.setKeyLabel(mfp: key.mfp, label: key.customName!);
      }
      for (final path in labeledPaths) {
        handle.setPathLabel(rustId: path.rustId, label: path.customName!);
      }
    } catch (e, st) {
      debugPrint('Failed to copy project labels to wallet: $e\n$st');
    }
  }
}
