import SwiftUI
import SwiftData
import AppKit
import UniformTypeIdentifiers

/// Settings > Import & Export. Desktop only: a full backup, or transactions as a spreadsheet, out of or into Piggybank.
struct ImportExportSettingsView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Account.name) private var allAccounts: [Account]
    private var accounts: [Account] { allAccounts.live }

    @State private var message: String?
    @State private var messageIsError = false

    // Restoring a backup replaces everything, so it waits for a yes.
    @State private var pendingBackup: BackupFile?
    @State private var pendingBackupName = ""

    // A bank's spreadsheet opens in the import sheet, where it is previewed before anything is added.
    @State private var pendingImport: PendingImport?

    var body: some View {
        Form {
            Section {
                actionRow("Export Backup…", detail: "Everything in OinklyBudget in one .pig file: accounts, transactions, bills, goals, holdings, budgets, your custom categories and payment methods, and your preferences.") { exportBackup() }
                actionRow("Export Transactions (CSV)…", detail: "Every transaction as a spreadsheet you can open in Numbers or Excel.") { exportCSV() }
            } header: {
                Text("Export")
            }

            Section {
                actionRow("Import Backup…", detail: "Restore from a .pig backup file. This replaces everything currently in OinklyBudget, including custom categories, payment methods and preferences.") { chooseBackup() }
                actionRow("Import Transactions (CSV)…", detail: "Add transactions from a bank's spreadsheet (CSV). You see a preview first, and can match the columns if they aren't recognised. To import into one account, open it and choose Import Statement.") { chooseCSV() }
            } header: {
                Text("Import")
            }

            if let message {
                Section {
                    Label(message, systemImage: messageIsError ? "exclamationmark.triangle.fill" : "checkmark.circle.fill")
                        .foregroundStyle(messageIsError ? Color.orange : Theme.green)
                }
            }
        }
        .formStyle(.grouped)
        .confirmationDialog(
            "Replace everything with this backup?",
            isPresented: Binding(get: { pendingBackup != nil }, set: { if !$0 { pendingBackup = nil } }),
            titleVisibility: .visible
        ) {
            Button("Replace Everything", role: .destructive, action: restoreBackup)
            Button("Cancel", role: .cancel) { pendingBackup = nil }
        } message: {
            Text("\(pendingBackupName) holds \(pendingBackup?.summary ?? ""). Everything currently in OinklyBudget is erased first, and this can't be undone.")
        }
        .sheet(item: $pendingImport) { ImportStatementSheet(account: nil, fileURL: $0.url) }
    }

    private func actionRow(_ title: String, detail: String, action: @escaping () -> Void) -> some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.body.weight(.medium))
                Text(detail).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            Button("Choose…", action: action)
        }
    }

    private func report(_ text: String, error: Bool = false) {
        message = text
        messageIsError = error
    }

    private static func stamp() -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: .now)
    }

    // MARK: Export

    private func exportBackup() {
        switch BackupExporter.exportWithPanel(from: modelContext) {
        case .saved(let summary, let name): report("Saved a backup with \(summary) to \(name).")
        case .failed(let reason): report("Couldn't save the backup: \(reason)", error: true)
        case nil: break
        }
    }

    private func exportCSV() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.commaSeparatedText]
        panel.nameFieldStringValue = "OinklyBudget Transactions \(Self.stamp()).csv"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            let text = try TransactionCSV.export(from: modelContext)
            try text.write(to: url, atomically: true, encoding: .utf8)
            let count = max(text.split(separator: "\n").count - 1, 0)
            report("Saved \(count) transaction\(count == 1 ? "" : "s") to \(url.lastPathComponent).")
        } catch {
            report("Couldn't save the file: \(error.localizedDescription)", error: true)
        }
    }

    // MARK: Import

    private func chooseBackup() {
        let panel = NSOpenPanel()
        // .pig is the backup format. Older backups saved as plain .json still open.
        panel.allowedContentTypes = [DataBackup.fileType, .json]
        panel.allowsMultipleSelection = false
        panel.message = "Choose a OinklyBudget backup file (.pig)."
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            let data = try Data(contentsOf: url)
            pendingBackup = try DataBackup.decode(data)
            pendingBackupName = url.lastPathComponent
            message = nil
        } catch {
            report(error.localizedDescription, error: true)
        }
    }

    private func restoreBackup() {
        guard let file = pendingBackup else { return }
        pendingBackup = nil
        // Account pages that are open step away first, so nothing is showing data as it is erased.
        DataDeletion.afterLeavingAccountPages {
            do {
                try DataBackup.restore(file, into: modelContext)
                report("Restored \(file.summary).")
            } catch {
                modelContext.rollback()
                report("Couldn't restore the backup: \(error.localizedDescription)", error: true)
            }
        }
    }

    private func chooseCSV() {
        guard let url = StatementFilePicker.choose() else { return }
        message = nil
        pendingImport = PendingImport(url: url)
    }
}
