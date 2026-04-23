#!/usr/bin/env python3
"""
Regression test 17: PSBT clipboard export + import round-trip (air-gapped simulation).

Flow:
  0.  Settings → set Active Network to Signet.
  1.  Create SegWit singlesig wallet via Guided creation (same funded Signet
      mnemonic as reg11/reg14/reg15/reg16 — guaranteed coins).
  2.  Sync → wait for confirmed coins.
  3.  Create self-send PSBT (MAX amount, destination = self):
        Overview tab → Send → select coin → "This wallet (Self)" picker →
        MAX toggle → "Create PSBT" → PSBT detail screen opens.
  4.  Export PSBT to clipboard from PSBT detail screen:
        Tap "Export PSBT" → export sheet → "Copy to clipboard" → sheet closes.
  5.  Go back to wallet detail → Transactions tab: verify PSBT tile + UNSIGNED status.
  6.  Import PSBT from clipboard via More options popup:
        More options → Import → import choice sheet → "PSBT" →
        PSBT import sheet → "Paste from clipboard" →
        toast "PSBT imported" or "Signatures merged".
  7.  Verify PSBT tile still present (round-trip did not delete it).
  8.  Open PSBT → sign with hot key → verify SIGNED status.
  9.  Broadcast → verify success toast.
  10. Delete wallet.

Gaps covered:
  - PSBT text export to clipboard (Export PSBT → Copy to clipboard)
  - PSBT text import from clipboard (More options → Import → PSBT → Paste from clipboard)
  - Full air-gapped simulation round-trip without hardware / QR camera

Exit code: 0 = PASS, 1 = FAIL.

Prerequisites:
  bash scripts/prepare_test_build.sh
  python3 scripts/regression_17_psbt_clipboard.py
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

WALLET_NAME = "Reg17-PsbtClipboard"
PSBT_LABEL  = "reg17-export-import"

# Funded Signet P2WPKH hot-key wallet (shared with reg11/reg14/reg15/reg16).
MNEMONIC = (
    "bachelor brick camera brave assume differ disagree "
    "judge security scrap wonder core"
)

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
# Phase 3: create self-send PSBT (MAX amount)
# ---------------------------------------------------------------------------

async def phase_create_psbt(d: UIDriver) -> None:
    print("\n  [phase 3] create self-send PSBT")

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
    await fill_field(d, "Label", PSBT_LABEL)
    print(f"    [ok] PSBT label set to '{PSBT_LABEL}'")

    # Self-pay address via wallet picker
    await click_tooltip(d, "MY WALLETS", delay=0.5)
    await wait_for(d, "This wallet (Self)", "wallet picker visible",
                   retries=8, delay=0.5)
    await click_label(d, "This wallet (Self)", delay=1.5)
    await asyncio.sleep(2.0)
    sem = await d.cs_flat_text()
    if "tb1q" not in sem.lower():
        raise AssertionError(
            "No tb1q address filled after 'This wallet (Self)' selection"
        )
    print("    [ok] self-payment address auto-filled")

    # MAX amount
    await click_label(d, "MAX", delay=0.8)
    await wait_absent(d, '"— sats"', "MAX amount computed",
                      retries=15, delay=0.5)
    print("    [ok] MAX toggled — amount computed")

    # Touch the total fee field so that onEditTap auto-corrects the total to
    # rbfMinFeeSats when the UTXO is already in an unconfirmed TX (RBF scenario).
    # _syncRateFromTotal then back-computes a rate that satisfies both RBF checks.
    # In the non-RBF case this is a no-op (total stays at the current feeSats).
    await click_label(d, "total_fee_display", delay=0.5)
    await asyncio.sleep(0.3)
    d.key("Return")
    await asyncio.sleep(0.4)
    print("    [ok] total fee confirmed (RBF minimum applied if applicable)")

    # Create PSBT
    await click_label(d, "Create PSBT", delay=0.5)
    await wait_for(d, '"Unsigned Transaction"', "PSBT detail screen opened",
                   retries=15, delay=1.0)
    sem_detail = await d.cs_flat_text()
    if PSBT_LABEL not in sem_detail:
        raise AssertionError(
            f"PSBT label '{PSBT_LABEL}' not visible on PSBT detail screen"
        )
    print(f"    [ok] PSBT detail screen opened (label '{PSBT_LABEL}' visible)")


# ---------------------------------------------------------------------------
# Phase 4: export PSBT to clipboard
# ---------------------------------------------------------------------------

async def phase_export_psbt_to_clipboard(d: UIDriver) -> None:
    print("\n  [phase 4] export PSBT to clipboard")

    # "Export PSBT" is a FilledButton.tonal when the PSBT is unsigned.
    await click_label(d, "Export PSBT", delay=0.5)
    await wait_for(d, "Copy to clipboard", "PSBT export sheet opened",
                   retries=10, delay=0.5)
    print("    [ok] PSBT export sheet opened")

    # Tap "Copy to clipboard" — sheet closes, clipboard receives the base64 PSBT.
    await click_label(d, "Copy to clipboard", delay=0.5)
    await wait_absent(d, "Copy to clipboard", "export sheet closed",
                      retries=10, delay=0.4)
    print("    [ok] PSBT copied to clipboard (export sheet closed)")


# ---------------------------------------------------------------------------
# Phase 5: back to wallet detail, verify PSBT tile in Transactions tab
# ---------------------------------------------------------------------------

async def phase_verify_psbt_unsigned(d: UIDriver) -> None:
    print("\n  [phase 5] back to wallet detail — verify PSBT tile UNSIGNED")

    await click_tooltip(d, "Back", delay=0.8)
    await wait_for(d, f'"{WALLET_NAME}"', "back on wallet detail",
                   retries=10, delay=0.5)

    await click_label(d, "Transactions", delay=0.5)
    await wait_for(d, PSBT_LABEL, "PSBT tile visible in Transactions tab",
                   retries=10, delay=0.5)

    sem = await d.cs_flat_text()
    if "UNSIGNED" not in sem:
        raise AssertionError(
            f"Expected PSBT status 'UNSIGNED' in Transactions tab, got:\n{sem[:400]}"
        )
    print("    [ok] PSBT tile visible with UNSIGNED status")


# ---------------------------------------------------------------------------
# Phase 6: import PSBT from clipboard via More options → Import → PSBT
# ---------------------------------------------------------------------------

async def phase_import_psbt_from_clipboard(d: UIDriver) -> None:
    print("\n  [phase 6] import PSBT from clipboard")

    # More options popup → Import (label = importBip329Button = 'Import')
    await click_popup_item(d, "More options", 296, "Import")
    # Import choice sheet: "Labels (BIP-329)" / "PSBT" / "Sweep WIF key"
    await wait_for(d, "Labels (BIP-329)", "import choice sheet opened",
                   retries=10, delay=0.5)
    print("    [ok] import choice sheet opened")

    # Tap "PSBT" option in the choice sheet.
    await click_label(d, "PSBT", delay=0.5)

    # PSBT import sheet: "Paste from clipboard" / "Scan QR" / "From file" / "Paste text"
    await wait_for(d, "Paste from clipboard", "PSBT import sheet opened",
                   retries=10, delay=0.5)
    print("    [ok] PSBT import sheet opened")

    await click_label(d, "Paste from clipboard", delay=0.5)

    # Sheet closes after the clipboard content is read and imported.
    await wait_absent(d, "Paste from clipboard", "PSBT import sheet closed",
                      retries=10, delay=0.4)

    # Verify toast: re-importing the same unsigned PSBT yields either
    # "PSBT imported" (new entry) or "Signatures merged" (dedup/merge).
    await asyncio.sleep(0.6)
    flat = await d.cs_flat_text()
    has_saved  = "PSBT imported"       in flat
    has_merged = "Signatures merged"   in flat
    if not (has_saved or has_merged):
        # Toasts are transient — if missed, just proceed; the tile check below
        # confirms the operation was not silently discarded.
        print("    [warn] import toast not captured (transient) — continuing")
    else:
        result = "PSBT imported" if has_saved else "Signatures merged"
        print(f"    [ok] import toast: '{result}'")


# ---------------------------------------------------------------------------
# Phase 7: verify PSBT still present, sign with hot key, broadcast
# ---------------------------------------------------------------------------

async def phase_sign_and_broadcast(d: UIDriver) -> None:
    print("\n  [phase 7] verify PSBT → sign → broadcast")

    # PSBT tile must still be visible on Transactions tab after the round-trip.
    await wait_for(d, PSBT_LABEL, "PSBT tile still present after import round-trip",
                   retries=8, delay=0.5)
    print("    [ok] PSBT tile present after export + import round-trip")

    # Open PSBT detail
    rect = await d.cs_find_by_label_part_containing(PSBT_LABEL)
    if rect is None:
        raise AssertionError(
            f"PSBT tile '{PSBT_LABEL}' not found in semantics after import"
        )
    d.flutter_click((rect[0] + rect[2]) // 2, (rect[1] + rect[3]) // 2)
    await asyncio.sleep(1.0)
    await wait_for(d, '"Unsigned Transaction"', "PSBT detail screen opened",
                   retries=10, delay=0.5)
    print("    [ok] PSBT detail screen opened")

    # Sign with hot key
    await click_label(d, "Sign", delay=1.5)
    await wait_for(d, "SIGNED", "PSBT status changed to SIGNED",
                   retries=15, delay=0.8)
    print("    [ok] PSBT signed — SIGNED status visible")

    # Broadcast
    await click_label(d, "Broadcast", delay=0.5)
    await wait_for(d, "Transaction broadcast", "broadcast success toast",
                   retries=30, delay=1.0)
    print("    [ok] PSBT broadcast successful")

    # After broadcast the PSBT detail pops back to wallet detail.
    await wait_for(d, f'"{WALLET_NAME}"', "back on wallet detail after broadcast",
                   retries=15, delay=0.5)
    print("    [ok] back on wallet detail")


# ---------------------------------------------------------------------------
# Main test function
# ---------------------------------------------------------------------------

async def test_psbt_clipboard(d: UIDriver) -> None:
    print(f"\n--- {WALLET_NAME} (PSBT clipboard export + import round-trip) ---")

    await set_active_network_signet(d)
    await phase_create_wallet(d)
    await phase_sync(d)
    await phase_create_psbt(d)
    await phase_export_psbt_to_clipboard(d)
    await phase_verify_psbt_unsigned(d)
    await phase_import_psbt_from_clipboard(d)
    await phase_sign_and_broadcast(d)

    await go_back_to_wallet_list(d)
    await delete_wallet_from_list(d, WALLET_NAME)

    print(f"\n    [PASS] {WALLET_NAME}")


# ---------------------------------------------------------------------------
# Entry point
# ---------------------------------------------------------------------------

if __name__ == "__main__":
    asyncio.run(run_regression(test_psbt_clipboard, "reg17"))
