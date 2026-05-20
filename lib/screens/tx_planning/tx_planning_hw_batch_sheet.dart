import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import 'package:deadbolt/cubit/hw_wallet_cubit.dart';
import 'package:deadbolt/cubit/tx_planning_cubit.dart';
import 'package:deadbolt/l10n/l10n.dart';
import 'package:deadbolt/screens/tx_planning/tx_planning_signing_cursor.dart';
import 'package:deadbolt/utils/toast_helper.dart'
    show showErrorToast, showErrorToastException;
import 'package:deadbolt/widgets/dialog_helpers.dart' show SheetHandle, showSheet;
import 'package:deadbolt/widgets/hw_wallet_common.dart';

/// Drive a single HW signing ceremony across every child PSBT of a
/// spaced plan. The sheet holds one [HwWalletCubit] (=> one device
/// session) for the whole batch; the user confirms once on the
/// hardware screen per child and never re-pairs in between.
///
/// Each successful HW signature is merged immediately via
/// [TxPlanningCubit.applySignedPsbts] before the next child is sent
/// to the device, so a hard kill mid-batch (OOM, unplug + force
/// quit, battery 0%) keeps every signature already produced. Abort
/// / finish-early just pop the sheet — nothing to flush.
///
/// Returns the last [APIBatchSignReport] produced by a per-child
/// merge (or `null` when the user dismissed before any sign
/// succeeded).
Future<APIBatchSignReport?> showTxPlanningHwBatchSheet(
  BuildContext context, {
  required APISpacedPlanSigningBundle bundle,
}) {
  // Grab the cubit up-front: showSheet builds with a child ctx that
  // doesn't see the parent's BlocProvider chain by default.
  final txPlanCubit = context.read<TxPlanningCubit>();
  return showSheet<APIBatchSignReport>(
    context,
    (_) => BlocProvider(
      create: (_) => HwWalletCubit()..scanDevices(),
      child: _HwBatchSheet(
        bundle: bundle,
        txPlanCubit: txPlanCubit,
      ),
    ),
  );
}

class _HwBatchSheet extends StatefulWidget {
  final APISpacedPlanSigningBundle bundle;
  final TxPlanningCubit txPlanCubit;
  const _HwBatchSheet({required this.bundle, required this.txPlanCubit});

  @override
  State<_HwBatchSheet> createState() => _HwBatchSheetState();
}

class _HwBatchSheetState extends State<_HwBatchSheet> {
  /// Index of the next child to ask the device to sign. Initialised
  /// in [initState] to the first non-finalized child as a coarse
  /// default; once the device pairs and we know its [_activeMfp] the
  /// cursor is rebased to the first child still pending for *that*
  /// key (skips children this device already signed in a previous
  /// session — essential in multisig where round 1 leaves every
  /// child non-finalized).
  late int _cursor;

  /// Fingerprint of the paired device. Null until [HwWalletReady]
  /// arrives. Drives the MFP-scoped cursor + the wrong-device guard.
  String? _activeMfp;

  /// How many children have been signed + persisted in this session.
  /// Drives the early-finish button label.
  int _signedCount = 0;

  /// Last report returned by a per-child `applySignedPsbts`. Handed
  /// back to the caller when the sheet pops.
  APIBatchSignReport? _lastReport;

  /// True once the user pressed Start; gates the auto-advance hook in
  /// the BlocListener (avoids re-issuing `signPsbt` while we're still
  /// on the Ready screen).
  bool _signingStarted = false;

  /// True while a per-child `applySignedPsbts` is in flight; disables
  /// every button and gates the listener so a transient HW state
  /// doesn't re-fire mid-merge.
  bool _applying = false;

  int get _total => widget.bundle.children.length;
  bool get _isDone => _cursor >= _total;

  @override
  void initState() {
    super.initState();
    _cursor = widget.bundle.firstUnfinalizedFrom(0);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return BlocConsumer<HwWalletCubit, HwWalletState>(
      listener: _onHwState,
      builder: (context, state) => Padding(
        padding: EdgeInsets.fromLTRB(
          16,
          0,
          16,
          MediaQuery.viewInsetsOf(context).bottom + 16,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const SheetHandle(),
            Text(
              l10n.txPlanningHwBatchTitle,
              style: Theme.of(context).textTheme.titleMedium,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            _buildBody(context, state),
          ],
        ),
      ),
    );
  }

  // -------------------------------------------------------------------------
  // Event hook — drives the per-PSBT loop.
  // -------------------------------------------------------------------------

  void _onHwState(BuildContext context, HwWalletState state) {
    // First-pair hook: capture the device fingerprint, validate it's
    // in the threshold, and rebase the cursor to the first child
    // pending for this key. Runs before the user presses Start so the
    // "Ready to sign N transactions" label already reflects what
    // this device actually has left to do.
    if (state is HwWalletReady && _activeMfp == null) {
      _adoptDevice(context, state.rootFingerprint);
      return;
    }
    if (!_signingStarted || _applying) return;
    if (state is HwWalletDone) {
      final result = state.result;
      if (result is HwSignedPsbtResult) {
        _persistAndAdvance(context, state, result);
      }
    }
  }

  void _adoptDevice(BuildContext context, String mfp) {
    final l10n = context.l10n;
    if (!widget.bundle.isKnownMfp(mfp)) {
      showErrorToast(l10n.txPlanningHwBatchWrongDevice(
        mfp.substring(0, mfp.length < 8 ? mfp.length : 8).toUpperCase(),
      ));
      Navigator.of(context).pop(_lastReport);
      return;
    }
    final next = widget.bundle.firstPendingForMfp(0, mfp);
    setState(() {
      _activeMfp = mfp;
      _cursor = next;
    });
    if (_isDone) {
      // Device is part of the plan but has nothing left to sign —
      // tell the user and bail out instead of showing a "Ready to
      // sign 0" Start button.
      showErrorToast(l10n.txPlanningHwBatchAllSigned);
      Navigator.of(context).pop(_lastReport);
    }
  }

  /// Merge the freshly-signed child to the DB, then re-arm the next
  /// child on the same HW session. Persisting per-child means a hard
  /// kill between signatures only loses the in-flight one.
  Future<void> _persistAndAdvance(
    BuildContext context,
    HwWalletDone state,
    HwSignedPsbtResult result,
  ) async {
    final child = widget.bundle.children[_cursor];
    final navigator = Navigator.of(context);
    final hwCubit = context.read<HwWalletCubit>();
    setState(() => _applying = true);
    try {
      _lastReport = await widget.txPlanCubit.applySignedPsbts([
        APISignedChildPsbt(
          psbtId: child.psbtId,
          signedB64: result.signedPsbtBase64,
        ),
      ]);
    } catch (e) {
      if (!mounted) return;
      showErrorToastException(e);
      // The HW already produced a signature we couldn't store — bail
      // out so the user can retry from a clean state next session.
      setState(() => _applying = false);
      navigator.pop(_lastReport);
      return;
    }
    if (!mounted) return;
    final mfp = _activeMfp;
    setState(() {
      _signedCount++;
      _cursor = mfp != null
          ? widget.bundle.firstPendingForMfp(_cursor + 1, mfp)
          : widget.bundle.firstUnfinalizedFrom(_cursor + 1);
      _applying = false;
    });
    if (_isDone) {
      navigator.pop(_lastReport);
    } else {
      _signNextOn(
        hwCubit,
        state.sessionId,
        state.productString,
        state.rootFingerprint,
      );
    }
  }

  // -------------------------------------------------------------------------
  // Body — switches on hw state + our cursor.
  // -------------------------------------------------------------------------

  Widget _buildBody(BuildContext context, HwWalletState state) {
    final l10n = context.l10n;
    final cubit = context.read<HwWalletCubit>();

    if (_applying) {
      return HwSpinner(label: l10n.txPlanningHwBatchApplying);
    }

    return switch (state) {
      HwWalletScanning() => HwSpinner(label: l10n.hwWalletScanning),
      HwWalletDevicesFound(devices: final devices) when devices.isEmpty =>
        HwEmptyDevices(onRefresh: cubit.scanDevices),
      HwWalletDevicesFound(devices: final devices) => HwDeviceList(
          devices: devices,
          onRefresh: cubit.scanDevices,
          onTap: (d) => cubit.connectDevice(d.devicePath),
        ),
      HwWalletConnecting() => HwSpinner(label: l10n.hwWalletUnlockDevice),
      HwWalletPairing(pairingCode: final code) ||
      HwWalletConfirming(pairingCode: final code) =>
        HwPairingCode(code: code),
      HwWalletReady(
        sessionId: final sid,
        productString: final prod,
        rootFingerprint: final mfp,
      ) =>
        _readyOrSigning(context, sid, prod, mfp),
      HwWalletOperating(operationLabel: final label) => Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _progressChip(context),
            const SizedBox(height: 12),
            HwSpinner(label: label),
          ],
        ),
      HwWalletError(message: final msg) => _errorPanel(context, msg),
      HwWalletDone() || HwWalletIdle() => const SizedBox.shrink(),
    };
  }

  Widget _readyOrSigning(
    BuildContext context,
    String sessionId,
    String productString,
    String rootFingerprint,
  ) {
    final l10n = context.l10n;
    if (!_signingStarted) {
      return Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          HwReadyHeader(
            productString: productString,
            rootFingerprint: rootFingerprint,
          ),
          const SizedBox(height: 12),
          Text(
            l10n.txPlanningHwBatchReady(_total - _cursor),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 12),
          FilledButton.icon(
            onPressed: () {
              setState(() => _signingStarted = true);
              _signNext(context, sessionId, productString, rootFingerprint);
            },
            icon: const Icon(Icons.draw_outlined),
            label: Text(l10n.txPlanningHwBatchStartButton),
          ),
        ],
      );
    }
    // signingStarted: a transient HwWalletReady between two operations.
    return HwSpinner(
      label: l10n.txPlanningHwBatchProgress(_cursor + 1, _total),
    );
  }

  Widget _errorPanel(BuildContext context, String message) {
    final l10n = context.l10n;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (_signingStarted) _progressChip(context),
        HwErrorMessage(message: message),
        OutlinedButton.icon(
          onPressed: () => context.read<HwWalletCubit>().scanDevices(),
          icon: const Icon(Icons.refresh),
          label: Text(
            _signingStarted
                ? l10n.txPlanningHwBatchRetryButton(_cursor + 1)
                : l10n.tryAgain,
          ),
        ),
        const SizedBox(height: 4),
        if (_signedCount > 0)
          TextButton.icon(
            onPressed: () => Navigator.of(context).pop(_lastReport),
            icon: const Icon(Icons.check),
            label: Text(
              l10n.txPlanningHwBatchFinishEarlyButton(_signedCount),
            ),
          ),
      ],
    );
  }

  Widget _progressChip(BuildContext context) {
    final l10n = context.l10n;
    return Chip(
      avatar: const Icon(Icons.draw_outlined, size: 18),
      label: Text(
        l10n.txPlanningHwBatchProgress(
          (_cursor + 1).clamp(1, _total),
          _total,
        ),
      ),
    );
  }

  // -------------------------------------------------------------------------
  // Actions
  // -------------------------------------------------------------------------

  void _signNext(
    BuildContext context,
    String sessionId,
    String productString,
    String rootFingerprint,
  ) =>
      _signNextOn(
        context.read<HwWalletCubit>(),
        sessionId,
        productString,
        rootFingerprint,
      );

  void _signNextOn(
    HwWalletCubit hwCubit,
    String sessionId,
    String productString,
    String rootFingerprint,
  ) {
    final child = widget.bundle.children[_cursor];
    hwCubit.signPsbt(
      sessionId: sessionId,
      productString: productString,
      rootFingerprint: rootFingerprint,
      psbtBase64: child.psbtB64,
      network: widget.bundle.network,
      descriptor: widget.bundle.descriptor,
      signerChainIndex: widget.bundle.keyChanges[rootFingerprint],
    );
  }

}
