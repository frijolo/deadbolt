import 'package:flutter/material.dart';

import 'package:deadbolt/l10n/l10n.dart';
import 'package:deadbolt/services/nostr_relay_settings.dart';

/// Full-screen settings page for managing Nostr relay URLs.
class NostrRelaysScreen extends StatefulWidget {
  const NostrRelaysScreen({super.key});

  @override
  State<NostrRelaysScreen> createState() => _NostrRelaysScreenState();
}

class _NostrRelaysScreenState extends State<NostrRelaysScreen> {
  final _settings = NostrRelaySettings();
  final _controller = TextEditingController();
  final _formKey = GlobalKey<FormState>();

  List<String> _relays = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final relays = await _settings.loadRelays();
    if (mounted) setState(() { _relays = relays; _loading = false; });
  }

  Future<void> _removeRelay(String url) async {
    await _settings.removeRelay(url);
    setState(() => _relays.remove(url));
  }

  Future<void> _addRelay() async {
    if (!_formKey.currentState!.validate()) return;
    final url = _controller.text.trim();
    if (_relays.contains(url)) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(context.l10n.nostrRelayDuplicate)),
        );
      }
      return;
    }
    await _settings.addRelay(url);
    setState(() { _relays.add(url); _controller.clear(); });
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return Scaffold(
      appBar: AppBar(title: Text(l10n.nostrRelaysLabel)),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                Expanded(
                  child: _relays.isEmpty
                      ? Center(
                          child: Text(
                            l10n.nostrRelaysSubtitle,
                            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                                ),
                          ),
                        )
                      : ListView.separated(
                          itemCount: _relays.length,
                          separatorBuilder: (context, index) =>
                              const Divider(height: 1, indent: 16, endIndent: 16),
                          itemBuilder: (context, i) {
                            final url = _relays[i];
                            return ListTile(
                              title: Text(
                                url,
                                overflow: TextOverflow.ellipsis,
                                style: Theme.of(context).textTheme.bodyMedium,
                              ),
                              trailing: IconButton(
                                icon: const Icon(Icons.delete_outline),
                                tooltip: context.l10n.delete,
                                onPressed: () => _removeRelay(url),
                              ),
                            );
                          },
                        ),
                ),
                const Divider(height: 1),
                SafeArea(
                  top: false,
                  child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
                  child: Form(
                    key: _formKey,
                    child: Row(
                      children: [
                        Expanded(
                          child: TextFormField(
                            controller: _controller,
                            decoration: InputDecoration(
                              hintText: l10n.nostrRelayAddHint,
                              isDense: true,
                              border: const OutlineInputBorder(),
                            ),
                            validator: (v) {
                              final s = (v ?? '').trim();
                              if (s.isEmpty) return l10n.required;
                              if (!s.startsWith('wss://') && !s.startsWith('ws://')) {
                                return l10n.nostrRelayInvalidUrl;
                              }
                              return null;
                            },
                            onFieldSubmitted: (_) => _addRelay(),
                            textInputAction: TextInputAction.done,
                          ),
                        ),
                        const SizedBox(width: 8),
                        FilledButton(
                          onPressed: _addRelay,
                          child: Text(l10n.add),
                        ),
                      ],
                    ),
                  ),
                ),
                ),
              ],
            ),
    );
  }
}
