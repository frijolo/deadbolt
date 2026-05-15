import 'package:flutter/material.dart';

import 'package:deadbolt/theme/app_theme.dart';
import 'package:deadbolt/l10n/l10n.dart';
import 'package:deadbolt/src/rust/api/model.dart';
import 'package:deadbolt/utils/bitcoin_formatter.dart';
import 'package:deadbolt/utils/spend_path_unlock.dart';
import 'package:deadbolt/widgets/colored_group_text.dart';

/// Full-screen UTXO picker. Returns the selected [APIUtxo] list via
/// [Navigator.pop], or null if the user cancelled.
class CoinSelectorScreen extends StatefulWidget {
  final List<APIUtxo> allUtxos;
  final APISpendPath? selectedPath;
  final int tipHeight;
  final List<APIUtxo> initiallySelected;
  final Map<String, String> keyLabels;
  final APINetwork network;

  const CoinSelectorScreen({
    super.key,
    required this.allUtxos,
    required this.network,
    this.selectedPath,
    this.tipHeight = 0,
    this.initiallySelected = const [],
    this.keyLabels = const {},
  });

  static Future<List<APIUtxo>?> push(
    BuildContext context, {
    required List<APIUtxo> allUtxos,
    required APINetwork network,
    APISpendPath? selectedPath,
    int tipHeight = 0,
    List<APIUtxo> initiallySelected = const [],
    Map<String, String> keyLabels = const {},
  }) {
    return Navigator.of(context).push<List<APIUtxo>>(
      MaterialPageRoute(
        builder: (_) => CoinSelectorScreen(
          allUtxos: allUtxos,
          network: network,
          selectedPath: selectedPath,
          tipHeight: tipHeight,
          initiallySelected: initiallySelected,
          keyLabels: keyLabels,
        ),
      ),
    );
  }

  @override
  State<CoinSelectorScreen> createState() => _CoinSelectorScreenState();
}

class _CoinSelectorScreenState extends State<CoinSelectorScreen> {
  late final Set<String> _selectedIds;
  String _searchQuery = '';
  final _searchCtrl = TextEditingController();

  String _utxoId(APIUtxo u) => '${u.txid}:${u.vout}';

  @override
  void initState() {
    super.initState();
    _selectedIds = {for (final u in widget.initiallySelected) _utxoId(u)};
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  List<APIUtxo> get _filtered {
    final q = _searchQuery.trim().toLowerCase();
    if (q.isEmpty) return widget.allUtxos;
    return widget.allUtxos.where((u) {
      return u.address.toLowerCase().contains(q) ||
          u.valueSat.toString().contains(q);
    }).toList();
  }

  List<APIUtxo> get _selectedUtxos {
    return widget.allUtxos
        .where((u) => _selectedIds.contains(_utxoId(u)))
        .toList();
  }

  void _toggleUtxo(APIUtxo utxo) {
    setState(() {
      final id = _utxoId(utxo);
      if (_selectedIds.contains(id)) {
        _selectedIds.remove(id);
      } else {
        _selectedIds.add(id);
      }
    });
  }

  void _done() {
    Navigator.of(context).pop(_selectedUtxos);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final filtered = _filtered;
    final selectedCount = _selectedIds.length;

    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.coinSelectorTitle),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(56),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: TextField(
              controller: _searchCtrl,
              decoration: InputDecoration(
                hintText: l10n.coinSelectorTitle,
                prefixIcon: const Icon(Icons.search, size: 20),
                isDense: true,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
                contentPadding: const EdgeInsets.symmetric(vertical: 8),
                suffixIcon: _searchQuery.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.clear, size: 18),
                        onPressed: () {
                          _searchCtrl.clear();
                          setState(() => _searchQuery = '');
                        },
                      )
                    : null,
              ),
              onChanged: (v) => setState(() => _searchQuery = v),
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: _done,
            child: Text(
              selectedCount > 0
                  ? l10n.coinSelectorDoneCount(selectedCount)
                  : l10n.coinSelectDone,
            ),
          ),
        ],
      ),
      body: SafeArea(
        child: filtered.isEmpty
            ? Center(
                child: Text(
                  l10n.noCoins,
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.onSurface.withAlpha(AppAlpha.secondary),
                  ),
                ),
              )
            : ListView.builder(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                itemCount: filtered.length,
                itemBuilder: (context, index) {
                  final utxo = filtered[index];
                  final isSelected = _selectedIds.contains(_utxoId(utxo));
                  return _CoinSelectorTile(
                    utxo: utxo,
                    isSelected: isSelected,
                    selectedPath: widget.selectedPath,
                    tipHeight: widget.tipHeight,
                    keyLabels: widget.keyLabels,
                    onTap: () => _toggleUtxo(utxo),
                  );
                },
              ),
      ),
    );
  }
}

class _CoinSelectorTile extends StatelessWidget {
  final APIUtxo utxo;
  final bool isSelected;
  final APISpendPath? selectedPath;
  final int tipHeight;
  final Map<String, String> keyLabels;
  final VoidCallback onTap;

  const _CoinSelectorTile({
    required this.utxo,
    required this.isSelected,
    required this.onTap,
    this.selectedPath,
    this.tipHeight = 0,
    this.keyLabels = const {},
  });

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final sats = utxo.valueSat.toInt();
    final isChange = utxo.keychain == APIKeychain.internal;

    // Timelock status for the currently selected spend path
    SpendPathStatus? timelockStatus;
    if (selectedPath != null) {
      final hasTimelock = selectedPath!.relTimelock.value > 0 ||
          selectedPath!.absTimelock.value > 0;
      if (hasTimelock) {
        timelockStatus =
            spendPathStatus(path: selectedPath!, utxo: utxo, tipHeight: tipHeight);
      }
    }

    final isMempool = utxo.mempoolSpendingTxid != null;
    final isSpending = isMempool || utxo.pendingPsbtIds.isNotEmpty;

    // Selection color takes priority; spending coins are faded when not selected.
    final cardColor = isSelected
        ? theme.colorScheme.primaryContainer.withAlpha(AppAlpha.pale)
        : null;
    final opacity = isSelected
        ? 1.0
        : isMempool
        ? 0.35
        : isSpending
        ? 0.55
        : 1.0;

    return Opacity(
      opacity: opacity,
      child: Card(
      margin: const EdgeInsets.only(bottom: 8),
      color: cardColor,
      clipBehavior: Clip.antiAlias,
      child: ListTile(
        leading: Checkbox(
          value: isSelected,
          onChanged: (_) => onTap(),
        ),
        onTap: onTap,
        title: Text(
          BitcoinFormatter.satsLabel(sats),
          style: const TextStyle(fontWeight: FontWeight.w600),
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ColoredGroupText(text: utxo.address, truncate: true),
            const SizedBox(height: 2),
            Row(
              children: [
                if (isMempool)
                  _SelectorBadge(label: l10n.coinMempoolSpend, color: Colors.red)
                else if (utxo.pendingPsbtIds.isNotEmpty)
                  _SelectorBadge(label: l10n.coinPendingSpend, color: Colors.orange)
                else if (!utxo.isConfirmed)
                  _SelectorBadge(label: l10n.txUnconfirmed, color: Colors.grey),
                const SizedBox(width: 6),
                _SelectorBadge(
                  label: isChange ? l10n.coinKeychainChange : l10n.coinKeychainReceive,
                  color: isChange ? Colors.amber : Colors.green,
                ),
                if (timelockStatus != null) ...[
                  const SizedBox(width: 6),
                  _TimelockBadge(status: timelockStatus),
                ],
              ],
            ),
          ],
        ),
      ),
    ),
    );
  }
}

class _SelectorBadge extends StatelessWidget {
  final String label;
  final Color color;

  const _SelectorBadge({required this.label, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(top: 2),
      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
      decoration: BoxDecoration(
        color: color.withAlpha(AppAlpha.dim),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        label,
        style: TextStyle(fontSize: 10, color: color),
      ),
    );
  }
}

class _TimelockBadge extends StatelessWidget {
  final SpendPathStatus status;

  const _TimelockBadge({required this.status});

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;

    final (icon, color, label) = switch (status) {
      SpendPathUnlocked() => (
          Icons.lock_open,
          Colors.green,
          l10n.spendPathUnlocked,
        ),
      SpendPathUnconfirmed() => (
          Icons.hourglass_empty,
          Colors.amber,
          l10n.spendPathUnconfirmed,
        ),
      SpendPathNeedsSync() => (
          Icons.sync_disabled,
          Colors.grey,
          l10n.spendPathNeedsSync,
        ),
      SpendPathRelLocked(:final remainingBlocks) => (
          Icons.lock_clock,
          Colors.orange,
          remainingBlocks != null
              ? l10n.spendPathBlocks(remainingBlocks)
              : l10n.spendPathLocked,
        ),
      SpendPathAbsLocked(:final remainingBlocks) => (
          Icons.lock_outline,
          Colors.red,
          remainingBlocks != null
              ? l10n.spendPathBlocks(remainingBlocks)
              : l10n.spendPathLocked,
        ),
    };

    return Container(
      margin: const EdgeInsets.only(top: 2),
      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
      decoration: BoxDecoration(
        color: color.withAlpha(AppAlpha.dim),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: color.withAlpha(AppAlpha.pale)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 9, color: color),
          const SizedBox(width: 3),
          Text(
            label,
            style: TextStyle(
              fontSize: 10,
              color: color,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }
}
