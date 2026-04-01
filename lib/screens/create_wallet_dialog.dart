import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import 'package:deadbolt/cubit/project_list_cubit.dart';
import 'package:deadbolt/cubit/wallet_list_cubit.dart';
import 'package:deadbolt/data/database.dart';
import 'package:deadbolt/screens/qr_scanner_screen.dart';
import 'package:deadbolt/screens/wallet_detail_screen.dart';
import 'package:deadbolt/services/wallet_service.dart';
import 'package:deadbolt/l10n/l10n.dart';
import 'package:deadbolt/src/rust/api/analyzer.dart' as rust_analyzer;
import 'package:deadbolt/src/rust/api/model.dart';
import 'package:deadbolt/src/rust/api/wallet.dart' show copyProjectKeysToWallet;
import 'package:deadbolt/utils/toast_helper.dart';
import 'package:deadbolt/widgets/loading_indicator.dart';
import 'package:deadbolt/widgets/network_dropdown_field.dart';
import 'package:deadbolt/widgets/protection_section.dart';

/// Opens [CreateWalletDialog] pre-filled with [project], then navigates to
/// [WalletDetailScreen] on success.  Shows an error toast if [project] has no
/// descriptor.
Future<void> createWalletFromProject(
    BuildContext context, Project project,
    {void Function(int)? onNavigate}) async {
  if (project.descriptor.isEmpty) {
    showErrorToast(context, context.l10n.projectHasNoDescriptor);
    return;
  }
  final cubit = context.read<WalletListCubit>();
  final walletPath = await Navigator.push<String>(
    context,
    MaterialPageRoute(
      fullscreenDialog: true,
      builder: (_) => CreateWalletDialog(cubit: cubit, preselectedProject: project),
    ),
  );
  if (walletPath != null && context.mounted) {
    // Switch to wallet tab and refresh list before navigating to wallet detail.
    onNavigate?.call(0);
    if (context.mounted) {
      context.read<WalletListCubit>().refresh();
    }
    if (context.mounted) {
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(
          builder: (_) => WalletDetailScreen(
            walletPath: walletPath,
            onNavigate: onNavigate,
          ),
        ),
        (route) => route.isFirst,
      );
    }
  }
}

class CreateWalletDialog extends StatefulWidget {
  final WalletListCubit cubit;
  final Project? preselectedProject;
  /// Called when the user wants to switch back to the guided wizard.
  /// Receives the [BuildContext] of [CreateWalletDialog] so the caller can
  /// do a `Navigator.pushReplacement` from the correct navigator.
  final void Function(BuildContext ctx)? onGoToGuided;

  const CreateWalletDialog({
    super.key,
    required this.cubit,
    this.preselectedProject,
    this.onGoToGuided,
  });

  @override
  State<CreateWalletDialog> createState() => _CreateWalletDialogState();
}

class _CreateWalletDialogState extends State<CreateWalletDialog> {
  final _nameController = TextEditingController();
  final _descriptorController = TextEditingController();
  final _formKey = GlobalKey<FormState>();

  APINetwork _selectedNetwork = APINetwork.testnet;
  bool _isCreating = false;
  bool _deleteProject = false;

  // Protection
  APIProtectionType _protectionType = APIProtectionType.deviceKey;
  APISecurityLevel _securityLevel = APISecurityLevel.standard;
  final _passwordController = TextEditingController();
  final _passwordConfirmController = TextEditingController();

  @override
  void initState() {
    super.initState();
    if (widget.preselectedProject != null) {
      final p = widget.preselectedProject!;
      _nameController.text = p.name;
      _selectedNetwork = APINetwork.values.byName(p.network);
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    _descriptorController.dispose();
    _passwordController.dispose();
    _passwordConfirmController.dispose();
    super.dispose();
  }

  String get _activeDescriptor =>
      widget.preselectedProject?.descriptor ?? _descriptorController.text.trim();

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;

    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.createWalletTitle),
      ),
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

              // Network — always shown so the user can pick the exact
              // testnet variant (testnet / testnet4 / signet / regtest)
              NetworkDropdownField(
                value: _selectedNetwork,
                onChanged: (n) => setState(() => _selectedNetwork = n),
              ),
              const SizedBox(height: 16),

              // Descriptor: editable (manual) or read-only card (from project)
              if (widget.preselectedProject == null) ...[
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
              ] else ...[
                _buildDescriptorCard(context),
                const SizedBox(height: 16),
              ],

              const SizedBox(height: 16),
              ProtectionSection(
                passwordController: _passwordController,
                passwordConfirmController: _passwordConfirmController,
                initialProtectionType: _protectionType,
                initialSecurityLevel: _securityLevel,
                onChanged: (type, level) => setState(() {
                  _protectionType = type;
                  _securityLevel = level;
                }),
              ),

              // Delete project checkbox (only when from project)
              if (widget.preselectedProject != null) ...[
                const SizedBox(height: 8),
                CheckboxListTile(
                  value: _deleteProject,
                  onChanged: (v) => setState(() => _deleteProject = v ?? false),
                  title: Text(l10n.deleteProjectAfterCreate),
                  controlAffinity: ListTileControlAffinity.leading,
                  contentPadding: EdgeInsets.zero,
                ),
              ],

              const SizedBox(height: 24),

              if (_isCreating)
                LoadingIndicator(message: l10n.creatingWallet)
              else ...[
                FilledButton(
                  onPressed: _onCreate,
                  child: Text(l10n.createWalletButton),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildDescriptorCard(BuildContext context) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(l10n.descriptorLabel, style: theme.textTheme.labelMedium),
            const SizedBox(height: 6),
            SelectableText(
              widget.preselectedProject!.descriptor,
              style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
            ),
          ],
        ),
      ),
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
    // Capture context-dependent values before any async gap
    final db = context.read<AppDatabase>();
    final service = context.read<WalletService>();
    final projectCubit = widget.preselectedProject != null
        ? context.read<ProjectListCubit>()
        : null;

    // Validate descriptor ↔ network compatibility via Rust before any async work
    if (desc.isNotEmpty) {
      try {
        await rust_analyzer.validateDescriptorNetwork(
          descriptor: desc,
          network: _selectedNetwork,
        );
      } catch (e) {
        if (mounted) showErrorToastException(context, e);
        return;
      }
    }

    setState(() => _isCreating = true);
    try {
      final password = _protectionType == APIProtectionType.userPassword
          ? _passwordController.text
          : null;
      final walletPath = await widget.cubit.createWallet(
        name: _nameController.text.trim(),
        descriptor: desc,
        network: _selectedNetwork,
        protectionType: _protectionType,
        password: password,
        securityLevel: _securityLevel,
      );

      if (widget.preselectedProject != null) {
        await _copyProjectLabels(widget.preselectedProject!, walletPath, db, service);
        await _copyProjectKeys(widget.preselectedProject!.id, walletPath, service, password);
      }

      if (_deleteProject && projectCubit != null && widget.preselectedProject != null) {
        projectCubit.deleteProject(widget.preselectedProject!.id);
      }

      if (mounted) Navigator.pop(context, walletPath);
    } catch (e) {
      setState(() => _isCreating = false);
      if (mounted) showErrorToastException(context, e);
    }
  }

  Future<void> _copyProjectKeys(
      int projectId, String walletPath, WalletService service, String? password) async {
    try {
      final appSupportDir = await service.getAppSupportDir();
      final deviceKeyHex = await service.getOrCreateEncryptionKey();
      copyProjectKeysToWallet(
        appSupportDir: appSupportDir,
        projectId: projectId,
        walletPath: walletPath,
        deviceKeyHex: deviceKeyHex,
        walletPassword: password,
      );
    } catch (e, st) {
      debugPrint('Failed to copy project keys to wallet: $e\n$st');
    }
  }

  Future<void> _copyProjectLabels(
      Project project, String walletPath, AppDatabase db, WalletService service) async {
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

      final handle = await service.openWallet(walletPath);
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
