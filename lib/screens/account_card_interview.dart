/// Pantalla temporal para elegir el diseño del card de cuenta descubierta.
/// Una vez decidido el diseño, eliminar este archivo.
library;

import 'package:flutter/material.dart';

import 'package:deadbolt/src/rust/api/model.dart';
import 'package:deadbolt/theme/app_theme.dart';
import 'package:deadbolt/utils/bitcoin_formatter.dart';
import 'package:deadbolt/widgets/colored_group_text.dart';
import 'package:deadbolt/widgets/mfp_badge.dart';

// ---------------------------------------------------------------------------
// Mock data
// ---------------------------------------------------------------------------

final _mockAccounts = [
  APIAccountInfo(
    accountIndex: 0,
    derivationPath: "84'/0'/0'",
    keyspec:
        "[aabbccdd/84'/0'/0']xpub6Gn3QNg8BnfNg4LCXasFoNVHqj68LBz5vr8a5FimSwm1sEVJUGjgqBGjfYHF9DRhCNRqAYS9VQpKXRkDWBagpNHJ7RR3d3mRY8P4X7sqW3g",
    walletType: APIWalletType.p2Wpkh,
    firstAddress: 'bc1qmockaddress0000000000000000000000000000',
    txCount: 5,
    balanceSat: BigInt.from(1234500),
  ),
  APIAccountInfo(
    accountIndex: 2,
    derivationPath: "84'/0'/2'",
    keyspec:
        "[aabbccdd/84'/0'/2']xpub6B2nVE8ZGnNb4LGPz9KxCz3Ua1QHPmAbS4R2NP1XmQ7TkDFTpxVGpVfBJUQ6HPJYDv9MnPk2XVkFsBLXzqy8E4QXy8e3FkTs1DP4p1BcrqY",
    walletType: APIWalletType.p2Wpkh,
    firstAddress: 'bc1qmockaddress0000000000000000000000000002',
    txCount: 12,
    balanceSat: BigInt.zero,
  ),
];

// ---------------------------------------------------------------------------
// Screen
// ---------------------------------------------------------------------------

class AccountCardInterviewScreen extends StatefulWidget {
  const AccountCardInterviewScreen({super.key});

  static Future<void> push(BuildContext context) => Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => const AccountCardInterviewScreen()),
      );

  @override
  State<AccountCardInterviewScreen> createState() =>
      _AccountCardInterviewScreenState();
}

class _AccountCardInterviewScreenState
    extends State<AccountCardInterviewScreen> {
  int? _selected;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Elige un diseño'),
        actions: [
          if (_selected != null)
            TextButton(
              onPressed: () => Navigator.pop(context, _selected),
              child: Text('Propuesta ${String.fromCharCode(65 + _selected!)}'),
            ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _buildVariant(
            label: 'A',
            description: 'Badge #N + path · tx·balance · [mfp] xpub corto',
            builder: _buildCardA,
          ),
          const SizedBox(height: 24),
          _buildVariant(
            label: 'B',
            description: 'MfpBadge + path + icono wallet · txs · balance · xpub coloreado',
            builder: _buildCardB,
          ),
          const SizedBox(height: 24),
          _buildVariant(
            label: 'C',
            description: 'Path · txs (una línea) + icono · xpub coloreado + balance',
            builder: _buildCardC,
          ),
          const SizedBox(height: 24),
          _buildVariant(
            label: 'D',
            description: 'xpub coloreado como elemento central · info compacta arriba · botón abajo',
            builder: _buildCardD,
          ),
        ],
      ),
    );
  }

  Widget _buildVariant({
    required String label,
    required String description,
    required Widget Function(APIAccountInfo account) builder,
  }) {
    final isSelected = _selected == label.codeUnitAt(0) - 65;
    final cs = Theme.of(context).colorScheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            GestureDetector(
              onTap: () =>
                  setState(() => _selected = label.codeUnitAt(0) - 65),
              child: Row(
                children: [
                  Icon(
                    isSelected
                        ? Icons.check_circle
                        : Icons.radio_button_unchecked,
                    size: 20,
                    color: isSelected ? cs.primary : cs.onSurfaceVariant,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    'Propuesta $label',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      color: isSelected ? cs.primary : null,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        Padding(
          padding: const EdgeInsets.only(left: 16, bottom: 8),
          child: Text(
            description,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: cs.onSurfaceVariant,
                ),
          ),
        ),
        for (final account in _mockAccounts) ...[
          builder(account),
          const SizedBox(height: 6),
        ],
      ],
    );
  }

  // --------------------------------------------------------------------------
  // Propuesta A — actual: badge #N + path + compact button
  // --------------------------------------------------------------------------
  Widget _buildCardA(APIAccountInfo account) {
    final cs = Theme.of(context).colorScheme;
    final btcValue = account.balanceSat.toDouble() / 1e8;
    final balanceText = account.balanceSat == BigInt.zero
        ? '0 BTC'
        : '${BitcoinFormatter.formatDouble(btcValue, 8)} BTC';

    final bracketEnd = account.keyspec.indexOf(']');
    final mfp = bracketEnd > 1
        ? account.keyspec.substring(1, bracketEnd).split('/').first
        : '';
    final xpub = bracketEnd >= 0
        ? account.keyspec.substring(bracketEnd + 1)
        : account.keyspec;
    final xpubShort = xpub.length > 16
        ? '${xpub.substring(0, 8)}…${xpub.substring(xpub.length - 6)}'
        : xpub;

    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 10, 8, 10),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 5, vertical: 1),
                        decoration: BoxDecoration(
                          color: cs.primaryContainer,
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(
                          '#${account.accountIndex}',
                          style: TextStyle(
                            fontSize: 10,
                            fontFamily: 'monospace',
                            color: cs.onPrimaryContainer,
                          ),
                        ),
                      ),
                      const SizedBox(width: 6),
                      Text(
                        account.derivationPath,
                        style: const TextStyle(
                          fontFamily: 'monospace',
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '${account.txCount} tx  ·  $balanceText',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '[$mfp] $xpubShort',
                    style: TextStyle(
                      fontFamily: 'monospace',
                      fontSize: 10,
                      color: cs.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            FilledButton.tonal(
              onPressed: () {},
              style: FilledButton.styleFrom(
                visualDensity: VisualDensity.compact,
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 0),
                textStyle: const TextStyle(fontSize: 12),
                minimumSize: const Size(0, 32),
              ),
              child: const Text('Crear'),
            ),
          ],
        ),
      ),
    );
  }

  // --------------------------------------------------------------------------
  // Propuesta B — MfpBadge + path + icon button · txs · balance · xpub colored
  // --------------------------------------------------------------------------
  Widget _buildCardB(APIAccountInfo account) {
    final btcValue = account.balanceSat.toDouble() / 1e8;
    final balanceText = account.balanceSat == BigInt.zero
        ? '0 BTC'
        : '${BitcoinFormatter.formatDouble(btcValue, 8)} BTC';

    final bracketEnd = account.keyspec.indexOf(']');
    final mfp = bracketEnd > 1
        ? account.keyspec.substring(1, bracketEnd).split('/').first
        : '';
    final xpub = bracketEnd >= 0
        ? account.keyspec.substring(bracketEnd + 1)
        : account.keyspec;

    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 10, 4, 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header: mfp badge + path + icon button
            Row(
              children: [
                MfpBadge(label: mfp, color: AppAccent.color),
                const SizedBox(width: 8),
                Text(
                  account.derivationPath,
                  style: const TextStyle(
                    fontFamily: 'monospace',
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const Spacer(),
                IconButton(
                  icon: const Icon(Icons.account_balance_wallet_outlined),
                  tooltip: 'Crear wallet',
                  visualDensity: VisualDensity.compact,
                  onPressed: () {},
                ),
              ],
            ),
            const SizedBox(height: 2),
            // txs
            Text(
              '${account.txCount} transacciones',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            // balance
            Text(
              balanceText,
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 4),
            // xpub coloreado truncado
            ColoredGroupText(
              text: xpub,
              fontSize: 11,
              truncate: true,
              monospace: true,
            ),
          ],
        ),
      ),
    );
  }

  // --------------------------------------------------------------------------
  // Propuesta C — una línea header (path · txs + icono) · xpub colored + balance
  // --------------------------------------------------------------------------
  Widget _buildCardC(APIAccountInfo account) {
    final cs = Theme.of(context).colorScheme;
    final btcValue = account.balanceSat.toDouble() / 1e8;
    final balanceText = account.balanceSat == BigInt.zero
        ? '0 BTC'
        : '${BitcoinFormatter.formatDouble(btcValue, 8)} BTC';

    final bracketEnd = account.keyspec.indexOf(']');
    final mfp = bracketEnd > 1
        ? account.keyspec.substring(1, bracketEnd).split('/').first
        : '';
    final xpub = bracketEnd >= 0
        ? account.keyspec.substring(bracketEnd + 1)
        : account.keyspec;

    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 8, 4, 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header row: path · txs · balance + icon button
            Row(
              children: [
                Text(
                  account.derivationPath,
                  style: const TextStyle(
                    fontFamily: 'monospace',
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                Text(
                  '  ·  ${account.txCount} tx  ·  $balanceText',
                  style: TextStyle(
                    fontSize: 12,
                    color: cs.onSurfaceVariant,
                  ),
                ),
                const Spacer(),
                IconButton(
                  icon: const Icon(Icons.add_circle_outline),
                  tooltip: 'Crear wallet',
                  visualDensity: VisualDensity.compact,
                  onPressed: () {},
                ),
              ],
            ),
            // xpub coloreado con mfp como prefijo
            Row(
              children: [
                Text(
                  '[$mfp] ',
                  style: TextStyle(
                    fontFamily: 'monospace',
                    fontSize: 10,
                    color: cs.onSurfaceVariant,
                  ),
                ),
                Expanded(
                  child: ColoredGroupText(
                    text: xpub,
                    fontSize: 10,
                    truncate: true,
                    monospace: true,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  // --------------------------------------------------------------------------
  // Propuesta D — info compacta arriba · xpub coloreado central · botón abajo
  // --------------------------------------------------------------------------
  Widget _buildCardD(APIAccountInfo account) {
    final cs = Theme.of(context).colorScheme;
    final btcValue = account.balanceSat.toDouble() / 1e8;
    final balanceText = account.balanceSat == BigInt.zero
        ? '0 BTC'
        : '${BitcoinFormatter.formatDouble(btcValue, 8)} BTC';

    final bracketEnd = account.keyspec.indexOf(']');
    final mfp = bracketEnd > 1
        ? account.keyspec.substring(1, bracketEnd).split('/').first
        : '';
    final xpub = bracketEnd >= 0
        ? account.keyspec.substring(bracketEnd + 1)
        : account.keyspec;

    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Top row: #N · path · txs · balance
            Row(
              children: [
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                  decoration: BoxDecoration(
                    color: cs.secondaryContainer,
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    '#${account.accountIndex}',
                    style: TextStyle(
                      fontSize: 10,
                      fontFamily: 'monospace',
                      color: cs.onSecondaryContainer,
                    ),
                  ),
                ),
                const SizedBox(width: 6),
                Text(
                  account.derivationPath,
                  style: const TextStyle(
                    fontFamily: 'monospace',
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const Spacer(),
                Text(
                  '${account.txCount} tx  ·  $balanceText',
                  style: TextStyle(fontSize: 11, color: cs.onSurfaceVariant),
                ),
              ],
            ),
            const SizedBox(height: 6),
            // xpub coloreado — elemento central
            Row(
              children: [
                Text(
                  '[$mfp]  ',
                  style: TextStyle(
                    fontFamily: 'monospace',
                    fontSize: 11,
                    color: cs.onSurfaceVariant,
                  ),
                ),
                Expanded(
                  child: ColoredGroupText(
                    text: xpub,
                    fontSize: 12,
                    truncate: true,
                    monospace: true,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            // Botón a ancho completo compacto
            SizedBox(
              width: double.infinity,
              child: FilledButton.tonal(
                onPressed: () {},
                style: FilledButton.styleFrom(
                  visualDensity: VisualDensity.compact,
                  textStyle: const TextStyle(fontSize: 12),
                  minimumSize: const Size(0, 32),
                ),
                child: const Text('Crear wallet'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
