# Deadbolt — Nostr Backup: Technical Reference

This document describes the full cryptographic protocol used by Deadbolt to store
and recover wallet descriptor backups on Nostr relays.

---

## Overview

Deadbolt publishes one **NIP-78 event** (kind `30078`) per xpub found in the wallet
descriptor. Each event is:

- Signed by a **deterministic Nostr keypair** derived from that xpub.
- Encrypted with the **XpubKey scheme**: Argon2id + AES-256-GCM, with a single
  decryption slot for the owning xpub.

This means any co-signer who has their own xpub can independently:

1. Locate their event on any relay (the author pubkey is deterministic from the xpub).
2. Decrypt it using only their xpub as the credential (no password, no seed phrase).

Only the **descriptor** is backed up — no seeds, no full database, no private keys.

---

## Addressing model: one xpub, multiple descriptors

One xpub can participate in multiple wallet descriptors (e.g. the same hardware
wallet key appears in a singlesig and in two different multisigs). Each descriptor
gets its own **addressable NIP-78 slot**, identified by a descriptor-specific
`d` tag:

```
d = "deadbolt-backup-{first8hex(SHA-256(descriptor))}"
```

Discovery from a relay requires no prior knowledge of the `d` tag. A single REQ
filter with `kinds=[30078]` and `authors=[derived_pubkey]` returns **all** backup
events for that xpub, regardless of how many descriptors it is part of.

---

## Step 1 — Nostr Keypair Derivation

The Nostr private key for a given xpub is derived as follows:

```
privkey_bytes = HMAC-SHA256(
    key  = "deadbolt-nostr-backup-v1",   // UTF-8 string used as HMAC key
    data = xpub                           // UTF-8 string (e.g. "xpub6C5sJ...")
)
```

The resulting 32 bytes are used directly as a **secp256k1 scalar** (private key).
The corresponding Nostr pubkey is the x-only (BIP-340) public key derived from
that scalar.

**Properties:**
- Deterministic: same xpub always yields the same keypair.
- Different xpubs always yield different keypairs.
- The private key is never stored anywhere — it is rederived on demand.

**Rust source:** `rust/src/api/wallet/nostr_backup.rs` → `derive_nostr_keypair()`

---

## Step 2 — Payload Construction

For each `(mfp, xpub)` pair extracted from the descriptor, Deadbolt builds a
JSON payload with the following structure:

```json
{
  "version": 1,
  "wallet_name": "My Wallet",
  "network": "bitcoin",
  "created_at": 1712000000,
  "protection": {
    "type": 2,
    "slots": [
      {
        "mfp": "deadbeef",
        "salt": "a1b2c3d4e5f6a7b8c9d0e1f2a3b4c5d6",
        "m_cost": 65536,
        "t_cost": 3,
        "p_cost": 1,
        "derivation": "84h/0h/0h",
        "wrapped_key": "aabbcc...1122334455..."
      }
    ]
  },
  "data": "base64encodedCiphertext..."
}
```

This payload is then base64-encoded and placed in the Nostr event's `content` field.

### 2a — Inner plaintext

The inner plaintext (what ultimately gets encrypted) is a minimal JSON object:

```json
{ "descriptor": "wpkh([deadbeef/84h/0h/0h]xpub6C5s.../<0;1>/*)" }
```

### 2b — Export data key

A fresh 32-byte random key is generated using the OS CSPRNG:

```
export_data_key = random_bytes(32)   // 64-char lowercase hex string internally
```

### 2c — AES-256-GCM encryption of the inner plaintext

```
nonce           = random_bytes(12)
ciphertext+tag  = AES-256-GCM(key=export_data_key, nonce=nonce, plaintext=inner_json)

data_field = base64( nonce[12] || ciphertext || tag[16] )
```

The nonce is prepended to the ciphertext before base64-encoding. Total overhead:
12 bytes (nonce) + 16 bytes (GCM tag) = 28 bytes.

### 2d — XpubKey slot: wrapping the export data key

The export data key is protected using the xpub as the credential:

```
slot_salt       = random_bytes(16)            // 32-char lowercase hex
wrapping_key    = Argon2id(
    password = xpub,                          // UTF-8 bytes
    salt     = slot_salt,
    m_cost   = 65536,                         // 64 MiB memory
    t_cost   = 3,                             // 3 iterations
    p_cost   = 1,                             // 1 thread
    out_len  = 32                             // 256-bit output
)
slot_nonce      = random_bytes(12)
wrapped_key     = hex( slot_nonce[12] || AES-256-GCM(
    key       = wrapping_key,
    nonce     = slot_nonce,
    plaintext = export_data_key               // 32 raw bytes
) )
```

The `wrapped_key` hex field is `nonce[12] || ciphertext[32] || tag[16]` = 60 bytes
= 120 hex chars.

**Rust source:**
- `rust/src/core/key_protection.rs` → `wrap_with_xpub()`, `wrap_key()`
- `rust/src/api/wallet/nostr_backup.rs` → `build_payload_for_xpub()`

---

## Step 3 — Nostr Event

The payload JSON bytes are base64-encoded and published as a **NIP-78 addressable
event** (kind 30078):

```json
{
  "kind": 30078,
  "pubkey": "<x-only-pubkey-hex derived from xpub>",
  "created_at": <unix_timestamp>,
  "tags": [
    ["d", "deadbolt-backup"],
    ["t", "deadbolt-backup"]
  ],
  "content": "<base64(payload_json_bytes)>",
  "id": "<sha256 of canonical event>",
  "sig": "<Schnorr signature over id>"
}
```

Key points:
- The `d` tag `"deadbolt-backup-{fingerprint}"` makes the event addressable (NIP-78).
  Only the latest event per `(pubkey, kind, d)` is kept by most relays. Different
  descriptors yield different fingerprints, so they coexist as separate slots.
- The event is signed with the private key derived in Step 1.
- One event is published per xpub — for a 2-of-3 multisig there are 3 events,
  each encrypted for a different co-signer.

**Relay protocol:** raw WebSocket with Nostr's `["EVENT", {...}]` JSON messages.
No NIP-42 auth or NIP-44 encryption is used — all cryptography is in the payload.

**Rust source:** `rust/src/api/wallet/nostr_backup.rs` → `build_nostr_event()`,
`ws_publish_event()`

---

## Step 4 — Recovery (Decryption)

To recover a descriptor from a backup:

### 4a — Locate all events for the xpub

Compute the Nostr pubkey from the xpub (same HMAC-SHA256 derivation as Step 1),
then send a REQ filter to a relay:

```json
["REQ", "sub1", {
  "kinds": [30078],
  "authors": ["<pubkey_hex>"]
}]
```

No `#d` filter is used. The relay returns **every** kind-30078 event authored by
this pubkey — one per distinct descriptor backed up under that xpub. The relay
returns `["EVENT", "sub1", {...}]` messages followed by `["EOSE", "sub1"]`.

When a descriptor has been re-published, only the latest event for each `d` tag
is returned by the relay (NIP-78 addressable event semantics).

### 4b — Decode the payload

```
payload_bytes = base64.decode(event["content"])
payload       = json.parse(payload_bytes)
```

### 4c — Unwrap the export data key

For each slot in `payload["protection"]["slots"]`:

```
wrapping_key   = Argon2id(
    password = xpub,
    salt     = bytes.fromhex(slot["salt"]),
    m_cost   = slot["m_cost"],     // 65536
    t_cost   = slot["t_cost"],     // 3
    p_cost   = slot["p_cost"],     // 1
    out_len  = 32
)
combined       = bytes.fromhex(slot["wrapped_key"])
nonce          = combined[:12]
ct             = combined[12:]
export_data_key = AES-256-GCM(key=wrapping_key, nonce=nonce).decrypt(ct)
// AES-GCM tag is the last 16 bytes of ct
```

If decryption fails (wrong xpub), try the next slot.

### 4d — Decrypt the descriptor

```
encrypted_inner = base64.decode(payload["data"])
nonce           = encrypted_inner[:12]
ct              = encrypted_inner[12:]
inner_bytes     = AES-256-GCM(key=export_data_key, nonce=nonce).decrypt(ct)
inner           = json.parse(inner_bytes)
descriptor      = inner["descriptor"]
```

**Rust source:** `rust/src/api/wallet/nostr_backup.rs` → `fetch_nostr_backup()`,
`import_nostr_backup()`

---

## Security Properties

| Property | Value |
|----------|-------|
| Symmetric cipher | AES-256-GCM (AEAD) |
| KDF | Argon2id (RFC 9106) |
| Argon2id memory | 64 MiB (m=65536) |
| Argon2id iterations | 3 |
| Argon2id parallelism | 1 |
| Nonce size | 12 bytes (random, OS CSPRNG) |
| Tag size | 16 bytes (GCM standard) |
| Key derivation for Nostr key | HMAC-SHA256 |
| Nostr signature scheme | Schnorr (BIP-340) |

**What is NOT stored on relays:**
- Seed phrases or BIP-39 mnemonics
- Private keys or xprvs
- Full wallet database
- Transaction history

**What IS stored on relays:**
- The wallet descriptor (public keys + script template)
- Wallet name, network, creation timestamp (all in the encrypted payload)

A relay operator who intercepts the event cannot decrypt it without knowing the
xpub. The xpub is public information (it appears in the derived Nostr pubkey), so
the threat model assumes xpubs are semi-public — an attacker with your xpub can
see your on-chain history but cannot spend funds.

---

## Default Relays

Deadbolt ships with the following default relay list (configurable in Settings →
Nostr Relays):

- `wss://relay.damus.io`
- `wss://relay.primal.net`
- `wss://nos.lol`

---

## Event Lifecycle

- Events use `kind: 30078` (NIP-78 arbitrary application data), which is
  **replaceable by `d` tag** — publishing a new backup for the same xpub replaces
  the old one on compliant relays.
- The `created_at` field inside the payload is the wallet's creation timestamp
  (not the backup timestamp), so it stays stable across re-publishes.
- The outer Nostr event's `created_at` is the actual publish time.
