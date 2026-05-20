import 'dart:convert' show base64Decode;

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_rust_bridge/flutter_rust_bridge_for_generated.dart'
    show PlatformInt64;

import 'package:deadbolt/cubit/tx_planning_cubit.dart';
import 'package:deadbolt/l10n/l10n.dart';
import 'package:deadbolt/screens/qr_scanner_screen.dart';
import 'package:deadbolt/screens/tx_planning/tx_planning_signing_cursor.dart';
import 'package:deadbolt/utils/toast_helper.dart'
    show showErrorToast, showErrorToastException;
import 'package:deadbolt/widgets/text_export_sheet.dart' show BcurQrView;

/// Iterative QR signing flow for a spaced plan signing bundle.
///
/// Drives a per-keyholder pass over the plan's children: shows the
/// animated BC-UR for the child at `_cursor` plus a "scan signature"
/// button. Each successful scan is merged immediately. The cursor only
/// advances when the merge produced **at least one new signer** on that
/// child (so re-scanning the same QR can't silently skip the row, and
/// multisig threshold isn't required to advance — one keyholder per
/// pass).
class TxPlanningQrSignView extends StatefulWidget {
  final APISpacedPlanSigningBundle initialBundle;

  /// MFP the user picked at the upstream MFP picker. Scopes the
  /// cursor so this pass only walks children pending **for this key**
  /// — critical for multisig where the first round leaves every
  /// child non-finalized.
  final String activeMfp;

  const TxPlanningQrSignView({
    super.key,
    required this.initialBundle,
    required this.activeMfp,
  });

  static Future<void> push(
    BuildContext context, {
    required APISpacedPlanSigningBundle bundle,
    required String activeMfp,
  }) {
    final cubit = context.read<TxPlanningCubit>();
    return Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder: (_) => BlocProvider<TxPlanningCubit>.value(
          value: cubit,
          child: TxPlanningQrSignView(
            initialBundle: bundle,
            activeMfp: activeMfp,
          ),
        ),
      ),
    );
  }

  @override
  State<TxPlanningQrSignView> createState() => _TxPlanningQrSignViewState();
}

class _TxPlanningQrSignViewState extends State<TxPlanningQrSignView> {
  late APISpacedPlanSigningBundle _bundle;
  late int _cursor;
  bool _busy = false;

  // Persisted across child rebuilds (each child uses a different ValueKey,
  // so BcurQrView's State is recreated per PSBT — without lifting these
  // up the sliders would snap back to defaults on every advance).
  int _densityIdx = 0;
  int _speedIdx = 1;

  @override
  void initState() {
    super.initState();
    _bundle = widget.initialBundle;
    _cursor = _bundle.firstPendingForMfp(0, widget.activeMfp);
  }

  int get _total => _bundle.children.length;

  APISpacedPlanChildPsbt? get _current =>
      _cursor < _total ? _bundle.children[_cursor] : null;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final current = _current;
    return Scaffold(
      appBar: AppBar(title: Text(l10n.txPlanningQrSignTitle)),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: current == null
              ? _allDone(context)
              : _signingBody(context, current),
        ),
      ),
    );
  }

  Widget _signingBody(BuildContext context, APISpacedPlanChildPsbt child) {
    final l10n = context.l10n;
    final urBytes = base64Decode(child.psbtB64);
    final position = _cursor + 1;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          l10n.txPlanningQrSignCurrent(position, _total),
          style: Theme.of(context).textTheme.titleMedium,
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 4),
        Text(
          l10n.txPlanningQrSignHint,
          style: Theme.of(context).textTheme.bodySmall,
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 12),
        Expanded(
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 360),
              child: BcurQrView(
                key: ValueKey<int>(child.psbtId.toInt()),
                urBytes: urBytes,
                urType: 'crypto-psbt',
                showControls: true,
                initialDensityIdx: _densityIdx,
                initialSpeedIdx: _speedIdx,
                onSettingsChanged: (d, s) {
                  _densityIdx = d;
                  _speedIdx = s;
                },
              ),
            ),
          ),
        ),
        const SizedBox(height: 16),
        FilledButton.icon(
          onPressed: _busy ? null : () => _scanAndMerge(child),
          icon: _busy
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.qr_code_scanner),
          label: Text(l10n.txPlanningQrSignScanButton),
        ),
      ],
    );
  }

  Widget _allDone(BuildContext context) {
    final l10n = context.l10n;
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.check_circle, color: Colors.green, size: 64),
          const SizedBox(height: 12),
          Text(
            l10n.txPlanningQrSignAllDone,
            style: Theme.of(context).textTheme.titleMedium,
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 16),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(),
            child: Text(l10n.close),
          ),
        ],
      ),
    );
  }

  Future<void> _scanAndMerge(APISpacedPlanChildPsbt child) async {
    final l10n = context.l10n;
    final cubit = context.read<TxPlanningCubit>();
    final scanned = await QrScannerScreen.push(context);
    if (scanned == null || scanned.isEmpty || !mounted) return;
    setState(() => _busy = true);

    // Snapshot of which keys had already signed this child before the
    // merge — used to detect whether the scanned PSBT actually added a
    // new signature (otherwise the merge is a silent no-op).
    final signedBefore = _signersByMfp(child.signers);

    APIBatchSignReport? report;
    try {
      report = await cubit.applySignedPsbts([
        APISignedChildPsbt(psbtId: child.psbtId, signedB64: scanned),
      ]);
    } catch (e) {
      if (!mounted) return;
      showErrorToastException(e);
      setState(() => _busy = false);
      return;
    }
    if (!mounted) return;

    if (report == null || report.signedIds.isEmpty) {
      final reason = report?.failed.isNotEmpty == true
          ? report!.failed.first.error
          : l10n.txPlanningQrSignMismatchToast;
      showErrorToast(reason);
      setState(() => _busy = false);
      return;
    }

    final APISpacedPlanSigningBundle? fresh;
    try {
      fresh = await cubit.prepareForBatchSigning();
    } catch (e) {
      if (!mounted) return;
      showErrorToastException(e);
      setState(() => _busy = false);
      return;
    }
    if (!mounted) return;
    if (fresh == null) {
      setState(() => _busy = false);
      return;
    }

    // Locate the same child in the refreshed bundle and check whether
    // any mfp's `has_signed` flipped false → true. If nothing changed
    // (e.g. the user re-scanned the unsigned QR, or the external signer
    // returned the PSBT untouched), don't advance — tell the user.
    final refreshedChild = _findChild(fresh, child.psbtId);
    final addedNew = refreshedChild != null &&
        _addedNewSigner(signedBefore, refreshedChild.signers);

    if (!addedNew) {
      setState(() {
        _bundle = fresh!;
        _busy = false;
      });
      showErrorToast(l10n.txPlanningQrSignNoNewSigToast);
      return;
    }

    setState(() {
      _bundle = fresh!;
      _cursor = _bundle.firstPendingForMfp(_cursor + 1, widget.activeMfp);
      _busy = false;
    });
  }

  static Map<String, bool> _signersByMfp(List<APIPsbtSignerStatus> signers) =>
      {for (final s in signers) s.mfp: s.hasSigned};

  static APISpacedPlanChildPsbt? _findChild(
    APISpacedPlanSigningBundle bundle,
    PlatformInt64 psbtId,
  ) {
    for (final c in bundle.children) {
      if (c.psbtId == psbtId) return c;
    }
    return null;
  }

  static bool _addedNewSigner(
    Map<String, bool> before,
    List<APIPsbtSignerStatus> after,
  ) {
    for (final s in after) {
      if (s.hasSigned && !(before[s.mfp] ?? false)) return true;
    }
    return false;
  }
}
