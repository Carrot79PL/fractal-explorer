import SwiftUI

struct ContentView: View {
    @AppStorage("lang") private var lang = Lang.current
    @StateObject private var renderer = FractalRenderer()
    @State private var showUI = true
    @State private var showInspector = true

    var body: some View {
        ZStack {
            MetalFractalView(renderer: renderer)
                .ignoresSafeArea()

            // Warstwa interfejsu: ukrywana przezroczystością (układ się nie zmienia, nic nie znika z hierarchii).
            VStack(spacing: 12) {
                HStack(alignment: .top) {
                    hud
                    Spacer()
                    Color.clear.frame(width: 260, height: 40)
                }
                HStack(alignment: .top) {
                    Spacer()
                    if showInspector { Inspector(renderer: renderer) }
                }
                .frame(maxHeight: .infinity, alignment: .top)
                toolbar
            }
            .padding(20)
            .opacity(showUI ? 1 : 0)
            .allowsHitTesting(showUI)
            .animation(.smooth(duration: 0.3), value: showUI)
            .animation(.smooth(duration: 0.3), value: showInspector)

            // Ukryte skróty klawiszowe (działają także przy ukrytym interfejsie).
            Group {
                Button("") { renderer.rotateBy(degrees: 5) }.keyboardShortcut("q", modifiers: [])
                Button("") { renderer.rotateBy(degrees: -5) }.keyboardShortcut("e", modifiers: [])
                Button("") { renderer.mode3D.toggle() }.keyboardShortcut("d", modifiers: [])
                Button("") { renderer.musicOn.toggle() }.keyboardShortcut("m", modifiers: [])
            }
            .frame(width: 0, height: 0)
            .opacity(0)

            // Przyciski w rogu: zawsze na wierzchu i zawsze klikalne.
            VStack {
                HStack { Spacer(); topButtons }
                Spacer()
            }
            .padding(20)

            if renderer.isExporting {
                VStack(spacing: 10) {
                    ProgressView()
                    Text(tr("Renderowanie obrazu…", "Rendering image…")).font(.callout)
                }
                .padding(24)
                .glassCard()
            }
        }
        .frame(minWidth: 960, minHeight: 560)
        .background(Color.black)
    }

    // MARK: HUD

    private var hud: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Image(systemName: renderer.model.symbol)
                Text(renderer.model.title).fontWeight(.semibold)
            }
            .font(.callout)
            .padding(.bottom, 2)
            hudRow("Re", renderer.realText)
            hudRow("Im", renderer.imagText + " i")
            hudRow("Zoom", renderer.zoomText)
            hudRow("Iter", renderer.iterText)
            if abs(renderer.angleDeg) > 0.5 { hudRow(tr("Kąt", "Angle"), String(format: "%.0f°", renderer.angleDeg)) }
            Text(tr("Autor: Tomasz Marchewka", "Author: Tomasz Marchewka"))
                .font(.system(size: 9))
                .foregroundStyle(.secondary)
                .padding(.top, 3)
        }
        .font(.system(.caption, design: .monospaced))
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .glassCard()
        .opacity(0.9)
        .allowsHitTesting(false)
    }

    private func hudRow(_ label: String, _ value: String) -> some View {
        HStack(spacing: 8) {
            Text(label).foregroundStyle(.secondary).frame(width: 34, alignment: .leading)
            Text(value).foregroundStyle(.primary)
        }
    }

    // MARK: Przyciski w rogu (zawsze widoczne)

    private var topButtons: some View {
        HStack(spacing: 8) {
            Button { lang = (lang == "pl" ? "en" : "pl") } label: {
                Text(lang == "pl" ? "PL" : "EN")
                    .font(.system(size: 12, weight: .semibold))
                    .frame(width: 20, height: 20)
                    .padding(10)
                    .glassCapsule()
                    .contentShape(Capsule())
            }
            .buttonStyle(.plain)
            .help(tr("Język: polski (kliknij, aby zmienić na English)", "Language: English (click to switch to Polski)"))
            RoundButton(symbol: "cube", help: tr("Krajobraz 3D (D)", "3D landscape (D)"), active: renderer.mode3D) {
                renderer.mode3D.toggle()
            }
            .opacity(showUI ? 1 : 0)
            .allowsHitTesting(showUI)
            RoundButton(symbol: renderer.musicOn ? "speaker.wave.2.fill" : "speaker.slash", help: tr("Muzyka ambient (M)", "Ambient music (M)"), active: renderer.musicOn) {
                renderer.musicOn.toggle()
            }
            .opacity(showUI ? 1 : 0)
            .allowsHitTesting(showUI)
            RoundButton(symbol: "sidebar.right", help: tr("Panel ustawień (I)", "Settings panel (I)"), active: showInspector) {
                if !showUI { showUI = true }
                showInspector.toggle()
            }
            .keyboardShortcut("i", modifiers: [])
            .opacity(showUI ? 1 : 0)
            .allowsHitTesting(showUI)
            RoundButton(symbol: showUI ? "eye.slash" : "eye", help: showUI ? tr("Ukryj interfejs (H)", "Hide interface (H)") : tr("Pokaż interfejs (H)", "Show interface (H)")) {
                showUI.toggle()
            }
            .keyboardShortcut("h", modifiers: [])
            .opacity(showUI ? 1 : 0.55)
        }
        .animation(.smooth(duration: 0.3), value: showUI)
    }

    // MARK: Pasek narzędzi

    private var toolbar: some View {
        HStack(spacing: 14) {
            Menu {
                ForEach(FractalModel.allCases) { m in
                    Button { renderer.model = m } label: {
                        Label(m.title, systemImage: m.symbol)
                    }
                    .keyboardShortcut(KeyEquivalent(Character("\(m.rawValue + 1)")), modifiers: [])
                }
            } label: {
                Label(renderer.model.title, systemImage: renderer.model.symbol)
                    .frame(minWidth: 120, alignment: .leading)
            }
            .menuStyle(.borderlessButton)
            .fixedSize()

            Divider().frame(height: 22)

            HStack(spacing: 5) {
                ForEach(0..<Palettes.count, id: \.self) { i in
                    PaletteChip(index: i, selected: renderer.paletteIndex == i)
                        .frame(width: 26, height: 16)
                        .onTapGesture { renderer.paletteIndex = i }
                        .help(Palettes.all[i].name)
                }
            }

            Divider().frame(height: 22)

            HStack(spacing: 8) {
                Image(systemName: "dial.low").foregroundStyle(.secondary)
                Slider(value: $renderer.baseIterations, in: 50...3000).frame(width: 110)
                Text("\(Int(renderer.baseIterations))")
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .frame(width: 34, alignment: .trailing)
            }
            .help(tr("Bazowa liczba iteracji (rośnie automatycznie z powiększeniem)", "Base iteration count (grows automatically with zoom)"))

            Divider().frame(height: 22)

            Button { renderer.autoZoom.toggle() } label: {
                Image(systemName: renderer.autoZoom ? "pause.fill" : "play.fill")
            }
            .keyboardShortcut(.space, modifiers: [])
            .help(tr("Film: automatyczne powiększanie do środka widoku (spacja)", "Movie: automatic zoom into the view center (space)"))

            Button { renderer.resetView() } label: { Image(systemName: "arrow.counterclockwise") }
                .keyboardShortcut("r", modifiers: [])
                .help(tr("Resetuj widok (R)", "Reset view (R)"))

            Button { renderer.saveFavorite() } label: { Image(systemName: "star") }
                .help(tr("Dodaj bieżący widok do ulubionych", "Add current view to favorites"))

            Menu {
                ForEach(ExportSize.allCases) { s in
                    Button(s.title) { renderer.saveSnapshot(s) }
                }
            } label: {
                Image(systemName: "square.and.arrow.down")
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
            .help(tr("Zapisz kadr jako PNG", "Save frame as PNG"))
        }
        .buttonStyle(.plain)
        .font(.system(size: 14, weight: .medium))
        .padding(.horizontal, 20)
        .padding(.vertical, 11)
        .glassCapsule()
    }
}

// MARK: - Panel boczny

private struct Inspector: View {
    @AppStorage("lang") private var lang = Lang.current
    @ObservedObject var renderer: FractalRenderer

    @State private var tab = 0
    private var tabs: [(String, String)] = [("Model", "square.stack.3d.up"), (tr("Kolor", "Color"), "paintpalette"),
                                            (tr("Efekty", "Effects"), "wand.and.stars"),
                                            (tr("Widok", "View"), "rotate.3d"), (tr("Miejsca", "Places"), "star")]

    var body: some View {
        VStack(spacing: 10) {
            HStack(spacing: 4) {
                ForEach(tabs.indices, id: \.self) { i in
                    Button { tab = i } label: {
                        VStack(spacing: 2) {
                            Image(systemName: tabs[i].1).font(.system(size: 14))
                            Text(tabs[i].0).font(.system(size: 10, weight: .medium))
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 6)
                        .foregroundStyle(tab == i ? Color.primary : Color.secondary)
                        .background(tab == i ? Color.white.opacity(0.16) : .clear,
                                    in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(4)
            .glassCard()

            // Zawartość zakładki mieści się bez przewijania; przewijanie tylko awaryjnie (np. bardzo dużo ulubionych).
            ViewThatFits(in: .vertical) {
                current
                ScrollView(showsIndicators: false) { current }
            }
        }
        .frame(width: 292)
    }

    @ViewBuilder private var current: some View {
        switch tab {
        case 0: modelSection
        case 1: colorSection
        case 2: effectsSection
        case 3: viewSection
        default: viewsSection
        }
    }

    // MARK: Model
    private var modelSection: some View {
        Card(title: "Model", symbol: "square.stack.3d.up") {
            Picker("Model", selection: $renderer.model) {
                ForEach(FractalModel.allCases) { m in Text(m.title).tag(m) }
            }
            .labelsHidden()

            if renderer.model.supportsPower {
                Stepper(value: $renderer.power, in: 2...8) {
                    Text(tr("Potęga z", "Power z") + superscript(renderer.power)).font(.callout)
                }
            }
            if renderer.model == .julia {
                SliderRow("c Re", value: $renderer.juliaRe, range: -2...2, format: "%+.3f")
                SliderRow("c Im", value: $renderer.juliaIm, range: -2...2, format: "%+.3f")
            }
            if renderer.model == .mandelbrot {
                Button { renderer.juliaFromCursor() } label: {
                    Label(tr("Julia z punktu pod kursorem", "Julia from point under cursor"), systemImage: "sparkles")
                        .frame(maxWidth: .infinity)
                }
                .keyboardShortcut("j", modifiers: [])
                .buttonStyle(.bordered)
                .controlSize(.small)
                .help(tr("Przesuń kursor nad wybrany punkt i naciśnij J", "Move the cursor over a point and press J"))
            }
            if renderer.model != .mandelbrot {
                Text(tr("Zoom do ok. 4·10⁴× (precyzja float). Głęboki zoom: Mandelbrot.", "Zoom up to ~4·10⁴× (float precision). Deep zoom: Mandelbrot only."))
                    .font(.caption2).foregroundStyle(.secondary)
            }
        }
    }

    // MARK: Kolor
    private var colorSection: some View {
        Card(title: tr("Kolor", "Color"), symbol: "paintpalette") {
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 6), count: 3), spacing: 6) {
                ForEach(0..<Palettes.count, id: \.self) { i in
                    VStack(spacing: 2) {
                        PaletteChip(index: i, selected: renderer.paletteIndex == i).frame(height: 24)
                        Text(Palettes.all[i].name).font(.system(size: 9)).foregroundStyle(.secondary)
                    }
                    .onTapGesture { renderer.paletteIndex = i }
                }
            }
            if renderer.model.supportsColorMode {
                Picker(tr("Tryb", "Mode"), selection: $renderer.colorMode) {
                    ForEach(0..<FractalRenderer.colorModes.count, id: \.self) { Text(FractalRenderer.colorModes[$0]).tag($0) }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
            }
            SliderRow(tr("Gęstość", "Density"), value: $renderer.density, range: 0.2...4, format: "%.2f")
            Toggle(tr("Cykl kolorów", "Color cycling"), isOn: $renderer.cycleColors).font(.callout)
            if renderer.cycleColors {
                SliderRow(tr("Prędkość", "Speed"), value: $renderer.cycleSpeed, range: 0.02...0.6, format: "%.2f")
            }
            Text(tr("Własna paleta", "Custom palette")).font(.caption).foregroundStyle(.secondary)
            HStack(spacing: 4) {
                ForEach(renderer.customColors.indices, id: \.self) { i in
                    ColorPicker("", selection: $renderer.customColors[i], supportsOpacity: false)
                        .labelsHidden()
                }
            }
        }
    }

    // MARK: Efekty
    private var effectsSection: some View {
        Card(title: tr("Efekty", "Effects"), symbol: "wand.and.stars") {
            Toggle(tr("Antyaliasing 2×2 (w spoczynku)", "Antialiasing 2×2 (at rest)"), isOn: $renderer.antialias).font(.callout)
            SliderRow(tr("Relief 3D", "3D relief"), value: $renderer.shade, range: 0...1, format: "%.2f")
            SliderRow(tr("Poświata", "Glow"), value: $renderer.glow, range: 0...1, format: "%.2f")
            SliderRow(tr("Nasycenie", "Saturation"), value: $renderer.saturation, range: 0...2, format: "%.2f")
            SliderRow(tr("Kontrast", "Contrast"), value: $renderer.contrast, range: 0.5...1.8, format: "%.2f")
            Toggle(tr("Kolorowe wnętrze zbioru", "Colored set interior"), isOn: $renderer.interiorColor).font(.callout)
            Toggle(tr("Odwróć kolory", "Invert colors"), isOn: $renderer.invert).font(.callout)
            Stepper(value: $renderer.kaleido, in: 0...12) {
                Text(renderer.kaleido < 2 ? tr("Kalejdoskop: wyłączony", "Kaleidoscope: off")
                                          : tr("Kalejdoskop: \(renderer.kaleido) segmentów", "Kaleidoscope: \(renderer.kaleido) segments"))
                    .font(.callout)
            }
        }
    }

    // MARK: Widok (obrót, 3D, dźwięk)
    private var viewSection: some View {
        VStack(spacing: 12) {
            Card(title: tr("Obrót", "Rotation"), symbol: "rotate.right") {
                SliderRow(tr("Kąt", "Angle"), value: $renderer.angleDeg, range: -180...180, format: "%.0f°")
                Toggle(tr("Automatyczny obrót", "Auto-rotate"), isOn: $renderer.autoRotate).font(.callout)
                if renderer.autoRotate {
                    SliderRow(tr("Prędkość", "Speed"), value: $renderer.rotateSpeed, range: -40...40, format: "%.0f°/s")
                }
                Text(tr("Gest obrotu na gładziku, klawisze Q / E.", "Trackpad rotate gesture, keys Q / E."))
                    .font(.caption2).foregroundStyle(.secondary)
            }
            Card(title: "3D", symbol: "cube") {
                Toggle(tr("Krajobraz 3D (D)", "3D landscape (D)"), isOn: $renderer.mode3D).font(.callout)
                if renderer.mode3D {
                    SliderRow(tr("Nachylenie", "Tilt"), value: $renderer.pitchDeg, range: 0...85, format: "%.0f°")
                    SliderRow(tr("Wysokość", "Height"), value: $renderer.heightScale, range: 0...1.5, format: "%.2f")
                    Text(tr("W trybie 3D zoom celuje w środek widoku.", "In 3D mode, zoom targets the view center."))
                        .font(.caption2).foregroundStyle(.secondary)
                }
            }
            Card(title: tr("Muzyka", "Music"), symbol: "music.note") {
                Toggle(tr("Muzyka ambient (M)", "Ambient music (M)"), isOn: $renderer.musicOn).font(.callout)
                if renderer.musicOn {
                    SliderRow(tr("Głośność", "Volume"), value: $renderer.musicVolume, range: 0...1, format: "%.2f")
                    Text(tr("Im głębszy zoom, tym jaśniejsze brzmienie.", "The deeper the zoom, the brighter the sound."))
                        .font(.caption2).foregroundStyle(.secondary)
                }
            }
        }
    }

    // MARK: Widoki
    private var viewsSection: some View {
        Card(title: tr("Miejsca", "Places"), symbol: "star") {
            ForEach(Preset.builtIn) { p in
                PlaceRow(title: p.name, symbol: "mappin.and.ellipse") { renderer.go(to: p.view) }
            }
            if !renderer.favorites.isEmpty {
                Divider()
                ForEach(renderer.favorites) { v in
                    PlaceRow(title: v.name, symbol: "star.fill", onDelete: { renderer.deleteFavorite(v) }) {
                        renderer.go(to: v)
                    }
                }
            }
            Button { renderer.saveFavorite() } label: {
                Label(tr("Zapisz bieżący widok", "Save current view"), systemImage: "plus").frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered).controlSize(.small)
        }
    }

    private func superscript(_ n: Int) -> String {
        let map: [Character: Character] = ["2": "²", "3": "³", "4": "⁴", "5": "⁵", "6": "⁶", "7": "⁷", "8": "⁸"]
        return String("\(n)".map { map[$0] ?? $0 })
    }
}

// MARK: - Elementy

private struct Card<Content: View>: View {
    let title: String
    let symbol: String
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            Label(title, systemImage: symbol)
                .font(.system(size: 11, weight: .semibold))
                .textCase(.uppercase)
                .foregroundStyle(.secondary)
            content
        }
        .padding(13)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassCard()
    }
}

private struct SliderRow: View {
    let label: String
    @Binding var value: Double
    let range: ClosedRange<Double>
    let format: String

    init(_ label: String, value: Binding<Double>, range: ClosedRange<Double>, format: String) {
        self.label = label; self._value = value; self.range = range; self.format = format
    }

    var body: some View {
        HStack(spacing: 8) {
            Text(label).font(.callout).frame(width: 62, alignment: .leading)
            Slider(value: $value, in: range)
            Text(String(format: format, value))
                .font(.system(.caption2, design: .monospaced))
                .foregroundStyle(.secondary)
                .frame(width: 44, alignment: .trailing)
        }
    }
}

private struct PaletteChip: View {
    let index: Int
    let selected: Bool

    var body: some View {
        RoundedRectangle(cornerRadius: 6, style: .continuous)
            .fill(Palettes.gradient(Palettes.all[index]))
            .overlay(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .strokeBorder(selected ? Color.white : Color.white.opacity(0.18), lineWidth: selected ? 2 : 0.8)
            )
            .shadow(color: selected ? .white.opacity(0.35) : .clear, radius: 4)
    }
}

private struct PlaceRow: View {
    let title: String
    let symbol: String
    var onDelete: (() -> Void)? = nil
    let action: () -> Void
    @State private var hover = false

    var body: some View {
        HStack {
            Button(action: action) {
                Label(title, systemImage: symbol)
                    .font(.callout)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            if let onDelete {
                Button(action: onDelete) { Image(systemName: "trash").font(.caption) }
                    .buttonStyle(.plain).foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 3).padding(.horizontal, 6)
        .background(hover ? Color.white.opacity(0.10) : .clear, in: RoundedRectangle(cornerRadius: 7))
        .onHover { hover = $0 }
    }
}

private struct RoundButton: View {
    let symbol: String
    let help: String
    var active = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 14, weight: .medium))
                .frame(width: 20, height: 20)
                .foregroundStyle(active ? Color.accentColor : Color.primary)
                .padding(10)
                .glassCapsule()
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .help(help)
    }
}

// MARK: - Styl „Liquid Glass" na materiałach

extension View {
    func glassCapsule() -> some View {
        self
            .background(.ultraThinMaterial, in: Capsule())
            .overlay(Capsule().strokeBorder(.white.opacity(0.22), lineWidth: 0.8))
            .shadow(color: .black.opacity(0.28), radius: 18, y: 6)
    }

    func glassCard() -> some View {
        self
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(.white.opacity(0.22), lineWidth: 0.8))
            .shadow(color: .black.opacity(0.28), radius: 18, y: 6)
    }
}

#Preview { ContentView() }
