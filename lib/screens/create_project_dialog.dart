import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'package:deadbolt/cubit/project_list_cubit.dart';
import 'package:deadbolt/cubit/settings_cubit.dart';
import 'package:deadbolt/errors.dart';
import 'package:deadbolt/l10n/l10n.dart';
import 'package:deadbolt/screens/qr_scanner_screen.dart';
import 'package:deadbolt/src/rust/api/model.dart';
import 'package:deadbolt/utils/enum_formatters.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

enum CreateMode { importDescriptor, fromScratch }

class CreateProjectDialog extends StatefulWidget {
  final ProjectListCubit cubit;

  const CreateProjectDialog({super.key, required this.cubit});

  @override
  State<CreateProjectDialog> createState() => _CreateProjectDialogState();
}

class _CreateProjectDialogState extends State<CreateProjectDialog> {
  final _descriptorController = TextEditingController();
  final _nameController = TextEditingController();
  CreateMode _mode = CreateMode.importDescriptor;
  late APINetwork _selectedNetwork;
  late APIWalletType _selectedWalletType;
  bool _loading = false;
  String? _error;
  String? _loadingMessage;
  bool _initialized = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_initialized) {
      final settings = context.read<SettingsCubit>().state;
      _selectedNetwork = settings.network;
      _selectedWalletType = settings.walletType;
      _initialized = true;
    }
  }

  @override
  void dispose() {
    _descriptorController.dispose();
    _nameController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.newProjectTitle),
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Mode selector
              SegmentedButton<CreateMode>(
                segments: [
                  ButtonSegment(
                    value: CreateMode.importDescriptor,
                    label: Text(l10n.importDescriptorMode),
                    icon: const Icon(Icons.file_download, size: 16),
                  ),
                  ButtonSegment(
                    value: CreateMode.fromScratch,
                    label: Text(l10n.fromScratchMode),
                    icon: const Icon(Icons.add_circle_outline, size: 16),
                  ),
                ],
                selected: {_mode},
                onSelectionChanged: (Set<CreateMode> newSelection) {
                  setState(() {
                    _mode = newSelection.first;
                    _error = null;
                  });
                },
              ),
              const SizedBox(height: 16),
              // Project name
              Text(
                l10n.projectNameLabel,
                style: TextStyle(fontSize: 11, color: cs.onSurface.withAlpha(138)),
              ),
              const SizedBox(height: 4),
              TextField(
                controller: _nameController,
                decoration: const InputDecoration(
                  border: OutlineInputBorder(),
                  contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                ),
              ),
              const SizedBox(height: 16),
              // Mode-specific content
              if (_mode == CreateMode.importDescriptor)
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Text(
                            l10n.descriptorLabel,
                            style: TextStyle(fontSize: 11, color: cs.onSurface.withAlpha(138)),
                          ),
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
                      Expanded(
                        child: TextField(
                          controller: _descriptorController,
                          decoration: InputDecoration(
                            hintText: l10n.descriptorHint,
                            border: const OutlineInputBorder(),
                            contentPadding: const EdgeInsets.all(12),
                          ),
                          maxLines: null,
                          expands: true,
                          textAlignVertical: TextAlignVertical.top,
                          style: const TextStyle(
                            fontFamily: 'monospace',
                            fontSize: 13,
                          ),
                        ),
                      ),
                    ],
                  ),
                )
              else
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      l10n.networkLabel,
                      style: TextStyle(fontSize: 11, color: cs.onSurface.withAlpha(138)),
                    ),
                    const SizedBox(height: 4),
                    PopupMenuButton<APINetwork>(
                      offset: const Offset(0, 32),
                      onSelected: (value) => setState(() => _selectedNetwork = value),
                      tooltip: l10n.selectNetworkTooltip,
                      itemBuilder: (context) => [
                        APINetwork.bitcoin,
                        APINetwork.testnet,
                      ].map((network) => PopupMenuItem(
                            value: network,
                            child: Text(localizedNetworkName(context, network)),
                          ))
                          .toList(),
                      child: Container(
                        width: double.infinity,
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                        decoration: BoxDecoration(
                          border: Border.all(color: cs.onSurface.withAlpha(61)),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              localizedNetworkName(context, _selectedNetwork),
                              style: const TextStyle(fontSize: 14),
                            ),
                            const Icon(Icons.arrow_drop_down, size: 24),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    Text(
                      l10n.walletTypeLabel,
                      style: TextStyle(fontSize: 11, color: cs.onSurface.withAlpha(138)),
                    ),
                    const SizedBox(height: 4),
                    PopupMenuButton<APIWalletType>(
                      offset: const Offset(0, 32),
                      onSelected: (value) => setState(() => _selectedWalletType = value),
                      tooltip: l10n.selectWalletTypeTooltip,
                      itemBuilder: (context) => [
                        APIWalletType.p2Tr,
                        APIWalletType.p2Wsh,
                        APIWalletType.p2ShWsh,
                        APIWalletType.p2Sh,
                        APIWalletType.p2Wpkh,
                        APIWalletType.p2ShWpkh,
                        APIWalletType.p2Pkh,
                      ].map((type) => PopupMenuItem(
                            value: type,
                            child: Text(localizedWalletTypeName(context, type)),
                          ))
                          .toList(),
                      child: Container(
                        width: double.infinity,
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                        decoration: BoxDecoration(
                          border: Border.all(color: cs.onSurface.withAlpha(61)),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              localizedWalletTypeName(context, _selectedWalletType),
                              style: const TextStyle(fontSize: 14),
                            ),
                            const Icon(Icons.arrow_drop_down, size: 24),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              if (_error != null)
                Padding(
                  padding: const EdgeInsets.only(top: 12),
                  child: Text(
                    _error!,
                    style: const TextStyle(color: Colors.red),
                  ),
                ),
              if (_loadingMessage != null)
                Padding(
                  padding: const EdgeInsets.only(top: 12),
                  child: Text(
                    _loadingMessage!,
                    style: TextStyle(color: cs.onSurface.withAlpha(178)),
                    textAlign: TextAlign.center,
                  ),
                ),
              const SizedBox(height: 16),
              FilledButton(
                onPressed: _loading ? null : _createProject,
                child: _loading
                    ? const SizedBox(
                        height: 20,
                        width: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : Text(_mode == CreateMode.importDescriptor
                        ? l10n.analyzeAndSave
                        : l10n.createProject),
              ),
            ],
          ),
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

  Future<void> _createProject() async {
    final l10n = context.l10n;
    // Validate project name (required for both modes)
    final name = _nameController.text.trim();
    if (name.isEmpty) {
      setState(() => _error = l10n.projectNameRequired);
      return;
    }

    if (_mode == CreateMode.importDescriptor) {
      // Import from descriptor
      final descriptor = _descriptorController.text.trim();
      if (descriptor.isEmpty) {
        setState(() => _error = l10n.descriptorEmpty);
        return;
      }

      setState(() {
        _loading = true;
        _error = null;
        _loadingMessage = l10n.analyzingDescriptor;
      });

      try {
        final projectId = await widget.cubit.createProject(
          descriptor: descriptor,
          name: name,
        );
        if (mounted) {
          Navigator.pop(context, projectId);
        }
      } catch (e) {
        if (mounted) {
          setState(() {
            _loading = false;
            _loadingMessage = null;
            _error = formatRustError(e);
          });
        }
      }
    } else {
      // Start from scratch
      setState(() {
        _loading = true;
        _error = null;
        _loadingMessage = l10n.creatingProject;
      });

      try {
        final projectId = await widget.cubit.createEmptyProject(
          name: name,
          network: _selectedNetwork,
          walletType: _selectedWalletType,
        );
        if (mounted) {
          Navigator.pop(context, projectId);
        }
      } catch (e) {
        if (mounted) {
          setState(() {
            _loading = false;
            _loadingMessage = null;
            _error = formatRustError(e);
          });
        }
      }
    }
  }
}
