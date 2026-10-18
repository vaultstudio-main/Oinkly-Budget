import SwiftUI
import SwiftData
import AppKit
import UniformTypeIdentifiers

/// Import a bank's CSV file. From an account's register every row goes into that account; from Settings the account
/// is chosen here. The file is read and guessed at first, shown as a preview, and nothing is saved until Import.
struct ImportStatementSheet: View {
    /// The account the statement belongs to. Nil from Settings, where an account is picked in the sheet.
    let account: Account?
    let fileURL: URL

    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \Account.name) private var allAccounts: [Account]
    private var accounts: [Account] { allAccounts.live }

    @State private var text = ""
    @State private var table: [[String]] = []
    @State private var layout = ImportLayout()
    @State private var loadProblem: String?

    @State private var chosenAccount: Account?
    @State private var skipDuplicates = true
    @State private var tidyPayees = true
    @State private var fillCategories = true

    @State private var saved = SavedImportLayout.load()
    @State private var usingSaved: SavedImportLayout.ID?
    @State private var newLayoutName = ""

    @State private var parsed = ParsedStatement()
    @State private var planned: [PlannedRow] = []

    @State private var result: StatementImporter.ImportResult?
    @State private var errorMessage: String?
    @State private var showsMapping = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if let result {
                doneView(result)
            } else if let loadProblem {
                problemView(loadProblem)
            } else {
                setupView
            }
        }
        .padding(20)
        .frame(width: 720, height: result == nil && loadProblem == nil ? 700 : 280)
        .task { load() }
        .onChange(of: layout) { refresh() }
        .onChange(of: chosenAccount) { replan() }
        .onChange(of: skipDuplicates) { replan() }
        .onChange(of: tidyPayees) { replan() }
    }

    // MARK: Setup

    private var setupView: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(account.map { "Import Statement into \($0.name)" } ?? "Import Transactions").font(.title2.bold())
                Text(fileURL.lastPathComponent).foregroundStyle(.secondary)
            }

            Form {
                Section {
                    if account == nil {
                        Picker("Add to account", selection: $chosenAccount) {
                            Text("Choose…").tag(Account?.none)
                            ForEach(accounts) { Text($0.name).tag(Optional($0)) }
                        }
                    }
                    if !saved.isEmpty {
                        Picker("Saved format", selection: $usingSaved) {
                            Text("Detected automatically").tag(SavedImportLayout.ID?.none)
                            ForEach(saved) { Text($0.name).tag(Optional($0.id)) }
                        }
                        .onChange(of: usingSaved) { applySaved() }
                    }
                    DisclosureGroup("How this file is read", isExpanded: $showsMapping) { mapping }
                } header: {
                    Text("File")
                }

                Section {
                    previewTable
                    summaryLine
                } header: {
                    Text("Preview")
                }

                Section {
                    Toggle("Skip transactions already in OinklyBudget", isOn: $skipDuplicates)
                    Toggle("Tidy bank text in payee names", isOn: $tidyPayees)
                        .help("Removes card prefixes, store numbers and long digit runs, and turns ALL CAPS into words.")
                    Toggle("Fill categories from payees you've used before", isOn: $fillCategories)
                    HStack {
                        TextField("Save this format as", text: $newLayoutName, prompt: Text("Name, such as Chase checking"))
                        Button("Save Format", action: saveLayout)
                            .disabled(newLayoutName.trimmingCharacters(in: .whitespaces).isEmpty)
                    }
                } header: {
                    Text("Options")
                }
            }
            .formStyle(.grouped)

            if let errorMessage { Text(errorMessage).foregroundStyle(Theme.red).font(.callout) }

            HStack {
                Spacer()
                Button("Cancel", role: .cancel) { dismiss() }.keyboardShortcut(.cancelAction)
                Button(importTitle, action: runImport)
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
                    .disabled(!canImport)
            }
        }
    }

    private var importableCount: Int { planned.filter { $0.account != nil && !(skipDuplicates && $0.isDuplicate) }.count }
    private var canImport: Bool { importableCount > 0 }
    private var importTitle: String { "Import \(importableCount.formatted()) Transaction\(importableCount == 1 ? "" : "s")" }

    // MARK: Mapping

    private var columnNames: [(Int, String)] {
        let width = table.map(\.count).max() ?? 0
        let head: [String] = layout.headerRow.flatMap { $0 < table.count ? table[$0] : nil } ?? []
        return (0..<width).map { index in
            let name = index < head.count ? head[index].trimmingCharacters(in: .whitespacesAndNewlines) : ""
            return (index, name.isEmpty ? "Column \(index + 1)" : name)
        }
    }

    private func columnPicker(_ title: String, _ binding: Binding<Int?>) -> some View {
        Picker(title, selection: binding) {
            Text("None").tag(Int?.none)
            ForEach(columnNames, id: \.0) { Text($0.1).tag(Optional($0.0)) }
        }
    }

    private var mapping: some View {
        VStack(alignment: .leading, spacing: 8) {
            Picker("Column names are in", selection: Binding(
                get: { layout.headerRow ?? -1 },
                set: { layout.headerRow = $0 < 0 ? nil : $0 }
            )) {
                Text("No header row").tag(-1)
                ForEach(0..<min(table.count, 20), id: \.self) { Text("Row \($0 + 1)").tag($0) }
            }
            Picker("Separator", selection: Binding(get: { layout.delimiter }, set: { layout.delimiter = $0; resplit() })) {
                Text("Comma").tag(",")
                Text("Semicolon").tag(";")
                Text("Tab").tag("\t")
                Text("Bar").tag("|")
            }
            columnPicker("Date", $layout.dateColumn)
            Picker("Date format", selection: $layout.dateStyle) {
                ForEach(DateStyle.all) { Text($0.title).tag($0) }
            }
            if parsed.dateIsAmbiguous, layout.dateStyle == .auto {
                Text("These dates could be month first or day first. Month first is assumed; change the date format if that is wrong.")
                    .font(.caption).foregroundStyle(.orange)
            }
            columnPicker("Payee or description", $layout.payeeColumn)
            columnPicker("Memo", $layout.memoColumn)
            columnPicker("Category", $layout.categoryColumn)
            Picker("Amounts", selection: $layout.amountStyle) {
                ForEach(AmountStyle.allCases) { Text($0.title).tag($0) }
            }
            if layout.amountStyle == .signed {
                columnPicker("Amount", $layout.amountColumn)
            } else {
                columnPicker("Debit (money out)", $layout.debitColumn)
                columnPicker("Credit (money in)", $layout.creditColumn)
            }
            Toggle("Positive amounts are charges (credit card files)", isOn: $layout.flipSign)
            Toggle("Numbers use a comma for decimals (1.234,56)", isOn: $layout.commaDecimal)
            if account == nil { columnPicker("Account name (optional)", $layout.accountColumn) }
        }
        .padding(.top, 6)
    }

    // MARK: Preview

    private var previewTable: some View {
        let shown = Array(planned.prefix(8))
        return VStack(alignment: .leading, spacing: 0) {
            if shown.isEmpty {
                Text("No transactions could be read yet. Open “How this file is read” and check the date and amount columns.")
                    .font(.callout).foregroundStyle(.secondary)
            } else {
                ForEach(shown) { item in
                    HStack(spacing: 10) {
                        Text(item.row.date ?? .now, format: .dateTime.month(.abbreviated).day().year())
                            .monospacedDigit().frame(width: 100, alignment: .leading)
                        Text(tidyPayees ? StatementImporter.tidy(item.row.payee) : item.row.payee).lineLimit(1)
                        Spacer()
                        if item.isDuplicate { Text("Already there").font(.caption).foregroundStyle(.orange) }
                        Text(item.row.amount ?? 0, format: .appCurrency)
                            .foregroundStyle((item.row.amount ?? 0) < 0 ? Theme.red : Theme.green)
                            .frame(width: 100, alignment: .trailing)
                    }
                    .font(.callout)
                    .padding(.vertical, 3)
                    Divider()
                }
                if planned.count > shown.count {
                    Text("and \((planned.count - shown.count).formatted()) more…").font(.caption).foregroundStyle(.secondary).padding(.top, 4)
                }
            }
        }
    }

    private var summaryLine: some View {
        let duplicates = planned.filter(\.isDuplicate).count
        let problems = parsed.problems
        return VStack(alignment: .leading, spacing: 3) {
            let dates = planned.compactMap(\.row.date)
            if let first = dates.min(), let last = dates.max() {
                Text("\(planned.count.formatted()) transactions from \(first.formatted(.dateTime.month(.abbreviated).day().year())) to \(last.formatted(.dateTime.month(.abbreviated).day().year()))")
            }
            if duplicates > 0 {
                Text("\(duplicates.formatted()) already in OinklyBudget\(skipDuplicates ? " and will be skipped" : "")")
                    .foregroundStyle(.orange)
            }
            if !problems.isEmpty {
                Text("\(problems.count.formatted()) row\(problems.count == 1 ? "" : "s") can't be read and will be left out. Row \(problems[0].id): \(problems[0].problem ?? "")")
                    .foregroundStyle(.secondary)
            }
        }
        .font(.callout)
    }

    // MARK: Done

    private func doneView(_ result: StatementImporter.ImportResult) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Imported \(result.added.formatted()) transaction\(result.added == 1 ? "" : "s")", systemImage: "checkmark.circle.fill")
                .font(.title2.bold()).foregroundStyle(Theme.green)
            if result.duplicatesSkipped > 0 { Text("Skipped \(result.duplicatesSkipped.formatted()) already in OinklyBudget.") }
            if parsed.problems.count > 0 { Text("\(parsed.problems.count.formatted()) rows couldn't be read and were left out.") }
            if result.uncategorized > 0 { Text("\(result.uncategorized.formatted()) had a category that didn't match yours, so they have none.") }
            Text("Wrong? Undo removes everything this import added.").foregroundStyle(.secondary)
            Spacer()
            HStack {
                Button("Undo Import") {
                    ImportHistory.undo(in: modelContext)
                    dismiss()
                }
                Spacer()
                Button("Done") { dismiss() }.keyboardShortcut(.defaultAction)
            }
        }
    }

    private func problemView(_ message: String) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Couldn't read that file", systemImage: "exclamationmark.triangle.fill").font(.title2.bold()).foregroundStyle(.orange)
            Text(message)
            Spacer()
            HStack { Spacer(); Button("Close") { dismiss() }.keyboardShortcut(.defaultAction) }
        }
    }

    // MARK: Work

    private func load() {
        guard table.isEmpty else { return }
        let scoped = fileURL.startAccessingSecurityScopedResource()
        defer { if scoped { fileURL.stopAccessingSecurityScopedResource() } }
        guard let data = try? Data(contentsOf: fileURL), let decoded = StatementImporter.decode(data) else {
            loadProblem = "The file couldn't be opened as text."
            return
        }
        text = decoded
        let delimiter = StatementImporter.detectDelimiter(decoded)
        table = TransactionCSV.parse(decoded, delimiter: Character(delimiter))
        guard !table.isEmpty else { loadProblem = "The file is empty."; return }

        layout = StatementImporter.guessLayout(table, delimiter: delimiter)
        // A format saved for this bank (same column names) is used straight away.
        if let headerRow = layout.headerRow, headerRow < table.count {
            let names = SavedImportLayout.normalized(table[headerRow])
            if let match = saved.first(where: { SavedImportLayout.normalized($0.headers) == names }) {
                usingSaved = match.id
                layout = match.layout
                layout.delimiter = delimiter
            }
        }
        // Card statements often list charges as positive numbers, so flip them when that is clearly the case.
        if account?.isCreditCard == true, let amountColumn = layout.amountColumn {
            let values = StatementImporter.dataRows(table, headerRow: layout.headerRow)
                .compactMap { amountColumn < $0.count ? StatementImporter.parseAmount($0[amountColumn], commaDecimal: layout.commaDecimal) : nil }
            if values.filter({ $0 > 0 }).count > values.filter({ $0 < 0 }).count * 2 { layout.flipSign = true }
        }
        chosenAccount = account ?? accounts.first
        refresh()
    }

    /// The separator changed, so the file is split again and the layout guessed again for the new columns.
    private func resplit() {
        let delimiter = layout.delimiter
        table = TransactionCSV.parse(text, delimiter: Character(delimiter))
        var fresh = StatementImporter.guessLayout(table, delimiter: delimiter)
        fresh.dateStyle = layout.dateStyle
        layout = fresh
    }

    private func applySaved() {
        guard let id = usingSaved, let match = saved.first(where: { $0.id == id }) else {
            layout = StatementImporter.guessLayout(table, delimiter: layout.delimiter)
            return
        }
        let delimiter = layout.delimiter
        layout = match.layout
        layout.delimiter = delimiter
    }

    private func refresh() {
        parsed = StatementImporter.parse(table, layout: layout)
        replan()
    }

    private func replan() {
        planned = StatementImporter.plan(parsed.rows, account: account, fallback: chosenAccount, tidyPayees: tidyPayees, in: modelContext)
    }

    private func saveLayout() {
        guard let headerRow = layout.headerRow, headerRow < table.count else {
            errorMessage = "Only files with a header row can be remembered, so the app can recognise the bank next time."
            return
        }
        let name = newLayoutName.trimmingCharacters(in: .whitespaces)
        var entry = SavedImportLayout(name: name, headers: table[headerRow], layout: layout)
        if let index = saved.firstIndex(where: { $0.name.lowercased() == name.lowercased() }) {
            entry.id = saved[index].id
            saved[index] = entry
        } else {
            saved.append(entry)
        }
        SavedImportLayout.store(saved)
        usingSaved = entry.id
        newLayoutName = ""
        errorMessage = nil
    }

    private func runImport() {
        errorMessage = nil
        do {
            result = try StatementImporter.add(planned, skipDuplicates: skipDuplicates, tidyPayees: tidyPayees,
                                               fillCategories: fillCategories, in: modelContext)
        } catch {
            modelContext.rollback()
            errorMessage = "Couldn't import: \(error.localizedDescription)"
        }
    }
}

/// Asks for the CSV file, then hands its location to the import sheet.
enum StatementFilePicker {
    @MainActor
    static func choose() -> URL? {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.commaSeparatedText, .plainText, .tabSeparatedText]
        panel.allowsMultipleSelection = false
        panel.message = "Choose a statement or transaction list saved as a CSV file."
        return panel.runModal() == .OK ? panel.url : nil
    }
}

struct PendingImport: Identifiable {
    let id = UUID()
    let url: URL
}
