#!/usr/bin/env python3
"""
Deadbolt live UI test driver.

Launches the Flutter *debug* build, connects to its VM service, and allows
UI interaction via VNC (x11vnc + vncdotool) with full state inspection via
the widget/semantics tree.

Why debug mode (not profile/release):
  - Profile and release strip the debug dump extensions: debugDumpApp,
    debugDumpRenderTree, debugDumpSemanticsTree return empty strings.
  - Debug mode has the full VM service with working tree dumps and is still
    compiled as a native binary (not flutter run).

How the coordinate systems align:
  - x11vnc launched with -id WID serves just the Flutter window.
    The VNC framebuffer starts at the X11 window top-left (which includes
    the GTK CSD title bar on GNOME/Adwaita).
  - Flutter's render canvas starts at (csd_x, csd_y) inside that X11 window.
  - So: VNC_mouse(fx + csd_x, fy + csd_y) = Flutter logical pixel (fx, fy).
  - On Wayland+XWayland: launch with GDK_BACKEND=x11 so the window is an
    X11 window that x11vnc and xdotool can find.

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
  pip3 install websockets vncdotool
  sudo apt install x11vnc
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

import socket
import struct
import threading

import websockets
from evdev import UInput, ecodes as _ec

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

# GNOME Remote Desktop (wayland-native) VNC endpoint.
# Set password once with: grdctl vnc set-password deadbolt
# Override via env: DEADBOLT_VNC_PASSWORD=... python3 scripts/...
VNC_PORT     = 5900
VNC_PASSWORD = os.environ.get("DEADBOLT_VNC_PASSWORD", "deadbolt")

# Flutter widget tree in debug mode can exceed 1 MB; allow up to 16 MB.
WS_MAX_SIZE = 16 * 1024 * 1024

# Client-side decoration (CSD) offset: on XWayland+GTK, the X11 window
# includes the GTK CSD title bar and border INSIDE its client area.
# The Flutter rendering canvas starts INSIDE this CSD frame.
# Detected empirically: on GNOME/Adwaita, Flutter(0,0) = xdotool(CSD_X, CSD_Y).
# Re-run scripts/calibrate_coords.py if you change your GTK theme.
_CSD_X_DEFAULT = 26   # horizontal CSD offset for uinput ABS events (fallback default)
_CSD_Y_DEFAULT = 70   # vertical CSD offset   for uinput ABS events (fallback default)

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
# Kernel-level keyboard via uinput (python-evdev)
# Bypasses all Wayland/XWayland focus concerns — events go directly to the
# kernel input stack, which libinput delivers to whatever Wayland surface
# the compositor considers focused.
# ---------------------------------------------------------------------------

# evdev keycodes for named keys
_EVKEY = {
    "return":    _ec.KEY_ENTER,
    "enter":     _ec.KEY_ENTER,
    "kpenter":   _ec.KEY_KPENTER,
    "esc":       _ec.KEY_ESC,
    "bsp":       _ec.KEY_BACKSPACE,
    "BackSpace": _ec.KEY_BACKSPACE,
    "delete":    _ec.KEY_DELETE,
    "tab":       _ec.KEY_TAB,
    "space":     _ec.KEY_SPACE,
    "spacebar":  _ec.KEY_SPACE,
    "ctrl":      _ec.KEY_LEFTCTRL,
    "lctrl":     _ec.KEY_LEFTCTRL,
    "rctrl":     _ec.KEY_RIGHTCTRL,
    "shift":     _ec.KEY_LEFTSHIFT,
    "lshift":    _ec.KEY_LEFTSHIFT,
    "rshift":    _ec.KEY_RIGHTSHIFT,
    "alt":       _ec.KEY_LEFTALT,
    "lalt":      _ec.KEY_LEFTALT,
    "ralt":      _ec.KEY_RIGHTALT,
    "super":     _ec.KEY_LEFTMETA,
    "left":      _ec.KEY_LEFT,
    "right":     _ec.KEY_RIGHT,
    "up":        _ec.KEY_UP,
    "down":      _ec.KEY_DOWN,
    "home":      _ec.KEY_HOME,
    "end":       _ec.KEY_END,
    "pgup":      _ec.KEY_PAGEUP,
    "pgdn":      _ec.KEY_PAGEDOWN,
    "f1":        _ec.KEY_F1,
    "f2":        _ec.KEY_F2,
    "f3":        _ec.KEY_F3,
    "f4":        _ec.KEY_F4,
    "f5":        _ec.KEY_F5,
    "f6":        _ec.KEY_F6,
    "f7":        _ec.KEY_F7,
    "f8":        _ec.KEY_F8,
    "f9":        _ec.KEY_F9,
    "f10":       _ec.KEY_F10,
    "f11":       _ec.KEY_F11,
    "f12":       _ec.KEY_F12,
}

# printable ASCII → (evdev keycode, needs_shift)
def _char_to_evkey(ch: str) -> tuple[int, bool]:
    c = ord(ch)
    if ch.isalpha():
        name = f"KEY_{ch.upper()}"
        return getattr(_ec, name), ch.isupper()
    digits = "0123456789"
    if ch in digits:
        return getattr(_ec, f"KEY_{ch}"), False
    # shifted symbols on US keyboard
    shifted = {
        '!': '1', '@': '2', '#': '3', '$': '4', '%': '5',
        '^': '6', '&': '7', '*': '8', '(': '9', ')': '0',
        '_': _ec.KEY_MINUS, '+': _ec.KEY_EQUAL,
        '{': _ec.KEY_LEFTBRACE, '}': _ec.KEY_RIGHTBRACE,
        '|': _ec.KEY_BACKSLASH, ':': _ec.KEY_SEMICOLON,
        '"': _ec.KEY_APOSTROPHE, '<': _ec.KEY_COMMA,
        '>': _ec.KEY_DOT, '?': _ec.KEY_SLASH, '~': _ec.KEY_GRAVE,
    }
    unshifted = {
        ' ': _ec.KEY_SPACE, '-': _ec.KEY_MINUS, '=': _ec.KEY_EQUAL,
        '[': _ec.KEY_LEFTBRACE, ']': _ec.KEY_RIGHTBRACE,
        '\\': _ec.KEY_BACKSLASH, ';': _ec.KEY_SEMICOLON,
        "'": _ec.KEY_APOSTROPHE, ',': _ec.KEY_COMMA,
        '.': _ec.KEY_DOT, '/': _ec.KEY_SLASH, '`': _ec.KEY_GRAVE,
    }
    if ch in shifted:
        base = shifted[ch]
        if isinstance(base, str):
            base = getattr(_ec, f"KEY_{base}")
        return base, True
    if ch in unshifted:
        return unshifted[ch], False
    return _ec.KEY_SPACE, False  # fallback


class _UInputDevice:
    """
    Virtual keyboard + absolute mouse via Linux uinput.

    Events are injected directly into the kernel input stack, which libinput
    then delivers to the Wayland compositor regardless of focus state.
    This completely bypasses Wayland/XWayland focus issues.

    Mouse uses ABS_X/ABS_Y (absolute positioning) — the device is registered
    with the screen resolution so coordinates map directly to screen pixels.
    """

    def __init__(self, screen_w: int = 1920, screen_h: int = 1080):
        from evdev import AbsInfo
        cap = {
            _ec.EV_KEY: list(range(1, 256)) + [_ec.BTN_LEFT, _ec.BTN_RIGHT, _ec.BTN_MIDDLE],
            _ec.EV_ABS: [
                (_ec.ABS_X, AbsInfo(value=0, min=0, max=screen_w - 1,
                                    fuzz=0, flat=0, resolution=1)),
                (_ec.ABS_Y, AbsInfo(value=0, min=0, max=screen_h - 1,
                                    fuzz=0, flat=0, resolution=1)),
            ],
            _ec.EV_REL: [_ec.REL_X, _ec.REL_Y, _ec.REL_WHEEL],
        }
        import evdev
        self._ui = UInput(
            events=cap,
            name="deadbolt-ui-driver",
            version=0x1,
            input_props=[evdev.InputDevice.ID_BUS_USB
                         if hasattr(evdev.InputDevice, 'ID_BUS_USB') else 0x03],
        )
        time.sleep(0.5)  # wait for udev + compositor to register the device

    # ── internal helpers ────────────────────────────────────────────────────

    def _press(self, keycode: int):
        self._ui.write(_ec.EV_KEY, keycode, 1)
        self._ui.syn()

    def _release(self, keycode: int):
        self._ui.write(_ec.EV_KEY, keycode, 0)
        self._ui.syn()

    # ── mouse ───────────────────────────────────────────────────────────────

    def mouse_move(self, x: int, y: int):
        """Move mouse pointer to absolute screen coordinates (x, y)."""
        self._ui.write(_ec.EV_ABS, _ec.ABS_X, x)
        self._ui.write(_ec.EV_ABS, _ec.ABS_Y, y)
        self._ui.syn()
        time.sleep(0.05)

    def mouse_click(self, x: int, y: int, button: int = 1):
        """Move to (x, y) and click the specified button (1=left, 2=middle, 3=right)."""
        btn = {1: _ec.BTN_LEFT, 2: _ec.BTN_MIDDLE, 3: _ec.BTN_RIGHT}[button]
        self.mouse_move(x, y)
        time.sleep(0.05)
        self._press(btn)
        time.sleep(0.05)
        self._release(btn)

    # ── keyboard ────────────────────────────────────────────────────────────

    def key_press(self, name: str):
        """Press and release a single named key (xdotool-style name or single char)."""
        kc = _EVKEY.get(name.lower()) or _EVKEY.get(name)
        shift = False
        if kc is None and len(name) == 1:
            kc, shift = _char_to_evkey(name)
        if kc is None:
            print(f"[uinput] WARNING: unknown key '{name}'")
            return
        if shift:
            self._press(_ec.KEY_LEFTSHIFT)
        self._press(kc)
        time.sleep(0.03)
        self._release(kc)
        if shift:
            self._release(_ec.KEY_LEFTSHIFT)

    def key_combo(self, combo: str):
        """Press a key combination like 'ctrl+a' — holds modifiers during press."""
        parts = [p.strip() for p in combo.replace("-", "+").split("+")]
        keycodes = []
        for p in parts:
            kc = _EVKEY.get(p.lower())
            if kc is None and len(p) == 1:
                kc, _ = _char_to_evkey(p)
            if kc:
                keycodes.append(kc)
        for kc in keycodes:
            self._press(kc)
            time.sleep(0.02)
        for kc in reversed(keycodes):
            self._release(kc)
            time.sleep(0.02)

    def type_text(self, text: str):
        """Type a string character by character."""
        for ch in text:
            kc, shift = _char_to_evkey(ch)
            if shift:
                self._press(_ec.KEY_LEFTSHIFT)
            self._press(kc)
            time.sleep(0.03)
            self._release(kc)
            if shift:
                self._release(_ec.KEY_LEFTSHIFT)
            time.sleep(0.02)

    def close(self):
        try:
            self._ui.close()
        except Exception:
            pass


# ---------------------------------------------------------------------------
# Minimal VNC input-only client (no framebuffer, no Twisted, no asyncio issues)
# ---------------------------------------------------------------------------

# X11 keysym values for named keys (VNC uses X11 keysyms)
_KEYSYM = {
    "return":    0xFF0D,
    "enter":     0xFF0D,
    "kpenter":   0xFF8D,
    "esc":       0xFF1B,
    "bsp":       0xFF08,
    "delete":    0xFFFF,
    "tab":       0xFF09,
    "spacebar":  0x0020,
    "space":     0x0020,
    "ctrl":      0xFFE3,   # Control_L
    "lctrl":     0xFFE3,
    "rctrl":     0xFFE4,
    "shift":     0xFFE1,   # Shift_L
    "lshift":    0xFFE1,
    "rshift":    0xFFE2,
    "alt":       0xFFE9,   # Alt_L
    "lalt":      0xFFE9,
    "ralt":      0xFFEA,
    "super":     0xFFEB,
    "left":      0xFF51,
    "right":     0xFF53,
    "up":        0xFF52,
    "down":      0xFF54,
    "home":      0xFF50,
    "end":       0xFF57,
    "pgup":      0xFF55,
    "pgdn":      0xFF56,
    "ins":       0xFF63,
    "f1":        0xFFBE,
    "f2":        0xFFBF,
    "f3":        0xFFC0,
    "f4":        0xFFC1,
    "f5":        0xFFC2,
    "f6":        0xFFC3,
    "f7":        0xFFC4,
    "f8":        0xFFC5,
    "f9":        0xFFC6,
    "f10":       0xFFC7,
    "f11":       0xFFC8,
    "f12":       0xFFC9,
}


def _vnc_des_key(password: str) -> bytes:
    """Derive the DES key from a VNC password (bit-reversal per RFC 6143 §7.2.2)."""
    pw = (password[:8] + "\x00" * 8)[:8]
    return bytes(
        sum((128 >> i) if (ord(c) & (1 << i)) else 0 for i in range(8))
        for c in pw
    )


class _VNCInput:
    """
    Input-only VNC client over a raw socket.

    Connects to a VNC server, authenticates, completes the init handshake,
    then sends mouse (PointerEvent) and keyboard (KeyEvent) RFB messages.
    No framebuffer subscription — pure input injection.
    """

    def __init__(self, host: str = "localhost", port: int = 5900,
                 password: str = "deadbolt"):
        self.host = host
        self.port = port
        self.password = password
        self._sock: socket.socket | None = None
        self._lock = threading.Lock()

    @staticmethod
    def _recv_exact(s: socket.socket, n: int) -> bytes:
        """Read exactly n bytes from socket."""
        buf = b""
        while len(buf) < n:
            chunk = s.recv(n - len(buf))
            if not chunk:
                raise ConnectionError("VNC connection closed unexpectedly")
            buf += chunk
        return buf

    def connect(self):
        s = socket.create_connection((self.host, self.port), timeout=10)
        s.settimeout(10)

        # ── Version handshake ───────────────────────────────────────────────
        self._recv_exact(s, 12)               # e.g. b'RFB 003.008\n'
        s.sendall(b"RFB 003.008\n")

        # ── Security types ──────────────────────────────────────────────────
        n = self._recv_exact(s, 1)[0]
        if n == 0:
            raise ConnectionError("VNC server refused connection")
        types = list(self._recv_exact(s, n))
        if 2 not in types:
            raise ConnectionError(f"VNC server does not offer VNC auth (got {types})")
        s.sendall(b"\x02")                    # choose VNC auth (type 2)

        # ── VNC authentication (DES challenge-response) ─────────────────────
        challenge = self._recv_exact(s, 16)
        from cryptography.hazmat.primitives.ciphers import Cipher, algorithms, modes
        from cryptography.hazmat.backends import default_backend
        key = _vnc_des_key(self.password)
        cipher = Cipher(algorithms.TripleDES(key * 3), modes.ECB(),
                        backend=default_backend())
        enc = cipher.encryptor()
        response = enc.update(challenge) + enc.finalize()
        s.sendall(response)
        result = struct.unpack("!I", self._recv_exact(s, 4))[0]
        if result != 0:
            raise ConnectionError("VNC authentication failed (wrong password?)")

        # ── ClientInit + ServerInit ─────────────────────────────────────────
        s.sendall(b"\x01")                    # shared = True
        # ServerInit: width(2) + height(2) + pixel_format(16) + name_len(4) + name
        header = self._recv_exact(s, 24)
        name_len = struct.unpack("!I", header[20:24])[0]
        if name_len > 0:
            self._recv_exact(s, name_len)

        self._sock = s

    def _send(self, data: bytes):
        with self._lock:
            if self._sock is None:
                raise RuntimeError("VNC not connected")
            self._sock.sendall(data)

    def mouse_event(self, x: int, y: int, buttons: int = 0):
        """Send a PointerEvent (RFB msg type 5)."""
        self._send(struct.pack("!BBHH", 5, buttons, x, y))

    def mouse_click(self, x: int, y: int, button: int = 1):
        """Move to (x, y) and click the given button (1=left, 2=middle, 3=right)."""
        mask = 1 << (button - 1)
        self.mouse_event(x, y, 0)        # move
        time.sleep(0.05)
        self.mouse_event(x, y, mask)     # press
        time.sleep(0.05)
        self.mouse_event(x, y, 0)        # release

    def key_event(self, keysym: int, down: bool):
        """Send a KeyEvent (RFB msg type 4)."""
        self._send(struct.pack("!BBxxI", 4, 1 if down else 0, keysym))

    def key_press(self, key: str):
        """Press and release a single key (xdotool-style name or single char)."""
        ks = self._resolve_keysym(key)
        self.key_event(ks, True)
        time.sleep(0.03)
        self.key_event(ks, False)

    def key_combo(self, combo: str):
        """
        Press a key combination such as 'ctrl+a' or 'ctrl-a'.
        Modifiers are held down while the final key is pressed.
        """
        parts = [p.strip() for p in combo.replace("-", "+").split("+")]
        # Map to keysyms
        syms = [self._resolve_keysym(p) for p in parts]
        # Press all down, release in reverse
        for ks in syms:
            self.key_event(ks, True)
            time.sleep(0.02)
        for ks in reversed(syms):
            self.key_event(ks, False)
            time.sleep(0.02)

    def type_text(self, text: str):
        """
        Type a string by sending individual KeyEvents for each character.
        For paste-style input, use paste() instead.
        """
        for ch in text:
            ks = ord(ch) if ord(ch) >= 0x20 else _KEYSYM.get(ch, ord(ch))
            if ch.isupper() or ch in '~!@#$%^&*()_+{}|:"<>?':
                self.key_event(_KEYSYM["shift"], True)
            self.key_event(ks, True)
            time.sleep(0.03)
            self.key_event(ks, False)
            if ch.isupper() or ch in '~!@#$%^&*()_+{}|:"<>?':
                self.key_event(_KEYSYM["shift"], False)
            time.sleep(0.02)

    def paste(self, text: str):
        """
        Send text via VNC clipboard (ClientCutText) then paste with Ctrl-V.
        Faster than type_text for long strings.
        """
        encoded = text.encode("latin-1", errors="replace")
        self._send(struct.pack("!BxxxI", 6, len(encoded)) + encoded)
        time.sleep(0.1)
        self.key_combo("ctrl+v")

    def _resolve_keysym(self, name: str) -> int:
        if len(name) == 1:
            return ord(name)
        lower = name.lower()
        if lower in _KEYSYM:
            return _KEYSYM[lower]
        # Try matching vncdotool key names (already lowercase)
        return _KEYSYM.get(lower, ord(name[0]) if name else 0x20)

    def disconnect(self):
        if self._sock:
            try:
                self._sock.close()
            except Exception:
                pass
            self._sock = None


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
    """Controls the Deadbolt debug build via VM service + VNC (x11vnc + vncdotool)."""

    def __init__(self, csd_x: int = _CSD_X_DEFAULT, csd_y: int = _CSD_Y_DEFAULT,
                 sandbox: bool = True, debug_mouse: bool = False):
        self.proc = None          # Flutter app process
        self.ws = None            # VM service WebSocket
        self.isolate_id = None
        self.window_id = None     # X11 window ID (decimal string)
        self._req_id = 0
        self.csd_x = csd_x       # Flutter→VNC horizontal offset (CSD title bar)
        self.csd_y = csd_y       # Flutter→VNC vertical offset (CSD title bar)
        self.sandbox = sandbox    # True: always start with empty app data
        self.debug_mouse = debug_mouse  # True: enable DEADBOLT_DEBUG_MOUSE crosshair overlay
        self._input: _UInputDevice | None = None  # uinput keyboard + mouse

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

        # Create virtual input device (keyboard + mouse via uinput)
        await self._start_input()

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

    async def calibrate(self):
        """Auto-calibrate CSD_X/CSD_Y by clicking at the window center and
        reading the Flutter-reported pointer coordinates from [mouse] output.

        DEADBOLT_MOUSE_LOG=1 must be active (always set by UIDriver.launch).
        The calibration click lands somewhere in the app body; it may trigger
        UI events (e.g. dismiss a dialog) but that is acceptable — the demo
        scripts handle UI state explicitly.
        """
        g = self.window_geometry()
        if g is None or self._input is None:
            print("[calib] WARNING: window or input not ready, skipping calibration")
            return

        abs_x = g["x"] + g["w"] // 2
        abs_y = g["y"] + g["h"] // 2

        log_before = len(self._app_log)
        self._input.mouse_click(abs_x, abs_y)
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

    async def _start_input(self):
        """Create a uinput virtual device for keyboard + mouse input.

        Events are injected directly into the kernel input stack.
        libinput picks them up and delivers them to the Wayland compositor,
        which routes them to the focused surface — bypassing all focus issues.
        """
        # Detect screen resolution for ABS mouse coordinates
        w, h = 1920, 1080
        try:
            out = subprocess.check_output(
                ["xdotool", "getdisplaygeometry"],
                env={**os.environ, "DISPLAY": DISPLAY},
                text=True, stderr=subprocess.DEVNULL,
            ).strip().split()
            w, h = int(out[0]), int(out[1])
        except Exception:
            pass
        print(f"[input] Creating uinput device (screen {w}×{h})")
        self._input = _UInputDevice(screen_w=w, screen_h=h)
        print("[input] uinput device ready")

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

    async def find_all_semantic_rects_by_tooltip(self, tooltip: str) -> list[tuple[int, int, int, int]]:
        """Find ALL semantic nodes matching a tooltip and return all their rects."""
        tree = await self.semantics_tree()
        lines = tree.splitlines()
        results = []
        for i, line in enumerate(lines):
            if f'tooltip: "{tooltip}"' in line:
                r = self._parse_semantics_rect_before(lines, i)
                if r is not None:
                    results.append(r)
        return results

    async def find_all_semantic_rects(self, label: str) -> list[tuple[int, int, int, int]]:
        """Find ALL semantic nodes matching a label and return all their rects."""
        tree = await self.semantics_tree()
        lines = tree.splitlines()
        results = []
        for i, line in enumerate(lines):
            if f'label: "{label}"' in line:
                r = self._parse_semantics_rect_before(lines, i)
                if r is not None:
                    results.append(r)
        return results

    async def find_semantic_rect_by_hint(self, hint: str) -> tuple[int, int, int, int] | None:
        """Find a semantic node by hint text (TextField hintText) and return its rect."""
        tree = await self.semantics_tree()
        lines = tree.splitlines()
        for i, line in enumerate(lines):
            if f'hint: "{hint}"' in line or (f'hint:' in line and hint in line):
                return self._parse_semantics_rect_before(lines, i)
        return None

    async def find_textfield_rect(self, label: str) -> tuple[int, int, int, int] | None:
        """
        Find the editable text area for a labeled TextField.

        Flutter's InputDecoration (labelText) creates a semantic node with the
        label text, but the *editable* child (the actual TextField) is flagged
        with 'isTextField' and 'isEnabled'.  This method finds the label node
        first, then looks forward in the semantics dump for the nearest
        'isTextField' node that shares an overlapping vertical range.

        Falls back to find_semantic_rect(label) if no TextField node is found.
        """
        tree = await self.semantics_tree()
        lines = tree.splitlines()

        # Step 1: find the label line
        label_line = None
        for i, line in enumerate(lines):
            if f'label: "{label}"' in line:
                label_line = i
                break
        if label_line is None:
            return await self.find_semantic_rect(label)

        label_rect = self._parse_semantics_rect_before(lines, label_line)

        # Step 2: scan forward for the nearest 'isTextField' node
        import re as _re
        node_re = _re.compile(r"SemanticsNode#\d+")
        for j in range(label_line + 1, min(len(lines), label_line + 80)):
            if "isTextField" in lines[j]:
                r = self._parse_semantics_rect_before(lines, j)
                if r is not None:
                    return r
            # Stop if we hit a sibling node at the same or lower depth
            # (i.e., we've left the scope of the label's parent)
            if node_re.search(lines[j]) and j > label_line + 3:
                # Allow a few lines for the textfield child node header
                # If we're already 3+ nodes past label, the textfield was not nearby
                break

        # Fallback: return label rect (click in lower portion so it hits the field)
        if label_rect:
            l, t, r, b = label_rect
            # Shift click point below the label into the input area
            return (l, b, r, b + max(40, (b - t)))
        return label_rect

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
    # VNC interaction
    # ------------------------------------------------------------------

    def flutter_click(self, fx: int, fy: int, button: int = 1, delay_s: float = 0.15):
        """
        Click at Flutter logical pixel coordinates (fx, fy).
        Converts to screen-absolute uinput coordinates:
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

    # vncdotool KEYMAP name translations (xdotool names → vncdotool names)
    _KEY_MAP = {
        "Return":    "return",
        "KP_Enter":  "kpenter",
        "Escape":    "esc",
        "BackSpace": "bsp",
        "Delete":    "delete",
        "Tab":       "tab",
        "space":     "spacebar",
        "ctrl":      "ctrl",
        "shift":     "shift",
        "alt":       "alt",
        "super":     "super",
        "Left":      "left",
        "Right":     "right",
        "Up":        "up",
        "Down":      "down",
        "Home":      "home",
        "End":       "end",
        "Prior":     "pgup",
        "Next":      "pgdn",
    }

    def _vkey(self, name: str) -> str:
        """Translate an xdotool-style key name to vncdotool KEYMAP name."""
        return self._KEY_MAP.get(name, name.lower())

    def _do_click(self, abs_x: int, abs_y: int, button: int = 1, delay_s: float = 0.15):
        """Send a mouse click at screen-absolute coordinates via uinput."""
        if self._input is None:
            raise RuntimeError("uinput device not initialised")
        self._input.mouse_click(abs_x, abs_y, button=button)
        time.sleep(delay_s)

    def type_text(self, text: str, delay_ms: int = 30):
        """Type arbitrary text via uinput keyboard (one key event per character).

        uinput events go directly to the kernel input stack and reach whatever
        Wayland surface has focus — no Wayland/XWayland focus indirection.
        """
        if self._input is None:
            raise RuntimeError("uinput device not initialised")
        self._input.type_text(text)

    def key(self, key_name: str):
        """Press a key or key combination via uinput.

        Accepts xdotool-style names: 'Return', 'Escape', 'ctrl+a', 'BackSpace'.
        Modifier combinations use '+' as separator.
        """
        if self._input is None:
            raise RuntimeError("uinput device not initialised")
        if "+" in key_name or "-" in key_name:
            self._input.key_combo(key_name)
        else:
            self._input.key_press(self._vkey(key_name))

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
        # Release uinput virtual device
        if self._input:
            self._input.close()
            self._input = None
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
