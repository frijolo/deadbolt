#!/usr/bin/env python3
"""
Regression test 07: guided multisig wallet creation via SimpleWalletDialog.

Exercises the multisig path of the 'Guided creation' flow:
  Wallet tab → '+' → 'Guided creation' → select 'Multisig' → fill name →
  add 2 or 3 Watch-Only keys → adjust threshold → Create wallet →
  wallet detail opens → back → delete wallet.

Sub-tests:
  Reg07-Guided-WSH-2of2   — 2 keys, Native SegWit, threshold=2
  Reg07-Guided-WSH-2of3   — 3 keys, Native SegWit, threshold=2
  Reg07-Guided-TR-2of3    — 3 keys, Taproot,       threshold=2

Exit code: 0 = all PASS, 1 = one or more FAIL.

Run:
  bash scripts/prepare_test_build.sh   # once, before first test run
  python3 scripts/regression_07_guided_multisig.py
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
# Test keys (testnet — same xpubs used in regression_02_multisig_wsh.py)
# ---------------------------------------------------------------------------

_KEYS = [
    {
        "mfp":  "4061aff0",
        "path": "48h/1h/0h/2h",
        "xpub": (
            "tpubDFAv39stw4ELPsWiyqNL2UcFwruoVdX89CEpzJwb1TV3k9JgW6tLPUicWJvRT5"
            "iUSH7HHdt6rXtgRSX5TWJZqDcwJZZTtj1WTcHLUCC7eXC"
        ),
    },
    {
        "mfp":  "ff81be5d",
        "path": "48h/1h/0h/2h",
        "xpub": (
            "tpubDDxjvuVfYHF4KcVyd5wkNS6pKJvg1x6CUtCRL3nRX2MDHKcja6M7YB7FYFYDkX"
            "zx8fL7k9bYi8XDpfPetqvd6ER2VYt1WsQSHYnhhT2EX7K"
        ),
    },
    {
        "mfp":  "f3d33d4f",
        "path": "48h/1h/0h/2h",
        "xpub": (
            "tpubDFLYS7v5vvjyhLMotrmn6KzdN46jJ8ife9yD8DUMygtNCR4U389Wr46vJj7kG9b"
            "JPqFmLSet7hAP5fVJvyc97x9fhKZ7Zm9cTdvMxHqT55h"
        ),
    },
]


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

async def _open_guided_dialog(d: UIDriver):
    """Navigate to wallet list and open the Guided creation screen."""
    await navigate_wallets(d)
    await click_tooltip(d, "New")
    await wait_for(d, "Guided creation", "Bottom sheet opened")
    await click_label(d, "Guided creation", delay=0.5)
    await wait_for(d, '"New Wallet"', "New Wallet screen opened")
    print("    [ok] 'New Wallet' screen open")


async def _select_multisig(d: UIDriver):
    """Switch wallet type to Multisig."""
    await click_label(d, "Multisig", delay=0.5)
    # After switching to multisig the 'Add key' button label changes to
    # 'Set key' / 'Add key' and the threshold row may appear later.
    print("    [ok] Multisig selected")


async def _select_script(d: UIDriver, label: str):
    """Click one of the script-type SegmentedButton segments."""
    await click_label(d, label, delay=0.4)
    print(f"    [ok] script type '{label}' selected")


async def _add_watch_only_key(d: UIDriver, key: dict):
    """
    Add one Watch-Only key via the manual-entry sheet.

    key: dict with 'mfp', 'path', 'xpub' fields.
    """
    await click_label(d, "Add key", delay=0.5)
    await open_watch_only_manual_entry(d)

    await fill_manual_keyspec(d, mfp=key["mfp"], path=key["path"],
                              xpub=key["xpub"], compact=True)

    await wait_for(d, key["mfp"].lower(), f"Key card for {key['mfp']} visible")
    print(f"    [ok] key '{key['mfp']}' added")


async def _set_threshold(d: UIDriver, target: int, current: int):
    """
    Adjust the multisig threshold from `current` to `target` using the
    'Increase threshold' / 'Decrease threshold' tooltip buttons.
    """
    while current < target:
        await click_tooltip(d, "Increase threshold", delay=0.3)
        current += 1
        print(f"    [ok] threshold → {current}")
    while current > target:
        await click_tooltip(d, "Decrease threshold", delay=0.3)
        current -= 1
        print(f"    [ok] threshold → {current}")


async def _create_and_verify(d: UIDriver, wallet_name: str):
    """Click 'Create wallet' and verify the wallet detail screen opens."""
    # Scroll down to ensure the button is fully in the interactive area,
    # especially on forms with 3+ keys where it lands near the window edge.
    d.scroll_down(3)
    await asyncio.sleep(0.4)
    await click_label(d, "Create wallet", delay=0.5)
    await wait_for(
        d, '"Receive"',
        f"Wallet detail loaded: '{wallet_name}'",
        retries=30, delay=1.0,
    )
    print(f"    [ok] wallet detail opened: '{wallet_name}'")

    sem = await d.cs_flat_text()
    assert '"Receive"' in sem, "Receive button not found"
    assert '"Send"' in sem,    "Send button not found"
    print("    [ok] Receive + Send buttons visible")


async def _verify_addresses_tab(d: UIDriver, wallet_name: str):
    """Navigate to Addresses tab and verify it loads correctly."""
    # Dismiss any open popup/overlay (e.g. residual PopupMenuButton from prior
    # scroll interactions) by pressing Escape before navigating.
    d.key("Escape")
    await asyncio.sleep(0.3)
    # Scroll down to ensure the NavigationBar is in the semantics viewport so
    # click_label finds the correct "Addresses" destination, not a stale rect.
    d.scroll_down(3)
    await asyncio.sleep(0.4)
    await click_label(d, "Addresses", delay=1.5)
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

async def _run_multisig_test(d: UIDriver, name: str, keys: list, threshold: int, script: str | None):
    """Common guided multisig wallet creation flow."""
    print(f"\n--- {name} ---")

    await _open_guided_dialog(d)
    await fill_field(d, "Wallet name", name)
    await _select_multisig(d)
    if script is not None:
        await _select_script(d, script)
    for key in keys:
        await _add_watch_only_key(d, key)
    await _set_threshold(d, target=threshold, current=len(keys))
    await _create_and_verify(d, name)
    await _verify_addresses_tab(d, name)
    await go_back_to_wallet_list(d)
    await delete_wallet_from_list(d, name)
    print(f"    [PASS] {name}")


# ---------------------------------------------------------------------------
# Entry point
# ---------------------------------------------------------------------------

async def test_guided_multisig(d: UIDriver):
    """Run all guided multisig sub-tests. Raises on first failure."""
    total = 3
    await _run_multisig_test(d, "Reg07-Guided-WSH-2of2", _KEYS[:2], 2, None)
    await _run_multisig_test(d, "Reg07-Guided-WSH-2of3", _KEYS[:3], 2, None)
    await _run_multisig_test(d, "Reg07-Guided-TR-2of3",   _KEYS[:3], 2, "Taproot")
    print(f"\n{'='*50}")
    print(f"[RESULT] PASS — all {total} guided multisig wallet creation sub-tests OK")


if __name__ == "__main__":
    asyncio.run(run_regression(test_guided_multisig, "reg07"))
