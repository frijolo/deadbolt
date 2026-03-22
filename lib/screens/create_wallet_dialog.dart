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
import 'package:deadbolt/utils/enum_formatters.dart';
import 'package:deadbolt/utils/toast_helper.dart';
import 'package:deadbolt/widgets/loading_indicator.dart';

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
  final VoidCallback? onGoToProjects;

  const CreateWalletDialog({
    super.key,
    required this.cubit,
    this.preselectedProject,
    this.onGoToProjects,
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
  final _passwordController = TextEditingController();
  final _passwordConfirmController = TextEditingController();
  bool _obscurePassword = true;
  bool _obscurePasswordConfirm = true;

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

              // Network — always shown so the user can pick the exact
              // testnet variant (testnet / testnet4 / signet / regtest)
              _buildNetworkDropdown(context),

              const SizedBox(height: 16),
              _buildProtectionSection(context),

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
                if (widget.preselectedProject == null) ...[
                  const SizedBox(height: 12),
                  OutlinedButton.icon(
                    onPressed: () {
                      Navigator.pop(context);
                      widget.onGoToProjects?.call();
                    },
                    icon: const Icon(Icons.design_services_outlined),
                    label: Text(l10n.fromProjectAction),
                  ),
                ],
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

  Widget _buildProtectionSection(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Wallet protection',
            style: Theme.of(context).textTheme.titleSmall),
        const SizedBox(height: 4),
        RadioGroup<APIProtectionType>(
          groupValue: _protectionType,
          onChanged: (v) => setState(() => _protectionType = v!),
          child: const Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Radio<APIProtectionType>(
                      value: APIProtectionType.deviceKey),
                  Expanded(
                    child: Text('Device key (automatic)'),
                  ),
                ],
              ),
              Row(
                children: [
                  Radio<APIProtectionType>(
                      value: APIProtectionType.userPassword),
                  Expanded(
                    child: Text('Password protection'),
                  ),
                ],
              ),
              Row(
                children: [
                  Radio<APIProtectionType>(
                      value: APIProtectionType.xpubKey),
                  Expanded(
                    child: Text('xpub key (any descriptor key unlocks)'),
                  ),
                ],
              ),
            ],
          ),
        ),
        if (_protectionType == APIProtectionType.xpubKey) ...[
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(
              children: [
                Icon(Icons.info_outline,
                    size: 16,
                    color: Theme.of(context).colorScheme.onSurfaceVariant),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Any xpub from the descriptor can unlock this wallet. '
                    'Do not share those xpubs with third parties.',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                  ),
                ),
              ],
            ),
          ),
        ],
        if (_protectionType == APIProtectionType.userPassword) ...[
          const SizedBox(height: 8),
          TextFormField(
            controller: _passwordController,
            obscureText: _obscurePassword,
            decoration: InputDecoration(
              labelText: 'Password',
              border: const OutlineInputBorder(),
              suffixIcon: IconButton(
                icon: Icon(_obscurePassword
                    ? Icons.visibility_off
                    : Icons.visibility),
                onPressed: () =>
                    setState(() => _obscurePassword = !_obscurePassword),
              ),
            ),
            validator: (v) {
              if (_protectionType != APIProtectionType.userPassword) {
                return null;
              }
              if (v == null || v.isEmpty) return 'Password cannot be empty';
              return null;
            },
          ),
          const SizedBox(height: 8),
          TextFormField(
            controller: _passwordConfirmController,
            obscureText: _obscurePasswordConfirm,
            decoration: InputDecoration(
              labelText: 'Confirm password',
              border: const OutlineInputBorder(),
              suffixIcon: IconButton(
                icon: Icon(_obscurePasswordConfirm
                    ? Icons.visibility_off
                    : Icons.visibility),
                onPressed: () => setState(
                    () => _obscurePasswordConfirm = !_obscurePasswordConfirm),
              ),
            ),
            validator: (v) {
              if (_protectionType != APIProtectionType.userPassword) {
                return null;
              }
              if (v != _passwordController.text) {
                return 'Passwords do not match';
              }
              return null;
            },
          ),
        ],
      ],
    );
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
