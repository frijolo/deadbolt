#!/usr/bin/env bash
# prepare_test_build.sh
#
# Builds the test binary: Flutter DEBUG (VM service active) + Rust RELEASE
# (fast Argon2id KDF).
#
# Why this matters:
#   - Flutter must be debug: only debug mode exposes debugDumpSemanticsTree
#     and the other VM service extensions that UIDriver uses.
#   - Rust must be release: Argon2id in Rust debug mode is 20-50x slower
#     (no optimizations, bounds-checked, no SIMD). A wallet unlock that takes
#     ~30 ms in release can take 1-3 s in debug. With m_cost=65536 it's worse.
#   - Solution: build Flutter debug normally (which also builds Rust debug
#     via Cargokit), then replace the .so with a separately-built release one.
#
# Usage (from project root):
#   bash scripts/prepare_test_build.sh          # full build
#   bash scripts/prepare_test_build.sh --rust-only  # only rebuild Rust + copy
#
# After running this, tests use:
#   build/linux/x64/debug/bundle/deadbolt       ← Flutter debug binary
#   build/linux/x64/debug/bundle/lib/*.so       ← Rust release library
#
# Re-run whenever:
#   - Flutter/Dart code changes
#   - Rust code changes
#   - After flutter clean

set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"

# Always revert the debug overlay on exit (success or failure) so sources stay clean.
trap 'bash "$ROOT/scripts/debug_overlay_setup.sh" revert 2>/dev/null || true' EXIT
RUST_DIR="$ROOT/rust"
RELEASE_SO="$RUST_DIR/target/release/librust_lib_deadbolt.so"
DEBUG_BUNDLE_LIB="$ROOT/build/linux/x64/debug/bundle/lib/librust_lib_deadbolt.so"

RUST_ONLY=false
for arg in "$@"; do
  [[ "$arg" == "--rust-only" ]] && RUST_ONLY=true
done

# ── Step 1: Apply debug overlay (idempotent) ─────────────────────────────────
echo "=== [1/4] Debug overlay ==="
bash "$ROOT/scripts/debug_overlay_setup.sh" apply

# ── Step 2: Flutter debug build (builds Rust debug via Cargokit) ─────────────
if [[ "$RUST_ONLY" == false ]]; then
  echo ""
  echo "=== [2/4] Flutter debug build ==="
  cd "$ROOT"
  flutter build linux --debug
  echo ""
  echo "=== [2b/4] Revert debug overlay (keep sources clean) ==="
  bash "$ROOT/scripts/debug_overlay_setup.sh" revert
else
  echo ""
  echo "=== [2/4] Flutter debug build SKIPPED (--rust-only) ==="
  if [[ ! -f "$DEBUG_BUNDLE_LIB" ]]; then
    echo "ERROR: $DEBUG_BUNDLE_LIB not found. Run without --rust-only first."
    exit 1
  fi
fi

# ── Step 3: Rust release build ───────────────────────────────────────────────
echo ""
echo "=== [3/4] Rust release build ==="
cd "$RUST_DIR"
cargo build --release
echo "    Built: $RELEASE_SO"

# ── Step 4: Replace debug .so with release version ───────────────────────────
echo ""
echo "=== [4/4] Inject Rust release .so into debug bundle ==="
cp "$RELEASE_SO" "$DEBUG_BUNDLE_LIB"
echo "    Replaced: $DEBUG_BUNDLE_LIB"

echo ""
echo "╔══════════════════════════════════════════════════╗"
echo "║  Test binary ready                               ║"
echo "║  Flutter : debug  (VM service + semantics dump)  ║"
echo "║  Rust    : release (fast KDF, ~30ms Argon2id)    ║"
echo "╚══════════════════════════════════════════════════╝"
echo ""
echo "Run tests:"
echo "  python3 scripts/regression_01_singlesig.py"
echo "  python3 scripts/regression_02_multisig_wsh.py"
echo "  python3 scripts/regression_03_taproot.py"
echo "  python3 scripts/regression_04_wallet_device_key.py"
echo "  python3 scripts/regression_05_wallet_password.py"
