# Security Policy

## Overview

Deadbolt is a Bitcoin descriptor analyzer and wallet manager — security software that helps users understand, analyze, and manage Bitcoin wallet configurations. We take security seriously and implement industry best practices to protect users.

## Supported Versions

| Version | Supported          |
| ------- | ------------------ |
| 1.x.x   | :white_check_mark: |
| < 1.0   | :x:                |

We recommend always using the latest stable release.

## Release Verification

**CRITICAL**: All official Deadbolt releases are cryptographically signed with GPG. Always verify releases before installation.

### GPG Key Information

**Maintainer**: frijolo
**Email**: frijolin@proton.me
**Key ID**: `593FBBED4849293C`
**Fingerprint**: `A629 277A 6EFC 89EC 035D  3788 593F BBED 4849 293C`

The full public key is available in this repository: [GPG_PUBLIC_KEY.asc](GPG_PUBLIC_KEY.asc)

### Quick Verification

```bash
# 1. Import the public key
curl -sL https://raw.githubusercontent.com/frijolo/deadbolt/master/GPG_PUBLIC_KEY.asc | gpg --import

# 2. Download release files from GitHub Releases
wget https://github.com/frijolo/deadbolt/releases/download/v1.9.3/SHA256SUMS
wget https://github.com/frijolo/deadbolt/releases/download/v1.9.3/SHA256SUMS.asc
wget https://github.com/frijolo/deadbolt/releases/download/v1.9.3/deadbolt-<platform>.<ext>

# 3. Verify GPG signature
gpg --verify SHA256SUMS.asc SHA256SUMS

# 4. Verify binary checksum
sha256sum -c SHA256SUMS --ignore-missing
```

**Detailed instructions**: See [docs/VERIFY_RELEASES.md](docs/VERIFY_RELEASES.md)

### What to Verify

✅ **Always verify**:
- GPG signature on `SHA256SUMS.asc` is valid
- Key fingerprint matches the one published here
- Binary checksum matches `SHA256SUMS`

❌ **Never install** if:
- GPG signature verification fails
- Checksum doesn't match
- Release is not from the official GitHub repository
- No signature files are provided

## Reporting a Vulnerability

We take all security bugs seriously. If you discover a security vulnerability in Deadbolt, please report it responsibly.

### Scope

**In scope**:
- Vulnerabilities in Deadbolt's code (Dart, Rust)
- Security issues in dependencies that affect Deadbolt
- Cryptographic implementation flaws
- Privacy leaks or data exposure
- Code injection vulnerabilities
- Authentication/authorization bypasses
- Supply chain security issues

**Out of scope**:
- Social engineering attacks
- Denial of Service attacks on user devices
- Issues in third-party services not under our control
- Vulnerabilities in outdated/unsupported versions

### How to Report

**DO NOT** create public GitHub issues for security vulnerabilities.

**Preferred methods** (in order):

1. **GitHub Security Advisories** (recommended)
   - Go to: https://github.com/frijolo/deadbolt/security/advisories
   - Click "Report a vulnerability"
   - Provide detailed information

2. **Encrypted Email**
   - Email: `frijolin@proton.me`
   - Encrypt your message with the maintainer's GPG key (see above)
   - Subject: `[SECURITY] Deadbolt Vulnerability Report`

### What to Include

Please provide:
- **Description** of the vulnerability
- **Steps to reproduce** the issue
- **Impact assessment** (who is affected, severity)
- **Proof of concept** code (if applicable)
- **Suggested fix** (optional but appreciated)
- **Your contact information** for follow-up

### Response Timeline

- **Initial response**: Within 48 hours
- **Vulnerability assessment**: Within 7 days
- **Fix development**: Depends on severity (critical: 7-14 days, high: 14-30 days, medium: 30-60 days)
- **Public disclosure**: After fix is released and users have time to update (typically 30 days)

### Disclosure Policy

We follow **coordinated disclosure**:

1. You report the vulnerability privately
2. We acknowledge and validate the issue
3. We develop and test a fix
4. We release a patched version
5. We publish a security advisory
6. You may publish your findings after the advisory (if you wish)

We will credit you in the security advisory unless you prefer to remain anonymous.

## Security Best Practices for Users

### Installation

1. **Download only from official sources**
   - GitHub Releases: https://github.com/frijolo/deadbolt/releases
   - Verify the repository URL carefully
   - Avoid third-party download sites

2. **Always verify signatures** (see above)

3. **Check for updates regularly**
   - Subscribe to GitHub releases: Click "Watch" → "Custom" → "Releases"
   - Enable notifications for security advisories

### Usage

1. **Keep Deadbolt updated**
   - Security fixes are released promptly
   - Older versions may have known vulnerabilities

2. **Understand what Deadbolt does**
   - Analyzes Bitcoin descriptors and manages on-device Bitcoin wallets
   - Supports hot signing keys (encrypted private keys stored locally) and BitBox02 hardware wallet signing
   - If you use hot signing keys, protect your device — the encrypted key material is stored in app-private storage. See [docs/WALLET_SECURITY.md](docs/WALLET_SECURITY.md) for the full security architecture
   - Wallet sync connects to the Electrum server configured in Settings (ships with a public default; point it at your own for stricter privacy) — no data sent to third parties beyond that server
   - Optional built-in Tor routing (arti) hides your IP from the Electrum server; enable in Settings
   - Does NOT collect telemetry or analytics

3. **Protect your descriptors and signing keys**
   - Descriptors contain public keys and reveal your wallet structure — avoid sharing them with untrusted parties
   - If using hot signing keys, use a strong wallet password and keep your device secure
   - Use the `.deadbolt` encrypted backup format to safely move wallets between devices

4. **Use on trusted devices**
   - Run Deadbolt on malware-free systems
   - Consider using an air-gapped device for maximum security

### Building from Source

For maximum trust, build Deadbolt from source:

```bash
# Clone repository
git clone https://github.com/frijolo/deadbolt.git
cd deadbolt

# Verify latest signed tag
git tag -v v1.9.3

# Checkout verified tag
git checkout v1.9.3

# Build
flutter pub get
flutter build <platform> --release
```

## Security Features

### Current Implementation

- ✅ **GPG-signed checksums** - SHA256SUMS file is cryptographically signed with GPG
- ✅ **Checksum verification** - SHA256 checksums for all release binaries
- ✅ **Signed commits** - All commits are GPG-signed (enabled from v1.0.0)
- ✅ **Signed tags** - All version tags are GPG-signed
- ✅ **Dependency pinning** - Exact version dependencies to prevent supply chain attacks
- ✅ **No telemetry** - No analytics, tracking, or data sent to external servers
- ✅ **Memory safety** - Core logic in Rust (memory-safe language)
- ✅ **CI/CD verification** - Automated testing on all platforms
- ✅ **Wallet encryption** - SQLCipher (AES-256-CBC) per-wallet database; data key wrapped with AES-256-GCM
- ✅ **Password-derived keys** - Argon2id KDF for password-protected wallets (Type 1) and xpub-protected wallets (Type 2)
- ✅ **XPub key protection** - Wallets can be unlocked by any registered xpub from the descriptor; brute-force infeasible due to xpub entropy (~256 bits)
- ✅ **Selectable Argon2id levels** - Standard / High / Extreme presets calibrated on real mobile hardware (300 ms / 1.6 s / 5.5 s)
- ✅ **Encrypted backups** - `.deadbolt` backup format uses Argon2id + AES-256-GCM; self-contained and portable
- ✅ **Nostr encrypted backup** - Wallet descriptors encrypted per-xpub (Argon2id + AES-256-GCM) and published to Nostr relays; the xpub is the sole credential to both locate and decrypt each event
- ✅ **Tor routing** - Optional embedded Tor client (arti) routes all Electrum traffic through the Tor network, hiding the user's IP from the Electrum server

### Planned Improvements

- 🔄 **Reproducible builds** - Bit-for-bit identical builds (planned)
- 🔄 **SBOM (Software Bill of Materials)** - Detailed dependency manifest (planned)
- 🔄 **Automated security scanning** - CodeQL, Dependabot, etc. (in progress)
- 🔄 **Third-party security audit** - Independent code review (future)

## Secure Development Practices

We follow these practices:

1. **Code Review**
   - All changes reviewed before merging
   - Security-sensitive code gets extra scrutiny

2. **Dependency Management**
   - Regular updates for security patches
   - Pinned versions to prevent unexpected changes
   - Review of transitive dependencies

3. **Testing**
   - Unit tests for Rust core logic
   - Integration tests for Dart/Rust FFI
   - Manual testing on all supported platforms

4. **Signed Commits**
   - All commits signed with maintainer's GPG key
   - Prevents unauthorized code injection

5. **Minimal Dependencies**
   - Only well-maintained, reputable dependencies
   - Prefer standard library implementations when possible

## Known Limitations

- **Descriptor privacy**: Descriptors contain public keys and wallet structure. While not as sensitive as private keys, they should still be handled carefully.
- **Platform security**: Deadbolt's security depends on the underlying OS and device security.
- **Side channels**: Like any software, Deadbolt may be vulnerable to side-channel attacks (timing, memory) on compromised systems.
- **Nostr backup — xpub ↔ identity correlation**: The Nostr keypair used to author encrypted backup events is derived deterministically from your xpub via `HMAC-SHA256("deadbolt-nostr-backup-v1", xpub)`. Anyone who knows your xpub can compute the matching Nostr pubkey, query any relay to enumerate your backup events, and decrypt their contents — the xpub is the single credential for all three operations. Since xpubs are semi-public by Bitcoin's threat model (visible in descriptors, shared with co-signers, derivable from on-chain data), this does not add new exposure — but users should be aware that Nostr relay operators can correlate backup activity to an xpub if that xpub is known. Enable Tor (Settings → Tor) to hide your IP from relay operators during backup operations. See [docs/NOSTR_BACKUP.md — Privacy Considerations](docs/NOSTR_BACKUP.md) for full details.

## Security Advisories

Published security advisories will be available at:
- GitHub Security Advisories: https://github.com/frijolo/deadbolt/security/advisories
- Releases page (for patched versions)

## Contact

- **General questions**: Open a GitHub issue
- **Security concerns**: Use the reporting process above
- **GPG key verification**: Check multiple sources (this file, project website, maintainer's social media)

---

**Last updated**: 2026-04-12
**GPG Fingerprint**: `A629 277A 6EFC 89EC 035D  3788 593F BBED 4849 293C`
