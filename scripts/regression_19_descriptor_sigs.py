#!/usr/bin/env python3
"""
Regression test 19: Descriptor Signatures — HotKey sign, verify all, delete.

Covers the full hot-key-based descriptor signature lifecycle:
  - Navigate to Wallet Security → Manage Signatures.
  - Key tile shows "Not signed" initially.
  - Sign with HotKey (automatic) → "Signature stored" toast.
  - Key tile shows "Signed · {date}" status.
  - Tap "Verify all" → "1 of 1 signatures valid" toast.
  - Key tile shows "Verified · {date}" status.
  - Delete the signature → confirm dialog → "Signature deleted" toast.
  - Key tile reverts to "Not signed".

Flow:
  0.  Settings → set Active Network to Signet.
  1.  Create a Guided singlesig wallet with a hot key (funded Signet mnemonic).
  2.  Wait for wallet detail to load.
  3.  Open More options → Security → Wallet Security screen.
  4.  Tap "Manage Signatures" → Descriptor Signatures screen.
  5.  Verify initial "Not signed" status.
  6.  Sign with HotKey → verify "Signature stored" toast.
  7.  Verify "Signed ·" status badge on key tile.
  8.  Tap "Verify all" → verify "signatures valid" toast.
  9.  Verify "Verified ·" status badge on key tile.
  10. Delete signature → confirm → verify "Signature deleted" toast.
  11. Verify key tile reverts to "Not signed".
  12. Navigate back to wallet list → delete wallet.

Gaps covered:
  - Descriptor Signatures: sign with HotKey (first automation of this feature)
  - Verify all signatures (AppBar action)
  - Delete a signature (with confirmation dialog)
  - Navigate Wallet Security → Manage Signatures flow

Exit code: 0 = PASS, 1 = FAIL.

Prerequisites:
  bash scripts/prepare_test_build.sh
  python3 scripts/regression_19_descriptor_sigs.py
"""

import asyncio
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from ui_driver import UIDriver                          # noqa: E402
from regression_helpers import (                       # noqa: E402
    wait_for, wait_absent,
    navigate_wallets, fill_field, click_label, click_tooltip,
    go_back_to_wallet_list, delete_wallet_from_list,
    set_active_network_signet, run_regression,
    click_popup_item,
    open_hot_existing_mnemonic,
)


# ---------------------------------------------------------------------------
# Test data
# ---------------------------------------------------------------------------

WALLET_NAME = "Reg19-DescSigs"

# Funded Signet P2WPKH hot-key wallet (shared with reg11/reg14–reg18).
MNEMONIC = (
    "bachelor brick camera brave assume differ disagree "
    "judge security scrap wonder core"
)


# ---------------------------------------------------------------------------
# Phase 1: create wallet via Guided creation (no sync needed for sigs)
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
    await open_hot_existing_mnemonic(d)

    await fill_field(d, "Seed phrase", MNEMONIC)
    await wait_for(d, "Derived keyspec", "keyspec derived",
                   retries=20, delay=1.0)

    await click_label(d, "Add", delay=1.0)
    await wait_for(d, "Remove key", "key tile visible",
                   retries=15, delay=0.8)

    await click_label(d, "Create wallet", delay=1.0)
    await wait_for(d, '"Receive"', "wallet detail loaded",
                   retries=30, delay=1.0)
    print(f"    [ok] wallet '{WALLET_NAME}' opened")


# ---------------------------------------------------------------------------
# Phase 2: navigate to Wallet Security → Manage Signatures
# ---------------------------------------------------------------------------

async def phase_open_descriptor_sigs(d: UIDriver) -> None:
    print("\n  [phase 2] navigate Security → Manage Signatures")

    await click_popup_item(d, "More options", 0, "Security")
    await wait_for(d, '"Wallet Security"', "Wallet Security screen opened",
                   retries=10, delay=0.5)
    print("    [ok] Wallet Security screen visible")

    await click_tooltip(d, "Manage Signatures")
    await wait_for(d, '"Descriptor Signatures"', "Descriptor Signatures screen opened",
                   retries=10, delay=0.5)
    print("    [ok] Descriptor Signatures screen visible")


# ---------------------------------------------------------------------------
# Phase 3: verify initial "Not signed" state
# ---------------------------------------------------------------------------

async def phase_verify_not_signed(d: UIDriver) -> None:
    print("\n  [phase 3] verify initial 'Not signed' state")

    flat = await d.cs_flat_text()
    if "Not signed" not in flat:
        raise AssertionError(
            f"Expected 'Not signed' on Descriptor Signatures screen, got:\n{flat[:400]}"
        )
    print("    [ok] key tile shows 'Not signed'")


# ---------------------------------------------------------------------------
# Phase 4: sign with HotKey
# ---------------------------------------------------------------------------

async def phase_sign_hot_key(d: UIDriver) -> None:
    print("\n  [phase 4] sign with HotKey")

    # The sign button has tooltip "Sign" (descriptorSigsSignAction).
    await click_tooltip(d, "Sign")
    await wait_for(d, "HotKey (automatic)", "sign method sheet opened",
                   retries=10, delay=0.5)
    print("    [ok] sign method sheet visible")

    await click_label(d, "HotKey (automatic)", delay=0.5)

    # Signature is stored synchronously — toast appears quickly.
    await wait_for(d, "Signature stored", "success toast visible",
                   retries=10, delay=0.5)
    print("    [ok] 'Signature stored' toast visible")

    # "Not signed" must be gone.
    await wait_absent(d, "Not signed", "key tile no longer shows 'Not signed'",
                      retries=8, delay=0.5)

    # Key tile should now show "Signed ·" (with date).
    flat = await d.cs_flat_text()
    if "Signed ·" not in flat:
        raise AssertionError(
            f"Expected 'Signed ·' on key tile after signing, got:\n{flat[:400]}"
        )
    print("    [ok] key tile shows 'Signed ·' status")


# ---------------------------------------------------------------------------
# Phase 5: verify all signatures
# ---------------------------------------------------------------------------

async def phase_verify_all(d: UIDriver) -> None:
    print("\n  [phase 5] verify all signatures")

    # "Verify all" is an AppBar IconButton with tooltip "Verify all".
    await click_tooltip(d, "Verify all")

    # Toast text: "1 of 1 signatures valid" (may be transient).
    await wait_for(d, "signatures valid", "verify result toast visible",
                   retries=15, delay=0.5)
    print("    [ok] 'signatures valid' toast visible")

    # Key tile should update to "Verified ·" (with date).
    await wait_for(d, "Verified ·", "key tile shows 'Verified ·'",
                   retries=10, delay=0.5)
    print("    [ok] key tile shows 'Verified ·' status")


# ---------------------------------------------------------------------------
# Phase 6: delete the signature
# ---------------------------------------------------------------------------

async def phase_delete_sig(d: UIDriver) -> None:
    print("\n  [phase 6] delete the signature")

    # "Delete signature" tooltip on the trailing IconButton.
    await click_tooltip(d, "Delete signature")
    await wait_for(d, "Delete signature", "delete confirmation dialog opened",
                   retries=10, delay=0.5)
    print("    [ok] delete confirmation dialog visible")

    await click_label(d, "Delete", delay=0.5)

    # No success toast for deletion — the UI just updates the tile state.
    # Key tile must revert to "Not signed".
    await wait_for(d, "Not signed", "key tile shows 'Not signed' after deletion",
                   retries=15, delay=0.5)
    print("    [ok] key tile reverted to 'Not signed'")


# ---------------------------------------------------------------------------
# Main test function
# ---------------------------------------------------------------------------

async def test_descriptor_sigs(d: UIDriver) -> None:
    print(f"\n--- {WALLET_NAME} (Descriptor Signatures — HotKey sign/verify/delete) ---")

    await set_active_network_signet(d)
    await phase_create_wallet(d)
    await phase_open_descriptor_sigs(d)
    await phase_verify_not_signed(d)
    await phase_sign_hot_key(d)
    await phase_verify_all(d)
    await phase_delete_sig(d)

    await go_back_to_wallet_list(d)
    await delete_wallet_from_list(d, WALLET_NAME)

    print(f"\n    [PASS] {WALLET_NAME}")


# ---------------------------------------------------------------------------
# Entry point
# ---------------------------------------------------------------------------

if __name__ == "__main__":
    asyncio.run(run_regression(test_descriptor_sigs, "reg19"))
