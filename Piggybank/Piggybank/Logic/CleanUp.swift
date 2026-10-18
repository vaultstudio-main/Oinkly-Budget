import Foundation
import SwiftData

/// Bulk changes to payee names and categories: merge look-alike payees, find and replace in names, and move every
/// transaction from one category to another. Each change can be undone.
@MainActor
enum CleanUp {
    struct PayeeRow: Identifiable {
        let name: String
        var count: Int
        var lastDate: Date?
        var id: String { name }
    }

    /// What a change did, so it can be put back.
    struct Change {
        var summary: String
        /// A transaction and the payee it had before.
        var payees: [(id: PersistentIdentifier, name: String)] = []
        /// Memorized payees that were removed, to bring back.
        var removedMemory: [(name: String, category: Category?, amount: Decimal)] = []
        /// Memorized payees that were renamed, with their old name.
        var renamedMemory: [(id: PersistentIdentifier, oldName: String)] = []
        /// A transaction, bill or memorized payee and the category it had before.
        var transactionCategories: [(id: PersistentIdentifier, category: Category?)] = []
        var billCategories: [(id: PersistentIdentifier, category: Category?)] = []
        var payeeCategories: [(id: PersistentIdentifier, category: Category?)] = []
        /// A repeating rule and the payee or category it had before.
        var rulePayees: [(id: PersistentIdentifier, name: String)] = []
        var ruleCategories: [(id: PersistentIdentifier, category: Category?)] = []
        /// A part of a split transaction and the category it had before.
        var splitCategories: [(id: PersistentIdentifier, category: Category?)] = []
        var deletedCategory: (name: String, symbol: String, colorHex: String, limit: Decimal, isIncome: Bool, key: String?)?
        var count: Int { max(payees.count, transactionCategories.count) }
    }

    // MARK: Payees

    /// Every payee name used on a transaction, with how many times and when it was last used. Transfers are left out.
    static func payeeRows(in context: ModelContext) -> [PayeeRow] {
        var descriptor = FetchDescriptor<Transaction>()
        descriptor.propertiesToFetch = [\.payee, \.date, \.transferID]
        let all = (try? context.fetch(descriptor)) ?? []
        var table: [String: PayeeRow] = [:]
        for transaction in all where transaction.isLive && !transaction.isTransfer {
            let name = transaction.payee
            guard !name.trimmingCharacters(in: .whitespaces).isEmpty else { continue }
            var row = table[name] ?? PayeeRow(name: name, count: 0, lastDate: nil)
            row.count += 1
            row.lastDate = max(row.lastDate ?? .distantPast, transaction.date)
            table[name] = row
        }
        return table.values.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    /// "Starbucks #1234", "STARBUCKS" and "Starbucks Coffee" look alike once case, digits and punctuation are gone.
    static func lookAlikeKey(_ name: String) -> String {
        let lowered = name.lowercased().filter { $0.isLetter || $0 == " " }
        let words = lowered.split(separator: " ").filter { !["inc", "llc", "co", "the", "store"].contains($0) }
        return words.prefix(2).joined(separator: " ")
    }

    /// Groups of payees that look like the same one, biggest groups first.
    static func lookAlikes(_ rows: [PayeeRow]) -> [[PayeeRow]] {
        Dictionary(grouping: rows) { lookAlikeKey($0.name) }
            .filter { !$0.key.isEmpty && $0.value.count > 1 }
            .values
            .map { $0.sorted { $0.count > $1.count } }
            .sorted { $0.count != $1.count ? $0.count > $1.count : ($0.first?.name ?? "") < ($1.first?.name ?? "") }
    }

    /// The new names a find and replace would give, for payees whose name contains `find`. Names that don't change
    /// are left out.
    static func replacements(find: String, replace: String, in rows: [PayeeRow]) -> [String: String] {
        let needle = find.trimmingCharacters(in: .whitespaces)
        guard !needle.isEmpty else { return [:] }
        var result: [String: String] = [:]
        for row in rows where row.name.range(of: needle, options: .caseInsensitive) != nil {
            let renamed = row.name.replacingOccurrences(of: needle, with: replace, options: .caseInsensitive)
                .trimmingCharacters(in: .whitespaces)
            if !renamed.isEmpty && renamed != row.name { result[row.name] = renamed }
        }
        return result
    }

    /// Renames payees on every transaction: each old name in `mapping` becomes its new name. The memorized payee list
    /// follows, so the old names stop being suggested.
    @discardableResult
    static func renamePayees(_ mapping: [String: String], in context: ModelContext) -> Change {
        var change = Change(summary: "")
        guard !mapping.isEmpty else { return change }
        let olds = Array(mapping.keys)
        let descriptor = FetchDescriptor<Transaction>(predicate: #Predicate<Transaction> { olds.contains($0.payee) })
        for transaction in ((try? context.fetch(descriptor)) ?? []) where transaction.isLive {
            guard let new = mapping[transaction.payee], !transaction.isOpeningDeposit else { continue }
            change.payees.append((transaction.persistentModelID, transaction.payee))
            transaction.payee = new
        }

        // Repeating rules follow, so the entries they make carry the new name.
        for rule in ((try? context.fetch(FetchDescriptor<RecurringTransaction>())) ?? []).live {
            guard let new = mapping[rule.payee] else { continue }
            change.rulePayees.append((rule.persistentModelID, rule.payee))
            rule.payee = new
        }

        // The memorized payee list: keep one entry per new name.
        let memory = ((try? context.fetch(FetchDescriptor<Payee>())) ?? []).filter(\.isLive)
        for (old, new) in mapping {
            let oldEntries = memory.filter { PayeeMemory.normalized($0.name) == PayeeMemory.normalized(old) }
            let target = memory.first { PayeeMemory.normalized($0.name) == PayeeMemory.normalized(new) }
            for (index, entry) in oldEntries.enumerated() where entry.isLive {
                if target == nil && index == 0 {
                    change.renamedMemory.append((entry.persistentModelID, entry.name))
                    entry.name = new
                } else if entry !== target {
                    change.removedMemory.append((entry.name, entry.lastCategory, entry.lastAmount))
                    context.delete(entry)
                }
            }
        }
        context.saveNow()
        let names = Set(mapping.values)
        change.summary = "Changed \(change.payees.count) transaction\(change.payees.count == 1 ? "" : "s") to \(names.count == 1 ? "“\(names.first!)”" : "\(names.count) new names")."
        return change
    }

    // MARK: Categories

    /// How many transactions in `category` could be moved: locked ones (payments, transfers, ATM) can't be.
    static func movable(in category: Category, context: ModelContext) -> [Transaction] {
        let id = category.persistentModelID
        let descriptor = FetchDescriptor<Transaction>(predicate: #Predicate<Transaction> { $0.category?.persistentModelID == id })
        return ((try? context.fetch(descriptor)) ?? []).filter { $0.isLive && $0.fixedCategoryTitle == nil }
    }

    /// Moves every ordinary transaction, bill and remembered payee from `sources` to `target`. With `deleteSources`,
    /// custom categories left empty are removed.
    @discardableResult
    static func moveCategories(from sources: [Category], to target: Category, deleteSources: Bool, in context: ModelContext) -> Change {
        var change = Change(summary: "")
        for source in sources where source.isLive && source !== target {
            for transaction in movable(in: source, context: context) {
                change.transactionCategories.append((transaction.persistentModelID, source))
                transaction.category = target
            }
            for rule in source.recurringRules.live {
                change.ruleCategories.append((rule.persistentModelID, source))
                rule.category = target
            }
            for part in source.splits where part.transaction?.isLive == true {
                change.splitCategories.append((part.persistentModelID, source))
                part.category = target
            }
            for bill in source.bills.live {
                change.billCategories.append((bill.persistentModelID, source))
                bill.category = target
            }
            for payee in source.payees.live {
                change.payeeCategories.append((payee.persistentModelID, source))
                payee.lastCategory = target
            }
            if deleteSources, source.isCustom, source.transactions.live.isEmpty {
                change.deletedCategory = (source.name, source.symbol, source.colorHex, source.monthlyLimit, source.isIncome, source.systemKey)
                context.delete(source)
            }
        }
        context.saveNow()
        let parts = change.splitCategories.count
        change.summary = "Moved \(change.transactionCategories.count) transaction\(change.transactionCategories.count == 1 ? "" : "s")"
            + (parts > 0 ? " and \(parts) split part\(parts == 1 ? "" : "s")" : "") + " to “\(target.name)”."
        return change
    }

    // MARK: Undo

    /// Puts a change back as it was.
    static func undo(_ original: Change, in context: ModelContext) {
        var change = original
        func fetch<T: PersistentModel>(_ type: T.Type, _ id: PersistentIdentifier) -> T? { context.model(for: id) as? T }
        for (id, name) in change.payees { if let transaction: Transaction = fetch(Transaction.self, id), transaction.isLive { transaction.payee = name } }
        for (id, name) in change.renamedMemory { if let entry: Payee = fetch(Payee.self, id), entry.isLive { entry.name = name } }
        for entry in change.removedMemory { context.insert(Payee(name: entry.name, lastCategory: entry.category?.isLive == true ? entry.category : nil, lastAmount: entry.amount)) }
        if let deleted = change.deletedCategory {
            let restored = Category(name: deleted.name, colorHex: deleted.colorHex, symbol: deleted.symbol, monthlyLimit: deleted.limit,
                                    isIncome: deleted.isIncome, systemKey: deleted.key)
            context.insert(restored)
            for index in change.transactionCategories.indices where change.transactionCategories[index].category?.isLive != true {
                change.transactionCategories[index].category = restored
            }
            for index in change.splitCategories.indices where change.splitCategories[index].category?.isLive != true {
                change.splitCategories[index].category = restored
            }
        }
        for (id, category) in change.transactionCategories { if let t: Transaction = fetch(Transaction.self, id), t.isLive { t.category = category } }
        for (id, name) in change.rulePayees { if let rule: RecurringTransaction = fetch(RecurringTransaction.self, id), rule.isLive { rule.payee = name } }
        for (id, category) in change.ruleCategories { if let rule: RecurringTransaction = fetch(RecurringTransaction.self, id), rule.isLive { rule.category = category } }
        for (id, category) in change.splitCategories { if let part: TransactionSplit = fetch(TransactionSplit.self, id) { part.category = category } }
        for (id, category) in change.billCategories { if let b: Bill = fetch(Bill.self, id), b.isLive { b.category = category } }
        for (id, category) in change.payeeCategories { if let p: Payee = fetch(Payee.self, id), p.isLive { p.lastCategory = category } }
        context.saveNow()
    }
}
