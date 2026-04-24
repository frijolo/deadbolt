#!/usr/bin/env python3
"""
Regression test 21: Wallet lifecycle management.

Covers two flows not tested elsewhere:

  Phase 1 — Delete project after create wallet:
    Create a project → open project detail → create wallet with the
    "Delete this project after creating the wallet" checkbox enabled →
    verify the wallet appears in the wallet list → verify the project is
    gone from the designer list → delete wallet.

  Phase 2 — Direct "From descriptor" wallet creation (wallet list):
    Wallet list → New → From descriptor → fill descriptor + wallet name →
    create wallet → verify wallet detail loads → delete wallet.

Neither flow has previously been covered by any regression test.

Gaps covered:
  - "Delete this project after creating the wallet" checkbox in CreateWalletDialog
  - Project auto-delete after wallet creation verified in designer list
  - Direct wallet creation from descriptor (no project) via wallet list New sheet

Exit code: 0 = PASS, 1 = FAIL.

Prerequisites:
  bash scripts/prepare_test_build.sh
  python3 scripts/regression_21_wallet_lifecycle.py
"""

import asyncio
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from ui_driver import UIDriver                          # noqa: E402
from regression_helpers import (                       # noqa: E402
    wait_for, wait_absent,
    navigate_designer, navigate_wallets,
    click_label, click_tooltip, fill_field,
    click_popup_item,
    create_project, go_back,
    go_back_to_wallet_list, delete_wallet_from_list,
    set_active_network_signet, run_regression,
    dismiss_startup_dialogs,
)


# ---------------------------------------------------------------------------
# Test data
# ---------------------------------------------------------------------------

PROJECT_NAME  = "Reg21-WPKH-Project"
WALLET_NAME_1 = "Reg21-Wallet-From-Project"
WALLET_NAME_2 = "Reg21-Wallet-From-Descriptor"

# Native segwit singlesig (signet) — same key as reg04/reg06 test wallets.
# mnemonic: piece blue stadium control fiction kick group mimic hollow dog mask interest
DESCRIPTOR = (
    "wpkh([ff81be5d/84h/1h/0h]"
    "tpubDDjVt7cey7cxQ1nXzxpXuNT5vJecpvtMhmZywA9U9ChWDk8z6HSGPJ7YS6pyd8ZXQyfCeUCXrkyEqNeTFUmpdXT9r3TD1DAYoY52UEyy1Yf"
    "/<0;1>/*)"
)

# Same descriptor as phase 1 — phase 1 wallet is deleted before phase 2 starts,
# so the same descriptor can be reused without conflict.
DESCRIPTOR_2 = DESCRIPTOR


# ---------------------------------------------------------------------------
# Phase 1: Delete project after create wallet
# ---------------------------------------------------------------------------

async def phase1_delete_project_after_create(d):
    print("\n  [phase 1] Delete-project-after-create-wallet checkbox")

    # create_project ends on the ProjectDetailScreen for PROJECT_NAME
    await create_project(d, PROJECT_NAME, DESCRIPTOR)

    # Open create-wallet dialog from project detail
    await click_popup_item(d, "More options", 72, "Create wallet")
    await wait_for(d, '"New Wallet"', "Create wallet dialog opened", retries=10, delay=0.6)

    # Override the pre-filled project name with the test wallet name
    await fill_field(d, "Wallet name", WALLET_NAME_1)

    # Enable "Delete this project after creating the wallet" checkbox
    await click_label(d, "Delete this project after creating the wallet", delay=0.5)
    print("    [ok] delete-project checkbox enabled")

    # Submit
    await click_label(d, "Create wallet", delay=0.5)

    # Wait for wallet detail to load (BDK init + sync can take several seconds)
    await wait_for(
        d, '"Receive"',
        f"Wallet detail loaded: '{WALLET_NAME_1}'",
        retries=30, delay=1.0,
    )
    await wait_for(d, f'"{WALLET_NAME_1}"', "Wallet name in AppBar")
    print(f"    [ok] wallet '{WALLET_NAME_1}' created")

    # WalletDetailScreen was pushed on top of WalletListScreen —
    # press Back to reach the list before the drawer becomes available.
    await go_back_to_wallet_list(d)

    # Navigate to Designer and verify project is gone
    await navigate_designer(d)
    await wait_absent(d, f'"{PROJECT_NAME}"', f"Project '{PROJECT_NAME}' auto-deleted")
    print(f"    [ok] project '{PROJECT_NAME}' deleted automatically")

    # Navigate to Wallets and clean up
    await navigate_wallets(d)
    await delete_wallet_from_list(d, WALLET_NAME_1)
    print("  [phase 1] PASS")


# ---------------------------------------------------------------------------
# Phase 2: Direct "From descriptor" wallet creation via wallet list
# ---------------------------------------------------------------------------

async def phase2_wallet_from_descriptor(d):
    print("\n  [phase 2] Direct wallet creation from descriptor (wallet list → New)")

    await navigate_wallets(d)
    await wait_for(d, '"Wallets"', "On wallet list")

    # Open the create-mode bottom sheet
    await click_tooltip(d, "New", delay=0.5)
    await wait_for(d, "From descriptor", "Create mode sheet opened", retries=8, delay=0.5)

    # Select "From descriptor"
    await click_label(d, "From descriptor", delay=0.5)
    await wait_for(d, '"New Wallet"', "New Wallet screen opened", retries=10, delay=0.6)

    # Fill wallet name and descriptor
    await fill_field(d, "Wallet name", WALLET_NAME_2)
    await fill_field(d, "Descriptor", DESCRIPTOR_2)

    # Submit
    await click_label(d, "Create wallet", delay=0.5)

    # Wait for wallet detail
    await wait_for(
        d, '"Receive"',
        f"Wallet detail loaded: '{WALLET_NAME_2}'",
        retries=30, delay=1.0,
    )
    await wait_for(d, f'"{WALLET_NAME_2}"', "Wallet name in AppBar")
    print(f"    [ok] wallet '{WALLET_NAME_2}' created from descriptor")

    # Clean up
    await go_back_to_wallet_list(d)
    await delete_wallet_from_list(d, WALLET_NAME_2)
    print("  [phase 2] PASS")


# ---------------------------------------------------------------------------
# Main test
# ---------------------------------------------------------------------------

async def test_reg21(d):
    await set_active_network_signet(d)
    await phase1_delete_project_after_create(d)
    await phase2_wallet_from_descriptor(d)


if __name__ == "__main__":
    asyncio.run(run_regression(test_reg21, "reg21"))
