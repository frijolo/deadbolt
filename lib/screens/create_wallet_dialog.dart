import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import 'package:deadbolt/cubit/project_list_cubit.dart';
import 'package:deadbolt/cubit/wallet_list_cubit.dart';
import 'package:deadbolt/data/database.dart';
import 'package:deadbolt/errors.dart';
import 'package:deadbolt/l10n/l10n.dart';
import 'package:deadbolt/src/rust/api/analyzer.dart' as rust_analyzer;
import 'package:deadbolt/src/rust/api/model.dart';
import 'package:deadbolt/utils/enum_formatters.dart';
import 'package:deadbolt/utils/toast_helper.dart';

enum _SourceMode { fromProject, manual }

class CreateWalletDialog extends StatefulWidget {
  final WalletListCubit cubit;

  const CreateWalletDialog({super.key, required this.cubit});

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
                TextFormField(
                  controller: _descriptorController,
                  maxLines: 4,
                  decoration: InputDecoration(
                    labelText: l10n.descriptorLabel,
                    hintText: l10n.descriptorHint,
                    border: const OutlineInputBorder(),
                  ),
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

    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: DropdownButtonFormField<Project>(
        initialValue: _selectedProject,
        decoration: InputDecoration(
          labelText: l10n.selectProjectLabel,
          border: const OutlineInputBorder(),
        ),
        items: projects
            .map((p) => DropdownMenuItem(
                  value: p,
                  child: Text(
                      '${p.name} (${localizedNetworkDisplayName(context, p.network)})'),
                ))
            .toList(),
        onChanged: (p) {
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
        validator: (v) => v == null ? l10n.selectProjectLabel : null,
      ),
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

  Future<void> _onCreate() async {
    if (!_formKey.currentState!.validate()) return;

    final desc = _activeDescriptor;

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
      final int? sourceProjectId =
          _sourceMode == _SourceMode.fromProject ? _selectedProject!.id : null;

      final walletPath = await widget.cubit.createWallet(
        name: _nameController.text.trim(),
        descriptor: desc,
        network: _selectedNetwork,
        sourceProjectId: sourceProjectId,
      );

      if (mounted) Navigator.pop(context, walletPath);
    } catch (e) {
      setState(() => _isCreating = false);
      if (mounted) showErrorToast(context, formatRustError(e));
    }
  }
}
