import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:deadbolt/cubit/wallet_detail_cubit.dart';
import 'package:deadbolt/utils/date_format.dart';
import 'package:deadbolt/l10n/l10n.dart';
import 'package:deadbolt/screens/nostr_relays_screen.dart';
import 'package:deadbolt/services/nostr_relay_settings.dart';
import 'package:deadbolt/services/wallet_service.dart';
import 'package:deadbolt/src/rust/api/wallet/nostr_backup.dart';
import 'package:deadbolt/utils/toast_helper.dart';
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

class _NostrBackupSheet extends StatefulWidget {
  final WalletDetailLoaded state;
  const _NostrBackupSheet({required this.state});

  @override
  State<_NostrBackupSheet> createState() => _NostrBackupSheetState();
}

class _NostrBackupSheetState extends State<_NostrBackupSheet> {
  final _relaySettings = NostrRelaySettings();

  List<String> _relays = [];
  // null = not yet checked
  Map<String, NostrRelayStatus?> _statusMap = {};
  bool _checking = false;
  bool _publishing = false;

  @override
  void initState() {
    super.initState();
    _loadRelays();
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
      if (mounted) showErrorToastException(context, e);
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
      if (mounted) showSuccessToast(context, context.l10n.nostrBackupPublished);
    } catch (e) {
      if (mounted) showErrorToastException(context, e);
    } finally {
      if (mounted) setState(() => _publishing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final cs = Theme.of(context).colorScheme;
    final ts = Theme.of(context).textTheme;

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SheetHandle(),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
          child: Row(
            children: [
              Text(l10n.nostrBackupTitle, style: ts.titleMedium),
              const Spacer(),
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
        // Security note
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
                Icon(Icons.info_outline, size: 16, color: cs.onSurfaceVariant),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    l10n.nostrBackupSecurityNote,
                    style: ts.bodySmall?.copyWith(color: cs.onSurfaceVariant),
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),
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
                  label: Text(_checking ? l10n.nostrBackupChecking : l10n.nostrBackupRefresh),
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
                  label: Text(_publishing ? l10n.nostrBackupPublishing : l10n.nostrBackupPublish),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _RelayStatusTile extends StatelessWidget {
  final String url;
  final NostrRelayStatus? status;

  const _RelayStatusTile({required this.url, required this.status});

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final cs = Theme.of(context).colorScheme;
    final ts = Theme.of(context).textTheme;

    Widget icon;
    String subtitle;
    Color? iconColor;

    if (status == null) {
      icon = Icon(Icons.help_outline, size: 18, color: cs.onSurfaceVariant);
      subtitle = '';
      iconColor = cs.onSurfaceVariant;
    } else if (status!.error != null) {
      icon = Icon(Icons.error_outline, size: 18, color: cs.error);
      subtitle = status!.error!;
      iconColor = cs.error;
    } else if (status!.hasBackup) {
      icon = const Icon(Icons.check_circle_outline, size: 18, color: Colors.green);
      iconColor = Colors.green;
      final ts = status!.lastPublishedAt;
      subtitle = ts != null
          ? formatDateTimeFromUnix(ts.toInt())
          : l10n.nostrBackupFound;
    } else {
      icon = Icon(Icons.cancel_outlined, size: 18, color: cs.error);
      subtitle = l10n.nostrBackupNotFound;
      iconColor = cs.error;
    }

    return ListTile(
      dense: true,
      contentPadding: const EdgeInsets.symmetric(horizontal: 16),
      leading: icon,
      title: Text(
        url,
        overflow: TextOverflow.ellipsis,
        style: ts.bodySmall,
      ),
      subtitle: subtitle.isNotEmpty
          ? Text(
              subtitle,
              style: ts.bodySmall?.copyWith(color: iconColor),
              overflow: TextOverflow.ellipsis,
            )
          : null,
    );
  }
}
