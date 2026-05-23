import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:deadbolt/config/constants.dart' show kElectrumPrivacyWarningHiddenUntilKey;
import 'package:deadbolt/config/app_settings_extensions.dart';
import 'package:deadbolt/cubit/settings_cubit.dart';
import 'package:deadbolt/cubit/wallet_detail_cubit.dart';
import 'package:deadbolt/l10n/l10n.dart';
import 'package:deadbolt/src/rust/api/model.dart';
import 'package:deadbolt/utils/api_network_extensions.dart';
export 'package:deadbolt/cubit/wallet_detail_cubit.dart' show APIUtxo;
import 'package:deadbolt/theme/app_theme.dart';
import 'package:deadbolt/utils/enum_formatters.dart';
import 'package:deadbolt/services/wallet_service.dart';
import 'package:deadbolt/services/wallet_sync_service.dart';
import 'package:deadbolt/utils/toast_helper.dart';
import 'package:deadbolt/widgets/password_prompt_dialog.dart';
import 'package:deadbolt/screens/wallet_security_screen.dart';
import 'package:deadbolt/widgets/mfp_badge.dart';
import 'package:deadbolt/widgets/hw_actions_sheet.dart' show showHwActionsSheet;
import 'package:deadbolt/widgets/popup_menu_helpers.dart';
import 'package:deadbolt/widgets/dialog_helpers.dart';
import 'package:deadbolt/widgets/edit_name_dialog.dart';
import 'package:deadbolt/screens/create_tx_screen.dart';
import 'package:deadbolt/screens/settings_screen.dart';
import 'package:deadbolt/screens/wallet_detail/wallet_detail_shared.dart';
import 'package:deadbolt/screens/wallet_detail/receive_dialog.dart';
import 'package:deadbolt/screens/wallet_detail/transactions_tab.dart';
import 'package:deadbolt/screens/wallet_detail/addresses_tab.dart';
import 'package:deadbolt/screens/wallet_detail/coins_tab.dart';
import 'package:deadbolt/widgets/loading_indicator.dart';
import 'package:deadbolt/screens/wallet_detail/views/wallet_overview_tab.dart';
import 'package:deadbolt/screens/wallet_detail/views/wallet_descriptor_tab.dart';
import 'package:deadbolt/screens/wallet_detail/export_flow.dart' show showExportChoiceSheet, ExportChoice, exportLabels, exportDescriptor, exportBackup;
import 'package:deadbolt/screens/wallet_detail/dialogs/publish_backup_sheet.dart' show showPublishBackupSheet;

import 'package:deadbolt/screens/wallet_detail/import_flow.dart' show showImportChoiceSheet;
import 'package:deadbolt/screens/wallet_detail/migration_flow.dart' show migrateWalletToProject;
import 'package:deadbolt/cubit/tx_planning_cubit.dart';
import 'package:deadbolt/screens/tx_planning/tx_planning_screen.dart';

class WalletDetailScreen extends StatelessWidget {
  final String walletPath;
  final void Function(int)? onNavigate;

  const WalletDetailScreen({super.key, required this.walletPath, this.onNavigate});

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return BlocProvider(
      create: (ctx) {
        return WalletDetailCubit.create(
          service: ctx.read<WalletService>(),
          syncService: ctx.read<WalletSyncService>(),
        )..load(walletPath,
            openingMessage: l10n.openingWallet,
            loadingDataMessage: l10n.loadingWalletData,
            biometricUnlockReason: l10n.biometricWalletUnlockReason);
      },
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
  StreamSubscription<List<APIAutoBroadcastResult>>? _autoBroadcastSub;

  @override
  void dispose() {
    _autoBroadcastSub?.cancel();
    super.dispose();
  }

  void _maybeStartAutoSync(BuildContext context, WalletDetailState state) {
    if (_autoSyncStarted || state is! WalletDetailLoaded) return;
    _autoSyncStarted = true;
    final settings = context.read<SettingsCubit>().state;
    final electrumUrl = settings.electrumUrlForNetwork(
      state.walletInfo.network,
    );
    final cubit = context.read<WalletDetailCubit>();
    cubit.setFiatConfig(
      settings.fiatEnabled,
      settings.fiatCurrency,
      settings.fiatProvider,
    );
    cubit.registerWithSyncService(electrumUrl);

    _autoBroadcastSub?.cancel();
    final l10n = context.l10n;
    _autoBroadcastSub = cubit.autoBroadcastEvents.listen((results) {
      for (final r in results) {
        final txid = r.txid;
        if (txid != null) {
          showSuccessToast(l10n.psbtAutoBroadcastedToast(txid));
        } else if (r.error != null) {
          showErrorToast(
            l10n.psbtAutoBroadcastFailedToast(r.id.toInt(), r.error!),
          );
        }
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return MultiBlocListener(
      listeners: [
        BlocListener<WalletDetailCubit, WalletDetailState>(
          listener: (context, state) async {
            _maybeStartAutoSync(context, state);
            if (state is WalletDetailLoaded) {
              handleTransientError(state.errorMessage,
                  context.read<WalletDetailCubit>().clearError);
            }
            if (state is WalletDetailNeedsPassword) {
              if (!context.mounted) return;
              final String? credential;
              if (state.isXpubKey) {
                credential = await showXpubUnlockDialog(context,
                    walletPath: state.walletPath, network: state.network);
              } else {
                credential = await showPasswordPrompt(
                  context,
                  title: context.l10n.enterWalletPassword,
                  subtitle: context.l10n.walletPasswordSubtitle,
                );
              }
              if (credential != null && context.mounted) {
                context
                    .read<WalletDetailCubit>()
                    .load(state.walletPath,
                        password: credential,
                        openingMessage: context.l10n.openingWallet,
                        loadingDataMessage: context.l10n.loadingWalletData);
              } else if (context.mounted) {
                Navigator.of(context).maybePop();
              }
            }
          },
        ),
        BlocListener<SettingsCubit, AppSettings>(
          listenWhen: (prev, curr) =>
              prev.fiatEnabled != curr.fiatEnabled ||
              prev.fiatCurrency != curr.fiatCurrency ||
              prev.fiatProvider != curr.fiatProvider,
          listener: (context, settings) {
            context.read<WalletDetailCubit>().setFiatConfig(
                  settings.fiatEnabled,
                  settings.fiatCurrency,
                  settings.fiatProvider,
                );
          },
        ),
      ],
      child: BlocBuilder<WalletDetailCubit, WalletDetailState>(
        builder: (context, state) {
          return switch (state) {
            WalletDetailInitial() ||
            WalletDetailNeedsPassword() =>
              Scaffold(
                appBar: AppBar(),
                body: const Center(child: CircularProgressIndicator()),
              ),
            WalletDetailLoading(:final message) => Scaffold(
                appBar: AppBar(),
                body: LoadingIndicator(message: message),
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
      network: fresh.walletInfo.network,
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
        context.read<WalletDetailCubit>().sync();
      case _WalletMenuAction.rescan:
        _handleRescan(context, state);
      case _WalletMenuAction.exportLabels:
        _handleExport(context, state);
      case _WalletMenuAction.importLabels:
        _handleImport(context, state);
      case _WalletMenuAction.generateProject:
        _handleGenerateProject(context, state);
      case _WalletMenuAction.planSpacedTxs:
        _openTxPlanning(context);
      case _WalletMenuAction.lock:
        context.read<WalletDetailCubit>().lockWallet();
        Navigator.of(context).pop();
      case _WalletMenuAction.changeProtection:
        WalletSecurityScreen.push(
          context,
          cubit: context.read<WalletDetailCubit>(),
        );
      case _WalletMenuAction.rename:
        _handleRename(context, state);
    }
  }

  void _handleRename(BuildContext context, WalletDetailLoaded state) {
    final cubit = context.read<WalletDetailCubit>();
    final l10n = context.l10n;
    showEditNameDialog(
      context,
      title: l10n.renameWalletTitle,
      currentName: state.walletInfo.name,
      onSave: (newName) async {
        if (newName == null || newName.isEmpty) return;
        if (newName == state.walletInfo.name) return;
        final ok = await cubit.renameWallet(newName);
        if (!ok) return;
        if (context.mounted) {
          showSuccessToast(context.l10n.walletRenamedToast(newName));
        }
      },
    );
  }

  void _openTxPlanning(BuildContext context) {
    // The TxPlanningCubit is already provided at the loaded-state level so
    // it survives navigation back-and-forth without re-running `load()`.
    // The planning screen + every earmark consumer pick it up from
    // context.
    final cubit = context.read<TxPlanningCubit>();
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => BlocProvider<TxPlanningCubit>.value(
        value: cubit,
        child: BlocProvider<WalletDetailCubit>.value(
          value: context.read<WalletDetailCubit>(),
          child: const TxPlanningScreen(),
        ),
      ),
    ));
  }

  Future<void> _openReceiveFlow(
    BuildContext context,
    WalletDetailLoaded state,
  ) async {
    final cubit = context.read<WalletDetailCubit>();
    final address = await cubit.getNextReceiveAddress();
    if (!context.mounted) return;
    if (address == null) {
      showErrorToast(context.l10n.noUnusedReceiveAddress);
      return;
    }
    showWalletDialog(context, ReceiveDialog(address: address));
  }

  Future<void> _handleRescan(
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

  Future<void> _handleExport(
    BuildContext context,
    WalletDetailLoaded state,
  ) async {
    final choice = await showExportChoiceSheet(context);
    if (choice == null || !context.mounted) return;
    switch (choice) {
      case ExportChoice.labels:
        await exportLabels(context, state);
      case ExportChoice.descriptor:
        await exportDescriptor(context, state);
      case ExportChoice.publishDescriptor:
        await showPublishBackupSheet(context, state: state);
      case ExportChoice.wallet:
        await exportBackup(context, state);
    }
  }

  Future<void> _handleImport(
    BuildContext context,
    WalletDetailLoaded state,
  ) async {
    await showImportChoiceSheet(
      context,
      walletPath: state.walletInfo.walletPath,
      network: state.walletInfo.network,
    );
  }

  Future<void> _handleGenerateProject(
    BuildContext context,
    WalletDetailLoaded state,
  ) async {
    await migrateWalletToProject(
      context: context,
      descriptor: state.walletInfo.descriptor,
      walletName: state.walletInfo.name,
      keyLabels: state.keyLabels,
      pathLabels: state.pathLabels,
      onNavigate: widget.onNavigate!,
    );
  }

  Widget _buildElectrumPrivacyWarning(BuildContext context, WalletDetailLoaded state) {
    if (!state.walletInfo.network.isMainnet) return const SizedBox.shrink();
    final settings = context.watch<SettingsCubit>().state;
    if (settings.electrumUrlForNetwork(APINetwork.bitcoin) != AppSettings.kDefaultElectrumMainnet) {
      return const SizedBox.shrink();
    }
    return const _ElectrumPrivacyWarningBanner();
  }

  Widget _buildLoaded(BuildContext context, WalletDetailLoaded state) {
    final l10n = context.l10n;
    final network = state.walletInfo.network;

    // Mount the TxPlanningCubit at the loaded-state root so the earmark
    // badge in coins_tab and the Reserved balance chip in
    // wallet_overview_tab pick it up via `context.watch`, and
    // `_openTxPlanning` can push the screen with a `BlocProvider.value`
    // over the same instance (no duplicate sync subscriptions).
    return BlocProvider<TxPlanningCubit>(
      create: (_) => TxPlanningCubit(
        wallet: state.walletHandle,
        walletPath: state.walletInfo.walletPath,
        syncService: context.read<WalletSyncService>(),
        walletService: context.read<WalletService>(),
      ),
      child: Builder(builder: (context) => PopScope(
      canPop: state.selectedTab == WalletDetailCubit.tabOverview,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) return;
        context.read<WalletDetailCubit>().selectTab(WalletDetailCubit.tabOverview);
      },
      child: Scaffold(
        appBar: AppBar(
          title: Text(state.walletInfo.name),
          actions: [
            MfpBadge(
              label: localizedNetworkDisplayName(context, network.name),
              color: AppAccent.color,
              letterSpacing: 0.0,
            ),
            if (state.isSyncing)
              const SizedBox(
                width: 40,
                height: 40,
                child: Center(
                  child: SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                ),
              )
            else
              IconButton(
                icon: const Icon(Icons.sync),
                tooltip: l10n.syncTooltip,
                onPressed: () => _onMenuAction(context, _WalletMenuAction.sync, state),
              ),
            PopupMenuButton<_WalletMenuAction>(
              tooltip: l10n.moreOptionsTooltip,
              onSelected: (action) => _onMenuAction(context, action, state),
              itemBuilder: (_) => [
                // Primary actions
                iconMenuItem(value: _WalletMenuAction.send, icon: Icons.arrow_upward, label: l10n.walletSendButton),
                iconMenuItem(value: _WalletMenuAction.receive, icon: Icons.arrow_downward, label: l10n.walletReceiveButton),
                const PopupMenuDivider(),
                // Chain state
                iconMenuItem(value: _WalletMenuAction.sync, icon: Icons.sync, label: l10n.syncButton, enabled: !state.isSyncing),
                iconMenuItem(value: _WalletMenuAction.rescan, icon: Icons.manage_search, label: l10n.rescanButton),
                const PopupMenuDivider(),
                // Advanced operations
                iconMenuItem(
                  value: _WalletMenuAction.planSpacedTxs,
                  icon: Icons.lock_clock,
                  label: l10n.txPlanningMenuEntry,
                ),
                iconMenuItem(value: _WalletMenuAction.generateProject, icon: Icons.design_services_outlined, label: l10n.generateProjectFromWallet),
                const PopupMenuDivider(),
                // Labels I/O
                iconMenuItem(value: _WalletMenuAction.exportLabels, icon: Icons.upload_outlined, label: l10n.exportBip329Button),
                iconMenuItem(value: _WalletMenuAction.importLabels, icon: Icons.download_outlined, label: l10n.importBip329Button),
                const PopupMenuDivider(),
                // Wallet settings
                iconMenuItem(value: _WalletMenuAction.rename, icon: Icons.edit_outlined, label: l10n.renameWalletMenu),
                iconMenuItem(value: _WalletMenuAction.changeProtection, icon: Icons.security, label: l10n.walletSecurityLabel),
                if (state.walletInfo.protection.protectionType ==
                        APIProtectionType.userPassword ||
                    state.walletInfo.protection.protectionType ==
                        APIProtectionType.xpubKey) ...[
                  const PopupMenuDivider(),
                  iconMenuItem(value: _WalletMenuAction.lock, icon: Icons.lock_outline, label: l10n.lockWallet),
                ],
              ],
            ),
          ],
        ),
        body: SafeArea(
          child: Column(
            children: [
              _buildElectrumPrivacyWarning(context, state),
              Expanded(
                child: switch (state.selectedTab) {
                  WalletDetailCubit.tabOverview => OverviewView(
                    state: state,
                    onSendTap: () => _openSendFlow(context, state),
                    onReceiveTap: () => _openReceiveFlow(context, state),
                    onSyncTap: () => _onMenuAction(context, _WalletMenuAction.sync, state),
                    onRescanTap: () => _onMenuAction(context, _WalletMenuAction.rescan, state),
                    onExportLabelsTap: () => _handleExport(context, state),
                    onImportLabelsTap: () => _handleImport(context, state),
                    onHwTap: () => showHwActionsSheet(
                      context,
                      walletName: state.walletInfo.name,
                      descriptor: state.walletInfo.descriptor,
                      network: state.walletInfo.network,
                    ),
                    onChangeProtectionTap: () => WalletSecurityScreen.push(
                      context,
                      cubit: context.read<WalletDetailCubit>(),
                    ),
                  ),
                  WalletDetailCubit.tabTransactions => TransactionsView(state: state),
                  WalletDetailCubit.tabAddresses => AddressesView(state: state),
                  WalletDetailCubit.tabCoins => CoinsView(state: state),
                  _ => DescriptorView(state: state),
                },
              ),
            ],
          ),
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
              label: l10n.descriptorLabel,
            ),
          ],
        ),
      ),
      )),
    );
  }
}

enum _WalletMenuAction {
  send,
  receive,
  sync,
  rescan,
  exportLabels,
  importLabels,
  generateProject,
  planSpacedTxs,
  lock,
  changeProtection,
  rename,
}

class _ElectrumPrivacyWarningBanner extends StatefulWidget {
  const _ElectrumPrivacyWarningBanner();

  @override
  State<_ElectrumPrivacyWarningBanner> createState() => _ElectrumPrivacyWarningBannerState();
}

class _ElectrumPrivacyWarningBannerState extends State<_ElectrumPrivacyWarningBanner> {
  bool _hidden = true;

  @override
  void initState() {
    super.initState();
    _checkDismissed();
  }

  Future<void> _checkDismissed() async {
    final prefs = await SharedPreferences.getInstance();
    final hiddenUntil = prefs.getInt(kElectrumPrivacyWarningHiddenUntilKey);
    final nowHidden = hiddenUntil != null && DateTime.now().millisecondsSinceEpoch < hiddenUntil;
    if (mounted) setState(() => _hidden = nowHidden);
  }

  Future<void> _dismissFor7Days() async {
    final prefs = await SharedPreferences.getInstance();
    final until = DateTime.now().add(const Duration(days: 7)).millisecondsSinceEpoch;
    await prefs.setInt(kElectrumPrivacyWarningHiddenUntilKey, until);
    if (mounted) setState(() => _hidden = true);
  }

  @override
  Widget build(BuildContext context) {
    if (_hidden) return const SizedBox.shrink();
    final l10n = context.l10n;
    final cs = Theme.of(context).colorScheme;
    return Material(
      color: cs.secondaryContainer,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Icon(Icons.privacy_tip_outlined, size: 18, color: cs.onSecondaryContainer),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                l10n.electrumPrivacyWarning,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: cs.onSecondaryContainer,
                    ),
              ),
            ),
            Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                TextButton(
                  style: TextButton.styleFrom(foregroundColor: cs.onSecondaryContainer),
                  onPressed: () => Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => const SettingsScreen()),
                  ),
                  child: Text(l10n.goToSettings),
                ),
                TextButton(
                  style: TextButton.styleFrom(foregroundColor: cs.onSecondaryContainer),
                  onPressed: _dismissFor7Days,
                  child: Text(l10n.dismiss),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
