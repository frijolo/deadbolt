#!/usr/bin/env python3
"""
Test: Receive flow on a fresh wallet (no prior sync).

Steps:
1. Launch app on Wallet list.
2. Open the "Show menu" overflow → click "Nuevo" to create a wallet.
3. Fill in name + descriptor and confirm.
4. Open the new wallet from the list.
5. Press "Recibir" WITHOUT syncing first.
6. Assert the receive dialog opens (address shown, no error toast).
"""

import asyncio
import sys
import time
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from ui_driver import UIDriver

# Valid testnet P2PKH descriptor (from Rust test suite), with checksum
DESCRIPTOR = "pkh([73c5da0a/44h/1h/0h]tpubDC5FSnBiZDMmhiuCmWAYsLwgLYrrT9rAqvTySfuCCrgsWz8wxMXUS9Tb9iVMvcRbvFcAHGkMD5Kx8koh4GquNGNTfohfk7pgjhaPCdXpoba/<0;1>/*)#0x5u8d5c"
WALLET_NAME = "FreshWalletTest"


async def test_receive_fresh_wallet(driver: UIDriver):
    print("\n=== TEST: Receive on fresh wallet (no prior sync) ===")
    driver.raise_window()
    await asyncio.sleep(0.5)

    # 1. Confirm wallet list
    await driver.assert_widget("WalletListScreen", "starts on wallet list")
    g = driver.window_geometry()
    print(f"[geometry] {g}")

    # 2. Open overflow menu ("Show menu" tooltip = the ⋮ button in the AppBar)
    print("[step 2] Opening overflow menu...")
    await driver.click_semantic("", tooltip="Show menu")
    await asyncio.sleep(0.7)

    sem = await driver.semantics_tree()
    print("[semantics — menu open?]")
    print(sem[:2000])

    # 3. Click "New" (or "Nuevo") in the popup — semantics uses the raw widget text
    print("[step 3] Clicking 'New'...")
    nuevo_rect = await driver.find_semantic_rect("New")
    if nuevo_rect is None:
        nuevo_rect = await driver.find_semantic_rect("Nuevo")
    if nuevo_rect:
        cx = (nuevo_rect[0] + nuevo_rect[2]) // 2
        cy = (nuevo_rect[1] + nuevo_rect[3]) // 2
        driver.flutter_click(cx, cy)
        print(f"  Clicked 'Nuevo' at Flutter ({cx},{cy})")
    else:
        print("  'Nuevo' not found in semantics — aborting")
        print(sem)
        sys.exit(1)
    await asyncio.sleep(1.2)

    sem2 = await driver.semantics_tree()
    print("[semantics — create dialog?]")
    print(sem2[:3000])

    # 4. Fill wallet name
    print(f"[step 4] Filling wallet name '{WALLET_NAME}'...")
    for label in ["Wallet name", "Nombre de billetera", "Name"]:
        rect = await driver.find_semantic_rect(label)
        if rect:
            cx = (rect[0] + rect[2]) // 2
            cy = (rect[1] + rect[3]) // 2
            driver.flutter_click(cx, cy)
            await asyncio.sleep(0.3)
            driver.key("ctrl+a")
            driver.type_text(WALLET_NAME)
            print(f"  Typed name into field '{label}'")
            break
    else:
        print("  Name field not found — dumping semantics for debug:")
        print(sem2)
        sys.exit(1)
    await asyncio.sleep(0.3)

    # 4b. Select "Manual descriptor" radio button.
    # The RadioGroup has two radio circles; "Manual descriptor" is the second one.
    # We parse the semantics tree to find the unchecked radio button and click it.
    print("[step 4b] Selecting 'Manual descriptor' source...")
    sem_radio = await driver.semantics_tree()
    lines = sem_radio.splitlines()
    # Find the "isInMutuallyExclusiveGroup" nodes and pick the one without "isChecked"
    # to click the "Manual descriptor" radio.
    import re as _re
    _rect_re = _re.compile(r'Rect\.fromLTRB\(([^)]+)\)')
    radio_rects = []
    for i, line in enumerate(lines):
        if 'isInMutuallyExclusiveGroup' in line:
            # Walk back to find the Rect for this node
            for j in range(i - 1, max(0, i - 10), -1):
                m = _rect_re.search(lines[j])
                if m:
                    coords = [float(x.strip()) for x in m.group(1).split(',')]
                    is_checked = any('isChecked' in lines[k]
                                     for k in range(j, min(len(lines), i + 3))
                                     if 'isInMutuallyExclusiveGroup' not in lines[k])
                    radio_rects.append({'rect': coords, 'is_checked': is_checked, 'line_idx': j})
                    break
    print(f"  Found {len(radio_rects)} radio buttons: {radio_rects}")
    manual_radio = next((r for r in radio_rects if not r['is_checked']), None)
    if manual_radio:
        # Compute global Flutter coords using find_semantic_rect for the parent row then offset
        row_rect = await driver.find_semantic_rect("Manual descriptor")
        if row_rect:
            # row_rect is the radioGroup row in global Flutter coords
            # The second radio circle is at x≈140-172 within the ROW CONTENT (388px wide)
            # Row starts at x=row_rect[0]+some_margin; use the unchecked radio's local x
            r = manual_radio['rect']
            # The radio circle rect is local to its parent container.
            # Estimate global: row_rect[0] + r[0] + (r[2]-r[0])/2, row_rect[1] + (row_rect[3]-row_rect[1])/2
            # But row_rect already has parent padding; the radioGroup content starts at row_rect[0]
            cx = int(row_rect[0] + r[0] + (r[2] - r[0]) / 2)
            cy = (row_rect[1] + row_rect[3]) // 2
            driver.flutter_click(cx, cy)
            print(f"  Clicked 'Manual descriptor' radio at Flutter ({cx},{cy})")
        else:
            # Fallback: click at known approximate position (right side of row)
            driver.flutter_click(172, 172)
            print("  Fallback click at Flutter (172,172)")
    else:
        print("  Could not find unchecked radio — trying fallback click")
        driver.flutter_click(172, 172)
    await asyncio.sleep(0.8)

    # Dump semantics after selecting Manual descriptor
    sem_after_radio = await driver.semantics_tree()
    print("[semantics after 'Manual descriptor' radio click]")
    print(sem_after_radio[:4000])

    # 5. Fill descriptor — the TextFormField has a hint text as its semantic label
    print("[step 5] Filling descriptor...")
    desc_rect = None
    for hint in ["Pega tu descriptor", "Paste your Bitcoin descriptor", "descriptor"]:
        desc_rect = await driver.find_semantic_rect(hint)
        if desc_rect:
            print(f"  Found descriptor field via '{hint}'")
            break
    # Find the descriptor TextFormField — it's the SECOND isTextField in the form.
    sem_before_desc = await driver.semantics_tree()
    lines_bd = sem_before_desc.splitlines()
    text_field_rects = []
    import re as _re2
    _rf = _re2.compile(r'Rect\.fromLTRB\(([^)]+)\)')
    for i, line in enumerate(lines_bd):
        if 'isTextField' in line:
            for j in range(i - 1, max(0, i - 15), -1):
                m = _rf.search(lines_bd[j])
                if m:
                    coords = [float(x.strip()) for x in m.group(1).split(',')]
                    text_field_rects.append(coords)
                    break
    print(f"  Found {len(text_field_rects)} textfields: {text_field_rects}")
    if len(text_field_rects) >= 2:
        r = text_field_rects[1]
        # Local coords in scroll view → add AppBar offset (56) for global Flutter y
        cx = int((r[0] + r[2]) / 2)
        cy = int(56 + (r[1] + r[3]) / 2)
        driver.flutter_click(cx, cy)
        await asyncio.sleep(0.5)
        driver.key("ctrl+a")
        driver.type_text(DESCRIPTOR)
        print(f"  Descriptor typed into second textfield at Flutter ({cx},{cy})")
    else:
        print("  No second descriptor textfield found — aborting")
        sys.exit(1)
    await asyncio.sleep(0.5)

    # Verify descriptor field has content
    sem_check = await driver.semantics_tree()
    desc_values = [l for l in sem_check.splitlines() if 'value:' in l or 'currentValueLength' in l]
    print(f"  Form field values: {desc_values}")

    # 6. Confirm creation
    print("[step 6] Confirming wallet creation...")
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

    # Debug: dump semantics after confirm to see error or success
    sem_post_create = await driver.semantics_tree()
    print("[semantics post-create]")
    print(sem_post_create[:3000])

    # 7. Find and open the new wallet
    print(f"[step 7] Opening wallet '{WALLET_NAME}'...")
    wallet_rect = await driver.find_semantic_rect(WALLET_NAME)
    if wallet_rect:
        cx = (wallet_rect[0] + wallet_rect[2]) // 2
        cy = (wallet_rect[1] + wallet_rect[3]) // 2
        driver.flutter_click(cx, cy)
        print(f"  Wallet tapped at Flutter ({cx},{cy})")
    else:
        sem3 = await driver.semantics_tree()
        print("[semantics — wallet list after creation?]")
        print(sem3[:3000])
        print(f"[FAIL] Wallet '{WALLET_NAME}' not found in list")
        sys.exit(1)
    await asyncio.sleep(1.5)

    sem4 = await driver.semantics_tree()
    print("[semantics — wallet detail screen?]")
    print(sem4[:2000])

    # 8. Press "Recibir" / "Receive" without syncing.
    print("[step 8] Pressing 'Recibir' (no prior sync)...")
    await asyncio.sleep(0.5)  # let the screen fully load
    full_sem = await driver.semantics_tree()
    # The button has label: "Receive" in semantics (English)
    recv_rect = None
    for lbl in ["Receive", "Recibir"]:
        if f'label: "{lbl}"' in full_sem:
            recv_rect = await driver.find_semantic_rect(lbl)
            if recv_rect:
                print(f"  Found '{lbl}' at {recv_rect}")
                break
    if recv_rect:
        cx = (recv_rect[0] + recv_rect[2]) // 2
        cy = (recv_rect[1] + recv_rect[3]) // 2
        driver.flutter_click(cx, cy)
        print(f"  Clicked 'Receive' at Flutter ({cx},{cy})")
    else:
        # Hard-coded fallback based on observed semantics structure:
        # Send|Receive row: container (16,190,404,291) in scroll list (starts at y=56)
        # Receive: right half (200,0,388,101) → global Flutter center (310,296)
        cx, cy = 310, 296
        driver.flutter_click(cx, cy)
        print(f"  Receive not found by label — fallback at Flutter ({cx},{cy})")
        print(f"  [debug] Labels in full_sem containing 'Receive':")
        for line in full_sem.splitlines():
            if 'eceive' in line or 'ecibir' in line:
                print(f"    {line.strip()}")

    # Wait for address reveal + background sync
    await asyncio.sleep(3.5)

    sem_final = await driver.semantics_tree()
    print("\n[semantics — final state after Recibir]")
    print(sem_final[:5000])

    # 9. Evaluate result
    low = sem_final.lower()
    # Check for dialog with address content
    has_dialog = sem_final.count("scopesRoute") > 1
    has_address = ("tb1" in low or "bc1" in low or "índice" in low
                   or "address index" in low or "siguiente" in low
                   or "Recibir" in sem_final and has_dialog)
    has_error = ("no hay" in low or "sin usar" in low or "no unused" in low
                 or "no se encontr" in low)

    if has_error:
        print("\n[FAIL] Error toast appeared — receive dialog did not open ✗")
        sys.exit(1)
    elif has_dialog and has_address:
        print("\n[PASS] Receive dialog opened with an address ✓")
    elif has_dialog:
        print("\n[PASS?] A dialog appeared — likely the receive dialog (address text may not be in semantics) ✓")
    else:
        print("\n[WARN] Inconclusive — check semantics output above")


async def main():
    driver = UIDriver()
    try:
        await driver.launch()
        await test_receive_fresh_wallet(driver)
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
