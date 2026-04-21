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
    Add one Watch-Only key via the 'Enter manually' flow.

    key: dict with 'mfp', 'path', 'xpub' fields.
    """
    await click_label(d, "Add key", delay=0.5)
    await wait_for(d, "Enter manually", "Key input method picker visible")

    await click_label(d, "Enter manually", delay=0.5)
    await wait_for(d, "Watch Only", "Manual entry form visible")

    await fill_field(d, "Master Fingerprint (MFP)", key["mfp"])
    await fill_field(d, "Derivation Path",           key["path"])
    await fill_field(d, "Extended Public Key (xpub)", key["xpub"])
    await click_label(d, "Add", delay=0.8)

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

    sem = await d.semantics_tree()
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
        sem_a = await d.semantics_tree()
        has_addr = '"#0\n' in sem_a or 'tb1q' in sem_a.lower()
        has_reveal = '"Reveal 20 more addresses"' in sem_a
        if has_addr or has_reveal:
            break
        await asyncio.sleep(1.0)
    else:
        raise AssertionError(
            f"Addresses tab shows neither addresses nor Reveal button for '{wallet_name}'"
        )
    print("    [ok] Addresses tab has at least one entry")


async def _go_back_to_wallet_list(d: UIDriver):
    # wallet_detail_screen PopScope: canPop only when on Overview tab.
    # From any other tab, Back navigates to Overview first; a second Back exits.
    await click_tooltip(d, "Back", delay=0.8)
    sem = await d.semantics_tree()
    if '"Wallets"' not in sem:
        await click_tooltip(d, "Back", delay=0.8)
    await wait_for(d, '"Wallets"', "Back on wallet list")
    print("    [ok] back on wallet list")


async def _delete_wallet(d: UIDriver, wallet_name: str):
    """Delete a wallet via its card popup menu."""
    await wait_for(d, wallet_name, "Wallet card visible")
    rect = await d.find_semantic_rect_by_tooltip("More options")
    assert rect is not None, "More options button not found on wallet card"
    cx = (rect[0] + rect[2]) // 2
    cy = (rect[1] + rect[3]) // 2
    d.flutter_click(cx, cy, delay_s=0.5)
    await asyncio.sleep(0.6)
    item_rect = await d.find_semantic_rect("Delete")
    assert item_rect is not None, "'Delete' item not found in popup"
    d.flutter_click(
        (item_rect[0] + item_rect[2]) // 2,
        (item_rect[1] + item_rect[3]) // 2,
    )
    await asyncio.sleep(0.4)
    await wait_for(d, '"Delete wallet"', "Delete confirmation dialog")
    await click_label(d, "Delete", delay=1.0)
    await wait_absent(d, wallet_name, f"'{wallet_name}' removed")
    print(f"    [ok] wallet '{wallet_name}' deleted")


# ---------------------------------------------------------------------------
# Sub-tests
# ---------------------------------------------------------------------------

async def test_guided_wsh_2of2(d: UIDriver):
    name = "Reg07-Guided-WSH-2of2"
    print(f"\n--- {name} ---")

    await _open_guided_dialog(d)
    await fill_field(d, "Wallet name", name)
    await _select_multisig(d)
    # Script: keep default 'SegWit' (native segwit P2WSH for multisig)
    await _add_watch_only_key(d, _KEYS[0])
    await _add_watch_only_key(d, _KEYS[1])
    # Default threshold after 2 keys = 1; raise to 2
    await _set_threshold(d, target=2, current=1)
    await _create_and_verify(d, name)
    await _verify_addresses_tab(d, name)
    await _go_back_to_wallet_list(d)
    await _delete_wallet(d, name)
    print(f"    [PASS] {name}")


async def test_guided_wsh_2of3(d: UIDriver):
    name = "Reg07-Guided-WSH-2of3"
    print(f"\n--- {name} ---")

    await _open_guided_dialog(d)
    await fill_field(d, "Wallet name", name)
    await _select_multisig(d)
    await _add_watch_only_key(d, _KEYS[0])
    await _add_watch_only_key(d, _KEYS[1])
    await _add_watch_only_key(d, _KEYS[2])
    # Default threshold after 3 keys = 1; raise to 2
    await _set_threshold(d, target=2, current=1)
    await _create_and_verify(d, name)
    await _verify_addresses_tab(d, name)
    await _go_back_to_wallet_list(d)
    await _delete_wallet(d, name)
    print(f"    [PASS] {name}")


async def test_guided_taproot_2of3(d: UIDriver):
    name = "Reg07-Guided-TR-2of3"
    print(f"\n--- {name} ---")

    await _open_guided_dialog(d)
    await fill_field(d, "Wallet name", name)
    await _select_multisig(d)
    await _select_script(d, "Taproot")
    await _add_watch_only_key(d, _KEYS[0])
    await _add_watch_only_key(d, _KEYS[1])
    await _add_watch_only_key(d, _KEYS[2])
    await _set_threshold(d, target=2, current=1)
    await _create_and_verify(d, name)
    await _verify_addresses_tab(d, name)
    await _go_back_to_wallet_list(d)
    await _delete_wallet(d, name)
    print(f"    [PASS] {name}")


# ---------------------------------------------------------------------------
# Entry point
# ---------------------------------------------------------------------------

CASES = [
    ("Reg07-Guided-WSH-2of2",  test_guided_wsh_2of2),
    ("Reg07-Guided-WSH-2of3",  test_guided_wsh_2of3),
    ("Reg07-Guided-TR-2of3",   test_guided_taproot_2of3),
]


async def main():
    d = UIDriver(sandbox=True)
    failed: list[str] = []
    try:
        await d.launch()
        d.raise_window()
        await dismiss_startup_dialogs(d)

        for name, fn in CASES:
            try:
                await fn(d)
            except (AssertionError, Exception) as exc:
                print(f"\n[FAIL] {name}: {exc}")
                failed.append(name)
                # Recovery: close any open sheet/dialog, then navigate back.
                # click_tooltip never raises when node is absent (just warns),
                # so check semantics explicitly before deciding to close or back.
                for _ in range(6):
                    sem = await d.semantics_tree()
                    if '"Wallets"' in sem:
                        break
                    if 'tooltip: "Close"' in sem:
                        await click_tooltip(d, "Close", delay=0.5)
                        continue
                    await click_tooltip(d, "Back", delay=0.5)
                try:
                    await _delete_wallet(d, name)
                except Exception:
                    pass
    except Exception as exc:
        print(f"\n[ERROR] Unexpected exception: {exc}")
        raise
    finally:
        await d.close()

    total = len(CASES)
    print(f"\n{'='*50}")
    if failed:
        print(f"[RESULT] FAIL — {len(failed)}/{total} sub-tests failed: {failed}")
        sys.exit(1)
    else:
        print(f"[RESULT] PASS — all {total} guided multisig wallet creation sub-tests OK")


if __name__ == "__main__":
    asyncio.run(main())
