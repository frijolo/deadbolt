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
  APINetwork _selectedNetwork = APINetwork.bitcoin;
  APIWalletType _selectedWalletType = APIWalletType.p2Tr;
  bool _loading = false;
  String? _error;

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
              TextField(
                controller: _nameController,
                decoration: InputDecoration(
                  labelText: _mode == CreateMode.fromScratch
                      ? 'Project name'
                      : 'Project name (optional)',
                  border: const OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 16),
              // Mode-specific content
              if (_mode == CreateMode.importDescriptor)
                Expanded(
                  child: TextField(
                    controller: _descriptorController,
                    decoration: const InputDecoration(
                      labelText: 'Descriptor',
                      hintText: 'Paste your Bitcoin descriptor here...',
                      border: OutlineInputBorder(),
                      alignLabelWithHint: true,
                    ),
                    maxLines: null,
                    expands: true,
                    textAlignVertical: TextAlignVertical.top,
                    style: const TextStyle(
                      fontFamily: 'monospace',
                      fontSize: 13,
                    ),
                  ),
                )
              else
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Network',
                      style: Theme.of(context).textTheme.titleSmall,
                    ),
                    const SizedBox(height: 8),
                    InputDecorator(
                      decoration: const InputDecoration(
                        border: OutlineInputBorder(),
                        contentPadding: EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 8,
                        ),
                      ),
                      child: DropdownButtonHideUnderline(
                        child: DropdownButton<APINetwork>(
                          value: _selectedNetwork,
                          isExpanded: true,
                          isDense: true,
                          items: [
                            APINetwork.bitcoin,
                            APINetwork.testnet,
                          ].map((network) => DropdownMenuItem(
                                value: network,
                                child: Text(network.displayName),
                              ))
                              .toList(),
                          onChanged: (value) {
                            if (value != null) {
                              setState(() => _selectedNetwork = value);
                            }
                          },
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    Text(
                      'Wallet type',
                      style: Theme.of(context).textTheme.titleSmall,
                    ),
                    const SizedBox(height: 8),
                    InputDecorator(
                      decoration: const InputDecoration(
                        border: OutlineInputBorder(),
                        contentPadding: EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 8,
                        ),
                      ),
                      child: DropdownButtonHideUnderline(
                        child: DropdownButton<APIWalletType>(
                          value: _selectedWalletType,
                          isExpanded: true,
                          isDense: true,
                          items: [
                            APIWalletType.p2Tr,
                            APIWalletType.p2Wsh,
                            APIWalletType.p2ShWsh,
                            APIWalletType.p2Sh,
                            APIWalletType.p2Wpkh,
                            APIWalletType.p2ShWpkh,
                            APIWalletType.p2Pkh,
                          ].map((type) => DropdownMenuItem(
                                value: type,
                                child: Text(type.displayName),
                              ))
                              .toList(),
                          onChanged: (value) {
                            if (value != null) {
                              setState(() => _selectedWalletType = value);
                            }
                          },
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
      });

      try {
        final projectId = await widget.cubit.createProject(
          descriptor: descriptor,
          name: _nameController.text.trim(),
        );
        if (mounted) {
          Navigator.pop(context, projectId);
        }
      } catch (e) {
        if (mounted) {
          setState(() {
            _loading = false;
            _error = formatRustError(e);
          });
        }
      }
    } else {
      // Start from scratch
      final name = _nameController.text.trim();
      if (name.isEmpty) {
        setState(() => _error = 'Project name is required');
        return;
      }

      setState(() {
        _loading = true;
        _error = null;
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
            _error = formatRustError(e);
          });
        }
      }
    }
  }
}
