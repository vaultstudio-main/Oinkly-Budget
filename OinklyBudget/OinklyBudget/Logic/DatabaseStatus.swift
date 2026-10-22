import Foundation
import SwiftData

/// Whether everything on screen is saved to the database, for the dot in the status bar. SwiftData saves a moment after a
/// change, so "saving" is normal and short. If a save keeps failing it says so.
@MainActor
@Observable
final class DatabaseStatus {
    static let shared = DatabaseStatus()

    enum State: Equatable {
        case saved
        /// Changes are waiting for the next save.
        case unsaved
        case problem(String)
    }

    private(set) var state: State = .saved
    private(set) var lastSaved: Date?
    private var dirtySince: Date?
    private var task: Task<Void, Never>?

    /// How long changes can wait before the app saves them itself and, if that fails, reports it.
    static let patience: TimeInterval = 4

    /// Starts watching. Safe to call more than once.
    func start() {
        guard task == nil else { return }
        task = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                if let context = OinklyBudgetAppDelegate.container?.mainContext { self?.poll(context: context) }
                try? await Task.sleep(for: .seconds(1))
            }
        }
    }

    /// One look at the database: saved, or waiting, or failing. Changes that wait longer than `patience` are saved here.
    func poll(context: ModelContext, now: Date = .now) {
        guard context.hasChanges else {
            if dirtySince != nil || state != .saved { lastSaved = now }
            dirtySince = nil
            state = .saved
            return
        }
        let since = dirtySince ?? now
        dirtySince = since
        guard now.timeIntervalSince(since) >= Self.patience else {
            if case .problem = state {} else { state = .unsaved }
            return
        }
        do {
            try context.save()
            dirtySince = nil
            lastSaved = now
            state = .saved
        } catch {
            state = .problem(error.localizedDescription)
        }
    }
}
