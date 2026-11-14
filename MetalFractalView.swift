import SwiftUI
import MetalKit

/// MTKView z obsługą myszy, kółka i gestów gładzika.
final class InteractiveMTKView: MTKView {
    weak var renderer: FractalRenderer?

    override var acceptsFirstResponder: Bool { true }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    private func point(_ event: NSEvent) -> CGPoint {
        convert(event.locationInWindow, from: nil)
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(NSTrackingArea(rect: .zero,
                                       options: [.mouseMoved, .activeInKeyWindow, .inVisibleRect],
                                       owner: self, userInfo: nil))
    }

    override func viewDidChangeBackingProperties() {
        super.viewDidChangeBackingProperties()
        // Retina: warstwa Metal musi znać współczynnik skali okna.
        if let scale = window?.backingScaleFactor {
            layer?.contentsScale = scale
            (layer as? CAMetalLayer)?.contentsScale = scale
        }
        renderer?.wake()
    }

    override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize)
        renderer?.wake()
    }

    override func mouseMoved(with event: NSEvent) {
        renderer?.cursorMoved(to: point(event), in: bounds.size)
    }

    override func mouseDown(with event: NSEvent) {
        if event.clickCount == 2 {
            renderer?.zoom(by: 2, at: point(event), in: bounds.size)
        }
    }

    override func mouseDragged(with event: NSEvent) {
        renderer?.pan(dx: event.deltaX, dy: event.deltaY, in: bounds.size)
        renderer?.cursorMoved(to: point(event), in: bounds.size)
    }

    override func scrollWheel(with event: NSEvent) {
        let k = event.hasPreciseScrollingDeltas ? 0.01 : 0.06
        let factor = exp(Double(event.scrollingDeltaY) * k)
        renderer?.zoom(by: factor, at: point(event), in: bounds.size)
    }

    override func magnify(with event: NSEvent) {
        renderer?.zoom(by: exp(Double(event.magnification) * 2.0), at: point(event), in: bounds.size)
    }
}

struct MetalFractalView: NSViewRepresentable {
    let renderer: FractalRenderer

    func makeNSView(context: Context) -> InteractiveMTKView {
        let view = InteractiveMTKView(frame: .zero, device: renderer.device)
        view.renderer = renderer
        renderer.configure(view)
        view.wantsLayer = true
        return view
    }

    func updateNSView(_ nsView: InteractiveMTKView, context: Context) {}
}
