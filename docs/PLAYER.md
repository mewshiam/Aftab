# The Aftab player — پخش‌کنندهٔ آفتاب

<div dir="rtl" align="right">

مستند فنی پخش‌کنندهٔ آفتاب مدیا: معماری، موتور پخش، زیرنویس‌های
قابل‌استایل، تنظیمات پخش، ژست‌های لمسی و کلیدهای ذخیره‌سازی.

</div>

---

## 1. Engine & rendering

Playback is **libmpv** through [`media_kit`](https://pub.dev/packages/media_kit)
on every supported platform (Android, Android TV, Windows). One deliberate
change from the earlier revisions:

```dart
Player(
  configuration: const PlayerConfiguration(
    libass: true,
    libassAndroidFont: 'assets/fonts/Vazirmatn-Regular.ttf',
    libassAndroidFontName: 'Vazirmatn',
  ),
)
```

`libass: true` moves subtitle rendering **into the video texture** (mpv +
libass) instead of media_kit's Flutter-widget `SubtitleView`. This is what
makes deep subtitle styling possible: the user's font, size, colors,
outline, background and position decisions are rendered by the same
engine mpv uses for its own OSD, frame-accurate and platform-identical.

Font availability:

| Platform | How bundled Vazirmatn reaches libass |
|---|---|
| Android | media_kit stages `libassAndroidFont` into the app's cache dir and sets `sub-fonts-dir` + `sub-font` before `mpv_initialize` |
| Windows | the player copies `Vazirmatn-*.ttf` from assets into `<app-support>/subtitle-fonts/` and sets `sub-fonts-dir` (before opening the media) |
| Any | generic families (`sans-serif`, `serif`, `monospace`) resolve via fontconfig against system fonts; arbitrary installed family names can be typed in the picker |

## 2. The property bridge

All custom playback behavior funnels through thin, fault-tolerant
wrappers in `lib/player/mpv_bridge.dart`:

- `applySubtitleStyle(player, style)` — pushes the whole `sub-*` set
- `addExternalSubtitle(player, path)` — `sub-add <path> select <title>`
- `applyVideoFit / applyZoom / setSubtitleDelay / setAudioDelay / applyHwDecoding / applySubtitleFontsDir / enableSidecarSubtitleAutoload`

Every call is `try`-guarded: a cosmetic preference can never break
playback. The **pure** mappings (what value goes to which property) live
in `subtitle_style.dart` and `playback_options.dart` and are unit-tested
without a player.

## 3. Subtitle styling

The complete user-controllable style (`SubtitleStyle`) and its mpv
vocabulary:

| Field | mpv property | Default | Range / notes |
|---|---|---|---|
| `fontFamily` | `sub-font` | `Vazirmatn` | presets + any installed family |
| `fontSize` | `sub-font-size` | `38` | 16–96; scaled px @ 720p window |
| `color` | `sub-color` | `#FFFFFFFF` | `#AARRGGBB`, **alpha first** |
| `outlineSize` | `sub-outline-size` | `3` | 0–8; 0 disables outline |
| `outlineColor` | `sub-outline-color` | `#FF000000` | |
| `background` | `sub-back-color` | `#00000000` | per-line box, alpha supported |
| `bold` / `italic` | `sub-bold` / `sub-italic` | `no` | fake-bold/italic |
| `position` | `sub-pos` | `100` | 50–130; 100 = default bottom |
| `overrideEmbedded` | `sub-ass-override` | `no` | `force` reapplies this look to ASS subs too |

Plain-text subtitles (SRT/VTT/…) are styled directly; ASS subtitles keep
their authored look unless *Override embedded styles* is enabled (a
deliberate opt-in because it can flatten karaoke/typesetting on purpose).

Editing surfaces, both backed by the same model:

- **Settings → Player → Subtitle appearance** — full editor with a live
  libass-like preview (stroke-rendered outline, background box, 720p
  scale factor, position mapping) and a reset action.
- **Player → ⚙ → Subtitle appearance** — pushes the same editor on a
  dark M3 route and applies every change to the running playback live.

**External subtitles.** The subtitle sheet offers *Add subtitle file…*
(`file_picker`, any file — mpv probes content, no extension filter that
could break platform pickers). The file is added via `sub-add … select`
and immediately becomes the active track; failure surfaces as a snackbar.
Sidecar files next to a downloaded video (matching or fuzzy names)
auto-load via `sub-auto=fuzzy`.

## 4. Playback settings

| Setting | Values | mpv |
|---|---|---|
| Screen fit | Fit / Stretch / Crop to fill / 16:9 / 4:3 / 2.35:1 | `video-aspect-override` (`no`/`W:H`/float) + `panscan` (0/1) |
| Zoom | −1 … +2 in 0.25 steps (2×…0.5×) | `video-zoom` (log2) |
| Speed | presets + free slider | `Player.setRate` (0.25–4×) |
| Audio delay | ±0.5/0.1 s steps, live | `audio-delay` |
| Subtitle delay | ±0.5/0.1 s steps, live | `sub-delay` |
| Sleep timer | off / 15 / 30 / 45 / 60 min | Flutter-side timer → pause + notice |
| Hardware decoding | on/off | `hwdec` = `auto-safe` / `no` |

`Stretch` uses the live surface aspect (the player tracks its
`LayoutBuilder` size), so it stays correct in fullscreen, split view and
window resize. Fit/zoom sheets apply live through callbacks — the user
sees the result while the sheet is open.

## 5. Touch gestures

`lib/player/gestures.dart` defines the zones and math; the screen wires
them to `GestureDetector` callbacks (touch form factors only — desktop
keeps keyboard/mouse, TV keeps D-pad).

```text
┌──────────────────┬──────────────────┐
│                  │                  │
│  brightness ↕    │   volume ↕       │
│                  │                  │
└──────────────────┴──────────────────┘
        ←  horizontal drag: seek  →
```

- Halves are **physical** in both text directions (left = brightness),
  matching mainstream player muscle memory.
- A full-height drag sweeps the whole range (brightness via the
  `screen_brightness` plugin's *application* brightness, restored on
  exit; volume via the player).
- Horizontal scrub maps full width → 180 s and **mirrors in RTL** so
  dragging toward the reading start seeks backward.
- Feedback is M3-styled: vertical value capsules on the gesture side,
  a seek chip with `±Ns` and the target timestamp, and a `۲×` chip while
  the press-and-hold speed boost is active.
- Brightness unavailability (unsupported display driver) degrades
  gracefully: the gesture disables itself after one notice.

Every gesture is individually switchable, and the double-tap jump is
selectable (5/10/15/30 s), in **Settings → Player → Player gestures**.

## 6. Persistence (settings store)

`PlayerSettingsController` persists through the Rust core's settings
map (`StoreSource.setSetting/getSetting`), under `player.*`:

| Namespace | Keys |
|---|---|
| `player.subs.` | `font`, `size`, `color`, `outline_size`, `outline_color`, `background`, `bold`, `italic`, `position`, `override` |
| `player.hwdec` | `1`/`0` |
| `player.gestures.` | `volume_swipe`, `brightness_swipe`, `seek_swipe`, `double_tap_seek`, `double_tap_seek_seconds`, `long_press_speed_boost` |

Colors persist in mpv's `#AARRGGBB` form; numeric fields round-trip with
clamping; corrupt values fall back field-by-field (tested).

## 7. Keyboard & remote (unchanged from v0.2)

Space/K play · J/L ±10 s · ←/→ ±5 s · ↑/↓ volume · M mute · F fullscreen ·
Esc exit; hardware media keys everywhere; TV keeps arrows free for D-pad
traversal.

## 8. Failure & lifecycle states

- Playback errors (mpv error stream) → themed error pane over the video
  with **retry** (re-opens the media); cleared automatically once
  playback resumes.
- Buffering → M3 progress indicator; resume notice after auto-resume.
- Progress persists every 5 s, on pause/complete and on exit (unchanged);
  the media is opened only after cosmetic properties are applied, so the
  first frame already honors subtitle style and hwdec.

## 9. Where the code lives

| File | Role |
|---|---|
| `lib/player/player_screen.dart` | the screen: M3 chrome, gestures, sheets, sleep timer |
| `lib/player/player_menus.dart` | M3 bottom sheets: speed, tracks, fit/zoom, delays, sleep, external subs |
| `lib/player/subtitle_style.dart` | pure subtitle style model → `sub-*` properties |
| `lib/player/playback_options.dart` | pure fit/zoom/delay/speed models → mpv values |
| `lib/player/gestures.dart` | pure gesture zones + drag math + per-gesture config |
| `lib/player/mpv_bridge.dart` | fault-tolerant `NativePlayer.setProperty/command` glue |
| `lib/data/player_settings.dart` | persisted `PlayerSettingsController` |
| `lib/features/settings/subtitle_appearance_screen.dart` | the style editor with live preview |
| `lib/features/settings/gesture_settings_screen.dart` | per-gesture switches |
| `lib/widgets/color_picker.dart` | M3 HSV color picker dialog |
| `test/player_test.dart` | 31 tests: mappings, math, persistence, screens |
