#!/usr/bin/env python3
"""
Shared helpers for Deadbolt regression tests.

Usage:
  from regression_helpers import (
      wait_for, wait_absent,
      navigate_designer, navigate_wallets, navigate_settings,
      click_label, click_tooltip,
      fill_field, click_popup_item,
      create_project, go_back, delete_project_from_list,
      go_back_to_wallet_list, delete_wallet_from_list,
      set_active_network_signet, run_regression,
  )
"""

import asyncio
import os
import re
import subprocess
import sys


# ---------------------------------------------------------------------------
# Navigation drawer
# ---------------------------------------------------------------------------
# Drawer layout (from debug_drawer.py semantics dump, GNOME/Adwaita):
#   item 0 "Wallet"   → Flutter center (192,  85)
#   item 1 "Designer" → Flutter center (192, 149)
#   item 2 "Settings" → Flutter center (192, 213)
#   item 3 "About"    → Flutter center (192, 277)
_DRAWER_FX  = 192
_DRAWER_FY0 = 85
_DRAWER_FH  = 64

# AppBar titles are not semantics nodes in Flutter; wait for a unique on-screen
# element instead. Tabs not listed here fall back to a fixed sleep.
_TAB_UNIQUE_LABELS = {
    "Wallets": "Select network",
    "Projects": "No projects",
    "Settings": "Settings",
}


async def dismiss_startup_dialogs(d):
    """
    Dismiss any dialogs that appear on first launch (e.g. beta disclaimer).
    Call this once right after UIDriver.launch() before any navigation.
    Safe to call even if no dialogs are showing.

    The disclaimer is triggered via addPostFrameCallback + async SharedPreferences
    read, so it can appear up to several seconds after the window is visible.
    We poll for up to 6 s before concluding no dialog will appear.
    """
    _BETA_MARKERS = ("Beta Software", "disclaimerTitle")
    for _ in range(12):
        await asyncio.sleep(0.5)
        flat = await d.cs_flat_text()
        if any(m in flat for m in _BETA_MARKERS):
            print("    [startup] Beta disclaimer visible — closing")
            try:
                await click_label(d, "Don't show for 7 days", delay=0.8)
            except AssertionError:
                pass  # button says "Close" instead
            flat2 = await d.cs_flat_text()
            if any(m in flat2 for m in _BETA_MARKERS):
                # Try "Close" with direct xdotool as fallback
                try:
                    await click_label(d, "Close", delay=0.8)
                except AssertionError:
                    # Final fallback: use xdotool to press Escape
                    import subprocess
                    subprocess.run(
                        ["xdotool", "key", "Escape"],
                        env={**os.environ, "DISPLAY": ":0"},
                        timeout=3,
                    )
                flat2 = await d.cs_flat_text()
            if any(m in flat2 for m in _BETA_MARKERS):
                # Last resort: find "Close" via cs_tree and click its rect
                tree = await d.cs_tree()
                for n in tree:
                    if n.get("label") == "Close":
                        rect = d._cs_rect(n)
                        if rect:
                            cx = (rect[0] + rect[2]) // 2
                            cy = (rect[1] + rect[3]) // 2
                            d.flutter_click(cx, cy)
                            await asyncio.sleep(1.0)
                            flat2 = await d.cs_flat_text()
                            if not any(m in flat2 for m in _BETA_MARKERS):
                                break
            if any(m in flat2 for m in _BETA_MARKERS):
                raise AssertionError("[startup] Beta disclaimer could not be dismissed")
            break

    print("    [startup] ready")


_DRAWER_LABELS = ["Wallet", "Designer", "Settings", "About"]


async def navigate_drawer(d, tab_index: int, expected_title: str):
    """Open the hamburger drawer and tap the item at `tab_index`.

    Tries to click by semantic label first (robust against layout shifts).
    Falls back to fixed coordinates if the label is not found within the
    drawer open animation window.
    """
    await d.click_semantic("", tooltip="Open navigation menu")
    await asyncio.sleep(1.5)

    label = _DRAWER_LABELS[tab_index] if tab_index < len(_DRAWER_LABELS) else None
    if label:
        rect = await d.cs_find_by_label(label)
        if rect is None:
            rect = await d.cs_find_by_label_part(label)
        if rect is None:
            rect = await d.cs_find_label_containing(label)
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
    unique = _TAB_UNIQUE_LABELS.get(expected_title)
    if unique:
        await wait_for(d, unique, f"Navigated to {expected_title}")
    else:
        await asyncio.sleep(2.0)
        print(f"    [ok] navigated to {expected_title} (fixed timeout)")


async def navigate_designer(d):
    """Navigate to the Designer (Projects) tab."""
    await navigate_drawer(d, 1, "Projects")


async def navigate_wallets(d):
    """Navigate to the Wallet tab."""
    await navigate_drawer(d, 0, "Wallets")


async def navigate_settings(d):
    """Navigate to the Settings tab."""
    await navigate_drawer(d, 2, "Settings")


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
        flat = await d.cs_flat_text()
        if label in flat:
            if desc:
                print(f"    [ok] {desc}")
            return flat
        await asyncio.sleep(delay)
    # Timeout — dump visible labels for debugging
    nodes = await d.cs_tree()
    visible = [
        n.get("label") or n.get("tooltip", "")
        for n in nodes
        if n.get("label") or n.get("tooltip")
    ]
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
        flat = await d.cs_flat_text()
        if label not in flat:
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


async def wait_for_tooltip(
    d, tooltip: str, desc: str = "", retries: int = 20, delay: float = 1.0
):
    """
    Poll until a semantic node with the given tooltip is present, then click it.
    Useful when a button is temporarily hidden (e.g. Sync wallet while isSyncing).
    """
    for _ in range(retries):
        rect = await d.cs_find_by_tooltip(tooltip)
        if rect is not None:
            await click_tooltip(d, tooltip)
            if desc:
                print(f"    [ok] {desc}")
            return
        await asyncio.sleep(delay)
    raise AssertionError(
        f"Timeout: tooltip '{tooltip}' not found in semantics"
        + (f" — {desc}" if desc else "")
    )


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
      - Oversized rect (height > 80): Flutter merges adjacent semantics nodes,
        so the actual input lives in the top ~56 px — click near the top.

    When `text` is empty the field is cleared via Ctrl+A + Delete instead of
    clipboard paste, because xclip does not reliably set an empty clipboard and
    a stale paste would leave the previous value in the field.
    """
    rect = await d.cs_find_textfield_by_label(field_label)
    if rect:
        cx = (rect[0] + rect[2]) // 2
        cy = (rect[1] + rect[3]) // 2
        if (rect[3] - rect[1]) < 30:
            # Separate label widget above the field — click below the label.
            cy = rect[3] + 28
        d.flutter_click(cx, cy)
    else:
        # Hint-text fallback
        for hint in ("Add a label...", field_label):
            r2 = await d.cs_find_by_label(hint)
            if r2:
                d.flutter_click((r2[0] + r2[2]) // 2, (r2[1] + r2[3]) // 2)
                break
        else:
            print(f"    [warn] field '{field_label}' not found — clicking center")
            d.flutter_click(*d.window_center())
    await asyncio.sleep(0.3)
    if text == "":
        # Clear via keyboard — xclip does not reliably set an empty clipboard.
        d.key("ctrl+a")
        await asyncio.sleep(0.1)
        d.key("Delete")
        await asyncio.sleep(0.2)
    else:
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
    rect = await d.cs_find_by_tooltip(trigger_tooltip)
    if rect is None:
        raise AssertionError(f"Popup trigger not found: tooltip='{trigger_tooltip}'")
    cx = (rect[0] + rect[2]) // 2
    cy = (rect[1] + rect[3]) // 2
    # Click trigger to open popup
    d.flutter_click(cx, cy, delay_s=0.5)
    await asyncio.sleep(0.6)
    # Find item by label (works regardless of popup position relative to trigger)
    item_rect = await d.cs_find_by_label(label)
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
    if await d.cs_find_by_label("Enter wallet password") is not None:
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
        rect = await d.cs_find_by_tooltip("More options")
        if rect is None:
            raise AssertionError("'More options' button not found on wallet detail")
        cx = (rect[0] + rect[2]) // 2
        item_y = rect[3] + offset
        print(f"    [lock] trying offset +{offset} at flutter ({cx},{item_y})")
        d.flutter_click(cx, (rect[1] + rect[3]) // 2, delay_s=0.5)
        await asyncio.sleep(0.4)
        d.flutter_click(cx, item_y)
        await asyncio.sleep(1.0)
        flat = await d.cs_flat_text()
        if '"Enter wallet password"' in flat or "Wallets" in flat:
            print(f"    [ok] wallet locked (offset +{offset} worked)")
            return
    raise AssertionError("Lock wallet action did not produce password prompt or navigate away")


async def open_wallet_from_list(d, wallet_name: str):
    """
    Tap a wallet card in the wallet list to open it.
    Must be on the WalletListScreen.
    """
    await wait_for(d, '"Wallets"', "On wallet list")
    rect = await d.cs_find_by_label_part(wallet_name)
    if rect is None:
        raise AssertionError(f"Wallet card '{wallet_name}' not found in wallet list")
    d.flutter_click((rect[0] + rect[2]) // 2, (rect[1] + rect[3]) // 2)
    await asyncio.sleep(1.5)


async def go_back_to_wallet_list(d):
    """
    Navigate back to the Wallet list from any depth (multi-tab safe).

    If already on the wallet list (no Back button present), returns immediately.
    Otherwise presses Back up to 5 times until the Wallets screen is detected.
    """
    # Already on the wallet list if there is no Back button.
    if await d.cs_find_by_tooltip("Back") is None:
        flat = await d.cs_flat_text()
        if '"Wallets"' in flat or "Select network" in flat:
            print("    [ok] back on wallet list")
            return
    for _ in range(5):
        await click_tooltip(d, "Back", delay=0.8)
        if await d.cs_find_by_label("Wallets") is not None:
            break
    await wait_for(d, '"Wallets"', "back on wallet list")
    print("    [ok] back on wallet list")


async def delete_wallet_from_list(d, wallet_name: str):
    """
    Delete a wallet via its card popup menu.
    Must be called while on WalletListScreen.

    Wallet card uses a merged multi-line semantic label, so `wallet_name`
    is matched as a plain substring (no surrounding quotes).
    """
    await wait_for(d, wallet_name, "wallet card visible")
    rect = await d.cs_find_by_tooltip("More options")
    if rect is None:
        raise AssertionError("'More options' button not found on wallet card")
    d.flutter_click((rect[0] + rect[2]) // 2, (rect[1] + rect[3]) // 2, delay_s=0.5)
    await asyncio.sleep(0.6)
    item_rect = await d.cs_find_by_label("Delete")
    if item_rect is None:
        raise AssertionError("'Delete' item not found in popup")
    d.flutter_click((item_rect[0] + item_rect[2]) // 2, (item_rect[1] + item_rect[3]) // 2)
    await asyncio.sleep(0.4)
    await wait_for(d, '"Delete wallet"', "delete confirmation dialog")
    await click_label(d, "Delete", delay=1.0)
    await wait_absent(d, wallet_name, f"'{wallet_name}' removed from list")
    print(f"    [ok] wallet '{wallet_name}' deleted")


async def set_active_network_signet(d):
    """
    Set the active network to Signet via the AppBar network badge.

    Flow: navigate to Wallets → tap 'Select network' badge → select 'Signet'.
    """
    print("\n  [phase 0] set Active Network to Signet")
    await navigate_wallets(d)
    await click_label(d, "Select network", delay=0.5)
    await wait_for(d, "Signet", "network picker sheet opened", retries=10, delay=0.5)
    await click_label(d, "Signet", delay=1.0)
    print("    [ok] Active Network set to Signet")


async def run_regression(test_func, test_id: str):
    """
    Standard harness for single-test regression scripts.

    Launches a sandbox UIDriver, dismisses startup dialogs, runs `test_func(d)`,
    and prints PASS/FAIL.  On failure the semantics tree is written to
    /tmp/<test_id>_cs_tree for debugging.

    Checks that no other deadbolt instance is running before launching,
    to avoid clicking on the wrong window.

    Usage in each script's main():

        if __name__ == "__main__":
            asyncio.run(run_regression(test_foo, "reg01"))
    """
    other = subprocess.run(
        ["pgrep", "-x", "deadbolt"],
        capture_output=True, text=True,
    )
    if other.stdout.strip():
        pids = other.stdout.strip().split("\n")
        raise RuntimeError(
            f"Another deadbolt instance is running (PID={pids[0]}). "
            f"Kill it with 'kill {pids[0]}' before running this test."
        )

    from ui_driver import UIDriver  # imported here to avoid circular dependency
    d = UIDriver(sandbox=True)
    try:
        await d.launch()
        d.raise_window()
        await dismiss_startup_dialogs(d)
        await test_func(d)
        print(f"\n{'='*50}")
        print("[RESULT] PASS")
    except AssertionError as exc:
        with open(f'/tmp/{test_id}_cs_tree', 'w') as f:
            f.write(await d.cs_tree_as_json())
        print(f"\n[FAIL] {exc}")
        print(f"    [debug] Full semantics tree written to /tmp/{test_id}_cs_tree")
        await d.close()
        sys.exit(1)
    except Exception as exc:
        with open(f'/tmp/{test_id}_cs_tree', 'w') as f:
            f.write(await d.cs_tree_as_json())
        print(f"\n[ERROR] {exc}")
        print(f"    [debug] Full semantics tree written to /tmp/{test_id}_cs_tree")
        await d.close()
        raise
    finally:
        try:
            await d.close()
        except Exception:
            pass
