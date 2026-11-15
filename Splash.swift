import SwiftUI
import AppKit

/// Stan ekranu startowego (pasek postępu + komunikat).
final class SplashModel: ObservableObject {
    @Published var progress = 0.0
    @Published var status = ""
}

struct SplashView: View {
    @ObservedObject var model: SplashModel

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            if let img = NSImage(contentsOf: Bundle.main.url(forResource: "splash", withExtension: "jpg") ?? URL(fileURLWithPath: "/dev/null")) {
                Image(nsImage: img).resizable().scaledToFill()
            } else {
                LinearGradient(colors: [.indigo, .black], startPoint: .top, endPoint: .bottom)
            }
            LinearGradient(colors: [.clear, .black.opacity(0.55), .black.opacity(0.88)],
                           startPoint: .init(x: 0.5, y: 0.25), endPoint: .bottom)
            VStack(alignment: .leading, spacing: 6) {
                Spacer()
                HStack(spacing: 14) {
                    Image(systemName: "circle.hexagongrid.fill")
                        .font(.system(size: 40, weight: .medium))
                        .foregroundStyle(LinearGradient(colors: [.cyan, .white, .orange], startPoint: .topLeading, endPoint: .bottomTrailing))
                    Text("Fractal Explorer")
                        .font(.system(size: 46, weight: .semibold, design: .rounded))
                        .foregroundStyle(.white)
                }
                Text(tr("Interaktywna eksploracja fraktali w czasie rzeczywistym · Metal", "Real-time interactive fractal exploration · Metal"))
                    .font(.system(size: 13)).foregroundStyle(.white.opacity(0.78))
                Text("Tomasz Marchewka")
                    .font(.system(size: 15, weight: .medium)).foregroundStyle(.white)
                    .padding(.top, 4)
                Spacer().frame(height: 14)
                ProgressView(value: model.progress)
                    .progressViewStyle(.linear).tint(.white.opacity(0.9)).frame(height: 3)
                HStack {
                    Text(model.status).font(.system(size: 11)).foregroundStyle(.white.opacity(0.7))
                    Spacer()
                    Text("v1.2").font(.system(size: 11)).foregroundStyle(.white.opacity(0.5))
                }
            }
            .padding(.horizontal, 32).padding(.bottom, 24)
        }
        .frame(width: 720, height: 440)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(.white.opacity(0.15), lineWidth: 0.8))
    }
}

/// Ekran startowy w stylu Photoshopa: małe bezramkowe okno na środku ekranu, główne okno pojawia się po nim.
final class SplashController {
    static let shared = SplashController()
    private var window: NSWindow?
    private var started = false
    private let model = SplashModel()

    private static let steps: [(Double, String, String)] = [
        (0.12, "Inicjalizacja Metal…", "Initializing Metal…"),
        (0.35, "Ładowanie shaderów…", "Loading shaders…"),
        (0.58, "Przygotowanie palet kolorów…", "Preparing color palettes…"),
        (0.80, "Obliczanie orbity referencyjnej…", "Computing reference orbit…"),
        (1.00, "Gotowe", "Ready")
    ]

    func start(main: NSWindow?) {
        guard !started, let main = main else { return }
        started = true
        let env = ProcessInfo.processInfo.environment
        if env["FRACTAL_NOSPLASH"] != nil || env["MANDELBROT_ZOOMTEST"] != nil || env["MANDELBROT_DEBUG"] != nil { return }

        main.alphaValue = 0
        let w = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 720, height: 440),
                         styleMask: [.borderless], backing: .buffered, defer: false)
        w.isOpaque = false
        w.backgroundColor = .clear
        w.hasShadow = true
        w.level = .floating
        w.contentView = NSHostingView(rootView: SplashView(model: model))
        w.center()
        w.alphaValue = 0
        w.makeKeyAndOrderFront(nil)
        window = w
        NSAnimationContext.runAnimationGroup { $0.duration = 0.35; w.animator().alphaValue = 1 }

        for (i, s) in Self.steps.enumerated() {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5 + Double(i) * 0.55) { [weak self] in
                withAnimation(.easeOut(duration: 0.5)) { self?.model.progress = s.0 }
                self?.model.status = tr(s.1, s.2)
            }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 3.5) { [weak self] in self?.finish(main: main) }
        DispatchQueue.main.asyncAfter(deadline: .now() + 8) { main.alphaValue = 1 }   // zabezpieczenie
    }

    private func finish(main: NSWindow) {
        main.alphaValue = 0
        main.makeKeyAndOrderFront(nil)
        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = 0.5
            main.animator().alphaValue = 1
            window?.animator().alphaValue = 0
        }, completionHandler: { [weak self] in
            self?.window?.orderOut(nil)
            self?.window = nil
        })
    }
}

/// Udostępnia okno hosta SwiftUI.
struct WindowAccessor: NSViewRepresentable {
    let onWindow: (NSWindow?) -> Void

    func makeNSView(context: Context) -> NSView {
        let v = WindowProbe()
        v.onWindow = onWindow
        return v
    }
    func updateNSView(_ nsView: NSView, context: Context) {}

    private final class WindowProbe: NSView {
        var onWindow: ((NSWindow?) -> Void)?
        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            guard window != nil else { return }
            DispatchQueue.main.async { [weak self] in self?.onWindow?(self?.window) }
        }
    }
}
