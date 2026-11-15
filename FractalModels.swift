import SwiftUI

// MARK: - Modele fraktali

enum FractalModel: Int, CaseIterable, Identifiable {
    case mandelbrot, burningShip, tricorn, multibrot, julia, newton

    var id: Int { rawValue }

    var title: String {
        switch self {
        case .mandelbrot:  return "Mandelbrot"
        case .burningShip: return tr("Płonący statek", "Burning Ship")
        case .tricorn:     return "Tricorn"
        case .multibrot:   return "Multibrot"
        case .julia:       return "Julia"
        case .newton:      return "Newton z³−1"
        }
    }

    var symbol: String {
        switch self {
        case .mandelbrot:  return "circle.hexagongrid"
        case .burningShip: return "flame"
        case .tricorn:     return "triangle"
        case .multibrot:   return "asterisk"
        case .julia:       return "sparkles"
        case .newton:      return "function"
        }
    }

    var homeCenter: DD2 {
        switch self {
        case .mandelbrot:  return DD2(x: DD(-0.5), y: DD(0))
        case .burningShip: return DD2(x: DD(-0.4), y: DD(0.5))
        case .tricorn:     return DD2(x: DD(-0.3), y: DD(0))
        case .multibrot, .julia, .newton: return DD2(x: DD(0), y: DD(0))
        }
    }

    var homeScale: Double {
        switch self {
        case .mandelbrot:  return 1.5
        case .burningShip: return 1.35
        case .tricorn:     return 1.7
        case .multibrot:   return 1.5
        case .julia:       return 1.55
        case .newton:      return 1.7
        }
    }

    /// Mandelbrot używa perturbacji (głęboki zoom); reszta liczy bezpośrednio w float32.
    var minScale: Double { self == .mandelbrot ? 1e-25 : 4e-5 }
    var supportsPower: Bool { self == .multibrot || self == .julia }
    var supportsColorMode: Bool { self != .newton }
}

// MARK: - Palety (jedno źródło prawdy dla shadera i podglądów w UI)

struct PaletteDef {
    let pl: String
    let en: String
    var name: String { tr(pl, en) }
    var colors: [SIMD3<Float>]
}

private func rgb(_ r: Float, _ g: Float, _ b: Float) -> SIMD3<Float> { SIMD3(r, g, b) / 255 }

enum Palettes {
    static let customIndex = 8
    static let count = 9

    static let defaultCustom: [SIMD3<Float>] = [
        rgb(8, 8, 40), rgb(60, 90, 220), rgb(120, 240, 220), rgb(250, 240, 140), rgb(240, 90, 90), rgb(60, 10, 70)
    ]

    static var all: [PaletteDef] = [
        PaletteDef(pl: "Klasyczny", en: "Classic", colors: [rgb(0, 7, 100), rgb(32, 107, 203), rgb(237, 255, 255), rgb(255, 170, 0), rgb(0, 2, 0)]),
        PaletteDef(pl: "Zorza", en: "Aurora", colors: [rgb(2, 6, 23), rgb(6, 40, 90), rgb(0, 140, 140), rgb(40, 220, 150), rgb(160, 255, 170), rgb(90, 110, 220), rgb(120, 40, 170), rgb(20, 10, 60)]),
        PaletteDef(pl: "Ogień", en: "Fire", colors: [rgb(10, 0, 0), rgb(120, 10, 0), rgb(235, 70, 0), rgb(255, 190, 30), rgb(255, 250, 200), rgb(90, 20, 10)]),
        PaletteDef(pl: "Kosmos", en: "Cosmos", colors: [rgb(5, 0, 20), rgb(40, 10, 100), rgb(120, 30, 170), rgb(230, 90, 190), rgb(255, 190, 220), rgb(80, 200, 255), rgb(10, 40, 110)]),
        PaletteDef(pl: "Lód", en: "Ice", colors: [rgb(2, 10, 30), rgb(20, 70, 140), rgb(120, 190, 240), rgb(235, 250, 255), rgb(150, 200, 235), rgb(40, 90, 160)]),
        PaletteDef(pl: "Neon", en: "Neon", colors: [rgb(10, 0, 30), rgb(255, 0, 128), rgb(0, 229, 255), rgb(124, 255, 0), rgb(255, 230, 0), rgb(40, 0, 90)]),
        PaletteDef(pl: "Zachód", en: "Sunset", colors: [rgb(20, 5, 40), rgb(90, 20, 100), rgb(200, 50, 90), rgb(255, 130, 50), rgb(255, 215, 120), rgb(120, 40, 80)]),
        PaletteDef(pl: "Mono", en: "Mono", colors: [rgb(0, 0, 0), rgb(60, 60, 60), rgb(200, 200, 200), rgb(255, 255, 255), rgb(120, 120, 120), rgb(20, 20, 20)]),
        PaletteDef(pl: "Własna", en: "Custom", colors: defaultCustom)
    ]

    /// Dane dla shadera: 9 palet × 8 float4; w pierwszego koloru = liczba kolorów.
    static func packed() -> [SIMD4<Float>] {
        var out = [SIMD4<Float>](repeating: .zero, count: count * 8)
        for (pi, p) in all.enumerated() {
            let n = min(p.colors.count, 8)
            for i in 0..<8 {
                let c = p.colors[i % max(n, 1)]
                out[pi * 8 + i] = SIMD4(c.x, c.y, c.z, i == 0 ? Float(n) : 0)
            }
        }
        return out
    }

    static func gradient(_ p: PaletteDef) -> LinearGradient {
        var cols = p.colors.map { Color(red: Double($0.x), green: Double($0.y), blue: Double($0.z)) }
        if let f = cols.first { cols.append(f) }
        return LinearGradient(colors: cols, startPoint: .leading, endPoint: .trailing)
    }
}

// MARK: - Zapisane widoki

/// Wszystkie ustawienia wyglądu zapisywane razem z miejscem, żeby wrócić do dokładnie tego samego widoku.
struct LookSettings: Codable, Equatable {
    var angle = 0.0
    var colorMode = 0
    var density = 1.0
    var shade = 0.0
    var glow = 0.0
    var saturation = 1.0
    var contrast = 1.0
    var invert = false
    var kaleido = 0
    var interior = false
    var mode3D = false
    var pitch = 66.0
    var height = 0.35
    var autoRotate = false
    var rotateSpeed = 8.0
    var antialias = true
    var cycleColors = false
    var cycleSpeed = 0.15
    var baseIterations = 300.0
    var phase = 0.0
    var customColors: [[Float]] = []   // 6 × RGB własnej palety
}

struct SavedView: Codable, Identifiable, Equatable {
    var id = UUID()
    var name: String
    var model: Int
    var reHi: Double, reLo: Double
    var imHi: Double, imLo: Double
    var scale: Double
    var palette: Int
    var juliaRe: Double = -0.8
    var juliaIm: Double = 0.156
    var power: Int = 3
    var look: LookSettings? = nil   // nil = miejsce bez ustawień wyglądu (np. gotowe miejsca, stare ulubione)
}

struct Preset: Identifiable {
    let id = UUID()
    let pl: String
    let en: String
    var name: String { tr(pl, en) }
    let view: SavedView

    static func make(_ name: String, _ en: String, model: FractalModel = .mandelbrot, re: Double, im: Double, zoom: Double,
                     palette: Int, jre: Double = -0.8, jim: Double = 0.156, power: Int = 3) -> Preset {
        Preset(pl: name, en: en, view: SavedView(name: name, model: model.rawValue,
                                           reHi: re, reLo: 0, imHi: im, imLo: 0,
                                           scale: model.homeScale / zoom, palette: palette,
                                           juliaRe: jre, juliaIm: jim, power: power))
    }

    static let builtIn: [Preset] = [
        .make("Dolina konika", "Seahorse Valley", re: -0.743643887037151, im: 0.131825904205330, zoom: 3e11, palette: 1),
        .make("Spirale", "Spirals", re: -0.7453, im: 0.1127, zoom: 4000, palette: 0),
        .make("Minibrot", "Minibrot", re: -1.76877883, im: -0.00173899, zoom: 60000, palette: 5),
        .make("Statek", "Ship", model: .burningShip, re: -1.762, im: 0.028, zoom: 60, palette: 2),
        .make("Julia: dendryty", "Julia: dendrites", model: .julia, re: 0, im: 0, zoom: 1, palette: 3, jre: -0.8, jim: 0.156),
        .make("Julia: królik", "Julia: rabbit", model: .julia, re: 0, im: 0, zoom: 1, palette: 4, jre: -0.123, jim: 0.745),
        .make("Multibrot z³", "Multibrot z³", model: .multibrot, re: 0, im: 0, zoom: 1, palette: 6, power: 3),
        .make("Newton", "Newton", model: .newton, re: 0, im: 0, zoom: 1, palette: 5)
    ]
}
