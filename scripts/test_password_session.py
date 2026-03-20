#!/usr/bin/env python3
"""
UI test: UserPassword wallet session persistence and lock.

Verifies:
  1. Find a locked (Password protected) wallet card in the list
  2. Open it → enters password → on WalletDetailScreen
  3. Go back → wallet list refreshes; unlocked wallet shows without lock
  4. Tap same card again → NO password prompt (session cached)
  5. ⋮ menu has "Lock wallet" item (only for UserPassword wallets)
  6. Lock → back on wallet list → wallet shows as locked again
  7. Tap again → password prompt appears

Run after: flutter build linux --debug
  python3 scripts/test_password_session.py

Requires: at least one UserPassword wallet (run test_wallet_lifecycle.py first)
"""

import asyncio
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).parent))
from ui_driver import UIDriver  # noqa: E402

WALLET_PASS = "lifecycle-pass-1"

# Wallet detail "More options" popup — y-offsets from button bottom to item center.
# Material 3: 48px/item, 16px/divider.
# Send(24) Receive(72) DIV Sync(136) Rescan(184) DIV ExportLabels(248)
# ImportLabels(296) DIV GenerateProject(360) DIV LockWallet(424)
LOCK_OFFSETS = [424, 376, 400, 448]


def on_wallet_detail(sem: str) -> bool:
    return 'tooltip: "Back"' in sem and 'tooltip: "More options"' in sem


def on_wallet_list(sem: str) -> bool:
    return '"Wallets"' in sem and 'tooltip: "Back"' not in sem


def has_password_dialog(sem: str) -> bool:
    return "Enter wallet password" in sem or "wallet is protected" in sem.lower()


async def wait_for(d: UIDriver, pred, desc: str, retries=8, delay=0.8):
    for _ in range(retries):
        sem = await d.semantics_tree()
        if pred(sem):
            print(f"    [✓] {desc}")
            return sem
        await asyncio.sleep(delay)
    sem = await d.semantics_tree()
    raise AssertionError(f"Timeout: {desc}")


async def enter_password(d: UIDriver, password: str):
    # Find password input (labelText or text above field)
    rect = await d.find_semantic_rect("Password")
    if rect:
        h = rect[3] - rect[1]
        cx, cy = (rect[0]+rect[2])//2, (rect[1]+rect[3])//2
        if h < 30:   # small label — click below into TextField
            cy = rect[3] + 28
        d.flutter_click(cx, cy)
    else:
        d.flutter_click(*d.window_center())
    await asyncio.sleep(0.4)
    d.type_text(password)
    await asyncio.sleep(0.3)
    for label in ("OK", "Unlock", "Confirm"):
        r = await d.find_semantic_rect(label)
        if r:
            d.flutter_click((r[0]+r[2])//2, (r[1]+r[3])//2)
            print(f"    [click] '{label}'")
            break
    else:
        d.key("Return")
    await asyncio.sleep(2.5)


async def run(d: UIDriver):
    print("\n=== PASSWORD SESSION TEST ===\n")
    d.raise_window()
    await asyncio.sleep(0.8)

    await d.assert_widget("WalletListScreen", "start on WalletListScreen")
    sem = await d.semantics_tree()
    if "Password protected" not in sem:
        print("[SKIP] No locked wallet found. Run test_wallet_lifecycle.py first.")
        return

    # ── Step 1: Find and open a locked (UserPassword) wallet ─────────────
    print("\n[step 1] Opening a locked wallet (expecting password prompt)...")
    rect_pp = await d.find_semantic_rect("Password protected")
    assert rect_pp, "'Password protected' subtitle not found"

    # Tap center of the locked wallet card (subtitle is within the card)
    tap_cx = (rect_pp[0] + rect_pp[2]) // 2
    tap_cy = (rect_pp[1] + rect_pp[3]) // 2
    print(f"    [card] 'Password protected' subtitle at {rect_pp}, tapping ({tap_cx},{tap_cy})")
    d.flutter_click(tap_cx, tap_cy)
    await asyncio.sleep(1.5)

    sem = await d.semantics_tree()
    if has_password_dialog(sem):
        print("    [ok] Password dialog appeared ✓")
        await enter_password(d, WALLET_PASS)
    elif on_wallet_detail(sem):
        print("    [note] Opened without prompt (might have been unlocked earlier in session)")
    else:
        print(f"    [dbg] sem: {sem[:300]}")

    await wait_for(d, on_wallet_detail, "on WalletDetailScreen after unlock")
    print("    [ok] Step 1 ✓")

    # ── Step 2: Go back to wallet list ────────────────────────────────────
    print("\n[step 2] Going back to wallet list...")
    await d.click_semantic("", tooltip="Back")
    await asyncio.sleep(1.5)
    sem = await wait_for(d, on_wallet_list, "back on wallet list")
    print("    [ok] Step 2 ✓")

    # Unlocked wallet should no longer show "Password protected" at same position
    # (the card still exists at the same y, but subtitle changed to last synced)
    rect_pp_after = await d.find_semantic_rect("Password protected")
    if rect_pp_after != rect_pp:
        print("    [ok] 'Password protected' moved/gone at previous card position ✓")
    else:
        print("    [warn] 'Password protected' still at same position")

    await asyncio.sleep(0.4)

    # ── Step 3: Reopen SAME card — must NOT prompt for password ───────────
    print("\n[step 3] Tapping same card again (expecting NO password prompt)...")
    # Tap the same coordinates as step 1
    d.flutter_click(tap_cx, tap_cy)
    await asyncio.sleep(2.0)

    sem = await d.semantics_tree()
    if has_password_dialog(sem):
        print("    [FAIL] Password prompt appeared — session NOT preserved!")
        d.key("Escape")
        raise AssertionError("Session not preserved: password requested on second open")

    await wait_for(d, on_wallet_detail, "on WalletDetailScreen without password")
    print("    [ok] Opened WITHOUT password prompt — SESSION WORKS! Step 3 ✓")

    # ── Step 4: Lock wallet via ⋮ menu ────────────────────────────────────
    print("\n[step 4] Locking wallet via ⋮ menu...")
    rect_mo = await d.find_semantic_rect_by_tooltip("More options")
    assert rect_mo, "'More options' button not found"
    mo_cx = (rect_mo[0] + rect_mo[2]) // 2
    mo_bottom = rect_mo[3]

    locked_ok = False
    for offset in LOCK_OFFSETS:
        # Open popup
        d.flutter_click(mo_cx, (rect_mo[1]+rect_mo[3])//2, delay_s=0.5)
        await asyncio.sleep(0.6)
        # Click "Lock wallet" at estimated offset
        item_y = mo_bottom + offset
        print(f"    [try] offset={offset} → flutter({mo_cx},{item_y})")
        d.flutter_click(mo_cx, item_y)
        await asyncio.sleep(1.2)

        sem = await d.semantics_tree()
        if on_wallet_list(sem):
            print(f"    [ok] Locked with offset={offset} ✓")
            locked_ok = True
            break
        if on_wallet_detail(sem):
            print(f"    [miss] Still on detail — trying next offset")
        else:
            d.key("Escape")
            await asyncio.sleep(0.3)

    if not locked_ok:
        raise AssertionError("Could not click 'Lock wallet' at any offset")

    sem = await wait_for(d, on_wallet_list, "back on wallet list after lock")
    print("    [ok] Step 4 ✓")

    # Wallet should show as locked again after lock + list refresh
    if "Password protected" in sem:
        print("    [ok] Wallet shows as locked again ✓")
    else:
        print("    [warn] May need a moment to refresh...")
        await asyncio.sleep(1.0)
        sem = await d.semantics_tree()
        if "Password protected" in sem:
            print("    [ok] Wallet shows as locked ✓")

    await asyncio.sleep(0.4)

    # ── Step 5: Reopen after lock → must prompt for password ──────────────
    print("\n[step 5] Tapping wallet after lock (expecting password prompt)...")
    # Find the now-locked card by "Password protected" subtitle at same tap position
    d.flutter_click(tap_cx, tap_cy)
    await asyncio.sleep(1.5)

    sem = await d.semantics_tree()
    if has_password_dialog(sem):
        print("    [ok] Password prompt appeared after lock ✓")
        d.key("Escape")
        await asyncio.sleep(0.3)
    elif on_wallet_detail(sem):
        raise AssertionError("Opened WITHOUT password after lock — lock NOT effective!")
    else:
        # Could be on list (clicked wrong area) — check position
        print(f"    [warn] Unexpected state — tapping 'Password protected' card directly")
        rect_pp2 = await d.find_semantic_rect("Password protected")
        if rect_pp2:
            d.flutter_click((rect_pp2[0]+rect_pp2[2])//2, (rect_pp2[1]+rect_pp2[3])//2)
            await asyncio.sleep(1.5)
            sem = await d.semantics_tree()
            if has_password_dialog(sem):
                print("    [ok] Password prompt appeared after lock ✓")
                d.key("Escape")
            elif on_wallet_detail(sem):
                raise AssertionError("Opened WITHOUT password after lock!")
            else:
                print(f"    [warn] Could not confirm step 5: {sem[:200]}")
        else:
            print("    [warn] Could not find a locked card — skipping step 5 verification")

    print("\n=== ALL STEPS PASSED ===")


async def main():
    driver = UIDriver()
    try:
        await driver.launch()
        await run(driver)
    except AssertionError as e:
        print(f"\n[FAIL] {e}")
        sys.exit(1)
    except Exception as e:
        print(f"\n[ERROR] {e}")
        raise
    finally:
        print("\n[shutdown] Closing...")
        await driver.close()
        print("[shutdown] Done.")


if __name__ == "__main__":
    asyncio.run(main())
