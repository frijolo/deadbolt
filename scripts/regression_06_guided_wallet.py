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
    In SimpleWalletDialog, add a Watch-Only key via the 'Enter manually' flow.

    Key input sheet flow (keyspec mode):
      1. Method picker shows first: 'Enter manually' option.
      2. Click 'Enter manually' → chips 'Watch Only' / 'Hot Key' appear.
      3. 'Watch Only' (separateFields tab) is selected by default.
      4. Fill MFP, derivation path, xpub → click 'Add'.
    """
    # Click 'Add key' (OutlinedButton.icon when no key yet)
    await click_label(d, "Add key", delay=0.5)
    await wait_for(d, "Enter manually", "Key input method picker visible")
    print("    [ok] method picker open")

    await click_label(d, "Enter manually", delay=0.5)
    await wait_for(d, "Watch Only", "Manual entry form visible")
    print("    [ok] 'Watch Only' tab visible")

    await fill_field(d, "Master Fingerprint (MFP)", _MFP)
    await fill_field(d, "Derivation Path", _PATH)
    await fill_field(d, "Extended Public Key (xpub)", _XPUB)
    await click_label(d, "Add", delay=0.8)
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

    sem = await d.semantics_tree()
    assert '"Receive"' in sem, "Receive button not found"
    assert '"Send"' in sem, "Send button not found"
    print("    [ok] Receive + Send buttons visible")


async def _go_back_to_wallet_list(d: UIDriver):
    await click_tooltip(d, "Back", delay=0.8)
    await wait_for(d, '"Wallets"', "Back on wallet list")
    print("    [ok] back on wallet list")


async def _delete_wallet(d: UIDriver, wallet_name: str):
    """Delete a wallet via its card popup menu.

    Wallet card uses ListTile with onTap → merged multi-line semantic label.
    Search with plain `wallet_name` (no surrounding quotes) instead of
    `'"name"'` to handle the multi-line label format.
    """
    # Multi-line label: "wallet_name\nTestnet Not yet synced"
    await wait_for(d, wallet_name, "Wallet card visible")
    rect = await d.find_semantic_rect_by_tooltip("More options")
    assert rect is not None, "More options button not found on wallet card"
    cx = (rect[0] + rect[2]) // 2
    cy = (rect[1] + rect[3]) // 2
    d.flutter_click(cx, cy, delay_s=0.5)
    await asyncio.sleep(0.6)
    item_rect = await d.find_semantic_rect("Delete")
    assert item_rect is not None, "'Delete' item not found in popup"
    d.flutter_click((item_rect[0] + item_rect[2]) // 2,
                    (item_rect[1] + item_rect[3]) // 2)
    await asyncio.sleep(0.4)
    await wait_for(d, '"Delete wallet"', "Delete confirmation dialog")
    await click_label(d, "Delete", delay=1.0)
    await wait_absent(d, wallet_name, f"'{wallet_name}' removed")
    print(f"    [ok] wallet '{wallet_name}' deleted")


# ---------------------------------------------------------------------------
# Sub-tests
# ---------------------------------------------------------------------------

async def test_guided_singlesig(d: UIDriver):
    name = "Reg06-Guided-Singlesig"
    print(f"\n--- {name} ---")

    await _open_guided_dialog(d)
    await fill_field(d, "Wallet name", name)
    # Script: keep default 'SegWit' (native segwit P2WPKH for singlesig)
    await _add_watch_only_key(d)
    # Network: default is testnet — no change needed
    await _create_and_verify(d, name)
    await _go_back_to_wallet_list(d)
    await _delete_wallet(d, name)
    print(f"    [PASS] {name}")


async def test_guided_taproot(d: UIDriver):
    name = "Reg06-Guided-Taproot"
    print(f"\n--- {name} ---")

    await _open_guided_dialog(d)
    await fill_field(d, "Wallet name", name)
    await _select_script(d, "Taproot")
    await _add_watch_only_key(d)
    await _create_and_verify(d, name)
    await _go_back_to_wallet_list(d)
    await _delete_wallet(d, name)
    print(f"    [PASS] {name}")


# ---------------------------------------------------------------------------
# Entry point
# ---------------------------------------------------------------------------

CASES = [
    ("Reg06-Guided-Singlesig", test_guided_singlesig),
    ("Reg06-Guided-Taproot",   test_guided_taproot),
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
                # Recovery: try to get back to wallet list
                for _ in range(3):
                    try:
                        await click_tooltip(d, "Back", delay=0.5)
                    except Exception:
                        break
                    sem = await d.semantics_tree()
                    if '"Wallets"' in sem:
                        break
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
        print(f"[RESULT] PASS — all {total} guided wallet creation sub-tests OK")


if __name__ == "__main__":
    asyncio.run(main())
