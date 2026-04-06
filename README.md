# Deadbolt

**A Bitcoin descriptor wallet with first-class multisig, Nostr backup, and built-in Tor**

Built with Flutter (UI) and Rust (BDK core), Deadbolt manages Bitcoin wallets from their output descriptor. It works equally well as an air-gapped coordinator, a hot wallet, or a multisig co-signer — without requiring a trusted server or a cloud account.

[![CI](https://github.com/frijolo/deadbolt/actions/workflows/ci.yml/badge.svg)](https://github.com/frijolo/deadbolt/actions/workflows/ci.yml)
[![Release](https://github.com/frijolo/deadbolt/actions/workflows/release.yml/badge.svg)](https://github.com/frijolo/deadbolt/releases)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE)

## What sets Deadbolt apart

**XPub-based wallet protection** — Wallets can be locked with any xpub from the descriptor instead of a password. Any co-signer key (or a connected BitBox02) unlocks the wallet directly — no password to remember or lose. Protection type (DeviceKey / Password / XPub) can be changed in-place at any time without export.

**Nostr encrypted backup** — Descriptors are encrypted per-xpub (Argon2id + AES-256-GCM) and published to Nostr relays. Each co-signer can independently locate and decrypt their own backup using only their xpub — no password, no seed phrase, no trusted server. See [docs/NOSTR_BACKUP.md](docs/NOSTR_BACKUP.md).

**Inheritance wallets** — Creates Taproot multi-path descriptors where you control funds normally and a designated heir can access them after a configurable timelock (3 months to custom blocks). The overview shows the earliest heir-access date based on actual UTXOs; re-vault resets the clock in one tap.

**Embedded Tor, no daemon** — All Electrum connections route through a built-in arti Tor client. No system Tor installation required; the circuit persists across app restarts.

**Deep descriptor analysis** — Parses every descriptor type (P2PKH, P2WPKH, P2WSH, Taproot, miniscript, multipath `<0;1>/*`). Extracts all xpubs with derivation paths, enumerates every spend path, and calculates the vbyte weight for each — useful for understanding complex miniscript policies before committing funds.

## Features

- **Wallet operations**: Build transactions with coin control and RBF; multi-recipient sends; direct sign-and-broadcast for hot wallets (no PSBT round-trip)
- **Hardware wallet**: Sign PSBTs and export xpubs from a BitBox02 via USB (Android, Linux, Windows) — see [docs/HARDWARE_WALLETS.md](docs/HARDWARE_WALLETS.md)
- **Hot signing keys**: Encrypted on-device keys for single-device workflows; WIF export and WIF sweep supported
- **Wallet recovery** (unified screen with three tabs): restore from a BIP-39 seed phrase with gap-limit account discovery; recover via a connected BitBox02 without revealing your seed; or scan by xpub/keyspec alone — Nostr backups are surfaced automatically alongside on-chain results in all three flows; SeedQR payloads (standard and compact) accepted directly from the camera
- **Labels**: BIP-329 import/export; Liana-format descriptor export
- **QR / BC-UR**: Animated QR for descriptors and PSBTs; SeedQR import; compatible with Coldcard, SeedSigner, Krux
- **Privacy**: No telemetry; sync only to your own Electrum server; optional Tor; fully offline descriptor analysis
- **Cross-platform**: Android, Linux, Windows; GPG-signed releases

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
tar -xzf deadbolt-linux-x64.tar.gz
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
2. **Analyze** — Deadbolt extracts:
   - Network type (mainnet/testnet/signet/regtest)
   - Wallet type (single-sig, multisig, taproot, etc.)
   - Public keys with derivation paths
   - Spend paths with fee weights
3. **Review** — Verify public keys match your expectations, understand spending conditions, estimate fees

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

- **Hot signing keys** — Encrypted key stored on-device; single-sig wallets sign and broadcast in one step without a PSBT round-trip
- **BitBox02** — Connect via USB; private keys never leave the device
- **Air-gapped coordinators** — Export unsigned PSBTs as animated BC-UR QR codes; import the signed result from any compatible signer (Coldcard, SeedSigner, Krux)

### What Deadbolt Does NOT Do

- **Does NOT send data to third parties** — Wallet sync connects only to the Electrum server you configure (and optionally through Tor)
- **Does NOT collect telemetry** — No analytics, tracking, or usage data of any kind

## Building from Source

See [docs/BUILDING.md](docs/BUILDING.md) for prerequisites, build steps, and how to run tests.

## Development

See [docs/DEVELOPMENT.md](docs/DEVELOPMENT.md) for project structure, architecture overview, and contribution guidelines.

## Security

Deadbolt is Bitcoin-related software — security is critical. See [SECURITY.md](SECURITY.md) for:

- Release verification instructions
- Vulnerability reporting process
- Security best practices
- GPG key information

**Always verify releases** before installation. Never trust, always verify.

## Privacy

- **No telemetry** — No analytics, tracking, or data collection
- **No built-in servers** — Wallet sync connects only to the Electrum server you configure
- **Optional Tor routing** — Enable the built-in Tor client to hide your wallet's IP address from the Electrum server
- **Local storage only** — Data stays on your device
- **Descriptor analysis is fully offline** — No network access needed to parse and analyze descriptors

Be aware: descriptors contain public keys and reveal wallet structure. Avoid sharing descriptors with untrusted parties.

## Dependencies

### Rust

- **bdk_wallet** (2.3.0) — Bitcoin descriptor parsing and wallet management
- **arti-client** + **tor-rtcompat** (0.22) — Embedded Tor client
- **bitbox-api** (0.9) + **async-hwi** (0.0.30) — BitBox02 hardware wallet integration
- **flutter_rust_bridge** (2.11.1) — Dart ↔ Rust FFI
- **rusqlite** (0.31, bundled-sqlcipher) — Encrypted SQLite storage
- **anyhow** / **thiserror** — Error handling

### Dart/Flutter

- **flutter_rust_bridge** (2.11.1) — FFI bindings
- **flutter_bloc** (9.1.1) — State management
- **drift** (2.31.0) — SQLite database for project persistence

See [pubspec.yaml](pubspec.yaml) and [rust/Cargo.toml](rust/Cargo.toml) for full dependency lists.

## License

This project is licensed under the **MIT License** — see [LICENSE](LICENSE) for details.

## Acknowledgments

- **Bitcoin Development Kit (BDK)** — For excellent Bitcoin descriptor libraries
- **Flutter** and **Rust** communities — For amazing tools and documentation
- Bitcoin Core developers — For descriptor specification and best practices

## Support

- **Issues**: [GitHub Issues](https://github.com/frijolo/deadbolt/issues)
- **Discussions**: [GitHub Discussions](https://github.com/frijolo/deadbolt/discussions)
- **Security**: See [SECURITY.md](SECURITY.md) for security-related concerns

## Disclaimer

Deadbolt is provided "as is" without warranty of any kind. While we strive for correctness and security, users should verify descriptors against multiple sources, test thoroughly before using in production, and not rely solely on Deadbolt for critical decisions.

**Use at your own risk.**

---

Made with love for the Bitcoin community. Not your keys, not your coins.
