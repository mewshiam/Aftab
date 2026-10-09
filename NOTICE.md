# NOTICE

This file documents third-party works incorporated into or used by Aftab Media
(آفتاب مدیا), as required by their respective licenses.

## CCloud

Aftab Media is a re-engineering of **CCloud**, an Android movie & TV series
streaming application.

- Upstream project: https://github.com/code3-dev/CCloud
- Upstream author: Hossein Pira
- Upstream license: MIT

```
MIT License

Copyright (c) 2025 Hossein Pira

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.
```

Aftab Media reuses from CCloud: the provider API contract (endpoint layout,
JSON response shapes, and helper-server failover semantics) and the product
concept. No CCloud source code is included verbatim in this repository; the
Android application was re-implemented in Flutter and the data layer was
re-implemented in Rust. The MIT notice above is retained out of respect for
the upstream project and its author.

## libmpv / mpv

Playback is powered by **libmpv**, embedded via the `media_kit` Flutter
plugins.

- Project: https://github.com/mpv-player/mpv
- License: GPL-2.0-or-later (libmpv is built by upstream with
  `--enable-lgpl` off, i.e. the full GPL applies to the binary we consume)

Because Aftab Media links libmpv dynamically, the combined work is a
derivative of a GPL-2.0-or-later work and is therefore distributed under
GPL-3.0 (GPL-2.0-or-later is one-way compatible with GPL-3.0). See
docs/LEGAL.md for the full analysis.

## media_kit

- Project: https://github.com/media-kit/media-kit
- License: MIT

## FFmpeg

libmpv embeds FFmpeg. The FFmpeg project is distributed under LGPL-2.1-or-
later / GPL-2.0-or-later depending on build configuration. No FFmpeg source
is included in this repository.

## Test media

The tiny fixture clips under `core/tests/fixtures/media/` were generated with
FFmpeg from synthesized sources (`testsrc`, `smptehdbars`, `color`) and are
dedicated to the public domain (CC0).
