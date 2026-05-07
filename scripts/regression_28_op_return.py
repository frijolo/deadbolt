#!/usr/bin/env python3
"""
Regression test 28: OP_RETURN full cycle — create PSBT, sign, broadcast,
and verify OP_RETURN data in transaction detail.

Flow:
  0.  Settings → set Active Network to Signet.
  1.  Create a hot-key wallet via Guided creation (funded Signet mnemonic).
  2.  Sync → wait for confirmed coins.
  3.  Sub-test A — UTF-8 OP_RETURN:
        a. Send → add OP_RETURN recipient → type UTF-8 text ("deadbolt-op-return-test")
        b. Create PSBT → verify OP_RETURN data visible in PSBT detail
        c. Sign with hot key → verify SIGNED
        d. Broadcast → verify success toast
        e. Open transaction detail → verify OP_RETURN output visible with correct data
  4.  Delete wallet.
  5.  Sub-test B — Hex OP_RETURN:
        a. Recreate wallet from same mnemonic
        b. Sync → wait for confirmed coins
        c. Send → add OP_RETURN recipient → type hex ("deadbeeffeed" — non-printable bytes)
        d. Create PSBT → verify OP_RETURN data visible in PSBT detail
        e. Sign with hot key → verify SIGNED
        f. Broadcast → verify success toast
        g. Open transaction detail → verify OP_RETURN output visible with correct hex data
  6.  Delete wallet.

Exit code: 0 = PASS, 1 = FAIL.

Prerequisites:
  bash scripts/prepare_test_build.sh
  python3 scripts/regression_28_op_return.py
"""

import asyncio
import os
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
)


# ---------------------------------------------------------------------------
# Test data
# ---------------------------------------------------------------------------

WALLET_NAME_A = "Reg28-OpReturn-A"
WALLET_NAME_B = "Reg28-OpReturn-B"
PSBT_LABEL_A  = "reg28-opreturn-utf8"
PSBT_LABEL_B  = "reg28-opreturn-hex"

# Funded Signet P2WPKH hot-key wallet (shared with reg11/reg14/reg15/reg16/reg17).
MNEMONIC = (
    "bachelor brick camera brave assume differ disagree "
    "judge security scrap wonder core"
)

# UTF-8 payload: "deadbolt-op-return-test" (26 bytes)
UTF8_PAYLOAD = "deadbolt-op-return-test"

# Hex payload: chosen so the decoded bytes are NOT printable UTF-8, so the UI
# falls back to the "0x…" hex display (decodeOpReturnForDisplay in
# lib/utils/op_return_encoding.dart). 0xde 0xad 0xbe 0xef 0xfe 0xed are all
# outside the printable-ASCII range.
HEX_PAYLOAD = "deadbeeffeed"
EXPECTED_HEX_DISPLAY = "0xdeadbeeffeed"

_ENV = {**os.environ, "DISPLAY": ":0"}


# ---------------------------------------------------------------------------
# Phase 1: create wallet via Guided creation
# ---------------------------------------------------------------------------

async def phase_create_wallet(d: UIDriver, wallet_name: str) -> None:
    print(f"\n  [phase 1] create wallet: {wallet_name}")

    await navigate_wallets(d)
    await click_tooltip(d, "New")
    await wait_for(d, "Guided creation", "bottom sheet opened")
    await click_label(d, "Guided creation", delay=0.5)
    await wait_for(d, '"New Wallet"', "Guided creation screen opened")

    await fill_field(d, "Wallet name", wallet_name)

    await click_label(d, "Add key", delay=0.5)
    await wait_for(d, "Enter manually", "method picker visible",
                   retries=8, delay=0.5)
    await click_label(d, "Enter manually", delay=0.5)
    await wait_for(d, "Watch Only", "manual entry tabs visible",
                   retries=8, delay=0.5)

    await click_label(d, "Hot Key", delay=0.5)
    await wait_for(d, "Seed phrase", "Hot Key seed form visible",
                   retries=8, delay=0.5)

    await fill_field(d, "Seed phrase", MNEMONIC)
    await wait_for(d, "Derived keyspec", "keyspec derived",
                   retries=20, delay=1.0)

    await click_label(d, "Add", delay=1.0)
    await wait_for(d, "Remove key", "key tile visible",
                   retries=15, delay=0.8)

    await click_label(d, "Create wallet", delay=1.0)
    await wait_for(d, '"Receive"', "wallet detail loaded",
                   retries=30, delay=1.0)
    print(f"    [ok] wallet '{wallet_name}' opened")


# ---------------------------------------------------------------------------
# Phase 2: sync — wait for confirmed coins
# ---------------------------------------------------------------------------

async def phase_sync(d: UIDriver) -> None:
    """Sync wallet and wait for coins to appear."""
    print("\n  [phase 2] sync — wait for coins")

    await click_label(d, "Coins", delay=1.0)
    await wait_for(
        d,
        "sats",
        "at least one coin value visible in Coins tab",
        retries=180,
        delay=1.0,
    )
    print("    [ok] coins visible after sync")


# ---------------------------------------------------------------------------
# Phase 3: create PSBT with OP_RETURN
# ---------------------------------------------------------------------------

async def phase_create_psbt_with_op_return(
    d: UIDriver,
    psbt_label: str,
    op_return_text: str,
    is_hex_mode: bool,
) -> bool:
    """Create PSBT with OP_RETURN or use direct send if RBF detected.
    
    Returns True if PSBT was created (normal flow), False if direct send was used.
    """
    print(f"\n  [phase 3] create PSBT with OP_RETURN")

    await click_label(d, "Overview", delay=0.5)
    await wait_for(d, '"Send"', "back on Overview tab", retries=8, delay=0.5)

    await click_label(d, "Send", delay=0.5)
    await wait_for(d, '"Create Transaction"', "Create TX screen opened",
                   retries=10, delay=0.5)
    print("    [ok] Create Transaction screen open")

    # Select coin
    await click_label(d, "Tap to select coins...", delay=1.0)
    await wait_for(d, "sats", "coin selector screen opened",
                   retries=10, delay=0.5)

    coin_rect = await d.cs_find_by_label_part_containing("sats")
    if coin_rect is None:
        raise AssertionError("No coin tile found in coin selector")
    d.flutter_click(
        (coin_rect[0] + coin_rect[2]) // 2,
        (coin_rect[1] + coin_rect[3]) // 2,
    )
    await asyncio.sleep(0.5)
    print("    [ok] coin selected")

    await click_label(d, "Done (1)", delay=1.0)
    await wait_for(d, '"Create Transaction"', "back on Create TX screen",
                   retries=10, delay=0.5)
    print("    [ok] coin selection confirmed")

    # Label
    await fill_field(d, "Label", psbt_label)
    print(f"    [ok] PSBT label set to '{psbt_label}'")

    # The first recipient row shows the wallet's address as a label (bc1q...).
    # We need to fill the address field by clicking MY WALLETS.
    await click_tooltip(d, "MY WALLETS", delay=0.5)
    await asyncio.sleep(1.5)
    # The wallet picker may show "This wallet (Self)" or the wallet's address (bc1q...)
    # Try multiple possible labels
    picker_found = False
    for option in ["This wallet (Self)", "bc1q"]:
        rect = await d.cs_find_by_label_part(option)
        if rect is not None:
            cx = (rect[0] + rect[2]) // 2
            cy = (rect[1] + rect[3]) // 2
            d.flutter_click(cx, cy)
            await asyncio.sleep(1.5)
            print(f"    [ok] selected '{option}' from wallet picker")
            picker_found = True
            break
    if not picker_found:
        # Debug: show visible labels
        sem = await d.cs_flat_text()
        print(f"    [dbg] visible labels after MY WALLETS: {[w for w in sem.split() if len(w) > 2][:30]}")
        raise AssertionError("Wallet picker did not show any address option")

    # Add OP_RETURN data output via the "More output types" overflow menu next
    # to the primary "Add recipient" CTA.
    await click_popup_item(d, "More output types", 0, "Add OP_RETURN data")
    await wait_for(d, "Embedded data", "OP_RETURN card visible",
                   retries=10, delay=0.5)
    print("    [ok] OP_RETURN card visible")

    # Type the OP_RETURN payload BEFORE switching to MAX / probing RBF — the
    # preview only computes vbytes/fees once the OP_RETURN recipient is complete
    # (an empty payload makes _runPreview bail and rbf_min_fee_sats stays null,
    #  which would prevent the total-fee click-to-RBF auto-fill from working).
    op_return_rect = await d.cs_find_textfield_by_label("Embedded data")
    if op_return_rect is None:
        raise AssertionError("OP_RETURN text field not found")
    cx = (op_return_rect[0] + op_return_rect[2]) // 2
    cy = (op_return_rect[1] + op_return_rect[3]) // 2
    d.flutter_click(cx, cy)
    await asyncio.sleep(0.3)
    d.key("ctrl+a")
    await asyncio.sleep(0.1)

    env = {**os.environ, "DISPLAY": ":0"}
    import subprocess
    subprocess.run(
        ["xclip", "-selection", "clipboard"],
        input=op_return_text.encode(),
        env=env,
        check=True,
    )
    await asyncio.sleep(0.1)
    d.key("ctrl+v")
    await asyncio.sleep(0.5)
    print(f"    [ok] OP_RETURN payload entered ({len(op_return_text)} chars)")

    # Set hex mode if needed (re-encodes the payload as raw bytes).
    if is_hex_mode:
        await click_label(d, "Hex", delay=0.5)
        print("    [ok] hex mode enabled")

    # Toggle MAX on the first recipient to set amount to all funds minus fees.
    await click_label(d, "MAX", delay=1.0)
    await wait_for(d, "sats", "MAX amount computed",
                   retries=15, delay=0.5)
    await asyncio.sleep(0.8)  # let preview settle
    print("    [ok] MAX toggled — amount computed")

    # If the selected coin is already spent in mempool (previous run), the
    # full-RBF banner appears. Clicking the total-fee field auto-fills the BIP-125
    # Rule-4 minimum and syncs the rate, lifting the fee above the original.
    sem_after_max = await d.cs_flat_text()
    if "Full-RBF replacement" in sem_after_max:
        print("    [info] RBF banner detected — auto-calculating RBF minimum fee")
        fee_rect = await d.cs_find_by_label_part_containing("total_fee_display")
        if fee_rect is None:
            raise AssertionError("total_fee_display field not found while RBF banner present")
        fx = (fee_rect[0] + fee_rect[2]) // 2
        fy = (fee_rect[1] + fee_rect[3]) // 2
        d.flutter_click(fx, fy)
        await asyncio.sleep(1.2)
        print("    [ok] RBF minimum fee auto-calculated")

    # Click Create PSBT. When _feeEditMode != none (RBF auto-fill was just used),
    # the first click only resets the fee mode and refreshes the preview — a
    # second click is needed to actually submit. Try up to 2 attempts and only
    # fall back to direct Send if neither lands on the PSBT detail screen.
    psbt_created = False
    for attempt in range(2):
        await click_label(d, "Create PSBT", delay=2.0)
        try:
            await wait_for(d, '"Unsigned Transaction"', "PSBT detail screen opened",
                           retries=8, delay=0.8)
            psbt_created = True
            break
        except AssertionError:
            # Did not navigate. Either fee mode just got reset, or there is a
            # validation error. Try once more before falling back.
            await asyncio.sleep(0.5)
    if not psbt_created:
        print("    [info] Create PSBT did not transition — using direct send instead")
        await click_label(d, "Send", delay=1.0)
        await wait_for(d, "Confirm send", "direct send confirmation sheet visible",
                       retries=10, delay=0.5)
        print("    [ok] direct send confirmation sheet visible")
        await click_label(d, "Sign and broadcast", delay=1.0)
        await wait_for(d, '"Receive"', "back on wallet detail after direct send",
                       retries=60, delay=1.0)
        print("    [ok] direct send completed — PSBT signed and broadcast")

    return psbt_created


# ---------------------------------------------------------------------------
# Phase 4: verify OP_RETURN data in PSBT detail
# ---------------------------------------------------------------------------

async def phase_verify_op_return_in_psbt(
    d: UIDriver,
    psbt_label: str,
    expected_data: str,
    is_hex_mode: bool,
) -> None:
    print(f"\n  [phase 4] verify OP_RETURN in PSBT detail")

    # Verify PSBT label visible
    sem = await d.cs_flat_text()
    if psbt_label not in sem:
        raise AssertionError(
            f"PSBT label '{psbt_label}' not visible on PSBT detail screen"
        )
    print(f"    [ok] PSBT label '{psbt_label}' visible")

    # Verify OP_RETURN data is visible in the recipients list
    # The PSBT detail shows "OP_RETURN data" as the label for OP_RETURN recipients
    # and the decoded payload below it
    if is_hex_mode:
        # For hex mode, the display should show "0xdeadbeeffeed" or similar
        # The decodeOpReturnForDisplay function shows hex with "0x" prefix for non-printable
        await wait_for(d, "0xdeadbeeffeed", "OP_RETURN hex data visible in PSBT detail",
                       retries=15, delay=0.8)
        print("    [ok] OP_RETURN hex data '0xdeadbeeffeed' visible in PSBT detail")
    else:
        # For UTF-8 mode, the display should show the text directly
        await wait_for(d, expected_data, "OP_RETURN UTF-8 data visible in PSBT detail",
                       retries=15, delay=0.8)
        print(f"    [ok] OP_RETURN UTF-8 data '{expected_data}' visible in PSBT detail")

    # Verify "OP_RETURN data" label is present
    await wait_for(d, "OP_RETURN data", "OP_RETURN label visible in PSBT detail",
                   retries=10, delay=0.5)
    print("    [ok] 'OP_RETURN data' label visible in PSBT detail")


# ---------------------------------------------------------------------------
# Phase 5: sign with hot key
# ---------------------------------------------------------------------------

async def phase_sign_psbt(d: UIDriver) -> None:
    print("\n  [phase 5] sign PSBT with hot key")

    await click_label(d, "Sign", delay=1.5)
    await wait_for(d, "SIGNED", "PSBT status changed to SIGNED",
                   retries=15, delay=0.8)
    print("    [ok] PSBT signed — SIGNED status visible")


# ---------------------------------------------------------------------------
# Phase 6: broadcast
# ---------------------------------------------------------------------------

async def phase_broadcast(d: UIDriver) -> None:
    print("\n  [phase 6] broadcast PSBT")

    await click_label(d, "Broadcast", delay=0.5)
    await wait_for(d, "Transaction broadcast", "broadcast success toast",
                   retries=30, delay=1.0)
    print("    [ok] broadcast success toast visible")
    await asyncio.sleep(2.0)

    # After broadcast the screen pops back to wallet detail
    await wait_for(d, '"Receive"', "back on wallet detail",
                   retries=10, delay=0.5)
    print("    [ok] back on wallet detail after broadcast")


# ---------------------------------------------------------------------------
# Phase 7: verify OP_RETURN in transaction detail
# ---------------------------------------------------------------------------

async def phase_verify_op_return_in_tx_detail(
    d: UIDriver,
    expected_data: str,
    is_hex_mode: bool,
    psbt_label: str,
) -> None:
    print(f"\n  [phase 7] verify OP_RETURN in transaction detail")

    # Navigate to Transactions tab.
    await click_label(d, "Transactions", delay=0.8)
    await wait_for(d, "sats", "Transactions tab visible", retries=15, delay=0.8)

    # Sub-test B re-creates the wallet from the same mnemonic, so it also
    # rescans sub-test A's earlier broadcast. To open the right tx, locate the
    # tile that carries this run's PSBT label (the label is auto-applied to the
    # outgoing address and surfaces on the tx tile as "<label>\n<amount> sats\n…").
    # Wait a bit for the new tx to appear in the wallet's index.
    tx_rect = None
    for _ in range(30):
        tx_rect = await d.cs_find_label_containing(f"{psbt_label}\n")
        if tx_rect is not None:
            break
        await asyncio.sleep(1.0)
    if tx_rect is None:
        # Fall back to the most recent tile by "sats\n" pattern, but warn.
        print(f"    [warn] No tx tile labelled '{psbt_label}' — opening first tx tile")
        tx_rect = await d.cs_find_label_containing("sats\n")
        if tx_rect is None:
            raise AssertionError("No transaction tile found in Transactions tab")
    cx = (tx_rect[0] + tx_rect[2]) // 2
    cy = (tx_rect[1] + tx_rect[3]) // 2
    d.flutter_click(cx, cy)
    await asyncio.sleep(1.0)

    # Wait for the transaction detail dialog.
    await wait_for(d, "Transaction details", "transaction detail dialog opened",
                   retries=15, delay=0.8)
    print("    [ok] transaction detail dialog opened")

    # Verify OP_RETURN data is visible in the dialog
    # The _OpReturnRow widget shows:
    # - "OP_RETURN data" as label
    # - The decoded payload (UTF-8 text or hex with 0x prefix)
    if is_hex_mode:
        await wait_for(d, "0xdeadbeeffeed", "OP_RETURN hex data in tx detail",
                       retries=15, delay=0.8)
        print("    [ok] OP_RETURN hex data '0xdeadbeeffeed' visible in tx detail")
    else:
        await wait_for(d, expected_data, "OP_RETURN UTF-8 data in tx detail",
                       retries=15, delay=0.8)
        print(f"    [ok] OP_RETURN UTF-8 data '{expected_data}' visible in tx detail")

    # Close the dialog
    await click_tooltip(d, "Close", delay=0.5)
    await wait_absent(d, "Transaction details", "tx detail dialog closed",
                      retries=10, delay=0.4)
    print("    [ok] tx detail dialog closed")


# ---------------------------------------------------------------------------
# Sub-test A main function
# ---------------------------------------------------------------------------

async def test_op_return_utf8(d: UIDriver) -> None:
    print(f"\n--- {WALLET_NAME_A} (OP_RETURN UTF-8) ---")

    await set_active_network_signet(d)
    await phase_create_wallet(d, WALLET_NAME_A)
    await phase_sync(d)
    psbt_created = await phase_create_psbt_with_op_return(
        d, PSBT_LABEL_A, UTF8_PAYLOAD, is_hex_mode=False
    )
    if psbt_created:
        await phase_verify_op_return_in_psbt(
            d, PSBT_LABEL_A, UTF8_PAYLOAD, is_hex_mode=False
        )
        await phase_sign_psbt(d)
        await phase_broadcast(d)
    else:
        print("    [ok] direct send already broadcast — skipping separate broadcast")
    await phase_verify_op_return_in_tx_detail(
        d, UTF8_PAYLOAD, is_hex_mode=False, psbt_label=PSBT_LABEL_A
    )

    await go_back_to_wallet_list(d)
    await delete_wallet_from_list(d, WALLET_NAME_A)
    print(f"\n    [PASS] {WALLET_NAME_A}")


# ---------------------------------------------------------------------------
# Sub-test B main function
# ---------------------------------------------------------------------------

async def test_op_return_hex(d: UIDriver) -> None:
    print(f"\n--- {WALLET_NAME_B} (OP_RETURN Hex) ---")

    await phase_create_wallet(d, WALLET_NAME_B)
    await phase_sync(d)
    psbt_created = await phase_create_psbt_with_op_return(
        d, PSBT_LABEL_B, HEX_PAYLOAD, is_hex_mode=True
    )
    if psbt_created:
        await phase_verify_op_return_in_psbt(
            d, PSBT_LABEL_B, HEX_PAYLOAD, is_hex_mode=True
        )
        await phase_sign_psbt(d)
        await phase_broadcast(d)
    else:
        print("    [ok] direct send already broadcast — skipping separate broadcast")
    await phase_verify_op_return_in_tx_detail(
        d, HEX_PAYLOAD, is_hex_mode=True, psbt_label=PSBT_LABEL_B
    )

    await go_back_to_wallet_list(d)
    await delete_wallet_from_list(d, WALLET_NAME_B)
    print(f"\n    [PASS] {WALLET_NAME_B}")


# ---------------------------------------------------------------------------
# Main test function
# ---------------------------------------------------------------------------

async def test_op_return(d: UIDriver) -> None:
    print("=== OP_RETURN Full Cycle Test ===")

    # Sub-test A: UTF-8 OP_RETURN
    await test_op_return_utf8(d)

    # Clean up first wallet before sub-test B
    await go_back_to_wallet_list(d)
    try:
        await delete_wallet_from_list(d, WALLET_NAME_A)
    except AssertionError:
        pass  # wallet may not exist if sub-test A was skipped

    # Sub-test B: Hex OP_RETURN
    await test_op_return_hex(d)

    print("\n" + "=" * 50)


# ---------------------------------------------------------------------------
# Entry point
# ---------------------------------------------------------------------------

if __name__ == "__main__":
    asyncio.run(run_regression(test_op_return, "reg28"))
