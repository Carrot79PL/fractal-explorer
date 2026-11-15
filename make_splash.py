#!/usr/bin/env python3
"""Generuje Assets/splash.jpg — tło ekranu startowego (numpy + Pillow)."""
import numpy as np
from PIL import Image, ImageFilter
W, H = 1440, 900
cx, cy, half = -0.74529, 0.11273, 0.0045
asp = W / H
ys, xs = np.mgrid[0:H, 0:W]
c = (cx + (xs / W - 0.5) * 2 * half * asp) + 1j * (cy + (0.5 - ys / H) * 2 * half)
z = np.zeros_like(c); sl = np.zeros(c.shape); alive = np.ones(c.shape, bool)
for i in range(900):
    z[alive] = z[alive] ** 2 + c[alive]
    esc = alive & (np.abs(z) > 256)
    sl[esc] = i + 1 - np.log2(np.log2(np.abs(z[esc])))
    alive &= ~esc
stops = np.array([[2,4,28],[10,40,120],[40,150,220],[170,235,245],[255,214,120],[240,120,60],[150,40,110],[30,10,70]], float) / 255
def pal(t):
    t = t % 1.0 * len(stops); i = t.astype(int) % len(stops); f = (t - np.floor(t))[..., None]
    f = f * f * (3 - 2 * f)
    return stops[i] * (1 - f) + stops[(i + 1) % len(stops)] * f
rgb = pal(np.sqrt(sl) * 0.14 + 0.05)
rgb[alive] = [0.005, 0.01, 0.04]
h = np.log2(sl + 1); gx, gy = np.gradient(h)
rgb = np.clip(rgb * (0.72 + 0.55 * np.clip(0.5 + (-gx - gy) * 6, 0, 1)[..., None]), 0, 1)
img = Image.fromarray((rgb * 255).astype(np.uint8))
glow = img.filter(ImageFilter.GaussianBlur(14))
img = Image.blend(img, Image.fromarray(np.clip(np.asarray(img, float) + np.asarray(glow, float) * 0.35, 0, 255).astype(np.uint8)), 0.6)
img.save("Assets/splash.jpg", quality=90)
print("OK")
