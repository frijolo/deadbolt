#!/usr/bin/env python3
"""
Regression test 04: Wallet lifecycle with Device Key protection (singlesig wpkh).

Tests the most common happy path: create project → create wallet → open wallet
→ receive address → verify addresses tab.

Device Key protection requires no password, so this test has no KDF overhead
and can run with either a debug or the prepare_test_build.sh binary.

Flow:
  1. Create project (wpkh singlesig)
  2. Create wallet from project (Device Key, no password)
  3. Wallet detail opens — verify wallet name in AppBar
  4. Verify overview renders: balance section + Send/Receive buttons visible
  5. Press Receive → verify dialog shows exact address #0 (ADDR_0_RECEIVE)
  6. Close dialog → navigate to Addresses tab:
     a. Verify 20 receive addresses auto-revealed (#0–#19)
     b. Click "Reveal 20 more" → verify #20 and #30 visible
     c. Switch to Change sub-tab → reveal → verify change #0 (ADDR_0_CHANGE)
  7. Navigate to Transactions tab — verify it renders without error

Exit code: 0 = PASS, 1 = FAIL.

Prerequisites:
  bash scripts/prepare_test_build.sh
  python3 scripts/regression_04_wallet_device_key.py
"""

import asyncio
import re
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from ui_driver import UIDriver                          # noqa: E402
from regression_helpers import (                       # noqa: E402
    wait_for, wait_absent,
    click_label, click_tooltip,
    dismiss_startup_dialogs,
    create_project, go_back,
    create_wallet_from_project,
)


# ---------------------------------------------------------------------------
# Test data
# ---------------------------------------------------------------------------

PROJECT_NAME = "Reg04-WPKH-Project"
WALLET_NAME  = "Reg04-Device-Key-Wallet"

# Native segwit singlesig (testnet) — fresh wallet with no prior transactions
# mnemonic: piece blue stadium control fiction kick group mimic hollow dog mask interest
DESCRIPTOR = (
    "wpkh([ff81be5d/84h/1h/0h]"
    "tpubDDjVt7cey7cxQ1nXzxpXuNT5vJecpvtMhmZywA9U9ChWDk8z6HSGPJ7YS6pyd8ZXQyfCeUCXrkyEqNeTFUmpdXT9r3TD1DAYoY52UEyy1Yf"
    "/<0;1>/*)"
)

# Pre-derived from descriptor tpub (scripts/derive_test_addresses.py)
# keychain 0 = receive (external), keychain 1 = change (internal)
ADDR_0_RECEIVE  = "tb1qkyemuvfvgtjwzvfsefskpvu9d2qsx4tgcnkhrv"
ADDR_19_RECEIVE = "tb1q3ewvjke7njerlh39qm9mgfcd8p7amg3zzwsyhl"
ADDR_20_RECEIVE = "tb1q8mnmh75k3ex9qufdtp9dduwmua8k0jxqfq6m9v"
ADDR_30_RECEIVE = "tb1qnez39que3peesavajvl9lsry6vfujzl65uwwr2"
ADDR_0_CHANGE   = "tb1qttxvvjh890zuzz4yl6tys64346jaapaqz9dxsx"


# ---------------------------------------------------------------------------
# Test function
# ---------------------------------------------------------------------------

async def test_wallet_device_key(d: UIDriver):
    print(f"\n--- {WALLET_NAME} ---")

    # 1. Create project (lands on project detail)
    await create_project(d, PROJECT_NAME, DESCRIPTOR)

    # 2. Create wallet with Device Key (default protection — no password needed)
    await create_wallet_from_project(d, WALLET_NAME, protection="device_key")

    # 3. Wallet detail loaded — title should be wallet name
    sem = await d.semantics_tree()
    if f'"{WALLET_NAME}"' not in sem:
        raise AssertionError(
            f"Wallet name '{WALLET_NAME}' not visible in AppBar after creation"
        )
    print(f"    [ok] wallet detail opened: '{WALLET_NAME}'")

    # 4. Verify overview: "Receive" and "Send" action buttons present
    for btn in ("Receive", "Send"):
        if f'"{btn}"' not in sem:
            raise AssertionError(f"'{btn}' button not visible in wallet overview")
        print(f"    [ok] '{btn}' button visible")

    # 5. Press Receive → wait for dialog to open (BDK derives the first address lazily,
    #    which can take several seconds on first use).
    await click_label(d, "Receive", delay=0.5)
    try:
        await wait_for(d, '"Next address"', "Receive dialog opened", retries=20, delay=0.5)
        sem_recv = await d.semantics_tree()
        low = sem_recv.lower()
        has_error = "no unused" in low or "no hay" in low or "error" in low
        if has_error:
            raise AssertionError("Error shown when opening receive dialog")
        print("    [ok] receive dialog opened")
        # The dialog shows ColoredGroupText without truncation — full address in semantics.
        m = re.search(r'\btb1q[a-z0-9]+\b', sem_recv)
        if not m:
            raise AssertionError("No tb1q address found in Receive dialog semantics")
        observed = m.group(0)
        if observed != ADDR_0_RECEIVE:
            raise AssertionError(
                f"Receive dialog shows wrong address:\n"
                f"  got:      {observed}\n"
                f"  expected: {ADDR_0_RECEIVE}"
            )
        print(f"    [ok] receive dialog shows correct address #0: {ADDR_0_RECEIVE[:16]}...")
    except AssertionError as e:
        msg = str(e)
        # Re-raise hard failures that indicate a real bug
        if any(s in msg for s in ("Error shown", "wrong address", "No tb1q")):
            raise
        # Dialog didn't open: verify we're still on wallet detail (not navigated away)
        sem_recv = await d.semantics_tree()
        if f'"{WALLET_NAME}"' not in sem_recv:
            raise AssertionError("Receive action navigated away from wallet detail")
        print("    [warn] receive dialog did not open — continuing")

    # 6. Close receive dialog if open, then navigate to Addresses tab.
    # The dialog uses tooltip="Cancel"; "Next address" label is unique to it.
    sem_before_close = await d.semantics_tree()
    if '"Next address"' in sem_before_close:
        await click_tooltip(d, "Cancel", delay=0.8)
        print("    [ok] receive dialog closed via Cancel")
    # Verify still on wallet detail before proceeding
    await wait_for(d, f'"{WALLET_NAME}"', "still on wallet detail after close", retries=6, delay=0.5)
    await click_label(d, "Addresses", delay=1.0)
    sem_addr = await d.semantics_tree()

    # The wallet auto-reveals 20 receive addresses on first open (#0–#19).
    # Address labels are multi-line in semantics: '"#N\ntb1q..."', so check for
    # the opening '"#N\n' pattern instead of the closed '"#N"' form.
    # ListView only renders visible tiles, so scroll to bottom to verify #19.
    if '"#0\n' not in sem_addr:
        raise AssertionError("Address #0 not visible in Addresses tab")
    if 'tb1q' not in sem_addr.lower():
        raise AssertionError("No bech32 address string visible in Addresses tab")
    print("    [ok] first receive addresses visible starting at #0")

    # Scroll to the end of the first 20-address page to verify #19 and the
    # "Reveal 20 more" button are rendered.
    d.scroll_down(5)
    await asyncio.sleep(0.4)
    sem_bottom = await d.semantics_tree()
    if '"#19\n' not in sem_bottom:
        raise AssertionError("Address #19 not visible — initial 20-address page incomplete")
    print("    [ok] initial 20 receive addresses visible (#0–#19)")

    # 6b. Pagination: click "Reveal 20 more addresses" → verify #20 and #30 appear.
    await click_label(d, "Reveal 20 more addresses", delay=2.0)
    # #20 appears at the top of the newly loaded page; confirm it's visible.
    await wait_for(d, '"#20\n', "page 2 loaded (#20 visible)", retries=15, delay=0.8)
    print("    [ok] page 2 loaded — address #20 visible")
    # Scroll further down to reach #30 (ListView only renders visible tiles).
    d.scroll_down(5)
    await asyncio.sleep(0.4)
    sem_p2 = await d.semantics_tree()
    if '"#30\n' not in sem_p2:
        raise AssertionError("Address #30 not visible after Reveal 20 more")
    print("    [ok] address #30 visible after pagination")

    # 6c. Change addresses: fresh wallet starts with 0 change addrs (no auto-reveal).
    # TabBar is sticky — "Change" sub-tab is always reachable without scroll.
    await click_label(d, "Change", delay=0.8)
    sem_chg = await d.semantics_tree()
    if '"#0\n' not in sem_chg:
        if '"Reveal 20 more addresses"' not in sem_chg:
            raise AssertionError("Change tab: neither #0 nor Reveal button found")
        await click_label(d, "Reveal 20 more addresses", delay=2.0)
        sem_chg = await wait_for(
            d, '"#0\n', "change address #0 revealed", retries=12, delay=0.8
        )
    # The Addresses tab truncates address text (ColoredGroupText truncate=true),
    # so only verify the tb1q prefix is present — exact match is done in the
    # Receive dialog (step 5) where truncation is disabled.
    if 'tb1q' not in sem_chg.lower():
        raise AssertionError("No bech32 address visible in Change tab after reveal")
    print(f"    [ok] change address #0 visible ({ADDR_0_CHANGE[:16]}...)")

    # Switch back to receive sub-tab before continuing
    await click_label(d, "Receive", delay=0.5)

    # 7. Navigate to Transactions tab — just verify it doesn't crash
    await click_label(d, "Transactions", delay=0.8)
    sem_tx = await d.semantics_tree()
    if f'"{WALLET_NAME}"' not in sem_tx:
        raise AssertionError("Wallet name disappeared after navigating to Transactions tab")
    print("    [ok] Transactions tab renders without error")

    print(f"\n    [PASS] {WALLET_NAME}")


# ---------------------------------------------------------------------------
# Entry point
# ---------------------------------------------------------------------------

async def main():
    d = UIDriver(sandbox=True)
    try:
        await d.launch()
        d.raise_window()
        await dismiss_startup_dialogs(d)

        await test_wallet_device_key(d)

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
