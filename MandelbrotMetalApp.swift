import SwiftUI

@main
struct MandelbrotMetalApp: App {
    init() { FractalRenderer.runHeadlessIfRequested() }

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .windowStyle(.hiddenTitleBar)
        .windowResizability(.contentMinSize)
    }
}
