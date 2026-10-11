#if os(macOS)
import SwiftUI
import AppKit

/// Makes the main window fill the usable screen every time it opens, whatever size it was left at.
/// That is the full screen minus the menu bar and the Dock, not macOS full screen mode.
private struct MaximizeOnOpen: NSViewRepresentable {
    final class Coordinator { var didMaximize = false }

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeNSView(context: Context) -> NSView { NSView() }

    func updateNSView(_ view: NSView, context: Context) {
        guard !context.coordinator.didMaximize else { return }
        DispatchQueue.main.async {
            guard !context.coordinator.didMaximize, let window = view.window,
                  let frame = (window.screen ?? NSScreen.main)?.visibleFrame else { return }
            context.coordinator.didMaximize = true
            window.setFrame(frame, display: true, animate: false)
        }
    }
}

extension View {
    /// Opens this window as large as the screen allows.
    func opensMaximized() -> some View { background(MaximizeOnOpen()) }
}
#endif
