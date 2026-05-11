# Deadbolt

**A descriptor-based Bitcoin wallet with multisig, Nostr backup, and hardware wallet support**

Deadbolt manages Bitcoin wallets directly from their output descriptor. No account creation, no cloud sync, no trusted server — your wallet lives on your device and connects only to the Electrum server you choose.

Works as a hot wallet, an air-gapped coordinator, or a multisig co-signer.

[![CI](https://github.com/frijolo/deadbolt/actions/workflows/ci.yml/badge.svg)](https://github.com/frijolo/deadbolt/actions/workflows/ci.yml)
[![Release](https://github.com/frijolo/deadbolt/actions/workflows/release.yml/badge.svg)](https://github.com/frijolo/deadbolt/releases)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE)

---

## Key Features

### Wallet recovery

Recover your wallet from a BIP-39 seed, an xpub/keyspec, or a connected hardware wallet. Built-in discovery scans accounts for balance, and automatically surfaces any descriptor backups found on Nostr or on-chain. SeedQR import supported for Coldcard, SeedSigner, and Krux.

### XPub-based wallet protection

Unlock your wallet with any xpub from the descriptor instead of a password. In a multisig setup, any co-signer can open the wallet independently — no shared secret to distribute or lose. Protection type can be changed at any time without exporting the wallet.

### Nostr encrypted backup

Descriptors are encrypted per-xpub and published to Nostr relays. Each co-signer can independently locate and decrypt their own backup using only their xpub — no password, no seed phrase, no trusted server.

### On-chain descriptor backup

Publish encrypted descriptor backups to the Bitcoin blockchain itself. The descriptor is committed to a Taproot vault and revealed via on-chain transactions, making it recoverable by any co-signer even if Nostr relays are unavailable. Built-in health checks show backup status at a glance.

### Hardware wallet support

Sign PSBTs and export xpubs from a BitBox02 via USB. Private keys never leave the device.

### Air-gapped workflows

Export unsigned PSBTs as animated QR codes (BC-UR). Import signed results from any compatible signer like Coldcard, SeedSigner, or Krux.

### Inheritance wallets

Create Taproot wallets where you control funds normally and a designated heir can access them after a configurable timelock (3 months to custom block height). Re-vault resets the clock in one tap.

### Deep descriptor analysis

Deadbolt parses every descriptor type (P2PKH, P2WPKH, P2WSH, Taproot, miniscript, multipath) and shows you exactly what each spend path costs in fees — before you commit any funds.

### Built-in Tor

All Electrum connections route through an embedded Tor client. No system Tor installation required.

### Privacy by design

- No telemetry, analytics, or data collection
- No built-in servers — sync only to your own Electrum server
- Optional Tor routing
- Descriptor analysis is fully offline

---

## Supported Descriptors

Deadbolt works with all standard Bitcoin descriptor formats:

- **Single-signature**: P2WPKH, P2SH-P2WPKH, P2PKH
- **Multisig**: sortedmulti, unsorted multi, custom miniscript policies
- **Taproot**: tr(), multi-path descriptors, internal key policies
- **Inheritance**: Taproot multi-path with heir timelocks

---

## Platforms

| Platform | Status |
|----------|--------|
| Android | ✅ Released |
| Linux (x64) | ✅ Released |
| Windows (x64) | ✅ Released |

All releases are GPG-signed. Verify before installing — see [SECURITY.md](SECURITY.md).

---

## Installation

### Android

Download the latest APK from [Releases](https://github.com/frijolo/deadbolt/releases) and install on your device.

### Linux

Download and extract the tarball from [Releases](https://github.com/frijolo/deadbolt/releases), then run:

```bash
tar -xzf deadbolt-linux-x64.tar.gz
cd deadbolt
./deadbolt
```

**BitBox02 on Linux**: a udev rule is needed for HID access. See [docs/HARDWARE_WALLETS.md](docs/HARDWARE_WALLETS.md).

### Windows

1. Download `deadbolt-windows-x64.zip` from [Releases](https://github.com/frijolo/deadbolt/releases)
2. Extract the ZIP
3. Run `deadbolt.exe`

---

## Getting Started

### 1. Create a wallet

Deadbolt offers multiple ways to get started:

- **Import a descriptor** — paste any Bitcoin descriptor to analyze and manage an existing wallet
- **Restore from seed** — recover a wallet from a BIP-39 phrase with automatic account discovery
- **Connect BitBox02** — recover or create a wallet from a connected hardware wallet
- **Create new** — generate a fresh single-sig, multisig, or inheritance wallet

### 2. Analyze the descriptor

Deadbolt parses the descriptor and shows:

- Network (mainnet, testnet, signet, regtest)
- Wallet type and spending conditions
- All public keys with derivation paths
- Every spend path with fee estimates

### 3. Manage your wallet

- Check balances and transaction history
- Create transactions with coin control and RBF
- Send to multiple recipients
- Receive with QR codes or addresses
- Back up descriptors via Nostr or on-chain; import/export via QR or SeedQR

---

## Technical Details

For developers and advanced users:

- **[docs/BUILDING.md](docs/BUILDING.md)** — Build from source, run tests
- **[docs/DEVELOPMENT.md](docs/DEVELOPMENT.md)** — Architecture, project structure, contribution guidelines
- **[docs/NOSTR_BACKUP.md](docs/NOSTR_BACKUP.md)** — Nostr backup protocol details
- **[docs/HARDWARE_WALLETS.md](docs/HARDWARE_WALLETS.md)** — BitBox02 setup and usage
- **[docs/DESCRIPTOR_SIGS.md](docs/DESCRIPTOR_SIGS.md)** — Descriptor ownership proofs
- **[SECURITY.md](SECURITY.md)** — Release verification, vulnerability reporting
- [pubspec.yaml](pubspec.yaml) / [rust/Cargo.toml](rust/Cargo.toml) — Full dependency lists

---

## License

This project is licensed under the **MIT License** — see [LICENSE](LICENSE) for details.

---

## Support

- **Issues**: [GitHub Issues](https://github.com/frijolo/deadbolt/issues)
- **Discussions**: [GitHub Discussions](https://github.com/frijolo/deadbolt/discussions)
- **Security**: See [SECURITY.md](SECURITY.md)

---

**Use at your own risk.** Not your keys, not your coins.
