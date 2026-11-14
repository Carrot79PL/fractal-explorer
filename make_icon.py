#!/usr/bin/env python3
"""Generuje AppIcon.icns (Mandelbrot, dolina konika) — numpy + Pillow + iconutil."""
import numpy as np, subprocess, os, shutil
from PIL import Image, ImageDraw, ImageFilter

N = 1024
cx, cy, half = -0.7453, 0.1127, 0.012   # spirale w dolinie konika
ys, xs = np.mgrid[0:N, 0:N]
c = (cx + (xs / N - 0.5) * 2 * half) + 1j * (cy + (0.5 - ys / N) * 2 * half)
z = np.zeros_like(c); sl = np.zeros(c.shape); alive = np.ones(c.shape, bool)
MAXIT = 700
for i in range(MAXIT):
    z[alive] = z[alive] ** 2 + c[alive]
    esc = alive & (np.abs(z) > 256)
    m = np.abs(z[esc])
    sl[esc] = i + 1 - np.log2(np.log2(m))
    alive &= ~esc
stops = np.array([[3,6,40],[20,60,170],[60,200,230],[250,245,200],[255,170,40],[170,40,110],[30,10,70]], float) / 255
def pal(t):
    t = t % 1.0 * len(stops); i = t.astype(int) % len(stops); f = (t - np.floor(t))[..., None]
    f = f * f * (3 - 2 * f)
    return stops[i] * (1 - f) + stops[(i + 1) % len(stops)] * f
rgb = pal(np.sqrt(sl) * 0.17)
rgb[alive] = [0.01, 0.01, 0.05]
# relief + winieta
h = np.log2(sl + 1); gx, gy = np.gradient(h)
shade = np.clip(0.5 + (-gx - gy) * 6, 0, 1)[..., None]
rgb = np.clip(rgb * (0.75 + 0.5 * shade), 0, 1)
r = np.hypot(xs - N / 2, ys - N / 2) / (N / 2)
rgb *= np.clip(1.15 - 0.35 * r ** 2, 0, 1)[..., None]
art = Image.fromarray((rgb * 255).astype(np.uint8))

# maska „squircle" w stylu macOS (margines ~10%)
S = 4; M = int(N * 0.098); size = N - 2 * M
mask = Image.new("L", (N * S, N * S), 0)
ImageDraw.Draw(mask).rounded_rectangle([M * S, M * S, (N - M) * S, (N - M) * S], radius=int(size * 0.225 * S), fill=255)
mask = mask.resize((N, N), Image.LANCZOS)
# połysk u góry
gloss = Image.new("L", (N, N), 0)
g = np.clip(1 - ys / (N * 0.55), 0, 1) ** 2 * 45
gloss = Image.fromarray(g.astype(np.uint8))
white = Image.new("RGB", (N, N), (255, 255, 255))
art = Image.composite(white, art, gloss)
# cień
shadow = Image.new("RGBA", (N, N), (0, 0, 0, 0))
sh = Image.new("L", (N, N), 0); sh.paste(mask.point(lambda v: int(v * 0.5)), (0, 14))
shadow.putalpha(sh.filter(ImageFilter.GaussianBlur(18)))
icon = shadow.copy(); icon.alpha_composite(Image.merge("RGBA", (*art.split(), mask)))
# cienka obwódka
edge = Image.new("L", (N, N), 0)
ImageDraw.Draw(edge).rounded_rectangle([M, M, N - M, N - M], radius=int(size * 0.225), outline=70, width=3)
icon.alpha_composite(Image.merge("RGBA", (Image.new("L",(N,N),255),)*3 + (edge,)))

d = "AppIcon.iconset"; shutil.rmtree(d, ignore_errors=True); os.makedirs(d)
for s in (16, 32, 128, 256, 512):
    icon.resize((s, s), Image.LANCZOS).save(f"{d}/icon_{s}x{s}.png")
    icon.resize((s * 2, s * 2), Image.LANCZOS).save(f"{d}/icon_{s}x{s}@2x.png")
subprocess.run(["iconutil", "-c", "icns", d, "-o", "AppIcon.icns"], check=True)
icon.save("icon_preview.png"); shutil.rmtree(d)
print("OK")
