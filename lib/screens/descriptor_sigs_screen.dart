import 'dart:convert';
import 'package:deadbolt/config/constants.dart' show kMonospaceFontFamily;

import 'package:flutter/gestures.dart' show DragStartBehavior;
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:qr_flutter/qr_flutter.dart';

import 'package:deadbolt/cubit/descriptor_sigs_cubit.dart';
import 'package:deadbolt/l10n/l10n.dart';
import 'package:deadbolt/screens/qr_scanner_screen.dart';
import 'package:deadbolt/src/rust/api/hw_wallet.dart' as rust_hw;
import 'package:deadbolt/theme/app_theme.dart';
import 'package:deadbolt/utils/date_format.dart';
import 'package:deadbolt/utils/toast_helper.dart';
import 'package:deadbolt/widgets/colored_group_text.dart';
import 'package:deadbolt/widgets/copy_icon_button.dart';
import 'package:deadbolt/widgets/dialog_helpers.dart';
import 'package:deadbolt/widgets/hw_wallet_sheet.dart' show showHwCheckRegisterAndSignSheet, showHwConnectSheet;
import 'package:deadbolt/widgets/mfp_badge.dart';
import 'package:deadbolt/widgets/text_export_sheet.dart' show BcurQrView, showQrDialog;

// ---------------------------------------------------------------------------
// Entry point
// ---------------------------------------------------------------------------

/// Full-page screen for managing descriptor signatures.
///
/// Push via [DescriptorSigsScreen.push].
class DescriptorSigsScreen extends StatelessWidget {
  const DescriptorSigsScreen._();

  static Future<void> push(
    BuildContext context, {
    required DescriptorSigsCubit cubit,
  }) {
    return Navigator.of(context).push<void>(MaterialPageRoute(
      builder: (_) => BlocProvider.value(
        value: cubit,
        child: const DescriptorSigsScreen._(),
      ),
    ));
  }

  @override
  Widget build(BuildContext context) {
    return BlocConsumer<DescriptorSigsCubit, DescriptorSigsState>(
      listener: (ctx, state) {
        if (state is DescriptorSigsError) {
          showErrorToast(state.message);
          Navigator.of(ctx).maybePop();
        }
      },
      builder: (ctx, state) => Scaffold(
        appBar: AppBar(
          title: Text(ctx.l10n.descriptorSigsTitle),
          actions: [
            IconButton(
              icon: const Icon(Icons.usb_outlined),
              tooltip: ctx.l10n.descriptorSigsConnectHw,
              onPressed: () => showHwConnectSheet(ctx),
            ),
            if (state is DescriptorSigsLoaded)
              IconButton(
                icon: const Icon(Icons.verified_outlined),
                tooltip: ctx.l10n.descriptorSigsVerifyAll,
                onPressed: () async {
                  try {
                    await ctx.read<DescriptorSigsCubit>().verify();
                    if (ctx.mounted) {
                      final s = ctx.read<DescriptorSigsCubit>().state;
                      if (s is DescriptorSigsLoaded) {
                        final valid = s.sigs.where((x) => x.isValid).length;
                        showSuccessToast(ctx.l10n
                            .descriptorSigsVerifyResult(valid, s.sigs.length));
                      }
                    }
                  } catch (e) {
                    if (ctx.mounted) showErrorToastException(e);
                  }
                },
              ),
          ],
        ),
        body: switch (state) {
          DescriptorSigsLoading() ||
          DescriptorSigsError() =>
            const Center(child: CircularProgressIndicator()),
          DescriptorSigsLoaded() => _LoadedBody(state: state),
        },
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Loaded body
// ---------------------------------------------------------------------------

class _LoadedBody extends StatelessWidget {
  final DescriptorSigsLoaded state;
  const _LoadedBody({required this.state});

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: Text(
            l10n.descriptorSigsSubtitle,
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ),
        Expanded(
          child: ListView.builder(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            itemCount: state.participatingKeys.length,
            itemBuilder: (ctx, i) {
              final key = state.participatingKeys[i];
              final sig = state.sigForMfp(key.mfp);
              return _KeyTile(
                mfp: key.mfp,
                derivationPath: key.derivationPath,
                xpub: key.xpub,
                sig: sig,
                hasVerified: state.hasVerified,
                keyIndex: i,
              );
            },
          ),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Per-key tile
// ---------------------------------------------------------------------------

class _KeyTile extends StatelessWidget {
  final String mfp;
  final String derivationPath;
  final String xpub;
  final APIDescriptorSig? sig;
  final bool hasVerified;
  final int keyIndex;

  const _KeyTile({
    required this.mfp,
    required this.derivationPath,
    required this.xpub,
    required this.sig,
    required this.hasVerified,
    required this.keyIndex,
  });

  String get _xpubEntry => '[$mfp/$derivationPath]$xpub';

  Color _keyColor(BuildContext context) {
    final ext = Theme.of(context).extension<KeyColorExtension>()!;
    return ext.keyColors[keyIndex % ext.keyColors.length];
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final keyColor = _keyColor(context);

    final hasSig = sig != null;

    Widget statusWidget;
    if (!hasSig) {
      statusWidget = Text(
        l10n.descriptorSigsNotSigned,
        style: theme.textTheme.bodySmall?.copyWith(color: colors.outline),
      );
    } else if (!hasVerified) {
      // Signed but not yet verified — show neutral label
      statusWidget = Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.edit_outlined, size: 13,
              color: colors.onSurface.withAlpha(AppAlpha.secondary)),
          const SizedBox(width: 4),
          Text(
            l10n.descriptorSigsSigned(formatDateTimeFromUnix(sig!.signedAt)),
            style: theme.textTheme.bodySmall
                ?.copyWith(color: colors.onSurface.withAlpha(AppAlpha.secondary)),
          ),
        ],
      );
    } else if (!sig!.isValid) {
      statusWidget = Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.warning_amber_rounded, size: 13, color: colors.error),
          const SizedBox(width: 4),
          Text(
            l10n.descriptorSigsInvalid,
            style: theme.textTheme.bodySmall?.copyWith(color: colors.error),
          ),
        ],
      );
    } else {
      statusWidget = Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.verified_outlined, size: 13, color: colors.primary),
          const SizedBox(width: 4),
          Text(
            l10n.descriptorSigsVerified(formatDateTimeFromUnix(sig!.signedAt)),
            style: theme.textTheme.bodySmall?.copyWith(color: colors.primary),
          ),
        ],
      );
    }

    final Widget? trailingWidget;
    if (!hasSig) {
      trailingWidget = IconButton(
        icon: Icon(Icons.draw_outlined, color: colors.primary),
        tooltip: l10n.descriptorSigsSignAction,
        onPressed: () => _showSignMethodSheet(context),
      );
    } else {
      trailingWidget = IconButton(
        icon: Icon(Icons.delete_outline, color: colors.error),
        tooltip: l10n.descriptorSigsDeleteAction,
        onPressed: () => _confirmDelete(context),
      );
    }

    return Card(
      margin: const EdgeInsets.only(top: 8),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
        leading: CircleAvatar(
          radius: 18,
          backgroundColor: keyColor.withAlpha(AppAlpha.subtle),
          child: Icon(Icons.key, color: keyColor, size: 18),
        ),
        title: Row(
          children: [
            MfpBadge(
              label: mfp.toUpperCase(),
              color: keyColor,
              letterSpacing: 0.5,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                derivationPath.isEmpty ? 'm' : 'm/$derivationPath',
                style: TextStyle(
                  fontSize: 11,
                  color: colors.onSurface.withAlpha(AppAlpha.secondary),
                  fontFamily: kMonospaceFontFamily,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 2),
            ColoredGroupText(
              text: xpub,
              fontSize: 11,
              truncate: true,
              monospace: true,
            ),
            const SizedBox(height: 4),
            statusWidget,
          ],
        ),
        trailing: trailingWidget,
      ),
    );
  }

  Future<void> _showSignMethodSheet(BuildContext context) async {
    final session = rust_hw.hwActiveSession();
    final hasBB02 = session != null &&
        session.rootFingerprint.toLowerCase() == mfp.toLowerCase();
    final cubit = context.read<DescriptorSigsCubit>();
    await showSheet<void>(
      context,
      (ctx) => _SignMethodSheet(
        mfp: mfp,
        xpubEntry: _xpubEntry,
        outerContext: context,
        hasBB02: hasBB02,
        cubit: cubit,
      ),
    );
  }

  Future<void> _confirmDelete(BuildContext context) async {
    final l10n = context.l10n;
    final confirmed = await confirmDestructive(
      context,
      title: l10n.descriptorSigsDeleteAction,
      body: 'MFP: $mfp',
    );
    if (confirmed && context.mounted) {
      try {
        await context.read<DescriptorSigsCubit>().deleteSig(mfp);
      } catch (e) {
        if (context.mounted) showErrorToastException(e);
      }
    }
  }
}

// ---------------------------------------------------------------------------
// Sign method bottom sheet
// ---------------------------------------------------------------------------

class _SignMethodSheet extends StatelessWidget {
  final String mfp;
  final String xpubEntry;
  final BuildContext outerContext;
  final bool hasBB02;
  final DescriptorSigsCubit cubit;

  const _SignMethodSheet({
    required this.mfp,
    required this.xpubEntry,
    required this.outerContext,
    required this.hasBB02,
    required this.cubit,
  });

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;

    // Determine which signing methods are available for this MFP.
    final cubitState = cubit.state;
    final hotKeyMfps = cubitState is DescriptorSigsLoaded
        ? cubitState.hotKeyMfps
        : const <String>{};
    final bool hasHotKey = hotKeyMfps.contains(mfp);

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
              child: Text(l10n.descriptorSigsChooseMethod,
                  style: Theme.of(context).textTheme.titleSmall),
            ),
            if (hasHotKey)
              ListTile(
                leading: const Icon(Icons.vpn_key_outlined),
                title: Text(l10n.descriptorSigsMethodHotKey),
                onTap: () async {
                  Navigator.pop(context);
                  await _signHotKey(outerContext, cubit);
                },
              ),
            if (hasBB02)
              ListTile(
                leading: const Icon(Icons.usb_outlined),
                title: Text(l10n.descriptorSigsMethodBB02),
                onTap: () async {
                  Navigator.pop(context);
                  if (outerContext.mounted) {
                    await _signBB02(outerContext, cubit);
                  }
                },
              ),
            ListTile(
              leading: const Icon(Icons.qr_code_scanner_outlined),
              title: Text(l10n.descriptorSigsMethodQRMessage),
              onTap: () async {
                Navigator.pop(context);
                if (outerContext.mounted) {
                  await _signQRMessage(outerContext, cubit);
                }
              },
            ),
            ListTile(
              leading: const Icon(Icons.qr_code_outlined),
              title: Text(l10n.descriptorSigsMethodQRBip322),
              onTap: () async {
                Navigator.pop(context);
                if (outerContext.mounted) {
                  await _signQRBip322(outerContext, cubit);
                }
              },
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _signHotKey(
      BuildContext context, DescriptorSigsCubit cubit) async {
    try {
      await cubit.signWithHotKey(mfp);
      if (context.mounted) {
        showSuccessToast(context.l10n.descriptorSigsSignSuccess);
      }
    } catch (e) {
      if (context.mounted) showErrorToastException(e);
    }
  }

  Future<void> _signBB02(
      BuildContext context, DescriptorSigsCubit cubit) async {
    try {
      final prep = cubit.preparePsbt(mfp);
      final cubitState = cubit.state;
      if (cubitState is! DescriptorSigsLoaded || !context.mounted) return;

      final slashIdx = xpubEntry.indexOf('/');
      final bracketIdx = xpubEntry.indexOf(']');
      final derivationPath = xpubEntry.substring(slashIdx + 1, bracketIdx);

      final signedPsbt = await showHwCheckRegisterAndSignSheet(
        context,
        psbtBase64: prep.psbtB64,
        walletName: 'BIP322-$derivationPath',
        policy: prep.signDescriptor,
        network: cubitState.network,
      );
      if (signedPsbt == null || !context.mounted) return;

      await cubit.completeSigFromPsbt(
        mfp: mfp,
        xpubEntry: xpubEntry,
        signedPsbtB64: signedPsbt,
      );
      if (context.mounted) showSuccessToast(context.l10n.descriptorSigsSignSuccess);
    } catch (e) {
      if (context.mounted) showErrorToastException(e);
    }
  }

  Future<void> _signQRMessage(
      BuildContext context, DescriptorSigsCubit cubit) async {
    try {
      final prep = cubit.preparePsbt(mfp);
      if (!context.mounted) return;

      await showSheet<void>(context, (ctx) => _QRMessageSheet(
        mfp: mfp,
        xpubEntry: xpubEntry,
        message: prep.message,
        cubit: cubit,
      ));
    } catch (e) {
      if (context.mounted) showErrorToastException(e);
    }
  }

  Future<void> _signQRBip322(
      BuildContext context, DescriptorSigsCubit cubit) async {
    try {
      final prep = cubit.preparePsbt(mfp);
      if (!context.mounted) return;

      await showSheet<void>(context, (ctx) => _QRBip322Sheet(
        mfp: mfp,
        xpubEntry: xpubEntry,
        prep: prep,
        cubit: cubit,
      ));
    } catch (e) {
      if (context.mounted) showErrorToastException(e);
    }
  }
}

// ---------------------------------------------------------------------------
// QR message sign sheet
// ---------------------------------------------------------------------------

class _QRMessageSheet extends StatefulWidget {
  final String mfp;
  final String xpubEntry;
  final String message;
  final DescriptorSigsCubit cubit;

  const _QRMessageSheet({
    required this.mfp,
    required this.xpubEntry,
    required this.message,
    required this.cubit,
  });

  @override
  State<_QRMessageSheet> createState() => _QRMessageSheetState();
}

class _QRMessageSheetState extends State<_QRMessageSheet> {
  final _sigController = TextEditingController();
  bool _submitting = false;

  @override
  void dispose() {
    _sigController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    return SafeArea(
      child: SingleChildScrollView(
        dragStartBehavior: DragStartBehavior.down,
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(l10n.descriptorSigsMethodQRMessage,
                style: theme.textTheme.titleSmall),
            const SizedBox(height: 12),
            Text(l10n.descriptorSigsMessage,
                style: theme.textTheme.labelMedium),
            const SizedBox(height: 8),
            LayoutBuilder(
              builder: (context, constraints) => GestureDetector(
                onTap: () => showQrDialog(context, widget.message),
                child: QrImageView(
                  data: widget.message,
                  version: QrVersions.auto,
                  errorCorrectionLevel: QrErrorCorrectLevel.M,
                  backgroundColor: Colors.white,
                  size: constraints.maxWidth,
                ),
              ),
            ),
            const SizedBox(height: 4),
            Row(
              children: [
                Expanded(
                  child: SelectableText(
                    widget.message,
                    style: theme.textTheme.bodySmall
                        ?.copyWith(fontFamily: kMonospaceFontFamily),
                  ),
                ),
                CopyIconButton(text: widget.message, size: 18),
              ],
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _sigController,
              maxLines: 3,
              decoration: InputDecoration(
                labelText: l10n.descriptorSigsQRMessageHint,
                border: const OutlineInputBorder(),
                suffixIcon: IconButton(
                  icon: const Icon(Icons.qr_code_scanner_outlined),
                  onPressed: () async {
                    final scanned = await QrScannerScreen.push(context);
                    if (scanned != null && mounted) {
                      _sigController.text = scanned;
                    }
                  },
                ),
              ),
            ),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: _submitting ? null : _submit,
                child: _submitting
                    ? const SizedBox.square(
                        dimension: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : Text(l10n.descriptorSigsSignAction),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _submit() async {
    final l10n = context.l10n;
    final sig = _sigController.text.trim();
    if (sig.isEmpty) return;
    setState(() => _submitting = true);
    try {
      await widget.cubit.addSigFromMessage(
        mfp: widget.mfp,
        xpubEntry: widget.xpubEntry,
        sigB64: sig,
      );
      if (mounted) {
        Navigator.pop(context);
        showSuccessToast(l10n.descriptorSigsSignSuccess);
      }
    } catch (e) {
      if (mounted) showErrorToastException(e);
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }
}

// ---------------------------------------------------------------------------
// QR BIP322 sign sheet (show PSBT QR → scan signed PSBT)
// ---------------------------------------------------------------------------

class _QRBip322Sheet extends StatefulWidget {
  final String mfp;
  final String xpubEntry;
  final APIPrepareDescriptorSigPsbt prep;
  final DescriptorSigsCubit cubit;

  const _QRBip322Sheet({
    required this.mfp,
    required this.xpubEntry,
    required this.prep,
    required this.cubit,
  });

  @override
  State<_QRBip322Sheet> createState() => _QRBip322SheetState();
}

class _QRBip322SheetState extends State<_QRBip322Sheet> {
  final _signedPsbtController = TextEditingController();
  bool _submitting = false;

  @override
  void dispose() {
    _signedPsbtController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    return SafeArea(
      child: SingleChildScrollView(
        dragStartBehavior: DragStartBehavior.down,
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(l10n.descriptorSigsMethodQRBip322,
                style: theme.textTheme.titleSmall),
            const SizedBox(height: 12),
            BcurQrView(
              urBytes: base64Decode(widget.prep.psbtB64),
              urType: 'crypto-psbt',
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _signedPsbtController,
              maxLines: 3,
              decoration: InputDecoration(
                labelText: l10n.descriptorSigsQRBip322Hint,
                border: const OutlineInputBorder(),
                suffixIcon: IconButton(
                  icon: const Icon(Icons.qr_code_scanner_outlined),
                  onPressed: () async {
                    final scanned = await QrScannerScreen.push(context);
                    if (scanned != null && mounted) {
                      _signedPsbtController.text = scanned;
                    }
                  },
                ),
              ),
            ),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: _submitting ? null : _submit,
                child: _submitting
                    ? const SizedBox.square(
                        dimension: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : Text(l10n.descriptorSigsSignAction),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _submit() async {
    final l10n = context.l10n;
    final signedPsbt = _signedPsbtController.text.trim();
    if (signedPsbt.isEmpty) return;
    setState(() => _submitting = true);
    try {
      await widget.cubit.completeSigFromPsbt(
        mfp: widget.mfp,
        xpubEntry: widget.xpubEntry,
        signedPsbtB64: signedPsbt,
      );
      if (mounted) {
        Navigator.pop(context);
        showSuccessToast(l10n.descriptorSigsSignSuccess);
      }
    } catch (e) {
      if (mounted) showErrorToastException(e);
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }
}
