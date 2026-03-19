#!/usr/bin/env python3
"""
Debug script: opens drawer and dumps full semantics tree to understand
drawer item positions.
"""
import asyncio
import subprocess
import sys
import time
sys.path.insert(0, str(__import__('pathlib').Path(__file__).parent))
from ui_driver import UIDriver

CSD_X = 26   # left CSD offset (pixels)
CSD_Y = 61   # top CSD offset (pixels) — derived: (54,89) - (28,28) = (+26,+61)


def flutter_to_xdotool(fx: int, fy: int) -> tuple[int, int]:
    """Convert Flutter logical pixel to xdotool --window coordinate."""
    return fx + CSD_X, fy + CSD_Y


async def main():
    d = UIDriver()
    await d.launch()
    d.raise_window()
    await asyncio.sleep(1.0)

    # Open drawer: Flutter hamburger center (28, 28) → xdotool (54, 89)
    print("Opening drawer...")
    subprocess.run(["xdotool", "windowactivate", "--sync", str(d.window_id)])
    time.sleep(0.3)
    hx, hy = flutter_to_xdotool(28, 28)
    subprocess.run([
        "xdotool",
        "mousemove", "--window", str(d.window_id), str(hx), str(hy),
        "click", "1"
    ])
    await asyncio.sleep(1.5)

    print("\n=== FULL SEMANTICS TREE (drawer open) ===")
    sem = await d.semantics_tree()
    print(sem)
    print("=== END ===")

    await d.close()


if __name__ == "__main__":
    asyncio.run(main())
