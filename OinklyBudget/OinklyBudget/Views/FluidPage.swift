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
