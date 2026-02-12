# GPG Setup Guide for Deadbolt

This guide walks you through setting up GPG signing for Deadbolt development. **GPG signing is mandatory** for all commits and releases to ensure the integrity and authenticity of the codebase.

## Why GPG Signing Matters

Deadbolt is Bitcoin-related security software. Users need to cryptographically verify that:
- Code commits come from legitimate maintainers
- Release binaries match the source code
- No supply chain tampering has occurred

GPG signing provides this assurance.

## Prerequisites

- Git installed
- GPG (GnuPG) installed
  - **Linux**: `sudo apt install gnupg` (Debian/Ubuntu) or `sudo dnf install gnupg` (Fedora)
  - **macOS**: `brew install gnupg`
  - **Windows**: Install [Gpg4win](https://gpg4win.org/)

## Step 1: Check for Existing GPG Keys

```bash
gpg --list-secret-keys --keyid-format=long
```

If you see keys listed with `sec` (secret key), you can skip to Step 3. Otherwise, generate a new key.

## Step 2: Generate a New GPG Key

### 2.1 Start Key Generation

```bash
gpg --full-generate-key
```

### 2.2 Answer Prompts

1. **Key type**: Select `(1) RSA and RSA` (default)
2. **Key size**: Enter `4096` (maximum security)
3. **Expiration**: Enter `2y` (2 years - recommended for signing keys)
   - You'll be prompted to renew before expiration
4. **Real name**: Your full name (as it appears on GitHub)
5. **Email address**: **Must match your GitHub email exactly**
6. **Comment**: Optional (e.g., "Deadbolt signing key")
7. **Passphrase**: Choose a **strong passphrase** - you'll need this for signing

### 2.3 Verify Key Creation

```bash
gpg --list-secret-keys --keyid-format=long
```

Output should look like:
```
sec   rsa4096/ABCD1234EFGH5678 2026-02-12 [SC] [expires: 2028-02-12]
      1234567890ABCDEF1234567890ABCDEF12345678
uid                 [ultimate] Your Name <your.email@example.com>
ssb   rsa4096/9876543210FEDCBA 2026-02-12 [E] [expires: 2028-02-12]
```

**Your key ID** is the part after `rsa4096/` (e.g., `ABCD1234EFGH5678`).

## Step 3: Configure Git to Sign Commits

### 3.1 Set Your Signing Key

```bash
# Replace ABCD1234EFGH5678 with your actual key ID
git config --global user.signingkey ABCD1234EFGH5678
```

### 3.2 Enable Automatic Signing

```bash
# Sign all commits by default
git config --global commit.gpgsign true

# Sign all tags by default
git config --global tag.gpgsign true
```

### 3.3 Verify Git Configuration

```bash
git config --global user.signingkey  # Should show your key ID
git config --global commit.gpgsign   # Should show "true"
git config --global tag.gpgsign      # Should show "true"
```

### 3.4 (Optional) Configure GPG TTY for Terminal

Add to your `~/.bashrc` or `~/.zshrc`:

```bash
export GPG_TTY=$(tty)
```

Then reload: `source ~/.bashrc` (or `~/.zshrc`)

## Step 4: Export Your Public Key

### 4.1 Export to File

```bash
# Replace ABCD1234EFGH5678 with your key ID
gpg --armor --export ABCD1234EFGH5678 > GPG_PUBLIC_KEY.asc
```

This creates `GPG_PUBLIC_KEY.asc` containing your public key in ASCII armor format.

### 4.2 Display Key Fingerprint

```bash
gpg --fingerprint ABCD1234EFGH5678
```

Example output:
```
pub   rsa4096 2026-02-12 [SC] [expires: 2028-02-12]
      1234 5678 90AB CDEF 1234  5678 90AB CDEF 1234 5678
uid           [ultimate] Your Name <your.email@example.com>
sub   rsa4096 2026-02-12 [E] [expires: 2028-02-12]
```

**Save the fingerprint** (the long hex number) - users will need this to verify your signatures.

## Step 5: Add GPG Key to GitHub

### 5.1 Copy Public Key

```bash
# Linux/macOS
cat GPG_PUBLIC_KEY.asc | xclip -selection clipboard  # or pbcopy on macOS

# Or just display and copy manually
cat GPG_PUBLIC_KEY.asc
```

### 5.2 Add to GitHub Account

1. Go to [GitHub Settings → SSH and GPG keys](https://github.com/settings/keys)
2. Click **New GPG key**
3. Paste the entire contents of `GPG_PUBLIC_KEY.asc` (including `-----BEGIN PGP PUBLIC KEY BLOCK-----` and `-----END PGP PUBLIC KEY BLOCK-----`)
4. Click **Add GPG key**

### 5.3 Verify GitHub Integration

After your next signed commit is pushed, GitHub will show a **Verified** badge next to it.

## Step 6: Configure GitHub Actions for Signing Releases

To enable automated GPG signing in GitHub Actions workflows:

### 6.1 Export Private Key (for GitHub Secrets)

```bash
# Replace ABCD1234EFGH5678 with your key ID
gpg --armor --export-secret-keys ABCD1234EFGH5678 | base64 -w0
```

**Copy the output** (long base64 string).

### 6.2 Add to GitHub Repository Secrets

1. Go to your GitHub repository
2. Navigate to **Settings → Secrets and variables → Actions**
3. Click **New repository secret**
4. Add two secrets:
   - **Name**: `GPG_PRIVATE_KEY`
     - **Value**: Paste the base64 output from 6.1
   - **Name**: `GPG_PASSPHRASE`
     - **Value**: Your GPG key passphrase

**Security note**: GitHub encrypts secrets and only exposes them to workflows. Never commit your private key to the repository.

## Step 7: Test Signing

### 7.1 Test Commit Signing

```bash
# Make a test change
echo "test" > test.txt
git add test.txt
git commit -m "Test GPG signing"

# Verify the commit is signed
git log --show-signature -1
```

You should see:
```
gpg: Signature made ...
gpg: Good signature from "Your Name <your.email@example.com>"
```

### 7.2 Test Tag Signing

```bash
git tag -s test-v1.0.0 -m "Test signed tag"

# Verify the tag is signed
git tag -v test-v1.0.0
```

You should see a "Good signature" message.

### 7.3 Clean Up Test

```bash
git tag -d test-v1.0.0
git reset HEAD~1
rm test.txt
```

## Troubleshooting

### "gpg: signing failed: Inappropriate ioctl for device"

**Solution**: Set GPG_TTY environment variable (see Step 3.4)

### "gpg: signing failed: No secret key"

**Solution**: Verify your signing key is configured correctly:
```bash
git config --global user.signingkey
gpg --list-secret-keys
```

### Commits not showing "Verified" on GitHub

**Possible causes**:
1. GPG key not added to GitHub account (Step 5)
2. Email in GPG key doesn't match git email:
   ```bash
   git config --global user.email  # Must match GPG key email
   ```
3. Key expired - check with `gpg --list-keys`

### GitHub Actions failing with GPG errors

**Check**:
1. `GPG_PRIVATE_KEY` secret is base64-encoded correctly (no newlines with `-w0` flag)
2. `GPG_PASSPHRASE` secret matches your key's passphrase
3. Workflow has `GPG_TTY` set (handled in workflow YAML)

## Key Maintenance

### Extending Key Expiration

Before your key expires:

```bash
gpg --edit-key ABCD1234EFGH5678
gpg> expire
# Follow prompts to set new expiration
gpg> save

# Re-export public key
gpg --armor --export ABCD1234EFGH5678 > GPG_PUBLIC_KEY.asc
```

Update the public key on GitHub and in the repository.

### Revoking a Compromised Key

If your private key is compromised:

```bash
# Generate revocation certificate
gpg --output revoke.asc --gen-revoke ABCD1234EFGH5678

# Import revocation
gpg --import revoke.asc

# Publish revocation
gpg --keyserver keyserver.ubuntu.com --send-keys ABCD1234EFGH5678
```

Then generate a new key and follow this guide from Step 2.

## Resources

- [GitHub: Signing commits with GPG](https://docs.github.com/en/authentication/managing-commit-signature-verification/signing-commits)
- [GnuPG Documentation](https://gnupg.org/documentation/)
- [Keybase](https://keybase.io/) - Alternative for publishing and verifying keys

## Next Steps

After completing GPG setup:

1. **Commit the public key**: `git add GPG_PUBLIC_KEY.asc && git commit -S -m "Add GPG public key"`
2. **Initialize repository**: Follow main setup instructions
3. **Create first release**: Tag with `git tag -s v1.0.0 -m "Release v1.0.0"`

---

**Security reminder**: Never share your private key or passphrase. Only the public key (`GPG_PUBLIC_KEY.asc`) should be committed to the repository.
