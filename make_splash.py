#!/usr/bin/env python3
"""Generuje Assets/splash.jpg — tło ekranu startowego (numpy + Pillow).
Użycie: make_splash.py [nazwa_wariantu] [szerokość]   (bez argumentów: wariant z VARIANT_DEFAULT, 1440 px)"""
import sys
import numpy as np
from PIL import Image, ImageFilter

PALETTES = {
    "aurora": [[1,3,20],[8,50,90],[0,160,170],[120,255,190],[250,240,160],[230,90,150],[110,30,150],[10,5,50]],
    "ember":  [[4,0,8],[60,5,40],[170,20,50],[255,100,30],[255,210,110],[255,250,225],[90,40,120],[10,0,30]],
    "ice":    [[2,6,24],[12,50,130],[70,150,230],[200,240,255],[255,255,255],[140,190,250],[40,80,170],[4,10,50]],
}
# nazwa: (typ, cx, cy, połowa wysokości, paleta, gęstość koloru, iteracje)
VARIANTS = {
    "julia":   ("julia", 0.0, 0.0, 1.25, "aurora", 0.10, 400, (-0.7269, 0.1889)),
    "spiral":  ("mandel", -0.743643887037151, 0.131825904205330, 6.0e-5, "ember", 0.11, 1600, None),
    "armada":  ("ship", -1.7443, -0.0183, 0.022, "ice", 0.10, 900, None),
    "seahorse":("mandel", -0.7453, 0.1127, 0.0045, "aurora", 0.14, 900, None),
}
VARIANT_DEFAULT = "julia"

def render(name, W):
    kind, cx, cy, half, pal_name, dens, maxit, jc = VARIANTS[name]
    H = int(W * 0.625)
    asp = W / H
    ys, xs = np.mgrid[0:H, 0:W]
    p = (cx + (xs / W - 0.5) * 2 * half * asp) + 1j * (cy + (0.5 - ys / H) * 2 * half)
    if kind == "julia": z = p.copy(); c = np.full_like(p, complex(*jc))
    else: z = np.zeros_like(p); c = p
    sl = np.zeros(p.shape); alive = np.ones(p.shape, bool)
    for i in range(maxit):
        if kind == "ship": z[alive] = np.abs(z[alive].real) + 1j * np.abs(z[alive].imag)
        z[alive] = z[alive] ** 2 + c[alive]
        esc = alive & (np.abs(z) > 256)
        sl[esc] = i + 1 - np.log2(np.log2(np.abs(z[esc])))
        alive &= ~esc
    stops = np.array(PALETTES[pal_name], float) / 255
    def pal(t):
        t = t % 1.0 * len(stops); i = t.astype(int) % len(stops); f = (t - np.floor(t))[..., None]
        f = f * f * (3 - 2 * f)
        return stops[i] * (1 - f) + stops[(i + 1) % len(stops)] * f
    rgb = pal(np.sqrt(sl) * dens + 0.05)
    rgb[alive] = [0.003, 0.005, 0.02]
    h = np.log2(sl + 1); gx, gy = np.gradient(h)
    rgb = np.clip(rgb * (0.7 + 0.6 * np.clip(0.5 + (-gx - gy) * 6, 0, 1)[..., None]), 0, 1)
    img = Image.fromarray((rgb * 255).astype(np.uint8))
    glow = np.asarray(img.filter(ImageFilter.GaussianBlur(W / 100)), float)
    img = Image.fromarray(np.clip(np.asarray(img, float) + glow * 0.30, 0, 255).astype(np.uint8))
    return img

if __name__ == "__main__":
    name = sys.argv[1] if len(sys.argv) > 1 else VARIANT_DEFAULT
    W = int(sys.argv[2]) if len(sys.argv) > 2 else 1440
    render(name, W).save("Assets/splash.jpg" if len(sys.argv) <= 3 else sys.argv[3], quality=90)
    print("OK", name)
