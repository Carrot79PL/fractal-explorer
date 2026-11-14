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
    float  angle;     // obrót widoku (rad)
    float  saturation;
    float  contrast;
    float  pitch;     // nachylenie kamery 3D (rad)
    float  hscale;    // skala wysokości 3D
    int    invert;
    int    kaleido;   // liczba segmentów kalejdoskopu (0/1 = wyłączony)
    int    interior;  // kolorowe wnętrze zbioru
    float  span;      // 3D: ile razy większy obszar niż widok obejmuje tekstura pola
    float  pad2;
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
            if (q2 * (q2 + q.x) < 0.25 * c.y * c.y) { r.trap = 0.3; return r; }
            float2 d = c + float2(1.0, 0.0);
            if (dot(d, d) < 0.0625) { r.trap = 0.3; return r; }
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
    if (!r.escaped) {
        if (u.interior != 0 && u.model != 5) {
            float tt = -log(r.trap + 1e-4) * 0.12 * u.density + u.time;
            return palMix(pal, u, tt) * 0.5;
        }
        return float3(0.0);
    }
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

static float2 rot2(float2 v, float a) {
    float c = cos(a), sn = sin(a);
    return float2(c * v.x - sn * v.y, sn * v.x + c * v.y);
}

/// Wektor w płaszczyźnie względem środka widoku: kalejdoskop (w osiach ekranu), potem obrót.
static float2 viewVec(float2 uv, constant Uniforms &u) {
    float2 sv = float2(uv.x * u.aspect, uv.y);
    if (u.kaleido > 1) {
        float seg = 6.2831853 / float(u.kaleido);
        float a = atan2(sv.y, sv.x);
        float rr = length(sv);
        a = a - seg * floor(a / seg);
        a = fabs(a - 0.5 * seg);
        sv = rr * float2(cos(a), sin(a));
    }
    return rot2(sv, u.angle);
}

static float3 grade(float3 col, constant Uniforms &u) {
    float lum = dot(col, float3(0.299, 0.587, 0.114));
    col = mix(float3(lum), col, u.saturation);
    col = (col - 0.5) * u.contrast + 0.5;
    if (u.invert != 0) col = 1.0 - col;
    return max(col, 0.0);
}

fragment float4 fragmentMain(VSOut in [[stage_in]],
                             constant Uniforms &u [[buffer(0)]],
                             constant float2 *ref [[buffer(1)]],
                             constant float4 *pal [[buffer(2)]]) {
    float2 base = viewVec(in.uv, u);
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
    float3 col = grade(acc / float(n * n), u);

    // delikatna winieta i dithering przeciw bandingowi
    col *= mix(1.0, 0.80, smoothstep(0.7, 1.9, length(in.uv)));
    float noise = fract(sin(dot(in.position.xy, float2(12.9898, 78.233))) * 43758.5453);
    col += (noise - 0.5) / 255.0;
    return float4(saturate(col), 1.0);
}

// MARK: Tryb 3D – przebieg 1: pole (kolor + wysokość w alfa) do tekstury

fragment float4 fragmentField(VSOut in [[stage_in]],
                              constant Uniforms &u [[buffer(0)]],
                              constant float2 *ref [[buffer(1)]],
                              constant float4 *pal [[buffer(2)]]) {
    PointResult r = evalPoint(viewVec(in.uv * u.span, u), u, ref);
    float hh;
    float3 col = grade(colorOf(r, u, pal, hh), u);
    float h = 1.0;
    if (r.escaped) h = saturate(log2(r.sl + 1.0) / log2(float(u.maxIter) + 1.0) * 1.15);
    return float4(col, h);
}

// MARK: Tryb 3D – przebieg 2: nieskończony teren do horyzontu (tekstura powtarzana lustrzanie + mgła)

struct MeshOut {
    float4 position [[position]];
    float2 tc;
    float  wz;
    float  zmax;
};

constant int MESH_G = 320;
constant float Z_NEAR = -4.5;
constant float Z_FAR = 60.0;
constant float CAM_D = 6.0;

static float camF(constant Uniforms &u) { return CAM_D * mix(0.95, 0.68, saturate(u.pitch / 1.3)); }

constexpr sampler fieldSampler(filter::linear, mip_filter::linear, address::mirrored_repeat);

vertex MeshOut vertexMesh(uint vid [[vertex_id]],
                          constant Uniforms &u [[buffer(0)]],
                          texture2d<float> tex [[texture(0)]]) {
    uint cell = vid / 6, k = vid % 6;
    const int2 corner[6] = { int2(0, 0), int2(1, 0), int2(0, 1), int2(1, 0), int2(1, 1), int2(0, 1) };
    int ix = int(cell % uint(MESH_G)) + corner[k].x;
    int iy = (MESH_G - 1 - int(cell / uint(MESH_G))) + corner[k].y;   // od najdalszego rzędu (malarz)
    float2 p = float2(ix, iy) / float(MESH_G);
    float cp = cos(u.pitch), sp = sin(u.pitch);
    float f = camF(u);
    float z = Z_NEAR + (Z_FAR - Z_NEAR) * pow(p.y, 2.2);
    float xh = u.aspect * max(1.1, (CAM_D + max(z, 0.0) * sp) / f * 1.2 + 0.3);
    float x = (p.x * 2.0 - 1.0) * xh;
    float2 tc = float2(x / (u.aspect * u.span) * 0.5 + 0.5, 0.5 - z / (2.0 * u.span));
    float h = tex.sample(fieldSampler, tc, level(2.5)).a;
    float y = h * u.hscale;
    float sy = z * cp + y * sp;
    float dc = y * cp - z * sp;
    float wd = CAM_D - dc;
    MeshOut o;
    o.position = float4(x / u.aspect * f / wd, sy * f / wd, saturate((wd - 1.0) / 40.0), 1.0);
    o.tc = tc;
    o.wz = z;
    o.zmax = Z_FAR;
    return o;
}

static float3 hazeColor(constant Uniforms &u, constant float4 *pal) {
    return palMix(pal, u, 0.35 + u.time) * 0.30 + float3(0.035, 0.045, 0.09);
}

fragment float4 fragmentSky(VSOut in [[stage_in]],
                            constant Uniforms &u [[buffer(0)]],
                            constant float4 *pal [[buffer(2)]]) {
    float sp = sin(u.pitch), cp = cos(u.pitch);
    float hy = sp > 0.02 ? camF(u) * cp / sp : 10.0;
    float3 haze = hazeColor(u, pal);
    float3 top = haze * 0.25 + float3(0.005, 0.008, 0.03);
    float3 col = mix(haze, top, smoothstep(hy, hy + 1.3, in.uv.y));
    float noise = fract(sin(dot(in.position.xy, float2(12.9898, 78.233))) * 43758.5453);
    return float4(saturate(col + (noise - 0.5) / 255.0), 1.0);
}

fragment float4 fragmentMesh(MeshOut in [[stage_in]],
                             constant Uniforms &u [[buffer(0)]],
                             constant float4 *pal [[buffer(2)]],
                             texture2d<float> tex [[texture(0)]]) {
    float2 px = 1.0 / float2(tex.get_width(), tex.get_height());
    float4 c = tex.sample(fieldSampler, in.tc);
    float hx = tex.sample(fieldSampler, in.tc + float2(px.x * 1.5, 0)).a - tex.sample(fieldSampler, in.tc - float2(px.x * 1.5, 0)).a;
    float hy = tex.sample(fieldSampler, in.tc + float2(0, px.y * 1.5)).a - tex.sample(fieldSampler, in.tc - float2(0, px.y * 1.5)).a;
    float dxw = 2.0 * u.aspect * u.span * px.x * 3.0;
    float dzw = 2.0 * u.span * px.y * 3.0;
    float3 n = normalize(float3(-u.hscale * hx / dxw, 1.0, u.hscale * hy / dzw));
    const float3 L = normalize(float3(-0.45, 0.75, 0.5));
    float cp = cos(u.pitch), sp = sin(u.pitch);
    float3 V = float3(0.0, cp, -sp);
    float diff = saturate(dot(n, L));
    float spec = pow(saturate(dot(n, normalize(L + V))), 40.0) * 0.22;
    float3 col = c.rgb * (0.30 + 0.95 * diff) + spec;
    // mgła do horyzontu (kolor zgodny z niebem)
    float d = max(in.wz + 1.3, 0.0);
    float fog = saturate(1.0 - exp(-d * 0.10));
    fog = mix(fog, 1.0, smoothstep(0.75, 1.0, d / (Z_FAR + 1.3)));
    col = mix(col, hazeColor(u, pal), fog);
    float noise = fract(sin(dot(in.position.xy, float2(12.9898, 78.233))) * 43758.5453);
    col += (noise - 0.5) / 255.0;
    return float4(saturate(col), 1.0);
}
