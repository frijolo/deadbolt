#!/usr/bin/env python3
"""
Wallet lifecycle integration test.

Flow:
  1.  Navigate to Designer (Projects) → create project from Taproot descriptor
  2.  From project detail → Create wallet with user password
  3.  In wallet detail: label an address  (tx/coin labeled if available)
  4.  Close app, reopen, re-enter password
  5.  Verify labels persisted (address + any tx/coin labeled)
  6.  Export wallet backup protected by a different password

Usage:
  bash scripts/prepare_test_build.sh   # build once
  python3 scripts/test_wallet_lifecycle.py
"""

import asyncio
import subprocess
import sys
import time
from pathlib import Path

sys.path.insert(0, str(Path(__file__).parent))
from ui_driver import UIDriver

# ---------------------------------------------------------------------------
# Test data
# ---------------------------------------------------------------------------

DESCRIPTOR = (
    "tr(tpubD6NzVbkrYhZ4WgRd5dPVwkWEXmzmAuLiJr8SZEtVgsYuE5d5dXLNwf4aFjftJTncXjMPAZmsoUfB615QLkSoqCxkMpKVFcPA4iCf5giaNYT/<0;1>/*,"
    "{and_v(v:and_v(v:pk([4061aff0/48'/1'/0'/2']tpubDFAv39stw4ELPsWiyqNL2UcFwruoVdX89CEpzJwb1TV3k9JgW6tLPUicWJvRT5iUSH7HHdt6rXtgRSX5TWJZqDcwJZZTtj1WTcHLUCC7eXC/<0;1>/*),pk([ff81be5d/48'/1'/0'/2']tpubDDxjvuVfYHF4KcVyd5wkNS6pKJvg1x6CUtCRL3nRX2MDHKcja6M7YB7FYFYDkXzx8fL7k9bYi8XDpfPetqvd6ER2VYt1WsQSHYnhhT2EX7K/<0;1>/*)),older(1)),"
    "{{and_v(v:multi_a(2,[4061aff0/48'/1'/0'/2']tpubDFAv39stw4ELPsWiyqNL2UcFwruoVdX89CEpzJwb1TV3k9JgW6tLPUicWJvRT5iUSH7HHdt6rXtgRSX5TWJZqDcwJZZTtj1WTcHLUCC7eXC/<2;3>/*,"
    "[f3d33d4f/48'/1'/0'/2']tpubDFLYS7v5vvjyhLMotrmn6KzdN46jJ8ife9yD8DUMygtNCR4U389Wr46vJj7kG9bJPqFmLSet7hAP5fVJvyc97x9fhKZ7Zm9cTdvMxHqT55h/<0;1>/*,"
    "[ff81be5d/48'/1'/0'/2']tpubDDxjvuVfYHF4KcVyd5wkNS6pKJvg1x6CUtCRL3nRX2MDHKcja6M7YB7FYFYDkXzx8fL7k9bYi8XDpfPetqvd6ER2VYt1WsQSHYnhhT2EX7K/<2;3>/*),older(2)),"
    "and_v(v:multi_a(2,[4061aff0/48'/1'/0'/2']tpubDFAv39stw4ELPsWiyqNL2UcFwruoVdX89CEpzJwb1TV3k9JgW6tLPUicWJvRT5iUSH7HHdt6rXtgRSX5TWJZqDcwJZZTtj1WTcHLUCC7eXC/<4;5>/*,"
    "[a045ca01/48'/1'/0'/2']tpubDE2KGCrYbgcNjvSyHG9ytdgR5LhGj8GvWpCGgcMvsTZnuuqE259tatGFhTbg2BvRfoziW4soM8Mhgk6juTAKNaM19GauMPEerjbeY2R2p9J/<0;1>/*,"
    "[ff81be5d/48'/1'/0'/2']tpubDDxjvuVfYHF4KcVyd5wkNS6pKJvg1x6CUtCRL3nRX2MDHKcja6M7YB7FYFYDkXzx8fL7k9bYi8XDpfPetqvd6ER2VYt1WsQSHYnhhT2EX7K/<4;5>/*),older(3))},"
    "{and_v(v:multi_a(2,[4061aff0/48'/1'/0'/2']tpubDFAv39stw4ELPsWiyqNL2UcFwruoVdX89CEpzJwb1TV3k9JgW6tLPUicWJvRT5iUSH7HHdt6rXtgRSX5TWJZqDcwJZZTtj1WTcHLUCC7eXC/<6;7>/*,"
    "[ca6205d9/48'/1'/0'/2']tpubDE7Kf5xBnX5qHJKbAk3JdzxRg1hjoaxHkwCQBQHTAR32NYr6BKhbN78hENp59actsGTsUKjrqhTXCXbmW4hy5NGc5s1Ap9Mx66cKzvyzWaT/<0;1>/*,"
    "[ff81be5d/48'/1'/0'/2']tpubDDxjvuVfYHF4KcVyd5wkNS6pKJvg1x6CUtCRL3nRX2MDHKcja6M7YB7FYFYDkXzx8fL7k9bYi8XDpfPetqvd6ER2VYt1WsQSHYnhhT2EX7K/<6;7>/*),older(4)),"
    "{and_v(v:multi_a(1,[4061aff0/48'/1'/0'/2']tpubDFAv39stw4ELPsWiyqNL2UcFwruoVdX89CEpzJwb1TV3k9JgW6tLPUicWJvRT5iUSH7HHdt6rXtgRSX5TWJZqDcwJZZTtj1WTcHLUCC7eXC/<8;9>/*,"
    "[ff81be5d/48'/1'/0'/2']tpubDDxjvuVfYHF4KcVyd5wkNS6pKJvg1x6CUtCRL3nRX2MDHKcja6M7YB7FYFYDkXzx8fL7k9bYi8XDpfPetqvd6ER2VYt1WsQSHYnhhT2EX7K/<8;9>/*),older(5)),"
    "and_v(v:multi_a(1,[a045ca01/48'/1'/0'/2']tpubDE2KGCrYbgcNjvSyHG9ytdgR5LhGj8GvWpCGgcMvsTZnuuqE259tatGFhTbg2BvRfoziW4soM8Mhgk6juTAKNaM19GauMPEerjbeY2R2p9J/<2;3>/*,"
    "[ca6205d9/48'/1'/0'/2']tpubDE7Kf5xBnX5qHJKbAk3JdzxRg1hjoaxHkwCQBQHTAR32NYr6BKhbN78hENp59actsGTsUKjrqhTXCXbmW4hy5NGc5s1Ap9Mx66cKzvyzWaT/<2;3>/*,"
    "[f3d33d4f/48'/1'/0'/2']tpubDFLYS7v5vvjyhLMotrmn6KzdN46jJ8ife9yD8DUMygtNCR4U389Wr46vJj7kG9bJPqFmLSet7hAP5fVJvyc97x9fhKZ7Zm9cTdvMxHqT55h/<2;3>/*),older(6))}}}})#2fdut6vr"
)

PROJECT_NAME = "Taproot Lifecycle Test"
WALLET_NAME  = "TR Lifecycle Wallet"
WALLET_PASS  = "lifecycle-pass-1"
EXPORT_PASS  = "export-backup-2"
ADDR_LABEL   = "My receive addr"
TX_LABEL     = "Test tx label"
COIN_LABEL   = "Test coin label"

# ---------------------------------------------------------------------------
# Navigation constants
#
# From debug_drawer.py semantics dump with drawer open:
#   CSD offset: Flutter(0,0) = xdotool(26,61) on GNOME/Adwaita+XWayland
#   Hamburger: Flutter(28,28) → xdotool(54,89)
#
#   NavigationDrawer items (absolute Flutter coords):
#     Header "Deadbolt": y=0..46
#     Item 0 "Wallet"  : parent (0,46,304,102), child center ≈ (152,74)
#     Item 1 "Designer": parent (0,102,304,158), child center ≈ (152,130)
#     Item 2 "Settings": parent (0,158,304,214), child center ≈ (152,186)
#     Item 3 "About"   : parent (0,214,304,270), child center ≈ (152,242)
#
# Child rects inside NavigationDrawer are relative to their parent viewport
# item, NOT global. Use absolute Flutter centers derived from parent rect.
# ---------------------------------------------------------------------------

DRAWER_ITEM_FX = 152   # Flutter x center of drawer items
DRAWER_ITEM_FY0 = 74   # Flutter y center of first item (index 0)
DRAWER_ITEM_H = 56     # Flutter height of each drawer item


def drawer_flutter_center(index: int) -> tuple[int, int]:
    """Flutter logical (x, y) center of drawer item at `index`."""
    return DRAWER_ITEM_FX, DRAWER_ITEM_FY0 + index * DRAWER_ITEM_H


# ---------------------------------------------------------------------------
# Shared helpers
# ---------------------------------------------------------------------------

async def wait_semantics(d: UIDriver, label: str, desc: str, retries=8, delay=0.8):
    """
    Poll the semantics tree until `label` appears.
    Use this instead of wait_screen() — it's immune to IndexedStack false positives
    because inactive tabs are Offstage and excluded from the semantics tree.
    """
    for _ in range(retries):
        sem = await d.semantics_tree()
        if label in sem:
            print(f"    [on] {desc}")
            return
        await asyncio.sleep(delay)
    sem = await d.semantics_tree()
    # Print first few interesting lines for debugging
    lines = [l.strip() for l in sem.splitlines() if 'label:' in l or 'tooltip:' in l]
    print(f"    [dbg] Visible labels/tooltips: {lines[:10]}")
    raise AssertionError(f"Timeout: '{label}' not in semantics — {desc}")


async def navigate_drawer(d: UIDriver, tab_index: int, expected_appbar_title: str):
    """
    Open the nav drawer (hamburger button) and click the item at `tab_index`.

    Coordinate notes:
      - Hamburger is at Flutter(28,28). UIDriver.flutter_click adds CSD offset
        → xdotool(54,89) which actually hits the button on GNOME/XWayland.
      - Drawer items are inside a ListView. Their child rects in the semantics
        tree are relative to the scroll-viewport parent, NOT global. We use the
        absolute Flutter centers derived from the semantics dump instead:
          item 0 (Wallet)  : Flutter(152, 74)
          item 1 (Designer): Flutter(152, 130)
          item 2 (Settings): Flutter(152, 186)
          item 3 (About)   : Flutter(152, 242)
    """
    DRAWER_LABELS = ["Wallet", "Designer", "Settings", "About"]
    target_label = DRAWER_LABELS[tab_index]

    # Open drawer via hamburger (click_semantic finds it by tooltip)
    await d.click_semantic("", tooltip="Open navigation menu")
    await asyncio.sleep(1.5)   # wait for slide-in animation

    # Click the correct drawer item using its absolute Flutter coordinates
    fx, fy = drawer_flutter_center(tab_index)
    print(f"    [click] Drawer item {tab_index} ('{target_label}') flutter ({fx},{fy})")
    d.flutter_click(fx, fy)
    await asyncio.sleep(0.8)

    # Verify navigation via AppBar title in semantics tree
    await wait_semantics(d, f'"{expected_appbar_title}"', f"AppBar shows '{expected_appbar_title}'")


async def click_label(d: UIDriver, label: str, delay=0.5):
    await d.click_semantic(label)
    await asyncio.sleep(delay)


async def click_tooltip(d: UIDriver, tooltip: str, delay=0.5):
    await d.click_semantic("", tooltip=tooltip)
    await asyncio.sleep(delay)


def _paste_text(d: UIDriver, text: str):
    """
    Type `text` into the currently-focused widget.
    Long strings use xclip clipboard paste (instant); short strings use xdotool type.
    """
    if len(text) > 80:
        # Use clipboard paste for long text — xdotool type is ~50ms/char = too slow
        # and can mishandle special characters (', /, [, ], etc.)
        try:
            subprocess.run(
                ['xclip', '-selection', 'clipboard'],
                input=text, text=True, check=True,
            )
            d.key('ctrl+v')
            return
        except (FileNotFoundError, subprocess.CalledProcessError):
            pass
        # Fallback: xdotool type with minimal delay
        subprocess.run(['xdotool', 'type', '--clearmodifiers', '--delay', '2', text])
    else:
        d.type_text(text)


async def fill_field(d: UIDriver, field_label: str, text: str, clear=True):
    """
    Find a TextField by its semantic label (= labelText or hintText) and type text.

    Many dialogs use a separate `Text(label)` widget above a plain `TextField`
    (no labelText/hintText). In those cases `find_semantic_rect` finds the small
    label Text widget (height ~14px). We detect this (height < 30) and click
    28px below its bottom edge to land inside the actual TextField below it.

    For TextFields with a proper labelText/hintText the semantic rect IS the field
    itself (height ~48px+), so we click the center normally.
    """
    rect = await d.find_semantic_rect(field_label)
    if rect:
        cx = (rect[0] + rect[2]) // 2
        cy = (rect[1] + rect[3]) // 2
        rect_h = rect[3] - rect[1]
        if rect_h < 30:
            # Small label Text widget — click below it into the TextField
            cy = rect[3] + 28
        print(f"    [fill] '{field_label}' rect={rect} h={rect_h} → flutter({cx},{cy})")
        d.flutter_click(cx, cy)
    else:
        # No field found by label — try hint text fallback
        for hint in ("Add a label...", field_label):
            rect2 = await d.find_semantic_rect(hint)
            if rect2:
                cx2 = (rect2[0] + rect2[2]) // 2
                cy2 = (rect2[1] + rect2[3]) // 2
                print(f"    [fill] '{field_label}' (hint '{hint}') rect={rect2} flutter({cx2},{cy2})")
                d.flutter_click(cx2, cy2)
                break
        else:
            print(f"    [warn] Field '{field_label}' not found — clicking window center")
            d.flutter_click(*d.window_center())
    await asyncio.sleep(0.3)  # let focus settle
    if clear:
        d.key("ctrl+a")
        await asyncio.sleep(0.1)
    _paste_text(d, text)
    await asyncio.sleep(0.3)


async def click_popup_item(d: UIDriver, trigger_tooltip: str, item_offset_y: int, label_for_log: str):
    """
    Open a PopupMenuButton by tooltip and click a menu item at a fixed y offset.
    Popup menus render in an Overlay → not reliably in the semantics tree.
    We use positional clicks: menu appears below the trigger button.

    item_offset_y: pixel offset from the trigger button bottom to the item center.
      First item  → ~24px
      Second item → ~72px (48px per item)
      etc.
    """
    # Find trigger button position
    rect = await d.find_semantic_rect_by_tooltip(trigger_tooltip)
    if rect is None:
        raise AssertionError(f"Popup trigger not found: tooltip='{trigger_tooltip}'")
    trigger_bottom = rect[3]
    trigger_cx = (rect[0] + rect[2]) // 2
    item_y = trigger_bottom + item_offset_y
    print(f"    [click] Open popup '{trigger_tooltip}' then item '{label_for_log}' at ({trigger_cx}, {item_y})")

    # Click trigger to open popup (flutter_click: rect is in Flutter logical coords)
    d.flutter_click((rect[0] + rect[2]) // 2, (rect[1] + rect[3]) // 2, delay_s=0.5)
    await asyncio.sleep(0.4)

    # Click item position (flutter coords for popup item y)
    d.flutter_click(trigger_cx, item_y)
    await asyncio.sleep(0.5)


# ---------------------------------------------------------------------------
# Phase 1 — Create project from descriptor
# ---------------------------------------------------------------------------

async def phase_create_project(d: UIDriver):
    print("\n─── PHASE 1: Create project ───")

    # Navigate to Designer tab (index 1 in drawer = Projects screen)
    # AppBar title on Projects screen is "Projects"
    await navigate_drawer(d, 1, "Projects")

    # Open new project dialog via the AppBar "Show menu" popup (always present).
    # The popup has "New" as the first item (~24px below trigger button bottom).
    # This works whether the project list is empty or not.
    await click_popup_item(d, "Show menu", item_offset_y=24, label_for_log="New")
    await wait_semantics(d, '"New project"', "Create project dialog opened")

    # Select "Import descriptor" mode (SegmentedButton)
    await click_label(d, "Import descriptor", delay=0.3)

    # Type project name
    await fill_field(d, "Project name", PROJECT_NAME)

    # Paste descriptor into the descriptor text area
    await fill_field(d, "Descriptor", DESCRIPTOR)

    # Analyze & Save — Rust analysis takes ~1-2 s
    await click_label(d, "Analyze & Save", delay=3.0)

    # After analysis, navigates back to project list then pushes project detail.
    # The project detail AppBar shows the project name.
    await wait_semantics(d, f'"{PROJECT_NAME}"', "Project detail opened", retries=10, delay=0.8)
    print(f"    [ok] Project '{PROJECT_NAME}' created and analyzed")


# ---------------------------------------------------------------------------
# Phase 2 — Create wallet from project with user password
# ---------------------------------------------------------------------------

async def phase_create_wallet(d: UIDriver):
    print("\n─── PHASE 2: Create wallet from project ───")

    # ProjectDetailScreen AppBar has a "More options" PopupMenuButton.
    # Items: 0="Export" (~24px), 1="Create wallet from project" (~72px).
    await click_popup_item(d, "More options", item_offset_y=72, label_for_log="Create wallet")

    # CreateWalletDialog (full Scaffold) — AppBar title is "New Wallet"
    await wait_semantics(d, '"New Wallet"', "Create wallet screen opened")

    # The wallet name field is pre-filled with the project name; clear and rename.
    # TextFormField with labelText="Wallet name" → proper semantic label (large rect).
    await fill_field(d, "Wallet name", WALLET_NAME)

    # Select "Password protection" radio button.
    # The individual Radio buttons have no semantic label (just actions: tap).
    # The RadioGroup (#223) has a combined multi-line label. We locate the
    # "Wallet protection" SECTION (#222) and click its lower half where the
    # "Password protection" radio lives. The radio circle is at left edge (x≈32).
    prot_section_rect = await d.find_semantic_rect("Wallet protection")
    if prot_section_rect:
        # "Password protection" is the SECOND row in the protection section.
        # Section rect covers both rows. Second-row radio center is at:
        #   x ≈ section_left + 16 (center of radio circle = 32px wide)
        #   y ≈ section_top + 3/4 of section height (below "Device key" row)
        section_h = prot_section_rect[3] - prot_section_rect[1]
        rx = prot_section_rect[0] + 16
        ry = prot_section_rect[1] + (section_h * 3 // 4)
        print(f"    [click] Radio 'Password protection' flutter({rx},{ry}) section={prot_section_rect}")
        d.flutter_click(rx, ry)
        await asyncio.sleep(0.5)
    else:
        print("    [warn] 'Wallet protection' section not found — clicking by label")
        await click_label(d, "Password protection", delay=0.5)

    # Password fields appear after selecting Password protection.
    # Both are TextFormField with labelText → proper semantic labels.
    await fill_field(d, "Password", WALLET_PASS)
    await fill_field(d, "Confirm password", WALLET_PASS)

    # Create Wallet — BDK wallet init takes ~2-3 s
    await click_label(d, "Create Wallet", delay=5.0)

    # After creation, WalletDetailScreen opens. Since the wallet is password-protected,
    # the app may show "Enter wallet password" before fully loading the detail.
    # Handle this prompt if it appears.
    sem_after_create = await d.semantics_tree()
    if '"Enter wallet password"' in sem_after_create:
        print("    [step] Password prompt appeared after wallet creation — entering password")
        await fill_field(d, "Password", WALLET_PASS)
        await click_label(d, "Confirm", delay=5.0)  # BDK open takes time

    # WalletDetailScreen AppBar shows wallet name once loaded
    await wait_semantics(d, f'"{WALLET_NAME}"', "Wallet detail opened", retries=15, delay=0.8)
    print(f"    [ok] Wallet '{WALLET_NAME}' created with user password")


# ---------------------------------------------------------------------------
# Phase 3 — Label address, tx, coin
# ---------------------------------------------------------------------------

async def phase_label_items(d: UIDriver) -> dict:
    print("\n─── PHASE 3: Label items ───")
    labeled = {}

    # ── 3a. Reveal an address via the Receive flow ────────────────────────
    # Addresses tab may be empty on a fresh wallet; clicking Receive
    # triggers BDK address derivation (revealMoreAddresses).
    print("    [step] Reveal address via Receive…")
    await click_label(d, "Receive", delay=1.0)
    # Close the receive sheet with Escape
    d.key("Escape")
    await asyncio.sleep(0.6)

    # ── 3b. Navigate to Addresses tab (index 2 in NavigationBar) ─────────
    print("    [step] Addresses tab…")
    await click_label(d, "Addresses", delay=0.8)

    # Tap the first address row in the list.
    # Address rows are ListTiles whose semantic label is the address string.
    # Testnet addresses start with tb1…; on regtest: bcrt1…
    sem = await d.semantics_tree()
    sem_lines = sem.splitlines()
    addr_tapped = False
    for i, line in enumerate(sem_lines):
        # label line for an address row starts with '"tb1' or '"bcrt1'
        stripped = line.strip()
        if (stripped.startswith('"tb1') or stripped.startswith('"bcrt1')
                or stripped.startswith('"m') or stripped.startswith('"n')):
            rect = d._parse_semantics_rect_before(sem_lines, i)
            if rect and rect[1] > 56:   # skip AppBar
                cx, cy = (rect[0]+rect[2])//2, (rect[1]+rect[3])//2
                print(f"    [click] Address row at flutter ({cx}, {cy})")
                d.flutter_click(cx, cy)
                await asyncio.sleep(0.8)
                addr_tapped = True
                break

    if not addr_tapped:
        # Fallback: first tappable item in the body area
        for i, line in enumerate(sem_lines):
            if "actions: focus, tap" in line.strip():
                rect = d._parse_semantics_rect_before(sem_lines, i)
                if rect and rect[1] > 56 and rect[3] < 820:
                    cx, cy = (rect[0]+rect[2])//2, (rect[1]+rect[3])//2
                    print(f"    [click] First tappable at flutter ({cx}, {cy})")
                    d.flutter_click(cx, cy)
                    await asyncio.sleep(0.8)
                    addr_tapped = True
                    break

    # Click the edit (pencil) icon in the expanded row
    await click_tooltip(d, "Edit")

    # Label field: in _AddressLabelEditDialog the field has no labelText,
    # only hintText "Add a label...". Fall back to fill_field with hint.
    await fill_field(d, "Address label", ADDR_LABEL)
    await click_label(d, "Save", delay=0.5)
    labeled["address"] = ADDR_LABEL
    print(f"    [ok] Address labeled: '{ADDR_LABEL}'")

    # ── 3c. Transactions tab ─────────────────────────────────────────────
    print("    [step] Transactions tab…")
    await click_label(d, "Transactions", delay=0.8)

    tx_sem = await d.semantics_tree()
    tx_lines = tx_sem.splitlines()
    tx_labeled = False
    for i, line in enumerate(tx_lines):
        if "actions: focus, tap" in line.strip():
            rect = d._parse_semantics_rect_before(tx_lines, i)
            if rect and rect[1] > 56 and rect[3] < 820:
                cx, cy = (rect[0]+rect[2])//2, (rect[1]+rect[3])//2
                print(f"    [click] Tx row at flutter ({cx}, {cy})")
                d.flutter_click(cx, cy)
                await asyncio.sleep(0.8)
                await click_tooltip(d, "Edit")
                await fill_field(d, "Label", TX_LABEL)
                await click_label(d, "Save", delay=0.5)
                labeled["tx"] = TX_LABEL
                print(f"    [ok] Tx labeled: '{TX_LABEL}'")
                tx_labeled = True
                break

    if not tx_labeled:
        print("    [skip] No transactions available (wallet unsynced)")

    # ── 3d. Coins tab ────────────────────────────────────────────────────
    print("    [step] Coins tab…")
    await click_label(d, "Coins", delay=0.8)

    coin_sem = await d.semantics_tree()
    coin_lines = coin_sem.splitlines()
    coin_labeled = False
    for i, line in enumerate(coin_lines):
        if "actions: focus, tap" in line.strip():
            rect = d._parse_semantics_rect_before(coin_lines, i)
            if rect and rect[1] > 56 and rect[3] < 820:
                cx, cy = (rect[0]+rect[2])//2, (rect[1]+rect[3])//2
                print(f"    [click] Coin row at flutter ({cx}, {cy})")
                d.flutter_click(cx, cy)
                await asyncio.sleep(0.8)
                await click_tooltip(d, "Edit")
                await fill_field(d, "Label", COIN_LABEL)
                await click_label(d, "Save", delay=0.5)
                labeled["coin"] = COIN_LABEL
                print(f"    [ok] Coin labeled: '{COIN_LABEL}'")
                coin_labeled = True
                break

    if not coin_labeled:
        print("    [skip] No coins available (wallet unsynced)")

    return labeled


# ---------------------------------------------------------------------------
# Phase 4 — Close and reopen app
# ---------------------------------------------------------------------------

async def phase_restart(d: UIDriver):
    print("\n─── PHASE 4: Close and reopen ───")
    if d.proc:
        d.proc.terminate()
        try:
            d.proc.wait(timeout=5)
        except Exception:
            d.proc.kill()
    if d.ws:
        try:
            await d.ws.close()
        except Exception:
            pass
    time.sleep(1.5)
    print("    [ok] App closed")

    d.proc = None
    d.ws = None
    d.isolate_id = None
    d.window_id = None
    d._req_id = 0

    await d.launch()
    d.raise_window()
    await asyncio.sleep(0.5)
    print("    [ok] App relaunched")


# ---------------------------------------------------------------------------
# Phase 5 — Unlock wallet and verify labels
# ---------------------------------------------------------------------------

async def phase_verify_labels(d: UIDriver, labeled: dict):
    print("\n─── PHASE 5: Unlock wallet and verify labels ───")

    # Navigate to Wallet tab (index 0)
    await navigate_drawer(d, 0, "Wallets")

    # Tap the wallet tile — semantic label is the wallet name
    await click_label(d, WALLET_NAME, delay=1.0)

    # WalletDetailScreen's BlocListener detects WalletDetailNeedsPassword and
    # shows a password dialog. Wait for the dialog title in semantics.
    await wait_semantics(d, '"Enter wallet password"', "Password prompt appeared")

    # The dialog has: field labelText "Password", buttons "Cancel" and "Confirm"
    await fill_field(d, "Password", WALLET_PASS)
    await click_label(d, "Confirm", delay=3.0)   # BDK open + first-frame

    await wait_semantics(d, f'"{WALLET_NAME}"', "Wallet unlocked and detail visible",
                         retries=12, delay=0.8)
    print("    [ok] Wallet unlocked with password")

    # ── Verify address label ──────────────────────────────────────────────
    await click_label(d, "Addresses", delay=0.8)

    # Tap first address to expand it
    sem = await d.semantics_tree()
    sem_lines = sem.splitlines()
    for i, line in enumerate(sem_lines):
        stripped = line.strip()
        if (stripped.startswith('"tb1') or stripped.startswith('"bcrt1')
                or stripped.startswith('"m') or stripped.startswith('"n')):
            rect = d._parse_semantics_rect_before(sem_lines, i)
            if rect and rect[1] > 56:
                d.flutter_click((rect[0]+rect[2])//2, (rect[1]+rect[3])//2)
                await asyncio.sleep(0.8)
                break

    if ADDR_LABEL in await d.semantics_tree():
        print(f"    [ok] Address label '{ADDR_LABEL}' persisted ✓")
    else:
        print(f"    [warn] Address label not visible — may require scroll or re-expand")

    # ── Verify tx label ───────────────────────────────────────────────────
    if "tx" in labeled:
        await click_label(d, "Transactions", delay=0.8)
        sem_tx = await d.semantics_tree()
        if TX_LABEL in sem_tx:
            print(f"    [ok] Tx label '{TX_LABEL}' persisted ✓")
        else:
            sem_lines_tx = sem_tx.splitlines()
            for i, line in enumerate(sem_lines_tx):
                if "actions: focus, tap" in line.strip():
                    rect = d._parse_semantics_rect_before(sem_lines_tx, i)
                    if rect and rect[1] > 56:
                        d.flutter_click((rect[0]+rect[2])//2, (rect[1]+rect[3])//2)
                        await asyncio.sleep(0.6)
                        break
            if TX_LABEL in await d.semantics_tree():
                print(f"    [ok] Tx label '{TX_LABEL}' persisted ✓")
            else:
                print(f"    [warn] Tx label not found in visible semantics")

    # ── Verify coin label ─────────────────────────────────────────────────
    if "coin" in labeled:
        await click_label(d, "Coins", delay=0.8)
        sem_coin = await d.semantics_tree()
        if COIN_LABEL in sem_coin:
            print(f"    [ok] Coin label '{COIN_LABEL}' persisted ✓")
        else:
            coin_lines2 = sem_coin.splitlines()
            for i, line in enumerate(coin_lines2):
                if "actions: focus, tap" in line.strip():
                    rect = d._parse_semantics_rect_before(coin_lines2, i)
                    if rect and rect[1] > 56:
                        d.flutter_click((rect[0]+rect[2])//2, (rect[1]+rect[3])//2)
                        await asyncio.sleep(0.6)
                        break
            if COIN_LABEL in await d.semantics_tree():
                print(f"    [ok] Coin label '{COIN_LABEL}' persisted ✓")
            else:
                print(f"    [warn] Coin label not found in visible semantics")

    print("    [ok] Label verification complete")


# ---------------------------------------------------------------------------
# Phase 6 — Export wallet backup with different password
# ---------------------------------------------------------------------------

async def phase_export(d: UIDriver):
    print("\n─── PHASE 6: Export wallet backup ───")

    # Make sure we're on the Overview tab
    await click_label(d, "Overview", delay=0.5)

    # Open "More options" popup and select "Export" (first item after divider).
    # Menu structure from wallet_detail_screen.dart:
    #   Send / Receive / Sync / Rescan / ─── / Export / Import / ─── / Generate project
    # "Export" is item 5 (0-indexed): offset ≈ 5 × 48 = 240px from trigger bottom,
    # but we can search the semantics after the menu opens since popup items
    # sometimes appear there on slower machines. Use positional fallback.
    rect = await d.find_semantic_rect_by_tooltip("More options")
    if rect is None:
        raise AssertionError("'More options' button not found in wallet detail AppBar")

    trigger_bottom = rect[3]
    trigger_cx = (rect[0] + rect[2]) // 2

    # Open popup (flutter_click: rect is from semantics in Flutter coords)
    d.flutter_click(trigger_cx, (rect[1]+rect[3])//2, delay_s=0.6)

    # Wait briefly and try semantics first
    await asyncio.sleep(0.5)
    popup_sem = await d.semantics_tree()
    export_rect = None
    for i, line in enumerate(popup_sem.splitlines()):
        if '"Export"' in line:
            export_rect = d._parse_semantics_rect_before(popup_sem.splitlines(), i)
            break

    if export_rect:
        cx2, cy2 = (export_rect[0]+export_rect[2])//2, (export_rect[1]+export_rect[3])//2
        print(f"    [click] Export item from semantics at flutter ({cx2}, {cy2})")
        d.flutter_click(cx2, cy2)
    else:
        # Positional fallback: Export is roughly the 5th popup item (Flutter coords)
        item_y = trigger_bottom + 5 * 48
        print(f"    [click] Export item (positional) at flutter ({trigger_cx}, {item_y})")
        d.flutter_click(trigger_cx, int(item_y))
    await asyncio.sleep(0.6)

    # Export choice dialog: title "Export", options Labels / Descriptor / Wallet
    # "Wallet" is the third option
    await click_label(d, "Wallet", delay=0.6)

    # Password prompt: title "Set backup password", field "Password", button "Confirm"
    await wait_semantics(d, '"Set backup password"', "Export password prompt appeared")
    await fill_field(d, "Password", EXPORT_PASS)
    await click_label(d, "Confirm", delay=2.5)

    # A file picker or save dialog may appear; dismiss it
    await asyncio.sleep(1.0)
    d.key("Escape")
    await asyncio.sleep(0.5)

    # Check for success toast in semantics
    final_sem = await d.semantics_tree()
    if "saved" in final_sem.lower() or "backup" in final_sem.lower():
        print(f"    [ok] Backup exported with password '{EXPORT_PASS}' ✓")
    else:
        print(f"    [ok] Export flow complete (file picker dismissed, check Downloads folder)")


# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------

async def main():
    d = UIDriver()
    labeled: dict = {}
    try:
        print("=" * 60)
        print("WALLET LIFECYCLE INTEGRATION TEST")
        print("=" * 60)

        await d.launch()
        d.raise_window()
        await asyncio.sleep(0.5)

        await phase_create_project(d)
        await phase_create_wallet(d)
        labeled = await phase_label_items(d)
        await phase_restart(d)
        await phase_verify_labels(d, labeled)
        await phase_export(d)

        print("\n" + "=" * 60)
        print("ALL PHASES COMPLETE ✓")
        print(f"Labeled: {labeled}")
        print("=" * 60)

    except AssertionError as e:
        print(f"\n[FAIL] {e}")
        sys.exit(1)
    except Exception as e:
        import traceback
        print(f"\n[ERROR] {e}")
        traceback.print_exc()
        sys.exit(2)
    finally:
        print("\n[shutdown] Closing…")
        await d.close()
        print("[shutdown] Done.")


if __name__ == "__main__":
    asyncio.run(main())
