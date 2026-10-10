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
flutter build apk            # APK (موبایل + تی‌وی)
```

</div>

---

<div dir="ltr" align="left">

## Aftab Media (English summary)

Aftab Media is a ground-up, production-quality re-engineering of the [CCloud](https://github.com/code3-dev/CCloud) Android streaming app into a **cross-platform, Persian-first media platform** for Android, Android TV, and Windows. All data logic, Persian text normalization, search, provider failover, persistence, downloads, and URL safety live in a single **Rust core** (`aftab-core`) exposed through a stable **C-ABI FFI** boundary (`core/include/aftab.h`). Playback uses **libmpv** via `media_kit` on every platform, with a fully Material 3 cinematic player: user-styled libass subtitles (font, size, colors, outline, background, position, external files), complete playback settings (screen fit, zoom, speed, audio/subtitle sync, sleep timer, hardware decoding), and per-gesture touch controls (volume, brightness, scrub-seek, double-tap jump, hold-to-speed-up). The repository ships with full docs, an integration-tested provider (tested against a real local HTTP server), resumable downloads with HTTP `Range` support, atomic JSON persistence, SSRF protections for untrusted media URLs, and a GitHub Actions CI pipeline that builds and tests the core on Linux and Windows and analyzes/builds the Flutter app.

### Repository layout

| Path | Description |
|------|-------------|
| `core/` | Rust crate `aftab-core` — models, Persian normalization, search, HTTP, provider, store, download, URL safety, FFI |
| `core/include/aftab.h` | Public C header for the FFI boundary |
| `core/ffi/smoke.c` | C smoke test compiled with `gcc` against `libaftab` |
| `app/` | Flutter application (mobile, TV, and Windows entry points) |
| `docs/` | Architecture, building, design system, player, provider API contract, legal notes |
| `tools/` | Icon and test-media generation scripts |
| `.github/workflows/ci.yml` | CI: core tests on Linux+Windows, FFI smoke test, Flutter analyze + build |

### License

This project is licensed under **GPL-3.0** because it links **libmpv** (GPL-2.0-or-later). The original CCloud project is MIT-licensed; its copyright notice is preserved in [NOTICE.md](NOTICE.md). See [docs/LEGAL.md](docs/LEGAL.md) for the full compatibility analysis.

</div>
