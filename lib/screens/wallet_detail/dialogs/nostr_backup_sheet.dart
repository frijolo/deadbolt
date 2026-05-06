import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:deadbolt/cubit/descriptor_sigs_cubit.dart';
import 'package:deadbolt/cubit/wallet_detail_cubit.dart';
import 'package:deadbolt/l10n/l10n.dart';
import 'package:deadbolt/screens/nostr_relays_screen.dart';
import 'package:deadbolt/screens/wallet_security_screen.dart';
import 'package:deadbolt/services/nostr_relay_settings.dart';
import 'package:deadbolt/services/wallet_service.dart';
import 'package:deadbolt/src/rust/api/wallet/nostr_backup.dart';
import 'package:deadbolt/utils/date_format.dart';
import 'package:deadbolt/utils/toast_helper.dart';
import 'package:deadbolt/utils/wallet_complexity.dart';
import 'package:deadbolt/widgets/dialog_helpers.dart';

Future<void> showNostrBackupSheet(
  BuildContext context, {
  required WalletDetailLoaded state,
}) {
  return showSheet(
    context,
    (ctx) => BlocProvider.value(
      value: context.read<WalletDetailCubit>(),
      child: _NostrBackupSheet(state: state),
    ),
  );
}

class _NostrBackupSheet extends StatelessWidget {
  final WalletDetailLoaded state;
  const _NostrBackupSheet({required this.state});

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final ts = Theme.of(context).textTheme;

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SheetHandle(),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 4),
          child: Text(l10n.nostrBackupTitle, style: ts.titleMedium),
        ),
        ConstrainedBox(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.of(context).size.height * 0.6,
          ),
          child: _NostrBackupContent(state: state),
        ),
      ],
    );
  }
}

class _NostrBackupContent extends StatefulWidget {
  final WalletDetailLoaded state;
  const _NostrBackupContent({required this.state});

  @override
  State<_NostrBackupContent> createState() => _NostrBackupContentState();
}

class _NostrBackupContentState extends State<_NostrBackupContent> {
  final _relaySettings = NostrRelaySettings();

  List<String> _relays = [];
  Map<String, NostrRelayStatus?> _statusMap = {};
  bool _checking = false;
  bool _publishing = false;
  DescriptorSigsCubit? _sigsCubit;

  @override
  void initState() {
    super.initState();
    _loadRelays();
    _sigsCubit = DescriptorSigsCubit(
      wallet: widget.state.walletHandle,
      participatingKeys: widget.state.descriptorAnalysis?.keys ?? [],
      hotKeyMfps: widget.state.hotKeys.map((k) => k.mfp).toSet(),
      network: widget.state.walletInfo.network,
    )..load();
  }

  @override
  void dispose() {
    _sigsCubit?.close();
    super.dispose();
  }

  Future<void> _loadRelays() async {
    final relays = await _relaySettings.loadRelays();
    if (!mounted) return;
    setState(() {
      _relays = relays;
      _statusMap = {for (final r in relays) r: null};
    });
  }

  Future<void> _checkStatus() async {
    if (_relays.isEmpty) return;
    setState(() => _checking = true);
    try {
      final statuses = await checkNostrBackupStatus(
        descriptor: widget.state.walletInfo.descriptor,
        relayUrls: _relays,
      );
      if (!mounted) return;
      setState(() {
        for (final s in statuses) {
          _statusMap[s.url] = s;
        }
      });
    } catch (e) {
      if (mounted) showErrorToastException(e);
    } finally {
      if (mounted) setState(() => _checking = false);
    }
  }

  Future<void> _publishBackup() async {
    if (_relays.isEmpty) return;
    setState(() => _publishing = true);
    final service = context.read<WalletService>();
    final deviceKey = await service.getOrCreateEncryptionKey();
    final walletPath = widget.state.walletInfo.walletPath;
    final openPassword = service.getCachedPassword(walletPath);
    try {
      final statuses = await publishNostrBackup(
        walletPath: walletPath,
        deviceKeyHex: deviceKey,
        openPassword: openPassword,
        relayUrls: _relays,
      );
      if (!mounted) return;
      setState(() {
        for (final s in statuses) {
          _statusMap[s.url] = s;
        }
      });
      if (mounted) showSuccessToast(context.l10n.nostrBackupPublished);
    } catch (e) {
      if (mounted) showErrorToastException(e);
    } finally {
      if (mounted) setState(() => _publishing = false);
    }
  }

  Future<void> _deleteBackup(String relayUrl) async {
    final l10n = context.l10n;
    final confirmed = await confirmDestructive(
      context,
      title: l10n.nostrBackupDelete,
      body: l10n.nostrBackupDeleteConfirm,
    );
    if (!confirmed || !mounted) return;

    setState(() => _statusMap[relayUrl] = NostrRelayStatus(
          url: relayUrl,
          hasBackup: false,
          lastPublishedAt: null,
          eventId: null,
          error: null,
          backedUpXpubs: 0,
          totalXpubs: _statusMap[relayUrl]?.totalXpubs ?? 0,
        ));

    try {
      final statuses = await deleteNostrBackup(
        descriptor: widget.state.walletInfo.descriptor,
        relayUrls: [relayUrl],
      );
      if (!mounted) return;
      setState(() {
        for (final s in statuses) {
          _statusMap[s.url] = s;
        }
      });
      if (mounted) showSuccessToast(l10n.nostrBackupDeleted);
    } catch (e) {
      if (mounted) showErrorToastException(e);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final cs = Theme.of(context).colorScheme;
    final ts = Theme.of(context).textTheme;
    final singlesig = isDescriptorTriviallyRecoverable(widget.state);
    final noteText = singlesig
        ? l10n.backupSinglesigShortNote
        : l10n.nostrBackupSecurityNote;
    final noteIcon = singlesig ? Icons.privacy_tip_outlined : Icons.info_outline;
    final noteColor = singlesig ? cs.error : cs.onSurfaceVariant;

    return SingleChildScrollView(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SizedBox(height: 8),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: cs.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(noteIcon, size: 16, color: noteColor),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      noteText,
                      style: ts.bodySmall?.copyWith(color: noteColor),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 8),
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                IconButton(
                  icon: const Icon(Icons.settings_outlined, size: 20),
                  tooltip: l10n.nostrRelaysLabel,
                  onPressed: () async {
                    await Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => const NostrRelaysScreen(),
                      ),
                    );
                    if (mounted) _loadRelays();
                  },
                ),
              ],
            ),
          ),
          if (_sigsCubit != null)
            _DescriptorSigStatusRow(
              sigsCubit: _sigsCubit!,
              walletState: widget.state,
            ),
          const SizedBox(height: 4),
          if (_relays.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Text(
                l10n.nostrBackupNoRelays,
                style: ts.bodySmall?.copyWith(color: cs.error),
              ),
            )
          else
            ...(_relays.map((url) => _RelayStatusTile(
                  url: url,
                  status: _statusMap[url],
                  onDelete: () => _deleteBackup(url),
                ))),
          const SizedBox(height: 12),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            child: Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _checking || _relays.isEmpty ? null : _checkStatus,
                    icon: _checking
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.refresh),
                    label: Text(_checking
                        ? l10n.nostrBackupChecking
                        : l10n.nostrBackupRefresh),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: FilledButton.icon(
                    onPressed: _publishing || _relays.isEmpty ? null : _publishBackup,
                    icon: _publishing
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                        : const Icon(Icons.cloud_upload_outlined),
                    label: Text(_publishing
                        ? l10n.nostrBackupPublishing
                        : l10n.nostrBackupPublish),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _RelayStatusTile extends StatelessWidget {
  final String url;
  final NostrRelayStatus? status;
  final VoidCallback onDelete;

  const _RelayStatusTile({
    required this.url,
    required this.status,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final cs = Theme.of(context).colorScheme;
    final ts = Theme.of(context).textTheme;

    final Color statusColor;
    final IconData statusIcon;
    String subtitle;

    if (status == null) {
      statusColor = cs.onSurfaceVariant;
      statusIcon = Icons.help_outline;
      subtitle = '';
    } else if (status!.error != null) {
      statusColor = cs.error;
      statusIcon = Icons.error_outline;
      subtitle = status!.error!;
    } else if (status!.hasBackup) {
      statusColor = Colors.green;
      statusIcon = Icons.check_circle_outline;
      final lastPublishedAt = status!.lastPublishedAt;
      final dateStr = lastPublishedAt != null
          ? formatDateTimeFromUnix(lastPublishedAt.toInt())
          : l10n.nostrBackupFound;
      subtitle = status!.totalXpubs > 1
          ? '${status!.backedUpXpubs}/${status!.totalXpubs} cosigners · $dateStr'
          : dateStr;
    } else if (status!.backedUpXpubs > 0) {
      statusColor = Colors.orange;
      statusIcon = Icons.warning_amber_outlined;
      subtitle = l10n.nostrBackupPartialCosigners(
          status!.backedUpXpubs, status!.totalXpubs);
    } else {
      statusColor = cs.error;
      statusIcon = Icons.cancel_outlined;
      subtitle = l10n.nostrBackupNotFound;
    }

    final icon = Icon(statusIcon, size: 18, color: statusColor);
    final hasBackup = status?.hasBackup == true;

    Widget? subtitleWidget;
    if (subtitle.isNotEmpty) {
      subtitleWidget = Text(
        subtitle,
        style: ts.bodySmall?.copyWith(color: statusColor),
        overflow: TextOverflow.ellipsis,
      );
    }

    return ListTile(
      dense: true,
      contentPadding: const EdgeInsets.only(left: 16, right: 4),
      leading: icon,
      title: Text(url, overflow: TextOverflow.ellipsis, style: ts.bodySmall),
      subtitle: subtitleWidget,
      trailing: hasBackup
          ? IconButton(
              icon: Icon(Icons.delete_outline, size: 18, color: cs.onSurfaceVariant),
              tooltip: l10n.nostrBackupDelete,
              onPressed: onDelete,
            )
          : null,
    );
  }
}

class _DescriptorSigStatusRow extends StatelessWidget {
  final DescriptorSigsCubit sigsCubit;
  final WalletDetailLoaded walletState;

  const _DescriptorSigStatusRow({
    required this.sigsCubit,
    required this.walletState,
  });

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final cs = Theme.of(context).colorScheme;
    final ts = Theme.of(context).textTheme;
    final keys = walletState.descriptorAnalysis?.keys ?? [];
    final total = keys.length;

    return BlocBuilder<DescriptorSigsCubit, DescriptorSigsState>(
      bloc: sigsCubit,
      builder: (ctx, sigsState) {
        final int signed;
        final bool anyInvalid;
        final bool allVerified;
        if (sigsState is DescriptorSigsLoaded) {
          signed = sigsState.sigs.length;
          anyInvalid = sigsState.sigs.any((s) => !s.isValid);
          allVerified = total > 0 && signed >= total && !anyInvalid;
        } else {
          signed = 0;
          anyInvalid = false;
          allVerified = false;
        }

        final (IconData icon, Color color) = anyInvalid
            ? (Icons.dangerous_outlined, cs.error)
            : allVerified
                ? (Icons.verified_outlined, Colors.green)
                : (Icons.warning_amber_outlined, Colors.orange);

        final statusText = anyInvalid
            ? l10n.descriptorSigInvalid
            : allVerified
                ? l10n.descriptorSigVerified
                : l10n.descriptorSigsSummary(signed, total > 0 ? total : 1);

        final needsAttention = !allVerified;

        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Row(
            children: [
              Icon(icon, size: 16, color: color),
              const SizedBox(width: 8),
              Expanded(
                child: Text(statusText, style: ts.bodySmall?.copyWith(color: color)),
              ),
              if (needsAttention && total > 0)
                TextButton.icon(
                  style: TextButton.styleFrom(
                    visualDensity: VisualDensity.compact,
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                  ),
                  onPressed: () async {
                    await WalletSecurityScreen.push(
                      context,
                      cubit: context.read<WalletDetailCubit>(),
                    );
                    if (context.mounted) sigsCubit.load();
                  },
                  icon: const Icon(Icons.security, size: 16),
                  label: Text(l10n.goToSecurity, style: ts.labelSmall),
                ),
            ],
          ),
        );
      },
    );
  }
}

