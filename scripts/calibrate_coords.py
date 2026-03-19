#!/usr/bin/env python3
"""
Calibration script to find the CSD offset between xdotool window coords
and Flutter logical pixel coords.
"""
import asyncio
import subprocess
import sys
import time
sys.path.insert(0, str(__import__('pathlib').Path(__file__).parent))
from ui_driver import UIDriver


async def main():
    d = UIDriver()
    await d.launch()
    d.raise_window()
    await asyncio.sleep(1.0)

    geom = d.window_geometry()
    print(f"xdotool window geometry: {geom}")

    # Hamburger is at Flutter logical (8,8,48,48), center=(28,28)
    # Test various xdotool positions to find which one opens the drawer
    candidates = [
        (28, 28),   # no offset
        (54, 66),   # left+26, top+38
        (54, 89),   # left+26, top+61
        (54, 127),  # left+26, top+99
        (28, 66),   # no left, top+38
        (28, 89),   # no left, top+61
        (28, 137),  # no left, top+109
    ]

    for (cx, cy) in candidates:
        print(f"\n--- Testing click at xdotool ({cx}, {cy}) ---")
        # Activate window first
        subprocess.run([
            "xdotool", "windowactivate", "--sync", str(d.window_id)
        ])
        time.sleep(0.3)
        subprocess.run([
            "xdotool",
            "mousemove", "--window", str(d.window_id), str(cx), str(cy),
            "click", "1"
        ])
        await asyncio.sleep(1.5)

        sem = await d.semantics_tree()
        items = [l.strip() for l in sem.splitlines() if 'label:' in l or 'tooltip:' in l]
        drawer_opened = any('"Wallet"' in s or '"Designer"' in s for s in items)
        print(f"  Semantics items: {items[:8]}")
        print(f"  Drawer opened: {drawer_opened}")

        if drawer_opened:
            print(f"\n>>> CORRECT OFFSET: click at xdotool ({cx}, {cy}) opens drawer")
            print(f"    Flutter (28,28) -> xdotool ({cx},{cy})")
            print(f"    CSD offset: left={cx-28}, top={cy-28}")
            # Click somewhere to close drawer
            d.key("Escape")
            await asyncio.sleep(0.5)
            break

        # Press Escape to close any opened overlay
        d.key("Escape")
        await asyncio.sleep(0.5)

    await d.close()


if __name__ == "__main__":
    asyncio.run(main())
