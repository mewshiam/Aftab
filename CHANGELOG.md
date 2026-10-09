# گزارش تغییرات (Changelog)

همهٔ تغییرات قابل‌توجه این پروژه در این فایل ثبت می‌شوند.
قالب بر پایهٔ [Keep a Changelog](https://keepachangelog.com/fa/1.1.0/) است و
نسخه‌بندی از [Semantic Versioning](https://semver.org/spec/v2.0.0.html) پیروی می‌کند.

All notable changes to this project are documented in this file.
The format is based on Keep a Changelog, and versioning follows Semantic Versioning.

---

## [0.1.0] — ۲۰۲۶-۱۰-۰۹

نخستین انتشار عمومی آفتاب مدیا — بازنویسی مهندسی‌شدهٔ پروژهٔ CCloud به‌صورت
پلتفرم رسانه‌ای چندسکویی، فارسی-اول و متن-باز (GPL-3.0-or-later).

First public release of Aftab Media — an engineered rewrite of the CCloud
project as a cross-platform, Persian-first, open-source media platform.

### Added / افزوده شد

**هستهٔ Rust (`aftab-core` 0.1.0)**
- مدل‌های دادهٔ سازگار با قرارداد JSON کلاود (Movie/Series/Season/Episode/Genre/Country) با تجزیهٔ بخشندهٔ آرایه‌ها.
- نرمال‌سازی فارسی: تبدیل ی/ك عربی، حلقهٔ الف-مدّه، ارقام فارسی/عربی، نیم‌فاصله (ZWNJ) و کلیدهای فشردهٔ غیرحساس به نیم‌فاصله.
- موتور جست‌وجو با امتیازدهی چندسطحی (تطبیق کامل، پیشوند واژه، پیشوند، زیررشته، دنبالهٔ نویسه‌ای) و مرتب‌سازی فارسی.
- کلاینت API سازگار با CCloud برای هر ۷ نقطهٔ انتهایی، همراه با تعویض شفاف سرور (host-swap failover) و مشاهده‌پذیری منبع (Sourced/Origin).
- محافظ SSRF و اعتبارسنجی نشانی رسانه (پروتکل‌ها، IPv4/IPv6 با براکت، رد میزبان‌های خصوصی) و لاگ‌های sanitized.
- ذخیره‌سازی اتمی (JSON، نوشتن موقتاً + انتقال نام) برای علاقه‌مندی‌ها و پیشرفت تماشا.
- دانلود قابل ازسرگیری با پشتیبانی HTTP Range (206/200).
- پل FFI با C-ABI پایدار (`include/aftab.h`)، خطاهای کدگذاری‌شدهٔ thread-local، محافظ panic و مدیریت حافظهٔ صریح.

**رابط کاربری Flutter (0.1.0+1)**
- رابط فارسی-اول و راست‌به‌چپ با فونت وزیرمتن: خانه، کاتالوگ، جزئیات، جست‌وجو، علاقه‌مندی‌ها و تنظیمات.
- پخش‌کنندهٔ مبتنی بر libmpv (media_kit) با تعویض کیفیت و ذخیرهٔ پیشرفت تماشا هر ۵ ثانیه.
- صفحهٔ خانهٔ مخصوص اندروید تی‌وی با پیمایش فوکوس‌محور برای کنترل از راه دور.
- اتصال کامل به هستهٔ Rust از طریق dart:ffi با مدیریت per-isolate.

**پلتفرم‌ها / Platforms**
- اندروید و اندروید تی‌وی (LAUNCHER + LEANBACK_LAUNCHER، نمادها و بنر تی‌وی).
- ویندوز x64 (ساخت release همراه با `aftab.dll`).
- کتابخانه‌های بومی برای سه ریزمعماری اندروید (arm64-v8a، armeabi-v7a، x86_64).

**زیرساخت / Infrastructure**
- CI با ۶ کار روی ۲ سیستم‌عامل: هستهٔ لینوکس (fmt + clippy -D warnings + ۱۳۶ آزمون + آزمون دودی FFI با gcc)، هستهٔ ویندوز (آزمون‌ها + ساخت MSVC + dll)، تحلیل و آزمون Flutter، کامپایل متقابل NDK، APK انتشار و ساخت ویندوز.
- مستندات: `ARCHITECTURE.md`، `BUILDING.md`، `PROVIDER-API.md`، `LEGAL.md` (زنجیرهٔ GPL-3.0 با libmpv و ارجاع MIT پروژهٔ CCloud).
- ابزارها: تولید نماد و بنر (`tools/gen_icons.py`) و رسانه‌های آزمون CC0 (`tools/gen_media.sh`).

### Evidence / شواهد کیفیت
- ۱۳۶ آزمون واحد و یکپارچگی Rust (شامل سرورهای HTTP محلی واقعی) — سبز در CI.
- ۳۲ بررسی دودی C-ABI با gcc در CI.
- `flutter analyze --fatal-infos` و `flutter test` — سبز در CI.
- همهٔ ۶ کار CI روی لینوکس و ویندوز سبز.

### Compatibility / سازگاری
- API سازگار با سرویس CCloud؛ کلید API همان ثابت عمومی سرویس بالادستی است.
- معماری‌های پشتیبانی‌شدهٔ اندروید: arm64-v8a، armeabi-v7a، x86_64.
- حداقل نسخهٔ Rust هسته: 1.75؛ مجموعهٔ SDK Dart: ≥3.3.

---

## [Unreleased]

تغییرات پس از این انتشار در بخش «Unreleased» ثبت می‌شوند تا در انتشار بعدی منتقل شوند.

[Unreleased]: https://github.com/mewshiam/Aftab/compare/v0.1.0...HEAD
[0.1.0]: https://github.com/mewshiam/Aftab/releases/tag/v0.1.0

