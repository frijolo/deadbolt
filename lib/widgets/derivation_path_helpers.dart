import 'package:flutter/material.dart';

import 'package:deadbolt/config/constants.dart' show kMonospaceFontFamily;
import 'package:deadbolt/l10n/l10n.dart';
import 'package:deadbolt/src/rust/api/model.dart';
import 'package:deadbolt/utils/api_network_extensions.dart';

/// Quick-path suggestion shown as an [ActionChip] under the derivation field.
class QuickPath {
  final String path;
  final String label;
  const QuickPath(this.path, this.label);
}

/// Returns the standard BIP derivation path for the given wallet type and network.
///
/// For P2TR:
/// - [isMultiPath] = true (e.g. inheritance/miniscript) → always m/48'/.../2'
/// - [isMultiPath] = false: [existingKeyCount] = 0 → m/86' (single-sig),
///   [existingKeyCount] > 0 → m/48'/.../2' (multi-signer)
/// [accountIndex] selects the BIP44 account level (default 0).
String defaultDerivationPath(
  APIWalletType walletType,
  APINetwork network,
  int existingKeyCount, {
  bool isMultiPath = false,
  int accountIndex = 0,
}) {
  final coin = network.coinType;
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

/// Suggested quick-paths for the seed tabs based on wallet type.
List<QuickPath> quickPaths(
  APIWalletType? walletType,
  APINetwork network, {
  bool isMultiPath = false,
}) {
  final coin = network.coinType;
  final paths = <QuickPath>[];

  if (walletType == null || walletType == APIWalletType.p2Wpkh) {
    paths.add(QuickPath("84'/$coin'/0'", 'BIP84 (Native SegWit)'));
  }
  if (walletType == null || walletType == APIWalletType.p2Tr) {
    if (!isMultiPath) {
      paths.add(QuickPath("86'/$coin'/0'", 'BIP86 (Taproot single-sig)'));
    }
    paths.add(QuickPath("48'/$coin'/0'/2'", 'BIP48 multisig (Taproot)'));
  }
  if (walletType == null ||
      walletType == APIWalletType.p2Wsh ||
      walletType == APIWalletType.p2ShWsh) {
    paths.add(QuickPath("48'/$coin'/0'/2'", 'BIP48 multisig (Native SegWit)'));
    paths.add(QuickPath("48'/$coin'/0'/1'", 'BIP48 multisig (P2SH-SegWit)'));
  }
  if (walletType == null || walletType == APIWalletType.p2Sh) {
    paths.add(QuickPath("49'/$coin'/0'", 'BIP49 (P2SH-SegWit)'));
  }
  if (walletType == null || walletType == APIWalletType.p2Pkh) {
    paths.add(QuickPath("44'/$coin'/0'", 'BIP44 (Legacy)'));
  }

  final seen = <String>{};
  return paths.where((p) => seen.add(p.path)).toList();
}

/// Modal dialog to override the derivation path manually.
Future<String?> showDerivationPathPicker(
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
        style: const TextStyle(fontFamily: kMonospaceFontFamily),
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
