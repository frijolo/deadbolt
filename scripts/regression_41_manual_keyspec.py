#!/usr/bin/env python3
"""
Regression test 41: manual keyspec entry parser coverage.

Tests the four parser paths of the manual-entry bottom sheet:
  1. Compact format:   [mfp/path]xpub
  2. Three lines (canonical order): mfp\\npath\\nxpub
  3. Three tokens out of order:      xpub\\nmfp\\npath
  4. Invalid input:                   should show error, sheet stays open

Exit code: 0 = PASS, 1 = FAIL.

Run:
  python3 scripts/regression_41_manual_keyspec.py
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
# Test data
# ---------------------------------------------------------------------------

_TEST_MFP = "4061aff0"
_TEST_PATH = "84h/0h/0h"
_TEST_XPUB = (
    "tpubDC5FSnBiZDMmhiuCmWAYsLwgLYrrT9rAqvTySfuCCrgsWz8wxMXUS9Tb9iVMvcRb"
    "vFcAHGkMD5Kx8koh4GquNGNTfohfk7pgjhaPCdXpoba"
)


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

async def _open_guided_wallet(d: UIDriver, name: str):
    """Open guided creation, set wallet name, return to 'Add key' state."""
    await navigate_wallets(d)
    await click_tooltip(d, "New", delay=0.5)
    await wait_for(d, "Guided creation", "Bottom sheet opened",
                   retries=10, delay=0.5)
    await click_label(d, "Guided creation", delay=0.5)
    await wait_for(d, '"New Wallet"', "Guided creation screen opened",
                   retries=10, delay=0.5)
    await fill_field(d, "Wallet name", name)
    await wait_for(d, '"Add key"', "Add key button visible",
                   retries=10, delay=0.5)


async def _add_key_via_manual_entry(d: UIDriver, *, compact: bool = True):
    """Open manual entry sheet, fill keyspec, confirm, verify key card."""
    await click_label(d, "Add key", delay=0.5)
    await open_watch_only_manual_entry(d)

    if compact:
        value = f"[{_TEST_MFP}/{_TEST_PATH}]{_TEST_XPUB}"
    else:
        value = f"{_TEST_MFP}\n{_TEST_PATH}\n{_TEST_XPUB}"
    await fill_field(d, "[mfp/path]xpub", value)
    await click_label(d, "Confirm", delay=0.8)

    await wait_for(d, _TEST_MFP.lower(), "Key card with MFP visible",
                   retries=15, delay=0.5)
    await wait_absent(d, "Watch-only key", "Add-key sheet closed",
                      retries=15, delay=0.5)
    print(f"    [ok] key card verified for MFP {_TEST_MFP}")


async def _verify_error_on_sheet(d: UIDriver):
    """Verify the error text is shown on the sheet and sheet stays open."""
    error_label = "Format not recognized"
    try:
        await wait_for(d, error_label, "Error text visible on sheet",
                       retries=10, delay=0.5)
        print(f"    [ok] error message '{error_label}' shown")
    except AssertionError:
        await wait_for(d, "No se reconoce",
                       "Error message (Spanish) visible on sheet",
                       retries=10, delay=0.5)
        print("    [ok] error message (Spanish) shown")
    # Sheet stays open (no Navigator.pop called) — verify by checking
    # that "Confirm" button is still present (it would be gone if sheet closed)
    await wait_for(d, "Confirm", "Sheet still open (Confirm button visible)",
                   retries=10, delay=0.5)


async def _create_wallet_and_verify(d: UIDriver, name: str):
    """Create wallet and verify it loads."""
    await click_label(d, "Create wallet", delay=0.5)
    await wait_for(d, '"Receive"', f"wallet detail loaded: '{name}'",
                   retries=30, delay=1.0)
    print(f"    [ok] wallet '{name}' created")


# ---------------------------------------------------------------------------
# Test cases
# ---------------------------------------------------------------------------

async def _test_compact_format(d: UIDriver):
    """Test 1: Compact keyspec format [mfp/path]xpub."""
    print("\n  [test 1] compact format [mfp/path]xpub")
    wallet_name = "Reg41-Compact"
    await _open_guided_wallet(d, wallet_name)
    await _add_key_via_manual_entry(d, compact=True)
    await _create_wallet_and_verify(d, wallet_name)
    await go_back_to_wallet_list(d)
    await delete_wallet_from_list(d, wallet_name)
    print("    [PASS] compact format")


async def _test_three_lines_canonical(d: UIDriver):
    """Test 2: Three lines in canonical order (mfp, path, xpub)."""
    print("\n  [test 2] three lines canonical order")
    wallet_name = "Reg41-Canonical"
    await _open_guided_wallet(d, wallet_name)
    await _add_key_via_manual_entry(d, compact=False)
    await _create_wallet_and_verify(d, wallet_name)
    await go_back_to_wallet_list(d)
    await delete_wallet_from_list(d, wallet_name)
    print("    [PASS] three lines canonical")


async def _test_three_lines_shuffled(d: UIDriver):
    """Test 3: Three tokens out of order (xpub, mfp, path)."""
    print("\n  [test 3] three tokens shuffled order")
    wallet_name = "Reg41-Shuffled"
    await _open_guided_wallet(d, wallet_name)
    await click_label(d, "Add key", delay=0.5)
    await open_watch_only_manual_entry(d)

    shuffled_value = f"{_TEST_XPUB}\n{_TEST_MFP}\n{_TEST_PATH}"
    await fill_field(d, "[mfp/path]xpub", shuffled_value)
    await click_label(d, "Confirm", delay=0.8)

    await wait_for(d, _TEST_MFP.lower(), "Key card with MFP visible",
                   retries=15, delay=0.5)
    await wait_absent(d, "Watch-only key", "Add-key sheet closed",
                      retries=15, delay=0.5)
    print(f"    [ok] key card verified for MFP {_TEST_MFP}")

    await _create_wallet_and_verify(d, wallet_name)
    await go_back_to_wallet_list(d)
    await delete_wallet_from_list(d, wallet_name)
    print("    [PASS] three tokens shuffled")


async def _test_invalid_format(d: UIDriver):
    """Test 4: Invalid input — should show error, sheet stays open."""
    print("\n  [test 4] invalid format")
    await navigate_wallets(d)
    await click_tooltip(d, "New", delay=0.5)
    await wait_for(d, "Guided creation", "Bottom sheet opened",
                   retries=10, delay=0.5)
    await click_label(d, "Guided creation", delay=0.5)
    await wait_for(d, '"New Wallet"', "Guided creation screen opened",
                   retries=10, delay=0.5)
    await click_label(d, "Add key", delay=0.5)
    await open_watch_only_manual_entry(d)

    # Two tokens only (no xpub) — should fail parsing
    invalid_value = f"{_TEST_MFP}\n{_TEST_PATH}"
    await fill_field(d, "[mfp/path]xpub", invalid_value)
    await click_label(d, "Confirm", delay=0.8)
    await _verify_error_on_sheet(d)
    print("    [PASS] invalid format rejected")


# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------

async def test_manual_keyspec(d: UIDriver):
    """Run all manual keyspec parser tests."""
    print(f"\n--- Regression 41: Manual keyspec entry parser ---")

    await _test_compact_format(d)
    await _test_three_lines_canonical(d)
    await _test_three_lines_shuffled(d)
    await _test_invalid_format(d)

    print(f"\n{'='*50}")
    print("[RESULT] PASS — all 4 manual keyspec parser tests OK")


if __name__ == "__main__":
    asyncio.run(run_regression(test_manual_keyspec, "reg41"))
