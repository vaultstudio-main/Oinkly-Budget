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

    // A spreadsheet is read first, then added once you've said which account the loose rows belong to.
    @State private var pendingCSV: TransactionCSV.Parsed?
    @State private var pendingCSVName = ""
    @State private var defaultAccount: Account?
    @State private var skipDuplicates = true

    private var rowsNeedingDefault: Int {
        guard let pendingCSV else { return 0 }
        let names = Set(accounts.map { $0.name.lowercased() })
        return pendingCSV.rows.filter { !names.contains($0.accountName.lowercased()) }.count
    }

    var body: some View {
        Form {
            Section {
                actionRow("Export Backup…", detail: "Everything in Piggybank Budgeting in one .pig file: accounts, transactions, bills, goals, holdings, budgets, your custom categories and payment methods, and your preferences.") { exportBackup() }
                actionRow("Export Transactions (CSV)…", detail: "Every transaction as a spreadsheet you can open in Numbers or Excel.") { exportCSV() }
            } header: {
                Text("Export")
            }

            Section {
                actionRow("Import Backup…", detail: "Restore from a .pig backup file. This replaces everything currently in Piggybank Budgeting, including custom categories, payment methods and preferences.") { chooseBackup() }
                actionRow("Import Transactions (CSV)…", detail: "Add transactions from a spreadsheet. Needs a Date column and an Amount column (or Debit and Credit).") { chooseCSV() }
            } header: {
                Text("Import")
            }

            if let pendingCSV, pendingCSV.problem == nil {
                Section("Ready to import: \(pendingCSVName)") {
                    LabeledContent("Transactions found", value: "\(pendingCSV.rows.count)")
                    if pendingCSV.skipped > 0 {
                        LabeledContent("Rows that couldn't be read", value: "\(pendingCSV.skipped)")
                    }
                    if rowsNeedingDefault > 0 {
                        Picker(pendingCSV.hasAccountColumn ? "Rows with no matching account go to" : "Add them to", selection: $defaultAccount) {
                            ForEach(accounts) { Text($0.name).tag(Optional($0)) }
                        }
                    }
                    Toggle("Skip ones already in Piggybank Budgeting", isOn: $skipDuplicates)
                    HStack {
                        Spacer()
                        Button("Cancel") { self.pendingCSV = nil }
                        Button("Import \(pendingCSV.rows.count) Transactions", action: importCSV)
                            .buttonStyle(.borderedProminent)
                            .disabled(pendingCSV.rows.isEmpty || (rowsNeedingDefault > 0 && defaultAccount == nil))
                    }
                }
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
            Text("\(pendingBackupName) holds \(pendingBackup?.summary ?? ""). Everything currently in Piggybank Budgeting is erased first, and this can't be undone.")
        }
        .onAppear {
            if defaultAccount == nil { defaultAccount = accounts.first }
        }
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
        panel.nameFieldStringValue = "Piggybank Budgeting Transactions \(Self.stamp()).csv"
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
        panel.message = "Choose a Piggybank Budgeting backup file (.pig)."
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
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.commaSeparatedText, .plainText]
        panel.allowsMultipleSelection = false
        panel.message = "Choose a spreadsheet (CSV) of transactions."
        guard panel.runModal() == .OK, let url = panel.url else { return }
        guard let data = try? Data(contentsOf: url),
              let text = String(data: data, encoding: .utf8) ?? String(data: data, encoding: .isoLatin1) else {
            report("Couldn't read that file.", error: true)
            return
        }
        let parsed = TransactionCSV.read(text)
        if let problem = parsed.problem {
            pendingCSV = nil
            report(problem, error: true)
            return
        }
        if parsed.rows.isEmpty {
            pendingCSV = nil
            report("No transactions could be read from that file.", error: true)
            return
        }
        pendingCSV = parsed
        pendingCSVName = url.lastPathComponent
        if defaultAccount == nil { defaultAccount = accounts.first }
        message = nil
    }

    private func importCSV() {
        guard let pendingCSV else { return }
        do {
            let result = try TransactionCSV.add(pendingCSV.rows, defaultAccount: defaultAccount, skipDuplicates: skipDuplicates, in: modelContext)
            var parts = ["Added \(result.added) transaction\(result.added == 1 ? "" : "s")"]
            if result.duplicates > 0 { parts.append("skipped \(result.duplicates) already there") }
            if pendingCSV.skipped > 0 { parts.append("\(pendingCSV.skipped) rows couldn't be read") }
            if result.uncategorized > 0 { parts.append("\(result.uncategorized) had a category that didn't match") }
            report(parts.joined(separator: ", ") + ".")
            self.pendingCSV = nil
        } catch {
            modelContext.rollback()
            report("Couldn't import: \(error.localizedDescription)", error: true)
        }
    }
}
