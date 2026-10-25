import AppKit
import SwiftData
import SwiftUI

/// Saving a manual backup to a .pig file, and remembering when it last happened.
@MainActor
enum BackupExporter {
    static let lastBackupKey = "piggybank.lastBackupDate"

    /// Stored as seconds since the reference date, so a view can watch it with @AppStorage.
    static var lastBackup: Date? {
        let seconds = UserDefaults.standard.double(forKey: lastBackupKey)
        return seconds > 0 ? Date(timeIntervalSinceReferenceDate: seconds) : nil
    }

    private static func stamp() -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: .now)
    }

    enum Outcome {
        case saved(summary: String, fileName: String)
        case failed(String)
    }

    /// Writes the backup into the default save location when there is one, else asks where to save. Nil when the save panel was cancelled.
    static func exportWithPanel(from context: ModelContext) -> Outcome? {
        let name = "Oinkly Budget Backup \(stamp()).\(DataBackup.fileExtension)"
        var summary = ""
        func write(to url: URL) throws {
            let file = try DataBackup.make(from: context)
            try DataBackup.encode(file).write(to: url, options: .atomic)
            summary = file.summary
            UserDefaults.standard.set(Date.now.timeIntervalSinceReferenceDate, forKey: lastBackupKey)
        }
        do {
            if let url = try DefaultSaveFolder.save(named: name, write) {
                return .saved(summary: summary, fileName: url.lastPathComponent)
            }
            let panel = NSSavePanel()
            panel.allowedContentTypes = [DataBackup.fileType]
            panel.nameFieldStringValue = name
            panel.message = "Save a backup of everything in Oinkly Budget."
            guard panel.runModal() == .OK, let url = panel.url else { return nil }
            try write(to: url)
            return .saved(summary: summary, fileName: url.lastPathComponent)
        } catch {
            return .failed(error.localizedDescription)
        }
    }
}

/// When to push a backup copy or an export on the user: only once there are a lot of transactions, which is when a spare
/// copy (and a fresh start for the oldest years, if you want one) is worth thinking about. Not while a backup copy is
/// set up, because that is already keeping a spare.
enum BackupReminder {
    static let snoozeKey = "piggybank.backupReminderSnoozedUntil"

    /// A gentle nudge from here, and a firmer one from `urgentCount`.
    static let softCount = 50_000
    static let urgentCount = 100_000

    struct Prompt {
        let count: Int
        let isUrgent: Bool
    }

    static func prompt(transactionCount: Int, lastBackup: Date?, snoozedUntil: Date?, now: Date = .now,
                       calendar: Calendar = .current) -> Prompt? {
        guard transactionCount >= softCount else { return nil }
        if ShadowCopyManager.isSetUpNow { return nil }
        if let snoozedUntil, snoozedUntil > now { return nil }
        let urgent = transactionCount >= urgentCount
        // A recent backup quiets the reminder: 6 months at the soft level, 3 months at the firm one.
        let allowedAge = calendar.date(byAdding: .month, value: urgent ? -3 : -6, to: now) ?? now
        if let lastBackup, lastBackup > allowedAge { return nil }
        return Prompt(count: transactionCount, isUrgent: urgent)
    }
}

/// A banner for Settings ▸ Data that asks for a backup copy once the transaction count is high.
struct BackupReminderBanner: View {
    @Environment(\.modelContext) private var modelContext
    /// How many transactions there are, counted by the page that shows this.
    let transactionCount: Int
    @AppStorage(BackupExporter.lastBackupKey) private var lastBackupInterval: Double = 0
    @AppStorage(BackupReminder.snoozeKey) private var snoozedInterval: Double = 0
    @State private var message: String?

    private var prompt: BackupReminder.Prompt? {
        BackupReminder.prompt(
            transactionCount: transactionCount,
            lastBackup: lastBackupInterval > 0 ? Date(timeIntervalSinceReferenceDate: lastBackupInterval) : nil,
            snoozedUntil: snoozedInterval > 0 ? Date(timeIntervalSinceReferenceDate: snoozedInterval) : nil)
    }

    var body: some View {
        if let prompt {
            let tint: Color = prompt.isUrgent ? .orange : .accentColor
            HStack(alignment: .center, spacing: 12) {
                Image(systemName: "externaldrive.badge.checkmark")
                    .font(.title2)
                    .foregroundStyle(tint)
                VStack(alignment: .leading, spacing: 2) {
                    Text("You have \(prompt.count.formatted()) transactions")
                        .font(.headline)
                    Text("That's a lot of history. Set up a backup copy so there is always a spare, or save a manual backup.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    if let message {
                        Text(message).font(.caption).foregroundStyle(.secondary)
                    }
                }
                Spacer(minLength: 8)
                Button("Later") {
                    let until = Calendar.current.date(byAdding: .day, value: 30, to: .now) ?? .now
                    snoozedInterval = until.timeIntervalSinceReferenceDate
                }
                .buttonStyle(.borderless)
                Button("Save Backup") { export() }
                Button("Set Up Backup Copy") { ShadowCopyManager.shared.chooseFolder() }
                    .buttonStyle(.borderedProminent)
                    .tint(tint)
            }
            .padding(.vertical, 4)
        }
    }

    private func export() {
        switch BackupExporter.exportWithPanel(from: modelContext) {
        case .saved(_, let name):
            // The stored date changed, so the banner re-evaluates and goes away.
            lastBackupInterval = Date.now.timeIntervalSinceReferenceDate
            message = "Saved \(name)."
        case .failed(let reason):
            message = "Couldn't save the backup: \(reason)"
        case nil:
            break
        }
    }
}
