import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import 'package:deadbolt/cubit/tx_planning_cubit.dart';
import 'package:deadbolt/cubit/wallet_detail_cubit.dart';
import 'package:deadbolt/l10n/l10n.dart';
import 'package:deadbolt/screens/tx_planning/tx_planning_draft_view.dart';
import 'package:deadbolt/screens/tx_planning/tx_planning_idle_view.dart';
import 'package:deadbolt/screens/tx_planning/tx_planning_running_view.dart';
import 'package:deadbolt/screens/tx_planning/tx_planning_terminal_view.dart';

/// Top-level screen for the spaced TX planning flow. Hosts the
/// [TxPlanningCubit] (provided by the caller via [BlocProvider]) and routes
/// among Idle / Draft / Running / Terminal sub-views based on the cubit's
/// current state. The cubit must already be constructed with the source
/// wallet handle.
class TxPlanningScreen extends StatelessWidget {
  const TxPlanningScreen({super.key});

  @override
  Widget build(BuildContext context) {
    // Hot keys live on the wallet detail cubit, which the caller mounts
    // alongside the planning cubit. Watching is fine — a hot-key add or
    // delete should re-render the picker.
    final walletState = context.watch<WalletDetailCubit>().state;
    final loaded = walletState is WalletDetailLoaded ? walletState : null;
    final List<APIHotKeyInfo> hotKeys = loaded?.hotKeys ?? const [];
    final int tipHeight = loaded?.tipHeight ?? 0;
    final Map<String, String> keyLabels = loaded?.keyLabels ?? const {};
    return Scaffold(
      appBar: AppBar(
        title: Text(context.l10n.txPlanningTitle),
      ),
      body: SafeArea(
        child: BlocBuilder<TxPlanningCubit, TxPlanningState>(
          builder: (context, state) => switch (state) {
            TxPlanningLoading() =>
              const Center(child: CircularProgressIndicator()),
            TxPlanningIdle(:final lastTerminal) =>
              TxPlanningIdleView(lastTerminal: lastTerminal),
            TxPlanningDraft(
              :final detail,
              :final lastCommitReport,
              :final signProgress,
              :final signers,
            ) =>
              TxPlanningDraftView(
                detail: detail,
                lastCommitReport: lastCommitReport,
                signProgress: signProgress,
                signers: signers,
                hotKeys: hotKeys,
                tipHeight: tipHeight,
                keyLabels: keyLabels,
                spendPath: loaded?.descriptorAnalysis?.spendPaths
                    .where((p) => p.id == detail.spendPathId)
                    .firstOrNull,
              ),
            TxPlanningRunning(:final detail, :final broadcastedTxids) =>
              TxPlanningRunningView(
                detail: detail,
                broadcastedTxids: broadcastedTxids,
                tipHeight: tipHeight,
              ),
            TxPlanningTerminal(:final detail) =>
              TxPlanningTerminalView(detail: detail),
          },
        ),
      ),
    );
  }
}
