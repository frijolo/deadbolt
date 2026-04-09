import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart' show ShareParams, SharePlus, XFile;

import 'package:deadbolt/cubit/project_list_cubit.dart';
import 'package:deadbolt/cubit/settings_cubit.dart';
import 'package:deadbolt/cubit/wallet_detail_cubit.dart';
import 'package:deadbolt/data/database.dart';
import 'package:deadbolt/l10n/l10n.dart';
import 'package:deadbolt/src/rust/api/model.dart';
export 'package:deadbolt/cubit/wallet_detail_cubit.dart' show APIUtxo;
import 'package:deadbolt/theme/app_theme.dart';
import 'package:deadbolt/utils/enum_formatters.dart';
import 'package:deadbolt/services/wallet_service.dart';
import 'package:deadbolt/services/wallet_sync_service.dart';
import 'package:deadbolt/utils/toast_helper.dart';
import 'package:deadbolt/widgets/password_prompt_dialog.dart';
import 'package:deadbolt/screens/wallet_security_screen.dart';
import 'package:deadbolt/screens/export_backup_dialog.dart'
    show showExportBackupDialog;
import 'package:deadbolt/src/rust/api/wallet/backup.dart' as rust_backup;
import 'package:deadbolt/widgets/mfp_badge.dart';
import 'package:deadbolt/utils/export_sheet.dart' show showDescriptorExportSheet;
import 'package:deadbolt/widgets/hw_actions_sheet.dart' show showHwActionsSheet;
import 'package:deadbolt/widgets/text_export_sheet.dart'
    show showTextExportSheet;
import 'package:deadbolt/widgets/popup_menu_helpers.dart';
import 'package:deadbolt/widgets/dialog_helpers.dart';
import 'package:deadbolt/widgets/text_import_sheet.dart'
    show showTextImportSheet, showPsbtImportSheet;
import 'package:deadbolt/screens/create_tx_screen.dart';
import 'package:deadbolt/screens/project_detail_screen.dart';
import 'package:deadbolt/screens/settings_screen.dart';
import 'package:deadbolt/screens/wallet_detail/wallet_detail_shared.dart';
import 'package:deadbolt/screens/wallet_detail/receive_dialog.dart';
import 'package:deadbolt/screens/sweep_wif_screen.dart';
import 'package:deadbolt/screens/wallet_detail/transactions_tab.dart';
import 'package:deadbolt/screens/wallet_detail/addresses_tab.dart';
import 'package:deadbolt/screens/wallet_detail/coins_tab.dart';
import 'package:deadbolt/widgets/loading_indicator.dart';
import 'package:deadbolt/screens/wallet_detail/views/wallet_overview_tab.dart';
import 'package:deadbolt/screens/wallet_detail/views/wallet_descriptor_tab.dart';
import 'package:deadbolt/screens/wallet_detail/dialogs/nostr_backup_dialog.dart'
    show showNostrBackupSheet;

class WalletDetailScreen extends StatelessWidget {
  final String walletPath;
  final void Function(int)? onNavigate;

  const WalletDetailScreen({super.key, required this.walletPath, this.onNavigate});

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return BlocProvider(
      create: (ctx) {
        return WalletDetailCubit(
          service: ctx.read<WalletService>(),
          syncService: ctx.read<WalletSyncService>(),
        )..load(walletPath,
            openingMessage: l10n.openingWallet,
            loadingDataMessage: l10n.loadingWalletData);
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
      case _WalletMenuAction.changeProtection:
        WalletSecurityScreen.push(
          context,
          cubit: context.read<WalletDetailCubit>(),
        );
    }
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
        showErrorToastException(e);
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

    final opts = await showExportBackupDialog(context);
    if (opts == null || !context.mounted) return;

    if (!context.mounted) return;

    final List<int> backupBytes;
    try {
      backupBytes = await rust_backup.exportWalletBackup(
        walletPath: walletPath,
        deviceKeyHex: deviceKey,
        openPassword: openPassword,
        exportProtection: opts.protectionType,
        exportPassword: opts.password,
        securityLevel: opts.securityLevel,
      );
    } catch (e) {
      if (context.mounted) showErrorToastException(e);
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
          await SharePlus.instance.share(
            ShareParams(
              files: [XFile(file.path, mimeType: 'application/octet-stream')],
              subject: fileName,
            ),
          );
        }
      } catch (e) {
        if (context.mounted) showErrorToastException(e);
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
        if (context.mounted) showSuccessToast(context.l10n.backupSaved);
      } catch (e) {
        if (context.mounted) showErrorToastException(e);
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
      showErrorToast(l10n.exportBip329Empty);
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
      bigText: true,
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
    final choice = await showSheet<_ExportChoice>(context, (ctx) => Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        ListTile(
          leading: const Icon(Icons.label_outline),
          title: Text(l10n.exportLabelsOption),
          onTap: () => Navigator.of(ctx).pop(_ExportChoice.labels),
        ),
        ListTile(
          leading: const Icon(Icons.schema_outlined),
          title: Text(l10n.descriptorLabel),
          onTap: () => Navigator.of(ctx).pop(_ExportChoice.descriptor),
        ),
        ListTile(
          leading: const Icon(Icons.save_alt_outlined),
          title: Text(l10n.walletExportLabel),
          onTap: () => Navigator.of(ctx).pop(_ExportChoice.wallet),
        ),
        ListTile(
          leading: const Icon(Icons.backup_outlined),
          title: Text(l10n.nostrBackupMenu),
          onTap: () => Navigator.of(ctx).pop(_ExportChoice.nostr),
        ),
        const SizedBox(height: 8),
      ],
    ));
    if (choice == null || !context.mounted) return;
    if (choice == _ExportChoice.labels) {
      _exportLabels(context, state);
    } else if (choice == _ExportChoice.descriptor) {
      _exportDescriptor(context, state);
    } else if (choice == _ExportChoice.nostr) {
      showNostrBackupSheet(context, state: state);
    } else {
      _exportBackup(context, state);
    }
  }

  Future<void> _importLabels(
    BuildContext context,
    WalletDetailLoaded state,
  ) async {
    final l10n = context.l10n;
    final content = await showTextImportSheet(context, bigText: true);
    if (content == null || content.trim().isEmpty) return;
    if (!context.mounted) return;
    final ok = await context.read<WalletDetailCubit>().importBip329Labels(content);
    if (context.mounted && ok) showSuccessToast(l10n.importBip329Success);
  }

  Future<void> _importWithChoice(
    BuildContext context,
    WalletDetailLoaded state,
  ) async {
    final l10n = context.l10n;
    final choice = await showSheet<_ImportChoice>(context, (ctx) => Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        ListTile(
          leading: const Icon(Icons.label_outline),
          title: Text(l10n.exportLabelsOption),
          onTap: () => Navigator.of(ctx).pop(_ImportChoice.labels),
        ),
        ListTile(
          leading: const Icon(Icons.receipt_long_outlined),
          title: Text(l10n.importPsbtOption),
          onTap: () => Navigator.of(ctx).pop(_ImportChoice.psbt),
        ),
        ListTile(
          leading: const Icon(Icons.vpn_key_outlined),
          title: Text(ctx.l10n.sweepWifTitle),
          onTap: () => Navigator.of(ctx).pop(_ImportChoice.sweepWif),
        ),
        const SizedBox(height: 8),
      ],
    ));
    if (choice == null || !context.mounted) return;
    switch (choice) {
      case _ImportChoice.labels:
        _importLabels(context, state);
      case _ImportChoice.psbt:
        _importPsbt(context);
      case _ImportChoice.sweepWif:
        _openSweepWif(context, state);
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
          imported.wasMerged ? l10n.importPsbtMerged : l10n.importPsbtSaved,
        );
      }
    } catch (e) {
      if (context.mounted) showErrorToastException(e);
    }
  }

  void _openSweepWif(BuildContext context, WalletDetailLoaded state) {
    final cubit = context.read<WalletDetailCubit>();
    SweepWifScreen.push(
      context,
      network: state.walletInfo.network,
      currentWalletPath: state.walletInfo.walletPath,
      getNextAddress: () => cubit.getNextReceiveAddress(),
      getAddressForWallet: (path) => cubit.getNextReceiveAddressFor(path),
      onSwept: () => cubit.sync(),
    );
  }

  Widget _buildElectrumPrivacyWarning(BuildContext context, WalletDetailLoaded state) {
    if (state.walletInfo.network != APINetwork.bitcoin) return const SizedBox.shrink();
    final settings = context.watch<SettingsCubit>().state;
    if (settings.electrumUrlForNetwork(APINetwork.bitcoin) != AppSettings.kDefaultElectrumMainnet) {
      return const SizedBox.shrink();
    }
    return const _ElectrumPrivacyWarningBanner();
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
              const PopupMenuDivider(),
              iconMenuItem(value: _WalletMenuAction.changeProtection, icon: Icons.security, label: l10n.walletSecurityLabel),
              if (state.walletInfo.protection.protectionType ==
                      APIProtectionType.userPassword ||
                  state.walletInfo.protection.protectionType ==
                      APIProtectionType.xpubKey) ...[
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
                0 => OverviewView(
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
                  onChangeProtectionTap: () => WalletSecurityScreen.push(
                    context,
                    cubit: context.read<WalletDetailCubit>(),
                  ),
                ),
                1 => TransactionsView(state: state),
                2 => AddressesView(state: state),
                3 => CoinsView(state: state),
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
    );
  }
}


enum _WalletMenuAction { send, receive, sync, rescan, exportLabels, importLabels, generateProject, lock, changeProtection }

enum _ExportChoice { labels, descriptor, wallet, nostr }

enum _ImportChoice { labels, psbt, sweepWif }

const _kElectrumPrivacyWarningHiddenUntilKey = 'electrumPrivacyWarningHiddenUntil';

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
    final hiddenUntil = prefs.getInt(_kElectrumPrivacyWarningHiddenUntilKey);
    final nowHidden = hiddenUntil != null && DateTime.now().millisecondsSinceEpoch < hiddenUntil;
    if (mounted) setState(() => _hidden = nowHidden);
  }

  Future<void> _dismissFor7Days() async {
    final prefs = await SharedPreferences.getInstance();
    final until = DateTime.now().add(const Duration(days: 7)).millisecondsSinceEpoch;
    await prefs.setInt(_kElectrumPrivacyWarningHiddenUntilKey, until);
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
