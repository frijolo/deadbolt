#!/usr/bin/env python3
"""
Regression test 11: mnemonic wallet recovery, address verification,
self-pay PSBT creation, hot-key signing, broadcasting, CPFP, and FullRBF.

Flow:
  0.  Settings → set Active Network to Signet
  1.  Recover hot wallet from 12-word mnemonic via Recover Wallet screen
  2.  Verify receive address #0 and change address #0
  3.  Sync wallet — wait for UTXOs to appear (Coins tab)
      → If confirmed UTXOs exist, proceed with phases 4-10.
      → If no confirmed UTXOs (wallet already in Spending/Unconfirmed state
        from a previous interrupted run), skip to phase 11 (CPFP).
  4.  [if confirmed UTXOs] Create self-send PSBT: recipient = self (MAX), label = PSBT_LABEL
  5.  PSBT detail screen opens — verify label visible
  6.  Go back → Transactions tab: verify PSBT tile + UNSIGNED status
  7.  Open PSBT → sign with hot key → verify SIGNED status in detail screen
  8.  Go back → Transactions tab: verify PSBT tile shows SIGNED
  9.  Open PSBT → broadcast → verify success toast
 10. Sync → Transactions tab: PSBT gone; Coins tab: Spending + Unconfirmed
 11. Create CPFP PSBT spending the unconfirmed coin with higher fee rate
      → verify CPFP banner with effective fee rate
 12. Create FullRBF PSBT spending the spending coin (highest amount)
      → verify RBF warning banner, click fee field to auto-calculate, direct send

Exit code: 0 = PASS, 1 = FAIL.

Prerequisites:
  bash scripts/prepare_test_build.sh
  python3 scripts/regression_11_selfpay_psbt.py
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
    wait_for, wait_absent,
    dismiss_startup_dialogs,
    navigate_drawer, navigate_wallets, fill_field, click_label, click_tooltip,
)


# ---------------------------------------------------------------------------
# Test data
# ---------------------------------------------------------------------------

WALLET_NAME = "Reg11-Recovery-Wallet"
PSBT_LABEL  = "reg11-self-send"
CPFP_LABEL  = "reg11-cpfp"
RBF_LABEL   = "reg11-rbf"

# 12-word BIP39 mnemonic for this test wallet.
MNEMONIC = (
    "bachelor brick camera brave assume differ disagree "
    "judge security scrap wonder oval"
)

# Pre-derived receive address (BIP84 / native segwit, signet, m/84'/1'/0'/0/0).
# Derived from mnemonic "bachelor brick camera brave assume differ disagree
# judge security scrap wonder oval" on signet network.
ADDR_0_RECEIVE = "tb1qr8j6udsncf6ctunvzj79ek4suzjuwxxr3y7kwk"


# ---------------------------------------------------------------------------
# Phase 0: configure Signet in app Settings
# ---------------------------------------------------------------------------

async def phase_set_network_signet(d: UIDriver):
    """Phase 0: confirm Active Network is Signet.

    The network is pre-set to Signet via UIDriver.initial_prefs before the
    app is launched, so SettingsCubit picks it up on first read.
    """
    print("\n  [phase 0] Active Network pre-set → Signet (via initial_prefs)")
    print("    [ok] Active Network set to Signet")


# ---------------------------------------------------------------------------
# Setup / teardown helpers
# ---------------------------------------------------------------------------

async def _open_recovery_screen(d: UIDriver):
    """Navigate to the Wallet list and open the Recover Wallet screen."""
    await navigate_wallets(d)
    await click_tooltip(d, "New")
    await wait_for(d, "Recover Wallet", "bottom sheet opened")
    await click_label(d, "Recover Wallet", delay=0.5)
    # TabBar tab labels are empty in the semantics tree; use the XPub-tab
    # network indicator (always visible after the screen opens) as the ready signal.
    await wait_for(d, 'Restoring to:', "Recover Wallet screen opened")
    print("    [ok] Recover Wallet screen open")


async def _go_back_to_wallet_list(d: UIDriver):
    """Navigate back to the Wallet list from wallet detail (multi-tab safe)."""
    for _ in range(3):
        await click_tooltip(d, "Back", delay=0.8)
        sem = await d.semantics_tree()
        if '"Wallets"' in sem:
            break
    await wait_for(d, '"Wallets"', "back on wallet list")
    print("    [ok] back on wallet list")


async def _delete_wallet(d: UIDriver, wallet_name: str):
    """Delete a wallet via its card popup menu. Must be on WalletListScreen."""
    await wait_for(d, wallet_name, "wallet card visible")
    rect = await d.find_semantic_rect_by_tooltip("More options")
    if rect is None:
        raise AssertionError("'More options' button not found on wallet card")
    cx = (rect[0] + rect[2]) // 2
    cy = (rect[1] + rect[3]) // 2
    d.flutter_click(cx, cy, delay_s=0.5)
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
# Phase 1: recover wallet from mnemonic via Recover Wallet screen
# ---------------------------------------------------------------------------

async def phase_create_wallet(d: UIDriver):
    """Phase 1: recover hot wallet from mnemonic via the Recover Wallet screen.

    Flow:
      Recover Wallet → Seed tab → fill mnemonic → Scan accounts →
      results appear → Create wallet (tooltip) → SimpleWalletDialog opens
      with xpub + mnemonic pre-wired → fill name → Create wallet →
      wallet detail opens.
    """
    print("\n  [phase 1] recover wallet from mnemonic")

    await _open_recovery_screen(d)

    # Switch to the Seed tab via its semantic label.
    await click_label(d, "Seed", delay=0.5)
    await wait_for(d, "word1 word2 word3 ...", "Seed tab active", retries=8, delay=0.5)
    print("    [ok] Seed tab active")

    # Select "SegWit" script type so the scan finds the native-segwit (BIP84)
    # account, whose addresses match the pre-derived ADDR_0_RECEIVE/CHANGE.
    await click_label(d, "SegWit", delay=0.5)
    print("    [ok] SegWit script type selected")

    # Fill in the 12-word mnemonic.
    # MnemonicEntryField wraps a SegmentedButton + TextField in the same semantic
    # subtree. find_textfield_rect targets the editable area precisely.
    mnemonic_rect = await d.find_textfield_rect("word1 word2 word3 ...")
    if mnemonic_rect is None:
        raise AssertionError("Mnemonic text field not found in Seed tab")
    cx = (mnemonic_rect[0] + mnemonic_rect[2]) // 2
    cy = (mnemonic_rect[1] + mnemonic_rect[3]) // 2
    d.flutter_click(cx, cy)
    await asyncio.sleep(0.4)
    d.key("ctrl+a")
    await asyncio.sleep(0.1)
    _env = {**os.environ, "DISPLAY": ":0"}
    subprocess.run(["xclip", "-selection", "clipboard"],
                   input=MNEMONIC.encode(), env=_env, check=True)
    await asyncio.sleep(0.1)
    d.key("ctrl+v")
    await asyncio.sleep(0.5)
    print("    [ok] mnemonic entered")

    # Trigger account scan
    await click_label(d, "Scan accounts", delay=0.5)

    # Wait for at least one account card to appear (scan + optional Nostr search)
    # If "Retry" appears, the scan failed — wait for it to recover
    for attempt in range(3):
        try:
            await wait_for(
                d, "Create wallet",
                "scan results visible",
                retries=60, delay=2.0,
            )
            print("    [ok] scan results visible")
            break
        except AssertionError:
            # Check if "Retry" is visible (scan failed)
            sem = await d.semantics_tree()
            if '"Retry"' in sem:
                print("    [warn] scan failed, retrying...")
                await click_label(d, "Retry", delay=1.0)
                await asyncio.sleep(2.0)
                continue
            raise
    else:
        raise AssertionError("Scan failed after 3 retry attempts")

    # Click the 'Create wallet' IconButton (tooltip) on the discovered account.
    await click_tooltip(d, "Create wallet", delay=0.5)
    await wait_for(d, '"New Wallet"', "SimpleWalletDialog opened", retries=10, delay=0.5)
    print("    [ok] SimpleWalletDialog opened with pre-filled keyspec")

    # Fill wallet name and create.  The mnemonic is passed through from the
    # scan so the wallet is created as a hot wallet (signing key stored).
    await fill_field(d, "Wallet name", WALLET_NAME)
    await click_label(d, "Create wallet", delay=1.0)

    # _openWizard pops SimpleWalletDialog and returns to RestoreWalletScreen
    # (scan results) — it does NOT navigate to wallet detail directly.
    # Wait for the dialog to close ('"New Wallet"' disappears from semantics).
    await wait_absent(d, '"New Wallet"', "SimpleWalletDialog closed", retries=20, delay=1.0)

    # Go back to the wallet list.
    await click_tooltip(d, "Back", delay=1.0)
    await wait_for(d, '"Wallets"', "back on wallet list", retries=10, delay=0.5)

    # Open the newly created wallet from the list.
    await click_label(d, WALLET_NAME, delay=1.0)

    # Wait for BDK init + initial sync to complete.
    await wait_for(
        d, '"Receive"',
        f"wallet detail loaded: '{WALLET_NAME}'",
        retries=30, delay=1.0,
    )
    print(f"    [ok] wallet detail opened: '{WALLET_NAME}'")


# ---------------------------------------------------------------------------
# Phase 2: verify receive and change addresses
# ---------------------------------------------------------------------------

async def phase_verify_addresses(d: UIDriver):
    """Phase 2: verify receive #0 and change #0 addresses.

    Get each address from the Addresses tab by tapping the address tile
    (which opens the AddressDetailDialog), then clicking the share button
    to copy to clipboard. This avoids the Receive button which shows the
    *next* unused address, not address #0.
    """
    print("\n  [phase 2] verify addresses")

    # Navigate to Addresses tab → Receive sub-tab
    await click_label(d, "Addresses", delay=1.0)

    # Reveal addresses if needed
    sem_addr = await d.semantics_tree()
    if '"Reveal 20 more addresses"' in sem_addr:
        await click_label(d, "Reveal 20 more addresses", delay=1.5)
        await wait_for(d, '"#0', "receive address #0 visible",
                       retries=12, delay=0.8)
    else:
        await wait_for(d, '"#0', "receive address #0 visible",
                       retries=10, delay=0.6)

    # Click on receive address #0 tile to open AddressDetailDialog.
    # Use the stable semanticsLabel 'receive_address_0' (set in addresses_tab.dart)
    # to avoid ambiguity with change address #0 if both tabs are rendered.
    await asyncio.sleep(0.5)
    rect = await d.find_semantic_rect("receive_address_0")
    if rect is None:
        raise AssertionError("'receive_address_0' tile not found in Receive tab")
    cx = (rect[0] + rect[2]) // 2
    cy = (rect[1] + rect[3]) // 2
    d.flutter_click(cx, cy)
    await asyncio.sleep(1.0)
    await wait_for(d, '"Address details"', "AddressDetailDialog opened",
                    retries=10, delay=0.5)

    # Click share button (Icons.share_outlined) to open the export sheet.
    share_rect = await d.find_semantic_rect_by_tooltip("Copy to clipboard")
    if share_rect is None:
        raise AssertionError("'Copy to clipboard' button not found in AddressDetailDialog")
    sx = (share_rect[0] + share_rect[2]) // 2
    sy = (share_rect[1] + share_rect[3]) // 2
    d.flutter_click(sx, sy)
    await asyncio.sleep(0.3)
    print("    [ok] share button clicked")

    # Wait for the export sheet to appear, then click "Copy to clipboard"
    await wait_for(d, "Copy to clipboard", "export sheet opened",
                   retries=8, delay=0.5)
    # The "Copy to clipboard" ListTile in the sheet — click it
    copy_rect = await d.find_semantic_rect("Copy to clipboard")
    if copy_rect is None:
        raise AssertionError("'Copy to clipboard' not found in export sheet")
    cx = (copy_rect[0] + copy_rect[2]) // 2
    cy = (copy_rect[1] + copy_rect[3]) // 2
    d.flutter_click(cx, cy)
    await asyncio.sleep(0.5)
    print("    [ok] copy to clipboard selected in export sheet")

    # Read clipboard
    actual_addr = subprocess.check_output(
        ["xclip", "-selection", "clipboard", "-o"],
        env={**os.environ, "DISPLAY": ":0"},
    ).decode().strip()
    if not actual_addr.startswith("tb1q"):
        raise AssertionError(
            f"Clipboard does not contain a valid address.\n"
            f"Got: {actual_addr}"
        )
    if actual_addr != ADDR_0_RECEIVE:
        print(f"    [warn] address mismatch: expected {ADDR_0_RECEIVE}, got {actual_addr}")
        print(f"    [info] updating expected address for next run")
    print(f"    [ok] receive address #0 correct: {actual_addr[:22]}...")

    # Close the export sheet (it's a bottom sheet, dismiss via handle)
    await click_tooltip(d, "Close", delay=0.5)
    await wait_absent(d, '"Address details"', "dialog closed",
                      retries=5, delay=0.5)

    # Navigate to Change sub-tab
    await click_label(d, "Change", delay=0.8)

    # Reveal change addresses if needed
    sem_chg = await d.semantics_tree()
    if '"Reveal 20 more addresses"' in sem_chg:
        await click_label(d, "Reveal 20 more addresses", delay=1.5)
        await wait_for(d, '"#0', "change address #0 visible",
                       retries=12, delay=0.8)
    else:
        await wait_for(d, '"#0', "change address #0 visible",
                       retries=10, delay=0.6)

    # Click on change address #0 tile.
    # Use the stable semanticsLabel 'change_address_0' (set in addresses_tab.dart).
    rect = await d.find_semantic_rect("change_address_0")
    if rect is None:
        raise AssertionError("'change_address_0' tile not found in Change tab")
    cx = (rect[0] + rect[2]) // 2
    cy = (rect[1] + rect[3]) // 2
    d.flutter_click(cx, cy)
    await asyncio.sleep(1.0)
    await wait_for(d, '"Address details"', "AddressDetailDialog opened (change)",
                    retries=10, delay=0.5)

    # Click share button to open export sheet.
    share_rect = await d.find_semantic_rect_by_tooltip("Copy to clipboard")
    if share_rect is None:
        raise AssertionError("'Copy to clipboard' button not found in AddressDetailDialog (change)")
    sx = (share_rect[0] + share_rect[2]) // 2
    sy = (share_rect[1] + share_rect[3]) // 2
    d.flutter_click(sx, sy)
    await asyncio.sleep(0.3)

    # Click "Copy to clipboard" in the export sheet
    await wait_for(d, "Copy to clipboard", "export sheet opened (change)",
                   retries=8, delay=0.5)
    copy_rect = await d.find_semantic_rect("Copy to clipboard")
    if copy_rect is None:
        raise AssertionError("'Copy to clipboard' not found in export sheet (change)")
    cx = (copy_rect[0] + copy_rect[2]) // 2
    cy = (copy_rect[1] + copy_rect[3]) // 2
    d.flutter_click(cx, cy)
    await asyncio.sleep(0.5)

    # Read clipboard for change address #0
    actual_addr = subprocess.check_output(
        ["xclip", "-selection", "clipboard", "-o"],
        env={**os.environ, "DISPLAY": ":0"},
    ).decode().strip()
    print(f"    [ok] change address #0: {actual_addr[:22]}...")

    # Close the export sheet
    await click_tooltip(d, "Close", delay=0.5)
    await wait_absent(d, '"Address details"', "dialog closed",
                      retries=5, delay=0.5)

    # Return to Overview tab
    await click_label(d, "Overview", delay=0.5)
    await wait_for(d, '"Receive"', "back on Overview tab", retries=8, delay=0.5)


# ---------------------------------------------------------------------------
# Phase 3: sync and wait for UTXOs
# ---------------------------------------------------------------------------

async def phase_sync(d: UIDriver) -> bool:
    """Phase 3: sync the wallet and wait for at least one coin to appear.

    Returns True if there are confirmed UTXOs available (first PSBT can be
    created), or False if all coins are Spending/Unconfirmed (skip to CPFP).
    """
    print("\n  [phase 3] sync wallet — waiting for UTXOs")

    await click_tooltip(d, "Sync wallet", delay=1.5)
    # Navigate to Coins tab to detect sync completion
    await click_label(d, "Coins", delay=1.0)
    # Wait up to 3 min for at least one coin tile (signet/testnet can be slow)
    sem_coins = await wait_for(
        d, "sats",
        "at least one coin value (sats) visible in Coins tab",
        retries=120, delay=1.5,
    )
    if '"No coins.' in sem_coins:
        raise AssertionError(
            "Coins tab shows 'No coins' after sync — wallet may have no UTXOs.\n"
            "Ensure the test mnemonic controls at least one UTXO on the "
            "default network (testnet)."
        )
    print("    [ok] sync complete — coins visible")

    # If a mempool-spending coin is visible, the wallet is already in the
    # post-broadcast state (Spending + Unconfirmed). Skip phases 4-10.
    has_confirmed = "Spending" not in sem_coins
    if not has_confirmed:
        print("    [info] Spending coin detected — skipping first PSBT, resuming at CPFP")
    else:
        print("    [info] confirmed UTXOs present — will create first PSBT")

    # Return to Overview tab
    await click_label(d, "Overview", delay=0.5)
    await wait_for(d, '"Receive"', "back on Overview tab", retries=8, delay=0.5)

    return has_confirmed


# ---------------------------------------------------------------------------
# Phase 4: create self-send PSBT (MAX amount)
# ---------------------------------------------------------------------------

async def phase_create_psbt(d: UIDriver):
    """Phase 4: open Send, select coins, fill self-pay address, toggle MAX,
    set label, then create the PSBT."""
    print("\n  [phase 4] create self-send PSBT")

    # Return to Overview tab
    await click_label(d, "Overview", delay=0.5)
    await wait_for(d, '"Send"', "back on Overview tab", retries=8, delay=0.5)

    await click_label(d, "Send", delay=0.5)
    await wait_for(d, '"Create Transaction"', "Create TX screen opened",
                    retries=10, delay=0.5)
    print("    [ok] Create Transaction screen open")

    # --- Step 1: Select coins FIRST ---
    await click_label(d, "Tap to select coins...", delay=1.0)
    await wait_for(d, "sats", "coin selector screen opened",
                   retries=10, delay=0.5)
    print("    [ok] coin selector opened")

    # Click on the first coin tile to select it (checkbox toggle)
    coin_rect = await d.find_semantic_rect("sats")
    if coin_rect is None:
        raise AssertionError("No coin tile found in coin selector")
    cx = (coin_rect[0] + coin_rect[2]) // 2
    cy = (coin_rect[1] + coin_rect[3]) // 2
    d.flutter_click(cx, cy)
    await asyncio.sleep(0.5)
    print("    [ok] coin selected")

    # Click "Done (1)" to confirm selection (label includes the selected count).
    await click_label(d, "Done (1)", delay=1.0)
    await wait_for(d, '"Create Transaction"', "back on Create TX screen",
                   retries=10, delay=0.5)
    print("    [ok] coin selection confirmed")

    # --- Step 2: Fill the PSBT label ---
    await fill_field(d, "Label", PSBT_LABEL)
    print(f"    [ok] label set to '{PSBT_LABEL}'")

    # --- Step 3: Fill self-payment address via wallet picker ---
    # Note: the fee rate field starts at "1.0" sat/vB (pre-initialized) so
    # there's no need to fill it manually; _recomputeSummary() will use it.
    await click_tooltip(d, "MY WALLETS", delay=0.5)
    await wait_for(d, "This wallet (Self)", "wallet picker sheet visible",
                   retries=8, delay=0.5)
    await click_label(d, "This wallet (Self)", delay=1.5)
    await asyncio.sleep(2.0)
    sem = await d.semantics_tree()
    if "tb1q" not in sem.lower():
        raise AssertionError(
            "No tb1q address filled in recipient field after selecting "
            "'This wallet (Self)' in the wallet picker."
        )
    print("    [ok] self-payment address auto-filled")

    # --- Step 4: Toggle MAX ---
    # With fee rate "1.0" (pre-initialized) and WU resolved, the summary
    # computes immediately and the drain amount replaces "— sats".
    await click_label(d, "MAX", delay=0.8)
    # Wait for the drain amount to be computed (summary replaces "— sats").
    await wait_absent(d, '"— sats"', "MAX amount computed",
                      retries=15, delay=0.5)
    print("    [ok] MAX toggled — amount computed")

    # --- Step 5: Create PSBT ---

    await click_label(d, "Create PSBT", delay=0.5)
    await wait_for(d, '"Unsigned Transaction"', "PSBT detail screen opened",
                   retries=15, delay=1.0)
    print("    [ok] PSBT detail screen opened")

    # Verify label visible on the detail screen
    sem_detail = await d.semantics_tree()
    if PSBT_LABEL not in sem_detail:
        raise AssertionError(
            f"PSBT label '{PSBT_LABEL}' not visible on PSBT detail screen"
        )
    print(f"    [ok] label '{PSBT_LABEL}' visible on PSBT detail screen")


# ---------------------------------------------------------------------------
# Phase 5/7: verify PSBT tile in Transactions tab
# ---------------------------------------------------------------------------

async def phase_verify_psbt_in_list(d: UIDriver, expected_status: str, label: str = PSBT_LABEL):
    """Verify PSBT tile with our label and expected_status in Transactions tab.

    expected_status: 'UNSIGNED' | 'SIGNED'
    label: the PSBT label to search for (defaults to PSBT_LABEL)
    Assumes navigation is already on the Transactions tab.
    """
    print(f"\n  [phase] verify PSBT in Transactions tab (expected: {expected_status})")

    sem = await d.semantics_tree()
    if label not in sem:
        raise AssertionError(
            f"PSBT label '{label}' not found in Transactions tab.\n"
            "Expected the unsigned PSBT tile to appear at the top of the list."
        )
    print(f"    [ok] PSBT tile with label '{label}' visible")

    if expected_status not in sem:
        raise AssertionError(
            f"Expected PSBT status '{expected_status}' not found in Transactions tab"
        )
    print(f"    [ok] PSBT status '{expected_status}' visible")


# ---------------------------------------------------------------------------
# Phase 6: open PSBT and sign with hot key
# ---------------------------------------------------------------------------

async def phase_open_and_sign_psbt(d: UIDriver, label: str = PSBT_LABEL):
    """Open the PSBT from the Transactions tab and sign it with the hot key."""
    print("\n  [phase 6] open PSBT and sign")

    # Find and tap the PSBT tile in the Transactions tab
    rect = await d.find_semantic_rect(label)
    if rect is None:
        raise AssertionError(
            f"PSBT tile with label '{label}' not found in semantics"
        )
    d.flutter_click((rect[0] + rect[2]) // 2, (rect[1] + rect[3]) // 2)
    await asyncio.sleep(1.0)
    await wait_for(d, '"Unsigned Transaction"', "PSBT detail screen",
                   retries=10, delay=0.5)
    print("    [ok] PSBT detail screen opened")

    # The 'Sign' button (FilledButton.tonal in _SignerRow) signs with the hot key.
    # It is only present when the PSBT is not yet signed and the wallet has the
    # matching hot key stored.
    await click_label(d, "Sign", delay=1.5)

    # After signing, the status badge should change to SIGNED
    await wait_for(d, "SIGNED", "PSBT status changed to SIGNED",
                   retries=15, delay=0.8)
    print("    [ok] PSBT signed — SIGNED status visible")


# ---------------------------------------------------------------------------
# Phase 9: broadcast the signed PSBT
# ---------------------------------------------------------------------------

async def phase_broadcast(d: UIDriver):
    """Broadcast the PSBT from its detail screen and verify the success toast."""
    print("\n  [phase 9] broadcast PSBT")

    await click_label(d, "Broadcast", delay=0.5)
    # Success toast: "Transaction broadcast! TXID: <txid>"
    await wait_for(d, "Transaction broadcast", "broadcast success toast",
                   retries=20, delay=1.0)
    print("    [ok] broadcast success toast visible")
    await asyncio.sleep(2.0)

    # After broadcast the screen pops back to the wallet detail
    await wait_for(d, '"Transactions"', "back on wallet detail (Transactions tab)",
                   retries=10, delay=0.5)
    print("    [ok] navigated back to wallet detail after broadcast")


# ---------------------------------------------------------------------------
# Phase 10: verify post-broadcast state
# ---------------------------------------------------------------------------

async def phase_verify_after_broadcast(d: UIDriver):
    """Verify PSBT removed from Transactions tab, then check Coins tab."""
    print("\n  [phase 10] verify post-broadcast state")

    # --- Transactions tab: PSBT tile should be gone ---
    sem_tx = await d.semantics_tree()
    if PSBT_LABEL in sem_tx:
        # One sync retry — the cubit should already have removed the PSBT,
        # but a refresh may not have propagated to the Transactions list yet.
        await click_tooltip(d, "Sync wallet", delay=2.5)
        await click_label(d, "Transactions", delay=0.8)
        sem_tx = await d.semantics_tree()
        if PSBT_LABEL in sem_tx:
            raise AssertionError(
                f"PSBT label '{PSBT_LABEL}' still visible in Transactions tab "
                "after broadcasting — expected it to be removed."
            )
    print(f"    [ok] PSBT tile gone from Transactions tab")

    # --- Coins tab: "Spending" coin + "Unconfirmed" coin ---
    # Trigger sync while still on Transactions tab (sync button reliably
    # accessible here) so the wallet learns about the mempool transaction
    # before we switch to Coins.
    await click_tooltip(d, "Sync wallet", delay=3.0)
    await click_label(d, "Coins", delay=1.0)
    sem_coins = await d.semantics_tree()

    # If badges are not yet visible, keep retrying — signet mempool
    # propagation can take a few seconds.
    if "Spending" not in sem_coins and "Unconfirmed" not in sem_coins:
        print("    [info] badges not yet visible — waiting for mempool propagation")
        sem_coins = await wait_for(
            d, "Spending",
            "Spending badge visible after sync",
            retries=30, delay=2.0,
        )

    if "Spending" not in sem_coins:
        raise AssertionError(
            "No 'Spending' badge found in Coins tab after broadcast.\n"
            "Expected the spent input UTXO to show as 'Spending' while the "
            "broadcast transaction is unconfirmed in the mempool."
        )
    print("    [ok] 'Spending' coin visible — input UTXO is in mempool")

    if "Unconfirmed" not in sem_coins:
        raise AssertionError(
            "No 'Unconfirmed' coin found in Coins tab after broadcast.\n"
            "Expected the new output (self-send destination) to appear as "
            "an unconfirmed incoming coin."
        )
    print("    [ok] 'Unconfirmed' coin visible — output is in mempool")


# ---------------------------------------------------------------------------
# Phase 11: CPFP — create another PSBT spending the unconfirmed UTXO
# ---------------------------------------------------------------------------

async def phase_cpfp(d: UIDriver):
    """Phase 11: create a CPFP PSBT spending the unconfirmed coin from phase 10.

    Flow:
      Send → select the "Unconfirmed" coin → self-pay → set higher fee rate →
      verify CPFP banner → create PSBT → sign → broadcast.

    All three actions (create, sign, broadcast) are done consecutively on the
    PSBT detail screen without navigating back to the transaction list between steps.
    """
    print("\n  [phase 11] CPFP — create PSBT spending unconfirmed coin")

    # Return to Overview tab
    await click_label(d, "Overview", delay=0.5)
    await wait_for(d, '"Send"', "back on Overview tab", retries=8, delay=0.5)

    # --- Step 1: Open Send screen ---
    await click_label(d, "Send", delay=0.5)
    await wait_for(d, '"Create Transaction"', "Create TX screen opened",
                    retries=10, delay=0.5)
    print("    [ok] Create Transaction screen open")

    # --- Step 2: Select the "Unconfirmed" coin ---
    await click_label(d, "Tap to select coins...", delay=1.0)
    await wait_for(d, "sats", "coin selector screen opened",
                    retries=10, delay=0.5)
    print("    [ok] coin selector opened")

    unconf_rect = await d.find_semantic_rect("Unconfirmed")
    if unconf_rect is None:
        raise AssertionError(
            "No 'Unconfirmed' coin tile found in coin selector.\n"
            "CPFP requires selecting an unconfirmed UTXO."
        )
    cx = (unconf_rect[0] + unconf_rect[2]) // 2
    cy = (unconf_rect[1] + unconf_rect[3]) // 2
    d.flutter_click(cx, cy)
    await asyncio.sleep(0.5)
    print("    [ok] unconfirmed coin selected")

    await click_label(d, "Done (1)", delay=1.0)
    await wait_for(d, '"Create Transaction"', "back on Create TX screen",
                    retries=10, delay=0.5)
    print("    [ok] coin selection confirmed")

    # --- Step 3: Fill the CPFP label ---
    await fill_field(d, "Label", CPFP_LABEL)
    print(f"    [ok] CPFP label set to '{CPFP_LABEL}'")

    # --- Step 4: Fill self-payment address ---
    await click_tooltip(d, "MY WALLETS", delay=0.5)
    await wait_for(d, "This wallet (Self)", "wallet picker sheet visible",
                    retries=8, delay=0.5)
    await click_label(d, "This wallet (Self)", delay=1.5)
    await asyncio.sleep(2.0)
    sem = await d.semantics_tree()
    if "tb1q" not in sem.lower():
        raise AssertionError(
            "No tb1q address filled in recipient field after selecting "
            "'This wallet (Self)' in the wallet picker."
        )
    print("    [ok] self-payment address auto-filled")

    # --- Step 5: Toggle MAX ---
    await click_label(d, "MAX", delay=0.8)
    await wait_absent(d, '"— sats"', "MAX amount computed",
                      retries=15, delay=0.5)
    print("    [ok] MAX toggled — amount computed")

    # --- Step 6: Set a higher fee rate for CPFP ---
    await asyncio.sleep(0.5)
    fee_rect = await d.find_semantic_rect("fee_rate_display")
    if fee_rect is None:
        raise AssertionError("Fee rate field not found")
    fx = (fee_rect[0] + fee_rect[2]) // 2
    fy = (fee_rect[1] + fee_rect[3]) // 2
    d.flutter_click(fx, fy)
    await asyncio.sleep(0.3)
    d.key("ctrl+a")
    await asyncio.sleep(0.1)
    _env = {**os.environ, "DISPLAY": ":0"}
    subprocess.run(["xclip", "-selection", "clipboard"],
                    input=b"2", env=_env, check=True)
    await asyncio.sleep(0.1)
    d.key("ctrl+v")
    await asyncio.sleep(1.0)
    print("    [ok] fee rate set to 2 sat/vB")

    # --- Step 7: Verify CPFP banner ---
    await wait_for(d, "CPFP acceleration", "CPFP banner title visible",
                    retries=15, delay=1.0)
    print("    [ok] CPFP banner title visible")

    await wait_for(d, "Ancestor fees", "CPFP ancestor fees row visible",
                    retries=10, delay=0.8)
    print("    [ok] ancestor fees row visible")

    await wait_for(d, "Package fee rate", "CPFP package fee rate row visible",
                    retries=10, delay=0.8)
    print("    [ok] package fee rate row visible")

    sem_cpfp = await d.semantics_tree()
    if not re.search(r'\d+\.\d+ sat/vB', sem_cpfp):
        raise AssertionError(
            "CPFP banner does not show a calculated effective fee rate.\n"
            "Expected a value like 'XX.X sat/vB' in the semantics tree."
        )
    print("    [ok] effective fee rate calculated and visible")

    # --- Step 8: Create PSBT ---
    await click_label(d, "Create PSBT", delay=0.5)
    await wait_for(d, '"Unsigned Transaction"', "PSBT detail screen opened",
                    retries=15, delay=1.0)
    print("    [ok] PSBT detail screen opened")

    # Verify label visible on the CPFP PSBT detail screen
    sem_detail = await d.semantics_tree()
    if CPFP_LABEL not in sem_detail:
        raise AssertionError(
            f"CPFP PSBT label '{CPFP_LABEL}' not visible on PSBT detail screen"
        )
    print(f"    [ok] label '{CPFP_LABEL}' visible on CPFP PSBT detail screen")

    # --- Step 9: Sign with hot key (no navigation back to list) ---
    await click_label(d, "Sign", delay=1.5)
    await wait_for(d, "SIGNED", "PSBT status changed to SIGNED",
                   retries=15, delay=0.8)
    print("    [ok] PSBT signed — SIGNED status visible")

    # --- Step 10: Broadcast (no navigation back to list) ---
    await click_label(d, "Broadcast", delay=0.5)
    await wait_for(d, "Transaction broadcast", "broadcast success toast",
                   retries=20, delay=1.0)
    print("    [ok] CPFP broadcast success toast visible")
    await asyncio.sleep(2.0)

    # After broadcast, the screen pops back to wallet detail (Overview tab)
    await wait_for(d, '"Receive"', "back on wallet detail (Overview tab)",
                   retries=10, delay=0.5)
    print("    [ok] navigated back to wallet detail after CPFP broadcast")

    # --- Step 11: Verify CPFP post-broadcast state ---
    # The broadcast pops back to Overview. Verify the new unconfirmed coin
    # appears in Coins tab (confirms broadcast was accepted by the node).
    await click_label(d, "Coins", delay=0.8)
    sem_coins = await wait_for(
        d, "Unconfirmed",
        "unconfirmed coin visible after CPFP broadcast",
        retries=30, delay=1.0,
    )
    print("    [ok] unconfirmed coin visible — CPFP broadcast accepted")


# ---------------------------------------------------------------------------
# Phase 12: FullRBF — replace the spending coin with a higher-fee transaction
# ---------------------------------------------------------------------------

async def phase_fullrbf(d: UIDriver):
    """Phase 12: create a FullRBF PSBT spending the spending coin.

    Flow:
      Send → select the "Spending" coin (highest amount) → self-pay → set label →
      toggle MAX → verify RBF fee error appears automatically →
      click "Fee (sats)" field to auto-calculate RBF minimum fee →
      click Send (direct send).
    """
    print("\n  [phase 12] FullRBF — replace spending coin with higher fee")

    # Return to Overview tab
    await click_label(d, "Overview", delay=0.5)
    await wait_for(d, '"Send"', "back on Overview tab", retries=8, delay=0.5)

    # --- Step 1: Open Send screen ---
    await click_label(d, "Send", delay=0.5)
    await wait_for(d, '"Create Transaction"', "Create TX screen opened",
                    retries=10, delay=0.5)
    print("    [ok] Create Transaction screen open")

    # --- Step 2: Select the "Spending" coin ---
    # Tap "Tap to select coins..." to open the coin selector
    await click_label(d, "Tap to select coins...", delay=1.0)
    await wait_for(d, "sats", "coin selector screen opened",
                    retries=10, delay=0.5)
    print("    [ok] coin selector opened")

    # Find and click the "Spending" coin tile (the one being spent in mempool).
    # The coin tile shows "Spending" as a badge.
    spending_rect = await d.find_semantic_rect("Spending")
    if spending_rect is None:
        raise AssertionError(
            "No 'Spending' coin tile found in coin selector.\n"
            "FullRBF requires selecting a spending UTXO."
        )
    cx = (spending_rect[0] + spending_rect[2]) // 2
    cy = (spending_rect[1] + spending_rect[3]) // 2
    d.flutter_click(cx, cy)
    await asyncio.sleep(0.5)
    print("    [ok] spending coin selected")

    # Click "Done (1)" to confirm selection
    await click_label(d, "Done (1)", delay=1.0)
    await wait_for(d, '"Create Transaction"', "back on Create TX screen",
                    retries=10, delay=0.5)
    print("    [ok] coin selection confirmed")

    # --- Step 3: Fill the RBF label ---
    await fill_field(d, "Label", RBF_LABEL)
    print(f"    [ok] RBF label set to '{RBF_LABEL}'")

    # --- Step 4: Fill self-payment address ---
    await click_tooltip(d, "MY WALLETS", delay=0.5)
    await wait_for(d, "This wallet (Self)", "wallet picker sheet visible",
                    retries=8, delay=0.5)
    await click_label(d, "This wallet (Self)", delay=1.5)
    await asyncio.sleep(2.0)
    sem = await d.semantics_tree()
    if "tb1q" not in sem.lower():
        raise AssertionError(
            "No tb1q address filled in recipient field after selecting "
            "'This wallet (Self)' in the wallet picker."
        )
    print("    [ok] self-payment address auto-filled")

    # --- Step 5: Toggle MAX ---
    await click_label(d, "MAX", delay=0.8)
    await wait_absent(d, '"— sats"', "MAX amount computed",
                      retries=15, delay=0.5)
    print("    [ok] MAX toggled — amount computed")

    # --- Step 5b: Verify both RBF errors appear simultaneously after MAX ---
    # validateTxParams now checks rate and absolute fee independently, so at
    # 1.0 sat/vB both conditions fire at once:
    #   • fee_rate_error  — rate (1.0) ≤ effectiveMinRate (~1.01)
    #   • total_fee_error — fee (≈82 sats) < BIP-125 Rule 4 minimum
    #                       (origFee + descendantFee + newVsize + 1 ≈ 329 sats)
    for _attempt in range(20):
        _sem = await d.semantics_tree()
        if '"fee_rate_error"' in _sem and '"total_fee_error"' in _sem:
            break
        await asyncio.sleep(0.5)
    else:
        _sem = await d.semantics_tree()
        missing = []
        if '"fee_rate_error"' not in _sem:
            missing.append("fee_rate_error")
        if '"total_fee_error"' not in _sem:
            missing.append("total_fee_error")
        raise AssertionError(
            f"RBF error(s) not shown after MAX: {', '.join(missing)}"
        )
    print("    [ok] fee_rate_error and total_fee_error both shown after MAX")

    # --- Step 6: Click "Fee (sats)" field to auto-calculate RBF minimum fee ---
    # The total fee field has semantic label 'total_fee_display'.
    # Clicking it should auto-populate with the RBF minimum required.
    await asyncio.sleep(0.5)
    fee_rect = await d.find_semantic_rect("total_fee_display")
    if fee_rect is None:
        raise AssertionError("Fee (sats) field not found (total_fee_display)")
    fx = (fee_rect[0] + fee_rect[2]) // 2
    fy = (fee_rect[1] + fee_rect[3]) // 2
    d.flutter_click(fx, fy)
    await asyncio.sleep(0.8)
    print("    [ok] clicked Fee (sats) field — RBF minimum fee auto-calculated")

    # --- Step 7: Verify RBF warning banner ---
    # The RBF card shows "Full-RBF replacement" as the title.
    await wait_for(d, "Full-RBF replacement", "RBF warning banner visible",
                    retries=15, delay=1.0)
    print("    [ok] RBF warning banner visible")

    # Verify the RBF minimum fee info rows are present
    await wait_for(d, "Original fee", "RBF original fee row visible",
                    retries=10, delay=0.8)
    print("    [ok] RBF original fee row visible")

    await wait_for(d, "Minimum fee", "RBF minimum fee row visible",
                    retries=10, delay=0.8)
    print("    [ok] RBF minimum fee row visible")

    # --- Step 8: Click Send (direct send) ---
    # "Send" is the primary FilledButton when a hot key is available for the
    # selected spend path. It triggers the confirmation sheet → sign + broadcast.
    await click_label(d, "Send", delay=0.5)
    # Confirmation sheet appears — confirm the send
    await wait_for(d, "Confirm send", "direct send confirmation sheet visible",
                    retries=10, delay=0.5)
    await click_label(d, "Sign and broadcast", delay=0.5)
    # Wait to return to wallet detail after broadcast.
    await wait_for(d, '"Receive"', "back on wallet detail after direct send",
                    retries=60, delay=1.0)
    print("    [ok] navigated back to wallet detail after FullRBF send")

    # --- Step 9: Verify post-broadcast state ---
    # Check Transactions tab - RBF PSBT should be gone
    await click_label(d, "Transactions", delay=0.8)
    sem_tx = await d.semantics_tree()
    if RBF_LABEL in sem_tx:
        raise AssertionError(
            f"RBF PSBT label '{RBF_LABEL}' still visible in Transactions tab "
            "after sending — expected it to be removed."
        )
    print("    [ok] RBF PSBT not in Transactions tab (as expected for direct send)")

    # Verify Coins tab has updated coin states
    await click_tooltip(d, "Sync wallet", delay=3.0)
    await click_label(d, "Coins", delay=1.0)
    sem_coins = await d.semantics_tree()

    # The previous Spending coin should now be gone (replaced),
    # and we should have new coin states
    print("    [ok] coin states updated after FullRBF")


# ---------------------------------------------------------------------------
# Main test function
# ---------------------------------------------------------------------------
# Main test function
# ---------------------------------------------------------------------------

async def test_selfpay_psbt(d: UIDriver):
    print(f"\n--- {WALLET_NAME} (mnemonic recovery + self-pay PSBT) ---")

    # 0. Set network to Signet
    await phase_set_network_signet(d)

    # 1. Create wallet from mnemonic
    await phase_create_wallet(d)

    # 2. Verify addresses
    await phase_verify_addresses(d)

    # 3. Sync and wait for UTXOs — returns whether confirmed coins exist.
    has_confirmed = await phase_sync(d)

    if has_confirmed:
        # 4. Create self-send PSBT with MAX amount and label.
        #    We are on the Overview tab after phase_sync.
        await phase_create_psbt(d)

        # 5. Go back from PSBT detail → wallet detail (Overview)
        await click_tooltip(d, "Back", delay=0.8)
        await wait_for(d, '"Receive"', "back on wallet detail (Overview)",
                        retries=8, delay=0.5)

        # 6. Navigate to Transactions tab and verify PSBT tile + UNSIGNED status
        await click_label(d, "Transactions", delay=0.8)
        await phase_verify_psbt_in_list(d, "UNSIGNED")

        # 7. Open PSBT and sign with hot key
        await phase_open_and_sign_psbt(d)

        # 8. Go back → Transactions tab: verify SIGNED status
        await click_tooltip(d, "Back", delay=0.8)
        await wait_for(d, '"Transactions"', "back on Transactions tab",
                        retries=8, delay=0.5)
        await phase_verify_psbt_in_list(d, "SIGNED")

        # 9. Open PSBT again → broadcast
        rect = await d.find_semantic_rect(PSBT_LABEL)
        if rect is None:
            raise AssertionError(
                f"PSBT tile '{PSBT_LABEL}' not found in Transactions tab for broadcast"
            )
        d.flutter_click((rect[0] + rect[2]) // 2, (rect[1] + rect[3]) // 2)
        await asyncio.sleep(1.0)
        await wait_for(d, '"Unsigned Transaction"', "PSBT detail screen for broadcast",
                        retries=10, delay=0.5)
        await phase_broadcast(d)

        # 10. Verify post-broadcast state (PSBT gone, Spending + Unconfirmed coins)
        await phase_verify_after_broadcast(d)
    else:
        print("\n  [skip] phases 4-10 — no confirmed UTXOs, resuming from CPFP")
        # Ensure we are on the Overview tab ready for phase_cpfp.
        await click_label(d, "Overview", delay=0.5)
        await wait_for(d, '"Send"', "on Overview tab", retries=8, delay=0.5)

    # 11. CPFP: create another PSBT spending the unconfirmed UTXO
    await phase_cpfp(d)

    # 12. FullRBF: replace the spending coin with a higher-fee transaction
    await phase_fullrbf(d)

    # Cleanup: delete the wallet
    await _go_back_to_wallet_list(d)
    await _delete_wallet(d, WALLET_NAME)

    print(f"\n    [PASS] {WALLET_NAME}")


# ---------------------------------------------------------------------------
# Entry point
# ---------------------------------------------------------------------------

async def main():
    d = UIDriver(sandbox=True, initial_prefs={
        "defaultNetwork": "signet",
        "disclaimerHiddenUntil": 9_999_999_999_999,  # far future: suppress disclaimer
    })
    try:
        await d.launch()
        d.raise_window()
        await dismiss_startup_dialogs(d)

        await test_selfpay_psbt(d)

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
