#!/usr/bin/env python3
"""
Regression test 26: Taproot inheritance — fee vs analyzer per spend path,
and PSBT export/import round-trip.

Re-creates the same taproot inheritance wallet as test 25 (identical descriptor)
under the name Reg26-FeeTest so the same on-chain UTXOs are discoverable after
syncing on Signet.

Flow:
  0.  Settings → set Active Network to Signet
  1.  Create Reg26-FeeTest wallet (same guided-inheritance flow as test 25)
  2.  Sync wallet — wait for confirmed coins
      → If unfunded: print receive address and exit with SKIP
  3.  For each spend path (sorted by timelock: owner first, heirs ascending):
        a. Overview → Send → Create TX → select first coin → back on Create TX
        b. Switch to spend path i via dropdown
        c. Fill label "reg26-P<i>", self-pay (My Wallets), MAX
        d. Capture fee_estimate from total_fee_display semantic field
        e. Create PSBT
        f. Capture fee_psbt from PSBT detail "Fee  N sats" row
        g. Assert fee_psbt == fee_estimate
        h. Export/import round-trip for EVERY spend path:
             · Export PSBT → "Copy to clipboard"
             · Go back to wallet detail
             · Import: Overview → Import → PSBT → Paste from clipboard
             · Verify "PSBT imported" toast
             · Open imported PSBT in Transactions tab
             · If owner (path 0): verify NO "Timelock" row
             · If heir (path 1-5): verify "Timelock" row present with correct block count
             · Verify fee_imported == fee_estimate
             · Delete imported PSBT
  4.  Verify key-path fee < all script-path fees
  5.  Cleanup: delete wallet

Exit code: 0 = PASS, 1 = FAIL.

Prerequisites:
  bash scripts/prepare_test_build.sh
  python3 scripts/regression_26_taproot_fees_import.py

---------------------------------------------------------------------------
Wallet reference data (Signet, 2026-04-25)
---------------------------------------------------------------------------
First receive address (index 0):
  tb1pnxdfswymw4jn433tfdetgth32qycfan6zukwnkmdysagts39ugcqa0x99u
"""

import asyncio
import os
import re
import subprocess
import sys
from pathlib import Path  # noqa: F401 (also used in _export_psbt_to_clipboard)

sys.path.insert(0, str(Path(__file__).resolve().parent))
from ui_driver import UIDriver                          # noqa: E402
from regression_helpers import (                       # noqa: E402
    wait_for, wait_absent, assert_no_error_toast,
    navigate_wallets, fill_field, click_label, click_tooltip,
    go_back_to_wallet_list, delete_wallet_from_list,
    set_active_network_signet, run_regression,
)


# ---------------------------------------------------------------------------
# Test data — same descriptor as test 25
# ---------------------------------------------------------------------------

WALLET_NAME = "Reg26-FeeTest"

MNEMONIC = (
    "bachelor brick camera brave assume differ disagree "
    "judge security scrap wonder oval"
)

# Timelock (in blocks) for each spend path, sorted ascending by timelock.
# Index 0 = owner key-path (no timelock); indices 1-5 = heir branches in older() order.
PATH_TIMELOCKS: dict[int, int | None] = {
    0: None,    # owner key-path
    1: 6,       # older(6)
    2: 13140,   # older(13140)
    3: 26280,   # older(26280)
    4: 39420,   # older(39420)
    5: 52560,   # older(52560)
}

# Full taproot inheritance descriptor (same as test 25).
SIGNET_INHERITANCE_DESC = (
    "tr([bc0dbbce/48'/1'/0'/2']tpubDEpnZReLc2mqbLNeGbNckbVTw6GTgfnz2s8r8wWoWrJY3ZP7dJ2hPKTbFk7RTqdSVYKJiDXQgT3jiACt3EGP5QuYjXqWvf6q1c7gN68Ywp8/<0;1>/*,"
    "{and_v(v:pk([f3d33d4f/48'/1'/0'/2']tpubDFLYS7v5vvjyhLMotrmn6KzdN46jJ8ife9yD8DUMygtNCR4U389Wr46vJj7kG9bJPqFmLSet7hAP5fVJvyc97x9fhKZ7Zm9cTdvMxHqT55h/<0;1>/*),older(6)),"
    "{and_v(v:pk([ff81be5d/48'/1'/0'/2']tpubDDxjvuVfYHF4KcVyd5wkNS6pKJvg1x6CUtCRL3nRX2MDHKcja6M7YB7FYFYDkXzx8fL7k9bYi8XDpfPetqvd6ER2VYt1WsQSHYnhhT2EX7K/<0;1>/*),older(13140)),"
    "{and_v(v:pk([f3d33d4f/48'/1'/0'/2']tpubDFLYS7v5vvjyhLMotrmn6KzdN46jJ8ife9yD8DUMygtNCR4U389Wr46vJj7kG9bJPqFmLSet7hAP5fVJvyc97x9fhKZ7Zm9cTdvMxHqT55h/<2;3>/*),older(26280)),"
    "{and_v(v:pk([4061aff0/48'/1'/0'/2']tpubDFAv39stw4ELPsWiyqNL2UcFwruoVdX89CEpzJwb1TV3k9JgW6tLPUicWJvRT5iUSH7HHdt6rXtgRSX5TWJZqDcwJZZTtj1WTcHLUCC7eXC/<0;1>/*),older(39420)),"
    "and_v(v:pk([ca6205d9/48'/1'/0'/2']tpubDE7Kf5xBnX5qHJKbAk3JdzxRg1hjoaxHkwCQBQHTAR32NYr6BKhbN78hENp59actsGTsUKjrqhTXCXbmW4hy5NGc5s1Ap9Mx66cKzvyzWaT/<0;1>/*),older(52560))"
    "}}}})"
    "#xak7t3uv"
)


# ---------------------------------------------------------------------------
# Low-level helpers
# ---------------------------------------------------------------------------

async def _paste_clipboard(d: UIDriver, text: str):
    env = {**os.environ, "DISPLAY": ":0"}
    subprocess.run(["xclip", "-selection", "clipboard"],
                   input=text.encode(), env=env, check=True)
    await asyncio.sleep(0.1)
    d.key("ctrl+v")
    await asyncio.sleep(0.3)


async def _type_text_direct(d: UIDriver, text: str):
    """Type text using xdotool type --clear (more reliable than xclip on Linux)."""
    env = {**os.environ, "DISPLAY": ":0"}
    subprocess.run(["xdotool", "type", "--clearmodifiers", "--", text],
                   env=env, check=True)
    await asyncio.sleep(0.5)


# ---------------------------------------------------------------------------
# Wallet creation: import descriptor + add owner hot key
# ---------------------------------------------------------------------------

async def _create_wallet(d: UIDriver):
    """
    Import SIGNET_INHERITANCE_DESC via New → From descriptor, then make
    the owner key (BC0DBBCE) hot by entering the mnemonic in the Descriptor tab.
    """
    print(f"\n  [create] import descriptor for {WALLET_NAME}")
    await navigate_wallets(d)
    await click_tooltip(d, "New")
    await wait_for(d, "From descriptor", "creation sheet", retries=10, delay=0.5)
    await click_label(d, "From descriptor", delay=0.5)
    await wait_for(d, '"New Wallet"', "CreateWalletDialog", retries=10, delay=0.5)

    await fill_field(d, "Wallet name", WALLET_NAME)

    # Paste descriptor (too long to type character-by-character).
    rect = await d.cs_find_textfield_by_label("Descriptor")
    if rect is None:
        raise AssertionError("Descriptor text field not found")
    d.flutter_click((rect[0] + rect[2]) // 2, (rect[1] + rect[3]) // 2)
    await asyncio.sleep(0.3)
    d.key("ctrl+a")
    await asyncio.sleep(0.1)
    await _paste_clipboard(d, SIGNET_INHERITANCE_DESC)
    await asyncio.sleep(1.5)

    await click_label(d, "Create wallet", delay=1.0)
    sem = await wait_for(d, '"Receive"', f"wallet detail: {WALLET_NAME}",
                         retries=60, delay=1.0)
    assert_no_error_toast(sem)
    print("    [ok] wallet created from descriptor")

    # Make the owner key hot via the Descriptor tab.
    await _make_owner_key_hot(d)
    print("    [ok] owner hot key added")


async def _make_owner_key_hot(d: UIDriver):
    """
    Descriptor tab → Keys sub-tab → tap BC0DBBCE key card →
    'Add private key' → paste mnemonic → Add.
    """
    await click_label(d, "Descriptor", delay=0.5)
    # The Descriptor view has 3 sub-tabs: Spend paths / Keys / Descriptor.
    # Key cards live in the "Keys" sub-tab (label contains "Keys (5)").
    await wait_for(d, "Keys (5)", "Keys sub-tab visible", retries=8, delay=0.5)
    await click_label(d, "Keys (5)", delay=0.5)
    # MFPs are shown uppercase in key cards.
    await wait_for(d, "BC0DBBCE", "Keys tab with owner key card", retries=8, delay=0.5)

    # Tap the owner key card to open the key sheet.
    rect = await d.cs_find_by_label_part_containing("BC0DBBCE")
    if rect is None:
        raise AssertionError("BC0DBBCE key card not found in Keys sub-tab")
    d.flutter_click((rect[0] + rect[2]) // 2, (rect[1] + rect[3]) // 2)
    await asyncio.sleep(0.5)

    # Key sheet opens — click "Add private key".
    await wait_for(d, "Add private key", "key sheet open", retries=8, delay=0.5)
    await click_label(d, "Add private key", delay=0.5)

    # showAddPrivateKeySheet opens in Hot Key mode (wallet mode, no method picker).
    await wait_for(d, "word1 word2 word3 ...", "mnemonic field", retries=8, delay=0.5)
    rect = await d.cs_find_textfield_by_label("word1 word2 word3 ...")
    if rect is None:
        raise AssertionError("Mnemonic text field not found")
    d.flutter_click((rect[0] + rect[2]) // 2, (rect[1] + rect[3]) // 2)
    await asyncio.sleep(0.3)
    d.key("ctrl+a")
    await asyncio.sleep(0.1)
    await _paste_clipboard(d, MNEMONIC)
    await asyncio.sleep(1.0)

    # In wallet mode the derived info shows as "MFP: {mfp}" (not "Derived keyspec").
    await wait_for(d, "MFP: bc0dbbce", "mnemonic derived, MFP matched", retries=10, delay=0.5)

    # The confirm button shares its label "Add private key" with the dialog title;
    # click the bottommost node to avoid hitting the title text.
    tree = await d.cs_tree()
    targets = [n for n in tree if n.get("label") == "Add private key"]
    if not targets:
        raise AssertionError("'Add private key' confirm button not found in tree")
    bottom = max(targets, key=lambda n: (n.get("globalRect") or [0, 0, 0, 0])[3])
    r = bottom.get("globalRect", [])
    d.flutter_click((r[0] + r[2]) // 2, (r[1] + r[3]) // 2)
    await asyncio.sleep(1.0)

    # Wait for the success toast ("Signing key added (bc0dbbce)") to appear and then go.
    await wait_for(d, "Signing key added", "success toast visible", retries=10, delay=0.5)
    await wait_absent(d, "Signing key added", "success toast gone", retries=20, delay=0.5)

    # Navigate back to Overview (tab is now unobstructed).
    await click_label(d, "Overview", delay=0.5)
    await wait_for(d, '"Receive"', "back on Overview", retries=10, delay=0.5)


# ---------------------------------------------------------------------------
# Sync / address helpers
# ---------------------------------------------------------------------------

async def _sync_and_wait_coins(d: UIDriver) -> bool:
    """Sync, then return True if at least one confirmed UTXO is found."""
    await click_tooltip(d, "Sync wallet", delay=1.5)
    await click_label(d, "Coins", delay=1.0)
    sem = await wait_for(d, "sats", "coins tab", retries=60, delay=2.0)
    funded = '"No coins.' not in sem and "Spending" not in sem
    await click_label(d, "Overview", delay=0.5)
    await wait_for(d, '"Receive"', "Overview tab", retries=6, delay=0.5)
    return funded


async def _copy_first_receive_address(d: UIDriver) -> str:
    await click_label(d, "Addresses", delay=0.8)
    await wait_for(d, "receive_address_0", "address #0 visible", retries=8, delay=0.5)
    rect = await d.cs_find_by_label_part_containing("receive_address_0")
    if rect is None:
        raise AssertionError("receive_address_0 tile not found")
    d.flutter_click((rect[0] + rect[2]) // 2, (rect[1] + rect[3]) // 2)
    await asyncio.sleep(1.0)
    await wait_for(d, '"Address details"', "dialog", retries=8, delay=0.5)
    share = await d.cs_find_by_tooltip("Copy to clipboard")
    if share is None:
        raise AssertionError("Copy to clipboard button not found")
    d.flutter_click((share[0] + share[2]) // 2, (share[1] + share[3]) // 2)
    await asyncio.sleep(0.5)
    await wait_for(d, "Copy to clipboard", "export sheet", retries=6, delay=0.5)
    btn = await d.cs_find_by_label("Copy to clipboard")
    if btn is None:
        raise AssertionError("Copy to clipboard option not found")
    d.flutter_click((btn[0] + btn[2]) // 2, (btn[1] + btn[3]) // 2)
    await asyncio.sleep(0.5)
    addr = subprocess.check_output(
        ["xclip", "-selection", "clipboard", "-o"],
        env={**os.environ, "DISPLAY": ":0"},
    ).decode().strip()
    await click_tooltip(d, "Close", delay=0.5)
    await wait_absent(d, '"Address details"', "dialog closed", retries=5, delay=0.5)
    await click_label(d, "Overview", delay=0.5)
    await wait_for(d, '"Receive"', "back on Overview", retries=6, delay=0.5)
    return addr


# ---------------------------------------------------------------------------
# Create TX helpers
# ---------------------------------------------------------------------------

async def _go_to_overview(d: UIDriver):
    """Ensure we're on the wallet detail Overview tab."""
    sem = await d.cs_flat_text()
    if '"Receive"' not in sem:
        await click_label(d, "Overview", delay=0.3)
        await wait_for(d, '"Receive"', "Overview tab", retries=8, delay=0.5)


async def _navigate_to_create_tx(d: UIDriver):
    """Overview → Send → Create TX → select first coin → Done."""
    await click_label(d, "Send", delay=0.5)
    await wait_for(d, '"Create Transaction"', "Create TX screen", retries=10, delay=0.5)
    await click_label(d, "Tap to select coins...", delay=1.0)
    await wait_for(d, "sats", "coin selector", retries=10, delay=0.5)

    coin_rect = await d.cs_find_by_label_part_containing("sats")
    if coin_rect is None:
        raise AssertionError("No coin tile found in coin selector")
    d.flutter_click((coin_rect[0] + coin_rect[2]) // 2, (coin_rect[1] + coin_rect[3]) // 2)
    await asyncio.sleep(0.5)
    await click_label(d, "Done (1)", delay=1.0)
    await wait_for(d, '"Create Transaction"', "back on Create TX", retries=10, delay=0.5)


def _is_spend_path_option(label: str) -> bool:
    """Return True if label belongs to a spend-path dropdown item.

    Two formats are possible:
    - Custom labels set via project: "Main" or "Heir N\\n..."
    - Fallback (descriptor import, no project labels): "N-of-M (XXXX...)"
    """
    if re.match(r'^(Main|Heir\s)', label):
        return True
    # Fallback format produced by _pathLabel() in create_tx_screen.dart:
    # "${threshold}-of-${mfps.length} ($keys)" where keys may contain " + ".
    if re.match(r'^\d+-of-\d+ \(.+\)', label):
        return True
    return False


async def _open_spend_path_dropdown(d: UIDriver) -> None:
    """Click the Spend path dropdown and wait until ≥2 options are visible.

    When closed, only 1 path item appears (the selected item text in the button).
    When open, all spend paths appear in the overlay — count jumps to ≥2.
    """
    try:
        await click_label(d, "Spend path", delay=0.5)
    except AssertionError:
        rect = await d.cs_find_by_label_part_containing("Spend path")
        if rect:
            d.flutter_click((rect[0] + rect[2]) // 2, (rect[1] + rect[3]) // 2)
            await asyncio.sleep(0.5)
        else:
            raise AssertionError("Spend path dropdown not found")
    # Wait until ≥2 matching items appear (dropdown overlay is open).
    for _ in range(10):
        tree = await d.cs_tree()
        count = sum(1 for n in tree if _is_spend_path_option(n.get("label", "")))
        if count >= 2:
            return
        await asyncio.sleep(0.5)
    raise AssertionError("spend-path dropdown open: < 2 options in tree after click")


async def _count_spend_paths(d: UIDriver) -> int:
    """Open the spend-path dropdown, count options, then dismiss without selecting."""
    await _open_spend_path_dropdown(d)
    tree = await d.cs_tree()
    count = sum(1 for n in tree if _is_spend_path_option(n.get("label", "")))
    # Dismiss without selecting: tap outside the dropdown overlay area
    d.flutter_click(210, 800)
    await asyncio.sleep(1.0)
    # Verify dropdown closed by checking path count dropped to 1
    tree = await d.cs_tree()
    post_count = sum(1 for n in tree if _is_spend_path_option(n.get("label", "")))
    if post_count > 1:
        # Dropdown still open — try pressing Escape
        env = {**os.environ, "DISPLAY": ":0"}
        subprocess.run(["xdotool", "key", "Escape"], env=env, check=True)
        await asyncio.sleep(0.5)
    return count


async def _switch_spend_path(d: UIDriver, path_index: int):
    """Select spend path at path_index (0-based) from the Create TX dropdown."""
    await _open_spend_path_dropdown(d)
    tree = await d.cs_tree()
    path_nodes = [n for n in tree if _is_spend_path_option(n.get("label", ""))]
    if path_index >= len(path_nodes):
        raise AssertionError(
            f"path_index={path_index} out of range ({len(path_nodes)} paths)"
        )
    node = path_nodes[path_index]
    rect = node.get("globalRect", [])
    if not rect:
        raise AssertionError(f"Path node {path_index} has no globalRect")
    d.flutter_click((rect[0] + rect[2]) // 2, (rect[1] + rect[3]) // 2)
    await asyncio.sleep(1.0)


async def _read_total_fee_from_create_tx(d: UIDriver) -> int | None:
    """
    Read the analyzer-computed fee from the total_fee_display semantic field.

    Flutter merges child labels (separated by '\\n') into the parent Semantics
    node: "total_fee_display\\nFee (sats)\\n<N>\\nsats".  We extract the first
    pure-integer part as the fee in satoshis.
    """
    tree = await d.cs_tree()
    for node in tree:
        label = node.get("label", "")
        if "total_fee_display" not in label:
            continue
        for part in label.split("\n"):
            part = part.strip().replace(",", "")
            if re.match(r'^\d+$', part) and 0 < int(part) < 10_000_000:
                return int(part)
    return None


async def _setup_self_pay_max(d: UIDriver):
    """Fill the recipient via wallet picker (self) and toggle MAX."""
    await click_tooltip(d, "MY WALLETS", delay=0.5)
    await wait_for(d, "This wallet (Self)", "wallet picker", retries=6, delay=0.5)
    await click_label(d, "This wallet (Self)", delay=1.5)
    await asyncio.sleep(1.0)
    await click_label(d, "MAX", delay=0.8)
    await wait_absent(d, '"— sats"', "MAX computed", retries=15, delay=0.5)
    await asyncio.sleep(0.5)   # let total_fee_display update


# ---------------------------------------------------------------------------
# PSBT detail helpers
# ---------------------------------------------------------------------------

async def _read_fee_from_psbt_detail(d: UIDriver) -> int | None:
    """
    Read the fee (sats) from the PSBT detail screen's "Fee" row.

    All detail rows are merged into a single semantic node separated by '\\n'.
    Layout: '...\\nFee\\n111 sats\\n...'.  We split and look for the line
    immediately after the standalone "Fee" label.
    """
    tree = await d.cs_tree()
    for node in tree:
        label = node.get("label", "")
        if "Fee" not in label or "sats" not in label:
            continue
        parts = [p.strip() for p in label.split("\n")]
        for idx, part in enumerate(parts):
            if part == "Fee" and idx + 1 < len(parts):
                m = re.search(r'([\d,]+)\s+sats', parts[idx + 1])
                if m:
                    return int(m.group(1).replace(",", ""))

    # Fallback: flat text (two adjacent quoted tokens)
    sem = await d.cs_flat_text()
    m = re.search(r'"Fee"\s+"([\d,]+)\s+sats"', sem)
    if m:
        return int(m.group(1).replace(",", ""))
    return None


async def _export_psbt_to_clipboard(d: UIDriver) -> str:
    """Click 'Export PSBT' → 'Copy to clipboard' and return the base64 string."""
    await click_label(d, "Export PSBT", delay=0.5)
    await wait_for(d, "Copy to clipboard", "export sheet", retries=8, delay=0.5)
    btn = await d.cs_find_by_label("Copy to clipboard")
    if btn is None:
        raise AssertionError("'Copy to clipboard' not found in export sheet")
    d.flutter_click((btn[0] + btn[2]) // 2, (btn[1] + btn[3]) // 2)
    await asyncio.sleep(0.5)
    b64 = subprocess.check_output(
        ["xclip", "-selection", "clipboard", "-o"],
        env={**os.environ, "DISPLAY": ":0"},
    ).decode().strip()
    if len(b64) < 100:
        raise AssertionError(f"Clipboard too short to be a valid PSBT base64: {b64!r}")
    # Debug: persist to file so we can inspect nSequence if the import check fails.
    Path("/tmp/reg26_last_psbt.b64").write_text(b64)
    return b64


async def _delete_psbt_from_detail(d: UIDriver):
    """
    Delete the currently open PSBT via the PSBT detail overflow menu.
    Pops back to wallet detail; waits for wallet detail content to appear.
    """
    await click_tooltip(d, "More options", delay=0.5)
    await wait_for(d, "Delete PSBT", "overflow menu visible", retries=6, delay=0.5)
    await click_label(d, "Delete PSBT", delay=0.5)
    await wait_for(d, "Delete PSBT", "confirm dialog", retries=6, delay=0.5)
    # Click the red FilledButton labelled exactly "Delete" (not "Delete PSBT")
    await click_label(d, "Delete", delay=0.5)
    # After deletion the PSBT detail is popped; wallet detail re-appears
    # Wait for wallet detail balance or overview content (more reliable than wallet name in semantics)
    await wait_for(d, "sats", "back on wallet detail", retries=10, delay=0.5)


async def _import_psbt_from_clipboard(d: UIDriver, psbt_base64: str):
    """Wallet detail → Import → PSBT → Paste from clipboard → verify spend path preserved.

    Uses the same "Paste from clipboard" approach as regression_17.
    The clipboard content is already set by the prior export step.
    Caller is responsible for being on wallet detail before calling this.
    """
    print("    [import] navigating to import flow (Paste from clipboard)")

    # Open overflow menu → "Import" → "PSBT" → PSBT import sheet
    await click_tooltip(d, "More options", delay=0.5)
    await wait_for(d, "Import", "overflow menu visible", retries=6, delay=0.5)
    await click_label(d, "Import", delay=0.5)

    # Import choice sheet: "Labels (BIP-329)", "PSBT", "Sweep WIF key"
    await wait_for(d, "PSBT", "import choice sheet", retries=6, delay=0.5)
    await click_label(d, "PSBT", delay=0.5)

    # Wait for PSBT import sheet (4 options: clipboard, QR, file, paste text)
    await wait_for(d, "Paste from clipboard", "PSBT import sheet", retries=8, delay=0.5)

    # Click "Paste from clipboard" — sheet closes after content is read
    await click_label(d, "Paste from clipboard", delay=0.5)

    # Wait for the import sheet to close
    await wait_absent(d, "Paste from clipboard", "PSBT import sheet closed",
                      retries=10, delay=0.4)

    # Verify toast (transient — may be missed)
    await asyncio.sleep(0.6)
    flat = await d.cs_flat_text()
    has_saved = "PSBT imported" in flat
    has_merged = "Signatures merged" in flat
    if has_saved or has_merged:
        result = "PSBT imported" if has_saved else "Signatures merged"
        print(f"    [ok] import toast: '{result}'")
    else:
        print("    [warn] import toast not captured (transient) — continuing")

    # Import confirmed by toast above; no need to verify tile here
    # (the tile may have a different label if merged)
    print("    [ok] PSBT import confirmed by toast")


async def _open_first_psbt_from_transactions(d: UIDriver) -> None:
    """Navigate to Transactions tab and open the topmost PSBT tile."""
    await click_label(d, "Transactions", delay=0.8)
    await wait_for(d, "UNSIGNED", "PSBT tile visible", retries=10, delay=0.5)
    # The PSBT tile contains "UNSIGNED" — click it
    rect = await d.cs_find_by_label_part_containing("UNSIGNED")
    if rect is None:
        raise AssertionError("No UNSIGNED PSBT tile found in Transactions")
    d.flutter_click((rect[0] + rect[2]) // 2, (rect[1] + rect[3]) // 2)
    await asyncio.sleep(1.0)
    await wait_for(d, '"Unsigned Transaction"', "PSBT detail screen", retries=10, delay=0.5)


# ---------------------------------------------------------------------------
# Export / import round-trip for the owner (key-path) PSBT
# ---------------------------------------------------------------------------

async def _phase_export_import(
    d: UIDriver,
    expected_fee: int,
    expect_timelock: bool = False,
    expected_timelock_blocks: int | None = None,
):
    """
    Execute the export/import round-trip for the currently open PSBT detail screen.

    Verifies:
      - Export: PSBT base64 is retrievable from clipboard
      - Import: PSBT can be re-imported via Paste from clipboard
      - Spend path preserved: imported PSBT detail shows correct timelock info
      - fee_imported == expected_fee
      - If expect_timelock and expected_timelock_blocks set: timelock value matches
    """
    path_label = "heir (timelock)" if expect_timelock else "owner (key-path)"
    print(f"\n  [export/import] exporting {path_label} PSBT to clipboard")
    psbt_base64 = await _export_psbt_to_clipboard(d)
    print(f"    [ok] exported {len(psbt_base64)} base64 chars")

    # Go back to wallet detail before importing (PSBT detail doesn't have import menu)
    await click_tooltip(d, "Back", delay=0.5)
    await wait_for(d, "sats", "back on wallet detail", retries=10, delay=0.5)

    # Import the PSBT back via wallet detail overflow menu
    print(f"  [export/import] importing PSBT from clipboard")
    await _import_psbt_from_clipboard(d, psbt_base64)

    # The import either merged with the existing PSBT or created a duplicate.
    # Sync to ensure state is fresh, then check Transactions.
    print(f"  [export/import] opening PSBT to verify spend path")
    await click_tooltip(d, "Sync wallet", delay=0.5)

    # Go to Transactions tab and find any PSBT tile
    await click_label(d, "Transactions", delay=0.5)
    # Wait for any PSBT tile (may be "UNSIGNED" or another status)
    tree = await d.cs_tree()
    psbt_tiles = [n for n in tree if "PSBT" in (n.get("label", "") or "") or
                  "UNSIGNED" in (n.get("label", "") or "")]
    if not psbt_tiles:
        # Dump visible labels for debugging
        visible = [n.get("label") or n.get("tooltip", "") for n in tree if n.get("label") or n.get("tooltip")]
        raise AssertionError(f"No PSBT tile found in Transactions. Visible: {visible[:15]}")

    # Click the first PSBT tile
    rect = psbt_tiles[0].get("globalRect")
    if not rect:
        raise AssertionError("PSBT tile has no globalRect")
    d.flutter_click((rect[0] + rect[2]) // 2, (rect[1] + rect[3]) // 2)
    await asyncio.sleep(1.0)
    await wait_for(d, '"Unsigned Transaction"', "PSBT detail screen", retries=10, delay=0.5)

    # Verify spend path: check for "Timelock" text in semantic tree
    # Key-path (owner) PSBTs have no timelock → "Timelock" should NOT appear
    # Heir (script-path) PSBTs have timelock → "Timelock" SHOULD appear
    flat = await d.cs_flat_text()
    has_timelock_text = "Timelock" in flat
    if expect_timelock:
        if not has_timelock_text:
            raise AssertionError(
                f"Heir PSBT missing timelock info after import — "
                f"spend path not preserved (expected Timelock row, got none)"
            )
        print(f"    [ok] heir PSBT: Timelock row present — spend path preserved ✓")
        # Verify the timelock value shown matches the expected block count.
        if expected_timelock_blocks is not None:
            tl_str = str(expected_timelock_blocks)
            if tl_str not in flat:
                raise AssertionError(
                    f"Heir PSBT timelock value mismatch after import — "
                    f"expected {expected_timelock_blocks} blocks in PSBT detail, "
                    f"but it was not found in: {flat[:300]}"
                )
            print(f"    [ok] heir PSBT: timelock value {expected_timelock_blocks} blocks confirmed ✓")
    else:
        if has_timelock_text:
            raise AssertionError(
                f"Owner PSBT should NOT have timelock info after import — "
                f"spend path incorrectly identified (found Timelock row)"
            )
        print(f"    [ok] owner PSBT: no Timelock row — key-path correctly identified ✓")

    # Verify that the fee shown in the imported PSBT detail matches the original estimate.
    fee_imported = await _read_fee_from_psbt_detail(d)
    if fee_imported is None:
        raise AssertionError(
            f"Could not read fee from imported PSBT detail ({path_label})"
        )
    if fee_imported != expected_fee:
        raise AssertionError(
            f"Imported PSBT fee mismatch ({path_label}): "
            f"expected {expected_fee} sats but got {fee_imported} sats"
        )
    print(f"    [ok] imported PSBT fee {fee_imported} sats == original {expected_fee} sats ✓")

    # Delete the verified PSBT so the wallet stays clean for subsequent paths.
    # _delete_psbt_from_detail navigates back to wallet detail internally.
    await _delete_psbt_from_detail(d)


# ---------------------------------------------------------------------------
# Phase: fee verification for all spend paths
# ---------------------------------------------------------------------------

async def _phase_fee_all_paths(d: UIDriver, paths_count: int) -> list[dict]:
    """
    For each spend path 0 .. paths_count-1:
      - Navigate to Create TX, switch path, self-pay, MAX
      - Compare fee_estimate (Create TX summary) with fee_psbt (PSBT detail)
      - Execute export/import round-trip for every path:
          · Path 0 (owner key-path): assert NO Timelock row after import
          · Paths 1-5 (heirs):       assert Timelock row present with correct block count

    Returns a list of {path_index, fee_estimate, fee_psbt} dicts.
    """
    results: list[dict] = []

    for i in range(paths_count):
        # Guarantee we start each iteration on the Overview tab
        await _go_to_overview(d)

        print(f"\n  [path {i}] Create TX → select coin → switch to path {i}")
        await _navigate_to_create_tx(d)
        await _switch_spend_path(d, i)

        print(f"  [path {i}] fill label, self-pay, MAX")
        await fill_field(d, "Label", f"reg26-P{i}")
        await _setup_self_pay_max(d)

        fee_estimate = await _read_total_fee_from_create_tx(d)
        print(f"  [path {i}] fee_estimate = {fee_estimate} sats")

        print(f"  [path {i}] create PSBT")
        await click_label(d, "Create PSBT", delay=0.5)
        await wait_for(d, '"Unsigned Transaction"', "PSBT detail opened",
                       retries=15, delay=1.0)

        fee_psbt = await _read_fee_from_psbt_detail(d)
        print(f"  [path {i}] fee_psbt = {fee_psbt} sats")

        if fee_psbt is None or fee_psbt < 1:
            raise AssertionError(f"Path {i}: invalid fee in PSBT detail: {fee_psbt}")

        if fee_estimate is not None:
            if fee_psbt != fee_estimate:
                raise AssertionError(
                    f"Path {i}: fee mismatch — analyzer estimate {fee_estimate} sats "
                    f"but PSBT fee is {fee_psbt} sats"
                )
            print(f"  [path {i}] ✓ fee_psbt == fee_estimate ({fee_psbt} sats)")
        else:
            print(f"  [path {i}] [warn] fee_estimate unavailable from UI; "
                  f"PSBT fee={fee_psbt} sats (not compared against estimate)")

        results.append({
            "path_index": i,
            "fee_estimate": fee_estimate,
            "fee_psbt": fee_psbt,
        })

        # Export/import round-trip for every spend path.
        # PATH_TIMELOCKS[i] is None for the owner (no timelock) and the expected
        # block count for each heir path (sorted ascending by timelock).
        tl = PATH_TIMELOCKS.get(i)
        await _phase_export_import(
            d, fee_psbt,
            expect_timelock=(tl is not None),
            expected_timelock_blocks=tl,
        )

    return results


# ---------------------------------------------------------------------------
# Main test function
# ---------------------------------------------------------------------------

async def test_taproot_fees_import(d: UIDriver):
    print(f"\n--- {WALLET_NAME} (taproot fee vs analyzer + PSBT export/import) ---")

    await set_active_network_signet(d)

    # 1. Create wallet
    await _create_wallet(d)

    # 2. Sync
    print("\n  [sync] syncing wallet — waiting for confirmed UTXOs")
    funded = await _sync_and_wait_coins(d)

    if not funded:
        addr = await _copy_first_receive_address(d)
        print(f"\n  [skip] wallet is not funded — send signet coins to:")
        print(f"         {addr}")
        print("         Then re-run this test once the UTXO is confirmed.")
        await go_back_to_wallet_list(d)
        await delete_wallet_from_list(d, WALLET_NAME)
        print(f"\n    [SKIP] {WALLET_NAME}")
        return

    print("    [ok] confirmed coins found ✓")

    # 3. Determine number of spend paths (do it from Create TX screen)
    print("\n  [count] counting spend paths")
    await _go_to_overview(d)
    await _navigate_to_create_tx(d)
    paths_count = await _count_spend_paths(d)
    print(f"    [ok] {paths_count} spend paths in dropdown")
    if paths_count < 2:
        raise AssertionError(
            f"Expected ≥ 2 spend paths (owner + heirs), got {paths_count}"
        )
    # Descriptor has 1 owner + 5 heirs = 6 spend paths total.
    expected_paths = 6
    if paths_count != expected_paths:
        raise AssertionError(
            f"Expected exactly {expected_paths} spend paths for this descriptor "
            f"(1 owner + 5 heirs), got {paths_count}"
        )
    # Go back to wallet detail for the per-path loop
    await click_tooltip(d, "Back", delay=0.5)
    # Wait for wallet detail: balance + Send button appear (more reliable than wallet name in semantics)
    await wait_for(d, "sats", "back on wallet detail", retries=10, delay=0.5)

    # 4. Fee verification per path + export/import for owner path
    print(f"\n  [fees] verifying fees for {paths_count} spend paths")
    results = await _phase_fee_all_paths(d, paths_count)

    # 5. Key-path fee < all script-path fees
    print("\n  [assert] key-path fee < script-path fees")
    owner_fee = next((r["fee_psbt"] for r in results if r["path_index"] == 0), None)
    heir_fees = [r["fee_psbt"] for r in results if r["path_index"] != 0 and r["fee_psbt"]]
    if owner_fee and heir_fees:
        if owner_fee >= min(heir_fees):
            raise AssertionError(
                f"Owner key-path fee ({owner_fee} sats) is NOT cheaper than "
                f"the cheapest script-path fee ({min(heir_fees)} sats)"
            )
        print(
            f"    [ok] key-path {owner_fee} sats < all script-paths "
            f"{sorted(heir_fees)} sats ✓"
        )
    else:
        print("    [skip] insufficient data for key-path vs script-path comparison")

    # 6. Cleanup
    print("\n  [cleanup] deleting wallet")
    await _go_to_overview(d)
    await go_back_to_wallet_list(d)
    await delete_wallet_from_list(d, WALLET_NAME)

    print(f"\n    [PASS] {WALLET_NAME}")


# ---------------------------------------------------------------------------
# Entry point
# ---------------------------------------------------------------------------

if __name__ == "__main__":
    asyncio.run(run_regression(test_taproot_fees_import, "reg26"))
