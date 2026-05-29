#!/usr/bin/env python3
"""
Regression test 45: Recover Wallet → Xpub tab end-to-end.

Reg39 covers the Hardware tab and reg11/reg29 cover the Seed tab; the Xpub
tab was previously untested. Exercises:
  - Pasting a bare xpub.
  - Triggering discovery (on-chain + Nostr).
  - Verifying the scan surfaces at least one account card with balance/tx
    metadata (the xpub used has confirmed activity on signet).
  - Creating a watch-only wallet from the scan result (Create wallet
    tooltip → SimpleWalletDialog → name → wallet detail opens).
  - Cleanup.

The xpub is the same one reg08 uses for its signet watch-only wallet
(mnemonic 'piece blue stadium ...', MFP ff81be5d, m/84'/1'/0'). That
account always has signet activity, so the scan is deterministic.

Exit code: 0 = PASS, 1 = FAIL.
"""

import asyncio
import os
import subprocess
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from ui_driver import UIDriver  # noqa: E402
from regression_helpers import (  # noqa: E402
    wait_for, wait_absent,
    navigate_wallets, click_label, click_tooltip, fill_field,
    set_active_network_signet, go_back_to_wallet_list,
    delete_wallet_from_list, run_regression,
)

WALLET_NAME = "Reg45-Xpub-Restore"

# Reg08's signet-funded native-segwit (BIP84) account, in keyspec format.
# The bare xpub is also accepted, but discovery only renders the
# 'Create wallet' action when a derivation path is present (see
# restore_wallet_screen.dart `foundOnChain = derivationPath?.isNotEmpty`).
XPUB = (
    "[ff81be5d/84h/1h/0h]"
    "tpubDDjVt7cey7cxQ1nXzxpXuNT5vJecpvtMhmZywA9U9ChWDk8z6HSGPJ7YS6pyd8ZXQ"
    "yfCeUCXrkyEqNeTFUmpdXT9r3TD1DAYoY52UEyy1Yf"
)

_ENV = {**os.environ, "DISPLAY": ":0"}


async def _open_recover_xpub_tab(d: UIDriver):
    print("\n  [phase 1] open Recover Wallet → Xpub tab")
    await navigate_wallets(d)
    await click_tooltip(d, "New")
    await wait_for(d, "Recover Wallet", "new-wallet sheet open",
                   retries=10, delay=0.5)
    await click_label(d, "Recover Wallet", delay=0.5)
    await wait_for(d, "Restoring to:", "Recover Wallet screen opened",
                   retries=10, delay=0.5)
    # The Xpub tab is the screen's default — verified by its hint label.
    await wait_for(d, "xpub6...", "Xpub tab active (hint visible)",
                   retries=10, delay=0.4)
    print("    [ok] Xpub tab active")


async def _paste_xpub(d: UIDriver):
    print("\n  [phase 2] paste xpub")
    rect = await d.cs_find_textfield_by_label("xpub6... or [mfp/path]xpub...")
    if rect is None:
        raise AssertionError("xpub textfield not found in Xpub tab")
    d.flutter_click((rect[0] + rect[2]) // 2, (rect[1] + rect[3]) // 2)
    await asyncio.sleep(0.3)
    d.key("ctrl+a")
    await asyncio.sleep(0.1)
    subprocess.run(["xclip", "-selection", "clipboard"],
                   input=XPUB.encode(), env=_ENV, check=True)
    await asyncio.sleep(0.1)
    d.key("ctrl+v")
    await asyncio.sleep(0.5)
    flat = await d.cs_flat_text()
    # xpub is a 111-char string; semantics may truncate, but at least the
    # leading characters must appear in the visible tree.
    assert XPUB[:24] in flat, "xpub not visible after paste"
    print("    [ok] xpub pasted")


async def _disable_backup_searches(d: UIDriver):
    """Turn off both 'Search Nostr backups' and 'Search on-chain backups'
    toggles so the scan returns pure discovery accounts (Create-wallet
    tooltip), not 'Restore from Nostr'/'Restore from on-chain' shortcuts.
    The Nostr/on-chain restore paths are out of scope for this regression."""
    print("\n  [phase 3a] disable backup searches")
    for label in ("Search Nostr backups", "Search on-chain backups"):
        for _ in range(5):
            if await d.cs_is_visible(label):
                break
            d.scroll_down(3)
            await asyncio.sleep(0.3)
        await click_label(d, label, delay=0.4)


async def _trigger_scan(d: UIDriver):
    print("\n  [phase 3b] trigger scan")
    for _ in range(5):
        if await d.cs_is_visible("Scan"):
            break
        d.scroll_down(3)
        await asyncio.sleep(0.4)
    await click_label(d, "Scan", delay=0.8)
    # Wait for at least one account card with a 'Create wallet' tooltip
    # (same readiness signal reg11/reg39 use). Allow generous time: signet
    # discovery + Nostr fetches can take a couple of minutes.
    for attempt in range(3):
        try:
            await wait_for(
                d, "Create wallet", "scan results visible",
                retries=180, delay=2.0,
            )
            print("    [ok] scan returned at least one account")
            return
        except AssertionError:
            sem = await d.cs_flat_text()
            if '"Retry"' in sem:
                print("    [warn] scan failed, retrying...")
                await click_label(d, "Retry", delay=1.0)
                await asyncio.sleep(2.0)
                continue
            raise
    raise AssertionError("Scan failed after 3 retry attempts")


async def _verify_account_has_activity(d: UIDriver):
    """The scanned account should expose at least one of: balance, tx count,
    or 'sats' — the reg08 xpub is known to be funded on signet."""
    flat = await d.cs_flat_text()
    has_activity = ("sats" in flat) or ("txs" in flat) or ("transactions" in flat.lower())
    assert has_activity, (
        "scan result does not advertise activity (no sats/txs found in tree) — "
        "the xpub may be looking at the wrong network or the electrum server "
        "is unreachable"
    )
    print("    [ok] account card advertises activity (sats/txs visible)")


async def _create_wallet_from_scan(d: UIDriver):
    print("\n  [phase 4] create watch-only wallet from scan result")
    await click_tooltip(d, "Create wallet", delay=0.6)
    await wait_for(d, '"New Wallet"', "SimpleWalletDialog opened",
                   retries=15, delay=0.5)
    await fill_field(d, "Wallet name", WALLET_NAME)
    await click_label(d, "Create wallet", delay=1.0)
    # SimpleWalletDialog pops back to RestoreWallet screen, not directly
    # to wallet detail (same behaviour as reg11).
    await wait_absent(d, '"New Wallet"', "SimpleWalletDialog closed",
                      retries=25, delay=1.0)
    # Pop the RestoreWallet screen back to the wallet list, then open
    # the wallet card.
    await click_tooltip(d, "Back", delay=0.8)
    await wait_for(d, '"Wallets"', "back on wallet list",
                   retries=15, delay=0.5)
    await click_label(d, WALLET_NAME, delay=1.0)
    await wait_for(d, '"Receive"', f"wallet detail loaded: '{WALLET_NAME}'",
                   retries=40, delay=1.0)


async def _cleanup(d: UIDriver):
    print("\n  [phase 5] cleanup")
    await go_back_to_wallet_list(d)
    await delete_wallet_from_list(d, WALLET_NAME)


# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------

async def test_restore_from_xpub(d: UIDriver):
    print(f"\n--- {WALLET_NAME} (Recover Wallet → Xpub tab) ---")
    await set_active_network_signet(d)
    await _open_recover_xpub_tab(d)
    await _paste_xpub(d)
    await _disable_backup_searches(d)
    await _trigger_scan(d)
    await _verify_account_has_activity(d)
    await _create_wallet_from_scan(d)
    await _cleanup(d)
    print(f"    [PASS] {WALLET_NAME}")


if __name__ == "__main__":
    asyncio.run(run_regression(test_restore_from_xpub, "reg45"))
