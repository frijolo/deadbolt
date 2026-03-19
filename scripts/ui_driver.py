#!/usr/bin/env python3
"""
Deadbolt live UI test driver.

Launches the Flutter *debug* build, connects to its VM service, and allows
UI interaction via xdotool with full state inspection via the widget/semantics
tree.

Why debug mode (not profile/release):
  - Profile and release strip the debug dump extensions: debugDumpApp,
    debugDumpRenderTree, debugDumpSemanticsTree return empty strings.
  - Debug mode has the full VM service with working tree dumps and is still
    compiled as a native binary (not flutter run).

How the coordinate systems align:
  - xdotool `mousemove --window WID X Y` uses coords relative to the X11
    client-area top-left (below the title bar) of window WID.
  - Flutter's RenderBox.localToGlobal(Offset.zero) gives coords relative to
    the Flutter frame top-left, which is the same X11 client-area origin.
  - They match 1:1 so widget offsets from the tree can go directly to xdotool.
  - On Wayland+XWayland: launch with GDK_BACKEND=x11 so xdotool can see the
    window at all (native Wayland windows are invisible to X11 tools).

Usage:
  # Build first (once):
  flutter build linux --debug

  # Run smoke test (default):
  python3 scripts/ui_driver.py

  # Dump UI trees and exit:
  python3 scripts/ui_driver.py --inspect

  # Interactive REPL:
  python3 scripts/ui_driver.py --interactive

Prerequisites:
  pip3 install websockets   (or: sudo apt install python3-websockets)
"""

import argparse
import asyncio
import json
import os
import re
import subprocess
import sys
import time
from pathlib import Path

import websockets

# ---------------------------------------------------------------------------
# Config
# ---------------------------------------------------------------------------

PROJECT_ROOT = Path(__file__).resolve().parent.parent
# Debug mode: full VM service with working debugDump* extensions.
BUNDLE_DIR = PROJECT_ROOT / "build/linux/x64/debug/bundle"
APP_BIN = BUNDLE_DIR / "deadbolt"
LIB_DIR = BUNDLE_DIR / "lib"

DISPLAY = ":0"
WINDOW_TITLE = "deadbolt"  # GTK window title (set in linux/runner/my_application.cc)

# Flutter widget tree in debug mode can exceed 1 MB; allow up to 16 MB.
WS_MAX_SIZE = 16 * 1024 * 1024

# Client-side decoration (CSD) offset: on XWayland+GTK, the X11 window
# includes the GTK CSD title bar and border INSIDE its client area.
# The Flutter rendering canvas starts INSIDE this CSD frame.
# Detected empirically: on GNOME/Adwaita, Flutter(0,0) = xdotool(CSD_X, CSD_Y).
# Re-run scripts/calibrate_coords.py if you change your GTK theme.
_CSD_X_DEFAULT = 26   # horizontal CSD offset (side border/shadow, added to both x and right)
_CSD_Y_DEFAULT = 61   # vertical CSD offset (title bar + top shadow)


# ---------------------------------------------------------------------------
# Driver
# ---------------------------------------------------------------------------

class UIDriver:
    """Controls the Deadbolt debug build via VM service + xdotool."""

    def __init__(self, csd_x: int = _CSD_X_DEFAULT, csd_y: int = _CSD_Y_DEFAULT):
        self.proc = None
        self.ws = None
        self.isolate_id = None
        self.window_id = None
        self._req_id = 0
        self.csd_x = csd_x   # Flutter-to-xdotool horizontal offset
        self.csd_y = csd_y   # Flutter-to-xdotool vertical offset

    # ------------------------------------------------------------------
    # Launch & connect
    # ------------------------------------------------------------------

    async def launch(self):
        """Check binary, launch app, connect to VM service, find window."""
        if not APP_BIN.exists():
            print("ERROR: debug build not found. Run: flutter build linux --debug")
            sys.exit(1)

        env = {
            **os.environ,
            "DISPLAY": DISPLAY,
            "LD_LIBRARY_PATH": str(LIB_DIR),
            # Force X11 backend so xdotool can find and interact with the window.
            # On Wayland+XWayland, without this GTK prefers native Wayland surfaces
            # which are invisible to xdotool (an X11-only tool).
            "GDK_BACKEND": "x11",
        }

        # Flutter Linux debug/profile binaries start VM service automatically;
        # port and auth token are random. We parse the URL from stdout.
        cmd = [str(APP_BIN)]
        print(f"[launch] {cmd[0]}")
        self.proc = subprocess.Popen(
            cmd,
            env=env,
            stdout=subprocess.PIPE,
            stderr=subprocess.STDOUT,
            text=True,
        )

        url = self._wait_for_vm_url(timeout=20)
        print(f"[launch] VM service: {url}")

        # WebSocket URL: http://host:port/TOKEN/ → ws://host:port/TOKEN/ws
        ws_url = url.rstrip("/") + "/ws"
        ws_url = ws_url.replace("http://", "ws://")
        print(f"[launch] WebSocket: {ws_url}")
        self.ws = await websockets.connect(ws_url, max_size=WS_MAX_SIZE)

        response = await self._rpc("getVM")
        isolates = response["result"].get("isolates", [])
        if not isolates:
            raise RuntimeError("No isolates found in VM")
        self.isolate_id = isolates[0]["id"]
        print(f"[launch] Isolate: {self.isolate_id}")

        # Wait for app window (GTK+XWayland takes a few seconds)
        print("[launch] Waiting for window...")
        for _ in range(60):
            self.window_id = self._find_window()
            if self.window_id:
                break
            time.sleep(0.3)

        if self.window_id:
            print(f"[launch] Window: {self.window_id} — {self.window_geometry()}")
        else:
            print("[launch] WARNING: window not found via xdotool")

        # Wait for Flutter to finish rendering the first frame
        await asyncio.sleep(2.0)

    def _wait_for_vm_url(self, timeout=20):
        deadline = time.time() + timeout
        while time.time() < deadline:
            if self.proc.poll() is not None:
                raise RuntimeError("App exited before VM service started")
            line = self.proc.stdout.readline()
            if not line:
                time.sleep(0.05)
                continue
            print(f"  [app] {line.rstrip()}")
            # Match: "The Dart VM service is listening on http://127.0.0.1:PORT/TOKEN=/"
            m = re.search(r"(http://[\d.]+:\d+/\S*)", line)
            if m:
                return m.group(1)
        raise TimeoutError("VM service URL not found within timeout")

    def _find_window(self):
        try:
            # Exact title match first
            out = subprocess.check_output(
                ["xdotool", "search", "--name", f"^{WINDOW_TITLE}$"],
                text=True, stderr=subprocess.DEVNULL,
            ).strip()
            ids = out.split()
            if ids:
                return ids[0]
            # Fallback: substring match
            out = subprocess.check_output(
                ["xdotool", "search", "--name", WINDOW_TITLE],
                text=True, stderr=subprocess.DEVNULL,
            ).strip()
            ids = out.split()
            return ids[0] if ids else None
        except Exception:
            return None

    def window_geometry(self):
        """Returns dict with x, y (screen position) and w, h (size in pixels)."""
        if not self.window_id:
            return None
        try:
            out = subprocess.check_output(
                ["xdotool", "getwindowgeometry", self.window_id], text=True
            )
            m = re.search(r"Position: (\d+),(\d+)", out)
            s = re.search(r"Geometry: (\d+)x(\d+)", out)
            if m and s:
                return {"x": int(m.group(1)), "y": int(m.group(2)),
                        "w": int(s.group(1)), "h": int(s.group(2))}
        except Exception:
            pass
        return None

    # ------------------------------------------------------------------
    # VM Service RPC helpers
    # ------------------------------------------------------------------

    async def _rpc(self, method, params=None):
        self._req_id += 1
        req_id = self._req_id
        payload = {"jsonrpc": "2.0", "id": req_id, "method": method}
        if params:
            payload["params"] = params
        await self.ws.send(json.dumps(payload))
        while True:
            raw = await asyncio.wait_for(self.ws.recv(), timeout=30)
            msg = json.loads(raw)
            if msg.get("id") == req_id:
                if "error" in msg:
                    raise RuntimeError(f"RPC error: {msg['error']}")
                return msg

    async def flutter_ext(self, ext_name, extra_params=None):
        params = {"isolateId": self.isolate_id}
        if extra_params:
            params.update(extra_params)
        return await self._rpc(f"ext.flutter.{ext_name}", params)

    # ------------------------------------------------------------------
    # UI inspection — require debug mode binary
    # ------------------------------------------------------------------

    async def widget_tree(self) -> str:
        """Full widget tree as text (~1.4 MB in debug mode).
        Use find_widgets() to search it instead of printing the whole thing."""
        r = await self.flutter_ext("debugDumpApp")
        return r.get("result", {}).get("data", "") or ""

    async def render_tree(self) -> str:
        """Render tree as text (RenderObjects with sizes and parent offsets)."""
        r = await self.flutter_ext("debugDumpRenderTree")
        return r.get("result", {}).get("data", "") or ""

    async def semantics_tree(self) -> str:
        """Semantics tree (only non-empty if accessibility services are active)."""
        r = await self.flutter_ext("debugDumpSemanticsTreeInTraversalOrder")
        return r.get("result", {}).get("data", "") or ""

    async def find_widgets(self, *keywords: str) -> list[str]:
        """
        Return lines from the widget tree that contain any of the keywords.
        Useful for asserting that a widget/screen/text is present.

        Example:
          lines = await driver.find_widgets("WalletListScreen", "NavigationBar")
        """
        tree = await self.widget_tree()
        results = []
        for line in tree.splitlines():
            if any(kw in line for kw in keywords):
                results.append(line.strip())
        return results

    async def assert_widget(self, keyword: str, msg: str = ""):
        """Assert that a widget/text exists in the current widget tree."""
        lines = await self.find_widgets(keyword)
        if not lines:
            raise AssertionError(
                f"Widget not found: '{keyword}'" + (f" — {msg}" if msg else "")
            )
        print(f"[assert] ✓ Found '{keyword}': {lines[0][:100]}")

    async def assert_no_widget(self, keyword: str, msg: str = ""):
        """Assert that a widget/text does NOT exist in the current widget tree."""
        lines = await self.find_widgets(keyword)
        if lines:
            raise AssertionError(
                f"Widget unexpectedly present: '{keyword}'" + (f" — {msg}" if msg else "")
            )
        print(f"[assert] ✓ Absent '{keyword}'")

    # ------------------------------------------------------------------
    # Semantic node helpers (precise coordinate-based clicking)
    # ------------------------------------------------------------------

    def _parse_semantics_rect_before(self, lines: list[str], target_line: int) -> tuple[int, int, int, int] | None:
        """
        Find the bounding rect for the semantics node that contains `target_line`,
        converted to global Flutter logical pixel coordinates.

        Flutter semantics dump format:
          Each SemanticsNode's rect is in its PARENT's coordinate space.
          Nodes are printed in pre-order; depth is indicated by the column position
          of 'SemanticsNode' in the line (deeper = further right).

        Algorithm:
          1. Scan backward from target_line to find the enclosing node's rect
             (child_rect) and the line with 'SemanticsNode#N' (child_node_line).
          2. Walk up the ancestor chain using COLUMN DEPTH to identify true parents
             (column < current column), collecting each ancestor's rect by scanning
             FORWARD from its header line to find its own rect property.
          3. Accumulate offsets: for each ancestor with non-zero origin, apply it.
             Skip ancestors at (0,0) origin — they're passthrough containers.
             Containment check validates each step; stop when check fails.
        """
        rect_re = re.compile(
            r"Rect\.fromLTRB\(([0-9.]+),\s*([0-9.]+),\s*([0-9.]+),\s*([0-9.]+)\)"
        )
        node_re = re.compile(r"SemanticsNode#\d+")

        def _parse(line):
            m = rect_re.search(line)
            return (int(float(m.group(1))), int(float(m.group(2))),
                    int(float(m.group(3))), int(float(m.group(4)))) if m else None

        def _node_col(idx: int) -> int:
            """Column (char offset) of 'SemanticsNode' in lines[idx], or -1."""
            m = node_re.search(lines[idx])
            return m.start() if m else -1

        def _node_rect(node_idx: int):
            """Find the rect in the few lines AFTER the node header at node_idx."""
            for k in range(node_idx + 1, min(len(lines), node_idx + 20)):
                if node_re.search(lines[k]):
                    break  # Hit a child node — stop
                r = _parse(lines[k])
                if r is not None:
                    return r
            return None

        def _parent_of(node_idx: int):
            """Line index of the parent node (first ancestor with strictly lower column)."""
            my_col = _node_col(node_idx)
            if my_col < 0:
                return None
            for k in range(node_idx - 1, max(0, node_idx - 2000), -1):
                if node_re.search(lines[k]):
                    c = _node_col(k)
                    if c < my_col:
                        return k
            return None

        # ── Step 1: find the enclosing node's local rect ────────────────────────
        child_rect = None
        child_node_line = None
        for j in range(target_line - 1, max(0, target_line - 30), -1):
            if node_re.search(lines[j]):
                child_node_line = j
                break
            r = _parse(lines[j])
            if r is not None and child_rect is None:
                child_rect = r

        if child_rect is None:
            return None
        if child_node_line is None:
            # Node header not found in backward window — return local rect as-is
            return child_rect

        # ── Step 2: walk up ancestors, accumulating global offset ───────────────
        current_rect = child_rect
        current_node_line = child_node_line

        for _ in range(15):  # max ancestor depth
            parent_node_line = _parent_of(current_node_line)
            if parent_node_line is None:
                break  # Reached the root

            parent_rect = _node_rect(parent_node_line)

            if parent_rect is None:
                # No rect for this ancestor (transparent container)
                current_node_line = parent_node_line
                continue

            if parent_rect[0] == 0 and parent_rect[1] == 0:
                # Parent at (0,0) — adding it is a no-op; keep going up
                current_node_line = parent_node_line
                continue

            # Parent has a non-zero origin — try to apply it as offset
            global_rect = (
                parent_rect[0] + current_rect[0],
                parent_rect[1] + current_rect[1],
                parent_rect[0] + current_rect[2],
                parent_rect[1] + current_rect[3],
            )
            # Containment check: parent must contain its child
            if (global_rect[0] >= parent_rect[0] and
                    global_rect[1] >= parent_rect[1] and
                    global_rect[2] <= parent_rect[2] and
                    global_rect[3] <= parent_rect[3]):
                current_rect = global_rect
                current_node_line = parent_node_line
            else:
                # Containment failed → current_rect is already in global space
                break

        return current_rect

    async def find_semantic_rect(self, label: str) -> tuple[int, int, int, int] | None:
        """
        Find a semantic node by label and return its rect (left, top, right, bottom)
        in Flutter logical pixels.

        The semantics tree is populated automatically when you call
        debugDumpSemanticsTreeInTraversalOrder in debug mode.

        Coordinate note:
          Semantic coords are in logical pixels relative to the Flutter frame origin.
          xdotool --window coords are in physical pixels relative to the X11 client area.
          On a 1.0x DPI display they match 1:1.
          On HiDPI, multiply by devicePixelRatio (check RenderView in render tree).
        """
        tree = await self.semantics_tree()
        lines = tree.splitlines()
        for i, line in enumerate(lines):
            if f'label: "{label}"' in line:
                return self._parse_semantics_rect_before(lines, i)
        # Multi-line label: "label:" appears on its own line (possibly with box-drawing
        # prefix like "│   │ label:") and the text follows on the next line(s).
        # e.g.  "│   │ label:\n│   │   "First line\n│   │   Second line""
        # We cannot use stripped == 'label:' because strip() only removes whitespace,
        # not the Unicode box-drawing characters (│, ├, └) that Flutter uses.
        for i, line in enumerate(lines):
            if 'label:' in line and '"' not in line:
                # Check next few lines for label text
                for k in range(i + 1, min(len(lines), i + 6)):
                    if f'"{label}"' in lines[k] or label in lines[k]:
                        return self._parse_semantics_rect_before(lines, i)
        return None

    async def find_semantic_rect_by_tooltip(self, tooltip: str) -> tuple[int, int, int, int] | None:
        """Find a semantic node by tooltip text and return its rect."""
        tree = await self.semantics_tree()
        lines = tree.splitlines()
        for i, line in enumerate(lines):
            if f'tooltip: "{tooltip}"' in line:
                return self._parse_semantics_rect_before(lines, i)
        return None

    async def click_semantic(self, label: str, tooltip: str = ""):
        """
        Click the center of a semantic node identified by label or tooltip.
        Coordinates are Flutter logical pixels → converted to xdotool via CSD offset.
        Falls back to a warning if the node is not found.
        """
        rect = None
        if label:
            rect = await self.find_semantic_rect(label)
        if rect is None and tooltip:
            rect = await self.find_semantic_rect_by_tooltip(tooltip)
        if rect is None:
            print(f"[click_semantic] WARNING: node not found: label='{label}' tooltip='{tooltip}'")
            return
        cx = (rect[0] + rect[2]) // 2
        cy = (rect[1] + rect[3]) // 2
        print(f"[click_semantic] '{label or tooltip}' flutter ({cx}, {cy}) → xdotool ({cx+self.csd_x}, {cy+self.csd_y})")
        self.flutter_click(cx, cy)

    # ------------------------------------------------------------------
    # Coordinate helpers
    # ------------------------------------------------------------------

    def window_center(self):
        """(x, y) center of the window in window-relative pixel coords."""
        g = self.window_geometry()
        return (g["w"] // 2, g["h"] // 2) if g else (400, 300)

    def pct(self, x_pct: float, y_pct: float):
        """Convert fractional window position (0.0–1.0) to pixel coords.
        (0.5, 0.5) = center, (0.0, 0.0) = top-left, (1.0, 1.0) = bottom-right."""
        g = self.window_geometry()
        if g:
            return int(g["w"] * x_pct), int(g["h"] * y_pct)
        return (400, 300)

    # ------------------------------------------------------------------
    # xdotool interaction
    # ------------------------------------------------------------------

    def flutter_click(self, fx: int, fy: int, button: int = 1, delay_s: float = 0.15):
        """
        Click at Flutter logical pixel coordinates (fx, fy).
        Automatically applies the CSD offset to convert to xdotool window coords.
        Use this when coordinates come from the semantics/widget tree.
        """
        self.click(fx + self.csd_x, fy + self.csd_y, button=button, delay_s=delay_s)

    def click(self, x: int, y: int, button: int = 1, delay_s: float = 0.15):
        """
        Click at (x, y) relative to the Flutter window's X11 client area.

        Coordinate system:
          - (0, 0) = top-left of the Flutter rendering surface (below title bar)
          - Matches Flutter RenderBox.localToGlobal(Offset.zero) coords exactly
          - Uses xdotool --window so coords are window-relative (not screen-absolute)
        """
        if not self.window_id:
            print(f"[click] WARNING: no window — using screen-absolute ({x}, {y})")
            subprocess.run(["xdotool", "mousemove", str(x), str(y), "click", str(button)])
        else:
            subprocess.run([
                "xdotool",
                "mousemove", "--window", self.window_id, str(x), str(y),
                "click", str(button),
            ])
        time.sleep(delay_s)

    def type_text(self, text: str, delay_ms: int = 50):
        """Type text at the current focus location."""
        subprocess.run(["xdotool", "type", "--clearmodifiers",
                        "--delay", str(delay_ms), text])

    def key(self, key_name: str):
        """Press a key by X11 keysym, e.g. 'Return', 'ctrl+a', 'Escape'."""
        subprocess.run(["xdotool", "key", "--clearmodifiers", key_name])

    def raise_window(self):
        """Bring window to front and focus it."""
        if self.window_id:
            subprocess.run(["xdotool", "windowraise", self.window_id])
            subprocess.run(["xdotool", "windowfocus", self.window_id])

    # ------------------------------------------------------------------
    # Teardown
    # ------------------------------------------------------------------

    async def close(self):
        if self.ws:
            try:
                await self.ws.close()
            except Exception:
                pass
        if self.proc:
            self.proc.terminate()
            try:
                self.proc.wait(timeout=5)
            except subprocess.TimeoutExpired:
                self.proc.kill()


# ---------------------------------------------------------------------------
# Test scenarios
# ---------------------------------------------------------------------------

async def test_smoke(driver: UIDriver):
    """
    Smoke test:
    1. Verify app starts on WalletListScreen.
    2. Open hamburger navigation drawer by clicking its semantic node.
    3. Click the Projects tab via semantic label.
    4. Verify ProjectListScreen appears in the widget tree.
    5. Navigate back to Wallets.
    """
    print("\n=== SMOKE TEST ===")
    driver.raise_window()
    await asyncio.sleep(0.5)

    g = driver.window_geometry()
    print(f"[geometry] {g}")

    # 1. Verify we start on the Wallets screen
    await driver.assert_widget("WalletListScreen", "app starts on Wallets screen")

    # 2. Open the navigation drawer (hamburger menu in mobile layout)
    print("[click] Opening navigation drawer via hamburger...")
    await driver.click_semantic("", tooltip="Open navigation menu")
    await asyncio.sleep(0.6)

    # 3. Click "Designer" (index 1) drawer item — items are at fixed Flutter coords
    #    Drawer is now open; Designer center = Flutter(152,130) → flutter_click applies CSD
    print("[click] Clicking Designer (index 1) in drawer...")
    driver.flutter_click(152, 130)   # Designer: DRAWER_ITEM_FY0=74 + 1*56=130
    await asyncio.sleep(0.8)

    # 4. Verify ProjectListScreen is now shown via AppBar title in semantics
    await driver.assert_widget("ProjectListScreen", "navigated to Projects screen")

    # 5. Go back to Wallets via drawer — Wallet is index 0, center Flutter(152,74)
    print("[click] Navigating back to Wallets...")
    await driver.click_semantic("", tooltip="Open navigation menu")
    await asyncio.sleep(1.5)
    driver.flutter_click(152, 74)   # Wallet: DRAWER_ITEM_FY0=74
    await asyncio.sleep(0.8)
    await driver.assert_widget("WalletListScreen", "navigated back to Wallets screen")

    print("\n[result] Smoke test PASSED ✓")


async def run_inspect(driver: UIDriver):
    """Dump useful UI info and exit."""
    g = driver.window_geometry()
    print(f"\n=== WINDOW GEOMETRY ===\n{g}")

    print("\n=== WIDGET TREE (searching for screen/navigation widgets) ===")
    lines = await driver.find_widgets(
        "Screen", "NavigationBar", "NavigationRail", "Cubit",
        "AppScaffold", "MaterialApp",
    )
    for line in lines[:40]:
        print(f"  {line}")

    print("\n=== SEMANTICS TREE ===")
    sem = await driver.semantics_tree()
    if sem and len(sem) > 5:
        print(sem[:3000])
    else:
        print("(empty — enable a screen reader to populate the semantics tree)")


async def run_interactive(driver: UIDriver):
    """Simple REPL for manual experiments with the running app."""
    print("\n=== INTERACTIVE MODE ===")
    print("Commands:")
    print("  click X Y       — click at window-relative coords")
    print("  pct X% Y%       — click at fractional position (e.g. pct 0.5 0.9)")
    print("  type TEXT       — type text at current focus")
    print("  key KEYSYM      — press key (e.g. Return, Escape, ctrl+a)")
    print("  find KEYWORD    — search widget tree for keyword")
    print("  assert KEYWORD  — assert widget present")
    print("  geom            — print window geometry")
    print("  semantics       — dump semantics tree")
    print("  quit            — exit")

    while True:
        try:
            line = input("\ndriver> ").strip()
        except (EOFError, KeyboardInterrupt):
            break
        if not line:
            continue
        parts = line.split(None, 2)
        cmd = parts[0].lower()

        if cmd == "quit":
            break
        elif cmd == "click" and len(parts) >= 3:
            driver.click(int(parts[1]), int(parts[2]))
            print("clicked")
        elif cmd == "pct" and len(parts) >= 3:
            x, y = driver.pct(float(parts[1]), float(parts[2]))
            print(f"clicking at ({x}, {y})")
            driver.click(x, y)
        elif cmd == "type" and len(parts) >= 2:
            driver.type_text(parts[1])
        elif cmd == "key" and len(parts) >= 2:
            driver.key(parts[1])
        elif cmd == "find" and len(parts) >= 2:
            results = await driver.find_widgets(parts[1])
            print(f"Found {len(results)} lines:")
            for r in results[:20]:
                print(f"  {r[:120]}")
        elif cmd == "assert" and len(parts) >= 2:
            try:
                await driver.assert_widget(parts[1])
            except AssertionError as e:
                print(f"FAIL: {e}")
        elif cmd == "geom":
            print(driver.window_geometry())
        elif cmd == "semantics":
            sem = await driver.semantics_tree()
            print(sem[:3000] if sem else "(empty)")
        else:
            print(f"Unknown command: {cmd}")


# ---------------------------------------------------------------------------
# Entry point
# ---------------------------------------------------------------------------

async def main():
    parser = argparse.ArgumentParser(description="Deadbolt live UI test driver")
    parser.add_argument("--inspect", action="store_true",
                        help="Dump UI trees and exit")
    parser.add_argument("--interactive", action="store_true",
                        help="Interactive REPL instead of running tests")
    args = parser.parse_args()

    driver = UIDriver()
    try:
        await driver.launch()

        if args.inspect:
            await run_inspect(driver)
        elif args.interactive:
            await run_interactive(driver)
        else:
            await test_smoke(driver)

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
