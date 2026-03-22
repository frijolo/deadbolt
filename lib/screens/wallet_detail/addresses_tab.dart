import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import 'package:deadbolt/cubit/wallet_detail_cubit.dart';
import 'package:deadbolt/l10n/l10n.dart';
import 'package:deadbolt/src/rust/api/model.dart';
import 'package:deadbolt/theme/app_theme.dart';
import 'package:deadbolt/widgets/colored_address_text.dart';
import 'package:deadbolt/screens/wallet_detail/wallet_detail_shared.dart';
import 'package:deadbolt/widgets/loading_indicator.dart';

// ─────────────────────────────────────────────────────────────
// Addresses view (tab 2)
// ─────────────────────────────────────────────────────────────

class AddressesView extends StatelessWidget {
  final WalletDetailLoaded state;

  const AddressesView({super.key, required this.state});

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;

    return DefaultTabController(
      length: 2,
      initialIndex: state.selectedAddressKeychain,
      child: Column(
        children: [
          TabBar(
            onTap: (index) =>
                context.read<WalletDetailCubit>().selectAddressKeychain(index),
            tabs: [
              Tab(text: l10n.receiveAddresses),
              Tab(text: l10n.changeAddresses),
            ],
          ),
          Expanded(
            child: TabBarView(
              physics: const NeverScrollableScrollPhysics(),
              children: [
                _AddressList(
                  addresses: state.receiveAddresses,
                  loaded: state.receiveAddressesLoaded,
                  keychain: APIKeychain.external_,
                  network: state.walletInfo.network,
                ),
                _AddressList(
                  addresses: state.changeAddresses,
                  loaded: state.changeAddressesLoaded,
                  keychain: APIKeychain.internal,
                  network: state.walletInfo.network,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _AddressList extends StatelessWidget {
  final List<APIAddress> addresses;
  final bool loaded;
  final APIKeychain keychain;
  final APINetwork network;

  const _AddressList({
    required this.addresses,
    required this.loaded,
    required this.keychain,
    required this.network,
  });

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;

    if (!loaded) {
      return LoadingIndicator(message: l10n.loadingAddresses);
    }

    if (addresses.isEmpty) {
      return Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(
            l10n.noAddresses,
            textAlign: TextAlign.center,
            style: TextStyle(
              color: Theme.of(context)
                  .colorScheme
                  .onSurface
                  .withAlpha(AppAlpha.secondary),
            ),
          ),
          const SizedBox(height: 16),
          FilledButton.tonal(
            onPressed: () =>
                context.read<WalletDetailCubit>().revealMoreAddresses(keychain),
            child: Text(l10n.revealMoreAddresses),
          ),
        ],
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      itemCount: addresses.length + 1,
      itemBuilder: (context, index) {
        if (index == addresses.length) {
          return Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: FilledButton.tonal(
              onPressed: () => context
                  .read<WalletDetailCubit>()
                  .revealMoreAddresses(keychain),
              child: Text(l10n.revealMoreAddresses),
            ),
          );
        }
        return _AddressTile(
          address: addresses[index],
          keychain: keychain,
          network: network,
        );
      },
    );
  }
}

class _AddressTile extends StatelessWidget {
  final APIAddress address;
  final APIKeychain keychain;
  final APINetwork network;

  const _AddressTile({
    required this.address,
    required this.keychain,
    required this.network,
  });

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final balanceSats = address.balanceSat.toInt();
    final hasBalance = balanceSats > 0;
    final isReused = hasBalance && address.txCount > 1;
    final label = address.effectiveLabel;
    final isInherited = address.isAuto;

    final bool isSpent = address.isUsed && !hasBalance;
    final double opacity = isSpent ? 0.45 : 1.0;

    final Color badgeColor;
    final Color badgeBg;
    if (!address.isUsed) {
      badgeColor = Colors.green;
      badgeBg = Colors.green.withAlpha(AppAlpha.dim);
    } else if (isReused) {
      badgeColor = Colors.red;
      badgeBg = Colors.red.withAlpha(AppAlpha.dim);
    } else if (hasBalance) {
      badgeColor = Colors.orange;
      badgeBg = Colors.orange.withAlpha(AppAlpha.dim);
    } else {
      badgeColor =
          Theme.of(context).colorScheme.onSurface.withAlpha(AppAlpha.pale);
      badgeBg = Theme.of(context).colorScheme.surfaceContainerHighest;
    }

    return Opacity(
      opacity: opacity,
      child: Card(
        margin: const EdgeInsets.only(bottom: 8),
        child: ListTile(
          leading: CircleAvatar(
            backgroundColor: badgeBg,
            child: Text(
              l10n.addressIndex(address.index.toInt()),
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.bold,
                color: badgeColor,
              ),
            ),
          ),
          title: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (label != null)
                Row(
                  children: [
                    Icon(
                      isInherited ? Icons.label_outline : Icons.label,
                      size: 12,
                      color: isInherited
                          ? Theme.of(context).colorScheme.outline
                          : null,
                    ),
                    const SizedBox(width: 4),
                    Expanded(
                      child: Text(
                        label,
                        style: TextStyle(
                          fontWeight: isInherited ? null : FontWeight.w500,
                          fontStyle: isInherited ? FontStyle.italic : null,
                          color: isInherited
                              ? Theme.of(context).colorScheme.outline
                              : null,
                        ),
                      ),
                    ),
                  ],
                ),
              ColoredAddressText(address: address.address, truncate: true),
            ],
          ),
          subtitle: hasBalance
              ? Text(
                  l10n.addressBalanceSats(balanceSats),
                  style: TextStyle(
                    color: isReused ? Colors.red : Colors.orange,
                    fontWeight: FontWeight.w600,
                  ),
                )
              : null,
          trailing: const Icon(Icons.chevron_right, size: 18),
          onTap: () => _showDetails(context),
        ),
      ),
    );
  }

  void _showDetails(BuildContext context) {
    showWalletDialog(
      context,
      AddressDetailDialog(
          address: address, keychain: keychain, network: network),
    );
  }
}
