"""Regenerates the app icon set and the in-app logo from the source artwork.

Usage: python3 tool/make_brand_assets.py   (from the repo root)

Cuts the neon mark out of the source artwork and rebuilds the icon from it.

The mark is keyed on *chroma* — how much redder a pixel is than its other two
channels. The artwork's tile, its border stroke and the canvas behind it are all
neutral or slightly blue (the border samples at 80,79,85), so they key to zero
exactly, while every part of the neon and its bloom keys positive. A luminance
key cannot do this: the border is brighter than the outer half of the glow, so
it survives and draws a square behind the mark.
"""
from PIL import Image, ImageDraw
import numpy as np

SRC = 'tool/brand/app_icon_source.jpg'   # the original artwork, wordmark and all
GLYPH_BOX = (303, 237, 721, 679)   # pink pixels, measured
# How far past the glyph to take the bloom. Bounded by the artwork's tile: the
# source's glow is *clipped* at the tile edge, a real step in the pixels that no
# colour key can undo, so anything that includes that edge shows a rounded
# square behind the mark. Staying inside it and feathering the frame is the only
# way to get a mark with no box around it.
BLOOM = 31


def cutout(size):
    src = Image.open(SRC).convert('RGB')
    x0, y0, x1, y1 = GLYPH_BOX
    cx, cy = (x0 + x1) / 2, (y0 + y1) / 2
    half = max(x1 - x0, y1 - y0) / 2 + BLOOM
    img = src.crop((int(cx - half), int(cy - half), int(cx + half), int(cy + half)))
    img = img.resize((size, size), Image.LANCZOS)

    a = np.asarray(img).astype(np.float32)
    r, g, b = a[..., 0], a[..., 1], a[..., 2]
    chroma = r - np.maximum(g, b)                 # neutral greys -> 0
    alpha = np.clip(chroma / 110.0, 0, 1) ** 0.85
    # The white-hot core of the strokes is nearly neutral, so chroma alone
    # would punch holes in it; brightness rescues exactly that — but only
    # where there is still some pink, or the white wordmark under the tile
    # would be rescued too.
    core = np.clip((a.max(axis=2) - 205) / 40.0, 0, 1) * (chroma > 20)
    alpha = np.maximum(alpha, core)
    # Feather the last few per cent of the frame. The bloom is wider than any
    # crop that stays clear of the wordmark, and a bloom cut off mid-falloff
    # leaves a faint square outline — exactly the artefact this is avoiding.
    n = a.shape[0]
    yy, xx = np.mgrid[0:n, 0:n]
    edge = np.maximum(np.abs(xx - n / 2), np.abs(yy - n / 2)) / (n / 2)
    alpha *= np.clip((0.99 - edge) / 0.18, 0, 1)
    rgb = np.clip(a / np.maximum(alpha[..., None], 0.25), 0, 255)
    return Image.fromarray(
        np.dstack([rgb, alpha * 255]).astype(np.uint8), 'RGBA')


def icon(size):
    """Icon = dark plate + the mark, with the bloom fading into the plate.

    Rebuilt rather than cropped: any crop of the source that keeps the glow
    outside the tile also keeps the tile's edge, which is what made the icon
    read as a square inside a square.
    """
    s = max(size, 512)
    yy, xx = np.mgrid[0:s, 0:s]
    d = np.sqrt((xx - s / 2) ** 2 + (yy - s / 2) ** 2) / (s / 2)
    lift = np.clip(1.0 - d * 0.85, 0, 1)          # gentle centre lift
    plate = np.dstack([10 + 12 * lift, 10 + 11 * lift, 13 + 13 * lift])
    base = Image.fromarray(plate.astype(np.uint8), 'RGB').convert('RGBA')

    mark = cutout(int(s * 0.90))
    off = (s - mark.width) // 2
    base.alpha_composite(mark, (off, off))
    return base.convert('RGB').resize((size, size), Image.LANCZOS)


def main():
    """Regenerates every brand asset from the one source artwork."""
    import glob

    cutout(512).save('assets/logo.png')          # in-app header mark
    print('assets/logo.png')

    def write(path, mode):
        size = Image.open(path).size[0]
        im = icon(size)
        # iOS rejects alpha in app icons and renders it black on device.
        im.convert(mode).save(path)

    targets = [(p, 'RGB') for p in glob.glob(
                   'ios/Runner/Assets.xcassets/AppIcon.appiconset/*.png')]
    targets += [(p, 'RGBA') for p in glob.glob(
                   'macos/Runner/Assets.xcassets/AppIcon.appiconset/*.png')]
    targets += [(p, 'RGBA') for p in glob.glob(
                   'android/app/src/main/res/mipmap-*/ic_launcher.png')]
    targets += [('web/icons/Icon-192.png', 'RGB'),
                ('web/icons/Icon-512.png', 'RGB'),
                ('web/icons/Icon-maskable-192.png', 'RGBA'),
                ('web/icons/Icon-maskable-512.png', 'RGBA'),
                ('web/favicon.png', 'RGBA')]
    for path, mode in targets:
        write(path, mode)

    # Android's round variant is masked to a circle by us, not by the launcher.
    for path in glob.glob('android/app/src/main/res/mipmap-*/ic_launcher_round.png'):
        size = Image.open(path).size[0]
        im = icon(size).convert('RGBA')
        mask = Image.new('L', (size * 4, size * 4), 0)
        ImageDraw.Draw(mask).ellipse([0, 0, size * 4 - 1, size * 4 - 1], fill=255)
        out = Image.new('RGBA', (size, size), (0, 0, 0, 0))
        out.paste(im, (0, 0), mask.resize((size, size), Image.LANCZOS))
        out.save(path)

    print('regenerated', len(targets) + 5, 'icons')


if __name__ == '__main__':
    main()
