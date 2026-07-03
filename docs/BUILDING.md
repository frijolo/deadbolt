# Building Deadbolt from Source

## Prerequisites

- **Flutter SDK** (latest stable): [Install Flutter](https://docs.flutter.dev/get-started/install)
  Requires **Dart SDK ≥ 3.10.7** (bundled with Flutter — check your version with `dart --version`)
- **Rust toolchain** (latest stable): [Install Rust](https://rustup.rs/)
- **flutter_rust_bridge_codegen** 2.12.0:
  ```bash
  cargo install flutter_rust_bridge_codegen --version 2.12.0
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

# Binaries will be in (path differs per platform):
#   build/app/outputs/flutter-apk/app-release.apk   (Android)
#   build/linux/x64/release/bundle/                 (Linux)
#   build/windows/x64/runner/Release/               (Windows)
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
cd rust && cargo clippy --all-features --all-targets -- -D warnings   # matches CI; plain `cargo clippy` won't lint test targets or fail on warnings
cd rust && cargo machete   # checks for unused dependencies (matches CI)
```

## Integration Tests

Integration tests require a running display. The easiest way to run the full
regression suite is `scripts/run_tests.sh`, which sets `DISPLAY=:0`, runs
`prepare_test_build.sh`, and then executes every `regression_NN_*.py` script
in order:

```bash
bash scripts/run_tests.sh                  # full build + all tests
bash scripts/run_tests.sh --rust-only      # skip Flutter rebuild, all tests
bash scripts/run_tests.sh --skip-build     # skip build entirely, all tests
bash scripts/run_tests.sh 01 03            # full build + only tests 01 and 03
```

To run scripts manually instead:

```bash
# Prepare test build (patches Rust bindings for headless use)
DISPLAY=:0 bash scripts/prepare_test_build.sh

# Run regression scripts (there are dozens under scripts/regression_NN_*.py —
# check `ls scripts/regression_*.py` for the current list)
DISPLAY=:0 python3 scripts/regression_01_singlesig.py
DISPLAY=:0 python3 scripts/regression_02_multisig_wsh.py
# ...
```

## Regenerating FFI Bindings

If you modify the Rust API (`rust/src/api/`), regenerate the Dart bindings:

```bash
flutter_rust_bridge_codegen generate
```

Never edit files under `lib/src/rust/` by hand — they are auto-generated.
