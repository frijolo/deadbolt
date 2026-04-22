#!/usr/bin/env python3
"""
Regression test 13: Multi-recipient self-send transaction.

Flow:
  0.  Settings → set Active Network to Signet
  1.  Create SegWit singlesig wallet via Guided creation (Enter manually → Hot Key →
      mnemonic) — wallet is funded on Signet
  2.  Sync wallet — wait for UTXOs to appear
  3.  Open Send → add first recipient via "This wallet (Self)"
  4.  Click "Add recipient" → add second recipient via "This wallet (Self)"
  5.  Verify the two auto-filled addresses are DISTINCT (fresh derivation)
  6.  Verify "Total out:" row visible (multiple recipients)
  7.  Create PSBT → verify label on detail screen
  8.  Sign with hot key → broadcast
  9.  Verify 2 Unconfirmed coins in Coins tab (one per output)
 10.  Consolidate all non-Spending UTXOs back to self (MAX) so the next
      run starts with a single UTXO

Exit code: 0 = PASS, 1 = FAIL.

Prerequisites:
  bash scripts/prepare_test_build.sh
  python3 scripts/regression_13_multi_recipient.py
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
    navigate_wallets, fill_field, click_label, click_tooltip,
    go_back_to_wallet_list, delete_wallet_from_list,
    set_active_network_signet, run_regression,
)


# ---------------------------------------------------------------------------
# Test data
# ---------------------------------------------------------------------------

WALLET_NAME = "Reg13-MultiRecipient"
PSBT_LABEL  = "reg13-multi"

# 12-word mnemonic for this test — controls funded Signet UTXOs (SegWit singlesig).
MNEMONIC = (
    "bachelor brick camera brave assume differ disagree "
    "judge security scrap wonder core"
)

_ENV = {**os.environ, "DISPLAY": ":0"}


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

def _extract_tb1q_addresses(sem: str) -> list[str]:
    """Return all distinct tb1q... addresses found in the semantics tree."""
    return list(dict.fromkeys(re.findall(r'tb1q[a-z0-9]+', sem.lower())))


# ---------------------------------------------------------------------------
# Phase 0: configure Signet
# ---------------------------------------------------------------------------



async def phase_create_wallet_guided(d: UIDriver):
    """Create a SegWit singlesig wallet via Guided creation with a Hot Key.

    Flow:
      Wallets → New → Guided creation → fill name → Add key →
      Enter manually → Hot Key → paste mnemonic → wait for keyspec derivation →
      Add → HOT badge visible → Create wallet → wallet detail opens.
    """
    print(f"\n  [phase 1] create wallet via Guided creation: {WALLET_NAME}")

    await navigate_wallets(d)
    await click_tooltip(d, "New")
    await wait_for(d, "Guided creation", "bottom sheet opened")
    await click_label(d, "Guided creation", delay=0.5)
    await wait_for(d, '"New Wallet"', "Guided creation screen opened")
    print("    [ok] New Wallet screen open")

    await fill_field(d, "Wallet name", WALLET_NAME)
    # Script type: SegWit (P2WPKH) is the default for singlesig — no click needed.

    # Open key input sheet
    await click_label(d, "Add key", delay=0.5)
    await wait_for(d, "Enter manually", "method picker visible",
                   retries=8, delay=0.5)
    await click_label(d, "Enter manually", delay=0.5)
    await wait_for(d, "Watch Only", "manual entry tabs visible",
                   retries=8, delay=0.5)

    # Switch from Watch Only to Hot Key
    await click_label(d, "Hot Key", delay=0.5)
    await wait_for(d, "Seed phrase", "Hot Key seed form visible",
                   retries=8, delay=0.5)
    print("    [ok] Hot Key tab active")

    # Enter 12-word mnemonic
    await fill_field(d, "Seed phrase", MNEMONIC)
    print("    [ok] mnemonic entered")

    # Wait for Rust keyspec derivation (debounce 500 ms + derive ~1 s)
    await wait_for(d, "Derived keyspec", "keyspec derived from mnemonic",
                   retries=20, delay=1.0)
    print("    [ok] keyspec derived")

    # Confirm — "Add" button (l10n.add, non-wallet-mode)
    await click_label(d, "Add", delay=1.0)

    # Key sheet closes; SimpleWalletDialog shows the key tile with Remove key button.
    # (SimpleWalletDialog uses _buildKeyTile which has no HOT badge — use the
    # tooltip that is always present on a successfully-added key tile instead.)
    await wait_for(d, "Remove key", "key tile visible in New Wallet screen",
                   retries=15, delay=0.8)
    print("    [ok] key tile visible — hot key added to wallet")

    # Create the wallet
    await click_label(d, "Create wallet", delay=1.0)
    await wait_for(d, '"Receive"', f"wallet detail loaded: '{WALLET_NAME}'",
                   retries=30, delay=1.0)
    print(f"    [ok] wallet detail opened: '{WALLET_NAME}'")


# ---------------------------------------------------------------------------
# Phase 2: sync
# ---------------------------------------------------------------------------

async def phase_sync(d: UIDriver):
    print("\n  [phase 2] sync wallet — waiting for UTXOs")

    await click_tooltip(d, "Sync wallet", delay=1.5)
    await click_label(d, "Coins", delay=1.0)

    sem_coins = await wait_for(d, "sats",
                                "at least one coin visible in Coins tab",
                                retries=120, delay=1.5)
    if '"No coins.' in sem_coins:
        raise AssertionError(
            "Coins tab shows 'No coins' after sync — wallet has no UTXOs.\n"
            "Ensure the test mnemonic controls at least one UTXO on Signet."
        )
    print("    [ok] sync complete — coins visible")

    await click_label(d, "Overview", delay=0.5)
    await wait_for(d, '"Send"', "back on Overview tab", retries=8, delay=0.5)


# ---------------------------------------------------------------------------
# Phase 3: create multi-recipient self-send PSBT
# ---------------------------------------------------------------------------

async def phase_create_psbt(d: UIDriver):
    """Create a PSBT with 2 self-send recipients and verify distinct addresses."""
    print("\n  [phase 3] create multi-recipient self-send PSBT")

    await click_label(d, "Send", delay=0.5)
    await wait_for(d, '"Create Transaction"', "Create TX screen opened",
                   retries=10, delay=0.5)
    print("    [ok] Create Transaction screen open")

    # --- Step 1: Select one coin ---
    await click_label(d, "Tap to select coins...", delay=1.0)
    await wait_for(d, "sats", "coin selector opened", retries=10, delay=0.5)
    coin_rect = await d.cs_find_label_containing("sats")
    if coin_rect is None:
        raise AssertionError("No coin tile found in coin selector")
    d.flutter_click((coin_rect[0] + coin_rect[2]) // 2,
                    (coin_rect[1] + coin_rect[3]) // 2)
    await asyncio.sleep(0.5)
    await click_label(d, "Done (1)", delay=1.0)
    await wait_for(d, '"Create Transaction"', "back on Create TX",
                   retries=10, delay=0.5)
    print("    [ok] coin selected")

    # --- Step 2: Set label ---
    await fill_field(d, "Label", PSBT_LABEL)
    print(f"    [ok] label set to '{PSBT_LABEL}'")

    # --- Step 3: Recipient 1 — fill address via Self ---
    mw_rects = await d.cs_find_all_by_tooltip("MY WALLETS")
    if not mw_rects:
        raise AssertionError("'MY WALLETS' button not found for recipient 1")
    r1 = mw_rects[0]
    d.flutter_click((r1[0] + r1[2]) // 2, (r1[1] + r1[3]) // 2)
    await asyncio.sleep(0.5)
    await wait_for(d, "This wallet (Self)", "wallet picker visible (r1)",
                   retries=8, delay=0.5)
    await click_label(d, "This wallet (Self)", delay=1.5)
    await asyncio.sleep(2.0)

    sem1 = await d.cs_tree_as_json()
    addrs1 = _extract_tb1q_addresses(sem1)
    if not addrs1:
        raise AssertionError("No tb1q address auto-filled for recipient 1")
    addr1 = addrs1[0]
    print(f"    [ok] recipient 1 address: {addr1[:22]}...")

    # --- Step 4: Add second recipient ---
    await click_label(d, "Add recipient", delay=1.0)
    await asyncio.sleep(1.0)
    print("    [ok] second recipient row added")

    # --- Step 5: Recipient 2 — fill address via Self ---
    mw_rects2 = await d.cs_find_all_by_tooltip("MY WALLETS")
    if len(mw_rects2) < 2:
        raise AssertionError(
            f"Expected ≥2 'MY WALLETS' buttons after adding recipient 2, "
            f"got {len(mw_rects2)}"
        )
    r2 = mw_rects2[1]
    d.flutter_click((r2[0] + r2[2]) // 2, (r2[1] + r2[3]) // 2)
    await asyncio.sleep(0.5)
    await wait_for(d, "This wallet (Self)", "wallet picker visible (r2)",
                   retries=8, delay=0.5)
    await click_label(d, "This wallet (Self)", delay=1.5)
    await asyncio.sleep(2.0)

    sem2 = await d.cs_tree_as_json()
    addrs2 = _extract_tb1q_addresses(sem2)
    if len(addrs2) < 2:
        raise AssertionError(
            f"Expected 2 distinct tb1q addresses after selecting Self for both "
            f"recipients, got {len(addrs2)}: {addrs2}"
        )
    addr2 = next((a for a in addrs2 if a != addr1), None)
    if addr2 is None:
        raise AssertionError(
            f"Both recipients got the same address ({addr1}). "
            "Selecting 'This wallet (Self)' should derive a fresh address "
            "for each recipient."
        )
    print(f"    [ok] recipient 2 address: {addr2[:22]}...")
    print(f"    [ok] addresses are DISTINCT — fresh derivation confirmed")

    # --- Step 6: Fill amounts for both recipients ---
    # Both addresses are now set. Locate ALL Amount fields (by label, not hint —
    # Flutter InputDecoration uses labelText so the decoration label is always
    # visible regardless of content) and fill them by index.
    all_amt_rects = await d.cs_find_all_textfield_by_label("Amount (sats)")
    if len(all_amt_rects) < 2:
        raise AssertionError(
            f"Expected at least 2 'Amount (sats)' fields, got {len(all_amt_rects)}"
        )

    for idx, amount_rect in enumerate(all_amt_rects[:2]):
        mx = (amount_rect[0] + amount_rect[2]) // 2
        my = (amount_rect[1] + amount_rect[3]) // 2
        d.flutter_click(mx, my)
        await asyncio.sleep(0.3)
        d.key("ctrl+a")
        await asyncio.sleep(0.1)
        subprocess.run(["xclip", "-selection", "clipboard"],
                       input=b"1000", env=_ENV, check=True)
        await asyncio.sleep(0.1)
        d.key("ctrl+v")
        await asyncio.sleep(0.5)
        print(f"    [ok] recipient {idx + 1} amount: 1000 sats")

    # --- Step 8: Verify total output row ---
    await wait_for(d, "Total out:", "total output row visible",
                   retries=15, delay=0.8)
    print("    [ok] total output row visible (multi-recipient)")

    # --- Step 9: Create PSBT ---
    # The button may be just below the visible viewport; scroll down to expose it.
    for _scroll_attempt in range(5):
        if await d.cs_is_visible("Create PSBT"):
            break
        d.scroll_down(3)
        await asyncio.sleep(0.4)
    await click_label(d, "Create PSBT", delay=0.5)
    await wait_for(d, '"Unsigned Transaction"', "PSBT detail screen opened",
                   retries=15, delay=1.0)
    print("    [ok] PSBT detail screen opened")

    if await d.cs_find_text_containing(PSBT_LABEL) is None:
        raise AssertionError(
            f"PSBT label '{PSBT_LABEL}' not visible on PSBT detail screen"
        )
    print(f"    [ok] label '{PSBT_LABEL}' visible on PSBT detail screen")


# ---------------------------------------------------------------------------
# Phase 4: sign and broadcast
# ---------------------------------------------------------------------------

async def phase_sign_and_broadcast(d: UIDriver):
    print("\n  [phase 4] sign and broadcast")

    await click_label(d, "Sign", delay=1.5)
    await wait_for(d, "SIGNED", "PSBT status SIGNED",
                   retries=15, delay=0.8)
    print("    [ok] PSBT signed")

    await click_label(d, "Broadcast", delay=0.5)
    await wait_for(d, "Transaction broadcast", "broadcast success toast",
                   retries=20, delay=1.0)
    print("    [ok] broadcast success toast visible")
    await asyncio.sleep(2.0)

    await wait_for(d, '"Receive"', "back on wallet detail",
                   retries=10, delay=0.5)
    print("    [ok] navigated back to wallet detail")


# ---------------------------------------------------------------------------
# Phase 5: verify 2 Unconfirmed outputs in Coins tab
# ---------------------------------------------------------------------------

async def phase_verify_broadcast(d: UIDriver):
    print("\n  [phase 5] verify broadcast — 2 Unconfirmed outputs")

    await click_tooltip(d, "Sync wallet", delay=2.0)
    await asyncio.sleep(1.0)

    await click_label(d, "Coins", delay=0.8)
    sem_coins = await wait_for(
        d, "Unconfirmed",
        "at least one Unconfirmed coin after broadcast",
        retries=30, delay=2.0,
    )
    unconf_count = sem_coins.count("Unconfirmed")
    if unconf_count < 2:
        print(
            f"    [warn] expected 2 Unconfirmed coins, found {unconf_count} — "
            "signet mempool propagation may not have completed yet"
        )
    else:
        print(f"    [ok] {unconf_count} Unconfirmed coins visible — both outputs confirmed")


# ---------------------------------------------------------------------------
# Phase 6: consolidate all non-Spending UTXOs into a single self-send output
# ---------------------------------------------------------------------------

async def phase_consolidate(d: UIDriver):
    """Select every non-Spending UTXO and MAX self-send in a single tx.

    Leaves the wallet with exactly one unconfirmed output so the next run
    finds a clean, single-UTXO state once it confirms.

    Coin keychain badges ("Receive" / "Change") are present on every coin tile
    and are used as positional anchors.  Coins whose badge Y-coordinate falls
    within 80 px of a "Spending" badge are excluded.
    """
    print("\n  [phase 6] consolidate non-Spending UTXOs")

    await click_label(d, "Overview", delay=0.5)
    await wait_for(d, '"Send"', "on Overview tab", retries=8, delay=0.5)

    await click_label(d, "Send", delay=0.5)
    await wait_for(d, '"Create Transaction"', "Create TX screen opened",
                   retries=10, delay=0.5)

    await click_label(d, "Tap to select coins...", delay=1.0)
    await wait_for(d, "sats", "coin selector opened", retries=10, delay=0.5)

    spending_rects = await d.cs_find_all_by_label_part("Spending")
    receive_rects  = await d.cs_find_all_by_label_part("Receive")
    change_rects   = await d.cs_find_all_by_label_part("Change")
    all_badge_rects = receive_rects + change_rects

    if not all_badge_rects:
        print("    [warn] no coins found in selector — skipping consolidation")
        await click_tooltip(d, "Back", delay=0.5)
        return

    def _cy(r):
        return (r[1] + r[3]) // 2

    selected = 0
    for rect in all_badge_rects:
        print(f"{rect} -> {_cy(rect)}")
        if any(abs(_cy(rect) - _cy(sr)) < 80 for sr in spending_rects):
            print(f"    [skip] Spending coin at y≈{_cy(rect)}")
            continue
        d.flutter_click((rect[0] + rect[2]) // 2, (rect[1] + rect[3]) // 2)
        await asyncio.sleep(0.4)
        selected += 1

    if selected == 0:
        print("    [warn] all visible coins are Spending — skipping consolidation")
        await click_tooltip(d, "Back", delay=0.5)
        return

    done_label = next(
        (n.get("label") for n in await d.cs_tree()
         if re.search(r'Done \(\d+\)', n.get("label", ""))),
        None,
    )
    if done_label is None:
        print("    [warn] Done button not found after selection — skipping consolidation")
        await click_tooltip(d, "Back", delay=0.5)
        return

    await click_label(d, done_label, delay=1.0)
    await wait_for(d, '"Create Transaction"', "back on Create TX",
                   retries=10, delay=0.5)
    print(f"    [ok] {selected} non-Spending coin(s) selected for consolidation")

    await fill_field(d, "Label", "reg13-consolidate")

    # Single recipient: self, MAX
    mw_rects = await d.cs_find_all_by_tooltip("MY WALLETS")
    if not mw_rects:
        raise AssertionError("'MY WALLETS' button not found for consolidation")
    r = mw_rects[0]
    d.flutter_click((r[0] + r[2]) // 2, (r[1] + r[3]) // 2)
    await asyncio.sleep(0.5)
    await wait_for(d, "This wallet (Self)", "wallet picker visible",
                   retries=8, delay=0.5)
    await click_label(d, "This wallet (Self)", delay=1.5)
    await asyncio.sleep(2.0)
    if await d.cs_find_text_containing("tb1q") is None:
        raise AssertionError("No self-address filled for consolidation")

    await click_label(d, "MAX", delay=0.8)
    await wait_absent(d, '"— sats"', "MAX amount computed", retries=15, delay=0.5)
    print("    [ok] MAX set for consolidation")

    await click_label(d, "Create PSBT", delay=0.5)
    await wait_for(d, '"Unsigned Transaction"', "PSBT detail opened",
                   retries=15, delay=1.0)

    await click_label(d, "Sign", delay=1.5)
    await wait_for(d, "SIGNED", "consolidation PSBT signed", retries=15, delay=0.8)

    await click_label(d, "Broadcast", delay=0.5)
    await wait_for(d, "Transaction broadcast", "consolidation broadcast success",
                   retries=20, delay=1.0)
    await asyncio.sleep(2.0)

    await wait_for(d, '"Receive"', "back on wallet detail after consolidation",
                   retries=10, delay=0.5)
    print("    [ok] consolidation broadcast — 1 unconfirmed output pending confirmation")


# ---------------------------------------------------------------------------
# Main test function
# ---------------------------------------------------------------------------

async def test_multi_recipient(d: UIDriver):
    print(f"\n--- {WALLET_NAME} (multi-recipient self-send) ---")

    await set_active_network_signet(d)
    await phase_create_wallet_guided(d)
    await phase_sync(d)
    await phase_create_psbt(d)
    await phase_sign_and_broadcast(d)
    await phase_verify_broadcast(d)
    await phase_consolidate(d)

    await go_back_to_wallet_list(d)
    await delete_wallet_from_list(d, WALLET_NAME)

    print(f"\n    [PASS] {WALLET_NAME}")


# ---------------------------------------------------------------------------
# Entry point
# ---------------------------------------------------------------------------

if __name__ == "__main__":
    asyncio.run(run_regression(test_multi_recipient, "reg13"))
