# Deadbolt Wallet Security Architecture

This document describes how Deadbolt stores, encrypts, and backs up wallet data. It is intended for users who want to audit the app's security or recover their data independently without relying on the app.

---

## Table of Contents

1. [File Layout](#file-layout)
2. [Device Key](#device-key)
3. [Key-Envelope Architecture](#key-envelope-architecture)
4. [Protection Types](#protection-types)
5. [`.meta` Sidecar File Format](#meta-sidecar-file-format)
6. [SQLCipher Database](#sqlcipher-database)
7. [`.deadbolt` Backup Format](#deadbolt-backup-format)
8. [Cryptographic Primitives](#cryptographic-primitives)
9. [Independent Recovery (Without the App)](#independent-recovery-without-the-app)
10. [Security Considerations](#security-considerations)

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

> **Warning**: If `.wallet_key` is lost, all Type 0 wallets become permanently inaccessible. Type 1 (UserPassword) wallets are unaffected, as their data keys are wrapped with a password-derived key instead.

---

## Key-Envelope Architecture

Each wallet has a unique **data key** (32 random bytes). This is the key that SQLCipher uses to encrypt the database file. The data key itself is never stored in plaintext — it is **wrapped** (encrypted) and stored in the `.meta` sidecar file.

```
┌─────────────────────────────────────────────────────────────┐
│  Type 0 (DeviceKey)          Type 1 (UserPassword)          │
│                                                             │
│  device_key (from .wallet_key)  Argon2id(password, salt)   │
│         │                              │                    │
│         ▼                              ▼                    │
│     AES-256-GCM wrap              AES-256-GCM wrap          │
│         │                              │                    │
│         ▼                              ▼                    │
│   wrapped_data_key ──────────────────── wrapped_data_key   │
│         │  (stored in .meta)           │  (stored in .meta)│
│         │                              │                    │
│    unwrap with device_key        unwrap with Argon2id key   │
│         │                              │                    │
│         ▼                              ▼                    │
│     data_key ────────────────────── data_key               │
│         │                              │                    │
│         └──────────┬───────────────────┘                    │
│                    ▼                                        │
│          PRAGMA key = x'<data_key>'                        │
│                    │                                        │
│                    ▼                                        │
│           <uuid>.db (SQLCipher)                            │
└─────────────────────────────────────────────────────────────┘
```

---

## Protection Types

### Type 0 — DeviceKey (automatic)

- The data key is wrapped with the **device key** stored in `.wallet_key`.
- No user password required to open the wallet.
- Wallets are tied to the device. Backups require `.wallet_key` to be moved alongside them, or use the `.deadbolt` export.

### Type 1 — UserPassword

- The data key is wrapped with a key derived from the **user's password** via Argon2id.
- The wallet requires the password every session (or until the app is terminated).
- Passwords are held in memory only during the active session and are never persisted to disk.
- These wallets are **portable**: the backup is fully self-contained and can be restored on any device given only the password.

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
  "m_cost": 65536,
  "t_cost": 3,
  "p_cost": 1,
  "wrapped_key": "<hex>"
}
```

**`wrapped_key` format**: `hex(nonce[12] || ciphertext[32] || tag[16])` — 60 bytes total, encoded as 120 hex characters.

The 12-byte nonce is randomly generated on every wrap operation (including migrations and re-keys).

---

## SQLCipher Database

Each `<uuid>.db` is a standard [SQLCipher](https://www.zetetic.net/sqlcipher/) (SQLite + AES-256-CBC) database. The key is applied as a **raw hex key** using:

```sql
PRAGMA key = "x'<data_key_hex>'";
```

This bypasses SQLCipher's own PBKDF2 derivation — the 32-byte data key is used directly as the AES-256 key material. The rest follows SQLCipher defaults (AES-256-CBC, PBKDF2 HMAC-SHA1 with 64000 iterations is skipped because a raw hex key is used).

### Internal Tables

The database contains [BDK (Bitcoin Development Kit)](https://github.com/bitcoindevkit/bdk) internal tables plus two Deadbolt-specific tables:

```sql
CREATE TABLE wallet_info (
    id          INTEGER PRIMARY KEY CHECK (id = 1),
    name        TEXT    NOT NULL,
    descriptor  TEXT    NOT NULL,
    network     TEXT    NOT NULL,   -- "bitcoin", "testnet", "signet", "regtest"
    created_at  INTEGER NOT NULL,   -- Unix seconds
    last_synced_at INTEGER          -- Unix seconds, NULL if never synced
);

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

`wallet_info` stores public metadata only. `seed_entries` holds wallet-level hot signing keys; it is present in all wallets but remains empty unless the user explicitly adds a signing key.

BDK tables store addresses, UTXOs, transactions, and descriptor data following the BDK SQLite persistence schema.

---

## `.deadbolt` Backup Format

A `.deadbolt` backup is a self-contained, password-encrypted JSON file. **The backup password is always required, regardless of the wallet's original protection type.** This means even Type 0 wallets can be exported to a portable backup.

### JSON Structure

```json
{
  "version": 1,
  "wallet_name": "My wallet",
  "network": "bitcoin",
  "created_at": 1710000000,
  "protection": {
    "type": 1,
    "salt": "<32-char hex = 16 bytes>",
    "m_cost": 65536,
    "t_cost": 3,
    "p_cost": 1
  },
  "data_key_wrapped": "<hex(nonce[12] || AES-GCM-ciphertext+tag of data_key_bytes)>",
  "data": "<base64(nonce[12] || AES-GCM-ciphertext+tag of raw_sqlcipher_db_bytes)>"
}
```

### What is encrypted

- **`data`**: the raw SQLCipher `.db` file bytes, encrypted with AES-256-GCM under `export_key`.
- **`data_key_wrapped`**: the 32-byte plaintext data key (the SQLCipher key), also encrypted with AES-256-GCM under `export_key`. This allows the importer to re-key the database after decryption.

### Key derivation (export)

```
export_key = Argon2id(
    password  = export_password,
    salt      = protection.salt (16 bytes, from hex),
    m_cost    = protection.m_cost,   // memory: 65536 KiB = 64 MiB
    t_cost    = protection.t_cost,   // iterations: 3
    p_cost    = protection.p_cost,   // parallelism: 1
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

On import, the restored database is always re-keyed to a fresh random data key and stored as a Type 0 (DeviceKey) wallet on the new device.

---

## Cryptographic Primitives

| Primitive | Library | Usage |
|-----------|---------|-------|
| AES-256-GCM | `aes-gcm` crate (RustCrypto) | Key wrapping, backup encryption |
| Argon2id | `argon2` crate (RustCrypto) | Password KDF for Type 1 wallets and backups |
| OS CSPRNG | `rand::OsRng` (Rust) | All random generation (keys, nonces, salts) |
| SQLCipher | BDK's bundled SQLCipher | Database encryption (AES-256-CBC, raw key mode) |
| SHA-256 | BDK | Spend path identifiers (internal) |

**Argon2id default parameters**:
- Memory: 65536 KiB (64 MiB)
- Iterations: 3
- Parallelism: 1
- Output length: 32 bytes

These target approximately 300ms on a modern CPU, following OWASP recommendations for interactive logins.

---

## Independent Recovery (Without the App)

This section describes how to decrypt and access a `.deadbolt` backup file using standard tools, without running Deadbolt.

You will need: Python 3 with `argon2-cffi` and `pycryptodome`, or any environment that supports Argon2id and AES-256-GCM. You will also need a SQLCipher-capable client (e.g. `sqlcipher` CLI or DB Browser for SQLite with SQLCipher support).

### Step 1: Parse the backup JSON

```python
import json, base64, binascii

with open("my_wallet.deadbolt", "rb") as f:
    backup = json.load(f)

protection = backup["protection"]
salt_bytes  = binascii.unhexlify(protection["salt"])
m_cost      = protection["m_cost"]   # 65536
t_cost      = protection["t_cost"]   # 3
p_cost      = protection["p_cost"]   # 1
```

### Step 2: Derive the export key

```python
from argon2.low_level import hash_secret_raw, Type

export_key = hash_secret_raw(
    secret=b"your export password",
    salt=salt_bytes,
    time_cost=t_cost,
    memory_cost=m_cost,
    parallelism=p_cost,
    hash_len=32,
    type=Type.ID,     # Argon2id
)
```

### Step 3: Decrypt the data key

```python
from Crypto.Cipher import AES

data_key_blob = binascii.unhexlify(backup["data_key_wrapped"])
nonce         = data_key_blob[:12]
ct_and_tag    = data_key_blob[12:]
ciphertext    = ct_and_tag[:-16]
tag           = ct_and_tag[-16:]

cipher    = AES.new(export_key, AES.MODE_GCM, nonce=nonce)
data_key  = cipher.decrypt_and_verify(ciphertext, tag)
# data_key is now 32 bytes — the SQLCipher key
data_key_hex = data_key.hex()
```

### Step 4: Decrypt the database

```python
db_blob    = base64.b64decode(backup["data"])
nonce      = db_blob[:12]
ct_and_tag = db_blob[12:]
ciphertext = ct_and_tag[:-16]
tag        = ct_and_tag[-16:]

cipher   = AES.new(export_key, AES.MODE_GCM, nonce=nonce)
db_bytes = cipher.decrypt_and_verify(ciphertext, tag)

with open("restored.db", "wb") as f:
    f.write(db_bytes)
```

### Step 5: Open the database with SQLCipher

Using the `sqlcipher` CLI:

```sh
sqlcipher restored.db
```

```sql
PRAGMA key = "x'<data_key_hex_from_step_3>';
-- Replace <data_key_hex_from_step_3> with the 64-char hex string.

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

**What is not protected**:
- The `.meta` file is unencrypted and reveals the protection type and, for Type 1 wallets, the Argon2id salt. An attacker with the `.meta` file can launch an offline password-guessing attack against Type 1 wallets if they also have the `.db` file.
- The `.wallet_key` file is protected by filesystem permissions only (mode 600). On Android, it is in app-private storage. If the device is compromised (rooted Android, physical access to Linux home dir), the device key is exposed, compromising all Type 0 wallets.
- The `.deadbolt` backup file is fully self-contained. Its security depends entirely on the strength of the export password and the computational hardness of Argon2id with the specified parameters.

**Backup recommendations**:
- Use a strong, unique export password (≥16 random characters) when creating `.deadbolt` backups.
- Store the export password separately from the backup file (e.g. in a password manager).
- Type 1 wallets offer better portability guarantees: they do not depend on the device key and can be fully recovered from the backup password alone.
- For Type 0 wallets, keep a secure copy of `.wallet_key` alongside your backups, or export to `.deadbolt` format (which is always password-protected regardless of the original type).
