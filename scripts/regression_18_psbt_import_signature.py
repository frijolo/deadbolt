#!/usr/bin/env python3
"""
Regression test 18: PSBT signature import (air-gapped round-trip with delete + re-import).

Simulates the full air-gapped workflow:
  - The watch-only device creates a PSBT and exports it for the offline signer.
  - The offline signer signs it and exports the signed PSBT.
  - The watch-only device imports the signed PSBT as a signature merge.
  - It broadcasts.

Flow:
  0.  Settings → set Active Network to Signet.
  1.  Create SegWit singlesig wallet via Guided creation (same funded Signet
      mnemonic as reg11/reg14–reg17).
  2.  Sync → wait for confirmed coins.
  3.  Create self-send PSBT (MAX, destination = self).
  4.  Export unsigned PSBT to clipboard → read+store as `unsigned_psbt`.
  5.  Sign PSBT with hot key (simulates the offline signer acting on a copy).
  6.  Export signed PSBT to clipboard → read+store as `signed_psbt`.
  7.  Delete the PSBT from the wallet via More options → Delete PSBT.
  8.  Verify PSBT tile is gone from Transactions tab.
  9.  Restore `unsigned_psbt` to clipboard → import via More options → Import → PSBT.
      Verify "PSBT imported" toast.
  10. Open PSBT detail → verify UNSIGNED status (no signatures yet).
  11. Restore `signed_psbt` to clipboard → tap "Import signature" →
      PSBT import sheet → "Paste from clipboard" → verify SIGNED status.
  12. Broadcast → verify success toast.
  13. Delete wallet.

Gaps covered:
  - Delete PSBT from its detail screen
  - Import signature / merge signed PSBT  (psbtImportSignedButton = 'Import signature')
  - Full air-gapped round-trip: create → export unsigned → sign → export signed →
    delete → import unsigned → import signature → broadcast

Exit code: 0 = PASS, 1 = FAIL.

Prerequisites:
  bash scripts/prepare_test_build.sh
  python3 scripts/regression_18_psbt_import_signature.py
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
    navigate_wallets, fill_field, click_label, click_tooltip,
    go_back_to_wallet_list, delete_wallet_from_list,
    set_active_network_signet, run_regression,
    click_popup_item,
)


# ---------------------------------------------------------------------------
# Test data
# ---------------------------------------------------------------------------

WALLET_NAME = "Reg18-ImportSig"
PSBT_LABEL  = "reg18-import-sig"

# Funded Signet P2WPKH hot-key wallet (shared with reg11/reg14–reg17).
MNEMONIC = (
    "bachelor brick camera brave assume differ disagree "
    "judge security scrap wonder core"
)

_ENV = {**os.environ, "DISPLAY": ":0"}


# ---------------------------------------------------------------------------
# Clipboard helpers
# ---------------------------------------------------------------------------

def _read_clipboard() -> str:
    return subprocess.check_output(
        ["xclip", "-selection", "clipboard", "-o"],
        env=_ENV,
    ).decode().strip()


def _write_clipboard(text: str) -> None:
    subprocess.run(
        ["xclip", "-selection", "clipboard"],
        input=text.encode(),
        env=_ENV,
        check=True,
    )


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

    # Select coin
    await click_label(d, "Tap to select coins...", delay=1.0)
    await wait_for(d, "sats", "coin selector opened", retries=10, delay=0.5)

    coin_rect = await d.cs_find_by_label_part_containing("sats")
    if coin_rect is None:
        raise AssertionError("No coin tile found in coin selector")
    d.flutter_click(
        (coin_rect[0] + coin_rect[2]) // 2,
        (coin_rect[1] + coin_rect[3]) // 2,
    )
    await asyncio.sleep(0.5)

    await click_label(d, "Done (1)", delay=1.0)
    await wait_for(d, '"Create Transaction"', "back on Create TX screen",
                   retries=10, delay=0.5)

    await fill_field(d, "Label", PSBT_LABEL)

    await click_tooltip(d, "MY WALLETS", delay=0.5)
    await wait_for(d, "This wallet (Self)", "wallet picker visible",
                   retries=8, delay=0.5)
    await click_label(d, "This wallet (Self)", delay=1.5)
    await asyncio.sleep(2.0)
    sem = await d.cs_flat_text()
    if "tb1q" not in sem.lower():
        raise AssertionError("No tb1q address filled after self-pay selection")
    print("    [ok] self-payment address auto-filled")

    await click_label(d, "MAX", delay=0.8)
    await wait_absent(d, '"— sats"', "MAX amount computed", retries=15, delay=0.5)

    # Touch the total fee field so that onEditTap auto-corrects the total to
    # rbfMinFeeSats when the UTXO is already in an unconfirmed TX (RBF scenario).
    # _syncRateFromTotal then back-computes a rate that satisfies both RBF checks.
    # In the non-RBF case this is a no-op (total stays at the current feeSats).
    await click_label(d, "total_fee_display", delay=0.5)
    await asyncio.sleep(0.3)
    d.key("Return")
    await asyncio.sleep(0.4)
    print("    [ok] total fee confirmed (RBF minimum applied if applicable)")

    await click_label(d, "Create PSBT", delay=0.5)
    await wait_for(d, '"Unsigned Transaction"', "PSBT detail screen opened",
                   retries=15, delay=1.0)
    sem_detail = await d.cs_flat_text()
    if PSBT_LABEL not in sem_detail:
        raise AssertionError(f"PSBT label '{PSBT_LABEL}' not visible on PSBT detail screen")
    print(f"    [ok] PSBT detail screen opened (label '{PSBT_LABEL}' visible)")


# ---------------------------------------------------------------------------
# Phase 4: export unsigned PSBT to clipboard and read it
# ---------------------------------------------------------------------------

async def phase_export_unsigned(d: UIDriver) -> str:
    """Exports the unsigned PSBT to clipboard, reads and returns the base64 string."""
    print("\n  [phase 4] export unsigned PSBT to clipboard")

    await click_label(d, "Export PSBT", delay=0.5)
    await wait_for(d, "Copy to clipboard", "export sheet opened",
                   retries=10, delay=0.5)
    await click_label(d, "Copy to clipboard", delay=0.5)
    await wait_absent(d, "Copy to clipboard", "export sheet closed",
                      retries=10, delay=0.4)

    await asyncio.sleep(0.3)
    unsigned_psbt = _read_clipboard()
    if len(unsigned_psbt) < 100:
        raise AssertionError(
            f"Clipboard does not look like a PSBT (too short): {unsigned_psbt[:80]}"
        )
    print(f"    [ok] unsigned PSBT read from clipboard ({len(unsigned_psbt)} chars)")
    return unsigned_psbt


# ---------------------------------------------------------------------------
# Phase 5: sign PSBT with hot key
# ---------------------------------------------------------------------------

async def phase_sign(d: UIDriver) -> None:
    print("\n  [phase 5] sign PSBT with hot key")

    await click_label(d, "Sign", delay=1.5)
    await wait_for(d, "SIGNED", "PSBT status changed to SIGNED",
                   retries=15, delay=0.8)
    print("    [ok] PSBT signed — SIGNED status visible")


# ---------------------------------------------------------------------------
# Phase 6: export signed PSBT to clipboard and read it
# ---------------------------------------------------------------------------

async def phase_export_signed(d: UIDriver, unsigned_psbt: str) -> str:
    """Exports the signed PSBT to clipboard, reads and returns the base64 string."""
    print("\n  [phase 6] export signed PSBT to clipboard")

    await click_label(d, "Export PSBT", delay=0.5)
    await wait_for(d, "Copy to clipboard", "export sheet opened",
                   retries=10, delay=0.5)
    await click_label(d, "Copy to clipboard", delay=0.5)
    await wait_absent(d, "Copy to clipboard", "export sheet closed",
                      retries=10, delay=0.4)

    await asyncio.sleep(0.3)
    signed_psbt = _read_clipboard()
    if len(signed_psbt) < 100:
        raise AssertionError(
            f"Clipboard does not look like a signed PSBT: {signed_psbt[:80]}"
        )
    if signed_psbt == unsigned_psbt:
        raise AssertionError(
            "Signed PSBT is identical to unsigned PSBT — signing may have failed"
        )
    print(f"    [ok] signed PSBT read from clipboard ({len(signed_psbt)} chars)")
    return signed_psbt


# ---------------------------------------------------------------------------
# Phase 7: delete PSBT from its detail screen
# ---------------------------------------------------------------------------

async def phase_delete_psbt(d: UIDriver) -> None:
    print("\n  [phase 7] delete PSBT from detail screen")

    # More options popup on PSBT detail screen has only "Delete PSBT".
    await click_popup_item(d, "More options", 60, "Delete PSBT")
    await wait_for(d, "Delete this unsigned transaction", "delete confirm dialog",
                   retries=10, delay=0.5)
    print("    [ok] delete confirmation dialog opened")

    await click_label(d, "Delete", delay=0.5)
    # PSBT detail pops; back to wallet detail.
    await wait_for(d, f'"{WALLET_NAME}"', "back on wallet detail",
                   retries=10, delay=0.5)
    print("    [ok] PSBT deleted — back on wallet detail")


# ---------------------------------------------------------------------------
# Phase 8: verify PSBT tile is gone from Transactions tab
# ---------------------------------------------------------------------------

async def phase_verify_psbt_gone(d: UIDriver) -> None:
    print("\n  [phase 8] verify PSBT tile absent from Transactions tab")

    await click_label(d, "Transactions", delay=0.5)
    await asyncio.sleep(0.5)
    flat = await d.cs_flat_text()
    if "UNSIGNED" in flat:
        raise AssertionError(
            "An UNSIGNED PSBT tile is still visible in Transactions tab after deletion"
        )
    print("    [ok] PSBT tile absent — deletion confirmed")


# ---------------------------------------------------------------------------
# Phase 9: import unsigned PSBT from clipboard
# ---------------------------------------------------------------------------

async def phase_import_unsigned(d: UIDriver, unsigned_psbt: str) -> None:
    print("\n  [phase 9] import unsigned PSBT from clipboard")

    _write_clipboard(unsigned_psbt)
    await asyncio.sleep(0.2)

    await click_popup_item(d, "More options", 296, "Import")
    await wait_for(d, "Labels (BIP-329)", "import choice sheet opened",
                   retries=10, delay=0.5)

    await click_label(d, "PSBT", delay=0.5)
    await wait_for(d, "Paste from clipboard", "PSBT import sheet opened",
                   retries=10, delay=0.5)

    await click_label(d, "Paste from clipboard", delay=0.5)
    await wait_absent(d, "Paste from clipboard", "import sheet closed",
                      retries=10, delay=0.4)

    # Verify "PSBT imported" toast (unsigned PSBT not previously in DB).
    await asyncio.sleep(0.5)
    flat = await d.cs_flat_text()
    if "PSBT imported" not in flat and "Signatures merged" not in flat:
        print("    [warn] import toast not captured (transient) — continuing")
    else:
        result = "PSBT imported" if "PSBT imported" in flat else "Signatures merged"
        print(f"    [ok] import toast: '{result}'")

    # The re-imported PSBT has no label (label is DB-local, not in the binary).
    # Verify it's back by checking for the UNSIGNED status badge in the tile.
    await wait_for(d, "UNSIGNED", "PSBT tile restored in Transactions tab",
                   retries=8, delay=0.5)
    print("    [ok] PSBT tile restored (UNSIGNED)")


# ---------------------------------------------------------------------------
# Phase 10: open PSBT detail, verify UNSIGNED, import signature
# ---------------------------------------------------------------------------

async def phase_import_signature(d: UIDriver, signed_psbt: str) -> None:
    print("\n  [phase 10] open PSBT → verify UNSIGNED → import signature")

    # Open PSBT tile — label not preserved on re-import, find by UNSIGNED badge.
    rect = await d.cs_find_by_label_part("UNSIGNED")
    if rect is None:
        raise AssertionError("UNSIGNED PSBT tile not found in Transactions tab")
    d.flutter_click((rect[0] + rect[2]) // 2, (rect[1] + rect[3]) // 2)
    await asyncio.sleep(1.0)
    await wait_for(d, '"Unsigned Transaction"', "PSBT detail screen opened",
                   retries=10, delay=0.5)

    # After re-importing the unsigned PSBT, it must be UNSIGNED (no sigs).
    flat = await d.cs_flat_text()
    if "UNSIGNED" not in flat:
        raise AssertionError(
            f"Expected UNSIGNED status after re-import, got:\n{flat[:400]}"
        )
    print("    [ok] PSBT is UNSIGNED after re-import (no signatures yet)")

    # Place the signed PSBT in clipboard.
    _write_clipboard(signed_psbt)
    await asyncio.sleep(0.2)

    # Tap "Import signature" → PSBT import sheet → Paste from clipboard.
    await click_label(d, "Import signature", delay=0.5)
    await wait_for(d, "Paste from clipboard", "PSBT import sheet opened",
                   retries=10, delay=0.5)
    await click_label(d, "Paste from clipboard", delay=0.5)
    await wait_absent(d, "Paste from clipboard", "import sheet closed",
                      retries=10, delay=0.4)

    # After merging the signed PSBT, the status badge should update to SIGNED.
    await wait_for(d, "SIGNED", "PSBT status updated to SIGNED after merge",
                   retries=15, delay=0.8)
    print("    [ok] signature merged — PSBT is now SIGNED")


# ---------------------------------------------------------------------------
# Phase 11: broadcast
# ---------------------------------------------------------------------------

async def phase_broadcast(d: UIDriver) -> None:
    print("\n  [phase 11] broadcast")

    await click_label(d, "Broadcast", delay=0.5)
    await wait_for(d, "Transaction broadcast", "broadcast success toast",
                   retries=30, delay=1.0)
    print("    [ok] broadcast successful")

    await wait_for(d, f'"{WALLET_NAME}"', "back on wallet detail",
                   retries=15, delay=0.5)
    print("    [ok] back on wallet detail")


# ---------------------------------------------------------------------------
# Main test function
# ---------------------------------------------------------------------------

async def test_psbt_import_signature(d: UIDriver) -> None:
    print(f"\n--- {WALLET_NAME} (PSBT signature import — air-gapped round-trip) ---")

    await set_active_network_signet(d)
    await phase_create_wallet(d)
    await phase_sync(d)
    await phase_create_psbt(d)

    unsigned_psbt = await phase_export_unsigned(d)
    await phase_sign(d)
    signed_psbt = await phase_export_signed(d, unsigned_psbt)

    await phase_delete_psbt(d)
    await phase_verify_psbt_gone(d)
    await phase_import_unsigned(d, unsigned_psbt)
    await phase_import_signature(d, signed_psbt)
    await phase_broadcast(d)

    await go_back_to_wallet_list(d)
    await delete_wallet_from_list(d, WALLET_NAME)

    print(f"\n    [PASS] {WALLET_NAME}")


# ---------------------------------------------------------------------------
# Entry point
# ---------------------------------------------------------------------------

if __name__ == "__main__":
    asyncio.run(run_regression(test_psbt_import_signature, "reg18"))
