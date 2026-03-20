import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart' show Share, XFile;

import 'package:deadbolt/cubit/project_list_cubit.dart';
import 'package:deadbolt/cubit/settings_cubit.dart';
import 'package:deadbolt/cubit/wallet_detail_cubit.dart';
import 'package:deadbolt/data/database.dart';
import 'package:deadbolt/l10n/l10n.dart';
import 'package:deadbolt/src/rust/api/model.dart';
export 'package:deadbolt/cubit/wallet_detail_cubit.dart' show APIUtxo;
import 'package:deadbolt/theme/app_theme.dart';
import 'package:deadbolt/utils/bitcoin_formatter.dart';
import 'package:deadbolt/utils/enum_formatters.dart';
import 'package:deadbolt/models/timelock_types.dart';
import 'package:deadbolt/services/wallet_service.dart';
import 'package:deadbolt/utils/toast_helper.dart';
import 'package:deadbolt/widgets/password_prompt_dialog.dart';
import 'package:deadbolt/src/rust/api/wallet.dart' as rust_wallet;
import 'package:deadbolt/widgets/mfp_badge.dart';
import 'package:deadbolt/widgets/descriptor_tab.dart';
import 'package:deadbolt/widgets/path_card.dart'
    show PathTimelockBadge, PathKeyPathBadge;
import 'package:deadbolt/utils/export_sheet.dart' show showDescriptorExportSheet;
import 'package:deadbolt/widgets/hw_actions_sheet.dart' show showHwActionsSheet;
import 'package:deadbolt/widgets/key_card.dart';
import 'package:deadbolt/widgets/wallet_path_detail_sheet.dart'
    show showWalletPathSheet;
import 'package:deadbolt/widgets/text_export_sheet.dart'
    show showTextExportSheet;
import 'package:deadbolt/widgets/popup_menu_helpers.dart';
import 'package:deadbolt/widgets/dialog_helpers.dart';
import 'package:deadbolt/widgets/text_import_sheet.dart'
    show showTextImportSheet, showPsbtImportSheet;
import 'package:deadbolt/screens/create_tx_screen.dart';
import 'package:deadbolt/screens/project_detail_screen.dart';
import 'package:deadbolt/widgets/add_key_dialog.dart' show showAddPrivateKeySheet;
import 'package:deadbolt/screens/wallet_detail/wallet_detail_shared.dart';
import 'package:deadbolt/screens/wallet_detail/receive_dialog.dart';
import 'package:deadbolt/screens/wallet_detail/transactions_tab.dart';
import 'package:deadbolt/screens/wallet_detail/addresses_tab.dart';
import 'package:deadbolt/screens/wallet_detail/coins_tab.dart';

class WalletDetailScreen extends StatelessWidget {
  final String walletPath;
  final void Function(int)? onNavigate;

  const WalletDetailScreen({super.key, required this.walletPath, this.onNavigate});

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (context) =>
          WalletDetailCubit(service: context.read<WalletService>())
            ..load(walletPath),
      child: _WalletDetailView(onNavigate: onNavigate),
    );
  }
}

class _WalletDetailView extends StatefulWidget {
  final void Function(int)? onNavigate;

  const _WalletDetailView({this.onNavigate});

  @override
  State<_WalletDetailView> createState() => _WalletDetailViewState();
}

class _WalletDetailViewState extends State<_WalletDetailView> {
  bool _autoSyncStarted = false;

  void _maybeStartAutoSync(BuildContext context, WalletDetailState state) {
    if (_autoSyncStarted || state is! WalletDetailLoaded) return;
    _autoSyncStarted = true;
    final settings = context.read<SettingsCubit>().state;
    final electrumUrl = settings.electrumUrlForNetwork(
      state.walletInfo.network,
    );
    context.read<WalletDetailCubit>().startAutoSync(electrumUrl);
  }

  @override
  Widget build(BuildContext context) {
    return BlocListener<WalletDetailCubit, WalletDetailState>(
      listener: (context, state) async {
        _maybeStartAutoSync(context, state);
        if (state is WalletDetailLoaded && state.errorMessage != null) {
          showErrorToast(context, state.errorMessage!);
          context.read<WalletDetailCubit>().clearError();
        }
        if (state is WalletDetailNeedsPassword) {
          final password = await showPasswordPrompt(
            context,
            title: 'Enter wallet password',
            subtitle: 'This wallet is protected with a password.',
          );
          if (password != null && context.mounted) {
            context
                .read<WalletDetailCubit>()
                .load(state.walletPath, password: password);
          } else if (context.mounted) {
            // User cancelled — pop back to wallet list
            Navigator.of(context).maybePop();
          }
        }
      },
      child: BlocBuilder<WalletDetailCubit, WalletDetailState>(
        builder: (context, state) {
          return switch (state) {
            WalletDetailInitial() ||
            WalletDetailLoading() ||
            WalletDetailNeedsPassword() =>
              Scaffold(
                appBar: AppBar(),
                body: const Center(child: CircularProgressIndicator()),
              ),
            WalletDetailError(:final message) => Scaffold(
              appBar: AppBar(),
              body: Center(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Text(message),
                ),
              ),
            ),
            WalletDetailLoaded() => _buildLoaded(context, state),
          };
        },
      ),
    );
  }

  Future<void> _openSendFlow(
    BuildContext context,
    WalletDetailLoaded state,
  ) async {
    final cubit = context.read<WalletDetailCubit>();
    await cubit.ensureCoinsLoaded();
    if (!context.mounted) return;
    final fresh = cubit.state;
    if (fresh is! WalletDetailLoaded) return;
    CreateTxScreen.push(
      context,
      allUtxos: fresh.utxos,
      tipHeight: fresh.tipHeight,
      spendPaths: fresh.descriptorAnalysis?.spendPaths,
      keyLabels: fresh.keyLabels,
      pathLabels: fresh.pathLabels,
    );
  }

  void _onMenuAction(
    BuildContext context,
    _WalletMenuAction action,
    WalletDetailLoaded state,
  ) {
    switch (action) {
      case _WalletMenuAction.send:
        _openSendFlow(context, state);
      case _WalletMenuAction.receive:
        _openReceiveFlow(context, state);
      case _WalletMenuAction.sync:
        final electrumUrl = context
            .read<SettingsCubit>()
            .state
            .electrumUrlForNetwork(state.walletInfo.network);
        context.read<WalletDetailCubit>().sync(electrumUrl);
      case _WalletMenuAction.rescan:
        _confirmRescan(context, state);
      case _WalletMenuAction.exportLabels:
        _exportWithChoice(context, state);
      case _WalletMenuAction.importLabels:
        _importWithChoice(context, state);
      case _WalletMenuAction.generateProject:
        _generateProjectFromWallet(context, state);
      case _WalletMenuAction.lock:
        context.read<WalletDetailCubit>().lockWallet();
        Navigator.of(context).pop();
    }
  }

  Future<void> _openReceiveFlow(
    BuildContext context,
    WalletDetailLoaded state,
  ) async {
    final cubit = context.read<WalletDetailCubit>();
    await cubit.ensureReceiveAddressLoaded();
    if (!context.mounted) return;
    final fresh = cubit.state;
    if (fresh is! WalletDetailLoaded) return;
    final unused = fresh.receiveAddresses
        .where((a) => !a.isUsed && (a.label == null || a.label!.isEmpty))
        .cast<APIAddress?>()
        .firstOrNull;
    if (!context.mounted) return;
    if (unused == null) {
      showErrorToast(context, context.l10n.noUnusedReceiveAddress);
      return;
    }
    showWalletDialog(context, ReceiveDialog(address: unused));
  }

  Future<void> _generateProjectFromWallet(
    BuildContext context,
    WalletDetailLoaded state,
  ) async {
    final projectCubit = context.read<ProjectListCubit>();
    final db = context.read<AppDatabase>();

    final existingProject = projectCubit.state is ProjectListLoaded
        ? (projectCubit.state as ProjectListLoaded)
            .projects
            .where((p) => p.descriptor == state.walletInfo.descriptor)
            .firstOrNull
        : null;

    if (existingProject != null && context.mounted) {
      widget.onNavigate?.call(1);
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(
          builder: (_) => ProjectDetailScreen(
            db: db,
            projectId: existingProject.id,
            onNavigate: widget.onNavigate,
          ),
        ),
      );
      return;
    }

    try {
      final projectId = await projectCubit.createProject(
        descriptor: state.walletInfo.descriptor,
        name: state.walletInfo.name,
      );
      if (!context.mounted) return;
      await _copyWalletLabelsToProject(
        db: db,
        projectId: projectId,
        keyLabels: state.keyLabels,
        pathLabels: state.pathLabels,
      );
      if (!context.mounted) return;
      widget.onNavigate?.call(1);
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(
          builder: (_) => ProjectDetailScreen(
            db: db,
            projectId: projectId,
            onNavigate: widget.onNavigate,
          ),
        ),
      );
    } catch (e) {
      if (context.mounted) {
        showErrorToastException(context, e);
      }
    }
  }

  Future<void> _copyWalletLabelsToProject({
    required AppDatabase db,
    required int projectId,
    required Map<String, String> keyLabels,
    required Map<int, String> pathLabels,
  }) async {
    try {
      final keys = await db.getKeysForProject(projectId);
      for (final key in keys) {
        final label = keyLabels[key.mfp];
        if (label != null && label.isNotEmpty) {
          await db.updateKeyName(key.id, label);
        }
      }
      final paths = await db.getSpendPathsForProject(projectId);
      for (final path in paths) {
        final label = pathLabels[path.rustId];
        if (label != null && label.isNotEmpty) {
          await db.updateSpendPathName(path.id, label);
        }
      }
    } catch (e, st) {
      debugPrint('Failed to copy wallet labels to project: $e\n$st');
    }
  }

  Future<void> _confirmRescan(
    BuildContext context,
    WalletDetailLoaded state,
  ) async {
    final l10n = context.l10n;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        titlePadding: kDialogTitlePadding,
        title: dialogCloseTitle(l10n.rescanConfirmTitle, onClose: () => Navigator.of(ctx).pop(false), tooltip: l10n.cancel),
        content: Text(l10n.rescanConfirmBody),
        actions: [
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text(l10n.rescanButton),
          ),
        ],
      ),
    );
    if (confirmed == true && context.mounted) {
      final settings = context.read<SettingsCubit>().state;
      final electrumUrl = settings.electrumUrlForNetwork(
        state.walletInfo.network,
      );
      context.read<WalletDetailCubit>().rescan(electrumUrl);
    }
  }

  Future<void> _exportBackup(
    BuildContext context,
    WalletDetailLoaded state,
  ) async {
    final walletPath = state.walletInfo.walletPath;
    final walletName = state.walletInfo.name;
    final service = context.read<WalletService>();
    final deviceKey = await service.getOrCreateEncryptionKey();
    final openPassword = service.getCachedPassword(walletPath);

    if (!context.mounted) return;

    // Always ask for an export password for portability
    final exportPassword = await showPasswordPrompt(
      context,
      title: 'Set backup password',
      subtitle: 'This password protects the backup file.',
      confirmRequired: true,
    );
    if (exportPassword == null || !context.mounted) return;

    final List<int> backupBytes;
    try {
      backupBytes = await rust_wallet.exportWalletBackup(
        walletPath: walletPath,
        deviceKeyHex: deviceKey,
        openPassword: openPassword,
        exportPassword: exportPassword,
      );
    } catch (e) {
      if (context.mounted) showErrorToastException(context, e);
      return;
    }

    if (!context.mounted) return;

    final safeName = walletName.replaceAll(RegExp(r'[^a-zA-Z0-9_-]'), '_');
    final fileName = '$safeName.deadbolt';

    // Desktop: native save dialog. Mobile: share sheet.
    if (defaultTargetPlatform == TargetPlatform.android ||
        defaultTargetPlatform == TargetPlatform.iOS) {
      try {
        final tempDir = await getTemporaryDirectory();
        final file = File(p.join(tempDir.path, fileName));
        await file.writeAsBytes(backupBytes);
        if (context.mounted) {
          await Share.shareXFiles(
            [XFile(file.path, mimeType: 'application/octet-stream')],
            subject: fileName,
          );
        }
      } catch (e) {
        if (context.mounted) showErrorToastException(context, e);
      }
    } else {
      try {
        final savedPath = await FilePicker.platform.saveFile(
          fileName: fileName,
          type: FileType.any,
          bytes: Uint8List.fromList(backupBytes),
        );
        if (savedPath == null) return;
        // Some desktop implementations don't write the bytes themselves
        if (!File(savedPath).existsSync()) {
          await File(savedPath).writeAsBytes(backupBytes);
        }
        if (context.mounted) showSuccessToast(context, 'Backup saved');
      } catch (e) {
        if (context.mounted) showErrorToastException(context, e);
      }
    }
  }

  Future<void> _exportLabels(
    BuildContext context,
    WalletDetailLoaded state,
  ) async {
    final cubit = context.read<WalletDetailCubit>();
    final l10n = context.l10n;
    final content = await cubit.exportBip329Labels();
    if (!context.mounted) return;
    if (content == null || content.isEmpty) {
      showErrorToast(context, l10n.exportBip329Empty);
      return;
    }
    final safeName = state.walletInfo.name
        .replaceAll(RegExp(r'[^\w\-]'), '_')
        .toLowerCase();
    showTextExportSheet(
      context,
      text: content,
      fileName: '${safeName}_labels',
      copiedMessage: l10n.exportBip329Copied,
      fileExtension: 'jsonl',
    );
  }

  Future<void> _exportDescriptor(
    BuildContext context,
    WalletDetailLoaded state,
  ) async {
    final l10n = context.l10n;
    final safeName = state.walletInfo.name
        .replaceAll(RegExp(r'[^\w\-]'), '_')
        .toLowerCase();
    await showDescriptorExportSheet(
      context,
      descriptor: state.walletInfo.descriptor,
      fileName: '${safeName}_descriptor',
      copiedMessage: l10n.copiedToClipboard,
    );
  }

  Future<void> _exportWithChoice(
    BuildContext context,
    WalletDetailLoaded state,
  ) async {
    final l10n = context.l10n;
    final choice = await showDialog<_ExportChoice>(
      context: context,
      builder: (ctx) => SimpleDialog(
        title: Text(l10n.exportBip329Button),
        children: [
          SimpleDialogOption(
            onPressed: () => Navigator.of(ctx).pop(_ExportChoice.labels),
            child: Row(
              children: [
                const Icon(Icons.label_outline, size: 20),
                const SizedBox(width: 12),
                Text(l10n.exportLabelsOption),
              ],
            ),
          ),
          SimpleDialogOption(
            onPressed: () => Navigator.of(ctx).pop(_ExportChoice.descriptor),
            child: Row(
              children: [
                const Icon(Icons.schema_outlined, size: 20),
                const SizedBox(width: 12),
                Text(l10n.descriptorTabLabel),
              ],
            ),
          ),
          SimpleDialogOption(
            onPressed: () => Navigator.of(ctx).pop(_ExportChoice.wallet),
            child: const Row(
              children: [
                Icon(Icons.save_alt_outlined, size: 20),
                SizedBox(width: 12),
                Text('Wallet'),
              ],
            ),
          ),
        ],
      ),
    );
    if (choice == null || !context.mounted) return;
    if (choice == _ExportChoice.labels) {
      _exportLabels(context, state);
    } else if (choice == _ExportChoice.descriptor) {
      _exportDescriptor(context, state);
    } else {
      _exportBackup(context, state);
    }
  }

  Future<void> _importLabels(
    BuildContext context,
    WalletDetailLoaded state,
  ) async {
    final l10n = context.l10n;
    final content = await showTextImportSheet(context);
    if (content == null || content.trim().isEmpty) return;
    if (!context.mounted) return;
    final ok = await context.read<WalletDetailCubit>().importBip329Labels(content);
    if (context.mounted && ok) showSuccessToast(context, l10n.importBip329Success);
  }

  Future<void> _importWithChoice(
    BuildContext context,
    WalletDetailLoaded state,
  ) async {
    final l10n = context.l10n;
    final choice = await showDialog<_ImportChoice>(
      context: context,
      builder: (ctx) => SimpleDialog(
        title: Text(l10n.importBip329Button),
        children: [
          SimpleDialogOption(
            onPressed: () => Navigator.of(ctx).pop(_ImportChoice.labels),
            child: Row(
              children: [
                const Icon(Icons.label_outline, size: 20),
                const SizedBox(width: 12),
                Text(l10n.exportLabelsOption),
              ],
            ),
          ),
          SimpleDialogOption(
            onPressed: () => Navigator.of(ctx).pop(_ImportChoice.psbt),
            child: Row(
              children: [
                const Icon(Icons.receipt_long_outlined, size: 20),
                const SizedBox(width: 12),
                Text(l10n.importPsbtOption),
              ],
            ),
          ),
        ],
      ),
    );
    if (choice == null || !context.mounted) return;
    if (choice == _ImportChoice.labels) {
      _importLabels(context, state);
    } else {
      _importPsbt(context);
    }
  }

  Future<void> _importPsbt(BuildContext context) async {
    final l10n = context.l10n;
    final psbtBase64 = await showPsbtImportSheet(context);
    if (psbtBase64 == null || psbtBase64.isEmpty) return;
    if (!context.mounted) return;
    try {
      final imported =
          await context.read<WalletDetailCubit>().importPsbt(psbtBase64);
      if (imported == null) return;
      if (context.mounted) {
        showSuccessToast(
          context,
          imported.wasMerged ? l10n.importPsbtMerged : l10n.importPsbtSaved,
        );
      }
    } catch (e) {
      if (context.mounted) showErrorToastException(context, e);
    }
  }

  Widget _buildLoaded(BuildContext context, WalletDetailLoaded state) {
    final l10n = context.l10n;
    final network = state.walletInfo.network;

    return Scaffold(
      appBar: AppBar(
        title: Text(state.walletInfo.name),
        actions: [
          MfpBadge(
            label: localizedNetworkDisplayName(context, network.name),
            color: AppAccent.color,
            letterSpacing: 0.0,
          ),
          const SizedBox(width: 4),
          PopupMenuButton<_WalletMenuAction>(
            tooltip: l10n.moreOptionsTooltip,
            onSelected: (action) => _onMenuAction(context, action, state),
            itemBuilder: (_) => [
              iconMenuItem(value: _WalletMenuAction.send, icon: Icons.arrow_upward, label: l10n.walletSendButton),
              iconMenuItem(value: _WalletMenuAction.receive, icon: Icons.arrow_downward, label: l10n.walletReceiveButton),
              const PopupMenuDivider(),
              iconMenuItem(value: _WalletMenuAction.sync, icon: Icons.sync, label: l10n.syncButton, enabled: !state.isSyncing),
              iconMenuItem(value: _WalletMenuAction.rescan, icon: Icons.manage_search, label: l10n.rescanButton),
              const PopupMenuDivider(),
              iconMenuItem(value: _WalletMenuAction.exportLabels, icon: Icons.upload_outlined, label: l10n.exportBip329Button),
              iconMenuItem(value: _WalletMenuAction.importLabels, icon: Icons.download_outlined, label: l10n.importBip329Button),
              const PopupMenuDivider(),
              iconMenuItem(value: _WalletMenuAction.generateProject, icon: Icons.design_services_outlined, label: l10n.generateProjectFromWallet),
              if (state.walletInfo.protection.protectionType ==
                  APIProtectionType.userPassword) ...[
                const PopupMenuDivider(),
                iconMenuItem(value: _WalletMenuAction.lock, icon: Icons.lock_outline, label: 'Lock wallet'),
              ],
            ],
          ),
        ],
      ),
      body: SafeArea(
        child: switch (state.selectedTab) {
          0 => _OverviewView(
            state: state,
            onSendTap: () => _openSendFlow(context, state),
            onReceiveTap: () => _openReceiveFlow(context, state),
            onSyncTap: () => _onMenuAction(context, _WalletMenuAction.sync, state),
            onRescanTap: () => _onMenuAction(context, _WalletMenuAction.rescan, state),
            onExportLabelsTap: () => _exportWithChoice(context, state),
            onImportLabelsTap: () => _importWithChoice(context, state),
            onHwTap: () => showHwActionsSheet(
              context,
              walletName: state.walletInfo.name,
              descriptor: state.walletInfo.descriptor,
              network: state.walletInfo.network,
            ),
          ),
          1 => TransactionsView(state: state),
          2 => AddressesView(state: state),
          3 => CoinsView(state: state),
          _ => _DescriptorView(state: state),
        },
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: state.selectedTab,
        onDestinationSelected: (index) =>
            context.read<WalletDetailCubit>().selectTab(index),
        destinations: [
          NavigationDestination(
            icon: const Icon(Icons.home_outlined),
            selectedIcon: const Icon(Icons.home),
            label: l10n.overviewTab,
          ),
          NavigationDestination(
            icon: const Icon(Icons.swap_horiz_outlined),
            selectedIcon: const Icon(Icons.swap_horiz),
            label: l10n.transactionsSection,
          ),
          NavigationDestination(
            icon: const Icon(Icons.account_balance_wallet_outlined),
            selectedIcon: const Icon(Icons.account_balance_wallet),
            label: l10n.addressesSection,
          ),
          NavigationDestination(
            icon: const Icon(Icons.toll_outlined),
            selectedIcon: const Icon(Icons.toll),
            label: l10n.coinsSection,
          ),
          NavigationDestination(
            icon: const Icon(Icons.schema_outlined),
            selectedIcon: const Icon(Icons.schema),
            label: l10n.descriptorTabLabel,
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────
// Overview view (tab 0) — balance + action buttons
// ─────────────────────────────────────────────────────────────

class _OverviewView extends StatelessWidget {
  final WalletDetailLoaded state;
  final VoidCallback onSendTap;
  final VoidCallback onReceiveTap;
  final VoidCallback onSyncTap;
  final VoidCallback onRescanTap;
  final VoidCallback onExportLabelsTap;
  final VoidCallback onImportLabelsTap;
  final VoidCallback onHwTap;

  const _OverviewView({
    required this.state,
    required this.onSendTap,
    required this.onReceiveTap,
    required this.onSyncTap,
    required this.onRescanTap,
    required this.onExportLabelsTap,
    required this.onImportLabelsTap,
    required this.onHwTap,
  });

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final balance = state.balance;
    final walletInfo = state.walletInfo;
    final totalSats =
        balance.confirmed +
        balance.trustedPending +
        balance.untrustedPending +
        balance.immature;
    final btcString = (totalSats.toDouble() / 100000000.0).toStringAsFixed(8);
    final lastSynced = walletInfo.lastSyncedAt != null
        ? DateTime.fromMillisecondsSinceEpoch(walletInfo.lastSyncedAt! * 1000)
        : null;

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        // ── Balance card ────────────────────────────────────────────────────
        Card(
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  l10n.balanceBtc(btcString),
                  style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  children: [
                    _BalanceChip(
                      label: l10n.balanceConfirmed,
                      sats: balance.confirmed.toInt(),
                    ),
                    if (balance.trustedPending + balance.untrustedPending >
                        BigInt.zero)
                      _BalanceChip(
                        label: l10n.balancePending,
                        sats: (balance.trustedPending +
                                balance.untrustedPending)
                            .toInt(),
                        dimmed: true,
                      ),
                    if (balance.immature > BigInt.zero)
                      _BalanceChip(
                        label: l10n.balanceImmature,
                        sats: balance.immature.toInt(),
                        dimmed: true,
                      ),
                  ],
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        lastSynced != null
                            ? l10n.lastSynced(_formatOverviewDateTime(lastSynced))
                            : l10n.notYetSynced,
                        style: TextStyle(
                          fontSize: 12,
                          color: Theme.of(context)
                              .colorScheme
                              .onSurface
                              .withAlpha(AppAlpha.secondary),
                        ),
                      ),
                    ),
                    if (state.isSyncing)
                      const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                  ],
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 20),

        // ── Primary actions ─────────────────────────────────────────────────
        Row(
          children: [
            Expanded(
              child: _ActionButton(
                icon: Icons.arrow_upward,
                label: l10n.walletSendButton,
                filled: true,
                onTap: onSendTap,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _ActionButton(
                icon: Icons.arrow_downward,
                label: l10n.walletReceiveButton,
                filled: true,
                onTap: onReceiveTap,
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),

        // ── Secondary actions ───────────────────────────────────────────────
        Row(
          children: [
            Expanded(
              child: _ActionButton(
                icon: Icons.sync,
                label: l10n.syncButton,
                enabled: !state.isSyncing,
                onTap: onSyncTap,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _ActionButton(
                icon: Icons.manage_search,
                label: l10n.rescanButton,
                onTap: onRescanTap,
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: _ActionButton(
                icon: Icons.upload_outlined,
                label: l10n.exportBip329Button,
                onTap: onExportLabelsTap,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _ActionButton(
                icon: Icons.download_outlined,
                label: l10n.importBip329Button,
                onTap: onImportLabelsTap,
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        _ActionButton(
          icon: Icons.memory,
          label: 'Hardware wallet',
          onTap: onHwTap,
        ),
      ],
    );
  }

  String _formatOverviewDateTime(DateTime dt) {
    return '${dt.day}/${dt.month}/${dt.year} '
        '${dt.hour.toString().padLeft(2, '0')}:'
        '${dt.minute.toString().padLeft(2, '0')}';
  }
}

class _ActionButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool filled;
  final bool enabled;
  final VoidCallback onTap;

  const _ActionButton({
    required this.icon,
    required this.label,
    this.filled = false,
    this.enabled = true,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Card(
      color: filled ? scheme.primaryContainer : scheme.surfaceContainerHighest,
      child: InkWell(
        onTap: enabled ? onTap : null,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 8),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                icon,
                size: 28,
                color: enabled
                    ? (filled
                        ? scheme.onPrimaryContainer
                        : scheme.onSurfaceVariant)
                    : scheme.onSurface.withAlpha(AppAlpha.muted),
              ),
              const SizedBox(height: 8),
              Text(
                label,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: filled ? FontWeight.bold : FontWeight.normal,
                  color: enabled
                      ? (filled
                          ? scheme.onPrimaryContainer
                          : scheme.onSurfaceVariant)
                      : scheme.onSurface.withAlpha(AppAlpha.muted),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────
// Shared widgets (balance card, sync row, tx tile, etc.)
// ─────────────────────────────────────────────────────────────

class _BalanceChip extends StatelessWidget {
  final String label;
  final int sats;
  final bool dimmed;

  const _BalanceChip({
    required this.label,
    required this.sats,
    this.dimmed = false,
  });

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: Theme.of(context).textTheme.labelSmall?.copyWith(
            color: Theme.of(
              context,
            ).colorScheme.onSurface.withAlpha(dimmed ? 97 : 178),
          ),
        ),
        Text(
          l10n.balanceSats(sats),
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
            color: Theme.of(
              context,
            ).colorScheme.onSurface.withAlpha(dimmed ? 97 : 210),
          ),
        ),
      ],
    );
  }
}

enum _WalletMenuAction { send, receive, sync, rescan, exportLabels, importLabels, generateProject, lock }


enum _ExportChoice { labels, descriptor, wallet }

enum _ImportChoice { labels, psbt }

// ─────────────────────────────────────────────────────────────
// Descriptor view (tab 4)
// ─────────────────────────────────────────────────────────────

Color _walletColorForMfpIndex(BuildContext context, int index) {
  final ext = Theme.of(context).extension<KeyColorExtension>()!;
  return ext.keyColors[index % ext.keyColors.length];
}

class _DescriptorView extends StatelessWidget {
  final WalletDetailLoaded state;

  const _DescriptorView({required this.state});

  @override
  Widget build(BuildContext context) {
    if (!state.descriptorLoaded) {
      return const Center(child: CircularProgressIndicator());
    }

    final analysis = state.descriptorAnalysis;
    if (analysis == null) {
      return Center(
        child: Text(
          context.l10n.descriptorSectionTitle,
          style: TextStyle(
            color: Theme.of(context).colorScheme.onSurface.withAlpha(AppAlpha.secondary),
          ),
        ),
      );
    }

    final isTaproot = analysis.walletType.name == 'p2Tr';
    final l10n = context.l10n;

    return DefaultTabController(
      length: 3,
      child: Column(
        children: [
          TabBar(
            tabs: [
              Tab(text: l10n.spendPathsSection(analysis.spendPaths.length)),
              Tab(text: l10n.keysSection(analysis.keys.length)),
              Tab(text: l10n.descriptorSectionTitle),
            ],
          ),
          Expanded(
            child: TabBarView(
              children: [
                _WalletSpendPathsTab(
                  paths: analysis.spendPaths,
                  keys: analysis.keys,
                  keyLabels: state.keyLabels,
                  pathLabels: state.pathLabels,
                  isTaproot: isTaproot,
                ),
                _WalletKeysTab(
                  keys: analysis.keys,
                  keyLabels: state.keyLabels,
                  hotKeys: state.hotKeys,
                ),
                DescriptorTab(descriptor: analysis.descriptor),
              ],
            ),
          ),
        ],
      ),
    );
  }
}


// ─────────────────────────────────────────────────────────────
// Wallet keys tab
// ─────────────────────────────────────────────────────────────

class _WalletKeysTab extends StatelessWidget {
  final List<APIPubKey> keys;
  final Map<String, String> keyLabels;
  final List<APIHotKeyInfo> hotKeys;

  const _WalletKeysTab({
    required this.keys,
    required this.keyLabels,
    required this.hotKeys,
  });

  @override
  Widget build(BuildContext context) {
    final hotMfps = hotKeys.map((k) => k.mfp).toSet();
    final cubit = context.read<WalletDetailCubit>();
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
      children: [
        for (var i = 0; i < keys.length; i++)
          KeyCard(
            key: ValueKey(keys[i].mfp),
            mfp: keys[i].mfp,
            derivationPath: keys[i].derivationPath,
            xpub: keys[i].xpub,
            label: keyLabels[keys[i].mfp],
            mfpColor: _walletColorForMfpIndex(context, i),
            isHot: hotMfps.contains(keys[i].mfp),
            onNameSave: (name) => cubit.setWalletKeyLabel(keys[i].mfp, name ?? ''),
            onMakeHot: !hotMfps.contains(keys[i].mfp)
                ? () => showAddPrivateKeySheet(
                      context,
                      cubit: cubit,
                      expectedMfp: keys[i].mfp,
                      keyLabel: keyLabels[keys[i].mfp],
                    )
                : null,
            onRevealSeed: hotMfps.contains(keys[i].mfp)
                ? () => cubit.revealHotKey(keys[i].mfp)
                : null,
            onDeletePrivateInfo: hotMfps.contains(keys[i].mfp)
                ? () => cubit.deleteHotKey(keys[i].mfp)
                : null,
            deletePrivateInfoDisclaimer: context.l10n.deleteWalletPrivateKeyDisclaimer,
          ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────
// Wallet spend paths tab
// ─────────────────────────────────────────────────────────────

class _WalletSpendPathsTab extends StatelessWidget {
  final List<APISpendPath> paths;
  final List<APIPubKey> keys;
  final Map<String, String> keyLabels;
  final Map<int, String> pathLabels;
  final bool isTaproot;

  const _WalletSpendPathsTab({
    required this.paths,
    required this.keys,
    required this.keyLabels,
    required this.pathLabels,
    required this.isTaproot,
  });

  Color _colorForMfp(BuildContext context, String mfp) {
    final idx = keys.indexWhere((k) => k.mfp == mfp);
    return _walletColorForMfpIndex(context, idx < 0 ? 0 : idx);
  }

  String _keyLabel(String mfp) => keyLabels[mfp] ?? mfp.toUpperCase();

  @override
  Widget build(BuildContext context) {
    if (paths.isEmpty) return const SizedBox.shrink();
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
      children: [
        for (final path in paths)
          _WalletPathCard(
            path: path,
            label: pathLabels[path.id],
            isTaproot: isTaproot,
            mfpColorProvider: (mfp) => _colorForMfp(context, mfp),
            keyLabelProvider: _keyLabel,
          ),
      ],
    );
  }
}

class _WalletPathCard extends StatelessWidget {
  final APISpendPath path;
  final String? label;
  final bool isTaproot;
  final Color Function(String mfp) mfpColorProvider;
  final String Function(String mfp) keyLabelProvider;

  const _WalletPathCard({
    required this.path,
    required this.isTaproot,
    required this.mfpColorProvider,
    required this.keyLabelProvider,
    this.label,
  });

  String get _autoPathLabel =>
      BitcoinFormatter.pathLabel(path.threshold, path.mfps, keyLabelProvider);

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final isKeyPath = path.trDepth == -1;
    final hasRelTimelock = path.relTimelock.value > 0;
    final hasAbsTimelock = path.absTimelock.value > 0;
    final hasTimelock = hasRelTimelock || hasAbsTimelock;

    final relType = path.relTimelock.timelockType == APIRelativeTimelockType.blocks
        ? RelativeTimelockType.blocks
        : RelativeTimelockType.time;
    final absType = path.absTimelock.timelockType == APIAbsoluteTimelockType.blocks
        ? AbsoluteTimelockType.blocks
        : AbsoluteTimelockType.timestamp;
    final timelockLabel = hasRelTimelock
        ? BitcoinFormatter.formatRelativeTimelock(relType, path.relTimelock.value)
        : BitcoinFormatter.formatAbsoluteTimelock(absType, path.absTimelock.value);

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
        leading: _buildLeading(context),
        title: Row(
          children: [
            Expanded(
              child: Text(
                label ?? _autoPathLabel,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight:
                      label != null ? FontWeight.w600 : FontWeight.normal,
                  color: label != null
                      ? cs.onSurface
                      : cs.onSurface.withAlpha(AppAlpha.muted),
                  fontStyle:
                      label != null ? FontStyle.normal : FontStyle.italic,
                ),
              ),
            ),
            if (hasTimelock)
              PathTimelockBadge(isRelative: hasRelTimelock, label: timelockLabel),
            if (isTaproot && isKeyPath) const PathKeyPathBadge(),
          ],
        ),
        trailing: const Icon(Icons.chevron_right, size: 18),
        onTap: () => showWalletPathSheet(
          context,
          path: path,
          initialLabel: label,
          isTaproot: isTaproot,
          mfpColorProvider: mfpColorProvider,
          keyLabelProvider: keyLabelProvider,
          onLabelSave: (name) =>
              context.read<WalletDetailCubit>().setWalletPathLabel(
                path.id,
                name ?? '',
              ),
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 4),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                ...path.mfps.map((mfp) {
                  final label = keyLabelProvider(mfp);
                  return MfpBadge(
                    label: label,
                    color: mfpColorProvider(mfp),
                    letterSpacing: label == mfp.toUpperCase() ? 0.5 : 0.0,
                  );
                }),
              ],
            ),
            const SizedBox(height: 6),
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  const Icon(Icons.payments_outlined,
                      size: 13, color: AppAccent.color),
                  const SizedBox(width: 4),
                  Text(
                    '${BitcoinFormatter.formatDouble(path.vbSweep, 2)} vB',
                    style: TextStyle(
                      fontSize: 11,
                      color: cs.onSurface.withAlpha(AppAlpha.mediumHigh),
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  if (path.trDepth >= 0) ...[
                    _buildSeparator(context),
                    const Icon(Icons.account_tree_outlined,
                        size: 13, color: AppAccent.color),
                    const SizedBox(width: 4),
                    Text(
                      '${path.trDepth}',
                      style: TextStyle(
                          fontSize: 11,
                          color: cs.onSurface.withAlpha(AppAlpha.mediumHigh)),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildLeading(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final mfps = path.mfps;
    return SizedBox(
      width: 40,
      height: 40,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          CircleAvatar(
            radius: 18,
            backgroundColor: AppAccent.color.withAlpha(AppAlpha.subtle),
            child: Icon(
              mfps.length == 1 ? Icons.key : Icons.diversity_3,
              color: AppAccent.color,
              size: 20,
            ),
          ),
          if (mfps.length > 1)
            Positioned(
              right: -4,
              bottom: -4,
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                decoration: BoxDecoration(
                  color: AppAccent.color.withAlpha(AppAlpha.mediumLow),
                  border: Border.all(color: AppAccent.color, width: 1),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  '${path.threshold}/${mfps.length}',
                  style: TextStyle(
                    color: cs.onSurface.withAlpha(AppAlpha.mediumHigh),
                    fontSize: 9,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildSeparator(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8),
      child: Text(
        '|',
        style: TextStyle(
            color: Theme.of(context).colorScheme.onSurface.withAlpha(AppAlpha.hint)),
      ),
    );
  }

}

