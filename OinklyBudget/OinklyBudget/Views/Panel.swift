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
        .background(Theme.panel, in: RoundedRectangle(cornerRadius: 8))
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
