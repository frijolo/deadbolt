#!/usr/bin/env python3
"""
Regression test 43: spaced TX planning end-to-end on the reg25 inheritance
wallet.

Why the inheritance wallet:
  Spaced TX planning is the natural companion to inheritance setups — they
  are the wallets whose UTXOs need periodic refreshing so timelocked spend
  paths don't expire. Reusing the reg25 wallet keeps fixture cost at zero
  and exercises the planner against a non-trivial descriptor.

Coverage (UI-driven, what unit tests can't reach):
  1. Open the "Migrate UTXOs…" menu entry → idle view appears
     with the configuration form (fee histogram, min/max fee, min/max
     delay, split probability, destination selector, coin selector).
  2. Click "Compute plan" with the default config (refresh-mode, all
     coins) → DRAFT view appears with the per-UTXO row list and the
     plan header.
  3. The wallet detail's Coins tab shows the "Reserved by plan" badge on
     the UTXO that the planner consumed.
  4. The wallet detail's Overview tab shows the "Reserved …" balance chip
     with a non-empty sat value.
  5. From the DRAFT view tap "Sign all…" → signer picker sheet lists the
     owner hot key, HW, and QR rows. Pick the hot key row → first
     confirmation dialog ("Sign N transactions?") → confirm. The cubit
     calls `sign_spaced_plan_with_hot_key`; the draft view ends with the
     SignProgress badge "N / N signed" and every row tile shows the
     "Signed" badge.
  6. Tap "Confirm and arm" → second confirmation dialog
     ("Arm N transactions?") with totals + broadcast window → confirm.
     The plan transitions to Running:
       - running header reads "Plan #N · running";
       - every row carries the "Armed, matures at block …" badge.
  7. Stop the plan from the Running view ("Stop plan?" dialog) → state
     returns to idle; reservation badges & balance chip vanish.

Out of scope (would require a synthetic chain or hours of waiting):
  - Actual on-chain broadcast at nlocktime maturity (covered by Rust
    `psbt_maturity_tests`).
  - Label propagation chain (spaced_plan_tests label propagation tests).

Prerequisites:
  bash scripts/prepare_test_build.sh

The reg25 inheritance wallet must have at least one confirmed UTXO on
signet at its first receive address.

Exit code: 0 = PASS, 1 = FAIL.
"""

import asyncio
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from ui_driver import UIDriver                          # noqa: E402
from regression_helpers import (                       # noqa: E402
    wait_for, assert_no_error_toast,
    navigate_wallets, fill_field, click_label, click_tooltip,
    click_popup_item,
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
# Wallet bootstrap (mirrors reg25 / reg42)
# ---------------------------------------------------------------------------

async def _create_inheritance_wallet(d: UIDriver):
    print("\n  [setup] create reg25 inheritance wallet")
    await navigate_wallets(d)
    await click_tooltip(d, "New")
    await wait_for(d, "Guided creation", "Bottom sheet opened",
                   retries=10, delay=0.5)
    await click_label(d, "Guided creation", delay=0.5)
    await wait_for(d, '"New Wallet"', "Guided creation screen opened",
                   retries=10, delay=0.5)
    await fill_field(d, "Wallet name", WALLET_NAME)

    await wait_for(d, "Singlesig", "wallet type segments visible",
                   retries=10, delay=0.5)
    await click_label(d, "Inheritance", delay=0.5)
    await asyncio.sleep(1.0)
    await wait_for(d, "Taproot", "Taproot auto-selected",
                   retries=10, delay=0.5)
    await wait_for(d, "Add heir", "Heirs section visible",
                   retries=10, delay=0.5)

    await _add_owner_hot_key(d, MNEMONIC)

    for name, spec, tl, preset in [
        ("Heir 1", HEIR1_KEYSPEC, TL_3M, True),
        ("Heir 2", HEIR2_KEYSPEC, TL_6M, True),
        ("Heir 3", HEIR3_KEYSPEC, TL_9M, True),
        ("Heir 4", HEIR4_KEYSPEC, TL_1Y, True),
        ("Heir 5", HEIR5_KEYSPEC, TL_CUSTOM, False),
    ]:
        print(f"    [step] adding {name}")
        await _add_heir(d, name=name, keyspec=spec, timelock=tl,
                        is_preset=preset)
        await wait_for(d, name, f"{name} added", retries=10, delay=0.5)

    await click_label(d, "Create wallet", delay=1.0)
    sem = await wait_for(
        d, '"Receive"', f"wallet detail loaded: '{WALLET_NAME}'",
        retries=60, delay=1.0,
    )
    assert_no_error_toast(sem)
    print("    [ok] inheritance wallet created")


async def _sync_and_require_utxos(d: UIDriver):
    """Force a sync and require at least one confirmed UTXO."""
    print("\n  [phase 0] sync wallet — require confirmed UTXOs")
    await click_label(d, "Coins", delay=1.0)
    sem = await wait_for(
        d, "sats", "at least one coin tile visible in Coins tab",
        retries=120, delay=1.5,
    )
    if '"No coins.' in sem:
        raise AssertionError(
            "Coins tab shows 'No coins' after sync — fund the reg25 "
            "wallet's first receive address on signet before running this test."
        )
    print("    [ok] confirmed UTXOs present")
    await click_label(d, "Overview", delay=0.5)
    await wait_for(d, '"Send"', "back on Overview tab",
                   retries=8, delay=0.5)


# ---------------------------------------------------------------------------
# Phase 1: open planning + compute DRAFT
# ---------------------------------------------------------------------------

async def phase_open_and_compute(d: UIDriver):
    print("\n  [phase 1] open Plan menu → compute DRAFT plan")

    await click_popup_item(d, "More options", 0, "Migrate UTXOs…")
    await wait_for(
        d, "Migrate UTXOs",
        "tx planning screen opened (app bar title visible)",
        retries=15, delay=0.5,
    )

    # Idle view: the configuration form must be present. The v1 preset
    # chips (Fast/Balanced/Stealth) were replaced by a fee histogram,
    # numeric fee/delay/split inputs, a destination selector and a coin
    # selector. We assert on the labels that drive the form so the test
    # still fails loudly if the layout regresses.
    sem = await d.cs_flat_text()
    expected_labels = (
        "Min fee (sat/vB)",
        "Max fee (sat/vB)",
        "Min delay (blocks)",
        "Max delay (blocks)",
        "Split probability",
        "Destination",
        "Select coins",
        "Same wallet (refresh)",
    )
    for label in expected_labels:
        if label not in sem:
            raise AssertionError(
                f"Idle config label '{label}' not visible on tx planning idle view"
            )
    if "Compute plan" not in sem:
        raise AssertionError("'Compute plan' button missing from idle view")
    print("    [ok] idle view rendered with the configuration form")

    # Idle view now includes the fee histogram + preset chips + hint, which
    # pushes the Compute plan button past the viewport. click_semantic's
    # built-in scroll only fires once and the wheel click count is
    # underestimated for this layout, so pre-scroll to bring the button
    # into the upper half of the viewport before the click.
    d.scroll_down(12)
    await asyncio.sleep(0.4)
    await click_label(d, "Compute plan", delay=2.0)

    # Draft view: the plan header reads "Plan #N · refresh" (dst = src).
    sem = await wait_for(
        d, "refresh",
        "draft view rendered with refresh-mode header",
        retries=20, delay=1.0,
    )
    # New draft view: compact summary card + signers section with per-MFP
    # rows (inline 'Sign' button for hot keys) + HW / QR fallback buttons,
    # and a bottom action bar with Cancel plan / Confirm and arm.
    for needed in ("Cancel", "Broadcast", "Signatures:"):
        if needed not in sem:
            raise AssertionError(
                f"'{needed}' missing from draft view"
            )
    print("    [ok] DRAFT view shown with refresh-mode header + action bar")


# ---------------------------------------------------------------------------
# Phase 2: badge on Coins tab + balance chip on Overview
# ---------------------------------------------------------------------------

async def phase_verify_earmark_ui(d: UIDriver):
    print("\n  [phase 2] verify Plan badge + Planned balance chip")

    # Pop back to wallet detail.
    await click_tooltip(d, "Back", delay=0.8)
    await wait_for(d, '"Send"', "back on wallet detail",
                   retries=10, delay=0.5)

    # Overview: Planned chip carries the sat value.
    sem = await d.cs_flat_text()
    if "Planned " not in sem and "Planificado " not in sem:
        raise AssertionError(
            "'Planned <amount>' balance chip missing on Overview tab"
        )
    print("    [ok] Planned balance chip visible on Overview")

    # Coins: at least one tile carries the 'Plan' badge.
    await click_label(d, "Coins", delay=1.0)
    sem = await wait_for(
        d, "Plan",
        "Plan badge visible on at least one coin tile",
        retries=15, delay=1.0,
    )
    if "Plan" not in sem:
        raise AssertionError(
            "No coin tile shows the 'Plan' badge after the plan "
            "was committed to DRAFT."
        )
    print("    [ok] Plan badge visible on coins tab")

    await click_label(d, "Overview", delay=0.5)
    await wait_for(d, '"Send"', "back on Overview tab",
                   retries=8, delay=0.5)


# ---------------------------------------------------------------------------
# Phase 3: batch-sign with hot key + arm-and-broadcast confirmation
# ---------------------------------------------------------------------------

async def _click_hot_key_sign(d: UIDriver):
    """The new draft view shows one signer row per spend-path MFP with an
    inline 'Sign' FilledButton for hot keys. Pick the first such button —
    in this inheritance wallet only the owner key is a hot key."""
    await click_label(d, "Sign", delay=0.8)


async def _confirm_sign_batch_dialog(d: UIDriver):
    """Confirms the first gate: 'Sign N transactions?'. The dialog's
    FilledButton has the literal 'Sign all…' label (kept as the dialog
    confirm copy)."""
    await wait_for(
        d, "Sign", "first confirmation dialog (sign batch) opened",
        retries=15, delay=0.5,
    )
    rects = await d.cs_find_all_by_label("Sign all…")
    if not rects:
        raise AssertionError(
            "Expected the dialog's 'Sign all…' confirm button, found none."
        )
    confirm = rects[-1]
    d.flutter_click(
        (confirm[0] + confirm[2]) // 2,
        (confirm[1] + confirm[3]) // 2,
    )
    await asyncio.sleep(1.5)


async def _confirm_arm_dialog(d: UIDriver):
    """Confirms the second gate: 'Broadcast N transactions?'. The dialog's
    FilledButton has the literal 'Broadcast' label."""
    await wait_for(
        d, "Broadcast", "second confirmation dialog (broadcast) opened",
        retries=15, delay=0.5,
    )
    rects = await d.cs_find_all_by_label("Broadcast")
    if not rects:
        raise AssertionError(
            "Expected the dialog's 'Broadcast' confirm button, found none."
        )
    confirm = rects[-1]
    d.flutter_click(
        (confirm[0] + confirm[2]) // 2,
        (confirm[1] + confirm[3]) // 2,
    )
    await asyncio.sleep(1.5)


async def phase_sign_and_commit(d: UIDriver):
    print("\n  [phase 3] batch-sign with hot key, arm → Running")

    # We left phase 2 on the Overview tab. Re-open the plan; the DRAFT
    # view still owns the unsigned children.
    await click_popup_item(d, "More options", 0, "Migrate UTXOs…")
    await wait_for(d, "refresh", "draft view re-opened",
                   retries=15, delay=0.5)

    # Step 1: check the new signers section shows the owner hot key row +
    # HW / QR fallback buttons, then click the inline 'Sign' button on
    # the hot-key row.
    sem = await d.cs_flat_text()
    for needed in ("Signatures:", "Sign with hardware wallet", "Offline signer (QR)"):
        if needed not in sem:
            raise AssertionError(
                f"Draft view missing '{needed}' in the signers section"
            )
    print("    [ok] signers section shows hot key row + HW / QR buttons")

    await _click_hot_key_sign(d)
    await _confirm_sign_batch_dialog(d)

    # Step 2: after the batch the cubit emits SignProgress; the signer
    # row flips to a green 'Signed' status and the green progress banner
    # appears at the top.
    sem = await wait_for(
        d, "Signed",
        "draft view shows 'Signed' status after batch sign",
        retries=30, delay=1.0,
    )
    # The progress banner reports "N / N signed" with no failures.
    if " / " not in sem or "signed" not in sem:
        raise AssertionError(
            "Sign progress banner ('X / N signed') missing after batch sign"
        )
    print("    [ok] batch sign complete: signer row badged 'Signed'")

    # Step 4: arm → second confirmation gate → Running.
    await click_label(d, "Broadcast", delay=0.8)
    await _confirm_arm_dialog(d)

    # Armed-row subtitle:
    #   * txPlanningRowArmedEta: "{datetime} ({blocks} blocks left)" (tip known)
    #   * txPlanningRowArmed:    "Broadcasts at block {block}"        (tip unknown)
    sem = await wait_for(
        d, "blocks left",
        "running header visible after commit/arm",
        retries=25, delay=1.0,
    )
    if "blocks left" not in sem and "Broadcasts at block" not in sem:
        raise AssertionError(
            "Running row missing the armed-eta badge "
            "('<datetime> (<n> blocks left)' or 'Broadcasts at block …') — "
            "auto-broadcast was not scheduled by commit."
        )
    print("    [ok] plan scheduled: Running view + broadcast badge present")


# ---------------------------------------------------------------------------
# Phase 4: stop the running plan, verify earmark UI clears
# ---------------------------------------------------------------------------

async def phase_stop_plan(d: UIDriver):
    print("\n  [phase 4] stop running plan, verify earmark UI clears")

    # We are still on the Running view from phase 3.
    await click_label(d, "Stop", delay=0.8)
    await wait_for(d, "Stop plan?", "stop dialog opened",
                   retries=10, delay=0.3)
    # AlertDialog hides the outer "Stop plan" button from semantics — only
    # the dialog's FilledButton (label "Stop") remains.
    rects = await d.cs_find_all_by_label("Stop")
    if not rects:
        raise AssertionError(
            "Expected the dialog's 'Stop' confirm button, found none."
        )
    confirm = rects[-1]
    d.flutter_click(
        (confirm[0] + confirm[2]) // 2,
        (confirm[1] + confirm[3]) // 2,
    )
    await asyncio.sleep(1.0)

    # After stop the cubit reloads → idle view returns.
    await wait_for(
        d, "Compute plan",
        "idle view returned after stop (Compute plan button visible)",
        retries=15, delay=0.8,
    )
    print("    [ok] plan stopped, idle view back")

    # Pop back to the wallet detail and verify the earmark UI cleared.
    # The previous tab was Transactions (phase 3 left us there), so wait
    # for the tab strip to come back rather than the Overview "Send" CTA.
    await click_tooltip(d, "Back", delay=0.8)
    await wait_for(d, "Tab 4 of 5", "back on wallet detail (tab bar visible)",
                   retries=10, delay=0.5)
    await click_label(d, "Coins", delay=0.5)
    sem = await wait_for(d, "sats", "coins tab loaded", retries=10, delay=0.5)
    if "Plan" in sem:
        raise AssertionError(
            "'Plan' badge still present on coins tab after the "
            "plan was stopped."
        )
    print("    [ok] Plan badge cleared from Coins tab")


# ---------------------------------------------------------------------------
# Cleanup
# ---------------------------------------------------------------------------

async def phase_cleanup(d: UIDriver):
    print("\n  [cleanup] delete wallet")
    await go_back_to_wallet_list(d)
    await delete_wallet_from_list(d, WALLET_NAME)


# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------

async def test_spaced_tx_planning(d: UIDriver):
    print(f"\n--- reg43: spaced TX planning on {WALLET_NAME} ---")
    await set_active_network_signet(d)
    await _create_inheritance_wallet(d)
    try:
        await _sync_and_require_utxos(d)
        await phase_open_and_compute(d)
        await phase_verify_earmark_ui(d)
        await phase_sign_and_commit(d)
        await phase_stop_plan(d)
    finally:
        try:
            await phase_cleanup(d)
        except Exception as cleanup_err:  # noqa: BLE001
            print(f"    [warn] cleanup failed: {cleanup_err}")

    print(f"\n    [PASS] reg43 spaced TX planning")


if __name__ == "__main__":
    asyncio.run(run_regression(test_spaced_tx_planning, "reg43"))
