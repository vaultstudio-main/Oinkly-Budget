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

/// A small bar along the bottom of the window, the floor under every page: what you're looking at on the left,
/// and a quick link to Help on the right. Long lists scroll inside the page above it.
struct StatusBar: View {
    let text: String
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        VStack(spacing: 0) {
            Divider()
            HStack(spacing: 12) {
                Text(text)
                    .lineLimit(1)
                    .foregroundStyle(.secondary)
                Spacer()
                Button {
                    openWindow(id: "help")
                } label: {
                    Label("Help", systemImage: "questionmark.circle")
                }
                .buttonStyle(.link)
                .help("Open OinklyBudget Help")
            }
            .font(.caption)
            .padding(.horizontal, 14)
            .frame(height: 24)
            .background(.bar)
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
