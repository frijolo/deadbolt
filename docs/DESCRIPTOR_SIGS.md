# Descriptor Signature Verification

Deadbolt lets each participating key in a wallet **sign a fingerprint of the descriptor**, producing a cryptographic proof that the owner of that key has seen and approved the exact descriptor used to construct the wallet.

These proofs serve a specific purpose: **verifying that a backup — whether a `.deadbolt` file or a Nostr recovery — contains the same descriptor that was originally set up**, not a tampered or substituted one.

---

## Why This Matters

A wallet descriptor contains the full script policy and all xpubs. If a backup is tampered (or if a different descriptor is accidentally imported), all derived addresses change and funds sent to the original addresses become unreachable. A descriptor signature proves that, at the time of signing, the signer had access to the key and intentionally associated it with this exact descriptor.

---

## Signing Methods

Four signing methods are supported, selectable per key:

| Method | Path | Signature format |
|--------|------|-----------------|
| **Hot Key** | Programmatic — no interaction required | BB02-BIP322 (DER) |
| **BitBox02 (USB)** | Device receives a PSBT, signs after user confirms "send to self, fee: 0" | BB02-BIP322 (DER) |
| **QR — PSBT** (Variant B) | Same PSBT exported as BC-UR QR; scanned back after signing on air-gapped device | BB02-BIP322 (DER) |
| **QR — Message** (Variant A) | Standard Bitcoin signed message exported as QR; signature scanned back | Bitcoin message sig (compact 65-byte base64) |

All four methods produce a signature over the **same canonical message** (see below). The two variants differ only in how the signature is obtained from the device.

---

## The Canonical Message

Before signing, Deadbolt computes a canonical message from the wallet descriptor:

```
message = "deadbolt-descriptor-v1:\n" + hex(SHA-256(canonical_descriptor))
```

`canonical_descriptor` is the descriptor string produced by `DescriptorAnalyzer::canonical_descriptor_str()` — a normalized form that strips checksum and trailing whitespace for stability.

The `SHA-256` hash keeps the message at a fixed ~85 characters regardless of descriptor length, which stays within hardware wallet message-signing limits (e.g. Coldcard ≤ 240 chars, BitBox02 also has limits).

**Rust source:** `rust/src/core/bip322.rs` → `descriptor_sig_message()`

---

## Signature Storage

Each wallet database stores at most **one signature per MFP** (master fingerprint) in the `descriptor_sigs` table:

```sql
CREATE TABLE descriptor_sigs (
    id         INTEGER PRIMARY KEY AUTOINCREMENT,
    mfp        TEXT NOT NULL UNIQUE,
    xpub_entry TEXT NOT NULL,   -- full [mfp/path]xpub string from the descriptor
    sig_method TEXT NOT NULL,   -- "bip322" or "message"
    sig_hex    TEXT NOT NULL,   -- DER hex (bip322) or compact base64 (message)
    signed_at  INTEGER NOT NULL -- Unix seconds
);
```

Re-signing with any method replaces the existing entry for that MFP (`INSERT OR REPLACE`).

**Rust source:** `rust/src/core/wallet_persistence/descriptor_sig_storage.rs`

---

## Signature Verification

Verification is performed **eagerly on every read** — there is no separate cache for validity. The `list_descriptor_sigs` API method recomputes validity for every stored signature against the wallet's current canonical message.

The `verify_descriptor_sigs` API method is intentionally identical. Its only distinction is at the Flutter layer: calling it sets `hasVerified = true` in the UI state, switching the display from a neutral "signed" label to "verified" (green) or "invalid" (red).

### `bip322` method (BB02-BIP322)

Reconstructs the deterministic two-transaction chain from the `xpub_entry` and `message`, computes the BIP-143 sighash, and verifies the stored DER signature with ECDSA.

See [BB02_BIP322.md](BB02_BIP322.md) for the full protocol.

**Rust source:** `rust/src/core/bip322.rs` → `verify_bip322_descriptor_sig()`

### `message` method (Variant A — standard Bitcoin message)

Accepts a 65-byte compact base64 signature as produced by most hardware wallets' native "sign message" feature. Verifies using the standard Bitcoin signed message hash:

```
hash = SHA256d( "\x18Bitcoin Signed Message:\n" + varint(len) + message )
```

The signing key must be `xpub/0/0` (the first external-chain child of the account xpub in the descriptor). Coldcard, BitBox02, and Krux "sign with address" all produce 65-byte compact signatures and are verified by this path.

Additionally, Krux's `HDKey.sign` path signs with the account-level xpub key directly over `SHA256(message)` (no magic prefix, DER format). The verifier auto-detects the format from the decoded signature length: 65 bytes → BIP137 compact; otherwise → DER.

**Rust source:** `rust/src/core/bip322.rs` → `verify_bitcoin_message_sig()`

---

## Nostr Backup Integration

When a wallet backup is published to Nostr, the stored descriptor signatures are **included in the encrypted payload** alongside the descriptor:

```json
{
  "descriptor": "wsh(sortedmulti(2,...)))",
  "descriptor_sigs": [
    {
      "mfp": "deadbeef",
      "xpub_entry": "[deadbeef/48'/0'/0'/2']xpub...",
      "sig_method": "bip322",
      "sig_hex": "3044..."
    }
  ]
}
```

On recovery from Nostr, Deadbolt verifies these signatures against the recovered descriptor before presenting the result to the user. The recovery UI shows a `descriptor_sig_verification` result with per-MFP validity.

**Rust source:** `rust/src/api/wallet/nostr_backup.rs` → `verify_descriptor_sigs_from_payload()`

---

## UI Entry Points

The feature is accessed via **Wallet → Security** (lock icon in the wallet overview or wallet menu):

- **Security screen** (`WalletSecurityScreen`) — shows encryption type and a summary of signature status per key. Tap the pencil icon to open the management screen.
- **Management screen** (`DescriptorSigsScreen`) — one tile per participating key, showing MFP, derivation path, xpub, and current status. The sign (✏) button opens a method selector sheet; the delete (🗑) button removes the stored signature after confirmation. The verify (✓) button in the AppBar re-verifies all signatures and shows a toast with the count of valid ones.

**Flutter sources:**
- `lib/screens/wallet_security_screen.dart`
- `lib/screens/descriptor_sigs_screen.dart`
- `lib/cubit/descriptor_sigs_cubit.dart`

---

## Signing Flow per Method

### Hot Key

1. `DescriptorSigsCubit.signWithHotKey(mfp)` → `wallet.sign_descriptor_with_hotkey(mfp)`
2. Rust loads the seed entry for the MFP, derives `root_xprv`, signs the BB02-BIP322 PSBT programmatically at `m/{account_path}/0/0`.
3. The signature is verified before storage.

### BitBox02 (USB)

1. `cubit.preparePsbt(mfp)` → builds the deterministic BB02-BIP322 PSBT and the temporary `wsh(pk(.../<0;1>/*))` descriptor.
2. `showHwCheckRegisterAndSignSheet(...)` registers the descriptor on the connected BB02 and sends the PSBT for signing. The BB02 displays "send to self, fee: 0".
3. On confirmation, `cubit.completeSigFromPsbt(...)` extracts the ECDSA signature from `partial_sigs[0]` and stores it.

### QR — PSBT (Variant B)

Same as BitBox02 but the PSBT is displayed as a BC-UR `crypto-psbt` animated QR. The user scans it with any PSBT-capable air-gapped device, signs, and scans back the signed PSBT.

### QR — Message (Variant A)

1. The canonical message is displayed as a static QR (and as selectable text for copy).
2. The user signs the message on any hardware wallet's native "sign message" feature and pastes or scans the resulting compact base64 signature.
3. `cubit.addSigFromMessage(...)` verifies and stores the signature.
