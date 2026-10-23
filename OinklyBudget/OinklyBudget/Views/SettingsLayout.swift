import SwiftUI

/// The look every settings window shares: a title, sections one under another in a scrolling body, and any buttons in a bar at the
/// bottom of the window, so they are always in the same place however much there is above them.
struct SettingsWindowLayout<Content: View, Footer: View>: View {
    let title: String
    @ViewBuilder let content: Content
    @ViewBuilder let footer: Footer

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                Text(title).font(.headline)
                content
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(20)
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            VStack(spacing: 0) {
                Divider()
                HStack(spacing: 10) { footer }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 20)
                    .padding(.vertical, 12)
            }
            .background(.bar)
        }
        .frame(minWidth: 400, minHeight: 360)
    }
}

/// One section of a settings window: a heading, a line saying what it does, then its controls.
struct SettingsSection<Content: View>: View {
    let title: String
    var note: String? = nil
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(.subheadline.weight(.semibold))
            if let note {
                Text(note).font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
            content
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
