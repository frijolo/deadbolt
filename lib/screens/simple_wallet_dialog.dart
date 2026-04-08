import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart' show DragStartBehavior;
import 'package:flutter_bloc/flutter_bloc.dart';

import 'package:deadbolt/cubit/settings_cubit.dart';
import 'package:deadbolt/l10n/l10n.dart';
import 'package:deadbolt/cubit/wallet_list_cubit.dart';
import 'package:deadbolt/models/timelock_types.dart';
import 'package:deadbolt/src/rust/api/analyzer.dart' as rust_analyzer;
import 'package:deadbolt/src/rust/api/model.dart';
import 'package:deadbolt/theme/app_theme.dart';
import 'package:deadbolt/utils/toast_helper.dart';
import 'package:deadbolt/services/wallet_service.dart';
import 'package:deadbolt/widgets/add_key_dialog.dart'
    show KeyspecResult, kKeyspecPattern, showKeyspecSheet;
import 'package:deadbolt/widgets/dialog_helpers.dart' show showSheet, sheetCloseTitle;
import 'package:deadbolt/widgets/key_edit_sheet.dart' show showKeySheet;
import 'package:deadbolt/widgets/loading_indicator.dart';
import 'package:deadbolt/widgets/mfp_badge.dart';
import 'package:deadbolt/widgets/colored_group_text.dart';
import 'package:deadbolt/utils/bitcoin_formatter.dart';
import 'package:deadbolt/utils/enum_formatters.dart';
import 'package:deadbolt/widgets/protection_section.dart';

// ---------------------------------------------------------------------------
// File-private helpers
// ---------------------------------------------------------------------------

enum _ScriptChoice { legacy, nestedSegwit, nativeSegwit, taproot }

enum _WalletMode { singlesig, multisig, inheritance }

/// Represents a single heir in an inheritance wallet.
class _HeirEntry {
  final String name;
  final KeyspecResult keyspec;
  final int timelockBlocks;

  const _HeirEntry({
    required this.name,
    required this.keyspec,
    required this.timelockBlocks,
  });

  _HeirEntry copyWith({String? name, KeyspecResult? keyspec, int? timelockBlocks}) =>
      _HeirEntry(
        name: name ?? this.name,
        keyspec: keyspec ?? this.keyspec,
        timelockBlocks: timelockBlocks ?? this.timelockBlocks,
      );
}

// Approximate blocks per unit at 10 min/block.
// Max relative timelock = 65,535 blocks (~1.24 years). All presets must stay within range.
const _k3Months = 13140;
const _k6Months = 26280;
const _k9Months = 39420;
const _k1Year = 52560;
const _kTimelockCustom = -1; // sentinel for the custom segment in SegmentedButton

APIPubKey _parseKeyspec(KeyspecResult result) {
  final m = kKeyspecPattern.firstMatch(result.keyspec);
  if (m == null) throw ArgumentError('Invalid keyspec: ${result.keyspec}');
  return APIPubKey(
    mfp: m.group(1)!,
    derivationPath: m.group(2)!,
    xpub: m.group(3)!,
  );
}

String _mfpOf(KeyspecResult result) =>
    kKeyspecPattern.firstMatch(result.keyspec)?.group(1) ?? '';

/// Infer script type from the BIP44 purpose field in a keyspec path.
_ScriptChoice _inferScriptFromKeyspec(String keyspec) {
  final m = kKeyspecPattern.firstMatch(keyspec);
  if (m == null) return _ScriptChoice.nativeSegwit;
  final path = m.group(2)!; // e.g. "84'/0'/0'"
  final purpose = path.split('/').first.replaceAll("'", '');
  return switch (purpose) {
    '44' => _ScriptChoice.legacy,
    '49' => _ScriptChoice.nestedSegwit,
    '84' => _ScriptChoice.nativeSegwit,
    '86' => _ScriptChoice.taproot,
    _ => _ScriptChoice.nativeSegwit,
  };
}

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

String _scriptDescription(AppLocalizations l10n, _ScriptChoice script, bool isMultisig) {
  return switch (script) {
    _ScriptChoice.legacy => isMultisig ? l10n.scriptDescP2sh : l10n.scriptDescP2pkh,
    _ScriptChoice.nestedSegwit => isMultisig ? l10n.scriptDescP2shWsh : l10n.scriptDescP2shWpkh,
    _ScriptChoice.nativeSegwit => isMultisig ? l10n.scriptDescP2wsh : l10n.scriptDescP2wpkh,
    _ScriptChoice.taproot => isMultisig ? l10n.scriptDescP2trMultisig : l10n.scriptDescP2trSinglesig,
  };
}

// ---------------------------------------------------------------------------
// Widget
// ---------------------------------------------------------------------------

class SimpleWalletDialog extends StatefulWidget {
  final WalletListCubit cubit;
  /// Pre-filled keyspecs from a restore-from-seed flow (singlesig only).
  final List<KeyspecResult> initialKeyspecs;
  /// Network pre-selected from the scan (null → use SettingsCubit default).
  final APINetwork? initialNetwork;

  const SimpleWalletDialog({
    super.key,
    required this.cubit,
    this.initialKeyspecs = const [],
    this.initialNetwork,
  });

  @override
  State<SimpleWalletDialog> createState() => _SimpleWalletDialogState();
}

class _SimpleWalletDialogState extends State<SimpleWalletDialog> {
  final _nameController = TextEditingController();
  final _passwordController = TextEditingController();
  final _passwordConfirmController = TextEditingController();
  final _formKey = GlobalKey<FormState>();

  _WalletMode _walletMode = _WalletMode.singlesig;
  _ScriptChoice _scriptChoice = _ScriptChoice.nativeSegwit;
  final List<KeyspecResult> _keyspecs = []; // each: "[mfp/path]xpub" + optional seed
  final Map<String, String?> _keyNamesByMfp = {};
  int _threshold = 1;

  // Inheritance-specific state
  final List<_HeirEntry> _heirs = [];

  late APINetwork _selectedNetwork;
  APIProtectionType _protectionType = APIProtectionType.deviceKey;
  APISecurityLevel _securityLevel = APISecurityLevel.standard;
  bool _isCreating = false;

  bool get _isMultisig =>
      _walletMode == _WalletMode.multisig || _walletMode == _WalletMode.inheritance;

  bool get _isInheritance => _walletMode == _WalletMode.inheritance;

  @override
  void initState() {
    super.initState();
    _selectedNetwork =
        widget.initialNetwork ?? context.read<SettingsCubit>().state.network;

    if (widget.initialKeyspecs.isNotEmpty) {
      _keyspecs.addAll(widget.initialKeyspecs);
      _walletMode = _WalletMode.singlesig;
      _scriptChoice = _inferScriptFromKeyspec(widget.initialKeyspecs.first.keyspec);
    }
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
        isMultiPath: _isMultisig,
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

  void _removeKey(int index) {
    final mfp = _mfpOf(_keyspecs[index]);
    setState(() {
      _keyspecs.removeAt(index);
      _keyNamesByMfp.remove(mfp);
      if (_threshold > _keyspecs.length && _keyspecs.isNotEmpty) {
        _threshold = _keyspecs.length;
      }
    });
  }

  void _showKeyInfo(int index) {
    final result = _keyspecs[index];
    final match = kKeyspecPattern.firstMatch(result.keyspec);
    if (match == null) return;
    final mfp = match.group(1)!;
    final derivationPath = match.group(2)!;
    final xpub = match.group(3)!;
    final ext = Theme.of(context).extension<KeyColorExtension>()!;
    final color = ext.keyColors[index % ext.keyColors.length];
    final isHot = result.mnemonic != null || result.xprv != null;

    showKeySheet(
      context,
      mfp: mfp,
      initialName: _keyNamesByMfp[mfp],
      derivationPath: derivationPath,
      xpub: xpub,
      mfpColor: color,
      onNameSave: (name) => setState(() => _keyNamesByMfp[mfp] = name),
      isHot: isHot,
      onRevealSeed: isHot ? () async => result.mnemonic ?? result.xprv : null,
    );
  }

  Future<void> _addHeir() async {
    final entry = await showSheet<_HeirEntry>(
      context,
      (_) => _HeirSetupSheet(
        network: _selectedNetwork,
        walletType: _mapWalletType(_scriptChoice, true),
        existingMfps: {
          ..._keyspecs.map(_mfpOf),
          ..._heirs.map((h) => _mfpOf(h.keyspec)),
        },
      ),
      isDismissible: false,
    );
    if (entry != null && mounted) {
      setState(() => _heirs.add(entry));
    }
  }

  void _removeHeir(int index) {
    setState(() => _heirs.removeAt(index));
  }

  Future<void> _editHeir(int index) async {
    final current = _heirs[index];
    final otherMfps = {
      ..._keyspecs.map(_mfpOf),
      for (int i = 0; i < _heirs.length; i++)
        if (i != index) _mfpOf(_heirs[i].keyspec),
    };
    final updated = await showSheet<_HeirEntry>(
      context,
      (_) => _HeirSetupSheet(
        network: _selectedNetwork,
        walletType: _mapWalletType(_scriptChoice, true),
        existingMfps: otherMfps,
        initialEntry: current,
      ),
      isDismissible: false,
    );
    if (updated != null && mounted) {
      setState(() => _heirs[index] = updated);
    }
  }

  /// Returns true = fix, false = continue anyway, null = cancel.
  Future<bool?> _showDuplicateTimelockDialog() {
    final l10n = context.l10n;
    return showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l10n.inheritanceDuplicateTimelockTitle),
        content: Text(l10n.inheritanceDuplicateTimelockBody),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(l10n.cancel),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(l10n.inheritanceDuplicateTimelockContinue),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(l10n.inheritanceDuplicateTimelockFix),
          ),
        ],
      ),
    );
  }

  /// Resolves a flat list of timelock values so every entry is unique and in
  /// [1, 65535]. Sorted by current value; each duplicate or zero is bumped to
  /// (previous + 1). Entries that already fit in [1, 65535] are left unchanged;
  /// only values that overflowed past 65535 are replaced with the largest
  /// unused values below 65535 (filling down from 65534). Original index order
  /// is preserved in the returned list.
  List<int> _resolveTimelocks(List<int> timelocks) {
    final indexed = timelocks.asMap().entries.toList()
      ..sort((a, b) => a.value.compareTo(b.value));
    int last = 0;
    final temp = <int>[];
    for (final e in indexed) {
      int tl = e.value < 1 ? 1 : e.value;
      if (tl <= last) tl = last + 1;
      temp.add(tl);
      last = tl;
    }
    // Replace overflowed values (> 65535) with the largest unused values
    // below 65535, working right-to-left so entries that already fit are
    // untouched.
    if (temp.isNotEmpty && temp.last > 65535) {
      final used = temp.where((v) => v <= 65535).toSet();
      int fill = 65534;
      for (int i = temp.length - 1; i >= 0; i--) {
        if (temp[i] > 65535) {
          while (used.contains(fill)) { fill--; }
          temp[i] = fill;
          used.add(fill);
          fill--;
        }
      }
    }
    final fixes = <int, int>{};
    for (int i = 0; i < indexed.length; i++) {
      fixes[indexed[i].key] = temp[i];
    }
    return List.generate(timelocks.length, (i) => fixes[i] ?? timelocks[i]);
  }

  Future<void> _onCreate() async {
    if (!_formKey.currentState!.validate()) return;

    if (_keyspecs.isEmpty) {
      showErrorToast(context.l10n.addAtLeastOneKey);
      return;
    }
    if (_walletMode == _WalletMode.multisig && _keyspecs.length < 2) {
      showErrorToast(context.l10n.multisigNeedsMinKeys);
      return;
    }
    if (_isInheritance) {
      if (_heirs.isEmpty) {
        showErrorToast(context.l10n.inheritanceNeedHeir);
        return;
      }
    }

    // Detect duplicate or zero timelocks among heir paths only.
    // The main (owner) path intentionally has no timelock — it is the keypath.
    List<_HeirEntry> workingHeirs = List.from(_heirs);
    if (_isInheritance) {
      final heirTimelocks = workingHeirs.map((h) => h.timelockBlocks).toList();
      if (heirTimelocks.toSet().length < heirTimelocks.length ||
          heirTimelocks.any((t) => t == 0)) {
        final fix = await _showDuplicateTimelockDialog();
        if (!mounted) return;
        if (fix == null) return;
        if (fix) {
          final fixed = _resolveTimelocks(heirTimelocks);
          workingHeirs = workingHeirs.asMap().entries
              .map((e) => e.value.copyWith(timelockBlocks: fixed[e.key]))
              .toList();
          setState(() {
            _heirs
              ..clear()
              ..addAll(workingHeirs);
          });
        }
      }
    }

    final keys = _keyspecs.map(_parseKeyspec).toList();
    final mfps = keys.map((k) => k.mfp).toList();
    final isTaproot = _scriptChoice == _ScriptChoice.taproot;

    late List<APISpendPathDef> spendPaths;
    late APIWalletType walletType;

    if (_isInheritance) {
      // Sort heirs by timelock ascending: shorter delay = higher priority in script tree
      final sortedHeirs = List<_HeirEntry>.from(workingHeirs)
        ..sort((a, b) => a.timelockBlocks.compareTo(b.timelockBlocks));

      // Owner path has no timelock; single-sig taproot uses the keypath.
      final ownerIsKeyPath = isTaproot && _keyspecs.length == 1;
      final ownerPriority = sortedHeirs.length; // highest priority = shallowest

      final ownerPath = APISpendPathDef(
        threshold: _threshold,
        mfps: mfps,
        relTimelock: kNoRelativeTimelock,
        absTimelock: kNoAbsoluteTimelock,
        isKeyPath: ownerIsKeyPath,
        priority: ownerPriority,
      );

      final heirPaths = <APISpendPathDef>[];
      for (int i = 0; i < sortedHeirs.length; i++) {
        final h = sortedHeirs[i];
        final heirKey = _parseKeyspec(h.keyspec);
        heirPaths.add(APISpendPathDef(
          threshold: 1,
          mfps: [heirKey.mfp],
          relTimelock: APIRelativeTimelock(
            timelockType: APIRelativeTimelockType.blocks,
            value: h.timelockBlocks,
          ),
          absTimelock: kNoAbsoluteTimelock,
          isKeyPath: false,
          priority: sortedHeirs.length - 1 - i,
        ));
      }

      // Collect heir APIPubKeys (owner keys already in `keys`)
      final heirKeys = sortedHeirs.map((h) => _parseKeyspec(h.keyspec)).toList();
      keys.addAll(heirKeys);

      spendPaths = [ownerPath, ...heirPaths];
      // Inheritance always needs multi-path builder (WSH or TR)
      walletType = _mapWalletType(_scriptChoice, true);
    } else {
      spendPaths = [
        APISpendPathDef(
          threshold: _isMultisig ? _threshold : 1,
          mfps: mfps,
          relTimelock: kNoRelativeTimelock,
          absTimelock: kNoAbsoluteTimelock,
          isKeyPath: !_isMultisig && isTaproot,
          priority: 0,
        ),
      ];
      walletType = _mapWalletType(_scriptChoice, _isMultisig);
    }

    String descriptor;
    try {
      descriptor = await rust_analyzer.buildDescriptor(
        walletType: walletType,
        keys: keys,
        spendPaths: spendPaths,
      );
    } catch (e) {
      if (mounted) showErrorToastException(e);
      return;
    }

    try {
      await rust_analyzer.validateDescriptorNetwork(
        descriptor: descriptor,
        network: _selectedNetwork,
      );
    } catch (e) {
      if (mounted) showErrorToastException(e);
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

      // Persist seed keys (hot), custom key labels, and inheritance path labels.
      final allKeyspecs = [..._keyspecs, ...workingHeirs.map((h) => h.keyspec)];
      final seedKeys = allKeyspecs
          .where((r) => r.mnemonic != null || r.xprv != null)
          .toList();
      final namedKeys = _keyNamesByMfp.entries
          .where((e) => e.value != null && e.value!.isNotEmpty);
      if ((seedKeys.isNotEmpty || namedKeys.isNotEmpty || _isInheritance) && mounted) {
        final service = context.read<WalletService>();
        final ownerPathLabel = _isInheritance ? context.l10n.inheritanceOwnerPathLabel : '';
        final handle = await service.openWallet(walletPath, password: password);
        for (final r in seedKeys) {
          if (r.mnemonic != null) {
            handle.addMnemonicKey(
                mnemonic: r.mnemonic!, passphrase: r.passphrase);
          } else if (r.xprv != null) {
            handle.addXprvKey(xprv: r.xprv!);
          }
        }
        for (final e in namedKeys) {
          handle.setKeyLabel(mfp: e.key, label: e.value!);
        }
        if (_isInheritance) {
          final analysis =
              await rust_analyzer.analyzeDescriptor(descriptor: descriptor);
          final ownerMfps = _keyspecs.map(_mfpOf).toSet();
          for (final sp in analysis.spendPaths) {
            final spMfps = sp.mfps.toSet();
            if (spMfps.length == ownerMfps.length &&
                spMfps.containsAll(ownerMfps)) {
              handle.setPathLabel(
                  rustId: sp.id,
                  label: ownerPathLabel);
            } else if (sp.mfps.length == 1) {
              final heirMfp = sp.mfps.first;
              final heir = workingHeirs
                  .where((h) =>
                      _mfpOf(h.keyspec) == heirMfp && h.name.isNotEmpty)
                  .firstOrNull;
              if (heir != null) {
                handle.setPathLabel(rustId: sp.id, label: heir.name);
              }
            }
          }
          for (final heir in workingHeirs) {
            if (heir.name.isNotEmpty) {
              handle.setKeyLabel(
                  mfp: _mfpOf(heir.keyspec), label: heir.name);
            }
          }
        }
      }

      if (mounted) Navigator.pop(context, walletPath);
    } catch (e) {
      if (mounted) setState(() => _isCreating = false);
      if (mounted) showErrorToastException(e);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.newWalletTitle),
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
        child: Form(
          key: _formKey,
          child: ListView(
            dragStartBehavior: DragStartBehavior.down,
            padding: const EdgeInsets.all(16),
            children: [
              // Name
              TextFormField(
                controller: _nameController,
                decoration: InputDecoration(
                  labelText: l10n.walletNameLabel,
                  border: const OutlineInputBorder(),
                ),
                validator: (v) =>
                    (v == null || v.trim().isEmpty) ? l10n.validatorNameRequired : null,
              ),
              const SizedBox(height: 20),

              // Wallet type (single / multi / inheritance)
              _buildSectionLabel(context, l10n.walletTypeLabel),
              const SizedBox(height: 8),
              SizedBox(
                width: double.infinity,
                child: SegmentedButton<_WalletMode>(
                  showSelectedIcon: false,
                  segments: [
                    ButtonSegment(
                        value: _WalletMode.singlesig,
                        label: Text(l10n.walletTypeSinglesig)),
                    ButtonSegment(
                        value: _WalletMode.multisig,
                        label: Text(l10n.walletTypeMultisig)),
                    ButtonSegment(
                        value: _WalletMode.inheritance,
                        label: Text(l10n.walletTypeInheritance)),
                  ],
                  selected: {_walletMode},
                  onSelectionChanged: (v) => setState(() {
                    _walletMode = v.first;
                    _threshold = 1;
                    if (_isInheritance) _scriptChoice = _ScriptChoice.taproot;
                  }),
                ),
              ),
              const SizedBox(height: 6),
              Text(
                switch (_walletMode) {
                  _WalletMode.singlesig => l10n.walletTypeSinglesigDesc,
                  _WalletMode.multisig => l10n.walletTypeMultisigDesc,
                  _WalletMode.inheritance => l10n.walletTypeInheritanceDesc,
                },
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
              ),
              const SizedBox(height: 20),

              // Script type
              _buildSectionLabel(context, l10n.scriptTypeLabel),
              const SizedBox(height: 8),
              SizedBox(
                width: double.infinity,
                child: SegmentedButton<_ScriptChoice>(
                  showSelectedIcon: false,
                  segments: [
                    if (!_isInheritance) ...[
                      ButtonSegment(
                          value: _ScriptChoice.legacy,
                          label: Text(l10n.scriptTypeLegacy)),
                      ButtonSegment(
                          value: _ScriptChoice.nestedSegwit,
                          label: Text(l10n.scriptTypeNested)),
                    ],
                    ButtonSegment(
                        value: _ScriptChoice.nativeSegwit,
                        label: Text(l10n.scriptTypeSegwit)),
                    ButtonSegment(
                        value: _ScriptChoice.taproot,
                        label: Text(l10n.scriptTypeTaproot)),
                  ],
                  selected: {_scriptChoice},
                  onSelectionChanged: (v) =>
                      setState(() => _scriptChoice = v.first),
                ),
              ),
              const SizedBox(height: 6),
              Text(
                _scriptDescription(l10n, _scriptChoice, _isMultisig),
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
              ),
              const SizedBox(height: 20),

              // Keys section
              _buildKeysSection(context),
              const SizedBox(height: 20),

              // Heirs section (inheritance only)
              if (_isInheritance) ...[
                _buildHeirsSection(context),
                const SizedBox(height: 20),
              ],

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
                LoadingIndicator(message: l10n.creatingWalletLabel)
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

  Widget _buildSectionLabel(BuildContext context, String label) =>
      Text(label, style: Theme.of(context).textTheme.labelMedium);

  Widget _buildKeysSection(BuildContext context) {
    final l10n = context.l10n;
    final ext = Theme.of(context).extension<KeyColorExtension>()!;
    final hasKeys = _keyspecs.isNotEmpty;

    // In inheritance mode the label is "Your keys"
    final sectionLabel = _isInheritance
        ? l10n.ownerKeysSection
        : (_isMultisig
            ? l10n.keysSection(hasKeys ? _keyspecs.length : 0)
            : l10n.keySectionLabel);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            _buildSectionLabel(context, sectionLabel),
            const Spacer(),
            if (_isMultisig || !hasKeys)
              TextButton.icon(
                onPressed: _addKey,
                icon: const Icon(Icons.add, size: 16),
                label: Text(l10n.addKeyButton),
                style: TextButton.styleFrom(
                    visualDensity: VisualDensity.compact),
              ),
          ],
        ),

        // Threshold row (multisig and inheritance owner with multiple keys)
        if (_isMultisig && _keyspecs.length >= 2) ...[
          const SizedBox(height: 4),
          Row(
            children: [
              Expanded(
                child: Text(
                  l10n.requiredSignatures(_threshold, _keyspecs.length),
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ),
              IconButton(
                onPressed: _threshold > 1
                    ? () => setState(() => _threshold--)
                    : null,
                tooltip: l10n.decreaseThresholdTooltip,
                icon: const Icon(Icons.remove_circle_outline, size: 20),
                visualDensity: VisualDensity.compact,
              ),
              Text('$_threshold',
                  style: Theme.of(context).textTheme.titleSmall),
              IconButton(
                onPressed: _threshold < _keyspecs.length
                    ? () => setState(() => _threshold++)
                    : null,
                tooltip: l10n.increaseThresholdTooltip,
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

  Widget _buildHeirsSection(BuildContext context) {
    final l10n = context.l10n;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            _buildSectionLabel(context, l10n.heirsSection),
            const Spacer(),
            TextButton.icon(
              onPressed: _addHeir,
              icon: const Icon(Icons.person_add_outlined, size: 16),
              label: Text(l10n.addHeir),
              style: TextButton.styleFrom(
                  visualDensity: VisualDensity.compact),
            ),
          ],
        ),
        if (_heirs.isNotEmpty) ...[
          const SizedBox(height: 8),
          for (int i = 0; i < _heirs.length; i++) ...[
            if (i > 0) const SizedBox(height: 4),
            _buildHeirTile(context, i),
          ],
        ],
      ],
    );
  }

  Widget _buildHeirTile(BuildContext context, int index) {
    final heir = _heirs[index];
    final match = kKeyspecPattern.firstMatch(heir.keyspec.keyspec);
    final mfp = match?.group(1) ?? '?';
    final approxLabel = _blocksToApproxLabel(context.l10n, heir.timelockBlocks);

    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 10, 4, 10),
        child: Row(
          children: [
            const Icon(Icons.person_outline, size: 18),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    heir.name.isEmpty ? context.l10n.inheritanceHeirN(index + 1) : heir.name,
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                  ),
                  const SizedBox(height: 2),
                  Row(
                    children: [
                      MfpBadge(
                        label: mfp,
                        color: Theme.of(context).colorScheme.tertiary,
                      ),
                      const SizedBox(width: 8),
                      Icon(Icons.lock_clock_outlined,
                          size: 13,
                          color: Theme.of(context).colorScheme.onSurfaceVariant),
                      const SizedBox(width: 2),
                      Text(
                        approxLabel,
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              color:
                                  Theme.of(context).colorScheme.onSurfaceVariant,
                            ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            IconButton(
              icon: const Icon(Icons.edit_outlined, size: 18),
              visualDensity: VisualDensity.compact,
              tooltip: context.l10n.editHeir,
              onPressed: () => _editHeir(index),
            ),
            IconButton(
              icon: Icon(Icons.delete_outline,
                  size: 18,
                  color: Colors.red.withAlpha(AppAlpha.deleteAction)),
              visualDensity: VisualDensity.compact,
              tooltip: context.l10n.removeKeyTooltip,
              onPressed: () => _removeHeir(index),
            ),
          ],
        ),
      ),
    );
  }

  String _blocksToApproxLabel(AppLocalizations l10n, int blocks) {
    if (blocks == _k3Months) return l10n.inheritanceThreeMonths;
    if (blocks == _k6Months) return l10n.inheritanceSixMonths;
    if (blocks == _k9Months) return l10n.inheritanceNineMonths;
    if (blocks == _k1Year) return l10n.inheritanceOneYear;
    return '~${BitcoinFormatter.formatDuration(blocks * 10)} ($blocks blocks)';
  }

  Widget _buildKeyTile(
      BuildContext context, int index, KeyColorExtension ext) {
    final result = _keyspecs[index];
    final match = kKeyspecPattern.firstMatch(result.keyspec);
    if (match == null) return const SizedBox.shrink();
    final mfp = match.group(1)!;
    final derivationPath = match.group(2)!;
    final xpub = match.group(3)!;
    final color = ext.keyColors[index % ext.keyColors.length];

    return Card(
      margin: EdgeInsets.zero,
      child: InkWell(
        onTap: () => _showKeyInfo(index),
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 10, 4, 10),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        MfpBadge(label: mfp, color: color),
                        const SizedBox(width: 8),
                        Text(
                          '/ $derivationPath',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            letterSpacing: 0.5,
                            color: Theme.of(context).colorScheme.onSurface.withAlpha(AppAlpha.high),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    ColoredGroupText(text: xpub, fontSize: 13, truncate: true, monospace: true),
                  ],
                ),
              ),
              IconButton(
                icon: const Icon(Icons.info_outline, size: 18),
                visualDensity: VisualDensity.compact,
                tooltip: context.l10n.keyDetailsTooltip,
                onPressed: () => _showKeyInfo(index),
              ),
              IconButton(
                icon: Icon(Icons.delete_outline,
                    size: 18,
                    color: Colors.red.withAlpha(AppAlpha.deleteAction)),
                visualDensity: VisualDensity.compact,
                tooltip: context.l10n.removeKeyTooltip,
                onPressed: () => _removeKey(index),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Heir setup bottom sheet
// ---------------------------------------------------------------------------

class _HeirSetupSheet extends StatefulWidget {
  final APINetwork network;
  final APIWalletType walletType;
  final Set<String> existingMfps;
  final _HeirEntry? initialEntry;

  const _HeirSetupSheet({
    required this.network,
    required this.walletType,
    required this.existingMfps,
    this.initialEntry,
  });

  @override
  State<_HeirSetupSheet> createState() => _HeirSetupSheetState();
}

class _HeirSetupSheetState extends State<_HeirSetupSheet> {
  final _nameController = TextEditingController();
  final _blocksController = TextEditingController();
  KeyspecResult? _keyspec;
  int _timelockBlocks = _k1Year;
  bool _isCustomTimelock = false;

  bool get _isEditing => widget.initialEntry != null;

  @override
  void initState() {
    super.initState();
    final initial = widget.initialEntry;
    if (initial != null) {
      _nameController.text = initial.name;
      _keyspec = initial.keyspec;
      _timelockBlocks = initial.timelockBlocks;
      _isCustomTimelock = initial.timelockBlocks != _k3Months &&
          initial.timelockBlocks != _k6Months &&
          initial.timelockBlocks != _k9Months &&
          initial.timelockBlocks != _k1Year;
    }
    if (_isCustomTimelock) {
      _blocksController.text = _timelockBlocks.toString();
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    _blocksController.dispose();
    super.dispose();
  }

  Future<void> _pickKey() async {
    final result = await showKeyspecSheet(
      context,
      network: widget.network,
      walletType: widget.walletType,
      existingKeyCount: 0,
      existingMfps: widget.existingMfps,
      isMultiPath: true,
    );
    if (result != null && mounted) {
      setState(() => _keyspec = result);
    }
  }

  String _timelockLabel(AppLocalizations l10n) {
    if (_timelockBlocks == _k3Months) return l10n.inheritanceThreeMonths;
    if (_timelockBlocks == _k6Months) return l10n.inheritanceSixMonths;
    if (_timelockBlocks == _k9Months) return l10n.inheritanceNineMonths;
    if (_timelockBlocks == _k1Year) return l10n.inheritanceOneYear;
    return '~${BitcoinFormatter.formatDuration(_timelockBlocks * 10)} ($_timelockBlocks blocks)';
  }

  // Short time approximation for inline use next to the blocks input field.
  String _approxDuration(AppLocalizations l10n) {
    if (_timelockBlocks == _k3Months) return l10n.inheritanceThreeMonthsShort;
    if (_timelockBlocks == _k6Months) return l10n.inheritanceSixMonthsShort;
    if (_timelockBlocks == _k9Months) return l10n.inheritanceNineMonthsShort;
    if (_timelockBlocks == _k1Year) return l10n.inheritanceOneYearShort;
    return '~${BitcoinFormatter.formatDuration(_timelockBlocks * 10)}';
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final canAdd = _keyspec != null;
    final mfp = _keyspec != null
        ? (kKeyspecPattern.firstMatch(_keyspec!.keyspec)?.group(1) ?? '')
        : null;

    return Padding(
      padding: EdgeInsets.only(
        left: 16,
        right: 16,
        top: 16,
        bottom: MediaQuery.viewInsetsOf(context).bottom + 16,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          sheetCloseTitle(
            context,
            _isEditing ? l10n.editHeir : l10n.addHeir,
            onClose: () => Navigator.pop(context),
            tooltip: l10n.cancel,
          ),
          const SizedBox(height: 16),

          // Heir name
          TextField(
            controller: _nameController,
            decoration: InputDecoration(
              labelText: l10n.heirName,
              hintText: l10n.heirNameHint,
              border: const OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 12),

          // Key picker
          Text(l10n.heirKey,
              style: Theme.of(context).textTheme.labelMedium),
          const SizedBox(height: 6),
          if (_keyspec == null)
            OutlinedButton.icon(
              onPressed: _pickKey,
              icon: const Icon(Icons.vpn_key_outlined, size: 16),
              label: Text(l10n.addKeyButton),
            )
          else
            Card(
              margin: EdgeInsets.zero,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                child: Row(
                  children: [
                    MfpBadge(
                      label: mfp!,
                      color: Theme.of(context).colorScheme.tertiary,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: ColoredGroupText(
                        text: kKeyspecPattern
                                .firstMatch(_keyspec!.keyspec)
                                ?.group(3) ??
                            '',
                        fontSize: 12,
                        truncate: true,
                        monospace: true,
                      ),
                    ),
                    IconButton(
                      icon: Icon(Icons.delete_outline,
                          size: 16,
                          color: Colors.red.withAlpha(AppAlpha.deleteAction)),
                      visualDensity: VisualDensity.compact,
                      onPressed: () => setState(() => _keyspec = null),
                    ),
                  ],
                ),
              ),
            ),
          const SizedBox(height: 12),

          // Timelock picker
          Text(l10n.heirTimelockLabel,
              style: Theme.of(context).textTheme.labelMedium),
          const SizedBox(height: 6),
          SizedBox(
            width: double.infinity,
            child: SegmentedButton<int>(
              showSelectedIcon: false,
              segments: [
                ButtonSegment(value: _k3Months, label: Text(l10n.inheritanceThreeMonthsShort)),
                ButtonSegment(value: _k6Months, label: Text(l10n.inheritanceSixMonthsShort)),
                ButtonSegment(value: _k9Months, label: Text(l10n.inheritanceNineMonthsShort)),
                ButtonSegment(value: _k1Year,   label: Text(l10n.inheritanceOneYearShort)),
                const ButtonSegment(value: _kTimelockCustom, label: Text('···')),
              ],
              selected: {_isCustomTimelock ? _kTimelockCustom : _timelockBlocks},
              onSelectionChanged: (sel) {
                final v = sel.first;
                setState(() {
                  if (v == _kTimelockCustom) {
                    _isCustomTimelock = true;
                    _blocksController.text = _timelockBlocks.toString();
                  } else {
                    _timelockBlocks = v;
                    _isCustomTimelock = false;
                  }
                });
              },
            ),
          ),
          const SizedBox(height: 4),
          AnimatedSize(
            duration: const Duration(milliseconds: 180),
            curve: Curves.easeInOut,
            alignment: Alignment.topCenter,
            child: _isCustomTimelock
                ? Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Slider(
                        value: _timelockBlocks.toDouble().clamp(1, 65535),
                        min: 1,
                        max: 65535,
                        divisions: 655,
                        onChanged: (v) {
                          final blocks = v.toInt();
                          setState(() => _timelockBlocks = blocks);
                          _blocksController
                            ..text = blocks.toString()
                            ..selection = TextSelection.collapsed(
                                offset: blocks.toString().length);
                        },
                      ),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          SizedBox(
                            width: 100,
                            child: TextField(
                              controller: _blocksController,
                              keyboardType: TextInputType.number,
                              textAlign: TextAlign.center,
                              decoration: const InputDecoration(
                                isDense: true,
                                contentPadding: EdgeInsets.symmetric(
                                    horizontal: 8, vertical: 8),
                                border: OutlineInputBorder(),
                              ),
                              onChanged: (v) {
                                final parsed = int.tryParse(v);
                                if (parsed != null && parsed >= 1 && parsed <= 65535) {
                                  setState(() => _timelockBlocks = parsed);
                                }
                              },
                            ),
                          ),
                          const SizedBox(width: 8),
                          Text(
                            '${l10n.blocksUnit} (${_approxDuration(l10n)})',
                            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                                ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                    ],
                  )
                : Padding(
                    padding: const EdgeInsets.only(top: 4, bottom: 12),
                    child: Center(
                      child: Text(
                        _timelockLabel(l10n),
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              color: Theme.of(context).colorScheme.onSurfaceVariant,
                            ),
                      ),
                    ),
                  ),
          ),

          // Add button
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: canAdd
                  ? () {
                      final name = _nameController.text.trim();
                      Navigator.pop(
                        context,
                        _HeirEntry(
                          name: name,
                          keyspec: _keyspec!,
                          timelockBlocks: _timelockBlocks,
                        ),
                      );
                    }
                  : null,
              icon: Icon(_isEditing ? Icons.check : Icons.person_add_outlined, size: 18),
              label: Text(_isEditing ? l10n.save : l10n.addHeir),
            ),
          ),
        ],
      ),
    );
  }
}


