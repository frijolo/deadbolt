#!/usr/bin/env python3
"""
Demo: create a singlesig SegWit wallet on Signet from a known seed.

Flow:
  1.  App launches (sandbox — always empty)
  2.  Dismiss the beta disclaimer
  3.  Navigate to Designer tab
  4.  Create a new "From Scratch" project: Signet / SingleSig / SegWit (P2WPKH)
  5.  Add the seed phrase as a Hot Key
  6.  Build the descriptor
  7.  Create a wallet from the project (Device key protection)
  8.  Sync the wallet
  9.  Review: Transactions → Addresses → Coins tabs

Usage:
  flutter build linux --debug       # build once
  python3 scripts/demo_singlesig_wallet.py
"""

import asyncio
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).parent))
from ui_driver import UIDriver

# ---------------------------------------------------------------------------
# Demo data
# ---------------------------------------------------------------------------

PROJECT_NAME = "Signet SingleSig Demo"
WALLET_NAME  = "Signet Demo Wallet"
SEED = "piece blue stadium control fiction kick group mimic hollow dog mask interest"

# Human-like pacing
STEP  = 0.8
PAUSE = 1.5
LONG  = 3.0
SYNC_TIMEOUT = 60.0

# Navigation drawer Flutter-logical centers (GNOME/Adwaita CSD calibrated)
DRAWER_FX    = 152
DRAWER_FY0   = 74
DRAWER_ITEM_H = 56


def drawer_center(index: int) -> tuple[int, int]:
    return DRAWER_FX, DRAWER_FY0 + index * DRAWER_ITEM_H


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

async def _sem(d: UIDriver) -> str:
    return await d.semantics_tree()


async def wait_sem(d: UIDriver, text: str, desc: str, timeout: float = 10.0):
    """Poll semantics tree until `text` appears."""
    import time
    deadline = time.time() + timeout
    while time.time() < deadline:
        if text in await _sem(d):
            print(f"  ✓  [{desc}]")
            return
        await asyncio.sleep(0.4)
    raise AssertionError(f"Timeout: '{text}' not in semantics — {desc}")


async def tap(d: UIDriver, label: str = "", tooltip: str = "", hint: str = "",
              desc: str = "", delay: float = STEP):
    """Find a semantic node by label / tooltip / hint and click its center."""
    rect = None
    if label:
        rect = await d.find_semantic_rect(label)
    if rect is None and tooltip:
        rect = await d.find_semantic_rect_by_tooltip(tooltip)
    if rect is None and hint:
        rect = await d.find_semantic_rect_by_hint(hint)
    if rect is None:
        raise AssertionError(f"Node not found  label={label!r}  tooltip={tooltip!r}  hint={hint!r}  [{desc}]")
    cx = (rect[0] + rect[2]) // 2
    cy = (rect[1] + rect[3]) // 2
    print(f"  → tap {label or tooltip or hint!r} at ({cx},{cy})  [{desc}]")
    d.flutter_click(cx, cy)
    await asyncio.sleep(delay)


async def tap_and_type(d: UIDriver, text: str, desc: str, label: str = "",
                       hint: str = "", delay: float = STEP):
    """Click a labeled/hinted text field and type text into it."""
    rect = None
    name = label or hint
    if label:
        rect = await d.find_textfield_rect(label)
    if rect is None and hint:
        rect = await d.find_semantic_rect_by_hint(hint)
    if rect is None:
        raise AssertionError(f"Text field not found: label={label!r} hint={hint!r}  [{desc}]")
    cx = (rect[0] + rect[2]) // 2
    cy = (rect[1] + rect[3]) // 2
    print(f"  → tap+type {name!r}='{text[:30]}'  [{desc}]  field@({cx},{cy})")
    d.flutter_click(cx, cy)
    await asyncio.sleep(0.5)
    d.key("ctrl+a")
    await asyncio.sleep(0.2)
    d.type_text(text, delay_ms=60)
    await asyncio.sleep(delay)


# ---------------------------------------------------------------------------
# Step 1 — Dismiss disclaimer
# ---------------------------------------------------------------------------

async def step_dismiss_disclaimer(d: UIDriver):
    print("\n[1] Dismiss beta disclaimer")
    sem = await _sem(d)
    if "Beta Software" not in sem:
        print("  ✓  [disclaimer already gone — skipping]")
        return
    await asyncio.sleep(STEP)
    await tap(d, label="Close", desc="close disclaimer", delay=PAUSE)
    sem = await _sem(d)
    assert "Beta Software" not in sem, "Disclaimer did not close"


# ---------------------------------------------------------------------------
# Step 2 — Navigate to Designer tab
# ---------------------------------------------------------------------------

async def step_navigate_to_designer(d: UIDriver):
    print("\n[2] Navigate to Designer (Projects)")
    sem = await _sem(d)
    if "Go to Designer" in sem:
        # Empty wallets screen has a shortcut button
        await tap(d, label="Go to Designer", desc="go to designer shortcut", delay=PAUSE)
    else:
        await tap(d, tooltip="Open navigation menu", desc="open drawer", delay=PAUSE)
        await wait_sem(d, "Designer", "drawer item visible", timeout=5)
        await tap(d, label="Designer", desc="select Designer", delay=PAUSE)
    await wait_sem(d, "Projects", "AppBar title = Projects")


# ---------------------------------------------------------------------------
# Step 3 — Create project From Scratch (Signet, SingleSig, SegWit)
# ---------------------------------------------------------------------------

async def step_create_project(d: UIDriver):
    print(f"\n[3] Create project '{PROJECT_NAME}'  (Signet / SingleSig / SegWit)")

    # Use the "New" button (visible in empty state or FAB); skip overflow menu
    await tap(d, label="New", desc="new project button", delay=PAUSE)
    await wait_sem(d, "New project", "dialog open")

    # Type project name FIRST while no other widget has focus
    await tap_and_type(d, label="Project name", text=PROJECT_NAME, desc="enter project name")
    await d.screenshot("/tmp/db_step3a.png")

    # Network → Signet
    await tap(d, tooltip="Select network", desc="open network picker")
    await wait_sem(d, "Signet", "network menu visible")
    await tap(d, label="Signet", desc="select Signet", delay=STEP)

    # Wallet type: SingleSig (probably already selected) + SegWit address format
    await wait_sem(d, "SegWit", "wallet type picker visible")
    await tap(d, label="SingleSig", desc="ensure SingleSig policy selected", delay=STEP)
    await tap(d, label="SegWit", desc="select SegWit address format", delay=STEP)
    await wait_sem(d, "→ Segwit (P2WPKH)", "wallet type confirmed as P2WPKH")

    await tap(d, label="Create Project", desc="confirm project creation", delay=LONG)
    # After creation the dialog closes and ProjectDetailScreen opens.
    # The detail screen shows the project name in the AppBar.
    await wait_sem(d, PROJECT_NAME, "project detail screen open", timeout=15)
    print(f"  ✓  Project '{PROJECT_NAME}' created")


# ---------------------------------------------------------------------------
# Step 4 — Add seed phrase as Hot Key
# ---------------------------------------------------------------------------

async def step_add_seed(d: UIDriver):
    print(f"\n[4] Add seed phrase as Hot Key")

    # Navigate to the Keys tab first (project opens on Spend paths tab)
    await tap(d, label="Keys (0)", desc="Keys tab", delay=STEP)
    await tap(d, label="Add key", desc="Add key FAB", delay=PAUSE)
    await wait_sem(d, "Enter manually", "method picker visible")
    await tap(d, label="Enter manually", desc="choose manual entry", delay=PAUSE)

    await wait_sem(d, "Hot Key", "tab chips visible")
    await tap(d, label="Hot Key", desc="select Hot Key tab", delay=STEP)

    await wait_sem(d, "word1 word2 word3", "mnemonic field visible")
    await tap_and_type(d, label="Seed phrase", text=SEED, desc="type seed phrase")
    print(f"  → typed {len(SEED.split())} words, waiting for derivation…")
    # Live derivation: 500 ms debounce + async Rust call
    await asyncio.sleep(LONG)
    await wait_sem(d, "84'", "keyspec derived (derivation path visible)", timeout=15)
    print("  ✓  Keyspec derived")

    await tap(d, label="Add", desc="confirm add key", delay=LONG)
    await wait_sem(d, PROJECT_NAME, "back on project detail", timeout=10)
    print("  ✓  Hot key added")


# ---------------------------------------------------------------------------
# Step 4b — Add spend path and assign the hot key
# ---------------------------------------------------------------------------

async def step_add_spend_path(d: UIDriver):
    print("\n[4b] Add spend path")

    import re as _re

    # Read the key MFP from the Keys tab BEFORE opening any popup.
    # KeyCard subtitle shows MfpBadge(label: mfp.toUpperCase()) — 8 uppercase hex chars.
    await tap(d, label="Keys (1)", desc="Keys tab to read MFP", delay=STEP)
    sem = await _sem(d)
    mfp_matches = _re.findall(r'\b[0-9A-F]{8}\b', sem)
    if not mfp_matches:
        raise AssertionError("Could not find MFP in Keys tab semantics tree")
    key_mfp = mfp_matches[0]
    print(f"  → found key MFP: {key_mfp}")

    # Navigate to Spend paths tab and open the sheet
    await tap(d, label="Spend paths (0)", desc="Spend paths tab", delay=STEP)
    await tap(d, label="Add spend path", desc="open spend path sheet", delay=PAUSE)

    # Bottom sheet opens — wait for the Keys section inside the sheet.
    # Extra sleep lets the DraggableScrollableSheet spring animation fully settle
    # before we try to tap a button inside it (mid-animation the sheet's
    # DragGestureRecognizer can win the gesture arena against the button tap).
    await wait_sem(d, "Keys", "spend path sheet open")
    await asyncio.sleep(LONG)  # wait for sheet to fully settle

    # Find the "+ Add key" PopupMenuButton semantic rect.
    # There may be multiple "Show menu" nodes (priority / threshold menus);
    # we want the one for adding keys, whose rect should be the one with
    # the smallest y-start (topmost "Show menu" in the sheet).
    all_show_menu_rects = await d.find_all_semantic_rects_by_tooltip("Show menu")
    if not all_show_menu_rects:
        all_show_menu_rects = await d.find_all_semantic_rects("Add key")
    if not all_show_menu_rects:
        raise AssertionError("Could not find '+ Add key' button in spend path sheet")
    # Pick the topmost rect (smallest y origin = the Add-key button, not priority/threshold)
    add_key_rect = min(all_show_menu_rects, key=lambda r: r[1])
    print(f"  → found {len(all_show_menu_rects)} 'Show menu' rect(s), using topmost: {add_key_rect}")

    # The semantic rect spans the full Keys section width (0-404).
    # The actual button is LEFT-aligned: icon+text starts at x≈16, ends at x≈110.
    # Use x=57 (visual center of the button) instead of the section center.
    btn_cx = 57
    btn_cy = (add_key_rect[1] + add_key_rect[3]) // 2
    # Ensure window has focus before clicking (terminal might have stolen it
    # during the LONG sleep above).
    d.raise_window()
    await asyncio.sleep(0.3)

    print(f"  → hovering over '+ Add key' at Flutter({btn_cx},{btn_cy})")
    # Hover first to register pointer position in Flutter, then click.
    g = d.window_geometry()
    abs_x = g["x"] + d.csd_x + btn_cx
    abs_y = g["y"] + d.csd_y + btn_cy
    d._input.mouse_move(abs_x, abs_y)
    await asyncio.sleep(0.4)  # let Flutter register hover
    await d.screenshot("/tmp/db_before_addkey_click.png")
    print(f"  → clicking '+ Add key' at Flutter({btn_cx},{btn_cy})")
    d.flutter_click(btn_cx, btn_cy)
    await asyncio.sleep(STEP)
    await d.screenshot("/tmp/db_after_addkey_click.png")

    # Popup menu should now be open — look for MFP in semantics.
    # Retry once with a fresh raise_window in case focus was lost.
    sem = await _sem(d)
    if key_mfp not in sem:
        print(f"  → MFP not found yet, retrying with raise_window…")
        d.raise_window()
        await asyncio.sleep(0.3)
        d._input.mouse_move(abs_x, abs_y)
        await asyncio.sleep(0.3)
        d.flutter_click(btn_cx, btn_cy)
        await asyncio.sleep(STEP)
        sem = await _sem(d)

    if key_mfp in sem:
        print(f"  → MFP {key_mfp} found in semantics, tapping")
        await tap(d, label=key_mfp, desc="select key by MFP", delay=STEP)
    else:
        await d.screenshot("/tmp/db_popup_fail.png")
        raise AssertionError(
            f"Popup did not open — MFP {key_mfp} not in semantics after clicking '+ Add key'"
        )

    # Verify the key was assigned: threshold row becomes "of 1"
    await wait_sem(d, "of 1", "key assigned to spend path", timeout=5)
    print(f"  ✓  Key {key_mfp} assigned")

    # Close the bottom sheet
    d.key("Escape")
    await asyncio.sleep(PAUSE)
    print("  ✓  Spend path added with key")


# ---------------------------------------------------------------------------
# Step 5 — Build the descriptor
# ---------------------------------------------------------------------------

async def step_build_descriptor(d: UIDriver):
    print("\n[5] Build descriptor")
    await wait_sem(d, "Build", "Build FAB visible after adding key")
    await tap(d, label="Build", desc="tap Build FAB", delay=LONG)
    await asyncio.sleep(LONG)
    sem = await _sem(d)
    # Build FAB disappears when isDirty becomes false after analysis
    assert "Building" not in sem, "Descriptor build still in progress"
    print("  ✓  Descriptor built and analyzed")


# ---------------------------------------------------------------------------
# Step 6 — Create wallet from project
# ---------------------------------------------------------------------------

async def step_create_wallet(d: UIDriver):
    print(f"\n[6] Create wallet '{WALLET_NAME}'")

    await tap(d, tooltip="More options", desc="overflow menu", delay=STEP)
    await wait_sem(d, "Create wallet", "Create wallet menu item visible")
    await tap(d, label="Create wallet", desc="open create wallet dialog", delay=PAUSE)

    await wait_sem(d, "Wallet name", "wallet dialog open")
    await tap_and_type(d, label="Wallet name", text=WALLET_NAME, desc="wallet name")

    # Keep Device key (default — no password needed)
    await wait_sem(d, "Device key", "protection options visible")
    await asyncio.sleep(STEP)

    await tap(d, label="Create Wallet", desc="confirm wallet creation", delay=LONG)
    await d.screenshot("/tmp/db_after_create_wallet.png")
    # After creation app navigates to WalletDetailScreen; Overview tab is visible
    await wait_sem(d, "Overview", "wallet detail: Overview tab", timeout=30)
    print(f"  ✓  Wallet '{WALLET_NAME}' created")


# ---------------------------------------------------------------------------
# Step 7 — Sync
# ---------------------------------------------------------------------------

async def step_sync(d: UIDriver):
    print("\n[7] Sync wallet with Signet Electrum")
    await wait_sem(d, "Sync", "Sync button visible")
    await tap(d, label="Sync", desc="trigger sync", delay=PAUSE)
    print(f"  → waiting up to {SYNC_TIMEOUT:.0f}s…")
    await wait_sem(d, "Last synced", "sync completed", timeout=SYNC_TIMEOUT)
    print("  ✓  Sync complete")


# ---------------------------------------------------------------------------
# Step 8 — Browse tabs
# ---------------------------------------------------------------------------

async def step_browse_tabs(d: UIDriver):
    print("\n[8] Review wallet tabs")

    print("  → Transactions tab")
    await tap(d, label="Transactions", desc="tap Transactions tab", delay=PAUSE)
    await asyncio.sleep(PAUSE)
    await d.screenshot("/tmp/deadbolt_demo_transactions.png")

    print("  → Addresses tab")
    await tap(d, label="Addresses", desc="tap Addresses tab", delay=PAUSE)
    await asyncio.sleep(PAUSE)
    await d.screenshot("/tmp/deadbolt_demo_addresses.png")

    print("  → Coins tab")
    await tap(d, label="Coins", desc="tap Coins tab", delay=PAUSE)
    await asyncio.sleep(PAUSE)
    await d.screenshot("/tmp/deadbolt_demo_coins.png")

    print("  ✓  Screenshots: /tmp/deadbolt_demo_*.png")


# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------

async def main():
    d = UIDriver(debug_mouse=True)  # crosshair overlay active for position verification
    try:
        await d.launch()
        d.raise_window()
        await asyncio.sleep(PAUSE)

        await step_dismiss_disclaimer(d)
        await step_navigate_to_designer(d)
        await step_create_project(d)
        await step_add_seed(d)
        await step_add_spend_path(d)
        await step_build_descriptor(d)
        await step_create_wallet(d)
        await step_sync(d)
        await step_browse_tabs(d)

        print("\n✓  Demo completed successfully")

    except AssertionError as e:
        print(f"\n✗  FAIL: {e}")
        try:
            await d.screenshot("/tmp/deadbolt_demo_failure.png")
            print("   Screenshot: /tmp/deadbolt_demo_failure.png")
        except Exception:
            pass
        sys.exit(1)
    except Exception as e:
        print(f"\n✗  ERROR: {e}")
        raise
    finally:
        print("\n[shutdown] Closing…")
        await d.close()


if __name__ == "__main__":
    asyncio.run(main())
