#!/usr/bin/env python3
"""
Regression test 14: Seed export and WIF export from a hot-key wallet.

Flow:
  0.  Settings → set Active Network to Signet
  1.  Create SegWit singlesig wallet via Guided creation (Enter manually →
      Hot Key → mnemonic)
  2.  Seed export — Descriptor tab → tap key card → View seed phrase →
      confirm dialog → SeedExportScreen:
        a. Words tab: verify mnemonic words visible
        b. QR Code tab: verify format selector (Standard SeedQR / Compact SeedQR)
        c. Paper Guide tab: verify segment guide visible
  3.  WIF export — Addresses tab → tap first address → address details
      dialog → share button → text export sheet → Export private key (WIF) →
      type confirm phrase → Show WIF → verify WIF visible
  4.  Delete wallet

Exit code: 0 = PASS, 1 = FAIL.

Prerequisites:
  bash scripts/prepare_test_build.sh
  python3 scripts/regression_14_export_seed.py
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
)


# ---------------------------------------------------------------------------
# Test data
# ---------------------------------------------------------------------------

WALLET_NAME = "Reg14-SeedExport"

# 12-word mnemonic — same wallet as reg13 (funded Signet singlesig P2WPKH).
MNEMONIC = (
    "bachelor brick camera brave assume differ disagree "
    "judge security scrap wonder core"
)

# First and last word of the mnemonic — used to verify the Words tab.
MNEMONIC_FIRST_WORD = "bachelor"
MNEMONIC_LAST_WORD  = "core"

# Confirm phrase required by the WIF export dialog.
WIF_CONFIRM_PHRASE = "my full wallet is at risk"

_ENV = {**os.environ, "DISPLAY": ":0"}


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

async def _go_back_to_wallet_list(d: UIDriver):
    for _ in range(4):
        await click_tooltip(d, "Back", delay=0.8)
        sem = await d.semantics_tree()
        if '"Wallets"' in sem:
            break
    await wait_for(d, '"Wallets"', "back on wallet list")
    print("    [ok] back on wallet list")


async def _delete_wallet(d: UIDriver, wallet_name: str):
    await wait_for(d, wallet_name, "wallet card visible")
    rect = await d.find_semantic_rect_by_tooltip("More options")
    if rect is None:
        raise AssertionError("'More options' button not found on wallet card")
    d.flutter_click((rect[0] + rect[2]) // 2, (rect[1] + rect[3]) // 2,
                    delay_s=0.5)
    await asyncio.sleep(0.6)
    item_rect = await d.find_semantic_rect("Delete")
    if item_rect is None:
        raise AssertionError("'Delete' item not found in popup")
    d.flutter_click((item_rect[0] + item_rect[2]) // 2,
                    (item_rect[1] + item_rect[3]) // 2)
    await asyncio.sleep(0.4)
    await wait_for(d, '"Delete wallet"', "delete confirmation dialog")
    await click_label(d, "Delete", delay=1.0)
    await wait_absent(d, wallet_name, f"'{wallet_name}' removed from list")
    print(f"    [ok] wallet '{wallet_name}' deleted")


# ---------------------------------------------------------------------------
# Phase 0: configure Signet
# ---------------------------------------------------------------------------

async def phase_set_network_signet(d: UIDriver):
    print("\n  [phase 0] set Active Network to Signet")
    await navigate_wallets(d)
    await click_label(d, "Select network", delay=0.5)
    await wait_for(d, "Signet", "network picker sheet opened",
                   retries=10, delay=0.5)
    await click_label(d, "Signet", delay=1.0)
    print("    [ok] Active Network set to Signet")


# ---------------------------------------------------------------------------
# Phase 1: create wallet via Guided creation with Hot Key
# ---------------------------------------------------------------------------

async def phase_create_wallet_guided(d: UIDriver):
    """Create a SegWit singlesig wallet with a hot key."""
    print(f"\n  [phase 1] create wallet via Guided creation: {WALLET_NAME}")

    await navigate_wallets(d)
    await click_tooltip(d, "New")
    await wait_for(d, "Guided creation", "bottom sheet opened")
    await click_label(d, "Guided creation", delay=0.5)
    await wait_for(d, '"New Wallet"', "Guided creation screen opened")
    print("    [ok] New Wallet screen open")

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
    print("    [ok] Hot Key tab active")

    await fill_field(d, "Seed phrase", MNEMONIC)
    print("    [ok] mnemonic entered")

    await wait_for(d, "Derived keyspec", "keyspec derived from mnemonic",
                   retries=20, delay=1.0)
    print("    [ok] keyspec derived")

    await click_label(d, "Add", delay=1.0)
    await wait_for(d, "Remove key", "key tile visible in New Wallet screen",
                   retries=15, delay=0.8)
    print("    [ok] hot key added")

    await click_label(d, "Create wallet", delay=1.0)
    await wait_for(d, '"Receive"', f"wallet detail loaded: '{WALLET_NAME}'",
                   retries=30, delay=1.0)
    print(f"    [ok] wallet detail opened: '{WALLET_NAME}'")


# ---------------------------------------------------------------------------
# Phase 2: seed export (Words, QR Code, Paper Guide)
# ---------------------------------------------------------------------------

async def phase_seed_export(d: UIDriver):
    """Navigate Descriptor tab → tap hot key card → export seed via all tabs."""
    print("\n  [phase 2] seed export")

    # Navigate to Descriptor tab (index 4 in bottom nav).
    await click_label(d, "Descriptor", delay=0.8)
    # DescriptorView has 3 inner sub-tabs: "Spend paths (N)", "Keys (N)", "Descriptor".
    # The default selected sub-tab is index 0 (Spend paths).
    # We need the "Keys (N)" sub-tab — its exact label depends on key count.
    await wait_for(d, "Keys (", "Descriptor view loaded with Keys sub-tab",
                   retries=10, delay=0.5)
    keys_tab_rect = await d.find_semantic_rect_containing("Keys (")
    if keys_tab_rect is None:
        raise AssertionError("'Keys (N)' sub-tab not found in Descriptor view")
    d.flutter_click((keys_tab_rect[0] + keys_tab_rect[2]) // 2,
                    (keys_tab_rect[1] + keys_tab_rect[3]) // 2)
    await asyncio.sleep(0.6)
    await wait_for(d, '"HOT"', "key card with HOT badge visible in Keys sub-tab",
                   retries=10, delay=0.5)
    print("    [ok] Keys sub-tab — HOT key card visible")

    # Tap the key card.  The card is a ListTile; clicking the HOT badge text
    # (which is inside the card's title Row) activates the same onTap.
    hot_rect = await d.find_semantic_rect("HOT")
    if hot_rect is None:
        raise AssertionError("HOT badge not found in Descriptor tab")
    d.flutter_click((hot_rect[0] + hot_rect[2]) // 2,
                    (hot_rect[1] + hot_rect[3]) // 2)
    await asyncio.sleep(0.8)

    await wait_for(d, "View seed phrase", "key sheet opened",
                   retries=10, delay=0.5)
    print("    [ok] key sheet opened")

    # Click "View seed phrase" button.
    await click_label(d, "View seed phrase", delay=0.5)
    await wait_for(d, "Show seed", "confirm dialog opened",
                   retries=10, delay=0.5)
    print("    [ok] confirm dialog opened")

    # Confirm — "Show seed" button.
    await click_label(d, "Show seed", delay=0.5)
    await wait_for(d, '"Seed Export"', "SeedExportScreen opened",
                   retries=10, delay=0.8)
    print("    [ok] SeedExportScreen opened")

    # ── Tab 0: Words ──────────────────────────────────────────────────────
    sem_words = await d.semantics_tree()
    if MNEMONIC_FIRST_WORD not in sem_words:
        raise AssertionError(
            f"First mnemonic word '{MNEMONIC_FIRST_WORD}' not visible on Words tab"
        )
    if MNEMONIC_LAST_WORD not in sem_words:
        raise AssertionError(
            f"Last mnemonic word '{MNEMONIC_LAST_WORD}' not visible on Words tab"
        )
    print(f"    [ok] Words tab — '{MNEMONIC_FIRST_WORD}' ... '{MNEMONIC_LAST_WORD}' visible")

    # Verify "Copy to clipboard" button is present.
    if "Copy to clipboard" not in sem_words:
        raise AssertionError("'Copy to clipboard' button not found on Words tab")
    print("    [ok] Words tab — Copy to clipboard button present")

    # ── Tab 1: QR Code ────────────────────────────────────────────────────
    await click_label(d, "QR Code", delay=0.8)
    sem_qr = await wait_for(d, "Standard SeedQR", "QR Code tab loaded",
                             retries=10, delay=0.5)
    if "Compact SeedQR" not in sem_qr:
        raise AssertionError("'Compact SeedQR' segment button not found on QR tab")
    print("    [ok] QR Code tab — Standard SeedQR / Compact SeedQR selector visible")

    # ── Tab 2: Paper Guide ────────────────────────────────────────────────
    await click_label(d, "Paper Guide", delay=0.8)
    sem_guide = await wait_for(d, "Tap QR to advance", "Paper Guide tab loaded",
                                retries=10, delay=0.5)
    if "Next" not in sem_guide and "Done" not in sem_guide:
        raise AssertionError(
            "Paper Guide tab: neither 'Next' nor 'Done' navigation button found"
        )
    print("    [ok] Paper Guide tab — segment guide visible with navigation buttons")

    # Navigate back to wallet detail.
    await click_tooltip(d, "Back", delay=0.8)
    await wait_for(d, '"HOT"', "back on Descriptor tab",
                   retries=10, delay=0.5)
    print("    [ok] back on Descriptor tab")


# ---------------------------------------------------------------------------
# Phase 3: WIF export
# ---------------------------------------------------------------------------

async def phase_wif_export(d: UIDriver):
    """Navigate Addresses tab → open first address details → export WIF."""
    print("\n  [phase 3] WIF export")

    # Navigate to Addresses tab.
    await click_label(d, "Addresses", delay=0.8)
    await wait_for(d, "tb1q", "addresses visible in Addresses tab",
                   retries=15, delay=0.8)
    print("    [ok] Addresses tab — receive addresses visible")

    # Tap the first tb1q address tile.
    addr_rect = await d.find_semantic_rect("tb1q")
    if addr_rect is None:
        raise AssertionError("No tb1q address found in Addresses tab")
    d.flutter_click((addr_rect[0] + addr_rect[2]) // 2,
                    (addr_rect[1] + addr_rect[3]) // 2)
    await asyncio.sleep(0.8)
    await wait_for(d, "Address details", "address details dialog opened",
                   retries=10, delay=0.5)
    print("    [ok] address details dialog opened")

    # Tap the share/copy icon button (tooltip: "Copy to clipboard") to open
    # the text export sheet which contains the WIF export option.
    share_rect = await d.find_semantic_rect_by_tooltip("Copy to clipboard")
    if share_rect is None:
        raise AssertionError(
            "'Copy to clipboard' icon button not found in address details dialog"
        )
    d.flutter_click((share_rect[0] + share_rect[2]) // 2,
                    (share_rect[1] + share_rect[3]) // 2)
    await asyncio.sleep(0.6)
    await wait_for(d, "Export private key (WIF)", "text export sheet opened",
                   retries=10, delay=0.5)
    print("    [ok] text export sheet opened — WIF option visible")

    # Tap "Export private key (WIF)".
    await click_label(d, "Export private key (WIF)", delay=0.5)
    await wait_for(d, "my full wallet is at risk", "WIF confirm dialog opened",
                   retries=10, delay=0.5)
    print("    [ok] WIF confirm dialog opened")

    # Type the confirm phrase into the TextField.
    phrase_field = await d.find_textfield_rect("my full wallet is at risk")
    if phrase_field is None:
        raise AssertionError(
            "Confirm phrase TextField not found in WIF export dialog"
        )
    mx = (phrase_field[0] + phrase_field[2]) // 2
    my = (phrase_field[1] + phrase_field[3]) // 2
    d.flutter_click(mx, my)
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

    # "Show WIF" button should now be enabled.
    await click_label(d, "Show WIF", delay=0.8)
    await wait_for(d, "WIF private key", "WIF display dialog opened",
                   retries=10, delay=0.8)
    print("    [ok] WIF display dialog opened — 'WIF private key' label visible")

    # Close the WIF display dialog.
    await click_label(d, "Close", delay=0.5)
    await asyncio.sleep(0.5)
    print("    [ok] WIF display dialog closed")


# ---------------------------------------------------------------------------
# Main test function
# ---------------------------------------------------------------------------

async def test_seed_export(d: UIDriver):
    print(f"\n--- {WALLET_NAME} (seed export & WIF export) ---")

    await phase_set_network_signet(d)
    await phase_create_wallet_guided(d)
    await phase_seed_export(d)
    await phase_wif_export(d)

    await _go_back_to_wallet_list(d)
    await _delete_wallet(d, WALLET_NAME)

    print(f"\n    [PASS] {WALLET_NAME}")


# ---------------------------------------------------------------------------
# Entry point
# ---------------------------------------------------------------------------

async def main():
    d = UIDriver(sandbox=True)
    try:
        await d.launch()
        d.raise_window()
        await dismiss_startup_dialogs(d)

        await test_seed_export(d)

        print(f"\n{'='*50}")
        print("[RESULT] PASS")

    except AssertionError as exc:
        print(f"\n[FAIL] {exc}")
        await d.close()
        sys.exit(1)
    except Exception as exc:
        print(f"\n[ERROR] {exc}")
        await d.close()
        raise
    finally:
        try:
            await d.close()
        except Exception:
            pass


if __name__ == "__main__":
    asyncio.run(main())
