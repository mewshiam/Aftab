# Building

<div dir="rtl">

## خلاصهٔ سریع

هستهٔ Rust را با cargo می‌سازید و آزمایش می‌کنید؛ اپلیکیشن را با flutter اجرا
می‌کنید. برای اپ روی ویندوز، یک بار باید اسکلت اجرایی ویندوز با
`flutter create` تولید شود (در ادامه توضیح داده شده).

</div>

## Prerequisites

| Tool | Version | Needed for |
|---|---|---|
| Rust toolchain | 1.75+ (`rustup default stable`) | core |
| A C compiler | gcc / clang / MSVC | core (cdylib, smoke test) |
| Flutter SDK | 3.22+ | app |
| Android SDK | API 35 (`flutter doctor` will guide) | Android builds |
| FFmpeg + Python/Pillow | any recent | regenerating fixtures/icons (optional) |

## Core (Rust)

```bash
cd core

# run the whole suite: unit + integration + fixture tests
cargo test

# lint gate used by CI
cargo fmt --check
cargo clippy --all-targets -- -D warnings

# release artifacts
cargo build --release
# → target/release/libaftab.so      (Android/Linux)
# → target/release/libaftab.a       (static)
```

### C-ABI smoke test (the C-consumer view)

```bash
cd core
cargo build --release
gcc -std=c11 -Wall -Wextra -Iinclude ffi/smoke.c \
    -Ltarget/release -laftab -lm -o /tmp/aftab-smoke
LD_LIBRARY_PATH=target/release /tmp/aftab-smoke
# → "all smoke checks passed"
```

On Windows (MSVC): `cl /Iinclude ffi\smoke.c /link target\release\aftab.dll.lib`
(after `cargo build --release`).

### Regenerating the media fixtures

```bash
tools/gen_media.sh          # FFmpeg clips for core/tests/fixtures/media/
cargo test --test media_fixtures
```

## App (Flutter)

```bash
cd app
flutter pub get

# static analysis (CI gate)
flutter analyze

# pure-Dart tests (no emulator needed)
flutter test

# Android phone/tablet + TV (one APK, both launchers)
flutter build apk --release

# run on a device
flutter run                 # mobile layout
flutter run -d <tv-device>  # TV layout (see below)
```

### Android notes

- The Android shell (`app/android/`) is committed: manifest with both
  `LAUNCHER` and `LEANBACK_LAUNCHER` intents, gradle files, launcher icons,
  and the TV banner.
- The native core must be present as `libaftab.so` inside the APK. The
  supported path is building it for the Android ABIs and letting the
  plugin-less app load it via `DynamicLibrary.open('libaftab.so')`. For
  local development, place the cross-compiled libraries under
  `app/android/app/src/main/jniLibs/<abi>/libaftab.so` (create the
  directory), then `flutter build apk`. ABIs worth building:
  `arm64-v8a` (phones/TV), `armeabi-v7a` (older phones),
  `x86_64` (emulators):
  ```bash
  rustup target add arm64-v8a armeabi-v7a x86_64   # aarch64-linux-android etc.
  cargo build --release --target aarch64-linux-android
  cp target/aarch64-linux-android/release/libaftab.so \
     app/android/app/src/main/jniLibs/arm64-v8a/libaftab.so
  ```
  (The NDK linker environment is required — see the Rust Android README.)
- CI (`.github/workflows/ci.yml`) builds the APK on every push using the
  hosted Android SDK; jniLibs for CI are produced by the workflow's
  `core-android` job.

### Windows notes

The Windows runner shell is intentionally not committed (it is generated
per-machine). One-time setup:

```bash
cd app
flutter create --platforms=windows .
```

Then, before `flutter run -d windows` / `flutter build windows`:

1. Build the core for Windows: `cargo build --release` with the
   `x86_64-pc-windows-msvc` toolchain → `aftab.dll`.
2. Copy `aftab.dll` next to the executable (or add a bundling step to
   `windows/CMakeLists.txt`).
3. `media_kit_libs_windows_video` already bundles `mpv-2.dll`
   automatically through its plugin packaging.

`flutter doctor -v` will tell you what else is missing (Visual Studio
"Desktop development with C++" workload is the usual item).

### Icons

```bash
python3 tools/gen_icons.py   # regenerates mipmap-* + assets/icons/icon-512.png
```

## CI

`.github/workflows/ci.yml` runs on every push and pull request:

| Job | Runner | Steps |
|---|---|---|
| `core-linux` | ubuntu-latest | fmt check, clippy `-D warnings`, full test suite, release build, gcc FFI smoke test |
| `core-windows` | windows-latest | full test suite, release build (MSVC) |
| `flutter-analyze` | ubuntu-latest | `pub get`, `flutter analyze`, `flutter test` |
| `flutter-apk` | ubuntu-latest | jniLibs build for 3 ABIs, `flutter build apk --release` |
| `flutter-windows` | windows-latest | core dll, `flutter create --platforms=windows .`, `flutter build windows --release` |

A green `core-linux` job is the strongest single signal: it means the
wire contract, failover, downloader, and FFI boundary all hold.
