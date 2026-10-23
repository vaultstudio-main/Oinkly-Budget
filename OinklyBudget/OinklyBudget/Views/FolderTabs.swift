import SwiftUI

/// A row of tabs like the tabs on file folders. The tab you are on is raised and joined to the page below it, the others sit
/// behind it, and a line runs along the bottom of the row. The page below should be the page's own background.
struct FolderTabs<Tab: Hashable & Identifiable>: View {
    let tabs: [Tab]
    @Binding var selection: Tab
    let title: (Tab) -> String
    /// The space before the first tab, so a row can line up with the page's own margin.
    var leading: CGFloat = 16

    private let shape = UnevenRoundedRectangle(topLeadingRadius: 9, bottomLeadingRadius: 0, bottomTrailingRadius: 0, topTrailingRadius: 9, style: .continuous)

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(alignment: .bottom, spacing: 3) {
                ForEach(tabs) { tab in tabButton(tab) }
            }
            .padding(.leading, leading)
            .padding(.trailing, 16)
        }
        // The line along the bottom, behind the tabs, so the raised one can cover it.
        .background(alignment: .bottom) { EdgeLine() }
    }

    private func tabButton(_ tab: Tab) -> some View {
        let selected = tab == selection
        return Button { selection = tab } label: {
            Text(title(tab))
                .font(.callout.weight(selected ? .semibold : .regular))
                .foregroundStyle(selected ? Color.primary : Color.secondary)
                .padding(.horizontal, 14)
                .padding(.top, selected ? 8 : 6)
                .padding(.bottom, selected ? 9 : 6)
                .background(selected ? Theme.background : Theme.panel, in: shape)
                .overlay { shape.strokeBorder(Theme.separator.opacity(selected ? 0.9 : 0.55), lineWidth: 1) }
                // The raised tab covers the line under it, so it opens onto the page.
                .overlay(alignment: .bottom) {
                    if selected { Rectangle().fill(Theme.background).frame(height: 2).padding(.horizontal, 1).offset(y: 1) }
                }
                .contentShape(shape)
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}
