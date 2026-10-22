import SwiftUI
import AppKit

/// Keeps the side panel at one width, every time the app opens, with no dragging. SwiftUI's own width limits are only
/// hints on the Mac, so this sets the limits on the split view's side panel item itself.
private struct FixedSidebarWidth: NSViewRepresentable {
    let width: CGFloat

    final class Probe: NSView {
        var width: CGFloat = 300
        private var attempts = 0

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            attempts = 0
            apply()
        }

        func apply() {
            // The split view can be built a moment after this view appears, so look again a few times.
            DispatchQueue.main.async { [weak self] in
                guard let self, let content = self.window?.contentView else { return }
                if let split = Self.splitView(in: content),
                   let controller = split.delegate as? NSSplitViewController,
                   let item = controller.splitViewItems.first {
                    item.canCollapse = false
                    item.isCollapsed = false
                    item.minimumThickness = self.width
                    item.maximumThickness = self.width
                    item.holdingPriority = NSLayoutConstraint.Priority(rawValue: 999)
                    split.setPosition(self.width, ofDividerAt: 0)
                } else if self.attempts < 10 {
                    self.attempts += 1
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { self.apply() }
                }
            }
        }

        private static func splitView(in view: NSView) -> NSSplitView? {
            if let split = view as? NSSplitView, split.delegate is NSSplitViewController { return split }
            for child in view.subviews {
                if let found = splitView(in: child) { return found }
            }
            return nil
        }
    }

    func makeNSView(context: Context) -> Probe {
        let probe = Probe()
        probe.width = width
        return probe
    }

    func updateNSView(_ probe: Probe, context: Context) {
        probe.width = width
        probe.apply()
    }
}

extension View {
    /// Fixes the width of the side panel in a navigation split view, so it can't be dragged wider or narrower.
    func fixedSidebarWidth(_ width: CGFloat) -> some View { background(FixedSidebarWidth(width: width)) }
}
