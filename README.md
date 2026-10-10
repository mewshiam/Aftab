<div dir="rtl" align="center">

# آفتاب مدیا (Aftab Media)

**پخش‌کنندهٔ رسانهٔ چندسکویی، فارسی-اول — اندروید، اندروید تی‌وی و ویندوز**

[![CI](https://github.com/mewshiam/Aftab/actions/workflows/ci.yml/badge.svg)](https://github.com/mewshiam/Aftab/actions/workflows/ci.yml)
[![License: GPL-3.0](https://img.shields.io/badge/License-GPL--3.0-blue.svg)](LICENSE)
[![Core: Rust](https://img.shields.io/badge/core-Rust-dea584?logo=rust)](core/)
[![UI: Flutter](https://img.shields.io/badge/UI-Flutter-02569B?logo=flutter)](app/)

</div>

---

<div dir="rtl" align="right">

## آفتاب مدیا چیست؟

آفتاب مدیا نسخهٔ بازنویسی‌شده و مهندسی‌شدهٔ پروژهٔ [CCloud](https://github.com/code3-dev/CCloud) است که از یک اپلیکیشن صرفاً اندرویدی (Kotlin + Jetpack Compose + ExoPlayer) به یک **پلتفرم رسانه‌ای چندسکویی** تبدیل شده است. هدف این پروژه ارائهٔ یک تجربهٔ تماشای فیلم و سریال با کیفیت، با معماری واقعی، مستندسازی کامل، آزمون‌های خودکار و یکپارچگی مداوم (CI) است.

### چرا بازنویسی؟

اپلیکیشن اصلی CCloud فقط برای اندروید نوشته شده بود و منطق داده، شبکه و پخش در لایهٔ UI آن گره خورده بود. آفتاب مدیا این منطق را به یک **هستهٔ Rust** منتقل می‌کند که:

- **یک بار نوشته می‌شود، همه‌جا اجرا می‌شود** — همان هسته از طریق FFI (C-ABI) روی اندروید، اندروید تی‌وی و ویندوز به کار می‌رود.
- **تست‌پذیر است** — ۱۳۷ آزمون واحد و یکپارچگی روی خودِ هسته (شامل سرور HTTP محلی برای آزمون‌های واقعی شبکه) + ۷۹ آزمون Dart/ویجت روی رابط کاربری؛ آنالیز `--fatal-infos` پاک.
- **امن است** — مرتب‌سازی فارسی و نرمال‌سازی یونیکد، محافظ SSRF روی نشانی‌های رسانه، و اعتبارسنجی ورودی‌ها در مرز FFI.

### امکانات کلیدی

- 🎨 **سیستم طراحی Material 3** — پالت روشن/تیره/پویا (Material You)، توکن‌های متمرکز، فونت وزیرمتن با ارقام بومی؛ مستندات کامل در [DESIGN-SYSTEM.md](docs/DESIGN-SYSTEM.md)
- 🧭 **ناوبری تطبیقی** — نوار پایین در گوشی، ریل در تبلت، ریل گسترده + میان‌برهای صفحه‌کلید در ویندوز، و پوستهٔ ۱۰-فوتی برای کنترل از راه دور در تی‌وی
- 🏠 **خانهٔ اکتشافی** — «ادامهٔ تماشا»، بنر منتخب، ریل‌های برترین فیلم‌ها/سریال‌ها و تازه‌ها
- 🔎 **کشف و جست‌وجوی درجه‌یک** — فیلتر ژانر/نوع/مرتب‌سازی، جست‌وجوهای اخیر، شمارش نتایج و رتبه‌بندی فارسی هسته
- 📺 **پخش‌کنندهٔ سینمایی متریال ۳ با libmpv** — زیرنویس‌های libass با استایل کامل کاربر (قلم/اندازه/رنگ/دورخط/پس‌زمینه/جای‌گذاری + بارگذاری زیرنویس خارجی)، تنظیمات کامل پخش (اندازهٔ صفحه، بزرگ‌نمایی، سرعت، تأخیر صدا/زیرنویس، زمان‌سنج خواب، رمزینه‌سازی سخت‌افزاری) و ژست‌های لمسی (صدا، روشنایی، جابه‌جایی زمان، دوضربه، نگه‌داشتن برای ۲×) — همه قابل تنظیم در تنظیمات ← پخش‌کننده؛ مستندات کامل در [PLAYER.md](docs/PLAYER.md)
- ❤️ **کتابخانهٔ واقعی** — علاقه‌مندی‌ها، ادامهٔ تماشا و دانلودهای آفلاین (دانلودکنندهٔ قابل-ازسرگیری هسته)
- 🌐 **فارسی-اول + انگلیسی** — راست‌به‌چپ/چپ‌به‌راست صحیح، ارقام فارسی/لاتین، تعویض زبان زنده
- ♿ **دسترس‌پذیری** — برچسب‌های معنایی، فوکوس قابل‌مشاهده، احترام به «کاهش حرکت»، وضعیت‌های کامل (اسکلت/خالی/خطا)

### معماری در یک نگاه

```
┌─────────────────────────────────────────────────────┐
│  رابط کاربری Flutter (فارسی/انگلیسی، RTL/LTR، طراحی M3) │
├─────────────────────────────────────────────────────┤
│  FFI (C-ABI) — include/aftab.h                      │
├─────────────────────────────────────────────────────┤
│  هستهٔ Rust (aftab-core)                             │
│  • model    مدل‌های داده (Movie/Series/Season/…)     │
│  • persian  نرمال‌سازی و مرتب‌سازی فارسی              │
│  • search   امتیازدهی و رتبه‌بندی جست‌وجو              │
│  • http     کلاینت HTTP با مهلت زمانی                 │
│  • provider کلاینت API کلاود + تعویض سرور             │
│  • store    ذخیره‌سازی اتمی علاقه‌مندی/پیشرفت          │
│  • download دانلود قابل ازسرگیری                       │
│  • urlsafe  محافظ SSRF و اعتبارسنجی نشانی             │
├─────────────────────────────────────────────────────┤
│  libmpv (پخش)  +  پلتفرم (Android / Windows)        │
└─────────────────────────────────────────────────────┘
```

مستندات کامل: [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md) · [راهنمای ساخت](docs/BUILDING.md) · [قرارداد API](docs/PROVIDER-API.md)

### ساخت سریع

هستهٔ Rust (شامل همهٔ آزمون‌ها):

```bash
cd core
cargo test
cargo build --release
```

اپلیکیشن Flutter:

```bash
cd app
flutter pub get
flutter run                  # اندروید
flutter run -d windows       # ویندوز
flutter build apk                        # APK جهانی (موبایل + تی‌وی)
flutter build apk --split-per-abi        # APK جداگانه برای هر معماری
```

### دانلود

آخرین انتشار‌ها: [github.com/mewshiam/Aftab/releases](https://github.com/mewshiam/Aftab/releases)

| بسته | برای |
|---|---|
| `aftab-…-android-universal.apk` | همهٔ دستگاه‌ها (arm64 + arm32 + x64) |
| `aftab-…-android-arm64-v8a.apk` | گوشی‌ها و تی‌وی‌های مدرن |
| `aftab-…-android-armeabi-v7a.apk` | گوشی‌های ۳۲-بیتی قدیمی‌تر |
| `aftab-…-android-x86_64.apk` | شبیه‌سازها و کروم‌بوک‌های اینتلی |
| `aftab-…-windows-x64.zip` | ویندوز ۶۴-بیتی |

انتشار‌ها خودکارند: هر تگ `v*` گردش‌کار `release.yml` را اجرا می‌کند و همهٔ بسته‌ها + `SHA256SUMS.txt` را منتشر می‌کند. Android x86 (۳۲-بیتی اینتلی) از سمت موتور Flutter حذف شده ([flutter#169884](https://github.com/flutter/flutter/pull/169884)) و APK جداگانه ندارد؛ `libaftab.so` برای x86 در بستهٔ jniLibs هسته هست. اپ ویندوز فقط x64 است (نسخهٔ ۳۲-بیتی از موتور Flutter و libmpv وجود ندارد)؛ `aftab.dll` برای x64 و x86 در بستهٔ DLLهای هسته هست.

</div>

---

<div dir="ltr" align="left">

## Aftab Media (English summary)

Aftab Media is a ground-up, production-quality re-engineering of the [CCloud](https://github.com/code3-dev/CCloud) Android streaming app into a **cross-platform, Persian-first media platform** for Android, Android TV, and Windows. All data logic, Persian text normalization, search, provider failover, persistence, downloads, and URL safety live in a single **Rust core** (`aftab-core`) exposed through a stable **C-ABI FFI** boundary (`core/include/aftab.h`). Playback uses **libmpv** via `media_kit` on every platform, with a fully Material 3 cinematic player: user-styled libass subtitles (font, size, colors, outline, background, position, external files), complete playback settings (screen fit, zoom, speed, audio/subtitle sync, sleep timer, hardware decoding), and per-gesture touch controls (volume, brightness, scrub-seek, double-tap jump, hold-to-speed-up). The repository ships with full docs, an integration-tested provider (tested against a real local HTTP server), resumable downloads with HTTP `Range` support, atomic JSON persistence, SSRF protections for untrusted media URLs, and a GitHub Actions CI pipeline that builds and tests the core on Linux and Windows and analyzes/builds the Flutter app; every `v*` tag automatically publishes a release with per-ABI Android APKs and the Windows build.

### Repository layout

| Path | Description |
|------|-------------|
| `core/` | Rust crate `aftab-core` — models, Persian normalization, search, HTTP, provider, store, download, URL safety, FFI |
| `core/include/aftab.h` | Public C header for the FFI boundary |
| `core/ffi/smoke.c` | C smoke test compiled with `gcc` against `libaftab` |
| `app/` | Flutter application (mobile, TV, and Windows entry points) |
| `docs/` | Architecture, building, design system, player, provider API contract, legal notes |
| `tools/` | Icon and test-media generation scripts |
| `.github/workflows/` | `ci.yml` — gates + builds on every push/PR; `release.yml` — automated release on every `v*` tag |

### Downloads

Latest release: [github.com/mewshiam/Aftab/releases](https://github.com/mewshiam/Aftab/releases)

| Asset | For |
|---|---|
| `aftab-…-android-universal.apk` | every device (arm64 + arm32 + x64) |
| `aftab-…-android-arm64-v8a.apk` | modern phones & Android TVs |
| `aftab-…-android-armeabi-v7a.apk` | older 32-bit ARM phones |
| `aftab-…-android-x86_64.apk` | Intel emulators & Chromebooks |
| `aftab-…-windows-x64.zip` | 64-bit Windows |

Releases are automated: pushing a `v*` tag runs `.github/workflows/release.yml`, which re-runs the full quality gates, builds every variant, and publishes the release with `SHA256SUMS.txt`. Android x86 (32-bit Intel) has no separate APK — the Flutter engine dropped it ([flutter#169884](https://github.com/flutter/flutter/pull/169884)) — but the x86 `libaftab.so` ships in the core jniLibs asset. The Windows app is x64-only (no 32-bit Flutter engine or libmpv exists); a 32-bit `aftab.dll` ships in the core DLLs asset for native embedders.

### License

This project is licensed under **GPL-3.0** because it links **libmpv** (GPL-2.0-or-later). The original CCloud project is MIT-licensed; its copyright notice is preserved in [NOTICE.md](NOTICE.md). See [docs/LEGAL.md](docs/LEGAL.md) for the full compatibility analysis.

</div>
