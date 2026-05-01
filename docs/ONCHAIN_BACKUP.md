# Deadbolt — On-Chain Backup: Technical Reference

This document describes the full cryptographic and Bitcoin protocol used by Deadbolt
to store wallet descriptor backups permanently on the Bitcoin blockchain.

---

## Overview

Deadbolt inscribes an **encrypted wallet descriptor** directly into a Bitcoin
transaction using a **commit-reveal** pattern inspired by the Ordinals/inscription
envelope format. Two transactions are required:

- **TX_COMMIT** — A standard PSBT signed by the wallet's own keys. Creates a
  Taproot vault output that commits to the encrypted payload via a tapscript leaf.
- **TX_REVEAL** — Built and broadcast by Deadbolt immediately after TX_COMMIT
  is broadcast. Spends the vault using the script path, making the payload permanently
  visible in the Bitcoin transaction graph.

Both transactions are broadcast in a **CPFP package**: TX_COMMIT pays only the
minimum relay fee, making it unlikely to reach a block on its own at typical fee
rates; TX_REVEAL carries the bulk of the fees, incentivising miners to include
both transactions together via CPFP. TX_COMMIT is technically valid as a
standalone transaction and could be mined independently if fee conditions allow.

For multisig wallets one additional **anchor output** per co-signer xpub is
included in TX_COMMIT. Anchor addresses are deterministic from each xpub and act as
the discovery index: any co-signer with their xpub can locate the backup on any
Electrum server without any out-of-band coordination.

Only the **descriptor** is stored on-chain — no seeds, no private keys, no full
wallet database.

---

## Transaction Structure

### TX_COMMIT outputs

| Canonical position | Script type | Contents |
|--------------------|-------------|----------|
| 0 | P2TR (script path) | Vault — commits to encrypted payload via tapscript leaf |
| 1…N | P2TR (key path, NUMS-tweaked) | One anchor output per xpub (330 sats each) |
| N+1 | P2TR (key path) | Change back to wallet (optional, omitted when dust) |

> **Note:** output positions are not guaranteed. BDK may reorder outputs at build
> time. All consumers (recovery, health check) locate the vault and anchor outputs
> by scriptPubKey, not by vout index.

### TX_REVEAL

| Field | Value |
|-------|-------|
| Inputs | `[0]` vault vout-0 of TX_COMMIT, `[1…N]` anchor vouts |
| Outputs | `[0]` Change P2TR (vault + anchors − fee) |
| Witness[0] | Script-path spend of vault: `<tapscript> <control_block>` |
| Witness[1…N] | Taproot key-path Schnorr signatures over each anchor input |

TX_REVEAL reveals the vault tapscript in its witness, permanently making the
encrypted payload recoverable from the blockchain.

---

## Step 1 — Anchor Key Derivation

For each xpub extracted from the wallet descriptor, Deadbolt derives a deterministic
secp256k1 keypair using the following loop:

```
anchor_domain_tag = b"deadbolt-anchor-v1"

for counter in 0..=255:
    candidate = HMAC-SHA256(
        key  = anchor_domain_tag,
        data = [counter_byte] || xpub_str_utf8
    )
    if candidate is a valid secp256k1 scalar:
        anchor_privkey = candidate
        break
```

The anchor P2TR address is a key-path-only P2TR using the x-only public key derived
from `anchor_privkey`, with no tweak (`None` merkle root).

**Properties:**
- Deterministic: same xpub always yields the same keypair.
- The loop terminates at `counter = 0` in practice; the fallback covers the
  negligible probability of an invalid scalar.
- The private key is never stored — it is rederived on demand during TX_REVEAL
  signing and backup health checks.

**Rust source:** `rust/src/api/wallet/descriptor_backup.rs` → `derive_anchor_key()`,
`anchor_p2tr_address()`

---

## Step 2 — Encrypted Payload Construction

### 2a — Export data key

A fresh 32-byte random key is generated using the OS CSPRNG:

```
export_data_key = random_bytes(32)
```

### 2b — zstd compression + AES-256-GCM encryption of the descriptor

An inner JSON object `{"descriptor":"...", "wallet_name":"..."}` is serialized to
bytes, compressed with zstd (level 22), then encrypted:

```
inner_json      = {"descriptor": descriptor_string, "wallet_name": wallet_name}
compressed      = zstd(inner_json_bytes, level=22)
nonce           = random_bytes(12)
ciphertext+tag  = AES-256-GCM(key=export_data_key, nonce=nonce, plaintext=compressed)
data_field      = base64( nonce[12] || ciphertext || tag[16] )
```

Total AES overhead: 12-byte nonce + 16-byte GCM tag = 28 bytes.

### 2c — XpubKey slots (one per participant)

One encryption slot is produced per `(mfp, xpub, derivation_path)` triple extracted
from the descriptor. Each slot wraps the export data key with the xpub as credential:

```
slot_salt       = random_bytes(16)            // stored as 32-char lowercase hex
wrapping_key    = Argon2id(
    password = xpub,                          // UTF-8 bytes
    salt     = slot_salt,
    m_cost   = 65536,                         // 64 MiB memory
    t_cost   = 3,                             // 3 iterations
    p_cost   = 1,                             // 1 thread
    out_len  = 32
)
slot_nonce      = random_bytes(12)
wrapped_key     = hex( slot_nonce[12] || AES-256-GCM(
    key       = wrapping_key,
    nonce     = slot_nonce,
    plaintext = export_data_key               // 32 raw bytes
) )                                           // = 120 hex chars (12+32+16 bytes)
```

### 2d — Outer payload JSON (version 3)

```json
{
  "version": 3,
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
  ],
  "data": "base64encodedCiphertext..."
}
```

For an N-of-M multisig there are M slots — one per co-signer xpub. Any co-signer
who holds their xpub can independently decrypt the payload.

**Rust source:** `rust/src/api/wallet/descriptor_backup.rs` → `build_encrypted_payload()`

---

## Step 3 — Vault Tapscript / Taproot

### 3a — Double compression

The payload goes through **two independent zstd compression passes** before
being embedded in the tapscript:

| Pass | Input | Output |
|------|-------|--------|
| Inner (Step 2c) | `{"descriptor":"...", "wallet_name":"..."} ` JSON bytes | Stored encrypted inside `"data"` field |
| Outer (Step 3a) | Entire outer payload JSON bytes | Stored in tapscript |

```
tapscript_payload = zstd( payload_json_bytes, level=22 )
```

This outer pass compresses the JSON envelope (version, slots, data),
which typically achieves additional size reduction because slot JSON and base64 have
predictable patterns.

### 3c — Inscription envelope

The outer-compressed bytes are encoded in the tapscript using a standard Script
push opcode envelope:

```
OP_1 (0x51)
OP_FALSE (0x00)
OP_IF (0x63)
  <direct-push / PUSHDATA1 / PUSHDATA2 of payload chunks, ≤ 520 bytes each>
OP_ENDIF (0x68)
```

This envelope mirrors the Ordinals inscription pattern. The script evaluates to
success (`OP_1` leaves `1` on the stack after `OP_FALSE OP_IF … OP_ENDIF` skips
the data block), so **anyone** who provides the tapscript and control block can
spend the vault via script path — which is exactly what TX_REVEAL does. There is
no signature required. Unauthorized key-path spends are prevented by the NUMS
internal key, which has no known discrete logarithm. The script's sole purpose is
to commit data in the witness; spending authority is governed entirely by the
Taproot tree structure.

### 3d — Taproot construction

The tapscript is placed as a single leaf (depth 0) in a Taproot tree:

```
internal_key = NUMS point
               (0x50929b74c1a04954b78b4b6035e97a5e078a5a0f28ec96d547bfee9ace803ac0)
merkle_root  = tapscript_leaf_hash
vault_output = P2TR( tweaked(internal_key, merkle_root) )
```

The internal key is a **Nothing Up My Sleeve (NUMS)** point with no known discrete
logarithm, ensuring the vault **cannot** be spent via key path. The only valid spend
is the script path in TX_REVEAL.

**Rust source:** `rust/src/api/wallet/descriptor_backup.rs` → `vault_tapscript()`,
`vault_taproot()`

---

## Step 4 — Fee Strategy (CPFP Package)

Deadbolt splits fees across TX_COMMIT and TX_REVEAL so that:

- TX_COMMIT pays at most `min_fee_rate` (default: 0.1 sat/vB + 1 sat guard),
  the minimum needed for relay. It is unlikely to reach a block on its own at
  typical fee rates, but it remains a valid standalone transaction.
- TX_REVEAL carries the remainder of the package fee, pulling TX_COMMIT into the
  mempool as a CPFP parent.
- TX_REVEAL is guaranteed to independently meet the minimum relay fee threshold
  (`reveal_vbytes × min_fee_rate`), preventing broadcast rejection at low fee rates.

```
total_fee     = ceil((commit_vbytes + reveal_vbytes) × user_fee_rate)
commit_fee    = ceil(commit_vbytes × min_fee_rate) + 1
reveal_fee    = max(total_fee − commit_fee, ceil(reveal_vbytes × min_fee_rate))
```

**Rust source:** `rust/src/api/wallet/descriptor_backup.rs` → `split_package_fees()`

---

## Step 5 — TX_REVEAL Construction and Signing

TX_REVEAL is built, signed, and broadcast entirely by Deadbolt **without user interaction**, immediately after TX_COMMIT is broadcast:

1. **Anchor inputs** — Each anchor output from TX_COMMIT is swept using the
   deterministic anchor private key (rederived from each xpub). Signed as
   Taproot key-path with `SIGHASH_DEFAULT`.
2. **Vault input** — Spent via script path: the witness pushes
   `[tapscript_bytes, control_block]`. No signature required (the script always
   fails evaluation; what matters is revealing the tapscript in the witness).
3. **Change output** — A single P2TR output back to the wallet's next receive
   address, receiving `vault_sats + anchor_sats − reveal_fee`.

**Rust source:** `rust/src/api/wallet/descriptor_backup.rs` → `build_reveal()`,
`sign_reveal()`

---

## Step 6 — Discovery (Finding a Backup)

To locate an existing backup for a given xpub:

### 6a — Compute the anchor address

Derive the anchor keypair (Step 1) and compute its P2TR address. This address is
unique to the xpub and stable across time.

### 6b — Query Electrum

```
history = electrum.script_get_history(anchor_address.script_pubkey())
```

For each transaction in `history`, fetch the full transaction and check whether
it has an output paying the anchor address. The **first such TX is TX_COMMIT**.

### 6c — Find TX_REVEAL

For each output of TX_COMMIT that is not a known anchor output, query its history:

```
for each non-anchor output (vout, spk) in TX_COMMIT:
    history = electrum.script_get_history(spk)
    for tx in history:
        if tx.input spends (TX_COMMIT_txid, vout):
            TX_REVEAL = tx
            break
```

The vault output is identified by exclusion (not a known anchor scriptPubKey),
since its position within TX_COMMIT is not fixed.

### 6d — Extract and decrypt

In TX_REVEAL's witness for the vault input (script-path spend), the second-to-last
stack item is the tapscript. Parse the inscription envelope to extract the
zstd-compressed bytes, then decompress to obtain the outer payload JSON.

Decrypt following the same XpubKey scheme used for Nostr backups (see Step 4c–4d
in [NOSTR_BACKUP.md](NOSTR_BACKUP.md)).

**Rust source:** `rust/src/api/wallet/descriptor_recovery.rs` → `fetch_onchain_backup()`,
`rust/src/api/wallet/descriptor_backup.rs` → `extract_raw_from_tapscript()`,
`extract_descriptor_from_reveal()`

---

## Step 7 — Backup Health Check

`check_backup_health()` verifies a previously published backup without requiring
user credentials:

1. Derives all anchor addresses from the open wallet's descriptor.
2. Queries Electrum for each anchor's history.
3. Finds TX_COMMIT as the transaction whose outputs cover **all** anchor addresses.
4. Locates TX_REVEAL and attempts to decrypt it using any participant xpub.
5. Verifies the decrypted descriptor produces the same first receive address as the
   current wallet (SHA-256 fingerprint comparison).

Returns `WalletBackupStatus`:

| Field | Meaning |
|-------|---------|
| `found` | At least one matching backup was found on-chain |
| `commit_txid` | TXID of the matching TX_COMMIT |
| `reveal_txid` | TXID of TX_REVEAL (if confirmed) |
| `anchors_reachable` | How many anchor addresses have TX_COMMIT in their history |
| `anchors_total` | Total number of anchors expected (one per xpub) |
| `descriptor_verified` | TX_REVEAL was decrypted and the descriptor matches this wallet |

A backup is **healthy** when: `found = true`, `reveal_txid ≠ null`,
`anchors_reachable = anchors_total`, and `descriptor_verified = true`.

**Rust source:** `rust/src/api/wallet/psbt.rs` → `WalletHandle::check_backup_health()`

---

## Flutter User Flow

```
OnchainBackupScreen
│
├── _Phase.loading
│     └── WalletHandle.checkBackupHealth()     // free — no Argon2id
│           ├── found → _Phase.backupExists    // show health status
│           └── not found → WalletHandle.computeBackupParams()
│                               └── _Phase.utxoSelection
│
├── _Phase.utxoSelection
│     └── user selects UTXOs, fee rate, spend path
│           └── WalletHandle.prepareBackupPsbt()
│                               └── _Phase.awaitingSignature
│
├── _Phase.awaitingSignature
│     └── sign via Hot Key / Hardware Wallet / QR export
│           └── _Phase.confirmBroadcast
│
├── _Phase.confirmBroadcast
│     └── user confirms fee summary
│           └── WalletHandle.finalizeBackup()
│                               └── _Phase.done
│
└── _Phase.backupExists
      └── show commit_txid, reveal_txid, anchor health, descriptor verification
            └── "Publish new backup" → _Phase.utxoSelection
```

**Flutter source:** `lib/screens/wallet_detail/onchain_backup_screen.dart`

---

## Decryption Protocol (Recovery)

### 7a — Extract raw bytes from the blockchain

Parse the witness of the script-path spend input in TX_REVEAL:

```
witness_items = tx.input[0].witness
tapscript     = witness_items[n - 2]   // second to last
control_block = witness_items[n - 1]   // last; first byte & 0xfe == 0xc0
```

Parse the inscription envelope from `tapscript` to recover the zstd-compressed
payload JSON bytes, then decompress.

### 7b — Parse outer payload

```
payload       = JSON.parse(zstd_decompress(tapscript_data))
assert payload["version"] == 3
```

### 7c — Unwrap export key (same as Nostr backup)

For each slot in `payload["slots"]`:

```
wrapping_key   = Argon2id(password=xpub, salt=slot["salt"], m=65536, t=3, p=1, len=32)
combined       = hex_decode(slot["wrapped_key"])  // 60 bytes
nonce          = combined[:12]
ct             = combined[12:]
export_key     = AES-256-GCM.decrypt(key=wrapping_key, nonce=nonce, ct=ct)
```

If decryption fails, try the next slot.

### 7d — Decrypt inner payload

```
encrypted_inner = base64_decode(payload["data"])
nonce           = encrypted_inner[:12]
ct              = encrypted_inner[12:]
compressed      = AES-256-GCM.decrypt(key=export_key, nonce=nonce, ct=ct)
inner_bytes     = zstd_decompress(compressed)
inner           = JSON.parse(inner_bytes)
descriptor      = inner["descriptor"]
wallet_name     = inner["wallet_name"]
```

**Rust source:** `rust/src/api/wallet/descriptor_backup.rs` → `decrypt_onchain_backup()`,
`decrypt_onchain_backup_json()`

---

## Security Properties

| Property | Value |
|----------|-------|
| Symmetric cipher | AES-256-GCM (AEAD) |
| KDF for slot wrapping | Argon2id (RFC 9106) |
| Argon2id memory | 64 MiB (m=65536) |
| Argon2id iterations | 3 |
| Argon2id parallelism | 1 |
| Nonce size | 12 bytes (random, OS CSPRNG) |
| GCM tag size | 16 bytes |
| Compression | zstd level 22 (two passes: inner + outer) |
| Vault internal key | NUMS point — no key-path spend possible |
| Anchor key derivation | HMAC-SHA256 with domain tag + counter |

**What is NOT stored on-chain:**
- Seed phrases or BIP-39 mnemonics
- Private keys or xprvs
- Full wallet database
- Transaction history

**What IS stored on-chain (inside the encrypted payload):**
- The wallet descriptor (public keys + script template)
- Wallet name

An attacker who can read the blockchain (everyone) can see the vault tapscript
bytes in TX_REVEAL's witness, but cannot decrypt the payload without knowing at
least one participant xpub.

---

## Privacy Considerations

### On-chain fingerprint

TX_COMMIT creates a distinctive UTXO pattern: one taproot vault output with a
NUMS internal key, one change output, and one P2TR per co-signer. This pattern
is identifiable on-chain by anyone who suspects the wallet uses Deadbolt backups,
regardless of whether they can decrypt the payload.

### Anchor address linkability

Anchor addresses are deterministic from xpubs. Anyone who knows your xpub can:

1. Derive your anchor P2TR address.
2. Query any Electrum server for its history to locate TX_COMMIT.
3. Find TX_REVEAL and obtain the encrypted payload.
4. Decrypt and read the full descriptor (xpub is the sole credential).

**Threat model**: xpubs are treated as semi-public. They are shared with co-signers
and often derivable from on-chain analysis. The backup system does not add new
exposure beyond what the xpub already grants.

### Mitigation

- Connect to a trusted Electrum server or one you self-host.
- Enable Tor in Settings so queries and broadcasts do not reveal your IP.
- Treat your xpub with the same care as your on-chain privacy.

---

## Rust Source Map

| File | Responsibility |
|------|---------------|
| `rust/src/api/wallet/descriptor_backup.rs` | Protocol constants, payload encryption, vault tapscript/taproot, anchor key derivation, TX_REVEAL construction/signing, fee splitting, decryption |
| `rust/src/api/wallet/descriptor_recovery.rs` | Electrum-based discovery, backup fetch, wallet import |
| `rust/src/api/wallet/psbt.rs` | `WalletHandle` methods: `compute_backup_params`, `prepare_backup_psbt`, `sign_backup_psbt`, `finalize_backup`, `check_backup_health` |
| `rust/src/api/wallet/descriptor_backup_tests.rs` | Unit tests: tapscript round-trips, anchor derivation, fee calculations |
| `rust/src/api/wallet/descriptor_recovery_tests.rs` | Unit tests: tapscript extraction |

## Flutter Source Map

| File | Responsibility |
|------|---------------|
| `lib/screens/wallet_detail/onchain_backup_screen.dart` | Full backup UI: UTXO selection, fee breakdown, signing, broadcast confirmation, health display |
| `lib/screens/wallet_detail/dialogs/publish_backup_sheet.dart` | Entry point sheet that routes to `OnchainBackupScreen` |
| `lib/src/rust/api/wallet/descriptor_backup.dart` | FRB-generated Dart bindings |
| `lib/src/rust/api/wallet/descriptor_recovery.dart` | FRB-generated Dart bindings |

---
