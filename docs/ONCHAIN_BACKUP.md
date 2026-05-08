# Deadbolt — On-Chain Backup: Protocol Reference

This document specifies the cryptographic and Bitcoin protocol Deadbolt uses to
publish wallet descriptor backups permanently on the Bitcoin blockchain. It is
written as a protocol description so that any independent implementation can
reproduce, verify, or recover a backup without depending on Deadbolt's source
tree.

Reference implementation: Rust under `rust/src/api/wallet/descriptor_backup.rs`
and `descriptor_recovery.rs`. A standalone recovery script independent of the
app is provided at `scripts/fetch_onchain_backup.py`.

---

## 1. Overview

Deadbolt inscribes an **encrypted wallet descriptor** into a Bitcoin transaction
using a **commit-reveal** pattern inspired by the Ordinals/inscription envelope
format. Two transactions are required:

- **TX_COMMIT** — A standard PSBT signed by the wallet's own keys. Creates a
  Taproot vault output that commits to the encrypted payload via a tapscript
  leaf, plus one anchor output per co-signer xpub.
- **TX_REVEAL** — Built and broadcast by Deadbolt automatically right after
  TX_COMMIT. Spends the vault using the script path and sweeps every anchor,
  making the encrypted payload permanently visible in the Bitcoin transaction
  graph.

Both transactions are broadcast as a **CPFP package**: TX_COMMIT pays only
slightly above the network minimum relay fee, so it is unlikely to be mined on
its own at typical fee rates; TX_REVEAL carries the bulk of the package fee and
pulls TX_COMMIT in via CPFP. TX_COMMIT is technically a valid standalone
transaction and could be mined independently if fee conditions allow.

The **anchor outputs** are deterministic from each co-signer's xpub. Anyone
holding their own xpub can locate the backup on any Electrum server with no
out-of-band coordination.

Only the **descriptor** (and the user-given wallet name) is stored on-chain —
no seeds, no private keys, no full wallet database.

---

## 2. Transaction Structure

### 2.1 TX_COMMIT — logical contents

> **Important.** Output positions are **not** part of the protocol. BDK may
> reorder outputs at build time. All consumers MUST locate outputs by their
> scriptPubKey, never by vout index.

| Logical role | Script type | Contents | Sats |
|--------------|-------------|----------|------|
| Vault | P2TR (script path) | Commits to encrypted payload via tapscript leaf | `vault_sats` (see §5) |
| Anchor (one per xpub) | P2TR (key path) | Funds TX_REVEAL and acts as discovery beacon | 330 |
| Change (optional) | Wallet's next internal-keychain output | Returns surplus to the wallet | `change_sat` |

If `change_sat` would fall below the P2TR dust limit (330 sats) the change
output is omitted entirely and the surplus is absorbed into the commit fee.

### 2.2 TX_REVEAL

| Field | Value |
|-------|-------|
| Inputs | The vault outpoint (script-path spend) plus every anchor outpoint (key-path spend) |
| Outputs | A single P2TR output paying the wallet's next **internal** (change) keychain address, value `vault_sats + Σ anchor_sats − reveal_fee` |
| Vault witness | `[tapscript_bytes, control_block]` — no signature required |
| Anchor witnesses | One Taproot key-path Schnorr signature with `SIGHASH_DEFAULT` per anchor input |

TX_REVEAL reveals the vault tapscript in its witness, permanently making the
encrypted payload recoverable from the chain.

---

## 3. Anchor Key Derivation

For each xpub extracted from the wallet descriptor, Deadbolt derives a
deterministic secp256k1 keypair using the following loop:

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

The xpub is fed to HMAC as its standard Base58Check string form (e.g.
`xpub6...`, `tpub...`, `Vpub...`), as produced by the BIP32 serialisation.

The anchor address is a **key-path-only** P2TR built from the x-only public key
of `anchor_privkey`, with no merkle root (`None`).

Properties:

- Deterministic: a given xpub always yields the same keypair.
- The loop terminates at `counter = 0` in practice; the fallback covers the
  negligible probability of an invalid scalar.
- The private key is never stored — it is rederived on demand for TX_REVEAL
  signing and for backup health checks.

---

## 4. Encrypted Payload Construction

### 4.1 Generate the export data key

```
export_data_key = random_bytes(32)        // OS CSPRNG
```

### 4.2 Inner zstd + AES-256-GCM (the descriptor)

A JSON object containing the descriptor and the wallet name is compressed and
encrypted:

```
inner_json     = {"descriptor": descriptor_string, "wallet_name": wallet_name}
compressed     = zstd(inner_json_bytes, level=22)
nonce          = random_bytes(12)
ciphertext+tag = AES-256-GCM(key=export_data_key, nonce=nonce, plaintext=compressed)
data_field     = base64( nonce[12] || ciphertext || tag[16] )
```

AES-256-GCM overhead: 12-byte nonce + 16-byte authentication tag = 28 bytes.

### 4.3 XpubKey slots — one per participant

For every `(mfp, xpub, derivation_path)` triple extracted from the descriptor
the export data key is wrapped using the xpub as credential. Triples are sorted
by `mfp` so that slot ordering is deterministic.

```
slot_salt    = random_bytes(16)            // serialised as 32-char lowercase hex
wrapping_key = Argon2id(
    password = xpub,                       // UTF-8 bytes of the Base58Check xpub
    salt     = slot_salt,
    m_cost   = 65536,                      // 64 MiB memory
    t_cost   = 3,                          // 3 iterations
    p_cost   = 1,                          // 1 thread
    out_len  = 32
)
slot_nonce   = random_bytes(12)
wrapped_key  = hex( slot_nonce[12]
                 || AES-256-GCM(key=wrapping_key, nonce=slot_nonce,
                                plaintext = export_data_key /* 32 raw bytes */) )
                                           // 12 + 32 + 16 = 60 bytes → 120 hex chars
```

### 4.4 Outer payload JSON (version 3)

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

For an N-of-M multisig there are M slots — one per co-signer xpub. Any holder
of any participant xpub can independently decrypt the payload.

The `derivation` field is informational (a UI hint) and is not used during
decryption.

---

## 5. Vault Output

### 5.1 Outer zstd compression

The entire outer payload JSON bytes go through a **second** independent zstd
pass before being embedded in the tapscript:

```
tapscript_payload = zstd( outer_payload_json_bytes, level=22 )
```

The two compression passes serve distinct purposes: the inner pass shrinks the
descriptor inside the encrypted blob; the outer pass shrinks the JSON envelope
(version, slots, base64 data) which has very predictable structure.

### 5.2 Inscription envelope

The compressed bytes are pushed into a tapscript using the standard envelope
format:

```
OP_1 (0x51)
OP_FALSE (0x00)
OP_IF (0x63)
  <push of payload chunks, ≤ 520 bytes each, via direct push / PUSHDATA1 / PUSHDATA2>
OP_ENDIF (0x68)
```

When this script is evaluated it succeeds: `OP_1` pushes `1`, `OP_FALSE` pushes
`0`, `OP_IF` pops `0` and skips the data block, and the final stack contains
`[1]`. **Anyone** who can produce the tapscript and a valid control block can
spend the vault via the script path — no signature is required. Spending
authority is governed entirely by the Taproot tree structure: key-path spends
are blocked because the internal key is a NUMS point with no known discrete
logarithm.

### 5.3 Taproot construction

The tapscript is placed as a single leaf at depth 0:

```
internal_key = NUMS point
               (0x50929b74c1a04954b78b4b6035e97a5e078a5a0f28ec96d547bfee9ace803ac0)
merkle_root  = tapscript_leaf_hash
vault_output = P2TR( tweaked(internal_key, merkle_root) )
```

The internal key is the standard "Nothing Up My Sleeve" point with no known
discrete logarithm, so the only valid spend is the script path used by
TX_REVEAL.

### 5.4 Vault output value

The vault output funds the anchor sweep plus the reveal fee. Its value is:

```
vault_sats = max( 330, reveal_fee − N_anchors × 330 )
```

This guarantees the vault is at least the P2TR dust minimum (330 sats) and that
TX_REVEAL has enough total input value to pay its fee plus a non-dust change
output back to the wallet.

---

## 6. Fee Strategy (CPFP Package)

The user-facing fee rate is split across the two transactions so that:

- **TX_COMMIT** pays close to the network minimum: `min_fee_rate × commit_vbytes
  + 1 sat`. The +1 sat guard ensures the transaction clears the relay floor on
  every node implementation. At normal fee rates TX_COMMIT is unlikely to be
  mined on its own.
- **TX_REVEAL** carries the rest of the package fee, becoming the CPFP child
  that pulls TX_COMMIT into a block. Its fee is also clamped from below by
  `min_fee_rate × reveal_vbytes` so that TX_REVEAL independently meets the
  relay floor even when `user_fee_rate ≈ min_fee_rate`.

```
total_fee  = ceil( (commit_vbytes + reveal_vbytes) × user_fee_rate )
commit_fee = ceil( commit_vbytes × min_fee_rate ) + 1
reveal_fee = max( total_fee − commit_fee,
                  ceil( reveal_vbytes × min_fee_rate ) )
```

`min_fee_rate` defaults to 0.1 sat/vB.

---

## 7. TX_REVEAL Construction and Signing

TX_REVEAL is built, signed, and broadcast entirely by Deadbolt **without user
interaction**, immediately after TX_COMMIT is broadcast:

1. **Inputs.**
   - Input 0: the vault outpoint, spent via the script path. Its witness is
     exactly `[tapscript_bytes, control_block]`. No signature is required.
   - Inputs 1…N: each anchor outpoint, in the same order as the participant
     triples (sorted by `mfp`). Each is spent with a Taproot key-path Schnorr
     signature using `SIGHASH_DEFAULT`.
2. **Output.** A single P2TR output paying the wallet's next **internal**
   (change) keychain address. Its value is
   `vault_sats + N × 330 − reveal_fee`. The change must be ≥ 330 sats; if not,
   the reveal is rejected before broadcast.
3. **nLockTime / nSequence.** TX_REVEAL uses `nLockTime = 0` and
   `nSequence = ENABLE_RBF_NO_LOCKTIME` on every input.

The control block for the script-path spend is computed from the Taproot tree
in §5.3 (single leaf, no merkle path).

---

## 8. Discovery (Finding a Backup)

There are two distinct discovery scenarios with different knowledge
assumptions. The protocol behaves correctly in both.

### 8.1 Discoverer with their own xpub only (recovery)

The recovering party knows only their own xpub — typically the only
information that survives a device loss alongside the seed phrase.

1. Derive the anchor keypair (§3) and compute the anchor P2TR address.
2. Query the Electrum server for that anchor's history:

   ```
   history = electrum.script_get_history(anchor_spk)
   ```

3. For every transaction in `history`, fetch the full transaction. **Every** tx
   that has an output paying the anchor address is a candidate `TX_COMMIT`.
   The same xpub may have published several backups over time, so the protocol
   does not assume a single match — implementations should iterate the full
   list and surface every successful recovery.
4. For each candidate `TX_COMMIT`, find `TX_REVEAL` by walking every output of
   the commit transaction except the one paying the queryer's own anchor and
   asking Electrum for the spending transaction:

   ```
   for (vout, output) in TX_COMMIT.output:
       if output.script_pubkey == discoverer_anchor_spk:
           continue   # already known to be an anchor
       history = electrum.script_get_history(output.script_pubkey)
       for tx in history:
           if tx spends (TX_COMMIT.txid, vout):
               TX_REVEAL = tx
               break
   ```

   This is robust to any output reordering applied by BDK at build time. Note
   that the discoverer cannot tell anchor outputs of other co-signers apart
   from the vault output — but this does not matter, because TX_REVEAL spends
   **all** outputs of TX_COMMIT, so any output the loop tries either yields
   the same TX_REVEAL or no result at all.

### 8.2 Discoverer who already has the wallet (health check)

When the wallet is loaded the discoverer knows the descriptor, hence every
participant xpub and every anchor address. The health check uses this stronger
knowledge:

1. Derive every anchor address.
2. Query all anchor histories from Electrum.
3. The unique transaction whose outputs pay **every** anchor address is
   `TX_COMMIT`. (Required: a backup must reach all anchors to be considered
   healthy.)
4. Locate `TX_REVEAL` as in §8.1, this time excluding **all** known anchor
   scriptPubKeys from the candidate output set.
5. Decrypt the payload using any one of the participant xpubs.
6. Verify that the decrypted descriptor produces the same first receive
   address as the open wallet (compared via SHA-256 hex of the address
   string).

A backup is **healthy** when all of the following hold:

| Field | Healthy value |
|-------|---------------|
| `found` | `true` |
| `reveal_txid` | not `null` |
| `anchors_reachable` | equals `anchors_total` |
| `descriptor_verified` | `true` |

---

## 9. Decryption Protocol

### 9.1 Extract the tapscript bytes

In `TX_REVEAL`, locate the input that performs the script-path spend (its
control block byte `& 0xfe == 0xc0`). Within that input's witness:

```
n             = witness.len()
tapscript     = witness[n - 2]
control_block = witness[n - 1]
```

Parse the inscription envelope from `tapscript` (§5.2), accumulating every
data push between `OP_IF` and `OP_ENDIF` to recover the outer-compressed
bytes. Decompress with zstd to obtain the outer payload JSON.

### 9.2 Parse the outer payload

```
payload = JSON.parse(zstd_decompress(tapscript_data))
assert payload["version"] == 3
```

### 9.3 Unwrap the export key

For each slot in `payload["slots"]`:

```
wrapping_key = Argon2id(
    password = xpub_utf8,
    salt     = hex_decode(slot["salt"]),
    m_cost   = slot["m_cost"],     // 65536 in v3
    t_cost   = slot["t_cost"],     // 3 in v3
    p_cost   = slot["p_cost"],     // 1 in v3
    out_len  = 32,
)
combined   = hex_decode(slot["wrapped_key"])    // 60 bytes
nonce      = combined[:12]
ct         = combined[12:]
export_key = AES-256-GCM.decrypt(key=wrapping_key, nonce=nonce, ct=ct)
                                              // 32 raw bytes
```

If decryption fails, try the next slot. If the outer JSON contains an `mfp`
field on a slot and the discoverer can compute their own MFP, slots whose
`mfp` does not match can be skipped as an optimisation.

### 9.4 Decrypt the inner payload

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

---

## 10. Security Properties

| Property | Value |
|----------|-------|
| Symmetric cipher | AES-256-GCM (AEAD) |
| KDF for slot wrapping | Argon2id (RFC 9106) |
| Argon2id memory | 64 MiB (m=65536) |
| Argon2id iterations | 3 |
| Argon2id parallelism | 1 |
| Nonce size | 12 bytes (random, OS CSPRNG) |
| GCM tag size | 16 bytes |
| Compression | zstd level 22 (two passes: inner descriptor + outer envelope) |
| Vault internal key | NUMS point — no key-path spend possible |
| Anchor key derivation | HMAC-SHA256 with domain tag + counter |

**What is NOT stored on-chain:**

- Seed phrases or BIP-39 mnemonics
- Private keys or xprvs
- Full wallet database
- Transaction history

**What IS stored on-chain (inside the encrypted payload):**

- The wallet descriptor (public keys + script template)
- The user-given wallet name

An attacker who can read the blockchain (everyone) can see the vault tapscript
bytes in TX_REVEAL's witness, but cannot decrypt the payload without knowing
at least one participant xpub.

---

## 11. Privacy Considerations

### On-chain fingerprint

TX_COMMIT creates a distinctive UTXO pattern: one Taproot vault output with a
NUMS internal key, one P2TR per co-signer, and an optional change output. This
pattern is identifiable on-chain by anyone who suspects the wallet uses
Deadbolt backups, regardless of whether they can decrypt the payload.

### Anchor address linkability

Anchor addresses are deterministic from xpubs. Anyone who knows your xpub can:

1. Derive your anchor P2TR address.
2. Query any Electrum server for its history to locate TX_COMMIT.
3. Find TX_REVEAL and obtain the encrypted payload.
4. Decrypt and read the full descriptor (xpub is the only credential).

**Threat model.** xpubs are treated as semi-public. They are shared with
co-signers and often derivable from on-chain analysis. The backup system does
not add new exposure beyond what the xpub already grants.

### Mitigation

- Connect to a trusted Electrum server, ideally self-hosted.
- Enable Tor in Settings so queries and broadcasts do not reveal your IP.
- Treat your xpub with the same care as your on-chain privacy.

---
