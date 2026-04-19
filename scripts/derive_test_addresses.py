#!/usr/bin/env python3
"""
Derive reference addresses from the reg04 descriptor tpub.

Usage:
    python3 scripts/derive_test_addresses.py

Output: address constants to hardcode in regression_04_wallet_device_key.py.
Descriptor: wpkh([ff81be5d/84h/1h/0h]tpub.../<0;1>/*)
"""

from embit import bip32, script
from embit.networks import NETWORKS

TPUB = (
    "tpubDDjVt7cey7cxQ1nXzxpXuNT5vJecpvtMhmZywA9U9ChWDk8z6HSGPJ7YS6pyd8ZX"
    "QyfCeUCXrkyEqNeTFUmpdXT9r3TD1DAYoY52UEyy1Yf"
)

NET = NETWORKS["test"]


def addr(keychain: int, index: int) -> str:
    key = bip32.HDKey.from_string(TPUB)
    child = key.derive([keychain, index])
    return script.p2wpkh(child).address(network=NET)


if __name__ == "__main__":
    receive_0  = addr(0,  0)
    receive_19 = addr(0, 19)
    receive_20 = addr(0, 20)
    receive_30 = addr(0, 30)
    change_0   = addr(1,  0)

    print("# Paste these into regression_04_wallet_device_key.py (Test data section)")
    print(f'ADDR_0_RECEIVE  = "{receive_0}"')
    print(f'ADDR_19_RECEIVE = "{receive_19}"')
    print(f'ADDR_20_RECEIVE = "{receive_20}"')
    print(f'ADDR_30_RECEIVE = "{receive_30}"')
    print(f'ADDR_0_CHANGE   = "{change_0}"')
