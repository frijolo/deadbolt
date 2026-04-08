import 'package:flutter/material.dart';

import 'package:deadbolt/l10n/l10n.dart';
import 'package:deadbolt/services/nostr_relay_settings.dart';

/// Full-screen settings page for managing Nostr relay URLs and connection
/// parameters (timeout and attempt count).
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
  int _timeoutSecs = NostrRelaySettings.defaultTimeoutSecs;
  int _maxAttempts = NostrRelaySettings.defaultMaxAttempts;
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
    final (relays, timeout, attempts) = await (
      _settings.loadRelays(),
      _settings.loadTimeoutSecs(),
      _settings.loadMaxAttempts(),
    ).wait;
    if (mounted) {
      setState(() {
        _relays = relays;
        _timeoutSecs = timeout;
        _maxAttempts = attempts;
        _loading = false;
      });
    }
  }

  Future<void> _removeRelay(String url) async {
    await _settings.removeRelay(url);
    setState(() => _relays.remove(url));
  }

  Future<void> _restoreDefaultRelays() async {
    await _settings.saveRelays(NostrRelaySettings.defaultRelays);
    setState(() => _relays = List.of(NostrRelaySettings.defaultRelays));
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
    setState(() {
      _relays.add(url);
      _controller.clear();
    });
  }

  Future<void> _saveTimeout(int secs) async {
    await _settings.saveTimeoutSecs(secs);
    await _settings.applyToRust();
    setState(() => _timeoutSecs = secs);
  }

  Future<void> _saveMaxAttempts(int n) async {
    await _settings.saveMaxAttempts(n);
    await _settings.applyToRust();
    setState(() => _maxAttempts = n);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(title: Text(l10n.nostrRelaysLabel)),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                Expanded(
                  child: ListView(
                    children: [
                      // ── Connection parameters ───────────────────────────────
                      Padding(
                        padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
                        child: Text(
                          l10n.nostrRelayTimeoutLabel,
                          style: theme.textTheme.labelMedium,
                        ),
                      ),
                      _StepperRow(
                        value: _timeoutSecs,
                        min: 5,
                        max: 120,
                        step: 5,
                        onChanged: _saveTimeout,
                      ),
                      Padding(
                        padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                        child: Text(
                          l10n.nostrRelayMaxAttemptsLabel,
                          style: theme.textTheme.labelMedium,
                        ),
                      ),
                      _StepperRow(
                        value: _maxAttempts,
                        min: 1,
                        max: 10,
                        step: 1,
                        onChanged: _saveMaxAttempts,
                      ),
                      const Divider(height: 32),
                      // ── Relay list ──────────────────────────────────────────
                      if (_relays.isEmpty)
                        Padding(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 16, vertical: 8),
                          child: Row(
                            children: [
                              Expanded(
                                child: Text(
                                  l10n.nostrRelaysSubtitle,
                                  style: theme.textTheme.bodyMedium?.copyWith(
                                    color: theme.colorScheme.onSurfaceVariant,
                                  ),
                                ),
                              ),
                              IconButton(
                                icon: const Icon(Icons.restore),
                                tooltip: l10n.restoreDefaults,
                                onPressed: _restoreDefaultRelays,
                              ),
                            ],
                          ),
                        )
                      else
                        ...List.generate(_relays.length, (i) {
                          final url = _relays[i];
                          return Column(
                            children: [
                              ListTile(
                                title: Text(
                                  url,
                                  overflow: TextOverflow.ellipsis,
                                  style: theme.textTheme.bodyMedium,
                                ),
                                trailing: IconButton(
                                  icon: const Icon(Icons.delete_outline),
                                  tooltip: l10n.delete,
                                  onPressed: () => _removeRelay(url),
                                ),
                              ),
                              if (i < _relays.length - 1)
                                const Divider(
                                    height: 1, indent: 16, endIndent: 16),
                            ],
                          );
                        }),
                    ],
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
                                if (!s.startsWith('wss://') &&
                                    !s.startsWith('ws://')) {
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

// ---------------------------------------------------------------------------
// Compact stepper row (− value +)
// ---------------------------------------------------------------------------

class _StepperRow extends StatelessWidget {
  final int value;
  final int min;
  final int max;
  final int step;
  final void Function(int) onChanged;

  const _StepperRow({
    required this.value,
    required this.min,
    required this.max,
    required this.step,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: Row(
        children: [
          IconButton(
            icon: const Icon(Icons.remove),
            onPressed: value - step >= min ? () => onChanged(value - step) : null,
          ),
          SizedBox(
            width: 48,
            child: Text(
              '$value',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyLarge,
            ),
          ),
          IconButton(
            icon: const Icon(Icons.add),
            onPressed: value + step <= max ? () => onChanged(value + step) : null,
          ),
        ],
      ),
    );
  }
}
