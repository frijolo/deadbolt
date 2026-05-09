import 'package:file_picker/file_picker.dart';
import 'package:deadbolt/config/constants.dart' show kMonospaceFontFamily;
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'package:deadbolt/cubit/project_list_cubit.dart';
import 'package:deadbolt/cubit/settings_cubit.dart';
import 'package:deadbolt/theme/app_theme.dart';
import 'package:deadbolt/widgets/mfp_badge.dart';
import 'package:deadbolt/errors.dart';
import 'package:deadbolt/l10n/l10n.dart';
import 'package:deadbolt/screens/qr_scanner_screen.dart';
import 'package:deadbolt/src/rust/api/model.dart';
import 'package:deadbolt/utils/enum_formatters.dart';
import 'package:deadbolt/widgets/wallet_type_picker.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

enum CreateMode { importDescriptor, fromScratch }

class CreateProjectDialog extends StatefulWidget {
  final ProjectListCubit cubit;
  final CreateMode mode;

  const CreateProjectDialog({super.key, required this.cubit, required this.mode});

  @override
  State<CreateProjectDialog> createState() => _CreateProjectDialogState();
}

class _CreateProjectDialogState extends State<CreateProjectDialog> {
  final _descriptorController = TextEditingController();
  final _nameController = TextEditingController();
  late CreateMode _mode;
  late APINetwork _selectedNetwork;
  WalletPolicy _policy = WalletPolicy.singleSig;
  WalletAddressFormat _addressFormat = WalletAddressFormat.segwit;
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
      _policy = walletPolicyFrom(settings.walletType);
      _addressFormat = walletAddressFormatFrom(settings.walletType);
      _mode = widget.mode;
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
    final title = widget.mode == CreateMode.importDescriptor
        ? l10n.importDescriptorMode
        : l10n.fromScratchMode;

    return Scaffold(
      appBar: AppBar(
        title: Text(title),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 16),
            child: Center(
              child: MfpBadge(
                label: localizedNetworkName(context, _selectedNetwork),
                color: AppAccent.color,
                letterSpacing: 0.0,
              ),
            ),
          ),
        ],
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Project name
              Text(
                l10n.projectNameLabel,
                style: TextStyle(fontSize: 11, color: cs.onSurface.withAlpha(AppAlpha.secondary)),
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
                            style: TextStyle(fontSize: 11, color: cs.onSurface.withAlpha(AppAlpha.secondary)),
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
                            fontFamily: kMonospaceFontFamily,
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
                    const SizedBox(height: 16),
                    Text(
                      l10n.walletTypeLabel,
                      style: TextStyle(fontSize: 11, color: cs.onSurface.withAlpha(AppAlpha.secondary)),
                    ),
                    const SizedBox(height: 4),
                    WalletTypePicker(
                      policy: _policy,
                      addressFormat: _addressFormat,
                      onPolicyChanged: (p) => setState(() => _policy = p),
                      onFormatChanged: (f) => setState(() => _addressFormat = f),
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
                    style: TextStyle(color: cs.onSurface.withAlpha(AppAlpha.mediumHigh)),
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
          walletType: walletTypeFromAxes(_policy, _addressFormat),
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

