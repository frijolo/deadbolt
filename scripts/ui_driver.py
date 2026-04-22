#!/usr/bin/env python3
"""
Deadbolt live UI test driver.

Launches the Flutter *debug* build, connects to its VM service, and allows
UI interaction via xdotool (XTEST) with full state inspection via the
widget/semantics tree.

Why debug mode (not profile/release):
  - Profile and release strip the debug dump extensions: debugDumpApp,
    debugDumpRenderTree, debugDumpSemanticsTree return empty strings.
  - Debug mode has the full VM service with working tree dumps and is still
    compiled as a native binary (not flutter run).

How the coordinate systems align:
  - xdotool injects events into the X11 window at screen-absolute coordinates.
  - Flutter's render canvas starts at (csd_x, csd_y) inside the GTK window
    (Client-Side Decoration offset on GNOME/Adwaita).
  - So: screen_abs = window_screen_pos + (csd_x, csd_y) + flutter_pos.
  - On Wayland+XWayland: launch with GDK_BACKEND=x11 so the window is an
    X11 window that xdotool can find.

Usage:
  # Build first (once — applies debug overlay + Rust release .so):
  bash scripts/prepare_test_build.sh

  # Run smoke test (default):
  python3 scripts/ui_driver.py

  # Dump UI trees and exit:
  python3 scripts/ui_driver.py --inspect

  # Interactive REPL:
  python3 scripts/ui_driver.py --interactive

Prerequisites:
  pip3 install websockets
  sudo apt install xdotool
"""

import argparse
import asyncio
import json
import os
import re
import shutil
import subprocess
import sys
import time
from pathlib import Path

import threading

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

# Sandbox: isolated XDG dirs so the app always starts empty.
#
#   XDG_DATA_HOME    → getApplicationSupportDirectory()  → wallets/, prefs, etc.
#   XDG_DOCUMENTS_DIR (via xdg-user-dir) → getApplicationDocumentsDirectory() → deadbolt.sqlite
#
# path_provider_linux calls the `xdg-user-dir DOCUMENTS` *binary*, which reads
# $XDG_CONFIG_HOME/user-dirs.dirs (not the XDG_DOCUMENTS_DIR env var directly).
# So we create a minimal user-dirs.dirs in the sandbox config dir and point
# XDG_CONFIG_HOME at it.
SANDBOX_DIR = Path("/tmp/deadbolt_test_sandbox")
SANDBOX_DATA_DIR = SANDBOX_DIR / "data"
SANDBOX_DOCUMENTS_DIR = SANDBOX_DIR / "documents"
SANDBOX_CONFIG_DIR = SANDBOX_DIR / "config"

# Flutter widget tree in debug mode can exceed 1 MB; allow up to 16 MB.
WS_MAX_SIZE = 16 * 1024 * 1024

# Client-side decoration (CSD) offset: on XWayland+GTK, the X11 window
# includes the GTK CSD title bar and border INSIDE its client area.
# The Flutter rendering canvas starts INSIDE this CSD frame.
# Detected empirically: on GNOME/Adwaita, Flutter(0,0) = xdotool(CSD_X, CSD_Y).
# Re-run scripts/calibrate_coords.py if you change your GTK theme.
_CSD_X_DEFAULT = 26   # horizontal CSD offset (GTK title bar on GNOME/Adwaita — fallback default)
_CSD_Y_DEFAULT = 70   # vertical CSD offset   (GTK title bar on GNOME/Adwaita — fallback default)

# Calibration file: written by scripts/calibrate.py, read at launch to skip
# live calibration during normal test runs.  Gitignored.
_CALIB_FILE = PROJECT_ROOT / "scripts" / ".calib"

# ---------------------------------------------------------------------------
# Mouse overlay patch
#
# The overlay widget is NOT committed to the repository (security: it logs all
# pointer coordinates to stdout). Instead, UIDriver writes it to disk and
# patches main.dart before building the debug binary, then reverts everything
# on shutdown.
# ---------------------------------------------------------------------------

_OVERLAY_DART_FILE = PROJECT_ROOT / "lib/widgets/debug_mouse_overlay.dart"
_MAIN_DART_FILE    = PROJECT_ROOT / "lib/main.dart"

# Markers used to locate the injection points in main.dart.
# Must stay in sync with the app_scaffold import line and themeMode line.
_PATCH_IMPORT_MARKER  = "import 'package:deadbolt/widgets/app_scaffold.dart';"
_PATCH_BUILDER_MARKER = "            themeMode: AppThemeManager.getThemeMode(settings.appTheme),"

# What to inject at each marker (replaces the marker line itself).
_PATCH_IMPORT_INJECT = """\
import 'package:deadbolt/widgets/app_scaffold.dart';
import 'dart:io';
import 'package:deadbolt/widgets/debug_mouse_overlay.dart';

// Injected by ui_driver for testing — not committed to the repository.
final bool _debugMouseEnabled =
    Platform.environment['DEADBOLT_DEBUG_MOUSE'] == '1';\
"""

_PATCH_BUILDER_INJECT = """\
            themeMode: AppThemeManager.getThemeMode(settings.appTheme),
            // Injected by ui_driver — reverted after test.
            builder: (context, child) => DebugMouseOverlay(
                showCrosshair: _debugMouseEnabled,
                child: child ?? const SizedBox()),\
"""

# Full source of the overlay widget (written to disk at test time, never committed).
_OVERLAY_DART_CODE = r"""
import 'package:flutter/material.dart';

/// Injected by ui_driver for pointer-position logging and optional crosshair.
/// Written before building and removed on shutdown — never committed to the repo.
class DebugMouseOverlay extends StatefulWidget {
  final Widget child;
  final bool showCrosshair;
  const DebugMouseOverlay({super.key, required this.child, this.showCrosshair = true});

  @override
  State<DebugMouseOverlay> createState() => _DebugMouseOverlayState();
}

class _DebugMouseOverlayState extends State<DebugMouseOverlay> {
  Offset? _pos;
  Offset? _lastPrinted;

  void _update(Offset pos, {bool forceLog = false}) {
    setState(() => _pos = pos);
    final last = _lastPrinted;
    final moved = last == null || (pos - last).distance > 4.0;
    if (forceLog || moved) {
      debugPrint('[mouse] (${pos.dx.round()}, ${pos.dy.round()})');
      _lastPrinted = pos;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        Listener(
          behavior: HitTestBehavior.translucent,
          onPointerHover: (e) => _update(e.localPosition),
          onPointerDown: (e) {
            _update(e.localPosition, forceLog: true);
            debugPrint('[mouse] DOWN (${e.localPosition.dx.round()}, ${e.localPosition.dy.round()})');
          },
          onPointerUp: (e) =>
              debugPrint('[mouse] UP   (${e.localPosition.dx.round()}, ${e.localPosition.dy.round()})'),
          onPointerMove: (e) => _update(e.localPosition),
          child: widget.child,
        ),
        if (_pos != null && widget.showCrosshair)
          Positioned.fill(
            child: IgnorePointer(
              child: CustomPaint(painter: _CrosshairPainter(_pos!)),
            ),
          ),
      ],
    );
  }
}

class _CrosshairPainter extends CustomPainter {
  final Offset pos;
  _CrosshairPainter(this.pos);

  @override
  void paint(Canvas canvas, Size size) {
    final circle = Paint()
      ..color = Colors.red.withAlpha(180)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.5;
    final fill = Paint()
      ..color = Colors.red.withAlpha(60)
      ..style = PaintingStyle.fill;
    const r = 14.0;
    canvas.drawCircle(pos, r, fill);
    canvas.drawCircle(pos, r, circle);
    final line = Paint()
      ..color = Colors.red.withAlpha(200)
      ..strokeWidth = 1.5;
    canvas.drawLine(pos.translate(-r - 6, 0), pos.translate(r + 6, 0), line);
    canvas.drawLine(pos.translate(0, -r - 6), pos.translate(0, r + 6), line);
    final tp = TextPainter(
      text: TextSpan(
        text: '(${pos.dx.round()}, ${pos.dy.round()})',
        style: const TextStyle(
          color: Colors.red,
          fontSize: 11,
          fontWeight: FontWeight.bold,
          backgroundColor: Color(0xCCFFFFFF),
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    tp.paint(canvas, pos.translate(r + 4, -tp.height / 2));
  }

  @override
  bool shouldRepaint(_CrosshairPainter old) => old.pos != pos;
}
""".lstrip()




# ---------------------------------------------------------------------------
# Driver
# ---------------------------------------------------------------------------

def _reset_sandbox():
    """Wipe and recreate the sandbox directories so the app starts empty."""
    if SANDBOX_DIR.exists():
        shutil.rmtree(SANDBOX_DIR)
    SANDBOX_DATA_DIR.mkdir(parents=True)
    SANDBOX_DOCUMENTS_DIR.mkdir(parents=True)
    SANDBOX_CONFIG_DIR.mkdir(parents=True)

    # path_provider_linux resolves getApplicationDocumentsDirectory() by running
    # `xdg-user-dir DOCUMENTS`, which reads $XDG_CONFIG_HOME/user-dirs.dirs.
    # Writing a minimal file here redirects that call to our sandbox directory.
    user_dirs = SANDBOX_CONFIG_DIR / "user-dirs.dirs"
    user_dirs.write_text(
        f'XDG_DOCUMENTS_DIR="{SANDBOX_DOCUMENTS_DIR}"\n'
    )
    print(f"[sandbox] Reset: {SANDBOX_DIR}")


class UIDriver:
    """Controls the Deadbolt debug build via VM service + xdotool (XTEST)."""

    def __init__(self, csd_x: int = _CSD_X_DEFAULT, csd_y: int = _CSD_Y_DEFAULT,
                 sandbox: bool = True, debug_mouse: bool = False):
        self.proc = None          # Flutter app process
        self.ws = None            # VM service WebSocket
        self.isolate_id = None
        self.window_id = None     # X11 window ID (decimal string)
        self._req_id = 0
        self.csd_x = csd_x       # Flutter→screen horizontal offset (GTK CSD title bar)
        self.csd_y = csd_y       # Flutter→screen vertical offset (GTK CSD title bar)
        self.sandbox = sandbox    # True: always start with empty app data
        self.debug_mouse = debug_mouse  # True: enable DEADBOLT_DEBUG_MOUSE crosshair overlay

    # ------------------------------------------------------------------
    # Launch & connect
    # ------------------------------------------------------------------

    async def launch(self):
        """Launch app, connect to VM service, find window.

        Prerequisites: the debug binary must already be built with the mouse
        overlay applied.  See scripts/debug_overlay_setup.sh for instructions.
        Run that script once before running any UI test; revert it when done.
        """

        if self.sandbox:
            _reset_sandbox()

        env = {
            **os.environ,
            "DISPLAY": DISPLAY,
            "LD_LIBRARY_PATH": str(LIB_DIR),
            # Force X11 backend so xdotool can find and interact with the window.
            # On Wayland+XWayland, without this GTK prefers native Wayland surfaces
            # which are invisible to xdotool (an X11-only tool).
            "GDK_BACKEND": "x11",
            # Enable the visual crosshair overlay when requested.
            "DEADBOLT_DEBUG_MOUSE": "1" if self.debug_mouse else "0",
            # Disable XIM/IBus input method to prevent compose-sequence interference
            # when injecting key events via xdotool.  Without this, IBus can buffer
            # characters and "commit" them in a way that clears the text field.
            "XMODIFIERS": "@im=none",
            "GTK_IM_MODULE": "none",
            "QT_IM_MODULE": "none",
        }

        if self.sandbox:
            # Redirect app data to the isolated sandbox so the app starts empty.
            env["XDG_DATA_HOME"] = str(SANDBOX_DATA_DIR)
            # XDG_CONFIG_HOME makes xdg-user-dir read our custom user-dirs.dirs,
            # which redirects getApplicationDocumentsDirectory() (drift DB) to sandbox.
            env["XDG_CONFIG_HOME"] = str(SANDBOX_CONFIG_DIR)

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

        # Drain remaining app output in background thread so the pipe doesn't block.
        # Crash-related lines (FATAL, Exception) are printed immediately.
        import threading
        self._app_log: list[str] = []
        def _drain():
            for line in self.proc.stdout:
                stripped = line.rstrip()
                self._app_log.append(stripped)
                if any(k in stripped for k in ("[FATAL", "Unhandled exception", "flutter:", "Error:", "[mouse]")):
                    print(f"  [app] {stripped}")
        threading.Thread(target=_drain, daemon=True).start()

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

        # Load calibrated CSD values if available; otherwise use defaults.
        # Run scripts/calibrate.py once to produce the .calib file.
        if _CALIB_FILE.exists():
            for line in _CALIB_FILE.read_text().splitlines():
                if '=' in line:
                    k, v = line.split('=', 1)
                    if k.strip() == 'CSD_X':
                        self.csd_x = int(v.strip())
                    elif k.strip() == 'CSD_Y':
                        self.csd_y = int(v.strip())
            print(f"[calib] Loaded from .calib: CSD_X={self.csd_x}, CSD_Y={self.csd_y}")
        else:
            print(f"[calib] No .calib file — using defaults CSD_X={self.csd_x}, CSD_Y={self.csd_y}")
            print("[calib]   Run 'python3 scripts/calibrate.py' to generate it.")

        # Auto-calibrate only when no .calib file is present.
        # The .calib file stores the GTK CSD decoration offset (title bar height,
        # border width) which is stable per desktop theme.  Auto-calibrating while
        # the beta disclaimer dialog is open produces wrong values because the
        # pointer event's localPosition is relative to the dialog widget, not the
        # window root.  Trust .calib when it exists; run calibrate.py to regenerate.
        if not _CALIB_FILE.exists():
            await self.calibrate()

    async def calibrate(self):
        """Auto-calibrate CSD_X/CSD_Y by clicking at the window center and
        reading the Flutter-reported pointer coordinates from [mouse] output.

        DEADBOLT_MOUSE_LOG=1 must be active (always set by UIDriver.launch).
        The calibration click lands somewhere in the app body; it may trigger
        UI events (e.g. dismiss a dialog) but that is acceptable — the demo
        scripts handle UI state explicitly.
        """
        g = self.window_geometry()
        if g is None:
            print("[calib] WARNING: window not ready, skipping calibration")
            return

        abs_x = g["x"] + g["w"] // 2
        abs_y = g["y"] + g["h"] // 2

        log_before = len(self._app_log)
        # Use xdotool (XTEST) for calibration.
        env = {**os.environ, "DISPLAY": DISPLAY}
        subprocess.run(
            ["xdotool", "mousemove", "--sync", str(abs_x), str(abs_y)],
            env=env, stderr=subprocess.DEVNULL,
        )
        time.sleep(0.04)
        subprocess.run(["xdotool", "click", "1"], env=env, stderr=subprocess.DEVNULL)
        await asyncio.sleep(0.4)

        new_lines = self._app_log[log_before:]
        for line in reversed(new_lines):
            m = re.search(r'\[mouse\] DOWN \((\d+), (\d+)\)', line)
            if m:
                fx, fy = int(m.group(1)), int(m.group(2))
                new_csd_x = abs_x - g["x"] - fx
                new_csd_y = abs_y - g["y"] - fy
                print(f"[calib] abs({abs_x},{abs_y}) → Flutter({fx},{fy})"
                      f" → CSD_X={new_csd_x}, CSD_Y={new_csd_y}")
                self.csd_x = new_csd_x
                self.csd_y = new_csd_y
                return

        print(f"[calib] WARNING: no [mouse] DOWN received; "
              f"keeping defaults CSD_X={self.csd_x}, CSD_Y={self.csd_y}")

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

    def _xdotool(self, *args, **kw):
        """Run xdotool with DISPLAY set so it works even when inherited env lacks it."""
        env = {**os.environ, "DISPLAY": DISPLAY}
        return subprocess.check_output(
            ["xdotool", *args], env=env, text=True,
            stderr=kw.get("stderr", subprocess.DEVNULL),
        )

    def _find_window(self):
        try:
            # Exact title match first
            out = self._xdotool("search", "--name", f"^{WINDOW_TITLE}$").strip()
            ids = out.split()
            if ids:
                return ids[0]
            # Fallback: substring match
            out = self._xdotool("search", "--name", WINDOW_TITLE).strip()
            ids = out.split()
            return ids[0] if ids else None
        except Exception:
            return None

    def window_geometry(self):
        """Returns dict with x, y (screen position) and w, h (size in pixels)."""
        if not self.window_id:
            return None
        try:
            out = self._xdotool("getwindowgeometry", self.window_id)
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

    async def deadbolt_ext(self, ext_name, extra_params=None):
        params = {"isolateId": self.isolate_id}
        if extra_params:
            params.update(extra_params)
        return await self._rpc(f"ext.deadbolt.{ext_name}", params)

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
    # Structured semantics (ext.deadbolt.semanticsJson) — cs_* methods
    #
    # These require a test build compiled with registerSemanticsJsonExtension()
    # (injected by debug_overlay_setup.sh).  Each node in the returned list is:
    #   { id, label, tooltip, hint, value, flags: [str,...],
    #     rect: [l,t,r,b], globalRect: [l,t,r,b] }
    # globalRect is in Flutter logical pixels relative to the canvas origin,
    # exactly like the coordinates returned by the text-based find_* methods.
    # ------------------------------------------------------------------

    async def cs_tree(self) -> list[dict]:
        """Fetch the full semantics tree as a flat list of structured nodes."""
        r = await self.deadbolt_ext("semanticsJson")
        return r.get("result", {}).get("nodes", [])

    async def cs_tree_as_json(self) -> str:
        """Fetch the full semantics tree as a flat list of structured nodes. JSON formatted."""
        data = await self.cs_tree()
        return json.dumps(data, sort_keys=True, indent=2)

    def _cs_rect(self, node: dict) -> tuple[int, int, int, int] | None:
        gr = node.get("globalRect")
        if gr is None:
            return None
        return (int(gr[0]), int(gr[1]), int(gr[2]), int(gr[3]))

    async def cs_find_by_label(self, label: str) -> tuple[int, int, int, int] | None:
        """Return the globalRect of the first node whose label exactly matches."""
        for node in await self.cs_tree():
            if node.get("label") == label:
                return self._cs_rect(node)
        return None

    async def cs_find_all_by_label(self, label: str) -> list[tuple[int, int, int, int]]:
        """Return globalRects of all nodes whose label exactly matches."""
        results = []
        for node in await self.cs_tree():
            if node.get("label") == label:
                r = self._cs_rect(node)
                if r is not None:
                    results.append(r)
        return results

    async def cs_find_label_containing(self, substring: str) -> tuple[int, int, int, int] | None:
        """Return the globalRect of the first node whose label contains `substring`."""
        for node in await self.cs_tree():
            if substring in node.get("label", ""):
                return self._cs_rect(node)
        return None

    async def cs_find_all_label_containing(self, substring: str) -> list[tuple[int, int, int, int]]:
        """Return globalRects of all nodes whose label contains `substring`."""
        results = []
        for node in await self.cs_tree():
            if substring in node.get("label", ""):
                r = self._cs_rect(node)
                if r is not None:
                    results.append(r)
        return results

    async def cs_find_by_label_part(self, part: str) -> tuple[int, int, int, int] | None:
        """Return the globalRect of the first node where any label part exactly matches.

        Flutter merges child semantics into a single label separated by '\n'.
        The 'labels' field is that string pre-split.  This method matches any
        individual part, so cs_find_by_label_part("Change") finds a node whose
        full label is "168,929 sats\ntb1q...\nChange".
        """
        for node in await self.cs_tree():
            if part in node.get("labels", node.get("label", "").split("\n")):
                return self._cs_rect(node)
        return None

    async def cs_find_all_by_label_part(self, part: str) -> list[tuple[int, int, int, int]]:
        """Return globalRects of all nodes where any label part exactly matches."""
        results = []
        for node in await self.cs_tree():
            if part in node.get("labels", node.get("label", "").split("\n")):
                r = self._cs_rect(node)
                if r is not None:
                    results.append(r)
        return results

    async def cs_find_by_label_part_containing(self, part: str) -> tuple[int, int, int, int] | None:
        """Return the globalRect of the first node where any label part contains the substring.

        Flutter merges child semantics into a single label separated by '\n'.
        The 'labels' field is that string pre-split.  This method matches if
        `part` is contained in any individual label part, so
        cs_find_by_label_part_containing("sats") finds "92,340 sats".
        """
        for node in await self.cs_tree():
            labels = node.get("labels", node.get("label", "").split("\n"))
            if any(part in label for label in labels):
                return self._cs_rect(node)
        return None

    async def cs_find_all_label_part_containing(self, part: str) -> list[tuple[int, int, int, int]]:
        """Return globalRects of all nodes where any label part contains the substring."""
        results = []
        for node in await self.cs_tree():
            labels = node.get("labels", node.get("label", "").split("\n"))
            if any(part in label for label in labels):
                r = self._cs_rect(node)
                if r is not None:
                    results.append(r)
        return results

    async def cs_find_by_tooltip(self, tooltip: str) -> tuple[int, int, int, int] | None:
        """Return the globalRect of the first node with an exactly matching tooltip."""
        for node in await self.cs_tree():
            if node.get("tooltip") == tooltip:
                return self._cs_rect(node)
        return None

    async def cs_find_all_by_tooltip(self, tooltip: str) -> list[tuple[int, int, int, int]]:
        """Return globalRects of all nodes with an exactly matching tooltip."""
        results = []
        for node in await self.cs_tree():
            if node.get("tooltip") == tooltip:
                r = self._cs_rect(node)
                if r is not None:
                    results.append(r)
        return results

    async def cs_find_by_hint(self, hint: str) -> tuple[int, int, int, int] | None:
        """Return the globalRect of the first node with an exactly matching hint."""
        for node in await self.cs_tree():
            if node.get("hint") == hint:
                return self._cs_rect(node)
        return None

    async def cs_find_all_by_hint(self, hint: str) -> list[tuple[int, int, int, int]]:
        """Return globalRects of all nodes with an exactly matching hint."""
        results = []
        for node in await self.cs_tree():
            if node.get("hint") == hint:
                r = self._cs_rect(node)
                if r is not None:
                    results.append(r)
        return results

    async def cs_find_text_containing(self, substring: str) -> tuple[int, int, int, int] | None:
        """Return the globalRect of the first node where label, value, or hint contains `substring`."""
        for node in await self.cs_tree():
            if (substring in node.get("label", "")
                    or substring in node.get("value", "")
                    or substring in node.get("hint", "")):
                return self._cs_rect(node)
        return None

    async def cs_find_all_text_containing(self, substring: str) -> list[tuple[int, int, int, int]]:
        """Return globalRects of all nodes where label, value, or hint contains `substring`."""
        results = []
        for node in await self.cs_tree():
            if (substring in node.get("label", "")
                    or substring in node.get("value", "")
                    or substring in node.get("hint", "")):
                r = self._cs_rect(node)
                if r is not None:
                    results.append(r)
        return results

    async def cs_find_textfield_by_label(self, label: str) -> tuple[int, int, int, int] | None:
        """Return the globalRect of the TextField closest to a given label node.

        Checks the label node itself for isTextField first, then scans forward
        up to 20 nodes for an enabled TextField child.  Falls back to the label
        node's rect if no TextField sibling is found.
        """
        nodes = await self.cs_tree()
        label_idx = next(
            (i for i, n in enumerate(nodes)
             if n.get("label") == label or label in n.get("labels", [])),
            None,
        )
        if label_idx is None:
            return None
        label_node = nodes[label_idx]
        if "isTextField" in label_node.get("flags", []):
            return self._cs_rect(label_node)
        for node in nodes[label_idx + 1: label_idx + 21]:
            flags = node.get("flags", [])
            if "isTextField" in flags and "isEnabled" in flags:
                return self._cs_rect(node)
        return self._cs_rect(label_node)

    async def cs_find_all_textfield_by_label(self, label: str) -> list[tuple[int, int, int, int]]:
        """Return globalRects of all TextFields associated with a given label.

        For each occurrence of a node matching `label` (exact or as a label part),
        applies the same two-pass strategy as cs_find_textfield_by_label:
          1. If the label node itself is a TextField, use its rect.
          2. Otherwise scan forward up to 20 nodes for the nearest enabled
             TextField child and use that rect.
          3. Fall back to the label node's rect if no TextField sibling is found.
        """
        nodes = await self.cs_tree()
        results = []
        for i, n in enumerate(nodes):
            if n.get("label") != label and label not in n.get("labels", []):
                continue
            if "isTextField" in n.get("flags", []):
                r = self._cs_rect(n)
                if r is not None:
                    results.append(r)
                continue
            found = None
            for sibling in nodes[i + 1: i + 21]:
                flags = sibling.get("flags", [])
                if "isTextField" in flags and "isEnabled" in flags:
                    found = self._cs_rect(sibling)
                    break
            if found is not None:
                results.append(found)
            else:
                r = self._cs_rect(n)
                if r is not None:
                    results.append(r)
        return results

    async def cs_flat_text(self) -> str:
        """Join all node text fields into a searchable string.

        Each non-empty field value is wrapped in double quotes so that
        patterns like '"Wallets"' or '"Unsigned Transaction"' match the
        same way they matched in the legacy semantics_tree() text dump.
        Individual entries from the `labels` array are also emitted so
        that badge labels (e.g. "HOT") are findable as '"HOT"'.
        """
        nodes = await self.cs_tree()
        parts = []
        for node in nodes:
            for key in ("label", "value", "hint", "tooltip"):
                v = node.get(key, "")
                if v:
                    parts.append(f'"{v}"')
            for entry in node.get("labels", []):
                if entry:
                    parts.append(f'"{entry}"')
        return " ".join(parts)

    async def cs_find_label_matching(self, pattern: str) -> tuple[int, int, int, int] | None:
        """Return the globalRect of the first node whose label matches regex `pattern`."""
        for node in await self.cs_tree():
            if re.search(pattern, node.get("label", "")):
                return self._cs_rect(node)
        return None

    async def cs_is_visible(self, label: str) -> bool:
        """Return True if a node with exactly this label exists and is not hidden."""
        for node in await self.cs_tree():
            if node.get("label") == label and "isHidden" not in node.get("flags", []):
                return True
        return False

    async def click_semantic(self, label: str, tooltip: str = ""):
        """
        Click the center of a semantic node identified by label or tooltip.
        Coordinates are Flutter logical pixels → converted to xdotool via CSD offset.

        If the target rect's bottom edge is beyond (window_height - _SCROLL_MARGIN),
        scroll the page down first so the target is fully visible before clicking.
        Flutter semantics positions for ListView children are in document space; they
        don't reflect the current scroll offset, so items near the bottom of long forms
        can appear at a valid y coordinate while still being off-screen.

        Falls back to a warning if the node is not found.
        """
        rect = None
        if label:
            rect = await self.cs_find_by_label_part(label)
        if rect is None and tooltip:
            rect = await self.cs_find_by_tooltip(tooltip)
        if rect is None:
            print(f"[click_semantic] WARNING: node not found: label='{label}' tooltip='{tooltip}'")
            return
        cx = (rect[0] + rect[2]) // 2
        cy = (rect[1] + rect[3]) // 2

        # Scroll into view if the bottom of the target is in the lower margin.
        g = self.window_geometry()
        if g:
            margin = 120  # px — scroll if target bottom is within this from window edge
            if rect[3] > g["h"] - margin:
                clicks = max(3, (rect[3] - (g["h"] - margin)) // 20 + 3)
                print(f"[click_semantic] scrolling down {clicks}× to expose '{label or tooltip}'")
                self.scroll_down(clicks, fx=cx, fy=g["h"] // 2)
                time.sleep(0.4)
                # Re-read rect after scroll — position in viewport may have changed.
                rect2 = None
                if label:
                    rect2 = await self.cs_find_by_label(label)
                if rect2 is None and tooltip:
                    rect2 = await self.cs_find_by_tooltip(tooltip)
                if rect2 is not None:
                    rect = rect2
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
    # Input: clicks and keyboard
    # ------------------------------------------------------------------

    def flutter_click(self, fx: int, fy: int, button: int = 1, delay_s: float = 0.15):
        """
        Click at Flutter logical pixel coordinates (fx, fy).
        Converts to screen-absolute coordinates:
          screen_abs = window_screen_pos + CSD_offset + flutter_pos
        Moves the X11 cursor to the target position first (via xdotool) so that
        Flutter receives the hover event and the pointer is registered at the
        correct location before the button press.
        """
        g = self.window_geometry()
        if g is None:
            raise RuntimeError("Cannot click: window geometry unknown")
        abs_x = g["x"] + self.csd_x + fx
        abs_y = g["y"] + self.csd_y + fy
        self._do_click(abs_x, abs_y, button=button, delay_s=delay_s)

    def click(self, x: int, y: int, button: int = 1, delay_s: float = 0.15):
        """
        Click at (x, y) relative to the Flutter window's X11 client area.
        Converts to screen-absolute coordinates by adding the window screen position.
        """
        g = self.window_geometry()
        if g is None:
            raise RuntimeError("Cannot click: window geometry unknown")
        abs_x = g["x"] + x
        abs_y = g["y"] + y
        self._do_click(abs_x, abs_y, button=button, delay_s=delay_s)

    def scroll_down(self, clicks: int = 3, fx: int | None = None, fy: int | None = None):
        """Scroll down `clicks` wheel-clicks at Flutter coordinates (fx, fy).

        Uses xdotool button 5 (scroll wheel down).  If fx/fy are not given,
        scrolls at the window center.
        """
        g = self.window_geometry()
        if g is None:
            return
        if fx is None:
            fx = g["w"] // 2
        if fy is None:
            fy = g["h"] // 2
        abs_x = g["x"] + self.csd_x + fx
        abs_y = g["y"] + self.csd_y + fy
        env = {**os.environ, "DISPLAY": DISPLAY}
        subprocess.run(
            ["xdotool", "mousemove", "--sync", str(abs_x), str(abs_y)],
            env=env, stderr=subprocess.DEVNULL,
        )
        time.sleep(0.04)
        for _ in range(clicks):
            subprocess.run(["xdotool", "click", "5"], env=env, stderr=subprocess.DEVNULL)
            time.sleep(0.05)

    def mouse_move(self, abs_x: int, abs_y: int):
        """Move the cursor to screen-absolute coordinates via xdotool (XTEST)."""
        env = {**os.environ, "DISPLAY": DISPLAY}
        subprocess.run(
            ["xdotool", "mousemove", "--sync", str(abs_x), str(abs_y)],
            env=env, stderr=subprocess.DEVNULL,
        )
        time.sleep(0.04)

    def _do_click(self, abs_x: int, abs_y: int, button: int = 1, delay_s: float = 0.15):
        """Send a mouse click at screen-absolute coordinates via xdotool (XTEST).

        xdotool uses the XTEST X11 extension which injects events directly into
        the X server event queue — reliable on X11.
        """
        env = {**os.environ, "DISPLAY": DISPLAY}
        subprocess.run(
            ["xdotool", "mousemove", "--sync", str(abs_x), str(abs_y)],
            env=env, stderr=subprocess.DEVNULL,
        )
        time.sleep(0.04)
        subprocess.run(
            ["xdotool", "click", str(button)],
            env=env, stderr=subprocess.DEVNULL,
        )
        time.sleep(delay_s)

    def type_text(self, text: str, delay_ms: int = 30):
        """Type arbitrary text via xdotool (XTEST)."""
        env = {**os.environ, "DISPLAY": DISPLAY}
        subprocess.run(
            ["xdotool", "type", "--clearmodifiers", f"--delay={delay_ms}", "--", text],
            env=env, stderr=subprocess.DEVNULL,
        )

    async def type_text_async(self, text: str):
        """Type text via xdotool asynchronously (non-blocking for the event loop)."""
        env = {**os.environ, "DISPLAY": DISPLAY}
        proc = await asyncio.create_subprocess_exec(
            "xdotool", "type", "--clearmodifiers", "--delay=30", "--", text,
            env=env, stderr=asyncio.subprocess.DEVNULL,
        )
        await proc.wait()

    def key(self, key_name: str):
        """Press a key or key combination via xdotool.

        Accepts xdotool-style names: 'Return', 'Escape', 'ctrl+a', 'BackSpace'.
        """
        env = {**os.environ, "DISPLAY": DISPLAY}
        subprocess.run(
            ["xdotool", "key", "--clearmodifiers", key_name],
            env=env, stderr=subprocess.DEVNULL,
        )

    def raise_window(self):
        """Bring window to front and give it X11 focus via xdotool."""
        if self.window_id:
            env = {**os.environ, "DISPLAY": DISPLAY}
            subprocess.run(["xdotool", "windowraise", self.window_id],
                           env=env, stderr=subprocess.DEVNULL)
            subprocess.run(["xdotool", "windowfocus", "--sync", self.window_id],
                           env=env, stderr=subprocess.DEVNULL)

    # ------------------------------------------------------------------
    # Screenshots (via Flutter VM service — no external tools needed)
    # ------------------------------------------------------------------

    async def screenshot(self, path: str = "/tmp/deadbolt_screenshot.png") -> str:
        """
        Capture the current Flutter frame via the VM service.
        Uses the `_flutter.screenshot` RPC which returns a base64 PNG.
        No external tools required; works regardless of display backend.
        """
        import base64
        r = await self._rpc("_flutter.screenshot")
        data = r.get("result", {}).get("screenshot", "")
        if not data:
            raise RuntimeError("VM service returned empty screenshot")
        Path(path).write_bytes(base64.b64decode(data))
        print(f"[screenshot] Saved: {path}")
        return path

    # ------------------------------------------------------------------
    # Hot reload / restart
    # ------------------------------------------------------------------

    async def hot_reload(self):
        """Trigger a Flutter hot reload via the VM Service."""
        await self.flutter_ext("reassemble")
        print("[hot_reload] Reassemble sent")
        await asyncio.sleep(0.5)

    # ------------------------------------------------------------------
    # Wait helpers
    # ------------------------------------------------------------------

    async def wait_for_widget(self, keyword: str, timeout: float = 10.0, interval: float = 0.3):
        """
        Poll the widget tree until `keyword` appears or `timeout` seconds elapse.
        Raises TimeoutError if not found in time.
        """
        deadline = asyncio.get_event_loop().time() + timeout
        while asyncio.get_event_loop().time() < deadline:
            lines = await self.find_widgets(keyword)
            if lines:
                print(f"[wait_for] ✓ '{keyword}' appeared")
                return lines
            await asyncio.sleep(interval)
        raise TimeoutError(f"Widget '{keyword}' did not appear within {timeout}s")

    async def wait_for_no_widget(self, keyword: str, timeout: float = 10.0, interval: float = 0.3):
        """
        Poll the widget tree until `keyword` disappears or `timeout` seconds elapse.
        Raises TimeoutError if still present after timeout.
        """
        deadline = asyncio.get_event_loop().time() + timeout
        while asyncio.get_event_loop().time() < deadline:
            lines = await self.find_widgets(keyword)
            if not lines:
                print(f"[wait_for_no] ✓ '{keyword}' gone")
                return
            await asyncio.sleep(interval)
        raise TimeoutError(f"Widget '{keyword}' was still present after {timeout}s")

    # ------------------------------------------------------------------
    # Teardown
    # ------------------------------------------------------------------

    async def close(self):
        # (gnome-remote-desktop is a system service — we do not start/stop it)
        # Close VM service WebSocket
        if self.ws:
            try:
                await self.ws.close()
            except Exception:
                pass
        # Terminate Flutter app
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
    print("  click X Y          — click at window-relative coords")
    print("  pct X% Y%          — click at fractional position (e.g. pct 0.5 0.9)")
    print("  type TEXT          — type text at current focus")
    print("  key KEYSYM         — press key (e.g. Return, Escape, ctrl+a)")
    print("  find KEYWORD       — search widget tree for keyword")
    print("  assert KEYWORD     — assert widget present")
    print("  wait KEYWORD       — wait for widget to appear (10s timeout)")
    print("  screenshot [PATH]  — capture window (default: /tmp/deadbolt_screenshot.png)")
    print("  reload             — hot reload via VM service")
    print("  geom               — print window geometry")
    print("  semantics          — dump semantics tree")
    print("  quit               — exit")

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
        elif cmd == "wait" and len(parts) >= 2:
            try:
                await driver.wait_for_widget(parts[1])
            except TimeoutError as e:
                print(f"TIMEOUT: {e}")
        elif cmd == "screenshot":
            path = parts[1] if len(parts) >= 2 else "/tmp/deadbolt_screenshot.png"
            try:
                await driver.screenshot(path)
            except Exception as e:
                print(f"ERROR: {e}")
        elif cmd == "reload":
            await driver.hot_reload()
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
    parser.add_argument("--no-sandbox", action="store_true",
                        help="Use real app data instead of isolated sandbox")
    args = parser.parse_args()

    driver = UIDriver(sandbox=not args.no_sandbox)
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
