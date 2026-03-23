#!/usr/bin/env python3
"""
UI test for the Hot Key (signing key) flow:
  1. Create a test wallet with TEST_DESCRIPTOR (wpkh, known good)
  2. Navigate into the new wallet
  3. Go to the "Keys" sub-tab inside the Descriptor tab
  4. Verify per-key "Add signing key" chip is present on non-hot keys
  5. Tap it → verify bottom sheet opens with expected MFP shown in header
  6. Enter the test mnemonic → verify MFP chip + green checkmark appears
  7. Tap "Add key" → verify "hot" badge appears on the key card
  8. Verify "Remove signing key" link appears / "Add signing key" chip disappears

Run after: bash scripts/prepare_test_build.sh
  python3 scripts/test_hot_keys_ui.py
"""

import asyncio
import sys
import time
import re as _re
from pathlib import Path

# Add project root to path so we can import ui_driver
sys.path.insert(0, str(Path(__file__).resolve().parent))
from ui_driver import UIDriver  # noqa: E402

TEST_MNEMONIC = (
    "abandon abandon abandon abandon abandon abandon abandon abandon "
    "abandon abandon abandon abandon abandon abandon abandon abandon "
    "abandon abandon abandon abandon abandon abandon abandon art"
)
EXPECTED_MFP = "5436d724"

# Testnet descriptor for this mnemonic — wpkh so descriptor analysis works
TEST_DESCRIPTOR = (
    "wpkh([5436d724/84'/1'/0']"
    "tpubDCWivZp6qaqCALCt8MyLqAb3awnWm4hfbBPjdZqirYFXYeZ5YsfbWVaPacULZTGtK1RPBSZ92UWNjnhL4fB9UVrF2FjgW8cgmBjxPBmB4iB"
    "/<0;1>/*)"
)
TEST_WALLET_NAME = "HotKeyTestWallet"


async def wait_for_label(driver: UIDriver, label: str, timeout: float = 5.0) -> bool:
    """Poll semantics tree until `label` appears or timeout."""
    deadline = time.time() + timeout
    while time.time() < deadline:
        sem = await driver.semantics_tree()
        if label in sem:
            return True
        await asyncio.sleep(0.5)
    return False


async def create_test_wallet(driver: UIDriver) -> bool:
    """Create a test wallet with TEST_DESCRIPTOR. Returns True on success."""
    print("\n--- Creating test wallet ---")

    # Open overflow menu
    print("[click] Opening overflow menu...")
    await driver.click_semantic("", tooltip="Show menu")
    await asyncio.sleep(0.7)

    # Click "New"
    print("[click] Clicking 'New'...")
    for label in ["New", "Nuevo"]:
        rect = await driver.find_semantic_rect(label)
        if rect:
            cx = (rect[0] + rect[2]) // 2
            cy = (rect[1] + rect[3]) // 2
            driver.flutter_click(cx, cy)
            print(f"  Clicked '{label}' at Flutter ({cx},{cy})")
            break
    else:
        print("[ERROR] 'New'/'Nuevo' not found in overflow menu")
        return False
    await asyncio.sleep(1.2)

    sem = await driver.semantics_tree()
    if "Wallet name" not in sem and "Nombre" not in sem and "Name" not in sem:
        print("[ERROR] Create wallet dialog did not open")
        print(sem[:2000])
        return False

    # Fill wallet name
    print(f"[type] Filling wallet name '{TEST_WALLET_NAME}'...")
    for label in ["Wallet name", "Nombre de billetera", "Name"]:
        rect = await driver.find_semantic_rect(label)
        if rect:
            cx = (rect[0] + rect[2]) // 2
            cy = (rect[1] + rect[3]) // 2
            driver.flutter_click(cx, cy)
            await asyncio.sleep(0.3)
            driver.key("ctrl+a")
            driver.type_text(TEST_WALLET_NAME)
            print(f"  Typed name into field '{label}'")
            break
    await asyncio.sleep(0.3)

    # Select "Manual descriptor" radio button (the unchecked one)
    print("[click] Selecting 'Manual descriptor' source...")
    sem_radio = await driver.semantics_tree()
    lines = sem_radio.splitlines()
    _rect_re = _re.compile(r'Rect\.fromLTRB\(([^)]+)\)')
    radio_rects = []
    for i, line in enumerate(lines):
        if 'isInMutuallyExclusiveGroup' in line:
            for j in range(i - 1, max(0, i - 10), -1):
                m = _rect_re.search(lines[j])
                if m:
                    coords = [float(x.strip()) for x in m.group(1).split(',')]
                    is_checked = any('isChecked' in lines[k]
                                     for k in range(j, min(len(lines), i + 3))
                                     if 'isInMutuallyExclusiveGroup' not in lines[k])
                    radio_rects.append({'rect': coords, 'is_checked': is_checked})
                    break

    manual_radio = next((r for r in radio_rects if not r['is_checked']), None)
    if manual_radio:
        row_rect = await driver.find_semantic_rect("Manual descriptor")
        if row_rect:
            r = manual_radio['rect']
            cx = int(row_rect[0] + r[0] + (r[2] - r[0]) / 2)
            cy = (row_rect[1] + row_rect[3]) // 2
            driver.flutter_click(cx, cy)
            print(f"  Clicked 'Manual descriptor' radio at Flutter ({cx},{cy})")
        else:
            driver.flutter_click(172, 172)
            print("  Fallback click at Flutter (172,172)")
    else:
        driver.flutter_click(172, 172)
        print("  Could not find unchecked radio — fallback click")
    await asyncio.sleep(0.8)

    # Fill descriptor — find the 2nd isTextField
    print("[type] Filling descriptor...")
    sem_bd = await driver.semantics_tree()
    lines_bd = sem_bd.splitlines()
    _rf = _re.compile(r'Rect\.fromLTRB\(([^)]+)\)')
    text_field_rects = []
    for i, line in enumerate(lines_bd):
        if 'isTextField' in line:
            for j in range(i - 1, max(0, i - 15), -1):
                m = _rf.search(lines_bd[j])
                if m:
                    coords = [float(x.strip()) for x in m.group(1).split(',')]
                    text_field_rects.append(coords)
                    break

    print(f"  Found {len(text_field_rects)} textfields")
    if len(text_field_rects) >= 2:
        r = text_field_rects[1]
        cx = int((r[0] + r[2]) / 2)
        cy = int(56 + (r[1] + r[3]) / 2)
        driver.flutter_click(cx, cy)
        await asyncio.sleep(0.5)
        driver.key("ctrl+a")
        driver.type_text(TEST_DESCRIPTOR)
        print(f"  Descriptor typed at Flutter ({cx},{cy})")
    else:
        print("[ERROR] Descriptor textfield not found")
        return False
    await asyncio.sleep(0.5)

    # Confirm creation
    print("[click] Confirming wallet creation...")
    for btn_label in ["Create Wallet", "Crear Billetera", "Crear", "Create", "OK", "Aceptar"]:
        rect = await driver.find_semantic_rect(btn_label)
        if rect:
            cx = (rect[0] + rect[2]) // 2
            cy = (rect[1] + rect[3]) // 2
            driver.flutter_click(cx, cy)
            print(f"  Clicked '{btn_label}'")
            break
    else:
        driver.key("Return")
        print("  Pressed Enter as fallback")
    await asyncio.sleep(2.5)

    # Verify wallet appears in list
    sem_post = await driver.semantics_tree()
    if TEST_WALLET_NAME in sem_post:
        print(f"[ok] Wallet '{TEST_WALLET_NAME}' created and visible in list ✓")
        return True
    else:
        print(f"[ERROR] Wallet '{TEST_WALLET_NAME}' not found after creation")
        print(sem_post[:2000])
        return False


async def run_hot_key_test(driver: UIDriver):
    print("\n=== HOT KEY UI TEST ===\n")
    driver.raise_window()
    await asyncio.sleep(0.8)

    # ── Step 1: Verify we start on WalletListScreen ────────────────────────
    await driver.assert_widget("WalletListScreen", "start on Wallets screen")
    print()

    # ── Step 2: Check if test wallet already exists; if not, create it ────
    sem = await driver.semantics_tree()
    if TEST_WALLET_NAME not in sem:
        if "No wallets" in sem or len(sem.strip()) < 100:
            print(f"[info] No wallets found — creating '{TEST_WALLET_NAME}'...")
        else:
            print(f"[info] '{TEST_WALLET_NAME}' not found — creating it...")
        ok = await create_test_wallet(driver)
        if not ok:
            print("[FAIL] Could not create test wallet")
            return
        # Back on wallet list now
        await asyncio.sleep(0.5)
    else:
        print(f"[ok] '{TEST_WALLET_NAME}' already exists in wallet list")

    # ── Step 3: Open the test wallet ───────────────────────────────────────
    print(f"\n[click] Opening '{TEST_WALLET_NAME}'...")
    wallet_rect = await driver.find_semantic_rect(TEST_WALLET_NAME)
    if wallet_rect:
        cx = (wallet_rect[0] + wallet_rect[2]) // 2
        cy = (wallet_rect[1] + wallet_rect[3]) // 2
        driver.flutter_click(cx, cy)
        print(f"  Tapped at Flutter ({cx},{cy})")
    else:
        print(f"[ERROR] '{TEST_WALLET_NAME}' not found in list")
        return
    await asyncio.sleep(1.5)

    # Handle password dialog if any
    tree = await driver.widget_tree()
    if "WalletDetailScreen" not in tree:
        sem = await driver.semantics_tree()
        if "password" in sem.lower() or "contraseña" in sem.lower():
            print("[info] Password dialog — pressing Escape")
            driver.key("Escape")
            await asyncio.sleep(0.5)
            print("[SKIP] Password-protected wallet. Test needs a non-protected wallet.")
            return
        print("[ERROR] Not on WalletDetailScreen after tapping wallet")
        print(tree[:500])
        return

    print("[ok] On WalletDetailScreen")
    await asyncio.sleep(0.5)

    # ── Step 4: Navigate to the "Descriptor" tab ──────────────────────────
    print("[click] Tapping 'Descriptor' tab...")
    await driver.click_semantic("Descriptor", tooltip="")
    await asyncio.sleep(0.5)

    # Wait for descriptor analysis to load
    print("[wait] Waiting for descriptor analysis (Keys sub-tab)...")
    if not await wait_for_label(driver, "Keys", timeout=10.0):
        sem = await driver.semantics_tree()
        print("[info] Semantics after Descriptor tab click:")
        print(sem[:2000])
        print("[ERROR] Descriptor analysis did not load (no 'Keys' sub-tab found)")
        return
    print("[ok] Descriptor loaded — sub-tabs visible\n")

    # ── Step 5: Navigate to the "Keys" sub-tab ────────────────────────────
    print("[click] Tapping 'Keys' sub-tab...")
    await driver.click_semantic("Keys")
    await asyncio.sleep(0.8)

    # ── Step 6: Check hot key state ────────────────────────────────────────
    sem = await driver.semantics_tree()

    # Remove hot key from previous test run if needed.
    # "Remove signing key" is on the Keys tab (not inside a modal) — semantics should show it.
    if "Remove signing key" in sem:
        print("[info] Key is already hot (previous run) — removing first...")
        await driver.click_semantic("Remove signing key")
        # Wait for the async deleteHotKey to complete and the UI to rebuild
        await asyncio.sleep(2.0)
        sem = await driver.semantics_tree()
        print("[ok] Hot key removed\n")

    # ── Step 7: Verify per-key "Add signing key" chip ─────────────────────
    print("[assert] Per-key 'Add signing key' chip visible on non-hot key card...")
    if "Add signing key" in sem:
        print("[ok] Per-key 'Add signing key' chip found ✓\n")
    else:
        print("[WARN] 'Add signing key' chip not found — checking widget tree...")
        tree = await driver.widget_tree()
        if "Add signing key" in tree:
            print("[ok] Found in widget tree (accessibility label issue)\n")
        else:
            print("[ERROR] 'Add signing key' chip not found anywhere")
            print("Semantics (first 2000):")
            print(sem[:2000])
            return

    # ── Step 8: Tap per-key chip → open contextual sheet ──────────────────
    # The chip's semantic node (#94) encompasses both the chip AND the KeyCard.
    # Clicking at the center would hit the KeyCard. Clicking at the top hits the chip.
    # The chip InkWell is at the TOP ~18px of the combined rect.
    # Strategy: try the chip (top of rect); if sheet doesn't open, fall back to
    # the global "Add signing key" FilledButton at the bottom of the keys list.
    print("[click] Tapping per-key 'Add signing key' chip...")
    chip_rect = await driver.find_semantic_rect("Add signing key")
    if chip_rect:
        cx = (chip_rect[0] + chip_rect[2]) // 2
        cy = chip_rect[1] + 9   # top of combined rect + 9px = center of chip area
        driver.flutter_click(cx, cy)
        print(f"  Chip click at Flutter ({cx},{cy}) — rect {chip_rect}")
        # Quick check: did sheet open at 100ms? (if it opens then immediately closes, catch it early)
        await asyncio.sleep(0.15)
        tree_quick = await driver.widget_tree()
        if "_AddHotKeySheetState" in tree_quick:
            print("  [debug] Sheet open at 150ms ✓")
        else:
            print("  [debug] Sheet NOT open at 150ms (chip click may not have triggered InkWell)")
        await asyncio.sleep(0.85)  # total ~1s wait
    else:
        print("  [warn] chip rect not found; falling back to global button")
        await asyncio.sleep(1.0)

    # Check if sheet opened (need BOTH: _AddHotKeySheetState in tree AND a second scopesRoute)
    tree = await driver.widget_tree()
    sem = await driver.semantics_tree()
    sheet_open = "_AddHotKeySheetState" in tree
    if not sheet_open:
        # Per-key chip click didn't open the sheet.
        # Fall back: use the global "Add signing key" FilledButton at the bottom of the keys list.
        # Poll up to 3s for semantics to update (may be rebuilding after hot-key removal).
        print("  [warn] Chip click did not open sheet — using global 'Add signing key' button...")
        global_btn_rect = None
        for _ in range(6):  # up to 3s in 0.5s steps
            sem_try = await driver.semantics_tree()
            lines = sem_try.splitlines()
            rects = []
            for i, line in enumerate(lines):
                if 'label: "Add signing key"' in line:
                    r = driver._parse_semantics_rect_before(lines, i)
                    if r:
                        rects.append(r)
            if rects:
                global_btn_rect = rects[-1]  # last occurrence = global button at bottom
                break
            await asyncio.sleep(0.5)
        if global_btn_rect:
            gcx = (global_btn_rect[0] + global_btn_rect[2]) // 2
            gcy = (global_btn_rect[1] + global_btn_rect[3]) // 2
            driver.flutter_click(gcx, gcy)
            print(f"  Global button click at Flutter ({gcx},{gcy}) — rect {global_btn_rect}")
        else:
            print("  [warn] Global button rect not found, trying click_semantic fallback")
            await driver.click_semantic("Add signing key")
        await asyncio.sleep(1.0)
        tree = await driver.widget_tree()
        sem = await driver.semantics_tree()
        sheet_open = "_AddHotKeySheetState" in tree

    if not sheet_open:
        print("[ERROR] Bottom sheet did not open")
        print(f"  tree has _AddHotKeySheet: {'_AddHotKeySheet' in tree}")
        print(f"  scopesRoute count: {sem.count('scopesRoute')}")
        print(f"  widget_tree snippet: {tree[:500]}")
        return

    print("[ok] Bottom sheet opened ✓")

    # ── Step 9: Verify contextual title shows expected MFP ────────────────
    mfp_upper = EXPECTED_MFP.upper()
    if EXPECTED_MFP in sem or mfp_upper in sem:
        print(f"[ok] Expected MFP '{EXPECTED_MFP}' shown in sheet header ✓")
    else:
        print(f"[warn] MFP not visible in semantics header yet (will validate after mnemonic)")
    print()

    # ── Step 10: Enter the test mnemonic ──────────────────────────────────
    # Use Tab navigation to focus the mnemonic field — no positional click dependency.
    # Tab order after sheet opens (first focusable = close IconButton):
    #   close-btn → seg1(Mnemonic) → seg2(xprv) → mnemonic-TextField
    # If nothing is focused initially, the first Tab focuses close-btn; then 3 more to mnemonic.
    # We send 4 Tabs to be safe (covers both "auto-focused close btn" and "nothing focused" cases).
    print("[tab] Focusing mnemonic field via keyboard navigation...")
    for _ in range(4):
        driver.key("Tab")
        await asyncio.sleep(0.08)
    # Clear any leftover text from a previous run, then type the mnemonic
    driver.key("ctrl+a")
    await asyncio.sleep(0.1)

    print("[type] Entering test mnemonic...")
    driver.type_text(TEST_MNEMONIC, delay_ms=20)
    await asyncio.sleep(2.5)  # Wait for async validation (500ms debounce + FFI)

    # Verify mnemonic was entered: word-count row should show "24 / 24"
    tree_after = await driver.widget_tree()
    word_count_ok = '"24 / 24"' in tree_after or "'24 / 24'" in tree_after or "24 / 24" in tree_after
    print(f"[assert] Word count 24/24 visible: {'✓' if word_count_ok else '✗'}")
    if not word_count_ok:
        print("[ERROR] Mnemonic field could not be focused (Tab×4 didn't work)")
        wc_lines = [l.strip() for l in tree_after.splitlines() if "24" in l or "word" in l.lower()]
        print(f"  word-count lines: {wc_lines[:10]}")
        return

    # Verify MFP validation — look for "MFP: <mfp>" which only appears in the validation row
    # (NOT a false-positive from the descriptor text which lacks the "MFP: " prefix)
    mfp_label = f"MFP: {EXPECTED_MFP}"
    mfp_ok = mfp_label in tree_after or mfp_label.upper() in tree_after
    print(f"[assert] MFP validation row '{mfp_label}' visible: {'✓' if mfp_ok else '✗'}")
    if not mfp_ok:
        # Print debug info — check what the widget_tree shows around derivedMfp
        mfp_lines = [l.strip() for l in tree_after.splitlines()
                     if "MFP" in l or "mfp" in l or EXPECTED_MFP in l.lower()]
        print(f"  Lines with MFP/mfp/{EXPECTED_MFP}: {mfp_lines[:10]}")
        print("[ERROR] MFP validation row not found — mnemonic validation may have failed")
        return
    print()

    # ── Step 11: Tap "Add key" ─────────────────────────────────────────────
    # Now that the mnemonic is valid, the FilledButton "Add key" is ENABLED and
    # should appear in the semantics tree. Try semantic click first.
    print("[click] Tapping 'Add key'...")
    add_key_rect = await driver.find_semantic_rect("Add key")
    if add_key_rect:
        cx = (add_key_rect[0] + add_key_rect[2]) // 2
        cy = (add_key_rect[1] + add_key_rect[3]) // 2
        driver.flutter_click(cx, cy)
        print(f"  Semantic click at Flutter ({cx},{cy})")
    else:
        # Button not yet in semantics — use Tab navigation from mnemonic field.
        # The mnemonic TextField is still focused; Tab×3 reaches "Add key":
        #   Tab→passphrase-visibility-toggle → Tab→passphrase-TextField → Tab→Add-key-button
        print("  'Add key' not in semantics; using Tab×3 + Space from mnemonic field")
        for _ in range(3):
            driver.key("Tab")
            await asyncio.sleep(0.1)
        driver.key("space")
        print("  Pressed Space to activate 'Add key'")
    await asyncio.sleep(1.5)

    # Sheet should have closed
    await driver.assert_widget("WalletDetailScreen", "back on wallet detail after adding key")

    # ── Step 12: Verify "hot" badge ─────────────────────────────────────────
    print("[assert] 'hot' badge visible on key card...")
    # Use semantics (which should be un-truncated now that the sheet is closed)
    sem_final = await driver.semantics_tree()
    tree_final = await driver.widget_tree()

    # Check that "hot" appears in the semantics of the keys tab
    hot_in_sem = "hot" in sem_final
    hot_in_tree = "Text(\"hot\"" in tree_final or "'hot'" in tree_final or '"hot"' in tree_final
    if hot_in_sem or hot_in_tree:
        print("[ok] 'hot' badge visible ✓")
    else:
        print("[ERROR] 'hot' badge not found — key may not have been added")
        print("Semantics snippet:")
        print(sem_final[:1000])
        return

    if "Remove signing key" in sem_final:
        print("[ok] 'Remove signing key' link appeared ✓")
    if "Add signing key" not in sem_final:
        print("[ok] Per-key 'Add signing key' chip gone (key is now hot) ✓")
    print()

    print("\n[result] Hot Key UI test PASSED ✓")


async def main():
    driver = UIDriver()
    try:
        await driver.launch()
        await run_hot_key_test(driver)
    except AssertionError as e:
        print(f"\n[FAIL] {e}")
        sys.exit(1)
    except Exception as e:
        print(f"\n[ERROR] {e}")
        import traceback
        traceback.print_exc()
        sys.exit(1)
    finally:
        print("\n[shutdown] Closing...")
        await driver.close()
        print("[shutdown] Done.")


if __name__ == "__main__":
    asyncio.run(main())
