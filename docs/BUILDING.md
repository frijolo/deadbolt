# Building Deadbolt from Source

## Prerequisites

- **Flutter SDK** (latest stable): [Install Flutter](https://docs.flutter.dev/get-started/install)
  Requires **Dart SDK ≥ 3.10.7** (bundled with Flutter — check your version with `dart --version`)
- **Rust toolchain** (latest stable): [Install Rust](https://rustup.rs/)
- **flutter_rust_bridge_codegen** 2.11.1:
  ```bash
  cargo install flutter_rust_bridge_codegen --version 2.11.1
  ```
- Platform-specific dependencies:
  - **Android**: Android SDK + NDK r26d
  - **Linux**: `libgtk-3-dev`, `clang`, `cmake`, `ninja-build`
  - **Windows**: Visual Studio 2022 with C++ tools

## Build Steps

```bash
# Clone repository
git clone https://github.com/frijolo/deadbolt.git
cd deadbolt

# Get Flutter dependencies
flutter pub get

# Build for your platform
flutter build apk --release       # Android
flutter build linux --release     # Linux
flutter build windows --release   # Windows

# Binaries will be in build/<platform>/release/
```

## Running Tests

```bash
# Dart/Flutter unit tests
flutter test
# NOTE: if you modified rust/src/api/, regenerate FFI bindings first:
#   flutter_rust_bridge_codegen generate

# Rust unit tests
cd rust && cargo test

# Linting
flutter analyze
cd rust && cargo clippy
cd rust && cargo machete   # checks for unused dependencies (matches CI)
```

## Integration Tests

Integration tests require a running display. Prepare the test build once after each code change, then run the Python regression scripts:

```bash
# Prepare test build (patches Rust bindings for headless use)
DISPLAY=:0 bash scripts/prepare_test_build.sh

# Run regression scripts (repeat for 01 through 09)
DISPLAY=:0 python3 scripts/regression_01_singlesig.py
DISPLAY=:0 python3 scripts/regression_02_multisig_wsh.py
# ...
DISPLAY=:0 python3 scripts/regression_09_restore_backup.py
```

## Regenerating FFI Bindings

If you modify the Rust API (`rust/src/api/`), regenerate the Dart bindings:

```bash
flutter_rust_bridge_codegen generate
```

Never edit files under `lib/src/rust/` by hand — they are auto-generated.
