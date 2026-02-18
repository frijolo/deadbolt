# Deadbolt

**A Bitcoin descriptor analyzer for understanding wallet configurations**

Deadbolt is a cross-platform tool that parses and analyzes Bitcoin wallet descriptors to extract network information, public keys, and spend paths with fee weight estimates. Built with Flutter (UI) and Rust (core logic), it provides a secure, offline way to understand complex Bitcoin wallet setups.

[![CI](https://github.com/frijolo/deadbolt/actions/workflows/ci.yml/badge.svg)](https://github.com/frijolo/deadbolt/actions/workflows/ci.yml)
[![Release](https://github.com/frijolo/deadbolt/actions/workflows/release.yml/badge.svg)](https://github.com/frijolo/deadbolt/releases)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE)

## Features

- **Descriptor Parsing**: Supports all Bitcoin descriptor types (P2PKH, P2WPKH, P2WSH, multisig, etc.)
- **Network Detection**: Automatically identifies mainnet, testnet, signet, or regtest
- **Public Key Extraction**: Parses extended public keys (xpub, ypub, zpub, tpub, etc.)
- **Spend Path Analysis**: Identifies all possible spending conditions in complex descriptors
- **Fee Estimation**: Calculates transaction weight for each spend path
- **Offline Operation**: No internet connection required - complete privacy
- **Cross-Platform**: Available for Android, Linux, Windows (iOS/macOS coming soon)
- **Signed Releases**: All binaries are GPG-signed for verification

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

### What Deadbolt Does NOT Do

- **Does NOT handle private keys** - Only analyzes descriptors (public information)
- **Does NOT connect to the internet** - Fully offline operation
- **Does NOT create transactions** - Read-only analysis tool
- **Does NOT store sensitive data** - Stores only descriptors and user-provided labels locally

## Building from Source

### Prerequisites

- **Flutter SDK** (3.x or later): [Install Flutter](https://docs.flutter.dev/get-started/install)
- **Rust toolchain** (1.70+): [Install Rust](https://rustup.rs/)
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
│   ├── screens/           # UI screens
│   ├── cubits/            # BLoC state management
│   └── src/rust/          # Auto-generated FFI bindings (DO NOT EDIT)
├── rust/                  # Rust core logic
│   ├── src/
│   │   ├── api/          # FFI boundary (exposed to Dart)
│   │   └── core/         # Internal logic (BDK, descriptors, etc.)
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

- **No network access** - Completely offline operation
- **No telemetry** - No analytics, tracking, or data collection
- **No third-party services** - No external dependencies at runtime
- **Local storage only** - Data stays on your device

However, be aware:
- Descriptors contain public keys and reveal wallet structure
- Avoid sharing descriptors with untrusted parties
- Use on trusted devices only

## Dependencies

### Rust

- **bdk_wallet** (2.3.0) - Bitcoin Development Kit for descriptor parsing
- **anyhow** - Error handling
- **flutter_rust_bridge** (2.11.1) - Dart ↔ Rust FFI

### Dart/Flutter

- **flutter_rust_bridge** (2.11.1) - FFI bindings
- **flutter_bloc** (9.1.1) - State management
- **drift** - SQLite database (for persistence)

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
