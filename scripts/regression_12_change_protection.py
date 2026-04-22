#!/usr/bin/env python3
"""
Regression test 12: Change wallet protection tier.

Tests changing protection from Device Key → Password → Device Key.

Flow:
   1. Create project (wpkh singlesig)
   2. Create wallet with Device Key protection
   3. Navigate to wallet detail → Overview tab
   4. Tap "Security" button → WalletSecurityScreen opens
   5. Tap edit button → enters edit mode
   6. Change protection to Password → enter new password → confirm
   7. Save → verify toast "Protection changed to Password"
   8. Lock wallet → go back to wallet list → reopen → verify password prompt
   9. Unlock with correct password → verify wallet detail loads
   10. Re-open Security screen → verify Password is still selected
   11. Change protection back to Device Key → save
   12. Verify toast "Protection changed to Unprotected" (toast uses Unprotected label)

Prerequisites:
   bash scripts/prepare_test_build.sh
   python3 scripts/regression_12_change_protection.py
"""

import asyncio
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from ui_driver import UIDriver                          # noqa: E402
from regression_helpers import (                       # noqa: E402
    wait_for, wait_absent,
    click_label, click_tooltip,
    fill_field,
    create_project, go_back,
    navigate_wallets,
    create_wallet_from_project,
    unlock_wallet, lock_wallet,
    open_wallet_from_list, run_regression,
    dismiss_startup_dialogs,
)


# ---------------------------------------------------------------------------
# Test data
# ---------------------------------------------------------------------------

PROJECT_NAME = "Reg12-Protection-Project"
WALLET_NAME  = "Reg12-Protection-Wallet"

DESCRIPTOR = (
    "wpkh([ff81be5d/84h/1h/0h]"
    "tpubDDjVt7cey7cxQ1nXzxpXuNT5vJecpvtMhmZywA9U9ChWDk8z6HSGPJ7YS6pyd8ZXQyfCeUCXrkyEqNeTFUmpdXT9r3TD1DAYoY52UEyy1Yf"
    "/<0;1>/*)"
)

PASSWORD = "test_password_123"


# ---------------------------------------------------------------------------
# Test function
# ---------------------------------------------------------------------------

async def test_change_protection(d: UIDriver):
    print(f"\n--- {WALLET_NAME} ---")

    # 1. Create project
    await create_project(d, PROJECT_NAME, DESCRIPTOR)

    # 2. Create wallet with Device Key protection (default)
    await create_wallet_from_project(d, WALLET_NAME, protection="device_key")

    # Verify wallet opened
    if await d.cs_find_by_label(WALLET_NAME) is None:
        raise AssertionError(f"Wallet name '{WALLET_NAME}' not in AppBar")
    print(f"    [ok] wallet detail opened: '{WALLET_NAME}'")

    # 3. Navigate to Overview tab (should already be there)
    await click_label(d, "Overview", delay=0.8)

    # 4. Tap "Security" button in the overview secondary grid
    # Security button has tooltip "Security" and icon "security"
    await click_label(d, "Security", delay=1.0)
    await wait_for(d, '"Change protection"', "WalletSecurityScreen opened")
    print("    [ok] Security screen opened")

    # 5. Tap edit button to enter edit mode
    # The edit button has tooltip "Change protection"
    await click_tooltip(d, "Change protection", delay=0.8)
    await wait_for(d, '"None"', "Edit mode: protection options visible")
    print("    [ok] Edit mode entered")

    # 6. Select "Password" option
    await click_label(d, "Password", delay=0.6)
    await wait_for(d, '"New password"', "Password fields visible", retries=8, delay=0.5)
    print("    [ok] Password option selected")

    # Enter new password and confirm
    await fill_field(d, "New password", PASSWORD)
    await fill_field(d, "Confirm password", PASSWORD)
    print("    [ok] Password entered")

    # 7. Save changes (button label "Change")
    await click_label(d, "Change", delay=2.0)

    # Wait for toast "Protection changed to Password"
    # Toast appears as a SnackBar with "Protection changed to Password"
    await wait_for(d, "Protection changed to Password", "Protection changed toast",
                   retries=20, delay=0.8)
    print("    [ok] Protection changed to Password ✓")

    # Wait for the Security screen to return to view mode
    await wait_for(d, '"Change protection"', "Returned to view mode", retries=10, delay=0.6)

    # 8. Lock wallet → go back → reopen → verify password prompt persists
    # Return to wallet detail first (we're still on WalletSecurityScreen)
    await go_back(d)
    await wait_for(d, f'"{WALLET_NAME}"', "Back on wallet detail", retries=8, delay=0.6)
    await lock_wallet(d)
    await asyncio.sleep(1.0)
    if await d.cs_find_by_label("Enter wallet password") is not None:
        print("    [ok] wallet locked: password prompt shown on detail screen")
        await go_back(d)
    elif await d.cs_find_by_label("Wallets") is not None:
        print("    [ok] wallet locked: navigated back to wallet list")
    else:
        raise AssertionError("After lock: neither password prompt nor wallet list visible")

    await wait_for(d, '"Wallets"', "On wallet list", retries=8, delay=0.6)
    await open_wallet_from_list(d, WALLET_NAME)
    await asyncio.sleep(1.5)
    if await d.cs_find_by_label("Enter wallet password") is None:
        raise AssertionError(
            "No password prompt after reopening wallet — re-encryption did not apply"
        )
    print("    [ok] password prompt shown after lock/reopen — re-encryption confirmed")

    # 9. Unlock with correct password → wallet detail must load
    await unlock_wallet(d, PASSWORD)
    await wait_for(d, f'"{WALLET_NAME}"', "Wallet detail loaded after unlock",
                   retries=25, delay=1.0)
    print("    [ok] wallet unlocked successfully with new password")

    # Navigate back to Overview tab for the Security screen check
    await click_label(d, "Overview", delay=0.8)
    await click_label(d, "Security", delay=1.0)
    await wait_for(d, '"Change protection"', "Security screen opened", retries=10, delay=0.6)

    # 10. Re-open Security screen to verify Password is selected
    await click_tooltip(d, "Change protection", delay=0.8)
    await wait_for(d, '"Password"', "Password still selected in edit mode")
    print("    [ok] Password protection confirmed")

    # Cancel to go back to view mode
    await click_label(d, "Cancel", delay=0.6)
    await wait_for(d, '"Change protection"', "Returned to view mode", retries=8, delay=0.5)

    # 11. Change protection back to Device Key (None)
    await click_tooltip(d, "Change protection", delay=0.8)
    await wait_for(d, '"None"', "Edit mode: None option visible")

    # Select "None" (Device Key)
    await click_label(d, "None", delay=0.6)
    print("    [ok] Selected None (Device Key)")

    # Save changes
    await click_label(d, "Change", delay=2.0)

    # 12. Wait for toast "Protection changed to Unprotected"
    await wait_for(d, "Protection changed to Unprotected", "Protection reverted toast",
                   retries=20, delay=0.8)
    print("    [ok] Protection changed back to Unprotected ✓")

    print(f"\n    [PASS] {WALLET_NAME}")


# ---------------------------------------------------------------------------
# Entry point
# ---------------------------------------------------------------------------

if __name__ == "__main__":
    asyncio.run(run_regression(test_change_protection, "reg12"))
