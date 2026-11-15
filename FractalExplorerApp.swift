import SwiftUI

@main
struct FractalExplorerApp: App {
    init() {
        NSApplication.shared.appearance = NSAppearance(named: .darkAqua)   // ciemny interfejs niezależnie od ustawień systemu
        FractalRenderer.runHeadlessIfRequested()
    }

    var body: some Scene {
        WindowGroup("Fractal Explorer") {
            ContentView()
        }
        .windowStyle(.hiddenTitleBar)
        .windowResizability(.contentMinSize)
    }
}
