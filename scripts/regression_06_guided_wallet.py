#!/usr/bin/env python3
"""
Regression test 06: guided wallet creation via SimpleWalletDialog.

Exercises the "Guided creation" bottom-sheet flow introduced in v1.5:
  Wallet tab → '+' → 'Guided creation' → fill name + key (Watch Only) →
  Create wallet → wallet detail opens → back → delete wallet.

Two sub-tests:
  Reg06-Guided-Singlesig  — single key, native SegWit (P2WPKH)
  Reg06-Guided-Taproot    — single key, Taproot (P2TR)

Exit code: 0 = all PASS, 1 = one or more FAIL.

Run:
  bash scripts/prepare_test_build.sh   # once, before first test run
  python3 scripts/regression_06_guided_wallet.py
"""

import asyncio
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from ui_driver import UIDriver                          # noqa: E402
from regression_helpers import (                       # noqa: E402
    wait_for, wait_absent,
    dismiss_startup_dialogs,
    navigate_wallets, fill_field, click_label, click_tooltip,
    go_back_to_wallet_list, delete_wallet_from_list,
    open_watch_only_manual_entry, fill_manual_keyspec,
    run_regression,
)

# ---------------------------------------------------------------------------
# Test key (testnet wpkh / taproot)
# ---------------------------------------------------------------------------
_MFP  = "73c5da0a"
_PATH = "84h/1h/0h"
_XPUB = (
    "tpubDC5FSnBiZDMmhiuCmWAYsLwgLYrrT9rAqvTySfuCCrgsWz8wxMXUS9Tb9iVMvcRb"
    "vFcAHGkMD5Kx8koh4GquNGNTfohfk7pgjhaPCdXpoba"
)

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

async def _open_guided_dialog(d: UIDriver):
    """
    From the Wallet list, open the 'Guided creation' dialog.
    Lands on the 'New Wallet' Scaffold.
    """
    await navigate_wallets(d)
    await click_tooltip(d, "New")
    # Bottom sheet: multi-line labels — search without surrounding quotes.
    await wait_for(d, "Guided creation", "Bottom sheet opened")
    await click_label(d, "Guided creation", delay=0.5)
    await wait_for(d, '"New Wallet"', "Guided creation screen opened")
    print("    [ok] 'New Wallet' screen open")


async def _add_watch_only_key(d: UIDriver):
    """
    In SimpleWalletDialog, add a Watch-Only key via the manual-entry sheet.

    Key input sheet flow:
      1. Capacity picker: 'Watch-only key' / 'Hot key'.
      2. Click 'Watch-only key' → 'Enter manually' tile.
      3. Fill compact keyspec → Confirm.
    """
    await click_label(d, "Add key", delay=0.5)
    await open_watch_only_manual_entry(d)
    print("    [ok] manual entry sheet open")

    await fill_manual_keyspec(d, mfp=_MFP, path=_PATH, xpub=_XPUB, compact=True)
    # Key card should appear with the MFP badge
    await wait_for(d, _MFP.lower(), "Key card with MFP visible")
    print(f"    [ok] key '{_MFP}' added")


async def _select_script(d: UIDriver, label: str):
    """
    Click one of the script-type SegmentedButton segments in SimpleWalletDialog.
    label: 'Legacy' | 'Nested' | 'SegWit' | 'Taproot'
    """
    await click_label(d, label, delay=0.4)
    print(f"    [ok] script type '{label}' selected")


async def _create_and_verify(d: UIDriver, wallet_name: str) -> None:
    """
    Click 'Create wallet', wait for wallet detail, verify Receive + Send.
    """
    await click_label(d, "Create wallet", delay=0.5)
    # BDK init + first sync: allow up to 30 s
    await wait_for(
        d, '"Receive"',
        f"Wallet detail loaded: '{wallet_name}'",
        retries=30, delay=1.0,
    )
    print(f"    [ok] wallet detail opened: '{wallet_name}'")

    sem = await d.cs_flat_text()
    assert '"Receive"' in sem, "Receive button not found"
    assert '"Send"' in sem, "Send button not found"
    print("    [ok] Receive + Send buttons visible")


async def _verify_addresses_tab(d: UIDriver, wallet_name: str):
    """Navigate to Addresses tab and verify it loads correctly."""
    await click_label(d, "Addresses", delay=1.0)
    # Poll up to 10 s: addresses may still be loading after a fresh wallet sync.
    for _ in range(10):
        sem_a = await d.cs_flat_text()
        has_addr = 'receive_address_0' in sem_a
        has_reveal = '"Reveal 20 more addresses"' in sem_a
        if has_addr or has_reveal:
            break
        await asyncio.sleep(1.0)
    else:
        raise AssertionError(
            f"Addresses tab shows neither addresses nor Reveal button for '{wallet_name}'"
        )
    print("    [ok] Addresses tab has at least one entry")


# ---------------------------------------------------------------------------
# Sub-tests
# ---------------------------------------------------------------------------

async def _run_guided_test(d: UIDriver, name: str, script: str | None):
    """Common guided wallet creation flow."""
    print(f"\n--- {name} ---")

    await _open_guided_dialog(d)
    await fill_field(d, "Wallet name", name)
    if script is not None:
        await _select_script(d, script)
    await _add_watch_only_key(d)
    await _create_and_verify(d, name)
    await _verify_addresses_tab(d, name)
    await go_back_to_wallet_list(d)
    await delete_wallet_from_list(d, name)
    print(f"    [PASS] {name}")


# ---------------------------------------------------------------------------
# Entry point
# ---------------------------------------------------------------------------

async def test_guided_wallet(d: UIDriver):
    """Run all guided wallet sub-tests. Raises on first failure."""
    total = 2
    await _run_guided_test(d, "Reg06-Guided-Singlesig", None)
    await _run_guided_test(d, "Reg06-Guided-Taproot", "Taproot")
    print(f"\n{'='*50}")
    print(f"[RESULT] PASS — all {total} guided wallet creation sub-tests OK")


if __name__ == "__main__":
    asyncio.run(run_regression(test_guided_wallet, "reg06"))
