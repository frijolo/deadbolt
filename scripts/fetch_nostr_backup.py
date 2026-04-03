#!/usr/bin/env python3
"""
Deadbolt Nostr Backup Recovery Tool
=====================================
Fetches and decrypts a wallet descriptor backup stored on Nostr relays.

This script replicates the exact cryptographic protocol used by the Deadbolt
app, showing every intermediate step and value so you can verify the process.

Usage:
    python fetch_nostr_backup.py --xpub <xpub_or_keyspec> \\
        --relay wss://relay.damus.io \\
        [--relay wss://relay.primal.net] \\
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

# ── Helpers ───────────────────────────────────────────────────────────────────

BOLD  = "\033[1m"
DIM   = "\033[2m"
GREEN = "\033[32m"
CYAN  = "\033[36m"
RESET = "\033[0m"

verbose = False


def step(n: int, title: str):
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


# ── Step 1: Parse xpub credential ─────────────────────────────────────────────

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

    # ── Steps 4-6 repeated for each event ────────────────────────────────────

    def decrypt_event(ev_index: int, event: dict) -> Optional[tuple[str, dict]]:
        """
        Try to decode and decrypt one event.
        Returns (descriptor, payload) on success, None if it can't be decrypted.
        """
        step(4 if ev_index == 0 else 4 + ev_index * 3,
             f"Decode event {ev_index + 1}/{len(events)} → payload JSON")
        print("  The event content is base64(payload_json_bytes).")

        d_tag = next((t[1] for t in event.get("tags", []) if t and t[0] == "d"), "(unknown)")
        info("  Event ID",    event.get("id", "?")[:32] + "…")
        info("  d-tag",       d_tag)
        info("  created_at",  str(event.get("created_at")))

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

        sub = ev_index * 3
        step(5 + sub, f"Unwrap export data key — event {ev_index + 1}")
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

        step(6 + sub, f"Decrypt descriptor — event {ev_index + 1}")
        try:
            encrypted_inner = base64.b64decode(payload["data"])
            inner_bytes     = aes_gcm_decrypt(export_data_key, encrypted_inner)
            inner: dict     = json.loads(inner_bytes)
            descriptor: str = inner.get("descriptor", "")
        except Exception as exc:
            print(f"  → Decryption failed: {exc}")
            return None

        if not descriptor:
            print("  → Skipped (no descriptor in decrypted payload)")
            return None

        ok("Descriptor decrypted successfully")
        if matched_mfp:
            info("  Key MFP", matched_mfp)

        return descriptor, payload

    # Sort events most-recent-first before processing
    events.sort(key=lambda e: e.get("created_at", 0), reverse=True)

    results: list[tuple[str, dict]] = []
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
    for i, (descriptor, payload) in enumerate(results):
        if len(results) > 1:
            print(f"\n  {BOLD}── Wallet {i + 1} of {len(results)} ──{RESET}")
        print()
        print(f"  Wallet name : {payload.get('wallet_name', '(unknown)')}")
        print(f"  Network     : {payload.get('network', '(unknown)')}")
        print()
        print(f"  Descriptor:")
        print(f"    {descriptor}")

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
      --relay wss://relay.damus.io \\
      --relay wss://relay.primal.net \\
      --relay wss://nos.lol \\
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
            "wss://relay.damus.io",
            "wss://relay.primal.net",
            "wss://nos.lol",
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
