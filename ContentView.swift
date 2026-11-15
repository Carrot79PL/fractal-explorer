import SwiftUI

struct ContentView: View {
    @StateObject private var renderer = FractalRenderer()
    @AppStorage("lang") private var lang = Lang.current
    @AppStorage("uiMode") private var uiMode = "easy"
    @State private var showUI = true
    @State private var panel: PanelKind? = nil
    @State private var showHelp = false
    @State private var showHint = true

    private var isPro: Bool { uiMode == "pro" }

    var body: some View {
        ZStack {
            MetalFractalView(renderer: renderer)
                .ignoresSafeArea()

            // Warstwa interfejsu: ukrywana przezroczystością (układ się nie zmienia).
            VStack(spacing: 12) {
                HStack(alignment: .top, spacing: 12) {
                    VStack(alignment: .leading, spacing: 10) {
                        brand
                        hud
                    }
                    Spacer()
                    Color.clear.frame(width: 300, height: 44)
                }
                Spacer(minLength: 0)
                if !isPro && showHint && panel == nil { hint }
                ViewThatFits(in: .horizontal) {
                    toolbar(inlinePalettes: true)
                    toolbar(inlinePalettes: false)
                }
            }
            .padding(20)
            .opacity(showUI ? 1 : 0)
            .allowsHitTesting(showUI)
            .animation(.smooth(duration: 0.3), value: showUI)
            .animation(.smooth(duration: 0.25), value: panel)
            .animation(.smooth(duration: 0.3), value: uiMode)

            // Karta opcji nad dolnym paskiem – całą wysokość okna może zająć, więc nic nie wychodzi za ramkę.
            if let p = panel {
                VStack(spacing: 0) {
                    Spacer(minLength: 0)
                    OptionsPanel(renderer: renderer, kind: p) { withAnimation(.smooth(duration: 0.25)) { panel = nil } }
                        .id(p)
                }
                .padding(.horizontal, 20).padding(.top, 20).padding(.bottom, 92)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .opacity(showUI ? 1 : 0)
                .allowsHitTesting(showUI)
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }

            shortcuts
            cornerButtons

            if showHelp { helpCard }
            if renderer.isExporting {
                VStack(spacing: 10) {
                    ProgressView()
                    Text(tr("Renderowanie obrazu…", "Rendering image…")).font(.callout)
                }
                .padding(24)
                .glassCard()
            }
        }
        .frame(minWidth: 1000, minHeight: 600)
        .background(Color.black)
        .preferredColorScheme(.dark)
        .background(WindowAccessor { SplashController.shared.start(main: $0) })
        .onChange(of: uiMode) { _, _ in if !isPro && panel != .places { panel = nil } }
        .onAppear {
            if let p = ProcessInfo.processInfo.environment["FRACTAL_PANEL"].flatMap({ Int($0) }).flatMap(PanelKind.init(rawValue:)) { panel = p }
            DispatchQueue.main.asyncAfter(deadline: .now() + 14) { withAnimation { showHint = false } }
        }
    }

    // MARK: Marka + przełącznik Easy / Pro

    private var brand: some View {
        HStack(spacing: 12) {
            Image(systemName: "circle.hexagongrid.fill")
                .font(.system(size: 20, weight: .medium))
                .foregroundStyle(LinearGradient(colors: [.cyan, .white, .orange], startPoint: .topLeading, endPoint: .bottomTrailing))
            VStack(alignment: .leading, spacing: 0) {
                Text("Fractal Explorer").font(.system(size: 13, weight: .semibold))
                Text("Tomasz Marchewka").font(.system(size: 9)).foregroundStyle(Color.white.opacity(0.66))
            }
            ModeSwitch(isPro: Binding(get: { isPro }, set: { uiMode = $0 ? "pro" : "easy" }))
        }
        .padding(.horizontal, 14).padding(.vertical, 9)
        .glassCard()
    }

    // MARK: HUD

    private var hud: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Image(systemName: renderer.model.symbol)
                Text(renderer.model.title).fontWeight(.semibold)
                if isPro {
                    Button { renderer.copyCoordinatesToPasteboard() } label: { Image(systemName: "doc.on.doc") }
                        .buttonStyle(.plain).foregroundStyle(Color.white.opacity(0.66))
                        .help(tr("Kopiuj współrzędne", "Copy coordinates"))
                }
            }
            .font(.callout)
            .padding(.bottom, 2)
            if isPro {
                hudRow("Re", renderer.realText)
                hudRow("Im", renderer.imagText + " i")
            }
            hudRow("Zoom", renderer.zoomText)
            if isPro {
                hudRow("Iter", renderer.iterText)
                if abs(renderer.angleDeg) > 0.5 { hudRow(tr("Kąt", "Angle"), String(format: "%.0f°", renderer.angleDeg)) }
            }
        }
        .font(.system(.caption, design: .monospaced))
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .fixedSize()
        .glassCard()
    }

    private func hudRow(_ label: String, _ value: String) -> some View {
        HStack(spacing: 8) {
            Text(label).foregroundStyle(Color.white.opacity(0.66)).frame(width: 34, alignment: .leading)
            Text(value).foregroundStyle(.primary)
        }
    }

    private var hint: some View {
        HStack(spacing: 18) {
            Label(tr("Kółko / pinch – zoom", "Scroll / pinch – zoom"), systemImage: "plus.magnifyingglass")
            Label(tr("Przeciągnij – przesuń", "Drag – pan"), systemImage: "hand.draw")
            Label(tr("Dwuklik – ×2", "Double-click – ×2"), systemImage: "cursorarrow.click.2")
            Label(tr("Dwa palce – obrót", "Two fingers – rotate"), systemImage: "rotate.right")
            Label(tr("Kostka – niespodzianka", "Dice – surprise me"), systemImage: "dice")
        }
        .font(.system(size: 12))
        .foregroundStyle(Color.white.opacity(0.66))
        .padding(.horizontal, 18).padding(.vertical, 9)
        .glassCapsule()
        .transition(.opacity)
    }

    // MARK: Przyciski w rogu (zawsze na wierzchu)

    private var cornerButtons: some View {
        VStack {
            HStack {
                Spacer()
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
                    RoundButton(symbol: "questionmark", help: tr("Skróty klawiszowe (?)", "Keyboard shortcuts (?)"), active: showHelp) {
                        withAnimation { showHelp.toggle() }
                    }
                    .opacity(showUI ? 1 : 0).allowsHitTesting(showUI)
                    RoundButton(symbol: showUI ? "eye.slash" : "eye",
                                help: showUI ? tr("Ukryj interfejs (H)", "Hide interface (H)") : tr("Pokaż interfejs (H)", "Show interface (H)")) {
                        showUI.toggle()
                    }
                    .opacity(showUI ? 1 : 0.55)
                }
                .animation(.smooth(duration: 0.3), value: showUI)
            }
            Spacer()
        }
        .padding(20)
    }

    // MARK: Skróty klawiszowe (jedno miejsce, działają także przy ukrytym interfejsie)

    private var shortcuts: some View {
        Group {
            Button("") { renderer.autoZoom.toggle() }.keyboardShortcut(.space, modifiers: [])
            Button("") { renderer.resetView() }.keyboardShortcut("r", modifiers: [])
            Button("") { renderer.rotateBy(degrees: 5) }.keyboardShortcut("q", modifiers: [])
            Button("") { renderer.rotateBy(degrees: -5) }.keyboardShortcut("e", modifiers: [])
            Button("") { renderer.mode3D.toggle() }.keyboardShortcut("d", modifiers: [])
            Button("") { renderer.musicOn.toggle() }.keyboardShortcut("m", modifiers: [])
            Button("") { renderer.surprise() }.keyboardShortcut("s", modifiers: [])
            Button("") { renderer.setTour(!renderer.tourOn) }.keyboardShortcut("t", modifiers: [])
            Button("") { renderer.juliaFromCursor() }.keyboardShortcut("j", modifiers: [])
            Button("") { withAnimation { showHelp.toggle() } }.keyboardShortcut("/", modifiers: [])
            Button("") { withAnimation { showUI.toggle() } }.keyboardShortcut("h", modifiers: [])
            Button("") { withAnimation(.smooth(duration: 0.25)) { panel = nil } }.keyboardShortcut("i", modifiers: [])
            ForEach(FractalModel.allCases) { m in
                Button("") { renderer.model = m }.keyboardShortcut(KeyEquivalent(Character("\(m.rawValue + 1)")), modifiers: [])
            }
        }
        .frame(width: 0, height: 0)
        .opacity(0)
    }

    // MARK: Pomoc

    private var helpCard: some View {
        let rows: [(String, String)] = [
            ("1 – 6", tr("wybór modelu", "choose model")), (tr("Spacja", "Space"), tr("film: automatyczny zoom", "movie: auto-zoom")),
            ("R", tr("reset widoku", "reset view")), ("Q / E", tr("obrót widoku", "rotate view")),
            ("D", tr("krajobraz 3D", "3D landscape")), ("M", tr("muzyka", "music")),
            ("S", tr("niespodzianka (losowy styl)", "surprise me (random style)")), ("T", tr("wycieczka po miejscach", "tour through places")),
            ("J", tr("Julia z punktu pod kursorem", "Julia from point under cursor")), ("I", tr("zamknij panel opcji", "close options panel")),
            ("H", tr("ukryj / pokaż interfejs", "hide / show interface")), ("?", tr("ta pomoc", "this help"))
        ]
        return VStack(alignment: .leading, spacing: 8) {
            Label(tr("Skróty i sterowanie", "Shortcuts & controls"), systemImage: "keyboard").font(.headline)
            ForEach(rows.indices, id: \.self) { i in
                HStack(spacing: 12) {
                    Text(rows[i].0).font(.system(.callout, design: .monospaced)).frame(width: 70, alignment: .leading)
                    Text(rows[i].1).font(.callout).foregroundStyle(Color.white.opacity(0.66))
                }
            }
            Divider()
            Text(tr("Zoom: kółko / pinch · Przesuwanie: przeciąganie · Obrót: skręć dwa palce na gładziku lub ⌥ + przeciąganie · Dwuklik: ×2",
                    "Zoom: wheel / pinch · Pan: drag · Rotate: twist two fingers on the trackpad or ⌥ + drag · Double-click: ×2"))
                .font(.caption).foregroundStyle(Color.white.opacity(0.66)).frame(width: 360, alignment: .leading)
        }
        .padding(22)
        .glassCard()
        .onTapGesture { withAnimation { showHelp = false } }
        .transition(.opacity.combined(with: .scale(scale: 0.96)))
    }

    // MARK: Pasek narzędzi

    private func toolbar(inlinePalettes: Bool) -> some View {
        HStack(spacing: 14) {
            Menu {
                ForEach(FractalModel.allCases) { m in
                    Button { renderer.model = m } label: { Label(m.title, systemImage: m.symbol) }
                }
            } label: {
                Label(renderer.model.title, systemImage: renderer.model.symbol)
                    .frame(minWidth: 110, alignment: .leading)
            }
            .menuStyle(.borderlessButton)
            .fixedSize()

            Divider().frame(height: 22)

            Menu {
                ForEach(Look.all) { look in
                    Button(look.name) { look.apply(renderer) }
                }
            } label: {
                Label(tr("Style", "Looks"), systemImage: "wand.and.stars")
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
            .help(tr("Gotowe style: paleta + efekty jednym kliknięciem", "Ready-made looks: palette + effects in one click"))

            if !isPro {
            Divider().frame(height: 22)

            if inlinePalettes {
                HStack(spacing: 5) {
                    ForEach(0..<Palettes.count, id: \.self) { i in
                        PaletteChip(index: i, selected: renderer.paletteIndex == i)
                            .frame(width: 26, height: 16)
                            .onTapGesture { renderer.paletteIndex = i }
                            .help(Palettes.all[i].name)
                    }
                }
            } else {
                Menu {
                    ForEach(0..<Palettes.count, id: \.self) { i in
                        Button(Palettes.all[i].name) { renderer.paletteIndex = i }
                    }
                } label: {
                    HStack(spacing: 6) {
                        PaletteChip(index: renderer.paletteIndex, selected: false).frame(width: 34, height: 16)
                        Text(Palettes.all[renderer.paletteIndex].name)
                    }
                }
                .menuStyle(.borderlessButton)
                .fixedSize()
            }
            }   // w Pro paletę wybiera się z karty Kolor (ikona obok)

            Divider().frame(height: 22)

            ForEach(PanelKind.allCases.filter { isPro || $0 == .places }) { k in
                toolButton(k.symbol, k.title, active: panel == k) {
                    withAnimation(.smooth(duration: 0.25)) { panel = (panel == k ? nil : k) }
                }
            }

            Divider().frame(height: 22)

            toolButton(renderer.autoZoom ? "pause.fill" : "play.fill", tr("Film: automatyczny zoom (spacja)", "Movie: auto-zoom (space)"), active: renderer.autoZoom) {
                renderer.autoZoom.toggle()
            }
            toolButton("cube", tr("Krajobraz 3D (D)", "3D landscape (D)"), active: renderer.mode3D) { renderer.mode3D.toggle() }
            toolButton(renderer.musicOn ? "speaker.wave.2.fill" : "speaker.slash", tr("Muzyka ambient (M)", "Ambient music (M)"), active: renderer.musicOn) {
                renderer.musicOn.toggle()
            }
            toolButton("dice", tr("Niespodzianka (S)", "Surprise me (S)")) { renderer.surprise() }

            Divider().frame(height: 22)

            toolButton("arrow.counterclockwise", tr("Resetuj widok (R)", "Reset view (R)")) { renderer.resetView() }
            toolButton("star", tr("Dodaj bieżący widok do ulubionych", "Add current view to favorites")) { renderer.saveFavorite() }
            Menu {
                ForEach(ExportSize.allCases) { s in Button(s.title) { renderer.saveSnapshot(s) } }
                Divider()
                Button(tr("Kopiuj obraz do schowka", "Copy image to clipboard")) { renderer.copyImageToPasteboard() }
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

    private func toolButton(_ symbol: String, _ help: String, active: Bool = false, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .foregroundStyle(active ? Color.accentColor : Color.primary)
                .frame(width: 22, height: 22)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(help)
    }
}

/// Przełącznik trybu Easy / Pro.
private struct ModeSwitch: View {
    @Binding var isPro: Bool

    var body: some View {
        HStack(spacing: 0) {
            segment("Easy", !isPro) { isPro = false }
            segment("Pro", isPro) { isPro = true }
        }
        .padding(2)
        .background(Color.white.opacity(0.10), in: Capsule())
        .help(tr("Easy: prosty interfejs · Pro: pełny panel ustawień", "Easy: simple interface · Pro: full settings panel"))
    }

    private func segment(_ title: String, _ on: Bool, _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 11, weight: .semibold))
                .padding(.horizontal, 11).padding(.vertical, 4)
                .foregroundStyle(on ? Color.black : Color.white.opacity(0.66))
                .background(on ? Color.white.opacity(0.92) : .clear, in: Capsule())
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Panel boczny

enum PanelKind: Int, CaseIterable, Identifiable {
    case model, color, effects, view, places
    var id: Int { rawValue }
    var symbol: String {
        switch self {
        case .model: return "slider.horizontal.3"
        case .color: return "paintpalette"
        case .effects: return "sparkles"
        case .view: return "rotate.3d"
        case .places: return "mappin.and.ellipse"
        }
    }
    var title: String {
        switch self {
        case .model: return tr("Model i iteracje", "Model & iterations")
        case .color: return tr("Kolor", "Color")
        case .effects: return tr("Efekty", "Effects")
        case .view: return tr("Obrót, 3D i muzyka", "Rotation, 3D & music")
        case .places: return tr("Miejsca", "Places")
        }
    }
}

/// Karta z opcjami wysuwana nad dolnym paskiem (zastępuje dawny panel boczny).
private struct OptionsPanel: View {
    @AppStorage("lang") private var lang = Lang.current
    @ObservedObject var renderer: FractalRenderer
    let kind: PanelKind
    let onClose: () -> Void

    var body: some View {
        VStack(spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: kind.symbol)
                Text(kind.title).font(.system(size: 13, weight: .semibold))
                Spacer()
                Button(action: onClose) { Image(systemName: "xmark").font(.system(size: 11, weight: .bold)).padding(4).contentShape(Rectangle()) }
                    .buttonStyle(.plain)
                    .foregroundStyle(Color.white.opacity(0.7))
            }
            .padding(.horizontal, 14).padding(.vertical, 8)
            .glassCapsule()

            // Mieści się bez przewijania; przewijanie tylko awaryjnie (np. bardzo dużo ulubionych).
            ViewThatFits(in: .vertical) {
                current
                ScrollView(showsIndicators: false) { current.padding(.bottom, 4) }
            }
        }
        .frame(width: 340)
    }

    @ViewBuilder private var current: some View {
        switch kind {
        case .model: modelSection
        case .color: colorSection
        case .effects: effectsSection
        case .view: viewSection
        case .places: viewsSection
        }
    }

    // MARK: Model
    private var modelSection: some View {
        Card(title: "Model", symbol: "square.stack.3d.up") {
            SliderRow(tr("Iteracje", "Iterations"), value: $renderer.baseIterations, range: 50...3000, format: "%.0f")
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
                .buttonStyle(.bordered)
                .controlSize(.small)
                .help(tr("Przesuń kursor nad wybrany punkt i naciśnij J", "Move the cursor over a point and press J"))
            }
            if renderer.model != .mandelbrot {
                Text(tr("Zoom do ok. 4·10⁴× (precyzja float). Głęboki zoom: Mandelbrot.", "Zoom up to ~4·10⁴× (float precision). Deep zoom: Mandelbrot only."))
                    .font(.caption2).foregroundStyle(Color.white.opacity(0.66))
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
                        Text(Palettes.all[i].name).font(.system(size: 9)).foregroundStyle(Color.white.opacity(0.66))
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
            Text(tr("Własna paleta", "Custom palette")).font(.caption).foregroundStyle(Color.white.opacity(0.66))
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 6), spacing: 6) {
                ForEach(renderer.customColors.indices, id: \.self) { i in
                    ColorPicker("", selection: $renderer.customColors[i], supportsOpacity: false)
                        .labelsHidden()
                }
            }
            Button { renderer.randomPalette() } label: {
                Label(tr("Losuj własną paletę", "Randomize custom palette"), systemImage: "dice").frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered).controlSize(.small)
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
                Text(tr("Skręć dwa palce na gładziku (wokół kursora), ⌥ + przeciąganie lub klawisze Q / E.", "Twist two fingers on the trackpad (around the cursor), ⌥ + drag, or keys Q / E."))
                    .font(.caption2).foregroundStyle(Color.white.opacity(0.66))
            }
            Card(title: "3D", symbol: "cube") {
                Toggle(tr("Krajobraz 3D (D)", "3D landscape (D)"), isOn: $renderer.mode3D).font(.callout)
                if renderer.mode3D {
                    SliderRow(tr("Nachylenie", "Tilt"), value: $renderer.pitchDeg, range: 0...85, format: "%.0f°")
                    SliderRow(tr("Wysokość", "Height"), value: $renderer.heightScale, range: 0...1.5, format: "%.2f")
                    Text(tr("W trybie 3D zoom celuje w środek widoku.", "In 3D mode, zoom targets the view center."))
                        .font(.caption2).foregroundStyle(Color.white.opacity(0.66))
                }
            }
            Card(title: tr("Muzyka", "Music"), symbol: "music.note") {
                Toggle(tr("Muzyka ambient (M)", "Ambient music (M)"), isOn: $renderer.musicOn).font(.callout)
                if renderer.musicOn {
                    SliderRow(tr("Głośność", "Volume"), value: $renderer.musicVolume, range: 0...1, format: "%.2f")
                    Text(tr("Im głębszy zoom, tym jaśniejsze brzmienie.", "The deeper the zoom, the brighter the sound."))
                        .font(.caption2).foregroundStyle(Color.white.opacity(0.66))
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
                    PlaceRow(title: v.name, symbol: "star.fill", onRename: { renderer.renameFavorite(v) }, onDelete: { renderer.deleteFavorite(v) }) {
                        renderer.go(to: v)
                    }
                }
            }
            Button { renderer.saveFavorite() } label: {
                Label(tr("Zapisz bieżący widok", "Save current view"), systemImage: "plus").frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered).controlSize(.small)
            Divider()
            Toggle(tr("Wycieczka po miejscach (T)", "Tour through places (T)"),
                   isOn: Binding(get: { renderer.tourOn }, set: { renderer.setTour($0) })).font(.callout)
            HStack(spacing: 6) {
                Button { renderer.copyCoordinatesToPasteboard() } label: {
                    Label(tr("Kopiuj współrzędne", "Copy coordinates"), systemImage: "doc.on.doc").frame(maxWidth: .infinity)
                }
                Button { renderer.copyImageToPasteboard() } label: {
                    Label(tr("Kopiuj obraz", "Copy image"), systemImage: "photo.on.rectangle").frame(maxWidth: .infinity)
                }
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
                .foregroundStyle(Color.white.opacity(0.66))
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
                .foregroundStyle(Color.white.opacity(0.66))
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
    var onRename: (() -> Void)? = nil
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
            if let onRename {
                Button(action: onRename) { Image(systemName: "pencil").font(.caption) }
                    .buttonStyle(.plain).foregroundStyle(Color.white.opacity(0.66))
                    .help(tr("Zmień nazwę", "Rename"))
            }
            if let onDelete {
                Button(action: onDelete) { Image(systemName: "trash").font(.caption) }
                    .buttonStyle(.plain).foregroundStyle(Color.white.opacity(0.66))
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
            .overlay(Capsule().fill(Color.black.opacity(0.24)).allowsHitTesting(false))
            .overlay(Capsule().strokeBorder(.white.opacity(0.22), lineWidth: 0.8))
            .shadow(color: .black.opacity(0.28), radius: 18, y: 6)
    }

    func glassCard() -> some View {
        self
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(Color.black.opacity(0.24)).allowsHitTesting(false))
            .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(.white.opacity(0.22), lineWidth: 0.8))
            .shadow(color: .black.opacity(0.28), radius: 18, y: 6)
    }
}

#Preview { ContentView() }
