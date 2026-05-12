# Development Guide

## Project Structure

```
deadbolt/
├── lib/                          # Dart/Flutter code
│   ├── main.dart                 # App entry point
│   ├── screens/                  # UI screens
│   │   └── wallet_detail/        # Wallet detail sub-screens (tabs, dialogs)
│   ├── cubit/                    # BLoC state management (per-feature cubits)
│   ├── services/                 # WalletService, WalletSyncService,
│   │                             #   ProjectDescriptorService, PriceService,
│   │                             #   FeeEstimationService, MempoolBlocksService,
│   │                             #   NostrRelaySettings, AndroidHwChannel
│   ├── data/                     # Drift SQLite database (projects)
│   ├── models/                   # Shared data models
│   ├── widgets/                  # Reusable widgets
│   ├── utils/                    # Formatters, helpers, toast, export sheet
│   ├── theme/                    # Material 3 theme
│   └── src/rust/                 # Auto-generated FFI bindings (DO NOT EDIT)
├── rust/                         # Rust core logic
│   └── src/
│       ├── api/                  # FFI boundary (exposed to Dart)
│       │   └── wallet/           # Wallet API (ops, queries, psbt, labels)
│       └── core/                 # Internal logic (BDK, descriptors, Tor, HW, etc.)
├── docs/                         # Documentation
├── .github/workflows/            # CI/CD pipelines
└── flutter_rust_bridge.yaml      # FFI code-gen configuration
```

## Architecture

**UI Layer** (Dart/Flutter)
- Material 3 UI with BLoC state management
- Core cubits: `WalletListCubit`, `WalletDetailCubit`, `ProjectListCubit`,
  `ProjectDetailCubit`, `SettingsCubit`, `HwWalletCubit`, `BiometricLockCubit`;
  screen-scoped: `DescriptorSigsCubit`. `WalletDetailCubit` is composed from
  per-domain mixins under `lib/cubit/wallet_detail/`.

**FFI Bridge** (flutter_rust_bridge 2.12.0)
- Type-safe Dart ↔ Rust communication
- Bindings auto-generated from `rust/src/api/`; never edit `lib/src/rust/` by hand

**Core Layer** (Rust)
- Bitcoin descriptor parsing and wallet management via BDK
- Hardware wallet signing via bitbox-api + async-hwi trait
- Embedded Tor via arti-client
- Wallet persistence in SQLCipher-encrypted SQLite (`rusqlite` + `bundled-sqlcipher`)

## Key Rust Modules

| Module | Purpose |
|--------|---------|
| `api/analyzer.rs` | Descriptor parsing, spend path analysis, fee weight, Liana export |
| `api/wallet/ops.rs` | Wallet CRUD, sync, protection types |
| `api/wallet/queries.rs` | Wallet read-side queries (balances, UTXOs, transactions) |
| `api/wallet/psbt.rs` | PSBT build, sign, merge, broadcast |
| `api/wallet/labels.rs` | BIP-329 label import/export |
| `api/wallet/backup.rs` | `.deadbolt` encrypted backup export/import |
| `api/wallet/nostr_backup.rs` | Nostr backup publish, fetch, delete |
| `api/wallet/descriptor_backup.rs` / `descriptor_recovery.rs` | On-chain commit/reveal descriptor backup + recovery |
| `api/wallet/descriptor_sig.rs` | Descriptor ownership proofs (BB02-BIP322, hot key, QR) |
| `api/wallet/detail_tx.rs` / `detail_address.rs` / `detail_rbf.rs` / `detail_cpfp.rs` | Wallet detail tab queries and RBF/CPFP construction |
| `api/wallet/discovery.rs` | BIP-44 gap-limit account discovery across script types |
| `api/hw_wallet.rs` | Hardware wallet FFI (xpub export, PSBT sign, message sign) |
| `api/wif_sweep.rs` | WIF sweep: resolve addresses, fetch UTXOs, build/sign/broadcast |
| `core/hw/mod.rs` | BitBox02 transport + async-hwi wrapper |
| `core/tor_manager.rs` | Embedded arti Tor client lifecycle |
| `core/key_protection.rs` | DeviceKey / Password / XPub protection schemes |
| `core/project_seeds.rs` | Hot key store (`project_seeds.db`) |

## Contributing

1. Fork the repository
2. Create a feature branch (`git checkout -b feature/amazing-feature`)
3. Commit with **signed commits** (`git commit -S -m "feat: add amazing feature"`)
4. Push to your fork and open a Pull Request

**All commits must be GPG-signed.** See [docs/GPG_SETUP.md](GPG_SETUP.md) for setup instructions.

## Code Style

- **Dart**: Follow [Effective Dart](https://dart.dev/guides/language/effective-dart) guidelines; run `flutter analyze`
- **Rust**: `cargo fmt` + `cargo clippy` before committing
- **Commits**: [Conventional Commits](https://www.conventionalcommits.org/) format
- **Comments**: English only
- **Error handling**: Surface errors as toasts (`ToastHelper`), never as full-screen error states
