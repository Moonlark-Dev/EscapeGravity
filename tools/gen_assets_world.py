#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""Escape Gravity - world layer asset generator.

Draws every PNG listed in docs/ASSET_MANIFEST.md section A into assets/world/.

Pipeline
--------
* All geometry is analytic (signed distance fields / radial fields) evaluated with
  numpy on a 4x supersampled grid, then downsampled with LANCZOS.
* Glow is a separate alpha layer -> gaussian blur -> tinted additive composite.
* No external assets, no network, PIL + numpy only.

Run:  python3 tools/gen_assets_world.py [name ...]
      (no args = build everything and write the verification report)
"""
from __future__ import annotations

import math
import os
import sys
import time

import numpy as np
from PIL import Image, ImageChops, ImageDraw, ImageFilter, ImageFont

SS = 4  # supersampling factor
ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT = os.path.join(ROOT, "assets", "world")

TAU = math.pi * 2.0


# --------------------------------------------------------------------------
# palette
# --------------------------------------------------------------------------
def C(h):
    h = h.lstrip("#")
    return np.array([int(h[i:i + 2], 16) for i in (0, 2, 4)], np.float32)


BG = C("05070F")
CYAN = C("39E6FF")
CYAN_D = C("0E5E77")
PURPLE = C("8B5CF6")
PURPLE_D = C("3B2470")
MAGENTA = C("FF3D81")
MAGENTA_D = C("6E1236")
AMBER = C("FFB347")
AMBER_D = C("7A4512")
MINT = C("5CF2A8")
MINT_D = C("12604A")
WHITE = C("FFFFFF")
ICE = C("D8FBFF")
DEEP = C("0B1220")
METAL = C("121A26")
METAL_D = C("080C13")
METAL_L = C("25303F")


# --------------------------------------------------------------------------
# small math helpers
# --------------------------------------------------------------------------
def clamp01(a):
    return np.clip(a, 0.0, 1.0)


def sstep(e0, e1, x):
    t = clamp01((x - e0) / (e1 - e0))
    return t * t * (3.0 - 2.0 * t)


def aa(d, width=1.0 / SS):
    """Coverage from a signed distance (negative = inside)."""
    return clamp01(0.5 - d / width)


def aa_soft(d, soft=0.0):
    """Coverage with a soft (world unit) falloff."""
    if soft <= 0:
        return aa(d)
    return clamp01(0.5 - d / soft)


def mix(a, b, t):
    a = np.asarray(a, np.float32)
    b = np.asarray(b, np.float32)
    t = t[..., None] if np.ndim(t) else t
    return a * (1.0 - t) + b * t


def norm3(v):
    n = math.sqrt(sum(c * c for c in v))
    return tuple(c / n for c in v)


# --------------------------------------------------------------------------
# signed distance fields (all coordinates in final-canvas units)
# --------------------------------------------------------------------------
def sd_circle(xx, yy, cx, cy, r):
    return np.hypot(xx - cx, yy - cy) - r


def sd_ring(xx, yy, cx, cy, r, hw):
    return np.abs(np.hypot(xx - cx, yy - cy) - r) - hw


def sd_seg(xx, yy, ax, ay, bx, by, r=0.0):
    px = xx - ax
    py = yy - ay
    ex = bx - ax
    ey = by - ay
    t = clamp01((px * ex + py * ey) / (ex * ex + ey * ey + 1e-9))
    dx = px - ex * t
    dy = py - ey * t
    return np.hypot(dx, dy) - r


def sd_box(xx, yy, cx, cy, hw, hh, r=0.0):
    qx = np.abs(xx - cx) - (hw - r)
    qy = np.abs(yy - cy) - (hh - r)
    return (np.hypot(np.maximum(qx, 0.0), np.maximum(qy, 0.0))
            + np.minimum(np.maximum(qx, qy), 0.0) - r)


def sd_poly(xx, yy, verts):
    """Exact polygon SDF (iq). verts: sequence of (x, y)."""
    v = np.asarray(verts, np.float32)
    n = len(v)
    px = xx
    py = yy
    d = (px - v[0, 0]) ** 2 + (py - v[0, 1]) ** 2
    s = np.ones_like(px, dtype=np.float32)
    j = n - 1
    for i in range(n):
        ex = v[j, 0] - v[i, 0]
        ey = v[j, 1] - v[i, 1]
        wx = px - v[i, 0]
        wy = py - v[i, 1]
        t = clamp01((wx * ex + wy * ey) / (ex * ex + ey * ey + 1e-9))
        bx = wx - ex * t
        by = wy - ey * t
        d = np.minimum(d, bx * bx + by * by)
        c1 = py >= v[i, 1]
        c2 = py < v[j, 1]
        c3 = ex * wy > ey * wx
        cond = (c1 & c2 & c3) | (~c1 & ~c2 & ~c3)
        s = np.where(cond, -s, s)
        j = i
    return s * np.sqrt(np.maximum(d, 0.0))


def sd_hex(xx, yy, cx, cy, r, rot=0.0):
    """Pointy-top hexagon, r = circumradius."""
    dx = xx - cx
    dy = yy - cy
    if rot:
        ca, sa = math.cos(rot), math.sin(rot)
        dx, dy = dx * ca + dy * sa, -dx * sa + dy * ca
    dx = np.abs(dx)
    dy = np.abs(dy)
    return np.maximum(dx * 0.8660254 + dy * 0.5, dy) - r * 0.8660254


def sd_diamond(xx, yy, cx, cy, r):
    dx = np.abs(xx - cx)
    dy = np.abs(yy - cy)
    return (dx + dy - r) * 0.70710678


def polar(xx, yy, cx, cy):
    dx = xx - cx
    dy = yy - cy
    return np.hypot(dx, dy), np.arctan2(dy, dx)


def ang_dist(a, b):
    d = np.abs((a - b + math.pi) % TAU - math.pi)
    return d


def sector_mask(ang, center, half, edge=0.01):
    """Angular band with soft edges (radians)."""
    d = ang_dist(ang, center)
    return clamp01((half - d) / edge)


# --------------------------------------------------------------------------
# noise
# --------------------------------------------------------------------------
def _hash2(ix, iy, seed):
    x = (ix.astype(np.int64) & 0x7FFFFFFF).astype(np.uint64)
    y = (iy.astype(np.int64) & 0x7FFFFFFF).astype(np.uint64)
    h = x * np.uint64(0x9E3779B1) ^ y * np.uint64(0x85EBCA77) ^ np.uint64(seed * 0x2545F491 + 1)
    h ^= h >> np.uint64(15)
    h *= np.uint64(0x2545F491)
    h ^= h >> np.uint64(13)
    return (h >> np.uint64(40)).astype(np.float32) / np.float32(16777216.0)


def vnoise(x, y, freq, seed=0, period=None):
    """Smooth value noise. If period is given the lattice wraps (tileable)."""
    xs = x * freq
    ys = y * freq
    ix = np.floor(xs)
    iy = np.floor(ys)
    fx = xs - ix
    fy = ys - iy
    fx = fx * fx * (3.0 - 2.0 * fx)
    fy = fy * fy * (3.0 - 2.0 * fy)
    ix = ix.astype(np.int64)
    iy = iy.astype(np.int64)
    if period:
        p = int(period)
        ix0 = ix % p
        iy0 = iy % p
        ix1 = (ix + 1) % p
        iy1 = (iy + 1) % p
    else:
        ix0, ix1 = ix, ix + 1
        iy0, iy1 = iy, iy + 1
    n00 = _hash2(ix0, iy0, seed)
    n10 = _hash2(ix1, iy0, seed)
    n01 = _hash2(ix0, iy1, seed)
    n11 = _hash2(ix1, iy1, seed)
    a = n00 * (1.0 - fx) + n10 * fx
    b = n01 * (1.0 - fx) + n11 * fx
    return a * (1.0 - fy) + b * fy


def fbm(x, y, freq=4.0, octaves=4, seed=0, period=None, gain=0.5, lac=2.0):
    total = 0.0
    amp = 1.0
    norm = 0.0
    f = float(freq)
    p = period
    for i in range(octaves):
        total = total + amp * vnoise(x, y, f, seed + i * 37, p)
        norm += amp
        amp *= gain
        f *= lac
        if p is not None:
            p = int(p * lac)
    return total / norm


def ridged(x, y, freq=4.0, octaves=4, seed=0, period=None):
    total = 0.0
    amp = 1.0
    norm = 0.0
    f = float(freq)
    p = period
    for i in range(octaves):
        n = vnoise(x, y, f, seed + i * 61, p)
        n = 1.0 - np.abs(2.0 * n - 1.0)
        total = total + amp * n * n
        norm += amp
        amp *= 0.5
        f *= 2.0
        if p is not None:
            p = int(p * 2)
    return total / norm


def noise1(t, freq, seed=0, period=1.0):
    """1-D tileable value noise; t in [0,1)."""
    x = (t * freq) % period
    i = np.floor(x)
    f = x - i
    f = f * f * (3.0 - 2.0 * f)
    a = _hash2(i.astype(np.int64), np.zeros_like(i, dtype=np.int64), seed)
    b = _hash2((i + 1).astype(np.int64), np.zeros_like(i, dtype=np.int64), seed)
    return a * (1.0 - f) + b * f


# --------------------------------------------------------------------------
# block painter / renderer
# --------------------------------------------------------------------------
class Block:
    """Per-tile float accumulator; avoids full-canvas float buffers."""

    __slots__ = ("rgb", "a", "_key")

    _counter = 0

    def __init__(self, shape):
        self.rgb = np.zeros(shape + (3,), np.float32)
        self.a = np.zeros(shape, np.float32)
        Block._counter += 1
        self._key = Block._counter

    def over(self, m, color, opacity=1.0):
        a2 = np.clip(m * opacity, 0.0, 1.0)
        col = np.asarray(color, np.float32)
        self.rgb = self.rgb * (1.0 - a2)[..., None] + col * a2[..., None]
        self.a = a2 + self.a * (1.0 - a2)
        return self

    def over_grad(self, m, col_a, col_b, t, opacity=1.0):
        a2 = np.clip(m * opacity, 0.0, 1.0)
        tt = np.clip(t, 0.0, 1.0)[..., None]
        col = np.asarray(col_a, np.float32) * (1.0 - tt) + np.asarray(col_b, np.float32) * tt
        self.rgb = self.rgb * (1.0 - a2)[..., None] + col * a2[..., None]
        self.a = a2 + self.a * (1.0 - a2)
        return self

    def add(self, m, color, intensity=1.0):
        col = np.asarray(color, np.float32) * intensity
        self.rgb = self.rgb + col * np.clip(m, 0.0, 1.0)[..., None]
        self.a = clamp01(self.a + np.clip(m, 0.0, 1.0) * (1.0 - self.a))
        return self

    def mul(self, m, factor):
        """Multiply existing light by factor inside mask m."""
        f = 1.0 + (factor - 1.0) * np.clip(m, 0.0, 1.0)
        self.rgb = self.rgb * f[..., None]
        return self

    def to_array(self):
        sh = self.a.shape
        dy = (np.arange(sh[0], dtype=np.int64) % _dither.shape[0])[:, None]
        dx = (np.arange(sh[1], dtype=np.int64) % _dither.shape[1])[None, :]
        dith = _dither[dy, dx]
        arr = np.empty(sh + (4,), np.uint8)
        # +-0.5 LSB dither: invisible, but removes banding on soft gradients
        arr[..., :3] = np.clip(self.rgb + 0.5 + dith[..., None], 0.0, 255.0).astype(np.uint8)
        al = np.clip(self.a * 255.0 + 0.5 + dith, 0.0, 255.0)
        al[al < 2.0] = 0.0
        arr[..., 3] = al.astype(np.uint8)
        return arr


_drng = np.random.default_rng(20261101)
_dither = (_drng.random((97, 101), dtype=np.float32) - 0.5) * 1.1


def render(w, h, fn, ss=SS, block=64):
    """Evaluate fn(XX, YY) -> uint8 array on a w*ss x h*ss grid, tile by tile."""
    W, H = int(round(w * ss)), int(round(h * ss))
    out = np.zeros((H, W, 4), np.uint8)
    xs = (np.arange(W, dtype=np.float32) + 0.5) / ss
    for y0 in range(0, H, block):
        y1 = min(y0 + block, H)
        ys = (np.arange(y0, y1, dtype=np.float32) + 0.5) / ss
        XX = np.broadcast_to(xs[None, :], (y1 - y0, W))
        YY = np.broadcast_to(ys[:, None], (y1 - y0, W))
        out[y0:y1] = fn(XX, YY)
    return Image.fromarray(out, "RGBA")


def finish(img, w, h):
    return img.resize((w, h), Image.LANCZOS)


def glow_layer(w, h, fn, radius, color, strength=1.0, ss=None, inner=None):
    """fn(xx,yy) -> alpha 0..1.  Blur it, tint it, return RGBA for additive use.

    inner: optional solid-coverage fn; it is subtracted after blurring so the
    glow only shows as a halo *around* the object instead of washing it out.
    """
    ss = SS if ss is None else ss

    def f(xx, yy):
        a = clamp01(fn(xx, yy))
        arr = np.empty(a.shape + (4,), np.uint8)
        arr[..., 0] = 255
        arr[..., 1] = 255
        arr[..., 2] = 255
        arr[..., 3] = (a * 255.0 + 0.5).astype(np.uint8)
        return arr

    m = render(w, h, f, ss=ss)
    b = m.filter(ImageFilter.GaussianBlur(max(0.01, radius * ss)))
    arr = np.asarray(b, dtype=np.float32)[..., 3]
    if inner is not None:
        def fi(xx, yy):
            a = clamp01(inner(xx, yy))
            arr2 = np.empty(a.shape + (4,), np.uint8)
            arr2[..., 0] = 255
            arr2[..., 1] = 255
            arr2[..., 2] = 255
            arr2[..., 3] = (a * 255.0 + 0.5).astype(np.uint8)
            return arr2
        arr = arr - np.asarray(render(w, h, fi, ss=ss), dtype=np.float32)[..., 3]
    arr = arr * float(strength)
    arr = np.clip(arr, 0.0, 255.0)
    # premultiplied: additive compositing must not add colour where the mask is 0
    k = arr / 255.0
    out = np.empty(arr.shape + (4,), np.uint8)
    out[..., 0] = (color[0] * k + 0.5).astype(np.uint8)
    out[..., 1] = (color[1] * k + 0.5).astype(np.uint8)
    out[..., 2] = (color[2] * k + 0.5).astype(np.uint8)
    out[..., 3] = arr.astype(np.uint8)
    img = Image.fromarray(out, "RGBA")
    if int(round(ss * 1000)) != int(round(SS * 1000)):
        img = img.resize((int(round(w * ss)), int(round(h * ss))), Image.BILINEAR)
    return img


def add(base, layer):
    return ImageChops.add(base, layer)


def over(base, layer):
    return Image.alpha_composite(base, layer)


def blur_rgba(img, radius):
    return img.filter(ImageFilter.GaussianBlur(radius * SS))


def save(img, name, w, h):
    assert img.size == (w, h), (name, img.size)
    img.save(os.path.join(OUT, name), "PNG", optimize=True)
    return name


def make(w, h, fn, glows=(), ss=SS):
    """fn -> uint8 block; glows = iterable of (mask_fn, radius, color, strength)."""
    img = render(w, h, fn, ss=ss)
    for g in glows:
        mfn, rad, col, strength = g[:4]
        inner = g[4] if len(g) > 4 else None
        img = add(img, glow_layer(w, h, mfn, rad, col, strength, ss=ss, inner=inner))
    return img


# --------------------------------------------------------------------------
# reusable sphere shading
# --------------------------------------------------------------------------
def sphere(xx, yy, cx, cy, r):
    """Returns (nx, ny, nz, inside_mask, radial distance in units of r)."""
    dx = (xx - cx) / r
    dy = (yy - cy) / r
    d2 = dx * dx + dy * dy
    nz = np.sqrt(np.clip(1.0 - d2, 0.0, 1.0))
    return dx, dy, nz, (d2 <= 1.0), np.sqrt(d2)


def lambert(nx, ny, nz, L, ambient=0.10, wrap=0.0):
    lx, ly, lz = L
    ndl = nx * lx + ny * ly + nz * lz
    if wrap:
        ndl = (ndl + wrap) / (1.0 + wrap)
    return ambient + (1.0 - ambient) * clamp01(ndl)


def sphere_color(base, shade, tint_shadow=(8, 10, 20)):
    """Multiply a base color by shade and blend toward a cool shadow tint."""
    s = np.clip(shade, 0.0, 2.2)[..., None]
    out = np.asarray(base, np.float32)[None, None, :] * s
    sh = (1.0 - clamp01(shade))[..., None] * 0.55
    return out * (1.0 - sh) + np.asarray(tint_shadow, np.float32) * sh


# ==========================================================================
# light / FX primitives
# ==========================================================================
def build_ship_glow():
    w = h = 160
    cx = cy = 80.0

    def fn(xx, yy):
        b = Block(xx.shape)
        r = np.hypot(xx - cx, yy - cy)
        a = 0.92 * np.exp(-(r / 33.0) ** 2.3) + 0.20 * np.exp(-(r / 62.0) ** 1.7)
        a = clamp01(a)
        # hot white core, faint cyan halo
        b.over(a, WHITE)
        b.add(clamp01(np.exp(-(r / 26.0) ** 2.0)) * 0.55, ICE)
        b.add(clamp01(np.exp(-(r / 48.0) ** 2.0)) * 0.18, CYAN)
        return b.to_array()

    return save(finish(make(w, h, fn), w, h), "ship_glow.png", w, h)


def build_engine_glow():
    w = h = 96
    cy = 48.0

    def fn(xx, yy):
        b = Block(xx.shape)
        u = clamp01((xx - 26.0) / 62.0)
        hw = 2.5 + 16.0 * u ** 0.5
        v = np.abs(yy - cy) / hw
        edge = np.exp(-(v * 1.45) ** 2.3)
        along = np.exp(-(u * 1.85) ** 1.5) * sstep(1.0, 0.66, u)
        plume = edge * along * 1.45
        core = np.exp(-(((xx - 33.0) / 10.0) ** 2 + ((yy - cy) / 8.5) ** 2))
        fade = sstep(25.0, 31.5, xx)
        a = clamp01(core * 1.15 + plume) * fade
        b.over(a, WHITE)
        b.over(a * 0.55, ICE, 0.9)
        b.add(clamp01(plume * 0.75 + core * 1.1) * fade, WHITE, 0.9)
        b.add(clamp01(plume * 0.35) * fade, CYAN, 0.45)
        return b.to_array()

    return save(finish(make(w, h, fn), w, h), "engine_glow.png", w, h)


def build_matter_small():
    w = h = 32
    cx = cy = 16.0

    def fn(xx, yy):
        b = Block(xx.shape)
        r = np.hypot(xx - cx, yy - cy)
        core = np.exp(-(r / 3.6) ** 2.0)
        halo = np.exp(-(r / 8.2) ** 1.8)
        a = clamp01(core * 1.0 + halo * 0.42)
        b.over(a, WHITE)
        b.add(clamp01(halo * 0.55), CYAN, 0.75)
        b.add(clamp01(core * 0.9), WHITE, 1.0)
        return b.to_array()

    return save(finish(make(w, h, fn), w, h), "matter_small.png", w, h)


def build_matter_big():
    w = h = 64
    cx = cy = 32.0

    def fn(xx, yy):
        b = Block(xx.shape)
        dx = xx - cx
        dy = yy - cy
        r = np.hypot(dx, dy)
        core = np.exp(-(r / 6.5) ** 2.0)
        halo = np.exp(-(r / 15.0) ** 1.8)
        hx = np.exp(-(np.abs(dy) / 1.35) ** 1.7) * np.exp(-(np.abs(dx) / 27.0) ** 2.2)
        hy = np.exp(-(np.abs(dx) / 1.35) ** 1.7) * np.exp(-(np.abs(dy) / 27.0) ** 2.2)
        dg = (hx + hy) * 0.62
        a = clamp01(core + halo * 0.40 + dg * 0.75)
        b.over(a, WHITE)
        b.add(clamp01(halo * 0.5 + dg * 0.6), CYAN, 0.7)
        b.add(clamp01(core * 1.0), WHITE, 1.0)
        return b.to_array()

    return save(finish(make(w, h, fn), w, h), "matter_big.png", w, h)


def build_spark():
    w = h = 32
    cx = cy = 16.0

    def fn(xx, yy):
        b = Block(xx.shape)
        r = np.hypot(xx - cx, yy - cy)
        a = clamp01(0.95 * np.exp(-(r / 5.0) ** 2.0) + 0.22 * np.exp(-(r / 12.0) ** 1.6))
        b.over(a, WHITE)
        b.add(clamp01(np.exp(-(r / 4.0) ** 2.0)) * 0.8, WHITE, 0.9)
        return b.to_array()

    return save(finish(make(w, h, fn), w, h), "spark.png", w, h)


def build_smoke():
    w = h = 128
    cx = cy = 64.0

    def fn(xx, yy):
        b = Block(xx.shape)
        nx = (xx - cx) / 64.0
        ny = (yy - cy) / 64.0
        r = np.hypot(nx, ny)
        n = fbm(nx * 0.5 + 3.2, ny * 0.5 + 1.7, 3.0, 4, seed=91)
        blobs = np.zeros_like(r)
        for (ox, oy, rr, amp) in ((0.0, 0.0, 0.42, 1.0),
                                  (0.22, -0.16, 0.30, 0.72),
                                  (-0.20, 0.18, 0.34, 0.62),
                                  (0.05, 0.24, 0.26, 0.5)):
            d = np.hypot(nx - ox, ny - oy) / rr
            blobs = np.maximum(blobs, np.exp(-(d ** 2.2)) * amp)
        a = blobs * (0.55 + 0.75 * n) * sstep(1.02, 0.30, r)
        a = clamp01(a * 1.15)
        b.over(a, WHITE)
        b.add(a * 0.35, ICE, 0.5)
        return b.to_array()

    return save(finish(make(w, h, fn), w, h), "smoke.png", w, h)


def build_shockwave():
    w = h = 512
    cx = cy = 256.0
    R = 200.0

    def fn(xx, yy):
        b = Block(xx.shape)
        r = np.hypot(xx - cx, yy - cy)
        ang = np.arctan2(yy - cy, xx - cx)
        fine = 0.82 + 0.36 * noise1((ang / TAU) % 1.0, 24.0, seed=13)
        core = np.exp(-((r - R) / 2.4) ** 2.0)
        halo = np.exp(-((r - R) / 17.0) ** 2.0) * 0.55
        inner = np.exp(-((r - R * 0.72) / 9.0) ** 2.0) * 0.10
        a = clamp01((core + halo) * fine + inner)
        b.over(a, WHITE)
        b.add(core * 0.9, WHITE, 1.0)
        return b.to_array()

    return save(finish(make(w, h, fn), w, h), "shockwave.png", w, h)


def build_gravity_ring():
    w = h = 512
    cx = cy = 256.0

    def fn(xx, yy):
        b = Block(xx.shape)
        r = np.hypot(xx - cx, yy - cy)
        ang = np.arctan2(yy - cy, xx - cx)
        b.over(np.zeros_like(r), WHITE, 0.0)
        for (rad, hw, ndash, alpha) in ((250.0, 0.85, 40.0, 0.62),
                                        (206.0, 0.7, 30.0, 0.38),
                                        (158.0, 0.6, 24.0, 0.24),
                                        (112.0, 0.55, 18.0, 0.15)):
            dash = sstep(-0.55, 0.15, np.sin(ang * ndash))
            a = np.exp(-((r - rad) / (hw + 0.6)) ** 2.0) * dash * alpha
            b.add(a, WHITE, 1.0)
        # faint radial ticks on the outer ring
        tick = np.exp(-((r - 262.0) / 3.2) ** 2.0) * sstep(-0.2, 0.35, np.sin(ang * 24.0)) * 0.28
        b.add(tick, WHITE, 1.0)
        return b.to_array()

    return save(finish(make(w, h, fn), w, h), "gravity_ring.png", w, h)


def build_reticle():
    w = h = 128
    cx = cy = 64.0
    red = C("FF3040")
    orange = C("FF9A3C")

    def arcs(xx, yy):
        r = np.hypot(xx - cx, yy - cy)
        ang = np.arctan2(yy - cy, xx - cx)
        m = np.zeros_like(r)
        for k in range(4):
            c = k * math.pi / 2.0
            m = np.maximum(m, sector_mask(ang, c, math.radians(30.0), 0.02))
        ring = np.exp(-((r - 45.0) / 2.6) ** 2.0) * m
        ring2 = np.exp(-((r - 45.0) / 6.5) ** 2.0) * m * 0.30
        return ring + ring2

    def ticks(xx, yy):
        r = np.hypot(xx - cx, yy - cy)
        ang = np.arctan2(yy - cy, xx - cx)
        m = np.zeros_like(r)
        for k in range(4):
            c = k * math.pi / 2.0 + math.pi / 4.0
            m = np.maximum(m, sector_mask(ang, c, math.radians(2.6), 0.02))
        return m * sstep(56.0, 54.0, r) * sstep(48.0, 50.0, r)

    def fn(xx, yy):
        b = Block(xx.shape)
        r = np.hypot(xx - cx, yy - cy)
        t = clamp01((r - 38.0) / 16.0)
        b.over_grad(clamp01(arcs(xx, yy)), red, orange, t)
        b.over_grad(ticks(xx, yy), red, orange, 0.5)
        dot = np.exp(-(r / 2.6) ** 2.0)
        b.over(dot, WHITE)
        b.add(clamp01(np.exp(-(r / 5.0) ** 2.0)) * 0.5, orange, 0.8)
        b.add(clamp01(arcs(xx, yy)) * 0.55, red, 0.55)
        return b.to_array()

    return save(finish(make(w, h, fn), w, h), "reticle.png", w, h)


def _diamond_marker(name, col):
    w = h = 72
    cx = cy = 36.0

    def fn(xx, yy):
        b = Block(xx.shape)
        d = sd_diamond(xx, yy, cx, cy, 26.0)
        fill = aa(d)
        edge = np.exp(-((d - 1.0) / 1.9) ** 2.0)
        b.over(fill, col, 0.14)
        b.over(edge, col, 1.0)
        b.over(np.exp(-((d - 1.0) / 0.6) ** 2.0), WHITE, 0.55)
        b.add(edge * 0.8, col, 0.75)
        dot = aa(sd_circle(xx, yy, cx, cy, 3.0))
        b.over(dot, col, 0.9)
        return b.to_array()

    return save(finish(make(w, h, fn), w, h), name, w, h)


def build_marker_zone():
    return _diamond_marker("marker_zone.png", MINT)


def build_marker_shop():
    return _diamond_marker("marker_shop.png", AMBER)


def build_marker_enemy():
    w = h = 72
    red = C("FF3D5A")
    hot = C("FF8A6A")
    verts = [(36, 8), (62, 58), (36, 46), (10, 58)]

    def fn(xx, yy):
        b = Block(xx.shape)
        d = sd_poly(xx, yy, verts)
        fill = aa(d)
        edge = np.exp(-((d - 1.1) / 2.0) ** 2.0)
        b.over_grad(fill, red, C("7A1024"), clamp01((yy - 8.0) / 50.0))
        b.over(edge, red, 1.0)
        b.over(np.exp(-((d - 1.1) / 0.55) ** 2.0), hot, 0.9)
        b.add(edge * 0.75, red, 0.8)
        return b.to_array()

    return save(finish(make(w, h, fn), w, h), "marker_enemy.png", w, h)


def build_arrow():
    w = h = 64
    verts = [(7, 27), (36, 27), (36, 15), (57, 32), (36, 49), (36, 37), (7, 37)]

    def fn(xx, yy):
        b = Block(xx.shape)
        d = sd_poly(xx, yy, verts)
        fill = aa(d)
        b.over_grad(fill, C("EAF7FF"), WHITE, clamp01((xx - 7.0) / 50.0))
        b.over(np.exp(-((d - 0.55) / 0.9) ** 2.0), WHITE, 0.8)
        return b.to_array()

    return save(finish(make(w, h, fn), w, h), "arrow.png", w, h)


def build_decoy():
    w = h = 64
    cx = cy = 32.0
    orb_r = 11.0
    L = norm3((-0.5, -0.6, 0.62))

    def fn(xx, yy):
        b = Block(xx.shape)
        r = np.hypot(xx - cx, yy - cy)
        ang = np.arctan2(yy - cy, xx - cx)
        # calibration ring + 8 radial ticks
        ring = np.exp(-((r - 22.0) / 0.75) ** 2.0)
        ticks = np.full_like(r, 1e9)
        for k in range(8):
            a = k * TAU / 8.0 + TAU / 16.0
            ca, sa = math.cos(a), math.sin(a)
            ticks = np.minimum(ticks, sd_seg(xx, yy, cx + ca * 23.6, cy + sa * 23.6,
                                             cx + ca * 25.8, cy + sa * 25.8, 0.45))
        tickm = np.exp(-(ticks / 0.62) ** 2.0)
        b.over(clamp01(ring * 0.8 + tickm * 0.9), MAGENTA, 0.9)
        b.over(clamp01(ring) * 0.35, C("FFB06A"), 0.5)
        # orb with smooth volume
        dx = (xx - cx) / orb_r
        dy = (yy - cy) / orb_r
        d2 = dx * dx + dy * dy
        nz = np.sqrt(np.clip(1.0 - d2, 0.0, 1.0))
        lam = clamp01(dx * L[0] + dy * L[1] + nz * L[2])
        shade = 0.18 + 0.95 * lam
        ball = aa(sd_circle(xx, yy, cx, cy, orb_r))
        col = mix(C("5A0A2A"), C("FF7A3C"), clamp01(lam * 1.15))
        col = col * shade[..., None]
        b.over(ball, WHITE, 0.0)
        b.over(ball * 0.0, col, 1.0)
        # tinted orb: paint color directly
        a2 = ball
        b.rgb = b.rgb * (1.0 - a2)[..., None] + col * a2[..., None]
        b.a = clamp01(a2 + b.a * (1.0 - a2))
        spec = np.exp(-(((xx - cx + 3.4) / 3.2) ** 2 + ((yy - cy + 3.8) / 2.8) ** 2))
        b.over(spec * ball, WHITE, 0.9)
        b.add(clamp01(ball * 0.45), MAGENTA, 0.35)
        b.add(clamp01(ball * 0.18 + ring * 0.45), MAGENTA, 0.3)
        return b.to_array()

    return save(finish(make(w, h, fn), w, h), "decoy.png", w, h)


def build_missile_warn():
    w = h = 96
    cx = cy = 48.0
    red = C("FF3D5A")
    hot = C("FFB3A0")

    def fn(xx, yy):
        b = Block(xx.shape)
        r = np.hypot(xx - cx, yy - cy)
        ang = np.arctan2(yy - cy, xx - cx)
        seg = sstep(-0.55, 0.05, np.sin(ang * 4.0))
        outer = np.exp(-((r - 40.0) / 1.9) ** 2.0) * seg
        outer2 = np.exp(-((r - 40.0) / 5.0) ** 2.0) * seg * 0.35
        inner = np.exp(-((r - 31.0) / 1.1) ** 2.0) * sstep(-0.2, 0.3, np.sin(ang * 12.0))
        b.over(clamp01(outer + inner * 0.75), red, 0.95)
        b.over(np.exp(-((r - 40.0) / 0.7) ** 2.0) * seg, hot, 0.8)
        b.add(clamp01(outer2 + outer * 0.6), red, 0.55)
        # four inward brackets
        for k in range(4):
            a = k * math.pi / 2.0 + math.pi / 4.0
            ca, sa = math.cos(a), math.sin(a)
            p0 = (cx + ca * 26.0, cy + sa * 26.0)
            p1 = (cx + ca * 34.0, cy + sa * 34.0)
            d = sd_seg(xx, yy, p0[0], p0[1], p1[0], p1[1], 1.15)
            b.over(aa(d), red, 0.9)
            b.add(np.exp(-(d / 2.4) ** 2.0) * 0.5, red, 0.6)
        return b.to_array()

    return save(finish(make(w, h, fn), w, h), "missile_warn.png", w, h)


def build_missile():
    w, h = 64, 28
    cy = 14.0
    body_dark = C("4A1405")
    body = C("FF5A2A")
    hot = C("FFC46A")
    verts = [(11, 7.6), (42, 7.6), (47, 9.4), (61, 14.0), (47, 18.6), (42, 20.4), (11, 20.4), (8, 14.0)]
    fin_t = [(13, 8.0), (23, 2.6), (25.5, 8.0)]
    fin_b = [(13, 20.0), (23, 25.4), (25.5, 20.0)]

    def fn(xx, yy):
        b = Block(xx.shape)
        d = sd_poly(xx, yy, verts)
        body_m = aa(d)
        t = clamp01((yy - 6.6) / 15.0)
        b.over_grad(body_m, body, body_dark, t)
        # fins
        b.over(aa(sd_poly(xx, yy, fin_t)), C("E8481F"), 0.95)
        b.over(aa(sd_poly(xx, yy, fin_b)), C("B03012"), 0.95)
        # nose cone warming to amber
        nt = clamp01((xx - 44.0) / 17.0)
        nose = aa(d) * clamp01(sd_seg(xx, yy, 46.0, cy, 61.0, cy, 6.2) < 0)
        b.over(nose, hot, 0.55 * nt)
        # top highlight + belly shadow
        b.over(aa(sd_seg(xx, yy, 13.0, 9.2, 44.0, 9.2, 1.0)), C("FFD9AE"), 0.75)
        b.over(aa(sd_seg(xx, yy, 12.0, 19.4, 44.0, 19.4, 1.2)), C("2A0A02"), 0.55)
        b.over(aa(sd_seg(xx, yy, 36.0, 8.0, 36.0, 20.0, 0.5)), C("5A1A06"), 0.5)
        b.over(aa(sd_seg(xx, yy, 30.0, 8.0, 30.0, 20.0, 0.5)), C("5A1A06"), 0.35)
        # nozzle + tail flame
        b.over(aa(sd_box(xx, yy, 9.6, cy, 1.6, 4.4, 0.7)), C("1E0700"), 0.85)
        fl = np.exp(-(((xx - 5.6) / 2.6) ** 2 + ((yy - cy) / 2.2) ** 2))
        b.add(clamp01(fl * 1.5), hot, 1.0)
        b.over(clamp01(fl * 1.25), C("FFF0C8"), 0.55)
        b.add(clamp01(body_m * 0.30), body, 0.55)
        return b.to_array()

    return save(finish(make(w, h, fn), w, h), "missile.png", w, h)


def build_drone():
    w = h = 64
    cx = cy = 32.0
    # Small violet interceptor drone, nose pointing +X.  The wide swept prongs
    # and magenta wings keep the silhouette distinct from the orange missile.
    body = [(56, 32), (44, 25), (32, 23), (22, 27), (16, 32), (22, 37), (32, 41), (44, 39)]
    wing_t = [(36, 24), (17, 11), (27, 27)]
    wing_b = [(36, 40), (17, 53), (27, 37)]

    def shape(xx, yy):
        m = aa(sd_poly(xx, yy, body))
        m = np.maximum(m, aa(sd_poly(xx, yy, wing_t)))
        m = np.maximum(m, aa(sd_poly(xx, yy, wing_b)))
        return m

    def fn(xx, yy):
        b = Block(xx.shape)
        b.over(aa(sd_poly(xx, yy, wing_t)), C("FF3D81"), 0.95)
        b.over(aa(sd_poly(xx, yy, wing_b)), C("B01E58"), 0.95)
        b.over(aa(sd_poly(xx, yy, body)), C("2A0C4A"))
        hull = aa(sd_poly(xx, yy, body))
        t = clamp01((yy - 20.0) / 24.0)
        b.over_grad(hull, C("C08BFF"), C("3D1A6E"), t)
        # bright spine + panel seams
        b.over(aa(sd_seg(xx, yy, 19.0, cy, 51.0, cy, 1.8)), C("F0E4FF"), 0.6)
        b.over(aa(sd_seg(xx, yy, 25.0, 27.0, 39.0, 27.0, 0.5)), C("FF7AB8"), 0.35)
        b.over(aa(sd_seg(xx, yy, 25.0, 37.0, 39.0, 37.0, 0.5)), C("FF7AB8"), 0.35)
        # wing edge highlights
        b.over(aa(sd_seg(xx, yy, 18.0, 13.0, 35.0, 25.0, 1.0)), C("FF9AC8"), 0.85)
        b.over(aa(sd_seg(xx, yy, 18.0, 51.0, 35.0, 39.0, 1.0)), C("FF5A9E"), 0.75)
        # sensor eye: magenta ring + white-hot core
        eye = sd_circle(xx, yy, 44.0, cy, 5.4)
        b.over(aa(eye), C("2A0520"))
        b.over(aa(eye - 1.8), MAGENTA)
        b.over(np.exp(-((eye + 0.4) / 1.3) ** 2.0), C("FFF0F8"), 0.95)
        # single nozzle + short violet tail flame
        b.over(aa(sd_box(xx, yy, 17.0, cy, 2.0, 4.2, 1.0)), C("14041F"))
        fl = np.exp(-(((xx - 11.5) / 2.8) ** 2 + ((yy - cy) / 2.5) ** 2))
        b.add(clamp01(fl * 1.4), MAGENTA, 1.0)
        b.over(clamp01(fl * 1.2), C("FFF0F8"), 0.6)
        b.add(clamp01(shape(xx, yy) * 0.22), PURPLE, 0.5)
        return b.to_array()

    def gmask(xx, yy):
        return shape(xx, yy)

    def solid(xx, yy):
        return shape(xx, yy)

    img = make(w, h, fn, glows=[(gmask, 3.0, PURPLE, 1.0, solid)])
    return save(finish(img, w, h), "drone.png", w, h)


# ==========================================================================
# ship
# ==========================================================================
SHIP_UPPER = [(114, 64), (96, 57.5), (80, 52), (46, 36), (32, 38),
              (29, 47), (44, 54), (54, 60), (46, 64)]
SHIP_HULL = SHIP_UPPER + [(x, 128 - y) for (x, y) in reversed(SHIP_UPPER[1:-1])]

SHIP_FUSE_U = [(114, 64), (98, 58.5), (76, 55.5), (52, 55.5), (34, 57.5), (30, 64)]
SHIP_FUSE = SHIP_FUSE_U + [(x, 128 - y) for (x, y) in reversed(SHIP_FUSE_U[1:-1])]

SHIP_WING_UP = [(88, 57.5), (76, 55.6), (52, 55.6), (34, 57.6), (29, 47),
                (32, 38), (46, 36)]
SHIP_WING_DN = [(x, 128 - y) for (x, y) in SHIP_WING_UP]

SHIP_CANOPY = [(93, 64), (86, 59.2), (76, 58.8), (68, 64), (76, 69.2), (86, 68.8)]


def build_ship():
    w = h = 128
    cyan_hot = C("BFF4FF")

    def hull(xx, yy):
        return sd_poly(xx, yy, SHIP_HULL)

    def fn(xx, yy):
        b = Block(xx.shape)
        d = hull(xx, yy)
        # light from upper-left: upper wing lit, lower wing in shadow
        lit = clamp01(1.0 - (yy - 34.0) / 62.0)

        # ---- wing base plates
        b.over(aa(d), C("0A1B24"))
        b.over_grad(aa(sd_poly(xx, yy, SHIP_WING_UP)), C("2A7288"), C("123542"), 1.0 - lit)
        b.over_grad(aa(sd_poly(xx, yy, SHIP_WING_DN)), C("123542"), C("081720"), 1.0 - lit)
        # inner wing panel seam
        seam_u = sd_seg(xx, yy, 76.0, 55.6, 36.0, 41.0, 0.0)
        seam_d = sd_seg(xx, yy, 76.0, 72.4, 36.0, 87.0, 0.0)
        b.over(np.exp(-(seam_u / 0.85) ** 2.0) * aa(d), C("06141B"), 0.7)
        b.over(np.exp(-(seam_d / 0.85) ** 2.0) * aa(d), C("040F15"), 0.7)
        # wing tip accent
        tip_u = np.exp(-(((xx - 37.0) / 7.0) ** 2 + ((yy - 40.0) / 3.2) ** 2))
        tip_d = np.exp(-(((xx - 37.0) / 7.0) ** 2 + ((yy - 88.0) / 3.2) ** 2))
        b.over(tip_u * aa(d), C("39E6FF"), 0.35)
        b.over(tip_d * aa(d), C("1E6E86"), 0.35)

        # ---- fuselage
        fd = sd_poly(xx, yy, SHIP_FUSE)
        b.over(aa(fd + 1.0), C("05131A"))
        b.over_grad(aa(fd), C("3D8DA6"), C("153846"), 1.0 - lit * 0.9)
        # armour plates on the fuselage
        b.over(aa(sd_poly(xx, yy, [(100, 64), (96, 59.5), (82, 58.6), (76, 64),
                                   (82, 69.4), (96, 68.5)])), C("205F76"), 0.55)
        b.over(aa(sd_poly(xx, yy, [(60, 64), (56, 57.6), (44, 58.0), (40, 64),
                                   (44, 70.0), (56, 70.4)])), C("1A4E60"), 0.55)
        # spine highlight
        spine = np.exp(-((yy - 64.0) / 1.7) ** 2.0) * aa(fd)
        b.over(spine * clamp01((xx - 34.0) / 20.0), C("9FE6F5"), 0.55)
        # nose tip hot
        b.over(aa(sd_circle(xx, yy, 112.0, 64.0, 2.6)), cyan_hot, 0.75)

        # ---- leading edge rim light
        lead = np.minimum(sd_seg(xx, yy, 112.0, 62.5, 96.0, 57.5, 0.0),
                          sd_seg(xx, yy, 96.0, 57.5, 80.0, 52.0, 0.0))
        lead = np.minimum(lead, sd_seg(xx, yy, 80.0, 52.0, 46.0, 36.0, 0.0))
        lead = np.minimum(lead, sd_seg(xx, yy, 112.0, 65.5, 96.0, 70.5, 0.0))
        lead = np.minimum(lead, sd_seg(xx, yy, 96.0, 70.5, 80.0, 76.0, 0.0))
        lead = np.minimum(lead, sd_seg(xx, yy, 80.0, 76.0, 46.0, 92.0, 0.0))
        b.over(np.exp(-(lead / 1.2) ** 2.0) * aa(d), CYAN, 0.95)
        b.over(np.exp(-(lead / 0.42) ** 2.0) * aa(d), WHITE, 0.8)
        # hull outline
        b.over(np.exp(-((np.abs(d) - 0.45) / 0.7) ** 2.0), C("6FE4F8"), 0.6)
        b.over(np.exp(-((np.abs(fd) - 0.45) / 0.6) ** 2.0), C("4EC9E0"), 0.45)

        # ---- engines (two nozzles flanking the tail notch)
        for ey in (58.5, 69.5):
            nd = sd_circle(xx, yy, 38.0, ey, 5.2)
            b.over(aa(nd + 1.0), C("041016"))
            b.over(np.exp(-((nd + 1.6) / 1.1) ** 2.0), C("2E8FA6"), 0.85)
            gl = np.exp(-(((xx - 34.5) / 3.2) ** 2 + ((yy - ey) / 3.4) ** 2))
            b.add(clamp01(gl * 1.25), CYAN, 0.9)
            b.over(clamp01(gl * 1.6), cyan_hot, 0.7)
        # exhaust streaks behind the ship
        for ey in (58.5, 69.5):
            st = np.exp(-(((xx - 27.0) / 7.0) ** 2 + ((yy - ey) / 1.5) ** 2))
            b.add(clamp01(st * 0.9), CYAN, 0.5)

        # ---- cockpit
        cd = sd_poly(xx, yy, SHIP_CANOPY)
        b.over(aa(cd + 1.2), C("150B33"))
        b.over_grad(aa(cd), C("8B5CF6"), C("2E1B62"), clamp01((yy - 58.0) / 12.0))
        b.over_grad(aa(cd - 1.2), C("C3AEFF"), C("5B3FA8"), clamp01((yy - 59.0) / 11.0))
        gl = np.exp(-(((xx - 80.0) / 5.5) ** 2 + ((yy - 61.2) / 2.1) ** 2))
        b.over(clamp01(gl) * aa(cd), WHITE, 0.85)
        b.over(np.exp(-((cd - 0.4) / 0.8) ** 2.0), C("D6C8FF"), 0.5)
        b.add(aa(cd) * 0.18, PURPLE, 0.4)

        # ---- greebles
        for (gx, gy, gw, gh) in ((62, 61.2, 7, 1.1), (62, 66.8, 7, 1.1),
                                 (50, 62.0, 4, 0.9), (50, 66.0, 4, 0.9)):
            b.over(aa(sd_box(xx, yy, gx, gy, gw, gh, 0.4)), C("071A22"), 0.65)
        b.over(aa(sd_seg(xx, yy, 30.0, 64.0, 44.0, 64.0, 0.5)), C("2E8FA6"), 0.5)
        return b.to_array()

    def gmask(xx, yy):
        return aa(hull(xx, yy) + 1.0)

    def solid(xx, yy):
        return aa(hull(xx, yy))

    img = make(w, h, fn, glows=[(gmask, 3.0, CYAN, 1.1, solid),
                                (gmask, 6.5, C("2E7FA0"), 0.8, solid)])
    return save(finish(img, w, h), "ship.png", w, h)


# ==========================================================================
# meteors
# ==========================================================================
def _meteor_shape(seed, n=11, r0=37.0, rough=0.22):
    rng = np.random.default_rng(seed)
    radii = 1.0 - rough * rng.random(n)
    radii = 0.7 * radii + 0.3 * (np.roll(radii, 1) + np.roll(radii, -1)) * 0.5
    pts = []
    for i in range(n):
        a = i * TAU / n + rng.uniform(-0.09, 0.09)
        rr = r0 * radii[i]
        pts.append((48.0 + math.cos(a) * rr, 48.0 + math.sin(a) * rr))
    return pts


METEORS = [(_meteor_shape(11), 21.5), (_meteor_shape(29), 19.0), (_meteor_shape(47), 23.0)]


def _build_meteor(idx, name):
    w = h = 96
    cx = cy = 48.0
    verts, R0 = METEORS[idx]
    L = norm3((-0.58, -0.62, 0.52))
    rng = np.random.default_rng(900 + idx * 31)
    craters = []
    for _ in range(6):
        a = rng.uniform(0, TAU)
        rr = R0 * rng.uniform(0.10, 0.70)
        craters.append((cx + math.cos(a) * rr, cy + math.sin(a) * rr,
                        rng.uniform(4.0, 8.5), rng.uniform(0.5, 1.0)))

    def fn(xx, yy):
        b = Block(xx.shape)
        d = sd_poly(xx, yy, verts)
        inside = aa(d)
        dx = (xx - cx) / R0
        dy = (yy - cy) / R0
        d2 = dx * dx + dy * dy
        nz = np.sqrt(np.clip(1.0 - d2, 0.0, 1.0))
        lam = clamp01(dx * L[0] + dy * L[1] + nz * L[2])
        # subtle faceting: mix smooth lambert with a lightly quantised one
        q = np.floor(lam * 6.0) / 6.0 + 0.0833
        lam_q = 0.72 * lam + 0.28 * q
        tex = fbm((xx - cx) / 96.0 + 0.5, (yy - cy) / 96.0 + 0.5, 6.0, 3, seed=700 + idx)
        patch = fbm((xx - cx) / 96.0 + 0.5, (yy - cy) / 96.0 + 0.5, 2.2, 3, seed=1300 + idx)
        col = mix(C("080D14"), C("4C5D70"), clamp01(lam_q * 1.25))
        col = mix(col, C("8DA2B8"), clamp01((lam_q - 0.68) * 3.2))
        col = col * (0.72 + 0.50 * tex)[..., None] * (0.78 + 0.44 * patch)[..., None]
        b.rgb = b.rgb * (1.0 - inside)[..., None] + col * inside[..., None]
        b.a = clamp01(inside + b.a * (1.0 - inside))
        # craters
        for (ccx, ccy, cr, dep) in craters:
            dc = np.hypot(xx - ccx, yy - ccy) / cr
            bowl = sstep(1.0, 0.80, dc)
            rim = np.exp(-((dc - 0.99) / 0.10) ** 2.0)
            side = clamp01(0.5 + 0.5 * ((xx - ccx) * L[0] + (yy - ccy) * L[1]) / cr)
            b.mul(bowl * inside, 1.0 - 0.40 * dep * (0.45 + 0.55 * (1.0 - side)))
            b.over(rim * inside * side, C("C6D8E8"), 0.42 * dep)
            b.over(rim * inside * (1.0 - side), C("04070C"), 0.34 * dep)
        # cool rim light on the lit limb + faint blue bounce
        band = clamp01(inside - aa(d + 1.4))
        b.over(band * clamp01(lam * 1.5) ** 1.5, C("7FE2F8"), 0.75)
        b.over(clamp01(inside - aa(d + 0.8)) * clamp01(lam * 2.0), C("E2FBFF"), 0.45)
        bounce = clamp01(inside - aa(d + 1.6)) * clamp01((0.45 - lam) * 1.6)
        b.over(bounce, C("2E5A78"), 0.35)
        # dark outline
        b.over(np.exp(-((np.abs(d) - 0.3) / 0.5) ** 2.0), C("050A10"), 0.4)
        return b.to_array()

    def gmask(xx, yy):
        return aa(sd_poly(xx, yy, verts) + 0.5)

    def solid(xx, yy):
        return aa(sd_poly(xx, yy, verts))

    img = make(w, h, fn, glows=[(gmask, 3.5, C("3FA8C8"), 0.95, solid)])
    return save(finish(img, w, h), name, w, h)


def build_meteor_1():
    return _build_meteor(0, "meteor_1.png")


def build_meteor_2():
    return _build_meteor(1, "meteor_2.png")


def build_meteor_3():
    return _build_meteor(2, "meteor_3.png")


# ==========================================================================
# nest (missile-nest enemy)
# ==========================================================================
def build_nest():
    w = h = 256
    cx = cy = 128.0
    petals = []
    for k in range(5):
        a = -math.pi / 2.0 + k * TAU / 5.0
        petals.append((a, math.cos(a), math.sin(a)))

    def fn(xx, yy):
        b = Block(xx.shape)
        union = np.zeros_like(xx)
        edge = np.zeros_like(xx)
        outer = np.zeros_like(xx)
        for (a, ca, sa) in petals:
            px = xx - cx
            py = yy - cy
            u = px * ca + py * sa          # along petal axis
            v = -px * sa + py * ca
            # petal: ellipse centre 58 along axis, half length 44, half width 30
            e = ((u - 56.0) / 44.0) ** 2 + (v / 30.0) ** 2
            m = aa((np.sqrt(e) - 1.0) * 30.0)
            union = np.maximum(union, m)
            outer = np.maximum(outer, np.exp(-((np.sqrt(e) - 1.0) / 0.09) ** 2))
            edge = np.maximum(edge, np.exp(-((np.sqrt(e) - 1.0) / 0.16) ** 2))
        # body
        b.over(union, C("2A0A22"))
        grad = clamp01((yy - 20.0) / 216.0)
        b.over_grad(union * 0.0 + union, C("4A1040"), C("1C0618"), grad)
        b.over_grad(union, C("6E1A56"), C("2A0A22"), clamp01(grad * 1.1))
        # radial ribs
        for (a, ca, sa) in petals:
            rib = sd_seg(xx, yy, cx + ca * 22.0, cy + sa * 22.0,
                         cx + ca * 96.0, cy + sa * 96.0, 1.1)
            b.over(np.exp(-(rib / 1.2) ** 2.0) * union, C("FF8AC0"), 0.35)
        # petal edges
        b.over(edge * union, C("FF3D81"), 0.85)
        b.over(edge * union * 0.6, WHITE, 0.35)
        b.over(outer * union, C("FF8AC0"), 0.55)
        # missile tubes at the petal tips
        for (a, ca, sa) in petals:
            tx = cx + ca * 86.0
            ty = cy + sa * 86.0
            tube = sd_circle(xx, yy, tx, ty, 9.5)
            b.over(aa(tube), C("12030C"))
            b.over(np.exp(-((tube + 1.6) / 1.4) ** 2.0), C("FF3D81"), 0.8)
            b.over(np.exp(-(tube / 4.5) ** 2.0) * aa(tube), C("FF9A5A"), 0.45)
            b.add(np.exp(-(tube / 5.5) ** 2.0) * aa(tube) * 0.7, MAGENTA, 0.5)
        # core
        core = sd_circle(xx, yy, cx, cy, 34.0)
        b.over(aa(core), C("1A0414"))
        b.over(aa(core - 3.0), C("3B0A28"))
        hexm = sd_hex(xx, yy, cx, cy, 30.0, 0.0)
        b.over(np.exp(-((hexm + 0.6) / 1.4) ** 2.0), MAGENTA, 0.85)
        b.over(np.exp(-((hexm + 0.6) / 0.5) ** 2.0), WHITE, 0.5)
        r = np.hypot(xx - cx, yy - cy)
        glow = np.exp(-(r / 17.0) ** 2.0)
        b.add(clamp01(glow * 1.25), MAGENTA, 0.95)
        b.over(clamp01(glow * 1.5), C("FFD9EC"), 0.85)
        b.add(clamp01(np.exp(-(r / 34.0) ** 2.0) * 0.6), MAGENTA, 0.5)
        # outer ring hint
        ring = np.exp(-((r - 108.0) / 1.2) ** 2.0)
        b.add(ring * 0.35, MAGENTA, 0.4)
        return b.to_array()

    def gmask(xx, yy):
        u = np.zeros_like(xx)
        for (a, ca, sa) in petals:
            px = xx - cx
            py = yy - cy
            uu = px * ca + py * sa
            vv = -px * sa + py * ca
            e = ((uu - 56.0) / 44.0) ** 2 + (vv / 30.0) ** 2
            u = np.maximum(u, aa((np.sqrt(e) - 1.0) * 30.0 + 0.5))
        return u

    def solid(xx, yy):
        u = np.zeros_like(xx)
        for (a, ca, sa) in petals:
            px = xx - cx
            py = yy - cy
            uu = px * ca + py * sa
            vv = -px * sa + py * ca
            e = ((uu - 56.0) / 44.0) ** 2 + (vv / 30.0) ** 2
            u = np.maximum(u, aa((np.sqrt(e) - 1.0) * 30.0))
        return u

    img = make(w, h, fn, glows=[(gmask, 5.0, MAGENTA, 1.0, solid),
                                (gmask, 13.0, C("8B1E52"), 0.6, solid)])
    return save(finish(img, w, h), "nest.png", w, h)


# ==========================================================================
# noise textures (evaluated once, then sampled bilinearly per tile)
# ==========================================================================
class Tex:
    def __init__(self, arr, wrap=False):
        self.a = np.ascontiguousarray(arr, dtype=np.float32)
        self.h, self.w = self.a.shape
        self.wrap = wrap

    def at(self, u, v):
        """u, v in [0,1) canvas coordinates."""
        fx = u * self.w - 0.5
        fy = v * self.h - 0.5
        if self.wrap:
            fx = np.mod(fx, self.w)
            fy = np.mod(fy, self.h)
            x0 = np.floor(fx).astype(np.int32)
            y0 = np.floor(fy).astype(np.int32)
            x1 = (x0 + 1) % self.w
            y1 = (y0 + 1) % self.h
            x0 = x0 % self.w
            y0 = y0 % self.h
        else:
            fx = np.clip(fx, 0.0, self.w - 1.001)
            fy = np.clip(fy, 0.0, self.h - 1.001)
            x0 = np.floor(fx).astype(np.int32)
            y0 = np.floor(fy).astype(np.int32)
            x1 = np.minimum(x0 + 1, self.w - 1)
            y1 = np.minimum(y0 + 1, self.h - 1)
        tx = (fx - x0).astype(np.float32)
        ty = (fy - y0).astype(np.float32)
        a = self.a
        top = a[y0, x0] * (1.0 - tx) + a[y0, x1] * tx
        bot = a[y1, x0] * (1.0 - tx) + a[y1, x1] * tx
        return top * (1.0 - ty) + bot * ty


def noise_tex(w, h, freq=3.0, octaves=4, seed=0, wrap=False, ridged_=False, res=None,
              norm=False):
    """Precompute fbm over the whole canvas at (reduced) resolution."""
    rw = res or w
    rh = res or h
    xs = (np.arange(rw, dtype=np.float32) + 0.5) / rw
    ys = (np.arange(rh, dtype=np.float32) + 0.5) / rh
    XX = np.broadcast_to(xs[None, :], (rh, rw))
    YY = np.broadcast_to(ys[:, None], (rh, rw))
    period = freq if wrap else None
    f = ridged if ridged_ else fbm
    arr = f(XX, YY, freq, octaves, seed, period).astype(np.float32)
    if norm:
        lo, hi = np.percentile(arr, 2.0), np.percentile(arr, 98.0)
        arr = np.clip((arr - lo) / max(1e-6, hi - lo), 0.0, 1.0)
    return Tex(arr, wrap=wrap)


def ramp(stops, t):
    ts = np.array([s[0] for s in stops], np.float32)
    cs = np.array([s[1] for s in stops], np.float32)
    t = np.clip(t, ts[0], ts[-1])
    out = np.empty(t.shape + (3,), np.float32)
    for c in range(3):
        out[..., c] = np.interp(t, ts, cs[:, c])
    return out


PLANET_L = norm3((-0.56, -0.50, 0.66))


def _planet_fields(xx, yy, cx, cy, R):
    dx = (xx - cx) / R
    dy = (yy - cy) / R
    d2 = dx * dx + dy * dy
    nz = np.sqrt(np.clip(1.0 - d2, 0.0, 1.0))
    rr = np.sqrt(d2) * R
    return dx, dy, nz, rr, d2


def _crater_list(seed, cx, cy, R, n, rmin, rmax):
    rng = np.random.default_rng(seed)
    out = []
    for _ in range(n):
        a = rng.uniform(0, TAU)
        rr = R * math.sqrt(rng.uniform(0.02, 0.78))
        out.append((cx + math.cos(a) * rr, cy + math.sin(a) * rr,
                    rng.uniform(rmin, rmax), rng.uniform(0.45, 1.0)))
    return out


def build_planet_1():
    w = h = 768
    cx = cy = 384.0
    R = 360.0
    L = PLANET_L
    craters = _crater_list(7, cx, cy, R, 8, 10.0, 26.0)
    tex1 = noise_tex(w, h, 3.0, 4, seed=31, res=384)
    tex2 = noise_tex(w, h, 7.0, 3, seed=57, res=384)
    tex3 = noise_tex(w, h, 14.0, 2, seed=71, res=384)

    def fn(xx, yy):
        b = Block(xx.shape)
        dx, dy, nz, rr, d2 = _planet_fields(xx, yy, cx, cy, R)
        d = rr - R
        inside = aa(d)
        lam = clamp01(dx * L[0] + dy * L[1] + nz * L[2])
        shade = 0.055 + 0.98 * lam ** 0.92
        u = xx / w
        v = yy / h
        n1 = tex1.at(u, v)
        n2 = tex2.at(u, v)
        n3 = tex3.at(u, v)
        band = 0.5 + 0.5 * np.sin(dy * 8.5 + n1 * 3.0)
        albedo = 0.62 + 0.32 * band + 0.30 * (n2 - 0.5) + 0.16 * (n3 - 0.5)
        base = mix(C("8A5A38"), C("C08A5A"), clamp01(albedo * 0.9))
        base = mix(base, C("E2B88C"), clamp01((albedo - 0.70) * 2.2))
        col = base * shade[..., None]
        # craters
        for (ccx, ccy, cr, dep) in craters:
            qx = xx - ccx
            qy = yy - ccy
            dc = np.sqrt(qx * qx + qy * qy) / cr
            bowl = sstep(1.02, 0.80, dc)
            rim = np.exp(-((dc - 0.98) / 0.12) ** 2.0)
            side = clamp01(0.5 + 0.5 * (qx * L[0] + qy * L[1]) / cr)
            col = col * (1.0 - bowl * (0.24 + 0.26 * (1.0 - side)) * dep)[..., None]
            col = col + C("F2CFA4") * (rim * side * 0.28 * dep * (0.35 + 0.65 * lam))[..., None]
            col = col * (1.0 - rim * (1.0 - side) * 0.20 * dep)[..., None]
        # cool terminator tint
        dark = clamp01(1.0 - lam * 2.2)
        col = col * (1.0 - dark * 0.55)[..., None] + C("121A30") * (dark * 0.35)[..., None]
        b.rgb = b.rgb * (1.0 - inside)[..., None] + col * inside[..., None]
        b.a = clamp01(inside + b.a * (1.0 - inside))
        fres = clamp01(1.0 - nz) ** 2.4
        b.over(inside * fres * clamp01(0.35 + lam * 1.1), C("5FE8FF"), 0.85)
        b.over(inside * fres * 0.5, C("D8FBFF"), 0.35)
        b.over(np.exp(-((d + 1.0) / 2.0) ** 2.0) * inside, C("060C16"), 0.5)
        return b.to_array()

    def solid(xx, yy):
        dx, dy, nz, rr, d2 = _planet_fields(xx, yy, cx, cy, R)
        return aa(rr - R)

    def atmo(xx, yy):
        dx, dy, nz, rr, d2 = _planet_fields(xx, yy, cx, cy, R)
        return np.exp(-np.maximum(rr - R, 0.0) / 30.0)

    img = make(w, h, fn, glows=[(atmo, 12.0, C("3FD6F5"), 0.85, solid),
                                (atmo, 34.0, C("1E6C8C"), 0.55, solid)])
    return save(finish(img, w, h), "planet_1.png", w, h)


def build_planet_2():
    w = h = 768
    cx = cy = 384.0
    R = 360.0
    L = norm3((-0.58, -0.46, 0.67))
    ring_rx, ring_ry = R * 1.34, R * 0.27
    tilt = math.radians(-9.0)
    tex1 = noise_tex(w, h, 3.5, 4, seed=101, res=384)
    tex2 = noise_tex(w, h, 9.0, 3, seed=131, res=384)
    tex3 = noise_tex(w, h, 18.0, 2, seed=151, res=384)

    def ring_mask(xx, yy):
        ca, sa = math.cos(tilt), math.sin(tilt)
        u = (xx - cx) * ca + (yy - cy) * sa
        v = -(xx - cx) * sa + (yy - cy) * ca
        e = np.sqrt((u / ring_rx) ** 2 + (v / ring_ry) ** 2)
        band = np.exp(-((e - 1.0) / 0.055) ** 2.0) * 0.85
        band += np.exp(-((e - 1.14) / 0.022) ** 2.0) * 0.45
        band += np.exp(-((e - 0.90) / 0.018) ** 2.0) * 0.35
        band *= 0.82 + 0.36 * tex2.at(xx / w, yy / h)
        return clamp01(band), v

    def fn(xx, yy):
        b = Block(xx.shape)
        dx, dy, nz, rr, d2 = _planet_fields(xx, yy, cx, cy, R)
        d = rr - R
        inside = aa(d)
        lam = clamp01(dx * L[0] + dy * L[1] + nz * L[2])
        shade = 0.05 + 1.0 * lam ** 0.9
        u = xx / w
        v = yy / h
        n1 = tex1.at(u, v)
        n2 = tex3.at(u, v)
        warp = 0.06 * np.sin(dx * 5.0 + n1 * 6.0) + 0.035 * (n1 - 0.5)
        vv = (dy + warp) * 7.2
        band = 0.5 + 0.5 * np.sin(vv * math.pi)
        band2 = 0.5 + 0.5 * np.sin(vv * math.pi * 2.3 + 1.7 + n2 * 1.2)
        t = clamp01(band * 0.70 + band2 * 0.30)
        base = ramp([(0.0, C("241146")), (0.26, C("4A2A8E")), (0.48, C("8B5CF6")),
                     (0.70, C("39C6E6")), (0.88, C("A8ECFF")), (1.0, C("E8FBFF"))], t)
        base = mix(base, C("2A1550"), clamp01(0.35 - lam) * 0.5)
        col = base * shade[..., None]
        spot = np.exp(-(((dx + 0.30) / 0.21) ** 2 + ((dy - 0.22) / 0.10) ** 2))
        col = mix(col, C("FF7AB0"), spot * 0.55 * shade)
        b.rgb = b.rgb * (1.0 - inside)[..., None] + col * inside[..., None]
        b.a = clamp01(inside + b.a * (1.0 - inside))
        fres = clamp01(1.0 - nz) ** 2.2
        b.over(inside * fres, C("7FE9FF"), 0.75)
        b.over(inside * fres * 0.6, C("E6FDFF"), 0.3)
        rm, rv = ring_mask(xx, yy)
        back = rm * clamp01(-rv / (ring_ry * 0.30))
        front = rm * clamp01(rv / (ring_ry * 0.30))
        b.over(back, C("B9A6E8"), 0.45)
        b.over(back, C("EAF6FF"), 0.16)
        b.over(front * aa(d + 0.5), C("C7B4F2"), 0.55)
        b.over(front * aa(d + 0.5), C("F4FBFF"), 0.22)
        return b.to_array()

    def solid(xx, yy):
        dx, dy, nz, rr, d2 = _planet_fields(xx, yy, cx, cy, R)
        return aa(rr - R)

    def atmo(xx, yy):
        dx, dy, nz, rr, d2 = _planet_fields(xx, yy, cx, cy, R)
        return np.exp(-np.maximum(rr - R, 0.0) / 26.0)

    img = make(w, h, fn, glows=[(atmo, 11.0, C("8E6CF0"), 0.9, solid),
                                (atmo, 30.0, C("3B2A80"), 0.5, solid)])
    return save(finish(img, w, h), "planet_2.png", w, h)


def build_planet_3():
    w = h = 768
    cx = cy = 384.0
    R = 360.0
    L = norm3((-0.55, -0.52, 0.65))
    tex1 = noise_tex(w, h, 2.6, 4, seed=211, ridged_=True, res=512)
    tex2 = noise_tex(w, h, 8.0, 3, seed=233, res=512)
    tex3 = noise_tex(w, h, 3.0, 3, seed=251, res=384)

    def fn(xx, yy):
        b = Block(xx.shape)
        dx, dy, nz, rr, d2 = _planet_fields(xx, yy, cx, cy, R)
        d = rr - R
        inside = aa(d)
        lam = clamp01(dx * L[0] + dy * L[1] + nz * L[2])
        shade = 0.05 + 1.0 * lam ** 0.9
        u = xx / w
        v = yy / h
        n = tex1.at(u, v)
        n2 = tex2.at(u, v)
        n3 = tex3.at(u, v)
        cracks = clamp01((n - 0.60) / 0.20) ** 1.5
        cracks *= 0.55 + 0.65 * n3
        frost = clamp01((n2 - 0.45) / 0.5)
        base = mix(C("6FB6D6"), C("CFF2FB"), clamp01(frost * 0.9 + 0.15))
        base = mix(base, C("EAFDFF"), clamp01((n2 - 0.70) * 3.0))
        col = base * shade[..., None]
        col = col * (1.0 - cracks * 0.70)[..., None] + C("0C3A5E") * (cracks * 0.42)[..., None]
        col = col + C("7FE8FF") * (cracks * 0.14 * lam)[..., None]
        dark = clamp01(1.0 - lam * 2.0)
        col = col * (1.0 - dark * 0.6)[..., None] + C("0B1A36") * (dark * 0.4)[..., None]
        b.rgb = b.rgb * (1.0 - inside)[..., None] + col * inside[..., None]
        b.a = clamp01(inside + b.a * (1.0 - inside))
        fres = clamp01(1.0 - nz) ** 2.0
        b.over(inside * fres, C("6FF0FF"), 0.95)
        b.over(inside * fres * 0.7, C("F0FFFF"), 0.45)
        b.over(np.exp(-((d + 1.0) / 2.0) ** 2.0) * inside, C("061018"), 0.45)
        return b.to_array()

    def solid(xx, yy):
        dx, dy, nz, rr, d2 = _planet_fields(xx, yy, cx, cy, R)
        return aa(rr - R)

    def atmo(xx, yy):
        dx, dy, nz, rr, d2 = _planet_fields(xx, yy, cx, cy, R)
        return np.exp(-np.maximum(rr - R, 0.0) / 28.0)

    img = make(w, h, fn, glows=[(atmo, 12.0, C("5CE8FF"), 0.95, solid),
                                (atmo, 32.0, C("1F7FA0"), 0.55, solid)])
    return save(finish(img, w, h), "planet_3.png", w, h)


# ==========================================================================
# star
# ==========================================================================
def build_star():
    w = h = 1536
    ss = 2
    cx = cy = 768.0
    R = 300.0
    tex = noise_tex(w, h, 8.0, 4, seed=901, res=640)
    tex2 = noise_tex(w, h, 26.0, 3, seed=913, res=640)

    def fn(xx, yy):
        b = Block(xx.shape)
        dx = xx - cx
        dy = yy - cy
        r = np.sqrt(dx * dx + dy * dy)
        ang = np.arctan2(dy, dx)
        th = (ang / TAU) % 1.0
        an = noise1(th, 10.0, seed=3)
        an2 = noise1(th, 30.0, seed=9)
        gran = tex.at(xx / w, yy / h)
        fine = tex2.at(xx / w, yy / h)

        # ---- photosphere
        inside = aa(r - R)
        q = np.clip(r / R, 0.0, 1.0)
        ld = 0.74 + 0.26 * np.sqrt(np.clip(1.0 - q * q, 0.0, 1.0))
        temp = clamp01(q ** 2.6)
        col = mix(C("E8FFFF"), C("FFFAE8"), temp)
        col = mix(col, C("FFD08A"), clamp01((q - 0.90) * 9.0))
        col = col * (0.87 + 0.22 * gran)[..., None] * (0.94 + 0.10 * fine)[..., None]
        col = col * ld[..., None]
        b.rgb = b.rgb * (1.0 - inside)[..., None] + col * inside[..., None]
        b.a = clamp01(inside + b.a * (1.0 - inside))

        # ---- chromosphere (thin hot rim just outside the disc)
        chromo = np.exp(-((r - R) / 2.6) ** 2.0) * sstep(R - 2.0, R + 1.0, r)
        b.over(chromo * 0.95, C("FFE6C0"), 1.0)

        # ---- corona, strictly outside the disc, fading to 0 by r=700
        tc = np.maximum(r - R, 0.0)
        outm = sstep(R - 2.0, R + 6.0, r) * sstep(700.0, 545.0, r)
        angmod = 0.68 + 0.62 * an
        cor_in = np.exp(-tc / 58.0) * 1.05
        cor_mid = np.exp(-tc / 145.0) * 0.46
        cor_out = np.exp(-tc / 330.0) * 0.15
        b.over(clamp01(cor_in * angmod) * outm, C("FFE2B8"), 0.95)
        b.over(clamp01(cor_mid * angmod) * outm, C("FF9A4A"), 0.88)
        b.over(clamp01(cor_out * angmod) * outm, C("C2501E"), 0.62)
        # radial rays
        ray = np.exp(-tc / 230.0) * clamp01((an2 - 0.48) * 2.6) * 0.42 * outm
        b.add(clamp01(ray), C("FFB870"), 0.85)
        b.add(clamp01(np.exp(-tc / 80.0) * 0.55) * outm, C("FFF2D8"), 0.7)
        return b.to_array()

    img = make(w, h, fn, ss=ss)
    return save(finish(img, w, h), "star.png", w, h)


# ==========================================================================
# turret (giant ring station)
# ==========================================================================
def seg_mask(ang, n, duty=0.9, phase=0.0, edge=0.01):
    t = ((ang - phase) / TAU * n) % 1.0
    d = np.minimum(t, 1.0 - t)
    hw = 0.5 * (1.0 - duty)
    return sstep(hw + edge, hw - edge, d)


def build_turret():
    w = h = 1024
    ss = 2
    cx = cy = 512.0
    tex = noise_tex(w, h, 34.0, 2, seed=401, res=512)
    tex2 = noise_tex(w, h, 9.0, 3, seed=419, res=512)
    Li = norm3((-0.5, -0.6, 0.62))

    def local(xx, yy, n, phase):
        dx = xx - cx
        dy = yy - cy
        r = np.sqrt(dx * dx + dy * dy)
        ang = np.arctan2(dy, dx)
        step = TAU / n
        dang = ((ang - phase + step * 0.5) % step) - step * 0.5
        return r * np.cos(dang), r * np.sin(dang), r, ang, dang

    def fn(xx, yy):
        b = Block(xx.shape)
        dx = xx - cx
        dy = yy - cy
        r = np.sqrt(dx * dx + dy * dy)
        ang = np.arctan2(dy, dx)
        nx = dx / 512.0
        ny = dy / 512.0
        lam = clamp01(0.5 - (nx * 0.42 + ny * 0.58))
        grain = tex.at(xx / w, yy / h)
        blotch = tex2.at(xx / w, yy / h)
        lamn = clamp01(lam * (0.94 + 0.10 * grain) + 0.05 * (blotch - 0.5))

        def cc(v):
            return C(v) if isinstance(v, str) else np.asarray(v, np.float32)

        def plate(mask, lo, hi, spec=0.55, spec_col="A6C2D6"):
            b.over(mask, C("070B11"))
            b.over_grad(mask, cc(lo), cc(hi), clamp01(1.0 - lamn))
            b.add(mask * clamp01((lamn - 0.60) * 2.6) * spec, cc(spec_col), 0.9)

        # ================= main armour ring 300..400 =================
        seg6 = seg_mask(ang, 6, duty=0.93, phase=math.radians(30), edge=0.005)
        ring_o = aa(sd_ring(xx, yy, cx, cy, 350.0, 50.0))
        plate(ring_o * seg6, "2E3F50", "728EA4", 0.7)
        # raised plating blocks, one per segment
        blk = aa(sd_ring(xx, yy, cx, cy, 352.0, 38.0)) * seg_mask(
            ang, 6, duty=0.80, phase=math.radians(30), edge=0.012)
        plate(blk, "3C5165", "86A3B9", 0.55)
        # chamfers
        b.over(np.exp(-((r - 399.0) / 1.6) ** 2.0) * seg6, C("93B4C8"), 0.55)
        b.over(np.exp(-((r - 400.5) / 1.0) ** 2.0) * seg6, C("CFE4F0"), 0.4)
        b.over(np.exp(-((r - 301.0) / 1.6) ** 2.0) * seg6, C("0B1219"), 0.9)
        b.over(np.exp(-((r - 318.0) / 1.4) ** 2.0) * seg6, C("16212D"), 0.6)
        # panel seams
        seam = np.exp(-((np.abs(((ang / TAU * 24.0) % 1.0) - 0.5) - 0.5) / 0.009) ** 2.0)
        b.over(seam * ring_o * seg6, C("05090F"), 0.45)
        # bolts
        kb = np.round(ang / (TAU / 48.0))
        ba = kb * TAU / 48.0
        bx = cx + np.cos(ba) * 385.0
        by = cy + np.sin(ba) * 385.0
        bolt = np.exp(-(((xx - bx) ** 2 + (yy - by) ** 2) / 5.0))
        b.over(bolt * 0.9 * seg6, C("A0BCCE"), 0.6)
        # outer gantry rim
        gant = aa(sd_ring(xx, yy, cx, cy, 414.0, 5.5)) * seg_mask(
            ang, 6, duty=0.88, phase=math.radians(30), edge=0.008)
        plate(gant, "1E2C3A", "5A768E", 0.5)
        for k in range(6):
            ga = k * TAU / 6.0 + math.radians(30)
            gx = cx + math.cos(ga) * 414.0
            gy = cy + math.sin(ga) * 414.0
            gl = np.exp(-(((xx - gx) ** 2 + (yy - gy) ** 2) / 26.0))
            b.add(gl * 0.75, CYAN, 0.85)
        # cyan lights in the segment gaps
        for k in range(6):
            ga = k * TAU / 6.0
            gx = cx + math.cos(ga) * 350.0
            gy = cy + math.sin(ga) * 350.0
            gl = np.exp(-(((xx - gx) ** 2 + (yy - gy) ** 2) / 44.0))
            b.add(gl * 0.8, CYAN, 0.85)
            b.over(gl * 1.5, C("DFFBFF"), 0.6)

        # ================= three gun bays =================
        u3, v3, _, _, _ = local(xx, yy, 3, math.pi / 2.0)
        bay = aa(sd_poly(u3, v3, [(298, 74), (402, 64), (408, 52), (408, -52),
                                  (402, -64), (298, -74)]))
        plate(bay, "26364A", "5E7A90", 0.45)
        # recessed dark bay
        rec = aa(sd_poly(u3, v3, [(308, 58), (396, 50), (396, -50), (308, -58)]))
        b.over(rec, C("060A11"))
        b.over_grad(rec, C("0B131B"), C("05080C"), clamp01(lam))
        # barrel rails
        for rv in (-38.0, 0.0, 38.0):
            rail = np.exp(-((v3 - rv) / 3.2) ** 2.0) * aa(np.abs(u3 - 352.0) - 46.0)
            b.over_grad(rail, C("2A3A4A"), C("7C99AF"), clamp01(1.0 - lamn))
            b.over(np.exp(-((v3 - rv - 2.2) / 1.0) ** 2.0) * aa(np.abs(u3 - 352.0) - 46.0),
                   C("A8C4D8"), 0.5)
        # muzzle block at the outer edge
        mz = aa(sd_ring(u3, v3, 0.0, 0.0, 398.0, 7.0)) * bay
        plate(mz, "3A4F63", "7C99AF", 0.5)
        bore = aa(sd_circle(u3, v3, 396.0, 0.0, 26.0)) * bay
        b.over(bore, C("05080C"))
        b.over(np.exp(-((np.hypot(u3 - 396.0, v3) - 26.0) / 2.4) ** 2.0) * bay, CYAN, 0.9)
        b.over(np.exp(-((np.hypot(u3 - 396.0, v3) - 26.0) / 0.9) ** 2.0) * bay,
               C("E6FEFF"), 0.7)
        # muzzle glow
        mglow = np.exp(-(((u3 - 400.0) / 9.0) ** 2 + (v3 / 40.0) ** 4.0))
        b.add(clamp01(mglow * 1.0), CYAN, 0.8)
        # bay corner bolts
        for (bu, bv) in ((312, 52), (312, -52), (390, 46), (390, -46)):
            b.over(aa(sd_circle(u3, v3, bu, bv, 3.2)), C("9CB6C8"), 0.65)

        # ================= mid energy ring 238..262 =================
        ring_m = aa(sd_ring(xx, yy, cx, cy, 250.0, 12.0))
        plate(ring_m, "2A3A4A", "64809A", 0.5)
        seg12 = seg_mask(ang, 12, duty=0.95, phase=0.0, edge=0.006)
        b.over(ring_m * seg12, C("1B2734"), 0.30)
        b.over(np.exp(-((r - 262.0) / 1.3) ** 2.0), C("86A3B9"), 0.55)
        b.over(np.exp(-((r - 238.0) / 1.3) ** 2.0), C("0E1620"), 0.85)
        energy = np.exp(-((r - 250.0) / 3.0) ** 2.0) * seg_mask(
            ang, 6, duty=0.64, phase=math.radians(30), edge=0.02)
        b.add(energy * 1.0, CYAN, 1.0)
        b.add(energy * 0.5, C("DFFBFF"), 0.85)
        b.add(np.exp(-((r - 250.0) / 9.0) ** 2.0) * seg_mask(
            ang, 6, 0.64, math.radians(30), 0.02) * 0.32, C("1E6C8C"), 0.7)
        kn = np.round((ang - math.pi / 2.0) / (TAU / 3.0))
        na = kn * TAU / 3.0 + math.pi / 2.0
        nd = np.exp(-((xx - (cx + np.cos(na) * 250.0)) ** 2 +
                      (yy - (cy + np.sin(na) * 250.0)) ** 2) / 46.0)
        b.add(clamp01(nd) * 0.9, C("B8F8FF"), 0.9)

        # ================= six struts =================
        u6, v6, _, _, _ = local(xx, yy, 6, math.radians(30))
        strut = [(158, 34), (292, 22), (292, -22), (158, -34)]
        sd6 = sd_poly(u6, v6, strut)
        sm = aa(sd6)
        plate(sm, "2A3A4C", "62809A", 0.5)
        b.over(aa(sd6 + 1.4) - aa(sd6 + 3.6), C("8AA8BC"), 0.55)
        b.over(np.exp(-((v6 - 24.0) / 1.2) ** 2.0) * sm, C("04070B"), 0.6)
        b.over(np.exp(-((v6 + 24.0) / 1.2) ** 2.0) * sm, C("04070B"), 0.6)
        b.add(np.exp(-(v6 / 1.8) ** 2.0) * sm * 0.5, C("3FA8C8"), 0.5)
        for ru in (186.0, 216.0, 246.0):
            b.over(np.exp(-((u6 - ru) / 1.8) ** 2.0) * sm, C("14202C"), 0.55)

        # ================= inner hub ring 130..170 =================
        ring_i = aa(sd_ring(xx, yy, cx, cy, 150.0, 20.0))
        seg6b = seg_mask(ang, 6, duty=0.90, phase=0.0, edge=0.008)
        plate(ring_i, "2C3C4E", "6A869E", 0.5)
        b.over(ring_i * seg6b, C("1B2734"), 0.40)
        b.over(np.exp(-((r - 170.0) / 1.4) ** 2.0) * seg6b, C("93B4C8"), 0.55)
        b.over(np.exp(-((r - 130.0) / 1.4) ** 2.0) * seg6b, C("0B1219"), 0.85)
        for k in range(6):
            a0 = k * TAU / 6.0 + math.radians(30)
            vt = aa(sd_poly(xx, yy, [(cx + math.cos(a0 + 0.055) * 162.0,
                                      cy + math.sin(a0 + 0.055) * 162.0),
                                     (cx + math.cos(a0 - 0.055) * 162.0,
                                      cy + math.sin(a0 - 0.055) * 162.0),
                                     (cx + math.cos(a0 - 0.055) * 138.0,
                                      cy + math.sin(a0 - 0.055) * 138.0),
                                     (cx + math.cos(a0 + 0.055) * 138.0,
                                      cy + math.sin(a0 + 0.055) * 138.0)]))
            b.over(vt, C("050A10"), 0.7)

        # ================= core =================
        hexd = sd_hex(xx, yy, cx, cy, 108.0, 0.0)
        hexp = aa(hexd)
        b.over(aa(hexd + 4.0), C("04070C"))
        plate(hexp, "2A3A4C", "5E788E", 0.5)
        b.over(np.exp(-((hexd + 1.4) / 1.8) ** 2.0), C("8B5CF6"), 0.7)
        well = aa(sd_circle(xx, yy, cx, cy, 92.0))
        b.over(well, C("0A0518"))
        b.add(aa(sd_ring(xx, yy, cx, cy, 86.0, 2.2)) * 0.8, PURPLE, 0.9)
        Rs = 64.0
        ddx = dx / Rs
        ddy = dy / Rs
        d2 = ddx * ddx + ddy * ddy
        nz = np.sqrt(np.clip(1.0 - d2, 0.0, 1.0))
        cl = clamp01(ddx * Li[0] + ddy * Li[1] + nz * Li[2])
        sphere_m = aa(np.sqrt(d2) * Rs - Rs)
        col = mix(C("150827"), C("7C4EE8"), clamp01(cl * 1.2))
        col = mix(col, C("DCCBFF"), clamp01((cl - 0.76) * 3.4))
        b.rgb = b.rgb * (1.0 - sphere_m)[..., None] + col * sphere_m[..., None]
        b.a = clamp01(sphere_m + b.a * (1.0 - sphere_m))
        b.over(np.exp(-((np.sqrt(d2) * Rs - Rs + 0.9) / 1.4) ** 2.0) * sphere_m,
               C("C0A6FF"), 0.75)
        spec = np.exp(-(((xx - cx + 21.0) / 13.0) ** 2 + ((yy - cy + 23.0) / 11.0) ** 2))
        b.over(clamp01(spec) * sphere_m, WHITE, 0.8)
        for k in range(3):
            a0 = k * TAU / 3.0 + math.radians(90)
            br = np.exp(-((r - 100.0) / 2.8) ** 2.0) * sector_mask(ang, a0, math.radians(40), 0.02)
            b.add(br * 0.95, PURPLE, 0.95)
            b.add(br * 0.4, C("E0D4FF"), 0.7)
        b.add(clamp01(np.exp(-(r / 104.0) ** 2.0) * 0.30), PURPLE, 0.5)
        return b.to_array()

    def gmask_outer(xx, yy):
        ang = np.arctan2(yy - cy, xx - cx)
        return aa(sd_ring(xx, yy, cx, cy, 350.0, 52.0)) * seg_mask(
            ang, 6, 0.93, math.radians(30), 0.005)

    def solid_ring(xx, yy):
        ang = np.arctan2(yy - cy, xx - cx)
        return aa(sd_ring(xx, yy, cx, cy, 350.0, 50.0)) * seg_mask(
            ang, 6, 0.93, math.radians(30), 0.005)

    def gmask_core(xx, yy):
        r = np.hypot(xx - cx, yy - cy)
        return np.exp(-(np.maximum(r - 64.0, 0.0) / 55.0) ** 2.0)

    img = make(w, h, fn, ss=ss, glows=[(gmask_outer, 5.0, CYAN, 0.7, solid_ring),
                                       (gmask_outer, 17.0, C("1E6C8C"), 0.4, solid_ring),
                                       (gmask_core, 9.0, PURPLE, 0.8)])
    return save(finish(img, w, h), "turret.png", w, h)


# ==========================================================================
# turret ember overlay
# ==========================================================================
def build_turret_ember():
    w = h = 768
    ss = 2
    cx = cy = 384.0
    R = 300.0
    rng = np.random.default_rng(1234)
    arcs = []
    for k in range(7):
        a0 = k * TAU / 7.0 + rng.uniform(-0.12, 0.12)
        half = rng.uniform(0.14, 0.30)
        rr = R + rng.uniform(-8, 8)
        hw = rng.uniform(4.0, 9.0)
        arcs.append((a0, half, rr, hw))
    cracks = []
    for k in range(9):
        a0 = rng.uniform(0, TAU)
        r0 = R - rng.uniform(10, 46)
        r1 = r0 - rng.uniform(26, 70)
        cracks.append((a0, r0, r1))

    def fn(xx, yy):
        b = Block(xx.shape)
        r = np.hypot(xx - cx, yy - cy)
        ang = np.arctan2(yy - cy, xx - cx)
        for (a0, half, rr, hw) in arcs:
            m = sector_mask(ang, a0, half, 0.02)
            core = np.exp(-((r - rr) / hw) ** 2.0) * m
            b.add(core * 1.1, C("FF3D2A"), 1.0)
            b.add(core * 0.55, C("FF9A4A"), 0.9)
            b.add(np.exp(-((r - rr) / (hw * 0.35)) ** 2.0) * m * 0.8, C("FFE0B0"), 0.8)
        for (a0, r0, r1) in cracks:
            ca, sa = math.cos(a0), math.sin(a0)
            d = sd_seg(xx, yy, cx + ca * r0, cy + sa * r0,
                       cx + ca * r1, cy + sa * r1, 0.0)
            cm = np.exp(-(d / 1.6) ** 2.0) * sstep(r1 - 4, r1 + 14, r)
            b.add(cm * 0.85, C("FF4A2A"), 0.9)
            b.add(np.exp(-(d / 0.6) ** 2.0) * cm * 0.6, C("FFD0A0"), 0.7)
        # hot specks on the ring
        for k in range(26):
            a0 = rng.uniform(0, TAU)
            rr = R + rng.uniform(-14, 14)
            px = cx + math.cos(a0) * rr
            py = cy + math.sin(a0) * rr
            sp = np.exp(-(((xx - px) ** 2 + (yy - py) ** 2) / 9.0))
            b.add(sp * 0.6, C("FF6A3A"), 0.7)
        return b.to_array()

    img = make(w, h, fn, ss=ss)
    return save(finish(img, w, h), "turret_ember.png", w, h)


# ==========================================================================
# safe zone
# ==========================================================================
def hex_edge(xx, yy, size):
    """Distance to the nearest hexagon edge (0 on the edge, 0.5 at the centre)."""
    u = xx / size
    v = yy / size
    r0, r1 = 1.0, 1.7320508
    h0, h1 = r0 * 0.5, r1 * 0.5
    a0 = np.mod(u, r0) - h0
    a1 = np.mod(v, r1) - h1
    b0 = np.mod(u - h0, r0) - h0
    b1 = np.mod(v - h1, r1) - h1
    use_a = (a0 * a0 + a1 * a1) < (b0 * b0 + b1 * b1)
    gx = np.where(use_a, a0, b0)
    gy = np.where(use_a, a1, b1)
    ax = np.abs(gx)
    ay = np.abs(gy)
    d = np.maximum(ax * 0.5 + ay * 0.8660254, ax)
    return 0.5 - d


def build_safezone():
    w = h = 640
    ss = 4
    cx = cy = 320.0
    R = 262.0

    def fn(xx, yy):
        b = Block(xx.shape)
        r = np.hypot(xx - cx, yy - cy)
        ang = np.arctan2(yy - cy, xx - cx)
        # ---- main ring (bright, slightly tapered)
        ring = np.exp(-((r - R) / 3.4) ** 2.0)
        ring_in = np.exp(-((r - R + 7.0) / 2.0) ** 2.0) * 0.55
        b.over(ring, C("B8FFE0"), 1.0)
        b.over(ring * 0.8, WHITE, 0.7)
        b.over(ring_in, C("5CF2A8"), 0.65)
        # ---- dashed inner ring
        dash = sstep(-0.35, 0.25, np.sin(ang * 36.0))
        dr = np.exp(-((r - (R - 30.0)) / 1.7) ** 2.0) * dash
        b.over(dr, MINT, 0.8)
        # ---- hex energy weave inside the annulus
        he = hex_edge(xx, yy, 26.0)
        hexm = np.exp(-(he / 0.030) ** 2.0)
        band = sstep(R - 66.0, R - 56.0, r) * sstep(R - 6.0, R - 16.0, r)
        b.over(hexm * band * 0.30, MINT, 0.5)
        # ---- hex nodes on the weave
        for k in range(12):
            a0 = k * TAU / 12.0 + 0.26
            hr = R - 38.0
            px = cx + math.cos(a0) * hr
            py = cy + math.sin(a0) * hr
            nd = np.exp(-(((xx - px) ** 2 + (yy - py) ** 2) / 16.0))
            b.over(nd * 0.9, C("CFFFE8"), 0.7)
        # ---- four entry chevrons pointing inward
        for k in range(4):
            a0 = k * TAU / 4.0 + math.pi / 4.0
            ca, sa = math.cos(a0), math.sin(a0)
            px, py = -sa, ca
            for off in (0.0, 9.0):
                tipr = R - 44.0 + off
                base = R - 20.0 + off
                p1 = (cx + ca * base + px * 13.0, cy + sa * base + py * 13.0)
                p2 = (cx + ca * tipr, cy + sa * tipr)
                p3 = (cx + ca * base - px * 13.0, cy + sa * base - py * 13.0)
                d = np.minimum(sd_seg(xx, yy, p1[0], p1[1], p2[0], p2[1], 1.5),
                               sd_seg(xx, yy, p3[0], p3[1], p2[0], p2[1], 1.5))
                m = aa(d)
                b.over(m, C("D8FFEE"), 0.95 if off == 0 else 0.45)
        # ---- outer tick marks
        tick = (np.exp(-((r - (R + 12.0)) / 1.3) ** 2.0)
                * sstep(-0.2, 0.3, np.sin(ang * 24.0)))
        b.over(tick * 0.5, MINT, 0.6)
        return b.to_array()

    def gmask(xx, yy):
        r = np.hypot(xx - cx, yy - cy)
        return np.exp(-((r - R) / 5.0) ** 2.0)

    def solid(xx, yy):
        r = np.hypot(xx - cx, yy - cy)
        return aa(np.abs(r - R) - 3.4)

    img = make(w, h, fn, ss=ss, glows=[(gmask, 6.0, MINT, 1.0, solid),
                                       (gmask, 20.0, C("1E8C6A"), 0.55, solid)])
    return save(finish(img, w, h), "safezone.png", w, h)


def build_safezone_fill():
    w = h = 640
    ss = 4
    cx = cy = 320.0

    def fn(xx, yy):
        b = Block(xx.shape)
        r = np.hypot(xx - cx, yy - cy)
        q = r / 290.0
        a = clamp01(np.exp(-(q / 0.78) ** 2.0) * 0.34 + np.exp(-(q / 0.40) ** 2.0) * 0.16)
        a = a * sstep(1.02, 0.80, q)
        b.over(a, WHITE)
        b.add(a * 0.35, C("E8FFFF"), 0.6)
        return b.to_array()

    img = make(w, h, fn, ss=ss)
    return save(finish(img, w, h), "safezone_fill.png", w, h)


# ==========================================================================
# shop station
# ==========================================================================
def build_shop_station():
    w = h = 640
    ss = 4
    cx = cy = 320.0
    Rh = 250.0
    tex = noise_tex(w, h, 26.0, 2, seed=555, res=384)

    def fn(xx, yy):
        b = Block(xx.shape)
        dx = xx - cx
        dy = yy - cy
        r = np.hypot(dx, dy)
        ang = np.arctan2(dy, dx)
        lam = clamp01(0.5 - (dx / 320.0 * 0.42 + dy / 320.0 * 0.58))
        grain = tex.at(xx / w, yy / h)
        lamn = clamp01(lam * (0.94 + 0.10 * grain))
        # ---- hex platform
        hexd = sd_hex(xx, yy, cx, cy, Rh, math.radians(30))
        b.over(aa(hexd + 5.0), C("05080D"))
        b.over(aa(hexd), C("0C1219"))
        b.over_grad(aa(hexd - 3.0), C("1B2836"), C("3A4C5E"), clamp01(1.0 - lamn))
        # amber rim strips
        b.over(np.exp(-((hexd + 2.0) / 1.6) ** 2.0), AMBER, 0.95)
        b.over(np.exp(-((hexd + 2.0) / 0.7) ** 2.0), C("FFE2B0"), 0.6)
        # inner hexagon plates
        hx2 = sd_hex(xx, yy, cx, cy, Rh * 0.78, math.radians(30))
        b.over(np.exp(-((hx2 + 1.0) / 1.1) ** 2.0), C("7A5A22"), 0.55)
        hx3 = sd_hex(xx, yy, cx, cy, Rh * 0.52, math.radians(30))
        b.over(aa(hx3), C("101822"), 0.85)
        b.over(np.exp(-((hx3 + 1.0) / 1.2) ** 2.0), AMBER, 0.7)
        # radial panel seams
        seam = np.exp(-((np.abs(((ang / TAU * 12.0) % 1.0) - 0.5) - 0.5) / 0.012) ** 2.0)
        b.over(seam * aa(hexd - 6.0) * aa(hx3 + 6.0), C("05080D"), 0.45)
        # ---- amber light strips along three edges
        for k in range(3):
            a0 = k * TAU / 3.0 + math.radians(30)
            ca, sa = math.cos(a0), math.sin(a0)
            d = sd_seg(xx, yy, cx + ca * 120.0, cy + sa * 120.0,
                       cx + ca * 232.0, cy + sa * 232.0, 0.0)
            strip = np.exp(-(d / 1.8) ** 2.0) * aa(hexd - 8.0)
            b.add(strip * 0.9, AMBER, 0.9)
            b.add(strip * 0.4, C("FFF0C8"), 0.7)
        # ---- central hub
        hub = aa(sd_circle(xx, yy, cx, cy, 92.0))
        b.over(aa(sd_circle(xx, yy, cx, cy, 97.0)), C("05080D"))
        b.over(hub, C("0E1620"))
        b.over_grad(aa(sd_circle(xx, yy, cx, cy, 86.0)), C("2A3A4A"), C("0D141C"),
                    clamp01(1.0 - lamn))
        b.over(np.exp(-((r - 92.0) / 1.8) ** 2.0), AMBER, 0.85)
        # dome
        Rs = 62.0
        ddx = dx / Rs
        ddy = dy / Rs
        d2 = ddx * ddx + ddy * ddy
        nz = np.sqrt(np.clip(1.0 - d2, 0.0, 1.0))
        cl = clamp01(ddx * -0.45 + ddy * -0.55 + nz * 0.70)
        dome_m = aa(np.sqrt(d2) * Rs - Rs)
        col = mix(C("1A1206"), C("FFB347"), clamp01(cl * 1.05))
        col = mix(col, C("FFF0D0"), clamp01((cl - 0.78) * 4.0))
        b.rgb = b.rgb * (1.0 - dome_m)[..., None] + col * dome_m[..., None]
        b.a = clamp01(dome_m + b.a * (1.0 - dome_m))
        b.over(np.exp(-((np.sqrt(d2) * Rs - Rs + 0.8) / 1.3) ** 2.0) * dome_m,
               C("FFE0A8"), 0.6)
        b.add(clamp01(np.exp(-(r / 100.0) ** 2.0) * 0.35), AMBER, 0.5)
        # ---- holo billboard (no text): translucent panel with glyph bars
        bx, by = cx + 150.0, cy - 150.0
        bd = sd_box(xx, yy, bx, by, 78.0, 40.0, 6.0)
        b.over(aa(bd), C("FFB347"), 0.10)
        b.over(np.exp(-((bd - 1.0) / 1.5) ** 2.0), AMBER, 0.85)
        b.over(np.exp(-((bd - 1.0) / 0.5) ** 2.0), C("FFF2D2"), 0.5)
        for i, (gx, gy, gw, gh) in enumerate(((bx - 40, by - 14, 34, 5),
                                              (bx - 40, by - 2, 22, 5),
                                              (bx - 40, by + 10, 44, 4),
                                              (bx + 26, by - 16, 8, 8),
                                              (bx + 26, by + 4, 8, 8))):
            g = aa(sd_box(xx, yy, gx, gy, gw, gh, 1.6))
            b.over(g * 0.55, AMBER if i % 2 == 0 else MAGENTA, 0.85)
        b.add(aa(bd) * 0.10, AMBER, 0.4)
        # billboard support beams
        for sx in (-1, 1):
            d = sd_seg(xx, yy, bx + sx * 60.0, by + 40.0, cx + sx * 40.0, cy - 92.0, 1.2)
            b.over(np.exp(-(d / 1.4) ** 2.0), C("8A6A2A"), 0.5)
        # ---- three docking arms
        for k in range(3):
            a0 = k * TAU / 3.0 + math.radians(90)
            ca, sa = math.cos(a0), math.sin(a0)
            d = sd_seg(xx, yy, cx + ca * 86.0, cy + sa * 86.0,
                       cx + ca * 258.0, cy + sa * 258.0, 9.0)
            b.over(aa(d), C("0B1219"))
            b.over_grad(aa(d - 2.0), C("2A3A4A"), C("141E28"), clamp01(1.0 - lamn))
            b.over(np.exp(-((d + 0.5) / 1.0) ** 2.0) * 0.7, C("8FB2C6"), 0.4)
            tip = aa(sd_circle(xx, yy, cx + ca * 256.0, cy + sa * 256.0, 12.0))
            b.over(tip, C("0E1620"))
            b.over(np.exp(-((np.hypot(xx - cx - ca * 256.0, yy - cy - sa * 256.0) - 12.0)
                            / 1.6) ** 2.0), AMBER, 0.8)
        return b.to_array()

    def gmask(xx, yy):
        return aa(sd_hex(xx, yy, cx, cy, Rh + 2.0, math.radians(30)))

    def solid(xx, yy):
        return aa(sd_hex(xx, yy, cx, cy, Rh, math.radians(30)))

    img = make(w, h, fn, ss=ss, glows=[(gmask, 7.0, AMBER, 0.55, solid),
                                       (gmask, 22.0, C("8C5A16"), 0.4, solid)])
    return save(finish(img, w, h), "shop_station.png", w, h)


# ==========================================================================
# warp ring
# ==========================================================================
def build_warp_ring():
    w = h = 1024
    ss = 2
    cx = cy = 512.0
    R = 400.0

    def fn(xx, yy):
        b = Block(xx.shape)
        r = np.hypot(xx - cx, yy - cy)
        ang = np.arctan2(yy - cy, xx - cx)
        th = (ang / TAU) % 1.0
        an = noise1(th, 26.0, seed=61)
        an2 = noise1(th, 7.0, seed=77)
        # main ring
        core = np.exp(-((r - R) / 2.2) ** 2.0)
        halo = np.exp(-((r - R) / 16.0) ** 2.0) * 0.45
        a = clamp01((core + halo) * (0.72 + 0.5 * an))
        b.over(a, C("D8FBFF"), 0.95)
        b.over(core * 0.85, WHITE, 0.8)
        # chromatic fringe
        b.add(np.exp(-((r - R - 6.0) / 3.0) ** 2.0) * 0.5, PURPLE, 0.55)
        b.add(np.exp(-((r - R + 7.0) / 3.0) ** 2.0) * 0.5, CYAN, 0.6)
        # inner secondary ring
        b.add(np.exp(-((r - R * 0.72) / 2.0) ** 2.0) * (0.4 + 0.4 * an2) * 0.55, CYAN, 0.6)
        # radial streaks rushing inward
        streak = np.exp(-((np.abs(((ang / TAU * 48.0) % 1.0) - 0.5) - 0.5) / 0.06) ** 2.0)
        inward = streak * sstep(R - 4.0, R - 70.0, r) * sstep(R - 190.0, R - 110.0, r)
        b.add(inward * 0.55, C("8FF0FF"), 0.7)
        outward = streak * sstep(R + 3.0, R + 40.0, r) * sstep(R + 120.0, R + 70.0, r)
        b.add(outward * 0.30, C("5FE8FF"), 0.6)
        # fade outer
        fade = sstep(500.0, 440.0, r)
        b.a = b.a * fade
        b.rgb = b.rgb * fade[..., None]
        return b.to_array()

    img = make(w, h, fn, ss=ss)
    return save(finish(img, w, h), "warp_ring.png", w, h)


# ==========================================================================
# fleet additions (Aegis carrier / gravity rig / relays / heavy ordnance)
# ==========================================================================
def _radial_poly(cx, cy, ctrl, n=96, scale=1.0):
    """Faceted closed hull from (deg, radius) control points (-180 .. 180)."""
    degs = np.array([c[0] for c in ctrl], np.float32)
    rads = np.array([c[1] for c in ctrl], np.float32)
    angs = np.linspace(-180.0, 180.0, n, endpoint=False)
    rr = np.interp(angs, degs, rads) * scale
    th = np.radians(angs)
    return [(float(cx + r * math.cos(t)), float(cy + r * math.sin(t)))
            for r, t in zip(rr, th)]


def _arm_frame(xx, yy, cx, cy, n, phase):
    """Fold the canvas into one of n symmetric wedge frames (turret style)."""
    dx = xx - cx
    dy = yy - cy
    r = np.sqrt(dx * dx + dy * dy)
    ang = np.arctan2(dy, dx)
    step = TAU / n
    dang = ((ang - phase + step * 0.5) % step) - step * 0.5
    return r * np.cos(dang), r * np.sin(dang), r, ang, dang


def _spiral_pts(cx, cy, base, r0, r1, sweep, steps=9):
    out = []
    for i in range(steps):
        t = i / float(steps - 1)
        a = base + sweep * t
        rr = r0 + (r1 - r0) * t
        out.append((cx + math.cos(a) * rr, cy + math.sin(a) * rr))
    return out


CARRIER_CTRL = [
    (-180.0, 316.0), (-168.0, 350.0), (-142.0, 364.0), (-118.0, 350.0),
    (-96.0, 374.0), (-74.0, 354.0), (-52.0, 370.0), (-34.0, 354.0),
    (-18.0, 372.0), (0.0, 404.0), (18.0, 372.0), (34.0, 354.0),
    (52.0, 370.0), (74.0, 354.0), (96.0, 374.0), (118.0, 350.0),
    (142.0, 364.0), (168.0, 350.0), (180.0, 316.0),
]


def build_carrier():
    """Aegis carrier: bow (+X) energy rail, layered armour, violet stern core."""
    w = h = 1024
    ss = 2
    cx = cy = 512.0
    tex = noise_tex(w, h, 30.0, 2, seed=811, res=512)
    tex2 = noise_tex(w, h, 8.0, 3, seed=827, res=512)

    hull = _radial_poly(cx, cy, CARRIER_CTRL, 96)
    h_mid = _radial_poly(cx, cy, CARRIER_CTRL, 96, 0.880)
    h_in = _radial_poly(cx, cy, CARRIER_CTRL, 96, 0.700)
    h_deck = _radial_poly(cx, cy, CARRIER_CTRL, 96, 0.500)
    bow_cap = [(cx + 404.0, cy), (cx + 370.0, cy - 60.0), (cx + 330.0, cy - 84.0),
               (cx + 346.0, cy), (cx + 330.0, cy + 84.0), (cx + 370.0, cy + 60.0)]

    def fn(xx, yy):
        b = Block(xx.shape)
        dx = xx - cx
        dy = yy - cy
        r = np.sqrt(dx * dx + dy * dy)
        ang = np.arctan2(dy, dx)
        lam = clamp01(0.5 - (dx / 512.0 * 0.42 + dy / 512.0 * 0.58))
        grain = tex.at(xx / w, yy / h)
        blotch = tex2.at(xx / w, yy / h)
        lamn = clamp01(lam * (0.92 + 0.12 * grain) + 0.06 * (blotch - 0.5))

        def cc(v):
            return C(v) if isinstance(v, str) else np.asarray(v, np.float32)

        def plate(mask, lo, hi, spec=0.45, spec_col="A6C2D6"):
            b.over(mask, C("05080D"))
            b.over_grad(mask, cc(lo), cc(hi), clamp01(1.0 - lamn))
            b.add(mask * clamp01((lamn - 0.60) * 2.6) * spec, cc(spec_col), 0.9)

        # ---- silhouette + base armour (kept dark; the belts carry the value)
        d = sd_poly(xx, yy, hull)
        body = aa(d)
        b.over(aa(d + 4.5), C("03060B"))
        b.over(aa(d + 1.0), C("070D15"))
        b.over_grad(body, C("101B26"), C("070C13"), clamp01(lamn * 1.05))
        b.over(np.exp(-((d + 1.3) / 1.4) ** 2.0), C("33506A"), 0.55)
        b.over(np.exp(-((d + 0.35) / 0.55) ** 2.0) * 0.75, C("7EA4BC"), 0.5)

        # ---- three stepped armour belts that follow the hull outline
        for (poly, lo, hi, spec) in ((h_mid, "161F2B", "3A5064", 0.40),
                                     (h_in, "18222E", "42606F", 0.40),
                                     (h_deck, "1B2733", "4A6876", 0.32)):
            dd = sd_poly(xx, yy, poly)
            plate(aa(dd), lo, hi, spec)
            b.over(np.exp(-((dd + 0.7) / 0.75) ** 2.0), C("8AACC2"), 0.40)
            b.over(np.exp(-((dd - 1.2) / 2.0) ** 2.0) * 0.85, C("04070C"), 0.75)

        # ---- facet seams (18 wedges) + belt dash marks
        seam = np.exp(-((np.abs(((ang / TAU * 18.0) % 1.0) - 0.5) - 0.5) / 0.0075) ** 2.0)
        b.over(seam * body * aa(d - 8.0) * 0.55, C("04080E"), 0.6)
        dash = sstep(-0.45, 0.20, np.sin(ang * 30.0))
        belt = np.exp(-((r - 300.0) / 1.4) ** 2.0) * dash * body
        b.over(belt * 0.7, C("060C14"), 0.55)
        b.over(np.exp(-((r - 356.0) / 1.1) ** 2.0) * body * 0.6, C("08101A"), 0.55)

        # ---- flight deck cut into the inner belt
        rw = sd_box(xx, yy, cx + 40.0, cy, 138.0, 60.0, 22.0)
        b.over(aa(rw + 4.0), C("04070B"))
        b.over(aa(rw), C("09111A"))
        b.over_grad(aa(rw - 5.0), C("0D1720"), C("060B12"), clamp01(1.0 - lamn))
        b.over(np.exp(-((rw + 2.2) / 1.3) ** 2.0), C("3A5468"), 0.55)
        b.over(np.exp(-((rw + 2.2) / 0.5) ** 2.0) * 0.6, C("94B8CC"), 0.4)
        for sy in (-1.0, 1.0):
            ys = cy + sy * 52.0
            b.add(np.exp(-((yy - ys) / 1.3) ** 2.0) * sstep(cx - 70.0, cx - 35.0, xx)
                  * sstep(cx + 155.0, cx + 120.0, xx) * 0.85, CYAN, 0.8)
        for gx in (-40.0, 10.0, 60.0, 110.0):
            b.over(aa(sd_box(xx, yy, cx + gx, cy, 1.7, 33.0, 1.7)) * 0.5,
                   C("2C465E"), 0.6)

        # ---- command hub at the aft end of the deck
        hubc = (cx - 74.0, cy)
        hubd = sd_hex(xx, yy, hubc[0], hubc[1], 62.0, math.radians(30))
        b.over(aa(hubd + 3.0), C("04070B"))
        plate(aa(hubd), "19242F", "48647A", 0.45)
        b.over(np.exp(-((hubd + 0.8) / 1.0) ** 2.0), C("8FB2C6"), 0.45)
        hh = sd_hex(xx, yy, hubc[0], hubc[1], 34.0, math.radians(30))
        b.over(aa(hh), C("131E29"))
        b.over(np.exp(-((hh + 1.0) / 1.1) ** 2.0), C("5A7E96"), 0.6)
        b.add(np.exp(-((hh + 1.0) / 1.6) ** 2.0) * 0.5, CYAN, 0.65)

        # ---- bow wedge plates (thicker nose armour)
        bd = sd_poly(xx, yy, bow_cap)
        b.over(np.exp(-((bd - 1.5) / 2.4) ** 2.0) * 0.7, C("04070C"), 0.7)
        plate(aa(bd), "22303C", "4E6A7E", 0.5)
        b.over(np.exp(-((bd + 0.8) / 0.9) ** 2.0), C("A6C6DA"), 0.5)
        b.over(np.exp(-((bd + 2.6) / 2.0) ** 2.0) * 0.6, CYAN, 0.28)
        seam_b = np.exp(-((np.abs(((ang / TAU * 8.0) % 1.0) - 0.5) - 0.5) / 0.012) ** 2.0)
        b.over(seam_b * aa(bd) * 0.5, C("05090F"), 0.55)
        # nose sensor slit
        slit = np.exp(-((yy - cy) / 1.6) ** 2.0) * sstep(348.0, 358.0, xx) * sstep(400.0, 390.0, xx)
        b.add(slit * 0.9, CYAN, 0.9)
        b.add(slit * 0.5, C("E8FFFF"), 0.7)

        # ---- cyan energy rail at the bow: two arcs over +-50 deg
        span = sstep(math.radians(50.0), math.radians(43.0), ang_dist(ang, 0.0))
        rail_o = np.exp(-((r - 330.0) / 2.1) ** 2.0) * span * aa(d - 3.0)
        rail_i = np.exp(-((r - 306.0) / 1.6) ** 2.0) * span * aa(d - 3.0)
        for rl, amp in ((rail_o, 1.0), (rail_i, 0.72)):
            b.over(rl * amp, C("9FF4FF"), 0.95)
            b.over(rl * amp * 0.55, WHITE, 0.85)
            b.add(rl * amp * 0.85, CYAN, 0.95)
        conn = np.exp(-((np.abs(((ang / TAU * 42.0) % 1.0) - 0.5) - 0.5) / 0.022) ** 2.0)
        bar = sstep(302.0, 307.0, r) * sstep(334.0, 329.0, r)
        b.add(conn * bar * span * 0.55, CYAN, 0.8)
        b.add(np.exp(-((r - 318.0) / 40.0) ** 2.0) * span * 0.28, CYAN, 0.5)
        for sgn in (-1.0, 1.0):
            ea = math.radians(50.0) * sgn
            ex = cx + math.cos(ea) * 318.0
            ey = cy + math.sin(ea) * 318.0
            nd = np.exp(-(((xx - ex) ** 2 + (yy - ey) ** 2) / 90.0))
            b.add(clamp01(nd * 1.1), CYAN, 0.95)
            b.over(clamp01(nd * 1.25), C("F0FEFF"), 0.8)
            b.over(aa(sd_circle(xx, yy, ex, ey, 9.0)) - aa(sd_circle(xx, yy, ex, ey, 5.4)),
                   C("BFF4FF"), 0.55)

        # ---- deck consoles + hatch greebles
        for (gx, gy) in ((-10.0, -118.0), (-10.0, 118.0), (116.0, -118.0), (116.0, 118.0)):
            gd = sd_box(xx, yy, cx + gx, cy + gy, 30.0, 11.0, 3.0)
            b.over(aa(gd), C("0E1822"))
            b.over(np.exp(-((gd + 0.6) / 0.8) ** 2.0), C("3E5A6E"), 0.5)
            b.add(aa(sd_box(xx, yy, cx + gx, cy + gy, 22.0, 1.3, 0.6)) * 0.55, CYAN, 0.5)
        for (gx, gy, gw, gh) in ((-150.0, -60.0, 22.0, 34.0), (-150.0, 60.0, 22.0, 34.0),
                                 (190.0, 0.0, 12.0, 26.0)):
            gd = sd_box(xx, yy, cx + gx, cy + gy, gw, gh, 4.0)
            b.over(aa(gd), C("101A24"))
            b.over(np.exp(-((gd + 0.6) / 0.7) ** 2.0), C("3A5364"), 0.45)

        # ---- stern: violet radiator core with four fins
        cxs, cys = cx - 190.0, cy
        rc = np.hypot(xx - cxs, yy - cys)
        b.over(aa(sd_circle(xx, yy, cxs, cys, 57.0)), C("04070C"))
        for k in range(4):
            fy = cys + (k - 1.5) * 25.0
            fd = sd_box(xx, yy, cxs, fy, 44.0, 7.0, 3.0)
            b.over(aa(fd), C("1B1029"))
            b.over(np.exp(-((fd + 0.7) / 0.9) ** 2.0), C("8B5CF6"), 0.55)
        b.over(aa(sd_circle(xx, yy, cxs, cys, 34.0)), C("220F35"))
        b.over_grad(aa(sd_circle(xx, yy, cxs, cys, 28.0)), C("6C3ED0"), C("241040"),
                    clamp01(1.0 - lamn))
        b.over(np.exp(-((rc - 34.0) / 1.5) ** 2.0), PURPLE, 0.9)
        b.over(np.exp(-((rc - 34.0) / 0.55) ** 2.0), C("E0D4FF"), 0.6)
        b.add(clamp01(np.exp(-(rc / 22.0) ** 2.0) * 1.05), MAGENTA, 0.9)
        b.over(clamp01(np.exp(-(rc / 13.0) ** 2.0) * 1.05), C("FFE6F2"), 0.85)

        # ---- twin exhaust bells at the stern
        for sgn in (-1.0, 1.0):
            nx0 = cx - 258.0
            ny0 = cy + sgn * 78.0
            nd = sd_circle(xx, yy, nx0, ny0, 30.0)
            b.over(aa(nd + 4.0), C("04070C"))
            b.over(aa(nd), C("0B1119"))
            b.over_grad(aa(nd - 7.0), C("22303E"), C("0C141D"), clamp01(1.0 - lamn))
            b.over(np.exp(-((nd + 1.5) / 1.2) ** 2.0), C("8B5CF6"), 0.9)
            b.over(np.exp(-((np.hypot(xx - nx0, yy - ny0) - 12.0) / 1.4) ** 2.0),
                   PURPLE, 0.85)
            gl = np.exp(-(((xx - nx0 + 6.0) / 9.0) ** 2 + ((yy - ny0) / 11.0) ** 2))
            b.add(clamp01(gl * 1.25), PURPLE, 0.95)
            b.over(clamp01(gl * 1.15), C("E6DAFF"), 0.7)

        # ---- running lights along the flanks
        for k in range(6):
            a0 = math.radians(-120.0 + k * 48.0)
            lx = cx + math.cos(a0) * 336.0
            ly = cy + math.sin(a0) * 336.0
            nd = np.exp(-(((xx - lx) ** 2 + (yy - ly) ** 2) / 22.0))
            b.add(clamp01(nd * 0.8), CYAN, 0.7)
        return b.to_array()

    def solid(xx, yy):
        return aa(sd_poly(xx, yy, hull))

    def gmask(xx, yy):
        return aa(sd_poly(xx, yy, hull) + 2.0)

    def rail_glow(xx, yy):
        ang = np.arctan2(yy - cy, xx - cx)
        r = np.hypot(xx - cx, yy - cy)
        span = sstep(math.radians(52.0), math.radians(40.0), ang_dist(ang, 0.0))
        return clamp01(np.exp(-((r - 318.0) / 26.0) ** 2.0) * span)

    def stern_glow(xx, yy):
        # tight enough that the violet spill stays inside the hull silhouette
        r = np.hypot(xx - cx + 210.0, yy - cy)
        return clamp01(np.exp(-(r / 46.0) ** 2.0))

    img = make(w, h, fn, ss=ss, glows=[(gmask, 5.0, CYAN, 0.55, solid),
                                       (gmask, 17.0, C("1E6C8C"), 0.35, solid),
                                       (rail_glow, 7.0, CYAN, 1.0),
                                       (stern_glow, 9.0, PURPLE, 0.55)])
    return save(finish(img, w, h), "carrier.png", w, h)


def build_shield_arc():
    """120 deg (X+-60) deflector band; concentric with the canvas, tintable."""
    w = h = 768
    cx = cy = 384.0
    Rm = 330.0
    span = math.radians(60.0)

    def fn(xx, yy):
        b = Block(xx.shape)
        r = np.hypot(xx - cx, yy - cy)
        ang = np.arctan2(yy - cy, xx - cx)
        fade = sstep(352.0, 340.0, r)
        edge = sstep(span, math.radians(44.0), ang_dist(ang, 0.0))
        core = np.exp(-((r - Rm) / 8.2) ** 2.0) * edge * fade
        halo = np.exp(-((r - Rm) / 13.0) ** 2.0) * edge * fade
        body = np.exp(-((r - Rm) / 13.0) ** 4.0) * edge * fade
        b.over(clamp01(body * 0.34), ICE, 0.9)
        b.over(clamp01(core * 0.92), C("EAFEFF"), 1.0)
        b.over(clamp01(core * 0.50 + halo * 0.26), WHITE, 0.85)
        b.add(clamp01(halo * 0.30), CYAN, 0.5)
        # inner facet line (gives the band a two-layer feel)
        inner = np.exp(-((r - (Rm - 10.0)) / 1.1) ** 2.0) * edge * fade
        b.over(inner * 0.45, C("CDEFFF"), 0.55)
        # outer chromatic fringe so the frontier reads as an energy field
        b.add(np.exp(-((r - (Rm + 8.0)) / 2.6) ** 2.0) * edge * fade * 0.35, CYAN, 0.5)
        # slightly hotter end segments, softly dissolving into the fade
        for sgn in (-1.0, 1.0):
            ea = np.exp(-(ang_dist(ang, span * sgn) / 0.05) ** 2.0)
            em = ea * edge * np.exp(-((r - Rm) / 15.0) ** 2.0) * fade
            b.over(clamp01(em * 0.55), C("F4FFFF"), 0.85)
            b.add(clamp01(em * 0.45), CYAN, 0.6)
        return b.to_array()

    img = make(w, h, fn, ss=2)
    return save(finish(img, w, h), "shield_arc.png", w, h)


def build_singularity_rig():
    """Gravity-well rig: three cold-steel rings, violet spiral arms, magenta core."""
    w = h = 768
    ss = 2
    cx = cy = 384.0
    tex = noise_tex(w, h, 26.0, 2, seed=849, res=384)
    arms = []
    for k in range(3):
        base = k * TAU / 3.0 + math.radians(90)
        arms.append(_spiral_pts(cx, cy, base, 292.0, 116.0, 1.78, steps=13))

    def fn(xx, yy):
        b = Block(xx.shape)
        dx = xx - cx
        dy = yy - cy
        r = np.sqrt(dx * dx + dy * dy)
        ang = np.arctan2(dy, dx)
        lam = clamp01(0.5 - (dx / 384.0 * 0.42 + dy / 384.0 * 0.58))
        grain = tex.at(xx / w, yy / h)
        lamn = clamp01(lam * (0.92 + 0.12 * grain))

        def cc(v):
            return C(v) if isinstance(v, str) else np.asarray(v, np.float32)

        def plate(mask, lo, hi, spec=0.5, spec_col="A6C2D6"):
            b.over(mask, C("060A10"))
            b.over_grad(mask, cc(lo), cc(hi), clamp01(1.0 - lamn))
            b.add(mask * clamp01((lamn - 0.58) * 2.6) * spec, cc(spec_col), 0.9)

        # ---- violet spiral arms, painted behind the gantry
        for pts in arms:
            n = len(pts) - 1
            for i in range(n):
                t = i / float(n)
                ax, ay = pts[i]
                bx, by = pts[i + 1]
                wdt = 7.0 * (1.0 - 0.60 * t)
                d = sd_seg(xx, yy, ax, ay, bx, by, 0.0)
                m = np.exp(-(d / wdt) ** 2.0)
                col = mix(C("6C3ED0"), C("8FF0FF"), clamp01(t ** 1.5))
                b.add(m * (0.26 + 0.52 * t), col, 0.85)
                b.add(np.exp(-(d / (wdt * 0.28)) ** 2.0) * (0.26 + 0.46 * t),
                      C("E6DCFF"), 0.8)
                b.add(np.exp(-(d / (wdt * 2.6)) ** 2.0) * 0.14, PURPLE, 0.6)

        # ---- six radial struts, also behind the rings
        u6, v6, _, _, _ = _arm_frame(xx, yy, cx, cy, 6, math.radians(30))
        strut = [(172.0, 16.0), (304.0, 11.0), (304.0, -11.0), (172.0, -16.0)]
        sd6 = sd_poly(u6, v6, strut)
        sm = aa(sd6)
        b.over(aa(sd6 + 2.2), C("05080D"))
        plate(sm, "1A2632", "46607A", 0.45)
        b.over(np.exp(-((sd6 + 0.9) / 0.8) ** 2.0), C("7E9CB2"), 0.45)
        b.over(np.exp(-(v6 / 8.0) ** 2.0) * sm, C("0A121B"), 0.5)
        b.add(np.exp(-(v6 / 1.2) ** 2.0) * sm * 0.40, C("3FA8C8"), 0.5)
        for ru in (206.0, 238.0, 270.0):
            b.over(np.exp(-((u6 - ru) / 1.2) ** 2.0) * sm * 0.75, C("16222E"), 0.5)

        # ================= three concentric gantry rings =================
        # outer ring
        ring_o = aa(sd_ring(xx, yy, cx, cy, 310.0, 13.0))
        plate(ring_o, "1E2A38", "4A6276", 0.5)
        b.over(np.exp(-((r - 322.0) / 1.1) ** 2.0), C("8FB0C6"), 0.5)
        b.over(np.exp(-((r - 298.0) / 1.1) ** 2.0), C("08111A"), 0.9)
        seam8 = np.exp(-((np.abs(((ang / TAU * 8.0) % 1.0) - 0.5) - 0.5) / 0.009) ** 2.0)
        b.over(seam8 * ring_o, C("05090F"), 0.75)
        for k in range(8):
            a0 = k * TAU / 8.0 + TAU / 16.0
            lx = cx + math.cos(a0) * 310.0
            ly = cy + math.sin(a0) * 310.0
            nd = np.exp(-(((xx - lx) ** 2 + (yy - ly) ** 2) / 13.0))
            b.add(clamp01(nd * 0.8), CYAN, 0.85)
            b.over(clamp01(nd * 0.9), C("DCFAFF"), 0.55)
        # mid ring, with violet energy between the plates
        ring_m = aa(sd_ring(xx, yy, cx, cy, 240.0, 12.0))
        plate(ring_m, "202C3A", "526A80", 0.45)
        b.over(np.exp(-((r - 252.0) / 1.0) ** 2.0), C("8FAEC2"), 0.45)
        b.over(np.exp(-((r - 228.0) / 1.0) ** 2.0), C("08111A"), 0.85)
        seam6 = np.exp(-((np.abs(((ang / TAU * 6.0) % 1.0) - 0.5) - 0.5) / 0.011) ** 2.0)
        b.over(seam6 * ring_m, C("05090F"), 0.7)
        # dashed cyan energy ring between the outer and mid gantries
        cy_ring = np.exp(-((r - 284.0) / 1.6) ** 2.0) * seg_mask(
            ang, 16, duty=0.48, phase=0.0, edge=0.03)
        b.add(cy_ring * 0.55, CYAN, 0.75)
        b.add(cy_ring * 0.22, C("DFFBFF"), 0.6)
        pv = np.exp(-((r - 240.0) / 3.4) ** 2.0) * (
            1.0 - seg_mask(ang, 6, duty=0.55, phase=0.0, edge=0.03))
        b.add(pv * 0.75, PURPLE, 0.9)
        b.add(pv * 0.28, C("E0D4FF"), 0.65)
        # inner ring, bright ice-cyan
        ring_i = aa(sd_ring(xx, yy, cx, cy, 166.0, 5.0))
        plate(ring_i, "34465A", "86A3B9", 0.5)
        b.add(np.exp(-((r - 166.0) / 1.9) ** 2.0) * 0.45, CYAN, 0.7)
        b.over(np.exp(-((r - 170.5) / 1.0) ** 2.0), C("CFF8FF"), 0.5)
        for k in range(12):
            a0 = k * TAU / 12.0
            lx = cx + math.cos(a0) * 166.0
            ly = cy + math.sin(a0) * 166.0
            nd = np.exp(-(((xx - lx) ** 2 + (yy - ly) ** 2) / 6.0))
            b.add(clamp01(nd * 0.7), CYAN, 0.75)

        # ================= core: dark well + magenta light =================
        b.over(aa(sd_circle(xx, yy, cx, cy, 112.0)), C("05030C"))
        b.over(aa(sd_circle(xx, yy, cx, cy, 104.0)), C("0A0518"))
        b.over_grad(aa(sd_circle(xx, yy, cx, cy, 96.0)), C("140A24"), C("05030C"),
                    clamp01(1.0 - lamn))
        # event horizon
        hor = np.exp(-((r - 91.0) / 2.4) ** 2.0)
        b.add(hor * 1.0, MAGENTA, 0.95)
        b.over(hor * 0.50, C("FFE0F0"), 0.8)
        # accretion swirl
        for k in range(2):
            pts = _spiral_pts(cx, cy, k * math.pi + 0.4, 86.0, 18.0, 2.5, steps=11)
            for i in range(len(pts) - 1):
                d = sd_seg(xx, yy, pts[i][0], pts[i][1], pts[i + 1][0], pts[i + 1][1], 0.0)
                b.add(np.exp(-(d / 2.2) ** 2.0) * 0.22, C("FF7AB0"), 0.65)
        # hot centre
        b.add(clamp01(np.exp(-(r / 16.0) ** 2.0) * 0.80), MAGENTA, 0.85)
        b.over(clamp01(np.exp(-(r / 7.5) ** 2.0) * 0.95), C("FFF4FA"), 0.85)
        # violet lensing haze around the well
        b.add(np.exp(-(np.maximum(r - 96.0, 0.0) / 44.0) ** 2.0) * 0.16, PURPLE, 0.5)
        # three spokes from the well to the inner ring
        for k in range(3):
            a0 = k * TAU / 3.0 + math.radians(90)
            ca, sa = math.cos(a0), math.sin(a0)
            d = sd_seg(xx, yy, cx + ca * 100.0, cy + sa * 100.0,
                       cx + ca * 162.0, cy + sa * 162.0, 0.0)
            b.over(np.exp(-(d / 3.2) ** 2.0) * 0.30, C("C8B4FF"), 0.6)
            b.add(np.exp(-(d / 2.0) ** 2.0) * 0.45, PURPLE, 0.65)
        return b.to_array()

    def gmask_rim(xx, yy):
        return aa(sd_ring(xx, yy, cx, cy, 310.0, 14.0))

    def solid_rim(xx, yy):
        return aa(sd_ring(xx, yy, cx, cy, 310.0, 13.0))

    def gmask_core(xx, yy):
        r = np.hypot(xx - cx, yy - cy)
        return np.exp(-(np.maximum(r - 60.0, 0.0) / 48.0) ** 2.0)

    def solid_core(xx, yy):
        r = np.hypot(xx - cx, yy - cy)
        return aa(r - 96.0)

    img = make(w, h, fn, ss=ss, glows=[(gmask_rim, 6.0, CYAN, 0.6, solid_rim),
                                       (gmask_rim, 18.0, C("1E6C8C"), 0.32, solid_rim),
                                       (gmask_core, 12.0, MAGENTA, 0.60, solid_core)])
    return save(finish(img, w, h), "singularity_rig.png", w, h)


def build_ring_repel():
    """Repulsion pulse: thin cyan ring + 8 outward spikes (additive, tintable)."""
    w = h = 512
    cx = cy = 256.0
    R = 210.0   # engine maps this radius with RIG_REPEL_RADIUS / 210
    spikes = []
    for k in range(8):
        a0 = k * TAU / 8.0 + TAU / 16.0
        spikes.append((math.cos(a0), math.sin(a0)))

    def fn(xx, yy):
        b = Block(xx.shape)
        r = np.hypot(xx - cx, yy - cy)
        ang = np.arctan2(yy - cy, xx - cx)
        fade = sstep(248.0, 232.0, r)
        core = np.exp(-((r - R) / 1.9) ** 2.0) * fade
        halo = np.exp(-((r - R) / 11.0) ** 2.0) * fade
        b.over(clamp01(core * 0.95), C("E6FEFF"), 1.0)
        b.over(clamp01(core * 0.55), WHITE, 0.9)
        b.add(clamp01(halo * 0.40), CYAN, 0.6)
        # dashed inner echo ring
        dash = np.exp(-((r - (R - 30.0)) / 1.3) ** 2.0) * sstep(
            -0.3, 0.25, np.sin(ang * 24.0)) * fade
        b.over(dash * 0.45, C("BFF4FF"), 0.55)
        # 8 outward spikes: bright ray + soft sheath + hot tip
        for (ca, sa) in spikes:
            p0 = (cx + ca * (R - 3.0), cy + sa * (R - 3.0))
            p1 = (cx + ca * 232.0, cy + sa * 232.0)
            d = sd_seg(xx, yy, p0[0], p0[1], p1[0], p1[1], 0.0)
            along = sstep(R - 4.0, R + 6.0, r)
            m = np.exp(-(d / 1.9) ** 2.0) * sstep(236.0, 216.0, r)
            b.add(clamp01(m * 0.95), C("8FF0FF"), 0.85)
            b.over(clamp01(m * 0.55), C("F0FFFF"), 0.65)
            ray = np.exp(-(d / 0.85) ** 2.0) * sstep(238.0, 214.0, r) * along
            b.add(clamp01(ray * 0.95), C("E6FEFF"), 0.85)
            tip = np.exp(-(((xx - cx - ca * 231.0) ** 2 + (yy - cy - sa * 231.0) ** 2) / 6.0))
            b.add(clamp01(tip * 0.85), C("BFF4FF"), 0.8)
        return b.to_array()

    img = make(w, h, fn, ss=4)
    return save(finish(img, w, h), "ring_repel.png", w, h)


def build_ring_siphon():
    """Siphon: thin violet ring + inward-curling arms (additive, tintable)."""
    w = h = 512
    cx = cy = 256.0
    R = 210.0   # engine maps this radius with RIG_SIPHON_RADIUS / 210
    arms = []
    for k in range(4):
        base = k * TAU / 4.0 + math.radians(45)
        arms.append(_spiral_pts(cx, cy, base, R - 6.0, 92.0, 1.30, steps=22))

    def fn(xx, yy):
        b = Block(xx.shape)
        r = np.hypot(xx - cx, yy - cy)
        ang = np.arctan2(yy - cy, xx - cx)
        fade = sstep(249.0, 233.0, r)
        core = np.exp(-((r - R) / 1.8) ** 2.0) * fade
        halo = np.exp(-((r - R) / 10.5) ** 2.0) * fade
        b.over(clamp01(core * 0.9), C("EDE4FF"), 1.0)
        b.over(clamp01(core * 0.5), WHITE, 0.85)
        b.add(clamp01(halo * 0.38), PURPLE, 0.6)
        # inward spiral arms, thinning as they fall toward the centre
        for pts in arms:
            n = len(pts) - 1
            for i in range(n):
                t = i / float(n)
                ax, ay = pts[i]
                bx, by = pts[i + 1]
                wdt = 4.8 * (1.0 - 0.52 * t)
                d = sd_seg(xx, yy, ax, ay, bx, by, 0.0)
                m = np.exp(-(d / wdt) ** 2.0) * (0.30 + 0.60 * (1.0 - t))
                b.add(clamp01(m), C("D8CCFF"), 0.85)
                b.add(clamp01(np.exp(-(d / (wdt * 0.35)) ** 2.0)
                              * (0.25 + 0.45 * (1.0 - t))), C("F2ECFF"), 0.75)
                b.add(clamp01(np.exp(-(d / (wdt * 2.2)) ** 2.0) * 0.16), C("A88CFF"), 0.55)
        # small inward chevrons on the ring (four gaps)
        for k in range(4):
            a0 = k * TAU / 4.0 + math.radians(45)
            ca, sa = math.cos(a0), math.sin(a0)
            px, py = -sa, ca
            tipx, tipy = cx + ca * (R - 24.0), cy + sa * (R - 24.0)
            hd = np.minimum(
                sd_seg(xx, yy, tipx, tipy, cx + ca * (R - 10.0) + px * 7.0,
                       cy + sa * (R - 10.0) + py * 7.0, 0.9),
                sd_seg(xx, yy, tipx, tipy, cx + ca * (R - 10.0) - px * 7.0,
                       cy + sa * (R - 10.0) - py * 7.0, 0.9))
            b.add(clamp01(np.exp(-(hd / 1.1) ** 2.0) * 0.85), C("CDBBFF"), 0.8)
        # faint dashed echo just inside the ring
        dash = np.exp(-((r - (R - 17.0)) / 1.2) ** 2.0) * sstep(
            -0.35, 0.2, np.sin(ang * 28.0)) * fade
        b.add(clamp01(dash * 0.35), PURPLE, 0.5)
        return b.to_array()

    img = make(w, h, fn, ss=4)
    return save(finish(img, w, h), "ring_siphon.png", w, h)


def build_pylon():
    """Twin relay station: hex dish + three prisms, amber bands, cyan slits."""
    w = h = 512
    ss = 3
    cx = cy = 256.0
    Rd = 150.0
    tex = noise_tex(w, h, 22.0, 2, seed=863, res=384)

    def fn(xx, yy):
        b = Block(xx.shape)
        dx = xx - cx
        dy = yy - cy
        r = np.sqrt(dx * dx + dy * dy)
        ang = np.arctan2(dy, dx)
        lam = clamp01(0.5 - (dx / 256.0 * 0.42 + dy / 256.0 * 0.58))
        grain = tex.at(xx / w, yy / h)
        lamn = clamp01(lam * (0.92 + 0.12 * grain))

        def cc(v):
            return C(v) if isinstance(v, str) else np.asarray(v, np.float32)

        def plate(mask, lo, hi, spec=0.5, spec_col="A6C2D6"):
            b.over(mask, C("060A10"))
            b.over_grad(mask, cc(lo), cc(hi), clamp01(1.0 - lamn))
            b.add(mask * clamp01((lamn - 0.58) * 2.6) * spec, cc(spec_col), 0.9)

        # ---- hex dish body
        hexd = sd_hex(xx, yy, cx, cy, Rd, math.radians(30))
        b.over(aa(hexd + 4.0), C("05080D"))
        b.over_grad(aa(hexd), C("16222E"), C("0C141D"), clamp01(lamn))
        b.over(np.exp(-((hexd + 1.2) / 1.4) ** 2.0), C("7E9CB2"), 0.55)
        b.over(np.exp(-((hexd + 0.4) / 0.6) ** 2.0) * 0.6, C("B8D2E4"), 0.5)
        hx2 = sd_hex(xx, yy, cx, cy, Rd * 0.76, math.radians(30))
        plate(aa(hx2), "2A3A4A", "627E96", 0.5)
        b.over(np.exp(-((hx2 + 0.9) / 1.0) ** 2.0), C("9CBCCF"), 0.45)
        b.over(np.exp(-((hx2 - 1.2) / 1.1) ** 2.0) * 0.55, C("05090E"), 0.6)
        # radial seams + amber rim strip
        seam = np.exp(-((np.abs(((ang / TAU * 12.0) % 1.0) - 0.5) - 0.5) / 0.012) ** 2.0)
        b.over(seam * aa(hexd - 6.0) * aa(hx2 + 5.0) * 0.55, C("05090F"), 0.5)
        b.over(np.exp(-((hexd + 6.0) / 1.5) ** 2.0), C("8A5A18"), 0.7)
        for k in range(6):
            a0 = k * TAU / 6.0 + math.radians(60)
            lx = cx + math.cos(a0) * (Rd * 0.88)
            ly = cy + math.sin(a0) * (Rd * 0.88)
            nd = np.exp(-(((xx - lx) ** 2 + (yy - ly) ** 2) / 22.0))
            b.add(clamp01(nd * 0.85), AMBER, 0.8)

        # ---- three antenna prisms (up, lower-left, lower-right)
        u3, v3, r3, _, _ = _arm_frame(xx, yy, cx, cy, 3, math.radians(-90))
        prism = [(116.0, 23.0), (198.0, 11.0), (208.0, 6.0), (208.0, -6.0),
                 (198.0, -11.0), (116.0, -23.0)]
        pd = sd_poly(u3, v3, prism)
        pm = aa(pd)
        plate(pm, "2A3A4A", "64809A", 0.55)
        b.over(np.exp(-((pd + 0.9) / 1.0) ** 2.0), C("A2C0D2"), 0.5)
        # dark channel down the middle + amber light strip
        b.over(np.exp(-(v3 / 3.2) ** 2.0) * pm, C("070C13"), 0.7)
        b.add(np.exp(-(v3 / 1.5) ** 2.0) * pm * 0.85, AMBER, 0.9)
        b.add(np.exp(-(v3 / 0.6) ** 2.0) * pm * 0.45, C("FFE8BE"), 0.7)
        # prism ribs
        for ru in (136.0, 160.0, 184.0):
            b.over(np.exp(-((u3 - ru) / 1.1) ** 2.0) * pm, C("0A121B"), 0.55)
        # tip cap + cyan slit at the base
        tip = aa(sd_circle(u3, v3, 204.0, 0.0, 7.0)) * pm
        b.over(tip, C("16222E"))
        b.add(np.exp(-(np.hypot(u3 - 206.0, v3) / 4.5) ** 2.0) * pm * 0.9, CYAN, 0.9)
        base = aa(sd_box(u3, v3, 120.0, 0.0, 5.0, 15.0, 2.0)) * pm
        b.add(base * 0.85, CYAN, 0.9)
        b.over(base * 0.6, C("DFFBFF"), 0.7)

        # ---- twin relay pods (+X / -X) and their cyan link
        for sgn in (-1.0, 1.0):
            px = cx + sgn * 92.0
            pod = sd_hex(xx, yy, px, cy, 36.0, math.radians(30))
            b.over(aa(pod + 3.0), C("05080D"))
            plate(aa(pod), "2C3C4E", "6A869E", 0.5)
            b.over(np.exp(-((pod + 0.7) / 0.8) ** 2.0), C("A8C6D8"), 0.5)
            dome = aa(sd_circle(xx, yy, px, cy, 20.0))
            b.over(dome, C("0B1219"))
            b.add(np.exp(-(np.hypot(xx - px, yy - cy) / 13.0) ** 2.0) * 0.9,
                  CYAN, 0.85)
            b.over(np.exp(-(np.hypot(xx - px, yy - cy) / 6.5) ** 2.0) * 0.95,
                   C("E8FEFF"), 0.8)
            b.over(np.exp(-((np.hypot(xx - px, yy - cy) - 20.0) / 1.2) ** 2.0),
                   AMBER, 0.75)
        b.add(np.exp(-((np.abs(dy) - 0.0) / 1.4) ** 2.0)
              * sstep(56.0, 72.0, np.abs(dx)) * sstep(86.0, 74.0, np.abs(dx)) * 0.55,
              CYAN, 0.6)

        # ---- central hub
        hub = sd_hex(xx, yy, cx, cy, 52.0, math.radians(30))
        b.over(aa(hub + 3.0), C("05080D"))
        b.over(aa(hub), C("101A24"))
        plate(aa(hub - 3.0), "2E3E50", "6E8AA2", 0.55)
        b.over(np.exp(-((hub + 1.0) / 1.2) ** 2.0), AMBER, 0.85)
        b.over(np.exp(-((hub + 1.0) / 0.5) ** 2.0), C("FFE9C4"), 0.55)
        core = np.exp(-(r / 17.0) ** 2.0)
        b.add(clamp01(core * 1.05), CYAN, 0.95)
        b.over(clamp01(core * 1.1), C("F0FEFF"), 0.85)
        b.add(clamp01(np.exp(-(r / 34.0) ** 2.0) * 0.35), CYAN, 0.5)
        return b.to_array()

    def solid(xx, yy):
        return aa(sd_hex(xx, yy, cx, cy, Rd, math.radians(30)))

    def gmask(xx, yy):
        return aa(sd_hex(xx, yy, cx, cy, Rd + 2.0, math.radians(30)))

    img = make(w, h, fn, ss=ss, glows=[(gmask, 6.0, AMBER, 0.5, solid),
                                       (gmask, 20.0, C("8C5A16"), 0.35, solid)])
    return save(finish(img, w, h), "pylon.png", w, h)


def build_guard_orb():
    """Interceptor guard orb: pale cyan sphere + thin ring, tintable."""
    w = h = 96
    cx = cy = 48.0
    R = 29.0
    L = norm3((-0.46, -0.56, 0.69))

    def fn(xx, yy):
        b = Block(xx.shape)
        r = np.hypot(xx - cx, yy - cy)
        fade = sstep(46.0, 39.0, r)
        # ---- sphere with a cool rim
        dx = (xx - cx) / R
        dy = (yy - cy) / R
        d2 = dx * dx + dy * dy
        nz = np.sqrt(np.clip(1.0 - d2, 0.0, 1.0))
        lam = clamp01(dx * L[0] + dy * L[1] + nz * L[2])
        ball = aa(np.sqrt(d2) * R - R)
        col = mix(C("1C5C74"), C("CDEFFA"), clamp01(lam * 1.18))
        col = mix(col, C("FFFFFF"), clamp01((lam - 0.82) * 4.2))
        b.rgb = b.rgb * (1.0 - ball)[..., None] + col * ball[..., None]
        b.a = clamp01(ball + b.a * (1.0 - ball))
        b.over(np.exp(-((np.sqrt(d2) * R - R + 0.9) / 1.3) ** 2.0) * ball,
               C("BFF4FF"), 0.7)
        spec = np.exp(-(((xx - cx + 8.0) / 4.6) ** 2 + ((yy - cy + 8.6) / 4.1) ** 2))
        b.over(clamp01(spec) * ball, WHITE, 0.9)
        # ---- thin equatorial ring
        ring = np.exp(-((r - 37.0) / 1.05) ** 2.0) * fade
        b.over(ring * 0.9, C("CFF8FF"), 0.95)
        b.over(ring * 0.5, WHITE, 0.7)
        b.add(ring * 0.85, CYAN, 0.8)
        # ---- bright core (kept small so the orb still reads as a sphere)
        b.add(clamp01(np.exp(-(r / 7.5) ** 2.0) * 0.55), WHITE, 0.9)
        b.over(clamp01(np.exp(-(r / 4.4) ** 2.0) * 0.55), C("FFFFFF"), 0.8)
        b.add(clamp01(np.exp(-(r / 19.0) ** 2.0) * 0.22), CYAN, 0.45)
        return b.to_array()

    img = make(w, h, fn, ss=4)
    return save(finish(img, w, h), "guard_orb.png", w, h)


def build_missile_booster():
    """Second-stage heavy torpedo: thicker hull, twin bells, white guide ring."""
    w, h = 64, 28
    cy = 14.0
    body_dark = C("501505")
    body = C("FF6A2E")
    hot = C("FFD08A")
    white = C("EAF7FF")
    verts = [(11.0, 6.2), (15.0, 4.6), (40.0, 4.6), (46.0, 6.8),
             (61.0, 14.0), (46.0, 21.2), (40.0, 23.4), (15.0, 23.4), (11.0, 21.8)]
    fin_t = [(14.0, 5.2), (26.0, 1.6), (27.0, 5.6)]
    fin_b = [(14.0, 22.8), (26.0, 26.4), (27.0, 22.4)]

    def fn(xx, yy):
        b = Block(xx.shape)
        d = sd_poly(xx, yy, verts)
        body_m = aa(d)
        t = clamp01((yy - 4.0) / 20.0)
        b.over_grad(body_m, body, body_dark, t)
        # fatter blast shield / fins
        b.over(aa(sd_poly(xx, yy, fin_t)), C("E8481F"), 0.95)
        b.over(aa(sd_poly(xx, yy, fin_b)), C("B03012"), 0.95)
        # nose warming to amber
        nt = clamp01((xx - 44.0) / 17.0)
        nose = body_m * aa(sd_seg(xx, yy, 46.0, cy, 61.0, cy, 6.4))
        b.over(nose, hot, 0.55 * nt)
        # top highlight + belly shadow + panel seams (heavier than missile.png)
        b.over(aa(sd_seg(xx, yy, 15.0, 7.4, 44.0, 7.4, 1.1)), C("FFE0B8"), 0.8)
        b.over(aa(sd_seg(xx, yy, 14.0, 21.4, 44.0, 21.4, 1.3)), C("2A0A02"), 0.55)
        b.over(aa(sd_seg(xx, yy, 34.0, 5.2, 34.0, 22.8, 0.55)), C("5A1A06"), 0.5)
        b.over(aa(sd_seg(xx, yy, 26.0, 5.2, 26.0, 22.8, 0.55)), C("5A1A06"), 0.35)
        # white guide ring amidships
        gd = np.abs(np.hypot((xx - 32.0) / 1.0, (yy - cy) / 1.36) - 4.6) - 0.24
        gm = aa(gd) * body_m
        b.over(gm * 0.80, white, 0.8)
        b.add(gm * 0.30, C("BFF4FF"), 0.5)
        # machined seam bands across the hull
        for bx in (21.0, 43.0):
            b.over(aa(np.abs(xx - bx) - 0.30) * body_m * 0.35, C("5A1A06"), 0.6)
        # twin nozzles
        for ny in (9.6, 18.4):
            nd = sd_box(xx, yy, 12.4, ny, 2.2, 2.6, 0.9)
            b.over(aa(nd), C("1E0700"), 0.9)
            b.over(np.exp(-((nd + 0.8) / 1.1) ** 2.0), C("8A2A0C"), 0.6)
            fl = np.exp(-(((xx - 7.4) / 2.6) ** 2 + ((yy - ny) / 2.1) ** 2))
            b.add(clamp01(fl * 1.5), hot, 1.0)
            b.over(clamp01(fl * 1.2), C("FFF0C8"), 0.55)
        b.add(clamp01(body_m * 0.26), body, 0.55)
        return b.to_array()

    img = make(w, h, fn, ss=4)
    return save(finish(img, w, h), "missile_booster.png", w, h)


def build_mine():
    """Slow drifting mine: dark sphere, six magenta spikes, hot core."""
    w = h = 56
    cx = cy = 28.0
    R = 14.0
    L = norm3((-0.44, -0.56, 0.70))

    def fn(xx, yy):
        b = Block(xx.shape)
        dx = xx - cx
        dy = yy - cy
        r = np.hypot(dx, dy)
        fade = sstep(26.0, 22.0, r)
        # ---- six spikes
        for k in range(6):
            a0 = k * TAU / 6.0 + math.radians(15)
            ca, sa = math.cos(a0), math.sin(a0)
            d = sd_seg(xx, yy, cx + ca * (R - 1.0), cy + sa * (R - 1.0),
                       cx + ca * 22.6, cy + sa * 22.6, 0.0)
            taper = sstep(22.8, 15.0, r)
            m = np.exp(-(d / 1.25) ** 2.0) * taper * fade
            b.over(clamp01(m * 0.85), C("6E1236"), 0.9)
            b.add(clamp01(m * 0.75), MAGENTA, 0.8)
            tp = np.exp(-(((xx - cx - ca * 22.4) ** 2 + (yy - cy - sa * 22.4) ** 2) / 5.0))
            b.add(clamp01(tp * 0.9) * fade, C("FF9AC0"), 0.8)
        # ---- hull
        dxn = dx / R
        dyn = dy / R
        d2 = dxn * dxn + dyn * dyn
        nz = np.sqrt(np.clip(1.0 - d2, 0.0, 1.0))
        lam = clamp01(dxn * L[0] + dyn * L[1] + nz * L[2])
        ball = aa(np.sqrt(d2) * R - R)
        col = mix(C("0A0E16"), C("3C4A5C"), clamp01(lam * 1.15))
        col = mix(col, C("6E8094"), clamp01((lam - 0.74) * 3.4))
        b.rgb = b.rgb * (1.0 - ball)[..., None] + col * ball[..., None]
        b.a = clamp01(ball + b.a * (1.0 - ball))
        b.over(np.exp(-((np.sqrt(d2) * R - R + 0.8) / 1.2) ** 2.0) * ball,
               C("7E94A8"), 0.55)
        # armour plates
        for k in range(3):
            a0 = k * TAU / 3.0 + math.radians(30)
            ca, sa = math.cos(a0), math.sin(a0)
            b.over(np.exp(-(sd_seg(xx, yy, cx + ca * 3.0, cy + sa * 3.0,
                                   cx + ca * R, cy + sa * R, 0.0) / 0.8) ** 2.0) * ball,
                   C("05080D"), 0.5)
        # ---- hot magenta core + pulse ring
        b.add(clamp01(np.exp(-(r / 6.4) ** 2.0) * 1.1), MAGENTA, 0.95)
        b.over(clamp01(np.exp(-(r / 3.4) ** 2.0) * 1.05), C("FFD6E8"), 0.9)
        b.over(np.exp(-((r - 7.6) / 0.75) ** 2.0) * 0.85, C("FF7AB0"), 0.8)
        spec = np.exp(-(((xx - cx + 4.0) / 2.6) ** 2 + ((yy - cy + 4.2) / 2.4) ** 2))
        b.over(clamp01(spec) * ball * 0.32, C("DCE8F4"), 0.5)
        return b.to_array()

    img = make(w, h, fn, ss=4)
    return save(finish(img, w, h), "mine.png", w, h)


# ==========================================================================
# explosions (8 frames)
# ==========================================================================
EXP_TEX = [noise_tex(256, 256, 5.0, 4, seed=610, res=256, norm=True),
           noise_tex(256, 256, 12.0, 3, seed=631, res=256, norm=True),
           noise_tex(256, 256, 2.5, 4, seed=653, res=256, norm=True)]


def _build_explosion(i):
    w = h = 256
    ss = 4
    cx = cy = 128.0
    t = i / 7.0
    Rf = 13.0 + 100.0 * t ** 0.55
    ringR = Rf * 1.12 + 6.0
    core_amp = max(0.0, 1.0 - 3.2 * t)
    ring_amp = sstep(0.06, 0.22, t) * (1.0 - sstep(0.40, 0.90, t))
    smoke_amp = sstep(0.32, 0.95, t)
    fade = 1.0 - 0.84 * t ** 1.5
    ta, tb, tc = EXP_TEX

    def fn(xx, yy):
        b = Block(xx.shape)
        r = np.hypot(xx - cx, yy - cy)
        u = xx / w
        v = yy / h
        n1 = ta.at(u + 0.11 * i, v + 0.07 * i)
        n2 = tb.at(u + 0.19 * i, v - 0.13 * i)
        n3 = tc.at(u - 0.05 * i, v + 0.09 * i)

        # ---- smoke shell (behind the fire, visible once the fire cools)
        if smoke_amp > 0.01:
            rs = 44.0 + 84.0 * t
            cloud = sstep(1.04, 0.10, r / (rs * (0.78 + 0.42 * n3)))
            cloud = clamp01(cloud * (0.40 + 1.05 * n1)) * smoke_amp
            b.over(cloud * 0.70, C("6E6678"), 1.0)
            b.over(cloud * 0.55 * n2, C("2E2A3C"), 1.0)
            # warm under-glow while the fire is still hot
            warm = clamp01(1.0 - t * 2.0)
            b.over(cloud * 0.55 * warm, C("B4562A"), 1.0)

        # ---- fireball
        if t < 0.92:
            q = r / (Rf * (0.84 + 0.32 * (n1 - 0.5)))
            fire = clamp01(1.0 - sstep(0.70, 1.0, q)) * (1.0 - 0.35 * smoke_amp)
            hot = clamp01(1.0 - q * 1.3)
            col = ramp([(0.0, C("FFFDF2")), (0.35, C("FFD87E")), (0.62, C("FF8A2E")),
                        (0.85, C("D84A14")), (1.0, C("6E1A08"))], clamp01(q))
            b.over(clamp01(fire), col, 1.0)
            b.add(clamp01(fire * hot * 1.1), C("FFEBBE"), 0.9)
            b.over(clamp01(fire * clamp01((n2 - 0.60) * 2.4) * 0.6), C("8A2A0A"), 0.75)

        # ---- shock ring
        if ring_amp > 0.01:
            wid = 2.2 + 8.0 * t
            ring = np.exp(-((r - ringR) / wid) ** 2.0) * ring_amp
            b.over(clamp01(ring), C("FFE8C0"), 0.95)
            b.over(clamp01(ring) * 0.9, WHITE, 0.65)
            b.add(clamp01(ring * 0.8), C("FFB347"), 0.8)

        # ---- core flash + rays
        if core_amp > 0.01:
            core = np.exp(-(r / (11.0 + 22.0 * t)) ** 2.0) * core_amp
            b.over(clamp01(core * 1.5), WHITE, 1.0)
            b.add(clamp01(core * 1.3), C("FFF6DC"), 0.95)
            ang = np.arctan2(yy - cy, xx - cx)
            th = (ang / TAU) % 1.0
            rays = np.exp(-(r / 95.0)) * clamp01((noise1(th, 12.0, seed=71) - 0.5) * 3.0)
            b.add(clamp01(rays * core_amp * 0.7), C("FFE9B8"), 0.8)

        f = np.float32(fade)
        b.a = b.a * f
        b.rgb = b.rgb * f
        return b.to_array()

    img = make(w, h, fn, ss=ss)
    return save(finish(img, w, h), "explosion_%d.png" % i, w, h)


def build_explosion_0():
    return _build_explosion(0)


def build_explosion_1():
    return _build_explosion(1)


def build_explosion_2():
    return _build_explosion(2)


def build_explosion_3():
    return _build_explosion(3)


def build_explosion_4():
    return _build_explosion(4)


def build_explosion_5():
    return _build_explosion(5)


def build_explosion_6():
    return _build_explosion(6)


def build_explosion_7():
    return _build_explosion(7)


# ==========================================================================
# nebulae (tileable)
# ==========================================================================
def _build_nebula(name, deep, mid, bright, seed):
    w = h = 1024
    ss = 1
    ta = noise_tex(w, h, 2.0, 5, seed=seed, wrap=True, res=512, norm=True)
    tb = noise_tex(w, h, 3.5, 4, seed=seed + 1, wrap=True, res=512, norm=True)
    tc = noise_tex(w, h, 8.0, 3, seed=seed + 2, wrap=True, res=512, norm=True)
    td = noise_tex(w, h, 16.0, 2, seed=seed + 3, wrap=True, res=512, norm=True)

    def fn(xx, yy):
        b = Block(xx.shape)
        u = xx / w
        v = yy / h
        wx = ta.at(u, v) - 0.5
        wy = tb.at(u, v) - 0.5
        u2 = u + 0.13 * wx
        v2 = v + 0.13 * wy
        base = ta.at(u2, v2)
        fil = tc.at(u2, v2)
        fine = td.at(u2, v2)
        d = clamp01(base) ** 1.35
        f = clamp01((fil - 0.38) / 0.62) ** 1.2
        g = clamp01((fine - 0.55) / 0.45)
        dens = clamp01(d * 0.90 + f * 0.60 + g * 0.15)
        col = mix(deep, mid, clamp01(dens * 1.35))
        col = mix(col, bright, clamp01((dens - 0.30) * 1.6))
        a = clamp01(dens ** 0.75 * 122.0)
        b.over(a / 255.0, col, 1.0)
        b.add(clamp01(dens ** 2.0 * 0.45), bright, 0.55)
        return b.to_array()

    img = make(w, h, fn, ss=ss)
    return save(finish(img, w, h), name, w, h)


def build_nebula_1():
    return _build_nebula("nebula_1.png", C("04141E"), C("3FD8F8"), C("D8FFFF"), 811)


def build_nebula_2():
    return _build_nebula("nebula_2.png", C("0A0520"), C("8B6AF0"), C("E0D4FF"), 823)


def build_nebula_3():
    return _build_nebula("nebula_3.png", C("1C0416"), C("E04A8A"), C("FFC0D8"), 837)


# ==========================================================================
# star fields / dust (tileable)
# ==========================================================================
def _splat(acc, x, y, sigma, amp, col):
    H, W = acc.shape[:2]
    R = int(sigma * 3.2) + 1
    ys = np.arange(y - R, y + R + 1)
    xs = np.arange(x - R, x + R + 1)
    dy = (ys - y).astype(np.float32)
    dx = (xs - x).astype(np.float32)
    g = np.exp(-((dx[None, :] ** 2 + dy[:, None] ** 2) / (2.0 * sigma * sigma)))
    yy = ys % H
    xx = xs % W
    add = g[..., None] * (np.asarray(col, np.float32) * amp)
    if acc.ndim == 2:
        add = add[..., 0]
    acc[np.ix_(yy, xx)] += add


def _starfield(name, w, h, ss, count, seed, rmin, rmax, amin, amax, flares, wrap=True):
    W, H = int(w * ss), int(h * ss)
    rng = np.random.default_rng(seed)
    rgb = np.zeros((H, W, 3), np.float32)
    alp = np.zeros((H, W), np.float32)
    cols = [WHITE, ICE, C("BFF0FF"), C("D8CCFF"), C("FFE8D0"), C("9FE8FF")]
    for _ in range(count):
        x = rng.uniform(0, W)
        y = rng.uniform(0, H)
        rad = rng.uniform(rmin, rmax) * ss
        amp = rng.uniform(amin, amax)
        col = cols[rng.integers(0, len(cols))]
        _splat(rgb, int(x), int(y), max(0.6, rad * 0.62), amp, col)
        _splat(alp, int(x), int(y), max(0.6, rad * 0.62), amp / 255.0, np.array([255.0], np.float32))
    # bright stars with a cross flare
    for _ in range(flares):
        x = rng.uniform(0, W)
        y = rng.uniform(0, H)
        rad = rng.uniform(rmax * 1.2, rmax * 2.0) * ss
        amp = rng.uniform(amax * 0.9, 255.0)
        col = cols[rng.integers(0, len(cols))]
        _splat(rgb, int(x), int(y), max(0.9, rad * 0.55), amp, col)
        _splat(alp, int(x), int(y), max(0.9, rad * 0.55), amp / 255.0, np.array([255.0], np.float32))
        # cross flare: two elongated gaussians
        R = int(rad * 5.0) + 1
        ys = np.arange(int(y) - R, int(y) + R + 1)
        xs = np.arange(int(x) - R, int(x) + R + 1)
        dy = (ys - int(y)).astype(np.float32)
        dx = (xs - int(x)).astype(np.float32)
        gy = np.exp(-(dy / max(1.0, rad * 0.5)) ** 2.0)
        gx = np.exp(-(dx / max(1.0, rad * 0.5)) ** 2.0)
        hbar = np.exp(-(dy[:, None] / max(0.8, rad * 0.30)) ** 2.0) * np.exp(
            -(dx[None, :] / (rad * 4.2)) ** 2.0)
        vbar = np.exp(-(dx[None, :] / max(0.8, rad * 0.30)) ** 2.0) * np.exp(
            -(dy[:, None] / (rad * 4.2)) ** 2.0)
        flare = np.maximum(hbar, vbar) * (amp / 255.0) * 0.55
        yy = ys % H
        xx = xs % W
        rgb[np.ix_(yy, xx)] += flare[..., None] * col
        alp[np.ix_(yy, xx)] = np.maximum(alp[np.ix_(yy, xx)], flare)
    arr = np.empty((H, W, 4), np.uint8)
    arr[..., :3] = np.clip(rgb, 0, 255).astype(np.uint8)
    arr[..., 3] = np.clip(alp * 255.0, 0, 255).astype(np.uint8)
    img = Image.fromarray(arr, "RGBA")
    return save(finish(img, w, h), name, w, h)


def build_bg_stars_far():
    return _starfield("bg_stars_far.png", 512, 512, 4, 520, 21, 0.35, 1.0, 16, 74, 0)


def build_bg_stars_near():
    return _starfield("bg_stars_near.png", 512, 512, 4, 92, 33, 0.6, 1.5, 60, 210, 14)


def build_dust():
    w = h = 256
    ss = 2
    ta = noise_tex(w, h, 3.0, 4, seed=741, wrap=True, res=256)

    def fn(xx, yy):
        b = Block(xx.shape)
        u = xx / w
        v = yy / h
        n = ta.at(u, v)
        fog = clamp01((n - 0.35) / 0.65) ** 2.0 * 0.055
        b.over(fog, C("8FD8F0"), 1.0)
        return b.to_array()

    img = make(w, h, fn, ss=ss)
    # grains
    W, H = w * ss, h * ss
    rng = np.random.default_rng(99)
    arr = np.asarray(img).astype(np.float32)
    rgb = arr[..., :3]
    alp = arr[..., 3]
    for _ in range(420):
        x = rng.uniform(0, W)
        y = rng.uniform(0, H)
        rad = rng.uniform(0.35, 0.9) * ss
        amp = rng.uniform(10, 34)
        _splat(rgb, int(x), int(y), max(0.5, rad), amp, C("CFEFFF"))
        _splat(alp[..., None], int(x), int(y), max(0.5, rad), amp / 255.0,
               np.array([255.0], np.float32))
    out = np.empty((H, W, 4), np.uint8)
    out[..., :3] = np.clip(rgb, 0, 255).astype(np.uint8)
    out[..., 3] = np.clip(alp, 0, 255).astype(np.uint8)
    img = Image.fromarray(out, "RGBA")
    return save(finish(img, w, h), "dust.png", w, h)


# ==========================================================================
# title background
# ==========================================================================
def build_title_bg():
    w, h = 1920, 1080
    ss = 1.5
    W, H = int(w * ss), int(h * ss)
    ta = noise_tex(w, h, 2.2, 5, seed=1301, res=512, norm=True)
    tb = noise_tex(w, h, 4.5, 4, seed=1319, res=512, norm=True)
    tc = noise_tex(w, h, 11.0, 3, seed=1337, res=512, norm=True)
    # planet limb: big sphere in the lower right
    px, py, PR = 2020.0, 1660.0, 1260.0
    ship_cx, ship_cy, ship_s = 470.0, 640.0, 0.62
    ship_pts = [(ship_cx + (x - 64.0) * ship_s, ship_cy + (y - 64.0) * ship_s)
                for (x, y) in SHIP_HULL]
    Li = norm3((-0.55, -0.52, 0.65))

    def fn(xx, yy):
        b = Block(xx.shape)
        u = xx / w
        v = yy / h
        # ---- deep space gradient
        g = clamp01(yy / h)
        base = mix(C("05070F"), C("080B18"), g)
        b.over(np.ones_like(xx), base, 1.0)
        # ---- nebula clouds
        wx = ta.at(u, v) - 0.5
        wy = tb.at(u, v) - 0.5
        u2 = u + 0.10 * wx
        v2 = v + 0.10 * wy
        n1 = ta.at(u2, v2)
        n2 = tc.at(u2, v2)
        cloud = clamp01((n1 - 0.42) / 0.58) ** 1.5
        fil = clamp01((n2 - 0.5) / 0.5) ** 2.0
        dens = clamp01(cloud * 0.8 + fil * 0.4)
        # cyan nebula upper-left, purple lower-middle, magenta far right
        cyc = np.exp(-(((u - 0.22) / 0.30) ** 2 + ((v - 0.30) / 0.34) ** 2))
        pur = np.exp(-(((u - 0.58) / 0.34) ** 2 + ((v - 0.62) / 0.34) ** 2))
        mag = np.exp(-(((u - 0.88) / 0.22) ** 2 + ((v - 0.35) / 0.30) ** 2))
        col = C("05070F") * 1.0
        col = col + C("1E8CB4") * (dens * cyc * 0.55)[..., None]
        col = col + C("6A46C8") * (dens * pur * 0.50)[..., None]
        col = col + C("B0225E") * (dens * mag * 0.42)[..., None]
        col = col + C("8FF0FF") * (clamp01(fil) * cyc * 0.20)[..., None]
        b.rgb = col
        b.a = np.ones_like(xx)
        # ---- big planet limb
        dx = (xx - px) / PR
        dy = (yy - py) / PR
        d2 = dx * dx + dy * dy
        rr = np.sqrt(d2) * PR
        inside = aa(rr - PR)
        nz = np.sqrt(np.clip(1.0 - d2, 0.0, 1.0))
        lam = clamp01(dx * Li[0] + dy * Li[1] + nz * Li[2])
        shade = 0.05 + 1.0 * lam ** 0.9
        band = 0.5 + 0.5 * np.sin(dy * 26.0 + n1 * 4.0)
        alb = 0.42 + 0.42 * band + 0.34 * (n2 - 0.5)
        pcol = mix(C("1A120C"), C("5E422C"), clamp01(alb))
        pcol = mix(pcol, C("9C7048"), clamp01((alb - 0.58) * 2.2))
        pcol = pcol * shade[..., None]
        dark = clamp01(1.0 - lam * 2.0)
        pcol = pcol * (1.0 - dark * 0.8)[..., None] + C("070B16") * (dark * 0.6)[..., None]
        limb = np.exp(-np.abs(rr - PR) / 9.0)
        pcol = pcol + C("39E6FF") * (limb * 0.55)[..., None]
        pcol = pcol + C("DFFBFF") * (np.exp(-np.abs(rr - PR) / 3.0) * 0.45)[..., None]
        fres = clamp01(1.0 - nz) ** 3.0
        pcol = pcol + C("2FA8C8") * (fres * 0.10)[..., None]
        b.rgb = b.rgb * (1.0 - inside)[..., None] + pcol * inside[..., None]
        # atmosphere halo outside the limb
        halo = np.exp(-np.maximum(rr - PR, 0.0) / 30.0) * 0.35
        b.rgb = b.rgb + C("2FB8D8")[None, None, :] * halo[..., None]
        # ---- gravity arcs around the planet
        for (ar, alp, dash) in ((PR + 34.0, 0.13, 160.0), (PR + 96.0, 0.08, 120.0),
                                (PR + 176.0, 0.05, 90.0)):
            e = np.sqrt(((xx - px) / (ar * 1.06)) ** 2 + ((yy - py) / (ar * 0.94)) ** 2)
            ang = np.arctan2((yy - py) / 0.94, (xx - px) / 1.06)
            dashm = sstep(-0.4, 0.2, np.sin(ang * dash))
            arc = np.exp(-((e - 1.0) / 0.0016) ** 2.0) * dashm * alp
            b.rgb = b.rgb + C("5FE8FF")[None, None, :] * arc[..., None]
        # ---- distant ship silhouette
        sd = sd_poly(xx, yy, ship_pts)
        sm = aa(sd)
        b.rgb = b.rgb * (1.0 - sm)[..., None] + C("06090F")[None, None, :] * sm[..., None]
        b.rgb = b.rgb + C("39E6FF")[None, None, :] * (
            np.exp(-((np.abs(sd) - 0.5) / 0.7) ** 2.0) * 0.5)[..., None]
        # engine glow + trail
        ex = ship_cx - 36.0 * ship_s
        eng = np.exp(-(((xx - ex) / 5.0) ** 2 + ((yy - ship_cy) / 3.2) ** 2))
        b.rgb = b.rgb + C("8FF6FF")[None, None, :] * (clamp01(eng) * 0.8)[..., None]
        trail = np.exp(-(((xx - ex + 60.0) / 55.0) ** 2 + ((yy - ship_cy) / 2.0) ** 2))
        b.rgb = b.rgb + C("39E6FF")[None, None, :] * (trail * 0.35)[..., None]
        # ---- vignette
        vx = (u - 0.5) * 2.0
        vy = (v - 0.5) * 2.0
        vig = clamp01((np.sqrt(vx * vx * 0.85 + vy * vy) - 0.55) / 1.0)
        b.rgb = b.rgb * (1.0 - vig * 0.55)[..., None]
        return b.to_array()

    img = render(w, h, fn, ss=ss)
    # ---- stars on top
    rng = np.random.default_rng(2027)
    arr = np.asarray(img).astype(np.float32)
    rgb = arr[..., :3]
    cols = [WHITE, ICE, C("BFF0FF"), C("D8CCFF"), C("FFE8D0")]
    for _ in range(430):
        x = rng.uniform(0, W)
        y = rng.uniform(0, H)
        rad = rng.uniform(0.45, 1.25) * ss
        amp = rng.uniform(14, 62)
        _splat(rgb, int(x), int(y), max(0.6, rad * 0.62), amp, cols[rng.integers(0, 5)])
    for _ in range(30):
        x = rng.uniform(0, W)
        y = rng.uniform(0, H)
        rad = rng.uniform(1.0, 1.8) * ss
        amp = rng.uniform(80, 170)
        col = cols[rng.integers(0, 5)]
        _splat(rgb, int(x), int(y), max(0.9, rad * 0.55), amp, col)
        R = int(rad * 5.0) + 1
        ys = np.arange(int(y) - R, int(y) + R + 1)
        xs = np.arange(int(x) - R, int(x) + R + 1)
        dy = (ys - int(y)).astype(np.float32)
        dx = (xs - int(x)).astype(np.float32)
        hbar = np.exp(-(dy[:, None] / max(0.8, rad * 0.3)) ** 2.0) * np.exp(
            -(dx[None, :] / (rad * 4.0)) ** 2.0)
        vbar = np.exp(-(dx[None, :] / max(0.8, rad * 0.3)) ** 2.0) * np.exp(
            -(dy[:, None] / (rad * 4.0)) ** 2.0)
        rgb[np.ix_(ys % H, xs % W)] += np.maximum(hbar, vbar)[..., None] * col * 0.5
    out = np.empty((H, W, 4), np.uint8)
    out[..., :3] = np.clip(rgb, 0, 255).astype(np.uint8)
    out[..., 3] = 255
    img = Image.fromarray(out, "RGBA")
    return save(finish(img, w, h), "title_bg.png", w, h)


# ==========================================================================
# manifest expectations
# ==========================================================================
EXPECTED = {
    "ship.png": (128, 128), "ship_glow.png": (160, 160), "engine_glow.png": (96, 96),
    "missile.png": (64, 28), "missile_warn.png": (96, 96), "turret.png": (1024, 1024),
    "turret_ember.png": (768, 768), "nest.png": (256, 256), "drone.png": (64, 64),
    "meteor_1.png": (96, 96), "meteor_2.png": (96, 96), "meteor_3.png": (96, 96),
    "matter_small.png": (32, 32), "matter_big.png": (64, 64),
    "planet_1.png": (768, 768), "planet_2.png": (768, 768), "planet_3.png": (768, 768),
    "star.png": (1536, 1536), "safezone.png": (640, 640), "safezone_fill.png": (640, 640),
    "shop_station.png": (640, 640), "decoy.png": (64, 64), "gravity_ring.png": (512, 512),
    "reticle.png": (128, 128), "marker_zone.png": (72, 72), "marker_shop.png": (72, 72),
    "marker_enemy.png": (72, 72), "arrow.png": (64, 64),
    "bg_stars_far.png": (512, 512), "bg_stars_near.png": (512, 512),
    "nebula_1.png": (1024, 1024), "nebula_2.png": (1024, 1024), "nebula_3.png": (1024, 1024),
    "dust.png": (256, 256), "shockwave.png": (512, 512), "spark.png": (32, 32),
    "smoke.png": (128, 128), "warp_ring.png": (1024, 1024), "title_bg.png": (1920, 1080),
    # fleet additions
    "carrier.png": (1024, 1024), "shield_arc.png": (768, 768),
    "singularity_rig.png": (768, 768), "ring_repel.png": (512, 512),
    "ring_siphon.png": (512, 512), "pylon.png": (512, 512),
    "guard_orb.png": (96, 96), "missile_booster.png": (64, 28), "mine.png": (56, 56),
}
for _i in range(8):
    EXPECTED["explosion_%d.png" % _i] = (256, 256)

TILEABLE = ["bg_stars_far.png", "bg_stars_near.png", "nebula_1.png", "nebula_2.png",
            "nebula_3.png", "dust.png"]
OPAQUE = ["title_bg.png"]

GROUPS = [
    ("ship & projectiles", ["ship.png", "ship_glow.png", "engine_glow.png", "missile.png",
                            "missile_warn.png", "nest.png", "drone.png"]),
    ("hazards & pickups", ["meteor_1.png", "meteor_2.png", "meteor_3.png", "decoy.png",
                           "matter_small.png", "matter_big.png"]),
    ("celestial bodies", ["planet_1.png", "planet_2.png", "planet_3.png", "star.png"]),
    ("stations & zones", ["turret.png", "turret_ember.png", "safezone.png",
                          "safezone_fill.png", "shop_station.png", "warp_ring.png"]),
    ("fleet additions", ["carrier.png", "shield_arc.png", "singularity_rig.png",
                         "pylon.png", "guard_orb.png", "missile_booster.png",
                         "mine.png", "ring_repel.png", "ring_siphon.png"]),
    ("hud / markers", ["reticle.png", "gravity_ring.png", "marker_zone.png",
                       "marker_shop.png", "marker_enemy.png", "arrow.png"]),
    ("fx", ["explosion_%d.png" % i for i in range(8)] + ["shockwave.png", "spark.png",
                                                          "smoke.png"]),
    ("space backdrop", ["bg_stars_far.png", "bg_stars_near.png", "nebula_1.png",
                        "nebula_2.png", "nebula_3.png", "dust.png"]),
    ("title", ["title_bg.png"]),
]


def verify():
    ok = True
    rows = []
    for name in sorted(EXPECTED):
        path = os.path.join(OUT, name)
        if not os.path.exists(path):
            rows.append((name, "-", "-", "-", "MISSING"))
            ok = False
            continue
        im = Image.open(path)
        size_ok = im.size == EXPECTED[name]
        mode_ok = im.mode == "RGBA"
        arr = np.asarray(im.convert("RGBA"))
        alpha = arr[..., 3]
        corners = [int(alpha[0, 0]), int(alpha[0, -1]), int(alpha[-1, 0]), int(alpha[-1, -1])]
        opaque_bg = name in OPAQUE
        border = np.concatenate([alpha[0], alpha[-1], alpha[:, 0], alpha[:, -1]])
        if opaque_bg:
            clear_ok = min(corners) == 255
        elif name in TILEABLE:
            clear_ok = True
        else:
            clear_ok = int(border.max()) <= 6
        bbox = im.getbbox()
        seam = ""
        if name in TILEABLE:
            d = np.abs(arr.astype(np.int16))
            seam_h = np.abs(d[:, 0] - d[:, -1]).mean()
            typ_h = np.abs(d[:, 1:] - d[:, :-1]).mean()
            seam_v = np.abs(d[0] - d[-1]).mean()
            typ_v = np.abs(d[1:] - d[:-1]).mean()
            seam_ok = (seam_h < typ_h * 8.0 + 3.0) and (seam_v < typ_v * 8.0 + 3.0)
            seam = "seam %.1f/%.1f ok" % (max(seam_h, seam_v), max(typ_h, typ_v)) \
                if seam_ok else "SEAM %.1f/%.1f BAD" % (max(seam_h, seam_v), max(typ_h, typ_v))
            if not seam_ok:
                ok = False
        status = "ok" if (size_ok and mode_ok and clear_ok) else "FAIL"
        if status != "ok":
            ok = False
        rows.append((name, "%dx%d" % im.size, im.mode,
                     "a%3d..%3d" % (int(alpha.min()), int(alpha.max())),
                     "%s bbox=%s %s" % (status, bbox, seam)))
    print("\n%-22s %-11s %-6s %-12s %s" % ("file", "size", "mode", "alpha", "check"))
    print("-" * 96)
    for r in rows:
        print("%-22s %-11s %-6s %-12s %s" % r)
    missing = [n for n in EXPECTED if not os.path.exists(os.path.join(OUT, n))]
    extra = [n for n in os.listdir(OUT)
             if n.endswith(".png") and n not in EXPECTED]
    print("-" * 96)
    print("files: %d/%d   missing: %s   unexpected: %s"
          % (len(EXPECTED) - len(missing), len(EXPECTED), missing or "none", extra or "none"))
    print("RESULT:", "ALL OK" if ok and not missing and not extra else "PROBLEMS")
    return ok


def contact_sheet(path, cell=196, cols=6, pad=10):
    try:
        font = ImageFont.truetype("DejaVuSans.ttf", 12)
        font_big = ImageFont.truetype("DejaVuSans-Bold.ttf", 20)
    except Exception:
        font = ImageFont.load_default()
        font_big = ImageFont.load_default()
    entries = []
    for title, names in GROUPS:
        entries.append(("group", title))
        for n in names:
            entries.append(("item", n))
    # layout pass
    x = pad
    y = pad + 46
    row_h = 0
    placed = []
    for kind, val in entries:
        if kind == "group":
            if x > pad:
                x = pad
                y += row_h + 12
                row_h = 0
            placed.append(("group", val, x, y))
            y += 26
            continue
        im = Image.open(os.path.join(OUT, val)).convert("RGBA")
        im.thumbnail((cell, cell - 22), Image.LANCZOS)
        wcell = max(im.width, 120)
        if x + wcell > pad + cols * (cell + pad):
            x = pad
            y += row_h + 12
            row_h = 0
        placed.append(("item", val, x, y, im))
        x += wcell + pad
        row_h = max(row_h, im.height + 26)
    total_w = pad + cols * (cell + pad)
    total_h = y + row_h + pad
    sheet = Image.new("RGBA", (total_w, total_h), (10, 12, 20, 255))
    d = ImageDraw.Draw(sheet)
    d.text((pad, 12), "Escape Gravity - world layer assets", fill=(150, 230, 255, 255),
           font=font_big)
    d.text((pad, 34), "%d files - assets/world/ - neon vector geometry" % len(EXPECTED),
           fill=(110, 130, 160, 255), font=font)
    for item in placed:
        if item[0] == "group":
            _, title, gx, gy = item
            d.text((gx, gy + 4), title.upper(), fill=(255, 179, 71, 235), font=font)
            d.line([(gx, gy + 20), (gx + 180, gy + 20)], fill=(70, 60, 40, 255), width=1)
        else:
            _, name, gx, gy, im = item
            sheet.alpha_composite(im, (gx, gy))
            d.text((gx, gy + im.height + 4), name, fill=(140, 190, 220, 255), font=font)
    sheet.convert("RGB").save(path)
    print("contact sheet ->", path, sheet.size)


# ==========================================================================
# entry point
# ==========================================================================
def all_builders():
    out = []
    for k in sorted(globals()):
        if k.startswith("build_") and callable(globals()[k]):
            out.append((k[len("build_"):], globals()[k]))
    return out


def main(argv):
    os.makedirs(OUT, exist_ok=True)
    want = [a for a in argv if not a.startswith("-")]
    builders = all_builders()
    if want:
        builders = [(n, f) for (n, f) in builders if n in want]
    t0 = time.time()
    for name, fn in builders:
        t = time.time()
        out = fn()
        print("  %-24s %5.1fs" % (out, time.time() - t), flush=True)
    print("built %d file(s) in %.1fs" % (len(builders), time.time() - t0))
    if not want:
        ok = verify()
        contact_sheet(os.path.join(ROOT, "docs", "preview_world.png"))
        return 0 if ok else 1
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
