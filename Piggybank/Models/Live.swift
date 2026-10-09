import Foundation
import SwiftData

extension PersistentModel {
    /// False once the object has been deleted. Reading any property of a deleted SwiftData object is fatal,
    /// and a screen can still hold one for a moment after a delete (for example while erasing all data).
    var isLive: Bool { !isDeleted && modelContext != nil }
}

extension Sequence where Element: PersistentModel {
    /// The objects that haven't been deleted.
    var live: [Element] { filter(\.isLive) }
}

extension Notification.Name {
    /// Posted just before accounts are deleted, so screens showing one can move away first.
    static let piggybankWillDeleteAccounts = Notification.Name("piggybankWillDeleteAccounts")
}

enum DataDeletion {
    /// Tells every window to leave account pages, waits a beat for that to take effect, then runs `work`.
    @MainActor
    static func afterLeavingAccountPages(_ work: @escaping @MainActor () -> Void) {
        NotificationCenter.default.post(name: .piggybankWillDeleteAccounts, object: nil)
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(250))
            work()
        }
    }
}
