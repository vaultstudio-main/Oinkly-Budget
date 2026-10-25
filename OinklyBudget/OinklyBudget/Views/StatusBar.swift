import SwiftUI

/// What the status bar at the bottom of the window says about the page being shown, such as "12 transactions · October 2026".
/// A page sets it with `.statusBarText(…)`; pages that don't fall back to their name.
private struct StatusBarTextKey: PreferenceKey {
    static let defaultValue: String? = nil
    static func reduce(value: inout String?, nextValue: () -> String?) { value = nextValue() ?? value }
}

extension View {
    func statusBarText(_ text: String) -> some View { preference(key: StatusBarTextKey.self, value: text) }
}

/// A small bar along the bottom of the window, the floor under every page: what you're looking at on the left, and on the
/// right one status for whether your data is saved: this Mac, the backup copy and, when sharing is on, the shared data. Long
/// lists scroll inside the page above it.
struct StatusBar: View {
    let text: String

    var body: some View {
        VStack(spacing: 0) {
            EdgeLine()
            HStack(spacing: 14) {
                Text(text)
                    .lineLimit(1)
                    .foregroundStyle(.secondary)
                Spacer()
                ShadowDatabaseStatusLabel()
            }
            .font(.caption)
            .padding(.horizontal, 14)
            .frame(height: 24)
            .background(.bar)
            .task { DatabaseStatus.shared.start() }
        }
    }

}

/// Puts a page above the status bar. The page keeps all the room above the bar and can set the bar's text.
struct StatusBarHost<Page: View>: View {
    let fallback: String
    let page: Page
    @State private var text: String?

    var body: some View {
        VStack(spacing: 0) {
            page
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .onPreferenceChange(StatusBarTextKey.self) { text = $0 }
            StatusBar(text: text ?? fallback)
        }
    }
}
