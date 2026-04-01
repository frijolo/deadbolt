#!/usr/bin/env python3
"""
Shared helpers for Deadbolt regression tests.

Usage:
  from regression_helpers import (
      wait_for, wait_absent,
      navigate_designer, navigate_wallets,
      click_label, click_tooltip,
      fill_field, click_popup_item,
      create_project, go_back, delete_project_from_list,
  )
"""

import asyncio
import os
import re
import subprocess


# ---------------------------------------------------------------------------
# Navigation drawer
# ---------------------------------------------------------------------------
# Drawer layout (from debug_drawer.py semantics dump, GNOME/Adwaita):
#   item 0 "Wallet"   → Flutter center (152,  74)
#   item 1 "Designer" → Flutter center (152, 130)
#   item 2 "Settings" → Flutter center (152, 186)
#   item 3 "About"    → Flutter center (152, 242)
_DRAWER_FX  = 152
_DRAWER_FY0 = 74
_DRAWER_FH  = 56


async def dismiss_startup_dialogs(d):
    """
    Dismiss any dialogs that appear on first launch (e.g. beta disclaimer).
    Call this once right after UIDriver.launch() before any navigation.
    Safe to call even if no dialogs are showing.
    """
    await asyncio.sleep(1.2)   # let the app settle + dialogs render
    sem = await d.semantics_tree()

    # Beta disclaimer dialog: title = "Beta Software — Use at Your Own Risk"
    # Buttons: "Don't show for 7 days" | "Close"
    if "Beta Software" in sem or "disclaimerTitle" in sem:
        print("    [startup] Beta disclaimer visible — closing")
        # Prefer "Don't show for 7 days" so the dialog stays suppressed for the
        # rest of the test run (avoids re-appearing between sub-tests).
        await click_label(d, "Don't show for 7 days", delay=0.8)
        sem2 = await d.semantics_tree()
        if "Beta Software" in sem2:
            # Fallback: try the plain Close button
            await click_label(d, "Close", delay=0.8)
            sem2 = await d.semantics_tree()
        if "Beta Software" in sem2:
            raise AssertionError("[startup] Beta disclaimer could not be dismissed")

    print("    [startup] ready")


_DRAWER_LABELS = ["Wallet", "Designer", "Settings", "About"]


async def navigate_drawer(d, tab_index: int, expected_title: str):
    """Open the hamburger drawer and tap the item at `tab_index`.

    Tries to click by semantic label first (robust against layout shifts).
    Falls back to fixed coordinates if the label is not found within the
    drawer open animation window.
    """
    await d.click_semantic("", tooltip="Open navigation menu")
    # Wait for the drawer open animation to complete.
    await asyncio.sleep(1.5)

    label = _DRAWER_LABELS[tab_index] if tab_index < len(_DRAWER_LABELS) else None
    if label:
        rect = await d.find_semantic_rect(label)
        if rect:
            cx = (rect[0] + rect[2]) // 2
            cy = (rect[1] + rect[3]) // 2
            print(f"    [drawer] item {tab_index} '{label}' flutter ({cx},{cy})")
            d.flutter_click(cx, cy)
        else:
            fx = _DRAWER_FX
            fy = _DRAWER_FY0 + tab_index * _DRAWER_FH
            print(f"    [drawer] item {tab_index} (fallback coords) flutter ({fx},{fy})")
            d.flutter_click(fx, fy)
    else:
        fx = _DRAWER_FX
        fy = _DRAWER_FY0 + tab_index * _DRAWER_FH
        print(f"    [drawer] item {tab_index} at flutter ({fx},{fy})")
        d.flutter_click(fx, fy)

    await asyncio.sleep(0.8)
    await wait_for(d, f'"{expected_title}"', f"AppBar shows '{expected_title}'")


async def navigate_designer(d):
    """Navigate to the Designer (Projects) tab."""
    await navigate_drawer(d, 1, "Projects")


async def navigate_wallets(d):
    """Navigate to the Wallet tab."""
    await navigate_drawer(d, 0, "Wallets")


# ---------------------------------------------------------------------------
# Wait helpers
# ---------------------------------------------------------------------------

async def wait_for(
    d, label: str, desc: str = "", retries: int = 12, delay: float = 0.8
) -> str:
    """
    Poll the semantics tree until `label` appears as a substring.
    Returns the semantics string on success.
    Raises AssertionError on timeout.
    """
    for _ in range(retries):
        sem = await d.semantics_tree()
        if label in sem:
            if desc:
                print(f"    [ok] {desc}")
            return sem
        await asyncio.sleep(delay)
    # Timeout — dump visible labels for debugging
    sem = await d.semantics_tree()
    visible = [ln.strip() for ln in sem.splitlines()
               if "label:" in ln or "tooltip:" in ln]
    print(f"    [dbg] visible labels/tooltips: {visible[:20]}")
    raise AssertionError(
        f"Timeout: '{label}' not found in semantics"
        + (f" — {desc}" if desc else "")
    )


async def wait_absent(
    d, label: str, desc: str = "", retries: int = 10, delay: float = 0.5
):
    """Poll until `label` disappears from the semantics tree."""
    for _ in range(retries):
        sem = await d.semantics_tree()
        if label not in sem:
            if desc:
                print(f"    [ok] {desc}")
            return
        await asyncio.sleep(delay)
    raise AssertionError(
        f"Timeout: '{label}' still present in semantics"
        + (f" — {desc}" if desc else "")
    )


def assert_no_error_toast(sem: str):
    """Raise if a Rust/Dart error toast is visible in the semantics tree."""
    low = sem.lower()
    error_patterns = ["error", "failed", "exception", "anyhowexception"]
    for pat in error_patterns:
        if pat in low:
            # Extract the snippet around the match for context
            idx = low.index(pat)
            snippet = sem[max(0, idx - 40): idx + 80].strip()
            raise AssertionError(f"Error indicator found in semantics: ...{snippet}...")


def extract_tab_count(sem: str, tab_prefix: str) -> int | None:
    """
    Extract the count from a tab label like 'Keys (3)' or 'Spend paths (2)'.

    Args:
        tab_prefix: e.g. "Keys" or "Spend paths"
    Returns the integer count, or None if not found.
    """
    # Flutter tab labels include accessibility text: "Keys (1)\nTab 2 of 3"
    # so we cannot require the closing quote immediately after the count.
    pattern = rf'"{re.escape(tab_prefix)} \((\d+)\)'
    m = re.search(pattern, sem)
    return int(m.group(1)) if m else None


# ---------------------------------------------------------------------------
# Interaction helpers
# ---------------------------------------------------------------------------

async def click_label(d, label: str, delay: float = 0.5):
    """Click a semantic node by its label text."""
    await d.click_semantic(label)
    await asyncio.sleep(delay)


async def click_tooltip(d, tooltip: str, delay: float = 0.5):
    """Click a semantic node by its tooltip."""
    await d.click_semantic("", tooltip=tooltip)
    await asyncio.sleep(delay)


async def _paste_text(d, text: str):
    """
    Insert text into the focused widget via clipboard (xclip + Ctrl+V).
    Using the clipboard avoids keyboard-layout issues with AltGr characters
    ({, }, [, ], #, etc.) and is much faster than key-by-key injection for
    long strings like descriptors.
    """
    env = {**os.environ, "DISPLAY": ":0"}
    subprocess.run(
        ["xclip", "-selection", "clipboard"],
        input=text.encode(),
        env=env,
        check=True,
    )
    await asyncio.sleep(0.1)
    d.key("ctrl+v")
    await asyncio.sleep(0.2)


async def fill_field(d, field_label: str, text: str, clear: bool = True):
    """
    Click a form field by its semantic label and type `text`.

    Handles two cases:
      - Large rect (height ≥ 30): labelText/hintText field — click center.
      - Small rect (height < 30): separate label Text widget above a plain
        TextField — click 28px below the label's bottom edge.
    """
    rect = await d.find_semantic_rect(field_label)
    if rect:
        cx = (rect[0] + rect[2]) // 2
        cy = (rect[1] + rect[3]) // 2
        if (rect[3] - rect[1]) < 30:
            cy = rect[3] + 28
        d.flutter_click(cx, cy)
    else:
        # Hint-text fallback
        for hint in ("Add a label...", field_label):
            r2 = await d.find_semantic_rect(hint)
            if r2:
                d.flutter_click((r2[0] + r2[2]) // 2, (r2[1] + r2[3]) // 2)
                break
        else:
            print(f"    [warn] field '{field_label}' not found — clicking center")
            d.flutter_click(*d.window_center())
    await asyncio.sleep(0.3)
    if clear:
        d.key("ctrl+a")
        await asyncio.sleep(0.1)
    await _paste_text(d, text)
    await asyncio.sleep(0.3)


async def click_popup_item(
    d, trigger_tooltip: str, item_offset_y: int, label: str
):
    """
    Open a PopupMenuButton (located by tooltip) and click the menu item with
    the given `label` text. The item is located by its semantic label after the
    popup opens, making the click robust against layout changes.

    `item_offset_y` is kept for backward compatibility but ignored — label
    search is used instead. Coordinate fallback uses the offset if the label
    isn't found in semantics.
    """
    rect = await d.find_semantic_rect_by_tooltip(trigger_tooltip)
    if rect is None:
        raise AssertionError(f"Popup trigger not found: tooltip='{trigger_tooltip}'")
    cx = (rect[0] + rect[2]) // 2
    cy = (rect[1] + rect[3]) // 2
    # Click trigger to open popup
    d.flutter_click(cx, cy, delay_s=0.5)
    await asyncio.sleep(0.6)
    # Find item by label (works regardless of popup position relative to trigger)
    item_rect = await d.find_semantic_rect(label)
    if item_rect is not None:
        ix = (item_rect[0] + item_rect[2]) // 2
        iy = (item_rect[1] + item_rect[3]) // 2
        print(f"    [popup] '{trigger_tooltip}' → '{label}' flutter ({ix},{iy})")
        d.flutter_click(ix, iy)
    else:
        # Fallback: coordinate-based click
        item_y = rect[3] + item_offset_y
        print(f"    [popup] '{trigger_tooltip}' → '{label}' (fallback) flutter ({cx},{item_y})")
        d.flutter_click(cx, item_y)
    await asyncio.sleep(0.5)


# ---------------------------------------------------------------------------
# Project helpers
# ---------------------------------------------------------------------------

async def create_project(d, name: str, descriptor: str):
    """
    Create a project via the project-list → 'New' button → bottom sheet
    → 'From descriptor' → CreateProjectDialog in import mode.

    Project list AppBar has an '+' IconButton (tooltip='New') that opens a
    bottom sheet with three options: "From scratch", "From descriptor",
    "Import project".  Selecting "From descriptor" opens CreateProjectDialog
    already in importDescriptor mode (title = "Import descriptor").

    After this call the driver is on the ProjectDetailScreen for `name`.
    """
    await navigate_designer(d)
    await click_tooltip(d, "New")
    # Multi-line label: "From descriptor\nPaste, scan or import..."
    # wait_for needs plain substring, not the quoted form used for single-line labels.
    await wait_for(d, 'From descriptor', "Bottom sheet opened")
    await click_label(d, "From descriptor", delay=0.4)
    # CreateProjectDialog opens directly in 'Import descriptor' mode.
    await wait_for(d, '"Import descriptor"', "Create project dialog opened")
    await fill_field(d, "Project name", name)
    await fill_field(d, "Descriptor", descriptor)
    # Rust analysis takes 1–4 s depending on descriptor complexity
    await click_label(d, "Analyze & Save", delay=0.5)
    await wait_for(
        d, f'"{name}"',
        f"Project detail: '{name}'",
        retries=15, delay=0.9,
    )
    # Wait for the tab bar to render (complex descriptors can delay the tabs
    # slightly after the project name appears in the AppBar).
    await wait_for(
        d, '"Spend paths (',
        "Tab bar rendered",
        retries=10, delay=0.6,
    )


async def go_back(d, delay: float = 0.8):
    """Press the AppBar Back button."""
    await click_tooltip(d, "Back", delay=delay)


async def delete_project_from_list(d, name: str):
    """
    Delete a project from the project-list screen via its card context menu.
    Must be called after navigating back to the project list.

    Project card "More options" popup items:
      item 0 = Edit (+24)           item 1 = Export (+72)
      item 2 = Create wallet (+120) item 3 = Delete (+168)
    """
    await wait_for(d, '"Projects"', "On project list")
    await click_popup_item(d, "More options", 168, "Delete")
    await wait_for(d, '"Delete project"', "Delete confirmation dialog", retries=6)
    await click_label(d, "Delete", delay=1.2)
    await wait_absent(d, f'"{name}"', f"'{name}' removed from list")
    print(f"    [ok] project '{name}' deleted")


# ---------------------------------------------------------------------------
# Wallet helpers
# ---------------------------------------------------------------------------

async def create_wallet_from_project(
    d,
    wallet_name: str,
    protection: str = "device_key",
    password: str = "",
    network: str | None = None,
):
    """
    Create a wallet from the current ProjectDetailScreen.

    Must be called while on a ProjectDetailScreen.
    Lands on the WalletDetailScreen for `wallet_name` on success.

    Project detail "More options" items (when not dirty):
      item 0 = Export (+24)    item 1 = Create wallet (+72)

    Args:
        protection: "device_key" (default) | "password" | "xpub"
        password:   Required when protection="password"
        network:    Optional localized network name to override the auto-detected
                    one (e.g. "Signet").  Uses the NetworkDropdownField on the
                    create-wallet screen.
    """
    await click_popup_item(d, "More options", 72, "Create wallet")
    await wait_for(d, '"New Wallet"', "Create wallet screen opened")

    # Wallet name field is pre-filled; overwrite with desired name
    await fill_field(d, "Wallet name", wallet_name)

    if network is not None:
        # The NetworkDropdownField (labelText "Network") shows the current value
        # as its label in semantics.  Tap the field to open the dropdown, then
        # select the requested network.
        await click_label(d, "Network", delay=0.5)
        await wait_for(d, f'"{network}"', f"network dropdown — {network}", retries=6, delay=0.4)
        await click_label(d, network, delay=0.4)
        print(f"    [ok] wallet network set to '{network}'")

    if protection == "password":
        # SegmentedButton — click the "Password" segment by label
        await click_label(d, "Password", delay=0.5)
        # Wait for form to rebuild with password fields visible
        await wait_for(d, '"Confirm password"', "Password fields visible", retries=10, delay=0.4)
        await fill_field(d, "New password", password)
        await fill_field(d, "Confirm password", password)

    # Create Wallet — BDK init takes 2–5 s (fast with Rust release)
    await click_label(d, "Create wallet", delay=0.5)

    # Handle immediate password prompt (can appear right after creation)
    await asyncio.sleep(3.0)
    sem = await d.semantics_tree()
    if '"Enter wallet password"' in sem:
        print("    [step] password prompt after creation — entering password")
        await fill_field(d, "Password", password)
        # KDF (Argon2id Standard: m=65536, t=5) + initial wallet sync can take 10–20 s
        await click_label(d, "Confirm", delay=8.0)

    # Wait for "Receive" button — unique to wallet detail, not present on creation form
    await wait_for(
        d, '"Receive"',
        f"Wallet detail loaded: '{wallet_name}'",
        retries=30, delay=1.0,
    )


async def unlock_wallet(d, password: str):
    """
    Enter a password when the wallet detail is showing the password prompt.
    Call this when WalletDetailNeedsPassword state is active.
    """
    await wait_for(d, '"Enter wallet password"', "Password prompt visible")
    await fill_field(d, "Password", password)
    # KDF (Argon2id Standard: m=65536, t=5) + wallet sync can take 10–20 s
    await click_label(d, "Confirm", delay=8.0)


async def lock_wallet(d):
    """
    Lock the current wallet via the 'More options' menu.

    Wallet detail "More options" items (typical order — no dividers in semantics):
      Send(+24) Receive(+72) — [divider] — Sync(+136) Rescan(+184) — [divider] —
      ExportLabels(+248) ImportLabels(+296) — [divider] —
      GenerateProject(+360) — [divider] — LockWallet(+424)

    Only present for UserPassword wallets.
    """
    # Try several offsets in case the menu layout shifts
    for offset in (424, 376, 400, 448):
        rect = await d.find_semantic_rect_by_tooltip("More options")
        if rect is None:
            raise AssertionError("'More options' button not found on wallet detail")
        cx = (rect[0] + rect[2]) // 2
        item_y = rect[3] + offset
        print(f"    [lock] trying offset +{offset} at flutter ({cx},{item_y})")
        d.flutter_click(cx, (rect[1] + rect[3]) // 2, delay_s=0.5)
        await asyncio.sleep(0.4)
        d.flutter_click(cx, item_y)
        await asyncio.sleep(1.0)
        sem = await d.semantics_tree()
        if '"Enter wallet password"' in sem or "Wallets" in sem:
            print(f"    [ok] wallet locked (offset +{offset} worked)")
            return
    raise AssertionError("Lock wallet action did not produce password prompt or navigate away")


async def open_wallet_from_list(d, wallet_name: str):
    """
    Tap a wallet card in the wallet list to open it.
    Must be on the WalletListScreen.
    """
    await wait_for(d, '"Wallets"', "On wallet list")
    rect = await d.find_semantic_rect(wallet_name)
    if rect is None:
        raise AssertionError(f"Wallet card '{wallet_name}' not found in wallet list")
    d.flutter_click((rect[0] + rect[2]) // 2, (rect[1] + rect[3]) // 2)
    await asyncio.sleep(1.5)
