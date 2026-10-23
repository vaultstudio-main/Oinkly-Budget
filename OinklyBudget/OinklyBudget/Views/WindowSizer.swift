import SwiftUI
import AppKit

/// Sets the size of the window it is in whenever `size` changes (and once when it first appears), keeping the window's top left corner
/// where it was and staying on screen. Anything the person dragged the window to in between is left alone until the next change.
struct WindowSizer: NSViewRepresentable {
    let size: CGSize

    final class Coordinator { var applied: CGSize? }

    func makeCoordinator() -> Coordinator { Coordinator() }
    func makeNSView(context: Context) -> NSView { NSView() }

    func updateNSView(_ view: NSView, context: Context) {
        guard context.coordinator.applied != size else { return }
        context.coordinator.applied = size
        DispatchQueue.main.async {
            guard let window = view.window else { return }
            var frame = window.frameRect(forContentRect: NSRect(origin: .zero, size: size))
            let old = window.frame
            frame.origin = CGPoint(x: old.minX, y: old.maxY - frame.height)
            if let visible = window.screen?.visibleFrame {
                frame.size.width = min(frame.width, visible.width)
                frame.size.height = min(frame.height, visible.height)
                frame.origin.x = min(max(frame.minX, visible.minX), visible.maxX - frame.width)
                frame.origin.y = min(max(frame.minY, visible.minY), visible.maxY - frame.height)
            }
            window.setFrame(frame, display: true, animate: true)
        }
    }
}
