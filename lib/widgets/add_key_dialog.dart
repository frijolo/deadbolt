import 'dart:async';

import 'package:flutter/gestures.dart' show DragStartBehavior;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:deadbolt/theme/app_theme.dart';
import 'package:deadbolt/cubit/project_detail_cubit.dart';
import 'package:deadbolt/cubit/wallet_detail_cubit.dart';
import 'package:deadbolt/errors.dart';
import 'package:deadbolt/l10n/l10n.dart';
import 'package:deadbolt/src/rust/api/analyzer.dart';
import 'package:deadbolt/src/rust/api/model.dart';
import 'package:deadbolt/src/rust/api/wallet.dart'
    show deriveKeyspec, deriveKeyspecFromXprv, validateMnemonic;
import 'package:deadbolt/utils/toast_helper.dart';
import 'package:deadbolt/widgets/dialog_helpers.dart' show SheetHandle, showSheet;
import 'package:deadbolt/widgets/hw_wallet_sheet.dart' show showHwXpubSheet;
import 'package:deadbolt/widgets/mnemonic_entry_field.dart';
import 'package:deadbolt/widgets/text_import_sheet.dart';

/// Pattern for parsing keyspec format: [mfp/path]xpub
final kKeyspecPattern = RegExp(r'^\[([0-9a-fA-F]{8})/([^\]]+)\](.+)$');

/// Result returned by [showKeyspecSheet].
/// [keyspec] is always populated; [mnemonic]/[passphrase]/[xprv] are set only
/// when the user entered the key via seed — allowing callers to store a hot key.
typedef KeyspecResult = ({
  String keyspec,
  String? mnemonic,
  String? passphrase,
  String? xprv,
});

/// Returns the standard BIP derivation path for the given wallet type and network.
///
/// For P2TR:
/// - [isMultiPath] = true (e.g. inheritance/miniscript) → always m/48'/.../2'
/// - [isMultiPath] = false: [existingKeyCount] = 0 → m/86' (single-sig),
///   [existingKeyCount] > 0 → m/48'/.../2' (multi-signer)
/// [accountIndex] selects the BIP44 account level (default 0).
String _defaultDerivationPath(
  APIWalletType walletType,
  APINetwork network,
  int existingKeyCount, {
  bool isMultiPath = false,
  int accountIndex = 0,
}) {
  final coin = network == APINetwork.bitcoin ? '0' : '1';
  final a = "$accountIndex'";
  return switch (walletType) {
    APIWalletType.p2Pkh => "m/44'/$coin'/$a",
    APIWalletType.p2Wpkh => "m/84'/$coin'/$a",
    APIWalletType.p2Sh || APIWalletType.p2ShWpkh => "m/49'/$coin'/$a",
    APIWalletType.p2Wsh || APIWalletType.p2ShWsh => "m/48'/$coin'/$a/1'",
    APIWalletType.p2Tr =>
      (isMultiPath || existingKeyCount > 0) ? "m/48'/$coin'/$a/2'" : "m/86'/$coin'/$a",
    APIWalletType.unknown => "m/86'/$coin'/$a",
  };
}

Future<String?> _showDerivationPathPicker(
  BuildContext context,
  String initialPath,
) async {
  final controller = TextEditingController(text: initialPath);
  return showDialog<String>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(context.l10n.keyDerivPathLabel),
      content: TextField(
        controller: controller,
        autofocus: true,
        decoration: const InputDecoration(hintText: "m/86'/0'/0'"),
        style: const TextStyle(fontFamily: 'monospace'),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx),
          child: Text(context.l10n.cancel),
        ),
        FilledButton(
          onPressed: () {
            final path = controller.text.trim();
            if (path.isNotEmpty) Navigator.pop(ctx, path);
          },
          child: Text(context.l10n.confirm),
        ),
      ],
    ),
  );
}

/// Quick-path suggestion for the seed tabs.
class _QuickPath {
  final String path;
  final String label;
  const _QuickPath(this.path, this.label);
}

List<_QuickPath> _quickPaths(
  APIWalletType? walletType,
  APINetwork network, {
  bool isMultiPath = false,
}) {
  final coin = network == APINetwork.bitcoin ? '0' : '1';
  final paths = <_QuickPath>[];

  if (walletType == null || walletType == APIWalletType.p2Wpkh) {
    paths.add(_QuickPath("84'/$coin'/0'", 'BIP84 (Native SegWit)'));
  }
  if (walletType == null || walletType == APIWalletType.p2Tr) {
    if (!isMultiPath) {
      paths.add(_QuickPath("86'/$coin'/0'", 'BIP86 (Taproot single-sig)'));
    }
    paths.add(_QuickPath("48'/$coin'/0'/2'", 'BIP48 multisig (Taproot)'));
  }
  if (walletType == null ||
      walletType == APIWalletType.p2Wsh ||
      walletType == APIWalletType.p2ShWsh) {
    paths.add(_QuickPath("48'/$coin'/0'/2'", 'BIP48 multisig (Native SegWit)'));
    paths.add(_QuickPath("48'/$coin'/0'/1'", 'BIP48 multisig (P2SH-SegWit)'));
  }
  if (walletType == null || walletType == APIWalletType.p2Sh) {
    paths.add(_QuickPath("49'/$coin'/0'", 'BIP49 (P2SH-SegWit)'));
  }
  if (walletType == null || walletType == APIWalletType.p2Pkh) {
    paths.add(_QuickPath("44'/$coin'/0'", 'BIP44 (Legacy)'));
  }

  final seen = <String>{};
  return paths.where((p) => seen.add(p.path)).toList();
}

enum _AddKeyTab { separateFields, seed }

enum _SeedType { mnemonic, xprv }

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
  late _AddKeyTab _tab;
  _SeedType _seedType = _SeedType.mnemonic;
  bool _showMethodPicker = false;
  String? _errorText;

  // --- Separate fields ---
  final _mfpController = TextEditingController();
  final _pathSepController = TextEditingController();
  final _xpubController = TextEditingController();

  // --- Mnemonic ---
  final _mnemonicController = TextEditingController();
  final _passphraseController = TextEditingController();
  bool _showPassphrase = false;

  // --- xprv ---
  final _xprvController = TextEditingController();

  // --- Account index (keyspec mode only, for seed tab) ---
  int _accountIndex = 0;

  // --- Shared: derivation path for mnemonic/xprv tabs (project mode only) ---
  late final TextEditingController _derivPathController;

  // --- Live-derive state (project mode: full keyspec) ---
  String? _derivedKeyspec;
  String? _deriveError;
  bool _deriving = false;
  Timer? _debounce;

  // --- Wallet mode: MFP preview via validateMnemonic ---
  String? _walletMfp;
  String? _walletMfpError;
  bool _walletValidating = false;
  Timer? _walletDebounce;

  bool get _isEditMode => widget.editingKey != null;

  @override
  void initState() {
    super.initState();
    _tab = (widget.walletMode || _isEditMode)
        ? _AddKeyTab.seed
        : _AddKeyTab.separateFields;
    _showMethodPicker = !_isEditMode && !widget.walletMode;

    if (_isEditMode) {
      final k = widget.editingKey!;
      _mfpController.text = k.mfp;
      _pathSepController.text = k.derivationPath;
      _xpubController.text = k.xpub;
    }

    final paths = _quickPaths(widget.walletType, widget.network,
        isMultiPath: widget.isMultiPath);
    final suggested = widget.walletType != null
        ? _defaultDerivationPath(
            widget.walletType!,
            widget.network,
            widget.existingKeyCount,
            isMultiPath: widget.isMultiPath,
          ).replaceFirst('m/', '')
        : '';
    _derivPathController = TextEditingController(
      text: widget.editingKey?.derivationPath.isNotEmpty == true
          ? widget.editingKey!.derivationPath.replaceFirst('m/', '')
          : suggested.isNotEmpty
              ? suggested
              : (paths.isNotEmpty ? paths.first.path : "84'/0'/0'"),
    );

    if (!widget.walletMode) {
      _mnemonicController.addListener(_scheduleDerive);
      _passphraseController.addListener(_scheduleDerive);
      _xprvController.addListener(_scheduleDerive);
      _derivPathController.addListener(_scheduleDerive);
    } else {
      _mnemonicController.addListener(_scheduleWalletValidate);
      _passphraseController.addListener(_scheduleWalletValidate);
    }
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _walletDebounce?.cancel();
    _mfpController.dispose();
    _pathSepController.dispose();
    _xpubController.dispose();
    _mnemonicController.dispose();
    _passphraseController.dispose();
    _xprvController.dispose();
    _derivPathController.dispose();
    super.dispose();
  }

  // --- Account index stepper ---

  void _setAccountIndex(int i) {
    if (!widget.keyspecMode) return;
    setState(() => _accountIndex = i);
    if (widget.walletType != null) {
      _derivPathController.text = _defaultDerivationPath(
        widget.walletType!,
        widget.network,
        widget.existingKeyCount,
        isMultiPath: widget.isMultiPath,
        accountIndex: _accountIndex,
      ).replaceFirst('m/', '');
    }
  }

  // --- Project mode: live derive full keyspec ---

  void _scheduleDerive() {
    if (_tab != _AddKeyTab.seed) return;
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 500), _derive);
  }

  Future<void> _derive() async {
    if (!mounted) return;
    final path = _derivPathController.text.trim();
    if (path.isEmpty) return;

    if (_seedType == _SeedType.mnemonic) {
      if (!_isValidWordCount) {
        setState(() {
          _derivedKeyspec = null;
          _deriveError = null;
        });
        return;
      }
    } else {
      if (_xprvController.text.trim().isEmpty) {
        setState(() {
          _derivedKeyspec = null;
          _deriveError = null;
        });
        return;
      }
    }

    setState(() {
      _deriving = true;
      _deriveError = null;
    });

    try {
      final String keyspec;
      if (_seedType == _SeedType.mnemonic) {
        keyspec = await deriveKeyspec(
          mnemonic: _mnemonicController.text.trim(),
          passphrase: _passphraseController.text.isEmpty
              ? null
              : _passphraseController.text,
          derivationPath: path,
          network: widget.network,
        );
      } else {
        keyspec = await deriveKeyspecFromXprv(
          xprvStr: _xprvController.text.trim(),
          derivationPath: path,
        );
      }
      if (!mounted) return;
      setState(() {
        _derivedKeyspec = keyspec;
        _deriving = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _deriveError = formatRustError(e);
        _derivedKeyspec = null;
        _deriving = false;
      });
    }
  }

  // --- Wallet mode: validate mnemonic for MFP preview ---

  void _scheduleWalletValidate() {
    _walletDebounce?.cancel();
    _walletDebounce = Timer(
      const Duration(milliseconds: 500),
      _validateMnemonicForWallet,
    );
  }

  Future<void> _validateMnemonicForWallet() async {
    if (!mounted) return;
    if (!_isValidWordCount) {
      setState(() {
        _walletMfp = null;
        _walletMfpError = null;
        _walletValidating = false;
      });
      return;
    }
    setState(() {
      _walletValidating = true;
      _walletMfpError = null;
    });
    try {
      final info = await validateMnemonic(
        mnemonic: _mnemonicController.text.trim(),
        passphrase: _passphraseController.text.isEmpty
            ? null
            : _passphraseController.text,
        network: widget.network,
      );
      if (!mounted) return;
      setState(() {
        _walletMfp = info.mfp;
        _walletMfpError = null;
        _walletValidating = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _walletMfp = null;
        _walletMfpError = formatRustError(e);
        _walletValidating = false;
      });
    }
  }

  int get _wordCount {
    final words = _mnemonicController.text.trim().split(RegExp(r'\s+'));
    return words.where((w) => w.isNotEmpty).length;
  }

  bool get _isValidWordCount => bip39ValidWordCounts.contains(_wordCount);

  // --- Submit ---

  Future<void> _submit() async {
    if (widget.walletMode) {
      await _submitWallet();
      return;
    }
    setState(() => _errorText = null);

    String mfp, path, xpub;

    switch (_tab) {
      case _AddKeyTab.separateFields:
        mfp = _mfpController.text.trim().toLowerCase();
        path = _pathSepController.text.trim();
        xpub = _xpubController.text.trim();
        if (mfp.isEmpty || path.isEmpty || xpub.isEmpty) {
          setState(() => _errorText = context.l10n.allFieldsRequired);
          return;
        }

      case _AddKeyTab.seed:
        if (_derivedKeyspec == null) {
          setState(
              () => _errorText = _deriveError ?? context.l10n.deriveKeyFirst);
          return;
        }
        final match = kKeyspecPattern.firstMatch(_derivedKeyspec!);
        if (match == null) {
          setState(() => _errorText = context.l10n.invalidDerivedKeyspec);
          return;
        }
        mfp = match.group(1)!.toLowerCase();
        path = match.group(2)!;
        xpub = match.group(3)!;
    }

    String? seedMnemonic;
    String? seedPassphrase;
    String? seedXprv;
    if (_tab == _AddKeyTab.seed) {
      if (_seedType == _SeedType.mnemonic) {
        seedMnemonic = _mnemonicController.text.trim();
        seedPassphrase = _passphraseController.text.isNotEmpty
            ? _passphraseController.text
            : null;
      } else {
        seedXprv = _xprvController.text.trim();
      }
    }

    await _addKeyFromParts(mfp, path, xpub,
        seedMnemonic: seedMnemonic,
        seedPassphrase: seedPassphrase,
        seedXprv: seedXprv);
  }

  Future<void> _submitWallet() async {
    setState(() => _errorText = null);

    if (_seedType == _SeedType.mnemonic) {
      if (_walletValidating) return;
      if (_walletMfp == null || _walletMfpError != null) {
        setState(() =>
            _errorText = _walletMfpError ?? context.l10n.enterValidSeedPhrase);
        return;
      }
      if (widget.expectedMfp != null &&
          _walletMfp!.toLowerCase() != widget.expectedMfp!.toLowerCase()) {
        setState(() => _errorText = context.l10n.mfpMismatch(
            _walletMfp!, widget.expectedMfp!));
        return;
      }
      final result = await widget.onAddMnemonic!(
        _mnemonicController.text.trim(),
        _passphraseController.text.isEmpty
            ? null
            : _passphraseController.text,
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

  /// Validates and adds (or updates) a key from parsed components (project mode).
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

  // --- Method picker actions ---

  Future<void> _onImportTapped() async {
    final result = await showTextImportSheet(context);
    if (result == null || !mounted) return;
    final match = kKeyspecPattern.firstMatch(result.trim());
    if (match == null) {
      setState(() {
        _showMethodPicker = false;
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

  Future<void> _onHardwareTapped() async {
    final suggested = widget.walletType != null
        ? _defaultDerivationPath(
            widget.walletType!,
            widget.network,
            widget.existingKeyCount,
            isMultiPath: widget.isMultiPath,
            accountIndex: _accountIndex,
          )
        : "m/86'/0'/0'";
    final path = await _showDerivationPathPicker(context, suggested);
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
        _showMethodPicker = false;
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

  // --- Build ---

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
          // Title row with close button
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
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
                                fontFamily: 'monospace',
                                color: Theme.of(context).colorScheme.secondary,
                              ),
                            )
                          else if (_isEditMode)
                            Text(
                              widget.editingKey!.mfp.toUpperCase(),
                              style: TextStyle(
                                fontSize: 12,
                                fontFamily: 'monospace',
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

          if (_showMethodPicker)
            _buildMethodPicker(l10n)
          else ...[
            // Manual mode: chips + form
            if (!_isEditMode && !widget.walletMode) ...[
              SizedBox(
                width: double.infinity,
                child: SegmentedButton<_AddKeyTab>(
                  showSelectedIcon: false,
                  segments: const [
                    ButtonSegment(
                      value: _AddKeyTab.separateFields,
                      label: Text('Watch Only'),
                      icon: Icon(Icons.visibility_outlined, size: 16),
                    ),
                    ButtonSegment(
                      value: _AddKeyTab.seed,
                      label: Text('Hot Key'),
                      icon: Icon(Icons.local_fire_department_outlined, size: 16),
                    ),
                  ],
                  selected: {_tab},
                  onSelectionChanged: (v) => setState(() {
                    _tab = v.first;
                    _errorText = null;
                    _derivedKeyspec = null;
                    _deriveError = null;
                  }),
                ),
              ),
              const SizedBox(height: 16),
            ],
            Flexible(
              child: SingleChildScrollView(
                dragStartBehavior: DragStartBehavior.down,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (_tab == _AddKeyTab.separateFields)
                      _buildSeparateFields(l10n),
                    if (_tab == _AddKeyTab.seed) _buildSeedForm(),
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

  Widget _buildMethodPicker(AppLocalizations l10n) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        _MethodTile(
          icon: Icons.download_outlined,
          title: l10n.importAction,
          subtitle: l10n.addKeyClipboardSubtitle,
          onTap: _onImportTapped,
        ),
        const SizedBox(height: 8),
        _MethodTile(
          icon: Icons.hardware,
          title: l10n.hwWalletTitle,
          subtitle: l10n.addKeyHwSubtitle,
          onTap: _onHardwareTapped,
        ),
        const SizedBox(height: 8),
        _MethodTile(
          icon: Icons.edit_outlined,
          title: l10n.addKeyManualTitle,
          subtitle: l10n.addKeyManualSubtitle,
          onTap: () => setState(() => _showMethodPicker = false),
          trailingIcon: Icons.chevron_right,
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

  Widget _buildSeedForm() {
    // Wallet mode: simplified — no derivation path, MFP preview only
    if (widget.walletMode) {
      return _buildWalletSeedForm();
    }

    final quickPaths = _quickPaths(widget.walletType, widget.network,
        isMultiPath: widget.isMultiPath);
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
              fontFamily: 'monospace',
            ),
          ),
          const SizedBox(height: 8),
        ],
        // Mnemonic / xprv toggle
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
            _derivedKeyspec = null;
            _deriveError = null;
          }),
          style: const ButtonStyle(visualDensity: VisualDensity.compact),
        ),
        ),
        const SizedBox(height: 12),
        if (_seedType == _SeedType.mnemonic) ...[
          MnemonicEntryField(controller: _mnemonicController),
          const SizedBox(height: 12),
          TextField(
            controller: _passphraseController,
            obscureText: !_showPassphrase,
            decoration: InputDecoration(
              border: const OutlineInputBorder(),
              labelText: context.l10n.bip39PassphraseLabel,
              suffixIcon: IconButton(
                icon: Icon(
                    _showPassphrase ? Icons.visibility_off : Icons.visibility),
                onPressed: () =>
                    setState(() => _showPassphrase = !_showPassphrase),
              ),
            ),
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
        if (widget.keyspecMode && widget.walletType != null)
          _buildAccountIndexStepper(),
        ..._buildDerivPathField(quickPaths),
        ..._buildDeriveResult(),
      ],
    );
  }

  Widget _buildAccountIndexStepper() {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        children: [
          Text(l10n.accountIndexLabel, style: theme.textTheme.labelMedium),
          const Spacer(),
          IconButton(
            icon: const Icon(Icons.remove_circle_outline, size: 20),
            onPressed: _accountIndex > 0
                ? () => _setAccountIndex(_accountIndex - 1)
                : null,
            visualDensity: VisualDensity.compact,
          ),
          SizedBox(
            width: 32,
            child: Center(
              child: Text('$_accountIndex',
                  style: theme.textTheme.titleSmall),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.add_circle_outline, size: 20),
            onPressed: () => _setAccountIndex(_accountIndex + 1),
            visualDensity: VisualDensity.compact,
          ),
        ],
      ),
    );
  }

  /// Seed form in wallet mode: no derivation path, MFP preview instead.
  Widget _buildWalletSeedForm() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
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
            _walletMfp = null;
            _walletMfpError = null;
          }),
          style: const ButtonStyle(visualDensity: VisualDensity.compact),
        ),
        ),
        const SizedBox(height: 12),
        if (_seedType == _SeedType.mnemonic) ...[
          MnemonicEntryField(
            controller: _mnemonicController,
            errorText: _walletMfpError,
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _passphraseController,
            obscureText: !_showPassphrase,
            decoration: InputDecoration(
              border: const OutlineInputBorder(),
              labelText: context.l10n.bip39PassphraseLabel,
              suffixIcon: IconButton(
                icon: Icon(
                    _showPassphrase ? Icons.visibility_off : Icons.visibility),
                onPressed: () =>
                    setState(() => _showPassphrase = !_showPassphrase),
              ),
            ),
          ),
          if (_walletValidating) ...[
            const SizedBox(height: 8),
            Row(children: [
              const SizedBox(
                  width: 14,
                  height: 14,
                  child: CircularProgressIndicator(strokeWidth: 2)),
              const SizedBox(width: 8),
              Text(context.l10n.validating, style: const TextStyle(fontSize: 12)),
            ]),
          ] else if (_walletMfp != null) ...[
            const SizedBox(height: 8),
            _buildWalletMfpPreview(),
          ],
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

  Widget _buildWalletMfpPreview() {
    final expected = widget.expectedMfp;
    final matches =
        expected == null || _walletMfp!.toLowerCase() == expected.toLowerCase();
    return Row(children: [
      Icon(
        matches ? Icons.check_circle : Icons.cancel,
        color: matches ? Colors.green : Colors.red,
        size: 16,
      ),
      const SizedBox(width: 4),
      if (matches)
        Text('MFP: $_walletMfp',
            style: const TextStyle(fontFamily: 'monospace'))
      else
        Expanded(
          child: Text(
            context.l10n.wrongKeyMfp(_walletMfp!, expected),
            style: const TextStyle(
                color: Colors.red, fontSize: 12, fontFamily: 'monospace'),
          ),
        ),
    ]);
  }

  Widget _buildSeparateFields(AppLocalizations l10n) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        TextField(
          controller: _mfpController,
          enabled: !_isEditMode,
          decoration: InputDecoration(
            labelText: l10n.mfpLabel,
            hintText: l10n.mfpHint,
          ),
          textCapitalization: TextCapitalization.none,
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _pathSepController,
          decoration: InputDecoration(
            labelText: l10n.derivationPathLabel,
            hintText: l10n.derivationPathHint,
          ),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _xpubController,
          decoration: InputDecoration(
            labelText: l10n.xpubLabel,
            hintText: l10n.xpubHint,
          ),
          maxLines: 2,
        ),
      ],
    );
  }

  List<Widget> _buildDerivPathField(List<_QuickPath> quickPaths) {
    return [
      TextField(
        controller: _derivPathController,
        decoration: InputDecoration(
          border: const OutlineInputBorder(),
          labelText: context.l10n.keyDerivPathLabel,
          hintText: "84'/0'/0'",
          helperText: context.l10n.derivPathWithoutLeading,
        ),
        style: const TextStyle(fontFamily: 'monospace'),
      ),
      if (quickPaths.isNotEmpty) ...[
        const SizedBox(height: 8),
        Wrap(
          spacing: 6,
          children: [
            for (final qp in quickPaths)
              ActionChip(
                label:
                    Text(qp.label, style: const TextStyle(fontSize: 11)),
                onPressed: () {
                  _derivPathController.text = qp.path;
                },
                visualDensity: VisualDensity.compact,
                padding: const EdgeInsets.symmetric(horizontal: 4),
              ),
          ],
        ),
      ],
      const SizedBox(height: 12),
    ];
  }

  List<Widget> _buildDeriveResult() {
    if (_deriving) {
      return [
        const Center(child: CircularProgressIndicator()),
        const SizedBox(height: 8),
      ];
    }
    if (_deriveError != null) {
      return [
        Text(_deriveError!,
            style: const TextStyle(color: Colors.red, fontSize: 13)),
        const SizedBox(height: 8),
      ];
    }
    if (_derivedKeyspec != null) {
      final match = kKeyspecPattern.firstMatch(_derivedKeyspec!);
      final derivedMfp = match?.group(1)?.toLowerCase();
      final mfpMatches = !_isEditMode ||
          derivedMfp == widget.editingKey!.mfp.toLowerCase();

      return [
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: (mfpMatches ? Colors.green : Colors.red).withAlpha(AppAlpha.faint),
            border: Border.all(
                color:
                    (mfpMatches ? Colors.green : Colors.red).withAlpha(AppAlpha.pale)),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(children: [
                Icon(
                  mfpMatches ? Icons.check_circle : Icons.cancel,
                  color: mfpMatches ? Colors.green : Colors.red,
                  size: 16,
                ),
                const SizedBox(width: 6),
                Text(
                  context.l10n.derivedKeyspecLabel,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                    color: mfpMatches ? Colors.green : Colors.red,
                  ),
                ),
              ]),
              const SizedBox(height: 4),
              SelectableText(
                _derivedKeyspec!,
                style:
                    const TextStyle(fontFamily: 'monospace', fontSize: 12),
              ),
              const SizedBox(height: 6),
              TextButton.icon(
                icon: const Icon(Icons.copy, size: 16),
                label: Text(context.l10n.copy),
                style: TextButton.styleFrom(
                  visualDensity: VisualDensity.compact,
                ),
                onPressed: () {
                  Clipboard.setData(ClipboardData(text: _derivedKeyspec!));
                },
              ),
            ],
          ),
        ),
        const SizedBox(height: 8),
      ];
    }
    return [];
  }
}

// ---------------------------------------------------------------------------

class _MethodTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;
  final IconData trailingIcon;

  const _MethodTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
    this.trailingIcon = Icons.arrow_forward_ios,
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
            Icon(trailingIcon,
                size: 16, color: cs.onSurface.withAlpha(AppAlpha.border)),
          ],
        ),
      ),
    );
  }
}
