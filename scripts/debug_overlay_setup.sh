#!/usr/bin/env bash
# Debug mouse overlay setup for UI tests.
#
# This file is GITIGNORED — never commit it or the files it creates.
#
# The overlay logs every pointer event to stdout so ui_driver.py can
# auto-calibrate CSD offsets and verify click positions.  It is NOT
# part of the production app.
#
# Usage:
#   bash scripts/.debug_overlay_setup.sh apply    # patch source + rebuild
#   bash scripts/.debug_overlay_setup.sh revert   # revert source
#   bash scripts/.debug_overlay_setup.sh status   # check current state

set -euo pipefail
REPO="$(cd "$(dirname "$0")/.." && pwd)"
OVERLAY="$REPO/lib/widgets/debug_mouse_overlay.dart"
MAIN="$REPO/lib/main.dart"

# ── Overlay widget source ────────────────────────────────────────────────────
OVERLAY_CODE='import '"'"'package:flutter/material.dart'"'"';

/// Injected by ui_driver for pointer-position logging and optional crosshair.
/// Written before building and removed on revert — never committed to the repo.
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
      debugPrint('"'"'[mouse] (${pos.dx.round()}, ${pos.dy.round()})'"'"');
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
            debugPrint('"'"'[mouse] DOWN (${e.localPosition.dx.round()}, ${e.localPosition.dy.round()})'"'"');
          },
          onPointerUp: (e) =>
              debugPrint('"'"'[mouse] UP   (${e.localPosition.dx.round()}, ${e.localPosition.dy.round()})'"'"'),
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
        text: '"'"'(${pos.dx.round()}, ${pos.dy.round()})'"'"',
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
'

# ── Helpers ──────────────────────────────────────────────────────────────────
is_applied() {
  [[ -f "$OVERLAY" ]] && grep -q "debug_mouse_overlay" "$MAIN"
}

cmd="${1:-status}"

case "$cmd" in
  apply)
    if is_applied; then
      echo "Already applied."
      exit 0
    fi
    printf '%s' "$OVERLAY_CODE" > "$OVERLAY"
    # Patch main.dart: inject import + flag + builder
    python3 - "$MAIN" <<'PYEOF'
import sys, re
path = sys.argv[1]
src = open(path).read()

IMPORT_MARKER  = "import 'package:deadbolt/widgets/app_scaffold.dart';"
BUILDER_MARKER = "            themeMode: AppThemeManager.getThemeMode(settings.appTheme),"

IMPORT_INJECT = """\
import 'package:deadbolt/widgets/app_scaffold.dart';
import 'dart:io';
import 'package:deadbolt/widgets/debug_mouse_overlay.dart';

// Injected by .debug_overlay_setup.sh — revert before committing.
final bool _debugMouseEnabled =
    Platform.environment['DEADBOLT_DEBUG_MOUSE'] == '1';\
"""

BUILDER_INJECT = """\
            themeMode: AppThemeManager.getThemeMode(settings.appTheme),
            // Injected by .debug_overlay_setup.sh — revert before committing.
            builder: (context, child) => DebugMouseOverlay(
                showCrosshair: _debugMouseEnabled,
                child: child ?? const SizedBox()),\
"""

src = src.replace(IMPORT_MARKER, IMPORT_INJECT, 1)
src = src.replace(BUILDER_MARKER, BUILDER_INJECT, 1)
open(path, 'w').write(src)
print("main.dart patched.")
PYEOF
    echo "Overlay applied. Now run: flutter build linux --debug"
    ;;

  revert)
    rm -f "$OVERLAY"
    git -C "$REPO" checkout -- lib/main.dart
    echo "Overlay reverted."
    ;;

  status)
    if is_applied; then
      echo "Status: APPLIED"
    else
      echo "Status: not applied"
    fi
    ;;

  *)
    echo "Usage: $0 {apply|revert|status}"
    exit 1
    ;;
esac
