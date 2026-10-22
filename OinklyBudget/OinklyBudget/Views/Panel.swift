import SwiftUI

/// A titled dark card used on the Summary screen.
struct Panel<Content: View>: View {
    let title: String
    /// Stretches to the tallest card in a row.
    var fillsHeight = false
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title.uppercased())
                .font(.caption)
                .foregroundStyle(.secondary)
                .accessibilityAddTraits(.isHeader)
            content
        }
        .padding(16)
        .frame(maxWidth: .infinity, maxHeight: fillsHeight ? .infinity : nil, alignment: .topLeading)
        .panelBackground(cornerRadius: 8)
    }
}

/// The big title at the top of a Mac page, so you always know which page you are on.
struct PageTitle: View {
    let title: String
    init(_ title: String) { self.title = title }

    var body: some View {
        HStack {
            Text(title).font(.largeTitle.bold())
                .accessibilityAddTraits(.isHeader)
            Spacer()
        }
    }
}

/// The fixed box at the top of a page: the page's title and its controls (month picker, tabs, filters) stay put while
/// everything below scrolls and stops at its edge. Put it above the page's scroll view, not inside it.
struct PinnedHeader<Controls: View>: View {
    let title: String
    @ViewBuilder let controls: Controls

    init(_ title: String, @ViewBuilder controls: () -> Controls) {
        self.title = title
        self.controls = controls()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            PageTitle(title)
            controls
        }
        .padding(.horizontal, 16)
        .padding(.top, 14)
        .padding(.bottom, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .pinnedHeaderStyle()
    }
}

extension PinnedHeader where Controls == EmptyView {
    init(_ title: String) { self.init(title) { EmptyView() } }
}

extension View {
    /// The look of the fixed box at the top of a page: solid, with a line under it, so what scrolls below never shows through.
    func pinnedHeaderStyle() -> some View {
        background(Theme.background)
            .overlay(alignment: .bottom) { EdgeLine() }
    }
}
