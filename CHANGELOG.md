# Changelog

All notable changes to Deadbolt are documented here, newest first.

---

## [Unreleased]

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

[v1.5.0]: https://github.com/frijolo/deadbolt/releases/tag/v1.5.0
[v1.4.1]: https://github.com/frijolo/deadbolt/releases/tag/v1.4.1
[v1.4.0]: https://github.com/frijolo/deadbolt/releases/tag/v1.4.0
[v1.5.2]: https://github.com/frijolo/deadbolt/releases/tag/v1.5.2
[v1.5.1]: https://github.com/frijolo/deadbolt/releases/tag/v1.5.1
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
