# Changelog

All notable changes to Deadbolt are documented here, newest first.

---

## [Unreleased]

### Improvements
- **Add private key inferred by MFP** — The wallet/project Keys view now shows a single "Add private key" button at the top instead of a per-card "Make hot" entry. The destination key is inferred from the seed's master fingerprint, with live xprv validation and explicit errors when the MFP doesn't match any watch-only key in the wallet or when the matched key already has a private key stored.
- **Unified Add-key flow attaches private keys** — Adding a key (mnemonic or xprv) whose MFP already matches an existing watch-only key in a project now prompts to attach it as the private key for that slot, removing the separate project-level "Add private key" button. The wallet Descriptor tab moves the "Add private key" button below the key list for a less crowded header.
- **Clearer stored-seed terminology** — Key-card labels and confirmation copy now talk about "Stored seed" / "Delete stored seed" with an explicit warning that, without a backup, deleting the seed permanently loses access while the watch-only public key remains.

### Fixes
- **Orphaned hot seed when removing a key from a project** — Removing a key that had a stored seed now cascade-deletes the seed from `project_seeds.db` instead of leaving the secret orphaned with no UI to reach it.

## [v1.9.7]

### New Features
- **Spaced transaction planning** — A new wallet menu entry plans N future-dated, single-input transactions per confirmed UTXO with randomised feerates, staggered nLockTimes, optional 2-output anti-fingerprint split, and label propagation from source coins to destination addresses. Covers both refresh (same wallet) and migrate (different destination) in one unified flow, batch-signed via hot key, hardware wallet, or QR with two confirmation gates. Auto-broadcast emits each child as its timelock matures; a Reserved balance chip and per-coin earmark badge surface active plans.
- **Future-dated transactions** — Create TX now exposes an optional broadcast delay (days / hours / minutes) that sets the PSBT's nLockTime to `max(tip, abs_timelock) + delta`, capped at ~1 year. Saved PSBTs gain an auto-broadcast switch; once the timelock matures, the next successful Electrum sync broadcasts them automatically and emits a toast. The transactions list shows a queued/locked badge with the unlock ETA.
- **Generate mnemonic wizard** — A new 3-step in-app flow (generate → verify by typed positions → configure) lets you create a fresh BIP39 seed without leaving Deadbolt or relying on external tools. Entropy comes from the operating system's secure random source with additional hashing applied as defense-in-depth, and intermediate buffers are wiped from memory once the seed is handed off.

### Fixes
- **Inconsistent export file names** — Exported files now use consistent sanitization for non-ASCII wallet names.
- **RBF fee re-validated at broadcast** — When sending an RBF replacement, Deadbolt now refetches the conflicting transactions' minimum fee right before broadcasting and re-checks the user's fee against it. Closes a race where a new descendant entering the mempool between preview and broadcast would push the minimum above the originally-typed fee and cause the relay to reject the replacement.

### Improvements
- **Restructured Add-key sheet** — The Add-key flow now opens at a capacity picker (Watch-only / Hot key) with per-source sub-pickers (manual, QR, file, hardware wallet, generate, existing mnemonic, xprv) instead of a single bloated dialog. Extracted shared widgets (`keyspec`, `derivation_path_helpers`, `gap_stepper`, `mnemonic_confirm_step`, `mnemonic_mfp_preview`) for reuse across the wizard and the manual paths.
- **Multi-step sheet back navigation** — `sheetCloseTitle` now accepts an optional `onBack`, and `showTextImportSheet` accepts an `initialAction` to skip its in-sheet picker when the caller has its own.

## [v1.9.6]

### Improvements
- **BitBox02 over USB on Android** — Connect, pair, register descriptors, fetch xpubs, sign PSBTs, and verify addresses on a BitBox02 via USB HID. Handles detach/retach cleanly, including while backgrounded.
- **Multi-leaf taproot HW signing** — Pass per-MFP change index to BitBox02 so the device signs the correct leaf in multi-leaf taproot descriptors.
- **BIP48 sortedmulti support** — Register, display addresses, and sign PSBTs for plain `wsh(sortedmulti(...))` and `sh(wsh(sortedmulti(...)))` descriptors via the BitBox02 Multisig variant.
- **keyChanges field on APISpendPath** — Added per-MFP change index to the spend path model for multi-leaf disambiguation.
- **Conditional scanning hints on restore** — Show Nostr and on-chain scan hints only when those search modes are active for the current scan.
- **Create TX responsiveness on multipath wallets** — Cache descriptor spend paths per wallet session so tapping the fee field, toggling MAX, or switching spend path no longer pays the ~50 ms miniscript-analysis cost on every preview.

### Fixes
- **HW xpub derivation on Android** — Route HW xpub derivation in the restore flow through the cubit dispatch loop so it works on Android.

### Test Fixes
- **On-chain backup regression** — Update vault validation to reflect §5.4 fee arithmetic (vault ≥ 330 sats dust threshold).

## [v1.9.5]

### New Features
- **Biometric & screenshot protection** — Add screenshot protection, biometric app lock, and per-wallet biometric unlock.
- **Descriptor alias/raw toggle** — Add toggle in the descriptor tab with key-label substitution.
- **On-chain descriptor backup** — Commit/reveal backup of descriptors via Signet.
- **Wallet detail refactor** — Split cubit, add PSBT preview screen, descriptor backup UI, and expanded test suite.
- **Descriptor display widget** — Add widget showing wallet descriptor with singlesig backup warning and stale credential fix.
- **OP_RETURN output support** — Add OP_RETURN output creation in transaction builder and display in transaction detail.
- **Seed recovery cache** — Cache first-address hash in wallet sidecar for fast locked-wallet seed recovery.
- **Security hardening** — Zeroize key material, sanitize logs, and harden clipboard for secrets.
- **Hot key corruption reporting** — Propagate RNG errors, expose corrupt hot keys in the list, and guard SQL table names.
- **APIHotKeyList exposure** — Expose hot key list via Rust API with corrupt-row reporting; clean up Rust API surface.
- **Clipboard timeout from settings** — Derive clipboard clear timeout from the biometric lock setting and add feedback toasts.

### Fixes
- **Biometric hidden state & SafeArea** — Fix biometric hidden state, post-sync address emit, and showSheet SafeArea behavior.
- **PSBT spend path inference** — Infer spend path from nSequence/nLockTime and install rustls provider at startup.
- **Anti-fee-sniping lock_time** — Ignore lock_time in PSBT spend path inference.
- **Mnemonic auto-attach** — Auto-attach mnemonic key after on-chain backup recovery and fix network hint.

### Improvements
- **Extracted shared helpers** — Extract shared copy/address/hex helpers, add sync no-op guards.

---

## [v1.9.4]

### New Features
- **Switch camera button in QR scanner** — When multiple working cameras are detected on desktop, a camera-switch button appears in the top-right corner of the scanner overlay, allowing the user to cycle through available cameras without leaving the screen.

### Fixes
- **Descriptor signatures reload** — Returning from the Security screen now triggers a fresh reload of descriptor signatures so tile states reflect any signing just completed.
- **Desktop QR scanner with multiple cameras** — The app no longer hangs when virtual cameras (v4l2loopback with no writer) are present. The C++ plugin now uses `poll()` with a 500 ms timeout before `VIDIOC_DQBUF` so unproductive devices return immediately instead of blocking forever. Camera selection probes each device with a test frame and advances to the next one on failure, ensuring the real camera is found even when virtual devices appear first.
- **Desktop QR scanner on Intel ipu6 laptops** — Camera init now tries each V4L2 device index in order and uses the first one that opens successfully, instead of always opening index 0 (which is metadata-only on ipu6 drivers and always fails).

### Improvements
- **Desktop QR scan loop** — Replaced the 300 ms `Timer.periodic` poll with a tight async loop; frames are captured and decoded back-to-back without a fixed delay.
- **Nostr backup recovery script** — `fetch_nostr_backup.py` now verifies descriptor ownership signatures (BIP322 and Bitcoin message) and reports their validity alongside each recovered wallet.
- **Bitcoin term normalization in Spanish** — Technical terms (Singlesig, Multisig, Outpoint, Keychain, Key Path, Sweep cost) are now shown in their standard English form in the Spanish locale, consistent with how the Bitcoin community uses them.

## [v1.9.3]

### Fixes
- **QR scanner on mobile** — Fixed an inverted condition that prevented `MobileScannerController` from ever being created; the controller is now properly initialized, stopped when a scan completes, and disposed on screen exit.
- **Relative timelock unlock threshold (BIP68)** — A UTXO locked with a relative block timelock is now considered broadcastable when `elapsed + 1 ≥ required` (matching Bitcoin Core's tip+1 mempool validation), reducing the displayed remaining-blocks count by one.
- **PSBT confirmation height for ghost UTXOs** — `psbt_max_utxo_conf_height` now falls back to the full wallet transaction history when BDK removes a UTXO from its unspent set (e.g. mempool spend / RBF), fixing nLockTime computation for replace-by-fee transactions.

### Improvements
- **Wallet back navigation** — Pressing back from any wallet tab (transactions, addresses, coins, descriptor) now navigates to the Overview tab instead of exiting the wallet; only pressing back from Overview returns to the wallet list.
- **Fee precision** — Transaction fee is now passed as an absolute satoshi amount (derived from the UI's pre-calculated estimate) instead of a fee rate, eliminating rounding errors from the sat/vB → sat/kwu conversion.

## [v1.9.2]

### New Features
- **Seed export screen** — Hot Key mnemonics now open a dedicated export screen with three tabs: word list, SeedQR (standard and compact formats), and a paper backup guide that segments the QR into transcribable chunks and lets the user verify the transcription by scanning.
- **Descriptor ownership signatures** — Each key in a wallet can sign the descriptor hash to prove ownership. Supports Hot Key (automatic), BitBox02 via USB, QR message signing, and QR BIP-322 PSBT. Signatures are stored per-wallet and included in Nostr backups; the app verifies them on restore.
- **Wallet Security screen** — A new "Security" entry in the wallet detail menu consolidates encryption info and descriptor-signature management in one place.
- **Wallet reorder** — A swap-vert button in the wallet list toggles reorder mode; wallets can be dragged to any position and the order is persisted per network via SharedPreferences.
- **Coin sort control** — The coins tab now has a sort button to order UTXOs by size (largest/smallest first) or age (oldest/newest first); the chosen sort is persisted across sessions.
- **Coin age and block in detail dialog** — The coin detail dialog now shows confirmation count, approximate age (~3d, ~2mo, ~1y), block number, and confirmation date, using the UTXO's confirmation timestamp from the chain.
- **Nearest unlock countdown on coin tiles** — The spend-path badge on timelocked coin tiles now appends the time until the nearest locked path unlocks (e.g. "1/2 · ~14d").
- **Estimated unlock date on spend-path rows** — Each locked spend path in the coin detail dialog now shows an approximate unlock date.
- **Restore defaults for Electrum and explorer URLs** — When a URL field is cleared, a restore icon appears to fill it back to the built-in default for that network.
- **Restore defaults for Nostr relays** — A restore button in the Nostr relay settings screen resets the list to the built-in defaults.

### Fixes
- **PSBT timelock for foreign UTXOs** — When building a transaction that spends mempool coins (foreign UTXOs), nSequence and nLockTime are now correctly set from the policy's relative/absolute timelock, fixing "Locktime requirement not satisfied" broadcast failures.
- **Coins tab total excludes spending coins** — The total balance shown above the coin list no longer counts UTXOs that are already being spent (mempool spend or pending PSBT).
- **Compact SeedQR format** — Compact SeedQR now stores raw entropy bytes (per SeedSigner/Krux spec) instead of 11-bit packed word indices, restoring compatibility with hardware wallets.

### Improvements
- **Spend status badges on coin detail** — The coin detail dialog shows a red "Mempool spend" badge or orange "Pending spend" badge when the UTXO is already being consumed.
- **Timelock display with date and time** — Locked spend-path rows now display the estimated unlock timestamp inline (e.g. "144 blocks · Apr 12, 2026 14:30") and switch to a time component when less than 48 hours remain.
- **Context-free toasts** — Toast helpers now use a global `ScaffoldMessengerKey`, so toasts can be shown from anywhere without requiring a `BuildContext`.
- **Simplified address and coin tile badges** — Removed `CircleAvatar` backgrounds; status is now conveyed by icon/text colour alone.

---

## [v1.9.1]

### New Features
- **Configurable Nostr relay timeout and retries** — The Nostr relay settings screen now exposes timeout (seconds) and attempts-per-relay controls, persisted across sessions and applied to Rust at startup and on change.

### Improvements
- **Updated default Nostr relays** — Default relay list is now nos.lol, relay.damus.io, and nostr.mom (replaces relay.nostr.band and relay.primal.net).
- **Nostr restore network warning** — When all relays fail to respond during a wallet restore (network error), a warning banner is shown so users know some backups may not have been found.
- **Fee presets from mempool blocks** — Priority, normal, and economy fee rates are now derived directly from the live mempool block snapshot (median of blocks 0, 1, and 2), replacing the separate fee-estimation API call. Fee values display one decimal place when the rate is not a whole number.
- **Dismissible Electrum privacy warning** — The privacy warning banner on the wallet detail screen can now be hidden for 7 days via a "Don't show for 7 days" button.

---

## [v1.9.0]

### New Features
- **Nostr backup** — Wallet descriptors can now be encrypted and published to Nostr relays for redundant off-device backup. Accessible from the wallet detail screen.
- **Restore from Nostr** — Recover a wallet directly from a Nostr backup using your xpub or seed phrase, without manual descriptor entry.
- **Account discovery on seed restore** — When restoring from a seed phrase, the app scans the blockchain for used accounts across all script types (P2WPKH, P2TR, P2SH-P2WPKH) and displays found wallets with balances and transaction counts. Nostr backups are also fetched and shown alongside on-chain results.
- **Nostr relay management** — New settings screen to add, remove, and reorder Nostr relay URLs.
- **Restore from hardware wallet** — New flow to recover a wallet from a connected BitBox02: the app exports the xpub, scans on-chain accounts, and fetches matching Nostr backups — all without entering a seed phrase.
- **SeedQR import** — The QR scanner now recognises SeedQR payloads (both standard 4-digit-per-word and compact binary formats), automatically decoding them into a BIP-39 mnemonic on the seed-restore screen.
- **Active network filter** — The network setting now acts as a global filter: only wallets on the active network are shown in all list views. A count of hidden wallets on other networks is displayed inline. The active network badge is visible in the app bar of all wallet/project creation and recovery screens.
- **Skip legacy derivations toggle** — When recovering from a hardware wallet, a new toggle lets you skip P2PKH (m/44′) derivation paths, avoiding unnecessary confirmation prompts on the device.

### Improvements
- **Unified recovery screen** — Seed, hardware wallet, and xpub recovery flows are now consolidated into a single screen with three tabs, replacing the three separate screens.
- **Cosigner backup count** — The Nostr backup status tile now shows how many of the descriptor's xpubs have a backup on each relay (e.g. "2/3 cosigners").
- **Nostr import confirmation** — Importing a Nostr backup now shows a confirmation dialog reminding users to verify the descriptor and receiving addresses before sending funds.

---

## [v1.8.0]

### New Features
- **Inheritance wallets** — New wallet type that creates multi-path Taproot descriptors: you control funds normally, and designated heirs can access them after a configurable timelock delay (3 months, 6 months, 9 months, 1 year, or custom blocks).
- **Inheritance status card** — The wallet overview now shows an inheritance panel displaying the earliest date a heir could access funds, based on the oldest confirmed UTXO and remaining timelock.
- **Re-vault** — One-tap button to sweep all funds back to the same wallet, resetting the inheritance timer.
- **Inheritance detection threshold** — New setting to configure the minimum timelock (in blocks) that distinguishes an inheritance path from a short-delay multisig path (default: 144 blocks ≈ 1 day).

### Fixes
- **Key removal crash** — Removing a key that is no longer in the edited list no longer throws; uses `firstOrNull` guard.
- **Null-safe keyspec parsing** — Invalid keyspec strings in the simple-wallet dialog no longer crash; handled gracefully.

### Improvements
- Coins tab now shows inheritance indicators on UTXOs for inheritance wallets.
- Hardware wallet sheet now shows "Unlock your device…" prompt.
- Network selector appears above the descriptor/key fields in wallet creation dialogs for a more logical flow.

---

## [v1.7.1]

### New Features
- **Live balances on wallet list** — Each wallet card now shows its balance and a syncing spinner in real time. All unlocked wallets sync automatically in the background; no need to open a wallet to see its balance.
- **Sync and Lock from wallet list** — The wallet card context menu now includes Sync and Lock actions.
- **Reactive Electrum sync** — Wallet balance and transaction list update instantly when a new block or relevant transaction is detected, without waiting for a polling interval.
- **Next-block fee histogram** — The send screen now shows a collapsible histogram of the next 6 projected mempool blocks (from mempool.space). Tapping a bar sets the fee rate instantly. Refreshes every 5 s and routes through Tor when active.

### Fixes
- **Fast navigation crash** — Navigating away from a wallet screen while it was still loading no longer produces "Cannot emit new states after calling close" errors.
- **Fee rate back-computation drift** — When switching to "edit total fee" mode, the fee rate field now shows a floored 8-decimal value that round-trips exactly through `ceil(rate × vbytes)` instead of a 2-decimal rounded value that could produce a ±1 sat mismatch.
- **Fee field focus loss** — Clearing the fee rate field no longer causes the input to lose focus (Flutter element identity was broken when the fee summary row disappeared from the ListView).
- **RBF minimum fee boundary** — BIP-125 Rule 3 and Rule 4 minimums now use strict `<` comparisons instead of `≤`, matching the protocol spec exactly.

---

## [v1.7.0]

### New Features
- **Restore wallet from seed** — New screen that scans the blockchain for all accounts derived from a mnemonic phrase (BIP44/49/84/86, configurable gap limits). Found accounts are listed with balance and tx count; already-imported wallets are matched and linked. Tapping an account opens the guided wizard pre-filled with the keyspec and seed.
- **Key info sheet in guided wizard** — The edit icon on key tiles is replaced by an info (ℹ) icon. Tapping it opens the existing key detail sheet showing MFP, derivation path, and full xpub with share. If the key was entered via seed, the sheet also shows the private seed reveal option. Custom names set here are persisted to the wallet on creation.

### Fixes
- **Restore-from-seed stale state** — After creating a wallet through the restore wizard, the account list now immediately reflects the newly created wallet (name badge + open arrow) instead of showing a stale "create" button.

### Improvements
- **Key tile layout in guided wizard** — Tiles now show `[MFP badge] / derivation path` on the first line and the coloured xpub on the second line, replacing the previous single-line xpub-only layout.
- **Unified bottom sheet drag handle** — All bottom sheets now show a consistent `SheetHandle` pill at the top (40 × 4 px, theme-tinted). Inline one-off handle implementations removed.
- **Full-width `SegmentedButton`** — Every `SegmentedButton` (wallet type, script type, key tab, seed type, word count, protection type) is now wrapped in `SizedBox(width: double.infinity)` so it stretches to the sheet width instead of centering.
- **Simplified sheet layouts** — Sheets previously backed by `DraggableScrollableSheet` (`key_edit_sheet`, `spend_path_edit_sheet`, `wallet_path_detail_sheet`) are replaced by `ConstrainedBox(maxHeight: 90%)` + `Flexible(SingleChildScrollView)` for a simpler, more predictable layout.
- **`showSheet` helper updated** — `isScrollControlled: true` is now always set so tall sheets (key entry, spend path editor) can use the full screen height without clipping.
- **Localization audit** — Full l10n pass across the app; all hardcoded strings localized, WIF export warning added.

---

## [v1.6.2]

### New Features
- **WIF key export** — Single-sig hot wallets can now export the private key of any address in WIF format. A security disclaimer is shown before revealing the key, which is then displayed with QR code, copy, and file-save options. Accessible via "Export private key (WIF)" in the address detail sheet.
- **WIF key sweep** — Funds held by any external WIF private key can be swept into the current wallet in one flow. The wizard resolves the key to P2WPKH, P2PKH, and P2SH-P2WPKH addresses, queries Electrum for UTXOs, and builds, signs, and broadcasts the sweep transaction with live fee-rate presets. Accessible via "Sweep WIF key" in the wallet import menu.

### Improvements
- **Fee presets extracted to reusable widget** — The economy / standard / priority fee preset selector is now a standalone `FeePresetsWidget` shared across the send screen and the WIF sweep screen.
- **Address detail layout** — The "Verify on device" and "Open in explorer" buttons in the address detail dialog are now stacked vertically for better readability on small screens.
- **`showTextExportSheet` extensible actions** — The text export bottom sheet now accepts optional `extraItems` to append custom actions below the built-in export options (used by the WIF export flow).
- **`showKeyspecSheet` returns seed material** — The key input sheet now returns a `KeyspecResult` record that includes the keyspec string and, when the user entered a seed, the mnemonic/passphrase/xprv — enabling the guided wallet wizard to store the hot key in a single step.
- **TextButton global style** — All `TextButton` instances now carry a subtle outline border matching the theme's outline colour, making them easier to distinguish from plain text on all screens.
- **Receive dialog scrollable** — The receive dialog is now marked `scrollable: true` to prevent overflow on small screens; address label is trimmed on save.
- **No-coins-selected error styling** — The "No coins selected" hint in the send screen is now shown in the error colour instead of secondary italic text.
- **Tor Electrum integration test** — Added `rust/tests/tor_electrum.rs` (`#[ignore]`), a manual integration test that bootstraps Tor and pings a user-supplied Electrum onion service.

---

## [v1.6.1]

### Improvements
- **Android release** — added `.apk.7z` artifact (7-zip max compression, ~45 MB) as a low-bandwidth alternative to the full APK (~151 MB).

## [v1.6.0]

### Security
- **Stronger Argon2id defaults** — Default KDF parameters raised to OWASP 2023 minimum (m=65536, t=3). Adding a new xpub slot to an existing wallet now inherits the slot parameters of the first existing slot for consistency.
- **MIT license added** — Repository now ships an explicit MIT license.
- **Pinned git fork dependencies** — `bitbox-api-rs` and `async-hwi` forks are now referenced by immutable commit SHA instead of branch name, preventing unintended upstream changes from being pulled on rebuild.

### New Features
- **Multi-recipient transactions** — The send screen now supports multiple outputs in a single transaction. Each recipient slot has its own address and amount field; one slot can be set to "MAX" (drain) to receive the remainder after all explicit outputs and fees. PSBT detail screen shows all outputs itemized with a "Total out" summary.
- **Direct send for hot single-sig wallets** — When a single-sig wallet has a locally available hot key, the send screen shows a "Send" button that signs and broadcasts the transaction in one step without going through the PSBT flow.
- **CPFP acceleration** — Unconfirmed transactions and coins show an "Accelerate" button that opens the send screen pre-loaded with the relevant UTXOs and a self-payment address, ready to build a child-pays-for-parent transaction. The ancestor package fee rate is shown in the send screen.
- **Tor routing** — Optional Tor support in Settings routes all Electrum connections through an embedded Tor client (arti). Persists across restarts.
- **Fee rate presets** — Three preset buttons (economy / standard / priority) appear above the fee fields in the send screen, fetching live rates from the configured block explorer (mempool.space by default). Selecting a preset updates both fee rate and total fee fields; editing manually deselects the preset.

### Improvements
- **RBF descendant tracking** — The RBF send screen now accounts for the full unconfirmed descendant cluster per BIP-125 Rule 4: the minimum absolute fee includes all descendant fees, and the minimum fee rate reflects the package rate of the entire conflict cluster.
- **Export/Import as bottom sheet** — The export and import choice menus in the wallet detail screen are now bottom sheets consistent with the rest of the app, instead of centered popup dialogs.
- **Mainnet Electrum privacy warning** — A persistent banner is displayed in the wallet detail screen when using a mainnet wallet with the default public Electrum server, with a direct link to Settings.
- **Share exports as files** — On mobile, sharing a PSBT, BIP-329 labels, or project now sends an actual file (`.psbt`, `.jsonl`, `.deadbolt.json`) via the native share sheet instead of raw text.
- **Simplified import/export for large content** — Project import and BIP-329 labels import/export now show only QR and file options, hiding clipboard and manual-paste for content too large for those flows.

### Fixes
- **RBF error messages** — When a replacement transaction fails validation, the error now distinguishes between fee rate too low (opens the rate field) and total fee too low (opens the total fee field), showing the exact minimum required in each case.
- **Labels missing from exported backups** — Wallet backups now capture a consistent database snapshot using `VACUUM INTO`, which consolidates any pending WAL writes into the exported file. Previously, labels set after the last checkpoint were silently omitted from the backup.
- **Duplicate sync spinner** — The wallet overview tab no longer shows a redundant sync spinner next to the last-synced timestamp; only the AppBar indicator remains.

---

## [v1.5.2]

### New Features
- **Guided wallet creation** — The Wallets tab + button now opens a bottom sheet with four options: Guided creation (new `SimpleWalletDialog` wizard), From descriptor, From project, and From backup.
- **Guided project creation** — The Designer tab + button now opens a bottom sheet with three options: From scratch, From descriptor, and Import project. The mode segmented button inside the dialog is gone.
- **BIP39 mnemonic entry field** — Mnemonic input in key derivation now uses a dedicated `MnemonicEntryField` widget with word-count indicator and inline error display.
- **BIP39 Rust API** — New `bip39Wordlist()` and `bip39ValidLastWords()` FFI functions expose the BIP39 English wordlist and valid-last-word filtering for mnemonic auto-complete.

### Fixes
- **Settings section label** — The "Defaults" section in Settings is now labelled "Wallet".
- **Connectivity field label clipping** — The first URL field label in the Electrum and Explorer sections was clipped by the expansion tile header; fixed with correct top padding.

### Improvements
- **Safe area fixes** — Bottom sheets and draggable sheet modals now correctly respect the system gesture bar on Android.
- **Threshold buttons now show tooltips** — The +/− threshold controls in the guided multisig wallet wizard display "Increase threshold" / "Decrease threshold" on hover for improved accessibility.

---

## [v1.5.1]

### New Features
- **Beta disclaimer** — A dismissible warning dialog appears on first launch (and every 7 days) reminding users the app is under active development and not yet suitable for real funds.
- **Security level selector at wallet creation** — When creating a password or xpub-protected wallet, users can now choose between Standard, High, and Extreme Argon2id resistance levels directly in the creation dialog (previously only changeable after the fact via Change Protection).
- **Auto-populated spend path for single-sig wallets** — When designing a single-sig project, the spend path is created automatically after the key is added, so the user never has to add it manually.

### Fixes
- **Descriptor checksum normalization** — Descriptors entered without a checksum are now stored with the correct BDK-canonical form, ensuring wallets created from those projects always use a valid descriptor.
- **Electrum broadcast errors now visible** — Errors from `sendrawtransaction` (which embed nested JSON in the message field) were silently swallowed due to a JSON parsing bug; they now display correctly as toasts.
- **sh(wpkh) spend path extraction** — Spend paths for P2SH-wrapped P2WPKH descriptors now correctly report key derivation chain indices.

### Improvements
- **Redesigned settings screen** — Settings are now grouped into four themed sections (Appearance, Defaults, Transactions, Connectivity), each in a card. Electrum and Explorer URL fields are collapsed by default inside the Connectivity card.
- **Redesigned protection section in create wallet dialog** — Protection type selector replaced with a compact `SegmentedButton` (None / Password / XPub). The security level selector is shown inline only when a keyed protection type is selected.

---

## [v1.5.0]

### New Features
- **XPub key protection (Type 2)** — Wallets can now be protected with any xpub from the descriptor. Each registered xpub receives its own encrypted slot in the `.meta` sidecar; any one of them unlocks the wallet. Hardware wallet users can unlock directly via BitBox02 without typing or pasting an xpub.
- **Change protection in-place** — A new "Encryption" button in the wallet overview and the wallet menu lets users switch between DeviceKey, Password, and XPub protection at any time, without exporting or importing the wallet. The database is re-keyed on the existing connection (no downtime, no backup required).
- **Selectable Argon2id security levels** — Change-protection and backup export now offer three resistance levels: Standard (~300 ms on mobile, 64 MB), High (~1.6 s, 256 MB), and Extreme (~5.5 s, 512 MB). Parameters were calibrated on real mid-range Android hardware.
- **Hardware wallet unlock for XPub wallets** — The XPub unlock dialog integrates with the BitBox02 flow: registered xpub slots are listed, the device root fingerprint is matched automatically, and the correct xpub is derived without manual input.

### Improvements
- Balance display in the wallet overview now cycles between sats, BTC, and fiat (when a price feed is configured) on tap.
- All full-screen loading spinners now display a descriptive status message (e.g. "Opening wallet…", "Loading wallet data…").
- Lock and unlock buttons in the wallet list are now a single `IconButton` in the trailing position, eliminating layout shift when toggling.
- XPub unlock dialog reorganized into two rows (secondary actions on top, primary actions below) to prevent overflow on narrow screens.

---

## [v1.4.1]

### New Features
- **All networks in project picker** — When creating a project from scratch, the network selector now shows all five networks (Mainnet, Testnet, Testnet4, Signet, Regtest). The selected network is then pre-filled when creating a wallet from that project.

---

## [v1.4.0]

### New Features
- **Hot signing keys** — Store encrypted private keys inside the app and sign PSBTs locally without any external device.
- **Password-protected wallets** — Wallets can be locked with a password; the key never leaves the device unencrypted.
- **Encrypted backup and import** — Export a wallet as an encrypted backup file and restore it on another device.
- **Locked-wallet indicator** — Locked wallets are shown in the wallet list with a lock icon so you can see their status at a glance without opening them.

### Improvements
- Redesigned project and wallet detail screens with a tab layout and sheet-based editing for a cleaner, more focused workflow.
- Guided empty state in the wallet screen when no project/wallet link exists yet, with a one-tap shortcut to navigate across.
- Cross-navigation between projects and wallets — tap the wallet badge on a project (or the project link on a wallet) to jump directly between them.
- PSBT signing and analysis now run in parallel, reducing wait time on multi-path descriptors.

---

## [v1.3.0]

### New Features
- **Hardware wallet support (BitBox02)** — Connect a BitBox02 via USB on Android, Linux, and Windows to register descriptors, fetch xpubs, and sign PSBTs directly from the device.

### Improvements
- Descriptor share button moved inside the expanded content card for a less cluttered header.

---

## [v1.2.0]

### New Features
- **Liana format export** — Export any descriptor in the format expected by the Liana wallet.
- **PSBT label inheritance** — Labels from matching spend paths and keys are pre-filled when constructing a PSBT, reducing manual annotation.

### Improvements
- Spent PSBT inputs are flagged visually; the delete menu item is styled in red to reduce accidental taps.
- Transaction list polish: confirmation badges, cleaner layout, and consistent icon sizing.

---

## [v1.1.3]

### New Features
- **BIP-329 label import/export** — Export and import wallet labels in the standard BIP-329 JSON format for interoperability with other wallets.
- **Receive dialog** — Generate and display a receive address directly from the wallet overview, with a QR code and copy button.
- **PSBT import and merge** — Import an existing PSBT and merge partial signatures into it, enabling multi-device signing workflows.
- **RBF validation** — The app detects Replace-By-Fee conflicts and warns before broadcasting a transaction that would be rejected.
- **Mempool ghost UTXOs** — Unconfirmed outputs from the mempool are shown in the coin list with a pending indicator.

### Improvements
- Wallet overview tab consolidates balance, recent transactions, and descriptor export in one place.
- Address status uses color-coded badges (unused / used / reused / with balance) for faster scanning.
- Spending badges appear on UTXOs currently being spent by a pending transaction.
- Settings are auto-saved on change without requiring an explicit save action.
- Outpoint strings use dynamic middle-truncation so the txid prefix and output index are always visible.
- Transaction and address detail dialogs use a two-column layout on wider screens.

---

## [v1.1.2]

### New Features
- **Label inheritance** — Labels assigned to keys and spend paths in a project are automatically suggested when the same key appears in a wallet, saving repetitive annotation work.
- **Entity detail dialogs** — Tap any transaction, address, or UTXO to open a full detail dialog with all available metadata.

### Fixes
- Errors during wallet operations (sync, broadcast, etc.) now appear as toasts instead of blocking the screen.
- Tapping the edit icon on a name field reliably opens the editor on the first tap.
- Address list scrolls correctly to the selected address after a sync.
- Timelock badge states are rendered accurately for all relative and absolute timelock combinations.
- Tab selection and lazily-loaded data are preserved when a sync completes while another tab is visible.

### Improvements
- Mobile navigation replaced hamburger drawer; Wallet tab opens by default for faster access to on-device wallets.
- Address transaction count is now accurate after rescanning.

---

## [v1.1.1]

### Improvements
- **Responsive UI during wallet operations** — Wallet reads (balance, transactions, addresses, UTXOs, PSBTs) now run on a background thread, eliminating freezes and Android ANR dialogs when opening or syncing a wallet.
- **Coin selector** — Choose specific UTXOs to spend when creating a transaction.
- **Inline fee and address editing** — Edit fee rate and recipient address directly in the create transaction screen without modal dialogs.
- **Send button as TX entry point** — Transaction creation is now accessed from the Send button in the wallet header for a cleaner flow.

---

## [v1.1.0]

### New Features
- **Wallet management** — Create, rename, and delete on-device Bitcoin wallets derived from any descriptor. Each wallet is an encrypted SQLite file stored in app support.
- **Electrum sync** — Sync wallet balances and transaction history against any Electrum server with automatic re-sync every 5 minutes.
- **PSBT workflow** — Create unsigned PSBTs with optional coin control and spend-path selection, merge partial signatures, and broadcast finalized transactions.
- **Addresses and coins tabs** — Browse all revealed addresses (receive/change) and unspent outputs with balances and confirmation status.
- **Key and path labels** — Label keys and spend paths per wallet, independent of project labels.

### Improvements
- Auto-sync starts immediately on wallet open and repeats every 5 minutes.
- QR export polish and consistent UI icons across wallet screens.

---

## [v1.0.4]

### New Features
- **Theme switching** — Choose between Light, Dark, or System default in Settings.
- **Project context menu** — Tap the menu on any project to edit its descriptor, export it, or delete it.

### Improvements
- All UI colors are now theme-aware; text and icons are legible in both light and dark modes.
- QR scanner progress bar repositioned to the top to avoid overlap with content.

---

## [v1.0.3]

### New Features
- **QR scanner** — Scan BC-UR animated QR codes to import descriptors on Android and Linux.
- **Export** — Share descriptors as QR codes or files, with platform-aware format selection.
- **Internationalization** — UI available in English and Spanish; language selectable in Settings.
- **Settings screen** — Configure default network, default wallet type, and language.
- **Always-visible "Add key" button** — Spend path cards show an inline button to add new keys without opening a menu.

### Improvements
- Import and export round-trip via QR fully supported on mobile and desktop.

---

## [v1.0.1]

### New Features
- **Taproot script path priorities** — Visual indicators for relative spend-path priority in Taproot descriptors.
- **NUMS xpub auto-generation** — Taproot descriptors without a keypath spend automatically get a NUMS placeholder.
- **Contextual loading messages** — Progress indicators show descriptive status text during analysis.
- **Simplified timelock UI** — Single timelock per spend path with badge-based editing (slider + live preview).
- **Project import/export** — Save and load projects as JSON files.
- **About screen and app icon** — App identity and version information.

### Fixes
- Derivation slot tracking now uses xpub correctly.
- Build number format changed to `YYMMDDHH` to fit Android `versionCode` limits.

---

## [v1.0.0]

Initial release of Deadbolt.

### Features
- Parse Bitcoin wallet descriptors (single-sig, multisig, Taproot).
- Extract network, wallet type, public keys, and spend paths.
- Display fee weight estimates per spend path.
- Label keys and spend paths per project.
- Persistent projects stored locally via SQLite.
- Re-analyze descriptors while preserving existing labels.
- Dark theme with orange accent.

[v1.9.7]: https://github.com/frijolo/deadbolt/releases/tag/v1.9.7
[v1.7.0]: https://github.com/frijolo/deadbolt/releases/tag/v1.7.0
[v1.6.2]: https://github.com/frijolo/deadbolt/releases/tag/v1.6.2
[v1.6.1]: https://github.com/frijolo/deadbolt/releases/tag/v1.6.1
[v1.6.0]: https://github.com/frijolo/deadbolt/releases/tag/v1.6.0
[v1.5.0]: https://github.com/frijolo/deadbolt/releases/tag/v1.5.0
[v1.4.1]: https://github.com/frijolo/deadbolt/releases/tag/v1.4.1
[v1.4.0]: https://github.com/frijolo/deadbolt/releases/tag/v1.4.0
[v1.5.2]: https://github.com/frijolo/deadbolt/releases/tag/v1.5.2
[v1.5.1]: https://github.com/frijolo/deadbolt/releases/tag/v1.5.1
[v1.9.6]: https://github.com/frijolo/deadbolt/releases/tag/v1.9.6
[v1.9.5]: https://github.com/frijolo/deadbolt/releases/tag/v1.9.5
[v1.9.4]: https://github.com/frijolo/deadbolt/releases/tag/v1.9.4
[v1.9.3]: https://github.com/frijolo/deadbolt/releases/tag/v1.9.3
[v1.9.2]: https://github.com/frijolo/deadbolt/releases/tag/v1.9.2
[v1.9.1]: https://github.com/frijolo/deadbolt/releases/tag/v1.9.1
[v1.9.0]: https://github.com/frijolo/deadbolt/releases/tag/v1.9.0
[v1.8.0]: https://github.com/frijolo/deadbolt/releases/tag/v1.8.0
[v1.7.1]: https://github.com/frijolo/deadbolt/releases/tag/v1.7.1
[v1.3.0]: https://github.com/frijolo/deadbolt/releases/tag/v1.3.0
[v1.2.0]: https://github.com/frijolo/deadbolt/releases/tag/v1.2.0
[v1.1.3]: https://github.com/frijolo/deadbolt/releases/tag/v1.1.3
[v1.1.2]: https://github.com/frijolo/deadbolt/releases/tag/v1.1.2
[v1.1.1]: https://github.com/frijolo/deadbolt/releases/tag/v1.1.1
[v1.1.0]: https://github.com/frijolo/deadbolt/releases/tag/v1.1.0
[v1.0.4]: https://github.com/frijolo/deadbolt/releases/tag/v1.0.4
[v1.0.3]: https://github.com/frijolo/deadbolt/releases/tag/v1.0.3
[v1.0.1]: https://github.com/frijolo/deadbolt/releases/tag/v1.0.1
[v1.0.0]: https://github.com/frijolo/deadbolt/releases/tag/v1.0.0
