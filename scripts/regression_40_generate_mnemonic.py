#!/usr/bin/env python3
"""
Regression test 40: Generate-mnemonic wizard (3-step flow).

Covers the wizard reached via:
  Add key -> Hot key -> Generate new mnemonic

Phases:
  1. 24-word smoke: switch to 24 in step 1, generate, assert 24 position
     markers ("1." .. "24.") appear in the grid.
  2. Switch back to 12 words, generate, capture the displayed words from the
     semantics tree.
  3. Verify step (error path): fill every position with the right word EXCEPT
     position #1 which is corrupted. Click Continue, expect the verify error
     message, fix word #1, Continue again -> reaches Confirm step.
  4. Confirm step: live derive completes ("Derived keyspec"), click the
     wizard's "Add key" button -> wizard pops with a KeyspecResult.
  5. New Wallet screen shows the hot key tile ("Remove key" visible).
     Create the wallet (device-key protection) and assert the HOT badge
     is present in the Keys sub-tab.
  6. Clean up: delete the wallet.

Prerequisites:
  bash scripts/prepare_test_build.sh
  python3 scripts/regression_40_generate_mnemonic.py
"""

import asyncio
import re
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from ui_driver import UIDriver                          # noqa: E402
from regression_helpers import (                       # noqa: E402
    wait_for, wait_absent,
    click_label, click_tooltip,
    fill_field,
    navigate_wallets,
    go_back_to_wallet_list, delete_wallet_from_list,
    open_hot_generate_new_mnemonic,
    run_regression,
)


WALLET_NAME = "Reg40-GenMnemonic"


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

POSITION_RE = re.compile(r"^(\d+)\.$")
LOWERCASE_WORD_RE = re.compile(r"^[a-z]+$")


async def capture_grid_words(d: UIDriver, count: int) -> list[str]:
    """
    Extract the BIP39 words displayed by the wizard's step 1 grid.

    Strategy: the grid renders each cell as `Text("N.")` + `SelectableText(word)`
    inside a Row. Each text widget produces its own semantics node. For every
    position marker ("1." through "N.") we find the lowercase-letter word
    node in the same vertical band whose left edge is just to the right of
    the marker.
    """
    nodes = await d.cs_tree()

    markers: dict[int, tuple[int, int, int, int]] = {}
    for node in nodes:
        label = (node.get("label") or "").strip()
        m = POSITION_RE.match(label)
        if not m:
            continue
        pos = int(m.group(1))
        if not (1 <= pos <= count):
            continue
        gr = node.get("globalRect")
        if not gr:
            continue
        markers[pos] = (int(gr[0]), int(gr[1]), int(gr[2]), int(gr[3]))

    if len(markers) != count:
        raise AssertionError(
            f"Expected {count} position markers in word grid; "
            f"found {sorted(markers.keys())}"
        )

    words: list[str] = []
    for pos in range(1, count + 1):
        ml, mt, mr_, mb = markers[pos]
        mcy = (mt + mb) // 2
        best: tuple[int, str] | None = None
        for node in nodes:
            label = (node.get("label") or "").strip()
            value = (node.get("value") or "").strip()
            word = value if value and LOWERCASE_WORD_RE.match(value) else (label if LOWERCASE_WORD_RE.match(label) else "")
            if not word:
                continue
            if len(word) < 3 or len(word) > 9:
                # BIP39 English words are 3..8 letters; allow 9 for safety.
                continue
            gr = node.get("globalRect")
            if not gr:
                continue
            l, t, r, b = int(gr[0]), int(gr[1]), int(gr[2]), int(gr[3])
            # If the word is in the same node as the marker (value field),
            # use the node directly.
            if l == ml and t == mt and r == mr_ and b == mb:
                best = (0, word)
                break
            if mcy < t or mcy > b:
                continue
            if l < mr_ - 2:
                continue
            dx = l - mr_
            if best is None or dx < best[0]:
                best = (dx, word)
        if best is None:
            raise AssertionError(
                f"Could not locate word node for position {pos} "
                f"(marker rect={markers[pos]})"
            )
        words.append(best[1])

    if len(set(words)) < 6:
        # Defensive: if the heuristic latched onto a single repeated label
        # (e.g. picked up a button text twice) we'd see lots of duplicates.
        # A real fresh mnemonic has ~no repeats at this scale.
        raise AssertionError(
            f"Captured words look suspicious (too many duplicates): {words}"
        )
    return words


def fake_other_word(real: str) -> str:
    """Return a BIP39-like (lowercase ASCII) word distinct from `real`.

    Used to corrupt one verify field. The wizard validates by exact string
    equality with the generated word, so any value != real triggers the error
    branch regardless of whether it is actually in the BIP39 wordlist.
    """
    return "abandon" if real != "abandon" else "ability"


# ---------------------------------------------------------------------------
# Phases
# ---------------------------------------------------------------------------

async def phase_open_wizard(d: UIDriver):
    print(f"\n  [phase 1] open generate-mnemonic wizard from guided creation")

    await navigate_wallets(d)
    await click_tooltip(d, "New")
    await wait_for(d, "Guided creation", "bottom sheet opened")
    await click_label(d, "Guided creation", delay=0.5)
    await wait_for(d, '"New Wallet"', "Guided creation screen opened")

    await fill_field(d, "Wallet name", WALLET_NAME)

    await click_label(d, "Add key", delay=0.5)
    await open_hot_generate_new_mnemonic(d)
    print("    [ok] wizard step 1 visible")


async def phase_24_word_smoke(d: UIDriver):
    print(f"\n  [phase 2] 24-word smoke")

    # Step 1 default is 12 words; click the "24 words" segment.
    await click_label(d, "24 words", delay=0.3)
    # Selecting a length clears any prior mnemonic; Generate button is back.
    await click_label(d, "Generate mnemonic", delay=1.0)
    # Wait for grid: the "24." position marker must appear.
    await wait_for(d, '"24."', "24-word grid rendered",
                   retries=10, delay=0.5)

    # Sanity: all 24 positions present and we can extract words.
    words24 = await capture_grid_words(d, 24)
    assert len(words24) == 24
    print(f"    [ok] 24 words captured (first={words24[0]}, last={words24[-1]})")


async def phase_generate_12(d: UIDriver) -> list[str]:
    print(f"\n  [phase 3] switch to 12 words and generate")

    await click_label(d, "12 words", delay=0.3)
    # The 24-word grid is cleared by onWordCountChanged; we expect the
    # "Generate mnemonic" button to be back. Click it.
    await wait_for(d, '"Generate mnemonic"',
                   "Generate button visible after length switch",
                   retries=10, delay=0.4)
    await click_label(d, "Generate mnemonic", delay=1.0)
    await wait_for(d, '"12."', "12-word grid rendered",
                   retries=10, delay=0.5)
    words = await capture_grid_words(d, 12)
    print(f"    [ok] 12 words captured (first={words[0]}, last={words[-1]})")
    return words


async def phase_verify_error_then_success(d: UIDriver, words: list[str]):
    print(f"\n  [phase 4] verify step (error path -> success)")

    # Step 2: advance from generate to verify.
    await click_label(d, "I have written them down", delay=0.8)
    await wait_for(d, '"Word #1"', "verify step rendered",
                   retries=10, delay=0.5)

    # Fill every position with the right word EXCEPT word #1 -> wrong.
    wrong = fake_other_word(words[0])
    for n in range(1, 13):
        await fill_field(d, f"Word #{n}", wrong if n == 1 else words[n - 1])
    print(f"    [ok] verify fields filled (word #1 corrupted to '{wrong}')")

    # Click Continue -> expect the global verify error message.
    await click_label(d, "Continue", delay=0.8)
    await wait_for(
        d,
        "Some words do not match",
        "verify error message visible after wrong word",
        retries=8, delay=0.4,
    )
    print("    [ok] verify error message visible (error path confirmed)")

    # Fix word #1 and continue again -> should advance to Confirm step.
    await fill_field(d, "Word #1", words[0])
    await click_label(d, "Continue", delay=1.0)
    # Confirm step contains the MnemonicConfirmStep widget which exposes
    # the "Derived keyspec" preview once Rust returns.
    await wait_for(d, "Derived keyspec", "Confirm step: keyspec derived",
                   retries=25, delay=1.0)
    print("    [ok] Confirm step reached and keyspec derived")


async def phase_confirm_and_create_wallet(d: UIDriver):
    print(f"\n  [phase 5] add key from wizard, create wallet, assert HOT")

    # Wizard's "Add key" button is the last node with that label in the
    # tree (the parent screen's Add-key button is covered by the modal).
    rects = await d.cs_find_all_by_label("Add key")
    if not rects:
        raise AssertionError("Wizard 'Add key' button not found in semantics")
    btn = rects[-1]
    d.flutter_click((btn[0] + btn[2]) // 2, (btn[1] + btn[3]) // 2)
    await asyncio.sleep(1.5)

    # Wizard pops, control returns to the New Wallet screen which now shows
    # the hot key tile with a "Remove key" action button.
    await wait_for(d, "Remove key",
                   "New Wallet: hot key tile present",
                   retries=15, delay=0.6)
    print("    [ok] wizard popped; New Wallet shows the hot key tile")

    # Create the wallet (device-key protection — no password overhead).
    await click_label(d, "Create wallet", delay=1.0)
    await wait_for(d, '"Receive"',
                   f"wallet detail loaded: '{WALLET_NAME}'",
                   retries=30, delay=1.0)
    print(f"    [ok] wallet detail opened: '{WALLET_NAME}'")

    # Navigate to Descriptor tab and assert HOT badge appears on the key.
    await click_label(d, "Descriptor", delay=1.0)
    await wait_for(d, 'Keys (1', "Keys sub-tab visible",
                   retries=20, delay=0.6)
    keys_tab = await d.cs_find_label_containing("Keys (")
    if keys_tab is None:
        raise AssertionError("'Keys (N)' sub-tab not found")
    d.flutter_click((keys_tab[0] + keys_tab[2]) // 2,
                    (keys_tab[1] + keys_tab[3]) // 2)
    await asyncio.sleep(0.6)
    await wait_for(d, 'HOT', "HOT badge visible on generated key",
                   retries=15, delay=0.6)
    print("    [ok] HOT badge present — hot key persisted from generated mnemonic")


async def phase_cleanup(d: UIDriver):
    print(f"\n  [phase 6] cleanup")
    await go_back_to_wallet_list(d)
    await delete_wallet_from_list(d, WALLET_NAME)


# ---------------------------------------------------------------------------
# Entry point
# ---------------------------------------------------------------------------

async def test_generate_mnemonic(d: UIDriver):
    print(f"\n--- {WALLET_NAME} (generate-mnemonic wizard) ---")

    await phase_open_wizard(d)
    await phase_24_word_smoke(d)
    words = await phase_generate_12(d)
    await phase_verify_error_then_success(d, words)
    await phase_confirm_and_create_wallet(d)
    await phase_cleanup(d)

    print(f"\n    [PASS] {WALLET_NAME}")


if __name__ == "__main__":
    asyncio.run(run_regression(test_generate_mnemonic, "reg40"))
