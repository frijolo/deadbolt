#!/usr/bin/env python3
"""
Regression test 22: Wallet list card operations.

Covers two flows not tested elsewhere:

  Phase 1 — Lock from wallet list card PopupMenu:
    Create password wallet → open (unlock) → go back to list →
    open card popup → verify "Lock wallet" item present (unlocked) →
    click "Lock wallet" → verify locked state (popup lacks "Lock wallet"
    and "Sync wallet" items) → tap card → password prompt appears →
    enter password → wallet detail reloads.

  Phase 2 — Manual sync from wallet list card menu:
    Go back to list → popup → "Sync wallet" → wait → verify "Last synced"
    text present on card, no error toast.

Gaps covered:
  - Lock wallet via wallet list card PopupMenu (different code path from
    wallet-detail lock in reg05/reg12: evictPassword + untrack vs detail menu)
  - Verify locked wallet card state via popup item visibility in semantics
  - Verify "Lock wallet" item absent when locked, "Sync wallet" absent when locked
  - Manual sync trigger from wallet list card menu

Exit code: 0 = PASS, 1 = FAIL.

Prerequisites:
  bash scripts/prepare_test_build.sh
  python3 scripts/regression_22_wallet_list_ops.py
"""

import asyncio
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from ui_driver import UIDriver                          # noqa: E402
from regression_helpers import (                       # noqa: E402
    wait_for, wait_absent,
    navigate_wallets,
    click_label,
    fill_field,
    create_project,
    create_wallet_from_project,
    open_wallet_from_list,
    unlock_wallet,
    go_back_to_wallet_list,
    delete_wallet_from_list,
    set_active_network_signet,
    run_regression,
    assert_no_error_toast,
)


# ---------------------------------------------------------------------------
# Test data
# ---------------------------------------------------------------------------

PROJECT_NAME = "Reg22-WPKH-Project"
WALLET_NAME  = "Reg22-LockFromList"
PASSWORD     = "reg22-test-password"

# Native segwit singlesig (signet) — same descriptor as reg05/reg06/reg21.
# mnemonic: piece blue stadium control fiction kick group mimic hollow dog mask interest
DESCRIPTOR = (
    "wpkh([ff81be5d/84h/1h/0h]"
    "tpubDDjVt7cey7cxQ1nXzxpXuNT5vJecpvtMhmZywA9U9ChWDk8z6HSGPJ7YS6pyd8ZXQyfCeUCXrkyEqNeTFUmpdXT9r3TD1DAYoY52UEyy1Yf"
    "/<0;1>/*)"
)


# ---------------------------------------------------------------------------
# Phase 1: Lock from wallet list card PopupMenu
# ---------------------------------------------------------------------------

async def phase1_lock_from_list(d):
    print("\n  [phase 1] Lock wallet from wallet list card PopupMenu")

    # Setup: create project → create password wallet.
    await create_project(d, PROJECT_NAME, DESCRIPTOR)
    await create_wallet_from_project(
        d, WALLET_NAME, protection="password", password=PASSWORD,
    )

    # After creation the wallet detail is open and session is active (unlocked).
    await wait_for(d, '"Receive"', "Wallet detail loaded", retries=30, delay=1.0)
    await wait_for(d, f'"{WALLET_NAME}"', "Wallet name in AppBar")
    print(f"    [ok] wallet '{WALLET_NAME}' created and unlocked")

    # Return to wallet list.
    await go_back_to_wallet_list(d)

    # --- Verify popup shows "Lock wallet" while session is active ---------------
    rect = await d.cs_find_by_tooltip("More options")
    if rect is None:
        raise AssertionError("'More options' button not found on wallet card")
    d.flutter_click((rect[0] + rect[2]) // 2, (rect[1] + rect[3]) // 2, delay_s=0.5)
    await asyncio.sleep(0.8)

    flat = await d.cs_flat_text()
    if '"Lock wallet"' not in flat:
        raise AssertionError(
            "Expected 'Lock wallet' in popup when session is active, but it was absent"
        )
    print("    [ok] popup shows 'Lock wallet' → wallet session is active (unlocked)")

    # --- Click "Lock wallet" (popup is still open) ------------------------------
    item_rect = await d.cs_find_by_label("Lock wallet")
    if item_rect is None:
        raise AssertionError("'Lock wallet' item not found in popup — cannot lock")
    d.flutter_click(
        (item_rect[0] + item_rect[2]) // 2,
        (item_rect[1] + item_rect[3]) // 2,
    )
    await asyncio.sleep(1.0)
    print("    [ok] 'Lock wallet' clicked — session evicted")

    # --- Verify locked state: popup must NOT contain "Lock wallet" or "Sync wallet" ---
    rect2 = await d.cs_find_by_tooltip("More options")
    if rect2 is None:
        raise AssertionError("'More options' button not found after locking")
    d.flutter_click(
        (rect2[0] + rect2[2]) // 2, (rect2[1] + rect2[3]) // 2, delay_s=0.5
    )
    await asyncio.sleep(0.8)

    flat_locked = await d.cs_flat_text()
    if '"Lock wallet"' in flat_locked:
        raise AssertionError(
            "'Lock wallet' still visible in popup after lock-from-list — wallet not locked"
        )
    if '"Sync wallet"' in flat_locked:
        raise AssertionError(
            "'Sync wallet' still visible in popup after lock-from-list — wallet not locked"
        )
    print("    [ok] popup has no 'Lock wallet' or 'Sync wallet' → wallet is locked")

    # Close popup.
    d.key("Escape")
    await asyncio.sleep(0.5)

    # --- Open wallet → password prompt must appear --------------------------------
    await open_wallet_from_list(d, WALLET_NAME)
    await wait_for(
        d, '"Enter wallet password"',
        "Password prompt after lock-from-list",
        retries=10, delay=0.5,
    )
    print("    [ok] password prompt visible — lock-from-list confirmed")

    # --- Unlock and verify wallet detail reloads ----------------------------------
    await unlock_wallet(d, PASSWORD)
    await wait_for(d, '"Receive"', "Wallet detail after unlock", retries=30, delay=1.0)
    await wait_for(d, f'"{WALLET_NAME}"', "Wallet name in AppBar after unlock")
    print("    [ok] wallet unlocked successfully via lock-from-list flow")
    print("  [phase 1] PASS")


# ---------------------------------------------------------------------------
# Phase 2: Manual sync from wallet list card menu
# ---------------------------------------------------------------------------

async def phase2_sync_from_list(d):
    print("\n  [phase 2] Manual sync from wallet list card menu")

    await go_back_to_wallet_list(d)

    # Verify the wallet is unlocked (popup must show "Sync wallet").
    rect = await d.cs_find_by_tooltip("More options")
    if rect is None:
        raise AssertionError("'More options' button not found for sync phase")
    d.flutter_click((rect[0] + rect[2]) // 2, (rect[1] + rect[3]) // 2, delay_s=0.5)
    await asyncio.sleep(0.8)
    flat_pre = await d.cs_flat_text()
    if '"Sync wallet"' not in flat_pre:
        raise AssertionError(
            "Expected 'Sync wallet' in popup before triggering sync "
            "(wallet should be unlocked at this point)"
        )
    print("    [ok] 'Sync wallet' item present — triggering sync")

    # Click "Sync wallet".
    sync_rect = await d.cs_find_by_label("Sync wallet")
    if sync_rect is None:
        raise AssertionError("'Sync wallet' item not found in popup")
    d.flutter_click(
        (sync_rect[0] + sync_rect[2]) // 2,
        (sync_rect[1] + sync_rect[3]) // 2,
    )
    await asyncio.sleep(4.0)

    # After sync: "Last synced" subtitle should be present and no error toast.
    flat_post = await d.cs_flat_text()
    assert_no_error_toast(flat_post)
    if "Last synced" not in flat_post:
        raise AssertionError(
            "Expected 'Last synced' on wallet card after sync, but it was absent"
        )
    print("    [ok] sync completed — 'Last synced' visible, no error toast")
    print("  [phase 2] PASS")


# ---------------------------------------------------------------------------
# Main test
# ---------------------------------------------------------------------------

async def test_reg22(d):
    await set_active_network_signet(d)
    await phase1_lock_from_list(d)
    await phase2_sync_from_list(d)
    await go_back_to_wallet_list(d)
    await delete_wallet_from_list(d, WALLET_NAME)


if __name__ == "__main__":
    asyncio.run(run_regression(test_reg22, "reg22"))
