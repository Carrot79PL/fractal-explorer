import SwiftUI
import MetalKit
import simd
import UniformTypeIdentifiers

// MARK: - Arytmetyka double-double (~32 cyfry dziesiętne)

struct DD {
    var hi: Double
    var lo: Double

    init(_ v: Double) { hi = v; lo = 0 }
    init(hi: Double, lo: Double) { self.hi = hi; self.lo = lo }

    @inline(__always) static func quickTwoSum(_ a: Double, _ b: Double) -> DD {
        let s = a + b
        return DD(hi: s, lo: b - (s - a))
    }
    @inline(__always) static func twoSum(_ a: Double, _ b: Double) -> DD {
        let s = a + b
        let bb = s - a
        return DD(hi: s, lo: (a - (s - bb)) + (b - bb))
    }
    @inline(__always) static func + (a: DD, b: DD) -> DD {
        let s = twoSum(a.hi, b.hi)
        return quickTwoSum(s.hi, s.lo + a.lo + b.lo)
    }
    @inline(__always) static prefix func - (a: DD) -> DD { DD(hi: -a.hi, lo: -a.lo) }
    @inline(__always) static func - (a: DD, b: DD) -> DD { a + (-b) }
    @inline(__always) static func * (a: DD, b: DD) -> DD {
        let p = a.hi * b.hi
        let e = fma(a.hi, b.hi, -p) + (a.hi * b.lo + a.lo * b.hi)
        return quickTwoSum(p, e)
    }
    @inline(__always) static func * (a: DD, b: Double) -> DD { a * DD(b) }
}

struct DD2 {
    var x: DD
    var y: DD
}

@inline(__always) private func cmul(_ a: SIMD2<Double>, _ b: SIMD2<Double>) -> SIMD2<Double> {
    SIMD2(a.x * b.x - a.y * b.y, a.x * b.y + a.y * b.x)
}

/// Układ musi odpowiadać `struct Uniforms` w Shaders.metal (136 bajtów).
struct FractalUniforms {
    var dcOff: SIMD2<Float>
    var center: SIMD2<Float>
    var juliaC: SIMD2<Float>
    var scale: Float
    var aspect: Float
    var pixel: Float
    var time: Float
    var maxIter: Int32
    var palette: Int32
    var refLen: Int32
    var shallow: Int32
    var model: Int32
    var power: Int32
    var aa: Int32
    var colorMode: Int32
    var density: Float
    var shade: Float
    var glow: Float
    var palette2: Int32 = 0
    var pmix: Float = 0
    var angle: Float = 0
    var saturation: Float = 1
    var contrast: Float = 1
    var pitch: Float = 0
    var hscale: Float = 0
    var invert: Int32 = 0
    var kaleido: Int32 = 0
    var interior: Int32 = 0
    var span: Float = 1
    var pad2: Float = 0
}

enum ExportSize: Int, CaseIterable, Identifiable {
    case k4 = 3840, k8 = 7680
    var id: Int { rawValue }
    var title: String { self == .k4 ? "PNG 4K (3840 px)" : "PNG 8K (7680 px)" }
}

/// Renderer + stan kamery + parametry wyglądu. `MTKViewDelegate` i `ObservableObject`.
final class FractalRenderer: NSObject, ObservableObject, MTKViewDelegate {

    static let maxOrbit = 20001
    static let span3D = 2.5
    static var colorModes: [String] { [tr("Iteracje", "Iterations"), tr("Kąt", "Angle"), tr("Pułapka orbity", "Orbit trap")] }

    // MARK: Parametry publikowane do SwiftUI
    @Published var model: FractalModel = .mandelbrot {
        didSet { if model != oldValue && !suppressHome { applyHome() }; wake() }
    }
    @Published var power = 3 { didSet { wake() } }
    @Published var juliaRe = -0.8 { didSet { wake() } }
    @Published var juliaIm = 0.156 { didSet { wake() } }
    @Published var paletteIndex = 0 {
        didSet {
            if oldValue != paletteIndex { prevPalette = oldValue; paletteFade = 1 }
            wake()
        }
    }
    private var prevPalette = 0
    private var paletteFade = 0.0
    @Published var colorMode = 0 { didSet { wake() } }
    @Published var density = 1.0 { didSet { wake() } }
    @Published var shade = 0.0 { didSet { wake() } }
    @Published var glow = 0.0 { didSet { wake() } }
    @Published var antialias = true { didSet { wake() } }
    @Published var cycleColors = false { didSet { wake() } }
    @Published var cycleSpeed = 0.15 { didSet { wake() } }
    @Published var autoZoom = false { didSet { if autoZoom { wake() } } }
    @Published var baseIterations: Double = 300 { didSet { wake() } }
    @Published var customColors: [Color] = Palettes.defaultCustom.map {
        Color(red: Double($0.x), green: Double($0.y), blue: Double($0.z))
    } {
        didSet { applyCustomColors(); wake() }
    }
    // Obrót, 3D, kolory i dźwięk
    @Published var angleDeg = 0.0 { didSet { if !syncing { setAngle(angleDeg * .pi / 180); lastInput = CACurrentMediaTime() } } }
    @Published var autoRotate = false { didSet { if autoRotate { wake() } } }
    @Published var rotateSpeed = 8.0 { didSet { wake() } }
    @Published var kaleido = 0 { didSet { wake() } }
    @Published var interiorColor = false { didSet { wake() } }
    @Published var saturation = 1.0 { didSet { wake() } }
    @Published var contrast = 1.0 { didSet { wake() } }
    @Published var invert = false { didSet { wake() } }
    @Published var mode3D = false { didSet { lastInput = CACurrentMediaTime(); wake() } }
    @Published var pitchDeg = 66.0 { didSet { wake() } }
    @Published var heightScale = 0.35 { didSet { wake() } }
    @Published var musicOn = false {
        didSet {
            if musicOn { if music == nil { music = AmbientMusic() }; music?.setVolume(musicVolume) }
            music?.setEnabled(musicOn)
        }
    }
    @Published var musicVolume = 0.5 { didSet { music?.setVolume(musicVolume) } }
    private var music: AmbientMusic?
    @Published var tourOn = false
    var tourTimer: Timer?
    var tourIndex = -1
    private var syncing = false
    private var angleRad = 0.0
    @Published var favorites: [SavedView] = []
    @Published var isExporting = false

    // HUD
    @Published var realText = "+0.0000000"
    @Published var imagText = "+0.0000000"
    @Published var zoomText = "1.0×"
    @Published var iterText = "0"

    // MARK: Metal
    let device: MTLDevice
    private let queue: MTLCommandQueue
    private let pipeline: MTLRenderPipelineState
    private let fieldPipeline: MTLRenderPipelineState
    private let meshPipeline: MTLRenderPipelineState
    private let skyPipeline: MTLRenderPipelineState
    private var fieldTex: MTLTexture?
    private weak var view: MTKView?
    private var orbitBuffers: [MTLBuffer] = []
    private let inflight = DispatchSemaphore(value: 3)
    private var frameIndex = 0
    private var suppressHome = false

    // MARK: Kamera
    private var anchor = FractalModel.mandelbrot.homeCenter
    private var anchorVec = SIMD2<Double>(0, 0)
    private var scale = FractalModel.mandelbrot.homeScale
    private var targetScale = FractalModel.mandelbrot.homeScale
    private var homing = false

    /// Obrót wektora z osi ekranu do osi płaszczyzny zespolonej.
    private func rotv(_ v: SIMD2<Double>) -> SIMD2<Double> {
        let c = cos(angleRad), s = sin(angleRad)
        return SIMD2(c * v.x - s * v.y, s * v.x + c * v.y)
    }

    private var center: DD2 {
        let r = rotv(anchorVec)
        return DD2(x: anchor.x - DD(r.x * scale), y: anchor.y - DD(r.y * scale))
    }

    /// Zmienia kąt obrotu wokół środka widoku (środek zostaje w miejscu).
    private func setAngle(_ a: Double) {
        let c = center
        anchor = c
        anchorVec = .zero
        angleRad = a
        wake()
    }

    func coordinatesString() -> String {
        let c = center
        let digits = min(17, max(7, Int(ceil(-log10(scale))) + 4))
        return String(format: "Re %+.*f, Im %+.*f, zoom %.3e, model %@",
                      digits, c.x.hi, digits, c.y.hi, model.homeScale / scale, model.title)
    }

    func rotateBy(degrees: Double) {
        setAngle(angleRad - degrees * .pi / 180)
        lastInput = CACurrentMediaTime()
    }

    // MARK: Orbita referencyjna (tylko Mandelbrot)
    private var orbitF: [SIMD2<Float>] = []
    private var orbitD: [SIMD2<Double>] = []
    private var orbitCenter = FractalModel.mandelbrot.homeCenter
    private var orbitCap = 0

    // Kursor / czas
    private var cursorUV = SIMD2<Double>(0, 0)
    private var aspect = 1.0
    private var lastTime = CACurrentMediaTime()
    private var lastInput = 0.0
    private var lastHUD = 0.0
    private let moveLevels = [0.12, 0.18, 0.25, 0.35, 0.5, 0.7]
    private var moveLevel = 4
    private var slowCount = 0
    private var restStage = 0       // 0: pełna rozdzielczość bez AA, 1: z AA (jeśli się opłaca)
    private var restAAOK = true
    private var fastCount = 0
    private var moveFactor: Double { moveLevels[moveLevel] }
    private var lastMoving = false
    private var phase = 0.0

    // Diagnostyka (MANDELBROT_DEBUG=1)
    private let debug = ProcessInfo.processInfo.environment["MANDELBROT_DEBUG"] != nil
    private var dbgFrames = 0
    private var dbgGPU = 0.0
    private var dbgStart = CACurrentMediaTime()

    private static let favoritesKey = "mandelbrot.favorites.v1"

    override init() {
        guard let device = MTLCreateSystemDefaultDevice(),
              let queue = device.makeCommandQueue(),
              let library = device.makeDefaultLibrary() else {
            fatalError("Metal jest niedostępny lub brak Shaders.metal w targecie.")
        }
        self.device = device
        self.queue = queue

        let d = MTLRenderPipelineDescriptor()
        d.vertexFunction = library.makeFunction(name: "vertexMain")
        d.fragmentFunction = library.makeFunction(name: "fragmentMain")
        d.colorAttachments[0].pixelFormat = .bgra8Unorm
        do { pipeline = try device.makeRenderPipelineState(descriptor: d) }
        catch { fatalError("Pipeline: \(error)") }

        let f = MTLRenderPipelineDescriptor()
        f.vertexFunction = library.makeFunction(name: "vertexMain")
        f.fragmentFunction = library.makeFunction(name: "fragmentField")
        f.colorAttachments[0].pixelFormat = .rgba16Float
        let m = MTLRenderPipelineDescriptor()
        m.vertexFunction = library.makeFunction(name: "vertexMesh")
        m.fragmentFunction = library.makeFunction(name: "fragmentMesh")
        m.colorAttachments[0].pixelFormat = .bgra8Unorm
        let k = MTLRenderPipelineDescriptor()
        k.vertexFunction = library.makeFunction(name: "vertexMain")
        k.fragmentFunction = library.makeFunction(name: "fragmentSky")
        k.colorAttachments[0].pixelFormat = .bgra8Unorm
        do {
            skyPipeline = try device.makeRenderPipelineState(descriptor: k)
            fieldPipeline = try device.makeRenderPipelineState(descriptor: f)
            meshPipeline = try device.makeRenderPipelineState(descriptor: m)
        } catch { fatalError("Pipeline 3D: \(error)") }

        super.init()
        for _ in 0..<3 {
            if let b = device.makeBuffer(length: Self.maxOrbit * MemoryLayout<SIMD2<Float>>.stride + 64,
                                         options: .storageModeShared) {
                orbitBuffers.append(b)
            }
        }
        if let data = UserDefaults.standard.data(forKey: Self.favoritesKey),
           let list = try? JSONDecoder().decode([SavedView].self, from: data) {
            favorites = list
        }
    }

    func configure(_ view: MTKView) {
        self.view = view
        view.device = device
        view.delegate = self
        view.colorPixelFormat = .bgra8Unorm
        view.framebufferOnly = true
        view.enableSetNeedsDisplay = false
        view.isPaused = false
        view.preferredFramesPerSecond = 60
        view.autoResizeDrawable = false
        view.clearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 1)
        runTestHooks()
    }

    func wake() { view?.isPaused = false }

    private func applyCustomColors() {
        Palettes.all[Palettes.customIndex].colors = customColors.map {
            let c = NSColor($0).usingColorSpace(.sRGB) ?? .black
            return SIMD3(Float(c.redComponent), Float(c.greenComponent), Float(c.blueComponent))
        }
        if paletteIndex != Palettes.customIndex { paletteIndex = Palettes.customIndex }
    }

    // MARK: Widok / ulubione

    private func applyHome() {
        anchor = model.homeCenter
        anchorVec = .zero
        scale = model.homeScale
        targetScale = model.homeScale
        homing = false
        autoZoom = false
        orbitF = []
        lastInput = CACurrentMediaTime()
    }

    func resetView() {
        autoZoom = false
        if angleRad != 0 { setAngle(0); syncing = true; angleDeg = 0; syncing = false }
        anchor = center
        anchorVec = .zero
        targetScale = model.homeScale
        homing = true
        lastInput = CACurrentMediaTime()
        wake()
    }

    func currentView(name: String) -> SavedView {
        let c = center
        return SavedView(name: name, model: model.rawValue,
                         reHi: c.x.hi, reLo: c.x.lo, imHi: c.y.hi, imLo: c.y.lo,
                         scale: scale, palette: paletteIndex,
                         juliaRe: juliaRe, juliaIm: juliaIm, power: power)
    }

    func go(to v: SavedView) {
        autoZoom = false
        suppressHome = true
        model = FractalModel(rawValue: v.model) ?? .mandelbrot
        suppressHome = false
        power = v.power; juliaRe = v.juliaRe; juliaIm = v.juliaIm
        paletteIndex = v.palette
        anchor = DD2(x: DD(hi: v.reHi, lo: v.reLo), y: DD(hi: v.imHi, lo: v.imLo))
        anchorVec = .zero
        scale = v.scale; targetScale = v.scale
        homing = false
        orbitF = []
        lastInput = CACurrentMediaTime()
        wake()
    }

    func saveFavorite() {
        let name = "\(tr("Widok", "View")) \(favorites.count + 1) · \(zoomText)"
        favorites.append(currentView(name: name))
        persistFavorites()
    }

    func deleteFavorite(_ v: SavedView) {
        favorites.removeAll { $0.id == v.id }
        persistFavorites()
    }

    private func persistFavorites() {
        if let data = try? JSONEncoder().encode(favorites) {
            UserDefaults.standard.set(data, forKey: Self.favoritesKey)
        }
    }

    /// Ustawia parametr c Julii na punkt pod kursorem w bieżącej płaszczyźnie (z Mandelbrota).
    func juliaFromCursor() {
        let c = center
        let pv = rotv(SIMD2(cursorUV.x * aspect, cursorUV.y))
        juliaRe = c.x.hi + pv.x * scale
        juliaIm = c.y.hi + pv.y * scale
        model = .julia
    }

    // MARK: Interakcja

    private func uv(for p: CGPoint, in size: CGSize) -> SIMD2<Double> {
        guard size.width > 0, size.height > 0 else { return .zero }
        return SIMD2(Double(p.x / size.width) * 2 - 1, Double(p.y / size.height) * 2 - 1)
    }

    func zoom(by factor: Double, at p: CGPoint, in size: CGSize) {
        guard size.height > 0, factor.isFinite, factor > 0 else { return }
        autoZoom = false
        homing = false
        lastInput = CACurrentMediaTime()
        let a = Double(size.width / size.height)
        let u = mode3D ? SIMD2<Double>(0, 0) : uv(for: p, in: size)
        let vec = SIMD2(u.x * a, u.y)
        let c = center
        let pv = rotv(vec)
        anchor = DD2(x: c.x + DD(pv.x * scale), y: c.y + DD(pv.y * scale))
        anchorVec = vec
        cursorUV = u
        targetScale = min(max(targetScale / factor, model.minScale), 3.0)
        wake()
    }

    func pan(dx: CGFloat, dy: CGFloat, in size: CGSize) {
        guard size.height > 0 else { return }
        autoZoom = false
        homing = false
        lastInput = CACurrentMediaTime()
        let k = 2.0 * scale / Double(size.height)
        let d = rotv(SIMD2(-Double(dx) * k, Double(dy) * k))
        anchor.x = anchor.x + DD(d.x)
        anchor.y = anchor.y + DD(d.y)
        wake()
    }

    func cursorMoved(to p: CGPoint, in size: CGSize) {
        cursorUV = uv(for: p, in: size)
        aspect = size.height > 0 ? Double(size.width / size.height) : 1
        updateHUD(force: false)
    }

    // MARK: Iteracje

    private func effectiveIterations(for s: Double) -> Int {
        let levels = max(0, log2(model.homeScale / s))
        return Int(min(baseIterations * (1 + 0.35 * levels), 20000))
    }

    // MARK: Orbita referencyjna (double-double)

    private func computeOrbit(at c: DD2, cap: Int) -> ([SIMD2<Float>], [SIMD2<Double>]) {
        var f = [SIMD2<Float>](); f.reserveCapacity(cap + 1)
        var d = [SIMD2<Double>](); d.reserveCapacity(cap + 1)
        f.append(.zero); d.append(.zero)
        var zr = DD(0), zi = DD(0)
        for _ in 0..<cap {
            let zr2 = zr * zr, zi2 = zi * zi, zri = zr * zi
            zr = (zr2 - zi2) + c.x
            zi = zri * 2.0 + c.y
            f.append(SIMD2(Float(zr.hi), Float(zi.hi)))
            d.append(SIMD2(zr.hi, zi.hi))
            if zr.hi * zr.hi + zi.hi * zi.hi > 1e6 { break }
        }
        return (f, d)
    }

    private func probeIterations(dcs: SIMD2<Double>, s: Double, Z: [SIMD2<Double>], cap: Int) -> Int {
        var w = SIMD2<Double>(0, 0)
        var n = 0
        for i in 0..<cap {
            let sw = w * s
            w = 2 * cmul(Z[n], w) + cmul(sw, w) + dcs
            n += 1
            let sw2 = w * s
            let z = Z[n] + sw2
            let m2 = z.x * z.x + z.y * z.y
            if m2 > 65536 { return i }
            if m2 < sw2.x * sw2.x + sw2.y * sw2.y || n >= Z.count - 1 {
                w = z / s
                n = 0
            }
        }
        return cap
    }

    private func prepareOrbit(needed: Int, aspect: Double) {
        let c = center
        let s = scale
        var stale = orbitF.isEmpty || needed > orbitCap
        if !stale {
            let ox = (c.x - orbitCenter.x).hi / s
            let oy = (c.y - orbitCenter.y).hi / s
            stale = max(abs(ox), abs(oy)) > 4
        }
        guard stale else { return }

        let cap = min(Int(Double(needed) * 1.3) + 64, Self.maxOrbit - 1)
        var refC = c
        var (f, d) = computeOrbit(at: refC, cap: cap)

        if f.count < cap + 1 {
            var best = f.count
            var bestVec = SIMD2<Double>(0, 0)
            let g = 3
            for gy in -g...g {
                for gx in -g...g {
                    let vec = rotv(SIMD2(Double(gx) / Double(g) * aspect, Double(gy) / Double(g) * (aspect > 0 ? (mode3D ? Self.span3D : 1) : 1)))
                    let n = probeIterations(dcs: vec, s: s, Z: d, cap: cap)
                    if n > best { best = n; bestVec = vec }
                }
            }
            if best > f.count {
                refC = DD2(x: c.x + DD(bestVec.x * s), y: c.y + DD(bestVec.y * s))
                (f, d) = computeOrbit(at: refC, cap: cap)
            }
        }
        orbitF = f
        orbitD = d
        orbitCenter = refC
        orbitCap = cap
    }

    // MARK: Uniformy

    private func makeUniforms(aspect: Double, pixelsHigh: Int, maxIter: Int, aa: Int, fade: Bool = true) -> FractalUniforms {
        let c = center
        let usesOrbit = model == .mandelbrot
        let ox = usesOrbit ? (c.x - orbitCenter.x).hi / scale : 0
        let oy = usesOrbit ? (c.y - orbitCenter.y).hi / scale : 0
        return FractalUniforms(dcOff: SIMD2(Float(ox), Float(oy)),
                               center: SIMD2(Float(c.x.hi), Float(c.y.hi)),
                               juliaC: SIMD2(Float(juliaRe), Float(juliaIm)),
                               scale: Float(scale),
                               aspect: Float(aspect),
                               pixel: Float(2.0 / Double(max(pixelsHigh, 1))),
                               time: Float(phase),
                               maxIter: Int32(maxIter),
                               palette: Int32(paletteIndex),
                               refLen: Int32(usesOrbit ? orbitF.count : 2),
                               shallow: scale > 1e-3 ? 1 : 0,
                               model: Int32(model.rawValue),
                               power: Int32(power),
                               aa: Int32(aa),
                               colorMode: Int32(colorMode),
                               density: Float(density),
                               shade: Float(shade),
                               glow: Float(glow),
                               palette2: Int32(prevPalette),
                               pmix: fade ? Float(paletteFade * paletteFade * (3 - 2 * paletteFade)) : 0,
                               angle: Float(angleRad),
                               saturation: Float(saturation),
                               contrast: Float(contrast),
                               pitch: Float(pitchDeg * .pi / 180),
                               hscale: Float(heightScale * 0.6 * (mode3D ? Self.span3D : 1)),
                               invert: invert ? 1 : 0,
                               kaleido: Int32(kaleido),
                               interior: (interiorColor || mode3D) ? 1 : 0,
                               span: Float(mode3D ? Self.span3D : 1))
    }

    private func updateHUD(force: Bool) {
        let now = CACurrentMediaTime()
        guard force || now - lastHUD > 0.25 else { return }
        lastHUD = now
        let c = center
        let pv = rotv(SIMD2(cursorUV.x * aspect, cursorUV.y))
        let r = c.x.hi + pv.x * scale
        let i = c.y.hi + pv.y * scale
        let digits = min(17, max(7, Int(ceil(-log10(scale))) + 4))
        let re = String(format: "%+.*f", digits, r)
        let im = String(format: "%+.*f", digits, i)
        let z = model.homeScale / scale
        let zt = z >= 1e4 ? String(format: "%.2e×", z) : String(format: "%.1f×", z)
        let it = "\(effectiveIterations(for: scale))"
        var deg = (angleRad * 180 / .pi).truncatingRemainder(dividingBy: 360)
        if deg > 180 { deg -= 360 } else if deg < -180 { deg += 360 }
        if abs(deg - angleDeg) > 0.05 { syncing = true; angleDeg = deg; syncing = false }
        music?.setDepth(min(1, max(0, log10(max(z, 1)) / 12)))
        if re != realText { realText = re }
        if im != imagText { imagText = im }
        if zt != zoomText { zoomText = zt }
        if it != iterText { iterText = it }
    }

    // MARK: Animacja

    private func step(dt: Double) -> Bool {
        var animating = false

        if autoZoom {
            anchor = center
            anchorVec = .zero
            scale = max(model.minScale, scale * exp(-0.55 * dt))
            targetScale = scale
            animating = true
            if scale <= model.minScale * 1.001 { autoZoom = false }
        } else {
            let a = 1 - exp(-dt * 10)
            if abs(log(scale / targetScale)) > 1e-4 {
                scale = exp(log(scale) + (log(targetScale) - log(scale)) * a)
                animating = true
            } else if scale != targetScale {
                scale = targetScale
            }
            if homing {
                let home = model.homeCenter
                let dx = home.x - anchor.x
                let dy = home.y - anchor.y
                if max(abs(dx.hi), abs(dy.hi)) > 1e-6 * scale {
                    anchor.x = anchor.x + DD(dx.hi * a)
                    anchor.y = anchor.y + DD(dy.hi * a)
                    animating = true
                } else {
                    anchor = home
                    homing = false
                }
            }
        }
        if autoRotate {
            setAngle(angleRad + rotateSpeed * .pi / 180 * dt)
            animating = true
        }
        if paletteFade > 0 {
            paletteFade = max(0, paletteFade - dt / 0.7)
            animating = true
        }
        if cycleColors {
            phase += dt * cycleSpeed
            animating = true
        }
        return animating
    }

    // MARK: MTKViewDelegate

    func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) { wake() }

    var dbgCPU = 0.0, dbgOrbit = 0.0, dbgDrawMax = 0.0
    func draw(in view: MTKView) {
        let now = CACurrentMediaTime()
        defer { let d = (CACurrentMediaTime() - now) * 1000; dbgCPU += d; dbgDrawMax = max(dbgDrawMax, d) }
        let dt = min(now - lastTime, 0.1)
        lastTime = now

        let animating = step(dt: dt)
        let moving = animating || now - lastInput < 0.3
        let backing = view.window?.backingScaleFactor ?? 2
        let f = moving ? moveFactor : 1.0
        lastMoving = moving
        let want = CGSize(width: (view.bounds.width * backing * f).rounded(),
                          height: (view.bounds.height * backing * f).rounded())
        guard want.width >= 1, want.height >= 1 else { return }
        if view.drawableSize != want { view.drawableSize = want }
        aspect = Double(want.width / want.height)

        guard let drawable = view.currentDrawable,
              let rpd = view.currentRenderPassDescriptor else { return }

        let itersFull = effectiveIterations(for: scale)
        let iters = itersFull
        if moving { restStage = 0 }
        if model == .mandelbrot { let t0 = CACurrentMediaTime(); prepareOrbit(needed: iters, aspect: aspect * (mode3D ? Self.span3D : 1)); dbgOrbit += (CACurrentMediaTime() - t0) * 1000 }

        inflight.wait()
        guard let cb = queue.makeCommandBuffer() else { inflight.signal(); return }

        let buf = orbitBuffers[frameIndex % 3]
        frameIndex += 1
        if model == .mandelbrot {
            _ = orbitF.withUnsafeBytes { memcpy(buf.contents(), $0.baseAddress!, $0.count) }
        }

        let aa = (!mode3D && antialias && !moving && restStage >= 1 && restAAOK) ? 2 : 1
        let uni = makeUniforms(aspect: aspect, pixelsHigh: Int(want.height), maxIter: iters, aa: aa)
        var drew = false
        if mode3D, let ftex = fieldTexture(width: min(4096, Int(want.width * 1.5)), height: min(4096, Int(want.height * 1.5))) {
            let fp = MTLRenderPassDescriptor()
            fp.colorAttachments[0].texture = ftex
            fp.colorAttachments[0].loadAction = .dontCare
            fp.colorAttachments[0].storeAction = .store
            if let e1 = cb.makeRenderCommandEncoder(descriptor: fp) {
                encode(e1, uniforms: uni, orbit: buf, pipelineOverride: fieldPipeline)
                e1.endEncoding()
                if let bl = cb.makeBlitCommandEncoder() { bl.generateMipmaps(for: ftex); bl.endEncoding() }
                if let enc = cb.makeRenderCommandEncoder(descriptor: rpd) {
                    encodeMesh(enc, uniforms: uni, tex: ftex)
                    enc.endEncoding()
                    drew = true
                }
            }
        }
        if !drew {
            guard let enc = cb.makeRenderCommandEncoder(descriptor: rpd) else { inflight.signal(); return }
            encode(enc, uniforms: uni, orbit: buf)
            enc.endEncoding()
        }
        cb.present(drawable)
        let sem = inflight
        let wasMoving = moving
        cb.addCompletedHandler { [weak self] cb in
            sem.signal()
            let ms = (cb.gpuEndTime - cb.gpuStartTime) * 1000
            DispatchQueue.main.async {
                guard let self = self else { return }
                if !wasMoving, aa == 1, ms > 0.5 { self.restAAOK = ms * 4 < 120 }
                if self.lastMoving, ms > 0.5 {
                    // Histereza: zmiana rozdzielczości = realokacja drawable, więc zmieniamy ją rzadko.
                    if ms > 6.5 { self.slowCount += 1; self.fastCount = 0 }
                    else if ms < 2.8 { self.fastCount += 1; self.slowCount = 0 }
                    else { self.slowCount = 0; self.fastCount = 0 }
                    if self.slowCount >= 2, self.moveLevel > 0 { self.moveLevel -= 1; self.slowCount = 0 }
                    if self.fastCount >= 120, self.moveLevel < 5 { self.moveLevel += 1; self.fastCount = 0 }
                }
                if self.debug { self.logFrame(gpuMs: ms, size: want, iters: iters) }
            }
        }
        cb.commit()

        updateHUD(force: !moving)
        if !moving {
            if restStage == 0 && antialias && restAAOK { restStage = 1 }
            else { restStage = 2; view.isPaused = true }
        }
    }

    private func logFrame(gpuMs: Double, size: CGSize, iters: Int) {
        dbgFrames += 1
        dbgGPU += gpuMs
        let t = CACurrentMediaTime()
        if t - dbgStart >= 1 {
            FileHandle.standardError.write(Data(String(
                format: "fps %.0f  gpu %.1f  cpu %.1f (max %.1f, orbita łącznie %.1f) ms  %dx%d  iter %d  zoom %.3g\n",
                Double(dbgFrames) / (t - dbgStart), dbgGPU / Double(dbgFrames), dbgCPU / Double(dbgFrames), dbgDrawMax, dbgOrbit,
                Int(size.width), Int(size.height), iters, model.homeScale / scale).utf8))
            dbgFrames = 0; dbgGPU = 0; dbgCPU = 0; dbgOrbit = 0; dbgDrawMax = 0; dbgStart = t
        }
    }

    private func fieldTexture(width: Int, height: Int) -> MTLTexture? {
        if let t = fieldTex, t.width == width, t.height == height { return t }
        let d = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .rgba16Float, width: width, height: height, mipmapped: true)
        d.usage = [.renderTarget, .shaderRead]
        d.storageMode = .private
        fieldTex = device.makeTexture(descriptor: d)
        return fieldTex
    }

    private func encodeMesh(_ enc: MTLRenderCommandEncoder, uniforms: FractalUniforms, tex: MTLTexture) {
        var u = uniforms
        var pal = Palettes.packed()
        let palLen = pal.count * MemoryLayout<SIMD4<Float>>.stride
        enc.setRenderPipelineState(skyPipeline)
        enc.setFragmentBytes(&u, length: MemoryLayout<FractalUniforms>.stride, index: 0)
        enc.setFragmentBytes(&pal, length: palLen, index: 2)
        enc.drawPrimitives(type: .triangleStrip, vertexStart: 0, vertexCount: 4)
        enc.setRenderPipelineState(meshPipeline)
        enc.setFragmentBytes(&pal, length: palLen, index: 2)
        enc.setVertexBytes(&u, length: MemoryLayout<FractalUniforms>.stride, index: 0)
        enc.setVertexTexture(tex, index: 0)
        enc.setFragmentBytes(&u, length: MemoryLayout<FractalUniforms>.stride, index: 0)
        enc.setFragmentTexture(tex, index: 0)
        enc.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 320 * 320 * 6)
    }

    private func encode(_ enc: MTLRenderCommandEncoder, uniforms: FractalUniforms, orbit: MTLBuffer,
                        pipelineOverride: MTLRenderPipelineState? = nil) {
        var u = uniforms
        var pal = Palettes.packed()
        enc.setRenderPipelineState(pipelineOverride ?? pipeline)
        enc.setFragmentBytes(&u, length: MemoryLayout<FractalUniforms>.stride, index: 0)
        enc.setFragmentBuffer(orbit, offset: 0, index: 1)
        enc.setFragmentBytes(&pal, length: pal.count * MemoryLayout<SIMD4<Float>>.stride, index: 2)
        enc.drawPrimitives(type: .triangleStrip, vertexStart: 0, vertexCount: 4)
    }

    // MARK: Eksport PNG

    func renderImage(longSide requested: Int) -> CGImage? {
        let is3D = mode3D
        let longSide = is3D ? min(requested, 3840) : requested
        let ds = view?.bounds.size ?? .zero
        let asp = (ds.width > 0 && ds.height > 0) ? Double(ds.width / ds.height) : 16.0 / 9.0
        let width = asp >= 1 ? longSide : Int((Double(longSide) * asp).rounded())
        let height = asp >= 1 ? Int((Double(longSide) / asp).rounded()) : longSide

        let iters = effectiveIterations(for: scale)
        if model == .mandelbrot { prepareOrbit(needed: iters, aspect: asp) }
        if orbitF.isEmpty { orbitF = [.zero, .zero] }
        guard let orbitBuf = orbitF.withUnsafeBytes({ device.makeBuffer(bytes: $0.baseAddress!, length: $0.count, options: .storageModeShared) })
        else { return nil }

        let desc = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .bgra8Unorm,
                                                            width: width, height: height, mipmapped: false)
        desc.usage = [.renderTarget]
        desc.storageMode = .shared
        guard let tex = device.makeTexture(descriptor: desc) else { return nil }

        let u = makeUniforms(aspect: asp, pixelsHigh: height, maxIter: iters, aa: (antialias && !is3D) ? 2 : 1, fade: false)
        var ftex: MTLTexture?
        if is3D {
            let fd = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .rgba16Float, width: width, height: height, mipmapped: true)
            fd.usage = [.renderTarget, .shaderRead]
            fd.storageMode = .private
            ftex = device.makeTexture(descriptor: fd)
            if ftex == nil { return nil }
        }
        let bands = max(16, height / 64)
        for b in 0..<bands {
            let y0 = height * b / bands
            let y1 = height * (b + 1) / bands
            let rpd = MTLRenderPassDescriptor()
            rpd.colorAttachments[0].texture = is3D ? ftex! : tex
            rpd.colorAttachments[0].loadAction = b == 0 ? .clear : .load
            rpd.colorAttachments[0].storeAction = .store
            rpd.colorAttachments[0].clearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 1)
            guard let cb = queue.makeCommandBuffer(),
                  let enc = cb.makeRenderCommandEncoder(descriptor: rpd) else { return nil }
            enc.setScissorRect(MTLScissorRect(x: 0, y: y0, width: width, height: y1 - y0))
            encode(enc, uniforms: u, orbit: orbitBuf, pipelineOverride: is3D ? fieldPipeline : nil)
            enc.endEncoding()
            cb.commit()
            cb.waitUntilCompleted()
        }
        if is3D, let ftex = ftex {
            if let cb = queue.makeCommandBuffer(), let bl = cb.makeBlitCommandEncoder() {
                bl.generateMipmaps(for: ftex); bl.endEncoding(); cb.commit(); cb.waitUntilCompleted()
            }
            let rpd = MTLRenderPassDescriptor()
            rpd.colorAttachments[0].texture = tex
            rpd.colorAttachments[0].loadAction = .clear
            rpd.colorAttachments[0].storeAction = .store
            rpd.colorAttachments[0].clearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 1)
            guard let cb = queue.makeCommandBuffer(),
                  let enc = cb.makeRenderCommandEncoder(descriptor: rpd) else { return nil }
            encodeMesh(enc, uniforms: u, tex: ftex)
            enc.endEncoding()
            cb.commit()
            cb.waitUntilCompleted()
        }

        var pixels = [UInt8](repeating: 0, count: width * height * 4)
        tex.getBytes(&pixels, bytesPerRow: width * 4,
                     from: MTLRegionMake2D(0, 0, width, height), mipmapLevel: 0)

        let info = CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue
        return pixels.withUnsafeMutableBytes { buf -> CGImage? in
            guard let ctx = CGContext(data: buf.baseAddress, width: width, height: height,
                                      bitsPerComponent: 8, bytesPerRow: width * 4,
                                      space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                      bitmapInfo: info) else { return nil }
            return ctx.makeImage()
        }
    }

    func saveSnapshot(_ size: ExportSize) {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.png]
        panel.nameFieldStringValue = "\(tr("Fraktal", "Fractal"))-\(model.title).png"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        isExporting = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { [weak self] in
            guard let self = self else { return }
            defer { self.isExporting = false }
            guard let image = self.renderImage(longSide: size.rawValue),
                  let data = NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:]) else {
                NSSound.beep(); return
            }
            do { try data.write(to: url) } catch { NSAlert(error: error).runModal() }
        }
    }

    // MARK: Hooki testowe (zmienne środowiskowe)

    private var hooksRan = false
    static var headless: FractalRenderer?

    /// Tryb testowy bez okna (MANDELBROT_SHOT + MANDELBROT_HEADLESS).
    static func runHeadlessIfRequested() {
        let env = ProcessInfo.processInfo.environment
        guard env["MANDELBROT_SHOT"] != nil, env["MANDELBROT_HEADLESS"] != nil else { return }
        let r = FractalRenderer()
        headless = r
        r.runTestHooks()
    }

    private func runTestHooks() {
        guard !hooksRan else { return }
        hooksRan = true
        let env = ProcessInfo.processInfo.environment
        if let spec = env["MANDELBROT_SHOT"] {
            // "model,re,im,zoom,paleta,tryb,shade,glow,ścieżka.png[,jre,jim,power]"
            let p = spec.split(separator: ",").map(String.init)
            guard p.count >= 9, let m = Int(p[0]), let re = Double(p[1]), let im = Double(p[2]),
                  let z = Double(p[3]), let pal = Int(p[4]), let cm = Int(p[5]),
                  let sh = Double(p[6]), let gl = Double(p[7]) else { return }
            suppressHome = true
            model = FractalModel(rawValue: m) ?? .mandelbrot
            suppressHome = false
            anchor = DD2(x: DD(re), y: DD(im)); anchorVec = .zero
            scale = model.homeScale / z; targetScale = scale
            paletteIndex = pal; colorMode = cm; shade = sh; glow = gl
            if p.count >= 12, let a = Double(p[9]), let b = Double(p[10]), let pw = Int(p[11]) {
                juliaRe = a; juliaIm = b; power = pw
            }
            if let extra = env["MANDELBROT_EXTRA"] {
                for kv in extra.split(separator: ";") {
                    let t = kv.split(separator: "=").map(String.init)
                    guard t.count == 2, let v = Double(t[1]) else { continue }
                    switch t[0] {
                    case "angle": setAngle(v * .pi / 180)
                    case "mode3d": mode3D = v != 0
                    case "pitch": pitchDeg = v
                    case "height": heightScale = v
                    case "kaleido": kaleido = Int(v)
                    case "interior": interiorColor = v != 0
                    case "sat": saturation = v
                    case "contrast": contrast = v
                    case "invert": invert = v != 0
                    case "music": musicOn = v != 0; musicVolume = 0.5
                    default: break
                    }
                }
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { [weak self] in
                guard let self = self else { return }
                if let img = self.renderImage(longSide: 1000) {
                    try? NSBitmapImageRep(cgImage: img).representation(using: .png, properties: [:])?
                        .write(to: URL(fileURLWithPath: p[8]))
                }
                if let m = self.music { FileHandle.standardError.write(Data("music peak \(m.peak)\n".utf8)) }
                exit(0)
            }
        }
        if env["MANDELBROT_ZOOMTEST"] != nil {
            anchor = DD2(x: DD(-0.7436438870371587), y: DD(0.1318259042053119)); anchorVec = .zero
            let start = CACurrentMediaTime()
            Timer.scheduledTimer(withTimeInterval: 1.0 / 60.0, repeats: true) { [weak self] _ in
                guard let self = self, let v = self.view else { return }
                self.zoom(by: 1.04, at: CGPoint(x: v.bounds.midX, y: v.bounds.midY), in: v.bounds.size)
                if CACurrentMediaTime() - start > 8 { exit(0) }
            }
        }
    }
}
