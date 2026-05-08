#!/usr/bin/env python3
"""
Deadbolt On-Chain Backup Recovery Tool
========================================
Fetches and decrypts a wallet descriptor backup published on the Bitcoin
blockchain by Deadbolt (commit-reveal pattern with Taproot inscriptions).

This script replicates the protocol described in docs/ONCHAIN_BACKUP.md and
shows every intermediate step so you can independently verify the process.

Usage:
    python3 fetch_onchain_backup.py --xpub <xpub_or_keyspec> \\
        --electrum <host:port[:s]> \\
        [--electrum <host:port[:s]>] \\
        [--network bitcoin|signet|testnet|regtest] \\
        [--verbose]

    xpub_or_keyspec:
        Bare xpub:   xpub6C5sJJ3iZxbk...
        Keyspec:     [deadbeef/84h/0h/0h]xpub6C5sJJ3iZxbk...

    Electrum endpoint format:
        host:port      → plain TCP
        host:port:s    → TLS (recommended for public servers)
        host:port:t    → plain TCP (explicit)

Requirements:
    pip install coincurve argon2-cffi cryptography zstandard embit

Protocol reference: docs/ONCHAIN_BACKUP.md
"""

from __future__ import annotations

import argparse
import base64
import hashlib
import hmac
import json
import re
import socket
import ssl
import sys
from dataclasses import dataclass
from typing import Optional

# ── Dependency check ──────────────────────────────────────────────────────────


def _require(package: str, import_name: str, install_hint: str):
    try:
        return __import__(import_name)
    except ImportError:
        print(f"\n[ERROR] Missing dependency: {package}")
        print(f"        Install with: pip install {install_hint}")
        sys.exit(1)


_require("coincurve", "coincurve", "coincurve")
_require("argon2-cffi", "argon2", "argon2-cffi")
_require("cryptography", "cryptography", "cryptography")
_require("zstandard", "zstandard", "zstandard")
_require("embit", "embit", "embit")

import coincurve  # noqa: E402
import io  # noqa: E402
import zstandard as zstd  # noqa: E402


def _zstd_decompress(data: bytes) -> bytes:
    """Streaming zstd decompress — Deadbolt frames don't embed content size."""
    dctx = zstd.ZstdDecompressor()
    with dctx.stream_reader(io.BytesIO(data)) as reader:
        return reader.read()
from argon2.low_level import hash_secret_raw, Type as Argon2Type  # noqa: E402
from cryptography.hazmat.primitives.ciphers.aead import AESGCM  # noqa: E402
from embit import bip32  # noqa: E402
from embit.transaction import Transaction  # noqa: E402

# ── Protocol constants ────────────────────────────────────────────────────────

ANCHOR_DOMAIN_TAG = b"deadbolt-anchor-v1"
NUMS_XONLY_HEX = "50929b74c1a04954b78b4b6035e97a5e078a5a0f28ec96d547bfee9ace803ac0"
ANCHOR_SATS = 330
PAYLOAD_VERSION = 3

# ── ANSI helpers ──────────────────────────────────────────────────────────────

BOLD = "\033[1m"
DIM = "\033[2m"
GREEN = "\033[32m"
YELLOW = "\033[33m"
RED = "\033[31m"
CYAN = "\033[36m"
RESET = "\033[0m"

verbose = False


def step(n, title: str):
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


def warn(msg: str):
    print(f"  {YELLOW}⚠ {msg}{RESET}")


def fail(msg: str):
    print(f"\n[FAIL] {msg}")
    sys.exit(1)


# ── Step 1: Parse xpub credential ─────────────────────────────────────────────


def parse_xpub_credential(credential: str) -> tuple[Optional[str], str]:
    """Parse a bare xpub or a keyspec `[mfp/path]xpub`."""
    credential = credential.strip()
    m = re.match(r"^\[([0-9a-fA-F]{8})([^\]]*)\](.+)$", credential)
    if m:
        return m.group(1).lower(), m.group(3).strip()
    return None, credential


# ── Step 2: Anchor key + address derivation ───────────────────────────────────


SECP256K1_N = 0xFFFFFFFF_FFFFFFFF_FFFFFFFF_FFFFFFFE_BAAEDCE6_AF48A03B_BFD25E8C_D0364141


def derive_anchor_privkey(xpub: str) -> bytes:
    """
    Deterministic anchor private key for an xpub.

        for counter in 0..=255:
            candidate = HMAC-SHA256(key=ANCHOR_DOMAIN_TAG,
                                    data=[counter] || xpub_utf8)
            if 1 <= int(candidate) < N:
                return candidate
    """
    xpub_bytes = xpub.encode("utf-8")
    for counter in range(256):
        h = hmac.new(
            ANCHOR_DOMAIN_TAG,
            bytes([counter]) + xpub_bytes,
            hashlib.sha256,
        ).digest()
        n = int.from_bytes(h, "big")
        if 1 <= n < SECP256K1_N:
            detail(f"counter={counter} privkey={h.hex()}")
            return h
    raise RuntimeError("All 256 HMAC outputs invalid (cosmic-ray-tier event)")


def xonly_pubkey(privkey: bytes) -> bytes:
    """Return the x-only (32-byte) public key from a 32-byte private key."""
    pk_compressed = coincurve.PrivateKey(privkey).public_key.format(compressed=True)
    return pk_compressed[1:]


def taproot_tweak_xonly(xonly: bytes, merkle_root: Optional[bytes]) -> bytes:
    """
    BIP-341 taproot tweak: P + int(t)·G where
        t = tagged_hash("TapTweak", xonly || (merkle_root or b""))
    """
    tagged = hashlib.sha256(b"TapTweak").digest()
    t = hashlib.sha256(
        tagged + tagged + xonly + (merkle_root if merkle_root else b"")
    ).digest()

    # P from x-only — try even-Y; flip to odd-Y if needed when adding back.
    full = b"\x02" + xonly
    P = coincurve.PublicKey(full)
    G_priv = coincurve.PrivateKey(t).public_key  # t·G
    Q = coincurve.PublicKey.combine_keys([P, G_priv])
    Q_compressed = Q.format(compressed=True)
    return Q_compressed[1:]  # x-only


def p2tr_script_pubkey(tweaked_xonly: bytes) -> bytes:
    """`OP_1 0x20 <32-byte x-only>`"""
    return bytes([0x51, 0x20]) + tweaked_xonly


def anchor_script_pubkey(xpub: str) -> bytes:
    """Compute the key-path-only P2TR scriptPubKey for an xpub's anchor."""
    sk = derive_anchor_privkey(xpub)
    xonly = xonly_pubkey(sk)
    tweaked = taproot_tweak_xonly(xonly, None)
    return p2tr_script_pubkey(tweaked)


# ── Step 3: Minimal Electrum client ───────────────────────────────────────────


@dataclass
class ElectrumEndpoint:
    host: str
    port: int
    tls: bool

    @classmethod
    def parse(cls, s: str) -> "ElectrumEndpoint":
        parts = s.strip().split(":")
        if len(parts) == 2:
            return cls(parts[0], int(parts[1]), tls=False)
        if len(parts) == 3:
            return cls(parts[0], int(parts[1]), tls=parts[2].lower() == "s")
        raise ValueError(f"Invalid Electrum endpoint: {s}")

    def __str__(self) -> str:
        return f"{self.host}:{self.port}{':s' if self.tls else ':t'}"


class ElectrumClient:
    """
    Minimal Electrum protocol client (JSON-RPC framed by '\\n').

    Implements only what the recovery flow needs:
      - blockchain.scripthash.get_history
      - blockchain.transaction.get
      - blockchain.block.header
    """

    def __init__(self, endpoint: ElectrumEndpoint, timeout: float = 20.0):
        sock = socket.create_connection((endpoint.host, endpoint.port), timeout=timeout)
        if endpoint.tls:
            ctx = ssl.create_default_context()
            ctx.check_hostname = False
            ctx.verify_mode = ssl.CERT_NONE
            sock = ctx.wrap_socket(sock, server_hostname=endpoint.host)
        sock.settimeout(timeout)
        self._sock = sock
        self._buf = b""
        self._id = 0
        self._endpoint = endpoint
        # Negotiate protocol version explicitly (some servers refuse otherwise).
        try:
            self._call("server.version", ["deadbolt-onchain-recovery", "1.4"])
        except Exception as exc:
            detail(f"server.version handshake skipped: {exc}")

    def _next_id(self) -> int:
        self._id += 1
        return self._id

    def _call(self, method: str, params: list):
        rid = self._next_id()
        msg = json.dumps({"jsonrpc": "2.0", "id": rid, "method": method, "params": params}) + "\n"
        self._sock.sendall(msg.encode("utf-8"))
        while b"\n" not in self._buf:
            chunk = self._sock.recv(65536)
            if not chunk:
                raise ConnectionError(f"Electrum server {self._endpoint} closed connection")
            self._buf += chunk
        line, self._buf = self._buf.split(b"\n", 1)
        resp = json.loads(line.decode("utf-8"))
        if "error" in resp and resp["error"] is not None:
            raise RuntimeError(f"Electrum error from {self._endpoint}: {resp['error']}")
        return resp.get("result")

    @staticmethod
    def script_hash(script_pubkey: bytes) -> str:
        """Electrum scripthash: reverse(sha256(spk)).hex()"""
        return hashlib.sha256(script_pubkey).digest()[::-1].hex()

    def get_history(self, script_pubkey: bytes) -> list[dict]:
        return self._call("blockchain.scripthash.get_history", [self.script_hash(script_pubkey)]) or []

    def get_transaction(self, txid: str) -> bytes:
        raw_hex = self._call("blockchain.transaction.get", [txid, False])
        return bytes.fromhex(raw_hex)

    def get_block_header(self, height: int) -> bytes:
        raw_hex = self._call("blockchain.block.header", [height])
        return bytes.fromhex(raw_hex)

    def close(self):
        try:
            self._sock.close()
        except Exception:
            pass


# ── Step 4: Inscription envelope parser ───────────────────────────────────────


def parse_inscription_envelope(tapscript: bytes) -> bytes:
    """
    Parse `OP_1 OP_FALSE OP_IF <pushes…> OP_ENDIF` and return the concatenated
    payload bytes.
    """
    pos = 0

    def expect(byte: int, name: str):
        nonlocal pos
        if pos >= len(tapscript) or tapscript[pos] != byte:
            actual = tapscript[pos] if pos < len(tapscript) else None
            raise ValueError(f"Expected {name} (0x{byte:02x}) at {pos}, got {actual}")
        pos += 1

    expect(0x51, "OP_1")
    expect(0x00, "OP_FALSE")
    expect(0x63, "OP_IF")

    out = bytearray()
    while True:
        if pos >= len(tapscript):
            raise ValueError(f"Unexpected end of tapscript at {pos}")
        op = tapscript[pos]
        if op == 0x68:  # OP_ENDIF
            break
        if 1 <= op <= 75:
            length = op
            pos += 1
            out += tapscript[pos : pos + length]
            pos += length
        elif op == 0x4C:
            pos += 1
            length = tapscript[pos]
            pos += 1
            out += tapscript[pos : pos + length]
            pos += length
        elif op == 0x4D:
            pos += 1
            length = int.from_bytes(tapscript[pos : pos + 2], "little")
            pos += 2
            out += tapscript[pos : pos + length]
            pos += length
        else:
            raise ValueError(f"Unexpected opcode 0x{op:02x} at offset {pos}")

    return bytes(out)


# ── Step 5: Argon2id + AES-GCM ────────────────────────────────────────────────


def argon2id_derive(password: str, salt_hex: str, m_cost: int, t_cost: int, p_cost: int) -> bytes:
    return hash_secret_raw(
        secret=password.encode("utf-8"),
        salt=bytes.fromhex(salt_hex),
        time_cost=t_cost,
        memory_cost=m_cost,
        parallelism=p_cost,
        hash_len=32,
        type=Argon2Type.ID,
    )


def aes_gcm_decrypt(key: bytes, blob: bytes) -> bytes:
    """blob = nonce[12] || ciphertext || tag[16]"""
    if len(blob) < 12 + 16:
        raise ValueError("Encrypted blob too short")
    return AESGCM(key).decrypt(blob[:12], blob[12:], None)


def decrypt_outer_payload(payload: dict, xpub_credential: str) -> tuple[str, dict, str]:
    """
    Decrypt the outer payload using any matching slot.
    Returns (descriptor, inner_dict, matched_mfp_or_empty).
    """
    mfp_hint, bare_xpub = parse_xpub_credential(xpub_credential)

    if payload.get("version") != PAYLOAD_VERSION:
        raise ValueError(f"Unsupported payload version {payload.get('version')} (expected {PAYLOAD_VERSION})")

    slots = payload.get("slots") or []
    if not slots:
        raise ValueError("Payload contains no slots")

    export_key: Optional[bytes] = None
    matched_mfp = ""
    for i, slot in enumerate(slots):
        slot_mfp = (slot.get("mfp") or "").lower()
        if mfp_hint and slot_mfp and slot_mfp != mfp_hint:
            detail(f"Slot {i}: skipped (mfp {slot_mfp} ≠ hint {mfp_hint})")
            continue
        try:
            wrapping_key = argon2id_derive(
                bare_xpub,
                slot["salt"],
                slot.get("m_cost", 65536),
                slot.get("t_cost", 3),
                slot.get("p_cost", 1),
            )
            export_key = aes_gcm_decrypt(wrapping_key, bytes.fromhex(slot["wrapped_key"]))
            matched_mfp = slot_mfp
            detail(f"Slot {i}: unwrapped (mfp={slot_mfp or 'none'})")
            break
        except Exception as exc:
            detail(f"Slot {i}: unwrap failed ({exc})")

    if export_key is None:
        raise ValueError("No slot could be unwrapped with the provided xpub")

    encrypted_inner = base64.b64decode(payload["data"])
    compressed = aes_gcm_decrypt(export_key, encrypted_inner)
    inner_bytes = _zstd_decompress(compressed)
    try:
        inner = json.loads(inner_bytes)
    except json.JSONDecodeError as exc:
        raise ValueError(
            f"inner payload is not valid JSON ({exc.msg}) — "
            "this backup may have been published by an older Deadbolt version"
        ) from exc
    if not isinstance(inner, dict):
        raise ValueError("Inner payload is not a JSON object")
    descriptor = inner.get("descriptor", "")
    if not descriptor:
        raise ValueError("Inner JSON contains no descriptor field")
    return descriptor, inner, matched_mfp


# ── Step 6: Reveal-tx witness extraction ──────────────────────────────────────


def extract_payload_from_reveal(reveal_tx: Transaction) -> bytes:
    """
    Locate the script-path-spend input in TX_REVEAL and return the outer
    zstd-decompressed payload bytes.
    """
    last_error = "no script-path spend found in any input"
    for idx, tx_in in enumerate(reveal_tx.vin):
        wit = tx_in.witness.items
        if len(wit) < 2:
            continue
        control_block = wit[-1]
        if not control_block or (control_block[0] & 0xFE) != 0xC0:
            continue
        tapscript = wit[-2]
        try:
            compressed = parse_inscription_envelope(tapscript)
            return _zstd_decompress(compressed)
        except Exception as exc:
            last_error = f"input {idx}: {exc}"
    raise ValueError(last_error)


# ── Step 7: Recovery orchestrator ─────────────────────────────────────────────


def find_reveal(client: ElectrumClient, commit_tx: Transaction, commit_txid: str,
                anchor_spk: bytes) -> tuple[Optional[str], Optional[Transaction], Optional[int]]:
    """
    For each output of TX_COMMIT that is not the queryer's anchor, ask Electrum
    for that output's history and look for a tx that spends (commit_txid, vout).
    Returns (reveal_txid_hex, reveal_tx, reveal_height) or (None, None, None).
    """
    # embit stores prev-txid in display (big-endian) order, matching the hex string.
    commit_txid_bytes = bytes.fromhex(commit_txid)
    for vout, txout in enumerate(commit_tx.vout):
        spk = bytes(txout.script_pubkey.data)
        if spk == anchor_spk:
            continue
        try:
            history = client.get_history(spk)
        except Exception as exc:
            detail(f"  history({vout}): {exc}")
            continue
        for item in history:
            cand_txid = item["tx_hash"]
            if cand_txid == commit_txid:
                continue
            try:
                raw = client.get_transaction(cand_txid)
                tx = Transaction.parse(raw)
            except Exception as exc:
                detail(f"  tx fetch {cand_txid[:12]}…: {exc}")
                continue
            for vin in tx.vin:
                if vin.txid == commit_txid_bytes and vin.vout == vout:
                    return cand_txid, tx, item.get("height", 0)
    return None, None, None


def recover(xpub_credential: str, endpoints: list[ElectrumEndpoint], _network: str):
    mfp_hint, bare_xpub = parse_xpub_credential(xpub_credential)

    step(1, "Parse xpub credential")
    info("MFP hint", mfp_hint or "(none)")
    info("xpub", bare_xpub)

    step(2, "Derive anchor address")
    spk = anchor_script_pubkey(bare_xpub)
    info("Anchor scriptPubKey", spk.hex())
    info("Electrum scripthash", ElectrumClient.script_hash(spk))

    step(3, "Connect to Electrum and look up anchor history")
    last_error: Optional[Exception] = None
    history: list[dict] = []
    client: Optional[ElectrumClient] = None
    for ep in endpoints:
        try:
            info("Connecting", str(ep))
            client = ElectrumClient(ep)
            history = client.get_history(spk)
            ok(f"Connected — {len(history)} tx(s) in anchor history")
            break
        except Exception as exc:
            last_error = exc
            warn(f"{ep}: {exc}")
            client = None
    if client is None:
        fail(f"All Electrum endpoints failed (last error: {last_error})")
    if not history:
        fail("Anchor history is empty — no backup published from this xpub")

    step(4, "Identify TX_COMMIT candidates")
    commits: list[tuple[str, Transaction, int]] = []
    for item in history:
        txid = item["tx_hash"]
        try:
            raw = client.get_transaction(txid)
            tx = Transaction.parse(raw)
        except Exception as exc:
            warn(f"{txid[:12]}…: tx fetch failed: {exc}")
            continue
        if any(bytes(o.script_pubkey.data) == spk for o in tx.vout):
            detail(f"  candidate commit {txid}")
            commits.append((txid, tx, item.get("height", 0)))

    if not commits:
        fail("No transaction in the anchor history pays the anchor address — corrupt server response?")

    ok(f"{len(commits)} TX_COMMIT candidate(s)")

    step(5, "Decrypt each backup")
    results = []
    for n, (commit_txid, commit_tx, _commit_height) in enumerate(commits, start=1):
        print()
        print(f"  {BOLD}── Backup {n} of {len(commits)} ──{RESET}")
        info("commit_txid", commit_txid)

        reveal_txid, reveal_tx, reveal_height = find_reveal(client, commit_tx, commit_txid, spk)
        if reveal_tx is None:
            warn("TX_REVEAL not found yet (commit may be unconfirmed/pending)")
            continue
        info("reveal_txid", reveal_txid)
        if reveal_height and reveal_height > 0:
            info("reveal height", str(reveal_height))

        try:
            outer_json_bytes = extract_payload_from_reveal(reveal_tx)
        except Exception as exc:
            warn(f"Failed to extract envelope: {exc}")
            continue

        try:
            payload = json.loads(outer_json_bytes)
        except Exception as exc:
            warn(f"Outer payload is not valid JSON: {exc}")
            continue

        info("payload version", str(payload.get("version")))
        info("payload slots", str(len(payload.get("slots") or [])))

        try:
            descriptor, inner, matched_mfp = decrypt_outer_payload(payload, xpub_credential)
        except Exception as exc:
            warn(f"Decryption failed: {exc}")
            continue

        ok("Descriptor decrypted")
        if matched_mfp:
            info("Slot MFP matched", matched_mfp)
        results.append({
            "commit_txid": commit_txid,
            "reveal_txid": reveal_txid,
            "descriptor": descriptor,
            "wallet_name": inner.get("wallet_name", ""),
        })

    client.close()

    if not results:
        fail("No backup could be decrypted with the provided xpub")

    step(6, "Recovered descriptor(s)")
    print(f"\n{BOLD}{'=' * 60}{RESET}")
    plural = "S" if len(results) > 1 else ""
    print(f"{BOLD}{f'  RECOVERED DESCRIPTOR{plural} ({len(results)} found)':^60}{RESET}")
    print(f"{BOLD}{'=' * 60}{RESET}")
    for i, r in enumerate(results, 1):
        if len(results) > 1:
            print(f"\n  {BOLD}── Wallet {i} of {len(results)} ──{RESET}")
        print()
        print(f"  Wallet name : {r['wallet_name'] or '(unknown)'}")
        print(f"  Commit txid : {r['commit_txid']}")
        print(f"  Reveal txid : {r['reveal_txid']}")
        print()
        print("  Descriptor:")
        print(f"    {r['descriptor']}")
    print()
    print(f"{BOLD}{'=' * 60}{RESET}")


# ── CLI ───────────────────────────────────────────────────────────────────────


def main():
    global verbose

    parser = argparse.ArgumentParser(
        description="Fetch and decrypt a Deadbolt on-chain descriptor backup.",
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog="""
Examples:
  # Mainnet, single TLS Electrum
  python3 fetch_onchain_backup.py \\
      --xpub xpub6C5sJJ3iZxbk... \\
      --electrum electrum.blockstream.info:50002:s

  # Signet, with MFP hint and multiple endpoints
  python3 fetch_onchain_backup.py \\
      --xpub "[deadbeef/84h/1h/0h]tpub6C5sJJ..." \\
      --network signet \\
      --electrum mempool.space:60602:s \\
      --electrum electrum.blockstream.info:60002:s \\
      --verbose
""",
    )
    parser.add_argument("--xpub", metavar="XPUB_OR_KEYSPEC",
                        help="Bare xpub or keyspec [mfp/path]xpub (prompted if omitted)")
    parser.add_argument("--electrum", action="append", dest="electrum", default=[],
                        metavar="HOST:PORT[:s|:t]",
                        help="Electrum endpoint (repeatable; prompted if omitted)")
    parser.add_argument("--network", choices=["bitcoin", "signet", "testnet", "regtest"],
                        default="bitcoin",
                        help="Bitcoin network (informational; protocol does not depend on it)")
    parser.add_argument("--verbose", "-v", action="store_true",
                        help="Print intermediate values")
    args = parser.parse_args()

    verbose = args.verbose

    print(f"""
{BOLD}Deadbolt On-Chain Backup Recovery{RESET}
{DIM}Protocol: HMAC-SHA256 anchor + Taproot inscription + Argon2id + AES-256-GCM{RESET}
{DIM}Reference: docs/ONCHAIN_BACKUP.md{RESET}
""")

    xpub = args.xpub
    if not xpub:
        print("Enter your xpub or keyspec ([mfp/path]xpub).")
        print(f"{DIM}Example: [deadbeef/84h/0h/0h]xpub6C5sJJ...{RESET}")
        xpub = input("xpub > ").strip()
        if not xpub:
            fail("No xpub provided.")

    raw_endpoints = args.electrum
    if not raw_endpoints:
        defaults = {
            "bitcoin": ["electrum.blockstream.info:50002:s"],
            "signet": ["mempool.space:60602:s"],
            "testnet": ["electrum.blockstream.info:60002:s"],
            "regtest": ["127.0.0.1:60401:t"],
        }[args.network]
        print()
        print("Enter Electrum endpoints (host:port[:s|:t]), one per line. Blank to finish.")
        print(f"{DIM}Press Enter to use defaults: {', '.join(defaults)}{RESET}")
        while True:
            line = input("electrum > ").strip()
            if not line:
                break
            raw_endpoints.append(line)
        if not raw_endpoints:
            raw_endpoints = defaults
            print(f"Using default endpoints: {', '.join(raw_endpoints)}")

    try:
        endpoints = [ElectrumEndpoint.parse(s) for s in raw_endpoints]
    except ValueError as exc:
        fail(str(exc))

    # Validate xpub format up-front using embit (also rejects keyspec edge cases).
    _, bare = parse_xpub_credential(xpub)
    try:
        bip32.HDKey.from_string(bare)
    except Exception as exc:
        fail(f"Invalid xpub: {exc}")

    recover(xpub, endpoints, args.network)


if __name__ == "__main__":
    main()
