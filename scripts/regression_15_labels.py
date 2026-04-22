#!/usr/bin/env python3
"""
Regression test 15: Coin, address, and transaction labeling.

Flow:
  0.  Settings → set Active Network to Signet
  1.  Create SegWit singlesig wallet via Guided creation (Enter manually →
      Hot Key → mnemonic) — same funded Signet wallet as reg11/reg14.
  2.  Sync and wait for confirmed coins.
  3.  Coin label:
        Coins tab → tap first coin → CoinDetailDialog →
        tap Edit icon → LabelDialog → type label → Save →
        close dialog → verify label visible on coin tile.
  4.  Address label:
        Addresses tab → tap first receive address → AddressDetailDialog →
        tap Edit icon → LabelDialog → type label → Save →
        close dialog → verify label visible on address tile.
  5.  Transaction label:
        Transactions tab → tap first transaction → TxDetailDialog →
        tap Edit icon → LabelDialog → type label → Save →
        close dialog → verify label visible on transaction tile.
  6.  Delete wallet.

Exit code: 0 = PASS, 1 = FAIL.

Prerequisites:
  bash scripts/prepare_test_build.sh
  python3 scripts/regression_15_labels.py
"""

import asyncio
import os
import subprocess
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from ui_driver import UIDriver                          # noqa: E402
from regression_helpers import (                       # noqa: E402
    wait_for, wait_absent,
    dismiss_startup_dialogs,
    navigate_wallets, fill_field, click_label, click_tooltip,
    go_back_to_wallet_list, delete_wallet_from_list,
    set_active_network_signet, run_regression,
)


# ---------------------------------------------------------------------------
# Test data
# ---------------------------------------------------------------------------

WALLET_NAME = "Reg15-Labels"

# Funded Signet P2WPKH hot-key wallet (shared with reg11/reg14).
MNEMONIC = (
    "bachelor brick camera brave assume differ disagree "
    "judge security scrap wonder core"
)

COIN_LABEL    = "reg15-coin-label"
ADDRESS_LABEL = "reg15-addr-label"
TX_LABEL      = "reg15-tx-label"

_ENV = {**os.environ, "DISPLAY": ":0"}


# ---------------------------------------------------------------------------
# Helper: type text into a focused field via clipboard paste
# ---------------------------------------------------------------------------

def _paste(d: UIDriver, text: str) -> None:
    subprocess.run(
        ["xclip", "-selection", "clipboard"],
        input=text.encode(),
        env=_ENV,
        check=True,
    )
    d.key("ctrl+a")
    d.key("ctrl+v")


# ---------------------------------------------------------------------------
# Phase 1: create wallet via Guided creation
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
    await wait_for(d, '"Receive"', f"wallet detail loaded",
                   retries=30, delay=1.0)
    print(f"    [ok] wallet '{WALLET_NAME}' opened")


# ---------------------------------------------------------------------------
# Phase 2: sync — wait for confirmed coins
# ---------------------------------------------------------------------------

async def phase_sync(d: UIDriver) -> None:
    print("\n  [phase 2] sync — wait for confirmed coins")

    await click_label(d, "Coins", delay=1.0)
    sem = await wait_for(
        d,
        "sats",
        "at least one coin value visible in Coins tab",
        retries=180,
        delay=1.0,
    )
    if '"No coins.' in sem:
        raise AssertionError(
            "Coins tab shows 'No coins' after sync — "
            "wallet may have no UTXOs on Signet."
        )
    print("    [ok] coins visible after sync")


# ---------------------------------------------------------------------------
# Phase 3: set and verify a coin label
# ---------------------------------------------------------------------------

async def phase_coin_label(d: UIDriver) -> None:
    print("\n  [phase 3] coin label")

    # Tap the first coin tile. The tile label is multi-line ("X sats\ntb1q...\ndate"),
    # while the summary header is single-line ("Total: X sats"). Search for the
    # newline-terminated pattern to skip the summary row.
    sats_rect = await d.cs_find_label_containing("sats\n")
    if sats_rect is None:
        raise AssertionError("No coin tile found in Coins tab")
    d.flutter_click(
        (sats_rect[0] + sats_rect[2]) // 2,
        (sats_rect[1] + sats_rect[3]) // 2,
    )
    await asyncio.sleep(0.8)
    await wait_for(d, "Coin details", "CoinDetailDialog opened",
                   retries=10, delay=0.5)
    print("    [ok] CoinDetailDialog opened")

    # Click Edit icon button (tooltip "Edit") next to the Label row.
    edit_rect = await d.cs_find_by_tooltip("Edit")
    if edit_rect is None:
        raise AssertionError("Edit button not found in CoinDetailDialog")
    d.flutter_click(
        (edit_rect[0] + edit_rect[2]) // 2,
        (edit_rect[1] + edit_rect[3]) // 2,
    )
    await asyncio.sleep(0.5)
    await wait_for(d, "Add a label...", "LabelDialog opened",
                   retries=10, delay=0.5)
    print("    [ok] LabelDialog opened")

    # Type the coin label.
    field_rect = await d.cs_find_textfield_by_label("Add a label...")
    if field_rect is None:
        raise AssertionError("Label TextField not found in LabelDialog")
    d.flutter_click(
        (field_rect[0] + field_rect[2]) // 2,
        (field_rect[1] + field_rect[3]) // 2,
    )
    await asyncio.sleep(0.3)
    _paste(d, COIN_LABEL)
    await asyncio.sleep(0.5)

    await click_label(d, "Save", delay=0.5)
    # LabelDialog auto-dismisses; back in CoinDetailDialog.
    await wait_for(d, "Coin details", "back in CoinDetailDialog after save",
                   retries=10, delay=0.5)
    print(f"    [ok] coin label saved: '{COIN_LABEL}'")

    # Close CoinDetailDialog.
    await click_tooltip(d, "Cancel", delay=0.5)
    await asyncio.sleep(0.5)

    # Verify the label appears on the coin tile in the list.
    if await d.cs_find_text_containing(COIN_LABEL) is None:
        raise AssertionError(
            f"Coin label '{COIN_LABEL}' not visible on coin tile after save"
        )
    print(f"    [ok] label '{COIN_LABEL}' visible on coin tile")


# ---------------------------------------------------------------------------
# Phase 4: set and verify an address label
# ---------------------------------------------------------------------------

async def phase_address_label(d: UIDriver) -> None:
    print("\n  [phase 4] address label")

    await click_label(d, "Addresses", delay=0.8)
    await wait_for(d, "tb1q", "addresses visible", retries=15, delay=0.8)

    # Tap the first receive address tile.
    addr_rect = await d.cs_find_label_containing("tb1q")
    if addr_rect is None:
        raise AssertionError("No tb1q address found in Addresses tab")
    d.flutter_click(
        (addr_rect[0] + addr_rect[2]) // 2,
        (addr_rect[1] + addr_rect[3]) // 2,
    )
    await asyncio.sleep(0.8)
    await wait_for(d, "Address details", "AddressDetailDialog opened",
                   retries=10, delay=0.5)
    print("    [ok] AddressDetailDialog opened")

    # Click Edit icon (tooltip "Edit") next to the "Address label" row.
    edit_rect = await d.cs_find_by_tooltip("Edit")
    if edit_rect is None:
        raise AssertionError("Edit button not found in AddressDetailDialog")
    d.flutter_click(
        (edit_rect[0] + edit_rect[2]) // 2,
        (edit_rect[1] + edit_rect[3]) // 2,
    )
    await asyncio.sleep(0.5)
    await wait_for(d, "Add a label...", "LabelDialog opened",
                   retries=10, delay=0.5)
    print("    [ok] LabelDialog opened for address")

    field_rect = await d.cs_find_textfield_by_label("Add a label...")
    if field_rect is None:
        raise AssertionError("Label TextField not found in LabelDialog")
    d.flutter_click(
        (field_rect[0] + field_rect[2]) // 2,
        (field_rect[1] + field_rect[3]) // 2,
    )
    await asyncio.sleep(0.3)
    _paste(d, ADDRESS_LABEL)
    await asyncio.sleep(0.5)

    await click_label(d, "Save", delay=0.5)
    await wait_for(d, "Address details", "back in AddressDetailDialog after save",
                   retries=10, delay=0.5)
    print(f"    [ok] address label saved: '{ADDRESS_LABEL}'")

    # Close AddressDetailDialog.
    await click_tooltip(d, "Close", delay=0.5)
    await asyncio.sleep(0.5)

    # Verify the label appears on the address tile.
    if await d.cs_find_text_containing(ADDRESS_LABEL) is None:
        raise AssertionError(
            f"Address label '{ADDRESS_LABEL}' not visible on address tile after save"
        )
    print(f"    [ok] label '{ADDRESS_LABEL}' visible on address tile")


# ---------------------------------------------------------------------------
# Phase 5: set and verify a transaction label
# ---------------------------------------------------------------------------

async def phase_tx_label(d: UIDriver) -> None:
    print("\n  [phase 5] transaction label")

    await click_label(d, "Transactions", delay=0.8)
    await wait_for(d, "sats", "transactions visible", retries=15, delay=1.0)

    # Tap the first transaction tile. Like coin tiles, the tx tile label is
    # multi-line ("±X sats\ndate"), so "sats\n" avoids the summary header.
    sats_rect = await d.cs_find_label_containing("sats\n")
    if sats_rect is None:
        raise AssertionError("No transaction tile found in Transactions tab")
    d.flutter_click(
        (sats_rect[0] + sats_rect[2]) // 2,
        (sats_rect[1] + sats_rect[3]) // 2,
    )
    await asyncio.sleep(0.8)
    await wait_for(d, "Transaction details", "TxDetailDialog opened",
                   retries=10, delay=0.5)
    print("    [ok] TxDetailDialog opened")

    # Click Edit icon (tooltip "Edit") next to the "Label" row.
    edit_rect = await d.cs_find_by_tooltip("Edit")
    if edit_rect is None:
        raise AssertionError("Edit button not found in TxDetailDialog")
    d.flutter_click(
        (edit_rect[0] + edit_rect[2]) // 2,
        (edit_rect[1] + edit_rect[3]) // 2,
    )
    await asyncio.sleep(0.5)
    await wait_for(d, "Add a label...", "LabelDialog opened",
                   retries=10, delay=0.5)
    print("    [ok] LabelDialog opened for transaction")

    field_rect = await d.cs_find_textfield_by_label("Add a label...")
    if field_rect is None:
        raise AssertionError("Label TextField not found in LabelDialog")
    d.flutter_click(
        (field_rect[0] + field_rect[2]) // 2,
        (field_rect[1] + field_rect[3]) // 2,
    )
    await asyncio.sleep(0.3)
    _paste(d, TX_LABEL)
    await asyncio.sleep(0.5)

    await click_label(d, "Save", delay=0.5)
    await wait_for(d, "Transaction details", "back in TxDetailDialog after save",
                   retries=10, delay=0.5)
    print(f"    [ok] transaction label saved: '{TX_LABEL}'")

    # Close TxDetailDialog.
    await click_tooltip(d, "Close", delay=0.5)
    await asyncio.sleep(0.5)

    # Verify the label appears on the transaction tile.
    if await d.cs_find_text_containing(TX_LABEL) is None:
        raise AssertionError(
            f"Transaction label '{TX_LABEL}' not visible on tx tile after save"
        )
    print(f"    [ok] label '{TX_LABEL}' visible on transaction tile")


# ---------------------------------------------------------------------------
# Main test function
# ---------------------------------------------------------------------------

async def test_labels(d: UIDriver) -> None:
    print(f"\n--- {WALLET_NAME} (coin / address / transaction labels) ---")

    await set_active_network_signet(d)
    await phase_create_wallet(d)
    await phase_sync(d)
    await phase_coin_label(d)
    await phase_address_label(d)
    await phase_tx_label(d)

    await go_back_to_wallet_list(d)
    await delete_wallet_from_list(d, WALLET_NAME)

    print(f"\n    [PASS] {WALLET_NAME}")


# ---------------------------------------------------------------------------
# Entry point
# ---------------------------------------------------------------------------

if __name__ == "__main__":
    asyncio.run(run_regression(test_labels, "reg15"))
