import 'dart:async';
import 'package:deadbolt/config/constants.dart' show kMonospaceFontFamily;

import 'package:flutter/gestures.dart' show DragStartBehavior;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show Clipboard;

import 'package:deadbolt/theme/app_theme.dart';
import 'package:deadbolt/cubit/project_detail_cubit.dart';
import 'package:deadbolt/cubit/wallet_detail_cubit.dart';
import 'package:deadbolt/errors.dart';
import 'package:deadbolt/l10n/l10n.dart';
import 'package:deadbolt/src/rust/api/analyzer.dart';
import 'package:deadbolt/src/rust/api/model.dart';
import 'package:deadbolt/utils/toast_helper.dart';
import 'package:deadbolt/widgets/derivation_path_helpers.dart';
import 'package:deadbolt/widgets/dialog_helpers.dart'
    show SheetHandle, sheetCloseTitle, showSheet;
import 'package:deadbolt/widgets/generate_mnemonic_sheet.dart'
    show showGenerateMnemonicSheet;
import 'package:deadbolt/widgets/hw_wallet_sheet.dart' show showHwXpubSheet;
import 'package:deadbolt/widgets/keyspec.dart';
import 'package:deadbolt/widgets/mnemonic_confirm_step.dart';
import 'package:deadbolt/widgets/mnemonic_entry_field.dart';
import 'package:deadbolt/widgets/mnemonic_mfp_preview.dart' show MnemonicMfpPreview, MfpPreview;
import 'package:deadbolt/widgets/text_import_sheet.dart';

export 'package:deadbolt/widgets/keyspec.dart'
    show KeyspecResult, kKeyspecPattern, parseManualKeyspec;

enum _SeedType { mnemonic, xprv }

/// Stage of the picker shown above the form (only in add-new-key mode).
///
/// The flow is:
///   capacity → (watchSources | hotSources) → form
///
/// In wallet mode (`make hot`) the user enters `hotSources` directly.
/// In edit mode the picker is skipped entirely.
enum _PickerStage { capacity, watchSources, hotSources, form }

// ---------------------------------------------------------------------------
// Public entry points
// ---------------------------------------------------------------------------

/// Opens the add/edit-key bottom sheet for a **project** context.
///
/// If [editingKey] is non-null the sheet opens in edit mode, pre-filling
/// fields with the key's current data.  Seed tabs (mnemonic/xprv) will
/// require that the derived MFP matches [editingKey.mfp].
Future<void> showAddKeySheet(
  BuildContext context,
  ProjectDetailCubit cubit, {
  EditableKey? editingKey,
  void Function(String mfp)? onKeyAdded,
}) async {
  final state = cubit.state as ProjectDetailLoaded;
  final network = APINetwork.values.byName(state.project.network);
  final walletType = state.editedWalletType ??
      APIWalletType.values.byName(state.project.walletType);
  final existingMfps =
      state.editedKeys!.map((k) => k.mfp.toLowerCase()).toSet();
  final existingKeyCount = state.editedKeys!.length;

  await showSheet<void>(
    context,
    (ctx) => _AddKeySheet(
      network: network,
      walletType: walletType,
      existingKeyCount: existingKeyCount,
      existingMfps: existingMfps,
      editingKey: editingKey,
      onKeyAdded: onKeyAdded,
      onAddKey: (key) => cubit.addKey(key),
      onUpdateKey: (key) => cubit.updateKey(key),
      onSeedAdded: (mnemonic, passphrase) async {
        await cubit.addProjectMnemonicHotKey(mnemonic, passphrase);
      },
      onXprvSeedAdded: (xprv) async {
        await cubit.addProjectXprvHotKey(xprv);
      },
    ),
    isDismissible: false,
  );
}

// Backward-compat alias used by spend_path_edit_sheet.
void showAddKeyDialog(
  BuildContext context,
  ProjectDetailCubit cubit, {
  void Function(String mfp)? onKeyAdded,
}) =>
    showAddKeySheet(context, cubit, onKeyAdded: onKeyAdded);

/// Opens the "Add private key" bottom sheet for a **wallet** context.
///
/// [expectedMfp] / [keyLabel] identify the watch-only key to make hot.
/// When null the sheet is used for adding a standalone signing key.
/// Returns true if a key was successfully added.
Future<bool> showAddPrivateKeySheet(
  BuildContext context, {
  required WalletDetailCubit cubit,
  String? expectedMfp,
  String? keyLabel,
}) async {
  final state = cubit.state;
  final network = state is WalletDetailLoaded
      ? state.walletInfo.network
      : APINetwork.testnet;

  final result = await showSheet<bool>(
    context,
    (ctx) => _AddKeySheet(
      network: network,
      walletMode: true,
      expectedMfp: expectedMfp,
      keyLabel: keyLabel,
      onAddMnemonic: (mnemonic, passphrase) =>
          cubit.addMnemonicKey(mnemonic, passphrase),
      onAddXprv: (xprv) => cubit.addXprvKey(xprv),
    ),
    isDismissible: false,
  );
  return result ?? false;
}

/// Opens the key input sheet to collect a single keyspec string.
///
/// Supports all input methods (manual xpub, mnemonic, xprv, import, hardware
/// wallet). Does NOT store anything — returns a [KeyspecResult] with the
/// keyspec and, if the user entered a seed, the mnemonic/passphrase/xprv so
/// callers can store a hot key. Returns null if the user cancelled.
Future<KeyspecResult?> showKeyspecSheet(
  BuildContext context, {
  required APINetwork network,
  required APIWalletType walletType,
  int existingKeyCount = 0,
  Set<String> existingMfps = const {},
  bool isMultiPath = false,
}) {
  return showSheet<KeyspecResult>(
    context,
    (ctx) => _AddKeySheet(
      network: network,
      walletType: walletType,
      existingKeyCount: existingKeyCount,
      existingMfps: existingMfps,
      isMultiPath: isMultiPath,
      keyspecMode: true,
    ),
    isDismissible: false,
  );
}

/// Opens the "Add private key" bottom sheet for a **project** context.
///
/// Stores the seed in the encrypted project_seeds.db via [cubit].
/// [expectedMfp] constrains which key is being made hot.
Future<bool> showAddProjectPrivateKeySheet(
  BuildContext context, {
  required ProjectDetailCubit cubit,
  required String expectedMfp,
  String? keyLabel,
}) async {
  final state = cubit.state as ProjectDetailLoaded;
  final network = APINetwork.values.byName(state.project.network);

  final result = await showSheet<bool>(
    context,
    (ctx) => _AddKeySheet(
      network: network,
      walletMode: true,
      expectedMfp: expectedMfp,
      keyLabel: keyLabel,
      onAddMnemonic: (mnemonic, passphrase) =>
          cubit.addProjectMnemonicHotKey(mnemonic, passphrase),
      onAddXprv: (xprv) => cubit.addProjectXprvHotKey(xprv),
    ),
    isDismissible: false,
  );
  return result ?? false;
}

// ---------------------------------------------------------------------------

class _AddKeySheet extends StatefulWidget {
  // Context data (project mode)
  final APINetwork network;
  final APIWalletType? walletType;
  final int existingKeyCount;
  final Set<String> existingMfps;

  // Edit mode
  final EditableKey? editingKey;
  final void Function(String mfp)? onKeyAdded;

  // Project callbacks
  final Future<void> Function(EditableKey key)? onAddKey;
  final Future<void> Function(EditableKey key)? onUpdateKey;
  final Future<void> Function(String mnemonic, String? passphrase)? onSeedAdded;
  final Future<void> Function(String xprv)? onXprvSeedAdded;

  // Wallet mode
  final bool walletMode;
  final String? expectedMfp;
  final String? keyLabel;
  final Future<APIHotKeyInfo?> Function(String mnemonic, String? passphrase)?
      onAddMnemonic;
  final Future<APIHotKeyInfo?> Function(String xprv)? onAddXprv;

  // Multi-path context (e.g. inheritance): forces BIP48/Taproot derivation path
  final bool isMultiPath;

  // Keyspec-only mode: pops with "[mfp/path]xpub" string instead of void
  final bool keyspecMode;

  const _AddKeySheet({
    required this.network,
    this.walletType,
    this.existingKeyCount = 0,
    this.existingMfps = const {},
    this.editingKey,
    this.onKeyAdded,
    this.onAddKey,
    this.onUpdateKey,
    this.onSeedAdded,
    this.onXprvSeedAdded,
    this.walletMode = false,
    this.expectedMfp,
    this.keyLabel,
    this.onAddMnemonic,
    this.onAddXprv,
    this.isMultiPath = false,
    this.keyspecMode = false,
  });

  @override
  State<_AddKeySheet> createState() => _AddKeySheetState();
}

class _AddKeySheetState extends State<_AddKeySheet> {
  _SeedType _seedType = _SeedType.mnemonic;
  late _PickerStage _stage;
  String? _errorText;

  // --- Mnemonic ---
  final _mnemonicController = TextEditingController();

  // --- xprv ---
  final _xprvController = TextEditingController();

  KeyspecResult? _capturedKeyspecResult;
  MfpPreview? _capturedMfpPreview;

  bool get _isEditMode => widget.editingKey != null;

  @override
  void initState() {
    super.initState();
    _mnemonicController.addListener(_onMnemonicChanged);
    _stage = _isEditMode
        ? _PickerStage.form
        : (widget.walletMode
            ? _PickerStage.hotSources
            : _PickerStage.capacity);
  }

  @override
  void dispose() {
    _mnemonicController.removeListener(_onMnemonicChanged);
    _mnemonicController.dispose();
    _xprvController.dispose();
    super.dispose();
  }

  void _onMnemonicChanged() {
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;

    return ConstrainedBox(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.sizeOf(context).height * 0.90,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SheetHandle(),
          Flexible(
            child: Padding(
              padding: EdgeInsets.fromLTRB(
                  16, 0, 16, 16 + MediaQuery.viewInsetsOf(context).bottom),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
          // Title row with optional back + close button
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (_stage == _PickerStage.watchSources ||
                  (_stage == _PickerStage.hotSources && !widget.walletMode))
                IconButton(
                  icon: const Icon(Icons.arrow_back),
                  tooltip: l10n.cancel,
                  visualDensity: VisualDensity.compact,
                  onPressed: () => setState(() {
                    _stage = _PickerStage.capacity;
                    _errorText = null;
                  }),
                ),
              Expanded(
                child: _isEditMode || widget.walletMode
                    ? Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            widget.walletMode
                                ? (widget.expectedMfp != null
                                    ? l10n.addPrivateKeyLabel
                                    : l10n.addSigningKeyLabel)
                                : l10n.editKeyTitle,
                            style: Theme.of(context).textTheme.titleLarge,
                          ),
                          if (widget.walletMode && widget.expectedMfp != null)
                            Text(
                              widget.keyLabel != null &&
                                      widget.keyLabel!.isNotEmpty
                                  ? '${widget.keyLabel} · ${widget.expectedMfp}'
                                  : 'Key: ${widget.expectedMfp}',
                              style: TextStyle(
                                fontSize: 12,
                                fontFamily: kMonospaceFontFamily,
                                color: Theme.of(context).colorScheme.secondary,
                              ),
                            )
                          else if (_isEditMode)
                            Text(
                              widget.editingKey!.mfp.toUpperCase(),
                              style: TextStyle(
                                fontSize: 12,
                                fontFamily: kMonospaceFontFamily,
                                color: Theme.of(context).colorScheme.secondary,
                              ),
                            ),
                        ],
                      )
                    : Text(
                        l10n.addKeyDialogTitle,
                        style: Theme.of(context).textTheme.titleLarge,
                      ),
              ),
              IconButton(
                icon: const Icon(Icons.close),
                tooltip: l10n.cancel,
                visualDensity: VisualDensity.compact,
                onPressed: () => Navigator.pop(context),
              ),
            ],
          ),
          const SizedBox(height: 12),

          if (_stage == _PickerStage.capacity)
            _buildCapacityPicker(l10n)
          else if (_stage == _PickerStage.watchSources)
            _buildWatchSourcesPicker(l10n)
          else if (_stage == _PickerStage.hotSources)
            _buildHotSourcesPicker(l10n)
          else ...[
            Flexible(
              child: SingleChildScrollView(
                dragStartBehavior: DragStartBehavior.down,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildSeedForm(),
                  ],
                ),
              ),
            ),
            if (_errorText != null)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(
                  _errorText!,
                  style: const TextStyle(color: Colors.red, fontSize: 12),
                ),
              ),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: _submit,
                child: Text(
                  widget.walletMode || _isEditMode
                      ? l10n.addPrivateKeyLabel
                      : l10n.add,
                ),
              ),
            ),
          ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// Step 1: pick between Watch-only and Hot.
  Widget _buildCapacityPicker(AppLocalizations l10n) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        _MethodTile(
          key: const ValueKey('addKeyCapacity_watchOnly'),
          icon: Icons.visibility_outlined,
          title: l10n.addKeyCapacityWatchOnlyTitle,
          subtitle: l10n.addKeyCapacityWatchOnlySubtitle,
          onTap: () => setState(() {
            _stage = _PickerStage.watchSources;
            _errorText = null;
          }),
        ),
        const SizedBox(height: 8),
        _MethodTile(
          key: const ValueKey('addKeyCapacity_hot'),
          icon: Icons.local_fire_department_outlined,
          title: l10n.addKeyCapacityHotTitle,
          subtitle: l10n.addKeyCapacityHotSubtitle,
          onTap: () => setState(() {
            _stage = _PickerStage.hotSources;
            _errorText = null;
          }),
        ),
        if (_errorText != null) ...[
          const SizedBox(height: 8),
          Text(
            _errorText!,
            style: const TextStyle(color: Colors.red, fontSize: 12),
          ),
        ],
      ],
    );
  }

  /// Step 2a: Watch-only sources. Paste / Scan / File / Hardware + a small
  /// secondary link to type the MFP/path/xpub fields by hand.
  Widget _buildWatchSourcesPicker(AppLocalizations l10n) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _MethodTile(
          key: const ValueKey('addKeyWatch_paste'),
          icon: Icons.content_paste_outlined,
          title: l10n.addKeyWatchSourcePasteTitle,
          subtitle: l10n.addKeyWatchSourcePasteSubtitle,
          onTap: _onWatchManualEntry,
        ),
        const SizedBox(height: 8),
        _MethodTile(
          key: const ValueKey('addKeyWatch_scan'),
          icon: Icons.qr_code_scanner,
          title: l10n.addKeyWatchSourceScanTitle,
          subtitle: l10n.addKeyWatchSourceScanSubtitle,
          onTap: () => _onWatchTextSource(TextImportAction.qr),
        ),
        const SizedBox(height: 8),
        _MethodTile(
          key: const ValueKey('addKeyWatch_file'),
          icon: Icons.file_open_outlined,
          title: l10n.addKeyWatchSourceFileTitle,
          subtitle: l10n.addKeyWatchSourceFileSubtitle,
          onTap: () => _onWatchTextSource(TextImportAction.file),
        ),
        const SizedBox(height: 8),
        _MethodTile(
          key: const ValueKey('addKeyWatch_hw'),
          icon: Icons.hardware,
          title: l10n.addKeyWatchSourceHwTitle,
          subtitle: l10n.addKeyWatchSourceHwSubtitle,
          onTap: _onHardwareTapped,
        ),
        if (_errorText != null) ...[
          const SizedBox(height: 8),
          Text(
            _errorText!,
            style: const TextStyle(color: Colors.red, fontSize: 12),
          ),
        ],
      ],
    );
  }

  /// Step 2b: Hot key sources. Generate / Enter mnemonic / Enter xprv.
  ///
  /// Generate is hidden in wallet mode ("make hot" requires the seed of a
  /// specific existing watch-only key — generating a new one would never match
  /// the expected MFP).
  Widget _buildHotSourcesPicker(AppLocalizations l10n) {
    final canGenerate = !widget.walletMode && widget.walletType != null;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (canGenerate) ...[
          _MethodTile(
            key: const ValueKey('addKeyHot_generate'),
            icon: Icons.casino_outlined,
            title: l10n.addKeyHotSourceGenerateTitle,
            subtitle: l10n.addKeyHotSourceGenerateSubtitle,
            onTap: _onGenerateMnemonicTapped,
          ),
          const SizedBox(height: 8),
        ],
        _MethodTile(
          key: const ValueKey('addKeyHot_mnemonic'),
          icon: Icons.password,
          title: l10n.addKeyHotSourceExistingTitle,
          subtitle: l10n.addKeyHotSourceExistingSubtitle,
          onTap: () => setState(() {
            _stage = _PickerStage.form;
            _seedType = _SeedType.mnemonic;
            _errorText = null;
          }),
        ),
        const SizedBox(height: 8),
        _MethodTile(
          key: const ValueKey('addKeyHot_xprv'),
          icon: Icons.vpn_key_outlined,
          title: l10n.addKeyHotSourceXprvTitle,
          subtitle: l10n.addKeyHotSourceXprvSubtitle,
          onTap: () => setState(() {
            _stage = _PickerStage.form;
            _seedType = _SeedType.xprv;
            _errorText = null;
          }),
        ),
        if (_errorText != null) ...[
          const SizedBox(height: 8),
          Text(
            _errorText!,
            style: const TextStyle(color: Colors.red, fontSize: 12),
          ),
        ],
      ],
    );
  }

  /// Opens the manual entry dialog (accepts either `[mfp/path]xpub` or three
  /// loose tokens in any order). Pipes parsed parts to [_addKeyFromParts].
  Future<void> _onWatchManualEntry() async {
    final parts = await _showManualKeyspecDialog(context);
    if (parts == null || !mounted) return;
    await _addKeyFromParts(
      parts.mfp.toLowerCase(),
      parts.path,
      parts.xpub,
    );
  }

  /// Generic text-import path: paste / scan QR / load file. The caller chooses
  /// the source via [action]; the parsed keyspec is then handed to
  /// [_addKeyFromParts].
  Future<void> _onWatchTextSource(TextImportAction action) async {
    final result = await showTextImportSheet(context, initialAction: action);
    if (result == null || !mounted) return;
    final match = kKeyspecPattern.firstMatch(result.trim());
    if (match == null) {
      setState(() {
        _stage = _PickerStage.watchSources;
        _errorText = context.l10n.invalidKeyspecFormat;
      });
      return;
    }
    await _addKeyFromParts(
      match.group(1)!.toLowerCase(),
      match.group(2)!,
      match.group(3)!,
    );
  }

  Future<void> _onGenerateMnemonicTapped() async {
    if (widget.walletType == null) return;
    final result = await showGenerateMnemonicSheet(
      context,
      network: widget.network,
      walletType: widget.walletType!,
      existingKeyCount: widget.existingKeyCount,
      isMultiPath: widget.isMultiPath,
    );
    if (result == null || !mounted) return;
    final match = kKeyspecPattern.firstMatch(result.keyspec);
    if (match == null) {
      setState(() {
        _stage = _PickerStage.hotSources;
        _errorText = context.l10n.invalidKeyspecFormat;
      });
      return;
    }
    await _addKeyFromParts(
      match.group(1)!.toLowerCase(),
      match.group(2)!,
      match.group(3)!,
      seedMnemonic: result.mnemonic,
      seedPassphrase: result.passphrase,
      seedXprv: result.xprv,
    );
  }

  Future<void> _onHardwareTapped() async {
    final suggested = widget.walletType != null
        ? defaultDerivationPath(
            widget.walletType!,
            widget.network,
            widget.existingKeyCount,
            isMultiPath: widget.isMultiPath,
          )
        : "m/86'/0'/0'";
    final path = await showDerivationPathPicker(context, suggested);
    if (path == null || !mounted) return;
    final keyspec = await showHwXpubSheet(
      context,
      derivationPath: path,
      network: widget.network,
    );
    if (keyspec == null || !mounted) return;
    final match = kKeyspecPattern.firstMatch(keyspec.trim());
    if (match == null) {
      setState(() {
        _stage = _PickerStage.watchSources;
        _errorText = context.l10n.invalidKeyspecFormat;
      });
      return;
    }
    await _addKeyFromParts(
      match.group(1)!.toLowerCase(),
      match.group(2)!,
      match.group(3)!,
    );
  }

  Future<void> _addKeyFromParts(String mfp, String path, String xpub,
      {String? seedMnemonic, String? seedPassphrase, String? seedXprv}) async {
    // In edit mode validate MFP matches
    if (_isEditMode && mfp != widget.editingKey!.mfp.toLowerCase()) {
      setState(() => _errorText = context.l10n.mfpMismatch(
          mfp, widget.editingKey!.mfp.toLowerCase()));
      return;
    }

    // In add mode check for duplicate MFP
    if (!_isEditMode && widget.existingMfps.contains(mfp)) {
      setState(() => _errorText = context.l10n.duplicateMfp(mfp));
      return;
    }

    // Validate key with Rust
    try {
      await validateKey(
        mfp: mfp,
        derivationPath: path,
        xpub: xpub,
        network: widget.network,
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _errorText = formatRustError(e));
      return;
    }

    if (!mounted) return;

    final key = EditableKey(
      originalDbId: widget.editingKey?.originalDbId,
      mfp: mfp,
      derivationPath: path,
      xpub: xpub,
      customName: widget.editingKey?.customName,
    );

    if (widget.keyspecMode) {
      Navigator.pop<KeyspecResult>(context, (
        keyspec: '[$mfp/$path]$xpub',
        mnemonic: seedMnemonic,
        passphrase: seedPassphrase,
        xprv: seedXprv,
      ));
      return;
    }

    if (_isEditMode) {
      await widget.onUpdateKey!(key);
    } else {
      await widget.onAddKey!(key);
      if (seedMnemonic != null && widget.onSeedAdded != null) {
        if (!mounted) return;
        await widget.onSeedAdded!(seedMnemonic, seedPassphrase);
      } else if (seedXprv != null && widget.onXprvSeedAdded != null) {
        if (!mounted) return;
        await widget.onXprvSeedAdded!(seedXprv);
      }
    }

    if (!mounted) return;
    widget.onKeyAdded?.call(mfp);
    Navigator.pop(context);
  }

  Future<void> _submit() async {
    if (widget.walletMode) {
      await _submitWallet();
      return;
    }
    setState(() => _errorText = null);

    final result = _capturedKeyspecResult;
    if (result == null || result.keyspec.isEmpty) {
      setState(() => _errorText = context.l10n.deriveKeyFirst);
      return;
    }
    final match = kKeyspecPattern.firstMatch(result.keyspec);
    if (match == null) {
      setState(() => _errorText = context.l10n.invalidDerivedKeyspec);
      return;
    }
    final mfp = match.group(1)!.toLowerCase();
    final path = match.group(2)!;
    final xpub = match.group(3)!;

    String? seedMnemonic;
    String? seedPassphrase;
    String? seedXprv;
    if (_seedType == _SeedType.mnemonic) {
      seedMnemonic = _mnemonicController.text.trim();
      seedPassphrase = _capturedKeyspecResult?.passphrase;
    } else {
      seedXprv = _xprvController.text.trim();
    }

    await _addKeyFromParts(mfp, path, xpub,
        seedMnemonic: seedMnemonic,
        seedPassphrase: seedPassphrase,
        seedXprv: seedXprv);
  }

  Future<void> _submitWallet() async {
    setState(() => _errorText = null);

    if (_seedType == _SeedType.mnemonic) {
      if (_capturedMfpPreview == null) {
        setState(() => _errorText = context.l10n.enterValidSeedPhrase);
        return;
      }
      final result = await widget.onAddMnemonic!(
        _mnemonicController.text.trim(),
        _capturedMfpPreview!.passphrase.isEmpty
            ? null
            : _capturedMfpPreview!.passphrase,
      );
      if (!mounted) return;
      if (result != null) {
        showSuccessToast(context.l10n.signingKeyAdded(result.mfp));
        Navigator.pop(context, true);
      }
      // On null: cubit already emitted error toast via BlocListener.
    } else {
      final xprv = _xprvController.text.trim();
      if (xprv.isEmpty) {
        setState(() => _errorText = context.l10n.enterXprvKey);
        return;
      }
      final result = await widget.onAddXprv!(xprv);
      if (!mounted) return;
      if (result != null) {
        showSuccessToast(context.l10n.signingKeyAdded(result.mfp));
        Navigator.pop(context, true);
      }
    }
  }

  Widget _buildSeedForm() {
    // Wallet mode: simplified — no derivation path, MFP preview only
    if (widget.walletMode) {
      return _buildWalletSeedForm();
    }

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (_isEditMode) ...[
          Text(
            'Must match MFP: ${widget.editingKey!.mfp.toUpperCase()}',
            style: TextStyle(
              fontSize: 12,
              color: Theme.of(context).colorScheme.secondary,
              fontFamily: kMonospaceFontFamily,
            ),
          ),
          const SizedBox(height: 8),
        ],
        if (_isEditMode) ...[
          SizedBox(
            width: double.infinity,
            child: SegmentedButton<_SeedType>(
              showSelectedIcon: false,
              segments: const [
                ButtonSegment(
                    value: _SeedType.mnemonic,
                    label: Text('Mnemonic'),
                    icon: Icon(Icons.password, size: 16)),
                ButtonSegment(
                    value: _SeedType.xprv,
                    label: Text('xprv'),
                    icon: Icon(Icons.vpn_key_outlined, size: 16)),
              ],
              selected: {_seedType},
              onSelectionChanged: (s) => setState(() {
                _seedType = s.first;
                _capturedKeyspecResult = null;
              }),
              style: const ButtonStyle(visualDensity: VisualDensity.compact),
            ),
          ),
          const SizedBox(height: 12),
        ],
        if (_seedType == _SeedType.mnemonic) ...[
          MnemonicEntryField(controller: _mnemonicController),
          const SizedBox(height: 12),
          MnemonicConfirmStep(
            mnemonic: _mnemonicController.text.trim(),
            network: widget.network,
            walletType: widget.walletType,
            existingKeyCount: widget.existingKeyCount,
            isMultiPath: widget.isMultiPath,
            showAccountStepper: widget.keyspecMode && widget.walletType != null,
            requiredMfp: _isEditMode ? widget.editingKey!.mfp : null,
            onResultChanged: (result) {
              setState(() => _capturedKeyspecResult = result);
            },
          ),
        ] else ...[
          TextField(
            controller: _xprvController,
            maxLines: 2,
            decoration: const InputDecoration(
              border: OutlineInputBorder(),
              labelText: 'Master xprv (depth 0)',
              hintText: 'xprv...',
            ),
          ),
        ],
      ],
    );
  }

  /// Seed form in wallet mode: no derivation path, MFP preview instead.
  ///
  /// The seed type (mnemonic / xprv) is preselected by the Hot sources picker
  /// tile the user tapped, so the inner toggle is omitted.
  Widget _buildWalletSeedForm() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (_seedType == _SeedType.mnemonic) ...[
          MnemonicEntryField(controller: _mnemonicController),
          const SizedBox(height: 12),
          MnemonicMfpPreview(
            mnemonic: _mnemonicController.text.trim(),
            network: widget.network,
            expectedMfp: widget.expectedMfp,
            onMfpChanged: (preview) {
              setState(() => _capturedMfpPreview = preview);
            },
          ),
        ] else ...[
          TextField(
            controller: _xprvController,
            maxLines: 2,
            decoration: const InputDecoration(
              border: OutlineInputBorder(),
              labelText: 'Master xprv (depth 0)',
              hintText: 'xprv...',
            ),
          ),
        ],
        const SizedBox(height: 12),
      ],
    );
  }

}

// ---------------------------------------------------------------------------

/// Shows a bottom sheet with a single multi-line text field that accepts
/// either a `[mfp/path]xpub` keyspec or three loose tokens (mfp, path, xpub)
/// detected by content. The field offers a paste suffix icon.
Future<({String mfp, String path, String xpub})?> _showManualKeyspecDialog(
  BuildContext context,
) async {
  final result = await showSheet<({String mfp, String path, String xpub})>(
    context,
    (ctx) => const _ManualKeyspecSheet(),
    isDismissible: false,
  );
  return result;
}

class _ManualKeyspecSheet extends StatefulWidget {
  const _ManualKeyspecSheet();

  @override
  State<_ManualKeyspecSheet> createState() => _ManualKeyspecSheetState();
}

class _ManualKeyspecSheetState extends State<_ManualKeyspecSheet> {
  final _controller = TextEditingController();
  String? _errorText;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _paste() async {
    final data = await Clipboard.getData('text/plain');
    final text = data?.text;
    if (text == null || text.isEmpty) return;
    _controller.text = text;
    _controller.selection = TextSelection.collapsed(
      offset: _controller.text.length,
    );
  }

  void _submit() {
    final parsed = parseManualKeyspec(_controller.text);
    if (parsed == null) {
      setState(() => _errorText = context.l10n.addKeyManualFormatError);
      return;
    }
    Navigator.pop(context, parsed);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final media = MediaQuery.of(context);

    return Padding(
      padding: EdgeInsets.only(bottom: media.viewInsets.bottom),
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: media.size.height * 0.9),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            sheetCloseTitle(
              context,
              l10n.addKeyManualDialogTitle,
              onClose: () => Navigator.pop(context),
            ),
            Flexible(
              child: SingleChildScrollView(
                dragStartBehavior: DragStartBehavior.down,
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    TextField(
                      controller: _controller,
                      autofocus: true,
                      maxLines: 6,
                      minLines: 4,
                      dragStartBehavior: DragStartBehavior.down,
                      style: const TextStyle(
                        fontFamily: kMonospaceFontFamily,
                        fontSize: 13,
                      ),
                      decoration: InputDecoration(
                        hintText: l10n.addKeyManualHint,
                        hintStyle: TextStyle(
                          fontFamily: kMonospaceFontFamily,
                          fontSize: 12,
                          color:
                              Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                        border: const OutlineInputBorder(),
                        errorText: _errorText,
                        suffixIcon: IconButton(
                          icon: const Icon(Icons.paste_outlined, size: 20),
                          tooltip: l10n.pasteFromClipboard,
                          onPressed: _paste,
                        ),
                      ),
                      onChanged: (_) {
                        if (_errorText != null) {
                          setState(() => _errorText = null);
                        }
                      },
                    ),
                    const SizedBox(height: 16),
                    SizedBox(
                      width: double.infinity,
                      child: FilledButton(
                        onPressed: _submit,
                        child: Text(l10n.confirm),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _MethodTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  const _MethodTile({
    super.key,
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(
          border: Border.all(color: cs.outlineVariant),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          children: [
            Icon(icon, size: 24, color: cs.primary),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title,
                      style:
                          const TextStyle(fontWeight: FontWeight.w600)),
                  Text(subtitle,
                      style: TextStyle(
                          fontSize: 12,
                          color: cs.onSurface.withAlpha(AppAlpha.secondary))),
                ],
              ),
            ),
            Icon(Icons.arrow_forward_ios,
                size: 16, color: cs.onSurface.withAlpha(AppAlpha.border)),
          ],
        ),
      ),
    );
  }
}
