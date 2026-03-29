import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import 'package:deadbolt/cubit/settings_cubit.dart';
import 'package:deadbolt/cubit/wallet_list_cubit.dart';
import 'package:deadbolt/models/timelock_types.dart';
import 'package:deadbolt/src/rust/api/analyzer.dart' as rust_analyzer;
import 'package:deadbolt/src/rust/api/model.dart';
import 'package:deadbolt/theme/app_theme.dart';
import 'package:deadbolt/utils/toast_helper.dart';
import 'package:deadbolt/services/wallet_service.dart';
import 'package:deadbolt/widgets/add_key_dialog.dart'
    show KeyspecResult, kKeyspecPattern, showKeyspecSheet;
import 'package:deadbolt/widgets/loading_indicator.dart';
import 'package:deadbolt/widgets/mfp_badge.dart';
import 'package:deadbolt/widgets/colored_group_text.dart';
import 'package:deadbolt/widgets/network_dropdown_field.dart';
import 'package:deadbolt/widgets/protection_section.dart';

// ---------------------------------------------------------------------------
// File-private helpers
// ---------------------------------------------------------------------------

enum _ScriptChoice { legacy, nestedSegwit, nativeSegwit, taproot }

APIPubKey _parseKeyspec(KeyspecResult result) {
  final m = kKeyspecPattern.firstMatch(result.keyspec)!;
  return APIPubKey(
    mfp: m.group(1)!,
    derivationPath: m.group(2)!,
    xpub: m.group(3)!,
  );
}

String _mfpOf(KeyspecResult result) =>
    kKeyspecPattern.firstMatch(result.keyspec)!.group(1)!;

APIWalletType _mapWalletType(_ScriptChoice script, bool isMultisig) {
  return switch (script) {
    _ScriptChoice.legacy => isMultisig ? APIWalletType.p2Sh : APIWalletType.p2Pkh,
    _ScriptChoice.nestedSegwit =>
      isMultisig ? APIWalletType.p2ShWsh : APIWalletType.p2ShWpkh,
    _ScriptChoice.nativeSegwit =>
      isMultisig ? APIWalletType.p2Wsh : APIWalletType.p2Wpkh,
    _ScriptChoice.taproot => APIWalletType.p2Tr,
  };
}

String _scriptDescription(_ScriptChoice script, bool isMultisig) {
  return switch (script) {
    _ScriptChoice.legacy => isMultisig
        ? 'P2SH — Oldest multisig standard. Highest fees.'
        : 'P2PKH — Oldest standard. Highest fees. Maximum compatibility.',
    _ScriptChoice.nestedSegwit => isMultisig
        ? 'P2SH-P2WSH — SegWit multisig with backward compatibility.'
        : 'P2SH-P2WPKH — SegWit wrapped for backward compatibility.',
    _ScriptChoice.nativeSegwit => isMultisig
        ? 'P2WSH — Native SegWit multisig. Lower fees, widely supported.'
        : 'P2WPKH — Most common modern standard. Lower fees.',
    _ScriptChoice.taproot => isMultisig
        ? 'P2TR — Taproot multisig. Best privacy. Requires compatible wallets.'
        : 'P2TR — Taproot. Best privacy and lowest fees.',
  };
}

// ---------------------------------------------------------------------------
// Widget
// ---------------------------------------------------------------------------

class SimpleWalletDialog extends StatefulWidget {
  final WalletListCubit cubit;

  const SimpleWalletDialog({super.key, required this.cubit});

  @override
  State<SimpleWalletDialog> createState() => _SimpleWalletDialogState();
}

class _SimpleWalletDialogState extends State<SimpleWalletDialog> {
  final _nameController = TextEditingController();
  final _passwordController = TextEditingController();
  final _passwordConfirmController = TextEditingController();
  final _formKey = GlobalKey<FormState>();

  bool _isMultisig = false;
  _ScriptChoice _scriptChoice = _ScriptChoice.nativeSegwit;
  final List<KeyspecResult> _keyspecs = []; // each: "[mfp/path]xpub" + optional seed
  int _threshold = 1;

  late APINetwork _selectedNetwork;
  APIProtectionType _protectionType = APIProtectionType.deviceKey;
  APISecurityLevel _securityLevel = APISecurityLevel.standard;
  bool _isCreating = false;

  @override
  void initState() {
    super.initState();
    _selectedNetwork = context.read<SettingsCubit>().state.network;
  }

  @override
  void dispose() {
    _nameController.dispose();
    _passwordController.dispose();
    _passwordConfirmController.dispose();
    super.dispose();
  }

  Future<KeyspecResult?> _collectKeyspec({Set<String> excludeMfps = const {}}) =>
      showKeyspecSheet(
        context,
        network: _selectedNetwork,
        walletType: _mapWalletType(_scriptChoice, _isMultisig),
        existingKeyCount: _keyspecs.length,
        existingMfps: excludeMfps,
      );

  Future<void> _addKey() async {
    final result = await _collectKeyspec(
        excludeMfps: _keyspecs.map(_mfpOf).toSet());
    if (result != null && mounted) {
      setState(() {
        _keyspecs.add(result);
        if (_threshold > _keyspecs.length) _threshold = _keyspecs.length;
      });
    }
  }

  Future<void> _replaceKey(int index) async {
    final excludeMfps = {
      for (final (i, k) in _keyspecs.indexed)
        if (i != index) _mfpOf(k),
    };
    final result = await _collectKeyspec(excludeMfps: excludeMfps);
    if (result != null && mounted) {
      setState(() => _keyspecs[index] = result);
    }
  }

  void _removeKey(int index) {
    setState(() {
      _keyspecs.removeAt(index);
      if (_threshold > _keyspecs.length && _keyspecs.isNotEmpty) {
        _threshold = _keyspecs.length;
      }
    });
  }

  Future<void> _onCreate() async {
    if (!_formKey.currentState!.validate()) return;

    if (_keyspecs.isEmpty) {
      showErrorToast(context, 'Add at least one key');
      return;
    }
    if (_isMultisig && _keyspecs.length < 2) {
      showErrorToast(context, 'Multi key wallets need at least 2 keys');
      return;
    }

    final keys = _keyspecs.map(_parseKeyspec).toList();
    final mfps = keys.map((k) => k.mfp).toList();
    final isTaproot = _scriptChoice == _ScriptChoice.taproot;

    final spendPaths = [
      APISpendPathDef(
        threshold: _isMultisig ? _threshold : 1,
        mfps: mfps,
        relTimelock: kNoRelativeTimelock,
        absTimelock: kNoAbsoluteTimelock,
        isKeyPath: !_isMultisig && isTaproot,
        priority: 0,
      ),
    ];
    final walletType = _mapWalletType(_scriptChoice, _isMultisig);

    String descriptor;
    try {
      descriptor = await rust_analyzer.buildDescriptor(
        walletType: walletType,
        keys: keys,
        spendPaths: spendPaths,
      );
    } catch (e) {
      if (mounted) showErrorToastException(context, e);
      return;
    }

    try {
      await rust_analyzer.validateDescriptorNetwork(
        descriptor: descriptor,
        network: _selectedNetwork,
      );
    } catch (e) {
      if (mounted) showErrorToastException(context, e);
      return;
    }

    if (!mounted) return;
    setState(() => _isCreating = true);
    try {
      final password = _protectionType == APIProtectionType.userPassword
          ? _passwordController.text
          : null;
      final walletPath = await widget.cubit.createWallet(
        name: _nameController.text.trim(),
        descriptor: descriptor,
        network: _selectedNetwork,
        protectionType: _protectionType,
        password: password,
        securityLevel: _securityLevel,
      );

      // If any key was entered via seed, persist it as a hot key now.
      final seedKeys = _keyspecs
          .where((r) => r.mnemonic != null || r.xprv != null)
          .toList();
      if (seedKeys.isNotEmpty && mounted) {
        final service = context.read<WalletService>();
        final handle = await service.openWallet(walletPath, password: password);
        for (final r in seedKeys) {
          if (r.mnemonic != null) {
            handle.addMnemonicKey(
                mnemonic: r.mnemonic!, passphrase: r.passphrase);
          } else if (r.xprv != null) {
            handle.addXprvKey(xprv: r.xprv!);
          }
        }
      }

      if (mounted) Navigator.pop(context, walletPath);
    } catch (e) {
      if (mounted) setState(() => _isCreating = false);
      if (mounted) showErrorToastException(context, e);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('New Wallet'),
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
                decoration: const InputDecoration(
                  labelText: 'Wallet name',
                  border: OutlineInputBorder(),
                ),
                validator: (v) =>
                    (v == null || v.trim().isEmpty) ? 'Name is required' : null,
              ),
              const SizedBox(height: 20),

              // Wallet type (single / multi)
              _buildSectionLabel(context, 'Wallet type'),
              const SizedBox(height: 8),
              SizedBox(
                width: double.infinity,
                child: SegmentedButton<bool>(
                  showSelectedIcon: false,
                  segments: const [
                    ButtonSegment(value: false, label: Text('Singlesig')),
                    ButtonSegment(value: true, label: Text('Multisig')),
                  ],
                  selected: {_isMultisig},
                  onSelectionChanged: (v) => setState(() {
                    _isMultisig = v.first;
                    _threshold = 1;
                  }),
                ),
              ),
              const SizedBox(height: 6),
              Text(
                _isMultisig
                    ? 'Multiple keys required to sign. Ideal for shared control or extra security.'
                    : 'One key controls the wallet. Best for personal use.',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
              ),
              const SizedBox(height: 20),

              // Script type
              _buildSectionLabel(context, 'Script type'),
              const SizedBox(height: 8),
              SizedBox(
                width: double.infinity,
                child: SegmentedButton<_ScriptChoice>(
                  showSelectedIcon: false,
                  segments: const [
                    ButtonSegment(
                        value: _ScriptChoice.legacy, label: Text('Legacy')),
                    ButtonSegment(
                        value: _ScriptChoice.nestedSegwit,
                        label: Text('Nested')),
                    ButtonSegment(
                        value: _ScriptChoice.nativeSegwit,
                        label: Text('SegWit')),
                    ButtonSegment(
                        value: _ScriptChoice.taproot, label: Text('Taproot')),
                  ],
                  selected: {_scriptChoice},
                  onSelectionChanged: (v) =>
                      setState(() => _scriptChoice = v.first),
                ),
              ),
              const SizedBox(height: 6),
              Text(
                _scriptDescription(_scriptChoice, _isMultisig),
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
              ),
              const SizedBox(height: 20),

              // Keys section
              _buildKeysSection(context),
              const SizedBox(height: 20),

              // Network
              NetworkDropdownField(
                value: _selectedNetwork,
                onChanged: (n) => setState(() => _selectedNetwork = n),
              ),
              const SizedBox(height: 16),

              // Protection
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
              const SizedBox(height: 24),

              // Create / loading
              if (_isCreating)
                const LoadingIndicator(message: 'Creating wallet…')
              else
                FilledButton(
                  onPressed: _onCreate,
                  child: const Text('Create wallet'),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSectionLabel(BuildContext context, String label) =>
      Text(label, style: Theme.of(context).textTheme.labelMedium);

  Widget _buildKeysSection(BuildContext context) {
    final ext = Theme.of(context).extension<KeyColorExtension>()!;
    final hasKeys = _keyspecs.isNotEmpty;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            _buildSectionLabel(
              context,
              _isMultisig
                  ? 'Keys${hasKeys ? ' (${_keyspecs.length})' : ''}'
                  : 'Key',
            ),
            const Spacer(),
            if (_isMultisig || !hasKeys)
              TextButton.icon(
                onPressed: _addKey,
                icon: const Icon(Icons.add, size: 16),
                label: const Text('Add key'),
                style: TextButton.styleFrom(
                    visualDensity: VisualDensity.compact),
              ),
          ],
        ),

        // Threshold row (multisig only)
        if (_isMultisig && _keyspecs.length >= 2) ...[
          const SizedBox(height: 4),
          Row(
            children: [
              Expanded(
                child: Text(
                  'Required signatures: $_threshold of ${_keyspecs.length}',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ),
              IconButton(
                onPressed: _threshold > 1
                    ? () => setState(() => _threshold--)
                    : null,
                tooltip: 'Decrease threshold',
                icon: const Icon(Icons.remove_circle_outline, size: 20),
                visualDensity: VisualDensity.compact,
              ),
              Text('$_threshold',
                  style: Theme.of(context).textTheme.titleSmall),
              IconButton(
                onPressed: _threshold < _keyspecs.length
                    ? () => setState(() => _threshold++)
                    : null,
                tooltip: 'Increase threshold',
                icon: const Icon(Icons.add_circle_outline, size: 20),
                visualDensity: VisualDensity.compact,
              ),
            ],
          ),
        ],

        // Key tiles
        if (hasKeys) ...[
          const SizedBox(height: 8),
          for (int i = 0; i < _keyspecs.length; i++) ...[
            if (i > 0) const SizedBox(height: 4),
            _buildKeyTile(context, i, ext),
          ],
        ],
      ],
    );
  }

  Widget _buildKeyTile(
      BuildContext context, int index, KeyColorExtension ext) {
    final result = _keyspecs[index];
    final match = kKeyspecPattern.firstMatch(result.keyspec)!;
    final mfp = match.group(1)!;
    final xpub = match.group(3)!;
    final color = ext.keyColors[index % ext.keyColors.length];

    return Card(
      margin: EdgeInsets.zero,
      child: ListTile(
        dense: true,
        leading: MfpBadge(label: mfp, color: color),
        title: ColoredGroupText(text: xpub, fontSize: 12, truncate: true, monospace: true),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            IconButton(
              icon: const Icon(Icons.edit_outlined, size: 18),
              visualDensity: VisualDensity.compact,
              tooltip: 'Replace key',
              onPressed: () => _replaceKey(index),
            ),
            IconButton(
              icon: Icon(Icons.delete_outline,
                  size: 18,
                  color: Colors.red.withAlpha(AppAlpha.deleteAction)),
              visualDensity: VisualDensity.compact,
              tooltip: 'Remove key',
              onPressed: () => _removeKey(index),
            ),
          ],
        ),
        onTap: () => _replaceKey(index),
      ),
    );
  }

}
