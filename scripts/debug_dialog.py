#!/usr/bin/env python3
"""Debug: open project list → open new project dialog → dump semantics."""
import asyncio, subprocess, sys, time
sys.path.insert(0, str(__import__('pathlib').Path(__file__).parent))
from ui_driver import UIDriver

DRAWER_FX = 152
DRAWER_FY0 = 74
DRAWER_ITEM_H = 56

async def main():
    d = UIDriver()
    await d.launch()
    d.raise_window()
    await asyncio.sleep(0.5)

    # Navigate to Designer (index 1)
    await d.click_semantic("", tooltip="Open navigation menu")
    await asyncio.sleep(1.5)
    d.flutter_click(DRAWER_FX, DRAWER_FY0 + 1 * DRAWER_ITEM_H)  # Designer
    await asyncio.sleep(1.0)

    # Open "Show menu" popup → "New"
    rect = await d.find_semantic_rect_by_tooltip("Show menu")
    print(f"'Show menu' rect: {rect}")
    if rect:
        trigger_bottom = rect[3]
        trigger_cx = (rect[0] + rect[2]) // 2
        # Click the trigger button
        d.flutter_click(trigger_cx, (rect[1]+rect[3])//2, delay_s=0.5)
        await asyncio.sleep(0.5)
        # Click first popup item ("New" at ~24px from button bottom)
        item_y = trigger_bottom + 24
        print(f"Clicking popup item at flutter ({trigger_cx}, {item_y})")
        d.flutter_click(trigger_cx, int(item_y))
        await asyncio.sleep(1.0)

    print("\n=== DIALOG SEMANTICS ===")
    sem = await d.semantics_tree()
    print(sem)
    print("=== END ===")

    await d.close()

asyncio.run(main())
