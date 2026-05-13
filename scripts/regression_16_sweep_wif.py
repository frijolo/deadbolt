#!/usr/bin/env python3
"""
Regression test 16: Sweep WIF — full flow including real broadcast on Signet.

Flow:
  0.  Settings → set Active Network to Signet
  1.  Create SegWit singlesig wallet via Guided creation (Hot key →
      Hot Key → mnemonic) — same funded Signet wallet as reg11/reg14/reg15.
  2.  Sync and wait for confirmed coins.
  3.  Export WIF of a guaranteed-funded address to clipboard:
        Coins tab → tap first non-"Spending" coin tile → CoinDetailDialog opens →
        tap the address row (non-truncated ColoredGroupText, no truncate=true) →
        CoinDetailDialog pops, _AddressDetailByStringDialog opens
        (renders AddressDetailDialog for that specific address) →
        share icon → text export sheet → "Export private key (WIF)" →
        sheet closes → WIF confirm dialog → type phrase → "Show WIF" →
        WIF display dialog → "Copy to clipboard" → WIF in clipboard,
        dialog closes.
  4.  Close AddressDetailDialog.
  5.  Navigate to Sweep WIF:
        More options popup → "Import" → bottom sheet → "Sweep WIF key".
  6.  In SweepWifScreen:
        Tap "Paste from clipboard" icon → WIF pasted.
        Tap "Find UTXOs".
        Verify "Controlled addresses" + total balance shown.
        Verify destination auto-filled (wallet's next receive address).
        Tap "Sweep X sat" button → Rust signs + broadcasts the transaction.
        Verify back on wallet detail (screen pops on success).
  7.  Delete wallet.

Exit code: 0 = PASS, 1 = FAIL.

Prerequisites:
  bash scripts/prepare_test_build.sh
  python3 scripts/regression_16_sweep_wif.py
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
    click_popup_item,
    open_hot_existing_mnemonic,
)


# ---------------------------------------------------------------------------
# Test data
# ---------------------------------------------------------------------------

WALLET_NAME = "Reg16-SweepWif"

# Funded Signet P2WPKH hot-key wallet (shared with reg11/reg14/reg15).
MNEMONIC = (
    "bachelor brick camera brave assume differ disagree "
    "judge security scrap wonder core"
)

# Confirm phrase required by the WIF export dialog.
WIF_CONFIRM_PHRASE = "my full wallet is at risk"

_ENV = {**os.environ, "DISPLAY": ":0"}


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
# Phase 3: export WIF of a funded address to clipboard via CoinDetailDialog
# ---------------------------------------------------------------------------

async def phase_export_wif_to_clipboard(d: UIDriver) -> None:
    """Navigate to a funded address via the Coins tab and export its WIF.

    Coins tab → tap first coin tile → CoinDetailDialog →
    tap the address row (opens _AddressDetailByStringDialog = AddressDetailDialog) →
    share icon → WIF confirm → Show WIF → Copy to clipboard.

    The address in CoinDetailDialog is rendered without truncation
    (ColoredGroupText without truncate=true), so any tb1q address found in
    the dialog's semantics tree belongs to the funded coin.
    """
    print("\n  [phase 3] export WIF of funded coin address to clipboard")

    # Tap the first coin tile that is NOT being spent (not "Spending" in label).
    # "Spending" coins have their UTXOs in the mempool — Electrum returns 0 balance.
    nodes = await d.cs_tree()
    sats_rect = None
    for node in nodes:
        label = node.get("label", "")
        if "sats\n" in label and "Spending" not in label:
            gr = node.get("globalRect")
            if gr:
                sats_rect = (int(gr[0]), int(gr[1]), int(gr[2]), int(gr[3]))
                break
    if sats_rect is None:
        raise AssertionError(
            "No non-spending coin tile found in Coins tab — "
            "all coins are in 'Spending' (mempool-spent) state"
        )
    d.flutter_click(
        (sats_rect[0] + sats_rect[2]) // 2,
        (sats_rect[1] + sats_rect[3]) // 2,
    )
    await asyncio.sleep(0.8)
    await wait_for(d, "Coin details", "CoinDetailDialog opened",
                   retries=10, delay=0.5)
    print("    [ok] CoinDetailDialog opened")

    # Tap the address row to open AddressDetailDialog.
    # In CoinDetailDialog the coin address is rendered as a full (non-truncated)
    # ColoredGroupText — its semantic label is the complete tb1q... string.
    # Tapping it triggers InkWell.onTap → pops CoinDetailDialog and shows
    # _AddressDetailByStringDialog (which loads AddressDetailDialog).
    addr_rect = await d.cs_find_label_containing("tb1q")
    if addr_rect is None:
        raise AssertionError("tb1q address not found in CoinDetailDialog")
    d.flutter_click(
        (addr_rect[0] + addr_rect[2]) // 2,
        (addr_rect[1] + addr_rect[3]) // 2,
    )
    await asyncio.sleep(1.0)
    await wait_for(d, "Address details", "AddressDetailDialog opened",
                   retries=15, delay=0.8)
    print("    [ok] AddressDetailDialog opened for funded coin address")

    # Tap the share/copy icon (tooltip "Copy to clipboard") → text export sheet.
    share_rect = await d.cs_find_by_tooltip("Copy to clipboard")
    if share_rect is None:
        raise AssertionError(
            "'Copy to clipboard' icon button not found in address details dialog"
        )
    d.flutter_click(
        (share_rect[0] + share_rect[2]) // 2,
        (share_rect[1] + share_rect[3]) // 2,
    )
    await asyncio.sleep(0.6)
    await wait_for(d, "Export private key (WIF)", "text export sheet opened",
                   retries=10, delay=0.5)
    print("    [ok] text export sheet opened — WIF option visible")

    # Tap "Export private key (WIF)" — sheet closes, WIF confirm dialog opens.
    await click_label(d, "Export private key (WIF)", delay=0.5)
    await wait_for(d, "my full wallet is at risk", "WIF confirm dialog opened",
                   retries=10, delay=0.5)
    print("    [ok] WIF confirm dialog opened")

    # Type the confirm phrase.
    phrase_field = await d.cs_find_textfield_by_label("my full wallet is at risk")
    if phrase_field is None:
        raise AssertionError(
            "Confirm phrase TextField not found in WIF export dialog"
        )
    d.flutter_click(
        (phrase_field[0] + phrase_field[2]) // 2,
        (phrase_field[1] + phrase_field[3]) // 2,
    )
    await asyncio.sleep(0.3)
    subprocess.run(
        ["xclip", "-selection", "clipboard"],
        input=WIF_CONFIRM_PHRASE.encode(),
        env=_ENV,
        check=True,
    )
    await asyncio.sleep(0.1)
    d.key("ctrl+v")
    await asyncio.sleep(0.8)
    print(f"    [ok] typed confirm phrase: '{WIF_CONFIRM_PHRASE}'")

    # "Show WIF" button is now enabled.
    await click_label(d, "Show WIF", delay=0.8)
    await wait_for(d, "Private key (WIF)", "WIF display dialog opened",
                   retries=10, delay=0.8)
    print("    [ok] WIF display dialog opened")

    # "Copy to clipboard" TextButton — copies WIF and auto-closes the dialog.
    await click_label(d, "Copy to clipboard", delay=0.8)
    await wait_absent(d, "Private key (WIF)", "WIF display dialog closed",
                      retries=10, delay=0.5)
    print("    [ok] WIF copied to clipboard")

    # Close AddressDetailDialog.
    await click_tooltip(d, "Close", delay=0.5)
    await wait_absent(d, "Address details", "AddressDetailDialog closed",
                      retries=10, delay=0.5)
    print("    [ok] AddressDetailDialog closed")


# ---------------------------------------------------------------------------
# Phase 4: navigate to SweepWifScreen
# ---------------------------------------------------------------------------

async def phase_open_sweep_wif(d: UIDriver) -> None:
    print("\n  [phase 4] open Sweep WIF screen")

    await click_popup_item(d, "More options", 296, "Import")
    await wait_for(d, "Sweep WIF key", "import sheet with Sweep option",
                   retries=10, delay=0.5)
    await click_label(d, "Sweep WIF key", delay=0.5)
    await wait_for(d, '"Sweep WIF key"', "SweepWifScreen opened",
                   retries=10, delay=0.8)
    print("    [ok] SweepWifScreen opened")


# ---------------------------------------------------------------------------
# Phase 5: paste WIF, query UTXOs, sweep, verify broadcast
# ---------------------------------------------------------------------------

async def phase_sweep_and_verify(d: UIDriver) -> None:
    print("\n  [phase 5] paste WIF, query UTXOs, and broadcast sweep")

    # Paste the WIF from clipboard via the paste icon button.
    paste_rect = await d.cs_find_by_tooltip("Paste from clipboard")
    if paste_rect is None:
        raise AssertionError(
            "'Paste from clipboard' icon button not found in SweepWifScreen"
        )
    d.flutter_click(
        (paste_rect[0] + paste_rect[2]) // 2,
        (paste_rect[1] + paste_rect[3]) // 2,
    )
    await asyncio.sleep(0.6)
    print("    [ok] pasted WIF from clipboard")

    # Click "Find UTXOs".
    await click_label(d, "Find UTXOs", delay=0.5)
    print("    [ok] 'Find UTXOs' clicked — querying Electrum...")

    # Wait for "Controlled addresses" (up to ~45 s for Electrum round-trip).
    await wait_for(
        d,
        "Controlled addresses",
        "WIF resolved — controlled addresses section visible",
        retries=45,
        delay=1.0,
    )
    print("    [ok] 'Controlled addresses' section appeared")

    # Verify UTXOs are found — the sweep button is only rendered when hasUtxos.
    flat = await d.cs_flat_text()
    if "Total:" not in flat:
        raise AssertionError(
            "Expected UTXOs on the exported WIF address but none were found. "
            "The CoinDetailDialog address and its on-chain UTXOs must match."
        )
    print("    [ok] positive total balance confirmed")

    # Verify destination was auto-filled with the wallet's next receive address.
    if "tb1q" not in flat:
        raise AssertionError(
            "Destination address (tb1q...) not visible — auto-fill may have failed"
        )
    print("    [ok] destination address auto-filled")

    # Click the sweep button. Label: "Sweep X sat" (amount varies).
    sweep_rect = await d.cs_find_label_containing("Sweep ")
    if sweep_rect is None:
        raise AssertionError("'Sweep X sat' button not found in SweepWifScreen")
    d.flutter_click(
        (sweep_rect[0] + sweep_rect[2]) // 2,
        (sweep_rect[1] + sweep_rect[3]) // 2,
    )
    await asyncio.sleep(0.5)
    print("    [ok] 'Sweep X sat' button tapped — broadcasting...")

    # On success: Rust signs + broadcasts, the screen pops, wallet detail loads.
    # On failure: stays on SweepWifScreen with an error toast.
    # The wallet name is always visible in the wallet detail AppBar.
    # SweepWifScreen shows "Sweep WIF key" in the AppBar — never the wallet name.
    await wait_for(
        d,
        WALLET_NAME,
        "back on wallet detail — sweep broadcast succeeded",
        retries=30,
        delay=1.0,
    )
    print("    [ok] sweep broadcast succeeded — back on wallet detail")


# ---------------------------------------------------------------------------
# Main test function
# ---------------------------------------------------------------------------

async def test_sweep_wif(d: UIDriver) -> None:
    print(f"\n--- {WALLET_NAME} (Sweep WIF full flow with real broadcast) ---")

    await set_active_network_signet(d)
    await phase_create_wallet(d)
    await phase_sync(d)
    await phase_export_wif_to_clipboard(d)
    await phase_open_sweep_wif(d)
    await phase_sweep_and_verify(d)

    await go_back_to_wallet_list(d)
    await delete_wallet_from_list(d, WALLET_NAME)

    print(f"\n    [PASS] {WALLET_NAME}")


# ---------------------------------------------------------------------------
# Entry point
# ---------------------------------------------------------------------------

if __name__ == "__main__":
    asyncio.run(run_regression(test_sweep_wif, "reg16"))
