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
/// right whether your data is saved (and whether the shared data is, when sharing is on). Long lists scroll inside the
/// page above it.
struct StatusBar: View {
    let text: String

    var body: some View {
        VStack(spacing: 0) {
            Divider()
            HStack(spacing: 14) {
                Text(text)
                    .lineLimit(1)
                    .foregroundStyle(.secondary)
                Spacer()
                SharingStatusDot()
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

/// A small coloured dot for the shared data, shown only while sharing is on: green when everything is saved to the shared
/// data, yellow while changes are waiting to be saved (click to save now), red when something is wrong.
private struct SharingStatusDot: View {
    private var session: SharedDataSession { SharedDataSession.shared }

    var body: some View {
        if let status = session.status {
            Button {
                if status == .unsaved { Task { await session.checkInNow(release: false) } }
            } label: {
                HStack(spacing: 5) {
                    Circle().fill(color(status)).frame(width: 8, height: 8)
                    Text(label(status)).foregroundStyle(.secondary)
                }
            }
            .buttonStyle(.plain)
            .help(detail(status))
            .accessibilityLabel("Sharing: \(label(status))")
            .accessibilityHint(detail(status))
        }
    }

    private func color(_ status: SharedDataSession.Status) -> Color {
        switch status {
        case .saved: Theme.green
        case .unsaved: .yellow
        case .problem: Theme.red
        }
    }

    private func label(_ status: SharedDataSession.Status) -> String {
        switch status {
        case .saved: "Shared · Saved"
        case .unsaved: "Shared · Not saved yet"
        case .problem: "Shared · Problem"
        }
    }

    private func detail(_ status: SharedDataSession.Status) -> String {
        switch status {
        case .saved: "Everything is saved to the shared data."
        case .unsaved: "Changes are saved to the shared data every couple of minutes, and when you hide or quit. Click to save now."
        case .problem(let why): why
        }
    }
}
