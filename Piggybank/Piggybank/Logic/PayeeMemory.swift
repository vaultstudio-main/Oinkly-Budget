import Foundation
import SwiftData

/// Matching and memorizing payees.
enum PayeeMemory {
    static func normalized(_ name: String) -> String {
        name.trimmingCharacters(in: .whitespaces).lowercased()
    }

    /// Payees whose names start with, then contain, `text`. Empty text matches nothing.
    static func matches(for text: String, in payees: [Payee], limit: Int = 5) -> [Payee] {
        let query = normalized(text)
        guard !query.isEmpty else { return [] }
        let prefix = payees.filter { normalized($0.name).hasPrefix(query) }
        let contains = payees.filter { !normalized($0.name).hasPrefix(query) && normalized($0.name).contains(query) }
        return Array((prefix + contains).prefix(limit))
    }

    static func exactMatch(for text: String, in payees: [Payee]) -> Payee? {
        let query = normalized(text)
        guard !query.isEmpty else { return nil }
        return payees.first { normalized($0.name) == query }
    }

    /// The newest ordinary transaction with this payee name, for filling in the memo and payment method the way you
    /// used them last time.
    @MainActor
    static func lastTransaction(for name: String, in context: ModelContext) -> Transaction? {
        let query = normalized(name)
        guard !query.isEmpty else { return nil }
        var descriptor = FetchDescriptor<Transaction>(
            predicate: #Predicate<Transaction> { $0.payee.localizedStandardContains(query) },
            sortBy: [SortDescriptor(\.date, order: .reverse), SortDescriptor(\.createdAt, order: .reverse)])
        descriptor.fetchLimit = 40
        return ((try? context.fetch(descriptor)) ?? []).first { $0.isLive && !$0.isTransfer && normalized($0.payee) == query }
    }

    /// A payment method as text: a built-in method's raw value, or "custom:" and the name of one of your own.
    static func raw(_ method: PaymentChoice?) -> String {
        switch method {
        case .type(let type): type.rawValue
        case .custom(let custom): custom.isLive ? "custom:\(custom.name)" : ""
        case nil: ""
        }
    }

    /// The built-in method in `raw`, if it is one. Your own methods are looked up by name by the caller.
    static func builtInMethod(_ raw: String) -> PaymentType? { PaymentType(rawValue: raw) }

    /// Creates or updates the memorized payee for a just-entered transaction.
    static func record(name: String, category: Category?, amount: Decimal, memo: String? = nil, method: PaymentChoice? = nil,
                       in context: ModelContext) {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }
        let payees = (try? context.fetch(FetchDescriptor<Payee>())) ?? []
        if let existing = exactMatch(for: trimmed, in: payees) {
            existing.lastCategory = category
            existing.lastAmount = amount
            if let memo { existing.lastMemo = memo }
            if memo != nil || method != nil { existing.lastMethodRaw = raw(method) }
        } else {
            let made = Payee(name: trimmed, lastCategory: category, lastAmount: amount)
            made.lastMemo = memo ?? ""
            made.lastMethodRaw = raw(method)
            context.insert(made)
        }
    }
}
