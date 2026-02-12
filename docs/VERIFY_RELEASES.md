# How to Verify Deadbolt Releases

**CRITICAL**: Always verify releases before installation. Deadbolt handles Bitcoin wallet descriptors - using unverified binaries is a serious security risk.

## Why Verification Matters

Deadbolt releases are GPG-signed to protect against:
- **Supply chain attacks** - Tampered binaries on mirrors or CDNs
- **Man-in-the-middle attacks** - Modified downloads during transit
- **Compromised infrastructure** - Malicious uploads to GitHub
- **Impersonation** - Fake releases from unauthorized parties

Verification proves:
1. The binary was built by the legitimate Deadbolt maintainer
2. The binary has not been modified since signing
3. The binary matches the published source code

## Prerequisites

- **GPG (GnuPG)** installed on your system
  - Linux: `sudo apt install gnupg` (Debian/Ubuntu) or `sudo dnf install gnupg` (Fedora)
  - macOS: `brew install gnupg`
  - Windows: [Gpg4win](https://gpg4win.org/)
- **sha256sum** utility (usually pre-installed on Linux/macOS, included with Git Bash on Windows)

## Step-by-Step Verification

### Step 1: Import the Maintainer's Public GPG Key

You only need to do this **once** (unless the key changes).

#### Option A: Import from Repository

```bash
# Download the public key from the repository
curl -sL https://raw.githubusercontent.com/frijolo/deadbolt/main/GPG_PUBLIC_KEY.asc -o deadbolt-gpg-key.asc

# Import the key
gpg --import deadbolt-gpg-key.asc
```

Replace `frijolo` with the actual GitHub username.

#### Option B: Import from Keyserver

```bash
# Import from public keyserver (if available)
gpg --keyserver keyserver.ubuntu.com --recv-keys FINGERPRINT
```

Replace `FINGERPRINT` with the maintainer's GPG key fingerprint (see SECURITY.md).

### Step 2: Verify the Key Fingerprint

**IMPORTANT**: Always verify the fingerprint through **multiple independent channels** to prevent man-in-the-middle attacks.

```bash
gpg --fingerprint <KEY_ID or EMAIL>
```

Expected output:
```
pub   rsa4096 YYYY-MM-DD [SC] [expires: YYYY-MM-DD]
      XXXX XXXX XXXX XXXX XXXX  XXXX XXXX XXXX XXXX XXXX
uid           [ unknown] Maintainer Name <email@example.com>
sub   rsa4096 YYYY-MM-DD [E] [expires: YYYY-MM-DD]
```

**Verify the fingerprint matches** what is published in:
- [SECURITY.md](../SECURITY.md) in this repository
- Project website (if available)
- Maintainer's personal website
- Maintainer's social media profiles (Twitter, Nostr, etc.)
- Third-party security audit reports

If the fingerprints don't match, **DO NOT PROCEED** - the key may be fake.

### Step 3: Download Release Files

Go to the [Releases page](https://github.com/frijolo/deadbolt/releases) and download:

1. **Binary for your platform**:
   - `deadbolt-android.apk` (Android)
   - `deadbolt-linux-x64.tar.gz` (Linux)
   - `deadbolt-windows-x64.zip` (Windows)

2. **Verification files** (required):
   - `SHA256SUMS` - Checksums of all binaries
   - `SHA256SUMS.asc` - GPG signature of the checksums file

Example using `wget`:

```bash
# Replace VERSION with the actual version (e.g., v1.0.0)
VERSION="v1.0.0"
REPO="https://github.com/frijolo/deadbolt/releases/download/${VERSION}"

# Download verification files
wget ${REPO}/SHA256SUMS
wget ${REPO}/SHA256SUMS.asc

# Download your platform binary
wget ${REPO}/deadbolt-linux-x64.tar.gz  # or deadbolt-android.apk, etc.
```

### Step 4: Verify the GPG Signature

Verify that `SHA256SUMS` was signed by the maintainer's GPG key:

```bash
gpg --verify SHA256SUMS.asc SHA256SUMS
```

**Expected output** (good signature):
```
gpg: Signature made Sat 12 Feb 2026 12:00:00 PM UTC
gpg:                using RSA key XXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXX
gpg: Good signature from "Maintainer Name <email@example.com>" [unknown]
gpg: WARNING: This key is not certified with a trusted signature!
gpg:          There is no indication that the signature belongs to the owner.
Primary key fingerprint: XXXX XXXX XXXX XXXX XXXX  XXXX XXXX XXXX XXXX XXXX
```

**What to check**:
- ✅ "Good signature from" matches the expected maintainer name/email
- ✅ Key fingerprint matches what you verified in Step 2
- ⚠️ "WARNING: This key is not certified" is normal (see "Understanding GPG Trust" below)

**BAD signatures** (DO NOT PROCEED):
```
gpg: BAD signature from "..."
gpg: Can't check signature: No public key
gpg: Signature made ... using ... key ID XXXXXXXX (wrong key)
```

If you see a bad signature, **do not use the binary** - it may have been tampered with.

### Step 5: Verify the Binary Checksum

Now verify that your downloaded binary matches the signed checksums:

```bash
sha256sum -c SHA256SUMS --ignore-missing
```

**Expected output**:
```
deadbolt-linux-x64.tar.gz: OK
```

**BAD checksum** (DO NOT PROCEED):
```
deadbolt-linux-x64.tar.gz: FAILED
sha256sum: WARNING: 1 computed checksum did NOT match
```

If the checksum fails, the file was corrupted or tampered with. Re-download and verify again.

### Step 6: Trust and Install

If both verifications passed:
- ✅ GPG signature is good and matches the maintainer's key
- ✅ Binary checksum matches the signed checksums

You can now safely install the binary.

## Quick Verification Script

For convenience, save this script as `verify-deadbolt.sh`:

```bash
#!/bin/bash
set -e

VERSION="${1:-v1.0.0}"
PLATFORM="${2:-linux-x64}"
REPO="https://github.com/frijolo/deadbolt/releases/download"

echo "Verifying Deadbolt ${VERSION} (${PLATFORM})"
echo "================================================"

# Determine file extension
case "${PLATFORM}" in
  android) EXT="apk" ;;
  linux*) EXT="tar.gz" ;;
  windows*) EXT="zip" ;;
  *) echo "Unknown platform: ${PLATFORM}"; exit 1 ;;
esac

BINARY="deadbolt-${PLATFORM}.${EXT}"

# Download files
echo "[1/5] Downloading verification files..."
wget -q ${REPO}/${VERSION}/SHA256SUMS
wget -q ${REPO}/${VERSION}/SHA256SUMS.asc

echo "[2/5] Downloading binary..."
wget -q ${REPO}/${VERSION}/${BINARY}

# Verify GPG signature
echo "[3/5] Verifying GPG signature..."
if gpg --verify SHA256SUMS.asc SHA256SUMS 2>&1 | grep -q "Good signature"; then
  echo "✅ GPG signature valid"
else
  echo "❌ GPG signature verification FAILED"
  exit 1
fi

# Verify checksum
echo "[4/5] Verifying binary checksum..."
if sha256sum -c SHA256SUMS --ignore-missing 2>&1 | grep -q "${BINARY}: OK"; then
  echo "✅ Checksum verified"
else
  echo "❌ Checksum verification FAILED"
  exit 1
fi

echo "[5/5] Verification complete!"
echo "================================================"
echo "✅ ${BINARY} is authentic and safe to install"
```

Usage:
```bash
chmod +x verify-deadbolt.sh
./verify-deadbolt.sh v1.0.0 linux-x64
```

## Understanding GPG Trust

When you first import a GPG key, you'll see:
```
gpg: WARNING: This key is not certified with a trusted signature!
```

This is **normal** and doesn't mean the signature is invalid. It means:
- You haven't explicitly marked this key as "trusted" in your GPG keyring
- You haven't signed the key yourself (Web of Trust)

The important part is:
1. ✅ "Good signature" appears
2. ✅ The fingerprint matches across multiple independent sources
3. ✅ The checksums match

### Marking the Key as Trusted (Optional)

If you want to suppress the warning:

```bash
gpg --edit-key <KEY_ID>
gpg> trust
# Select "5 = I trust ultimately"
gpg> quit
```

**Only do this** after verifying the fingerprint through multiple channels.

## Troubleshooting

### "Can't check signature: No public key"

**Solution**: You haven't imported the maintainer's public key (Step 1)

### "BAD signature"

**Possible causes**:
1. File was corrupted during download - re-download and try again
2. File was tampered with - **DO NOT USE**, report to maintainers
3. Using the wrong GPG key - verify fingerprint

### Checksum mismatch

**Possible causes**:
1. Incomplete download - re-download the binary
2. File was modified - **DO NOT USE**, report to maintainers

### "gpg: Signature made ... using ... ID XXXXXXXX" (unknown key)

**Solution**: The file was signed with a different key. Verify:
- Are you on the correct GitHub repository?
- Is this a legitimate release?
- Has the maintainer changed keys? (check SECURITY.md)

## Reporting Issues

If you encounter:
- Invalid signatures
- Checksum mismatches that persist after re-downloading
- Suspicious or unexpected verification results

**Report immediately**:
- GitHub Issues: https://github.com/frijolo/deadbolt/issues
- Email: security@example.com (if available)
- Do NOT use the binary

## Additional Security Measures

For maximum security:

1. **Verify source code** - Clone the repository and inspect the code
2. **Build from source** - Compile your own binary from verified source
3. **Reproducible builds** - Compare your build to the official release (if supported)
4. **Air-gapped verification** - Verify signatures on an offline machine

## Resources

- [GNU Privacy Guard (GPG) Documentation](https://gnupg.org/documentation/)
- [How to Verify Signatures (Bitcoin Core example)](https://bitcoincore.org/en/download/)
- [Web of Trust Explained](https://en.wikipedia.org/wiki/Web_of_trust)

---

**Remember**: When dealing with Bitcoin-related software, always verify. Trust, but verify.
