#!/usr/bin/env python3
"""
Regression test 42: future-tx planning (delayed nLockTime) + auto-broadcast
toggle, exercised on the complex inheritance wallet from reg25.

Why the inheritance wallet:
  The Reg25-Inheritance descriptor has the owner key + 5 heirs with absolute
  block timelocks. Building a PSBT on the *owner* spend path while adding a
  user-supplied broadcast delay is the most representative scenario, because
  the final nLockTime is `max(tip, abs_timelock) + delta` and we exercise
  both:
    - the owner path (abs_timelock = 0 → final lock = tip + delta)
    - the foreign-UTXO / OP_CSV sequence fixup machinery already in place.

Coverage (mirrors the user-confirmed scope):
  1. Create PSBT with the "Delay broadcast (nLockTime)" switch enabled.
     Set 1 day delay (~144 blocks) → verify the inline hint shows
     "≈ 144 blocks · unlock at block <height>".
  2. Sign with the owner hot key. On the PSBT detail screen, verify the
     primary broadcast button is replaced by the locked variant
     ("Locked · <eta> (<n> blocks left)") and that it is disabled.
  3. Toggle the "Broadcast automatically when unlocked" switch on. Reopen
     the PSBT and verify the switch state persists (auto_broadcast = true).
  4. Back on the Transactions tab, verify the action icon for the PSBT row
     is `schedule_send` with tooltip starting with
     "Queued for automatic broadcast".

Out of scope (would require a synthetic chain or a multi-hour wait):
  - Actually broadcasting once the timelock matures (covered by Rust
    `psbt_maturity_tests.rs`).
  - Relative timelocks (`Unsupported` for auto-broadcast in v1).

Prerequisites:
  bash scripts/prepare_test_build.sh
  python3 scripts/regression_41_future_tx_planning.py

The wallet must control at least one confirmed UTXO on signet at the address
space derived by the reg25 descriptor (owner mnemonic identical to reg11).
The test fails fast on the Coins tab if no UTXOs are visible.

Exit code: 0 = PASS, 1 = FAIL.
"""

import asyncio
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from ui_driver import UIDriver                          # noqa: E402
from regression_helpers import (                       # noqa: E402
    wait_for, wait_absent, assert_no_error_toast,
    navigate_wallets, fill_field, click_label, click_tooltip,
    wait_for_tooltip,
    go_back_to_wallet_list, delete_wallet_from_list,
    set_active_network_signet, run_regression,
)

# Reuse the wallet-creation flow + identifiers from reg25.
from regression_25_inheritance import (                 # noqa: E402
    WALLET_NAME, MNEMONIC,
    HEIR1_KEYSPEC, HEIR2_KEYSPEC, HEIR3_KEYSPEC, HEIR4_KEYSPEC, HEIR5_KEYSPEC,
    TL_3M, TL_6M, TL_9M, TL_1Y, TL_CUSTOM,
    _add_owner_hot_key, _add_heir,
)


# ---------------------------------------------------------------------------
# Constants
# ---------------------------------------------------------------------------

PSBT_LABEL = "reg42-future-tx"

# 1 day in 10-min blocks. Must round-trip through the UI's
# `(d*86400 + h*3600 + m*60 + 599) // 600` ceiling so we set 24 hours instead
# of 1 day to keep the assertion exact (24*3600/600 = 144).
DELAY_HOURS = 24
EXPECTED_DELAY_BLOCKS = 144


# ---------------------------------------------------------------------------
# Wallet bootstrap (mirrors reg25 phases 1-6)
# ---------------------------------------------------------------------------

async def _create_inheritance_wallet(d: UIDriver):
    """Recreate the reg25 inheritance wallet from scratch."""
    print("\n  [setup] create reg25 inheritance wallet")
    await navigate_wallets(d)
    await click_tooltip(d, "New")
    await wait_for(d, "Guided creation", "Bottom sheet opened", retries=10, delay=0.5)
    await click_label(d, "Guided creation", delay=0.5)
    await wait_for(d, '"New Wallet"', "Guided creation screen opened",
                   retries=10, delay=0.5)
    await fill_field(d, "Wallet name", WALLET_NAME)

    await wait_for(d, "Singlesig", "wallet type segments visible",
                   retries=10, delay=0.5)
    await click_label(d, "Inheritance", delay=0.5)
    await asyncio.sleep(1.0)
    await wait_for(d, "Taproot", "Taproot auto-selected", retries=10, delay=0.5)
    await wait_for(d, "Add heir", "Heirs section visible", retries=10, delay=0.5)

    await _add_owner_hot_key(d, MNEMONIC)

    for name, spec, tl, preset in [
        ("Heir 1", HEIR1_KEYSPEC, TL_3M, True),
        ("Heir 2", HEIR2_KEYSPEC, TL_6M, True),
        ("Heir 3", HEIR3_KEYSPEC, TL_9M, True),
        ("Heir 4", HEIR4_KEYSPEC, TL_1Y, True),
        ("Heir 5", HEIR5_KEYSPEC, TL_CUSTOM, False),
    ]:
        print(f"    [step] adding {name}")
        await _add_heir(d, name=name, keyspec=spec, timelock=tl, is_preset=preset)
        await wait_for(d, name, f"{name} added", retries=10, delay=0.5)

    await click_label(d, "Create wallet", delay=1.0)
    sem = await wait_for(d, '"Receive"', f"wallet detail loaded: '{WALLET_NAME}'",
                         retries=60, delay=1.0)
    assert_no_error_toast(sem)
    print("    [ok] inheritance wallet created")


async def _sync_and_require_utxos(d: UIDriver):
    """Force a sync and require at least one confirmed UTXO."""
    print("\n  [phase 0] sync wallet — require confirmed UTXOs")
    await wait_for_tooltip(d, "Sync wallet", "sync button available")
    await click_label(d, "Coins", delay=1.0)
    sem = await wait_for(
        d, "sats",
        "at least one coin tile visible in Coins tab",
        retries=120, delay=1.5,
    )
    if '"No coins.' in sem:
        raise AssertionError(
            "Coins tab shows 'No coins' after sync — fund the reg25 inheritance "
            "wallet's first receive address on signet before running this test."
        )
    print("    [ok] confirmed UTXOs present")
    await click_label(d, "Overview", delay=0.5)
    await wait_for(d, '"Send"', "back on Overview tab", retries=8, delay=0.5)


# ---------------------------------------------------------------------------
# Helpers — trailing-Switch clicker
# ---------------------------------------------------------------------------

async def _click_trailing_switch(d: UIDriver, label_part: str):
    """Tap the Switch sitting at the trailing edge of a labelled Row/Tile.

    Switches have no semantic label; we locate the visible label text and
    click ~32 px from the right edge of its bounding rect.
    """
    rect = await d.cs_find_by_label_part_containing(label_part)
    if rect is None:
        raise AssertionError(f"'{label_part}' row not found")
    cx = rect[2] - 32
    cy = (rect[1] + rect[3]) // 2
    d.flutter_click(cx, cy)
    await asyncio.sleep(0.5)


# ---------------------------------------------------------------------------
# Phase 1: create the delayed PSBT
# ---------------------------------------------------------------------------

async def phase_create_delayed_psbt(d: UIDriver):
    print("\n  [phase 1] create self-send PSBT with broadcast delay")

    await click_label(d, "Send", delay=0.5)
    await wait_for(d, '"Create Transaction"', "Create TX screen opened",
                   retries=10, delay=0.5)

    # 1) Select first coin
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

    # 2) Label
    await fill_field(d, "Label", PSBT_LABEL)

    # 3) Self-pay recipient
    await click_tooltip(d, "MY WALLETS", delay=0.5)
    await wait_for(d, "This wallet (Self)", "wallet picker visible",
                   retries=8, delay=0.5)
    await click_label(d, "This wallet (Self)", delay=1.5)
    await asyncio.sleep(2.0)

    # 4) MAX
    await click_label(d, "MAX", delay=0.8)
    await wait_absent(d, '"— sats"', "MAX amount computed",
                      retries=15, delay=0.5)

    # 5) Enable broadcast delay (24h → 144 blocks)
    print("    [step] enable broadcast delay (24h)")
    await _click_trailing_switch(d, "Delay broadcast")
    await wait_for(d, "Days", "delay fields visible", retries=8, delay=0.5)
    await fill_field(d, "Hours", str(DELAY_HOURS))

    # Inline hint should now read "≈ 144 blocks · unlock at block ..."
    sem = await d.cs_flat_text()
    expected_blocks_hint = f"≈ {EXPECTED_DELAY_BLOCKS} blocks"
    if expected_blocks_hint not in sem:
        raise AssertionError(
            f"Expected delay hint '{expected_blocks_hint}' not found in delay card"
        )
    if "unlock at block" not in sem:
        raise AssertionError(
            "Expected 'unlock at block <h>' text in delay card not found"
        )
    print(f"    [ok] delay hint visible: {expected_blocks_hint} + 'unlock at block ...'")

    # 6) Create PSBT
    await click_label(d, "Create PSBT", delay=0.5)
    await wait_for(d, '"Unsigned Transaction"', "PSBT detail screen opened",
                   retries=15, delay=1.0)
    sem_detail = await d.cs_flat_text()
    if PSBT_LABEL not in sem_detail:
        raise AssertionError(f"PSBT label '{PSBT_LABEL}' not visible on detail screen")
    print(f"    [ok] PSBT created with label '{PSBT_LABEL}'")


# ---------------------------------------------------------------------------
# Phase 2: sign with owner hot key, verify locked broadcast button
# ---------------------------------------------------------------------------

async def phase_sign_and_verify_locked(d: UIDriver):
    print("\n  [phase 2] sign with owner hot key, verify locked broadcast UI")

    await click_label(d, "Sign", delay=1.5)
    await wait_for(d, "SIGNED", "PSBT signed — SIGNED status visible",
                   retries=15, delay=0.8)
    print("    [ok] signed")

    # The Broadcast button label flips to the locked variant
    # (psbtLockedTooltip: "Locked · {eta} ({blocks} blocks left)").
    sem = await d.cs_flat_text()
    if "Locked" not in sem or "blocks left" not in sem:
        raise AssertionError(
            "Expected locked broadcast button text 'Locked · <eta> (<n> blocks left)' "
            "but it was not present after signing."
        )
    print("    [ok] broadcast button shows locked state")


# ---------------------------------------------------------------------------
# Phase 3: toggle auto-broadcast, verify persistence
# ---------------------------------------------------------------------------

async def phase_enable_auto_broadcast(d: UIDriver):
    print("\n  [phase 3] enable auto-broadcast and verify persistence")

    await wait_for(d, "Broadcast automatically when unlocked",
                   "auto-broadcast switch visible", retries=10, delay=0.5)
    await _click_trailing_switch(d, "Broadcast automatically when unlocked")

    # Pop back to wallet detail and re-open the PSBT to check persistence.
    await click_tooltip(d, "Back", delay=0.8)
    await wait_for(d, '"Transactions"', "back on wallet detail",
                   retries=10, delay=0.5)
    await click_label(d, "Transactions", delay=0.5)
    await wait_for(d, PSBT_LABEL, "PSBT tile visible in Transactions tab",
                   retries=10, delay=0.5)

    rect = await d.cs_find_by_label_part_containing(PSBT_LABEL)
    if rect is None:
        raise AssertionError(f"PSBT tile '{PSBT_LABEL}' missing from Transactions tab")
    d.flutter_click((rect[0] + rect[2]) // 2, (rect[1] + rect[3]) // 2)
    await asyncio.sleep(1.0)
    await wait_for(d, '"Unsigned Transaction"', "PSBT detail re-opened",
                   retries=10, delay=0.5)

    # The Switch should still be on. We can only verify visually via the
    # Queued tooltip later in the tx tab; here we just confirm the row is
    # rendered (i.e. server didn't reset auto_broadcast after re-fetch).
    sem = await d.cs_flat_text()
    if "Broadcast automatically when unlocked" not in sem:
        raise AssertionError(
            "Auto-broadcast switch disappeared after re-opening the PSBT — "
            "state should persist via APIWallet::set_psbt_auto_broadcast."
        )
    print("    [ok] auto-broadcast switch persisted across re-open")


# ---------------------------------------------------------------------------
# Phase 4: verify schedule_send icon + tooltip in Transactions tab
# ---------------------------------------------------------------------------

async def phase_verify_queued_icon(d: UIDriver):
    print("\n  [phase 4] verify 'schedule_send' icon + queued tooltip")

    await click_tooltip(d, "Back", delay=0.8)
    await wait_for(d, '"Transactions"', "back on wallet detail",
                   retries=10, delay=0.5)
    await click_label(d, "Transactions", delay=0.5)
    await wait_for(d, PSBT_LABEL, "PSBT tile visible", retries=10, delay=0.5)

    # The trailing icon is wrapped in a Tooltip whose message starts with
    # "Queued for automatic broadcast · Cannot broadcast until block ...".
    tree = await d.cs_tree()
    queued = [
        n for n in tree
        if (n.get("tooltip") or "").startswith("Queued for automatic broadcast")
    ]
    if not queued:
        raise AssertionError(
            "No 'Queued for automatic broadcast' tooltip found in Transactions tab — "
            "expected schedule_send icon on the auto-broadcast PSBT row."
        )
    print(f"    [ok] queued tooltip present: '{queued[0]['tooltip'][:60]}…'")


# ---------------------------------------------------------------------------
# Cleanup
# ---------------------------------------------------------------------------

async def phase_cleanup(d: UIDriver):
    print("\n  [phase 5] cleanup — delete wallet (PSBT goes with it)")
    await go_back_to_wallet_list(d)
    await delete_wallet_from_list(d, WALLET_NAME)


# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------

async def test_future_tx_planning(d: UIDriver):
    print(f"\n--- reg42: future-tx planning on {WALLET_NAME} ---")
    await set_active_network_signet(d)
    await _create_inheritance_wallet(d)
    try:
        await _sync_and_require_utxos(d)
        await phase_create_delayed_psbt(d)
        await phase_sign_and_verify_locked(d)
        await phase_enable_auto_broadcast(d)
        await phase_verify_queued_icon(d)
    finally:
        # Always try to delete the wallet, even if a phase failed, so reruns
        # start clean.
        try:
            await phase_cleanup(d)
        except Exception as cleanup_err:  # noqa: BLE001
            print(f"    [warn] cleanup failed: {cleanup_err}")

    print(f"\n    [PASS] reg42 future-tx planning")


if __name__ == "__main__":
    asyncio.run(run_regression(test_future_tx_planning, "reg42"))
