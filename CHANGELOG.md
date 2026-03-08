# Changelog

All notable changes to Deadbolt are documented here, newest first.

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

[v1.0.4]: https://github.com/frijolo/deadbolt/releases/tag/v1.0.4
[v1.0.3]: https://github.com/frijolo/deadbolt/releases/tag/v1.0.3
[v1.0.1]: https://github.com/frijolo/deadbolt/releases/tag/v1.0.1
[v1.0.0]: https://github.com/frijolo/deadbolt/releases/tag/v1.0.0
