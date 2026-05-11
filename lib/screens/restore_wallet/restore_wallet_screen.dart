import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import 'package:deadbolt/cubit/hw_wallet_cubit.dart';
import 'package:deadbolt/config/app_settings_extensions.dart';
import 'package:deadbolt/cubit/settings_cubit.dart';
import 'package:deadbolt/cubit/wallet_list_cubit.dart';
import 'package:deadbolt/l10n/l10n.dart';
import 'package:deadbolt/screens/simple_wallet_dialog.dart';
import 'package:deadbolt/screens/wallet_detail_screen.dart';
import 'package:deadbolt/services/nostr_relay_settings.dart';
import 'package:deadbolt/services/wallet_service.dart';
import 'package:deadbolt/src/rust/api/hw_wallet.dart' as rust_hw;
import 'package:deadbolt/src/rust/api/model.dart';
import 'package:deadbolt/src/rust/api/wallet/descriptor_recovery.dart' as rust_onchain;
import 'package:deadbolt/src/rust/api/wallet/discovery.dart' as rust_discovery;
import 'package:deadbolt/src/rust/api/wallet/nostr_backup.dart' as rust_nostr;
import 'package:deadbolt/theme/app_theme.dart';
import 'package:deadbolt/utils/bitcoin_formatter.dart';
import 'package:deadbolt/utils/date_format.dart';
import 'package:deadbolt/utils/toast_helper.dart';
import 'package:deadbolt/widgets/add_key_dialog.dart' show KeyspecResult, kKeyspecPattern;
import 'package:deadbolt/widgets/mfp_badge.dart';

import '_hardware_tab.dart';
import '_seed_tab.dart';
import '_xpub_tab.dart';

enum RestoreScriptType { legacy, nestedSegwit, nativeSegwit, taproot }

enum _ScanPhase {
  idle,
  deriving, // HW only: exporting keys from device
  scanning, // on-chain + Nostr
  done,
  error,
}

class _NostrFoundBackup {
  final String xpub;
  final List<int> bytes;
  final String? walletName;
  final String? network;
  final int? createdAt;
  final String? firstAddress;
  final APIWalletType? walletType;
  final String? descriptor;
  final rust_nostr.APIDescriptorSigVerification? descriptorSigVerification;
  int? txCount;
  BigInt? balanceSat;

  _NostrFoundBackup({
    required this.xpub,
    required this.bytes,
    this.walletName,
    this.network,
    this.createdAt,
    this.firstAddress,
    this.walletType,
    this.descriptor,
    this.descriptorSigVerification,
  });
}

class _OnChainFoundBackup {
  final String xpub;
  final List<int> bytes;
  final String commitTxid;
  final String? revealTxid;
  final String? walletName;
  final String? network;
  final int? createdAt;
  final String? firstAddress;
  final APIWalletType? walletType;
  final String? descriptor;
  final int anchorsReachable;
  final int anchorsTotal;
  int? txCount;
  BigInt? balanceSat;

  _OnChainFoundBackup({
    required this.xpub,
    required this.bytes,
    required this.commitTxid,
    this.revealTxid,
    this.walletName,
    this.network,
    this.createdAt,
    this.firstAddress,
    this.walletType,
    this.descriptor,
    this.anchorsReachable = 0,
    this.anchorsTotal = 0,
  });
}

typedef _UnifiedWallet = ({
  String? firstAddress,
  String? firstAddressHash,
  String? walletName,
  String? derivationPath,
  APIWalletType? walletType,
  int? txCount,
  BigInt? balanceSat,
  bool hasNostrBackup,
  bool hasOnChainBackup,
  String? commitTxid,
  bool isExisting,
  String? existingWalletName,
});

class RestoreWalletScreen extends StatefulWidget {
  const RestoreWalletScreen({super.key});

  static Future<void> push(BuildContext context) => Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => BlocProvider(
            create: (_) => HwWalletCubit()..restoreOrScan(),
            child: const RestoreWalletScreen(),
          ),
        ),
      );

  @override
  State<RestoreWalletScreen> createState() => _RestoreWalletScreenState();
}

class _RestoreWalletScreenState extends State<RestoreWalletScreen>
    with SingleTickerProviderStateMixin {
  // ── Shared settings ────────────────────────────────────────────────────────
  late APINetwork _selectedNetwork;
  int _accountGapLimit = 20;
  int _addressGapLimit = 20;

  // ── Scan phase ─────────────────────────────────────────────────────────────
  _ScanPhase _phase = _ScanPhase.idle;
  String? _errorMessage;
  // HW-specific progress during deriving phase
  int _derivedCount = 0;
  int _totalToDeriving = 0;
  // Seed credentials from the last seed scan; null when using xpub/HW tab.
  String? _lastSeedMnemonic;
  String? _lastSeedPassphrase;
  // Active search modes for the current scan (used by scanning-phase UI).
  bool _searchNostrActive = false;
  bool _searchOnChainActive = false;

  // ── Results ────────────────────────────────────────────────────────────────
  List<APIAccountInfo> _accounts = [];
  int _totalScanned = 0;
  Map<String, APIWalletInfo> _walletByFirstAddressHash = {};
  List<_UnifiedWallet> _unifiedWallets = [];
  // Index maps for O(1) lookups in card widget.
  Map<String, _NostrFoundBackup> _nostrByAddress = {};
  Map<String, _OnChainFoundBackup> _onChainByAddress = {};
  Map<String, APIAccountInfo> _accountByAddress = {};
  // True when Nostr was searched but every relay failed due to network errors.
  bool _nostrAllRelaysFailed = false;

  // ── Tab controller ─────────────────────────────────────────────────────────
  late TabController _tabController;

  // Track which tab triggered the last scan so error retry restores the UI.
  int _lastActiveTab = 0;

  @override
  void initState() {
    super.initState();
    _selectedNetwork = context.read<SettingsCubit>().state.network;
    _tabController = TabController(length: 3, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  String get _electrumUrl =>
      context.read<SettingsCubit>().state.electrumUrlForNetwork(_selectedNetwork);

  // ── Scan entry points ──────────────────────────────────────────────────────

  void _resetScanState(_ScanPhase startPhase) {
    setState(() {
      _phase = startPhase;
      _errorMessage = null;
      _accounts = [];
      _totalScanned = 0;
      _nostrAllRelaysFailed = false;
      _searchNostrActive = false;
      _searchOnChainActive = false;
    });
  }

  Future<void> _onSeedScan(
    String mnemonic,
    String? passphrase,
    RestoreScriptType? scriptFilter,
    bool nonStandardPaths,
    bool searchNostr,
    bool searchOnChain,
  ) async {
    _lastActiveTab = 1;
    _lastSeedMnemonic = mnemonic;
    _lastSeedPassphrase = passphrase;
    _resetScanState(_ScanPhase.scanning);
    setState(() {
      _searchNostrActive = searchNostr;
      _searchOnChainActive = searchOnChain;
    });

    final types = scriptFilter != null
        ? [scriptFilter]
        : RestoreScriptType.values;
    final url = _electrumUrl;

    try {
      final futures = types.map((t) => rust_discovery.discoverAccounts(
            mnemonic: mnemonic,
            passphrase: passphrase,
            walletType: _toWalletType(t),
            network: _selectedNetwork,
            electrumUrl: url,
            accountGapLimit: _accountGapLimit,
            addressGapLimit: _addressGapLimit,
            nonStandardPaths: nonStandardPaths,
          ));

      // deriveXpubsForNostr does not depend on discovery results — run in parallel.
      final xpubsFuture = (searchNostr || searchOnChain)
          ? rust_discovery.deriveXpubsForNostr(
              mnemonic: mnemonic,
              passphrase: passphrase,
              network: _selectedNetwork,
              accountCount: _accountGapLimit,
            )
          : Future.value(<String>[]);

      final (results, deviceHashToWallet, xpubs) = await (
        Future.wait(futures),
        _buildDeviceHashToWallet(),
        xpubsFuture,
      ).wait;
      if (!mounted) return;

      final merged = results.expand((r) => r.accounts).toList();
      final totalScanned =
          results.map((r) => r.scannedCount).fold(0, (a, b) => a + b);

      final (nostrBackups, onChainBackups) = await (
        searchNostr ? _fetchNostrBackups(xpubs) : Future.value(<_NostrFoundBackup>[]),
        searchOnChain ? _fetchOnChainBackups(xpubs, url) : Future.value(<_OnChainFoundBackup>[]),
      ).wait;
      if (!mounted) return;

      if (searchNostr) {
        await _enrichNostrOnlyBackups(nostrBackups, merged, url);
        if (!mounted) return;
      }

      // Enrich on-chain-only backups with descriptor scan data.
      final nostrAddresses = {for (final b in nostrBackups) if (b.firstAddress != null) b.firstAddress!};
      final mergedAddresses = {for (final a in merged) a.firstAddress};
      final nostrOnlyAddresses = nostrAddresses.difference(mergedAddresses);
      if (onChainBackups.isNotEmpty) {
        await _enrichOnChainOnlyBackups(onChainBackups, merged, nostrOnlyAddresses, url);
        if (!mounted) return;
      }

      _applyResults(
          accounts: merged,
          totalScanned: totalScanned,
          nostrBackups: nostrBackups,
          onChainBackups: onChainBackups,
          deviceHashToWallet: deviceHashToWallet);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _errorMessage = e.toString();
        _phase = _ScanPhase.error;
      });
    }
  }

  Future<void> _onXpubScan(
    String xpub,
    RestoreScriptType? scriptFilter,
    bool searchNostr,
    bool searchOnChain,
  ) async {
    _lastActiveTab = 0;
    _lastSeedMnemonic = null;
    _lastSeedPassphrase = null;
    _resetScanState(_ScanPhase.scanning);
    setState(() {
      _searchNostrActive = searchNostr;
      _searchOnChainActive = searchOnChain;
    });

    final url = _electrumUrl;

    try {
      // Build keyspecs for all (or selected) script types using this xpub.
      final types = scriptFilter != null
          ? [scriptFilter]
          : RestoreScriptType.values;
      final keyspecsByType = types
          .map((t) => rust_discovery.APIWalletTypeKeyspecs(
                walletType: _toWalletType(t),
                keyspecs: [xpub],
              ))
          .toList();

      final (discovered, deviceHashToWallet) = await (
        rust_discovery.discoverAccountsFromKeyspecs(
          keyspecsByType: keyspecsByType,
          network: _selectedNetwork,
          electrumUrl: url,
          addressGapLimit: _addressGapLimit,
        ),
        _buildDeviceHashToWallet(),
      ).wait;
      if (!mounted) return;

      final bareXpub = _bareXpub(xpub);

      final (nostrBackups, onChainBackups) = await (
        searchNostr ? _fetchNostrBackups([bareXpub]) : Future.value(<_NostrFoundBackup>[]),
        searchOnChain ? _fetchOnChainBackups([bareXpub], url) : Future.value(<_OnChainFoundBackup>[]),
      ).wait;
      if (!mounted) return;

      if (searchNostr) {
        await _enrichNostrOnlyBackups(nostrBackups, discovered.accounts, url);
        if (!mounted) return;
      }

      final nostrAddresses = {for (final b in nostrBackups) if (b.firstAddress != null) b.firstAddress!};
      final mergedAddresses = {for (final a in discovered.accounts) a.firstAddress};
      final nostrOnlyAddresses = nostrAddresses.difference(mergedAddresses);
      if (onChainBackups.isNotEmpty) {
        await _enrichOnChainOnlyBackups(onChainBackups, discovered.accounts, nostrOnlyAddresses, url);
        if (!mounted) return;
      }

      _applyResults(
          accounts: discovered.accounts,
          totalScanned: discovered.scannedCount,
          nostrBackups: nostrBackups,
          onChainBackups: onChainBackups,
          deviceHashToWallet: deviceHashToWallet);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _errorMessage = e.toString();
        _phase = _ScanPhase.error;
      });
    }
  }

  Future<void> _onHwScan(
      String sessionId, bool searchNostr, bool skipLegacy, bool searchOnChain) async {
    _lastActiveTab = 2;
    _lastSeedMnemonic = null;
    _lastSeedPassphrase = null;
    _resetScanState(_ScanPhase.deriving);
    setState(() {
      _derivedCount = 0;
      _totalToDeriving = 0;
      _searchNostrActive = searchNostr;
      _searchOnChainActive = searchOnChain;
    });

    final url = _electrumUrl;

    try {
      // 1. Get all derivation paths from Rust.
      final pathsByType = await rust_discovery.hwDerivationPathsForDiscovery(
        accountGapLimit: _accountGapLimit,
        network: _selectedNetwork,
        skipLegacy: skipLegacy,
      );
      final total = pathsByType.fold<int>(0, (s, t) => s + t.paths.length);
      if (!mounted) return;
      setState(() => _totalToDeriving = total);

      // 2. Derive xpubs from device.
      final cubit = context.read<HwWalletCubit>();
      final keyspecsByType = <rust_discovery.APIWalletTypeKeyspecs>[];
      for (final typeEntry in pathsByType) {
        final keyspecs = <String>[];
        for (final path in typeEntry.paths) {
          final keyspec = await cubit.callHw(
            rust_hw.hwGetXpub(
              sessionId: sessionId,
              derivationPath: path,
              network: _selectedNetwork,
            ),
          );
          keyspecs.add(keyspec);
          _derivedCount++;
          if (!mounted) return;
          setState(() {});
        }
        keyspecsByType.add(rust_discovery.APIWalletTypeKeyspecs(
          walletType: typeEntry.walletType,
          keyspecs: keyspecs,
        ));
      }

      if (!mounted) return;
      setState(() => _phase = _ScanPhase.scanning);

      // 3. On-chain discovery + device hash → wallet map.
      final (discovered, deviceHashToWallet) = await (
        rust_discovery.discoverAccountsFromKeyspecs(
          keyspecsByType: keyspecsByType,
          network: _selectedNetwork,
          electrumUrl: url,
          addressGapLimit: _addressGapLimit,
        ),
        _buildDeviceHashToWallet(),
      ).wait;
      if (!mounted) return;

      // 4. Nostr and on-chain search for all derived xpubs.
      final allXpubs =
          keyspecsByType.expand((t) => t.keyspecs).map(_bareXpub).toList();

      final (nostrBackups, onChainBackups) = await (
        searchNostr ? _fetchNostrBackups(allXpubs) : Future.value(<_NostrFoundBackup>[]),
        searchOnChain ? _fetchOnChainBackups(allXpubs, url) : Future.value(<_OnChainFoundBackup>[]),
      ).wait;
      if (!mounted) return;

      if (searchNostr) {
        await _enrichNostrOnlyBackups(nostrBackups, discovered.accounts, url);
        if (!mounted) return;
      }

      final nostrAddresses = {for (final b in nostrBackups) if (b.firstAddress != null) b.firstAddress!};
      final mergedAddresses = {for (final a in discovered.accounts) a.firstAddress};
      final nostrOnlyAddresses = nostrAddresses.difference(mergedAddresses);
      if (onChainBackups.isNotEmpty) {
        await _enrichOnChainOnlyBackups(onChainBackups, discovered.accounts, nostrOnlyAddresses, url);
        if (!mounted) return;
      }

      _applyResults(
          accounts: discovered.accounts,
          totalScanned: discovered.scannedCount,
          nostrBackups: nostrBackups,
          onChainBackups: onChainBackups,
          deviceHashToWallet: deviceHashToWallet);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _errorMessage = e.toString();
        _phase = _ScanPhase.error;
      });
    }
  }

  // ── Shared helpers ─────────────────────────────────────────────────────────

  /// After discovery, scan on-chain data for Nostr-only backups that have
  /// a descriptor but no matching on-chain account.
  Future<void> _enrichNostrOnlyBackups(
    List<_NostrFoundBackup> nostrBackups,
    List<APIAccountInfo> accounts,
    String url,
  ) async {
    final mergedAddresses = {for (final a in accounts) a.firstAddress};
    final nostrOnly = nostrBackups
        .where((b) =>
            !mergedAddresses.contains(b.firstAddress) && b.descriptor != null)
        .toList();
    if (nostrOnly.isEmpty) return;
    await Future.wait(nostrOnly.map((b) async {
      try {
        final scan = await rust_discovery.scanDescriptor(
          descriptor: b.descriptor!,
          network: _selectedNetwork,
          electrumUrl: url,
          addressGapLimit: _addressGapLimit,
        );
        b.txCount = scan.txCount.toInt();
        b.balanceSat = scan.balanceSat;
      } catch (e) {
        debugPrint('[restore scan error] $e');
        // Best-effort; leave null on failure.
      }
    }));
  }

  /// After discovery, scan on-chain data for on-chain-only backups that have
  /// a descriptor but no matching on-chain account and no Nostr backup.
  Future<void> _enrichOnChainOnlyBackups(
    List<_OnChainFoundBackup> onChainBackups,
    List<APIAccountInfo> accounts,
    Set<String> nostrOnlyAddresses,
    String url,
  ) async {
    final mergedAddresses = {for (final a in accounts) a.firstAddress};
    final onChainOnly = onChainBackups
        .where((b) =>
            !mergedAddresses.contains(b.firstAddress) &&
            !nostrOnlyAddresses.contains(b.firstAddress) &&
            b.descriptor != null)
        .toList();
    if (onChainOnly.isEmpty) {
      return;
    }
    await Future.wait(onChainOnly.map((b) async {
      try {
        final scan = await rust_discovery.scanDescriptor(
          descriptor: b.descriptor!,
          network: _selectedNetwork,
          electrumUrl: url,
          addressGapLimit: _addressGapLimit,
        );
        b.txCount = scan.txCount.toInt();
        b.balanceSat = scan.balanceSat;
      } catch (e) {
        // Best-effort; leave null on failure.
      }
    }));
  }

  /// Build the unified wallet list and apply results to state.
  void _applyResults({
    required List<APIAccountInfo> accounts,
    required int totalScanned,
    required List<_NostrFoundBackup> nostrBackups,
    required List<_OnChainFoundBackup> onChainBackups,
    required Map<String, APIWalletInfo> deviceHashToWallet,
  }) {
    final nostrAddresses = {for (final b in nostrBackups) b.firstAddress};
    final onChainAddresses = {for (final b in onChainBackups) b.firstAddress};
    final mergedAddresses = {for (final a in accounts) a.firstAddress};

    // Addresses already covered by on-chain (to avoid double-listing with Nostr).
    final nostrOnlyAddresses = nostrAddresses.difference(mergedAddresses);

    final unified = <_UnifiedWallet>[
      ...accounts.map((a) {
        final hash = rust_discovery.sha256Hex(input: a.firstAddress);
        final existing = deviceHashToWallet[hash];
        return (
          firstAddress: a.firstAddress,
          firstAddressHash: hash,
          walletName: null,
          derivationPath: a.derivationPath,
          walletType: a.walletType,
          txCount: a.txCount,
          balanceSat: a.balanceSat,
          hasNostrBackup: nostrAddresses.contains(a.firstAddress),
          hasOnChainBackup: onChainAddresses.contains(a.firstAddress),
          commitTxid: null,
          isExisting: existing != null,
          existingWalletName: existing?.name,
        );
      }),
      ...nostrBackups
          .where((b) => nostrOnlyAddresses.contains(b.firstAddress))
          .map((b) {
            final hash = b.firstAddress != null
                ? rust_discovery.sha256Hex(input: b.firstAddress!)
                : null;
            final existing = hash != null ? deviceHashToWallet[hash] : null;
            return (
              firstAddress: b.firstAddress,
              firstAddressHash: hash,
              walletName: b.walletName,
              derivationPath: '',
              walletType: b.walletType,
              txCount: b.txCount,
              balanceSat: b.balanceSat,
              hasNostrBackup: true,
              hasOnChainBackup: onChainAddresses.contains(b.firstAddress),
              commitTxid: null,
              isExisting: existing != null,
              existingWalletName: existing?.name,
            );
          }),
      ...onChainBackups
          .where((b) =>
              !mergedAddresses.contains(b.firstAddress) &&
              !nostrOnlyAddresses.contains(b.firstAddress))
          .map((b) {
            final hash = b.firstAddress != null
                ? rust_discovery.sha256Hex(input: b.firstAddress!)
                : null;
            final existing = hash != null ? deviceHashToWallet[hash] : null;
            return (
              firstAddress: b.firstAddress,
              firstAddressHash: hash,
              walletName: b.walletName,
              derivationPath: '',
              walletType: b.walletType,
              txCount: b.txCount,
              balanceSat: b.balanceSat,
              hasNostrBackup: false,
              hasOnChainBackup: true,
              commitTxid: b.commitTxid,
              isExisting: existing != null,
              existingWalletName: existing?.name,
            );
          }),
    ];
    setState(() {
      _accounts = accounts;
      _totalScanned = totalScanned;
      _walletByFirstAddressHash = deviceHashToWallet;
      _unifiedWallets = unified;
      _nostrByAddress = {
        for (final b in nostrBackups)
          if (b.firstAddress != null) b.firstAddress!: b
      };
      _onChainByAddress = {
        for (final b in onChainBackups)
          if (b.firstAddress != null) b.firstAddress!: b
      };
      _accountByAddress = {for (final a in accounts) a.firstAddress: a};
      _phase = _ScanPhase.done;
    });
  }

  Future<Map<String, APIWalletInfo>> _buildDeviceHashToWallet() async {
    final wallets = switch (context.read<WalletListCubit>().state) {
      WalletListLoaded(:final wallets) =>
        wallets.where((w) => w.network == _selectedNetwork).toList(),
      _ => <APIWalletInfo>[],
    };
    final entries = await Future.wait(wallets.map((w) async {
      try {
        final addr = await rust_discovery.firstAddressFromDescriptor(
            descriptor: w.descriptor, network: _selectedNetwork);
        final hash = rust_discovery.sha256Hex(input: addr);
        return MapEntry(hash, w);
      } catch (e) {
        debugPrint('[restore discovery error] $e');
        return null;
      }
    }));
    return Map.fromEntries(
        entries.whereType<MapEntry<String, APIWalletInfo>>());
  }

  Future<void> _refreshWalletMap() async {
    final map = await _buildDeviceHashToWallet();
    if (!mounted) return;
    setState(() => _walletByFirstAddressHash = map);
  }

  Future<List<_NostrFoundBackup>> _fetchNostrBackups(List<String> xpubs) async {
    final settings = NostrRelaySettings();
    final relays = await settings.loadRelays();
    if (relays.isEmpty) return [];

    // Push latest timeout/attempts settings to Rust before querying.
    await settings.applyToRust();

    final results = <_NostrFoundBackup>[];
    final seenNames = <String>{};
    bool networkErrorOccurred = false;

    await Future.wait(xpubs.map((xpub) async {
      try {
        final responses = await rust_nostr.fetchNostrBackup(
          xpub: xpub,
          relayUrls: relays,
        );
        for (final resp in responses) {
          final byteList = resp.bytes.toList();
          final name = resp.walletName;
          if (name != null) {
            if (seenNames.contains(name)) continue;
            seenNames.add(name);
          }
          results.add(_NostrFoundBackup(
            xpub: xpub,
            bytes: byteList,
            walletName: name,
            network: resp.network,
            createdAt: resp.createdAt?.toInt(),
            firstAddress: resp.firstAddress,
            walletType: resp.walletType,
            descriptor: resp.descriptor,
            descriptorSigVerification: resp.descriptorSigVerification,
          ));
        }
      } catch (e) {
        // Rust throws "No relay could be reached" when every relay failed
        // due to a network error (timeout, connection refused, etc.).
        // "No backup found..." means relays responded but had no backup — not a network issue.
        if (e.toString().contains('No relay could be reached')) {
          networkErrorOccurred = true;
        }
      }
    }));

    // Flag is set if any single xpub had all its relays unreachable,
    // regardless of whether other xpubs succeeded.
    _nostrAllRelaysFailed = networkErrorOccurred;

    results.sort((a, b) => (b.createdAt ?? 0).compareTo(a.createdAt ?? 0));
    return results;
  }

  Future<List<_OnChainFoundBackup>> _fetchOnChainBackups(
      List<String> xpubs, String electrumUrl) async {
    final networkHint = _selectedNetwork.name;
    final results = <_OnChainFoundBackup>[];
    await Future.wait(xpubs.map((xpub) async {
      try {
        final responses = await rust_onchain.fetchOnchainBackup(
          xpubCredential: xpub,
          electrumUrl: electrumUrl,
          networkHint: networkHint,
        );
        for (int i = 0; i < responses.length; i++) {
          final resp = responses[i];
          results.add(_OnChainFoundBackup(
            xpub: xpub,
            bytes: resp.bytes.toList(),
            commitTxid: resp.commitTxid,
            revealTxid: resp.revealTxid,
            walletName: resp.walletName,
            network: resp.network,
            createdAt: resp.createdAt?.toInt(),
            firstAddress: resp.firstAddress,
            walletType: resp.walletType,
            descriptor: resp.descriptor,
            anchorsReachable: resp.anchorsReachable,
            anchorsTotal: resp.anchorsTotal,
          ));
        }
      } catch (e) {
        debugPrint('[restore onchain error] $e');
      }
    }));
    results.sort((a, b) => (b.createdAt ?? 0).compareTo(a.createdAt ?? 0));
    return results;
  }

  Future<void> _importFromOnChain(_OnChainFoundBackup backup) =>
      _importBackup(
        bytes: backup.bytes,
        xpub: backup.xpub,
        // The backup was discovered via the active network's Electrum
        // endpoint, so the active network is the correct hint. The blob's
        // own network field is unreliable (Signet backups can carry
        // "testnet" because Signet shares Bitcoin's testnet magic in some
        // legacy paths).
        networkHint: _selectedNetwork.name,
        rustImport: rust_onchain.importOnchainBackup,
      );

  Future<void> _importFromNostr(List<int> bytes, String xpub) => _importBackup(
        bytes: bytes,
        xpub: xpub,
        networkHint: _selectedNetwork.name,
        rustImport: rust_nostr.importNostrBackup,
      );

  Future<void> _importBackup({
    required List<int> bytes,
    required String xpub,
    required String networkHint,
    required Future<dynamic> Function({
      required List<int> backupBytes,
      required String xpubCredential,
      required String deviceKeyHex,
      required String walletsDir,
      required String networkHint,
    }) rustImport,
  }) async {
    // When the user reached the import button via the Seed tab, we still
    // hold the mnemonic that derived the matching xpub. Carrying it through
    // lets us auto-attach a hot key after import so the user does not have
    // to re-enter the same words on the Descriptor → Keys tab.
    final mnemonic = _lastSeedMnemonic;
    final passphrase = _lastSeedPassphrase;
    final l10n = context.l10n;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Row(
          children: [
            Icon(Icons.warning_amber_outlined,
                color: Theme.of(ctx).colorScheme.tertiary),
            const SizedBox(width: 8),
            Expanded(child: Text(l10n.nostrImportTamperTitle)),
          ],
        ),
        content: Text(l10n.nostrImportTamperBody),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(l10n.cancel),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(l10n.nostrRestoreImport),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    final service = context.read<WalletService>();
    final deviceKey = await service.getOrCreateEncryptionKey();
    final walletsDir = await service.getWalletsDir();
    try {
      final result = await rustImport(
        backupBytes: bytes,
        xpubCredential: xpub,
        deviceKeyHex: deviceKey,
        walletsDir: walletsDir,
        networkHint: networkHint,
      );
      if (!mounted) return;
      // Auto-attach the seed as a hot key when we have it. The recovery
      // scanner only surfaced this backup because at least one descriptor
      // key matched the xpub derived from `mnemonic`, so addMnemonicKey
      // will find a matching MFP. Errors here are non-fatal — the wallet
      // is already imported watch-only and the user can retry manually.
      if (mnemonic != null) {
        try {
          final handle = await service.openWallet(result.wallet.walletPath);
          handle.addMnemonicKey(mnemonic: mnemonic, passphrase: passphrase);
        } catch (e) {
          debugPrint('[restore auto-attach mnemonic] $e');
        }
      }
      if (!mounted) return;
      context.read<WalletListCubit>().refresh();
      if (mounted) {
        await Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) =>
                WalletDetailScreen(walletPath: result.wallet.walletPath),
          ),
        );
        if (mounted) await _refreshWalletMap();
      }
    } catch (e) {
      if (mounted) showErrorToastException(e);
    }
  }

  Future<void> _openWizard(
    APIAccountInfo account, {
    String? mnemonic,
    String? passphrase,
  }) async {
    final cubit = context.read<WalletListCubit>();
    final keyspec = (
      keyspec: account.keyspec,
      mnemonic: mnemonic,
      passphrase: passphrase,
      xprv: null,
    ) as KeyspecResult;

    final walletPath = await Navigator.push<String>(
      context,
      MaterialPageRoute(
        fullscreenDialog: true,
        builder: (_) => SimpleWalletDialog(
          cubit: cubit,
          initialKeyspecs: [keyspec],
          initialNetwork: _selectedNetwork,
        ),
      ),
    );

    if (walletPath != null && mounted) await _refreshWalletMap();
  }

  void _openWallet(APIWalletInfo wallet) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => WalletDetailScreen(walletPath: wallet.walletPath),
      ),
    );
  }

  // ── Static helpers ─────────────────────────────────────────────────────────

  static String _bareXpub(String keyspec) {
    final i = keyspec.indexOf(']');
    return i >= 0 ? keyspec.substring(i + 1) : keyspec;
  }

  static APIWalletType _toWalletType(RestoreScriptType t) => switch (t) {
        RestoreScriptType.legacy => APIWalletType.p2Pkh,
        RestoreScriptType.nestedSegwit => APIWalletType.p2ShWpkh,
        RestoreScriptType.nativeSegwit => APIWalletType.p2Wpkh,
        RestoreScriptType.taproot => APIWalletType.p2Tr,
      };

  static String _scriptTypeLabel(AppLocalizations l10n, APIWalletType t) =>
      switch (t) {
        APIWalletType.p2Pkh => l10n.scriptTypeLegacy,
        APIWalletType.p2ShWpkh => l10n.scriptTypeNested,
        APIWalletType.p2Wpkh => l10n.scriptTypeSegwit,
        APIWalletType.p2Tr => l10n.scriptTypeTaproot,
        _ => t.name,
      };

  static String _extractMfp(String keyspec) =>
      kKeyspecPattern.firstMatch(keyspec)?.group(1) ?? '';

  // ── Build ──────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final showTabs = _phase == _ScanPhase.idle;

    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.recoverWalletTitle),
        bottom: showTabs
            ? TabBar(
                controller: _tabController,
                tabs: [
                  Tab(text: l10n.restoreTabXpub),
                  Tab(text: l10n.restoreTabSeed),
                  Tab(text: l10n.restoreTabHardware),
                ],
              )
            : null,
      ),
      body: SafeArea(
        child: switch (_phase) {
          _ScanPhase.idle => _buildIdleBody(l10n),
          _ScanPhase.deriving => _buildDerivingBody(l10n),
          _ScanPhase.scanning => _buildScanningBody(l10n),
          _ScanPhase.done => _buildDoneBody(l10n),
          _ScanPhase.error => _buildErrorBody(l10n),
        },
      ),
    );
  }

  Widget _buildIdleBody(AppLocalizations l10n) {
    return TabBarView(
      controller: _tabController,
      children: [
        XpubTab(
          network: _selectedNetwork,
          accountGapLimit: _accountGapLimit,
          addressGapLimit: _addressGapLimit,
          onAccountGapChanged: (v) => setState(() => _accountGapLimit = v),
          onAddressGapChanged: (v) => setState(() => _addressGapLimit = v),
          onScan: _onXpubScan,
        ),
        SeedTab(
          network: _selectedNetwork,
          accountGapLimit: _accountGapLimit,
          addressGapLimit: _addressGapLimit,
          onAccountGapChanged: (v) => setState(() => _accountGapLimit = v),
          onAddressGapChanged: (v) => setState(() => _addressGapLimit = v),
          onScan: _onSeedScan,
        ),
        HardwareTab(
          network: _selectedNetwork,
          accountGapLimit: _accountGapLimit,
          addressGapLimit: _addressGapLimit,
          onAccountGapChanged: (v) => setState(() => _accountGapLimit = v),
          onAddressGapChanged: (v) => setState(() => _addressGapLimit = v),
          onScan: _onHwScan,
        ),
      ],
    );
  }

  // ── Progress bodies ────────────────────────────────────────────────────────

  Widget _buildDerivingBody(AppLocalizations l10n) {
    final textTheme = Theme.of(context).textTheme;
    final progress =
        _totalToDeriving > 0 ? _derivedCount / _totalToDeriving : null;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            LinearProgressIndicator(value: progress),
            const SizedBox(height: 24),
            Text(
              _totalToDeriving > 0
                  ? l10n.hwDiscoveryDeriving(_derivedCount, _totalToDeriving)
                  : '…',
              style: textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            Text(
              l10n.hwWalletNoConfirmNeeded,
              style: textTheme.bodySmall,
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildScanningBody(AppLocalizations l10n) {
    final textTheme = Theme.of(context).textTheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const LinearProgressIndicator(),
            const SizedBox(height: 24),
            Text(l10n.scanAccountsScanning, style: textTheme.titleMedium),
            const SizedBox(height: 8),
            Text(
              l10n.scanAccountsScanningHint(
                  _accountGapLimit, _addressGapLimit),
              style: textTheme.bodySmall,
              textAlign: TextAlign.center,
            ),
            if (_searchNostrActive) ...[
              const SizedBox(height: 4),
              Text(
                l10n.searchNostrScanningHint,
                style: textTheme.bodySmall,
                textAlign: TextAlign.center,
              ),
            ],
            if (_searchOnChainActive) ...[
              const SizedBox(height: 4),
              Text(
                l10n.onChainScanningHint,
                style: textTheme.bodySmall,
                textAlign: TextAlign.center,
              ),
            ],
          ],
        ),
      ),
    );
  }

  // ── Error body ─────────────────────────────────────────────────────────────

  Widget _buildErrorBody(AppLocalizations l10n) {
    final errorColor = Theme.of(context).colorScheme.error;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.error_outline, size: 48, color: errorColor),
            const SizedBox(height: 16),
            Text(_errorMessage ?? '',
                style: TextStyle(color: errorColor),
                textAlign: TextAlign.center),
            const SizedBox(height: 24),
            FilledButton(
              onPressed: () {
                setState(() {
                  _phase = _ScanPhase.idle;
                  _tabController.animateTo(_lastActiveTab);
                });
              },
              child: Text(l10n.scanAccountsRetry),
            ),
          ],
        ),
      ),
    );
  }

  // ── Done body (shared results) ─────────────────────────────────────────────

  Widget _buildDoneBody(AppLocalizations l10n) {
    final hasActivity = _accounts.isNotEmpty;
    final mfp = hasActivity ? _extractMfp(_accounts.first.keyspec) : null;
    final hasAnyResults = hasActivity || _unifiedWallets.isNotEmpty;
    final theme = Theme.of(context);

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        if (!hasAnyResults) ...[
          const SizedBox(height: 32),
          const Center(child: Icon(Icons.search_off, size: 64)),
          const SizedBox(height: 16),
          Center(
            child: Text(l10n.scanAccountsNoActivity,
                textAlign: TextAlign.center),
          ),
          const SizedBox(height: 8),
          Center(
            child: Text(
              l10n.scanAccountsScannedCount(_totalScanned),
              style: theme.textTheme.bodySmall,
            ),
          ),
          if (_nostrAllRelaysFailed) ...[
            const SizedBox(height: 16),
            _buildNostrWarningBanner(l10n),
          ],
          const SizedBox(height: 32),
          FilledButton(
            onPressed: () => setState(() {
              _phase = _ScanPhase.idle;
              _tabController.animateTo(_lastActiveTab);
            }),
            child: Text(l10n.scanAccountsRetry),
          ),
        ] else ...[
          if (hasActivity) ...[
            Row(
              children: [
                Text(l10n.keyFingerprintLabel,
                    style: theme.textTheme.labelMedium),
                const SizedBox(width: 8),
                MfpBadge(label: mfp!, color: AppAccent.color),
              ],
            ),
            const SizedBox(height: 8),
          ],
          Text(
            l10n.scanAccountsFoundBackups(_unifiedWallets.length),
            style: theme.textTheme.titleMedium,
          ),
          Text(
            l10n.scanAccountsScannedCount(_totalScanned),
            style: theme.textTheme.bodySmall,
          ),
          if (_nostrAllRelaysFailed) ...[
            const SizedBox(height: 12),
            _buildNostrWarningBanner(l10n),
          ],
          const SizedBox(height: 12),
          for (final w in _unifiedWallets) ...[
            _buildUnifiedWalletCard(l10n, w),
            const SizedBox(height: 8),
          ],
        ],
      ],
    );
  }

  Widget _buildNostrWarningBanner(AppLocalizations l10n) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: theme.colorScheme.errorContainer,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.wifi_off,
              size: 18, color: theme.colorScheme.onErrorContainer),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              l10n.nostrSearchNetworkWarning,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onErrorContainer,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildUnifiedWalletCard(AppLocalizations l10n, _UnifiedWallet w) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final foundOnChain = w.derivationPath?.isNotEmpty == true;
    final hasChainData = w.txCount != null || w.balanceSat != null;

    final satsText = w.balanceSat != null && w.balanceSat != BigInt.zero
        ? '${BitcoinFormatter.formatNum(w.balanceSat!.toInt())} sats'
        : hasChainData
            ? '0 sats'
            : null;

    final scriptLabel =
        w.walletType != null ? _scriptTypeLabel(l10n, w.walletType!) : null;
    final isExisting = w.isExisting;
    final existingWalletName = w.existingWalletName;

    final nostrBackup = w.hasNostrBackup && w.firstAddress != null
        ? _nostrByAddress[w.firstAddress!]
        : null;
    final onChainBackup = w.hasOnChainBackup && w.firstAddress != null
        ? _onChainByAddress[w.firstAddress!]
        : null;

    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 10, 4, 10),
        child: Row(
          children: [
            if (scriptLabel != null) ...[
              _ScriptBadge(label: scriptLabel),
              const SizedBox(width: 6),
            ],
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    w.walletName ??
                        (w.derivationPath?.isNotEmpty == true
                            ? w.derivationPath
                            : null) ??
                        l10n.nostrRestoreFound,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      fontFamily:
                          w.derivationPath?.isNotEmpty == true &&
                                  w.walletName == null
                              ? 'monospace'
                              : null,
                      fontWeight: FontWeight.w600,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                  if (satsText != null || (w.txCount != null && w.txCount! > 0))
                    Text(
                      [
                        ?satsText,
                        if (w.txCount != null) '${w.txCount} txs',
                      ].join(' · '),
                      style: theme.textTheme.bodySmall
                          ?.copyWith(color: cs.onSurfaceVariant),
                    ),
                  if (nostrBackup != null) ...[
                    const SizedBox(height: 2),
                    _NostrBackupMeta(
                      backup: nostrBackup,
                      walletName:
                          w.walletName == null ? nostrBackup.walletName : null,
                      l10n: l10n,
                    ),
                    if (nostrBackup.descriptorSigVerification != null)
                      _DescriptorSigBadge(
                        verification: nostrBackup.descriptorSigVerification!,
                        l10n: l10n,
                      ),
                  ],
                  if (onChainBackup != null) ...[
                    const SizedBox(height: 2),
                    _OnChainBackupMeta(
                      backup: onChainBackup,
                      commitTxid: w.commitTxid,
                      l10n: l10n,
                    ),
                  ],
                ],
              ),
            ),
            if (isExisting) ...[
              _ScriptBadge(
                label: existingWalletName!,
                background: cs.primaryContainer,
                foreground: cs.onPrimaryContainer,
              ),
              const SizedBox(width: 4),
              IconButton(
                icon: const Icon(Icons.chevron_right),
                onPressed: () {
                  final wallet = _walletByFirstAddressHash[w.firstAddressHash];
                  if (wallet == null) {
                    showErrorToast(l10n.walletNotFound);
                    return;
                  }
                  _openWallet(wallet);
                },
              ),
            ] else ...[
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (foundOnChain)
                    IconButton(
                      icon: const Icon(Icons.account_balance_wallet_outlined),
                      tooltip: l10n.scanAccountsCreateWallet,
                      visualDensity: VisualDensity.compact,
                      onPressed: () => _openWizard(
                        _accountByAddress[w.firstAddress!]!,
                        mnemonic: _lastSeedMnemonic,
                        passphrase: _lastSeedPassphrase,
                      ),
                    ),
                  if (w.hasNostrBackup)
                    IconButton(
                      icon: const Icon(Icons.cloud_download_outlined),
                      tooltip: l10n.importFromNostrBackup,
                      visualDensity: VisualDensity.compact,
                      onPressed: () {
                        final b = _nostrByAddress[w.firstAddress!]!;
                        _importFromNostr(b.bytes, b.xpub);
                      },
                    ),
                  if (w.hasOnChainBackup)
                    IconButton(
                      icon: const Icon(Icons.link),
                      tooltip: l10n.onChainBadge,
                      visualDensity: VisualDensity.compact,
                      onPressed: () => _importFromOnChain(
                          _onChainByAddress[w.firstAddress!]!),
                    ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Nostr backup metadata row
// ---------------------------------------------------------------------------

class _NostrBackupMeta extends StatelessWidget {
  final _NostrFoundBackup backup;
  final String? walletName;
  final AppLocalizations l10n;

  const _NostrBackupMeta(
      {required this.backup, this.walletName, required this.l10n});

  @override
  Widget build(BuildContext context) {
    final ts = Theme.of(context).textTheme;
    final cs = Theme.of(context).colorScheme;

    final dateStr = backup.createdAt != null
        ? formatDateTimeFromUnix(backup.createdAt!)
        : null;
    final headerParts = [?walletName, ?dateStr];
    final headerText = headerParts.join(' → ');

    return Row(children: [
      Icon(Icons.cloud_done_outlined, size: 12, color: cs.onSurfaceVariant),
      const SizedBox(width: 3),
      Flexible(
        child: Text(
          headerText,
          style: ts.bodySmall
              ?.copyWith(color: cs.onSurfaceVariant, fontSize: 10),
          overflow: TextOverflow.ellipsis,
        ),
      ),
    ]);
  }
}

class _OnChainBackupMeta extends StatelessWidget {
  final _OnChainFoundBackup backup;
  final String? commitTxid;
  final AppLocalizations l10n;

  const _OnChainBackupMeta({
    required this.backup,
    this.commitTxid,
    required this.l10n,
  });

  @override
  Widget build(BuildContext context) {
    final ts = Theme.of(context).textTheme;
    final cs = Theme.of(context).colorScheme;
    final dateStr = backup.createdAt != null
        ? formatDateTimeFromUnix(backup.createdAt!)
        : null;
    final hasAnchors = backup.anchorsTotal > 0;
    final anchorsHealthy = hasAnchors && backup.anchorsReachable == backup.anchorsTotal;
    final anchorsPartial = hasAnchors && backup.anchorsReachable > 0 && backup.anchorsReachable < backup.anchorsTotal;

    IconData? anchorIcon;
    Color? anchorColor;
    String? anchorLabel;

    if (hasAnchors) {
      if (anchorsHealthy) {
        anchorIcon = Icons.verified;
        anchorColor = Colors.green;
      } else if (anchorsPartial) {
        anchorIcon = Icons.warning_amber;
        anchorColor = Colors.orange;
      } else {
        anchorIcon = Icons.dangerous;
        anchorColor = Colors.red;
      }
      anchorLabel = l10n.onChainBackupAnchorsHealth(
        anchorsHealthy || anchorsPartial ? backup.anchorsReachable : 0,
        backup.anchorsTotal,
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (dateStr != null) ...[
          Row(children: [
            Icon(Icons.cloud_done_outlined, size: 12, color: cs.onSurfaceVariant),
            const SizedBox(width: 3),
            Flexible(
              child: Text(
                dateStr,
                style: ts.bodySmall
                    ?.copyWith(color: cs.onSurfaceVariant, fontSize: 10),
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ]),
          const SizedBox(height: 1),
        ],
        if (anchorIcon != null) ...[
          Row(children: [
            Icon(anchorIcon, size: 11, color: anchorColor),
            const SizedBox(width: 3),
            Flexible(
              child: Text(
                anchorLabel!,
                style: ts.bodySmall?.copyWith(
                  color: anchorColor,
                  fontSize: 10,
                  fontWeight: FontWeight.w600,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ]),
        ],
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Script type badge
// ---------------------------------------------------------------------------

class _ScriptBadge extends StatelessWidget {
  final String label;
  final Color? background;
  final Color? foreground;

  const _ScriptBadge({required this.label, this.background, this.foreground});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
      decoration: BoxDecoration(
        color: background ?? cs.secondaryContainer,
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.w600,
          color: foreground ?? cs.onSecondaryContainer,
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Descriptor signature status badge (restore screen)
// ---------------------------------------------------------------------------

class _DescriptorSigBadge extends StatelessWidget {
  final rust_nostr.APIDescriptorSigVerification verification;
  final AppLocalizations l10n;

  const _DescriptorSigBadge({required this.verification, required this.l10n});

  @override
  Widget build(BuildContext context) {
    final hasInvalid = verification.hasInvalid;
    final ownerSigned = verification.ownerXpubSigned;
    final validCount = verification.validCount;
    final totalXpubs = verification.totalXpubs;
    final isMultisig = totalXpubs > 1;

    final IconData icon;
    final Color color;
    final String label;

    if (totalXpubs == 0) {
      // Descriptor parsing failed — signature status cannot be evaluated.
      icon = Icons.help_outline;
      color = Colors.grey;
      label = l10n.descriptorSigUnknown;
    } else if (hasInvalid) {
      icon = Icons.dangerous;
      color = Colors.red;
      label = l10n.descriptorSigInvalid;
    } else if (validCount == 0) {
      icon = Icons.warning_amber;
      color = Colors.orange;
      label = l10n.descriptorSigAbsent;
    } else if (!ownerSigned) {
      icon = Icons.warning_amber;
      color = Colors.orange;
      label = isMultisig
          ? '$validCount/$totalXpubs · ${l10n.descriptorSigOwnerUnsigned}'
          : l10n.descriptorSigOwnerUnsigned;
    } else if (totalXpubs > 0 && validCount < totalXpubs) {
      icon = Icons.warning_amber;
      color = Colors.orange;
      label = '$validCount/$totalXpubs ${l10n.descriptorSigVerified}';
    } else {
      icon = Icons.verified;
      color = Colors.green;
      label = isMultisig
          ? '$validCount/$totalXpubs ${l10n.descriptorSigVerified}'
          : l10n.descriptorSigVerified;
    }

    return Padding(
      padding: const EdgeInsets.only(top: 2),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 11, color: color),
          const SizedBox(width: 3),
          Flexible(
            child: Text(
              label,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: color,
                    fontSize: 10,
                    fontWeight: FontWeight.w600,
                  ),
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }
}
