#!/usr/bin/env python3
"""Generate Aftab Media launcher icons and the Android TV banner.

The motif is a rising sun (آفتاب): a warm amber disc with rays over a deep
navy sky — language-neutral, legible at 48px, and honest at 320x180.

Outputs (into the app/ tree):
  - mipmap-*/ic_launcher.png  (48, 72, 96, 144, 192)
  - mipmap-xxxhdpi/banner.png (320x180, TV leanback banner)
  - assets/icons/icon-512.png (source of truth)
"""

from PIL import Image, ImageDraw
import math
import os

ROOT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "app")

NAVY = (14, 19, 32, 255)
AMBER = (245, 166, 35, 255)
AMBER_LIGHT = (255, 200, 87, 255)
DEEP_AMBER = (179, 111, 0, 255)


def rounded_mask(size: int, radius: int) -> Image.Image:
    mask = Image.new("L", (size, size), 0)
    d = ImageDraw.Draw(mask)
    d.rounded_rectangle([0, 0, size - 1, size - 1], radius=radius, fill=255)
    return mask


def draw_sun(img: Image.Image, scale: float) -> None:
    """Draw the sun motif scaled relative to the icon size."""
    d = ImageDraw.Draw(img)
    w, h = img.size
    cx, cy = w / 2, h * 0.62

    # horizon line glow
    horizon_y = h * 0.72
    d.rectangle([0, horizon_y, w, h], fill=NAVY)

    # rays — eight, rotating around the disc
    ray_len = 0.30 * w * scale
    inner = 0.20 * w * scale
    for k in range(8):
        ang = math.radians(k * 45)
        x1 = cx + math.cos(ang) * inner
        y1 = cy + math.sin(ang) * inner
        x2 = cx + math.cos(ang) * (inner + ray_len)
        y2 = cy + math.sin(ang) * (inner + ray_len)
        d.line([x1, y1, x2, y2], fill=AMBER_LIGHT, width=max(2, int(3 * scale)))

    # disc with a subtle two-tone: upper-left light, lower-right deep
    r = 0.17 * w * scale
    d.ellipse([cx - r, cy - r, cx + r, cy + r], fill=AMBER)
    r2 = r * 0.55
    d.ellipse(
        [cx - r2, cy - r2 - r * 0.18, cx + r2, cy + r2 - r * 0.18],
        fill=AMBER_LIGHT,
    )

    # clip anything below the horizon: redraw the ground on top
    ground = Image.new("RGBA", img.size, (0, 0, 0, 0))
    dg = ImageDraw.Draw(ground)
    dg.rectangle([0, horizon_y, w, h], fill=NAVY)
    img.alpha_composite(ground)

    # thin amber horizon line
    d = ImageDraw.Draw(img)
    d.rectangle(
        [0, horizon_y, w, horizon_y + max(2, int(3 * scale))],
        fill=DEEP_AMBER,
    )


def make_icon(size: int, radius_ratio: float = 0.22) -> Image.Image:
    img = Image.new("RGBA", (size, size), NAVY)
    draw_sun(img, scale=size / 192.0)
    out = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    out.paste(img, (0, 0), rounded_mask(size, int(size * radius_ratio)))
    return out


def make_banner() -> Image.Image:
    w, h = 320, 180
    img = Image.new("RGBA", (w, h), NAVY)
    d = ImageDraw.Draw(img)

    # a wide sun rising from the right third
    cx, cy = w * 0.72, h * 0.98
    r = h * 0.52
    d.ellipse([cx - r, cy - r, cx + r, cy + r], fill=AMBER)
    r2 = r * 0.55
    d.ellipse([cx - r2, cy - r2 - r * 0.16, cx + r2, cy + r2 - r * 0.16], fill=AMBER_LIGHT)

    for k in range(-2, 3):
        ang = math.radians(-90 + k * 18)
        x1 = cx + math.cos(ang) * (r + 6)
        y1 = cy + math.sin(ang) * (r + 6)
        x2 = cx + math.cos(ang) * (r + 26)
        y2 = cy + math.sin(ang) * (r + 26)
        d.line([x1, y1, x2, y2], fill=AMBER_LIGHT, width=4)

    # ground
    d.rectangle([0, int(h * 0.86), w, h], fill=NAVY)
    d.rectangle([0, int(h * 0.86), w, int(h * 0.86) + 3], fill=DEEP_AMBER)
    return img


def main() -> None:
    mipmaps = {
        "mdpi": 48,
        "hdpi": 72,
        "xhdpi": 96,
        "xxhdpi": 144,
        "xxxhdpi": 192,
    }
    for density, size in mipmaps.items():
        path = os.path.join(
            ROOT, "android", "app", "src", "main", "res",
            f"mipmap-{density}", "ic_launcher.png",
        )
        os.makedirs(os.path.dirname(path), exist_ok=True)
        make_icon(size).save(path)
        print(f"wrote {path} ({size}x{size})")

    banner = os.path.join(
        ROOT, "android", "app", "src", "main", "res", "mipmap-xxxhdpi", "banner.png",
    )
    make_banner().save(banner)
    print(f"wrote {banner} (320x180)")

    icon512 = os.path.join(ROOT, "assets", "icons", "icon-512.png")
    os.makedirs(os.path.dirname(icon512), exist_ok=True)
    make_icon(512, radius_ratio=0.24).save(icon512)
    print(f"wrote {icon512} (512x512)")


if __name__ == "__main__":
    main()
