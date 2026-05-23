# Deadbolt Wallet Security Architecture

This document describes how Deadbolt stores, encrypts, and backs up wallet data. It is intended for users who want to audit the app's security or recover their data independently without relying on the app.

---

## Table of Contents

1. [File Layout](#file-layout)
2. [Device Key](#device-key)
3. [Key-Envelope Architecture](#key-envelope-architecture)
4. [Protection Types](#protection-types)
5. [Biometric Unlock](#biometric-unlock)
6. [`.meta` Sidecar File Format](#meta-sidecar-file-format)
7. [SQLCipher Database](#sqlcipher-database)
8. [`.deadbolt` Backup Format](#deadbolt-backup-format)
9. [Cryptographic Primitives](#cryptographic-primitives)
10. [Independent Recovery (Without the App)](#independent-recovery-without-the-app)
11. [Security Considerations](#security-considerations)
12. [Descriptor Signatures](#descriptor-signatures)

---

## File Layout

All wallet data lives under the app's support directory:

| Platform | App support directory |
|----------|-----------------------|
| Android  | `/data/data/com.deadbolt.app/files/` |
| Linux    | `~/.local/share/deadbolt/` |
| Windows  | `%APPDATA%\deadbolt\deadbolt\` |
| macOS    | `~/Library/Application Support/deadbolt/` |

Within that directory:

```
<app_support>/
├── .wallet_key              ← device key (64 hex chars = 32 bytes)
├── project_seeds.db         ← SQLCipher-encrypted project-level hot signing keys
├── project_seeds.db.meta    ← JSON sidecar: wrapped data key for project_seeds.db
└── wallets/
    ├── <uuid>.db            ← SQLCipher-encrypted BDK wallet database
    ├── <uuid>.db.meta       ← JSON sidecar: protection type + wrapped data key
    ├── <uuid>.db            ← (another wallet)
    └── <uuid>.db.meta
```

Each wallet gets a random UUIDv4 filename (`<uuid>.db`) on creation.

---

## Device Key

The device key is a single 32-byte random value, encoded as 64 lowercase hex characters, stored in `.wallet_key`.

**Generation**: Dart's `Random.secure()` (backed by the OS CSPRNG).

**File permissions**: `chmod 600` on Unix-like systems (owner read/write only).

**Purpose**: The device key is the wrapping key for **Type 0 (DeviceKey)** wallets. It never directly encrypts database contents — each wallet has its own per-wallet data key that is wrapped by the device key.

> **Warning**: If `.wallet_key` is lost, all Type 0 wallets become permanently inaccessible. Type 1 (UserPassword) and Type 2 (XpubKey) wallets are unaffected, as their data keys are wrapped with a credential-derived key instead.

---

## Key-Envelope Architecture

Each wallet has a unique **data key** (32 random bytes). This is the key that SQLCipher uses to encrypt the database file. The data key itself is never stored in plaintext — it is **wrapped** (encrypted) and stored in the `.meta` sidecar file.

```
┌──────────────────────────────────────────────────────────────────────────────┐
│  Type 0 (DeviceKey)   Type 1 (UserPassword)       Type 2 (XpubKey)          │
│                                                                              │
│  device_key           Argon2id(password,salt)   Argon2id(xpubN, saltN)      │
│  (from .wallet_key)          │                  (one slot per descriptor xpub)│
│         │                   ▼                          │                     │
│         ▼            AES-256-GCM wrap          AES-256-GCM wrap (per slot)  │
│   AES-256-GCM wrap          │                          │                     │
│         │                   ▼                          ▼                     │
│   wrapped_data_key    wrapped_data_key          wrapped_data_key[0..N]       │
│   (in .meta)          (in .meta)                (in .meta, one per xpub)    │
│         │                   │                          │                     │
│         │    ╔══════════════╪══════════════════════════╪═══════════╗        │
│         │    ║  Optional biometric slot (Type 1 or 2 only)         ║        │
│         │    ║                                                      ║        │
│         │    ║  biometric_key (random 32 bytes)                     ║        │
│         │    ║  stored in platform keystore,                        ║        │
│         │    ║  released only after hardware biometric auth         ║        │
│         │    ║         │                                            ║        │
│         │    ║         ▼                                            ║        │
│         │    ║   AES-256-GCM wrap (no KDF)                          ║        │
│         │    ║         │                                            ║        │
│         │    ║         ▼                                            ║        │
│         │    ║  biometric_slots[i].wrapped_key (in .meta)           ║        │
│         │    ╚══════════════╪══════════════════════════════════════╝        │
│         │                   │                          │                     │
│    unwrap with         unwrap with              unwrap with any              │
│    device_key          Argon2id key or          matching xpub or             │
│                        biometric_key            biometric_key                │
│         │                   │                          │                     │
│         └─────────────┬─────┘──────────────────────────┘                    │
│                       ▼                                                      │
│             PRAGMA key = x'<data_key>'                                       │
│                       │                                                      │
│                       ▼                                                      │
│              <uuid>.db (SQLCipher)                                           │
└──────────────────────────────────────────────────────────────────────────────┘
```

---

## Protection Types

### Type 0 — DeviceKey (automatic)

- The data key is wrapped with the **device key** stored in `.wallet_key`.
- No user credential required to open the wallet.
- Wallets are tied to the device. Backups require `.wallet_key` to be moved alongside them, or use the `.deadbolt` export.

### Type 1 — UserPassword

- The data key is wrapped with a key derived from the **user's password** via Argon2id.
- The wallet requires the password every session (or until the app is terminated).
- Passwords are held in memory only during the active session and are never persisted to disk.
- These wallets are **portable**: the backup is fully self-contained and can be restored on any device given only the password.

### Type 2 — XpubKey

- The data key is wrapped independently with **each xpub present in the descriptor**. Any one of them can unlock the wallet.
- Opening the wallet requires pasting any registered xpub (bare or in keyspec `[mfp/path]xpub` format). Hardware wallet users can unlock directly via a connected BitBox02 — the device's root fingerprint is matched against registered slots automatically.
- Since xpubs already carry ~256 bits of entropy, brute-force attack against an individual slot is computationally infeasible.
- These wallets are **portable**: they do not depend on the device key and can be unlocked on any device by anyone who possesses a registered xpub.
- Slots can be added or removed after creation (requires presenting a currently-registered xpub).

### Biometric Unlock (optional add-on for Type 1 and Type 2)

Type 1 and Type 2 wallets can optionally have one or more **biometric slots** registered. A biometric slot wraps the same `data_key` with a randomly generated 32-byte key that is stored in the platform's hardware-backed keystore. This allows the wallet to be opened with a fingerprint or face scan instead of typing the password or xpub — the biometric key is released by the hardware only after authentication passes (see [Biometric Unlock](#biometric-unlock)).

Biometric slots are entirely optional. Removing all slots, reinstalling the app, or restoring the wallet on a new device reverts to the primary protection type transparently — the wallet can always be opened with the original password or xpub.

### Changing Protection

Any protection type can be changed to any other at any time using the **Encryption** button in the wallet overview or the wallet menu. The operation re-encrypts the database in-place via `PRAGMA rekey` on the existing connection — no export or import is required, and the wallet remains accessible throughout. A fresh data key is generated on every protection change for forward secrecy.

---

## Biometric Unlock

Biometric unlock is an optional layer that can be added to any Type 1 (UserPassword) or Type 2 (XpubKey) wallet on devices that have enrolled biometrics. It is **not a protection type** — it is a supplementary slot that wraps the same data key with a randomly generated key stored in the platform's hardware security module.

### How it works

When biometric unlock is enabled for a wallet, Deadbolt:

1. Generates a 32-byte random key (`biometric_key`) in Flutter using `Random.secure()`.
2. Sends it to Rust, which wraps the wallet's `data_key` with `biometric_key` via AES-256-GCM (no KDF — the key is already 256 bits of entropy) and stores the resulting `BiometricSlot` in the `.meta` file.
3. Stores `biometric_key` in the platform's hardware-backed keystore under the slot ID (a UUID v4 generated by Rust), protected so it can only be read after biometric authentication.

On subsequent opens, the app reads `biometric_key` from the keystore — which triggers the hardware biometric prompt — then passes it to Rust to unwrap the `data_key` and open the wallet. If biometric authentication fails or is cancelled, the wallet falls back to the primary credential prompt.

### Platform keystore locations

The `biometric_key` is stored by the [`biometric_storage`](https://pub.dev/packages/biometric_storage) plugin, which uses the platform's hardware security module:

| Platform | Storage mechanism | Biometric binding |
|----------|-------------------|--------------------|
| Android  | Android Keystore (AES-256-GCM) | `setUserAuthenticationRequired(true)` — the hardware enforces biometric authentication before the decryption cipher is authorized; the key cannot be used without passing through the hardware biometric stack |
| iOS      | Keychain with `kSecAccessControlBiometryCurrentSet` | The entry is invalidated if enrolled biometrics change (new fingerprint added) |
| macOS    | Keychain with `kSecAccessControlBiometryCurrentSet` | Same as iOS |
| Linux    | GNOME Keyring via libsecret | No biometric support — the option is hidden on Linux |

**On Android specifically**: the decryption cipher is initialized only inside a `BiometricPrompt.CryptoObject` session. The Android OS hardware (or Trusted Execution Environment) verifies the biometric and authorizes the cipher as an atomic operation — there is no separate app-level authentication step that could be bypassed by a compromised process.

### Wrapping scheme

```
biometric_key = 32 random bytes (Dart Random.secure)
wrapped_key   = hex(nonce[12] || AES-256-GCM_encrypt(key=biometric_key, plaintext=data_key_bytes))
```

No KDF is applied between `biometric_key` and the AES-256-GCM key because `biometric_key` already contains 256 bits of entropy. The `wrapped_key` format is identical to other slot types in the `.meta` file.

### Loss and recovery

| Event | Effect |
|-------|--------|
| App reinstalled / data cleared | `biometric_key` is lost (keystore cleared). Rust `.meta` slot remains but cannot be unwrapped. Wallet opens normally with password/xpub. |
| New biometric enrolled (iOS/macOS) | Keychain entry invalidated by `kSecAccessControlBiometryCurrentSet`. Biometric unlock stops working; wallet falls back to password. Re-enable biometric to create a new slot. |
| Biometric disabled in OS settings | Authentication fails; wallet falls back to password. |
| Wallet restored from `.deadbolt` backup | Biometric slots are not included in backups. Re-enable after restore. |
| Wallet restored on a new device | Same as backup restore — no biometric slot on the new device. |

The wallet's primary credential (password or xpub) is **always sufficient** to open the wallet, regardless of biometric slot state.

### Security properties and limitations

**Hardware enforcement (Android)**: The `biometric_key` cannot be read from the Android Keystore without a successful biometric operation at the hardware level. A compromised process cannot bypass this by calling `read()` without authentication.

**App-sandbox protection**: On a non-rooted device, the keystore is isolated to the Deadbolt app. Other apps cannot access `biometric_key`.

**RAM exposure**: After successful authentication, `biometric_key` exists in Dart heap memory as a `String` for the duration of the wallet open operation. Dart strings are GC-managed and cannot be explicitly zeroed. On a device where an attacker can dump process memory (rooted Android, jailbroken iOS), the key could theoretically be extracted. This is equivalent to the risk of extracting a cached password from RAM, and is disclosed in the app UI.

**Device with unlocked bootloader or custom OS**: Hardware security guarantees may be reduced. The Trusted Execution Environment (TEE) that enforces `setUserAuthenticationRequired` can be replaced on devices with an unlocked bootloader. This limitation is inherent to the Android security model and applies to all apps that use Android Keystore biometric binding.

---

## `.meta` Sidecar File Format

Each `.db` file has a companion `<uuid>.db.meta` file containing JSON. This file is **not encrypted** — it holds only the wrapped data key (not the plaintext key) and the KDF parameters needed to unwrap it.

### Type 0 — DeviceKey

```json
{
  "type": "device_key",
  "version": 1,
  "wrapped_key": "<hex>"
}
```

### Type 1 — UserPassword

```json
{
  "type": "user_password",
  "version": 1,
  "salt": "<hex>",
  "m_cost": 4096,
  "t_cost": 1,
  "p_cost": 1,
  "wrapped_key": "<hex>",
  "display_name": "My Wallet",
  "network": "bitcoin",
  "last_synced_at": 1710000000,
  "biometric_slots": [
    {
      "id": "550e8400-e29b-41d4-a716-446655440000",
      "wrapped_key": "<hex>"
    }
  ]
}
```

`display_name`, `network`, and `last_synced_at` are cached in the sidecar so locked wallets can be shown in the list without opening them. They are refreshed on every successful open and sync.

`biometric_slots` is omitted from the JSON entirely when no biometric unlock has been registered (`#[serde(default)]` on the Rust side ensures backward compatibility with older `.meta` files).

### Type 2 — XpubKey

```json
{
  "type": "xpub_key",
  "version": 1,
  "slots": [
    {
      "mfp": "deadbeef",
      "salt": "<hex>",
      "m_cost": 4096,
      "t_cost": 1,
      "p_cost": 1,
      "derivation": "48h/0h/0h/2h",
      "wrapped_key": "<hex>"
    }
  ],
  "display_name": "My Wallet",
  "network": "bitcoin",
  "last_synced_at": 1710000000,
  "biometric_slots": [
    {
      "id": "550e8400-e29b-41d4-a716-446655440000",
      "wrapped_key": "<hex>"
    }
  ]
}
```

Each entry in `slots` corresponds to one xpub from the descriptor. `mfp` is the 8-hex-char master fingerprint used for fast slot lookup. `derivation` is a display hint for the UI only; it does not affect key derivation. `wrapped_key` format is identical to Type 1.

**`biometric_slots[i].id`**: A UUID v4 generated by Rust when the slot is created. This ID is used as the key name in the platform keystore (stored as `deadbolt_biometric_<id>` by the [`biometric_storage`](https://pub.dev/packages/biometric_storage) plugin). The ID has no security significance — it is a pointer to the keystore entry, not a secret.

**`biometric_slots[i].wrapped_key`**: The wallet's `data_key` wrapped with the `biometric_key` via AES-256-GCM. The `biometric_key` is the secret held by the platform keystore; without it, `wrapped_key` cannot be decrypted. A wallet with biometric slots can always be opened by ignoring `biometric_slots` entirely and using the primary credential (`wrapped_key` / `slots`).

**`wrapped_key` format (all types)**: `hex(nonce[12] || ciphertext[32] || tag[16])` — 60 bytes total, encoded as 120 hex characters.

The 12-byte nonce is randomly generated on every wrap operation (including migrations and re-keys).

---

## SQLCipher Database

Each `<uuid>.db` is a standard [SQLCipher](https://www.zetetic.net/sqlcipher/) (SQLite + AES-256-CBC) database. The key is applied as a **raw hex key** using:

```sql
PRAGMA key = "x'<data_key_hex>'";
```

This bypasses SQLCipher's own PBKDF2 derivation — the 32-byte data key is used directly as the AES-256 key material. The rest follows SQLCipher defaults (AES-256-CBC, PBKDF2 HMAC-SHA1 with 64000 iterations is skipped because a raw hex key is used).

### Internal Tables

The database contains [BDK (Bitcoin Development Kit)](https://github.com/bitcoindevkit/bdk) internal tables plus several Deadbolt-specific tables:

```sql
-- Single-row wallet metadata
CREATE TABLE wallet_info (
    id          INTEGER PRIMARY KEY CHECK (id = 1),
    name        TEXT    NOT NULL,
    descriptor  TEXT    NOT NULL,
    network     TEXT    NOT NULL,   -- "bitcoin", "testnet", "signet", "regtest"
    created_at  INTEGER NOT NULL,   -- Unix seconds
    last_synced_at INTEGER          -- Unix seconds, NULL if never synced
);

-- Hot signing keys stored inside the wallet
CREATE TABLE seed_entries (
    id         INTEGER PRIMARY KEY AUTOINCREMENT,
    mfp        TEXT NOT NULL UNIQUE,  -- Master fingerprint of the key
    seed_type  TEXT NOT NULL,         -- "mnemonic" or "xprv"
    mnemonic   TEXT,                  -- BIP39 phrase (if seed_type = "mnemonic")
    passphrase TEXT NOT NULL DEFAULT '',
    xprv       TEXT,                  -- Master private key (if seed_type = "xprv")
    created_at INTEGER NOT NULL
);
```

Additional Deadbolt-specific tables store labels (`tx_labels`, `address_labels`, `key_labels`, `path_labels`, `coin_labels`), saved unsigned transactions / PSBTs (`unsigned_txs`), cached fiat prices (`fiat_prices`), and descriptor ownership signatures (`descriptor_sigs`). All of these are created on demand and remain empty until the relevant feature is used.

`wallet_info` stores public metadata only. `seed_entries` holds wallet-level hot signing keys; it is present in all wallets but remains empty unless the user explicitly adds a signing key.

BDK tables store addresses, UTXOs, transactions, and descriptor data following the BDK SQLite persistence schema.

---

## `.deadbolt` Backup Format

A `.deadbolt` backup is a self-contained, credential-encrypted JSON file. A credential is always required for export (password or xpub), regardless of the wallet's original protection type. **Type 0 (DeviceKey) wallets cannot be exported** — change the protection type first if a portable backup is needed.

### JSON Structure

```json
{
  "version": 2,
  "wallet_name": "My wallet",
  "network": "bitcoin",
  "created_at": 1710000000,
  "protection": {
    "type": 1,
    "slots": [
      {
        "mfp": "deadbeef",
        "salt": "<32-char hex = 16 bytes>",
        "m_cost": 65536,
        "t_cost": 3,
        "p_cost": 1,
        "derivation": "",
        "wrapped_key": "<hex(nonce[12] || AES-GCM-ciphertext+tag of data_key_bytes)>"
      }
    ]
  },
  "data_key_wrapped": "<hex(nonce[12] || AES-GCM-ciphertext+tag of data_key_bytes)>",
  "data": "<base64(nonce[12] || AES-GCM-ciphertext+tag of raw_sqlcipher_db_bytes)>"
}
```

`protection.type` is `1` (UserPassword) or `2` (XpubKey). For UserPassword backups, `slots` contains one entry whose `mfp` is the SHA-256 fingerprint of the password. For XpubKey backups, `slots` contains one entry per descriptor xpub; any one slot can decrypt the backup.

### What is encrypted

- **`data`**: the raw SQLCipher `.db` file bytes, encrypted with AES-256-GCM under `export_data_key`.
- **`data_key_wrapped`**: the 32-byte SQLCipher data key, also encrypted with AES-256-GCM under `export_data_key`. This allows the importer to re-key the database after decryption.

### Key derivation (export)

The export credential depends on the backup type:

- **UserPassword**: credential = password; salt from `protection.slots[0]`
- **XpubKey**: credential = xpub string; salt from the matching slot in `protection.slots`

```
export_key = Argon2id(
    password  = export_credential,
    salt      = slot.salt (16 bytes, from hex),
    m_cost    = slot.m_cost,   // memory: 65536 KiB = 64 MiB
    t_cost    = slot.t_cost,   // iterations: 3
    p_cost    = slot.p_cost,   // parallelism: 1
    output    = 32 bytes
)
```

### Encryption (AES-256-GCM)

```
nonce = random 12 bytes (OsRng)
ciphertext+tag = AES-256-GCM_encrypt(key=export_key, nonce=nonce, plaintext=data)
stored as: nonce || ciphertext || tag
```

The `data` field is Base64-encoded. The `data_key_wrapped` field is hex-encoded.

### Import flow

On import, the original wallet protection type is preserved:
- **Type 0 / Type 1 backups**: the restored database is re-keyed to a fresh random data key and stored as a Type 0 (DeviceKey) wallet on the new device.
- **Type 2 (XpubKey) backups**: imported using any registered xpub as the credential. The restored wallet retains XpubKey protection on the new device.

---

## Cryptographic Primitives

| Primitive | Library | Usage |
|-----------|---------|-------|
| AES-256-GCM | `aes-gcm` crate (RustCrypto) | Key wrapping, backup encryption |
| Argon2id | `argon2` crate (RustCrypto) | Password KDF for Type 1 wallets and backups |
| OS CSPRNG | `rand::OsRng` (Rust) | All random generation (keys, nonces, salts) |
| OS CSPRNG | Dart `Random.secure()` | Biometric key generation |
| Android Keystore AES-256-GCM | `biometric_storage` plugin / Android OS | Hardware-backed biometric key storage and decryption |
| iOS/macOS Keychain | `biometric_storage` plugin / Apple OS | Hardware-backed biometric key storage |
| SQLCipher | BDK's bundled SQLCipher | Database encryption (AES-256-CBC, raw key mode) |
| SHA-256 | BDK | Spend path identifiers (internal) |

**Argon2id parameters** vary by context:

*Wallet creation (Type 1 / Type 2)*:
- The security level chosen at creation time (default **Standard** = 64 MiB / 5 iters) is applied immediately; there is no separate "initial low-cost" tier.
- For Type 2 (XpubKey), the xpub itself provides ~256 bits of entropy, making brute-force computationally infeasible regardless of Argon2 parameters.
- For Type 1 (UserPassword), users who want higher resistance can pick **High** or **Extreme** at creation, or re-encrypt later via **Change Protection**.

*Change-protection and backup export (selectable security level)*:
| Level    | Memory     | Iterations | Target latency (mobile) |
|----------|------------|------------|-------------------------|
| Standard | 64 MiB     | 5          | ~300 ms                 |
| High     | 256 MiB    | 6          | ~1.6 s                  |
| Extreme  | 512 MiB    | 10         | ~5.5 s                  |

Parameters were benchmarked on a mid-range Android device (Termux, aarch64).

---

## Independent Recovery (Without the App)

This section describes how to decrypt and access a `.deadbolt` backup file using standard tools, without running Deadbolt.

You will need: Python 3 with `argon2-cffi` and `pycryptodome`, or any environment that supports Argon2id and AES-256-GCM. You will also need a SQLCipher-capable client (e.g. `sqlcipher` CLI or DB Browser for SQLite with SQLCipher support).

### Step 1: Parse the backup JSON

```python
import json, base64, binascii

with open("my_wallet.deadbolt", "rb") as f:
    backup = json.load(f)

# UserPassword backups: use your password as credential.
# XpubKey backups: use your xpub string as credential (e.g. "xpub6C5s...").
# For XpubKey, adjust the slot index to match your key.
protection = backup["protection"]
slot       = protection["slots"][0]
salt_bytes = binascii.unhexlify(slot["salt"])
m_cost     = slot["m_cost"]    # 65536
t_cost     = slot["t_cost"]    # 3
p_cost     = slot["p_cost"]    # 1
```

### Step 2: Derive the intermediate wrapping key

```python
from argon2.low_level import hash_secret_raw, Type

credential = b"your export password"   # or b"xpub6C5s..." for XpubKey backups

wrapping_key = hash_secret_raw(
    secret=credential,
    salt=salt_bytes,
    time_cost=t_cost,
    memory_cost=m_cost,
    parallelism=p_cost,
    hash_len=32,
    type=Type.ID,     # Argon2id
)
```

### Step 3: Derive the export data key

```python
from Crypto.Cipher import AES

def aes_gcm_decrypt(key, blob_hex_or_bytes, is_hex=True):
    """Decrypt nonce[12] || ciphertext || tag[16] blob."""
    blob = binascii.unhexlify(blob_hex_or_bytes) if is_hex else blob_hex_or_bytes
    nonce, ct_tag = blob[:12], blob[12:]
    ct, tag = ct_tag[:-16], ct_tag[-16:]
    cipher = AES.new(key, AES.MODE_GCM, nonce=nonce)
    return cipher.decrypt_and_verify(ct, tag)

export_data_key = aes_gcm_decrypt(wrapping_key, slot["wrapped_key"])
```

### Step 4: Decrypt the SQLCipher key and database

```python
# Decrypt the SQLCipher data key
data_key = aes_gcm_decrypt(export_data_key, backup["data_key_wrapped"])
data_key_hex = data_key.hex()

# Decrypt the database bytes
db_blob  = base64.b64decode(backup["data"])
db_bytes = aes_gcm_decrypt(export_data_key, db_blob, is_hex=False)

with open("restored.db", "wb") as f:
    f.write(db_bytes)
```

### Step 5: Open the database with SQLCipher

Using the `sqlcipher` CLI:

```sh
sqlcipher restored.db
```

```sql
PRAGMA key = "x'<data_key_hex_from_step_4>'";
-- Replace <data_key_hex_from_step_4> with the 64-char hex string.

SELECT name, descriptor, network, datetime(created_at, 'unixepoch') FROM wallet_info;
```

The database uses WAL journal mode. All Bitcoin transaction and UTXO data is stored in BDK's internal tables alongside the `wallet_info` table.

### Manual UTXO/transaction access

BDK's SQLite persistence tables include:
- `wallet` — wallet metadata (descriptor, network)
- `tx` — transactions
- `utxo` — unspent outputs
- `script_pubkey` — derived addresses

These follow the [BDK SQLite schema](https://github.com/bitcoindevkit/bdk/tree/master/crates/wallet). The `descriptor` field in `wallet_info` contains the full Bitcoin output descriptor — sufficient to reconstruct the wallet in any descriptor-compatible software (BDK, Bitcoin Core with descriptor wallets, Sparrow, etc.).

---

## Security Considerations

**What is protected**:
- Each wallet `.db` contains a `seed_entries` table for wallet-level hot signing keys (mnemonic or xprv + passphrase). This table is encrypted as part of the SQLCipher database, protected by the same per-wallet data key described above.
- The `wallet_info` table and all BDK tables contain **no private key material** — only the public descriptor (xpubs), transaction history, UTXOs, and labels.
- The descriptor contains extended public keys (xpubs) from which addresses can be derived, but not private keys.

**Note on project seeds**: The designer (project) mode has a separate `project_seeds.db` file where hot keys can be stored at the project level. Keys can be copied from there into a specific wallet's `seed_entries` table. These are two independent encrypted stores.

---

## Descriptor Signatures

Deadbolt allows each participating key in a wallet to produce a cryptographic proof that the owner of that key has seen and approved the exact descriptor. These proofs are stored in the `descriptor_sigs` table inside the wallet database and are included in Nostr backups.

Verification is stateless — it requires only the stored `(xpub_entry, message, sig)` triple and no network access. When recovering from a Nostr backup, the app verifies any attached signatures against the recovered descriptor before presenting the result to the user.

Four signing methods are supported: **Hot Key** (programmatic), **BitBox02 via USB**, **QR — PSBT** (Variant B, for any air-gapped PSBT signer), and **QR — Message** (Variant A, standard Bitcoin signed message, for Coldcard, BitBox02, Krux, etc.).

For the full protocol, see [DESCRIPTOR_SIGS.md](DESCRIPTOR_SIGS.md). For the BB02-specific BIP-322 adaptation, see [BB02_BIP322.md](BB02_BIP322.md).

**What is not protected**:
- The `.meta` file is unencrypted and reveals the protection type and, for Type 1 wallets, the Argon2id salt. An attacker with the `.meta` file can launch an offline password-guessing attack against Type 1 wallets if they also have the `.db` file. Type 2 slots also contain a salt per xpub, but the xpub itself provides ~256 bits of entropy, making brute-force infeasible.
- The `.meta` file also stores `biometric_slots[i].wrapped_key` in plaintext. This is a ciphertext that wraps the `data_key` using `biometric_key`. Without `biometric_key` from the platform keystore, this ciphertext cannot be decrypted — it provides no information about the wallet data. The `id` fields are UUIDs with no secret value.
- The `.wallet_key` file is protected by filesystem permissions only (mode 600). On Android, it is in app-private storage. If the device is compromised (rooted Android, physical access to Linux home dir), the device key is exposed, compromising all Type 0 wallets. Type 1 and Type 2 wallets are unaffected.
- The `.deadbolt` backup file is fully self-contained. Its security depends entirely on the strength of the export password and the computational hardness of Argon2id with the specified parameters. Biometric slots are never included in `.deadbolt` backups.
- **Biometric unlock on rooted Android**: on a device with a compromised OS or unlocked bootloader, the Trusted Execution Environment (TEE) that enforces `setUserAuthenticationRequired(true)` may be bypassed or replaced. An attacker could potentially access the platform keystore without biometric authentication, then use the recovered `biometric_key` to unwrap the `data_key` from `.meta`. This is disclosed in the app UI. On a stock, non-rooted device, this attack path is not available.

**Backup recommendations**:
- Use a strong, unique export password (≥16 random characters) when creating `.deadbolt` backups.
- Store the export password separately from the backup file (e.g. in a password manager).
- Type 1 and Type 2 wallets offer better portability guarantees: they do not depend on the device key and can be fully recovered on any device given only the password or a registered xpub.
- For Type 0 wallets, keep a secure copy of `.wallet_key` alongside your backups, or export to `.deadbolt` format (which is always password-protected regardless of the original type).
- Consider using **Change Protection** with High or Extreme security level if you store significant funds in a password-protected wallet — the default creation parameters are optimized for speed, not maximum brute-force resistance.
