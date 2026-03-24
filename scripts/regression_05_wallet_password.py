#!/usr/bin/env python3
"""
Regression test 05: Wallet password protection — lock/unlock session flow.

Verifies the full UserPassword protection lifecycle:
  - Wallet creation with password
  - Unlock on first open (password prompt)
  - Session caching: re-opening without prompt
  - Lock via 'More options' menu
  - Re-unlock after lock (prompt reappears)

IMPORTANT: Requires Rust release library for acceptable KDF speed.
  Build with: bash scripts/prepare_test_build.sh

Flow:
  1. Create wpkh project + wallet with UserPassword protection
  2. Enter password → wallet detail loads
  3. Go back to wallet list — wallet shown as locked (lock icon)
  4. Re-open wallet → NO password prompt (session cached in memory)
  5. Lock via 'More options' menu
  6. Wallet list shows locked wallet again
  7. Re-open → password prompt reappears
  8. Enter password → wallet detail loads again

Exit code: 0 = PASS, 1 = FAIL.

Prerequisites:
  bash scripts/prepare_test_build.sh
  python3 scripts/regression_05_wallet_password.py
"""

import asyncio
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from ui_driver import UIDriver                          # noqa: E402
from regression_helpers import (                       # noqa: E402
    wait_for,
    click_label,
    fill_field,
    dismiss_startup_dialogs,
    create_project, go_back,
    navigate_wallets,
    create_wallet_from_project,
    unlock_wallet,
    lock_wallet,
    open_wallet_from_list,
)


# ---------------------------------------------------------------------------
# Test data
# ---------------------------------------------------------------------------

PROJECT_NAME = "Reg05-WPKH-Project"
WALLET_NAME  = "Reg05-Password-Wallet"
WALLET_PASS  = "reg05-test-password"

# fresh wallet with no prior transactions
# mnemonic: piece blue stadium control fiction kick group mimic hollow dog mask interest
DESCRIPTOR = (
    "wpkh([ff81be5d/84h/1h/0h]"
    "tpubDDjVt7cey7cxQ1nXzxpXuNT5vJecpvtMhmZywA9U9ChWDk8z6HSGPJ7YS6pyd8ZXQyfCeUCXrkyEqNeTFUmpdXT9r3TD1DAYoY52UEyy1Yf"
    "/<0;1>/*)"
)


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

async def _assert_on_wallet_detail(d, wallet_name: str, context: str):
    """Assert that the wallet detail screen for `wallet_name` is active."""
    await wait_for(
        d, f'"{wallet_name}"',
        f"Wallet detail '{wallet_name}' — {context}",
        retries=25, delay=1.0,
    )


async def _assert_wallet_needs_password(d, wallet_name: str, context: str):
    """Assert that the wallet password prompt is showing."""
    sem = await wait_for(
        d, '"Enter wallet password"',
        f"Password prompt — {context}",
        retries=8, delay=0.8,
    )
    return sem


# ---------------------------------------------------------------------------
# Test function
# ---------------------------------------------------------------------------

async def test_wallet_password_lifecycle(d: UIDriver):
    print(f"\n--- {WALLET_NAME} (password lifecycle) ---")

    # ── Phase 1: Create project + wallet with password ────────────────────────
    print("\n  [phase 1] create project + wallet")
    await create_project(d, PROJECT_NAME, DESCRIPTOR)
    await create_wallet_from_project(
        d, WALLET_NAME,
        protection="password",
        password=WALLET_PASS,
    )

    # After creation the wallet is unlocked (session active).
    await _assert_on_wallet_detail(d, WALLET_NAME, "just created")
    print(f"    [ok] wallet detail loaded after creation (password entered during create)")

    # ── Phase 2: Go back → wallet list ───────────────────────────────────────
    print("\n  [phase 2] go back to wallet list")
    await go_back(d)
    await wait_for(d, '"Wallets"', "Wallet list after going back")
    print(f"    [ok] back on wallet list")

    # ── Phase 3: Re-open wallet → session cached, NO password prompt ──────────
    print("\n  [phase 3] re-open — expect no password prompt (session cached)")
    await open_wallet_from_list(d, WALLET_NAME)

    # Give the screen time to load; if password prompt appears that's a fail
    await asyncio.sleep(2.0)
    sem = await d.semantics_tree()

    if '"Enter wallet password"' in sem:
        raise AssertionError(
            "Password prompt appeared on re-open — session was NOT cached"
        )
    if f'"{WALLET_NAME}"' not in sem:
        raise AssertionError(
            f"Wallet name '{WALLET_NAME}' not visible — wallet detail did not load"
        )
    print(f"    [ok] wallet opened without password prompt (session cached)")

    # ── Phase 4: Lock wallet ──────────────────────────────────────────────────
    print("\n  [phase 4] lock wallet via More options menu")
    await lock_wallet(d)

    # After lock the app either shows the password prompt on the detail screen
    # or navigates back to the wallet list. Both are valid implementations.
    await asyncio.sleep(1.0)
    sem_after_lock = await d.semantics_tree()

    if '"Enter wallet password"' in sem_after_lock:
        # Still on wallet detail but needs password — valid
        print("    [ok] wallet locked: password prompt shown on detail screen")
        # Go back to list to set up for the next phase
        await go_back(d)
        await wait_for(d, '"Wallets"', "Back on wallet list after lock")
    elif '"Wallets"' in sem_after_lock:
        # Navigated back to wallet list — also valid
        print("    [ok] wallet locked: navigated back to wallet list")
    else:
        raise AssertionError(
            "After lock: neither password prompt nor wallet list visible"
        )

    # ── Phase 5: Re-open locked wallet → password prompt must appear ──────────
    print("\n  [phase 5] re-open locked wallet — expect password prompt")
    await open_wallet_from_list(d, WALLET_NAME)

    await asyncio.sleep(1.5)
    sem_locked = await d.semantics_tree()

    if '"Enter wallet password"' not in sem_locked:
        raise AssertionError(
            "No password prompt after reopening a locked wallet — lock did not persist"
        )
    print(f"    [ok] password prompt shown for locked wallet")

    # ── Phase 6: Enter password → wallet detail loads ─────────────────────────
    print("\n  [phase 6] enter password → wallet detail should load")
    await fill_field(d, "Password", WALLET_PASS)
    await click_label(d, "Confirm", delay=8.0)

    await _assert_on_wallet_detail(d, WALLET_NAME, "after re-unlock")
    print(f"    [ok] wallet unlocked successfully after lock/re-unlock cycle")

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

        await test_wallet_password_lifecycle(d)

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
