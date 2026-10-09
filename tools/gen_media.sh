#!/usr/bin/env bash
# Generate the tiny MP4 fixture clips used by the core's download/media
# integrity tests. Synthesized with FFmpeg (CC0, no external sources).
#
# Usage: tools/gen_media.sh   (run from the repository root)

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
OUT="$ROOT/core/tests/fixtures/media"
mkdir -p "$OUT"

# 1) A 2-second test pattern clip — the "video" fixture (video-only, tiny).
ffmpeg -y -loglevel error \
    -f lavfi -i "testsrc2=size=256x144:rate=12:duration=2" \
    -c:v libx264 -preset ultrafast -crf 32 -pix_fmt yuv420p \
    "$OUT/testsrc.mp4"

# 2) SMPTE bars, 1 second, video-only — poster/quality-switch fixture.
ffmpeg -y -loglevel error \
    -f lavfi -i "smptehdbars=size=320x180:rate=15:duration=1" \
    -c:v libx264 -preset ultrafast -pix_fmt yuv420p \
    "$OUT/bars.mp4"

# 3) A 1-second black clip with a single keyframe — minimal seek fixture.
ffmpeg -y -loglevel error \
    -f lavfi -i "color=c=black:size=320x180:rate=15:duration=1" \
    -c:v libx264 -preset ultrafast -pix_fmt yuv420p \
    "$OUT/black.mp4"

ls -la "$OUT"
echo "media fixtures regenerated"
