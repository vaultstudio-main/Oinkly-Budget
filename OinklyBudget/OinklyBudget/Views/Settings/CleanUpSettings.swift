import SwiftUI
import SwiftData

/// Settings ▸ Clean Up: find and replace in payee names, merge look-alike payees, and move a category's transactions
/// to another category. Every change can be undone straight afterwards.
struct CleanUpSettingsView: View {
    private enum Mode: String, CaseIterable, Identifiable {
        case payees = "Payees", categories = "Categories"
        var id: Self { self }
    }

    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Category.name) private var allCategories: [Category]

    @State private var mode = Mode.payees
    @State private var rows: [CleanUp.PayeeRow] = []
    @State private var search = ""
    @State private var selection = Set<String>()
    @State private var find = ""
    @State private var replace = ""
    @State private var showingLookAlikes = false
    @State private var renaming: [String]?
    @State private var categorySelection = Set<PersistentIdentifier>()
    @State private var movingCategories = false
    @State private var lastChange: CleanUp.Change?
    @State private var message: String?

    private var categories: [Category] { allCategories.live }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Picker("", selection: $mode) {
                ForEach(Mode.allCases) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .frame(maxWidth: 260)

            if mode == .payees { payees } else { categoryPane }

            HStack {
                if let message { Label(message, systemImage: "checkmark.circle.fill").foregroundStyle(Theme.green).font(.callout) }
                Spacer()
                if lastChange != nil {
                    Button("Undo Last Change") { undo() }
                }
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .onAppear { reload() }
        .sheet(item: Binding(get: { renaming.map { NameList(names: $0) } }, set: { if $0 == nil { renaming = nil } })) { list in
            MergePayeesSheet(names: list.names, rows: rows) { target in
                apply(CleanUp.renamePayees(Dictionary(uniqueKeysWithValues: list.names.filter { $0 != target }.map { ($0, target) }), in: modelContext))
            }
        }
        .sheet(isPresented: $movingCategories) {
            MoveCategorySheet(sources: categories.filter { categorySelection.contains($0.persistentModelID) }, categories: categories) { target, deleteSources, sources in
                apply(CleanUp.moveCategories(from: sources, to: target, deleteSources: deleteSources, in: modelContext))
                categorySelection = []
            }
        }
    }

    private struct NameList: Identifiable {
        let names: [String]
        var id: String { names.joined(separator: "|") }
    }

    private func reload() { rows = CleanUp.payeeRows(in: modelContext) }

    private func apply(_ change: CleanUp.Change) {
        lastChange = change
        message = change.summary
        selection = []
        reload()
    }

    private func undo() {
        guard let change = lastChange else { return }
        CleanUp.undo(change, in: modelContext)
        lastChange = nil
        message = "Put everything back."
        reload()
    }

    // MARK: Payees

    private var filtered: [CleanUp.PayeeRow] {
        let text = search.trimmingCharacters(in: .whitespaces)
        return text.isEmpty ? rows : rows.filter { $0.name.localizedCaseInsensitiveContains(text) }
    }

    private var replacements: [String: String] { CleanUp.replacements(find: find, replace: replace, in: rows) }

    private var payees: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Find and replace in payee names.
            GroupBox {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        TextField("Find in payee names", text: $find).textFieldStyle(.roundedBorder)
                        Image(systemName: "arrow.right").foregroundStyle(.secondary)
                        TextField("Replace with", text: $replace).textFieldStyle(.roundedBorder)
                        Button("Replace All") { apply(CleanUp.renamePayees(replacements, in: modelContext)); find = ""; replace = "" }
                            .disabled(replacements.isEmpty)
                    }
                    let count = rows.filter { replacements[$0.name] != nil }.reduce(0) { $0 + $1.count }
                    Text(find.isEmpty ? "Type part of a name to find, like “#1234” or “Coffee Co”, and what to change it to."
                         : replacements.isEmpty ? "No payee names contain “\(find)”."
                         : "\(replacements.count) payee name\(replacements.count == 1 ? "" : "s") and \(count) transaction\(count == 1 ? "" : "s") would change.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            HStack {
                TextField("Search payees", text: $search).textFieldStyle(.roundedBorder).frame(maxWidth: 220)
                Spacer()
                Toggle("Show look-alikes", isOn: $showingLookAlikes).toggleStyle(.button)
                Button("Merge Selected") { renaming = Array(selection).sorted() }.disabled(selection.count < 2)
                Button("Rename") { renaming = Array(selection) }.disabled(selection.count != 1)
            }

            if showingLookAlikes { lookAlikes } else { payeeList }
        }
    }

    private var payeeList: some View {
        List(filtered, selection: $selection) { row in
            HStack {
                Text(row.name).lineLimit(1)
                Spacer()
                Text("\(row.count)×").foregroundStyle(.secondary)
                if let date = row.lastDate {
                    Text(date, format: .dateTime.month(.abbreviated).year()).font(.caption).foregroundStyle(.tertiary).frame(width: 70, alignment: .trailing)
                }
            }
            .tag(row.name)
        }
        .overlay {
            if rows.isEmpty { ContentUnavailableView("No payees yet", systemImage: "person.2", description: Text("Payees appear here as you add transactions.")) }
        }
    }

    private var lookAlikes: some View {
        let groups = CleanUp.lookAlikes(rows)
        return List {
            if groups.isEmpty {
                Text("No look-alike payees. Your list is clean.").foregroundStyle(.secondary)
            }
            ForEach(Array(groups.enumerated()), id: \.offset) { _, group in
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(group) { row in
                        HStack { Text(row.name); Spacer(); Text("\(row.count)×").foregroundStyle(.secondary) }.font(.callout)
                    }
                    HStack {
                        Text("Merge all into “\(group[0].name)”").font(.caption).foregroundStyle(.secondary)
                        Spacer()
                        Button("Merge") {
                            apply(CleanUp.renamePayees(Dictionary(uniqueKeysWithValues: group.dropFirst().map { ($0.name, group[0].name) }), in: modelContext))
                        }
                        .controlSize(.small)
                    }
                }
                .padding(.vertical, 4)
            }
        }
    }

    // MARK: Categories

    private var categoryPane: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Pick the categories to empty, then choose where their transactions go. Payments, transfers and ATM withdrawals keep their own locked category.")
                .font(.callout)
                .foregroundStyle(.secondary)
            List(selection: $categorySelection) {
                Section("Expenses") { ForEach(categories.filter { !$0.isIncome }) { categoryRow($0) } }
                Section("Income") { ForEach(categories.filter(\.isIncome)) { categoryRow($0) } }
            }
            HStack {
                Spacer()
                Button("Move Transactions") { movingCategories = true }
                    .disabled(categorySelection.isEmpty || Set(categories.filter { categorySelection.contains($0.persistentModelID) }.map(\.isIncome)).count != 1)
            }
        }
    }

    private func categoryRow(_ category: Category) -> some View {
        HStack(spacing: 10) {
            CategoryBadge(category: category, size: 24)
            Text(category.name)
            if category.isCustom { Text("Custom").font(.caption2).foregroundStyle(.secondary) }
            Spacer()
            Text("\(category.transactions.live.count)").foregroundStyle(.secondary)
        }
        .tag(category.persistentModelID)
    }
}

// MARK: Merge or rename payees

/// Choose the name the selected payees become: one of them, or a new one.
private struct MergePayeesSheet: View {
    let names: [String]
    let rows: [CleanUp.PayeeRow]
    let onApply: (String) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var chosen: String
    @State private var typed = ""

    init(names: [String], rows: [CleanUp.PayeeRow], onApply: @escaping (String) -> Void) {
        self.names = names
        self.rows = rows
        self.onApply = onApply
        // The most used name is the starting choice.
        func uses(_ name: String) -> Int { rows.first { $0.name == name }?.count ?? 0 }
        _chosen = State(initialValue: names.max { uses($0) < uses($1) } ?? names.first ?? "")
    }

    private var target: String { typed.trimmingCharacters(in: .whitespaces).isEmpty ? chosen : typed.trimmingCharacters(in: .whitespaces) }
    private var affected: Int { rows.filter { names.contains($0.name) && $0.name != target }.reduce(0) { $0 + $1.count } }

    var body: some View {
        NavigationStack {
            Form {
                Section(names.count == 1 ? "Rename" : "Merge \(names.count) payees") {
                    if names.count > 1 {
                        Picker("Use this name", selection: $chosen) {
                            ForEach(names, id: \.self) { Text($0).tag($0) }
                        }
                    }
                    FormTextField(names.count > 1 ? "Or type a new name" : "New name", text: $typed, hint: names.count > 1 ? "Leave empty to use the name above" : names.first ?? "")
                }
                Section {
                    Text(affected == 0 ? "Nothing would change." : "\(affected) transaction\(affected == 1 ? "" : "s") will be changed to “\(target)”. The old names stop being suggested. You can undo this right after.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
            }
            .formStyle(.grouped)
            .navigationTitle(names.count == 1 ? "Rename Payee" : "Merge Payees")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button(names.count == 1 ? "Rename" : "Merge") { onApply(target); dismiss() }.disabled(target.isEmpty || affected == 0)
                }
            }
        }
        .frame(minWidth: 460, minHeight: 320)
    }
}

// MARK: Move a category's transactions

private struct MoveCategorySheet: View {
    let sources: [Category]
    let categories: [Category]
    let onApply: (Category, Bool, [Category]) -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @State private var target: Category?
    @State private var deleteSources = false

    private var options: [Category] {
        let income = sources.first?.isIncome ?? false
        return categories.filter { $0.isIncome == income && !sources.contains($0) }
    }

    private var count: Int { sources.reduce(0) { $0 + CleanUp.movable(in: $1, context: modelContext).count } }
    private var canDelete: Bool { sources.contains { $0.isCustom } }

    var body: some View {
        NavigationStack {
            Form {
                Section("Move transactions from") {
                    ForEach(sources) { Label($0.name, systemImage: $0.symbol) }
                }
                Section("To") {
                    Picker("Category", selection: $target) {
                        Text("Choose…").tag(Category?.none)
                        ForEach(options) { Label($0.name, systemImage: $0.symbol).tag(Optional($0)) }
                    }
                    if canDelete { Toggle("Delete the old custom categories afterward", isOn: $deleteSources) }
                }
                Section {
                    Text(count == 0 ? "No transactions to move." : "\(count) transaction\(count == 1 ? "" : "s"), plus any bills and remembered payees, will move to “\(target?.name ?? "…")”. You can undo this right after.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
            }
            .formStyle(.grouped)
            .navigationTitle("Move Transactions")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Move") { if let target { onApply(target, deleteSources, sources); dismiss() } }.disabled(target == nil)
                }
            }
        }
        .frame(minWidth: 460, minHeight: 380)
    }
}
