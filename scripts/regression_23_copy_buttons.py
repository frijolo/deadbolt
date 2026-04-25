#!/usr/bin/env python3
"""
Regression test 23: CopyIconButton in detail dialogs.

Verifies that the compact copy-icon buttons in CoinDetailDialog and
TxDetailDialog (migrated to CopyIconButton in the C2 refactor) actually
write content to the system clipboard when clicked.

Flow:
  1. Set Active Network to Signet.
  2. Create funded hot-key wallet via Guided creation (same mnemonic as
     reg11/reg14/reg15).
  3. Sync until confirmed coins are visible.
  4. Phase A — Coin detail copy:
       Coins tab → tap first coin tile → CoinDetailDialog →
       click "Copy to clipboard" tooltip button (outpoint copy) →
       read clipboard → verify it looks like a valid outpoint (txid:vout).
  5. Phase B — Transaction detail copy:
       Transactions tab → tap first tx tile → TxDetailDialog →
       click "Copy to clipboard" tooltip button (txid copy) →
       read clipboard → verify it looks like a valid txid (64-char hex).
  6. Delete wallet.

Gaps covered:
  - CopyIconButton in CoinDetailDialog (outpoint copy)
  - CopyIconButton in TxDetailDialog (txid copy)
  - Clipboard correctness: content is a valid outpoint / txid string

Exit code: 0 = PASS, 1 = FAIL.

Prerequisites:
  bash scripts/prepare_test_build.sh
  python3 scripts/regression_23_copy_buttons.py
"""

import asyncio
import os
import re
import subprocess
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from ui_driver import UIDriver                          # noqa: E402
from regression_helpers import (                       # noqa: E402
    wait_for,
    navigate_wallets,
    click_label, click_tooltip,
    fill_field,
    go_back_to_wallet_list, delete_wallet_from_list,
    set_active_network_signet, run_regression,
)


# ---------------------------------------------------------------------------
# Test data
# ---------------------------------------------------------------------------

WALLET_NAME = "Reg23-CopyButtons"

# Funded Signet P2WPKH hot-key wallet (shared with reg11/reg14/reg15/reg16).
MNEMONIC = (
    "bachelor brick camera brave assume differ disagree "
    "judge security scrap wonder core"
)

_ENV = {**os.environ, "DISPLAY": ":0"}

_TXID_RE = re.compile(r'^[0-9a-f]{64}$')
_OUTPOINT_RE = re.compile(r'^[0-9a-f]{64}:\d+$')


# ---------------------------------------------------------------------------
# Clipboard helper
# ---------------------------------------------------------------------------

def _read_clipboard() -> str:
    """Return current X11 clipboard content (empty string on error)."""
    try:
        result = subprocess.run(
            ["xclip", "-selection", "clipboard", "-o"],
            capture_output=True,
            env=_ENV,
            timeout=3,
        )
        return result.stdout.decode(errors="replace").strip()
    except Exception:
        return ""


def _clear_clipboard() -> None:
    """Clear X11 clipboard so we can detect a fresh write."""
    subprocess.run(
        ["xclip", "-selection", "clipboard"],
        input=b"",
        env=_ENV,
        check=False,
    )


# ---------------------------------------------------------------------------
# Phase 1: create wallet via Guided creation
# ---------------------------------------------------------------------------

async def phase_create_wallet(d: UIDriver) -> None:
    print(f"\n  [phase 1] create wallet: {WALLET_NAME}")

    await navigate_wallets(d)
    await click_tooltip(d, "New")
    await wait_for(d, "Guided creation", "bottom sheet opened")
    await click_label(d, "Guided creation", delay=0.5)
    await wait_for(d, '"New Wallet"', "Guided creation screen opened")

    await fill_field(d, "Wallet name", WALLET_NAME)

    await click_label(d, "Add key", delay=0.5)
    await wait_for(d, "Enter manually", "method picker visible",
                   retries=8, delay=0.5)

    await click_label(d, "Enter manually", delay=0.5)
    await wait_for(d, "Watch Only", "manual entry tabs visible",
                   retries=8, delay=0.5)

    await click_label(d, "Hot Key", delay=0.5)
    await wait_for(d, "Seed phrase", "Hot Key seed form visible",
                   retries=8, delay=0.5)

    await fill_field(d, "Seed phrase", MNEMONIC)
    await wait_for(d, "Derived keyspec", "keyspec derived",
                   retries=20, delay=1.0)

    await click_label(d, "Add", delay=1.0)
    await wait_for(d, "Remove key", "key tile visible",
                   retries=15, delay=0.8)

    await click_label(d, "Create wallet", delay=1.0)
    await wait_for(d, '"Receive"', f"wallet detail loaded",
                   retries=30, delay=1.0)
    print(f"    [ok] wallet '{WALLET_NAME}' opened")


# ---------------------------------------------------------------------------
# Phase 2: sync — wait for confirmed coins
# ---------------------------------------------------------------------------

async def phase_sync(d: UIDriver) -> None:
    print("\n  [phase 2] sync — wait for confirmed coins")

    await click_label(d, "Coins", delay=1.0)
    sem = await wait_for(
        d,
        "sats",
        "at least one coin value visible in Coins tab",
        retries=180,
        delay=1.0,
    )
    if '"No coins.' in sem:
        raise AssertionError(
            "Coins tab shows 'No coins' after sync — "
            "wallet may have no UTXOs on Signet."
        )
    print("    [ok] coins visible after sync")


# ---------------------------------------------------------------------------
# Phase A: copy outpoint from CoinDetailDialog
# ---------------------------------------------------------------------------

async def phase_copy_outpoint(d: UIDriver) -> None:
    print("\n  [phase A] copy outpoint from CoinDetailDialog")

    # Ensure we are on the Coins tab.
    await click_label(d, "Coins", delay=0.8)
    await wait_for(d, "sats", "Coins tab visible", retries=10, delay=0.5)

    # Tap the first coin tile (multi-line label contains "sats\n").
    sats_rect = await d.cs_find_label_containing("sats\n")
    if sats_rect is None:
        raise AssertionError("No coin tile found in Coins tab")
    d.flutter_click(
        (sats_rect[0] + sats_rect[2]) // 2,
        (sats_rect[1] + sats_rect[3]) // 2,
    )
    await asyncio.sleep(0.8)
    await wait_for(d, "Coin details", "CoinDetailDialog opened",
                   retries=10, delay=0.5)
    print("    [ok] CoinDetailDialog opened")

    # Clear clipboard before clicking so we can detect a fresh write.
    _clear_clipboard()

    # Click the "Copy to clipboard" tooltip button (CopyIconButton — outpoint).
    copy_rect = await d.cs_find_by_tooltip("Copy to clipboard")
    if copy_rect is None:
        raise AssertionError(
            "Copy to clipboard button not found in CoinDetailDialog"
        )
    d.flutter_click(
        (copy_rect[0] + copy_rect[2]) // 2,
        (copy_rect[1] + copy_rect[3]) // 2,
    )
    await asyncio.sleep(0.8)

    # Read and validate clipboard content.
    clipboard = _read_clipboard()
    if not _OUTPOINT_RE.match(clipboard):
        raise AssertionError(
            f"Clipboard does not look like a valid outpoint (txid:vout). "
            f"Got: '{clipboard[:80]}'"
        )
    print(f"    [ok] outpoint copied: '{clipboard}'")

    # Close CoinDetailDialog.
    await click_tooltip(d, "Cancel", delay=0.5)
    await wait_for(d, "Coins", "back on Coins tab", retries=8, delay=0.4)


# ---------------------------------------------------------------------------
# Phase B: copy txid from TxDetailDialog
# ---------------------------------------------------------------------------

async def phase_copy_txid(d: UIDriver) -> None:
    print("\n  [phase B] copy txid from TxDetailDialog")

    await click_label(d, "Transactions", delay=0.8)
    await wait_for(d, "sats", "Transactions tab visible", retries=10, delay=0.5)

    # Tap the first transaction tile.
    sats_rect = await d.cs_find_label_containing("sats\n")
    if sats_rect is None:
        raise AssertionError("No transaction tile found in Transactions tab")
    d.flutter_click(
        (sats_rect[0] + sats_rect[2]) // 2,
        (sats_rect[1] + sats_rect[3]) // 2,
    )
    await asyncio.sleep(0.8)
    await wait_for(d, "Transaction details", "TxDetailDialog opened",
                   retries=10, delay=0.5)
    print("    [ok] TxDetailDialog opened")

    _clear_clipboard()

    # Click the "Copy to clipboard" tooltip button (CopyIconButton — txid).
    copy_rect = await d.cs_find_by_tooltip("Copy to clipboard")
    if copy_rect is None:
        raise AssertionError(
            "Copy to clipboard button not found in TxDetailDialog"
        )
    d.flutter_click(
        (copy_rect[0] + copy_rect[2]) // 2,
        (copy_rect[1] + copy_rect[3]) // 2,
    )
    await asyncio.sleep(0.8)

    # Read and validate clipboard content.
    clipboard = _read_clipboard()
    if not _TXID_RE.match(clipboard):
        raise AssertionError(
            f"Clipboard does not look like a valid txid (64-char hex). "
            f"Got: '{clipboard[:80]}'"
        )
    print(f"    [ok] txid copied: '{clipboard[:16]}…'")

    # Close TxDetailDialog.
    await click_tooltip(d, "Close", delay=0.5)


# ---------------------------------------------------------------------------
# Test entry point
# ---------------------------------------------------------------------------

async def test(d: UIDriver) -> None:
    await set_active_network_signet(d)
    await phase_create_wallet(d)
    await phase_sync(d)
    await phase_copy_outpoint(d)
    await phase_copy_txid(d)

    print(f"\n    [PASS] {WALLET_NAME}")

    await go_back_to_wallet_list(d)
    await delete_wallet_from_list(d, WALLET_NAME)


if __name__ == "__main__":
    asyncio.run(run_regression(test, "reg23"))
