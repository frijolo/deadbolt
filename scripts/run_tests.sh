#!/usr/bin/env bash
# run_tests.sh
#
# Equivalent to the /test skill: sets DISPLAY=:0, runs prepare_test_build.sh,
# then executes all regression_NN scripts in order.
# Uses PID file (/tmp/deadbolt_test.pid) for exact process tracking.
#
# Usage (from project root):
#   bash scripts/run_tests.sh                  # full build + all tests
#   bash scripts/run_tests.sh --rust-only      # skip Flutter rebuild, all tests
#   bash scripts/run_tests.sh --skip-build     # skip build entirely, all tests
#   bash scripts/run_tests.sh 01 03            # full build + only tests 01 and 03

set -euo pipefail
export DISPLAY=:0

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SCRIPTS="$ROOT/scripts"
PID_FILE="/tmp/deadbolt_test.pid"

# ── Parse arguments ───────────────────────────────────────────────────────────
RUST_ONLY=false
SKIP_BUILD=false
SELECTED_TESTS=()

for arg in "$@"; do
  case "$arg" in
    --rust-only)   RUST_ONLY=true ;;
    --skip-build)  SKIP_BUILD=true ;;
    [0-9][0-9])    SELECTED_TESTS+=("$arg") ;;
    *)
      echo "Unknown argument: $arg"
      echo "Usage: $0 [--rust-only] [--skip-build] [NN ...]"
      exit 1
      ;;
  esac
done

# ── Step 1: Build ─────────────────────────────────────────────────────────────
if [[ "$SKIP_BUILD" == true ]]; then
  echo "=== Build SKIPPED (--skip-build) ==="
elif [[ "$RUST_ONLY" == true ]]; then
  echo "=== Preparing test build (--rust-only) ==="
  bash "$SCRIPTS/prepare_test_build.sh" --rust-only
else
  echo "=== Preparing test build ==="
  bash "$SCRIPTS/prepare_test_build.sh"
fi

# ── Step 2: Collect regression scripts ────────────────────────────────────────
ALL_SCRIPTS=( $(ls "$SCRIPTS"/regression_[0-9][0-9]_*.py | sort) )

if [[ ${#SELECTED_TESTS[@]} -gt 0 ]]; then
  RUN_SCRIPTS=()
  for num in "${SELECTED_TESTS[@]}"; do
    match=$(ls "$SCRIPTS"/regression_"${num}"_*.py 2>/dev/null || true)
    if [[ -z "$match" ]]; then
      echo "ERROR: No regression script found for index $num"
      exit 1
    fi
    RUN_SCRIPTS+=("$match")
  done
else
  RUN_SCRIPTS=("${ALL_SCRIPTS[@]}")
fi

# ── Step 3: PID-file cleanup helper ───────────────────────────────────────────
# Kill only the tracked deadbolt process via PID file.
# NEVER use pkill -f — it matches the script's own command line, killing itself.
kill_stale_deadbolt() {
    if [ -f "$PID_FILE" ]; then
        local pid
        pid=$(cat "$PID_FILE" 2>/dev/null | tr -d '[:space:]')
        if [ -n "$pid" ]; then
            echo "[cleanup] PID file exists (PID=$pid)"
            if kill -0 "$pid" 2>/dev/null; then
                echo "[cleanup] Process $pid still alive — sending SIGKILL"
                kill -9 "$pid" 2>/dev/null || true
                local waited=0
                while [ $waited -lt 50 ]; do
                    if ! kill -0 "$pid" 2>/dev/null; then
                        echo "[cleanup] Process $pid exited"
                        break
                    fi
                    sleep 0.1
                    waited=$((waited + 1))
                done
                if kill -0 "$pid" 2>/dev/null; then
                    echo "[cleanup] Process $pid did not exit in time"
                fi
            else
                echo "[cleanup] PID $pid not alive — stale file"
            fi
        fi
        rm -f "$PID_FILE"
    fi
    # No PID file → the Python finally block already killed deadbolt cleanly.
    # Nothing to do. Never use pkill -f (it matches our own process).
}

# ── Step 4: Run tests ─────────────────────────────────────────────────────────
PASS=0
FAIL=0
FAILED_NAMES=()

# Kill any leftover processes before starting
kill_stale_deadbolt

for script in "${RUN_SCRIPTS[@]}"; do
  name="$(basename "$script")"
  echo ""
  echo "──────────────────────────────────────────────"
  echo "  Running: $name"
  echo "──────────────────────────────────────────────"

  # Cleanup BEFORE each test to prevent zombies from previous test
  kill_stale_deadbolt

  if DISPLAY=:0 python3 "$script"; then
    echo "  PASS: $name"
    (( PASS++ )) || true
  else
    echo "  FAIL: $name"
    (( FAIL++ )) || true
    FAILED_NAMES+=("$name")
  fi
done

# ── Summary ───────────────────────────────────────────────────────────────────
echo ""
echo "╔══════════════════════════════════════════════════╗"
printf  "║  Tests passed: %-3d  failed: %-3d                 ║\n" "$PASS" "$FAIL"
echo "╚══════════════════════════════════════════════════╝"

if [[ ${#FAILED_NAMES[@]} -gt 0 ]]; then
  echo ""
  echo "Failed scripts:"
  for n in "${FAILED_NAMES[@]}"; do
    echo "  - $n"
  done
  exit 1
fi
