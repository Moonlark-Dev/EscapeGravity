#!/usr/bin/env python3
"""Escape Gravity - UI layer asset generator.

Generates every file listed in docs/ASSET_MANIFEST.md section "B. UI 层"
into assets/ui/ and the contact sheet docs/preview_ui.png.

All artwork is drawn at 4x supersampling with PIL + numpy, then resized with
LANCZOS (premultiplied alpha) and glow layers are composited from gaussian
blurred masks.  Re-running overwrites every product deterministically.

    python3 tools/gen_assets_ui.py
"""

import math
import os
import sys

import numpy as np
from PIL import Image, ImageChops, ImageDraw, ImageFilter, ImageFont

# --------------------------------------------------------------------------
# constants
# --------------------------------------------------------------------------
S = 4  # supersampling factor
ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
UI_DIR = os.path.join(ROOT, "assets", "ui")
DOCS_DIR = os.path.join(ROOT, "docs")
PREVIEW = os.path.join(DOCS_DIR, "preview_ui.png")

FONT_BOLD = "/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf"
FONT_REG = "/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf"

DEEP = (5, 7, 15)
CYAN = (57, 230, 255)
PURPLE = (139, 92, 246)
MAGENTA = (255, 61, 129)
AMBER = (255, 179, 71)
MINT = (92, 242, 168)
WHITE = (255, 255, 255)
ICE = (205, 248, 255)
GLASS = (10, 17, 31)


def C(col, a=255):
    return (int(col[0]), int(col[1]), int(col[2]), int(round(a)))


def lerp(c1, c2, t):
    return tuple(int(round(c1[i] + (c2[i] - c1[i]) * t)) for i in range(3))


# --------------------------------------------------------------------------
# low level helpers
# --------------------------------------------------------------------------
def new_rgba(size, scale=S):
    return Image.new("RGBA", (int(round(size[0] * scale)), int(round(size[1] * scale))), (0, 0, 0, 0))


def resize_rgba(img, size):
    """LANCZOS downscale in premultiplied space (no dark fringes)."""
    arr = np.asarray(img, dtype=np.float32) / 255.0
    a = arr[..., 3:4]
    prem = np.concatenate([arr[..., :3] * a, a], axis=-1)
    pim = Image.fromarray(np.clip(prem * 255.0 + 0.5, 0, 255).astype(np.uint8), "RGBA")
    pim = pim.resize((int(size[0]), int(size[1])), Image.LANCZOS)
    b = np.asarray(pim, dtype=np.float32) / 255.0
    aa = b[..., 3:4]
    rgb = np.where(aa > 1e-6, b[..., :3] / np.maximum(aa, 1e-6), 0.0)
    out = np.concatenate([np.clip(rgb, 0.0, 1.0), aa], axis=-1)
    return Image.fromarray(np.clip(out * 255.0 + 0.5, 0, 255).astype(np.uint8), "RGBA")


def soft_mask(layer, radius_px, gain=1.0):
    """Blur only the alpha channel, preserving colour -> soft glow silhouette."""
    a = (layer if layer.mode == "L" else layer.getchannel("A"))
    a = a.filter(ImageFilter.GaussianBlur(radius_px * S))
    if gain != 1.0:
        a = a.point(lambda v: min(255, int(round(v * gain))))
    return a


def glow_layer(layer, radius_px, color=None, gain=1.0):
    a = soft_mask(layer, radius_px, gain)
    if color is None:
        if layer.mode != "RGBA":
            color = (255, 255, 255)
        else:
            out = layer.copy()
            out.putalpha(a)
            return out
    out = Image.new("RGBA", layer.size, C(color, 0))
    out.putalpha(a)
    return out


def over(base, top):
    return Image.alpha_composite(base, top)


def add_glow(base, glow):
    """Additive (screen-like) glow compositing in premultiplied space."""
    b = np.asarray(base, dtype=np.float32) / 255.0
    g = np.asarray(glow, dtype=np.float32) / 255.0
    ba, ga = b[..., 3:4], g[..., 3:4]
    p = np.clip(b[..., :3] * ba + g[..., :3] * ga, 0.0, 1.0)
    a = np.clip(ba + ga, 0.0, 1.0)
    p = np.minimum(p, a)
    rgb = np.where(a > 1e-6, p / np.maximum(a, 1e-6), 0.0)
    out = np.concatenate([np.clip(rgb, 0.0, 1.0), a], axis=-1)
    return Image.fromarray(np.clip(out * 255.0 + 0.5, 0, 255).astype(np.uint8), "RGBA")


def clip_alpha(img, mask):
    img.putalpha(ImageChops.multiply(img.getchannel("A"), mask))
    return img


def poly_mask(size, pts, scale=S):
    m = Image.new("L", (int(size[0] * scale), int(size[1] * scale)), 0)
    ImageDraw.Draw(m).polygon([(x * scale, y * scale) for x, y in pts], fill=255)
    return m


def mask_from(size, box, radius=0, scale=S):
    m = Image.new("L", (int(size[0] * scale), int(size[1] * scale)), 0)
    d = ImageDraw.Draw(m)
    b = [box[0] * scale, box[1] * scale, box[2] * scale, box[3] * scale]
    if radius:
        d.rounded_rectangle(b, radius=radius * scale, fill=255)
    else:
        d.rectangle(b, fill=255)
    return m


def vert_band(size, box, color, a0, a1, scale=S):
    """Constant-across-x vertical alpha ramp (9-patch safe)."""
    x0, y0, x1, y1 = [int(round(v * scale)) for v in box]
    h, w = max(1, y1 - y0), max(1, x1 - x0)
    t = np.linspace(0.0, 1.0, h, dtype=np.float32)[:, None]
    alpha = np.broadcast_to(a0 + (a1 - a0) * t, (h, w))
    arr = np.empty((h, w, 4), np.uint8)
    arr[..., 0] = color[0]
    arr[..., 1] = color[1]
    arr[..., 2] = color[2]
    arr[..., 3] = np.clip(alpha, 0, 255).astype(np.uint8)
    out = Image.new("RGBA", (int(size[0] * scale), int(size[1] * scale)), (0, 0, 0, 0))
    out.alpha_composite(Image.fromarray(arr, "RGBA"), (max(0, x0), max(0, y0)))
    return out


def radial_fill(size, cx, cy, r0, r1, c0, a0, c1, a1, scale=S, hard=False):
    """Radial gradient disc (alpha falls to a1 at r1); hard=True cuts a crisp disc."""
    W, H = int(size[0] * scale), int(size[1] * scale)
    yy, xx = np.mgrid[0:H, 0:W].astype(np.float32)
    dist = np.hypot(xx - cx * scale, yy - cy * scale) / scale
    d = dist / r1
    t = np.clip((d - r0 / max(r1, 1e-6)) / max(1e-6, 1.0 - r0 / max(r1, 1e-6)), 0, 1)
    rgb = np.array(c0, np.float32) * (1 - t[..., None]) + np.array(c1, np.float32) * t[..., None]
    alpha = a0 * (1 - t) + a1 * t
    if hard:
        alpha = alpha * np.clip((r1 - dist) / 1.6, 0, 1)
    arr = np.concatenate([rgb, alpha[..., None]], axis=-1)
    return Image.fromarray(np.clip(arr, 0, 255).astype(np.uint8), "RGBA")


def rot_pts(pts, cx, cy, deg):
    r = math.radians(deg)
    co, si = math.cos(r), math.sin(r)
    return [(cx + (x - cx) * co - (y - cy) * si, cy + (x - cx) * si + (y - cy) * co) for x, y in pts]


def star4(A, cx, cy, r, color, waist=0.16):
    """Four point sparkle drawn as a filled star polygon."""
    k = r * waist
    pts = [(cx, cy - r), (cx + k, cy - k), (cx + r, cy), (cx + k, cy + k),
           (cx, cy + r), (cx - k, cy + k), (cx - r, cy), (cx - k, cy - k)]
    A.poly(pts, color, 0, fill=color, close=True)


def droplet(A, cx, cy, r, color, width=0.0, fill=None):
    pts = [(cx, cy - 1.45 * r),
           (cx + 0.62 * r, cy - 0.55 * r),
           (cx + 0.95 * r, cy + 0.25 * r),
           (cx + 0.82 * r, cy + 0.85 * r),
           (cx + 0.35 * r, cy + 1.2 * r),
           (cx - 0.35 * r, cy + 1.2 * r),
           (cx - 0.82 * r, cy + 0.85 * r),
           (cx - 0.95 * r, cy + 0.25 * r),
           (cx - 0.62 * r, cy - 0.55 * r)]
    A.poly(pts, color, width, fill=fill, close=True)


# --------------------------------------------------------------------------
# drawing canvas (coordinates are in final pixels, multiplied by S here)
# --------------------------------------------------------------------------
class Art:
    def __init__(self, size, scale=S):
        self.size = size
        self.scale = scale
        self.img = Image.new("RGBA", (int(size[0] * scale), int(size[1] * scale)), (0, 0, 0, 0))
        self.d = ImageDraw.Draw(self.img, "RGBA")

    # -- primitives ---------------------------------------------------------
    def rect(self, box, radius=0, fill=None, outline=None, width=1.0):
        b = [box[0] * self.scale, box[1] * self.scale, box[2] * self.scale, box[3] * self.scale]
        w = max(1, int(round(width * self.scale)))
        if radius:
            self.d.rounded_rectangle(b, radius=radius * self.scale, fill=fill,
                                     outline=outline, width=w)
        else:
            self.d.rectangle(b, fill=fill, outline=outline, width=w)

    def line(self, pts, color, width=1.0, caps=True):
        w = max(1, int(round(width * self.scale)))
        p = [(x * self.scale, y * self.scale) for x, y in pts]
        if len(p) < 2:
            return
        self.d.line(p, fill=color, width=w, joint="curve")
        if caps:
            r = width * self.scale / 2.0
            for q in (p[0], p[-1]):
                self.d.ellipse([q[0] - r, q[1] - r, q[0] + r, q[1] + r], fill=color)

    def poly(self, pts, color, width=1.0, fill=None, close=True):
        p = [(x * self.scale, y * self.scale) for x, y in pts]
        if fill is not None:
            self.d.polygon(p, fill=fill)
        if width > 0:
            seq = list(p) + ([p[0]] if close else [])
            w = max(1, int(round(width * self.scale)))
            self.d.line(seq, fill=color, width=w, joint="curve")
            r = width * self.scale / 2.0
            for q in (seq[0], seq[-1]):
                self.d.ellipse([q[0] - r, q[1] - r, q[0] + r, q[1] + r], fill=color)

    def circle(self, c, r, color, width=1.0, fill=None):
        box = [(c[0] - r) * self.scale, (c[1] - r) * self.scale,
               (c[0] + r) * self.scale, (c[1] + r) * self.scale]
        if fill is not None:
            self.d.ellipse(box, fill=fill)
        if width > 0:
            self.d.ellipse(box, outline=color, width=max(1, int(round(width * self.scale))))

    def arc(self, c, r, a0, a1, color, width=1.0, caps=True):
        box = [(c[0] - r) * self.scale, (c[1] - r) * self.scale,
               (c[0] + r) * self.scale, (c[1] + r) * self.scale]
        self.d.arc(box, a0, a1, fill=color, width=max(1, int(round(width * self.scale))))
        if caps:
            rw = width * self.scale / 2.0
            for a in (a0, a1):
                x = (c[0] + r * math.cos(math.radians(a))) * self.scale
                y = (c[1] + r * math.sin(math.radians(a))) * self.scale
                self.d.ellipse([x - rw, y - rw, x + rw, y + rw], fill=color)

    def dot(self, c, r, color):
        c = (c[0] * self.scale, c[1] * self.scale)
        r = r * self.scale
        self.d.ellipse([c[0] - r, c[1] - r, c[0] + r, c[1] + r], fill=color)


def finish_icon(A, glows, size):
    """Composite glow stack under the line art, then down-sample."""
    out = Image.new("RGBA", A.img.size, (0, 0, 0, 0))
    for radius, color, gain in glows:
        out = add_glow(out, glow_layer(A.img, radius, color, gain))
    out = over(out, A.img)
    return resize_rgba(out, size)


# ==========================================================================
# 9-slice panels & buttons
# ==========================================================================
def panel_9p(accent=CYAN, bracket=CYAN, alt=False):
    W = H = 96
    A = Art((W, H))
    clip = mask_from((W, H), (0.5, 0.5, W - 0.5, H - 0.5), 8.5)
    base = Image.new("RGBA", A.img.size, C((10, 17, 31), 214))
    base.putalpha(ImageChops.multiply(base.getchannel("A"), mask_from((W, H), (0.6, 0.6, W - 0.6, H - 0.6), 8.5)))

    # inner edge bloom ------------------------------------------------------
    edge = Image.new("RGBA", A.img.size, (0, 0, 0, 0))
    ImageDraw.Draw(edge).rounded_rectangle(
        [3.5 * S, 3.5 * S, (W - 3.5) * S, (H - 3.5) * S],
        radius=7 * S, outline=C(accent, 96), width=int(7 * S))
    eg = glow_layer(edge, 6.0, accent, 0.95)
    eg.putalpha(ImageChops.multiply(eg.getchannel("A"), clip))
    base = over(base, eg)

    # glass shading: top sheen / bottom shade (constant along x) ------------
    base = over(base, vert_band((W, H), (0, 0.6, W, 13), (130, 205, 240), 30, 0))
    base = over(base, vert_band((W, H), (0, H - 12, W, H - 0.6), (0, 0, 0), 0, 38))

    # rim stroke ------------------------------------------------------------
    stroke = Image.new("RGBA", A.img.size, (0, 0, 0, 0))
    ImageDraw.Draw(stroke).rounded_rectangle(
        [1.4 * S, 1.4 * S, (W - 1.4) * S, (H - 1.4) * S],
        radius=7.6 * S, outline=C(accent, 232), width=int(1.15 * S))
    base = over(base, stroke)
    # faint inner hairline for the "glass thickness"
    hair = Image.new("RGBA", A.img.size, (0, 0, 0, 0))
    ImageDraw.Draw(hair).rounded_rectangle(
        [3.2 * S, 3.2 * S, (W - 3.2) * S, (H - 3.2) * S],
        radius=6.4 * S, outline=C(accent, 54), width=int(0.9 * S))
    base = over(base, hair)

    # corner brackets -------------------------------------------------------
    B = Art((W, H))
    for sx in (0, 1):
        for sy in (0, 1):
            x0, y0 = (6.0 if sx == 0 else W - 6.0), (6.0 if sy == 0 else H - 6.0)
            dx, dy = (1 if sx == 0 else -1), (1 if sy == 0 else -1)
            B.line([(x0, y0 + 13 * dy), (x0, y0), (x0 + 13 * dx, y0)], C(bracket, 240), 1.9)
    base = over(base, glow_layer(B.img, 3.2, bracket, 1.1))
    base = over(base, B.img)

    out = Image.new("RGBA", A.img.size, (0, 0, 0, 0))
    out = over(out, base)
    clip_alpha(out, mask_from((W, H), (0.4, 0.4, W - 0.4, H - 0.4), 8.4))
    return resize_rgba(out, (W, H))


def card_9p():
    W = H = 96
    A = Art((W, H))
    clip = mask_from((W, H), (0.5, 0.5, W - 0.5, H - 0.5), 9)
    base = Image.new("RGBA", A.img.size, C((12, 15, 30), 218))
    base.putalpha(ImageChops.multiply(base.getchannel("A"), clip))

    edge = Image.new("RGBA", A.img.size, (0, 0, 0, 0))
    ImageDraw.Draw(edge).rounded_rectangle(
        [3.5 * S, 3.5 * S, (W - 3.5) * S, (H - 3.5) * S],
        radius=7 * S, outline=C(PURPLE, 80), width=int(6 * S))
    eg = glow_layer(edge, 6.0, PURPLE, 0.9)
    eg.putalpha(ImageChops.multiply(eg.getchannel("A"), clip))
    base = over(base, eg)
    base = over(base, vert_band((W, H), (0, 0.6, W, 12), (160, 150, 255), 26, 0))

    stroke = Image.new("RGBA", A.img.size, (0, 0, 0, 0))
    ImageDraw.Draw(stroke).rounded_rectangle(
        [1.4 * S, 1.4 * S, (W - 1.4) * S, (H - 1.4) * S],
        radius=8 * S, outline=C((120, 110, 210), 190), width=int(1.1 * S))
    base = over(base, stroke)

    # glowing top bar (uniform through the stretchable middle) -------------
    bar = Art((W, H))
    bar.rect((9, 3.4, W - 9, 6.6), radius=1.6, fill=C(CYAN, 238))
    bar.rect((22, 3.0, W - 22, 7.0), radius=2.0, fill=C(PURPLE, 60))
    bar.line([(12, 5.0), (W - 12, 5.0)], C(ICE, 255), 1.1)
    base = over(base, add_glow(base, glow_layer(bar.img, 4.5, CYAN, 1.0)))
    base = over(base, bar.img)

    # corner brackets + top corner dots
    B = Art((W, H))
    for sx in (0, 1):
        for sy in (0, 1):
            x0, y0 = (6.5 if sx == 0 else W - 6.5), (6.5 if sy == 0 else H - 6.5)
            dx, dy = (1 if sx == 0 else -1), (1 if sy == 0 else -1)
            B.line([(x0, y0 + 11 * dy), (x0, y0), (x0 + 11 * dx, y0)], C(CYAN, 225), 1.7)
    base = over(base, glow_layer(B.img, 3.0, CYAN, 1.0))
    base = over(base, B.img)
    clip_alpha(base, mask_from((W, H), (0.4, 0.4, W - 0.4, H - 0.4), 8.9))
    return resize_rgba(base, (W, H))


def button_9p(state="normal"):
    W = H = 96
    A = Art((W, H))
    chamfer = 7.0
    poly = [(chamfer, 0.8), (W - chamfer, 0.8), (W - 0.8, chamfer), (W - 0.8, H - chamfer),
            (W - chamfer, H - 0.8), (chamfer, H - 0.8), (0.8, H - chamfer), (0.8, chamfer)]
    inside = [(chamfer + 2.4, 3.2), (W - chamfer - 2.4, 3.2), (W - 3.2, chamfer + 2.4),
              (W - 3.2, H - chamfer - 2.4), (W - chamfer - 2.4, H - 3.2),
              (chamfer + 2.4, H - 3.2), (3.2, H - chamfer - 2.4), (3.2, chamfer + 2.4)]

    if state == "normal":
        fill, a = (11, 27, 48), 226
        edge_col, edge_a = CYAN, 225
        glyph = None
    elif state == "hover":
        fill, a = (15, 37, 62), 232
        edge_col, edge_a = (125, 244, 255), 255
        glyph = None
    elif state == "pressed":
        fill, a = (24, 49, 78), 240
        edge_col, edge_a = (225, 255, 255), 255
        glyph = None
    else:  # disabled
        fill, a = (17, 21, 29), 205
        edge_col, edge_a = (86, 100, 112), 170
        glyph = None

    base = Art((W, H))
    base.poly(poly, C(edge_col, edge_a), 0, fill=C(fill, a))

    # inner top sheen + bottom shade (constant in x -> stretch safe)
    layer = Image.new("RGBA", A.img.size, (0, 0, 0, 0))
    layer = over(layer, vert_band((W, H), (0, 1.4, W, 20), (150, 220, 255) if state != "disabled" else (150, 165, 180), 34 if state != "disabled" else 16, 0))
    layer = over(layer, vert_band((W, H), (0, H - 14, W, H - 1.2), (0, 0, 0), 0, 42))
    layer.putalpha(ImageChops.multiply(layer.getchannel("A"), mask_from((W, H), (2, 2, W - 2, H - 2), 0)))
    base.img = over(base.img, layer)

    # outline + inner glow
    inner = Art((W, H))
    inner.poly(inside, C(edge_col, 120 if state != "disabled" else 70), 0.9, fill=None, close=True)
    base.img = over(base.img, glow_layer(inner.img, 4.0, edge_col, 1.2 if state == "hover" else 0.8))
    base.img = over(base.img, inner.img)
    base.poly(poly, C(edge_col, edge_a), 1.5, fill=None, close=True)

    # corner ticks
    B = Art((W, H))
    tick = 9.0
    tick_col = C(edge_col, 200 if state != "disabled" else 120)
    B.line([(4.2, 4.2 + tick), (4.2, 4.2), (4.2 + tick, 4.2)], tick_col, 1.6)
    B.line([(W - 4.2 - tick, 4.2), (W - 4.2, 4.2), (W - 4.2, 4.2 + tick)], tick_col, 1.6)
    B.line([(4.2, H - 4.2 - tick), (4.2, H - 4.2), (4.2 + tick, H - 4.2)], tick_col, 1.6)
    B.line([(W - 4.2 - tick, H - 4.2), (W - 4.2, H - 4.2), (W - 4.2, H - 4.2 - tick)], tick_col, 1.6)
    base.img = over(base.img, glow_layer(B.img, 2.6, edge_col, 1.0))
    base.img = over(base.img, B.img)

    if state == "pressed":
        # inset shadow ring
        sh = Art((W, H))
        sh.poly(inside, C((0, 0, 0), 90), 2.4, fill=None, close=True)
        base.img = over(base.img, glow_layer(sh.img, 3.0, (0, 0, 0), 0.8))
        base.img = over(base.img, sh.img)

    assert glyph is None
    clip_alpha(base.img, poly_mask((W, H), poly))
    return resize_rgba(base.img, (W, H))


def bar_bg_9p():
    W, H = 48, 24
    A = Art((W, H))
    base = Image.new("RGBA", A.img.size, (0, 0, 0, 0))
    base.paste(Image.new("RGBA", A.img.size, C((5, 9, 16), 236)), (0, 0),
               mask_from((W, H), (0.5, 0.5, W - 0.5, H - 0.5), 3.2))
    A.img = over(A.img, base)
    # inner shadow top, uniform in x
    A.img = over(A.img, vert_band((W, H), (1, 1, W - 1, 8), (0, 0, 0), 70, 0))
    # border
    sky = Art((W, H))
    sky.rect((1.2, 1.2, W - 1.2, H - 1.2), radius=2.6, outline=C((34, 104, 128), 210), width=1.0)
    A.img = over(A.img, glow_layer(sky.img, 2.0, (34, 130, 160), 0.7))
    A.img = over(A.img, sky.img)
    # small end ticks inside the corner slices
    T = Art((W, H))
    T.line([(3.4, H / 2), (5.0, H / 2)], C((70, 200, 230), 160), 1.4)
    T.line([(W - 5.0, H / 2), (W - 3.4, H / 2)], C((70, 200, 230), 160), 1.4)
    A.img = over(A.img, T.img)
    clip_alpha(A.img, mask_from((W, H), (0.3, 0.3, W - 0.3, H - 0.3), 3.1))
    return resize_rgba(A.img, (W, H))


def bar_fill(name):
    W, H = 64, 16
    if name == "shield":
        c0, c1 = CYAN, (228, 252, 255)
        top = (200, 252, 255)
    elif name == "exp":
        c0, c1 = PURPLE, MAGENTA
        top = (235, 200, 255)
    elif name == "fuel":
        c0, c1 = MINT, (198, 246, 112)
        top = (215, 255, 195)
    elif name == "boost":
        c0, c1 = (255, 108, 58), AMBER
        top = (255, 220, 160)
    else:  # hp
        c0, c1 = (255, 52, 74), (255, 152, 72)
        top = (255, 180, 170)

    Wp, Hp = W * S, H * S
    xs = np.linspace(0, 1, Wp, dtype=np.float32)[None, :, None]
    ys = np.linspace(0, 1, Hp, dtype=np.float32)[:, None, None]
    cols = np.array(c0, np.float32)[None, None, :] * (1 - xs) + np.array(c1, np.float32)[None, None, :] * xs
    bevel = 1.0 + 0.30 * np.exp(-((ys - 0.20) ** 2) / 0.02) - 0.24 * np.clip((ys - 0.74) / 0.26, 0, 1)
    cols = np.clip(cols * bevel, 0, 255)
    alpha = np.full((Hp, Wp, 1), 255.0, np.float32)
    arr = np.concatenate([cols, alpha], -1).astype(np.uint8)
    grad = Image.fromarray(arr, "RGBA")

    A = Art((W, H))
    A.img = over(A.img, grad)
    mask = mask_from((W, H), (0.5, 0.5, W - 0.5, H - 0.5), 2.4)
    A.img.putalpha(ImageChops.multiply(A.img.getchannel("A"), mask))
    # glossy top highlight / darker bottom seam
    A.line([(3.4, 2.2), (W - 3.4, 2.2)], C(top, 235), 1.2)
    A.line([(3.4, H - 2.4), (W - 3.4, H - 2.4)], C((0, 0, 0), 80), 1.2)
    return resize_rgba(A.img, (W, H))


def prompt_key_9p():
    W = H = 96
    A = Art((W, H))
    clip = mask_from((W, H), (1, 1, W - 1, H - 1), 11)
    base = Image.new("RGBA", A.img.size, C((8, 14, 24), 222))
    base.putalpha(ImageChops.multiply(base.getchannel("A"), clip))
    base = over(base, vert_band((W, H), (1, 1.4, W - 1, 12), (140, 210, 240), 26, 0))
    base = over(base, vert_band((W, H), (1, H - 12, W - 1, H - 1), (0, 0, 0), 0, 34))

    stroke = Art((W, H))
    stroke.rect((1.5, 1.5, W - 1.5, H - 1.5), radius=10.5, outline=C((110, 220, 240), 200), width=1.2)
    base = over(base, stroke.img)
    inner = Art((W, H))
    inner.rect((4.0, 4.0, W - 4.0, H - 4.0), radius=8.5, outline=C((70, 160, 190), 70), width=0.9)
    base = over(base, inner.img)

    B = Art((W, H))
    for sx in (0, 1):
        for sy in (0, 1):
            x0, y0 = (6.0 if sx == 0 else W - 6.0), (6.0 if sy == 0 else H - 6.0)
            dx, dy = (1 if sx == 0 else -1), (1 if sy == 0 else -1)
            B.line([(x0, y0 + 10 * dy), (x0, y0), (x0 + 10 * dx, y0)], C((160, 240, 255), 230), 1.7)
    base = over(base, glow_layer(B.img, 2.6, CYAN, 0.9))
    base = over(base, B.img)
    clip_alpha(base, mask_from((W, H), (0.4, 0.4, W - 0.4, H - 0.4), 8.9))
    return resize_rgba(base, (W, H))


# ==========================================================================
# radar
# ==========================================================================
def radar_plate():
    W = H = 320
    cx = cy = 160.0
    R = 152.0
    A = Art((W, H))
    disc_mask = Image.new("L", A.img.size, 0)
    ImageDraw.Draw(disc_mask).ellipse(
        [(cx - R) * S, (cy - R) * S, (cx + R) * S, (cy + R) * S], fill=255)
    disc = radial_fill((W, H), cx, cy, 0, R, (18, 32, 52), 244, (6, 10, 18), 251, hard=True)
    A.img = over(A.img, disc)

    # faint instrument grid inside the plate
    for r, al in ((38, 78), (76, 68), (114, 58), (146, 52)):
        A.circle((cx, cy), r, C((72, 198, 232), al), width=1.0)
    A.line([(cx - 140, cy), (cx + 140, cy)], C((72, 198, 232), 68), 1.0)
    A.line([(cx, cy - 140), (cx, cy + 140)], C((72, 198, 232), 68), 1.0)
    for ang in (45, 135):
        dx, dy = math.cos(math.radians(ang)), math.sin(math.radians(ang))
        A.line([(cx - 140 * dx, cy - 140 * dy), (cx + 140 * dx, cy + 140 * dy)],
               C((72, 198, 232), 26), 1.0)

    # tick ring
    for i in range(36):
        ang = i * 10.0
        major = (i % 9 == 0)
        mid = (i % 3 == 0)
        r0 = 135 if major else (141 if mid else 145)
        p0 = (cx + r0 * math.cos(math.radians(ang)), cy + r0 * math.sin(math.radians(ang)))
        p1 = (cx + 146 * math.cos(math.radians(ang)), cy + 146 * math.sin(math.radians(ang)))
        A.line([p0, p1], C((160, 242, 255), 200 if major else (110 if mid else 70)),
               1.6 if major else (1.1 if mid else 0.9))

    # inner dark ring for depth, then rim glow -- both confined to the plate
    inner_dark = Image.new("RGBA", A.img.size, (0, 0, 0, 0))
    ImageDraw.Draw(inner_dark).ellipse(
        [(cx - R + 9) * S, (cy - R + 9) * S, (cx + R - 9) * S, (cy + R - 9) * S],
        outline=C((0, 0, 0), 120), width=int(7 * S))
    ig = glow_layer(inner_dark, 5.0, (0, 0, 0), 0.6)
    ig.putalpha(ImageChops.multiply(ig.getchannel("A"), disc_mask))
    A.img = over(A.img, ig)

    rim = Image.new("RGBA", A.img.size, (0, 0, 0, 0))
    ImageDraw.Draw(rim).ellipse(
        [(cx - R + 3.2) * S, (cy - R + 3.2) * S, (cx + R - 3.2) * S, (cy + R - 3.2) * S],
        outline=C(CYAN, 200), width=int(4.2 * S))
    rg = glow_layer(rim, 5.0, CYAN, 0.95)
    rg.putalpha(ImageChops.multiply(rg.getchannel("A"), disc_mask))
    A.img = over(A.img, rg)

    # crisp outer rings + centre
    A.circle((cx, cy), R - 0.8, C(CYAN, 240), width=2.2)
    A.circle((cx, cy), R - 3.6, C((215, 252, 255), 120), width=0.9)
    A.circle((cx, cy), 8.5, C(CYAN, 60), width=1.0)
    A.dot((cx, cy), 2.8, C((205, 250, 255), 235))
    return resize_rgba(A.img, (W, H))


def radar_sweep():
    W = H = 320
    cx = cy = 160.0
    span = 70.0
    R = 149.0
    arr = np.zeros((H * S, W * S, 4), np.float32)
    yy, xx = np.mgrid[0:H * S, 0:W * S].astype(np.float32) + 0.5
    dx = (xx - cx * S) / S
    dy = (yy - cy * S) / S
    r = np.hypot(dx, dy)
    ang = np.degrees(np.arctan2(dy, dx))
    d = (ang + 90.0 + 180.0) % 360.0 - 180.0
    in_sector = np.abs(d) <= span / 2.0
    t = np.clip((d + span / 2.0) / span, 0, 1)           # 0 = trailing, 1 = leading
    radial = np.clip((r - 8) / 34.0, 0, 1) * (1 - np.clip((r - (R - 14)) / 14.0, 0, 1))
    alpha = 150.0 * (t ** 1.9) * radial * in_sector
    lead = np.exp(-((d - span / 2.0) ** 2) / (2 * 1.0 ** 2)) * np.clip((R - r) / 6.0, 0, 1) * (r > 3)
    alpha = np.clip(alpha + 210.0 * lead, 0, 255)
    rgb = np.array([76.0, 214.0, 255.0], np.float32)
    tint = np.clip(lead[..., None] * 0.85, 0, 1)
    rgb_all = rgb[None, None, :] * (1 - tint) + np.array([226.0, 250.0, 255.0], np.float32)[None, None, :] * tint
    arr[..., :3] = rgb_all
    arr[..., 3] = alpha
    img = Image.fromarray(np.clip(arr, 0, 255).astype(np.uint8), "RGBA")
    out = add_glow(img, glow_layer(img, 3.0, (90, 220, 255), 0.5))
    return resize_rgba(out, (W, H))


def radar_player():
    W = H = 28
    A = Art((W, H))
    A.poly([(14, 4.5), (23, 23), (14, 19), (5, 23)], C(WHITE, 255), 2.0, fill=C((235, 252, 255), 245))
    out = add_glow(Image.new("RGBA", A.img.size, (0, 0, 0, 0)), glow_layer(A.img, 3.0, (160, 245, 255), 1.0))
    out = over(out, A.img)
    return resize_rgba(out, (W, H))


def radar_zone():
    W = H = 24
    A = Art((W, H))
    A.poly([(12, 2.5), (21.5, 12), (12, 21.5), (2.5, 12)], C(MINT, 255), 2.0, fill=C((40, 120, 95), 110))
    out = add_glow(Image.new("RGBA", A.img.size, (0, 0, 0, 0)), glow_layer(A.img, 3.0, MINT, 1.0))
    out = over(out, A.img)
    return resize_rgba(out, (W, H))


def radar_shop():
    W = H = 24
    A = Art((W, H))
    A.rect((5, 5, 19, 19), radius=1.5, outline=C(AMBER, 255), width=2.0)
    A.dot((12, 12), 2.2, C((255, 240, 205), 255))
    out = add_glow(Image.new("RGBA", A.img.size, (0, 0, 0, 0)), glow_layer(A.img, 3.0, AMBER, 1.0))
    out = over(out, A.img)
    return resize_rgba(out, (W, H))


def radar_enemy():
    W = H = 28
    A = Art((W, H))
    A.circle((14, 14), 9.2, C((255, 90, 90), 200), width=1.5)
    A.dot((14, 14), 4.2, C((255, 70, 80), 255))
    A.dot((14, 14), 1.8, C((255, 220, 210), 255))
    out = add_glow(Image.new("RGBA", A.img.size, (0, 0, 0, 0)), glow_layer(A.img, 3.5, (255, 70, 90), 1.1))
    out = over(out, A.img)
    return resize_rgba(out, (W, H))


def radar_threat():
    W = H = 18
    A = Art((W, H))
    A.dot((9, 9), 3.4, C((255, 110, 60), 255))
    A.circle((9, 9), 6.2, C((255, 150, 90), 160), width=1.0)
    out = add_glow(Image.new("RGBA", A.img.size, (0, 0, 0, 0)), glow_layer(A.img, 3.0, (255, 90, 50), 1.2))
    out = over(out, A.img)
    return resize_rgba(out, (W, H))


def threat_arc():
    W = H = 512
    cx = cy = 256.0
    rr = 225.0
    half = 45.0  # exact 90 degrees, centred on top (-Y)
    arr = np.zeros((H * S, W * S, 4), np.float32)
    yy, xx = np.mgrid[0:H * S, 0:W * S].astype(np.float32) + 0.5
    dx = (xx - cx * S) / S
    dy = (yy - cy * S) / S
    r = np.hypot(dx, dy)
    ang = np.degrees(np.arctan2(dy, dx))
    d = (ang - (-90.0) + 180.0) % 360.0 - 180.0
    band = np.clip((r - (rr - 15)) / 3.0, 0, 1) * (1 - np.clip((r - (rr + 15)) / 3.0, 0, 1))
    ang_soft = np.clip((half - np.abs(d)) / 3.0, 0, 1)
    core = band * ang_soft
    edge = np.exp(-((r - (rr - 13)) ** 2) / (2 * 2.0 ** 2)) * ang_soft
    alpha = 245.0 * core + 60.0 * edge
    rgb = np.array([238.0, 252.0, 255.0], np.float32)
    arr[..., :3] = rgb[None, None, :]
    arr[..., 3] = np.clip(alpha, 0, 255)
    img = Image.fromarray(np.clip(arr, 0, 255).astype(np.uint8), "RGBA")
    out = add_glow(img, glow_layer(img, 4.0, (200, 245, 255), 1.0))
    out = add_glow(out, glow_layer(img, 12.0, (120, 210, 255), 0.8))
    return resize_rgba(out, (W, H))


# ==========================================================================
# joystick / action buttons
# ==========================================================================
def joystick_base():
    W = H = 256
    A = Art((W, H))
    c = (128, 128)
    # faint interior wash
    A.img = over(A.img, radial_fill((W, H), 128, 128, 0, 124, (40, 120, 150), 16, (20, 60, 80), 0))
    A.circle(c, 120, C(CYAN, 210), width=2.4)
    A.circle(c, 111, C(CYAN, 80), width=1.0)
    A.circle(c, 99, C(CYAN, 46), width=1.0)
    # cross
    A.line([(128, 74), (128, 182)], C(CYAN, 55), 1.4)
    A.line([(74, 128), (182, 128)], C(CYAN, 55), 1.4)
    # tick marks on the diagonals
    for ang in (45, 135, 225, 315):
        x0 = 128 + 112 * math.cos(math.radians(ang))
        y0 = 128 + 112 * math.sin(math.radians(ang))
        x1 = 128 + 120 * math.cos(math.radians(ang))
        y1 = 128 + 120 * math.sin(math.radians(ang))
        A.line([(x0, y0), (x1, y1)], C(CYAN, 150), 1.4)
    A.circle(c, 5.0, C(CYAN, 90), width=1.2)
    out = add_glow(Image.new("RGBA", A.img.size, (0, 0, 0, 0)), glow_layer(A.img, 5.0, CYAN, 0.35))
    out = over(out, A.img)
    return resize_rgba(out, (W, H))


def joystick_knob():
    W = H = 160
    c = (80, 80)
    A = Art((W, H))
    A.img = over(A.img, radial_fill((W, H), 76, 72, 0, 63,
                                    (165, 240, 252), 130, (22, 62, 92), 78, hard=True))
    A.arc(c, 56, 25, 155, C((0, 16, 34), 120), width=6.0)
    A.circle(c, 63, C((228, 253, 255), 250), width=2.6)
    A.circle(c, 57.5, C(CYAN, 95), width=1.2)
    A.circle(c, 48, C(CYAN, 42), width=1.0)
    # specular highlight
    A.arc(c, 55.5, 196, 252, C((255, 255, 255), 235), width=2.8)
    A.arc(c, 51, 200, 246, C((225, 255, 255), 110), width=1.4)
    A.dot((80, 80), 4.0, C((225, 255, 255), 130))
    out = add_glow(Image.new("RGBA", A.img.size, (0, 0, 0, 0)),
                   glow_layer(A.img, 5.0, CYAN, 0.40))
    out = over(out, A.img)
    return resize_rgba(out, (W, H))


def btn_boost(down=False):
    W = H = 192
    A = Art((W, H))
    c = (96, 96)
    R = 90.0
    if not down:
        A.img = over(A.img, radial_fill((W, H), 96, 96, 0, 80, (26, 24, 32), 242, (8, 11, 20), 250, hard=True))
        ring, ring2, glyph = C(CYAN, 110), C(AMBER, 220), C(AMBER, 255)
        glyph_core = C((255, 232, 190), 255)
    else:
        A.img = over(A.img, radial_fill((W, H), 96, 96, 0, 80, (66, 42, 22), 248, (18, 14, 14), 252, hard=True))
        ring, ring2, glyph = C((255, 220, 170), 200), C(AMBER, 255), C((255, 240, 215), 255)
        glyph_core = C(WHITE, 255)
    A.circle(c, R, ring, width=2.6)
    A.circle(c, 82.5, ring2, width=2.6)
    # ticks
    for i in range(12):
        ang = i * 30.0
        p0 = (96 + 85 * math.cos(math.radians(ang)), 96 + 85 * math.sin(math.radians(ang)))
        p1 = (96 + 90 * math.cos(math.radians(ang)), 96 + 90 * math.sin(math.radians(ang)))
        A.line([p0, p1], C(AMBER, 130), 1.6)
    # double chevron (boost / thrust)
    G = Art((W, H))
    G.line([(72, 88), (96, 62), (120, 88)], glyph, 7.0)
    G.line([(72, 116), (96, 90), (120, 116)], glyph, 7.0)
    G.line([(72, 88), (96, 62), (120, 88)], C((255, 255, 255), 90), 2.0)
    A.img = over(A.img, glow_layer(G.img, 5.0, AMBER, 1.1))
    A.img = over(A.img, G.img)
    if down:
        pass
    out = add_glow(Image.new("RGBA", A.img.size, (0, 0, 0, 0)), glow_layer(A.img, 4.0, (255, 170, 90), 0.35))
    out = over(out, A.img)
    return resize_rgba(out, (W, H))


def btn_skill():
    W = H = 160
    A = Art((W, H))
    c = (80, 80)
    r = 68.0
    hexp = [(80 + r * math.cos(math.radians(a)), 80 + r * math.sin(math.radians(a)))
            for a in (-90, -30, 30, 90, 150, 210)]
    A.poly(hexp, C((8, 15, 27), 175), 0, fill=None, close=True)
    A.img = over(A.img, A.img)  # keep flat
    A.poly(hexp, C(CYAN, 215), 2.4, fill=C((8, 16, 28), 170), close=True)
    A.poly([(80 + (x - 80) * 0.87, 80 + (y - 80) * 0.87) for x, y in hexp], C(CYAN, 50), 1.0, close=True)
    # inner tick marks at the six facets
    for a_deg in (-90, -30, 30, 90, 150, 210):
        a_r = math.radians(a_deg)
        p0 = (80 + 48 * math.cos(a_r), 80 + 48 * math.sin(a_r))
        p1 = (80 + 56 * math.cos(a_r), 80 + 56 * math.sin(a_r))
        A.line([p0, p1], C((140, 235, 255), 90), 1.2)
    for x, y in hexp:
        A.dot((x, y), 2.8, C((200, 252, 255), 230))
    out = add_glow(Image.new("RGBA", A.img.size, (0, 0, 0, 0)), glow_layer(A.img, 4.0, CYAN, 0.45))
    out = over(out, A.img)
    return resize_rgba(out, (W, H))


def btn_item():
    W = H = 160
    A = Art((W, H))
    A.rect((16, 16, 144, 144), radius=18, fill=C((8, 15, 26), 165), outline=C(CYAN, 205), width=2.4)
    A.rect((21, 21, 139, 139), radius=14, outline=C(CYAN, 45), width=1.0)
    B = Art((W, H))
    for sx in (0, 1):
        for sy in (0, 1):
            x0 = 22 if sx == 0 else W - 22
            y0 = 22 if sy == 0 else H - 22
            dx = 1 if sx == 0 else -1
            dy = 1 if sy == 0 else -1
            B.line([(x0, y0 + 18 * dy), (x0, y0), (x0 + 18 * dx, y0)], C((190, 250, 255), 225), 2.2)
    A.img = over(A.img, glow_layer(B.img, 3.2, CYAN, 0.8))
    A.img = over(A.img, B.img)
    out = add_glow(Image.new("RGBA", A.img.size, (0, 0, 0, 0)), glow_layer(A.img, 3.5, CYAN, 0.3))
    out = over(out, A.img)
    return resize_rgba(out, (W, H))


# ==========================================================================
# icons - designed on a 128px grid, down-sampled to the requested size
# ==========================================================================
def ic_pulse(A):
    c = (64, 64)
    A.circle(c, 18, C(CYAN, 255), width=5.5)
    A.circle(c, 29, C(CYAN, 180), width=5.0)
    A.circle(c, 40, C((120, 205, 240), 105), width=4.6)
    A.line([(47, 64), (81, 64)], C(ICE, 255), 6.0)
    A.line([(64, 47), (64, 81)], C(ICE, 255), 6.0)
    A.dot(c, 3.2, C(WHITE, 255))


def ic_gravity(A):
    c = (64, 64)
    pts = []
    for i in range(96):
        t = i / 95.0
        ang = math.radians(-90 + t * 1.55 * 360)
        r = 12 + 30 * t
        pts.append((64 + r * math.cos(ang), 64 + r * math.sin(ang)))
    # colour ramp: cyan core -> purple rim
    n = len(pts)
    for i in range(n - 1):
        t = i / (n - 1)
        col = lerp(CYAN, PURPLE, min(1.0, t * 1.25))
        alpha = 255 if t < 0.9 else int(255 - (t - 0.9) / 0.1 * 90)
        A.line([pts[i], pts[i + 1]], C(col, alpha), 5.4, caps=False)
    A.circle(c, 5.0, C(ICE, 255), width=0, fill=C((225, 255, 255), 255))
    A.circle(c, 10.5, C(CYAN, 80), width=1.6)
    # inward chevron at the well mouth
    A.line([(76, 26), (64, 38), (76, 50)], C((190, 240, 255), 190), 3.6)


def ic_dash(A):
    A.line([(21, 49), (56, 49)], C(CYAN, 120), 4.0)
    A.line([(18, 64), (63, 64)], C(CYAN, 210), 5.2)
    A.line([(23, 79), (54, 79)], C(CYAN, 120), 4.0)
    ship = [(74, 46), (94, 58), (104, 64), (94, 70), (74, 82), (80, 64)]
    A.poly(ship, C(ICE, 255), 5.4, fill=C((30, 90, 120), 190))
    A.line([(80, 56), (92, 64), (80, 72)], C((230, 255, 255), 220), 3.0)


def ic_decoy(A):
    c = (64, 66)
    A.arc(c, 27, 205, 335, C(MAGENTA, 150), 4.4)
    A.arc(c, 37, 210, 330, C(MAGENTA, 85), 4.0)
    diamond = [(64, 42), (79, 60), (64, 86), (49, 60)]
    A.poly(diamond, C(MAGENTA, 255), 5.4, fill=C((64, 14, 36), 180))
    A.dot((64, 61), 4.0, C((255, 205, 228), 255))
    A.line([(64, 86), (64, 95)], C(MAGENTA, 255), 5.0)
    A.line([(53, 95), (75, 95)], C(MAGENTA, 230), 5.0)


def ic_fuel(A):
    A.rect((44, 38, 84, 96), radius=7, outline=C(MINT, 255), width=5.2)
    A.rect((55, 29, 73, 38), radius=2, outline=C(MINT, 255), width=4.4)
    A.line([(50, 84), (78, 84)], C(MINT, 120), 2.6)
    droplet(A, 64, 66, 12, C((215, 255, 238), 250), 3.0, C((180, 255, 220), 120))
    A.dot((72, 56), 2.4, C((240, 255, 250), 220))


def ic_flare(A):
    c = (64, 68)
    for ang in (-150, -30, 90):
        a = math.radians(ang)
        p0 = (64 + 15 * math.cos(a), 68 + 15 * math.sin(a))
        p1 = (64 + 30 * math.cos(a), 68 + 30 * math.sin(a))
        A.line([p0, p1], C(AMBER, 220), 4.4)
        A.dot((64 + 39 * math.cos(a), 68 + 39 * math.sin(a)), 4.2, C((255, 226, 175), 255))
        A.circle((64 + 39 * math.cos(a), 68 + 39 * math.sin(a)), 8.0, C(AMBER, 110), width=1.2)
    A.circle(c, 10, C(AMBER, 200), width=3.4)
    A.dot(c, 4.0, C((255, 245, 220), 255))


def ic_item_decoy(A):
    c = (64, 64)
    A.arc(c, 42, -62, 62, C(MAGENTA, 95), 4.0)
    A.arc(c, 42, 118, 242, C(MAGENTA, 95), 4.0)
    pod = [(64, 27), (80, 45), (80, 83), (64, 99), (48, 83), (48, 45)]
    A.poly(pod, C(MAGENTA, 255), 5.2, fill=C((58, 10, 32), 200))
    A.circle(c, 9.5, C((255, 175, 210), 255), width=4.2)
    A.dot(c, 3.0, C(WHITE, 255))


def ic_charge(A):
    c = (64, 64)
    A.arc(c, 40, -58, 240, C(CYAN, 235), 5.4)
    bolt = [(72, 33), (43, 68), (60, 68), (54, 99), (85, 59), (66, 59)]
    A.poly(bolt, C(AMBER, 255), 2.2, fill=C((255, 197, 96), 255))
    A.poly([(67, 45), (52, 64), (60, 64), (57, 82), (74, 61), (65, 61)],
           C((255, 246, 225), 255), 0, fill=C((255, 238, 200), 235))
    A.dot((72, 33), 3.0, C((255, 235, 190), 255))


def ic_item_mine(A):
    """引力水雷道具：紫色球体 + 三条环绕轨道 + 三根短刺。"""
    c = (64, 64)
    A.arc(c, 44, 196, 344, C(PURPLE, 130), 3.8)
    A.arc(c, 44, 16, 164, C(PURPLE, 130), 3.8)
    A.arc(c, 33, 22, 158, C((186, 158, 255), 120), 3.0)
    A.arc(c, 33, 202, 338, C((186, 158, 255), 95), 3.0)
    for ang in (-90, 30, 150):
        a = math.radians(ang)
        p0 = (64 + 21 * math.cos(a), 64 + 21 * math.sin(a))
        p1 = (64 + 30 * math.cos(a), 64 + 30 * math.sin(a))
        A.line([p0, p1], C((208, 178, 255), 235), 4.4)
        A.dot((64 + 34 * math.cos(a), 64 + 34 * math.sin(a)), 3.4,
              C((240, 214, 255), 255))
    A.circle(c, 20, C(PURPLE, 255), 5.2, fill=C((44, 20, 82), 215))
    A.circle(c, 11, C((186, 156, 255), 190), 2.4)
    A.dot((60, 59), 4.0, C((246, 236, 255), 255))
    star4(A, 64, 64, 6.0, C((255, 246, 255), 190), 0.30)


def ic_service(A):
    """现场满额维修：护盾 + 扳手。"""
    shield = [(64, 24), (95, 37), (95, 64), (64, 100), (33, 64), (33, 37)]
    A.poly(shield, C(MINT, 255), 5.2, fill=C((10, 42, 33), 195))
    A.poly([(64, 34), (86, 43), (86, 62), (64, 90), (42, 62), (42, 43)],
           C((130, 255, 205), 110), 2.2, close=True)
    # wrench: open C-head + slim handle, laid across the shield
    A.line([(44, 86), (66, 64)], C((228, 255, 243), 252), 6.4)
    A.arc((77, 51), 11, 36, 296, C((228, 255, 243), 252), 5.6)
    A.dot((44, 86), 4.4, C((228, 255, 243), 240))
    A.dot((74, 34), 2.6, C((16, 74, 56), 210))


def ic_mod_gravity(A):
    """引力弹弓流改装芯片：箭头绕行星 + 速度线。"""
    cx, cy = 64.0, 66.0
    A.circle((58, 70), 18, C((176, 238, 255), 235), 4.6, fill=C((9, 40, 54), 205))
    A.arc((58, 70), 9.5, 200, 340, C((140, 235, 255), 150), 2.2)
    A.dot((52, 64), 2.8, C((190, 246, 255), 200))
    # slingshot trajectory: swings over the planet and leaves to the upper right
    A.arc((cx, cy), 38, 186, 300, C(CYAN, 235), 5.2)
    a = math.radians(305.0)
    ex, ey = cx + 38 * math.cos(a), cy + 38 * math.sin(a)
    rad = (math.cos(a), math.sin(a))
    tan = (-math.sin(a), math.cos(a))
    tip = (ex + tan[0] * 15.0, ey + tan[1] * 15.0)
    b1 = (ex + rad[0] * 12.0 - tan[0] * 3.0, ey + rad[1] * 12.0 - tan[1] * 3.0)
    b2 = (ex - rad[0] * 12.0 - tan[0] * 3.0, ey - rad[1] * 12.0 - tan[1] * 3.0)
    A.poly([tip, b1, b2], C(CYAN, 255), 2.2, fill=C((196, 252, 255), 250))
    for dy, al in ((-9, 120), (1, 190), (11, 120)):
        A.line([(18, 88 + dy), (38, 88 + dy)], C(CYAN, al), 4.2)


def ic_mod_deceive(A):
    """欺骗劫持流：断裂/偏移的锁定准星 + 诱饵点。"""
    c = (60, 60)
    A.arc(c, 33, -42, 58, C(MAGENTA, 240), 5.2)
    A.arc(c, 33, 82, 172, C(MAGENTA, 240), 5.2)
    A.arc(c, 33, 196, 244, C(MAGENTA, 120), 5.2)
    # extruded radar ticks, offset from the reticle centre
    for ang in (-90, 20):
        a = math.radians(ang)
        p0 = (c[0] + 39 * math.cos(a), c[1] + 39 * math.sin(a))
        p1 = (c[0] + 45 * math.cos(a), c[1] + 45 * math.sin(a))
        A.line([p0, p1], C((255, 150, 195), 220), 3.6)
    # crosshair sits off-centre -> the lock is spoiled
    A.line([(74, 54), (74, 84)], C((255, 186, 214), 235), 3.8)
    A.line([(59, 69), (89, 69)], C((255, 186, 214), 235), 3.8)
    A.dot((74, 69), 4.0, C(WHITE, 255))
    A.dot((34, 96), 5.0, C((255, 204, 228), 255))
    A.circle((34, 96), 10, C(MAGENTA, 150), 2.4)
    A.line([(41, 91), (56, 78)], C(MAGENTA, 110), 2.2)


def ic_mod_billiard(A):
    """星体台球流：陨石 + 台球撞击线。"""
    rock = [(40, 42), (64, 38), (82, 52), (88, 74), (76, 94), (52, 100),
            (34, 88), (30, 60)]
    A.poly(rock, C(AMBER, 255), 5.0, fill=C((58, 34, 10), 225))
    A.circle((52, 60), 8, C((255, 214, 156), 140), 2.4)
    A.circle((72, 80), 5, C((255, 214, 156), 110), 2.0)
    A.dot((44, 80), 2.6, C((255, 226, 176), 160))
    A.line([(104, 22), (78, 43)], C((255, 240, 208), 255), 4.6)
    star4(A, 72, 45, 13, C((255, 242, 214), 235), 0.20)
    A.arc((72, 45), 17, -55, 55, C(AMBER, 150), 3.0)
    for dy in (-16, 4, 22):
        A.line([(96, 84 + dy), (108, 76 + dy)], C((255, 196, 110), 120), 3.0)
    A.dot((30, 50), 3.0, C((255, 220, 160), 200))
    A.dot((26, 70), 2.4, C((255, 210, 145), 170))


def ic_mod_trap(A):
    """陷阱阵列流：三角锚点 + 环绕弧线。"""
    c = (64, 64)
    A.arc(c, 42, 198, 342, C(PURPLE, 145), 4.4)
    A.arc(c, 42, 18, 162, C(PURPLE, 145), 4.4)
    A.arc(c, 30, 200, 340, C((178, 156, 255), 95), 3.0)
    A.arc(c, 30, 20, 160, C((178, 156, 255), 95), 3.0)
    for ang in (-90, 30, 150):
        a = math.radians(ang)
        ca, sa = math.cos(a), math.sin(a)
        px, py = -sa, ca
        tip = (64 + 34 * ca, 64 + 34 * sa)
        b1 = (64 + 20 * ca + 9 * px, 64 + 20 * sa + 9 * py)
        b2 = (64 + 20 * ca - 9 * px, 64 + 20 * sa - 9 * py)
        A.poly([tip, b1, b2], C((196, 176, 255), 245), 3.6, fill=C((46, 24, 86), 190))
        A.dot((64 + 26 * ca, 64 + 26 * sa), 2.8, C((230, 214, 255), 235))
    A.circle(c, 11, C((170, 140, 255), 200), 3.2)
    A.dot(c, 4.0, C((246, 240, 255), 255))


def ic_awaken(A):
    """超载觉醒：同心爆发环 + 闪电。"""
    c = (64, 64)
    A.arc(c, 46, -46, 46, C(AMBER, 150), 4.4)
    A.arc(c, 46, 134, 226, C(AMBER, 150), 4.4)
    A.arc(c, 46, 200, 340, C(MAGENTA, 95), 3.0)
    A.circle(c, 34, C(AMBER, 120), 3.2)
    A.circle(c, 24, C((255, 196, 110), 190), 3.4)
    bolt = [(78, 24), (42, 68), (62, 68), (52, 106), (90, 56), (66, 56)]
    A.poly(bolt, C(MAGENTA, 235), 2.6, fill=C((255, 198, 102), 250))
    A.poly([(72, 38), (54, 64), (64, 64), (58, 88), (78, 58), (67, 58)],
           C((255, 248, 224), 252), 0, fill=C((255, 246, 218), 240))
    A.dot((78, 24), 3.4, C((255, 238, 190), 255))
    A.dot((52, 106), 3.0, C((255, 226, 170), 235))


def icon_drawings():
    return {
        "icon_skill_pulse": (ic_pulse, CYAN),
        "icon_skill_gravity": (ic_gravity, PURPLE),
        "icon_skill_dash": (ic_dash, CYAN),
        "icon_skill_decoy": (ic_decoy, MAGENTA),
        "icon_item_fuel": (ic_fuel, MINT),
        "icon_item_flare": (ic_flare, AMBER),
        "icon_item_decoy": (ic_item_decoy, MAGENTA),
        "icon_item_charge": (ic_charge, AMBER),
        "icon_item_mine": (ic_item_mine, PURPLE),
        "icon_service": (ic_service, MINT),
        "icon_mod_gravity": (ic_mod_gravity, CYAN),
        "icon_mod_deceive": (ic_mod_deceive, MAGENTA),
        "icon_mod_billiard": (ic_mod_billiard, AMBER),
        "icon_mod_trap": (ic_mod_trap, PURPLE),
        "icon_awaken": (ic_awaken, AMBER),
    }


def make_icon(name, size, fn, color):
    A = Art((128, 128))
    fn(A)
    glows = [(10.0, color, 0.85), (4.0, color, 0.55)]
    return finish_icon(A, glows, (size, size))


def ic_token(A):
    c = (48, 48)
    r = 32.0
    hexp = [(48 + r * math.cos(math.radians(a)), 48 + r * math.sin(math.radians(a)))
            for a in (0, 60, 120, 180, 240, 300)]
    A.poly(hexp, C(MAGENTA, 255), 4.4, fill=C((72, 16, 40), 190))
    A.poly([(48 + (x - 48) * 0.72, 48 + (y - 48) * 0.72) for x, y in hexp],
           C((255, 160, 200), 120), 2.0, close=True)
    star4(A, 48, 48, 13, C((255, 210, 230), 255), 0.22)
    A.circle(c, 3.0, C((255, 245, 250), 255), width=0, fill=C((255, 245, 250), 255))


def ic_shield(A):
    pts = [(64, 24), (95, 37), (95, 65), (64, 100), (33, 65), (33, 37)]
    A.poly(pts, C(CYAN, 255), 5.4, fill=C((10, 36, 48), 170))
    inner = [(64, 38), (82, 46), (82, 63), (64, 85), (46, 63), (46, 46)]
    A.poly(inner, C(CYAN, 100), 2.4, close=True)
    A.line([(64, 48), (64, 76)], C((190, 250, 255), 150), 2.0)


def ic_exp(A):
    star4(A, 64, 62, 34, C(PURPLE, 255), 0.26)
    star4(A, 64, 62, 22, C((210, 185, 255), 200), 0.30)
    A.dot((94, 92), 4.0, C((230, 210, 255), 230))
    A.arc((64, 62), 44, 20, 70, C(PURPLE, 90), 1.8)


def ic_hud_fuel(A):
    droplet(A, 64, 62, 26, C(MINT, 255), 5.4, C((16, 60, 48), 160))
    A.line([(52, 68), (76, 68)], C((215, 255, 235), 140), 2.4)
    A.dot((56, 52), 4.0, C((230, 255, 245), 120))


def ic_hud_boost(A):
    A.line([(36, 76), (64, 46), (92, 76)], C(AMBER, 255), 6.0)
    A.line([(36, 102), (64, 72), (92, 102)], C(AMBER, 255), 6.0)
    A.line([(36, 50), (64, 28), (92, 50)], C((255, 225, 180), 0), 0)


def ic_hud_crosshair(A):
    c = (64, 64)
    for a0 in (-28, 62, 152, 242):
        A.arc(c, 34, a0, a0 + 56, C((255, 84, 84), 245), 5.4)
    for ang in (0, 90, 180, 270):
        p0 = (64 + 42 * math.cos(math.radians(ang)), 64 + 42 * math.sin(math.radians(ang)))
        p1 = (64 + 50 * math.cos(math.radians(ang)), 64 + 50 * math.sin(math.radians(ang)))
        A.line([p0, p1], C((255, 120, 100), 220), 3.6)
    A.dot(c, 4.0, C((255, 140, 120), 255))
    A.circle(c, 7.5, C((255, 90, 80), 120), width=1.4)


def icon64(name, size):
    fns = {
        "icon_shield.png": (ic_shield, CYAN),
        "icon_exp.png": (ic_exp, PURPLE),
        "icon_fuel.png": (ic_hud_fuel, MINT),
        "icon_boost.png": (ic_hud_boost, AMBER),
        "icon_crosshair.png": (ic_hud_crosshair, (255, 90, 80)),
    }
    fn, col = fns[name]
    A = Art((128, 128))
    fn(A)
    return finish_icon(A, [(8.0, col, 0.6), (3.0, col, 0.35)], (size, size))


# ==========================================================================
# full screen FX / patterns
# ==========================================================================
def vignette():
    W, H = 1280, 720
    yy, xx = np.mgrid[0:H, 0:W].astype(np.float32)
    nx = (xx - W / 2) / (W / 2)
    ny = (yy - H / 2) / (H / 2)
    d = np.hypot(nx, ny) / math.sqrt(2.0)
    a = 128.0 * np.clip(d, 0, 1) ** 2.1
    arr = np.zeros((H, W, 4), np.uint8)
    arr[..., 0:3] = 0
    arr[..., 3] = np.clip(a, 0, 255).astype(np.uint8)
    return Image.fromarray(arr, "RGBA")


def letterbox_glow():
    W, H = 2048, 256
    arr = np.zeros((H, W, 4), np.float32)
    y = np.arange(H, dtype=np.float32) - H / 2.0 + 0.5
    outer = 44.0 * np.exp(-(y / 52.0) ** 2)
    mid = 62.0 * np.exp(-(y / 16.0) ** 2)
    core = 120.0 * np.exp(-(y / 2.6) ** 2)
    alpha = np.clip(outer + mid + core, 0, 255)
    arr[..., 0] = 130
    arr[..., 1] = 228
    arr[..., 2] = 255
    arr[..., 3] = alpha[:, None]
    return Image.fromarray(np.clip(arr, 0, 255).astype(np.uint8), "RGBA")


def hex_pattern():
    W = H = 256
    a = np.array([32.0, 0.0])
    b = np.array([16.0, 32.0])
    yy, xx = np.mgrid[0:H * S, 0:W * S].astype(np.float32) + 0.5
    x = (xx / S).ravel()
    y = (yy / S).ravel()
    # lattice coordinates: p = u*a + v*b
    v = y / b[1]
    u = (x - v * b[0]) / a[0]
    u = np.round(u)
    v = np.round(v)
    px = u * a[0] + v * b[0]
    py = v * b[1]
    dx, dy = x - px, y - py
    neigh = [(32.0, 0.0), (-32.0, 0.0), (16.0, 32.0), (-16.0, -32.0), (-16.0, 32.0), (16.0, -32.0)]
    dmax = np.full_like(dx, -1e9)
    for nx, ny in neigh:
        ln = math.hypot(nx, ny)
        s = (nx * dx + ny * dy - (nx * nx + ny * ny) / 2.0) / ln
        dmax = np.maximum(dmax, s)
    dist = -dmax  # >0 inside the cell, 0 on an edge
    half_w = 0.5
    aa = 1.1
    alpha = np.clip((half_w - np.abs(dist)) / aa + 0.5, 0, 1) * 18.0
    rgb = np.array([120.0, 200.0, 230.0], np.float32)
    out = np.zeros((H * S, W * S, 4), np.float32)
    out[..., :3] = rgb
    out[..., 3] = alpha.reshape(H * S, W * S)
    img = Image.fromarray(np.clip(out, 0, 255).astype(np.uint8), "RGBA")
    return resize_rgba(img, (W, H))


def divider():
    W, H = 512, 8
    arr = np.zeros((H * S, W * S, 4), np.float32)
    x = np.arange(W * S, dtype=np.float32) / (W * S - 1)
    prof = np.clip(np.sin(np.pi * np.clip(x, 0.0, 0.999999)), 0.0, 1.0) ** 1.5
    y = np.arange(H * S, dtype=np.float32)[:, None]
    core = np.exp(-((y - 4 * S + 0.5) / (0.9 * S)) ** 2)
    halo = np.exp(-((y - 4 * S + 0.5) / (2.2 * S)) ** 2) * 0.55
    alpha = (core * 255 + halo * 255) * prof[None, :]
    arr[..., 0] = 120
    arr[..., 1] = 235
    arr[..., 2] = 255
    arr[..., 3] = np.clip(alpha, 0, 255)
    img = Image.fromarray(np.clip(arr, 0, 255).astype(np.uint8), "RGBA")
    return resize_rgba(img, (W, H))


def cd_dark():
    W = H = 256
    yy, xx = np.mgrid[0:H, 0:W].astype(np.float32)
    d = np.hypot(xx - 128, yy - 128) / 128.0
    a = 152.0 + 34.0 * np.clip(d, 0, 1) ** 1.5
    arr = np.zeros((H, W, 4), np.uint8)
    arr[..., 3] = np.clip(a, 0, 255).astype(np.uint8)
    return Image.fromarray(arr, "RGBA")


# ==========================================================================
# title logo
# ==========================================================================
def render_text_mask(text, size, tracking):
    font = ImageFont.truetype(FONT_BOLD, int(round(size * S)))
    track = tracking * S
    widths = [font.getlength(ch) for ch in text]
    total = sum(widths) + track * (len(text) - 1)
    W = int(math.ceil(total)) + 80
    H = int(math.ceil(size * S * 1.7))
    m = Image.new("L", (W, H), 0)
    d = ImageDraw.Draw(m)
    baseline = int(H * 0.80)
    x = 40.0
    for ch, wd in zip(text, widths):
        d.text((x, baseline), ch, font=font, fill=255, anchor="ls")
        x += wd + track
    bb = m.getbbox()
    return m.crop(bb)


def shift_mask(m, dx, dy):
    out = Image.new("L", m.size, 0)
    out.paste(m, (int(round(dx)), int(round(dy))))
    return out


def neon_glow(mask, layers, cap=0.95):
    """Single combined neon halo: alpha = weighted blur sum (capped), colour by radius."""
    Wp, Hp = mask.size
    acc = np.zeros((Hp, Wp), np.float32)
    col = np.zeros((Hp, Wp, 3), np.float32)
    for radius, color, weight in layers:
        g = np.asarray(mask.filter(ImageFilter.GaussianBlur(radius * S)), np.float32) / 255.0
        acc += weight * g
        col += np.asarray(color, np.float32)[None, None, :] * (weight * g)[..., None]
    a = np.clip(acc, 0.0, cap)
    rgb = np.where(a[..., None] > 1e-5, col / np.maximum(a[..., None], 1e-5), 0.0)
    out = np.concatenate([np.clip(rgb, 0.0, 1.0), a[..., None]], axis=-1)
    return Image.fromarray(np.clip(out * 255.0 + 0.5, 0, 255).astype(np.uint8), "RGBA")


def title_logo():
    W, H = 1400, 400
    Wp, Hp = W * S, H * S
    line1 = render_text_mask("ESCAPE", 118, 60)
    line2 = render_text_mask("GRAVITY", 228, 24)
    gap = 26 * S
    total = line1.height + gap + line2.height
    y0 = (Hp - total) // 2
    mask = Image.new("L", (Wp, Hp), 0)
    x1 = (Wp - line1.width) // 2
    mask.paste(line1, (x1, y0))
    y2 = y0 + line1.height + gap
    x2 = (Wp - line2.width) // 2
    mask.paste(line2, (x2, y2))
    bb = mask.getbbox()
    top, bot = bb[1], bb[3]

    # ---------------- decorations (behind the wordmark) ----------------
    deco = Image.new("RGBA", (Wp, Hp), (0, 0, 0, 0))
    dd = ImageDraw.Draw(deco)
    box1 = [(700 - 650) * S, (205 - 148) * S, (700 + 650) * S, (205 + 148) * S]
    box2 = [(700 - 556) * S, (205 - 112) * S, (700 + 556) * S, (205 + 112) * S]
    dd.ellipse(box1, outline=C(CYAN, 58), width=max(1, int(1.4 * S)))
    dd.ellipse(box2, outline=C(PURPLE, 52), width=max(1, int(1.2 * S)))
    dd.arc(box1, 154, 206, fill=C((210, 250, 255), 170), width=max(1, int(1.7 * S)))
    dd.arc(box1, 334, 386, fill=C((210, 250, 255), 170), width=max(1, int(1.7 * S)))
    dd.arc(box2, 160, 200, fill=C((190, 170, 255), 120), width=max(1, int(1.3 * S)))
    dd.arc(box2, 340, 380, fill=C((190, 170, 255), 120), width=max(1, int(1.3 * S)))

    # side accents flanking the big word
    mid_y = (y2 + line2.height * 0.45) / S
    for xa, xb, sign in ((46, 122, 1), (1278, 1354, -1)):
        dd.line([xa * S, mid_y * S, xb * S, mid_y * S], fill=C(CYAN, 110), width=max(1, int(1.2 * S)))
        dd.ellipse([(xb - 2.4) * S, (mid_y - 2.4) * S, (xb + 2.4) * S, (mid_y + 2.4) * S],
                   fill=C((220, 250, 255), 190))

    # underline with a diamond in the gap
    yb = (bot / S) + 13
    dd.line([(x2 / S) + 40, yb, 660, yb], fill=C(PURPLE, 110), width=max(1, int(1.2 * S)))
    dd.line([(740, yb), ((x2 + line2.width) / S) - 40, yb], fill=C(PURPLE, 110), width=max(1, int(1.2 * S)))
    dd.polygon([(700 * S, (yb - 4) * S), (704 * S, yb * S), (700 * S, (yb + 4) * S), (696 * S, yb * S)],
               fill=C((210, 180, 255), 200))

    # sparkles
    for sx, sy, r, col, al in ((150, 108, 10, ICE, 235), (1252, 104, 8, (205, 185, 255), 210),
                               (92, 302, 6, CYAN, 170), (1310, 292, 7, MAGENTA, 160),
                               (612, 372, 4.5, ICE, 150), (788, 370, 4.0, PURPLE, 150)):
        pts = [(sx, sy - r), (sx + r * 0.15, sy - r * 0.15), (sx + r, sy),
               (sx + r * 0.15, sy + r * 0.15), (sx, sy + r), (sx - r * 0.15, sy + r * 0.15),
               (sx - r, sy), (sx - r * 0.15, sy - r * 0.15)]
        dd.polygon([(px * S, py * S) for px, py in pts], fill=C(col, al))

    # ---------------- gradient text fill ----------------
    yy, xx = np.mgrid[0:Hp, 0:Wp].astype(np.float32)
    t = np.clip((yy - top) / max(1.0, (bot - top)), 0, 1)
    stops = [(0.00, (205, 252, 255)), (0.22, (57, 230, 255)), (0.45, (92, 190, 255)),
             (0.68, (122, 120, 250)), (0.86, (139, 92, 246)), (1.00, (206, 96, 230))]
    cols = np.zeros((Hp, Wp, 3), np.float32)
    ts = np.array([p[0] for p in stops], np.float32)
    for k in range(3):
        vs = np.array([p[1][k] for p in stops], np.float32)
        cols[..., k] = np.interp(t, ts, vs).reshape(Hp, Wp)

    # bottom shade for volume
    dark = ImageChops.subtract(mask, shift_mask(mask, -2.6 * S, -2.6 * S))
    shade = 1.0 - 0.42 * (np.asarray(dark, np.float32) / 255.0)[..., None]
    cols = np.clip(cols * shade, 0, 255)

    fill = Image.fromarray(np.clip(cols, 0, 255).astype(np.uint8), "RGB").convert("RGBA")
    fill.putalpha(mask)

    # dark outline ring behind the fill
    outline = ImageChops.subtract(mask.filter(ImageFilter.MaxFilter(19)), mask)
    ol = Image.new("RGBA", (Wp, Hp), C((5, 8, 20), 0))
    ol.putalpha(outline.point(lambda v: min(225, int(v * 0.95))))

    # top-left bevel highlight
    rim = ImageChops.subtract(mask, shift_mask(mask, 2.0 * S, 2.0 * S))
    rim_layer = Image.new("RGBA", (Wp, Hp), C((235, 255, 255), 0))
    rim_layer.putalpha(rim.point(lambda v: int(v * 0.62)))

    art = Image.new("RGBA", (Wp, Hp), (0, 0, 0, 0))
    art = over(art, ol)
    art = over(art, fill)
    art = over(art, rim_layer)

    # ---------------- glow stack ----------------
    glow = neon_glow(mask, [
        (2.0, (215, 252, 255), 0.55),
        (7.0, (80, 226, 255), 0.55),
        (18.0, (66, 150, 255), 0.38),
        (38.0, (132, 86, 236), 0.30),
    ], cap=0.92)
    deco_glow = add_glow(Image.new("RGBA", (Wp, Hp), (0, 0, 0, 0)),
                         glow_layer(deco, 5.0, (100, 215, 255), 0.30))

    out = Image.new("RGBA", (Wp, Hp), (0, 0, 0, 0))
    out = over(out, deco_glow)
    out = over(out, glow)
    out = over(out, deco)
    out = over(out, art)
    return resize_rgba(out, (W, H))


# ==========================================================================
# app icon
# ==========================================================================
def app_icon():
    W = H = 512
    yy, xx = np.mgrid[0:H, 0:W].astype(np.float32)
    nx = (xx - 256) / 256.0
    ny = (yy - 256) / 256.0
    d = np.clip(np.hypot(nx, ny) / math.sqrt(2.0), 0, 1)
    base = (np.array([32, 48, 88], np.float32) * (1 - d[..., None] ** 0.9)
            + np.array([4, 6, 14], np.float32) * (d[..., None] ** 0.9))
    for bx, by, br, col, amp in ((150, 120, 210, (30, 110, 160), 0.60),
                                 (380, 400, 250, (90, 45, 150), 0.60),
                                 (400, 110, 170, (120, 40, 100), 0.30)):
        g = np.exp(-(((xx - bx) ** 2 + (yy - by) ** 2) / (2 * br * br)))[..., None]
        base += np.array(col, np.float32) * g * amp * 0.35
    bg = Image.fromarray(np.clip(base, 0, 255).astype(np.uint8), "RGB").convert("RGBA")

    # sparse stars
    rng = np.random.default_rng(11)
    star = Image.new("RGBA", (W * S, H * S), (0, 0, 0, 0))
    ds = ImageDraw.Draw(star)
    for _ in range(80):
        sx, sy = rng.uniform(10, W - 10), rng.uniform(10, H - 10)
        r = rng.uniform(0.5, 1.3)
        al = int(rng.uniform(40, 150))
        ds.ellipse([(sx - r) * S, (sy - r) * S, (sx + r) * S, (sy + r) * S],
                   fill=C((205, 235, 255), al))
    bg = over(bg, resize_rgba(star, (W, H)))

    A = Art((W, H))
    E = Art((W, H))   # emissive strokes -> glow
    c = (256, 300)

    # gravity well rings (perspective)
    for rw, rh, al, w in ((150, 52, 205, 3.0), (122, 40, 145, 2.4),
                          (96, 30, 88, 2.0), (72, 22, 62, 1.8)):
        box = [(c[0] - rw) * S, (c[1] - rh) * S, (c[0] + rw) * S, (c[1] + rh) * S]
        A.d.arc(box, 0, 360, fill=C(CYAN, al), width=max(1, int(w * S)))
        E.d.arc(box, 0, 360, fill=C(CYAN, al), width=max(1, int(w * S)))

    # black hole core + bright rim
    core = [(c[0] - 54) * S, (c[1] - 19) * S, (c[0] + 54) * S, (c[1] + 19) * S]
    A.d.ellipse(core, fill=C((2, 5, 12), 255))
    A.d.arc(core, 182, 358, fill=C((170, 245, 255), 225), width=int(2.2 * S))
    E.d.arc(core, 182, 358, fill=C((170, 245, 255), 225), width=int(2.2 * S))
    A.circle((c[0], c[1] - 3), 6, C((120, 235, 255), 60), width=1.2)

    # orbiting matter dot
    A.dot((146, 286), 4.0, C((170, 255, 220), 230))
    E.dot((146, 286), 4.0, C(MINT, 230))

    # escape ship heading up-right, nose +X then rotated
    nose_deg = -40.0
    ship_local = [(50, 0), (20, -17), (-10, -19), (-28, -11), (-20, 0), (-28, 11), (-10, 19), (20, 17)]
    ship = [(x + 382, y + 146) for x, y in rot_pts(ship_local, 0, 0, nose_deg)]
    rear = rot_pts([(-28, 0)], 0, 0, nose_deg)[0]
    rear = (rear[0] + 382, rear[1] + 146)
    ang = math.radians(nose_deg + 180)
    trail = []
    for i in range(26):
        t = i / 25.0
        p = (rear[0] + math.cos(ang) * (8 + 44 * t), rear[1] + math.sin(ang) * (8 + 44 * t))
        trail.append((p, 6.5 * (1 - t) + 1.2, 130 * (1 - t) ** 1.6))
    for p, rr, aa in trail:
        A.dot(p, rr, C((255, 170, 90), aa))
    A.poly(ship, C((230, 255, 255), 255), 4.4, fill=C((16, 52, 70), 248))
    cockpit = [(x + 382, y + 146) for x, y in rot_pts([(8, -5), (20, 0), (8, 5)], 0, 0, nose_deg)]
    A.poly(cockpit, C((220, 200, 255), 235), 0, fill=C(PURPLE, 245))
    A.dot(rear, 4.0, C((255, 220, 160), 255))
    E.poly(ship, C((225, 255, 255), 255), 4.4, fill=None, close=True)
    E.dot(rear, 4.0, C((255, 210, 140), 255))

    # speed dashes behind the ship
    A.line([(300, 208), (330, 193)], C((140, 235, 255), 120), 2.2)
    A.line([(286, 232), (311, 219)], C((140, 235, 255), 90), 1.8)

    out = bg.resize((W * S, H * S), Image.LANCZOS)
    out = add_glow(out, glow_layer(E.img, 6.0, (95, 228, 255), 0.55))
    out = add_glow(out, glow_layer(E.img, 20.0, (105, 110, 240), 0.38))
    out = over(out, A.img)
    return resize_rgba(out, (W, H)).convert("RGB").convert("RGBA")


# ==========================================================================
# registry / generation
# ==========================================================================
def build_all():
    os.makedirs(UI_DIR, exist_ok=True)
    os.makedirs(DOCS_DIR, exist_ok=True)
    out = {}

    def put(name, img):
        img.save(os.path.join(UI_DIR, name), "PNG")
        out[name] = img

    put("panel_9p.png", panel_9p(CYAN, CYAN))
    put("panel_alt_9p.png", panel_9p(PURPLE, MAGENTA, alt=True))
    put("card_9p.png", card_9p())
    put("button_9p.png", button_9p("normal"))
    put("button_hover_9p.png", button_9p("hover"))
    put("button_pressed_9p.png", button_9p("pressed"))
    put("button_disabled_9p.png", button_9p("disabled"))
    put("bar_bg_9p.png", bar_bg_9p())
    for n in ("shield", "exp", "fuel", "boost", "hp"):
        put("bar_fill_%s.png" % n, bar_fill(n))
    put("radar_plate.png", radar_plate())
    put("radar_sweep.png", radar_sweep())
    put("radar_player.png", radar_player())
    put("radar_zone.png", radar_zone())
    put("radar_shop.png", radar_shop())
    put("radar_enemy.png", radar_enemy())
    put("radar_threat.png", radar_threat())
    put("threat_arc.png", threat_arc())
    put("joystick_base.png", joystick_base())
    put("joystick_knob.png", joystick_knob())
    put("btn_boost.png", btn_boost(False))
    put("btn_boost_down.png", btn_boost(True))
    put("btn_skill.png", btn_skill())
    put("btn_item.png", btn_item())
    for name, (fn, col) in icon_drawings().items():
        put(name + ".png", make_icon(name, 128, fn, col))
    put("icon_token.png", make_icon("icon_token", 96, ic_token, MAGENTA))
    for n in ("icon_shield.png", "icon_exp.png", "icon_fuel.png", "icon_boost.png", "icon_crosshair.png"):
        put(n, icon64(n, 64))
    put("vignette.png", vignette())
    put("letterbox_glow.png", letterbox_glow())
    put("hex_pattern.png", hex_pattern())
    put("title_logo.png", title_logo())
    put("app_icon.png", app_icon())
    put("prompt_key.png", prompt_key_9p())
    put("divider.png", divider())
    put("cd_dark.png", cd_dark())
    return out


MANIFEST_UI = [
    ("panel_9p.png", (96, 96)), ("panel_alt_9p.png", (96, 96)), ("card_9p.png", (96, 96)),
    ("button_9p.png", (96, 96)), ("button_hover_9p.png", (96, 96)),
    ("button_pressed_9p.png", (96, 96)), ("button_disabled_9p.png", (96, 96)),
    ("bar_bg_9p.png", (48, 24)),
    ("bar_fill_shield.png", (64, 16)), ("bar_fill_exp.png", (64, 16)),
    ("bar_fill_fuel.png", (64, 16)), ("bar_fill_boost.png", (64, 16)),
    ("bar_fill_hp.png", (64, 16)),
    ("radar_plate.png", (320, 320)), ("radar_sweep.png", (320, 320)),
    ("radar_player.png", (28, 28)), ("radar_zone.png", (24, 24)),
    ("radar_shop.png", (24, 24)), ("radar_enemy.png", (28, 28)),
    ("radar_threat.png", (18, 18)), ("threat_arc.png", (512, 512)),
    ("joystick_base.png", (256, 256)), ("joystick_knob.png", (160, 160)),
    ("btn_boost.png", (192, 192)), ("btn_boost_down.png", (192, 192)),
    ("btn_skill.png", (160, 160)), ("btn_item.png", (160, 160)),
    ("icon_skill_pulse.png", (128, 128)), ("icon_skill_gravity.png", (128, 128)),
    ("icon_skill_dash.png", (128, 128)), ("icon_skill_decoy.png", (128, 128)),
    ("icon_item_fuel.png", (128, 128)), ("icon_item_flare.png", (128, 128)),
    ("icon_item_decoy.png", (128, 128)), ("icon_item_charge.png", (128, 128)),
    ("icon_item_mine.png", (128, 128)), ("icon_service.png", (128, 128)),
    ("icon_mod_gravity.png", (128, 128)), ("icon_mod_deceive.png", (128, 128)),
    ("icon_mod_billiard.png", (128, 128)), ("icon_mod_trap.png", (128, 128)),
    ("icon_awaken.png", (128, 128)),
    ("icon_token.png", (96, 96)),
    ("icon_shield.png", (64, 64)), ("icon_exp.png", (64, 64)),
    ("icon_fuel.png", (64, 64)), ("icon_boost.png", (64, 64)),
    ("icon_crosshair.png", (64, 64)),
    ("vignette.png", (1280, 720)), ("letterbox_glow.png", (2048, 256)),
    ("hex_pattern.png", (256, 256)), ("title_logo.png", (1400, 400)),
    ("app_icon.png", (512, 512)), ("prompt_key.png", (96, 96)),
    ("divider.png", (512, 8)), ("cd_dark.png", (256, 256)),
]

NINE_PATCH = {
    "panel_9p.png": 24, "panel_alt_9p.png": 24, "card_9p.png": 24,
    "button_9p.png": 24, "button_hover_9p.png": 24, "button_pressed_9p.png": 24,
    "button_disabled_9p.png": 24, "bar_bg_9p.png": 8, "prompt_key.png": 24,
}

OPAQUE_ALLOWED = {"app_icon.png"}  # full opaque background on purpose
FULL_ALPHA_ALLOWED = {"app_icon.png"}


def audit(folder=UI_DIR, verbose=True):
    ok = True
    rows = []
    for name, size in MANIFEST_UI:
        path = os.path.join(folder, name)
        if not os.path.isfile(path):
            print("MISSING %s" % name)
            ok = False
            continue
        im = Image.open(path)
        issues = []
        if im.size != size:
            issues.append("size %s != %s" % (im.size, size))
        if im.mode != "RGBA":
            issues.append("mode %s" % im.mode)
        arr = np.asarray(im.convert("RGBA"), np.uint8)
        if name in NINE_PATCH:
            b = NINE_PATCH[name]
            cx0, cy0, cx1, cy1 = b, b, size[0] - b, size[1] - b
            inner = arr[cy0:cy1, cx0:cx1].astype(np.int16)
            spread = int(max(np.ptp(inner[..., 3]), np.ptp(inner[..., 0]),
                             np.ptp(inner[..., 1]), np.ptp(inner[..., 2])))
            if spread > 2:
                issues.append("9-slice centre not flat (spread=%d)" % spread)
            if arr[0, 0, 3] > 6:
                issues.append("9-slice corner not transparent (a=%d)" % arr[0, 0, 3])
        if name not in FULL_ALPHA_ALLOWED:
            # transparent assets must not carry an unexpected white/opaque bg
            corners = [arr[0, 0], arr[0, -1], arr[-1, 0], arr[-1, -1]]
            if name not in ("vignette.png", "cd_dark.png"):
                if max(c[3] for c in corners) > 8:
                    issues.append("corner alpha not transparent")
        if name == "threat_arc.png":
            cx = cy = size[0] // 2
            rr = 225
            hits = []
            for deg in range(-180, 180, 2):
                a = math.radians(deg)
                x = int(cx + rr * math.cos(a))
                y = int(cy + rr * math.sin(a))
                hits.append((deg, int(arr[y, x, 3])))
            on = [d for d, al in hits if al > 120]
            off = [d for d, al in hits if al < 20]
            if not on or min(on) < -137 or max(on) > -43:
                issues.append("arc angle extent %s..%s" % (min(on or [0]), max(on or [0])))
            if any(-40 <= d <= 40 and al > 30 for d, al in hits):
                issues.append("arc leaks into lower half")
        if issues:
            ok = False
            rows.append((name, "FAIL: " + "; ".join(issues)))
        else:
            rows.append((name, "ok  %dx%d RGBA" % size))
        if verbose:
            print("%-28s %-10s %s" % (name, "%dx%d" % im.size, rows[-1][1]))
    if verbose:
        total = len(MANIFEST_UI)
        good = sum(1 for _, msg in rows if msg.startswith("ok"))
        print("\naudit: %d/%d ok" % (good, total))
    return ok


# --------------------------------------------------------------------------
# contact sheet
# --------------------------------------------------------------------------
def contact_sheet(out_path=PREVIEW):
    cols = 6
    cell_w, cell_h = 246, 196
    pad = 10
    header = 64
    rows = (len(MANIFEST_UI) + cols - 1) // cols
    W = cols * cell_w + pad * 2
    H = header + rows * cell_h + pad
    sheet = Image.new("RGB", (W, H), (13, 16, 22))
    d = ImageDraw.Draw(sheet)
    font = ImageFont.truetype(FONT_REG, 11)
    font_b = ImageFont.truetype(FONT_BOLD, 19)
    font_s = ImageFont.truetype(FONT_REG, 11)
    d.text((pad + 4, 16), "ESCAPE GRAVITY  /  UI assets", font=font_b, fill=(190, 245, 255))
    d.text((pad + 4, 42), "49 files  ·  assets/ui/  ·  RGBA  ·  4x supersampled",
           font=font_s, fill=(110, 150, 170))

    for i, (name, size) in enumerate(MANIFEST_UI):
        r, c = divmod(i, cols)
        x0 = pad + c * cell_w
        y0 = header + r * cell_h
        # checker board
        for yy in range(y0, y0 + cell_h - 18, 8):
            for xx in range(x0 + 2, x0 + cell_w - 2, 8):
                shade = (26, 30, 38) if ((xx // 8 + yy // 8) % 2 == 0) else (20, 23, 29)
                d.rectangle([xx, yy, xx + 7, yy + 7], fill=shade)
        path = os.path.join(UI_DIR, name)
        if not os.path.isfile(path):
            d.text((x0 + 8, y0 + 60), "MISSING", font=font, fill=(255, 90, 90))
            continue
        im = Image.open(path).convert("RGBA")
        max_w, max_h = cell_w - 26, cell_h - 44
        sc = min(max_w / im.width, max_h / im.height, 2.6)
        tw, th = max(1, int(im.width * sc)), max(1, int(im.height * sc))
        thumb = im.resize((tw, th), Image.LANCZOS)
        sheet.paste(thumb, (x0 + (cell_w - tw) // 2, y0 + (cell_h - 18 - th) // 2), thumb)
        label = name
        tw_label = d.textlength(label, font=font)
        d.text((x0 + (cell_w - tw_label) // 2, y0 + cell_h - 16), label,
               font=font, fill=(150, 175, 195))

    sheet.save(out_path, "PNG")
    return out_path


def main():
    imgs = build_all()
    print("generated %d files in %s\n" % (len(imgs), UI_DIR))
    ok = audit()
    prev = contact_sheet()
    print("contact sheet: %s" % prev)
    if not ok:
        sys.exit(1)


if __name__ == "__main__":
    main()
