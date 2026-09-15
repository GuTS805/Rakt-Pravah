"""Derives every app icon from the single source logo in assets/logo.png.

The source is a full lockup (drop + wordmark + tagline) on a white background,
which cannot be used as-is:

  * The hands inside the drop are white negative space, and that white is
    connected to the background through a notch at the top right — so it
    cannot be separated from it automatically. Keying out the background
    therefore punches holes through the hands, and the drop falls apart on a
    dark background. White is a real colour in this mark, so the artwork keeps
    its white and is presented on a white chip instead. Background removal is
    still used, but only to locate the artwork.
  * The wordmark is illegible at the 26-34px the in-app mark renders at, and
    the word "BloodLink" already appears as live text beside it. So the drop is
    split off from the lockup and used on its own.
  * Android tints notification icons to a flat silhouette, so a coloured logo
    becomes a white blob. A dedicated white-on-transparent silhouette is
    generated for that.

Run:  python tool/build_logo_assets.py
"""

from __future__ import annotations

import os
from collections import deque

import numpy as np
from PIL import Image, ImageDraw

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SRC = os.path.join(ROOT, "assets", "logo.png")

# A pixel counts as background if every channel is at least this bright.
WHITE_CUTOFF = 232


def load_rgba() -> Image.Image:
    return Image.open(SRC).convert("RGBA")


def strip_background(img: Image.Image) -> Image.Image:
    """Flood-fills transparency from the border, preserving interior white."""
    arr = np.array(img)
    h, w = arr.shape[:2]
    near_white = (arr[:, :, :3] >= WHITE_CUTOFF).all(axis=2)

    outside = np.zeros((h, w), dtype=bool)
    queue: deque[tuple[int, int]] = deque()

    for x in range(w):
        for y in (0, h - 1):
            if near_white[y, x] and not outside[y, x]:
                outside[y, x] = True
                queue.append((y, x))
    for y in range(h):
        for x in (0, w - 1):
            if near_white[y, x] and not outside[y, x]:
                outside[y, x] = True
                queue.append((y, x))

    while queue:
        y, x = queue.popleft()
        for dy, dx in ((1, 0), (-1, 0), (0, 1), (0, -1)):
            ny, nx = y + dy, x + dx
            if 0 <= ny < h and 0 <= nx < w and near_white[ny, nx] and not outside[ny, nx]:
                outside[ny, nx] = True
                queue.append((ny, nx))

    arr[:, :, 3] = np.where(outside, 0, 255)
    return Image.fromarray(arr)


def split_mark(img: Image.Image) -> Image.Image:
    """Returns the drop alone, by cutting at the first blank band below it.

    The lockup stacks drop / wordmark / tagline, so there are two interior
    gaps. The first one is the drop's baseline — taking the widest instead
    keeps the wordmark attached, since the gap above the tagline is the
    larger of the two.
    """
    alpha = np.array(img)[:, :, 3]
    filled = alpha.any(axis=1)
    rows = np.where(filled)[0]
    top, bottom = rows[0], rows[-1]

    y = top
    while y <= bottom:
        if not filled[y]:
            return img.crop((0, 0, img.width, y))
        y += 1
    return img.crop((0, 0, img.width, bottom))


def trim(img: Image.Image) -> Image.Image:
    box = img.getbbox()
    return img.crop(box) if box else img


def squared_on_white(img: Image.Image, pad_ratio: float = 0.08) -> Image.Image:
    """Centres the artwork on an opaque white square.

    White rather than transparent because the hands are white and open to the
    background — see the module docstring. Anything consuming this is expected
    to clip it to a chip shape.
    """
    side = int(max(img.size) * (1 + pad_ratio * 2))
    canvas = Image.new("RGBA", (side, side), (255, 255, 255, 255))
    canvas.paste(img, ((side - img.width) // 2, (side - img.height) // 2), img)
    return canvas


def on_white_tile(mark: Image.Image, size: int) -> Image.Image:
    """Launcher icon: the mark on a white rounded tile, matching how the brand
    is presented, and giving the icon a consistent shape next to other apps."""
    tile = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    draw = ImageDraw.Draw(tile)
    draw.rounded_rectangle(
        [(0, 0), (size - 1, size - 1)],
        radius=int(size * 0.22),
        fill=(255, 255, 255, 255),
    )
    inner = int(size * 0.72)
    art = mark.copy()
    art.thumbnail((inner, inner), Image.LANCZOS)
    tile.paste(art, ((size - art.width) // 2, (size - art.height) // 2), art)
    return tile


def silhouette(mark: Image.Image, size: int) -> Image.Image:
    """White-on-transparent, for Android's notification tinting.

    Android flattens a notification icon to its alpha and tints it, so a
    colour logo arrives as a solid blob. The shape is taken from the coloured
    pixels, which keeps the hands legible as cut-outs.
    """
    art = mark.copy()
    art.thumbnail((size, size), Image.LANCZOS)
    arr = np.array(art.convert("RGBA"))
    coloured = ~(arr[:, :, :3] >= WHITE_CUTOFF).all(axis=2)
    out = np.zeros_like(arr)
    out[:, :, 0:3] = 255
    out[:, :, 3] = coloured * 255
    shape = Image.fromarray(out)
    canvas = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    canvas.paste(shape, ((size - shape.width) // 2, (size - shape.height) // 2),
                 shape)
    return canvas


def save(img: Image.Image, *parts: str) -> None:
    path = os.path.join(ROOT, *parts)
    os.makedirs(os.path.dirname(path), exist_ok=True)
    img.save(path)
    print(f"  {os.path.relpath(path, ROOT)}  {img.size[0]}x{img.size[1]}")


def main() -> None:
    print("Reading", os.path.relpath(SRC, ROOT))
    source = load_rgba()
    cut_out = strip_background(source)

    # The stripped copy is only a measuring tool: it says where the artwork
    # sits and where the drop ends. The saved assets are cropped from the
    # original so the hands keep their white.
    full = source.crop(cut_out.getbbox())
    mark = squared_on_white(source.crop(split_mark(cut_out).getbbox()))

    print("Brand assets:")
    save(full, "assets", "logo_full.png")
    save(mark, "assets", "logo_mark.png")

    print("Android launcher:")
    for folder, px in (
        ("mipmap-mdpi", 48),
        ("mipmap-hdpi", 72),
        ("mipmap-xhdpi", 96),
        ("mipmap-xxhdpi", 144),
        ("mipmap-xxxhdpi", 192),
    ):
        save(on_white_tile(mark, px),
             "android", "app", "src", "main", "res", folder, "ic_launcher.png")

    print("Android notification (tinted silhouette):")
    for folder, px in (
        ("drawable-mdpi", 24),
        ("drawable-hdpi", 36),
        ("drawable-xhdpi", 48),
        ("drawable-xxhdpi", 72),
        ("drawable-xxxhdpi", 96),
    ):
        save(silhouette(mark, px),
             "android", "app", "src", "main", "res", folder, "ic_notification.png")

    # Web icons use the same white chip: a browser tab or PWA shelf is rarely
    # white, and the bare artwork would lose its hands there too.
    print("Web:")
    save(on_white_tile(mark, 32), "web", "favicon.png")
    for px in (192, 512):
        save(on_white_tile(mark, px), "web", "icons", f"Icon-{px}.png")
        save(on_white_tile(mark, px), "web", "icons", f"Icon-maskable-{px}.png")


if __name__ == "__main__":
    main()
