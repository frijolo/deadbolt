#!/usr/bin/env python3
"""
Regression test 10: Hot key (signing key) management in wallet detail.

Tests adding a mnemonic-based signing key to a watch-only wallet key slot,
verifying the HOT badge appears, then removing it.

Flow:
  1. Create project (wpkh singlesig, known MFP 5436d724)
  2. Create wallet from project (Device Key protection, no password)
  3. Navigate to Descriptor tab → Keys (1) sub-tab
  4. Tap the "Add private key" button below the keys list → addPrivateKeySheet
     opens directly on the hot-sources picker (walletMode)
  5. Enter test mnemonic → 24/24 word count confirmed; banner shows the seed
     will be attached to the (only) watch-only key in the wallet
  6. Confirm → HOT badge visible on key card
  7. Open key card → key_edit_sheet shows "Delete stored seed" button
  8. Click "Delete stored seed" → confirm dialog → "Delete seed" → HOT badge gone

Prerequisites:
  bash scripts/prepare_test_build.sh
  python3 scripts/regression_10_hot_keys.py
"""

import asyncio
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from ui_driver import UIDriver                          # noqa: E402
from regression_helpers import (                       # noqa: E402
    wait_for, wait_absent,
    click_label,
    dismiss_startup_dialogs,
    fill_field,
    create_project,
    create_wallet_from_project, run_regression,
)


# ---------------------------------------------------------------------------
# Test data
# ---------------------------------------------------------------------------

PROJECT_NAME = "Reg10-HotKey-Project"
WALLET_NAME  = "Reg10-HotKey-Wallet"

# wpkh singlesig descriptor for the standard BIP39 test mnemonic
# (abandon×23 + art, 24 words). MFP = 5436d724.
DESCRIPTOR = (
    "wpkh([5436d724/84h/1h/0h]"
    "tpubDCWivZp6qaqCALCt8MyLqAb3awnWm4hfbBPjdZqirYFXYeZ5YsfbWVaPacULZTGtK1RPBSZ92UWNjnhL4fB9UVrF2FjgW8cgmBjxPBmB4iB"
    "/<0;1>/*)"
)

MNEMONIC = (
    "abandon abandon abandon abandon abandon abandon abandon abandon "
    "abandon abandon abandon abandon abandon abandon abandon abandon "
    "abandon abandon abandon abandon abandon abandon abandon art"
)

EXPECTED_MFP     = "5436d724"
EXPECTED_MFP_UP  = EXPECTED_MFP.upper()   # KeyCard title when label is absent


# ---------------------------------------------------------------------------
# Test function
# ---------------------------------------------------------------------------

async def test_hot_keys(d: UIDriver):
    print(f"\n--- {WALLET_NAME} ---")

    # 1. Create project (lands on ProjectDetailScreen)
    await create_project(d, PROJECT_NAME, DESCRIPTOR)

    # 2. Create wallet (device key — no password overhead)
    await create_wallet_from_project(d, WALLET_NAME, protection="device_key")

    if await d.cs_find_by_label(WALLET_NAME) is None:
        raise AssertionError(f"Wallet name '{WALLET_NAME}' not in AppBar after creation")
    print(f"    [ok] wallet detail opened: '{WALLET_NAME}'")

    # 3. Navigate to Descriptor tab via bottom NavigationBar
    await click_label(d, "Descriptor", delay=1.5)
    # Tab label in semantics is "Keys (1)\nTab 2 of 3" — search without closing quote
    await wait_for(d, 'Keys (1', "Keys (1) sub-tab visible", retries=20, delay=0.8)
    print("    [ok] Descriptor tab analysis complete — sub-tabs visible")

    # 4. Click the Keys (1) sub-tab
    await click_label(d, "Keys (1)", delay=0.6)
    if await d.cs_find_by_label("HOT") is not None:
        raise AssertionError("HOT badge already present — sandbox not clean")
    print("    [ok] Keys sub-tab active — no HOT badge (expected)")

    # 5. Click the "Add private key" button below the keys list
    #    → opens addPrivateKeySheet directly on hotSources picker (walletMode).
    #    The destination key is inferred from the seed's MFP, so no key card
    #    has to be tapped first.
    await wait_for(d, '"Add private key"', "Add private key button visible",
                   retries=8, delay=0.5)
    await click_label(d, "Add private key", delay=1.2)
    await wait_for(d, '"Enter existing mnemonic"', "addPrivateKeySheet hotSources picker visible",
                   retries=8, delay=0.5)
    await click_label(d, "Enter existing mnemonic", delay=0.6)
    # The seed form renders a MnemonicEntryField which shows "Seed phrase" label
    await wait_for(d, '"Seed phrase"', "addPrivateKeySheet SeedTab visible",
                   retries=8, delay=0.5)
    print("    [ok] addPrivateKeySheet opened (mnemonic form visible)")

    # 7a. Switch to 24-word mode so the counter shows 24/24 after paste
    await click_label(d, "24", delay=0.4)

    # 7b. Enter mnemonic via clipboard paste (fill_field uses xclip + Ctrl+V)
    await fill_field(d, "word1 word2 word3 ...", MNEMONIC)

    # Wait for Rust BIP39 validation (debounce 250 ms + key derivation ~1-2 s)
    await asyncio.sleep(3.5)
    tree = await d.cs_flat_text()
    if "24 / 24" not in tree:
        raise AssertionError("Mnemonic not validated — '24 / 24' not found in widget tree")
    print("    [ok] mnemonic validated: 24/24 words")

    # 8. Confirm — the sheet title and the FilledButton share the label
    #    "Add private key"; cs_find_all_by_label returns both, the button
    #    is always last in the tree (bottom of the sheet).
    rects = await d.cs_find_all_by_label("Add private key")
    if not rects:
        raise AssertionError("Confirm button 'Add private key' not found in semantics")
    btn_rect = rects[-1]
    cx = (btn_rect[0] + btn_rect[2]) // 2
    cy = (btn_rect[1] + btn_rect[3]) // 2
    d.flutter_click(cx, cy)
    await asyncio.sleep(1.5)

    # Sheet closes; WalletDetailCubit.addMnemonicKey stores the hot key;
    # WalletKeysTab rebuilds with HOT badge on the key card.
    # The badge text "HOT" appears within a multi-line semantics label — match
    # without surrounding quotes.
    await wait_for(d, 'HOT', "HOT badge visible after key added",
                   retries=15, delay=0.8)
    print("    [ok] HOT badge visible — signing key added ✓")

    # 9. Tap the key card again → key_edit_sheet with private-key section visible
    await click_label(d, EXPECTED_MFP_UP, delay=0.6)
    await wait_for(d, '"Delete stored seed"', "key_edit_sheet: delete button visible",
                   retries=8, delay=0.5)
    print("    [ok] key_edit_sheet opened — 'Delete stored seed' visible")

    # 10. Click "Delete stored seed" → confirmation AlertDialog
    await click_label(d, "Delete stored seed", delay=0.6)
    # Dialog title is also "Delete stored seed"; the confirm button is "Delete seed"
    await wait_for(d, '"Delete stored seed"', "confirmation dialog visible",
                   retries=6, delay=0.5)

    # 11. Confirm deletion ("Delete seed" = deletePrivateKeyConfirm i18n key)
    await click_label(d, "Delete seed", delay=1.5)

    # Dialog and sheet close; cubit deletes the hot key; HOT badge disappears
    await wait_absent(d, 'HOT', "HOT badge gone — key removed", retries=12, delay=0.5)
    print("    [ok] HOT badge gone — signing key removed ✓")

    print(f"\n    [PASS] {WALLET_NAME}")


# ---------------------------------------------------------------------------
# Entry point
# ---------------------------------------------------------------------------

if __name__ == "__main__":
    asyncio.run(run_regression(test_hot_keys, "reg10"))
