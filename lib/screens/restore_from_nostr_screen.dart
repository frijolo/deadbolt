import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:deadbolt/cubit/wallet_list_cubit.dart';
import 'package:deadbolt/utils/date_format.dart';
import 'package:deadbolt/l10n/l10n.dart';
import 'package:deadbolt/services/nostr_relay_settings.dart';
import 'package:deadbolt/services/wallet_service.dart';
import 'package:deadbolt/src/rust/api/wallet/nostr_backup.dart';
import 'package:deadbolt/utils/toast_helper.dart';

enum _Step { enterXpub, searching, found, importing }

class RestoreFromNostrScreen extends StatefulWidget {
  const RestoreFromNostrScreen({super.key});

  /// Push the screen and return the wallet path if an import succeeds.
  static Future<String?> push(BuildContext context) => Navigator.push<String>(
        context,
        MaterialPageRoute(
          fullscreenDialog: true,
          builder: (_) => const RestoreFromNostrScreen(),
        ),
      );

  @override
  State<RestoreFromNostrScreen> createState() => _RestoreFromNostrScreenState();
}

class _RestoreFromNostrScreenState extends State<RestoreFromNostrScreen> {
  final _xpubController = TextEditingController();
  final _credentialController = TextEditingController();
  final _xpubFormKey = GlobalKey<FormState>();

  _Step _step = _Step.enterXpub;

  /// All backups found for the searched xpub (one per distinct descriptor).
  List<NostrBackupResponse> _responses = [];

  /// One name override controller per found backup.
  List<TextEditingController> _nameControllers = [];

  @override
  void dispose() {
    _xpubController.dispose();
    _credentialController.dispose();
    for (final c in _nameControllers) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _search() async {
    if (!_xpubFormKey.currentState!.validate()) return;
    final xpub = _xpubController.text.trim();
    setState(() => _step = _Step.searching);

    try {
      final relays = await NostrRelaySettings().loadRelays();
      if (relays.isEmpty) {
        if (!mounted) return;
        throw Exception(context.l10n.nostrBackupNoRelays);
      }

      final responses = await fetchNostrBackup(
        xpub: xpub,
        relayUrls: relays,
      );

      // Build one name controller per found backup, pre-filled with wallet name.
      final nameControllers = responses
          .map((r) => TextEditingController(text: r.walletName ?? ''))
          .toList();

      setState(() {
        _responses = responses;
        for (final c in _nameControllers) {
          c.dispose();
        }
        _nameControllers = nameControllers;
        _credentialController.text = xpub;
        _step = _Step.found;
      });
    } catch (e) {
      if (mounted) {
        showErrorToastException(context, e);
        setState(() => _step = _Step.enterXpub);
      }
    }
  }

  Future<void> _import(int index) async {
    final resp = _responses[index];
    setState(() => _step = _Step.importing);

    try {
      final service = context.read<WalletService>();
      final deviceKey = await service.getOrCreateEncryptionKey();
      final walletsDir = await service.getWalletsDir();

      final nameOverride = _nameControllers[index].text.trim();

      final info = await importNostrBackup(
        backupBytes: resp.bytes.toList(),
        xpubCredential: _credentialController.text.trim(),
        deviceKeyHex: deviceKey,
        walletsDir: walletsDir,
        walletNameOverride: nameOverride.isEmpty ? null : nameOverride,
      );

      if (!mounted) return;
      context.read<WalletListCubit>().refresh();
      Navigator.pop(context, info.walletPath);
    } catch (e) {
      if (mounted) {
        showErrorToastException(context, e);
        setState(() => _step = _Step.found);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return Scaffold(
      appBar: AppBar(title: Text(l10n.nostrRestoreTitle)),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: switch (_step) {
            _Step.enterXpub => _buildEnterXpub(l10n),
            _Step.searching => _buildSearching(l10n),
            _Step.found => _buildFound(l10n),
            _Step.importing => _buildImporting(l10n),
          },
        ),
      ),
    );
  }

  Widget _buildEnterXpub(AppLocalizations l10n) => Form(
        key: _xpubFormKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(l10n.nostrRestoreEnterXpub),
            const SizedBox(height: 12),
            TextFormField(
              controller: _xpubController,
              decoration: InputDecoration(
                hintText: l10n.nostrRestoreXpubHint,
                border: const OutlineInputBorder(),
              ),
              minLines: 2,
              maxLines: 4,
              validator: (v) {
                if ((v ?? '').trim().isEmpty) return l10n.required;
                return null;
              },
            ),
            const SizedBox(height: 24),
            FilledButton(
              onPressed: _search,
              child: Text(l10n.nostrRestoreSearch),
            ),
          ],
        ),
      );

  Widget _buildSearching(AppLocalizations l10n) => Column(
        children: [
          const SizedBox(height: 40),
          const CircularProgressIndicator(),
          const SizedBox(height: 16),
          Text(l10n.nostrRestoreSearching),
        ],
      );

  Widget _buildFound(AppLocalizations l10n) {
    final cs = Theme.of(context).colorScheme;
    final ts = Theme.of(context).textTheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Credential field — shared for all found backups
        Text(l10n.nostrRestoreEnterCredential),
        const SizedBox(height: 8),
        TextFormField(
          controller: _credentialController,
          decoration: const InputDecoration(border: OutlineInputBorder()),
          minLines: 2,
          maxLines: 4,
        ),
        const SizedBox(height: 16),
        // Watch-only note
        Container(
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
                  l10n.nostrRestoreWatchOnlyNote,
                  style: ts.bodySmall?.copyWith(color: cs.onSurfaceVariant),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 20),
        // One card per found backup
        for (int i = 0; i < _responses.length; i++) ...[
          _buildBackupCard(l10n, i),
          const SizedBox(height: 12),
        ],
        OutlinedButton(
          onPressed: () => setState(() {
            _step = _Step.enterXpub;
            _responses = [];
          }),
          child: Text(l10n.cancel),
        ),
      ],
    );
  }

  Widget _buildBackupCard(AppLocalizations l10n, int index) {
    final resp = _responses[index];
    final cs = Theme.of(context).colorScheme;
    final ts = Theme.of(context).textTheme;
    final dateStr =
        resp.createdAt != null ? formatDateTimeFromUnix(resp.createdAt!.toInt()) : null;

    return Card(
      elevation: 0,
      color: cs.surfaceContainerHighest,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                const Icon(Icons.check_circle_outline, color: Colors.green, size: 18),
                const SizedBox(width: 8),
                Text(l10n.nostrRestoreFound,
                    style: ts.titleSmall?.copyWith(color: Colors.green)),
              ],
            ),
            const SizedBox(height: 8),
            if (resp.network != null) ...[
              _PreviewRow(l10n.nostrRestoreNetwork, resp.network!),
              const SizedBox(height: 4),
            ],
            if (dateStr != null) _PreviewRow(l10n.nostrRestoreDate, dateStr),
            const SizedBox(height: 12),
            TextFormField(
              controller: _nameControllers[index],
              decoration: InputDecoration(
                labelText: l10n.nostrRestoreWalletName,
                border: const OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            FilledButton(
              onPressed: () => _import(index),
              child: Text(l10n.nostrRestoreImport),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildImporting(AppLocalizations l10n) => Column(
        children: [
          const SizedBox(height: 40),
          const CircularProgressIndicator(),
          const SizedBox(height: 16),
          Text(l10n.nostrBackupPublishing),
        ],
      );
}

class _PreviewRow extends StatelessWidget {
  final String label;
  final String value;
  const _PreviewRow(this.label, this.value);

  @override
  Widget build(BuildContext context) {
    final ts = Theme.of(context).textTheme;
    final cs = Theme.of(context).colorScheme;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 90,
          child: Text(label,
              style: ts.bodySmall?.copyWith(color: cs.onSurfaceVariant)),
        ),
        Expanded(
          child: Text(value, style: ts.bodySmall),
        ),
      ],
    );
  }
}
