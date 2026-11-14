#include <metal_stdlib>
using namespace metal;

// Musi odpowiadać `FractalUniforms` w FractalRenderer.swift (88 bajtów).
struct Uniforms {
    float2 dcOff;     // (środek widoku - punkt referencyjny) / scale
    float2 center;    // środek widoku (float)
    float2 juliaC;    // parametr c zbioru Julii
    float  scale;     // połowa wysokości widoku w jednostkach płaszczyzny
    float  aspect;
    float  pixel;     // rozmiar piksela w jednostkach `vec` (2 / wysokość w px)
    float  time;      // przesunięcie koloru (animacja)
    int    maxIter;
    int    palette;
    int    refLen;
    int    shallow;
    int    model;     // 0 Mandelbrot, 1 Burning Ship, 2 Tricorn, 3 Multibrot, 4 Julia, 5 Newton
    int    power;
    int    aa;        // krotność supersamplingu (n x n)
    int    colorMode; // 0 iteracje, 1 kąt, 2 pułapka orbity
    float  density;
    float  shade;
    float  glow;
    int    palette2;  // poprzednia paleta (płynne przejście)
    float  pmix;      // 1 = jeszcze poprzednia, 0 = już nowa
};

struct VSOut {
    float4 position [[position]];
    float2 uv;
};

vertex VSOut vertexMain(uint vid [[vertex_id]]) {
    float2 p[4] = { float2(-1,-1), float2(1,-1), float2(-1,1), float2(1,1) };
    VSOut o;
    o.position = float4(p[vid], 0, 1);
    o.uv = p[vid];
    return o;
}

// MARK: Palety – 9 palet po maks. 8 kolorów; w komponencie w pierwszego koloru siedzi liczba kolorów.

static float3 samplePalette(constant float4 *pal, int index, float t) {
    constant float4 *p = pal + index * 8;
    int N = int(p[0].w);
    float x = fract(t) * float(N);
    int i = int(floor(x));
    float f = x - float(i);
    float3 p0 = p[(i + N - 1) % N].xyz, p1 = p[i % N].xyz;
    float3 p2 = p[(i + 1) % N].xyz,     p3 = p[(i + 2) % N].xyz;
    float3 c = 0.5 * ((2.0 * p1) + (p2 - p0) * f
        + (2.0 * p0 - 5.0 * p1 + 4.0 * p2 - p3) * f * f
        + (3.0 * p1 - p0 - 3.0 * p2 + p3) * f * f * f);
    return max(c, 0.0);
}

static float2 cmul(float2 a, float2 b) {
    return float2(a.x * b.x - a.y * b.y, a.x * b.y + a.y * b.x);
}
static float2 cdiv(float2 a, float2 b) {
    return float2(a.x * b.x + a.y * b.y, a.y * b.x - a.x * b.y) / dot(b, b);
}
static float2 cpow(float2 z, int d) {
    float2 r = z;
    for (int k = 1; k < d; k++) r = cmul(r, z);
    return r;
}

struct PointResult {
    bool  escaped;
    float sl;     // gładka liczba iteracji
    float trap;   // minimalna odległość orbity od „krzyża"
    float ang;    // kąt ostatniego z
    float root;   // numer pierwiastka (Newton)
};

constant float BAILOUT = 256.0;

// MARK: Punkt – wszystkie modele

static PointResult evalPoint(float2 vec, constant Uniforms &u, constant float2 *ref) {
    PointResult r; r.escaped = false; r.sl = 0; r.trap = 1e9; r.ang = 0; r.root = 0;
    float s = u.scale;

    if (u.model == 0) {
        // Mandelbrot: teoria perturbacji (orbita referencyjna z CPU), głęboki zoom.
        if (u.shallow != 0) {
            float2 c = u.center + vec * s;
            float2 q = c - float2(0.25, 0.0);
            float q2 = dot(q, q);
            if (q2 * (q2 + q.x) < 0.25 * c.y * c.y) return r;
            float2 d = c + float2(1.0, 0.0);
            if (dot(d, d) < 0.0625) return r;
        }
        float2 dcs = u.dcOff + vec;
        float2 w = float2(0.0);
        int n = 0;
        float m2 = 0.0;
        float2 z = float2(0.0);
        int i = 0;
        for (; i < u.maxIter; i++) {
            float2 Z = ref[n];
            float2 sw = s * w;
            w = 2.0 * cmul(Z, w) + cmul(sw, w) + dcs;
            n++;
            sw = s * w;
            z = ref[n] + sw;
            m2 = dot(z, z);
            r.trap = min(r.trap, min(abs(z.x), abs(z.y)));
            if (m2 > BAILOUT * BAILOUT) { r.escaped = true; break; }
            if (m2 < dot(sw, sw) || n >= u.refLen - 1) { w = z / s; n = 0; }
        }
        if (r.escaped) {
            r.sl = max(float(i + 1) - log2(log2(m2) / log2(BAILOUT)), 0.0);
            r.ang = atan2(z.y, z.x);
        }
        return r;
    }

    float2 P = u.center + vec * s;

    if (u.model == 5) {
        // Newton dla z^3 - 1
        float2 z = P;
        const float2 roots[3] = { float2(1, 0), float2(-0.5, 0.8660254), float2(-0.5, -0.8660254) };
        int lim = min(u.maxIter, 200);
        for (int i = 0; i < lim; i++) {
            float2 z2 = cmul(z, z);
            float2 f = cmul(z2, z) - float2(1, 0);
            float2 d = 3.0 * z2;
            if (dot(d, d) < 1e-20) break;
            z -= cdiv(f, d);
            for (int k = 0; k < 3; k++) {
                float2 e = z - roots[k];
                float d2 = dot(e, e);
                if (d2 < 1e-10) {
                    r.escaped = true; r.root = float(k);
                    r.sl = float(i) + 1.0 - log2(max(-log10(max(d2, 1e-30)), 1.0) / 5.0);
                    r.ang = atan2(z.y, z.x);
                    return r;
                }
            }
        }
        return r;
    }

    float2 z, c;
    int d = (u.model == 3 || u.model == 4) ? max(u.power, 2) : 2;
    switch (u.model) {
        case 1: z = float2(0); c = float2(P.x, -P.y); break;   // Burning Ship (odwrócony, by „statek" był prosto)
        case 4: z = P;         c = u.juliaC;           break;
        default: z = float2(0); c = P;                  break;   // Tricorn i Multibrot
    }
    float m2 = 0.0;
    int i = 0;
    for (; i < u.maxIter; i++) {
        if (u.model == 1) z = float2(abs(z.x), abs(z.y));
        if (u.model == 2) z.y = -z.y;
        z = (d == 2 ? cmul(z, z) : cpow(z, d)) + c;
        m2 = dot(z, z);
        r.trap = min(r.trap, min(abs(z.x), abs(z.y)));
        if (m2 > BAILOUT * BAILOUT) { r.escaped = true; break; }
    }
    if (r.escaped) {
        r.sl = max(float(i + 1) - log(log2(m2) / log2(BAILOUT)) / log(float(d)), 0.0);
        r.ang = atan2(z.y, z.x);
    }
    return r;
}

// MARK: Kolor jednej próbki

static float3 palMix(constant float4 *pal, constant Uniforms &u, float t) {
    float3 a = samplePalette(pal, u.palette, t);
    if (u.pmix <= 0.0) return a;
    return mix(a, samplePalette(pal, u.palette2, t), u.pmix);
}

static float3 colorOf(PointResult r, constant Uniforms &u, constant float4 *pal, thread float &height) {
    height = 0.0;
    if (!r.escaped) return float3(0.0);
    float t;
    float3 col;
    if (u.model == 5) {
        float bright = 0.30 + 0.70 * exp(-r.sl * 0.11 * u.density);
        col = palMix(pal, u, r.root / 3.0 + 0.08 + u.time) * bright;
        height = log2(r.sl + 1.0);
    } else {
        if (u.colorMode == 1)      t = r.ang / 6.2831853 * u.density + sqrt(r.sl) * 0.03 + u.time;
        else if (u.colorMode == 2) t = -log(r.trap + 1e-4) * 0.12 * u.density + sqrt(r.sl) * 0.02 + u.time;
        else                       t = sqrt(r.sl) * 0.13 * u.density + u.time;
        col = palMix(pal, u, t);
        height = log2(r.sl + 1.0);
    }
    if (u.glow > 0.0) {
        float3 g = palMix(pal, u, 0.62 + u.time);
        col += u.glow * 1.3 * exp(-r.sl * 0.05) * (g + 0.25);
    }
    return col;
}

fragment float4 fragmentMain(VSOut in [[stage_in]],
                             constant Uniforms &u [[buffer(0)]],
                             constant float2 *ref [[buffer(1)]],
                             constant float4 *pal [[buffer(2)]]) {
    float2 base = float2(in.uv.x * u.aspect, in.uv.y);
    int n = max(u.aa, 1);
    float3 acc = float3(0.0);
    const float3 L = normalize(float3(-0.55, 0.65, 0.55));
    float lit0 = L.z;

    for (int sy = 0; sy < n; sy++) {
        for (int sx = 0; sx < n; sx++) {
            float2 off = ((float2(sx, sy) + 0.5) / float(n) - 0.5) * u.pixel;
            PointResult r = evalPoint(base + off, u, ref);
            float h;
            float3 col = colorOf(r, u, pal, h);
            if (u.shade > 0.0) {
                float2 g = float2(dfdx(h), dfdy(h));
                g = clamp(g, -1.0, 1.0);
                float3 nrm = normalize(float3(-g * 3.0, 1.0));
                float lit = clamp(dot(nrm, L), 0.0, 1.0);
                col *= max(1.0 + u.shade * 1.8 * (lit - lit0), 0.0);
            }
            acc += col;
        }
    }
    float3 col = acc / float(n * n);

    // delikatna winieta i dithering przeciw bandingowi
    col *= mix(1.0, 0.80, smoothstep(0.7, 1.9, length(in.uv)));
    float noise = fract(sin(dot(in.position.xy, float2(12.9898, 78.233))) * 43758.5453);
    col += (noise - 0.5) / 255.0;
    return float4(saturate(col), 1.0);
}
