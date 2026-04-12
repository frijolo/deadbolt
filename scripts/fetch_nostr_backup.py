#!/usr/bin/env python3
"""
Deadbolt Nostr Backup Recovery Tool
=====================================
Fetches and decrypts a wallet descriptor backup stored on Nostr relays.

This script replicates the exact cryptographic protocol used by the Deadbolt
app, showing every intermediate step and value so you can verify the process.

Usage:
    python fetch_nostr_backup.py --xpub <xpub_or_keyspec> \\
        --relay wss://nos.lol \\
        [--relay wss://relay.damus.io] \\
        [--verbose]

    xpub_or_keyspec:
        Bare xpub:   xpub6C5sJJ3iZxbk...
        Keyspec:     [deadbeef/84h/0h/0h]xpub6C5sJJ3iZxbk...

Requirements:
    pip install websockets coincurve argon2-cffi cryptography

Protocol reference: docs/NOSTR_BACKUP.md
"""

import argparse
import asyncio
import base64
import hashlib
import hmac
import json
import re
import sys
from typing import Optional

# ── Dependency check ──────────────────────────────────────────────────────────

def _require(package: str, import_name: str, install_hint: str):
    try:
        return __import__(import_name)
    except ImportError:
        print(f"\n[ERROR] Missing dependency: {package}")
        print(f"        Install with: pip install {install_hint}")
        sys.exit(1)


_coincurve  = _require("coincurve",    "coincurve",            "coincurve")
_argon2     = _require("argon2-cffi",  "argon2",               "argon2-cffi")
_crypto     = _require("cryptography", "cryptography",         "cryptography")
_websockets = _require("websockets",   "websockets",           "websockets")

import coincurve
import websockets
from argon2.low_level import hash_secret_raw, Type as Argon2Type
from cryptography.hazmat.primitives.ciphers.aead import AESGCM

# ── Helpers ──────────────────────────────────────────────────────────────────

BOLD   = "\033[1m"
DIM    = "\033[2m"
GREEN  = "\033[32m"
YELLOW = "\033[33m"
RED    = "\033[31m"
CYAN   = "\033[36m"
RESET  = "\033[0m"

verbose = False


def step(n: int | str, title: str):
    print(f"\n{BOLD}{'─' * 60}{RESET}")
    print(f"{BOLD}Step {n}: {title}{RESET}")
    print(f"{BOLD}{'─' * 60}{RESET}")


def info(label: str, value: str):
    print(f"  {CYAN}{label:<28}{RESET} {value}")


def detail(msg: str):
    if verbose:
        print(f"  {DIM}{msg}{RESET}")


def ok(msg: str):
    print(f"  {GREEN}✓ {msg}{RESET}")


def fail(msg: str):
    print(f"\n[FAIL] {msg}")
    sys.exit(1)


# ── Step 1: Parse xpub credential ────────────────────────────────────────────

def parse_xpub_credential(credential: str) -> tuple[Optional[str], str]:
    """
    Parse bare xpub or keyspec [mfp/path]xpub.
    Returns (mfp_hint, xpub).
    """
    credential = credential.strip()
    m = re.match(r'^\[([0-9a-fA-F]{8})([^\]]*)\](.+)$', credential)
    if m:
        mfp  = m.group(1).lower()
        xpub = m.group(3).strip()
        return mfp, xpub
    return None, credential


# ── Step 2: Derive Nostr keypair from xpub ────────────────────────────────────

def derive_nostr_keypair(xpub: str) -> tuple[bytes, bytes, str]:
    """
    Derive a deterministic Nostr keypair from an xpub.

    Algorithm:
        privkey = HMAC-SHA256(key="deadbolt-nostr-backup-v1", data=xpub)

    Returns (privkey_bytes[32], pubkey_xonly[32], pubkey_hex[64]).
    """
    privkey_bytes = hmac.new(
        b"deadbolt-nostr-backup-v1",
        xpub.encode("utf-8"),
        hashlib.sha256,
    ).digest()

    detail(f"HMAC-SHA256 output (privkey): {privkey_bytes.hex()}")

    priv_obj = coincurve.PrivateKey(privkey_bytes)
    # compressed pubkey = 02/03 || x[32]
    compressed = priv_obj.public_key.format(compressed=True)
    xonly_bytes = compressed[1:]          # strip parity prefix → x coordinate
    pubkey_hex  = xonly_bytes.hex()

    return privkey_bytes, xonly_bytes, pubkey_hex


# ── Step 3: Fetch all events from Nostr relay ────────────────────────────────

async def fetch_all_events_from_relay(
    relay_url: str,
    pubkey_hex: str,
    timeout_sec: int = 15,
) -> list[dict]:
    """
    Connect to a Nostr relay and request ALL kind-30078 backup events for the
    given pubkey. No #d filter — one pubkey may have multiple descriptors backed
    up with distinct d-tags. Returns the latest event per d-tag.
    """
    filter_obj = {
        "kinds": [30078],
        "authors": [pubkey_hex],
        # No "#d" filter — discover all descriptors for this xpub.
    }
    req_msg = json.dumps(["REQ", "dbl1", filter_obj])

    detail(f"Connecting to {relay_url}")
    detail(f"REQ filter: {json.dumps(filter_obj, indent=2)}")

    # key = d-tag string, value = (created_at, event_dict)
    best_per_dtag: dict[str, tuple[int, dict]] = {}

    try:
        async with websockets.connect(relay_url, open_timeout=10) as ws:
            await ws.send(req_msg)
            detail("REQ sent, waiting for events…")

            async def read_loop():
                async for raw in ws:
                    msg = json.loads(raw)
                    if not isinstance(msg, list) or len(msg) < 2:
                        continue
                    if msg[0] == "EOSE":
                        detail("EOSE received — end of stored events")
                        break
                    if msg[0] == "EVENT" and msg[1] == "dbl1" and len(msg) >= 3:
                        ev = msg[2]
                        ts = ev.get("created_at", 0)
                        # Extract d-tag
                        d_tag = next(
                            (t[1] for t in ev.get("tags", []) if t and t[0] == "d"),
                            "",
                        )
                        detail(f"EVENT: id={ev.get('id','?')[:12]}… d={d_tag} ts={ts}")
                        prev_ts, _ = best_per_dtag.get(d_tag, (0, {}))
                        if ts >= prev_ts:
                            best_per_dtag[d_tag] = (ts, ev)

            await asyncio.wait_for(read_loop(), timeout=timeout_sec)

    except asyncio.TimeoutError:
        detail("Timeout while waiting for EOSE")
    except Exception as exc:
        detail(f"Relay error: {exc}")

    return [ev for _, ev in best_per_dtag.values()]


# ── Step 4: Argon2id key derivation ───────────────────────────────────────────

def argon2id_derive(password: str, salt_hex: str, m_cost: int, t_cost: int, p_cost: int) -> bytes:
    """
    Derive a 32-byte key using Argon2id.
    password : xpub string (UTF-8)
    salt_hex : lowercase hex (16 bytes → 32 chars)
    """
    salt = bytes.fromhex(salt_hex)
    return hash_secret_raw(
        secret=password.encode("utf-8"),
        salt=salt,
        time_cost=t_cost,
        memory_cost=m_cost,
        parallelism=p_cost,
        hash_len=32,
        type=Argon2Type.ID,
    )


# ── Step 5: AES-256-GCM decrypt ───────────────────────────────────────────────

def aes_gcm_decrypt(key_bytes: bytes, blob: bytes) -> bytes:
    """
    Decrypt AES-256-GCM ciphertext in Deadbolt's wire format:
        blob = nonce[12] || ciphertext || tag[16]
    """
    if len(blob) < 28:   # 12 nonce + 16 tag minimum
        raise ValueError(f"Blob too short: {len(blob)} bytes")
    nonce = blob[:12]
    ct    = blob[12:]    # includes 16-byte GCM tag at the end
    return AESGCM(key_bytes).decrypt(nonce, ct, None)


# ── Descriptor signature verification ────────────────────────────────────────
#
# Replicates the verification logic from rust/src/core/bip322.rs and
# rust/src/api/wallet/descriptor_sig.rs so that the integrity of the
# ownership proofs stored inside the backup can be checked independently.

_B58_ALPHA = "123456789ABCDEFGHJKLMNPQRSTUVWXYZabcdefghijkmnopqrstuvwxyz"


def _b58decode_check(s: str) -> bytes:
    """Base58check decode. Returns the payload without the 4-byte checksum."""
    n = 0
    for ch in s:
        n = n * 58 + _B58_ALPHA.index(ch)
    leading = len(s) - len(s.lstrip("1"))
    nbytes  = (n.bit_length() + 7) // 8
    raw = b"\x00" * leading + (n.to_bytes(nbytes, "big") if nbytes else b"")
    if len(raw) < 4:
        raise ValueError("base58check: too short")
    payload, chk = raw[:-4], raw[-4:]
    if hashlib.sha256(hashlib.sha256(payload).digest()).digest()[:4] != chk:
        raise ValueError("base58check: bad checksum")
    return payload


def _parse_xpub(xpub_str: str) -> tuple[bytes, bytes]:
    """
    Decode an xpub/tpub string.
    Layout: version(4) depth(1) fingerprint(4) child_number(4) chain_code(32) key(33)
    Returns (chain_code[32], compressed_pubkey[33]).
    """
    payload = _b58decode_check(xpub_str)   # 78 bytes
    return payload[13:45], payload[45:78]


def _bip32_ckd_pub(chain_code: bytes, pubkey: bytes, index: int) -> tuple[bytes, bytes]:
    """Non-hardened BIP32 child public key derivation."""
    data        = pubkey + index.to_bytes(4, "big")
    mac         = hmac.new(chain_code, data, hashlib.sha512).digest()
    il, child_cc = mac[:32], mac[32:]
    il_point    = coincurve.PrivateKey(il).public_key
    child_pub   = coincurve.PublicKey.combine_keys(
        [il_point, coincurve.PublicKey(pubkey)]
    ).format(compressed=True)
    return child_cc, child_pub


def _xpub_derive_pubkey(xpub_str: str, path: list[int]) -> bytes:
    """Derive a compressed pubkey at the given non-hardened path from an xpub string."""
    chain_code, pubkey = _parse_xpub(xpub_str)
    for idx in path:
        chain_code, pubkey = _bip32_ckd_pub(chain_code, pubkey, idx)
    return pubkey


# ── Low-level Bitcoin serialisation helpers ───────────────────────────────────

def _sha256d(data: bytes) -> bytes:
    return hashlib.sha256(hashlib.sha256(data).digest()).digest()


def _ser_u32le(n: int) -> bytes:
    return n.to_bytes(4, "little")


def _ser_u64le(n: int) -> bytes:
    return n.to_bytes(8, "little")


def _ser_varint(n: int) -> bytes:
    if n < 0xFD:
        return bytes([n])
    if n <= 0xFFFF:
        return b"\xfd" + n.to_bytes(2, "little")
    return b"\xfe" + n.to_bytes(4, "little")


def _ser_script(script: bytes) -> bytes:
    return _ser_varint(len(script)) + script


def _make_p2wsh(pubkey: bytes) -> tuple[bytes, bytes]:
    """
    Build scripts for wsh(pk(pubkey)).
    Returns (witness_script, p2wsh_spk).

    witness_script = OP_PUSH33 <pubkey[33]> OP_CHECKSIG (35 bytes)
    p2wsh_spk      = OP_0 OP_PUSH32 <SHA256(witness_script)>  (34 bytes)
    """
    witness_script = bytes([0x21]) + pubkey + bytes([0xAC])        # OP_CHECKSIG = 0xac
    ws_hash        = hashlib.sha256(witness_script).digest()       # SHA256, not SHA256d
    p2wsh_spk      = bytes([0x00, 0x20]) + ws_hash
    return witness_script, p2wsh_spk


def _funding_txid_wire(message: str, p2wsh_spk: bytes) -> bytes:
    """
    Serialize funding_tx and return its txid in wire byte order.

    funding_tx:
      version = 2
      input[0]: prevhash = SHA256(message)[::-1], vout=0, empty script_sig, MAX sequence
      output[0]: 1 sat → p2wsh_spk
      locktime = 0

    Rust uses Txid::from_str(&hex::encode(sha256_bytes)) which stores sha256_bytes
    reversed internally (display ↔ wire byte order flip).  Wire format uses the
    internal (reversed) representation.
    """
    fake_txid_wire = hashlib.sha256(message.encode()).digest()[::-1]   # reversed

    tx = (
        _ser_u32le(2)           +   # version
        _ser_varint(1)          +   # input count
        fake_txid_wire          +   # prevhash (32 bytes, wire order)
        _ser_u32le(0)           +   # vout = 0
        _ser_varint(0)          +   # script_sig = empty
        _ser_u32le(0xFFFFFFFF)  +   # sequence = MAX
        _ser_varint(1)          +   # output count
        _ser_u64le(1)           +   # value = 1 sat
        _ser_script(p2wsh_spk)  +   # scriptPubKey
        _ser_u32le(0)               # locktime
    )
    # txid wire = SHA256d(raw_tx)  (no reversal; display would be SHA256d[::-1])
    return _sha256d(tx)


def _bip143_sighash(
    funding_txid_wire: bytes,
    change_p2wsh_spk: bytes,
    witness_script: bytes,
) -> bytes:
    """
    BIP-143 P2WSH sighash for to_sign_tx (SIGHASH_ALL).

    to_sign_tx:
      version = 2
      input[0]:  (funding_txid_wire, 0), empty script_sig, MAX sequence
      output[0]: 1 sat → change_p2wsh_spk
      locktime = 0
    """
    outpoint      = funding_txid_wire + _ser_u32le(0)
    sequence      = _ser_u32le(0xFFFFFFFF)
    hash_prevouts = _sha256d(outpoint)
    hash_sequence = _sha256d(sequence)
    hash_outputs  = _sha256d(_ser_u64le(1) + _ser_script(change_p2wsh_spk))

    # scriptCode for P2WSH = varint(len) + witness_script
    script_code = _ser_varint(len(witness_script)) + witness_script

    preimage = (
        _ser_u32le(2)   +   # nVersion
        hash_prevouts   +
        hash_sequence   +
        outpoint        +   # the specific outpoint
        script_code     +
        _ser_u64le(1)   +   # value being spent
        sequence        +
        hash_outputs    +
        _ser_u32le(0)   +   # nLocktime
        _ser_u32le(1)       # SIGHASH_ALL
    )
    return _sha256d(preimage)


# ── High-level signature verifiers ───────────────────────────────────────────

def _descriptor_sig_message(descriptor: str) -> str:
    """
    Canonical message for descriptor ownership proofs.
    Matches descriptor_sig_message() in rust/src/core/bip322.rs.
    """
    h = hashlib.sha256(descriptor.encode()).hexdigest()
    return f"deadbolt-descriptor-v1:\n{h}"


def _verify_bip322_sig(xpub_entry: str, message: str, sig_hex: str) -> bool:
    """
    Verify a BB02-BIP322 DER ECDSA signature.

    Reconstructs the deterministic transaction chain (funding_tx → to_sign_tx),
    computes the BIP-143 sighash, and checks the DER signature against xpub/0/0.
    Mirrors verify_bip322_descriptor_sig() in rust/src/core/bip322.rs.
    """
    try:
        m = re.match(r"^\[([^\]]+)\](.+)$", xpub_entry)
        bare_xpub = m.group(2) if m else xpub_entry

        signing_pub             = _xpub_derive_pubkey(bare_xpub, [0, 0])
        change_pub              = _xpub_derive_pubkey(bare_xpub, [1, 0])
        witness_script, p2wsh   = _make_p2wsh(signing_pub)
        _, change_p2wsh         = _make_p2wsh(change_pub)

        funding_txid  = _funding_txid_wire(message, p2wsh)
        sighash       = _bip143_sighash(funding_txid, change_p2wsh, witness_script)

        sig_der = bytes.fromhex(sig_hex)
        return coincurve.PublicKey(signing_pub).verify(sig_der, sighash, hasher=None)
    except Exception:
        return False


def _verify_message_sig(xpub_entry: str, message: str, sig_b64: str) -> bool:
    """
    Verify a Bitcoin message signature (BIP137 compact 65-byte or Krux DER).

    65-byte compact (BIP137):
      hash  = SHA256d("\x18Bitcoin Signed Message:\n" + varint + message)
      key   = xpub/0/0  (recovered via ECDSA recovery)
    DER without recovery byte (Krux):
      hash  = SHA256(message)  (no magic prefix)
      key   = account-level xpub key (no child derivation)

    Mirrors verify_bitcoin_message_sig() in rust/src/core/bip322.rs.
    """
    try:
        m = re.match(r"^\[([^\]]+)\](.+)$", xpub_entry)
        bare_xpub = m.group(2) if m else xpub_entry
        msg_bytes = message.encode()
        raw       = base64.b64decode(sig_b64)

        if len(raw) == 65:
            # BIP137 compact — recover key and compare to xpub/0/0
            varint   = _ser_varint(len(msg_bytes))
            preimage = b"\x18Bitcoin Signed Message:\n" + varint + msg_bytes
            msg_hash = _sha256d(preimage)

            flag   = raw[0]
            rec_id = ((flag - 31) if flag >= 31 else (flag - 27)) & 0x03
            # coincurve recovery format: r(32) || s(32) || rec_id(1)
            rec_sig   = raw[1:65] + bytes([rec_id])
            recovered = coincurve.PublicKey.from_signature_and_message(
                rec_sig, msg_hash, hasher=None
            )
            expected = _xpub_derive_pubkey(bare_xpub, [0, 0])
            return recovered.format(compressed=True) == expected
        else:
            # Krux DER — verify against account-level xpub key, plain SHA256
            _, account_pub = _parse_xpub(bare_xpub)
            msg_hash = hashlib.sha256(msg_bytes).digest()
            return coincurve.PublicKey(account_pub).verify(raw, msg_hash, hasher=None)
    except Exception:
        return False


def _check_descriptor_sigs(descriptor: str, sigs: list) -> list[dict]:
    """
    Verify every descriptor ownership proof in the backup payload.

    Returns a list of dicts: {mfp, xpub_entry, sig_method, valid}.
    """
    if not sigs:
        return []
    message = _descriptor_sig_message(descriptor)
    results = []
    for entry in sigs:
        xpub_entry = entry.get("xpub_entry", "")
        sig_method = entry.get("sig_method", "")
        mfp        = entry.get("mfp", "")
        sig_field  = entry.get("sig_hex", "")

        if sig_method == "bip322":
            valid = _verify_bip322_sig(xpub_entry, message, sig_field)
        elif sig_method == "message":
            valid = _verify_message_sig(xpub_entry, message, sig_field)
        else:
            valid = False

        results.append({"mfp": mfp, "xpub_entry": xpub_entry, "sig_method": sig_method, "valid": valid})
    return results


# ── Main recovery flow ────────────────────────────────────────────────────────

async def recover(credential: str, relay_urls: list[str]) -> str:

    # ── Step 1 ────────────────────────────────────────────────────────────────
    step(1, "Parse xpub credential")
    mfp_hint, xpub = parse_xpub_credential(credential)
    info("Input credential",  credential[:60] + ("…" if len(credential) > 60 else ""))
    info("Parsed xpub",       xpub[:40] + "…")
    info("MFP hint",          mfp_hint or "(none — will try all slots)")
    ok("Credential parsed")

    # ── Step 2 ────────────────────────────────────────────────────────────────
    step(2, "Derive Nostr keypair from xpub")
    print(f"""
  Algorithm:
    privkey = HMAC-SHA256(
        key  = "deadbolt-nostr-backup-v1",
        data = xpub
    )
    pubkey  = secp256k1_xonly(privkey)
""")
    privkey_bytes, xonly_bytes, pubkey_hex = derive_nostr_keypair(xpub)
    info("Nostr private key (hex)", privkey_bytes.hex())
    info("Nostr pubkey (x-only)",   pubkey_hex)
    ok("Keypair derived")

    # ── Step 3 ────────────────────────────────────────────────────────────────
    step(3, "Fetch all backup events from Nostr relays")
    print("""
  Sending REQ filter (no #d — discovers ALL descriptors for this xpub):
    kind   = 30078  (NIP-78 addressable application data)
    author = <derived pubkey>
""")
    events: list[dict] = []
    for url in relay_urls:
        print(f"  Trying relay: {url}")
        events = await fetch_all_events_from_relay(url, pubkey_hex)
        if events:
            info("Events found on relay", url)
            info("Total events",          str(len(events)))
            ok(f"{len(events)} event(s) retrieved")
            break
        else:
            print(f"    → Not found on {url}")

    if not events:
        fail("No backup events found on any relay.\n"
             "Make sure the xpub is correct and the wallet has been backed up.")

    # ── Steps 4–6 per backup (4.N decode, 5.N unwrap key, 6.N decrypt) ──────

    def decrypt_event(ev_index: int, event: dict) -> Optional[tuple[str, dict, str]]:
        """
        Try to decode and decrypt one event.
        Returns (descriptor, payload) on success, None if it can't be decrypted.
        """
        n = ev_index + 1
        step(f"4.{n}", f"Decode backup {n}/{len(events)} → payload JSON")
        print("  The event content is base64(payload_json_bytes).")

        d_tag = next((t[1] for t in event.get("tags", []) if t and t[0] == "d"), "(unknown)")
        info("  Event ID",    event.get("id", "?")[:32] + "…")
        info("  d-tag",       d_tag)
        info("  created_at",  str(event.get("created_at")))

        if not event.get("content"):
            print("  → Skipped (deletion event — content is empty)")
            return None

        try:
            payload: dict = json.loads(base64.b64decode(event["content"]))
        except Exception as exc:
            print(f"  → Skipped (malformed content): {exc}")
            return None

        info("  Wallet name",  str(payload.get("wallet_name")))
        info("  Network",      str(payload.get("network")))
        info("  Slots",        str(len(payload.get("protection", {}).get("slots", []))))

        if payload.get("version") != 1:
            print(f"  → Skipped (unsupported version {payload.get('version')})")
            return None
        if payload.get("protection", {}).get("type") != 2:
            print(f"  → Skipped (unexpected protection type)")
            return None

        slots: list[dict] = payload["protection"]["slots"]

        step(f"5.{n}", f"Unwrap export data key — backup {n}/{len(events)}")
        print(f"""
  Argon2id(password=xpub, salt=slot.salt, m_cost={slots[0].get('m_cost',65536)},
           t_cost={slots[0].get('t_cost',3)}, p_cost={slots[0].get('p_cost',1)})
  then AES-256-GCM(wrapping_key).decrypt(slot.wrapped_key)
""")
        export_data_key: Optional[bytes] = None
        matched_mfp: Optional[str] = None

        for i, slot in enumerate(slots):
            slot_mfp = slot.get("mfp", "")
            if mfp_hint and slot_mfp.lower() != mfp_hint.lower():
                detail(f"Slot {i} skipped (MFP hint mismatch)")
                continue

            print(f"  Trying slot {i}: mfp={slot_mfp or '(empty)'}")
            print("  Running Argon2id KDF…")
            try:
                wrapping_key_bytes = argon2id_derive(
                    password=xpub,
                    salt_hex=slot["salt"],
                    m_cost=slot.get("m_cost", 65536),
                    t_cost=slot.get("t_cost", 3),
                    p_cost=slot.get("p_cost", 1),
                )
            except Exception as exc:
                detail(f"Argon2id error: {exc}")
                continue

            try:
                combined_bytes  = bytes.fromhex(slot["wrapped_key"])
                export_data_key = aes_gcm_decrypt(wrapping_key_bytes, combined_bytes)
                matched_mfp     = slot_mfp
                ok(f"Slot {i} decrypted (mfp={slot_mfp or 'none'})")
                break
            except Exception:
                detail(f"Slot {i} does not match this xpub")

        if export_data_key is None:
            print("  → Skipped (xpub does not match any slot in this backup)")
            return None

        step(f"6.{n}", f"Decrypt descriptor — backup {n}/{len(events)}")
        try:
            encrypted_inner = base64.b64decode(payload["data"])
            inner_bytes     = aes_gcm_decrypt(export_data_key, encrypted_inner)
            inner: dict     = json.loads(inner_bytes)
            descriptor: str = inner.get("descriptor", "")
            raw_sigs: list  = inner.get("descriptor_sigs", [])
        except Exception as exc:
            print(f"  → Decryption failed: {exc}")
            return None

        if not descriptor:
            print("  → Skipped (no descriptor in decrypted payload)")
            return None

        ok("Descriptor decrypted successfully")
        if matched_mfp:
            info("  Key MFP", matched_mfp)
        if raw_sigs:
            info("  Ownership proofs found", str(len(raw_sigs)))

        return descriptor, payload, raw_sigs

    # Sort events most-recent-first before processing
    events.sort(key=lambda e: e.get("created_at", 0), reverse=True)

    results: list[tuple[str, dict, list]] = []
    for idx, ev in enumerate(events):
        r = decrypt_event(idx, ev)
        if r:
            results.append(r)

    if not results:
        fail("No backup could be decrypted with the provided xpub.")

    # ── Results ───────────────────────────────────────────────────────────────
    print(f"\n{BOLD}{'=' * 60}{RESET}")
    plural = "S" if len(results) > 1 else ""
    print(f"{BOLD}{f'  RECOVERED DESCRIPTOR{plural} ({len(results)} found)':^60}{RESET}")
    print(f"{BOLD}{'=' * 60}{RESET}")

    first_descriptor = results[0][0]
    for i, (descriptor, payload, raw_sigs) in enumerate(results):
        if len(results) > 1:
            print(f"\n  {BOLD}── Wallet {i + 1} of {len(results)} ──{RESET}")
        print()
        print(f"  Wallet name : {payload.get('wallet_name', '(unknown)')}")
        print(f"  Network     : {payload.get('network', '(unknown)')}")
        print()
        print(f"  Descriptor:")
        print(f"    {descriptor}")

        # ── Descriptor ownership signature verification ──────────────────────
        print()
        if raw_sigs:
            print(f"  {BOLD}Descriptor Ownership Signatures:{RESET}")
            sig_results = _check_descriptor_sigs(descriptor, raw_sigs)
            for r in sig_results:
                status = f"{GREEN}✓ VALID{RESET}" if r["valid"] else f"{RED}✗ INVALID{RESET}"
                print(f"    {status}  [{r['mfp']}]  method={r['sig_method']}")
            n_valid   = sum(1 for r in sig_results if r["valid"])
            n_total   = len(sig_results)
            if n_valid == n_total:
                ok(f"All {n_total} ownership signature(s) verified")
            else:
                print(f"  {YELLOW}⚠ {n_valid}/{n_total} ownership signature(s) valid{RESET}")
        else:
            print(f"  {DIM}No ownership signatures in this backup{RESET}")

    print()
    print(f"{BOLD}{'=' * 60}{RESET}")

    return first_descriptor


# ── CLI ───────────────────────────────────────────────────────────────────────

def main():
    global verbose

    parser = argparse.ArgumentParser(
        description="Fetch and decrypt a Deadbolt Nostr descriptor backup.",
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog="""
Examples:
  # Bare xpub, single relay
  python fetch_nostr_backup.py \\
      --xpub xpub6C5sJJ3iZxbkUDa4z... \\
      --relay wss://relay.damus.io

  # Keyspec with MFP hint, multiple relays
  python fetch_nostr_backup.py \\
      --xpub "[deadbeef/84h/0h/0h]xpub6C5sJJ3..." \\
      --relay wss://nos.lol \\
      --relay wss://relay.damus.io \\
      --relay wss://nostr.mom \\
      --verbose
""",
    )
    parser.add_argument(
        "--xpub",
        metavar="XPUB_OR_KEYSPEC",
        help="Bare xpub or keyspec [mfp/path]xpub (prompted if omitted)",
    )
    parser.add_argument(
        "--relay", action="append", dest="relays", default=[],
        metavar="WSS_URL",
        help="Nostr relay WebSocket URL (can be specified multiple times; prompted if omitted)",
    )
    parser.add_argument(
        "--verbose", "-v", action="store_true",
        help="Print detailed intermediate values",
    )
    args = parser.parse_args()

    verbose = args.verbose

    print(f"""
{BOLD}Deadbolt Nostr Backup Recovery{RESET}
{DIM}Protocol: HMAC-SHA256 key derivation + Argon2id + AES-256-GCM{RESET}
{DIM}Reference: docs/NOSTR_BACKUP.md{RESET}
""")

    # ── Interactive prompts for missing arguments ──────────────────────────────

    xpub = args.xpub
    if not xpub:
        print("Enter your xpub or keyspec ([mfp/path]xpub).")
        print(f"{DIM}Example: [deadbeef/84h/0h/0h]xpub6C5sJJ...{RESET}")
        xpub = input("xpub > ").strip()
        if not xpub:
            fail("No xpub provided.")

    relays = args.relays
    if not relays:
        default_relays = [
            "wss://nos.lol",
            "wss://relay.damus.io",
            "wss://nostr.mom",
        ]
        print()
        print("Enter relay URLs one per line (blank line to finish).")
        print(f"{DIM}Press Enter immediately to use defaults: {', '.join(default_relays)}{RESET}")
        while True:
            url = input("relay > ").strip()
            if not url:
                break
            relays.append(url)
        if not relays:
            relays = default_relays
            print(f"Using default relays: {', '.join(relays)}")

    asyncio.run(recover(xpub, relays))


if __name__ == "__main__":
    main()
