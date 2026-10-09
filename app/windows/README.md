# Windows platform notes

<div dir="rtl">

## چکیده

پوستهٔ اجرایی ویندوز (runner) تولیدشده توسط `flutter create` است و در
مخزن نگه‌داری نمی‌شود؛ اما همهٔ اجزای خاصِ پروژه — DLL هسته، بسته‌بندی
mpv و نکات مسیر یابی — این سند و CI پوشش می‌دهند.

</div>

## One-time setup (per machine)

```powershell
cd app
flutter create --platforms=windows .
```

This generates `windows/runner`, `windows/CMakeLists.txt`, and the plugin
registration. It is intentionally **not committed**: it is machine-generated
scaffolding, identical for every project, and regenerating it is one command.

## The core DLL

`DynamicLibrary.open('aftab.dll')` in `lib/core/aftab_ffi.dart` resolves
against the executable's directory (and `PATH`). Build and place it:

```powershell
cd core
cargo build --release                 # → target\release\aftab.dll
copy target\release\aftab.dll ..\app\windows\runner\Release\
```

CI (`flutter-windows` job) does this automatically after the build —
download the `aftab-windows-build` artifact for a ready-to-run folder.

### Optional: bundle automatically via CMake

After `flutter create`, you can append a bundling rule to
`windows/CMakeLists.txt` (inside the `add_executable` target section):

```cmake
# Bundle the Aftab core next to the executable.
set(AFTAB_DLL "$ENV{AFTAB_DLL_PATH}")
if(EXISTS "${AFTAB_DLL}")
  add_custom_command(TARGET ${BINARY_NAME} POST_BUILD
    COMMAND ${CMAKE_COMMAND} -E copy_if_different
            "${AFTAB_DLL}"
            "$<TARGET_FILE_DIR:${BINARY_NAME}>/aftab.dll")
endif()
```

…with `AFTAB_DLL_PATH` pointing at the release DLL. The CI job copies the
file directly instead, which is simpler and equally correct.

## libmpv

`media_kit_libs_windows_video` (in `pubspec.yaml`) bundles `mpv-2.dll`
through the Flutter plugin mechanism — no manual steps. The plugin places
it next to the built executable at build time.

## Requirements

- Visual Studio 2022 with the "Desktop development with C++" workload.
- Windows 10 1809+ (matching libmpv builds).
- `flutter doctor -v` must show the Windows toolchain as green.

## Known platform specifics

- The store file lives in `%APPDATA%\<app>\aftab-store.json` via
  `path_provider`'s `getApplicationSupportDirectory()`.
- Watch progress and favorites use the same core code path as Android —
  the file is portable between machines.
- Persian text shaping is handled by Flutter's HarfBuzz integration; no
  platform font installation is needed for the UI (system fonts cover
  Arabic-script shaping on Windows 10+).
