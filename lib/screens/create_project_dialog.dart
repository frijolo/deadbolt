import 'package:flutter/material.dart';

import 'package:deadbolt/cubit/project_list_cubit.dart';
import 'package:deadbolt/errors.dart';
import 'package:deadbolt/src/rust/api/model.dart';
import 'package:deadbolt/utils/enum_formatters.dart';

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
  APINetwork _selectedNetwork = APINetwork.testnet;
  APIWalletType _selectedWalletType = APIWalletType.p2Tr;
  bool _loading = false;
  String? _error;
  String? _loadingMessage;

  @override
  void dispose() {
    _descriptorController.dispose();
    _nameController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('New project'),
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Mode selector
              SegmentedButton<CreateMode>(
                segments: const [
                  ButtonSegment(
                    value: CreateMode.importDescriptor,
                    label: Text('Import descriptor'),
                    icon: Icon(Icons.file_download, size: 16),
                  ),
                  ButtonSegment(
                    value: CreateMode.fromScratch,
                    label: Text('Start from scratch'),
                    icon: Icon(Icons.add_circle_outline, size: 16),
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
              const Text(
                'Project name',
                style: TextStyle(fontSize: 11, color: Colors.white54),
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
                      const Text(
                        'Descriptor',
                        style: TextStyle(fontSize: 11, color: Colors.white54),
                      ),
                      const SizedBox(height: 4),
                      Expanded(
                        child: TextField(
                          controller: _descriptorController,
                          decoration: const InputDecoration(
                            hintText: 'Paste your Bitcoin descriptor here...',
                            border: OutlineInputBorder(),
                            contentPadding: EdgeInsets.all(12),
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
                    const Text(
                      'Network',
                      style: TextStyle(fontSize: 11, color: Colors.white54),
                    ),
                    const SizedBox(height: 4),
                    PopupMenuButton<APINetwork>(
                      offset: const Offset(0, 32),
                      onSelected: (value) => setState(() => _selectedNetwork = value),
                      tooltip: 'Select network',
                      itemBuilder: (context) => [
                        APINetwork.bitcoin,
                        APINetwork.testnet,
                      ].map((network) => PopupMenuItem(
                            value: network,
                            child: Text(network.displayName),
                          ))
                          .toList(),
                      child: Container(
                        width: double.infinity,
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                        decoration: BoxDecoration(
                          border: Border.all(color: Colors.white24),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              _selectedNetwork.displayName,
                              style: const TextStyle(fontSize: 14),
                            ),
                            const Icon(Icons.arrow_drop_down, size: 24),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    const Text(
                      'Wallet type',
                      style: TextStyle(fontSize: 11, color: Colors.white54),
                    ),
                    const SizedBox(height: 4),
                    PopupMenuButton<APIWalletType>(
                      offset: const Offset(0, 32),
                      onSelected: (value) => setState(() => _selectedWalletType = value),
                      tooltip: 'Select wallet type',
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
                            child: Text(type.displayName),
                          ))
                          .toList(),
                      child: Container(
                        width: double.infinity,
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                        decoration: BoxDecoration(
                          border: Border.all(color: Colors.white24),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              _selectedWalletType.displayName,
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
                    style: const TextStyle(color: Colors.white70),
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
                        ? 'Analyze & Save'
                        : 'Create Project'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _createProject() async {
    // Validate project name (required for both modes)
    final name = _nameController.text.trim();
    if (name.isEmpty) {
      setState(() => _error = 'Project name is required');
      return;
    }

    if (_mode == CreateMode.importDescriptor) {
      // Import from descriptor
      final descriptor = _descriptorController.text.trim();
      if (descriptor.isEmpty) {
        setState(() => _error = 'Descriptor cannot be empty');
        return;
      }

      setState(() {
        _loading = true;
        _error = null;
        _loadingMessage = 'Analyzing descriptor...';
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
        _loadingMessage = 'Creating project...';
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
