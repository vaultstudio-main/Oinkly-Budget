import SwiftUI

/// Makes a page flow with the window the way a web page does. Up to `designWidth` the page is laid out at its own size, with the window's
/// width deciding how it arranges itself. On a wider window everything on it (text, padding, charts) grows with the window, up to
/// `largest` times, so a big screen shows the same page larger instead of a small page lost in empty space.
///
/// The scale comes only from the window's width, and the page is given the room that is left once it is drawn larger, so nothing the
/// page does can change the scale. That keeps it from ever feeding back into itself.
struct FluidPage<Content: View>: View {
    static var designWidth: CGFloat { 1500 }
    static var largest: CGFloat { 1.5 }

    @ViewBuilder let content: Content
    @State private var width: CGFloat = 0

    private var scale: CGFloat { min(max(width / Self.designWidth, 1), Self.largest) }

    var body: some View {
        FluidScaleLayout(scale: scale) {
            content.scaleEffect(scale, anchor: .topLeading)
        }
        .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { width = $0 }
    }
}

/// Lays its one child out in the room it is given divided by `scale`. The child is drawn `scale` times larger with `scaleEffect`, which on
/// its own changes how a view looks but not the room it takes, so this fills the whole room it is given.
private struct FluidScaleLayout: Layout {
    let scale: CGFloat

    private func inner(_ proposal: ProposedViewSize) -> ProposedViewSize {
        ProposedViewSize(width: proposal.width.map { $0 / scale }, height: proposal.height.map { $0 / scale })
    }

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        guard let child = subviews.first else { return .zero }
        let size = child.sizeThatFits(inner(proposal))
        return CGSize(width: proposal.width ?? size.width * scale, height: proposal.height ?? size.height * scale)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        guard let child = subviews.first else { return }
        child.place(at: bounds.origin, anchor: .topLeading, proposal: ProposedViewSize(width: bounds.width / scale, height: bounds.height / scale))
    }
}

/// A pop-up that keeps its own size on any screen it fits, and on a smaller one is cut down to fit and scrolls instead. A 14-inch MacBook
/// has less room than the 27-inch screen the editors were drawn on, and a pop-up taller or wider than the screen would have its Save
/// button off screen with no way to reach it.
private struct ScreenFitted<Content: View>: View {
    let width: CGFloat
    let height: CGFloat
    @ViewBuilder let content: Content

    /// What a pop-up can have of the screen: its usable area, less the title bar and a margin around it.
    private var limit: CGSize {
        let visible = NSScreen.main?.visibleFrame.size ?? CGSize(width: 1440, height: 900)
        return CGSize(width: visible.width - 48, height: visible.height - 96)
    }

    var body: some View {
        let fitted = CGSize(width: min(width, limit.width), height: min(height, limit.height))
        if fitted.width < width || fitted.height < height {
            ScrollView([.horizontal, .vertical]) {
                content.frame(width: width, height: height)
            }
            .frame(width: fitted.width, height: fitted.height)
        } else {
            content.frame(width: width, height: height)
        }
    }
}

extension View {
    /// `frame(width:height:)` for a pop-up, that cuts the pop-up down to fit a smaller screen and lets it scroll there.
    func screenFitted(width: CGFloat, height: CGFloat) -> some View {
        ScreenFitted(width: width, height: height) { self }
    }
}
