import SwiftUI
import AppKit

/// Gotowe „style" – jednym kliknięciem ustawiają paletę, efekty i (opcjonalnie) tryb 3D.
struct Look: Identifiable {
    let id: Int
    let pl: String, en: String
    var name: String { tr(pl, en) }
    let apply: (FractalRenderer) -> Void

    static let all: [Look] = [
        Look(id: 0, pl: "Klasyczny", en: "Classic") { r in r.resetLook(); r.paletteIndex = 0 },
        Look(id: 1, pl: "Neon", en: "Neon") { r in r.resetLook(); r.paletteIndex = 5; r.glow = 0.6; r.shade = 0.4; r.contrast = 1.2; r.saturation = 1.3 },
        Look(id: 2, pl: "Relief", en: "Relief") { r in r.resetLook(); r.paletteIndex = 7; r.shade = 0.85; r.glow = 0.1; r.contrast = 1.2 },
        Look(id: 3, pl: "Ogień", en: "Fire") { r in r.resetLook(); r.paletteIndex = 2; r.glow = 0.5; r.shade = 0.5; r.interiorColor = true },
        Look(id: 4, pl: "Lód", en: "Ice") { r in r.resetLook(); r.paletteIndex = 4; r.shade = 0.6; r.contrast = 1.1 },
        Look(id: 5, pl: "Kalejdoskop", en: "Kaleidoscope") { r in
            r.resetLook(); r.paletteIndex = 3; r.kaleido = 6; r.interiorColor = true; r.glow = 0.3; r.rotateSpeed = 6; r.autoRotate = true },
        Look(id: 6, pl: "Zorza 3D", en: "Aurora 3D") { r in
            r.resetLook(); r.paletteIndex = 1; r.glow = 0.2; r.pitchDeg = 68; r.heightScale = 0.4; r.mode3D = true },
        Look(id: 7, pl: "Zachód słońca 3D", en: "Sunset 3D") { r in
            r.resetLook(); r.paletteIndex = 6; r.pitchDeg = 74; r.heightScale = 0.45; r.mode3D = true; r.autoRotate = true; r.rotateSpeed = 4 }
    ]
}

extension FractalRenderer {
    /// Przywraca neutralne ustawienia wyglądu (bez zmiany pozycji i modelu).
    func resetLook() {
        shade = 0; glow = 0; saturation = 1; contrast = 1; invert = false
        kaleido = 0; interiorColor = false; density = 1; cycleColors = false
        autoRotate = false; mode3D = false
    }

    /// Losowy zestaw: miejsce + styl.
    func surprise() {
        if let p = Preset.builtIn.randomElement() { go(to: p.view) }
        Look.all.randomElement()?.apply(self)
        if Bool.random() { randomPalette() }
    }

    /// Losowa, harmonijna własna paleta.
    func randomPalette() {
        let h0 = Double.random(in: 0..<1)
        let spread = Double.random(in: 0.12...0.4)
        var cols: [Color] = []
        for i in 0..<6 {
            let f = Double(i) / 5.0
            let h = (h0 + f * spread + (i % 2 == 0 ? 0 : 0.5 * Double.random(in: 0...0.5))).truncatingRemainder(dividingBy: 1)
            let s = 0.55 + 0.4 * Double.random(in: 0...1)
            let b = i == 0 || i == 5 ? 0.12 + 0.2 * Double.random(in: 0...1) : 0.55 + 0.45 * Double.random(in: 0...1)
            cols.append(Color(hue: h, saturation: s, brightness: b))
        }
        customColors = cols
    }

    /// Wycieczka: co kilkanaście sekund przeskakuje do następnego miejsca.
    func setTour(_ on: Bool) {
        tourTimer?.invalidate(); tourTimer = nil
        tourOn = on
        guard on else { return }
        tourNext()
        tourTimer = Timer.scheduledTimer(withTimeInterval: 14, repeats: true) { [weak self] _ in self?.tourNext() }
    }

    private func tourNext() {
        let all = Preset.builtIn.map(\.view) + favorites
        guard !all.isEmpty else { return }
        tourIndex = (tourIndex + 1) % all.count
        go(to: all[tourIndex])
        autoZoom = all[tourIndex].model == FractalModel.mandelbrot.rawValue && all[tourIndex].scale > 1e-6
    }

    func copyCoordinatesToPasteboard() {
        let text = coordinatesString()
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }

    func copyImageToPasteboard() {
        isExporting = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { [weak self] in
            guard let self = self else { return }
            defer { self.isExporting = false }
            guard let image = self.renderImage(longSide: 2400) else { NSSound.beep(); return }
            NSPasteboard.general.clearContents()
            NSPasteboard.general.writeObjects([NSImage(cgImage: image, size: .zero)])
        }
    }
}
