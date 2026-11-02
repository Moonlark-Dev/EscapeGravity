#!/usr/bin/env python3
"""Post-process generated placeholder art: fixes clipping, makes nebulae read
on black, and replaces the explosion strip with a designed fireball sequence.
Run after tools/gen_assets_world.py (it is idempotent)."""
import os
import numpy as np
from PIL import Image, ImageFilter

ROOT = os.path.join(os.path.dirname(__file__), "..")
W = os.path.join(ROOT, "assets", "world")


def boost_nebulae():
    for name, gain in (("nebula_1", 2.4), ("nebula_2", 2.6), ("nebula_3", 2.8)):
        p = os.path.join(W, name + ".png")
        im = np.array(Image.open(p).convert("RGBA")).astype(np.float32)
        a = im[..., 3] * gain
        im[..., 3] = np.clip(a, 0, 255)
        rgb = im[..., :3] * 1.08
        im[..., :3] = np.clip(rgb, 0, 255)
        Image.fromarray(im.astype("uint8"), "RGBA").save(p)


def mask_planet2():
    p = os.path.join(W, "planet_2.png")
    im = Image.open(p).convert("RGBA")
    a = np.array(im).astype(np.float32)
    h, w = a.shape[:2]
    yy, xx = np.mgrid[0:h, 0:w]
    r = np.hypot(xx - w / 2, yy - h / 2)
    # keep the sphere, remove the edge-on ring that ran off the canvas
    fade = np.clip((378.0 - r) / 9.0, 0.0, 1.0)
    a[..., 3] *= fade
    Image.fromarray(a.astype("uint8"), "RGBA").save(p)


def clean_shop_station():
    p = os.path.join(W, "shop_station.png")
    im = Image.open(p).convert("RGBA")
    a = np.array(im).astype(np.float32)
    h, w = a.shape[:2]
    yy, xx = np.mgrid[0:h, 0:w]
    region = (xx > 380) & (xx < 565) & (yy > 110) & (yy < 255)
    r = a[..., 0]
    g = a[..., 1]
    b = a[..., 2]
    red = region & (r > 120) & (r > g * 1.35) & (r > b * 1.2)
    a[..., 3][red] = 0.0
    # soften the hole a little
    alpha = Image.fromarray(a[..., 3].astype("uint8"), "L").filter(ImageFilter.GaussianBlur(1.2))
    a[..., 3] = np.array(alpha).astype(np.float32)
    Image.fromarray(a.astype("uint8"), "RGBA").save(p)


def make_explosions():
    S = 256
    yy, xx = np.mgrid[0:S, 0:S].astype(np.float32)
    cx = cy = (S - 1) * 0.5
    px = (xx - cx) / (S * 0.5)
    py = (yy - cy) / (S * 0.5)
    r = np.hypot(px, py)
    ang = np.arctan2(py, px)
    rng = np.random.default_rng(11)
    # irregular flame edge
    noise = np.zeros_like(r)
    for k, amp in zip((3, 5, 7, 11), (0.10, 0.06, 0.04, 0.025)):
        noise += amp * np.sin(ang * k + rng.uniform(0, 6.28)) * np.sin(r * 6.0 + rng.uniform(0, 6.28))
    embers = [(rng.uniform(0, 6.28), rng.uniform(0.15, 0.42), rng.uniform(0.012, 0.03)) for _ in range(14)]
    for i in range(8):
        t = i / 7.0
        radius = 0.16 + 0.94 * (t ** 0.62)
        rn = r / radius * (1.0 + noise)
        body = np.clip((1.02 - rn) / 0.42, 0.0, 1.0)
        body = body * body * (3.0 - 2.0 * body)
        core = np.exp(-((rn / (0.34 + 0.25 * t)) ** 2))
        heat = np.clip(1.0 - rn, 0.0, 1.0)
        # colour ramp: white core -> yellow -> orange -> deep red
        col = np.zeros((S, S, 3), dtype=np.float32)
        white = np.array([1.0, 0.98, 0.90])
        yellow = np.array([1.0, 0.78, 0.32])
        orange = np.array([1.0, 0.38, 0.10])
        red = np.array([0.55, 0.09, 0.05])
        c1 = np.clip(heat * 1.6, 0, 1)[..., None]
        col += white * core[..., None] * (1.4 - t)
        col += yellow * c1 * body[..., None] * 0.9
        col += orange * (1 - c1) * body[..., None]
        col += red * (1 - heat[..., None]) * body[..., None] * 0.5
        alpha = body * (1.0 - 0.82 * max(0.0, t - 0.35) / 0.65)
        alpha = np.clip(alpha, 0, 1) * (0.97 if t < 0.55 else 0.75 * (1.0 - t) + 0.15)
        # embers
        for (ea, ed, es) in embers:
            d = ed * (0.35 + 1.3 * t)
            ex = cx + np.cos(ea) * d * S * 0.5
            ey = cy + np.sin(ea) * d * S * 0.5
            rr = es * S * 0.5 * (1.0 - 0.4 * t)
            dot = np.exp(-(((xx - ex) ** 2 + (yy - ey) ** 2) / (rr * rr + 1e-3)) * 2.0)
            col += dot[..., None] * np.array([1.0, 0.55, 0.22]) * 0.8
            alpha += dot * 0.7
        alpha = np.clip(alpha, 0, 1)
        rgba = np.zeros((S, S, 4), dtype=np.float32)
        rgba[..., :3] = np.clip(col, 0, 1) * 255
        rgba[..., 3] = alpha * 255
        out = Image.fromarray(rgba.astype("uint8"), "RGBA")
        out.save(os.path.join(W, "explosion_%d.png" % i))


def main():
    boost_nebulae()
    mask_planet2()
    clean_shop_station()
    make_explosions()
    print("post assets done")


if __name__ == "__main__":
    main()
