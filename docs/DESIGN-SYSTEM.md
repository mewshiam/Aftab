# سیستم طراحی آفتاب مدیا (Aftab Media Design System)

<div dir="rtl">

این سند سیستم طراحی رابط کاربری نسخهٔ بازطراحی‌شده (v0.2) را مستند می‌کند.
همهٔ توکن‌ها در کد منبع واحد هستند و از این سند مستقیماً به آن‌ها ارجاع داده می‌شود.

</div>

This document describes the v0.2 UI redesign's design system. Every token
lives in a single source of truth in the code; this document references
rather than duplicates decisions where possible.

---

## 1. Identity — «گوشهٔ نور» (Edge of Light)

<div dir="rtl">

هویت بصری از نام پروژه می‌آید: **آفتاب** (خورشید). سینما در تاریکی، و یک
رنگ کهربایی گرم مثل نور خورشید که از گوشهٔ پرده می‌تابد.

- **تیره (پیش‌فرض):** اتاق پروژکشن — پس‌زمینهٔ آبی-سیاه عمیق، رنگ اصلی کهربایی گرم.
- **روشن:** کاغذ گرم با کهربایی عمیق (کنتراست AA).
- تزئین اضافی نداریم: بدون شیشه‌کاری (glassmorphism)، بدون سایه‌های اضافی،
  بدون گوشه‌های گردِ بیش‌ازحد. **محتوا قهرمان است، نه قاب.**

</div>

The visual identity derives from the project's name — **Aftab** (sunshine):
a cinema in the dark with one warm amber accent. Dark is the default
(projector room); light is warm paper with deep amber for AA contrast.
No glassmorphism, no decorative shadows, no oversized rounding — content,
not chrome, is the hero.

## 2. Color (Material 3 roles)

Source: `app/lib/design/color_schemes.dart`, dynamic variant in
`app/lib/design/theme.dart` (`withDynamicColor`).

| Role | Dark | Light |
|---|---|---|
| `primary` | `#F6B545` (amber) | `#8A5400` (deep amber) |
| `onPrimary` | `#2A1A00` | `#FFFFFF` |
| `secondary` | `#A6C9BF` (slate-teal) | `#4A625B` |
| `tertiary` | `#E5B8C4` (rose) | `#7A564F` |
| `surface` | `#10131B` | `#FCF8F4` (warm paper) |
| `onSurface` | `#E7E9F0` | `#1C1B17` |
| `onSurfaceVariant` | `#B9BFCB` | `#4A473F` |
| `outline` | `#8A93A3` | `#7B776C` |
| `error` | `#FFB4AB` | `#93000A` |

- Semantic M3 roles only — screens never hard-code colors.
- **Theme modes:** system / light / dark (Settings → Appearance).
- **Dynamic color (Material You):** opt-in; on Android 12+ the wallpaper
  palette replaces the brand palette via `DynamicColorBuilder`; other
  platforms fall back to the brand schemes.

## 3. Typography — Vazirmatn

Source: `app/lib/design/typography.dart`, assets in `app/assets/fonts/`
(OFL licensed, license registered into the About → Licenses page).

- One family for Persian **and** Latin so mixed-direction titles stay
  visually consistent; platform fonts remain the glyph fallback.
- Bundled static weights: **400 / 500 / 600 / 700**.
- Scale (M3 names): `headlineMedium` 700, `titleLarge` 600,
  `titleMedium` 600, `bodyMedium` 400, `labelLarge` 600, `bodySmall`
  400 (variant color).
- TV multiplies the whole scale by **1.12×** (10-foot readability).
- **Digits are locale-aware** (`app/lib/utils/format.dart`): Persian
  ۰۱۲۳۴۵۶۷۸۹ with the Persian decimal mark **٫** under `fa`, Latin digits
  under `en`. Every number in the UI flows through these helpers.

## 4. Spacing, radius, elevation, motion

Source: `app/lib/design/tokens.dart`.

| Token | Values |
|---|---|
| Spacing | 4 / 8 / 12 / 16 / 24 / 32 / 48 dp; screen padding 12→16→24 by width class |
| Radius | sm 8, md 12, lg 16 (cards: md; deliberately restrained) |
| Elevation | cards flat (tonal surfaces); sheets/dialogs use container tones, not shadows |
| Motion | fast 150 ms, normal 250 ms, emphasized 400 ms; `Curves.easeOutCubic` |
| Reduced motion | every animation collapses to `Duration.zero` when the OS requests it (`AftabMotion.maybe`) |

## 5. Responsive & adaptive layout

Source: `app/lib/platform/form_factor.dart`, `app/lib/navigation/app_shell.dart`.

M3 window size classes:

| Width | Class | Navigation |
|---|---|---|
| < 600 | compact | bottom `NavigationBar` (5 destinations) |
| 600–839 | medium | `NavigationRail` (labels) |
| ≥ 840 | expanded | extended `NavigationRail`; two-pane Discover; Ctrl+1…5 |

Form factor resolution: **user TV override → Android leanback method
channel (`aftab/device`) → conservative ≥900 dp heuristic → desktop OS →
width class.** The TV toggle hot-swaps the shell without restart.

Destinations (one information architecture everywhere): خانه/Home،
کشف/Discover، جست‌وجو/Search، کتابخانه/Library، تنظیمات/Settings.

## 6. Components

All in `app/lib/components/`:

- **`AftabImage`** — artwork with disk cache (`image_cache.dart`, FNV-1a
  keys, 4096-file cap with oldest-first eviction), skeleton placeholder,
  graceful fallback icon, decode downsampling to the card's device pixels.
- **`PosterCard`** — 2:3 artwork, title, year · IMDb line, watch-progress
  strip, downloaded badge, full semantics label; `compact` for rails.
- **`WideCard`** — 16:9 landscape with progress + play chip
  (continue-watching rows).
- **`EpisodeTile`** — episode row with thumbnail and duration.
- **`MediaRail`** — titled horizontal rail with skeleton mode.
- **`HeroBanner`** — restrained featured strip (only when real artwork
  exists; 1.6× taller on TV).
- **`TvFocusable`** — scale 1.05 + 3 dp primary border + glow for D-pad focus.
- **`SkeletonBox` / `SkeletonPosterGrid` / `SkeletonRail`** — pulse
  placeholders (static under reduced motion).
- **`AftabErrorPane` / `AftabEmptyPane` / `AftabInlineError`** — plain
  language + retry or next-step actions; never a blank screen or dead end.

## 7. States

Every significant surface implements: initial loading (skeletons shaped
like the content), loaded, empty (with a useful next step), search-no-
results (with suggestions), network failure (retry), per-rail soft
failure (the rest of the page keeps working), missing artwork (fallback
icon), download failure (reason surfaced). Refresh: pull-to-refresh on
lists/grids, R key on TV.

## 8. RTL / LTR & localization

- `fa-IR` is the default locale; `en-US` is one Settings tap away. ARB
  templates: `app/lib/l10n/app_fa.arb` (template) + `app_en.arb`, class
  `S`, generated by `flutter gen-l10n` during `pub get`.
- All layout uses direction-aware primitives
  (`EdgeInsetsDirectional`, `PositionedDirectional`,
  `AlignmentDirectional`); no manual string reversal, no forced RTL for
  English.
- Mixed-direction text (English titles inside Persian UI) relies on the
  Unicode bidirectional algorithm; punctuation-joined metadata uses the
  `·` separator which renders neutrally in both directions.
- Player double-tap seek maps physical position to **logical** thirds so
  "back" stays under the start-side thumb in RTL.
- Plurals and numbers are locale-formatted (see §3).

## 9. Accessibility

- Semantic labels on every media card (title — type), image, and icon
  button; tooltips everywhere.
- Focus visibility: `focusColor` from the scheme; `TvFocusable` for
  D-pad unmistakability on TV.
- Touch targets ≥ 48 dp; TV targets larger via scale.
- State is never color-only (icons + text accompany every status).
- Reduced-motion respected by all animations and skeletons.
- Text scales with the OS setting (no fixed-height text containers).

## 10. Player chrome

Built around the unchanged `media_kit` (libmpv) engine:

- Auto-hiding gradient controls; tap toggles; any key/mouse shows.
- Seek bar with position/duration (locale digits), ±10 s buttons,
  double-tap thirds (touch), J/L ±10 s and arrows ±5 s (desktop).
- Volume slider + mute on desktop (hardware volume on mobile/TV).
- Settings sheet: speed (0.5–2×), audio track, subtitle track (incl.
  off), quality (movies, switching preserves position).
- Fullscreen (touch): landscape lock + immersive; restored on exit.
- Keyboard: Space/K play, J/L seek, ↑/↓ volume, M mute, F fullscreen,
  Esc exit. Media keys everywhere. TV keeps arrows free for D-pad.
- Buffering indicator; resume notice ("از ۱:۲۳ ادامه می‌دهیم").

## 11. Performance

- Disk-cached, decode-downsampled artwork; `RepaintBoundary` per card.
- `IndexedStack` keeps tab state (scroll positions, loaded pages).
- Debounced search (350 ms) with local Persian re-ranking in flight.
- Isolate-backed data calls (existing core pattern) — the UI thread
  never blocks on the network.
- const constructors throughout; analyzer-enforced.

## 12. Where tokens live

| Concern | File |
|---|---|
| Spacing / radius / motion / breakpoints | `lib/design/tokens.dart` |
| Color schemes | `lib/design/color_schemes.dart` |
| Theme assembly + dynamic color | `lib/design/theme.dart` |
| Typography | `lib/design/typography.dart` |
| Locale number/duration formatting | `lib/utils/format.dart` |
| Strings (fa/en) | `lib/l10n/app_*.arb` |
