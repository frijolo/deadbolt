import 'package:deadbolt/cubit/wallet_detail_cubit.dart' show WalletDetailLoaded;

/// True when the wallet's descriptor is trivially recoverable from the seed
/// or xpub via standard discovery: a single spend path with one signer and
/// no timelocks. For these wallets, publishing extra descriptor backups
/// (Nostr or on-chain) adds privacy risk without recovery benefit.
bool isDescriptorTriviallyRecoverable(WalletDetailLoaded state) {
  final analysis = state.descriptorAnalysis;
  if (analysis == null) return false;
  final paths = analysis.spendPaths;
  if (paths.length != 1) return false;
  final p = paths.first;
  if (p.threshold != 1 || p.mfps.length != 1) return false;
  if (p.relTimelock.value > 0 || p.absTimelock.value > 0) return false;
  return true;
}
