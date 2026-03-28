# Deadbolt

**A Bitcoin descriptor analyzer and wallet manager**

Deadbolt is a cross-platform tool that parses and analyzes Bitcoin wallet descriptors to extract network information, public keys, and spend paths with fee weight estimates. It also creates on-device Bitcoin wallets, syncs balances via Electrum, and builds PSBTs (unsigned transactions) with optional coin control. Built with Flutter (UI) and Rust (core logic), it provides a secure, privacy-preserving way to understand and manage Bitcoin wallet setups.

[![CI](https://github.com/frijolo/deadbolt/actions/workflows/ci.yml/badge.svg)](https://github.com/frijolo/deadbolt/actions/workflows/ci.yml)
[![Release](https://github.com/frijolo/deadbolt/actions/workflows/release.yml/badge.svg)](https://github.com/frijolo/deadbolt/releases)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE)

## Features

- **Descriptor Parsing**: Supports all Bitcoin descriptor types (P2PKH, P2WPKH, P2WSH, multisig, Taproot, miniscript, etc.)
- **Network Detection**: Automatically identifies mainnet, testnet, signet, or regtest
- **Public Key Extraction**: Parses extended public keys (xpub, ypub, zpub, tpub, etc.)
- **Spend Path Analysis**: Identifies all possible spending conditions in complex descriptors
- **Fee Estimation**: Calculates transaction weight for each spend path
- **Wallet Management**: Create on-device wallets, sync balances via Electrum, view UTXOs and transactions
- **PSBT Workflow**: Build PSBTs with coin control and RBF support; import and merge partial signatures; broadcast finalized transactions
- **Multi-Recipient Transactions**: Send to multiple addresses in a single transaction with per-output amounts; one output can be set to "MAX" to receive the wallet remainder
- **Direct Send**: Single-sig wallets with a local hot key can sign and broadcast in one step — no PSBT round-trip required
- **Local Signing**: Store encrypted private keys on-device (hot signing keys) and sign PSBTs without any external device
- **Hardware Wallet Signing**: Sign PSBTs and export xpubs directly from a BitBox02 (Android, Linux, Windows). See [docs/HARDWARE_WALLETS.md](docs/HARDWARE_WALLETS.md)
- **Password-Protected Wallets**: Lock individual wallets with a password; the key never leaves the device unencrypted
- **XPub Key Protection**: Protect wallets with any xpub from the descriptor — any registered key can unlock, including via hardware wallet (no password to remember or lose)
- **Change Protection In-Place**: Switch between DeviceKey, Password, and XPub protection at any time from the wallet overview, without export or import
- **Encrypted Backup & Restore**: Export a wallet as an encrypted `.deadbolt` backup file and restore it on any device
- **BIP-329 Labels**: Import and export wallet labels in the standard BIP-329 format
- **Liana Format Export**: Export any descriptor in the format expected by the Liana wallet
- **QR Support**: Import/export descriptors and PSBTs via QR codes (including animated BC-UR)
- **Project Import/Export**: Save and load descriptor projects as JSON files
- **Theme Support**: Light, Dark, and System default themes
- **Internationalization**: UI available in English and Spanish
- **Tor Routing**: Optional embedded Tor client (arti) routes all Electrum connections through the Tor network — no system Tor daemon required, persists across restarts
- **Fiat Price Display**: Optional BTC price overlay (CoinGecko or mempool.space) shows balance and transaction amounts in fiat alongside sats/BTC
- **Configurable Connectivity**: Set custom Electrum and block explorer URLs per network (mainnet, testnet, testnet4, signet, regtest), adjustable minimum fee rate
- **Guided Wallet Wizard**: Step-by-step wizard for creating single-sig and multisig wallets without manually crafting a descriptor
- **Privacy-First**: No telemetry, no analytics, no data collection — wallet sync uses your own Electrum server; optionally route through Tor for enhanced network privacy
- **Cross-Platform**: Available for Android, Linux, and Windows
- **Signed Releases**: SHA256 checksums are GPG-signed for release verification

## Installation

### Android

Download the latest APK from [Releases](https://github.com/frijolo/deadbolt/releases):

```bash
# Install via ADB
adb install deadbolt-android.apk
```

Or install directly on your device.

### Linux

Download and extract the tarball:

```bash
# Extract
tar -xzf deadbolt-linux-x64.tar.gz

# Run
cd deadbolt
./deadbolt
```

**Hardware wallet (BitBox02) on Linux**: a udev rule is required to access the HID device without root. See [docs/HARDWARE_WALLETS.md](docs/HARDWARE_WALLETS.md) for the one-line setup command.

### Windows

1. Download `deadbolt-windows-x64.zip` from [Releases](https://github.com/frijolo/deadbolt/releases)
2. Extract the ZIP file
3. Run `deadbolt.exe`

### Verifying Releases

Always verify releases before installation. See [SECURITY.md](SECURITY.md) for instructions.

## Usage

### Basic Workflow

1. **Enter or paste a Bitcoin descriptor** into the input field
2. **Analyze** - Deadbolt will parse and extract:
   - Network type (mainnet/testnet/signet/regtest)
   - Wallet type (single-sig, multisig, taproot, etc.)
   - Public keys with derivation paths
   - Spend paths with fee weights
3. **Review** - Examine the extracted information:
   - Verify public keys match your expectations
   - Understand spending conditions
   - Estimate transaction fees

### Example Descriptors

**Single-sig P2WPKH (native SegWit)**:
```
wpkh([d34db33f/84h/0h/0h]xpub6CqzLtyKdJN53jPY13W6GdyB8ZGWuFZuBPU4Xh9DXm6Q66ZEp4BT4NXvz7XbYKHpGnKpRYhF5HCkV4FWdE0hM1qLdLGj3AqnVLxjbqH9cPE/0/*)
```

**2-of-3 multisig**:
```
wsh(sortedmulti(2,[aabbccdd/48h/0h/0h/2h]xpub6E2..., [11223344/48h/0h/0h/2h]xpub6Df..., [99887766/48h/0h/0h/2h]xpub6Fa...))
```

**Taproot single-key**:
```
tr([d34db33f/86h/0h/0h]xpub6BgBgS...)
```

### Signing Options

Deadbolt supports two signing workflows:

- **Hot signing keys** - Store an encrypted private key on-device and sign PSBTs locally without any external hardware
- **BitBox02 hardware wallet** - Connect a BitBox02 via USB to keep private keys off the device entirely

Both workflows produce a signed PSBT that can be broadcast directly from the app.

### What Deadbolt Does NOT Do

- **Does NOT send data to third parties** - Wallet sync connects only to the Electrum server you configure (and optionally through Tor)
- **Does NOT collect telemetry** - No analytics, tracking, or usage data of any kind

## Building from Source

### Prerequisites

- **Flutter SDK** (3.10.7 or later): [Install Flutter](https://docs.flutter.dev/get-started/install)
- **Rust toolchain** (latest stable): [Install Rust](https://rustup.rs/)
- **flutter_rust_bridge_codegen**: `cargo install flutter_rust_bridge_codegen --version 2.11.1`
- Platform-specific dependencies:
  - **Android**: Android SDK, NDK r26d
  - **Linux**: `libgtk-3-dev`, `clang`, `cmake`, `ninja-build`
  - **Windows**: Visual Studio 2022 with C++ tools

### Build Steps

```bash
# Clone repository
git clone https://github.com/frijolo/deadbolt.git
cd deadbolt

# Get Flutter dependencies
flutter pub get

# Build for your platform
flutter build apk --release       # Android
flutter build linux --release     # Linux
flutter build windows --release   # Windows

# Binaries will be in build/<platform>/release/
```

### Running Tests

```bash
# Dart/Flutter tests
flutter test

# Rust tests
cd rust
cargo test

# Linting
flutter analyze
cd rust && cargo clippy
```

## Development

### Project Structure

```
deadbolt/
├── lib/                    # Dart/Flutter code
│   ├── main.dart          # App entry point
│   ├── screens/           # UI screens (+ screens/wallet_detail/ sub-screens)
│   ├── cubit/             # BLoC state management (6 cubits)
│   ├── services/          # WalletService, ProjectDescriptorService, PriceService
│   ├── data/              # Drift database (projects only)
│   ├── models/            # Shared data models
│   ├── widgets/           # Reusable widgets
│   ├── utils/             # Formatters, helpers, toast
│   ├── theme/             # Material 3 theme
│   └── src/rust/          # Auto-generated FFI bindings (DO NOT EDIT)
├── rust/                  # Rust core logic
│   ├── src/
│   │   ├── api/          # FFI boundary (exposed to Dart)
│   │   │   └── wallet/   # Wallet API (directory)
│   │   └── core/         # Internal logic (BDK, descriptors, Tor, etc.)
│   └── Cargo.toml
├── docs/                  # Documentation
├── .github/workflows/     # CI/CD pipelines
└── flutter_rust_bridge.yaml  # FFI configuration
```

### Architecture

- **UI Layer** (Dart/Flutter): Material 3 UI, BLoC state management, responsive layout
- **FFI Bridge** (flutter_rust_bridge): Type-safe Dart ↔ Rust communication
- **Core Layer** (Rust): Bitcoin descriptor parsing via BDK, wallet analysis, fee calculation

### Contributing

Contributions are welcome! Please:

1. Fork the repository
2. Create a feature branch (`git checkout -b feature/amazing-feature`)
3. Commit your changes with **signed commits** (`git commit -S -m "Add amazing feature"`)
4. Push to your fork (`git push origin feature/amazing-feature`)
5. Open a Pull Request

**Note**: All commits must be GPG-signed. See [docs/GPG_SETUP.md](docs/GPG_SETUP.md) for setup instructions.

### Code Style

- **Dart**: Follow [Effective Dart](https://dart.dev/guides/language/effective-dart) guidelines
- **Rust**: Use `cargo fmt` and `cargo clippy`
- **Commits**: Use [Conventional Commits](https://www.conventionalcommits.org/) format
- **Comments**: English only

## Security

Deadbolt is Bitcoin-related software - security is critical. See [SECURITY.md](SECURITY.md) for:

- Release verification instructions
- Vulnerability reporting process
- Security best practices
- GPG key information

**Always verify releases** before installation. Never trust, always verify.

## Privacy

Deadbolt is designed with privacy in mind:

- **No telemetry** - No analytics, tracking, or data collection
- **No built-in servers** - Wallet sync connects only to the Electrum server you configure
- **Optional Tor routing** - Enable the built-in Tor client to hide your wallet's IP address from the Electrum server
- **Local storage only** - Data stays on your device
- **Descriptor analysis is fully offline** - No network access needed to parse and analyze descriptors

However, be aware:
- Descriptors contain public keys and reveal wallet structure
- Avoid sharing descriptors with untrusted parties
- Use on trusted devices only

## Dependencies

### Rust

- **bdk_wallet** (2.3.0) - Bitcoin Development Kit for descriptor parsing and wallet management
- **arti-client** + **tor-rtcompat** (0.22) - Embedded Tor client
- **bitbox-api** (0.9) - BitBox02 hardware wallet integration
- **flutter_rust_bridge** (2.11.1) - Dart ↔ Rust FFI
- **anyhow** / **thiserror** - Error handling

### Dart/Flutter

- **flutter_rust_bridge** (2.11.1) - FFI bindings
- **flutter_bloc** (9.1.1) - State management
- **drift** (2.31.0) - SQLite database for project persistence

See [pubspec.yaml](pubspec.yaml) and [rust/Cargo.toml](rust/Cargo.toml) for full dependency lists.

## License

This project is licensed under the **MIT License** - see [LICENSE](LICENSE) file for details.

## Acknowledgments

- **Bitcoin Development Kit (BDK)** - For excellent Bitcoin descriptor libraries
- **Flutter** and **Rust** communities - For amazing tools and documentation
- Bitcoin Core developers - For descriptor specification and best practices

## Support

- **Issues**: [GitHub Issues](https://github.com/frijolo/deadbolt/issues)
- **Discussions**: [GitHub Discussions](https://github.com/frijolo/deadbolt/discussions)
- **Security**: See [SECURITY.md](SECURITY.md) for security-related concerns

## Disclaimer

Deadbolt is provided "as is" without warranty of any kind. While we strive for correctness and security, users should:

- Verify descriptors against multiple sources
- Test thoroughly before using in production
- Understand that software bugs may exist
- Not rely solely on Deadbolt for critical decisions

**Use at your own risk.**

---

Made with ❤️ for the Bitcoin community. Not your keys, not your coins.
