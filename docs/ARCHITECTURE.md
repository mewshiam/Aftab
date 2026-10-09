# Architecture

<div dir="rtl">

## نگاه کلی

آفتاب مدیا از یک تصمیم معماری بنیادین پیروی می‌کند: **تمام منطق غیرِ‌رابط‌کاربری در یک هستهٔ Rust واحد زندگی می‌کند** و رابط Flutter فقط «رنگ و حرکت» است. این تصمیم سه دلیل دارد. نخست، سازگاری بین پلتفرم‌ها: منطق داده‌ای که یک بار در Rust نوشته و آزموده شود، روی اندروید، اندروید تی‌وی و ویندوز بدون بازنویسی و بدون واگرایی رفتار اجرا می‌شود. دوم، آزمون‌پذیری: هسته با ۱۳۶ آزمون واحد و یکپارچگی (شامل سرورهای HTTP محلی واقعی) پوشش داده شده است — چنین پوششی در لایهٔ UI هرگز عملی نیست. سوم، امنیت: اعتبارسنجی نشانی‌ها و محافظ SSRF باید در یک مرز واحد و قابل‌ممیزی انجام شود، نه پراکنده در هر صفحهٔ Dart.

</div>

## The layer cake

```
┌───────────────────────────────────────────────────────────────┐
│                     Flutter (app/)                             │
│                                                               │
│  ui/            tv/            player/                         │
│  home, catalog, tv home        mpv player screen               │
│  detail, search, favorites     (media_kit → libmpv)            │
│  settings                                                     │
│                                                               │
│  core/  aftab_ffi.dart  catalog.dart  store.dart  models.dart  │
│         (dart:ffi bindings, isolate-wrapped)                  │
├────────────── C-ABI boundary: core/include/aftab.h ───────────┤
│                                                               │
│                     Rust core (core/, crate aftab)             │
│                                                               │
│  model.rs      the CCloud JSON contract, lenient parsing      │
│  persian.rs    Arabic→Farsi folding, ZWNJ policy, digits      │
│  search.rs     exact/word-prefix/prefix/substring/subsequence │
│  http.rs       ureq (rustls) client, Range support             │
│  provider.rs   7 endpoints + helper-server failover           │
│  store.rs      atomic JSON persistence                        │
│  download.rs   resumable downloads (206/200)                  │
│  urlsafe.rs    SSRF guard, IPv6-safe, redaction               │
│  error.rs      stable numeric taxonomy                        │
│  ffi.rs        panic-guarded C-ABI surface                    │
├───────────────────────────────────────────────────────────────┤
│  libmpv (GPL-2.0-or-later) · platform (Android / Windows)     │
└───────────────────────────────────────────────────────────────┘
```

## Why Rust for the core

The upstream CCloud app implements its data layer in Kotlin with OkHttp +
`org.json`, directly inside ViewModels. That works for one platform, but it
means Persian text handling, failover, and URL validation live in code that
cannot be exercised without an Android emulator. The Rust core inverts
that: the same logic that runs in production runs under `cargo test`
against fixture HTTP servers on any machine — and the C-ABI it exposes is
the *only* way the UI can reach it. There is no second implementation to
drift.

## The FFI contract

`core/include/aftab.h` is the single source of truth for the boundary. Its
rules:

1. **Ownership is explicit.** Heap strings come back as `char *` and are
   freed by `aftab_free_string`. Handles are opaque pointers with matching
   `*_free` functions. Dart's `AftabRaw`/`AftabFfi` wrap every call so a
   leak is impossible by construction.
2. **Errors are codes.** A failure leaves a numeric code (and message) in a
   thread-local slot; `AftabException` in Dart carries that code. No
   NULL-dereference paths exist.
3. **No panics cross.** Every entry point is wrapped in
   `catch_unwind`; a panic degrades to `AFTAB_UNKNOWN` instead of UB.
4. **Threading.** Provider calls are read-only and safe to run
   concurrently; store calls serialize through a mutex. The Dart layer
   additionally runs every catalog/store call inside `Isolate.run`, so the
   platform thread never blocks on the network.

The contract is verified from the C side itself: `core/ffi/smoke.c` is
compiled with plain `gcc` against the built `libaftab` and asserts 32
behaviors — the same view a Windows linker or a future native consumer
would have.

## Persian text pipeline

All Persian-aware matching flows through two functions in `persian.rs`:

- **`normalize_persian`** — canonical storage/display form. Folds Arabic
  codepoints to their Farsi equivalents (ي→ی، ك→ک، ة→ه، أ/إ/ٱ→ا), unifies
  Persian and Arabic-Indic digits to ASCII, strips tatweel and combining
  diacritics, and collapses whitespace. ZWNJ (نیم‌فاصله) is *preserved*
  because stored text should stay typographically correct.
- **`compact_key`** — matching form. Everything above, plus ZWNJ removal,
  alef-madda folding (آ→ا — so «آفتاب» and «افتاب» are the same key), and
  ASCII lowercasing.

`search.rs` then scores structurally: exact (100) > word-prefix (85) >
prefix (80+bonus) > substring (60+bonus) > subsequence (25+coverage). The
subsequence tier is what makes sloppy remote input («سطن» → «سلطان»)
findable on a twelve-key TV remote.

## Provider and failover

`provider.rs` reproduces the upstream wire contract exactly (see
[PROVIDER-API.md](PROVIDER-API.md)): the same paths, the same JSON shapes,
the same helper-server host-swap failover. Two deliberate improvements:

- Failover is **observable**: every response carries its `Origin`
  (primary or helper #N) and the server that answered, so tests and the
  settings screen can show which mirror is alive.
- Malformed array items are **skipped, not fatal** — mirroring upstream's
  `catch { continue }` loops, but pinned by tests (including the
  "all items bad" degenerate case, which is an error, not an empty list).

## URL safety

Every URL that arrives *from the API* (as opposed to app configuration)
must pass `urlsafe::check_url` before the player or downloader touches it:
http/https only, no userinfo, host resolves to a public address
(loopback/private/link-local/multicast/CGNAT/doc ranges all refused,
IPv6 brackets handled). Trusted app configuration (the provider base and
helpers) is exempt — otherwise local fixture testing and mirrors on
private networks would be impossible. `redact_url_for_log` keeps
scheme/host/port and drops everything else, so diagnostics stay useful
without leaking API keys embedded in paths.

## Persistence

`store.rs` is one JSON document per install, written atomically
(temp file + rename). A crash mid-write leaves either the old or the new
state — never a truncated file. The schema carries a version and refuses
to open documents from a newer schema, which makes future migrations safe.

## Playback

Playback is libmpv (`media_kit` on every platform — `media_kit_libs_android_video`
and `media_kit_libs_windows_video` bundle the backend). The player screen
persists watch progress through the Rust store every five seconds and on
exit; quality switching re-opens the media at the new URL while the store
keeps its position keyed by content id, not by URL — so switching quality
keeps your place.

## What deliberately stays out of the core

- Anything visual: colors, layout, widgets.
- Platform channels: the core is pure C-ABI, no Flutter plugin code.
- Secrets: the API key is a *wire constant* inherited from upstream, never
  an authentication credential of the user, and no tokens ever enter the
  repository or the store.

## Testing strategy

| Layer | Evidence |
|---|---|
| Pure text logic | 114 unit tests across `persian`, `search`, `model`, `urlsafe`, `store`, `error` |
| Provider wire behavior | 11 integration tests against a **real local HTTP server** (`tests/common/mod.rs`), covering paths, failover, lenient parsing, unreachable-everything |
| Downloader | 8 integration tests: 200 full transfer, 206 resume, range-blind restart, progress callbacks, strict policy |
| FFI boundary | 32-check C smoke test compiled with `gcc` against `libaftab` |
| Media fixtures | 3 integrity tests (existence, `ftyp` box, pairwise distinct) |
| Dart | Pure-Dart model/progress tests (`app/test/`), plus `flutter analyze` and platform builds in CI |

The fixture server is a real TCP listener with a real HTTP/1.1 parser —
not a mock of our own client. Only the *remote server* is synthesized,
which is precisely the boundary tests should fake.
