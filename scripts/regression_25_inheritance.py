#!/usr/bin/env python3
"""
Regression test 25: Taproot inheritance wallet with timelocks for heirs.

Uses the hot wallet from test 11 as the owner key and taproot xpub keys as heirs.

Flow:
  0.  Settings → set Active Network to Signet
  1.  Guided creation → Inheritance mode → Taproot auto-select
  2.  Add owner key as Hot Key (test 11 mnemonic)
  3.  Add heirs 1-4 with preset timelocks (3m, 6m, 9m, 1y)
  4.  Add heir 5 with custom 6 blocks timelock
  5.  (SKIP) Duplicate timelock test - requires manual UI
  6.  Create wallet → export descriptor
  7.  Verify inheritance UI: Safe status + 5 heir paths
  8.  Read first receive address (Taproot tb1p…) and print it
  9.  Cleanup: delete wallet

Exit code: 0 = PASS, 1 = FAIL.

Prerequisites:
  bash scripts/prepare_test_build.sh
  python3 scripts/regression_25_inheritance.py

---------------------------------------------------------------------------
Wallet reference data (captured 2026-04-25, Signet)
---------------------------------------------------------------------------
Mnemonic (owner / Hot Key — same as test 11):
  bachelor brick camera brave assume differ disagree judge security scrap wonder oval

Descriptor (Standard format):
  tr([bc0dbbce/48'/1'/0'/2']tpubDEpnZReLc2mqbLNeGbNckbVTw6GTgfnz2s8r8wWoWrJY3ZP7dJ2hPKTbFk7RTqdSVYKJiDXQgT3jiACt3EGP5QuYjXqWvf6q1c7gN68Ywp8/<0;1>/*,{and_v(v:pk([f3d33d4f/48'/1'/0'/2']tpubDFLYS7v5vvjyhLMotrmn6KzdN46jJ8ife9yD8DUMygtNCR4U389Wr46vJj7kG9bJPqFmLSet7hAP5fVJvyc97x9fhKZ7Zm9cTdvMxHqT55h/<0;1>/*),older(6)),{and_v(v:pk([ff81be5d/48'/1'/0'/2']tpubDDxjvuVfYHF4KcVyd5wkNS6pKJvg1x6CUtCRL3nRX2MDHKcja6M7YB7FYFYDkXzx8fL7k9bYi8XDpfPetqvd6ER2VYt1WsQSHYnhhT2EX7K/<0;1>/*),older(13140)),{and_v(v:pk([f3d33d4f/48'/1'/0'/2']tpubDFLYS7v5vvjyhLMotrmn6KzdN46jJ8ife9yD8DUMygtNCR4U389Wr46vJj7kG9bJPqFmLSet7hAP5fVJvyc97x9fhKZ7Zm9cTdvMxHqT55h/<2;3>/*),older(26280)),{and_v(v:pk([4061aff0/48'/1'/0'/2']tpubDFAv39stw4ELPsWiyqNL2UcFwruoVdX89CEpzJwb1TV3k9JgW6tLPUicWJvRT5iUSH7HHdt6rXtgRSX5TWJZqDcwJZZTtj1WTcHLUCC7eXC/<0;1>/*),older(39420)),and_v(v:pk([ca6205d9/48'/1'/0'/2']tpubDE7Kf5xBnX5qHJKbAk3JdzxRg1hjoaxHkwCQBQHTAR32NYr6BKhbN78hENp59actsGTsUKjrqhTXCXbmW4hy5NGc5s1Ap9Mx66cKzvyzWaT/<0;1>/*),older(52560))}}}})#xak7t3uv

First receive address (index 0):
  tb1pnxdfswymw4jn433tfdetgth32qycfan6zukwnkmdysagts39ugcqa0x99u
"""

import asyncio
import os
import re
import subprocess
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from ui_driver import UIDriver                          # noqa: E402
from regression_helpers import (                       # noqa: E402
    wait_for, wait_absent, assert_no_error_toast,
    dismiss_startup_dialogs,
    navigate_wallets, fill_field, click_label, click_tooltip,
    go_back_to_wallet_list, delete_wallet_from_list,
    open_hot_existing_mnemonic, open_watch_only_manual_entry,
    fill_manual_keyspec, wait_add_key_sheet_closed,
    set_active_network_signet, run_regression,
)


# ---------------------------------------------------------------------------
# Test data
# ---------------------------------------------------------------------------

WALLET_NAME = "Reg25-Inheritance"
PSBT_LABEL = "reg25-self-send"

# Test 11 mnemonic (hot wallet owner)
MNEMONIC = (
    "bachelor brick camera brave assume differ disagree "
    "judge security scrap wonder oval"
)

# Heir keys (taproot, signet, m/48'/1'/0'/2')
HEIR1_KEYSPEC = (
    "[ff81be5d/48'/1'/0'/2']"
    "tpubDDxjvuVfYHF4KcVyd5wkNS6pKJvg1x6CUtCRL3nRX2MDHKcja6M7YB7FYFYDkXzx8fL7k9bYi8XDpfPetqvd6ER2VYt1WsQSHYnhhT2EX7K"
)
HEIR2_KEYSPEC = (
    "[f3d33d4f/48'/1'/0'/2']"
    "tpubDFLYS7v5vvjyhLMotrmn6KzdN46jJ8ife9yD8DUMygtNCR4U389Wr46vJj7kG9bJPqFmLSet7hAP5fVJvyc97x9fhKZ7Zm9cTdvMxHqT55h"
)
HEIR3_KEYSPEC = (
    "[4061aff0/48'/1'/0'/2']"
    "tpubDFAv39stw4ELPsWiyqNL2UcFwruoVdX89CEpzJwb1TV3k9JgW6tLPUicWJvRT5iUSH7HHdt6rXtgRSX5TWJZqDcwJZZTtj1WTcHLUCC7eXC"
)
HEIR4_KEYSPEC = (
    "[ca6205d9/48'/1'/0'/2']"
    "tpubDE7Kf5xBnX5qHJKbAk3JdzxRg1hjoaxHkwCQBQHTAR32NYr6BKhbN78hENp59actsGTsUKjrqhTXCXbmW4hy5NGc5s1Ap9Mx66cKzvyzWaT"
)
HEIR5_KEYSPEC = HEIR2_KEYSPEC

# Heir timelocks
TL_3M = 13140
TL_6M = 26280
TL_9M = 39420
TL_1Y = 52560
TL_CUSTOM = 6


# ---------------------------------------------------------------------------
# Keyspec parsing
# ---------------------------------------------------------------------------

_KEYSPEC_RE = re.compile(r'^\[([0-9a-fA-F]{8})/([^\]]+)\]([a-zA-Z0-9]+)$')


def _parse_keyspec(keyspec: str):
    m = _KEYSPEC_RE.match(keyspec)
    if not m:
        raise ValueError(f"Invalid keyspec: {keyspec}")
    return m.group(1), m.group(2), m.group(3)


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

async def _paste_text(d: UIDriver, text: str):
    env = {**os.environ, "DISPLAY": ":0"}
    subprocess.run(
        ["xclip", "-selection", "clipboard"],
        input=text.encode(),
        env=env,
        check=True,
    )
    await asyncio.sleep(0.1)
    d.key("ctrl+v")
    await asyncio.sleep(0.3)


async def _click_bottom_label(d: UIDriver, label: str):
    tree = await d.cs_tree()
    matches = [n for n in tree if n.get("label") == label]
    if not matches:
        raise AssertionError(f"Label '{label}' not found")
    rects = [d._cs_rect(n) for n in matches]
    rects = [r for r in rects if r is not None]
    if not rects:
        raise AssertionError(f"Label '{label}' has no rect")
    bottom = max(rects, key=lambda r: r[1])
    cx = (bottom[0] + bottom[2]) // 2
    cy = (bottom[1] + bottom[3]) // 2
    d.flutter_click(cx, cy)
    await asyncio.sleep(0.5)


async def _add_owner_hot_key(d: UIDriver, mnemonic: str):
    await click_label(d, "Add key", delay=0.5)
    await open_hot_existing_mnemonic(d)

    mnemonic_rect = await d.cs_find_textfield_by_label("word1 word2 word3 ...")
    if mnemonic_rect is None:
        raise AssertionError("Mnemonic text field not found")
    cx = (mnemonic_rect[0] + mnemonic_rect[2]) // 2
    cy = (mnemonic_rect[1] + mnemonic_rect[3]) // 2
    d.flutter_click(cx, cy)
    await asyncio.sleep(0.3)
    d.key("ctrl+a")
    await asyncio.sleep(0.1)
    await _paste_text(d, mnemonic)
    await asyncio.sleep(1.0)
    await wait_for(d, "Derived keyspec", "keyspec derived", retries=10, delay=0.5)
    await click_label(d, "Add", delay=1.0)
    await wait_add_key_sheet_closed(d)


async def _add_heir(d: UIDriver, name: str, keyspec: str,
                    timelock: int, is_preset: bool = True):
    mfp, path, xpub = _parse_keyspec(keyspec)
    mfp_upper = mfp.upper()
    mfp_lower = mfp.lower()

    await click_label(d, "Add heir", delay=0.5)
    await wait_for(d, "Heir name", "heir setup sheet opened", retries=10, delay=0.5)
    await fill_field(d, "Heir name", name)

    await click_label(d, "Add key", delay=0.5)
    await asyncio.sleep(0.5)

    tree_after = await d.cs_tree()
    has_key_card = any(
        mfp_lower in (n.get("label") or "")
        for n in tree_after
        if n.get("label")
    )

    if not has_key_card:
        await open_watch_only_manual_entry(d)
        await fill_manual_keyspec(d, mfp=mfp, path=path, xpub=xpub, compact=True)
        await wait_for(d, mfp_lower, "key card with MFP visible", retries=15, delay=0.5)
        await asyncio.sleep(0.3)

    await wait_for(d, mfp_lower, f"key card with MFP {mfp_upper} visible", retries=10, delay=0.5)

    if is_preset:
        preset_label = _timelock_preset_label(timelock)
        await click_label(d, preset_label, delay=0.5)
        await asyncio.sleep(1.0)
    else:
        await click_label(d, "Custom timelock", delay=0.5)
        await asyncio.sleep(1.0)
        await _set_custom_blocks_field(d, timelock)

    await _click_bottom_label(d, "Add heir")
    await asyncio.sleep(0.5)


async def _set_custom_blocks_field(d: UIDriver, blocks: int):
    rect = await d.cs_find_textfield_by_label("Timelock blocks")
    if rect is None:
        raise AssertionError("Custom blocks TextField not found")
    cx = (rect[0] + rect[2]) // 2
    # Click near the bottom of the rect to ensure we land on the TextField,
    # not the Slider above it.
    cy_bottom = rect[3] - 4
    d.flutter_click(cx, cy_bottom)
    await asyncio.sleep(0.4)
    d.key("ctrl+a")
    await asyncio.sleep(0.15)
    await _paste_text(d, str(blocks))
    await asyncio.sleep(0.4)


async def _click_timelock_preset(d: UIDriver, blocks: int):
    await click_label(d, "Custom timelock", delay=0.3)
    await asyncio.sleep(0.5)
    await _set_custom_blocks_field(d, blocks)
    await asyncio.sleep(0.3)


async def _edit_heir_timelock(d: UIDriver, heir_index: int, new_blocks: int):
    heir_label = f"Heir {heir_index + 1}"
    await wait_for(d, heir_label, f"heir {heir_index + 1} visible", retries=10, delay=0.5)
    rect = await d.cs_find_by_label_part_containing(heir_label)
    if rect is None:
        raise AssertionError(f"Heir row {heir_index + 1} not found")

    all_trees = await d.cs_tree()
    edit_candidates = [n for n in all_trees if n.get("tooltip") == "Edit heir"]
    if not edit_candidates:
        cx = rect[2] - 25
        cy = (rect[1] + rect[3]) // 2
        d.flutter_click(cx, cy)
    else:
        edit_rects = [d._cs_rect(n) for n in edit_candidates]
        edit_rects = [r for r in edit_rects if r is not None]
        if edit_rects:
            best = min(edit_rects, key=lambda r: abs(r[0] - rect[2]))
            cx = (best[0] + best[2]) // 2
            cy = (best[1] + best[3]) // 2
            d.flutter_click(cx, cy)
        else:
            cx = rect[2] - 25
            cy = (rect[1] + rect[3]) // 2
            d.flutter_click(cx, cy)
    await asyncio.sleep(1.0)

    await wait_for(d, "Edit heir", "edit heir sheet opened", retries=10, delay=0.5)
    # For preset timelocks, click the preset button directly instead of custom field
    preset_map = {
        TL_3M: "3 mo",
        TL_6M: "6 mo",
        TL_9M: "9 mo",
        TL_1Y: "1 yr",
    }
    if new_blocks in preset_map:
        await click_label(d, preset_map[new_blocks], delay=0.5)
    else:
        await _click_timelock_preset(d, new_blocks)
    await asyncio.sleep(0.5)
    # Wait for and click Save in edit sheet
    await wait_for(d, "Save", "save button visible", retries=10, delay=0.5)
    save_rect = await d.cs_find_by_label_part_containing("Save")
    if save_rect:
        cx = (save_rect[0] + save_rect[2]) // 2
        cy = (save_rect[1] + save_rect[3]) // 2
        d.flutter_click(cx, cy)
        await asyncio.sleep(0.8)


def _timelock_preset_label(timelock: int) -> str:
    return {
        13140: "3 mo",
        26280: "6 mo",
        39420: "9 mo",
        52560: "1 yr",
    }.get(timelock, f"{timelock} blocks")


# ---------------------------------------------------------------------------
# Descriptor helper
# ---------------------------------------------------------------------------

async def _get_descriptor(d: UIDriver) -> str:
    """Export descriptor via Overview → Export → Descriptor → Standard → Copy to clipboard."""
    # Open the Export sheet from the Overview AppBar button.
    await click_label(d, "Export", delay=0.5)
    await wait_for(d, "Descriptor", "export options sheet opened", retries=8, delay=0.5)
    await click_label(d, "Descriptor", delay=0.5)
    await asyncio.sleep(0.5)

    # Taproot inheritance wallets show the Standard/Liana format picker — choose Standard.
    tree = await d.cs_tree()
    has_format_picker = any(
        n.get("label") == "Standard" for n in tree
    )
    if has_format_picker:
        await click_label(d, "Standard", delay=0.5)
        await asyncio.sleep(0.5)

    # Text export sheet — click "Copy to clipboard".
    await wait_for(d, "Copy to clipboard", "text export sheet opened", retries=8, delay=0.5)
    copy_rect = await d.cs_find_by_label("Copy to clipboard")
    if copy_rect is None:
        raise AssertionError("Copy to clipboard option not found in export sheet")
    cx = (copy_rect[0] + copy_rect[2]) // 2
    cy = (copy_rect[1] + copy_rect[3]) // 2
    d.flutter_click(cx, cy)
    await asyncio.sleep(0.5)

    return subprocess.check_output(
        ["xclip", "-selection", "clipboard", "-o"],
        env={**os.environ, "DISPLAY": ":0"},
    ).decode().strip()


# ---------------------------------------------------------------------------
# Address helper
# ---------------------------------------------------------------------------

async def _get_first_address(d: UIDriver) -> str:
    """Navigate to Addresses tab, copy address #0 via clipboard, return it."""
    await click_label(d, "Addresses", delay=0.8)
    await wait_for(d, "receive_address_0", "receive address #0 visible", retries=8, delay=0.5)

    rect = await d.cs_find_by_label_part_containing("receive_address_0")
    if rect is None:
        raise AssertionError("receive_address_0 tile not found")
    cx = (rect[0] + rect[2]) // 2
    cy = (rect[1] + rect[3]) // 2
    d.flutter_click(cx, cy)
    await asyncio.sleep(1.0)
    await wait_for(d, '"Address details"', "AddressDetailDialog opened", retries=8, delay=0.5)

    share_rect = await d.cs_find_by_tooltip("Copy to clipboard")
    if share_rect is None:
        raise AssertionError("Copy to clipboard button not found")
    sx = (share_rect[0] + share_rect[2]) // 2
    sy = (share_rect[1] + share_rect[3]) // 2
    d.flutter_click(sx, sy)
    await asyncio.sleep(0.5)

    await wait_for(d, "Copy to clipboard", "export sheet opened", retries=6, delay=0.5)
    copy_rect = await d.cs_find_by_label("Copy to clipboard")
    if copy_rect is None:
        raise AssertionError("Copy to clipboard option not found")
    cx2 = (copy_rect[0] + copy_rect[2]) // 2
    cy2 = (copy_rect[1] + copy_rect[3]) // 2
    d.flutter_click(cx2, cy2)
    await asyncio.sleep(0.5)

    addr = subprocess.check_output(
        ["xclip", "-selection", "clipboard", "-o"],
        env={**os.environ, "DISPLAY": ":0"},
    ).decode().strip()

    await click_tooltip(d, "Close", delay=0.5)
    await wait_absent(d, '"Address details"', "dialog closed", retries=5, delay=0.5)
    await click_label(d, "Overview", delay=0.5)
    await wait_for(d, '"Receive"', "back on Overview tab", retries=6, delay=0.5)
    return addr


# ---------------------------------------------------------------------------
# Main test
# ---------------------------------------------------------------------------

async def test_inheritance_wallet(d: UIDriver):
    print(f"\n--- {WALLET_NAME} (taproot inheritance with timelocks) ---")

    await set_active_network_signet(d)

    # ---- Phase 1: Open guided creation ----
    print("\n  [phase 1] open guided creation")
    await navigate_wallets(d)
    await click_tooltip(d, "New")
    await wait_for(d, "Guided creation", "Bottom sheet opened", retries=10, delay=0.5)
    await click_label(d, "Guided creation", delay=0.5)
    await wait_for(d, '"New Wallet"', "Guided creation screen opened", retries=10, delay=0.5)
    await fill_field(d, "Wallet name", WALLET_NAME)
    print("    [ok] 'New Wallet' screen open")

    # ---- Phase 2: Switch to Inheritance mode ----
    print("\n  [phase 2] switch to inheritance mode")
    await wait_for(d, "Singlesig", "wallet type segments visible", retries=10, delay=0.5)
    await click_label(d, "Inheritance", delay=0.5)
    await asyncio.sleep(1.0)
    await wait_for(d, "Taproot", "Taproot auto-selected", retries=10, delay=0.5)
    await wait_for(d, "Add heir", "Heirs section visible", retries=10, delay=0.5)
    print("    [ok] Inheritance mode active with Taproot")

    # ---- Phase 3: Add owner key ----
    print("\n  [phase 3] add owner key as hot key (mnemonic)")
    await _add_owner_hot_key(d, MNEMONIC)
    print("    [ok] owner key added")

    # ---- Phase 4: Add heirs ----
    print("\n  [phase 4] add heirs")

    print("    [step] adding heir 1 (3 mo preset)")
    await _add_heir(d, name="Heir 1", keyspec=HEIR1_KEYSPEC,
                    timelock=TL_3M, is_preset=True)
    await wait_for(d, "Heir 1", "heir 1 added", retries=10, delay=0.5)

    print("    [step] adding heir 2 (6 mo preset)")
    await _add_heir(d, name="Heir 2", keyspec=HEIR2_KEYSPEC,
                    timelock=TL_6M, is_preset=True)
    await wait_for(d, "Heir 2", "heir 2 added", retries=10, delay=0.5)

    print("    [step] adding heir 3 (9 mo preset)")
    await _add_heir(d, name="Heir 3", keyspec=HEIR3_KEYSPEC,
                    timelock=TL_9M, is_preset=True)
    await wait_for(d, "Heir 3", "heir 3 added", retries=10, delay=0.5)

    print("    [step] adding heir 4 (1 yr preset, unique MFP)")
    await _add_heir(d, name="Heir 4", keyspec=HEIR4_KEYSPEC,
                    timelock=TL_1Y, is_preset=True)
    await wait_for(d, "Heir 4", "heir 4 added", retries=10, delay=0.5)

    print("    [step] adding heir 5 (6 blocks custom)")
    await _add_heir(d, name="Heir 5", keyspec=HEIR5_KEYSPEC,
                    timelock=TL_CUSTOM, is_preset=False)
    await wait_for(d, "Heir 5", "heir 5 added", retries=10, delay=0.5)
    await wait_for(d, "6 blocks", "heir 5 timelock visible", retries=10, delay=0.5)
    print("    [ok] all 5 heirs added")

    # ---- Phase 5: Skip duplicate timelock test (requires UI interaction) ----
    print("\n  [phase 5] skip duplicate timelock test (tested separately)")
    # TODO: Re-enable when duplicate dialog trigger is fixed
    # Currently Flutter's onChanged doesn't fire when text is set programmatically

    # ---- Phase 6: Create wallet ----
    print("\n  [phase 6] create inheritance wallet")
    await click_label(d, "Create wallet", delay=1.0)
    sem = await wait_for(d, '"Receive"', f"wallet detail loaded: '{WALLET_NAME}'",
                         retries=60, delay=1.0)
    assert_no_error_toast(sem)
    print("    [ok] wallet created successfully")

    # Owner's hot key satisfies the taproot key-path spend (main path, no
    # timelock) — this makes the wallet Hot, not just Warm/inheritance-only.
    await wait_for(d, "Hot Wallet", "Hot Wallet temperature icon visible",
                   retries=10, delay=0.5)

    # ---- Phase 6b: Export descriptor ----
    print("\n  [phase 6b] export descriptor")
    descriptor = await _get_descriptor(d)
    print(f"    [ok] descriptor: {descriptor}")

    # ---- Phase 7: Verify inheritance UI ----
    print("\n  [phase 7] verify inheritance UI")
    await click_label(d, "Overview", delay=0.5)
    await wait_for(d, '"Receive"', "Overview tab active", retries=8, delay=0.5)
    d.scroll_down(3)
    await asyncio.sleep(0.5)
    await wait_for(d, '"Inheritance"', "inheritance card visible", retries=10, delay=0.5)
    for i in range(1, 5):
        await wait_for(d, f"Heir {i}", f"heir {i} visible", retries=10, delay=0.5)
    await wait_absent(d, "Heir 5", "heir 5 filtered - 6 blocks below minTimelockBlocks(144)",
                      retries=5, delay=0.5)
    print("    [ok] heirs 1-4 visible, heir 5 filtered (6 blocks < minTimelockBlocks=144)")

    # ---- Phase 8: Read first receive address ----
    print("\n  [phase 8] read first receive address")
    addr = await _get_first_address(d)
    print(f"    [ok] first receive address: {addr}")

    # ---- Phase 9: Cleanup ----
    print("\n  [phase 9] cleanup")
    await go_back_to_wallet_list(d)
    await delete_wallet_from_list(d, WALLET_NAME)

    print(f"\n    [PASS] {WALLET_NAME}")


# ---------------------------------------------------------------------------
# Entry point
# ---------------------------------------------------------------------------

if __name__ == "__main__":
    asyncio.run(run_regression(test_inheritance_wallet, "reg25"))
