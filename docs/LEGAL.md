# Legal & license compatibility

<div dir="rtl">

## چرا GPL-3.0؟

انتخاب پروانهٔ GPL-3.0 برای آفتاب مدیا اجباری است، نه سلیقه‌ای: پخش
ویدیو با **libmpv** انجام می‌شود و libmpv تحت پروانهٔ GPL-2.0-or-later
توزیع می‌شود. برنامه‌ای که به آن **پیوند** می‌شود، اثر مشتق محسوب می‌شود
و باید پروانه‌ای سازگار با GPL انتخاب کند. GPL-2.0-or-later با GPL-3.0
سازگار است (سازگاری یک‌طرفه)، بنابراین GPL-3.0 انتخاب شد.

</div>

## The chain of obligations

### 1. libmpv (GPL-2.0-or-later)

- Aftab Media **links** libmpv dynamically (bundled by the `media_kit`
  plugin packages for Android and Windows).
- Linking creates a derived work of libmpv in the combined binary.
- GPL-2.0-or-later is upward-compatible with GPL-3.0: distributing the
  combined work under GPL-3.0 satisfies every GPL-2.0 obligation that
  applies here (attribution, source availability of our side, and the
  right to relink).
- Therefore: **the repository is GPL-3.0** (`LICENSE`), and the app's
  About screen + NOTICE name mpv and its license.
- We do not modify libmpv; we consume upstream builds. No additional
  obligation (such as providing libmpv's own sources) is triggered beyond
  pointing at upstream, which the NOTICE does.

### 2. CCloud (MIT)

- Aftab Media is a re-engineering of the CCloud Android app
  (`https://github.com/code3-dev/CCloud`, © 2025 Hossein Pira, MIT).
- What was reused: the **provider API contract** (endpoint layout, JSON
  shapes, failover semantics) and the product concept. No CCloud source
  code is included verbatim — the Android app was re-implemented in
  Flutter, and the data layer in Rust.
- MIT obligations: retain the copyright notice and permission notice.
  `NOTICE.md` carries them verbatim. MIT is one-way compatible with
  GPL-3.0, so incorporating MIT-derived design/code into this GPL-3.0
  project is permitted with the notice preserved — which it is.
- Compatibility note (LGPL §4 / GPL compatibility of MIT): MIT places no
  copyleft requirements, so relicensing the *derivative* under GPL-3.0 is
  allowed; the MIT notice remains as an attribution obligation, not a
  license conflict.

### 3. media_kit and its plugin packages (MIT)

Bundled via pub; notices in `NOTICE.md`. MIT→GPL-3.0 compatibility as
above.

### 4. FFmpeg (LGPL-2.1+ / GPL-2+ depending on build)

FFmpeg is embedded inside the libmpv builds we consume; no FFmpeg source
ships in this repository. The test fixtures under
`core/tests/fixtures/media/` were generated locally from synthesized
sources (`testsrc2`, `smptehdbars`, `color`) and are dedicated to the
public domain (CC0) — they contain no third-party content.

### 5. This repository's own code

- `core/` (Rust) — GPL-3.0-or-later (declared in `Cargo.toml`).
- `app/` (Dart/Flutter) — GPL-3.0-or-later (header in pubspec
  description; the LICENSE at the root covers the whole work).
- `docs/`, `tools/` — GPL-3.0-or-later as part of the combined work.

## The API key question

The catalog API key embedded in URLs (`4F5A…`) is a **wire constant of
the public service** inherited from the upstream open-source client — it
is not a user credential, not a secret owned by this project, and not
authentication material of any individual. It is committed openly exactly
as upstream commits it. No user tokens, PATs, or personal identifiers
exist anywhere in this repository, and the project's own secrets policy
(`.gitignore`) blocks accidental token files.

## Practical consequences for distributors

- If you distribute binaries (APKs, Windows builds), GPL-3.0 requires
  offering the **corresponding source** — pointing at this repository at
  the exact commit satisfies that, provided you have not made private
  modifications.
- If you make private modifications and distribute the result, you must
  offer *your* sources too.
- Nothing here restricts **running** the app or **internal use**.
- The `media_kit`-bundled binaries keep their own notices; see
  `NOTICE.md` for the full attribution list.
