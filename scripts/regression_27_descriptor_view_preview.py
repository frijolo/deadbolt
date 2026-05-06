#!/usr/bin/env python3
"""
Regression test 27: tokenized descriptor visualization across the app.

Verifies the unified DescriptorViewer (extracted from DescriptorTab) renders
correctly in every read-only descriptor surface:

  1. Project Designer → Descriptor tab (DescriptorTab wrapper).
  2. Create Wallet preview when launched from a project (DescriptorViewer).
  3. Wallet Detail → Descriptor tab (DescriptorTab wrapper, labels copied
     from the project into the wallet via setKeyLabel).

For each surface we exercise:

  - Alias mode without labels falls back to '@<mfp>' placeholders.
  - Toggling Raw exposes the unredacted MFPs and ALL xpubs (no '@' prefix).
  - After labeling, alias mode substitutes '@<label>' for each MFP and
    fingerprints/xpubs disappear from view.

Reuses the wsh(multi(2,A,B,C)) descriptor from regression_02 (signet xpubs,
MFPs 4061aff0 / ff81be5d / f3d33d4f).

Exit code: 0 = PASS, 1 = FAIL.

Run:
  bash scripts/prepare_test_build.sh   # once
  python3 scripts/regression_27_descriptor_view_preview.py
"""

import asyncio
import os
import subprocess
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from ui_driver import UIDriver                          # noqa: E402
from regression_helpers import (                       # noqa: E402
    wait_for,
    click_label,
    click_tooltip,
    click_popup_item,
    fill_field,
    create_project, go_back, delete_project_from_list,
    create_wallet_from_project,
    go_back_to_wallet_list, delete_wallet_from_list,
    set_active_network_signet,
    run_regression,
)


# ---------------------------------------------------------------------------
# Test data
# ---------------------------------------------------------------------------

PROJECT_NAME = "Reg27-DescriptorView"
WALLET_NAME = "Reg27-Wallet"

# Reused from regression_25 (Taproot inheritance) — the most complex descriptor
# in the test suite. Stresses every branch of the tokenizer/formatter:
#   - tr(...) keyword
#   - taproot script tree with deep `{leaf, {leaf, {...}}}` brace nesting
#   - and_v(v:pk(...), older(N)) timelock branches (5 of them)
#   - duplicate MFP (f3d33d4f appears twice, once on <0;1> and once on <2;3>)
# 5 unique MFPs, 5+ spend paths, taproot internal key + script tree.
DESCRIPTOR = (
    "tr([bc0dbbce/48'/1'/0'/2']"
    "tpubDEpnZReLc2mqbLNeGbNckbVTw6GTgfnz2s8r8wWoWrJY3ZP7dJ2hPKTbFk7RTqdSVYKJiDXQgT3jiACt3EGP5QuYjXqWvf6q1c7gN68Ywp8"
    "/<0;1>/*,"
    "{and_v(v:pk([f3d33d4f/48'/1'/0'/2']"
    "tpubDFLYS7v5vvjyhLMotrmn6KzdN46jJ8ife9yD8DUMygtNCR4U389Wr46vJj7kG9bJPqFmLSet7hAP5fVJvyc97x9fhKZ7Zm9cTdvMxHqT55h"
    "/<0;1>/*),older(6)),"
    "{and_v(v:pk([ff81be5d/48'/1'/0'/2']"
    "tpubDDxjvuVfYHF4KcVyd5wkNS6pKJvg1x6CUtCRL3nRX2MDHKcja6M7YB7FYFYDkXzx8fL7k9bYi8XDpfPetqvd6ER2VYt1WsQSHYnhhT2EX7K"
    "/<0;1>/*),older(13140)),"
    "{and_v(v:pk([f3d33d4f/48'/1'/0'/2']"
    "tpubDFLYS7v5vvjyhLMotrmn6KzdN46jJ8ife9yD8DUMygtNCR4U389Wr46vJj7kG9bJPqFmLSet7hAP5fVJvyc97x9fhKZ7Zm9cTdvMxHqT55h"
    "/<2;3>/*),older(26280)),"
    "{and_v(v:pk([4061aff0/48'/1'/0'/2']"
    "tpubDFAv39stw4ELPsWiyqNL2UcFwruoVdX89CEpzJwb1TV3k9JgW6tLPUicWJvRT5iUSH7HHdt6rXtgRSX5TWJZqDcwJZZTtj1WTcHLUCC7eXC"
    "/<0;1>/*),older(39420)),"
    "and_v(v:pk([ca6205d9/48'/1'/0'/2']"
    "tpubDE7Kf5xBnX5qHJKbAk3JdzxRg1hjoaxHkwCQBQHTAR32NYr6BKhbN78hENp59actsGTsUKjrqhTXCXbmW4hy5NGc5s1Ap9Mx66cKzvyzWaT"
    "/<0;1>/*),older(52560))}}}})"
)

# Five unique MFPs. f3d33d4f appears twice in the descriptor (with different
# multipath wildcards <0;1> and <2;3>) but shares one DB row / one alias map
# entry — the alias substitution covers BOTH occurrences from a single label.
KEYS = [
    ("bc0dbbce", "Alice"),
    ("f3d33d4f", "Bob"),
    ("ff81be5d", "Carol"),
    ("4061aff0", "Dave"),
    ("ca6205d9", "Eve"),
]

# Distinctive xpub prefixes — Raw mode must expose ALL of them. Picked long
# enough to be unique across the 5 xpubs (e.g. tpubDE… disambiguates between
# bc0dbbce and ca6205d9 on the 5th character).
XPUB_FRAGMENTS = [
    "tpubDEpnZReLc2mqbLNeGbNckb",  # bc0dbbce
    "tpubDFLYS7v5vvjyhLMotrmn6",   # f3d33d4f
    "tpubDDxjvuVfYHF4KcVyd5wkN",   # ff81be5d
    "tpubDFAv39stw4ELPsWiyqNL2",   # 4061aff0
    "tpubDE7Kf5xBnX5qHJKbAk3Jd",   # ca6205d9
]

_ENV = {**os.environ, "DISPLAY": ":0"}


# ---------------------------------------------------------------------------
# Generic helpers
# ---------------------------------------------------------------------------

def _press_escape():
    """Dismiss the topmost Flutter route via Escape."""
    subprocess.run(["xdotool", "key", "Escape"], env=_ENV, timeout=3)


async def _collect_label_rects(d: UIDriver, label: str):
    """Return rects of nodes whose label exactly matches `label` OR contains
    it as a substring (Flutter sometimes merges multiline labels like
    'Descriptor\\nTab 5 of 5')."""
    exact = await d.cs_find_all_by_label(label)
    fuzzy = await d.cs_find_all_label_containing(label)
    seen = set()
    out = []
    for r in (exact + fuzzy):
        key = tuple(r)
        if key in seen:
            continue
        seen.add(key)
        out.append(r)
    return out


async def _click_topmost_label(d: UIDriver, label: str, delay: float = 0.6):
    """Click the rect with the smallest Y (topmost) among nodes matching
    `label`, exact or substring."""
    rects = await _collect_label_rects(d, label)
    if not rects:
        raise AssertionError(f"No node with label '{label}' found")
    top = min(rects, key=lambda r: r[1])
    cx = (top[0] + top[2]) // 2
    cy = (top[1] + top[3]) // 2
    print(f"    [click] topmost '{label}' at flutter ({cx},{cy}) "
          f"[{len(rects)} candidate(s)]")
    d.flutter_click(cx, cy)
    await asyncio.sleep(delay)


async def _click_bottommost_label(d: UIDriver, label: str, delay: float = 0.6):
    """Click the rect with the largest Y (bottom-most) among nodes matching
    `label`, exact or substring."""
    rects = await _collect_label_rects(d, label)
    if not rects:
        raise AssertionError(f"No node with label '{label}' found")
    bottom = max(rects, key=lambda r: r[3])
    cx = (bottom[0] + bottom[2]) // 2
    cy = (bottom[1] + bottom[3]) // 2
    print(f"    [click] bottommost '{label}' at flutter ({cx},{cy}) "
          f"[{len(rects)} candidate(s)]")
    d.flutter_click(cx, cy)
    await asyncio.sleep(delay)


# ---------------------------------------------------------------------------
# Assertions over a `cs_flat_text` snapshot
# ---------------------------------------------------------------------------

def _assert_alias_no_labels(sem: str, *, where: str):
    print(f"    [check] {where}: alias mode without labels")
    for mfp, _ in KEYS:
        token = f"@{mfp}"
        if token not in sem:
            raise AssertionError(
                f"{where}: alias mode (no labels) — expected '{token}' placeholder"
            )
        print(f"      [ok] '{token}' visible")
    for frag in XPUB_FRAGMENTS:
        if frag in sem:
            raise AssertionError(
                f"{where}: alias mode should NOT expose xpub '{frag}'"
            )
    print(f"      [ok] xpubs hidden")
    # Defensive: ensure no leftover labels from a previous run.
    for _, label in KEYS:
        if f"@{label}" in sem:
            raise AssertionError(
                f"{where}: alias mode (no labels) — unexpected leftover '@{label}'"
            )


def _assert_raw(sem: str, *, where: str):
    print(f"    [check] {where}: raw mode")
    for frag in XPUB_FRAGMENTS:
        if frag not in sem:
            raise AssertionError(
                f"{where}: raw mode — expected xpub fragment '{frag}'"
            )
    print(f"      [ok] all {len(XPUB_FRAGMENTS)} xpub fragments visible")
    for mfp, _ in KEYS:
        if mfp not in sem:
            raise AssertionError(f"{where}: raw mode — expected MFP '{mfp}'")
        if f"@{mfp}" in sem:
            raise AssertionError(
                f"{where}: raw mode — unexpected alias '@{mfp}'"
            )
    print(f"      [ok] all MFPs visible without '@' prefix")


def _assert_alias_with_labels(sem: str, *, where: str):
    print(f"    [check] {where}: alias mode with labels")
    for mfp, label in KEYS:
        token = f"@{label}"
        if token not in sem:
            raise AssertionError(
                f"{where}: alias mode (with labels) — missing '{token}'"
            )
        if mfp in sem:
            raise AssertionError(
                f"{where}: alias mode (with labels) — MFP '{mfp}' should be hidden"
            )
        print(f"      [ok] '{token}' visible, MFP '{mfp}' hidden")
    # Confirms the toggle is in alias mode (not raw, where xpubs would show).
    for frag in XPUB_FRAGMENTS:
        if frag in sem:
            raise AssertionError(
                f"{where}: alias mode (with labels) — xpub '{frag}' should be hidden"
            )
    print(f"      [ok] xpubs hidden — toggle confirmed in alias")


# ---------------------------------------------------------------------------
# Per-screen flows
# ---------------------------------------------------------------------------

async def _verify_project_descriptor_tab(d: UIDriver, *, with_labels: bool):
    """On the project detail screen, click the Descriptor tab and run the
    alias/raw toggle checks. Leaves the controller back on alias mode."""
    label = "with labels" if with_labels else "no labels"
    print(f"\n  [project descriptor tab — {label}]")
    await click_label(d, "Descriptor", delay=0.8)
    await asyncio.sleep(0.5)

    sem = await d.cs_flat_text()
    if with_labels:
        _assert_alias_with_labels(sem, where="project")
    else:
        _assert_alias_no_labels(sem, where="project")

    await click_label(d, "Raw", delay=0.6)
    sem = await d.cs_flat_text()
    _assert_raw(sem, where="project")

    await click_label(d, "Alias", delay=0.6)


async def _verify_create_wallet_preview(d: UIDriver, *, with_labels: bool):
    """Open the Create Wallet dialog from the current project detail and run
    the toggle checks, then close the dialog."""
    label = "with labels" if with_labels else "no labels"
    print(f"\n  [create wallet preview — {label}]")
    await click_popup_item(d, "More options", 72, "Create wallet")
    await wait_for(d, '"New Wallet"', "Create wallet screen opened")
    # Wait for the async _projectKeyLabels load to settle.
    await asyncio.sleep(1.2)

    sem = await d.cs_flat_text()
    if with_labels:
        _assert_alias_with_labels(sem, where="create-wallet")
    else:
        _assert_alias_no_labels(sem, where="create-wallet")

    await click_label(d, "Raw", delay=0.6)
    sem = await d.cs_flat_text()
    _assert_raw(sem, where="create-wallet")

    await click_label(d, "Alias", delay=0.6)
    sem = await d.cs_flat_text()
    if with_labels:
        _assert_alias_with_labels(sem, where="create-wallet (after toggle)")
    else:
        _assert_alias_no_labels(sem, where="create-wallet (after toggle)")

    await click_tooltip(d, "Close", delay=0.6)
    await wait_for(d, f'"{PROJECT_NAME}"', "Back on project detail")


async def _verify_wallet_descriptor_tab(d: UIDriver):
    """On WalletDetailScreen, navigate to the Descriptor section, click the
    inner Descriptor sub-tab, and run the alias/raw toggle checks."""
    print("\n  [wallet detail descriptor tab]")
    # Bottom nav 'Descriptor' (bottommost match — the same string also appears
    # as the inner sub-tab once the section is rendered).
    await _click_bottommost_label(d, "Descriptor", delay=1.0)
    # Wait for the inner TabBar to mount; spend paths is the default sub-tab.
    await wait_for(d, "Spend paths (", "wallet descriptor section loaded",
                   retries=15, delay=0.6)
    # Inner sub-tab 'Descriptor' (topmost match — bottom nav is at the bottom).
    await _click_topmost_label(d, "Descriptor", delay=1.0)
    # Wait for the toggle to render.
    await wait_for(d, '"Alias"', "alias toggle visible",
                   retries=10, delay=0.4)

    sem = await d.cs_flat_text()
    _assert_alias_with_labels(sem, where="wallet")

    await click_label(d, "Raw", delay=0.6)
    sem = await d.cs_flat_text()
    _assert_raw(sem, where="wallet")

    await click_label(d, "Alias", delay=0.6)
    sem = await d.cs_flat_text()
    _assert_alias_with_labels(sem, where="wallet (after toggle)")


# ---------------------------------------------------------------------------
# Phase B: label project keys
# ---------------------------------------------------------------------------

async def _click_label_starting_with(d: UIDriver, prefix: str, delay: float = 0.6):
    """Click the topmost rect whose label contains `prefix`. Used to hit
    'Keys (N)' / 'Spend paths (N)' tabs without hard-coding the count."""
    rect = await d.cs_find_label_containing(prefix)
    if rect is None:
        raise AssertionError(f"No label containing '{prefix}' found")
    cx = (rect[0] + rect[2]) // 2
    cy = (rect[1] + rect[3]) // 2
    d.flutter_click(cx, cy)
    await asyncio.sleep(delay)


async def _label_project_keys(d: UIDriver):
    """Open each key card on the Keys tab and assign a custom name."""
    print("\n  [phase B] label project keys")
    await _click_label_starting_with(d, "Keys (", delay=0.8)
    # First key card MFP (uppercase) confirms the Keys tab finished rendering.
    await wait_for(d, KEYS[0][0].upper(), "Keys tab rendered", retries=8, delay=0.4)

    for mfp, label in KEYS:
        mfp_upper = mfp.upper()
        # Tap the key card by its MFP badge (uppercase in the UI).
        rect = await d.cs_find_by_label_part(mfp_upper)
        if rect is None:
            raise AssertionError(f"Key card with MFP '{mfp_upper}' not found")
        cx = (rect[0] + rect[2]) // 2
        cy = (rect[1] + rect[3]) // 2
        d.flutter_click(cx, cy, delay_s=0.6)
        await wait_for(
            d, '"Key name"',
            f"Key sheet opened for {mfp}",
            retries=10, delay=0.4,
        )
        name_rect = await d.cs_find_by_label_part(mfp_upper)
        if name_rect is None:
            raise AssertionError(f"Name row not found in key sheet for {mfp}")
        d.flutter_click(
            (name_rect[0] + name_rect[2]) // 2,
            (name_rect[1] + name_rect[3]) // 2,
            delay_s=0.5,
        )
        await wait_for(d, '"Enter a name"', "Edit name dialog open",
                       retries=8, delay=0.3)
        await fill_field(d, "Enter a name", label)
        await click_label(d, "Save", delay=0.5)
        # Sheet remains open — close it via Escape.
        _press_escape()
        await asyncio.sleep(0.6)
        sem = await d.cs_flat_text()
        if label not in sem:
            raise AssertionError(
                f"Label '{label}' not visible on Keys tab after save"
            )
        print(f"    [ok] labeled {mfp} → {label}")


# ---------------------------------------------------------------------------
# Test function
# ---------------------------------------------------------------------------

async def test_descriptor_view_preview(d: UIDriver):
    print(f"\n--- {PROJECT_NAME} ---")

    # The wallet uses signet xpubs; the wallet list filters by active network,
    # so we need the active network on signet to find/delete the wallet later.
    await set_active_network_signet(d)

    # Phase 0 — create project, lands on project detail (Spend paths default).
    await create_project(d, PROJECT_NAME, DESCRIPTOR)

    # Phase 1a — project Descriptor tab without labels (#1).
    await _verify_project_descriptor_tab(d, with_labels=False)

    # Phase A — Create Wallet preview without labels (#3).
    await _verify_create_wallet_preview(d, with_labels=False)

    # Phase B — label project keys via the Keys tab.
    await _label_project_keys(d)

    # Phase 1b — project Descriptor tab WITH labels (#1, post-label).
    await _verify_project_descriptor_tab(d, with_labels=True)

    # Phase C — Create Wallet preview WITH labels (#3, post-label).
    await _verify_create_wallet_preview(d, with_labels=True)

    # Phase D — actually create the wallet, verify wallet detail descriptor (#2).
    print("\n  [phase D] create wallet, verify wallet detail descriptor")
    await create_wallet_from_project(d, WALLET_NAME, protection="device_key")
    await _verify_wallet_descriptor_tab(d)

    # Cleanup — wallet, then project.
    await go_back_to_wallet_list(d)
    await delete_wallet_from_list(d, WALLET_NAME)
    # Manually navigate to the Designer / Projects tab. We avoid
    # `navigate_designer` because it expects "No projects" (empty state) and
    # our project still exists.
    await click_tooltip(d, "Open navigation menu", delay=1.0)
    await click_label(d, "Designer", delay=1.5)
    await wait_for(d, '"Projects"', "Project list reached")
    await delete_project_from_list(d, PROJECT_NAME)

    print(f"    [PASS] {PROJECT_NAME}")


# ---------------------------------------------------------------------------
# Entry point
# ---------------------------------------------------------------------------

if __name__ == "__main__":
    asyncio.run(run_regression(test_descriptor_view_preview, "reg27"))
