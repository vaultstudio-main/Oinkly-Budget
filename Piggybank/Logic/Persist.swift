import SwiftData
import SwiftUI

/// SwiftData writes changes to disk, and refreshes every screen that reads them, on its own schedule.
/// That left a gap of a few seconds where a posted, edited or deleted transaction wasn't reflected everywhere.
/// These make it immediate.
extension ModelContext {
    /// Saves right now if anything changed.
    func saveNow() {
        guard hasChanges else { return }
        try? save()
    }
}

/// Saves pending changes within a fraction of a second, even for edits made in place (such as typing in the
/// register), so every window and the "last 15 transactions" always show the latest.
struct AutoSaveModifier: ViewModifier {
    @Environment(\.modelContext) private var modelContext

    func body(content: Content) -> some View {
        content.task {
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(300))
                modelContext.saveNow()
            }
        }
    }
}

extension View {
    func savesChangesImmediately() -> some View { modifier(AutoSaveModifier()) }
}
