import AppKit
import SwiftData
import SwiftUI

/// Saving a full backup to a file, and remembering when it last happened.
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

    /// Asks where to save, then writes the backup. Nil when the save panel was cancelled.
    static func exportWithPanel(from context: ModelContext) -> Outcome? {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [DataBackup.fileType]
        panel.nameFieldStringValue = "Piggybank Financial Backup \(stamp()).\(DataBackup.fileExtension)"
        panel.message = "Save a backup of everything in Piggybank Financial."
        guard panel.runModal() == .OK, let url = panel.url else { return nil }
        do {
            let file = try DataBackup.make(from: context)
            try DataBackup.encode(file).write(to: url, options: .atomic)
            UserDefaults.standard.set(Date.now.timeIntervalSinceReferenceDate, forKey: lastBackupKey)
            return .saved(summary: file.summary, fileName: url.lastPathComponent)
        } catch {
            return .failed(error.localizedDescription)
        }
    }
}

/// When to push a backup on the user. The longer the history, the sooner it asks again: from two years of data a
/// backup older than a year is flagged, and from three years one older than six months.
enum BackupReminder {
    static let snoozeKey = "piggybank.backupReminderSnoozedUntil"

    struct Prompt {
        let years: Int
        let isUrgent: Bool
    }

    static func prompt(oldest: Date?, lastBackup: Date?, snoozedUntil: Date?, now: Date = .now,
                       calendar: Calendar = .current) -> Prompt? {
        guard let oldest else { return nil }
        let years = calendar.dateComponents([.year], from: oldest, to: now).year ?? 0
        guard years >= 2 else { return nil }
        if let snoozedUntil, snoozedUntil > now { return nil }
        let urgent = years >= 3
        let allowedAge = calendar.date(byAdding: .month, value: urgent ? -6 : -12, to: now) ?? now
        if let lastBackup, lastBackup > allowedAge { return nil }
        return Prompt(years: years, isUrgent: urgent)
    }
}

/// A banner on the Summary that asks for a backup once there are a couple of years of history.
struct BackupReminderBanner: View {
    @Environment(\.modelContext) private var modelContext
    /// The date of the oldest transaction, found by the page that shows this.
    let oldest: Date?
    @AppStorage(BackupExporter.lastBackupKey) private var lastBackupInterval: Double = 0
    @AppStorage(BackupReminder.snoozeKey) private var snoozedInterval: Double = 0
    @State private var message: String?

    private var prompt: BackupReminder.Prompt? {
        BackupReminder.prompt(
            oldest: oldest,
            lastBackup: lastBackupInterval > 0 ? Date(timeIntervalSinceReferenceDate: lastBackupInterval) : nil,
            snoozedUntil: snoozedInterval > 0 ? Date(timeIntervalSinceReferenceDate: snoozedInterval) : nil)
    }

    var body: some View {
        Group {
            if let prompt {
                let tint: Color = prompt.isUrgent ? .orange : .accentColor
                HStack(alignment: .center, spacing: 14) {
                    Image(systemName: "externaldrive.badge.checkmark")
                        .font(.title2)
                        .foregroundStyle(tint)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(prompt.isUrgent ? "Back up your \(prompt.years) years of history" : "Time for a backup")
                            .font(.headline)
                        Text("Piggybank Financial holds \(prompt.years) years of your money now. Save a backup file somewhere safe, like iCloud Drive or an external drive.")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                        if let message {
                            Text(message).font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    Spacer(minLength: 12)
                    Button("Later") {
                        let until = Calendar.current.date(byAdding: .day, value: 30, to: .now) ?? .now
                        snoozedInterval = until.timeIntervalSinceReferenceDate
                    }
                    .buttonStyle(.borderless)
                    Button("Export Backup…") { export() }
                        .buttonStyle(.borderedProminent)
                        .tint(tint)
                }
                .padding(14)
                .background(tint.opacity(0.12), in: RoundedRectangle(cornerRadius: 12))
                .overlay(RoundedRectangle(cornerRadius: 12).stroke(tint.opacity(0.45), lineWidth: 1))
            }
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
